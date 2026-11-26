extends TestCase
## Headless integration tests for Workstream `island`:
## 17 stylized props, 11 procedural archetypes, 11-island archipelago, Outpost
## dock depth / mooring clearance / shelter / restock, Pawn beach landing walk,
## 3-dig DigSite unearthing, Outpost MerchantStall selling, shore factor & discovery.

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


func _init_host() -> void:
	Net.start_single_player()
	Sea.amp_scale = 0.0
	Sea.time = 0.0


func test_all_17_props_load() -> void:
	check_eq(ALL_PROPS.size(), 17, "expected 17 stylized props")
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


func test_all_11_archetypes_generate() -> void:
	_init_host()
	check_eq(IslandGenerator.ARCHETYPES.size(), 11, "expected 11 island archetypes")
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
		# Verify all col_* helper meshes are hidden visually.
		for c_node in isl.find_children("col_*", "MeshInstance3D", true, false):
			var c_mi := c_node as MeshInstance3D
			check(not c_mi.visible, "col_* mesh still visible on %s: %s" % [arch, c_mi.name])
		isl.queue_free()
	await physics_frames(2)


func test_archipelago_11_islands_no_overlap() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)

	var all_islands := arch.get_islands()
	check_eq(all_islands.size(), 11, "archipelago must contain 11 islands")

	var seen_ids := {}
	var seen_names := {}
	for isl in all_islands:
		check(not seen_ids.has(isl.island_id), "duplicate island_id: " + isl.island_id)
		check(not seen_names.has(isl.display_name), "duplicate display_name: " + isl.display_name)
		seen_ids[isl.island_id] = true
		seen_names[isl.display_name] = true

	var op0 := arch.get_outpost(0)
	var op1 := arch.get_outpost(1)
	var starter := arch.get_starter_treasure_island()
	check(op0 != null and op0.island_id == "port_scoundrel", "outpost 0 must be port_scoundrel")
	check(op1 != null and op1.island_id == "barnacle_haven", "outpost 1 must be barnacle_haven")
	check(starter != null and starter.island_id == "cutlass_cay", "starter treasure island must be cutlass_cay")
	check(starter.get_dig_sites().size() >= 1, "Cutlass Cay should have an active DigSite")

	var dist_starter := op0.global_position.distance_to(starter.global_position)
	check(dist_starter >= 380.0 and dist_starter <= 520.0,
		"Cutlass Cay distance %.1f m should be ~430 m NNE of Port Scoundrel" % dist_starter)

	# Verify zero overlaps and >320 m open sailing channels between every island pair.
	for i in all_islands.size():
		for j in range(i + 1, all_islands.size()):
			var a := all_islands[i]
			var b := all_islands[j]
			var center_dist := Vector2(
				a.global_position.x - b.global_position.x,
				a.global_position.z - b.global_position.z).length()
			var channel := center_dist - a.island_radius - b.island_radius
			check(channel > 320.0,
				"channel between %s and %s too narrow: %.1f m" % [a.island_id, b.island_id, channel])

	# Verify get_map_data() works cleanly with VoyageComposer.
	var map_data := arch.get_map_data()
	check_eq(map_data.size(), 11, "get_map_data should return 11 entries")
	var extracted := VoyageComposer.extract_archipelago_data(arch)
	check_eq(extracted.size(), 11, "VoyageComposer must extract all 11 islands cleanly")

	arch.queue_free()
	await physics_frames(2)


func test_outpost_dock_depth_mooring_and_restock() -> void:
	_init_host()
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(2)

	for idx in [0, 1]:
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


