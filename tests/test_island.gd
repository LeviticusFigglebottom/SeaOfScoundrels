extends TestCase
## Headless integration tests for Workstream `island`:
## 17 base stylized props (+ optional Wave 24A architecture/jungle props), 14
## procedural archetypes, 14-island multi-tier archipelago (38-182 m radius, 91
## pairwise channels > 320 m), Outpost dock depth / mooring clearance / shelter /
## restock (all 3 Outposts), harbour bunting / grog keg / campfire bard, Pawn
## beach landing walk, 3-dig DigSite unearthing, Outpost MerchantStall selling,
## shore factor & discovery, FortBastion/FortVault, SmugglersGrotto & VolcanoCaldera.

const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")

const ALL_PROPS: Array[String] = [
	"palm_tall.glb",
	"palm_curved.glb",
	"bush_fern.glb",
	"rock_boulder.glb",
	"rock_spire.glb",
	"rock_arch.glb",
	"dock_pier.glb",
	"outpost_tavern.glb",
	"outpost_stall.glb",
	"beacon_tower.glb",
	"chest_treasure.glb",
	"dig_mound.glb",
	"shipwreck_hulk.glb",
	"barrel_prop.glb",
	"crate_supply.glb",
	"campfire.glb",
	"notice_board.glb",
]

const OPTIONAL_WAVE24_PROPS: Array[String] = [
	"jungle_banyan.glb",
	"ruin_arch.glb",
	"ruin_pillar.glb",
	"timber_bridge.glb",
	"harbour_warehouse.glb",
	"seawall_bastion.glb",
	"watchtower_wood.glb",
]


func _init_host() -> void:
	Net.start_single_player()
	Sea.amp_scale = 0.0
	Sea.time = 0.0


func test_all_17_props_load() -> void:
	check_eq(ALL_PROPS.size(), 17, "expected 17 stylized base props")
	var expected_empties := {
		"dock_pier.glb": "Lantern_Dock",
		"outpost_tavern.glb": "Lantern_Tavern",
		"outpost_stall.glb": "Lantern_Stall",
		"beacon_tower.glb": "Lantern_Beacon",
		"campfire.glb": "Lantern_Fire",
	}
	var expected_cols := {
		"dock_pier.glb": 2,
		"outpost_tavern.glb": 4,
		"outpost_stall.glb": 3,
		"beacon_tower.glb": 3,
	}
	for filename in ALL_PROPS:
		var path := "res://assets/generated/props/" + filename
		check(ResourceLoader.exists(path), "missing prop " + path)
		var packed := load(path) as PackedScene
		check(packed != null, "failed to load PackedScene " + path)
		if packed == null:
			continue
		var inst := packed.instantiate()
		check(inst is Node3D, "prop root must be Node3D: " + filename)
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 1, "prop has no meshes: " + filename)
		if expected_empties.has(filename):
			var empty_name: String = expected_empties[filename]
			var found_empty := inst.find_child(empty_name, true, false)
			check(found_empty != null, "missing empty %s in %s" % [empty_name, filename])
		if expected_cols.has(filename):
			var col_meshes := inst.find_children("col_*", "MeshInstance3D", true, false)
			check(col_meshes.size() >= int(expected_cols[filename]),
				"too few col_* meshes in %s (%d)" % [filename, col_meshes.size()])
		inst.free()

	# Also validate any Wave 24A optional architecture/jungle props present in assets/generated/props/.
	for opt_name in OPTIONAL_WAVE24_PROPS:
		var opt_path := "res://assets/generated/props/" + opt_name
		if not ResourceLoader.exists(opt_path):
			continue
		var opt_packed := load(opt_path) as PackedScene
		check(opt_packed != null, "failed to load optional Wave 24A PackedScene " + opt_path)
		if opt_packed == null:
			continue
		var opt_inst := opt_packed.instantiate()
		check(opt_inst is Node3D, "optional prop root must be Node3D: " + opt_name)
		var opt_meshes := opt_inst.find_children("*", "MeshInstance3D", true, false)
		check(opt_meshes.size() >= 1, "optional prop has no meshes: " + opt_name)
		opt_inst.free()


func test_all_14_archetypes_generate() -> void:
	_init_host()
	check_eq(IslandGenerator.ARCHETYPES.size(), 14, "expected 14 island archetypes")
	for arch in IslandGenerator.ARCHETYPES:
		var isl := IslandGenerator.build_island({
			"id": "test_" + String(arch),
			"name": "Test " + String(arch),
			"archetype": arch,
			"seed": 700 + IslandGenerator.ARCHETYPES.find(arch),
		})
		add_child(isl)
		check(isl.peak_height >= 24.0, "archetype %s peak too low: %.1f" % [arch, isl.peak_height])
		check(isl.surface_height(isl.seabed_radius + 4.0, 0.0) <= -18.0,
			"archetype %s seabed must descend to <= -18 m" % arch)
		check(isl.contour_points.size() >= 12,
			"archetype %s contour_points too small (%d)" % [arch, isl.contour_points.size()])
		var terrain_body := isl.get_node_or_null(^"TerrainBody") as StaticBody3D
		check(terrain_body != null and terrain_body.collision_layer == 1,
			"archetype %s TerrainBody must be on layer 1" % arch)
		# Verify adaptive terrain grid resolution scales cleanly with island size tier.
		var expected_res := 72
		if isl.island_radius > 145.0:
			expected_res = 120
		elif isl.island_radius > 105.0:
			expected_res = 104
		elif isl.island_radius > 60.0:
			expected_res = 88
		check_eq(isl._grid_res, expected_res,
			"archetype %s (r=%.1f m) should use adaptive grid_res=%d" % [arch, isl.island_radius, expected_res])
		# Verify all col_* helper meshes are hidden visually.
		for c_node in isl.find_children("col_*", "MeshInstance3D", true, false):
			var c_mi := c_node as MeshInstance3D
			check(not c_mi.visible, "col_* mesh still visible on %s: %s" % [arch, c_mi.name])
		isl.queue_free()
	await physics_frames(3)


func test_archipelago_14_islands_no_overlap() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)

	var all_islands := arch.get_islands()
	check_eq(all_islands.size(), 14, "archipelago must contain 14 islands")

	var seen_ids := {}
	var seen_names := {}
	var min_radius := INF
	var max_radius := 0.0
	for isl in all_islands:
		check(not seen_ids.has(isl.island_id), "duplicate island_id: " + isl.island_id)
		check(not seen_names.has(isl.display_name), "duplicate display_name: " + isl.display_name)
		seen_ids[isl.island_id] = true
		seen_names[isl.display_name] = true
		min_radius = minf(min_radius, isl.island_radius)
		max_radius = maxf(max_radius, isl.island_radius)

	check(min_radius <= 42.0, "archipelago must include tiny sea-stack tier (min_radius=%.1f <= 42 m)" % min_radius)
	check(max_radius >= 175.0, "archipelago must include massive flagship tier (max_radius=%.1f >= 175 m)" % max_radius)

	var outposts := arch.get_outposts()
	check(outposts.size() >= 3, "archipelago must provide >= 3 Outposts including Galleon's Reach (got %d)" % outposts.size())
	var op0 := arch.get_outpost(0)
	var op1 := arch.get_outpost(1)
	var op2 := arch.get_outpost(2)
	var starter := arch.get_starter_treasure_island()
	check(op0 != null and op0.island_id == "port_scoundrel", "outpost 0 must be port_scoundrel")
	check(op1 != null and op1.island_id == "barnacle_haven", "outpost 1 must be barnacle_haven")
	check(op2 != null and op2.island_id == "galleons_reach" and op2 is Outpost, "outpost 2 must be galleons_reach Outpost")
	check(starter != null and starter.island_id == "cutlass_cay", "starter treasure island must be cutlass_cay")
	check(starter.get_dig_sites().size() >= 1, "Cutlass Cay should have an active DigSite")

	# Verify new Siren's Tooth sea-stack & Sovereign's Bastion Grand Citadel (with FortBastion + FortVault).
	var sirens := arch.get_island_by_id("sirens_tooth")
	check(sirens != null and sirens.archetype == &"sea_stack" and sirens.island_radius <= 42.0,
		"Siren's Tooth must spawn as Tier 1 sea_stack")
	var citadel := arch.get_island_by_id("sovereigns_bastion")
	check(citadel != null and citadel.archetype == &"grand_citadel" and citadel.island_radius >= 175.0,
		"Sovereign's Bastion must spawn as Tier 4 grand_citadel")
	if citadel != null:
		var cit_bastion := citadel.get_node_or_null(^"FortBastion")
		check(cit_bastion != null, "Sovereign's Bastion must crown its mesa with FortBastion")
		if cit_bastion != null:
			var cit_vault := cit_bastion.get_node_or_null(^"FortVault")
			check(cit_vault != null, "Sovereign's Bastion FortBastion must mount FortVault")
			var cit_bats := citadel.find_children("*", "FortBattery", true, false)
			check_eq(cit_bats.size(), 4, "Sovereign's Bastion must mount 4 FortBattery sea-batteries")

	var dist_starter := op0.global_position.distance_to(starter.global_position)
	check(dist_starter >= 380.0 and dist_starter <= 520.0,
		"Cutlass Cay distance %.1f m should be ~430-490 m NNE of Port Scoundrel" % dist_starter)

	# Verify zero overlaps and >320 m open sailing channels across ALL 91 island pairs.
	var pair_count := 0
	var min_channel := INF
	for i in all_islands.size():
		for j in range(i + 1, all_islands.size()):
			var a := all_islands[i]
			var b := all_islands[j]
			var center_dist := Vector2(
				a.global_position.x - b.global_position.x,
				a.global_position.z - b.global_position.z).length()
			var channel := center_dist - a.island_radius - b.island_radius
			min_channel = minf(min_channel, channel)
			pair_count += 1
			check(channel > 320.0,
				"channel between %s and %s too narrow: %.1f m" % [a.island_id, b.island_id, channel])
	check_eq(pair_count, 91, "must verify all 91 pairwise channels across 14 islands")
	print("    archipelago 14 islands: radius %.1f..%.1f m, %d pairs, min_channel=%.1f m" % [
		min_radius, max_radius, pair_count, min_channel])

	# Verify get_map_data() works cleanly with VoyageComposer.
	var map_data := arch.get_map_data()
	check_eq(map_data.size(), 14, "get_map_data should return 14 entries")
	var extracted := VoyageComposer.extract_archipelago_data(arch)
	check_eq(extracted.size(), 14, "VoyageComposer must extract all 14 islands cleanly")

	arch.queue_free()
	await physics_frames(3)


func test_outpost_dock_depth_mooring_and_restock() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	for idx in [0, 1, 2]:
		var op := arch.get_outpost(idx)
		check(op != null, "missing outpost %d" % idx)
		if op == null:
			continue

		var pier_end := op.get_world_pier_end()
		var pier_depth := op.seabed_depth(pier_end)
		check(pier_depth > 4.5, "%s pier end depth %.2f m must exceed 4.5 m" % [op.island_id, pier_depth])

		var moor_world := op.get_world_mooring_transform()
		var moor_depth := op.seabed_depth(moor_world.origin)
		check(moor_depth > 4.5, "%s mooring depth %.2f m must exceed 4.5 m" % [op.island_id, moor_depth])

		# Check full sloop footprint around mooring_transform (bow, stern, port/starboard).
		for off: Vector3 in [Vector3(0.0, 0.0, -6.5), Vector3(0.0, 0.0, 6.5), Vector3(-2.2, 0.0, 0.0), Vector3(2.2, 0.0, 0.0)]:
			var pt: Vector3 = moor_world * off
			var d := op.seabed_depth(pt)
			check(d > 4.0, "%s sloop mooring footprint depth %.2f m at %s must exceed 4.0 m" % [op.island_id, d, off])

		# Verify mooring sits safely ~4.45 m abeam of pier centerline with zero pier overlap
		# and bow (-Z) aligned seaward with pier (-Z).
		var moor_in_dock := op.dock_local_transform.affine_inverse() * op.mooring_transform.origin
		check_near(absf(moor_in_dock.x), Outpost.MOORING_ABEAM_OFFSET, 0.25,
			"%s mooring abeam offset" % op.island_id)
		var clearance := absf(moor_in_dock.x) - Outpost.PIER_HALF_WIDTH - 2.20
		check(clearance >= 0.35, "%s hull-to-pier clearance %.2f m too tight" % [op.island_id, clearance])
		var dot_fwd := (-op.mooring_transform.basis.z).dot(-op.dock_local_transform.basis.z)
		check(dot_fwd > 0.99, "%s mooring bow must face straight out to open sea" % op.island_id)

		# Verify Tavern shelter, Beacon Tower light, and Voyage Board interactable.
		check(op.tavern_shelter != null and op.tavern_shelter.is_in_group(&"shelter"),
			"%s tavern shelter Area3D must be in group shelter" % op.island_id)
		check(op.beacon_light != null and op.beacon_light.global_position.y > 22.0,
			"%s beacon light must shine high above sea level" % op.island_id)
		check(op.voyage_board_interactable != null, "%s missing Voyage Board interactable" % op.island_id)

	# Verify Voyage Board signal and Quartermaster ship restocking on a real Ship.
	var op0 := arch.get_outpost(0)
	var board_fired := [false]
	op0.voyage_board_used.connect(func(_p: Node) -> void: board_fired[0] = true)
	op0.voyage_board_interactable.interact(null)
	check(board_fired[0], "voyage_board_used signal did not fire")

	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.start_anchored = true
	add_child(ship)
	ship.global_transform = op0.get_world_mooring_transform()
	ship.cannonballs_remaining = 3
	ship.planks_remaining = 2
	var ok := op0.restock_ship(ship)
	check(ok, "Outpost.restock_ship should return true")
	check_eq(ship.cannonballs_remaining, Ship.MAX_CANNONBALLS, "cannonballs refilled")
	check_eq(ship.planks_remaining, Ship.MAX_PLANKS, "planks refilled")

	ship.queue_free()
	arch.queue_free()
	await physics_frames(2)


func test_pawn_walks_from_water_onto_cutlass_cay() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(3)

	var cutlass := arch.get_starter_treasure_island()
	check(cutlass != null, "missing Cutlass Cay")
	if cutlass == null:
		arch.queue_free()
		return

	# Find the shallow landing waterline right in front of Cutlass Cay's primary beach cove.
	var land_basis := Basis(Vector3.UP, 2.77)
	var seaward := -land_basis.z
	var start_local := Vector3.ZERO
	var found_water := false
	for dist in range(24, 95, 2):
		var cand := seaward * float(dist)
		var h := cutlass.surface_height(cand.x, cand.z)
		if h <= -0.9 and h >= -2.4:
			start_local = Vector3(cand.x, maxf(h + 0.1, -1.2), cand.z)
			found_water = true
			break
	check(found_water, "could not find shallow landing water off Cutlass Cay")

	var pawn := PAWN_SCENE.instantiate() as Pawn
	add_child(pawn)
	pawn.global_position = cutlass.global_position + start_local
	# Walk straight ashore along -seaward (inland toward the beach cove).
	var inland_dir := (-seaward).normalized()
	pawn.wish_dir = inland_dir
	pawn.wish_sprint = true

	var max_y := pawn.global_position.y
	var reached_dry_walk := false
	for _tick in 260:
		await physics_frames(1)
		if pawn.global_position.y > max_y:
			max_y = pawn.global_position.y
		if pawn.is_grounded() and pawn.global_position.y >= 1.25:
			reached_dry_walk = true
			break

	check(reached_dry_walk,
		"Pawn should walk cleanly from shallow water onto dry Cutlass Cay beach (final y=%.2f, mode=%d, grounded=%s)"
		% [pawn.global_position.y, pawn.mode, pawn.is_grounded()])
	var expected_h := cutlass.world_surface_height(pawn.global_position)
	check_near(pawn.global_position.y, expected_h, 0.45,
		"Pawn feet should match Cutlass Cay terrain surface height")

	pawn.queue_free()
	arch.queue_free()
	await physics_frames(2)


func test_dig_site_three_digs_unearths_chest() -> void:
	_init_host()
	var cutlass := IslandGenerator.build_island({
		"id": "dig_test_cay",
		"name": "Dig Test Cay",
		"archetype": &"treasure_peak",
		"seed": 4242,
	})
	add_child(cutlass)
	await physics_frames(2)

	var dig_pt := cutlass.dig_points[0] if not cutlass.dig_points.is_empty() else Vector3(0.0, 2.0, -24.0)
	var site := cutlass.spawn_dig_site(dig_pt, &"corsair_chest")
	await physics_frames(1)

	var unearthed_chests: Array[Carryable] = []
	site.unearthed.connect(func(c: Carryable) -> void: unearthed_chests.append(c))

	# Out-of-range dig (> 2.4 m) must not advance.
	var r_far := site.dig(site.global_position + Vector3(3.5, 0.0, 0.0))
	check(not bool(r_far["hit"]), "dig beyond 2.4 m should miss")
	check_eq(site.dig_count, 0, "dig_count must stay 0 after out-of-range dig")

	# Dig 1 & 2 progress cleanly without spawning yet.
	var r1 := site.dig(site.global_position + Vector3(0.5, 0.0, 0.0))
	check(bool(r1["hit"]) and not bool(r1["unearthed"]), "dig 1 should hit and not unearth yet")
	check_eq(int(r1["remaining"]), 2, "2 digs should remain")

	var r2 := site.dig(site.global_position + Vector3(-0.4, 0.0, 0.6))
	check(bool(r2["hit"]) and not bool(r2["unearthed"]), "dig 2 should hit and not unearth yet")
	check_eq(int(r2["remaining"]), 1, "1 dig should remain")

	# Dig 3 unearths a real Carryable treasure chest!
	var r3 := site.dig(site.global_position)
	check(bool(r3["hit"]) and bool(r3["unearthed"]), "dig 3 must unearth treasure")
	check_eq(unearthed_chests.size(), 1, "unearthed signal must fire once")
	var chest: Carryable = r3["chest"] as Carryable
	check(chest != null and chest is Carryable, "spawned treasure must be a Carryable")
	if chest != null:
		var info := TreasureCatalog.inspect_carryable(chest)
		check_eq(info.get("treasure_id"), &"corsair_chest", "spawned chest must match treasure_id")
		check(int(info.get("gold_value", 0)) > 0, "spawned chest must have positive gold value")

	# Dig 4 after unearthing must be rejected.
	var r4 := site.dig(site.global_position)
	check(not bool(r4["hit"]), "dig after unearthing should return hit=false")

	cutlass.queue_free()
	await physics_frames(2)


func test_outpost_merchant_sells_chest() -> void:
	_init_host()
	var saved_profile: Dictionary = Game.profile.data.duplicate(true)

	var outpost := IslandGenerator.build_island({
		"id": "port_test",
		"name": "Port Test",
		"archetype": &"outpost",
		"seed": 5151,
	}) as Outpost
	add_child(outpost)
	await physics_frames(2)

	var sold_events: Array[Dictionary] = []
	outpost.treasure_sold.connect(func(it: Node, g: int, r: int) -> void:
		sold_events.append({"item": it, "gold": g, "renown": r}))

	# Test 1: Full Pawn pick_up -> interact with MerchantStall -> Economy sale!
	var start_gold: int = int(Game.profile.data.get("gold", 0))
	var start_renown: int = Economy.get_company_renown(Game.profile, &"gilded_compass")

	var chest := TreasureCatalog.create_treasure_carryable(&"wayfarer_chest", Vector3.ZERO)
	add_child(chest)
	var pawn := PAWN_SCENE.instantiate() as Pawn
	add_child(pawn)
	pawn.global_position = outpost.merchant_stall.global_position + Vector3(0.0, 0.2, -1.6)
	check(pawn.pick_up(chest), "Pawn should pick up treasure chest")
	pawn.focus = outpost.merchant_stall.interactable
	pawn.interact()
	await physics_frames(2)

	check(pawn.carried == null, "Pawn should no longer hold chest after selling")
	check_eq(sold_events.size(), 1, "treasure_sold should fire on pawn sale")
	check_eq(int(Game.profile.data["gold"]), start_gold + 240, "Wayfarer chest should award 240 gold")
	check_eq(Economy.get_company_renown(Game.profile, &"gilded_compass"), start_renown + 40,
		"Wayfarer chest should award 40 renown")
	check(not is_instance_valid(chest), "sold chest should be freed")

	# Test 2: Plain untagged Carryable uses 250g / 40 renown fallback.
	var plain := Carryable.new()
	plain.item_name = "Mystery Crate"
	add_child(plain)
	var gold_before_plain: int = int(Game.profile.data["gold"])
	var renown_before_plain: int = Economy.get_company_renown(Game.profile, &"gilded_compass")
	check(plain.hand_to(outpost.merchant_stall), "MerchantStall must accept plain Carryable")
	await physics_frames(2)
	check_eq(int(Game.profile.data["gold"]), gold_before_plain + 250, "plain Carryable fallback 250 gold")
	check_eq(Economy.get_company_renown(Game.profile, &"gilded_compass"), renown_before_plain + 40,
		"plain Carryable fallback 40 renown")
	check(not is_instance_valid(plain), "sold plain Carryable should be freed")

	pawn.queue_free()
	outpost.queue_free()
	Game.profile.data = saved_profile
	await physics_frames(2)


func test_shore_factor_and_discovery() -> void:
	_init_host()
	var saved_profile: Dictionary = Game.profile.data.duplicate(true)
	Game.profile.data["discoveries"] = []

	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(1)

	var cutlass := arch.get_starter_treasure_island()
	check(cutlass != null, "missing Cutlass Cay")
	if cutlass != null:
		# Beach shoreline point should report strong shore_factor (> 0.75).
		var beach_pt := cutlass.global_position + (cutlass.dig_points[0] if not cutlass.dig_points.is_empty() else Vector3(0.0, 1.5, 20.0))
		var sf_beach := arch.nearest_shore_factor(beach_pt)
		check(sf_beach > 0.75, "shore_factor on beach should exceed 0.75 (got %.3f)" % sf_beach)

		# Deep open sailing channel far from all islands should report 0.0.
		var sf_open := arch.nearest_shore_factor(Vector3(0.0, 0.0, -250.0))
		check_near(sf_open, 0.0, 0.01, "shore_factor in deep open channel should be 0.0")

		check_eq(arch.nearest_island(cutlass.global_position + Vector3(15.0, 0.0, 0.0)), cutlass,
			"nearest_island near Cutlass Cay must be Cutlass Cay")

		# First discovery succeeds, second call returns null.
		var discovered_sig: Array[Island] = []
		arch.island_discovered.connect(func(isl: Island) -> void: discovered_sig.append(isl))
		var d1 := arch.check_discovery(cutlass.global_position + Vector3(0.0, 0.0, 40.0))
		check_eq(d1, cutlass, "first check_discovery near Cutlass Cay must discover it")
		check_eq(discovered_sig.size(), 1, "island_discovered signal must emit once")
		var d2 := arch.check_discovery(cutlass.global_position + Vector3(0.0, 0.0, 40.0))
		check(d2 == null, "repeat check_discovery must return null")

	arch.queue_free()
	Game.profile.data = saved_profile
	await physics_frames(2)


func test_fort_bastion_and_sea_batteries() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	var fort := arch.get_island_by_id("ironwatch_fort")
	check(fort != null, "missing ironwatch_fort in Archipelago")
	if fort == null:
		arch.queue_free()
		return

	var bastion := fort.get_node_or_null(^"FortBastion")
	check(bastion != null, "Ironwatch Fort must generate a FortBastion node")
	if bastion == null:
		arch.queue_free()
		return

	check(bastion.get_node_or_null(^"BastionStonework") is MeshInstance3D,
		"FortBastion must contain sculpted BastionStonework mesh")
	check(bastion.get_node_or_null(^"WatchtowerGantry") is MeshInstance3D,
		"FortBastion must contain WatchtowerGantry timber mesh")
	var brazier := bastion.get_node_or_null(^"SignalBrazier") as Node3D
	check(brazier != null, "FortBastion must contain SignalBrazier")
	var brazier_light := bastion.find_child("SignalBrazierLight", true, false) as OmniLight3D
	check(brazier_light != null, "FortBastion must contain SignalBrazierLight")
	if brazier_light != null:
		check(brazier_light.global_position.y > 24.0,
			"Signal Brazier light should crown Ironwatch Fort high above sea level (got %.1f m)" % brazier_light.global_position.y)
		var calm_energy := brazier_light.light_energy
		bastion.call(&"set_siege_beacon", true)
		check(bool(bastion.get(&"is_siege_beacon_active")), "set_siege_beacon(true) should activate siege beacon")
		check(brazier_light.light_energy > calm_energy,
			"Siege beacon flare should boost brazier light energy")
		bastion.call(&"set_siege_beacon", false)
		check(not bool(bastion.get(&"is_siege_beacon_active")), "set_siege_beacon(false) should calm siege beacon")

	# Verify exactly 4 FortBattery emplacements mounted cleanly on the bastion.
	var found_nodes := fort.find_children("*", "FortBattery", true, false)
	check_eq(found_nodes.size(), 4, "Ironwatch Fort must mount 4 FortBattery sea-batteries")
	var batteries: Array[FortBattery] = []
	for n in found_nodes:
		var fb := n as FortBattery
		check(fb != null and not fb.destroyed, "FortBattery must start intact")
		if fb != null:
			batteries.append(fb)
			check(fb.global_position.y > 14.0,
				"FortBattery %s must sit grounded on the elevated bastion parapet (y=%.2f)" % [fb.name, fb.global_position.y])
			check(fb.interactable != null and fb.interactable.enabled,
				"FortBattery %s must expose an enabled Interactable" % fb.name)

	# Spawn a real player Ship approaching Ironwatch Fort's seaward landing lane (~105 m out).
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.faction = &"player"
	ship.start_anchored = true
	ship.enable_effects = false
	add_child(ship)
	var seaward := (-fort.mooring_transform.basis.z).normalized()
	var ship_pos := fort.global_position + seaward * 105.0
	ship_pos.y = 0.0
	ship.global_position = ship_pos
	await physics_frames(2)

	# Activate siege and watch batteries track, telegraph priming fuse, and fire a real Cannonball!
	var fired_balls: Array[Cannonball] = []
	for fb in batteries:
		fb.enable_effects = false
		fb.battery_fired.connect(func(b: Cannonball) -> void: fired_balls.append(b))
	bastion.call(&"set_siege_active", true)

	var saw_telegraph := false
	for _tick in 220:
		await physics_frames(1)
		for fb in batteries:
			if fb.is_telegraphing():
				saw_telegraph = true
		if not fired_balls.is_empty():
			break

	check(saw_telegraph, "At least one FortBattery must visibly telegraph its priming fuse before firing")
	check(not fired_balls.is_empty(), "Active siege FortBattery must fire a real Cannonball at approaching player ship")
	if not fired_balls.is_empty():
		var ball := fired_balls[0]
		check(is_instance_valid(ball), "Fired Cannonball must remain valid right after launch")
		var launch_pos := ball.global_position
		check(ball.velocity.length() > 40.0,
			"Fired Cannonball speed %.1f m/s should match ~52 m/s muzzle velocity" % ball.velocity.length())
		var to_ship := (ship.global_position - launch_pos)
		to_ship.y = 0.0
		var vel_horiz := Vector3(ball.velocity.x, 0.0, ball.velocity.z)
		check(to_ship.normalized().dot(vel_horiz.normalized()) > 0.75,
			"Fired Cannonball must travel seaward toward the approaching player ship")
		# Verify shot clears stone embrasure piers cleanly over the first 0.25 s of flight.
		var early_impact := [false]
		ball.impacted.connect(func(_p: Vector3, _t: Node) -> void: early_impact[0] = true)
		await physics_frames(15)
		check(not early_impact[0], "FortBattery shot must clear its own embrasure masonry without clipping")
		if is_instance_valid(ball):
			check(ball.global_position.distance_to(launch_pos) > 10.0,
				"FortCannonball should travel cleanly out toward sea after launch")

	# Verify a Pawn can walk right through the open landing-ramp gateway into the bastion courtyard!
	var scout := PAWN_SCENE.instantiate() as Pawn
	add_child(scout)
	var gate_outer := (bastion as Node3D).global_transform * Vector3(0.0, 0.25, -13.0)
	gate_outer.y = fort.world_surface_height(gate_outer) + 0.15
	scout.global_position = gate_outer
	var inward_dir := ((bastion as Node3D).global_position - gate_outer)
	inward_dir.y = 0.0
	scout.wish_dir = inward_dir.normalized()
	scout.wish_sprint = true
	var entered_courtyard := false
	for _gt in 120:
		await physics_frames(1)
		var local_p := (bastion as Node3D).to_local(scout.global_position)
		if Vector2(local_p.x, local_p.z).length() < 7.5 and scout.is_grounded():
			entered_courtyard = true
			break
	check(entered_courtyard, "Pawn must walk cleanly through Ironwatch Fort's open landing-ramp gateway into the courtyard")
	scout.queue_free()

	# Verify manual player Interactable firing on an intact, ready battery.
	var manual_bat := batteries[0]
	manual_bat.set_siege_active(false)
	manual_bat.repair_battery()
	var before_manual := fired_balls.size()
	manual_bat.interactable.interact(null)
	check_eq(fired_balls.size(), before_manual + 1, "Interactable 'Fire Fort Cannon' must fire a Cannonball")

	# Verify hitbox proxy forwards damage and take_damage() cleanly silences & repairs the battery.
	var destroyed_events: Array[FortBattery] = []
	manual_bat.battery_destroyed.connect(func(b: FortBattery) -> void: destroyed_events.append(b))
	var hitbox := manual_bat.find_child("BatteryHitbox", true, false)
	check(hitbox != null and hitbox is StaticBody3D, "FortBattery must include a StaticBody3D BatteryHitbox")
	if hitbox != null:
		hitbox.call(&"apply_damage", 35.0, null)
	else:
		manual_bat.take_damage(35.0)
	check(not manual_bat.destroyed, "Partial damage should not silence FortBattery yet")
	check_near(manual_bat.health, manual_bat.max_health - 35.0, 0.01, "Health should decrement accurately")
	manual_bat.take_damage(60.0)
	check(manual_bat.destroyed, "Lethal take_damage() must mark FortBattery destroyed")
	check_near(manual_bat.health, 0.0, 0.01, "Destroyed FortBattery health must clamp to 0")
	check(not manual_bat.is_telegraphing(), "Destroyed FortBattery must cancel any telegraph")
	check(not manual_bat.interactable.enabled, "Destroyed FortBattery interactable must disable")
	check_eq(destroyed_events.size(), 1, "battery_destroyed signal must emit once")
	check(manual_bat.fire_battery() == null, "Destroyed FortBattery must refuse to fire")

	manual_bat.repair_battery()
	check(not manual_bat.destroyed and manual_bat.interactable.enabled,
		"repair_battery() must restore FortBattery to fighting shape")

	# Clean teardown with zero leaks.
	bastion.call(&"set_siege_active", false)
	ship.queue_free()
	arch.queue_free()
	await physics_frames(3)


func test_smugglers_grotto_and_volcano_caldera() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	# 1. Verify FortBastion warm faceted weathered limestone polish.
	var fort := arch.get_island_by_id("ironwatch_fort")
	check(fort != null, "missing ironwatch_fort")
	if fort != null:
		var stone_mi := fort.get_node_or_null(^"FortBastion/BastionStonework") as MeshInstance3D
		check(stone_mi != null and stone_mi.material_override is StandardMaterial3D,
			"FortBastion BastionStonework must have StandardMaterial3D override")
		if stone_mi != null and stone_mi.material_override is StandardMaterial3D:
			var smat := stone_mi.material_override as StandardMaterial3D
			check(smat.roughness >= 0.895, "FortBastion stone roughness should be >= 0.90 (got %.2f)" % smat.roughness)
		if stone_mi != null and stone_mi.mesh != null:
			var s_arr := stone_mi.mesh.surface_get_arrays(0)
			var s_norms: PackedVector3Array = s_arr[Mesh.ARRAY_NORMAL]
			var flat_tris := 0
			var total_tris := int(s_norms.size() / 3.0)
			for ti in total_tris:
				var n0 := s_norms[ti * 3]
				var n1 := s_norms[ti * 3 + 1]
				var n2 := s_norms[ti * 3 + 2]
				if n0.dot(n1) > 0.999 and n0.dot(n2) > 0.999:
					flat_tris += 1
			check_eq(flat_tris, total_tris,
				"BastionStonework must be 100%% flat-shaded faceted masonry (%d/%d flat tris)" % [flat_tris, total_tris])

	# 2. Verify Smuggler's Cove generates walkable SmugglersGrotto sea cave!
	var cove := arch.get_island_by_id("smugglers_cove")
	check(cove != null, "missing smugglers_cove in Archipelago")
	if cove != null:
		var grotto := cove.get_node_or_null(^"SmugglersGrotto") as Node3D
		check(grotto != null, "Smuggler's Cove must generate a SmugglersGrotto child node")
		if grotto != null:
			check(grotto.position.y >= 1.1 and grotto.position.y <= 3.0,
				"SmugglersGrotto mouth elevation %.2f m must sit cleanly on walkable cove beach" % grotto.position.y)
			var grotto_inland_d := Vector2(grotto.position.x, grotto.position.z).length()
			check(grotto_inland_d >= 4.5,
				"SmugglersGrotto must be sunk deeper inland into the amphitheatre cliff wall (dist=%.2f m)" % grotto_inland_d)

			var vault := grotto.get_node_or_null(^"GrottoVaultMesh") as MeshInstance3D
			check(vault != null and vault.mesh != null and vault.mesh.get_faces().size() >= 300,
				"SmugglersGrotto must contain sculpted faceted rock vault geometry")
			if vault != null and vault.material_override is StandardMaterial3D:
				var vmat := vault.material_override as StandardMaterial3D
				check(vmat.vertex_color_is_srgb, "GrottoVaultMesh material must interpret warm ochre vertex colors in sRGB")
				check(vmat.roughness >= 0.90, "GrottoVaultMesh roughness must be >= 0.90 (got %.2f)" % vmat.roughness)
			if vault != null and vault.mesh != null:
				var v_arr := vault.mesh.surface_get_arrays(0)
				var v_norms: PackedVector3Array = v_arr[Mesh.ARRAY_NORMAL]
				var v_flat := 0
				var v_total := int(v_norms.size() / 3.0)
				for ti in v_total:
					var n0 := v_norms[ti * 3]
					var n1 := v_norms[ti * 3 + 1]
					var n2 := v_norms[ti * 3 + 2]
					if n0.dot(n1) > 0.999 and n0.dot(n2) > 0.999:
						v_flat += 1
				check_eq(v_flat, v_total,
					"GrottoVaultMesh must be 100%% flat-shaded faceted limestone (%d/%d flat tris)" % [v_flat, v_total])
			var brow_ferns := cove.find_children("GrottoBrowFern_*", "Node3D", true, false)
			check(brow_ferns.size() >= 2,
				"SmugglersGrotto brow must be dressed with >= 2 lush fern clumps (got %d)" % brow_ferns.size())
			var flank_boulders := cove.find_children("GrottoFlankBoulder_*", "Node3D", true, false)
			check(flank_boulders.size() >= 2,
				"SmugglersGrotto shoulders must be anchored by flanking coastal boulders (got %d)" % flank_boulders.size())
			var table := grotto.get_node_or_null(^"ContrabandStashTable") as MeshInstance3D
			check(table != null and table.mesh != null,
				"SmugglersGrotto must contain a raised timber ContrabandStashTable")

			# Real rain shelter Area3D in group `shelter` with BoxShape3D enclosing cave interior.
			var shelter := grotto.get_node_or_null(^"GrottoShelter") as Area3D
			check(shelter != null and shelter.is_in_group(&"shelter"),
				"SmugglersGrotto must include GrottoShelter Area3D in group 'shelter'")
			var shelter_cs := shelter.get_node_or_null(^"ShelterBox") as CollisionShape3D if shelter != null else null
			var shelter_box := shelter_cs.shape as BoxShape3D if shelter_cs != null else null
			check(shelter_box != null and shelter_box.size.x >= 5.0 and shelter_box.size.y >= 4.0 and shelter_box.size.z >= 9.0,
				"GrottoShelter BoxShape3D must enclose the walkable sea cave interior")

			# Two hanging flickering smuggler brass lanterns.
			var lanterns := grotto.find_children("SmugglerLanternLight_*", "OmniLight3D", true, false)
			check_eq(lanterns.size(), 2, "SmugglersGrotto must hang 2 warm brass OmniLight3D lanterns")

			# Verify a real Pawn walks cleanly from outside the cove mouth deep into the sheltered cave!
			var explorer := PAWN_SCENE.instantiate() as Pawn
			add_child(explorer)
			var start_pos := grotto.global_transform * Vector3(0.0, 0.25, -4.0)
			start_pos.y = cove.world_surface_height(start_pos) + 0.14
			explorer.global_position = start_pos
			var into_cave := grotto.global_basis.z
			into_cave.y = 0.0
			explorer.wish_dir = into_cave.normalized()
			explorer.wish_sprint = true

			var reached_interior := false
			for _tick in 180:
				await physics_frames(1)
				var lp := grotto.to_local(explorer.global_position)
				if lp.z >= 3.8 and absf(lp.x) < 2.8 and explorer.is_grounded():
					reached_interior = true
					break
			check(reached_interior,
				"Pawn must walk cleanly through SmugglersGrotto mouth into interior (final local=%s, grounded=%s)"
				% [grotto.to_local(explorer.global_position), explorer.is_grounded()])

			# Stand inside the grotto and confirm Pawn remains grounded and sheltered from rain.
			explorer.wish_dir = Vector3.ZERO
			explorer.wish_sprint = false
			await physics_frames(12)
			check(explorer.is_grounded(), "Pawn must remain stably grounded inside SmugglersGrotto")
			if shelter_cs != null and shelter_box != null:
				var eye_in_shelter := shelter_cs.global_transform.affine_inverse() * (explorer.global_position + Vector3(0.0, 1.5, 0.0))
				var half := shelter_box.size * 0.5
				check(absf(eye_in_shelter.x) < half.x and absf(eye_in_shelter.y) < half.y and absf(eye_in_shelter.z) < half.z,
					"Pawn standing inside SmugglersGrotto must be enclosed by GrottoShelter box (local=%s, half=%s)"
					% [eye_in_shelter, half])
			explorer.queue_free()

	# 3. Verify Cinder Crag generates VolcanoCaldera with glowing magma, fissures, rim light & lean plumes!
	var crag := arch.get_island_by_id("cinder_crag")
	check(crag != null, "missing cinder_crag in Archipelago")
	if crag != null:
		check(crag.peak_height >= 80.0,
			"Cinder Crag basalt caldera rim must tower >= 80 m (got %.1f m)" % crag.peak_height)
		var caldera := crag.get_node_or_null(^"VolcanoCaldera") as Node3D
		check(caldera != null, "Cinder Crag must generate a VolcanoCaldera child node")
		if caldera != null:
			check(caldera.global_position.y > 55.0 and caldera.global_position.y < crag.peak_height - 8.0,
				"VolcanoCaldera (y=%.1f m) must sit recessed inside Cinder Crag's %.1f m summit caldera bowl"
				% [caldera.global_position.y, crag.peak_height])

			# Confirm the jagged basalt caldera rim surrounds & rises higher than the magma pool.
			var scale_r := crag.island_radius / 60.0
			var higher_rim_pts := 0
			for ri in 8:
				var ang := TAU * float(ri) / 8.0
				var rim_w := caldera.global_transform * Vector3(cos(ang) * 14.5 * scale_r, 0.0, sin(ang) * 14.5 * scale_r)
				if crag.world_surface_height(rim_w) > caldera.global_position.y + 4.0:
					higher_rim_pts += 1
			check(higher_rim_pts >= 7,
				"Caldera rim walls must cradle VolcanoCaldera around its perimeter (%d/8 rim points elevated)" % higher_rim_pts)

			var magma := caldera.get_node_or_null(^"MagmaPool") as MeshInstance3D
			check(magma != null and magma.mesh != null and magma.mesh.get_faces().size() >= 100,
				"VolcanoCaldera must contain sculpted glowing MagmaPool mesh")
			var crust := caldera.get_node_or_null(^"ObsidianCrust") as MeshInstance3D
			check(crust != null and crust.mesh != null and crust.mesh.get_faces().size() >= 100,
				"VolcanoCaldera must contain cracked faceted ObsidianCrust mesh")

			var fissures := caldera.get_node_or_null(^"LavaFissureMesh") as MeshInstance3D
			check(fissures != null and fissures.mesh != null and fissures.mesh.get_faces().size() >= 200,
				"VolcanoCaldera must contain sculpted LavaFissureMesh cascading down the basalt flank")
			if fissures != null and fissures.mesh != null:
				var f_aabb := fissures.mesh.get_aabb()
				check(f_aabb.size.z >= 22.0 and f_aabb.size.y >= 20.0,
					"LavaFissureMesh must snake >= 22 m seaward and descend >= 20 m down Cinder Crag (aabb=%s)" % f_aabb.size)
				var fmat := fissures.material_override as StandardMaterial3D
				check(fmat != null and fmat.emission_enabled and fmat.emission_energy_multiplier >= 2.5,
					"LavaFissureMesh must have glowing emissive material (energy >= 2.5)")

			var cal_light := caldera.get_node_or_null(^"CalderaMagmaLight") as OmniLight3D
			check(cal_light != null and cal_light.position.y >= 7.0 and cal_light.omni_range >= 70.0 and cal_light.light_energy >= 9.0,
				"CalderaMagmaLight must sit high (y>=7m) with wide bounce range (>=70m) and bright energy (>=9)")

			var ash_plume := caldera.get_node_or_null(^"VolcanoAshPlume") as GPUParticles3D
			var ember_plume := caldera.get_node_or_null(^"VolcanoEmberPlume") as GPUParticles3D
			check(ash_plume != null and ash_plume.emitting and ash_plume.draw_pass_1 != null and ash_plume.process_material != null,
				"VolcanoCaldera must emit a towering VolcanoAshPlume GPUParticles3D")
			check(ash_plume != null and ash_plume.amount <= 28,
				"VolcanoAshPlume must stay lean <= 28 particles (got %d)" % (ash_plume.amount if ash_plume != null else -1))
			check(ember_plume != null and ember_plume.emitting and ember_plume.draw_pass_1 != null and ember_plume.process_material != null,
				"VolcanoCaldera must emit rising VolcanoEmberPlume GPUParticles3D")
			check(ember_plume != null and ember_plume.amount <= 24,
				"VolcanoEmberPlume must stay lean <= 24 particles (got %d)" % (ember_plume.amount if ember_plume != null else -1))

			# Let _process pulse molten magma & fissure glow, then verify clean _exit_tree particle teardown.
			await physics_frames(4)
			crag.remove_child(caldera)
			check(ash_plume != null and not ash_plume.emitting and ash_plume.draw_pass_1 == null and ash_plume.process_material == null,
				"VolcanoCaldera._exit_tree must stop ash_plume and null draw_pass_1/process_material")
			check(ember_plume != null and not ember_plume.emitting and ember_plume.draw_pass_1 == null and ember_plume.process_material == null,
				"VolcanoCaldera._exit_tree must stop ember_plume and null draw_pass_1/process_material")
			caldera.free()

	# 4. Verify BrainTableCorals stays strictly <= 420 tris and <= 3 MultiMeshes total on CoralReef.
	var atoll := arch.get_island_by_id("crescent_atoll")
	if atoll != null:
		var reef := atoll.get_node_or_null(^"CoralReef") as CoralReef
		check(reef != null and reef.get_multimesh_count() == 3,
			"Crescent Atoll CoralReef must maintain strictly 3 MultiMesh draw calls")
		if reef != null:
			var brain_mmi := reef.get_node_or_null(^"BrainTableCorals") as MultiMeshInstance3D
			check(brain_mmi != null and brain_mmi.multimesh != null and brain_mmi.multimesh.mesh != null,
				"CoralReef must contain BrainTableCorals MultiMesh")
			if brain_mmi != null and brain_mmi.multimesh != null and brain_mmi.multimesh.mesh != null:
				var brain_tris := int(brain_mmi.multimesh.mesh.get_faces().size() / 3.0)
				check(brain_tris > 0 and brain_tris <= 420,
					"BrainTableCorals mesh must stay lean <= 420 tris (got %d tris)" % brain_tris)

	arch.queue_free()
	await physics_frames(3)


func test_outpost_harbour_life_bunting_grog_keg_and_bard() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(4)

	var op0 := arch.get_outpost(0)
	var op1 := arch.get_outpost(1)
	check(op0 != null and op1 != null, "archipelago provides at least two Outposts")
	if op0 == null or op1 == null:
		arch.queue_free()
		return

	# 1. Verify HarbourBunting: 1 batched draw call, valid ArrayMesh, wind shader, high overhead clearance.
	var bunting := op0.find_child("HarbourBunting", true, false) as MeshInstance3D
	check(bunting != null and bunting == op0.harbour_bunting,
		"Outpost builds batched HarbourBunting MeshInstance3D")
	var bunting_tris := 0
	if bunting != null:
		check_eq(bunting.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"HarbourBunting disables shadows for lean draw cost")
		var smat := bunting.material_override as ShaderMaterial
		check(smat != null and smat.shader == Outpost.BUNTING_SHADER,
			"HarbourBunting binds bunting_wind.gdshader")
		check(bunting.mesh is ArrayMesh and bunting.mesh.get_surface_count() == 1,
			"HarbourBunting uses a single batched ArrayMesh surface")
		if bunting.mesh is ArrayMesh:
			var arr := (bunting.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			bunting_tris = floori(float(verts.size()) / 3.0)
			check(bunting_tris >= 300, "HarbourBunting has festive posts, ropes & pennants (%d tris)" % bunting_tris)
			# Every fluttering pennant vertex (UV.y > 0.1) must clear >= 4.15 m above terrain!
			var min_pennant_clear := INF
			var pennant_verts := 0
			for vi in verts.size():
				if uvs[vi].y > 0.1:
					pennant_verts += 1
					var v := verts[vi]
					min_pennant_clear = minf(min_pennant_clear, v.y - op0.surface_height(v.x, v.z))
			check(pennant_verts >= 60, "HarbourBunting encodes flutter weights on pennant vertices (%d)" % pennant_verts)
			check(min_pennant_clear >= 4.15,
				"All bunting pennant tips hang high overhead (min_clear=%.2f m >= 4.15 m)" % min_pennant_clear)
		if smat != null:
			var wt0: float = float(smat.get_shader_parameter(&"wind_time"))
			await get_tree().process_frame
			await get_tree().process_frame
			var wt1: float = float(smat.get_shader_parameter(&"wind_time"))
			check(wt1 > wt0, "HarbourBunting updates wind_time smoothly in _process (%.3f -> %.3f)" % [wt0, wt1])

	# 2. Verify Interactive Sculpted TavernGrogKeg, static mesh sharing, tavern_toast signal & +35 HP heal!
	var keg0 := op0.find_child("TavernGrogKeg", true, false) as Node3D
	var keg_mi0 := op0.find_child("TavernGrogKegMesh", true, false) as MeshInstance3D
	var keg_mi1 := op1.find_child("TavernGrogKegMesh", true, false) as MeshInstance3D
	check(keg0 != null and keg0 == op0.tavern_keg_node, "Outpost places TavernGrogKeg beside the Tavern porch")
	check(keg_mi0 != null and keg_mi0.mesh is ArrayMesh, "TavernGrogKeg uses a sculpted ArrayMesh")
	var keg_tris := 0
	if keg_mi0 != null and keg_mi0.mesh is ArrayMesh:
		var karr := (keg_mi0.mesh as ArrayMesh).surface_get_arrays(0)
		var kverts: PackedVector3Array = karr[Mesh.ARRAY_VERTEX]
		keg_tris = floori(float(kverts.size()) / 3.0)
		check(keg_tris >= 250, "TavernGrogKeg has sculpted cradle/keg/hoops/tap/mug (%d tris)" % keg_tris)
	if keg_mi0 != null and keg_mi1 != null:
		check_eq(keg_mi0.mesh, keg_mi1.mesh, "Outposts share statically cached TavernGrogKeg ArrayMesh")
	if keg0 != null:
		var expected_ky := op0.surface_height(keg0.position.x, keg0.position.z)
		check_near(keg0.position.y, expected_ky, 0.08, "TavernGrogKeg sits grounded cleanly on terrain")

	check(op0.tavern_keg_interactable != null, "Outpost exposes tavern_keg_interactable")
	var toast_pawns: Array[Node] = []
	op0.tavern_toast.connect(func(p: Node) -> void: toast_pawns.append(p))
	var captain := PAWN_SCENE.instantiate() as Pawn
	add_child(captain)
	captain.global_position = op0.global_position + (keg0.position if keg0 != null else Vector3.ZERO) + Vector3(0.0, 0.2, -1.2)
	captain.apply_damage(50.0, null)
	check_near(captain.health, 50.0, 0.01, "damaged Pawn starts at 50.0 HP before tavern toast")
	op0.tavern_keg_interactable.interact(captain)
	check_eq(toast_pawns.size(), 1, "interacting with tavern_keg_interactable emits tavern_toast once")
	check_eq(toast_pawns[0], captain, "tavern_toast emits interacting Pawn")
	check_near(captain.health, 85.0, 0.01, "tapping tavern grog keg heals damaged Pawn by +35 HP")
	captain.queue_free()

	# 3. Verify Harbour Campfire Shanty Musician (TavernBardNPC) & held 3D sculpted instrument!
	var bard := op0.find_child("TavernBardNPC", true, false) as Node3D
	check(bard != null and bard == op0.tavern_bard_node, "Outpost spawns TavernBardNPC by the harbour campfire")
	if bard != null:
		var campfire := op0.find_child("OutpostCampfire", true, false) as Node3D
		if campfire != null:
			var d_fire := Vector2(bard.position.x - campfire.position.x, bard.position.z - campfire.position.z).length()
			check(d_fire > 1.0 and d_fire < 3.5,
				"TavernBardNPC stands beside the harbour campfire (dist=%.2f m)" % d_fire)
		var bard_cv := bard.get_node_or_null(^"CharacterVisual") as CharacterVisual
		check(bard_cv != null and bard_cv.skeleton != null, "TavernBardNPC owns a bound CharacterVisual skeleton")
		if bard_cv != null and bard_cv.hand_right != null:
			var held := bard_cv.hand_right.find_child("ShantyInstrument_*", true, false) as Node3D
			check(held != null, "TavernBardNPC holds a sculpted 3D shanty instrument in hand_right")

	# 4. Verify BeaconGlowCore is a sculpted ArrayMesh and ZERO raw primitive MeshInstance3Ds remain on Outpost!
	var beacon_core := op0.find_child("BeaconGlowCore", true, false) as MeshInstance3D
	check(beacon_core != null and beacon_core.mesh is ArrayMesh,
		"BeaconGlowCore uses sculpted faceted ArrayMesh instead of SphereMesh")
	var beacon_tris := 0
	if beacon_core != null and beacon_core.mesh is ArrayMesh:
		var barr := (beacon_core.mesh as ArrayMesh).surface_get_arrays(0)
		var bverts: PackedVector3Array = barr[Mesh.ARRAY_VERTEX]
		beacon_tris = floori(float(bverts.size()) / 3.0)

	var raw_prims: Array[String] = []
	for node in op0.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			raw_prims.append(mi.name)
	check(raw_prims.is_empty(),
		"Outpost must have zero raw primitive MeshInstance3Ds (found: %s)" % str(raw_prims))
	print("    outpost sculpted meshes: HarbourBunting=%d, TavernGrogKeg=%d, BeaconGlowCore=%d tris" % [
		bunting_tris, keg_tris, beacon_tris])

	arch.queue_free()
	await physics_frames(3)
	check(Outpost._keg_mesh == null and Outpost._beacon_halo_mesh == null,
		"Outpost releases static mesh cache cleanly after all Outposts exit tree")


func test_message_bottles_and_campfire_cookpots() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	# 1. Tropical beach islands deterministically wash up glinting MessageBottles.
	var tropical_ids: Array[String] = [
		"cutlass_cay",
		"smugglers_cove",
		"crescent_atoll",
		"wreckers_shoal",
		"gulls_arch",
	]
	var bottles: Array[MessageBottle] = []
	for tid in tropical_ids:
		var isl := arch.get_island_by_id(tid)
		check(isl != null, "Archipelago contains tropical island '%s'" % tid)
		var bottle := isl.get_node_or_null(^"BeachMessageBottle") as MessageBottle
		check(bottle != null, "tropical island '%s' spawns BeachMessageBottle" % tid)
		if bottle == null:
			continue
		bottles.append(bottle)
		check(bottle.is_in_group(MessageBottle.GROUP), "%s bottle is in group message_bottles" % tid)
		check(bottle.interactable != null and bottle.interactable.enabled,
			"%s bottle has enabled Interactable" % tid)
		check_near(bottle.interactable.reach, 2.8, 0.01, "%s bottle reach == 2.8 m" % tid)

		# Grounded cleanly on dry upper golden sand clear of dig sites.
		var surf_y := isl.surface_height(bottle.position.x, bottle.position.z)
		check_near(bottle.position.y, surf_y, 0.05, "%s bottle grounded at surface_height()" % tid)
		check(bottle.position.y >= 0.40 and bottle.position.y <= 3.10,
			"%s bottle sits on dry beach shoreline (y=%.2f)" % [tid, bottle.position.y])
		for dp in isl.dig_points:
			var d_dig := Vector2(bottle.position.x - dp.x, bottle.position.z - dp.z).length()
			check(d_dig >= 4.0, "%s bottle clears dig site (dist=%.2f m)" % [tid, d_dig])

		# Clue points to a different archipelago island & valid catalog treasure.
		var clue := bottle.get_clue_dict()
		check(String(clue["clue_id"]) != "", "%s bottle has clue_id" % tid)
		check(String(clue["target_island_id"]) != "" and String(clue["target_island_id"]) != tid,
			"%s bottle clue points to another island (%s)" % [tid, String(clue["target_island_id"])])
		check(arch.get_island_by_id(String(clue["target_island_id"])) != null,
			"%s bottle clue target exists in Archipelago" % tid)
		check(TreasureCatalog.has_treasure(StringName(clue["treasure_id"])),
			"%s bottle clue treasure '%s' exists in TreasureCatalog" % [tid, String(clue["treasure_id"])])
		check(String(clue["clue_text"]).strip_edges() != "", "%s bottle has readable clue_text" % tid)

	# Outposts must not wash up beach bottles.
	var op0 := arch.get_outpost(0)
	check(op0.get_node_or_null(^"BeachMessageBottle") == null,
		"Outposts do not spawn BeachMessageBottle")

	# 2. Verify sculpted ArrayMesh geometry, zero raw primitives, and static mesh sharing.
	check(bottles.size() >= 2, "at least 2 MessageBottles spawned across tropical islands")
	var b0 := bottles[0]
	var b1 := bottles[1]
	var core_mi0 := b0.find_child("BottleCoreMesh", true, false) as MeshInstance3D
	var glass_mi0 := b0.find_child("BottleGlassMesh", true, false) as MeshInstance3D
	var glint_mi0 := b0.find_child("BottleGlint", true, false) as MeshInstance3D
	var core_mi1 := b1.find_child("BottleCoreMesh", true, false) as MeshInstance3D
	var glass_mi1 := b1.find_child("BottleGlassMesh", true, false) as MeshInstance3D

	check(core_mi0 != null and core_mi0.mesh is ArrayMesh, "MessageBottle builds sculpted BottleCoreMesh")
	check(glass_mi0 != null and glass_mi0.mesh is ArrayMesh, "MessageBottle builds sculpted BottleGlassMesh")
	check(glint_mi0 != null and glint_mi0.mesh is ArrayMesh, "MessageBottle builds sculpted BottleGlint")
	check_eq(glint_mi0.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"BottleGlint disables shadows")
	if core_mi0 != null and core_mi1 != null:
		check_eq(core_mi0.mesh, core_mi1.mesh, "MessageBottles share statically cached BottleCoreMesh")
	if glass_mi0 != null and glass_mi1 != null:
		check_eq(glass_mi0.mesh, glass_mi1.mesh, "MessageBottles share statically cached BottleGlassMesh")

	var raw_prims: Array[String] = []
	var total_bottle_tris := 0
	for node in b0.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims.append(mi.name)
		total_bottle_tris += _count_array_mesh_tris(mi.mesh)
	check(raw_prims.is_empty(), "MessageBottle has zero raw PrimitiveMeshes (found: %s)" % str(raw_prims))
	check(total_bottle_tris >= 500, "MessageBottle has hero sculpted triangle count (%d >= 500)" % total_bottle_tris)
	print("    MessageBottle sculpted tris: total=%d (core=%d, glass=%d, glint=%d)" % [
		total_bottle_tris,
		_count_array_mesh_tris(core_mi0.mesh),
		_count_array_mesh_tris(glass_mi0.mesh),
		_count_array_mesh_tris(glint_mi0.mesh),
	])

	# 3. Verify idempotent host-authoritative bottle_collected signal & cleanup of visuals.
	var received: Array[Dictionary] = []
	b0.bottle_collected.connect(func(bot: MessageBottle, pawn_node: Node, c: Dictionary) -> void:
		received.append({"bottle": bot, "pawn": pawn_node, "clue": c})
	)
	var captain := PAWN_SCENE.instantiate() as Pawn
	add_child(captain)
	captain.global_position = b0.global_position + Vector3(0.0, 0.1, -1.0)

	b0.interactable.interact(captain)
	check_eq(received.size(), 1, "interacting with MessageBottle emits bottle_collected once")
	check(b0.collected, "MessageBottle marks collected = true")
	check(not b0.interactable.enabled, "collected MessageBottle disables interactable")
	var vis_root := b0.get_node_or_null(^"BottleVisual") as Node3D
	check(vis_root != null and not vis_root.visible, "collected MessageBottle hides visuals")
	check(not glint_mi0.visible, "collected MessageBottle hides sunlit glint star")
	if received.size() == 1:
		check_eq(received[0]["bottle"], b0, "bottle_collected passes bottle instance")
		check_eq(received[0]["pawn"], captain, "bottle_collected passes interacting Pawn")
		var c: Dictionary = received[0]["clue"] as Dictionary
		check_eq(c["clue_id"], b0.clue_id, "bottle_collected clue_id matches")
		check_eq(c["target_island_id"], b0.target_island_id, "bottle_collected target_island_id matches")
		check_eq(c["treasure_id"], b0.treasure_id, "bottle_collected treasure_id matches")

	# Re-interacting or calling collect() again must be strictly idempotent.
	b0.interactable.interact(captain)
	check(not b0.collect(captain), "repeat collect() returns false idempotently")
	check_eq(received.size(), 1, "bottle_collected never fires twice")
	captain.queue_free()

	# 4. Verify BeachCampfire across tropical/fort islands includes CampfireCookingStove!
	var campfire_islands: Array[String] = ["cutlass_cay", "smugglers_cove", "ironwatch_fort"]
	for cid in campfire_islands:
		var isl := arch.get_island_by_id(cid)
		var fire := isl.find_child("BeachCampfire", true, false) as Node3D
		check(fire != null, "%s has BeachCampfire" % cid)
		if fire == null:
			continue
		var stove := fire.get_node_or_null(^"CampfireCookingStove") as CookingStove
		check(stove != null, "%s BeachCampfire attaches CampfireCookingStove" % cid)
		if stove != null:
			check(not stove.build_hearth, "%s CampfireCookingStove sets build_hearth = false" % cid)
			check(stove.interactable != null and stove.interactable.enabled,
				"%s CampfireCookingStove exposes active Interactable" % cid)

	arch.queue_free()
	await physics_frames(3)
	check(MessageBottle._opaque_mesh == null and MessageBottle._glass_mesh == null and MessageBottle._glint_mesh == null,
		"MessageBottle releases static mesh cache cleanly after all bottles exit tree")


func _count_array_mesh_tris(mesh: Mesh) -> int:
	var total := 0
	if mesh == null:
		return 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if raw_idx is PackedInt32Array and not (raw_idx as PackedInt32Array).is_empty():
			total += floori(float((raw_idx as PackedInt32Array).size()) / 3.0)
		else:
			var raw_verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if raw_verts is PackedVector3Array:
				total += floori(float((raw_verts as PackedVector3Array).size()) / 3.0)
	return total


func test_bonus_island_supply_barrels_and_teardown() -> void:
	_init_host()
	var barrel_gd: GDScript = preload("res://src/world/supply_barrel.gd")
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	# 1. Verify tropical islands (including Cutlass Cay) spawn bonus SupplyBarrels and outposts do not.
	var cutlass := arch.get_island_by_id("cutlass_cay")
	var outpost := arch.get_island_by_id("port_scoundrel")
	check(cutlass != null and outpost != null, "archipelago builds cutlass_cay and port_scoundrel")

	var cutlass_barrels: Array[Node3D] = []
	for c in cutlass.get_children():
		if c is Node3D and c.is_in_group(&"supply_barrels"):
			cutlass_barrels.append(c as Node3D)
	check(cutlass_barrels.size() >= 1 and cutlass_barrels.size() <= 2,
		"Cutlass Cay spawns 1-2 bonus SupplyBarrels (got %d)" % cutlass_barrels.size())

	var outpost_barrels := 0
	for c in outpost.get_children():
		if c.is_in_group(&"supply_barrels"):
			outpost_barrels += 1
	check_eq(outpost_barrels, 0, "outposts do not spawn island bonus SupplyBarrels")

	var all_barrels := get_tree().get_nodes_in_group(&"supply_barrels")
	check(all_barrels.size() >= 6, "archipelago spawns bonus SupplyBarrels across non-outpost islands (got %d)" % all_barrels.size())

	# 2. Verify zero raw primitives, grounded placement, sculpted golden emblem & shared static cache.
	var b0 := cutlass_barrels[0]
	var b1 := all_barrels[all_barrels.size() - 1] as Node3D
	var surf_y := cutlass.surface_height(b0.position.x, b0.position.z)
	check_near(b0.position.y, surf_y, 0.12, "Cutlass Cay SupplyBarrel snaps cleanly to terrain surface")
	for dp in cutlass.dig_points:
		check(Vector2(b0.position.x - dp.x, b0.position.z - dp.z).length() >= 3.0,
			"SupplyBarrel keeps clear of island dig_points")

	var emblem0 := b0.find_child("SupplyTagEmblem", true, false) as MeshInstance3D
	var emblem1 := b1.find_child("SupplyTagEmblem", true, false) as MeshInstance3D
	check(emblem0 != null and emblem0.mesh is ArrayMesh and emblem0.visible,
		"SupplyBarrel crowns lid with visible sculpted SupplyTagEmblem ArrayMesh")
	if emblem0 != null and emblem1 != null:
		check_eq(emblem0.mesh, emblem1.mesh, "SupplyBarrels share statically cached emblem ArrayMesh")
		check(_count_array_mesh_tris(emblem0.mesh) >= 120,
			"SupplyTagEmblem has sculpted flat-faceted geometry (%d tris)" % _count_array_mesh_tris(emblem0.mesh))

	var raw_prims: Array[String] = []
	for node in b0.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			raw_prims.append(mi.name)
	check(raw_prims.is_empty(), "SupplyBarrel contains zero raw PrimitiveMeshes (found: %s)" % str(raw_prims))

	# 3. Verify one-press take-all heals wounded pawn, emits supplies_taken once, hides emblem & stays idempotent.
	var captain := PAWN_SCENE.instantiate() as Pawn
	add_child(captain)
	captain.global_position = b0.global_position + Vector3(0.0, 0.1, -1.2)
	captain.apply_damage(35.0)
	var hp_before := captain.health

	var taken_events: Array[Dictionary] = []
	b0.connect(&"supplies_taken", func(bar: Node, p_node: Node, loot: Dictionary) -> void:
		taken_events.append({"barrel": bar, "pawn": p_node, "loot": loot})
	)

	var it := b0.get(&"interactable") as Interactable
	check(it != null and it.enabled and it.prompt == "Take all supplies (+6 balls, +3 planks)",
		"SupplyBarrel exposes one-press take-all Interactable prompt")
	it.interact(captain)

	check_eq(taken_events.size(), 1, "supplies_taken emits once on interact")
	check(bool(b0.get(&"looted")), "SupplyBarrel marks looted = true")
	check(not it.enabled, "looted SupplyBarrel disables interactable")
	check(emblem0 != null and not emblem0.visible, "looted SupplyBarrel hides golden SupplyTagEmblem")
	check_near(captain.health, hp_before + 18.0, 0.05, "SupplyBarrel heals wounded captain (+18 HP)")
	if taken_events.size() == 1:
		var loot: Dictionary = taken_events[0]["loot"] as Dictionary
		check_eq(int(loot.get("cannonballs", 0)), 6, "loot awards +6 cannonballs")
		check_eq(int(loot.get("planks", 0)), 3, "loot awards +3 planks")

	# Repeat interact / take_all must be strictly idempotent.
	it.interact(captain)
	var repeat_loot: Dictionary = b0.call(&"take_all", captain) as Dictionary
	check(repeat_loot.is_empty(), "repeat take_all() returns empty dict idempotently")
	check_eq(taken_events.size(), 1, "supplies_taken never fires twice")
	captain.queue_free()

	# 4. Zero-leak teardown releases static SupplyBarrel mesh/material cache.
	arch.queue_free()
	await physics_frames(3)
	check(barrel_gd.get(&"_emblem_mesh") == null and barrel_gd.get(&"_brass_mat") == null,
		"SupplyBarrel releases static shared cache cleanly when all barrels exit tree")


func test_night_island_fireflies_daylight_and_distance_gating() -> void:
	_init_host()
	var saved_weather := Weather.get_state()
	Weather.day_length_seconds = 0.0
	Weather.time_of_day = 12.0

	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	var cutlass := arch.get_island_by_id("cutlass_cay")
	var port := arch.get_island_by_id("port_scoundrel")
	var cinder := arch.get_island_by_id("cinder_crag")
	check(cutlass != null and port != null and cinder != null, "Archipelago contains cutlass_cay, port_scoundrel & cinder_crag")

	var cutlass_ff := cutlass.get_node_or_null(^"IslandFireflies") as GPUParticles3D if cutlass != null else null
	var port_ff := port.get_node_or_null(^"IslandFireflies") as GPUParticles3D if port != null else null
	var cinder_ff := cinder.get_node_or_null(^"IslandFireflies") as GPUParticles3D if cinder != null else null

	check(cutlass_ff != null, "Cutlass Cay mounts IslandFireflies GPUParticles3D")
	check(port_ff != null, "Port Scoundrel mounts IslandFireflies GPUParticles3D")
	check(cinder_ff == null, "Volcanic Cinder Crag skips tropical IslandFireflies")

	if cutlass_ff != null:
		check_eq(cutlass_ff.amount, 36, "IslandFireflies uses 1-draw-call particle budget (amount = 36)")
		check(cutlass_ff.draw_pass_1 is QuadMesh, "IslandFireflies uses billboarded QuadMesh (zero primitives)")
		var qm := cutlass_ff.draw_pass_1 as QuadMesh
		var mat := qm.material as StandardMaterial3D if qm != null else null
		check(mat != null and mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and mat.albedo_texture is ImageTexture,
			"IslandFireflies uses additive unshaded feathered ImageTexture")

		# 1. Noon daylight -> completely hidden & inactive (0.00 ms GPU cost!).
		Weather.time_of_day = 12.0
		cutlass.update_night_ambience(cutlass.global_position + Vector3(0.0, 4.0, 20.0), true)
		check(not cutlass_ff.visible and not cutlass_ff.emitting, "IslandFireflies stays hidden and idle at noon")

		# 2. Nighttime within 95 m -> visible, emitting, full amount_ratio.
		Weather.time_of_day = 22.5
		cutlass.update_night_ambience(cutlass.global_position + Vector3(0.0, 4.0, 35.0), true)
		check(cutlass_ff.visible and cutlass_ff.emitting, "IslandFireflies activates cleanly at night within 95 m")
		check(cutlass_ff.amount_ratio >= 0.95, "IslandFireflies reaches full amount_ratio at deep night (got %.2f)" % cutlass_ff.amount_ratio)

		# 3. Nighttime beyond 95 m -> cleanly culled!
		cutlass.update_night_ambience(cutlass.global_position + Vector3(0.0, 4.0, 120.0), true)
		check(not cutlass_ff.visible and not cutlass_ff.emitting, "IslandFireflies culls cleanly beyond 95 m")

		# 4. Headless mode without a camera still activates cleanly at night.
		cutlass.update_night_ambience(Vector3.ZERO, false)
		check(cutlass_ff.visible and cutlass_ff.emitting, "IslandFireflies activates cleanly at night without active camera")

	# 5. Zero-leak teardown releases static firefly glow texture when all islands exit tree.
	arch.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(cutlass_ff), "IslandFireflies freed cleanly with its Island")
	check(Island._firefly_glow_tex == null, "Island releases static _firefly_glow_tex cleanly when all islands exit tree")
	Weather.apply_state(saved_weather)


func test_outpost_lighthouse_rotating_beacon_beam() -> void:
	_init_host()
	var saved_weather := Weather.get_state()
	Weather.day_length_seconds = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.0)

	var outpost := IslandGenerator.build_island(Archipelago.ISLAND_SPECS[0]) as Outpost
	add_child(outpost)
	await physics_frames(2)

	# 1. Verify LighthouseBeam mounted under BeaconTower using sculpted ArrayMesh (0 primitives) + shader.
	var beam := outpost.beacon_beam
	check(beam != null and beam.name == "LighthouseBeam", "Outpost mounts LighthouseBeam MeshInstance3D")
	check(outpost.beacon_node != null and beam != null and beam.get_parent() == outpost.beacon_node,
		"LighthouseBeam is mounted cleanly on Outpost's BeaconTower")
	if beam != null:
		check(beam.mesh is ArrayMesh and not (beam.mesh is PrimitiveMesh),
			"LighthouseBeam uses sculpted dual-cone ArrayMesh (zero raw PrimitiveMeshes)")
		var beam_tris := _count_array_mesh_tris(beam.mesh)
		print("    lighthouse volumetric beam: %d tris (dual opposing 74 m Fresnel cones)" % beam_tris)
		check(beam_tris >= 128, "LighthouseBeam dual-cone ArrayMesh has smooth volumetric rings (%d tris)" % beam_tris)
		check_eq(beam.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"LighthouseBeam disables shadow casting")
		check_eq(beam.gi_mode, GeometryInstance3D.GI_MODE_DISABLED, "LighthouseBeam disables GI")
		check(beam.extra_cull_margin >= 75.0, "LighthouseBeam sets generous extra_cull_margin for 74 m cones")
		var smat := beam.material_override as ShaderMaterial
		check(smat != null and smat.shader == Outpost.LIGHTHOUSE_BEAM_SHADER,
			"LighthouseBeam uses lighthouse_beam.gdshader")

		# 2. Clear midday sun -> hidden (0.00 ms GPU cost!).
		Weather.time_of_day = 12.0
		Weather.set_weather(0.0, 8.0, 0.0)
		await get_tree().process_frame
		check(not beam.visible, "LighthouseBeam stays hidden in clear midday sun")

		# 3. Midnight -> activates smoothly and rotates continuously across frames!
		Weather.time_of_day = 23.0
		Weather.set_weather(0.0, 8.0, 0.0)
		await get_tree().process_frame
		check(beam.visible, "LighthouseBeam activates cleanly at midnight")
		var night_intensity := float(smat.get_shader_parameter(&"beam_intensity")) if smat != null else 0.0
		check(night_intensity > 0.5, "LighthouseBeam intensity > 0.5 at midnight (got %.2f)" % night_intensity)
		var yaw_before := beam.rotation.y
		for _i in 12:
			await get_tree().process_frame
		var rot_delta := absf(wrapf(beam.rotation.y - yaw_before, -PI, PI))
		check(rot_delta > 0.02, "LighthouseBeam rotates smoothly across frames (delta=%.3f rad)" % rot_delta)

		# 4. Daytime heavy storm mist -> activates cleanly as a storm navigation guide!
		Weather.time_of_day = 12.0
		Weather.set_weather(0.85, 19.0, 0.0)
		await get_tree().process_frame
		check(beam.visible, "LighthouseBeam activates during a heavy daytime storm")
		var storm_intensity := float(smat.get_shader_parameter(&"beam_intensity")) if smat != null else 0.0
		check(storm_intensity > 0.5, "LighthouseBeam intensity > 0.5 in daytime storm (got %.2f)" % storm_intensity)

	# 5. Zero-leak teardown releases static _beacon_beam_mesh & _beacon_beam_mat cleanly!
	outpost.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(beam), "LighthouseBeam freed cleanly with Outpost")
	check(Outpost._beacon_beam_mesh == null and Outpost._beacon_beam_mat == null,
		"Outpost releases static _beacon_beam_mesh and _beacon_beam_mat cleanly on teardown")
	Weather.apply_state(saved_weather)


func test_tavern_bard_interactive_shanty_request_and_teardown() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	var outpost := arch.get_island_by_id("port_scoundrel") as Outpost
	check(outpost != null, "Port Scoundrel Outpost present")
	check(outpost.tavern_bard_node != null, "Outpost builds TavernBardNPC")
	check(outpost.tavern_bard_interactable != null and outpost.tavern_bard_interactable.enabled,
		"TavernBardNPC attaches enabled TavernBardInteractable")
	check_eq(outpost.tavern_bard_interactable.name, "TavernBardInteractable", "interactable name matches")
	check_eq(outpost.tavern_bard_interactable.prompt, "Request a tavern shanty", "initial prompt asks to request shanty")
	check_near(outpost.tavern_bard_interactable.reach, 2.8, 0.01, "TavernBardInteractable reach is 2.8 m")
	check(not outpost.tavern_bard_playing, "TavernBard starts idle before shanty request")

	var captain := PAWN_SCENE.instantiate() as Pawn
	add_child(captain)
	captain.global_position = outpost.tavern_bard_node.global_position + Vector3(0.0, 0.1, 1.2)

	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	# 1. Request shanty via Interactable -> plays spatialized shanty, spawns zero-primitive BardShantyMotes!
	outpost.tavern_bard_interactable.interact(captain)
	check(outpost.tavern_bard_playing, "interacting with TavernBard toggles tavern_bard_playing = true")
	check_eq(outpost.tavern_bard_interactable.prompt, "Silence tavern shanty", "active prompt updates to Silence tavern shanty")
	check(Audio.is_shanty_playing(), "TavernBard starts Audio shanty playback")
	check_near(float(Audio._stems[&"concertina"]["goal"]), 1.0, 0.01, "concertina stem active")
	check_near(float(Audio._stems[&"whistle"]["goal"]), 1.0, 0.01, "whistle stem active")
	var motes := outpost.tavern_bard_node.get_node_or_null(^"BardShantyMotes") as GPUParticles3D
	check(motes != null and motes.emitting and motes.amount == 8, "TavernBard spawns emitting 8-mote BardShantyMotes")
	check(motes != null and motes.draw_pass_1 is ArrayMesh and not (motes.draw_pass_1 is PrimitiveMesh),
		"BardShantyMotes uses zero-primitive ArrayMesh card")
	check(notices.has("Tavern Bard: Raise a tankard, Captain - here's a shanty for the harbour!"),
		"TavernBard posts cheerful harbour toast")

	# 2. Interact again -> silences tavern shanty, removes BardShantyMotes, restores prompt.
	outpost.tavern_bard_interactable.interact(captain)
	await get_tree().process_frame
	check(not outpost.tavern_bard_playing, "second interact silences TavernBard shanty")
	check_eq(outpost.tavern_bard_interactable.prompt, "Request a tavern shanty", "prompt resets cleanly")
	check(outpost.tavern_bard_node.get_node_or_null(^"BardShantyMotes") == null, "BardShantyMotes detached on silence")
	check(not is_instance_valid(motes), "BardShantyMotes freed cleanly on silence")

	# 3. Tear down Outpost while TavernBard is actively playing -> zero leaks!
	outpost.toggle_tavern_bard_shanty(captain)
	var live_motes := outpost.tavern_bard_node.get_node_or_null(^"BardShantyMotes") as GPUParticles3D
	check(live_motes != null and outpost.tavern_bard_playing, "re-enabled TavernBard before teardown check")

	Game.notice.disconnect(notice_cb)
	captain.queue_free()
	arch.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(live_motes), "BardShantyMotes freed cleanly on Outpost teardown")
	Audio.stop_shanty(0.05)


func test_outpost_tavern_signboard_and_interactive_pier_fog_bell() -> void:
	_init_host()
	var saved_weather := Weather.get_state()
	Weather.set_weather(0.0, 11.0, 0.2)

	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	var op0 := arch.get_outpost(0)
	var op1 := arch.get_outpost(1)
	check(op0 != null and op1 != null, "Archipelago builds at least two Outposts")
	if op0 == null or op1 == null:
		arch.queue_free()
		Weather.apply_state(saved_weather)
		return

	# 1. Verify Sculpted Swinging TavernSignboard on OutpostTavern front porch fascia.
	var sign0 := op0.tavern_sign_node
	var pivot0 := op0.tavern_sign_pivot
	check(sign0 != null and sign0.name == "TavernSignboard", "Outpost builds TavernSignboard node")
	check(pivot0 != null and pivot0.name == "TavernSignPivot", "TavernSignboard builds swinging TavernSignPivot")
	var bracket_mi := sign0.get_node_or_null(^"TavernSignBracket") as MeshInstance3D if sign0 != null else null
	var board_mi := pivot0.get_node_or_null(^"TavernSignBoard") as MeshInstance3D if pivot0 != null else null
	var face_mi := pivot0.get_node_or_null(^"TavernSignFace") as MeshInstance3D if pivot0 != null else null
	var bracket_mi1 := op1.tavern_sign_node.get_node_or_null(^"TavernSignBracket") as MeshInstance3D if op1.tavern_sign_node != null else null
	var board_mi1 := op1.tavern_sign_pivot.get_node_or_null(^"TavernSignBoard") as MeshInstance3D if op1.tavern_sign_pivot != null else null

	check(bracket_mi != null and bracket_mi.mesh is ArrayMesh, "TavernSignBracket uses sculpted ArrayMesh")
	check(board_mi != null and board_mi.mesh is ArrayMesh, "TavernSignBoard uses sculpted ArrayMesh")
	check(face_mi != null and face_mi.mesh is ArrayMesh, "TavernSignFace uses sculpted double-sided ArrayMesh")
	if bracket_mi != null and bracket_mi1 != null:
		check_eq(bracket_mi.mesh, bracket_mi1.mesh, "Outposts share statically cached TavernSignBracket mesh")
	if board_mi != null and board_mi1 != null:
		check_eq(board_mi.mesh, board_mi1.mesh, "Outposts share statically cached TavernSignBoard mesh")

	var bracket_tris := _count_array_mesh_tris(bracket_mi.mesh) if bracket_mi != null else 0
	var board_tris := _count_array_mesh_tris(board_mi.mesh) if board_mi != null else 0
	var face_tris := _count_array_mesh_tris(face_mi.mesh) if face_mi != null else 0
	check(bracket_tris >= 220, "TavernSignBracket has forged scrollwork geometry (%d tris >= 220)" % bracket_tris)
	check(board_tris >= 220, "TavernSignBoard has sculpted chain links, beveled plaque & brass brackets (%d tris >= 220)" % board_tris)
	check_eq(face_tris, 4, "TavernSignFace is a crisp double-sided 4-tri UV plaque")

	# Verify 256x160 painted crest texture & EMISSION_OP_MULTIPLY warm gold glow mask (dark wood = 0 emission!).
	var face_mat := face_mi.material_override as StandardMaterial3D if face_mi != null else null
	check(face_mat != null and face_mat.emission_enabled and face_mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY,
		"TavernSignFace uses EMISSION_OP_MULTIPLY so dark mahogany stays unlit while gold emblem & banner glint")
	if face_mat != null:
		var alb_tex := face_mat.albedo_texture as ImageTexture
		var emit_tex := face_mat.emission_texture as ImageTexture
		check(alb_tex != null and alb_tex.get_width() == 256 and alb_tex.get_height() == 160,
			"TavernSignFace paints 256x160 albedo crest ImageTexture")
		check(emit_tex != null and emit_tex.get_width() == 256 and emit_tex.get_height() == 160,
			"TavernSignFace paints 256x160 warm gold emission mask ImageTexture")
		if emit_tex != null:
			var eimg := emit_tex.get_image()
			# Plain dark mahogany corner field stays zero emission; bright gold border/text shines!
			var wood_px := eimg.get_pixel(28, 30)
			var frame_px := eimg.get_pixel(6, 80)
			check(wood_px.r < 0.02 and wood_px.g < 0.02 and wood_px.b < 0.02,
				"Dark mahogany wood field has zero emission in glow mask (got %s)" % str(wood_px))
			check(frame_px.r > 0.35 and frame_px.g > 0.25,
				"Gilded border/emblem glows warmly in emission mask (got %s)" % str(frame_px))

	# Verify wind-driven pendulum sway updates tavern_sign_pivot.rotation smoothly across frames!
	if pivot0 != null:
		var rot_before := pivot0.rotation
		for _i in 10:
			await get_tree().process_frame
		var rot_delta := pivot0.rotation.distance_to(rot_before)
		check(rot_delta > 0.005,
			"TavernSignPivot sways smoothly under harbour wind (delta=%.4f rad)" % rot_delta)

	# 2. Verify Interactive Seaward PierFogBell mounted atop seaward PORT bollard piling (-1.58, 2.23, -15.6).
	var bell0 := op0.pier_bell_node
	var bell_piv0 := op0.pier_bell_pivot
	var bell_it := op0.pier_bell_interactable
	check(bell0 != null and bell0.name == "PierFogBell", "Outpost builds PierFogBell atop seaward port piling")
	check(bell_piv0 != null and bell_piv0.name == "PierBellPivot", "PierFogBell builds swinging PierBellPivot")
	check(bell_it != null and bell_it.name == "PierFogBellInteractable" and bell_it.enabled,
		"PierFogBell exposes enabled PierFogBellInteractable")
	if bell_it != null:
		check_eq(bell_it.prompt, "Ring harbour fog-bell", "PierFogBellInteractable prompt matches")
		check_near(bell_it.reach, 2.4, 0.01, "PierFogBellInteractable reach is 2.4 m")

	if bell0 != null:
		var expected_bell_pos := op0.dock_local_transform * Vector3(-1.58, 2.23, -15.6)
		check(bell0.position.distance_to(expected_bell_pos) < 0.02,
			"PierFogBell sits squarely atop DockPier seaward PORT bollard piling")

	var frame_mi := bell0.get_node_or_null(^"PierBellFrame") as MeshInstance3D if bell0 != null else null
	var cup_mi := bell_piv0.get_node_or_null(^"PierBellCup") as MeshInstance3D if bell_piv0 != null else null
	var frame_mi1 := op1.pier_bell_node.get_node_or_null(^"PierBellFrame") as MeshInstance3D if op1.pier_bell_node != null else null
	var cup_mi1 := op1.pier_bell_pivot.get_node_or_null(^"PierBellCup") as MeshInstance3D if op1.pier_bell_pivot != null else null

	check(frame_mi != null and frame_mi.mesh is ArrayMesh, "PierBellFrame uses sculpted ArrayMesh")
	check(cup_mi != null and cup_mi.mesh is ArrayMesh, "PierBellCup uses lathe-turned sculpted ArrayMesh")
	if frame_mi != null and frame_mi1 != null:
		check_eq(frame_mi.mesh, frame_mi1.mesh, "Outposts share statically cached PierBellFrame mesh")
	if cup_mi != null and cup_mi1 != null:
		check_eq(cup_mi.mesh, cup_mi1.mesh, "Outposts share statically cached PierBellCup mesh")

	var frame_tris := _count_array_mesh_tris(frame_mi.mesh) if frame_mi != null else 0
	var cup_tris := _count_array_mesh_tris(cup_mi.mesh) if cup_mi != null else 0
	check(frame_tris >= 280, "PierBellFrame has sculpted gallows yoke & piling collar (%d tris >= 280)" % frame_tris)
	check(cup_tris >= 380, "PierBellCup has sculpted hollow lathe-turned bronze bell & clapper (%d tris >= 380)" % cup_tris)

	# Confirm ZERO raw PrimitiveMeshes anywhere across TavernSignboard, PierFogBell & the entire Outpost!
	var raw_prims: Array[String] = []
	for node in op0.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			raw_prims.append(mi.name)
	check(raw_prims.is_empty(), "Outpost has zero raw PrimitiveMeshes (found: %s)" % str(raw_prims))

	# Verify ring_pier_bell() & PierFogBellInteractable impulse pendulum swing, emit pier_bell_rung & post notice!
	var rung_pawns: Array[Node] = []
	var rung_cb := func(p: Node) -> void: rung_pawns.append(p)
	op0.pier_bell_rung.connect(rung_cb)
	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	var captain := PAWN_SCENE.instantiate() as Pawn
	add_child(captain)
	captain.global_position = bell0.global_position + Vector3(0.8, -0.8, 0.8) if bell0 != null else Vector3.ZERO

	if bell_it != null:
		bell_it.interact(captain)
	else:
		op0.ring_pier_bell(captain)
	check_eq(rung_pawns.size(), 1, "Interacting with PierFogBell emits pier_bell_rung once")
	check_eq(rung_pawns[0], captain, "pier_bell_rung passes interacting Pawn")
	var expected_notice := "Harbour fog-bell tolls across %s! Fair winds, Captain!" % op0.display_name
	check(notices.has(expected_notice), "ring_pier_bell posts harbour greeting notice (%s)" % expected_notice)

	var max_bell_swing := absf(bell_piv0.rotation.x) if bell_piv0 != null else 0.0
	for _i in 12:
		await get_tree().process_frame
		if bell_piv0 != null:
			max_bell_swing = maxf(max_bell_swing, absf(bell_piv0.rotation.x))
	check(max_bell_swing > 0.15,
		"ring_pier_bell swings PierBellPivot robustly via damped harmonic pendulum (max=%.3f rad)" % max_bell_swing)

	print("    outpost wave21c sculpted tris: TavernSignBracket=%d, TavernSignBoard=%d, TavernSignFace=%d, PierBellFrame=%d, PierBellCup=%d" % [
		bracket_tris, board_tris, face_tris, frame_tris, cup_tris])

	Game.notice.disconnect(notice_cb)
	op0.pier_bell_rung.disconnect(rung_cb)
	captain.queue_free()
	arch.queue_free()
	await physics_frames(3)

	# 3. Verify 100% zero-leak teardown of all new static shared meshes, materials & textures!
	check(not is_instance_valid(sign0) and not is_instance_valid(bell0),
		"TavernSignboard and PierFogBell freed cleanly with Outpost")
	check(Outpost._tavern_sign_bracket_mesh == null and Outpost._tavern_sign_board_mesh == null \
			and Outpost._tavern_sign_face_mesh == null and Outpost._tavern_sign_albedo_tex == null \
			and Outpost._tavern_sign_emit_tex == null and Outpost._tavern_sign_face_mat == null \
			and Outpost._pier_bell_frame_mesh == null and Outpost._pier_bell_cup_mesh == null \
			and Outpost._pier_bell_iron_mat == null and Outpost._pier_bell_bronze_mat == null,
		"Outpost.clear_shared_cache() releases all TavernSignboard & PierFogBell static resources cleanly")
	Weather.apply_state(saved_weather)


func test_sculpted_high_detail_flora_and_rock_props() -> void:
	# Regression guard for Pass Q2B sculpted flora & rock upgrades:
	# verifies high-detail tri budgets, UV2 wind weights, valid MikkTSpace tangents,
	# preserved PBR material names, and col_* collision meshes.
	var specs: Array[Dictionary] = [
		{
			"file": "palm_tall.glb",
			"min_tris": 3200, "max_tris": 5200, "cols": 2,
			"need_uv2": true, "min_foliage_tris": 2400,
			"mats": ["mat_foliage", "mat_bark_palm", "mat_paint"],
		},
		{
			"file": "palm_curved.glb",
			"min_tris": 3200, "max_tris": 5200, "cols": 2,
			"need_uv2": true, "min_foliage_tris": 2200,
			"mats": ["mat_foliage", "mat_bark_palm", "mat_paint"],
		},
		{
			"file": "jungle_banyan.glb",
			"min_tris": 4500, "max_tris": 7000, "cols": 1,
			"need_uv2": true, "min_foliage_tris": 3000,
			"mats": ["mat_foliage", "mat_bark_banyan"],
		},
		{
			"file": "bush_fern.glb",
			"min_tris": 1800, "max_tris": 3000, "cols": 0,
			"need_uv2": true, "min_foliage_tris": 1400,
			"mats": ["mat_foliage", "mat_bark_banyan", "mat_paint"],
		},
		{
			"file": "rock_boulder.glb",
			"min_tris": 350, "max_tris": 800, "cols": 1,
			"need_uv2": false, "min_foliage_tris": 0,
			"mats": ["mat_rock"],
		},
		{
			"file": "rock_spire.glb",
			"min_tris": 350, "max_tris": 800, "cols": 3,
			"need_uv2": false, "min_foliage_tris": 0,
			"mats": ["mat_rock"],
		},
	]

	for spec in specs:
		var fname: String = String(spec["file"])
		var path := "res://assets/generated/props/" + fname
		check(ResourceLoader.exists(path), "missing prop " + path)
		var packed := load(path) as PackedScene
		check(packed != null, "failed to load " + path)
		if packed == null:
			continue
		var inst := packed.instantiate() as Node3D
		check(inst != null, "prop root must be Node3D: " + fname)
		if inst == null:
			continue

		var vis_tris := 0
		var foliage_tris := 0
		var col_count := 0
		var found_mats: Dictionary = {}
		var foliage_has_uv2 := false
		var foliage_max_w := 0.0
		var all_have_tangents := true

		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if mi.name.begins_with("col_"):
				col_count += 1
				continue
			var mesh := mi.mesh
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
				var s_tris := 0
				if raw_idx is PackedInt32Array and not (raw_idx as PackedInt32Array).is_empty():
					s_tris = floori(float((raw_idx as PackedInt32Array).size()) / 3.0)
				else:
					var raw_v: Variant = arrays[Mesh.ARRAY_VERTEX]
					if raw_v is PackedVector3Array:
						s_tris = floori(float((raw_v as PackedVector3Array).size()) / 3.0)
				vis_tris += s_tris

				var raw_tan: Variant = arrays[Mesh.ARRAY_TANGENT]
				if not (raw_tan is PackedFloat32Array) or (raw_tan as PackedFloat32Array).is_empty():
					all_have_tangents = false

				var mat := mesh.surface_get_material(si)
				var mname := mat.resource_name if mat != null else ""
				if not mname.is_empty():
					found_mats[mname] = true
				if mname.begins_with("mat_foliage"):
					foliage_tris += s_tris
					var raw_uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
					if raw_uv2 is PackedVector2Array and not (raw_uv2 as PackedVector2Array).is_empty():
						foliage_has_uv2 = true
						for uv2_pt: Vector2 in (raw_uv2 as PackedVector2Array):
							foliage_max_w = maxf(foliage_max_w, uv2_pt.x)

		var min_t: int = int(spec["min_tris"])
		var max_t: int = int(spec["max_tris"])
		var req_cols: int = int(spec["cols"])
		var need_uv2: bool = bool(spec["need_uv2"])
		var min_fol_t: int = int(spec["min_foliage_tris"])

		check(vis_tris >= min_t and vis_tris <= max_t,
			"%s visual tris %d outside sculpted budget [%d..%d]" % [fname, vis_tris, min_t, max_t])
		check_eq(col_count, req_cols, "%s must preserve %d col_* colliders" % [fname, req_cols])
		check(all_have_tangents, "%s visual surfaces must all carry valid MikkTSpace tangents" % fname)
		for req_mat_v: Variant in (spec["mats"] as Array):
			var req_mat := String(req_mat_v)
			var matched := false
			for fm_key: Variant in found_mats.keys():
				if String(fm_key).begins_with(req_mat):
					matched = true
					break
			check(matched, "%s missing required PBR material '%s' (found: %s)" % [fname, req_mat, str(found_mats.keys())])
		if need_uv2:
			check(foliage_tris >= min_fol_t,
				"%s foliage tris %d below sculpted minimum %d" % [fname, foliage_tris, min_fol_t])
			check(foliage_has_uv2, "%s mat_foliage surface must preserve UV2 Wind channel" % fname)
			check(foliage_max_w >= 0.75,
				"%s UV2 wind sway weights must reach tips (>= 0.75, got %.2f)" % [fname, foliage_max_w])
		print("    prop %s: %d tris (foliage=%d, cols=%d, uv2_max=%.2f)" % [
			fname, vis_tris, foliage_tris, col_count, foliage_max_w])
		inst.free()


func test_q3b_living_island_wildlife_species_behaviors_grounding_and_teardown() -> void:
	_init_host()
	var saved_weather := Weather.get_state()
	Weather.day_length_seconds = 0.0
	Weather.time_of_day = 11.5

	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	var pawn := PAWN_SCENE.instantiate() as Pawn
	add_child(pawn)
	# Park pawn near Cutlass Cay outer reef so Cutlass is active while distant islands cull.
	var cutlass := arch.get_island_by_id("cutlass_cay")
	var port := arch.get_island_by_id("port_scoundrel")
	var volcano := arch.get_island_by_id("cinder_crag")
	var galleons := arch.get_island_by_id("galleons_reach")
	check(cutlass != null and port != null and volcano != null and galleons != null,
		"Archipelago must provide cutlass_cay, port_scoundrel, cinder_crag, and galleons_reach")
	if cutlass == null or port == null or volcano == null or galleons == null:
		pawn.queue_free()
		arch.queue_free()
		Weather.apply_state(saved_weather)
		return

	pawn.global_position = cutlass.global_position + Vector3(0.0, 2.0, -78.0)

	var wildlifes := IslandWildlife.populate_archipelago(self, arch, pawn)
	await physics_frames(1)
	check_eq(wildlifes.size(), 14, "IslandWildlife must populate all 14 archipelago islands")

	# 1. Verify group membership, zero PrimitiveMeshes, sRGB vertex colors, & flush grounding across ALL 14 islands.
	var raw_prims: Array[String] = []
	var bad_mats: Array[String] = []
	var total_turtles := 0
	var total_crabs := 0
	var total_parrots := 0
	var total_insects := 0
	for w in wildlifes:
		check(w.is_in_group(&"island_wildlife"), "IslandWildlife %s must belong to group island_wildlife" % w.get_parent().name)
		var isl := w.get_parent() as Island
		check(isl != null, "IslandWildlife must attach directly as child of Island")
		if isl == null:
			continue

		for node in w.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null:
				continue
			if mi.mesh is PrimitiveMesh:
				raw_prims.append("%s/%s" % [isl.island_id, mi.name])
			var mat := mi.material_override as StandardMaterial3D
			if mat == null or not mat.vertex_color_use_as_albedo or not mat.vertex_color_is_srgb or mat.uv1_world_triplanar:
				bad_mats.append("%s/%s" % [isl.island_id, mi.name])

		for t_node in w.get_turtles():
			total_turtles += 1
			var gh := isl.surface_height(t_node.position.x, t_node.position.z)
			check(t_node.position.y > 0.10, "SeaTurtle on %s must stay above water (y=%.3f)" % [isl.island_id, t_node.position.y])
			check(absf(t_node.position.y - gh) < 0.12,
				"SeaTurtle on %s must sit flush on terrain (y=%.3f vs h=%.3f)" % [isl.island_id, t_node.position.y, gh])

		for c_node in w.get_crabs():
			total_crabs += 1
			var gh := isl.surface_height(c_node.position.x, c_node.position.z)
			check(c_node.position.y > 0.10, "CoralCrab on %s must stay above water (y=%.3f)" % [isl.island_id, c_node.position.y])
			check(absf(c_node.position.y - gh) < 0.12,
				"CoralCrab on %s must sit flush on terrain (y=%.3f vs h=%.3f)" % [isl.island_id, c_node.position.y, gh])

		total_parrots += w.get_parrots().size()
		total_insects += w.get_insects().size()

	check(raw_prims.is_empty(), "IslandWildlife must have ZERO PrimitiveMeshes (found: %s)" % str(raw_prims))
	check(bad_mats.is_empty(), "All IslandWildlife materials must use vertex_color_is_srgb=true (bad: %s)" % str(bad_mats))

	# 2. Verify sculpted triangle counts for all 4 species (body + articulated appendages).
	var parrot_scarlet_tris := _count_array_mesh_tris(IslandWildlife._parrot_scarlet_body) \
		+ _count_array_mesh_tris(IslandWildlife._parrot_scarlet_wing_l) \
		+ _count_array_mesh_tris(IslandWildlife._parrot_scarlet_wing_r)
	var parrot_emerald_tris := _count_array_mesh_tris(IslandWildlife._parrot_emerald_body) \
		+ _count_array_mesh_tris(IslandWildlife._parrot_emerald_wing_l) \
		+ _count_array_mesh_tris(IslandWildlife._parrot_emerald_wing_r)
	var turtle_tris := _count_array_mesh_tris(IslandWildlife._turtle_body_mesh) \
		+ _count_array_mesh_tris(IslandWildlife._turtle_head_mesh) \
		+ _count_array_mesh_tris(IslandWildlife._turtle_flipper_l_mesh) \
		+ _count_array_mesh_tris(IslandWildlife._turtle_flipper_r_mesh)
	var crab_tris := _count_array_mesh_tris(IslandWildlife._crab_body_mesh) \
		+ _count_array_mesh_tris(IslandWildlife._crab_claw_l_mesh) \
		+ _count_array_mesh_tris(IslandWildlife._crab_claw_r_mesh)
	var butterfly_tris := _count_array_mesh_tris(IslandWildlife._butterfly_body_mesh) \
		+ _count_array_mesh_tris(IslandWildlife._butterfly_morpho_wing_l) \
		+ _count_array_mesh_tris(IslandWildlife._butterfly_morpho_wing_r)
	var firefly_tris := _count_array_mesh_tris(IslandWildlife._firefly_mesh)

	check(parrot_scarlet_tris >= 380 and parrot_emerald_tris >= 380,
		"Parrot sculpted tris must be >= 380 (scarlet=%d, emerald=%d)" % [parrot_scarlet_tris, parrot_emerald_tris])
	check(turtle_tris >= 440, "SeaTurtle sculpted tris must be >= 440 (got %d)" % turtle_tris)
	check(crab_tris >= 280, "CoralCrab sculpted tris must be >= 280 (got %d)" % crab_tris)
	check(butterfly_tris >= 48, "Butterfly sculpted tris must be >= 48 (got %d)" % butterfly_tris)
	check(firefly_tris >= 16, "Firefly sculpted tris must be >= 16 (got %d)" % firefly_tris)

	# 3. Verify biome rules & guaranteed Cutlass Cay + Port Scoundrel beach showcase fauna.
	var cw := cutlass.get_node_or_null(^"IslandWildlife") as IslandWildlife
	var pw := port.get_node_or_null(^"IslandWildlife") as IslandWildlife
	var vw := volcano.get_node_or_null(^"IslandWildlife") as IslandWildlife
	var gw := galleons.get_node_or_null(^"IslandWildlife") as IslandWildlife
	check(cw != null and pw != null and vw != null and gw != null, "Key islands must mount IslandWildlife")
	check_eq(vw.get_turtles().size(), 0, "Volcanic Cinder Crag must skip sea turtles")
	check_eq(vw.get_insects().size(), 0, "Volcanic Cinder Crag must skip meadow butterflies")
	for showcase_pair: Array in [[cutlass, cw], [port, pw]]:
		var s_isl := showcase_pair[0] as Island
		var s_w := showcase_pair[1] as IslandWildlife
		check(s_w.get_turtles().size() >= 1, "%s must place >= 1 basking sea turtle" % s_isl.display_name)
		check(s_w.get_crabs().size() >= 2, "%s must place >= 2 coral sand-crabs" % s_isl.display_name)
		check(s_w.get_insects().size() >= 2, "%s must place >= 2 butterflies/fireflies" % s_isl.display_name)
		check(s_w.get_parrots().size() >= 1, "%s must place >= 1 Scarlet Macaw" % s_isl.display_name)

	# 4. Verify distance culling (> island_radius + 180 m skips distant islands, keeps near Cutlass active).
	cw._process(0.05)
	gw._process(0.05)
	check(not cw.distance_culled, "Near Cutlass Cay wildlife must remain active")
	check(gw.distance_culled, "Distant Galleon's Reach wildlife (> radius + 180 m) must distance-cull")

	# 5. Verify live behaviors: crab scuttling, turtle crawling/flippers, butterfly flapping & figure-8 path!
	var turtle0 := cw.get_turtles()[0]
	var turtle0_start := turtle0.position
	var turtle0_fl := turtle0.get_node_or_null(^"FrontLeftFlipper") as Node3D
	var turtle0_fl_rot0 := turtle0_fl.rotation if turtle0_fl != null else Vector3.ZERO

	var crab_starts: Array[Vector3] = []
	for c_node in cw.get_crabs():
		crab_starts.append(c_node.position)

	var insect0 := cw.get_insects()[0]
	var insect0_start := insect0.position
	var bf_vis0 := insect0.get_node_or_null(^"ButterflyVisual") as Node3D
	var ff_vis0 := insect0.get_node_or_null(^"FireflyVisual") as Node3D
	var bf_wl := bf_vis0.get_node_or_null(^"LeftWing") as Node3D if bf_vis0 != null else null
	var bf_wl_rot0 := bf_wl.rotation if bf_wl != null else Vector3.ZERO
	check(bf_vis0 != null and bf_vis0.visible and ff_vis0 != null and not ff_vis0.visible,
		"Daytime (11:30) must show sculpted ButterflyVisual and hide FireflyVisual")

	var max_bf_wing_delta := 0.0
	var max_fl_delta := 0.0
	for _step in 36:
		cw._process(0.05)
		if bf_wl != null:
			max_bf_wing_delta = maxf(max_bf_wing_delta, bf_wl.rotation.distance_to(bf_wl_rot0))
		if turtle0_fl != null:
			max_fl_delta = maxf(max_fl_delta, turtle0_fl.rotation.distance_to(turtle0_fl_rot0))

	var crab_moved := false
	for ci in cw.get_crabs().size():
		var cn := cw.get_crabs()[ci]
		if cn.position.distance_to(crab_starts[ci]) > 0.15:
			crab_moved = true
		var gh := cutlass.surface_height(cn.position.x, cn.position.z)
		check(absf(cn.position.y - gh) < 0.12 and cn.position.y > 0.10,
			"Scuttling CoralCrab must stay flush on terrain & above water (y=%.3f vs h=%.3f)" % [cn.position.y, gh])
	check(crab_moved, "Stepping _process() must advance CoralCrab scuttling across beach")

	var turtle_moved := turtle0.position.distance_to(turtle0_start) > 0.12
	var t_gh := cutlass.surface_height(turtle0.position.x, turtle0.position.z)
	check(turtle_moved, "Stepping _process() must advance SeaTurtle crawling along shore arc")
	check(max_fl_delta > 0.15, "SeaTurtle front flippers must stroke smoothly while crawling (delta=%.3f)" % max_fl_delta)
	check(absf(turtle0.position.y - t_gh) < 0.12 and turtle0.position.y > 0.10,
		"Crawling SeaTurtle must stay flush on terrain & above water (y=%.3f vs h=%.3f)" % [turtle0.position.y, t_gh])

	check(insect0.position.distance_to(insect0_start) > 0.15,
		"Stepping _process() must advance Butterfly along its figure-8 glade path")
	check(max_bf_wing_delta > 0.25,
		"Butterfly wings must flap smoothly during daytime flight (delta=%.3f)" % max_bf_wing_delta)

	# 6. Verify Parrot startle into soaring circular flight when player approaches < 5 m, then glides back to perch!
	var parrot0 := cw.get_parrots()[0]
	var perch_pos0 := parrot0.position
	check(not cw.is_parrot_flying(0), "Scarlet Macaw 0 should start perched calmly")
	pawn.global_position = cutlass.global_transform * (perch_pos0 + Vector3(2.2, 0.0, 1.5))
	cw._process(0.05)
	check(cw.is_parrot_flying(0), "Parrot must startle into soaring flight when player approaches < 5 m")

	# Step pawn back out of startle zone so parrot completes its 6..9 s soaring flight and glides back to perch.
	pawn.global_position = cutlass.global_position + Vector3(0.0, 2.0, -78.0)
	var peak_flight_y := parrot0.position.y
	var max_orbit_dist := 0.0
	for _step in 60:
		cw._process(0.05)
		peak_flight_y = maxf(peak_flight_y, parrot0.position.y)
		max_orbit_dist = maxf(max_orbit_dist, Vector2(parrot0.position.x - perch_pos0.x, parrot0.position.z - perch_pos0.z).length())
	check(peak_flight_y > perch_pos0.y + 1.8,
		"Startled parrot must climb into soaring flight (peak_y=%.2f vs perch=%.2f)" % [peak_flight_y, perch_pos0.y])
	check(max_orbit_dist > 5.0,
		"Startled parrot must soar outward in circular flight (max_dist=%.2f m)" % max_orbit_dist)

	for _step in 180:
		cw._process(0.05)
		if not cw.is_parrot_flying(0):
			break
	check(not cw.is_parrot_flying(0), "Startled parrot must smoothly glide back down to perch after flight")
	check(parrot0.position.distance_to(perch_pos0) < 0.15,
		"Returning parrot must alight accurately on its original perch")

	# 7. Verify turtle shy head-tucking when player approaches < 3.5 m.
	var t_head := turtle0.get_node_or_null(^"HeadPivot") as Node3D
	var head_z_calm := t_head.position.z if t_head != null else -0.50
	pawn.global_position = cutlass.global_transform * (turtle0.position + Vector3(1.5, 0.0, 0.0))
	for _step in 16:
		cw._process(0.05)
	if t_head != null:
		check(t_head.position.z > head_z_calm + 0.06,
			"SeaTurtle must pull head inward when player steps within 3.5 m (z=%.3f -> %.3f)" % [head_z_calm, t_head.position.z])

	# 8. Verify seamless Day -> Dusk/Night butterfly-to-firefly swap!
	Weather.time_of_day = 21.5
	cw._process(0.05)
	check(bf_vis0 != null and not bf_vis0.visible and ff_vis0 != null and ff_vis0.visible,
		"Nighttime (21:30) must swap ButterflyVisual off and show glowing FireflyVisual")

	print("    q3b island wildlife: 14 islands (%d parrots, %d turtles, %d crabs, %d insects), tris=[parrot:%d/%d, turtle:%d, crab:%d, butterfly:%d, firefly:%d]" % [
		total_parrots, total_turtles, total_crabs, total_insects,
		parrot_scarlet_tris, parrot_emerald_tris, turtle_tris, crab_tris, butterfly_tris, firefly_tris])

	# 9. Verify 100% clean teardown and static shared cache release (0 ObjectDB leaks).
	pawn.queue_free()
	arch.queue_free()
	await physics_frames(3)
	IslandWildlife.clear_shared_cache()

	check(not is_instance_valid(cw), "IslandWildlife nodes must free cleanly on Archipelago teardown")
	check_eq(IslandWildlife._active_instances, 0, "IslandWildlife active instance counter must return to 0")
	check(IslandWildlife._parrot_scarlet_body == null and IslandWildlife._parrot_emerald_body == null \
			and IslandWildlife._turtle_body_mesh == null and IslandWildlife._crab_body_mesh == null \
			and IslandWildlife._butterfly_body_mesh == null and IslandWildlife._firefly_mesh == null \
			and IslandWildlife._feather_mat == null and IslandWildlife._shell_mat == null \
			and IslandWildlife._butterfly_mat == null and IslandWildlife._firefly_mat == null,
		"IslandWildlife.clear_shared_cache() must release all static meshes and materials cleanly")

	Weather.apply_state(saved_weather)


func test_q5a_upgraded_harbour_bastion_pier_architecture_and_rocks() -> void:
	# Verify Pass Q5A sculpted seawall_bastion, dock_pier, sunlit limestone rocks, and coastal architecture.
	var prop_specs: Array[Dictionary] = [
		{
			"file": "seawall_bastion.glb",
			"min_tris": 1000,
			"max_tris": 2500,
			"cols": 2,
			"empty": "Lantern_Seawall",
			"mats": ["mat_stone", "mat_wood", "mat_iron", "mat_rope", "mat_foliage"],
			"need_ivy_uv2": true,
			"max_base_y": -0.60,
			"warm_stone": true,
		},
		{
			"file": "dock_pier.glb",
			"min_tris": 3000,
			"max_tris": 18000,
			"cols": 10,
			"empty": "Lantern_Dock",
			"mats": ["mat_wood", "mat_stone", "mat_rope", "mat_iron"],
			"need_ivy_uv2": false,
			"max_base_y": -0.60,
			"warm_stone": false,
		},
		{
			"file": "rock_boulder.glb",
			"min_tris": 350,
			"max_tris": 800,
			"cols": 1,
			"empty": "",
			"mats": ["mat_rock"],
			"need_ivy_uv2": false,
			"max_base_y": 0.0,
			"warm_rock": true,
		},
		{
			"file": "rock_spire.glb",
			"min_tris": 350,
			"max_tris": 800,
			"cols": 3,
			"empty": "",
			"mats": ["mat_rock"],
			"need_ivy_uv2": false,
			"max_base_y": -0.50,
			"warm_rock": true,
		},
		{
			"file": "rock_arch.glb",
			"min_tris": 400,
			"max_tris": 1200,
			"cols": 3,
			"empty": "",
			"mats": ["mat_rock"],
			"need_ivy_uv2": false,
			"max_base_y": -0.50,
			"warm_rock": true,
		},
		{
			"file": "outpost_tavern.glb",
			"min_tris": 3000,
			"max_tris": 12000,
			"cols": 8,
			"empty": "Lantern_Tavern",
			"mats": ["mat_plaster", "mat_stone", "mat_wood"],
			"need_ivy_uv2": false,
			"max_base_y": -0.70,
			"warm_stone": false,
		},
		{
			"file": "harbour_warehouse.glb",
			"min_tris": 2500,
			"max_tris": 12000,
			"cols": 2,
			"empty": "Lantern_Warehouse",
			"mats": ["mat_plaster", "mat_stone", "mat_wood"],
			"need_ivy_uv2": false,
			"max_base_y": -0.70,
			"warm_stone": false,
		},
		{
			"file": "beacon_tower.glb",
			"min_tris": 2500,
			"max_tris": 10000,
			"cols": 3,
			"empty": "Lantern_Beacon",
			"mats": ["mat_plaster", "mat_stone", "mat_wood"],
			"need_ivy_uv2": false,
			"max_base_y": -0.70,
			"warm_stone": false,
		},
	]

	for spec: Dictionary in prop_specs:
		var fname := String(spec["file"])
		var path := "res://assets/generated/props/" + fname
		var packed := load(path) as PackedScene
		check(packed != null, "Q5A prop failed to load: " + path)
		if packed == null:
			continue
		var inst := packed.instantiate() as Node3D
		check(inst != null, "Q5A prop root must be Node3D: " + fname)
		if inst == null:
			continue

		var vis_tris := 0
		var col_count := 0
		var found_mats: Dictionary = {}
		var all_have_tangents := true
		var ivy_has_uv2 := false
		var ivy_max_w := 0.0
		var min_vis_y := 999.0
		var warm_r_sum := 0.0
		var warm_g_sum := 0.0
		var warm_b_sum := 0.0
		var warm_count := 0
		var moss_count := 0

		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if mi.name.begins_with("col_"):
				col_count += 1
				continue
			var mesh := mi.mesh
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
				var s_tris := 0
				if raw_idx is PackedInt32Array and not (raw_idx as PackedInt32Array).is_empty():
					s_tris = floori(float((raw_idx as PackedInt32Array).size()) / 3.0)
				else:
					var raw_v0: Variant = arrays[Mesh.ARRAY_VERTEX]
					if raw_v0 is PackedVector3Array:
						s_tris = floori(float((raw_v0 as PackedVector3Array).size()) / 3.0)
				vis_tris += s_tris

				var raw_tan: Variant = arrays[Mesh.ARRAY_TANGENT]
				if not (raw_tan is PackedFloat32Array) or (raw_tan as PackedFloat32Array).is_empty():
					all_have_tangents = false

				var mat := mesh.surface_get_material(si)
				var mname := mat.resource_name if mat != null else ""
				if not mname.is_empty():
					found_mats[mname] = true

				var raw_verts: Variant = arrays[Mesh.ARRAY_VERTEX]
				var raw_cols: Variant = arrays[Mesh.ARRAY_COLOR]
				if raw_verts is PackedVector3Array:
					var verts := raw_verts as PackedVector3Array
					for vi in verts.size():
						var vp := mi.transform * verts[vi]
						min_vis_y = minf(min_vis_y, vp.y)
						if raw_cols is PackedColorArray and vi < (raw_cols as PackedColorArray).size():
							var vc: Color = (raw_cols as PackedColorArray)[vi]
							if bool(spec.get("warm_rock", false)) and mname.begins_with("mat_rock") and vp.y >= 0.50:
								if vc.g > vc.r + 0.03:
									moss_count += 1
								else:
									warm_r_sum += vc.r
									warm_g_sum += vc.g
									warm_b_sum += vc.b
									warm_count += 1
							elif bool(spec.get("warm_stone", false)) and mname.begins_with("mat_stone") and vp.y >= 0.70:
								warm_r_sum += vc.r
								warm_g_sum += vc.g
								warm_b_sum += vc.b
								warm_count += 1

				if mname.begins_with("mat_foliage"):
					var raw_uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
					if raw_uv2 is PackedVector2Array and not (raw_uv2 as PackedVector2Array).is_empty():
						ivy_has_uv2 = true
						for uv2_pt: Vector2 in (raw_uv2 as PackedVector2Array):
							ivy_max_w = maxf(ivy_max_w, uv2_pt.x)

		var min_t: int = int(spec["min_tris"])
		var max_t: int = int(spec["max_tris"])
		var req_cols: int = int(spec["cols"])
		check(vis_tris >= min_t and vis_tris <= max_t,
			"%s visual tris %d outside Q5A budget [%d..%d]" % [fname, vis_tris, min_t, max_t])
		check_eq(col_count, req_cols, "%s must preserve %d col_* colliders" % [fname, req_cols])
		check(all_have_tangents, "%s visual surfaces must all carry valid MikkTSpace tangents" % fname)

		var req_empty := String(spec["empty"])
		if not req_empty.is_empty():
			check(inst.find_child(req_empty, true, false) != null,
				"%s must preserve %s empty marker" % [fname, req_empty])

		for req_mat_v: Variant in (spec["mats"] as Array):
			var req_mat := String(req_mat_v)
			var matched := false
			for fm_key: Variant in found_mats.keys():
				if String(fm_key).begins_with(req_mat):
					matched = true
					break
			check(matched, "%s missing required material '%s' (found: %s)" % [fname, req_mat, str(found_mats.keys())])

		if bool(spec["need_ivy_uv2"]):
			check(ivy_has_uv2, "%s sea-ivy mat_foliage must carry UV2 wind weights" % fname)
			check(ivy_max_w >= 0.70,
				"%s sea-ivy UV2 wind sway weights must reach tips (>= 0.70, got %.2f)" % [fname, ivy_max_w])

		var max_base_y: float = float(spec["max_base_y"])
		check(min_vis_y <= max_base_y,
			"%s foundation/base must plunge cleanly <= %.2f m (got min_y=%.2f)" % [fname, max_base_y, min_vis_y])

		if bool(spec.get("warm_rock", false)) or bool(spec.get("warm_stone", false)):
			check(warm_count > 20, "%s must contain sunlit limestone/sandstone upper vertices" % fname)
			if warm_count > 0:
				var mr := warm_r_sum / float(warm_count)
				var mg := warm_g_sum / float(warm_count)
				var mb := warm_b_sum / float(warm_count)
				check(mr >= 0.45 and mr >= mg and mg > mb and (mr - mb) >= 0.12,
					"%s upper stone/rock must be warm sunlit limestone, not dark charcoal (mean rgb=%.2f,%.2f,%.2f)" % [
						fname, mr, mg, mb])
				if fname == "rock_boulder.glb" or fname == "rock_arch.glb":
					check(moss_count > 0, "%s must include emerald coastal moss cap accents on upper shelves" % fname)
				print("    q5a %s: %d tris, %d cols, min_y=%.2f, sunlit_rgb=(%.2f,%.2f,%.2f), moss_v=%d" % [
					fname, vis_tris, col_count, min_vis_y, mr, mg, mb, moss_count])
		else:
			print("    q5a %s: %d tris, %d cols, min_y=%.2f" % [fname, vis_tris, col_count, min_vis_y])

		inst.free()


func test_q7a_remaining_outpost_ruin_wreck_and_camp_prop_craft() -> void:
	# Verify Pass Q7A upgrades across the remaining 10 outpost, ruin, wreck, camp & bridge props:
	# sculpted hero budgets, MikkTSpace tangents, preserved empties & colliders, warm Q5A coral-sandstone
	# harmony (no cold grey regressions), Q2B UV2-weighted sculpted ruin foliage, and chest carry bounds.
	var prop_specs: Array[Dictionary] = [
		{
			"file": "outpost_stall.glb",
			"min_tris": 4200, "max_tris": 8500,
			"cols": ["col_stall_counter", "col_stall_back", "col_stall_roof"],
			"empty": "Lantern_Stall",
			"mats": ["mat_stone", "mat_wood", "mat_awning", "mat_brass", "mat_iron", "mat_rope", "mat_paint", "mat_lantern_glass"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": -1.10, "warm_mat": "mat_stone", "warm_min_y": 0.0,
		},
		{
			"file": "notice_board.glb",
			"min_tris": 2200, "max_tris": 4800,
			"cols": ["col_notice_board"],
			"empty": "",
			"mats": ["mat_stone", "mat_wood", "mat_shingle", "mat_brass", "mat_iron", "mat_paint", "mat_lantern_glass"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": -0.60, "warm_mat": "mat_stone", "warm_min_y": 0.0,
		},
		{
			"file": "ruin_arch.glb",
			"min_tris": 2800, "max_tris": 5800,
			"cols": ["col_arch_l", "col_arch_r"],
			"empty": "",
			"mats": ["mat_stone", "mat_rock", "mat_brass", "mat_foliage"],
			"need_foliage_uv2": true, "min_foliage_tris": 800,
			"max_base_y": -1.10, "warm_mat": "mat_stone", "warm_min_y": 0.50,
		},
		{
			"file": "ruin_pillar.glb",
			"min_tris": 1200, "max_tris": 2800,
			"cols": ["col_pillar"],
			"empty": "",
			"mats": ["mat_stone", "mat_rock", "mat_brass", "mat_foliage"],
			"need_foliage_uv2": true, "min_foliage_tris": 350,
			"max_base_y": -0.95, "warm_mat": "mat_stone", "warm_min_y": 0.35,
		},
		{
			"file": "campfire.glb",
			"min_tris": 1800, "max_tris": 3800,
			"cols": [],
			"empty": "Lantern_Fire",
			"mats": ["mat_rock", "mat_embers", "mat_iron", "mat_brass", "mat_wood", "mat_bark_banyan", "mat_paint"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": -0.10, "warm_mat": "mat_rock", "warm_min_y": 0.0,
		},
		{
			"file": "shipwreck_hulk.glb",
			"min_tris": 3600, "max_tris": 7200,
			"cols": ["col_wreck_hull", "col_wreck_mast"],
			"empty": "",
			"mats": ["mat_wood", "mat_awning", "mat_iron", "mat_brass", "mat_rock", "mat_rope"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": -1.00, "warm_mat": "", "warm_min_y": 0.0,
		},
		{
			"file": "chest_treasure.glb",
			"min_tris": 2000, "max_tris": 4200,
			"cols": [],
			"empty": "",
			"mats": ["mat_wood", "mat_brass", "mat_iron", "mat_paint"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": 0.05, "warm_mat": "", "warm_min_y": 0.0,
		},
		{
			"file": "watchtower_wood.glb",
			"min_tris": 5800, "max_tris": 9500,
			"cols": ["col_watch_base", "col_watch_deck"],
			"empty": "Lantern_Watch",
			"mats": ["mat_stone", "mat_wood", "mat_thatch", "mat_brass", "mat_iron", "mat_rope", "mat_awning", "mat_lantern_glass"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": -1.70, "warm_mat": "mat_stone", "warm_min_y": 0.0,
		},
		{
			"file": "timber_bridge.glb",
			"min_tris": 5600, "max_tris": 9500,
			"cols": ["col_bridge_deck_0", "col_bridge_deck_1", "col_bridge_deck_2"],
			"empty": "",
			"mats": ["mat_stone", "mat_wood", "mat_iron", "mat_rope"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": -1.80, "warm_mat": "mat_stone", "warm_min_y": 0.0,
		},
		{
			"file": "dig_mound.glb",
			"min_tris": 600, "max_tris": 1400,
			"cols": [],
			"empty": "",
			"mats": ["mat_paint", "mat_rock", "mat_wood", "mat_bark_banyan", "mat_rope"],
			"need_foliage_uv2": false, "min_foliage_tris": 0,
			"max_base_y": -0.20, "warm_mat": "mat_rock", "warm_min_y": 0.0,
		},
	]

	for spec: Dictionary in prop_specs:
		var fname := String(spec["file"])
		var path := "res://assets/generated/props/" + fname
		check(ResourceLoader.exists(path), "Q7A prop missing: " + path)
		var packed := load(path) as PackedScene
		check(packed != null, "Q7A prop failed to load: " + path)
		if packed == null:
			continue
		var inst := packed.instantiate() as Node3D
		check(inst != null, "Q7A prop root must be Node3D: " + fname)
		if inst == null:
			continue

		var vis_tris := 0
		var foliage_tris := 0
		var col_names: Dictionary = {}
		var found_mats: Dictionary = {}
		var all_have_tangents := true
		var fol_has_uv2 := false
		var fol_max_w := 0.0
		var bmin := Vector3(INF, INF, INF)
		var bmax := Vector3(-INF, -INF, -INF)
		var warm_mat := String(spec["warm_mat"])
		var warm_min_y: float = float(spec["warm_min_y"])
		var warm_r_sum := 0.0
		var warm_g_sum := 0.0
		var warm_b_sum := 0.0
		var warm_count := 0

		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if mi.name.begins_with("col_"):
				col_names[mi.name] = mi
				continue
			var mesh := mi.mesh
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
				var s_tris := 0
				if raw_idx is PackedInt32Array and not (raw_idx as PackedInt32Array).is_empty():
					s_tris = floori(float((raw_idx as PackedInt32Array).size()) / 3.0)
				else:
					var raw_v0: Variant = arrays[Mesh.ARRAY_VERTEX]
					if raw_v0 is PackedVector3Array:
						s_tris = floori(float((raw_v0 as PackedVector3Array).size()) / 3.0)
				vis_tris += s_tris

				var raw_tan: Variant = arrays[Mesh.ARRAY_TANGENT]
				if not (raw_tan is PackedFloat32Array) or (raw_tan as PackedFloat32Array).is_empty():
					all_have_tangents = false

				var mat := mesh.surface_get_material(si)
				var mname := mat.resource_name if mat != null else ""
				if not mname.is_empty():
					found_mats[mname] = true

				var raw_verts: Variant = arrays[Mesh.ARRAY_VERTEX]
				var raw_cols: Variant = arrays[Mesh.ARRAY_COLOR]
				if raw_verts is PackedVector3Array:
					var verts := raw_verts as PackedVector3Array
					for vi in verts.size():
						var vp := mi.transform * verts[vi]
						bmin = Vector3(minf(bmin.x, vp.x), minf(bmin.y, vp.y), minf(bmin.z, vp.z))
						bmax = Vector3(maxf(bmax.x, vp.x), maxf(bmax.y, vp.y), maxf(bmax.z, vp.z))
						if not warm_mat.is_empty() and mname.begins_with(warm_mat) and vp.y >= warm_min_y:
							if raw_cols is PackedColorArray and vi < (raw_cols as PackedColorArray).size():
								var vc: Color = (raw_cols as PackedColorArray)[vi]
								warm_r_sum += vc.r
								warm_g_sum += vc.g
								warm_b_sum += vc.b
								warm_count += 1

				if mname.begins_with("mat_foliage"):
					foliage_tris += s_tris
					var raw_uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
					if raw_uv2 is PackedVector2Array and not (raw_uv2 as PackedVector2Array).is_empty():
						fol_has_uv2 = true
						for uv2_pt: Vector2 in (raw_uv2 as PackedVector2Array):
							fol_max_w = maxf(fol_max_w, uv2_pt.x)

		var min_t: int = int(spec["min_tris"])
		var max_t: int = int(spec["max_tris"])
		var req_cols: Array = spec["cols"] as Array
		check(vis_tris >= min_t and vis_tris <= max_t,
			"%s visual tris %d outside Q7A budget [%d..%d]" % [fname, vis_tris, min_t, max_t])
		check_eq(col_names.size(), req_cols.size(), "%s must preserve exactly %d col_* colliders" % [fname, req_cols.size()])
		for req_col_v: Variant in req_cols:
			var cname := String(req_col_v)
			check(col_names.has(cname), "%s missing required collider '%s' (found: %s)" % [fname, cname, str(col_names.keys())])
		check(all_have_tangents, "%s visual surfaces must all carry valid MikkTSpace tangents" % fname)

		var req_empty := String(spec["empty"])
		if not req_empty.is_empty():
			check(inst.find_child(req_empty, true, false) != null,
				"%s must preserve %s empty marker" % [fname, req_empty])

		for req_mat_v: Variant in (spec["mats"] as Array):
			var req_mat := String(req_mat_v)
			var matched := false
			for fm_key: Variant in found_mats.keys():
				if String(fm_key).begins_with(req_mat):
					matched = true
					break
			check(matched, "%s missing required material '%s' (found: %s)" % [fname, req_mat, str(found_mats.keys())])

		if bool(spec["need_foliage_uv2"]):
			var min_fol_t: int = int(spec["min_foliage_tris"])
			check(foliage_tris >= min_fol_t,
				"%s sculpted Q2B ruin foliage tris %d below minimum %d" % [fname, foliage_tris, min_fol_t])
			check(fol_has_uv2, "%s mat_foliage must carry UV2 wind weights" % fname)
			check(fol_max_w >= 0.80,
				"%s cascading vine UV2 wind sway weights must reach tips (>= 0.80, got %.2f)" % [fname, fol_max_w])

		var max_base_y: float = float(spec["max_base_y"])
		check(bmin.y <= max_base_y,
			"%s base must plunge cleanly <= %.2f m (got min_y=%.2f)" % [fname, max_base_y, bmin.y])

		if not warm_mat.is_empty():
			check(warm_count > 20, "%s must contain warm sunlit sandstone %s vertices" % [fname, warm_mat])
			if warm_count > 0:
				var mr := warm_r_sum / float(warm_count)
				var mg := warm_g_sum / float(warm_count)
				var mb := warm_b_sum / float(warm_count)
				check(mr >= 0.45 and mr >= mg and mg > mb and (mr - mb) >= 0.12,
					"%s %s must stay warm sunlit Caribbean sandstone, not cold grey (mean rgb=%.2f,%.2f,%.2f)" % [
						fname, warm_mat, mr, mg, mb])
				print("    q7a %s: %d tris, %d cols, min_y=%.2f, %s_rgb=(%.2f,%.2f,%.2f), fol=%d" % [
					fname, vis_tris, col_names.size(), bmin.y, warm_mat, mr, mg, mb, foliage_tris])
		else:
			print("    q7a %s: %d tris, %d cols, min_y=%.2f, sz=(%.2f,%.2f,%.2f)" % [
				fname, vis_tris, col_names.size(), bmin.y, bmax.x - bmin.x, bmax.y - bmin.y, bmax.z - bmin.z])

		# Preserve exact walkable ~3.8 m arch opening between ruin_arch colliders!
		if fname == "ruin_arch.glb":
			var col_l := col_names.get("col_arch_l") as MeshInstance3D
			var col_r := col_names.get("col_arch_r") as MeshInstance3D
			if col_l != null and col_r != null:
				var aabb_l := col_l.get_aabb()
				var aabb_r := col_r.get_aabb()
				var opening_w := (col_r.position.x + aabb_r.position.x) - (col_l.position.x + aabb_l.end.x)
				check(opening_w >= 3.75,
					"ruin_arch.glb must preserve walkable ~3.8 m opening between col_arch_l and col_arch_r (got %.2f m)" % opening_w)

		# Strictly preserve ~0.66 x 0.44 x 0.44 m carry footprint on chest_treasure so FP carry hands never clip!
		if fname == "chest_treasure.glb":
			var sz := bmax - bmin
			check(sz.x <= 0.76 and sz.y <= 0.48 and sz.z <= 0.54,
				"chest_treasure.glb must preserve carry footprint <= (0.76,0.48,0.54) m (got %s)" % str(sz))

		inst.free()


func test_q8a_outpost_lantern_halos_campfire_chimney_smoke_and_npc_greetings() -> void:
	_init_host()
	var saved_weather := Weather.get_state()
	Weather.day_length_seconds = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 9.0, 0.3)

	var outpost := IslandGenerator.build_island(Archipelago.ISLAND_SPECS[0]) as Outpost
	check(outpost != null, "Port Scoundrel builds cleanly as Outpost")
	if outpost == null:
		Weather.apply_state(saved_weather)
		return
	add_child(outpost)
	await physics_frames(2)

	# 1. Warm atmospheric lantern halos (zero raw primitives, role-scaled, strong night vs midday lift).
	var halo_count := outpost.get_harbour_halo_count()
	check(halo_count >= 4, "Outpost mounts >= 4 atmospheric lantern halos (got %d)" % halo_count)
	var beacon_halo := outpost.find_child("Lantern_Beacon_Halo", true, false) as MeshInstance3D
	var fire_halo := outpost.find_child("Lantern_Fire_Halo", true, false) as MeshInstance3D
	var tavern_halo := outpost.find_child("Lantern_Tavern_Halo", true, false) as MeshInstance3D
	var dock_halo := outpost.find_child("Lantern_Dock_Halo", true, false) as MeshInstance3D
	var stall_halo := outpost.find_child("Lantern_Stall_Halo", true, false) as MeshInstance3D
	for hmi: MeshInstance3D in [beacon_halo, fire_halo, tavern_halo, dock_halo, stall_halo]:
		check(hmi != null and hmi.mesh is ArrayMesh and not (hmi.mesh is PrimitiveMesh),
			"Outpost lantern halo must use shared zero-primitive ArrayMesh")
		if hmi != null:
			check_eq(hmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"Outpost lantern halo disables shadows: " + hmi.name)
			check(hmi.material_override is ShaderMaterial, "Outpost lantern halo binds inline ShaderMaterial: " + hmi.name)
	if beacon_halo != null:
		var bmat := beacon_halo.material_override as ShaderMaterial
		check_near(float(bmat.get_shader_parameter(&"halo_scale")), 3.8, 0.01, "Lantern_Beacon_Halo scale == 3.8 m")
		check(beacon_halo.visibility_range_end >= 1799.0, "Lantern_Beacon_Halo stays visible out to 1800 m")
	if fire_halo != null:
		var fmat := fire_halo.material_override as ShaderMaterial
		check_near(float(fmat.get_shader_parameter(&"halo_scale")), 1.65, 0.01, "Lantern_Fire_Halo scale == 1.65 m")
	if tavern_halo != null:
		var tmat := tavern_halo.material_override as ShaderMaterial
		check_near(float(tmat.get_shader_parameter(&"halo_scale")), 1.35, 0.01, "Lantern_Tavern_Halo scale == 1.35 m")
		check_near(tavern_halo.visibility_range_end, 280.0, 1.0, "Lantern_Tavern_Halo culls at 280 m")

	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 8.0, 0.3)
	for _i in 8:
		outpost.step_harbour_atmosphere(0.25)
	var day_energy := outpost.get_harbour_halo_energy()
	check(day_energy >= 0.10 and day_energy <= 0.25,
		"Midday harbour halo energy stays subtle (got %.3f)" % day_energy)

	Weather.time_of_day = 23.0
	Weather.set_weather(0.0, 8.0, 0.3)
	for _i in 8:
		outpost.step_harbour_atmosphere(0.25)
	var night_energy := outpost.get_harbour_halo_energy()
	check(night_energy > day_energy * 3.0,
		"Midnight harbour halo energy (%.3f) must exceed 3x midday energy (%.3f)" % [night_energy, day_energy])
	check(night_energy >= 1.00 and night_energy <= 1.35,
		"Midnight harbour halo energy sits in rich atmospheric band [1.00..1.35] (got %.3f)" % night_energy)

	# 2. Dancing campfire flames + swirling ember sparks (zero primitives, >= 30 tris).
	check(outpost.has_campfire_flames(), "Outpost mounts sculpted CampfireFlames cluster")
	var flame_tris := outpost.get_campfire_flame_tri_count()
	check(flame_tris >= 30, "CampfireFlames multi-tongue ArrayMesh has >= 30 tris (got %d)" % flame_tris)
	var flames_mi := outpost.find_child("CampfireFlames", true, false) as MeshInstance3D
	check(flames_mi != null and flames_mi.mesh is ArrayMesh and not (flames_mi.mesh is PrimitiveMesh),
		"CampfireFlames uses zero-primitive ArrayMesh")
	if flames_mi != null:
		check_eq(flames_mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"CampfireFlames disables shadow casting")
	var embers_gp := outpost.find_child("CampfireEmbers", true, false) as GPUParticles3D
	check(embers_gp != null and embers_gp.emitting, "Outpost mounts emitting CampfireEmbers GPUParticles3D")
	if embers_gp != null:
		check(embers_gp.draw_pass_1 is ArrayMesh and not (embers_gp.draw_pass_1 is PrimitiveMesh),
			"CampfireEmbers uses zero-primitive diamond ArrayMesh")

	# 3. Wind-drifting Tavern chimney woodsmoke mounted cleanly at exact chimney flue top!
	check(outpost.has_tavern_chimney_smoke(), "Outpost mounts TavernChimneySmoke on OutpostTavern")
	var smoke_gp := outpost.tavern_node.get_node_or_null(^"TavernChimneySmoke") as GPUParticles3D if outpost.tavern_node != null else null
	check(smoke_gp != null and smoke_gp.emitting, "TavernChimneySmoke is a direct emitting child of OutpostTavern")
	if smoke_gp != null:
		check(smoke_gp.position.distance_to(Outpost.TAVERN_CHIMNEY_FLUE_LOCAL) < 0.02,
			"TavernChimneySmoke sits at exact chimney flue top (3.30, 8.30, 1.85)")
		check(smoke_gp.draw_pass_1 is ArrayMesh and not (smoke_gp.draw_pass_1 is PrimitiveMesh),
			"TavernChimneySmoke uses zero-primitive billboard ArrayMesh card")

	var min_wind_dot := 1.0
	for h_rad: float in [0.0, PI * 0.5, PI]:
		Weather.set_weather(0.0, 11.0, h_rad)
		for _s in 6:
			outpost.step_harbour_atmosphere(0.25)
		var wv := Weather.wind_vector()
		var w_dir := Vector2(wv.x, wv.z).normalized()
		var drift := outpost.get_tavern_chimney_smoke_drift()
		var d_dir := Vector2(drift.x, drift.z).normalized()
		var align := w_dir.dot(d_dir)
		min_wind_dot = minf(min_wind_dot, align)
		check(align > 0.90,
			"TavernChimneySmoke drift aligns with Weather.wind_vector() at heading %.2f (dot=%.3f)" % [h_rad, align])
		if smoke_gp != null and smoke_gp.process_material is ParticleProcessMaterial:
			var pm := smoke_gp.process_material as ParticleProcessMaterial
			check(pm.gravity.distance_to(drift) < 0.05,
				"TavernChimneySmoke ParticleProcessMaterial.gravity tracks cached smoke drift")

	# 4. Expressive Harbour NPC approach greetings (smooth turning, cooldown, bard continuity & depart relaxation).
	var merch := outpost.find_child("MerchantFactorNPC", true, false) as Node3D
	var bard := outpost.tavern_bard_node
	check(merch != null, "Outpost spawns MerchantFactorNPC")
	check(bard != null, "Outpost spawns TavernBardNPC")
	var greet_before := outpost.get_harbour_npc_greeting_count()
	check_eq(greet_before, 0, "No harbour NPC greetings fire before a visitor approaches")

	if merch != null:
		var home_yaw := merch.rotation.y
		var merch_parent := merch.get_parent() as Node3D
		var target_dir_local := Basis(Vector3.UP, home_yaw + 0.72) * Vector3(0.0, 0.0, -3.5)
		var visitor_near := merch_parent.to_global(merch.position + target_dir_local)
		var visitor_far := merch.global_position + Vector3(45.0, 0.0, 45.0)

		outpost.step_harbour_atmosphere(0.20, visitor_near)
		var merch_drv := merch.get_node_or_null(^"AnimationDriver") as AnimationDriver
		check(merch_drv != null and merch_drv.get_current_action() == &"shout",
			"MerchantFactorNPC plays valid welcoming AnimationDriver action (&'shout')")
		for _i in 5:
			outpost.step_harbour_atmosphere(0.25, visitor_near)
		var turned_diff := angle_difference(home_yaw, merch.rotation.y)
		check(turned_diff > 0.35 and absf(turned_diff) <= Outpost.NPC_MAX_TURN_RAD + 0.02,
			"MerchantFactorNPC turns smoothly toward approaching visitor within clamp (delta=%.3f rad)" % turned_diff)
		var greet_after_approach := outpost.get_harbour_npc_greeting_count()
		check(greet_after_approach >= 1,
			"Approaching within 3.5 m triggers warm harbour NPC greeting (count=%d)" % greet_after_approach)

		# Depart briefly (2.0 s) and return within 14 s cooldown: must NOT spam greeting!
		for _i in 4:
			outpost.step_harbour_atmosphere(0.5, visitor_far)
		for _i in 4:
			outpost.step_harbour_atmosphere(0.25, visitor_near)
		check_eq(outpost.get_harbour_npc_greeting_count(), greet_after_approach,
			"Harbour NPC respects 14.0 s cooldown without spamming greetings")

		# Depart far (> 11 m) for 15.0 s: NPC relaxes cleanly back to home_yaw and cooldown expires.
		for _i in 30:
			outpost.step_harbour_atmosphere(0.5, visitor_far)
		var relaxed_err := absf(angle_difference(home_yaw, merch.rotation.y))
		check(relaxed_err < 0.04,
			"MerchantFactorNPC relaxes cleanly back to home_yaw after departure (err=%.4f rad)" % relaxed_err)

		# Re-approaching after 14.0 s cooldown elapsed triggers a fresh greeting!
		outpost.step_harbour_atmosphere(0.25, visitor_near)
		check(outpost.get_harbour_npc_greeting_count() > greet_after_approach,
			"MerchantFactorNPC greets warmly again after 14.0 s cooldown expires")

	if bard != null:
		var bard_drv := bard.get_node_or_null(^"AnimationDriver") as AnimationDriver
		var bard_parent := bard.get_parent() as Node3D
		var bard_home := bard.rotation.y
		var bard_vis := bard_parent.to_global(bard.position + Basis(Vector3.UP, bard_home - 0.65) * Vector3(0.0, 0.0, -3.0))
		for _i in 5:
			outpost.step_harbour_atmosphere(0.25, bard_vis)
		check(absf(angle_difference(bard_home, bard.rotation.y)) > 0.25,
			"TavernBardNPC turns gaze gently toward approaching Captain")
		check(bard_drv != null and bard_drv.get_current_action() == &"play_instrument",
			"TavernBardNPC keeps playing instrument smoothly while greeting Captain")

	# Confirm ZERO raw PrimitiveMeshes anywhere across the upgraded Outpost!
	var raw_prims: Array[String] = []
	for node in outpost.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh:
			raw_prims.append(mi.name)
	check(raw_prims.is_empty(), "Q8A Outpost must have zero raw PrimitiveMeshes (found: %s)" % str(raw_prims))

	print("    q8a harbour atmosphere: halos=%d (day=%.2f -> night=%.2f), flames=%d tris, wind_align>=%.3f, greetings=%d" % [
		halo_count, day_energy, night_energy, flame_tris, min_wind_dot, outpost.get_harbour_npc_greeting_count()])

	# 5. Clean zero-leak teardown releases ALL Q8A static caches!
	outpost.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(flames_mi) and not is_instance_valid(embers_gp) and not is_instance_valid(smoke_gp),
		"Q8A campfire flames, embers & chimney smoke nodes free cleanly with Outpost")
	check(Outpost._outpost_halo_mesh == null and Outpost._outpost_halo_shader == null \
			and Outpost._campfire_flame_mesh == null and Outpost._campfire_flame_shader == null \
			and Outpost._campfire_ember_mesh == null and Outpost._campfire_ember_mat == null \
			and Outpost._chimney_smoke_card_mesh == null and Outpost._chimney_smoke_shader == null \
			and Outpost._chimney_smoke_mat == null,
		"Outpost releases all Q8A static shared meshes, shaders & materials cleanly on teardown")
	Weather.apply_state(saved_weather)


func test_q15b_waterfall_rainbow_fumarole_magma_halo_and_emissary_prestige_motes() -> void:
	_init_host()
	var saved_weather := Weather.get_state()
	Weather.day_length_seconds = 0.0
	Weather.time_of_day = 12.0
	Weather.storminess = 0.0

	var holder := Node3D.new()
	add_child(holder)

	# 1. IslandWaterfall: zero-primitive additive sunlit 7-band prismatic WaterfallMistRainbow arch!
	var wf := IslandWaterfall.create(16.0, 4.2)
	holder.add_child(wf)
	await physics_frames(1)

	var rb := wf.get_mist_rainbow_node()
	check(rb != null and rb.name == "WaterfallMistRainbow",
		"IslandWaterfall mounts WaterfallMistRainbow MeshInstance3D")
	check(rb != null and rb.mesh is ArrayMesh and not (rb.mesh is PrimitiveMesh),
		"WaterfallMistRainbow uses zero-primitive sculpted ArrayMesh")
	var rb_tris := 0
	if rb != null and rb.mesh is ArrayMesh:
		var rb_am := rb.mesh as ArrayMesh
		check_eq(rb.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"WaterfallMistRainbow disables shadow casting")
		check(rb.visibility_range_end >= IslandWaterfall.CULL_DIST + 39.5,
			"WaterfallMistRainbow sets visibility_range_end == CULL_DIST + 40 m")
		var rmat := rb.material_override as StandardMaterial3D
		check(rmat != null and rmat.vertex_color_use_as_albedo and rmat.vertex_color_is_srgb,
			"WaterfallMistRainbow uses sRGB vertex-colored StandardMaterial3D")
		check(rmat != null and rmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				and rmat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
				and rmat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
				and rmat.cull_mode == BaseMaterial3D.CULL_DISABLED
				and rmat.albedo_texture == null,
			"WaterfallMistRainbow uses zero-VRAM unshaded additive double-sided material")
		var rb_bad_n := 0
		var rb_min_lum := 99.0
		var rb_max_lum := 0.0
		for si in rb_am.get_surface_count():
			var arr := rb_am.surface_get_arrays(si)
			var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var norms := arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
			var cols := arr[Mesh.ARRAY_COLOR] as PackedColorArray
			rb_tris += floori(float(verts.size()) / 3.0)
			check_eq(norms.size(), verts.size(), "WaterfallMistRainbow has unit normal per vertex")
			check_eq(cols.size(), verts.size(), "WaterfallMistRainbow has color per vertex")
			for nv: Vector3 in norms:
				if not nv.is_finite() or absf(nv.length() - 1.0) > 0.01:
					rb_bad_n += 1
			for cv: Color in cols:
				var lum := maxf(cv.r, maxf(cv.g, cv.b))
				rb_min_lum = minf(rb_min_lum, lum)
				rb_max_lum = maxf(rb_max_lum, lum)
		check_eq(rb_bad_n, 0, "WaterfallMistRainbow has 100% finite unit normals")
		check(rb_tris >= 140, "WaterfallMistRainbow builds curved 7-band arch geometry (got %d tris)" % rb_tris)
		check(rb_min_lum < 0.001 and rb_max_lum > 0.35,
			"WaterfallMistRainbow feathers cleanly to black rims while preserving spectral core")

	Weather.time_of_day = 12.0
	Weather.storminess = 0.0
	wf.tick_atmosphere()
	var noon_rb := wf.get_mist_rainbow_strength()
	check(rb != null and rb.visible and noon_rb > 0.35,
		"WaterfallMistRainbow shines in sunlit clear noon (strength=%.3f)" % noon_rb)

	Weather.time_of_day = 0.5
	Weather.storminess = 0.0
	wf.tick_atmosphere()
	var night_rb := wf.get_mist_rainbow_strength()
	check(rb != null and not rb.visible and night_rb < 0.02,
		"WaterfallMistRainbow hides cleanly at midnight 0.5h (strength=%.3f)" % night_rb)

	Weather.time_of_day = 12.0
	Weather.storminess = 0.95
	wf.tick_atmosphere()
	var storm_rb := wf.get_mist_rainbow_strength()
	check(rb != null and not rb.visible and storm_rb < 0.02,
		"WaterfallMistRainbow fades cleanly in heavy storm 0.95 (strength=%.3f)" % storm_rb)

	Weather.time_of_day = 12.0
	Weather.storminess = 0.0
	wf.tick_atmosphere()
	check(rb != null and rb.visible and wf.get_mist_rainbow_strength() > 0.35,
		"WaterfallMistRainbow restores in clear noon")
	wf.set_distance_active(false)
	check(rb != null and not rb.visible and is_equal_approx(wf.get_mist_rainbow_strength(), 0.0),
		"WaterfallMistRainbow respects set_distance_active(false)")
	wf.set_distance_active(true)
	check(rb != null and rb.visible and wf.get_mist_rainbow_strength() > 0.35,
		"WaterfallMistRainbow restores on set_distance_active(true)")

	# 2. VolcanicFumarole: zero-primitive 48-tri additive VentMagmaHalo billboard disc!
	Weather.time_of_day = 12.0
	Weather.storminess = 0.0
	var fum := VolcanicFumarole.create(1.15, 0.42)
	holder.add_child(fum)
	await physics_frames(1)

	var halo := fum.get_magma_halo_node()
	check(halo != null and halo.name == "VentMagmaHalo",
		"VolcanicFumarole mounts VentMagmaHalo MeshInstance3D")
	check(halo != null and halo.mesh is ArrayMesh and not (halo.mesh is PrimitiveMesh),
		"VentMagmaHalo uses zero-primitive sculpted ArrayMesh")
	var halo_tris := 0
	if halo != null and halo.mesh is ArrayMesh:
		var halo_am := halo.mesh as ArrayMesh
		check(halo.position.distance_to(Vector3(0.0, 1.32, 0.0)) < 0.01,
			"VentMagmaHalo sits at (0, 1.32, 0) above glowing sulfur throat")
		check_eq(halo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"VentMagmaHalo disables shadow casting")
		check(halo.visibility_range_end >= VolcanicFumarole.CULL_DIST + 39.5,
			"VentMagmaHalo sets visibility_range_end == CULL_DIST + 40 m")
		var hmat := halo.material_override as StandardMaterial3D
		check(hmat != null and hmat.vertex_color_use_as_albedo and hmat.vertex_color_is_srgb
				and hmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				and hmat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
				and hmat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED
				and hmat.billboard_keep_scale
				and hmat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
				and hmat.cull_mode == BaseMaterial3D.CULL_DISABLED
				and hmat.albedo_texture == null,
			"VentMagmaHalo uses zero-VRAM additive unshaded billboard StandardMaterial3D")
		var h_arr := halo_am.surface_get_arrays(0)
		var h_verts := h_arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var h_norms := h_arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
		halo_tris = floori(float(h_verts.size()) / 3.0)
		check_eq(halo_tris, 48, "VentMagmaHalo builds exact 48-tri 16-wedge radial disc")
		var h_bad_n := 0
		for nv: Vector3 in h_norms:
			if not nv.is_finite() or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.005:
				h_bad_n += 1
		check_eq(h_bad_n, 0, "VentMagmaHalo normals are 100% finite (0, 0, 1) unit vectors")

	Weather.time_of_day = 12.0
	fum.step_fumarole(0.05)
	var simmer_day := fum.get_magma_halo_energy()
	check(simmer_day >= 0.30 and simmer_day <= 0.58,
		"VentMagmaHalo simmers gently at midday ~0.42 (got %.3f)" % simmer_day)

	Weather.time_of_day = 0.5
	fum.step_fumarole(0.0)
	var simmer_night := fum.get_magma_halo_energy()
	check(simmer_night > simmer_day * 1.25,
		"VentMagmaHalo brightens warmer at midnight vs midday (%.3f > %.3f)" % [simmer_night, simmer_day])

	Weather.time_of_day = 12.0
	fum.trigger_eruption_pulse()
	var erupt_day := fum.get_magma_halo_energy()
	check(erupt_day > simmer_day * 2.0,
		"VentMagmaHalo surges fiercely during eruption pulse (%.3f > %.3f)" % [erupt_day, simmer_day])

	fum.set_distance_active(false)
	check(halo != null and not halo.visible and is_equal_approx(fum.get_magma_halo_energy(), 0.0),
		"VentMagmaHalo hides cleanly when distance-culled")
	fum.set_distance_active(true)
	check(halo != null and halo.visible and fum.get_magma_halo_energy() > 0.5,
		"VentMagmaHalo restores when back in distance range")

	# 3. ShipEmissaryFlag: zero-primitive 10x8-tri EmissaryGradeMotes MultiMeshInstance3D!
	var sloop := SLOOP_SCENE.instantiate() as Ship
	sloop.enable_effects = false
	sloop.start_anchored = true
	holder.add_child(sloop)
	await physics_frames(2)

	var sflag := ShipEmissaryFlag.mount_to_ship(sloop)
	check(sflag != null, "ShipEmissaryFlag mounts cleanly onto Sloop")
	var motes := sflag.get_grade_motes_node() if sflag != null else null
	check(motes != null and motes.name == "EmissaryGradeMotes",
		"ShipEmissaryFlag mounts EmissaryGradeMotes MultiMeshInstance3D")
	check(motes != null and motes.get_parent() != null and motes.get_parent().name == "EmissaryWindPivot",
		"EmissaryGradeMotes attaches cleanly under EmissaryWindPivot")
	var mote_tris := 0
	var mote_count := 0
	if motes != null:
		check_eq(motes.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"EmissaryGradeMotes disables shadow casting")
		check(motes.visibility_range_end >= 219.5,
			"EmissaryGradeMotes sets visibility_range_end == 220 m")
		var mmat := motes.material_override as StandardMaterial3D
		check(mmat != null and mmat.vertex_color_use_as_albedo and mmat.vertex_color_is_srgb
				and mmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				and mmat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
				and mmat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
				and mmat.cull_mode == BaseMaterial3D.CULL_DISABLED
				and mmat.albedo_texture == null,
			"EmissaryGradeMotes uses zero-VRAM unshaded additive sRGB material")
		var mm := motes.multimesh
		check(mm != null and mm.mesh is ArrayMesh and not (mm.mesh is PrimitiveMesh),
			"EmissaryGradeMotes MultiMesh uses zero-primitive ArrayMesh")
		if mm != null and mm.mesh is ArrayMesh:
			mote_count = mm.instance_count
			check_eq(mote_count, 10, "EmissaryGradeMotes allocates exact 10 prestige mote instances")
			var mam := mm.mesh as ArrayMesh
			var m_arr := mam.surface_get_arrays(0)
			var m_verts := m_arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var m_norms := m_arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
			mote_tris = floori(float(m_verts.size()) / 3.0)
			check_eq(mote_tris, 8, "EmissaryGradeMotes diamond sparkle mesh has exact 8 tris (10x8 = 80)")
			var m_bad_n := 0
			for nv: Vector3 in m_norms:
				if not nv.is_finite() or absf(nv.length() - 1.0) > 0.01:
					m_bad_n += 1
			check_eq(m_bad_n, 0, "EmissaryGradeMotes diamond mesh has 100% finite unit normals")

	# Grades 0..3 stay hidden; Grades 4 & 5 activate prestige sparkle aura!
	for g in range(0, 4):
		sflag.set_emissary(&"gilded_compass", g)
		check(not sflag.is_grade_aura_active() and motes != null and not motes.visible,
			"EmissaryGradeMotes stays hidden at Grade %d" % g)

	sflag.set_emissary(&"gilded_compass", 4)
	check(sflag.is_grade_aura_active() and motes != null and motes.visible,
		"EmissaryGradeMotes activates cleanly at Grade 4")
	var g4_pos0 := sflag.get_grade_mote_positions()[0]
	var g4_cols := sflag.get_grade_mote_colors()
	var g4_lum := 0.0
	for i in mote_count:
		var c := g4_cols[i]
		g4_lum += c.r + c.g + c.b
	sflag.tick_grade_motes(0.25)
	var g4_pos1 := sflag.get_grade_mote_positions()[0]
	check(g4_pos1.distance_to(g4_pos0) > 0.05 and g4_pos1.z > g4_pos0.z,
		"tick_grade_motes(0.25) streams motes smoothly downwind (z=%.3f -> %.3f)" % [g4_pos0.z, g4_pos1.z])

	sflag.set_emissary(&"gilded_compass", 5)
	check(sflag.is_grade_aura_active() and motes != null and motes.visible,
		"EmissaryGradeMotes stays active at Grade 5")
	var g5_cols := sflag.get_grade_mote_colors()
	var g5_lum := 0.0
	for i in mote_count:
		var c := g5_cols[i]
		g5_lum += c.r + c.g + c.b
	check(g5_lum > g4_lum * 1.35,
		"Grade 5 prestige motes shine brighter than Grade 4 (%.2f > %.2f)" % [g5_lum, g4_lum])

	# Verify all 3 Trading Companies switch company aura tints cleanly!
	var company_cols: Dictionary = {}
	var company_mats: Dictionary = {}
	for cid: StringName in [&"gilded_compass", &"sunken_archive", &"iron_tide"]:
		sflag.set_emissary(cid, 5)
		sflag.tick_grade_motes(0.05)
		var mcols := sflag.get_grade_mote_colors()
		var sum_c := Color(0.0, 0.0, 0.0, 1.0)
		for i in mote_count:
			var ic := mcols[i]
			sum_c.r += ic.r
			sum_c.g += ic.g
			sum_c.b += ic.b
		company_cols[cid] = Color(sum_c.r / float(mote_count), sum_c.g / float(mote_count), sum_c.b / float(mote_count), 1.0)
		var smat := motes.material_override as StandardMaterial3D
		if smat != null:
			company_mats[cid] = smat.albedo_color
	var c_gc: Color = company_cols[&"gilded_compass"]
	var c_sa: Color = company_cols[&"sunken_archive"]
	var c_it: Color = company_cols[&"iron_tide"]
	check(c_gc.r > c_gc.b and c_gc.g > c_gc.b,
		"gilded_compass Grade V motes glow warm gold (rgb=%.2f,%.2f,%.2f)" % [c_gc.r, c_gc.g, c_gc.b])
	check(c_sa.g > c_sa.r and c_sa.b > c_sa.r,
		"sunken_archive Grade V motes glow arcane turquoise (rgb=%.2f,%.2f,%.2f)" % [c_sa.r, c_sa.g, c_sa.b])
	check(c_it.r > c_it.g and c_it.r > c_it.b,
		"iron_tide Grade V motes glow blazing crimson-gold (rgb=%.2f,%.2f,%.2f)" % [c_it.r, c_it.g, c_it.b])
	check(company_mats[&"gilded_compass"] != company_mats[&"sunken_archive"]
			and company_mats[&"sunken_archive"] != company_mats[&"iron_tide"],
		"EmissaryGradeMotes material albedo tint switches cleanly across all 3 Trading Companies")

	print("    q15b prestige atmosphere: rainbow=%d tris (noon=%.2f night=%.2f storm=%.2f), magma_halo=%d tris (simmer=%.2f night=%.2f erupt=%.2f), emissary_motes=%dx%d tris" % [
		rb_tris, noon_rb, night_rb, storm_rb, halo_tris, simmer_day, simmer_night, erupt_day, mote_count, mote_tris])

	# 4. Vulkan-clean zero-leak teardown across all three systems!
	holder.queue_free()
	await physics_frames(3)
	check_eq(IslandWaterfall._active_waterfalls, 0, "IslandWaterfall active count returns to 0")
	check(IslandWaterfall._rainbow_mesh == null and IslandWaterfall._rainbow_mat == null,
		"IslandWaterfall releases _rainbow_mesh and _rainbow_mat with 0 leaks")
	check_eq(VolcanicFumarole._active_fumaroles, 0, "VolcanicFumarole active count returns to 0")
	check(VolcanicFumarole._magma_halo_mesh == null,
		"VolcanicFumarole releases _magma_halo_mesh with 0 leaks")
	check_eq(ShipEmissaryFlag._active_instances, 0, "ShipEmissaryFlag active count returns to 0")
	check(ShipEmissaryFlag._mote_mesh == null,
		"ShipEmissaryFlag releases _mote_mesh with 0 leaks")

	Weather.apply_state(saved_weather)
