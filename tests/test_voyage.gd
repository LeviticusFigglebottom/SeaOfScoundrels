extends TestCase
## Headless tests for src/voyage/: TreasureCatalog, Economy, VoyageComposer,
## VoyageManager, and WorldDirector.

const TEMP_PROFILE_PATH := "user://test_voyage_profile.json"


class MockShip:
	extends Node
	var water_level: float = 0.0
	var add_water_calls: int = 0

	func add_water(amount: float) -> void:
		add_water_calls += 1
		water_level = clampf(water_level + amount, 0.0, 1.0)


class MockBailShip:
	extends Node
	var _water: float = 0.0
	var water_level: float:
		get:
			return _water
		set(_v):
			pass

	func bail(amount: float) -> void:
		_water = clampf(_water - amount, 0.0, 1.0)


var _saved_weather: Dictionary = {}


func _save_weather() -> void:
	_saved_weather = Weather.get_state()
	Weather.lightning_enabled = false
	Weather.day_length_seconds = 0.0


func _restore_weather() -> void:
	if _saved_weather.is_empty():
		return
	Weather.set_weather(
		float(_saved_weather["storm"]),
		float(_saved_weather["wind_speed"]),
		float(_saved_weather["wind_heading"]),
		0.0,
		float(_saved_weather["cloudiness"])
	)
	Weather.clear_storm_cell(0.0)
	Weather.set_focus(Vector3.ZERO)
	Weather.apply_state(_saved_weather)
	Weather.lightning_enabled = true


# ---------------------------------------------------------------------------
# 1. Treasure catalogue, cursed/fragile traits, and Carryable creation
# ---------------------------------------------------------------------------

func test_treasure_catalog_and_carryable() -> void:
	var all_ids := TreasureCatalog.get_all_ids()
	check(all_ids.size() >= 10, "expected >= 10 catalogue treasures, got %d" % all_ids.size())

	var cursed_count := 0
	var fragile_count := 0
	var required_keys := [
		"id", "name", "tier", "tier_label", "gold_value", "renown_value",
		"company_id", "mass_kg", "carry_speed_factor", "buoyancy",
		"float_radius", "shape", "tint", "accent_tint", "cursed",
		"curse_flood_rate", "fragile", "description",
	]

	for tid in all_ids:
		check(TreasureCatalog.has_treasure(tid), "has_treasure(%s)" % tid)
		var entry := TreasureCatalog.get_entry(tid)
		for k in required_keys:
			check(entry.has(k), "entry %s missing key '%s'" % [tid, k])
		check_eq(entry["id"], tid, "entry id matches catalogue key")
		check(String(entry["name"]).strip_edges() != "", "entry %s name non-empty" % tid)
		check(String(entry["description"]).strip_edges() != "", "entry %s description non-empty" % tid)
		check(int(entry["tier"]) >= 1 and int(entry["tier"]) <= 5, "entry %s tier in 1..5" % tid)
		check(int(entry["gold_value"]) > 0, "entry %s gold_value positive" % tid)
		check(int(entry["renown_value"]) > 0, "entry %s renown_value positive" % tid)
		check(Economy.COMPANIES.has(entry["company_id"]), "entry %s valid company_id" % tid)
		check(float(entry["mass_kg"]) > 0.0, "entry %s mass_kg positive" % tid)
		check(float(entry["buoyancy"]) > 1.0, "entry %s buoyancy floats (>1.0)" % tid)
		check(float(entry["float_radius"]) > 0.0, "entry %s float_radius positive" % tid)
		var csf := float(entry["carry_speed_factor"])
		check(csf > 0.0 and csf <= 1.0, "entry %s carry_speed_factor in (0, 1]" % tid)
		if bool(entry["cursed"]):
			cursed_count += 1
			check(float(entry["curse_flood_rate"]) > 0.0, "cursed %s has flood rate" % tid)
		if bool(entry["fragile"]):
			fragile_count += 1

	check(cursed_count >= 1, "catalogue includes at least one cursed treasure")
	check(fragile_count >= 1, "catalogue includes at least one fragile treasure")

	# Defensive copy check on get_entry.
	var copy_entry := TreasureCatalog.get_entry(&"driftwood_chest")
	copy_entry["gold_value"] = 999999
	check_eq(int(TreasureCatalog.get_entry(&"driftwood_chest")["gold_value"]), 120,
		"get_entry returns defensive copy")

	# Query helpers: company & tier filters + deterministic pick.
	for comp_id in Economy.COMPANIES.keys():
		check(not TreasureCatalog.get_by_company(comp_id).is_empty(),
			"company %s has catalogue treasures" % comp_id)
	check(not TreasureCatalog.get_by_tier(4, 5).is_empty(), "high-tier treasures exist")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var picked := TreasureCatalog.pick_random_for_tier(rng, 2, 3, &"gilded_compass")
	check(TreasureCatalog.has_treasure(picked), "pick_random_for_tier returns valid id")
	var picked_entry := TreasureCatalog.get_entry(picked)
	check(int(picked_entry["tier"]) >= 2 and int(picked_entry["tier"]) <= 3, "tier within range")
	check_eq(picked_entry["company_id"], &"gilded_compass", "company filter respected")

	# Create Carryables across distinct shapes and inspect metadata + scene setup.
	var sample_ids: Array[StringName] = [
		&"driftwood_chest",
		&"weeping_bilge_chest",
		&"drowned_skull",
		&"archive_chalice",
		&"spice_crate",
		&"ledger_coffer",
	]
	var created: Array[Carryable] = []
	for tid in sample_ids:
		var spawn_pos := Vector3(float(created.size()) * 2.0, 4.0, 0.0)
		var item := TreasureCatalog.create_treasure_carryable(tid, spawn_pos)
		check(item is Carryable, "%s creates a Carryable" % tid)
		check(item.is_in_group(TreasureCatalog.TREASURE_GROUP), "%s in treasure group" % tid)
		check_eq(item.collision_layer, Carryable.LAYER, "%s collision layer 6" % tid)
		check_eq(item.collision_mask, Carryable.MASK, "%s collision mask" % tid)
		check(item.interactable != null, "%s has Interactable handle" % tid)
		check(item.get_node_or_null("CollisionShape") is CollisionShape3D, "%s has CollisionShape3D" % tid)
		check(item.get_node_or_null("Visual") is Node3D, "%s has Visual node" % tid)

		var expected := TreasureCatalog.get_entry(tid)
		var info := TreasureCatalog.inspect_carryable(item)
		check_eq(info["treasure_id"], tid, "%s metadata treasure_id" % tid)
		check_eq(info["name"], expected["name"], "%s metadata name" % tid)
		check_eq(int(info["tier"]), int(expected["tier"]), "%s metadata tier" % tid)
		check_eq(int(info["base_gold_value"]), int(expected["gold_value"]), "%s base_gold_value" % tid)
		check_eq(int(info["gold_value"]), int(expected["gold_value"]), "%s gold_value" % tid)
		check_eq(int(info["renown_value"]), int(expected["renown_value"]), "%s renown_value" % tid)
		check_eq(info["company_id"], expected["company_id"], "%s company_id" % tid)
		check_eq(bool(info["cursed"]), bool(expected["cursed"]), "%s cursed flag" % tid)
		check_eq(bool(info["fragile"]), bool(expected["fragile"]), "%s fragile flag" % tid)
		check_near(float(info["integrity"]), 1.0, 0.001, "%s starts at full integrity" % tid)
		created.append(item)

	# Verify adding a treasure Carryable to the tree keeps a single Interactable.
	var tree_chest := created[0]
	add_child(tree_chest)
	await physics_frames(1)
	var interactable_count := 0
	for child in tree_chest.get_children():
		if child is Interactable:
			interactable_count += 1
	check_eq(interactable_count, 1, "Carryable._ready reuses prebuilt Interactable")

	# Fragile degradation: hard drop, soft drop, floor value, and non-fragile immunity.
	var crate := created[4]  # spice_crate (fragile, base 450g)
	var soft_res := TreasureCatalog.notify_drop_impact(crate, TreasureCatalog.FRAGILE_IMPACT_THRESHOLD - 0.5)
	check(not bool(soft_res["damaged"]), "soft drop does not crack fragile crate")
	check_near(float(crate.get_meta(&"integrity")), 1.0, 0.001, "integrity unchanged on soft drop")

	var hard_res := TreasureCatalog.notify_drop_impact(crate, 8.5)
	check(bool(hard_res["damaged"]), "hard drop cracks fragile crate")
	check(float(hard_res["integrity"]) < 1.0, "integrity decreases after hard drop")
	check(int(hard_res["gold_value"]) < 450, "gold value drops when fragile crate cracks")

	var battered := TreasureCatalog.damage_fragile_carryable(crate, 5.0)
	check_near(float(battered["integrity"]), 0.0, 0.001, "integrity clamps at 0.0")
	var expected_min := TreasureCatalog.compute_effective_value(450, 0.0, true)
	check_eq(int(battered["gold_value"]), expected_min, "battered fragile value hits min fraction floor")
	check(expected_min >= roundi(450.0 * TreasureCatalog.FRAGILE_MIN_VALUE_FRAC) - 1,
		"min fraction retains ~25% value")

	var sturdy := created[0]  # driftwood_chest (not fragile)
	var sturdy_res := TreasureCatalog.damage_fragile_carryable(sturdy, 0.5)
	check(not bool(sturdy_res["damaged"]), "non-fragile chest ignores fragile damage")
	check_eq(int(sturdy.get_meta(&"gold_value")), 120, "non-fragile chest retains full value")

	# Cursed bilge weeping & fragile hold-water submersion via step_aboard_hazards.
	var weeping := created[1]  # weeping_bilge_chest (cursed, flood_rate 0.018/s)
	var fresh_crate := TreasureCatalog.create_treasure_carryable(&"spice_crate")
	var ship := MockShip.new()
	add_child(ship)
	var tick1 := TreasureCatalog.step_aboard_hazards([weeping, fresh_crate], ship, 10.0)
	check_near(float(tick1["flood_added"]), 0.18, 0.001, "cursed chest adds flood_rate * delta")
	check_near(ship.water_level, 0.18, 0.001, "ship hold water increased via add_water")
	check_eq(int(tick1["damaged_count"]), 0, "dry hold (<0.35) does not soak fragile crate")

	# Once hold water rises above 0.35, fragile crate begins soaking.
	ship.water_level = 0.5
	var tick2 := TreasureCatalog.step_aboard_hazards([weeping, fresh_crate], ship, 5.0)
	check_eq(int(tick2["damaged_count"]), 1, "flooded hold (>0.35) degrades fragile crate")
	check(float(fresh_crate.get_meta(&"integrity")) < 1.0, "soaked crate loses integrity")
	check(int(tick2["total_cargo_value"]) > 0, "step_aboard_hazards sums cargo value")

	# Fallback bail(-flood) path for read-only water_level ship API.
	var bail_ship := MockBailShip.new()
	add_child(bail_ship)
	var tick3 := TreasureCatalog.step_aboard_hazards([weeping], bail_ship, 5.0)
	check_near(float(tick3["flood_added"]), 0.09, 0.001, "cursed flood computed on bail fallback ship")
	check_near(bail_ship.water_level, 0.09, 0.001, "read-only water_level falls back to bail(-flood)")

	# Clean up all allocated nodes.
	fresh_crate.free()
	ship.queue_free()
	bail_ship.queue_free()
	for idx in created.size():
		if created[idx].is_inside_tree():
			created[idx].queue_free()
		else:
			created[idx].free()
	await physics_frames(1)


func test_sculpted_treasure_meshes_no_primitives() -> void:
	TreasureCatalog.clear_mesh_cache()

	# 1. Verify EVERY catalogue treasure visual uses valid sculpted ArrayMesh geometry
	#    with ZERO raw primitive meshes (SphereMesh/BoxMesh/CylinderMesh/CapsuleMesh/PrismMesh).
	var all_ids := TreasureCatalog.get_all_ids()
	var seen_shapes: Dictionary = {}
	for tid in all_ids:
		var entry := TreasureCatalog.get_entry(tid)
		var shape_kind: StringName = StringName(entry["shape"])
		seen_shapes[shape_kind] = true
		var item := TreasureCatalog.create_treasure_carryable(tid)
		var visual := item.get_node_or_null(^"Visual") as Node3D
		check(visual != null, "%s builds a Visual Node3D" % tid)

		var mis := _collect_mesh_instances(visual)
		check(not mis.is_empty(), "%s visual contains at least one MeshInstance3D" % tid)
		var total_tris := 0
		for mi in mis:
			var m := mi.mesh
			check(m != null, "%s MeshInstance3D '%s' has non-null mesh" % [tid, mi.name])
			check(m is ArrayMesh, "%s mesh '%s' is sculpted ArrayMesh" % [tid, mi.name])
			check(not (m is PrimitiveMesh), "%s mesh '%s' is not a raw PrimitiveMesh" % [tid, mi.name])
			check(not (m is SphereMesh) and not (m is BoxMesh) and not (m is CylinderMesh),
				"%s mesh '%s' has zero SphereMesh/BoxMesh/CylinderMesh" % [tid, mi.name])
			check(m.get_surface_count() >= 1, "%s mesh '%s' has >= 1 surface" % [tid, mi.name])
			total_tris += _count_mesh_triangles(m)
		check(total_tris >= 200, "%s visual has hero-grade triangle count (%d >= 200)" % [tid, total_tris])

		# Cursed chests must carry a glowing spectral CursedAuraTrim overlay.
		if bool(entry["cursed"]) and (shape_kind == &"chest" or shape_kind == &"coffer"):
			var cursed_trim := visual.get_node_or_null(^"CursedAuraTrim") as MeshInstance3D
			check(cursed_trim != null and cursed_trim.mesh is ArrayMesh,
				"%s attaches glowing CursedAuraTrim ArrayMesh" % tid)
			if cursed_trim != null and cursed_trim.mesh is ArrayMesh:
				var has_emissive := false
				for si in cursed_trim.mesh.get_surface_count():
					var mat := cursed_trim.mesh.surface_get_material(si)
					if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
						has_emissive = true
				check(has_emissive, "%s CursedAuraTrim includes emissive spectral rune material" % tid)

		item.free()

	for expected_shape in [&"skull", &"chalice", &"crate", &"chest", &"coffer"]:
		check(seen_shapes.has(expected_shape), "verified treasure archetype '%s'" % expected_shape)

	# 2. Directly inspect sculpted SurfaceTool ArrayMeshes across all 4 procedural archetypes
	#    (including the sculpted banded pirate chest fallback for normal + cursed chests).
	var archetype_ids: Array[StringName] = [
		&"drowned_skull",
		&"captains_skull",
		&"archive_chalice",
		&"spice_crate",
		&"wayfarer_chest",
		&"weeping_bilge_chest",
		&"ledger_coffer",
	]
	for tid in archetype_ids:
		var entry := TreasureCatalog.get_entry(tid)
		var mesh := TreasureCatalog.build_sculpted_mesh(entry)
		check(mesh is ArrayMesh, "build_sculpted_mesh(%s) returns ArrayMesh" % tid)
		check(mesh.get_surface_count() >= 2,
			"build_sculpted_mesh(%s) has multi-surface materials (%d)" % [tid, mesh.get_surface_count()])
		var tris := _count_mesh_triangles(mesh)
		check(tris >= 600, "build_sculpted_mesh(%s) has rich sculpted detail (%d >= 600 tris)" % [tid, tris])

		# Verify vertex colors, normals, and VERTEX_COLOR_USE_AS_ALBEDO on every surface.
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			var raw_verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			var raw_norms: Variant = arrays[Mesh.ARRAY_NORMAL]
			var raw_cols: Variant = arrays[Mesh.ARRAY_COLOR]
			check(raw_verts is PackedVector3Array and not (raw_verts as PackedVector3Array).is_empty(),
				"%s surface %d has vertices" % [tid, si])
			var vert_count := (raw_verts as PackedVector3Array).size() if raw_verts is PackedVector3Array else 0
			check(raw_norms is PackedVector3Array and (raw_norms as PackedVector3Array).size() == vert_count,
				"%s surface %d has normals per vertex" % [tid, si])
			check(raw_cols is PackedColorArray and (raw_cols as PackedColorArray).size() == vert_count,
				"%s surface %d has vertex colors" % [tid, si])
			var mat := mesh.surface_get_material(si)
			check(mat is StandardMaterial3D and (mat as StandardMaterial3D).vertex_color_use_as_albedo,
				"%s surface %d uses vertex_color_use_as_albedo" % [tid, si])

		# Grounded cleanly at y = 0 with pirate carry proportions (~0.34..0.65 m).
		var aabb := mesh.get_aabb()
		check(aabb.position.y >= -0.015 and aabb.position.y <= 0.025,
			"%s grounded near y=0 (min_y=%.3f)" % [tid, aabb.position.y])
		check(aabb.size.y >= 0.32 and aabb.size.y <= 0.65,
			"%s carry height in 0.32..0.65 m (got %.3f)" % [tid, aabb.size.y])
		if OS.get_cmdline_user_args().has("--treasure-stats"):
			print("    [treasure-sculpt] %-20s shape=%-8s surfs=%d tris=%5d y=[%.3f..%.3f] size=(%.3f,%.3f,%.3f)" % [
				String(tid), String(entry["shape"]), mesh.get_surface_count(), tris,
				aabb.position.y, aabb.end.y, aabb.size.x, aabb.size.y, aabb.size.z])

	if OS.get_cmdline_user_args().has("--treasure-stats"):
		for tid in all_ids:
			var it := TreasureCatalog.create_treasure_carryable(tid)
			var vis_mis := _collect_mesh_instances(it.get_node(^"Visual"))
			var sum_t := 0
			var desc: PackedStringArray = []
			for mi in vis_mis:
				var mt := _count_mesh_triangles(mi.mesh)
				sum_t += mt
				desc.append("%s:%d" % [mi.name, mt])
			print("    [treasure-live]   %-20s nodes=%d total_tris=%5d [%s]" % [
				String(tid), vis_mis.size(), sum_t, ", ".join(desc)])
			it.free()

	# 3. Verify static WeakRef mesh cache shares identical ArrayMesh instances across live spawns.
	var skull_a := TreasureCatalog.create_treasure_carryable(&"drowned_skull")
	var skull_b := TreasureCatalog.create_treasure_carryable(&"drowned_skull")
	var skull_c := TreasureCatalog.create_treasure_carryable(&"captains_skull")
	var mi_a := _collect_mesh_instances(skull_a.get_node(^"Visual"))[0]
	var mi_b := _collect_mesh_instances(skull_b.get_node(^"Visual"))[0]
	var mi_c := _collect_mesh_instances(skull_c.get_node(^"Visual"))[0]
	check(mi_a.mesh == mi_b.mesh, "spawning duplicate drowned_skull shares cached ArrayMesh")
	check(mi_a.mesh != mi_c.mesh, "distinct skull tiers build distinct cached ArrayMeshes")

	var cursed_a := TreasureCatalog.create_treasure_carryable(&"weeping_bilge_chest")
	var cursed_b := TreasureCatalog.create_treasure_carryable(&"weeping_bilge_chest")
	var trim_a := cursed_a.get_node(^"Visual").get_node_or_null(^"CursedAuraTrim") as MeshInstance3D
	var trim_b := cursed_b.get_node(^"Visual").get_node_or_null(^"CursedAuraTrim") as MeshInstance3D
	check(trim_a != null and trim_b != null and trim_a.mesh == trim_b.mesh,
		"cursed chests share cached CursedAuraTrim ArrayMesh")

	skull_a.free()
	skull_b.free()
	skull_c.free()
	cursed_a.free()
	cursed_b.free()
	TreasureCatalog.clear_mesh_cache()


func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node == null:
		return out
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_collect_mesh_instances(child))
	return out


func _count_mesh_triangles(mesh: Mesh) -> int:
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


# ---------------------------------------------------------------------------
# 2. Economy, curved renown progression, sidegrade trade-offs, Profile persistence
# ---------------------------------------------------------------------------

func test_economy_renown_sidegrades_and_profile() -> void:
	# Verify 3 companies and curved polynomial renown table.
	check_eq(Economy.get_companies().size(), 3, "3 trading companies registered")
	check_eq(Economy.rank_threshold(1), 0, "Rank 1 starts at 0 renown")
	check_eq(Economy.rank_threshold(2), 100, "Rank 2 threshold is 100")
	check_eq(Economy.rank_threshold(3), 300, "Rank 3 threshold is 300")
	var prev_delta := 0
	for r in range(2, Economy.MAX_RANK + 1):
		var delta_r := Economy.rank_threshold(r) - Economy.rank_threshold(r - 1)
		check(delta_r > prev_delta, "rank curve is strictly convex at rank %d" % r)
		prev_delta = delta_r
		check(Economy.rank_title(r) != "", "rank %d has a title" % r)
	check_eq(Economy.rank_for_renown(0), 1, "0 renown = Rank 1")
	check_eq(Economy.rank_for_renown(99), 1, "99 renown = Rank 1")
	check_eq(Economy.rank_for_renown(100), 2, "100 renown = Rank 2")
	check_eq(Economy.rank_for_renown(Economy.rank_threshold(Economy.MAX_RANK)), Economy.MAX_RANK,
		"max renown hits MAX_RANK")

	var prof := Profile.new()
	check_eq(Economy.get_company_rank(prof, &"gilded_compass"), 1, "new profile starts Rank 1")

	# Default ship modifiers are all neutral 1.0 baseline.
	var base_mods := Economy.get_ship_modifiers(prof)
	check_near(float(base_mods["speed"]), 1.0, 0.0001, "default speed 1.0")
	check_near(float(base_mods["turn_rate"]), 1.0, 0.0001, "default turn_rate 1.0")
	check_near(float(base_mods["breach_resist"]), 1.0, 0.0001, "default breach_resist 1.0")
	check_near(float(base_mods["downwind"]), 1.0, 0.0001, "default downwind 1.0")
	check_near(float(base_mods["close_hauled"]), 1.0, 0.0001, "default close_hauled 1.0")
	check_near(float(base_mods["breach_radius"]), 1.0, 0.0001, "default breach_radius 1.0")
	check_near(float(base_mods["reload_scale"]), 1.0, 0.0001, "default reload_scale 1.0")

	# Selling treasure awards gold & renown and climbs ranks.
	var sale1 := Economy.sell_treasure(prof, TreasureCatalog.get_entry(&"sovereign_chest"))
	check(bool(sale1["ok"]), "sell sovereign_chest succeeds")
	check_eq(int(sale1["gold_awarded"]), 700, "sovereign_chest awards 700 gold")
	check_eq(int(sale1["renown_awarded"]), 100, "sovereign_chest awards 100 renown")
	check_eq(int(sale1["old_rank"]), 1, "old_rank was 1")
	check_eq(int(sale1["new_rank"]), 2, "100 renown promotes to Rank 2")
	check(bool(sale1["ranked_up"]), "ranked_up flag true")
	check(String(sale1["rank_up_notice"]) != "", "rank_up_notice populated")

	# Sell additional treasures across all three companies to reach Rank 3+.
	for tid in [&"sovereign_chest", &"sovereign_chest", &"corsair_chest"]:
		Economy.sell_treasure(prof, TreasureCatalog.get_entry(tid))
	for _i in 3:
		Economy.sell_treasure(prof, TreasureCatalog.get_entry(&"captains_skull"))
	for _i in 2:
		Economy.sell_treasure(prof, TreasureCatalog.get_entry(&"ledger_coffer"))

	check(Economy.get_company_rank(prof, &"gilded_compass") >= 3, "Gilded Compass climbed to Rank 3+")
	check(Economy.get_company_rank(prof, &"iron_tide") >= 3, "Iron Tide climbed to Rank 3+")
	check(Economy.get_company_rank(prof, &"sunken_archive") >= 2, "Sunken Archive climbed to Rank 2+")
	check_eq(int(prof.data["stats"]["chests_sold"]), 9, "chests_sold stat incremented accurately")

	# Fragile item sold at 50% integrity pays discounted gold.
	var damaged_sale := Economy.sell_treasure(prof, {"treasure_id": &"spice_crate", "integrity": 0.5})
	check(bool(damaged_sale["ok"]), "damaged fragile crate sells")
	var expected_damaged_gold := TreasureCatalog.compute_effective_value(450, 0.5, true)
	check_eq(int(damaged_sale["gold_awarded"]), expected_damaged_gold,
		"damaged fragile sale pays discounted effective gold")

	# Purchase guardrails: rank gate, gold gate, duplicate buy, unowned equip, wrong slot.
	var rookie := Profile.new()
	rookie.add_gold(5000)
	check(not Economy.can_purchase(rookie, &"hull_stout_oak"), "rank-gated unlock blocked at Rank 1")
	var blocked_res := Economy.purchase_unlock(rookie, &"hull_stout_oak")
	check(not bool(blocked_res["ok"]), "purchase_unlock refuses rank-locked fitting")
	check(not Economy.equip_loadout(rookie, &"hull", &"hull_stout_oak"), "cannot equip unowned fitting")

	var broke := Profile.new()
	broke.add_renown("iron_tide", 500)
	check(not Economy.can_purchase(broke, &"hull_stout_oak"), "gold-gated unlock blocked when broke")

	# Purchase & equip every sidegrade archetype and verify real mechanical trade-offs.
	var sidegrades: Array[StringName] = [
		&"hull_stout_oak",
		&"hull_swift_cedar",
		&"sail_broad_canvas",
		&"sail_close_hauled",
		&"cannon_heavy_shot",
		&"cannon_quick_swivel",
		&"trait_steady_hands",
		&"flag_crimson_gull",
		&"sail_sunburst",
	]
	for uid in sidegrades:
		var gold_before := int(prof.data["gold"])
		var cost := int(Economy.get_unlock(uid)["cost"])
		var buy := Economy.purchase_unlock(prof, uid)
		check(bool(buy["ok"]), "purchase %s succeeded (reason: %s)" % [uid, buy.get("reason", "")])
		check_eq(int(prof.data["gold"]), gold_before - cost, "gold deducted for %s" % uid)
		check(Economy.is_unlocked(prof, uid), "%s is now unlocked" % uid)

	# Cannot repurchase an owned unlock.
	var dup_buy := Economy.purchase_unlock(prof, &"hull_stout_oak")
	check(not bool(dup_buy["ok"]), "cannot purchase already-owned unlock")
	# Wrong slot equip fails.
	check(not Economy.equip_loadout(prof, &"sail", &"hull_stout_oak"),
		"equipping hull into sail slot is rejected")

	# Trade-off check 1: Stout Oak Hull (+breach_resist, -speed, -turn_rate).
	check(Economy.equip_loadout(prof, &"hull", &"hull_stout_oak"), "equip hull_stout_oak")
	var mods_stout := Economy.get_ship_modifiers(prof)
	check(float(mods_stout["breach_resist"]) > 1.0, "stout hull improves breach_resist")
	check(float(mods_stout["speed"]) < 1.0, "stout hull trades away top speed")
	check(float(mods_stout["turn_rate"]) < 1.0, "stout hull trades away turn_rate")

	# Trade-off check 2: Swift Cedar Hull (+speed, +turn_rate, -breach_resist).
	check(Economy.equip_loadout(prof, &"hull", &"hull_swift_cedar"), "equip hull_swift_cedar")
	var mods_swift := Economy.get_ship_modifiers(prof)
	check(float(mods_swift["speed"]) > 1.0 and float(mods_swift["turn_rate"]) > 1.0,
		"swift hull boosts speed & turn_rate")
	check(float(mods_swift["breach_resist"]) < 1.0, "swift hull trades away breach_resist")

	# Trade-off check 3: Broad Storm-Canvas vs Split-Gaff Close-Hauler.
	check(Economy.equip_loadout(prof, &"sail", &"sail_broad_canvas"), "equip sail_broad_canvas")
	var mods_broad := Economy.get_ship_modifiers(prof)
	check(float(mods_broad["downwind"]) > 1.0 and float(mods_broad["close_hauled"]) < 1.0,
		"broad canvas gains downwind, loses close-hauled")

	check(Economy.equip_loadout(prof, &"sail", &"sail_close_hauled"), "equip sail_close_hauled")
	var mods_close := Economy.get_ship_modifiers(prof)
	check(float(mods_close["close_hauled"]) > 1.0 and float(mods_close["downwind"]) < 1.0,
		"close-hauler gains close-hauled, loses downwind")

	# Trade-off check 4: Heavy Culverins vs Quick-Breech Swivels.
	check(Economy.equip_loadout(prof, &"cannon", &"cannon_heavy_shot"), "equip cannon_heavy_shot")
	var mods_heavy := Economy.get_ship_modifiers(prof)
	check(float(mods_heavy["breach_radius"]) > 1.0 and float(mods_heavy["reload_scale"]) > 1.0,
		"heavy culverins widen breach at slower reload")

	check(Economy.equip_loadout(prof, &"cannon", &"cannon_quick_swivel"), "equip cannon_quick_swivel")
	var mods_quick := Economy.get_ship_modifiers(prof)
	check(float(mods_quick["reload_scale"]) < 1.0 and float(mods_quick["breach_radius"]) < 1.0,
		"quick swivels reload faster with smaller breach")

	# Crew trait stacks cleanly & cosmetics leave numeric stats untouched.
	check(Economy.equip_loadout(prof, &"trait", &"trait_steady_hands"), "equip trait_steady_hands")
	check(Economy.equip_loadout(prof, &"flag", &"flag_crimson_gull"), "equip flag_crimson_gull")
	check(Economy.equip_loadout(prof, &"sail_cosmetic", &"sail_sunburst"), "equip sail_sunburst")
	var mods_final := Economy.get_ship_modifiers(prof)
	check_near(float(mods_final["speed"]), 1.12, 0.0001, "final speed from swift cedar")
	check_near(float(mods_final["close_hauled"]), 1.22, 0.0001, "final close_hauled from close-hauler")
	check_near(float(mods_final["reload_scale"]), 0.75 * 0.80, 0.0001,
		"cannon & steady_hands reload_scale stack multiplicatively")
	check_near(float(mods_final["patch_scale"]), 1.25, 0.0001, "steady_hands patch_scale applied")
	check_eq(mods_final["flag_id"], &"flag_crimson_gull", "flag cosmetic tracked in modifiers")
	check_eq(mods_final["sail_cosmetic_id"], &"sail_sunburst", "sail cosmetic tracked in modifiers")

	# Persist through Profile save/load round-trip and verify full fidelity.
	check_eq(prof.save(TEMP_PROFILE_PATH), OK, "Profile.save succeeds")
	var loaded := Profile.new()
	check(loaded.load_from(TEMP_PROFILE_PATH), "Profile.load_from succeeds")
	check_eq(int(loaded.data["gold"]), int(prof.data["gold"]), "gold survives save/load")
	for comp_id in Economy.COMPANIES.keys():
		check_eq(
			Economy.get_company_renown(loaded, comp_id),
			Economy.get_company_renown(prof, comp_id),
			"renown for %s survives save/load" % comp_id
		)
		check_eq(
			Economy.get_company_rank(loaded, comp_id),
			Economy.get_company_rank(prof, comp_id),
			"rank for %s survives save/load" % comp_id
		)
	for uid in sidegrades:
		check(Economy.is_unlocked(loaded, uid), "unlock %s survives save/load" % uid)
	for slot in Economy.DEFAULT_LOADOUT.keys():
		check_eq(
			Economy.get_equipped(loaded, slot),
			Economy.get_equipped(prof, slot),
			"equipped %s survives save/load" % slot
		)
	var loaded_mods := Economy.get_ship_modifiers(loaded)
	for stat_key in ["speed", "turn_rate", "downwind", "close_hauled", "breach_resist",
			"breach_radius", "reload_scale", "patch_scale"]:
		check_near(float(loaded_mods[stat_key]), float(mods_final[stat_key]), 0.0001,
			"modifier %s matches after Profile save/load" % stat_key)

	# Clearing an optional slot restores default &"" and clearing hull restores hull_standard.
	check(Economy.equip_loadout(loaded, &"trait", &""), "clear optional trait slot")
	check_eq(Economy.get_equipped(loaded, &"trait"), &"", "cleared trait returns empty")
	check(Economy.equip_loadout(loaded, &"hull", &""), "clear hull slot restores default")
	check_eq(Economy.get_equipped(loaded, &"hull"), &"hull_standard", "cleared hull falls back to standard")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PROFILE_PATH))


# ---------------------------------------------------------------------------
# 3. VoyageComposer 60-voyage variety simulation & Story Chapters 1..3
# ---------------------------------------------------------------------------

func test_voyage_composer_variety_simulation() -> void:
	var roster := VoyageComposer.default_archipelago_roster()
	check_eq(roster.size(), 11, "simulated archipelago has 11 islands")

	var composer := VoyageComposer.new(0x5C00D2E1)
	var shape_counts: Dictionary = {}
	var island_counts: Dictionary = {}
	var prev_shape := &""
	var prev_island := &""
	var generated_shapes: Array[StringName] = []
	var generated_islands: Array[StringName] = []

	for i in 60:
		var diff := 1 + (i % 5)
		var v := composer.compose_voyage(roster, diff, &"", &"", &"port_scoundrel")
		var shape: StringName = v.get("shape", &"")
		var target_id: StringName = v.get("target_island_id", &"")

		check(VoyageComposer.SHAPES.has(shape), "voyage %d has valid shape '%s'" % [i, shape])
		check(target_id != &"", "voyage %d has non-empty target island" % i)
		check(target_id != &"port_scoundrel", "voyage %d does not target origin outpost" % i)
		check(String(v.get("title", "")) != "", "voyage %d has title" % i)
		check(Economy.COMPANIES.has(v.get("company_id", &"")), "voyage %d has valid company" % i)

		# Modular 4-part structure: Hook, Site, Complication, Payoff + stages.
		var hook: Dictionary = v.get("hook", {})
		var site: Dictionary = v.get("site", {})
		var comp: Dictionary = v.get("complication", {})
		var payoff: Dictionary = v.get("payoff", {})
		var stages: Array = v.get("stages", [])
		check(not hook.is_empty() and String(hook.get("briefing", "")) != "", "voyage %d has hook" % i)
		check(not site.is_empty() and site.get("island_id", &"") == target_id, "voyage %d site matches target" % i)
		check(not comp.is_empty() and String(comp.get("description", "")) != "", "voyage %d has complication" % i)
		check(int(payoff.get("estimated_gold", 0)) > 0, "voyage %d estimated_gold > 0" % i)
		check(int(payoff.get("estimated_renown", 0)) > 0, "voyage %d estimated_renown > 0" % i)
		var treasures: Array = payoff.get("treasures", [])
		check(not treasures.is_empty(), "voyage %d has payoff treasures" % i)
		for tid in treasures:
			check(TreasureCatalog.has_treasure(tid), "voyage %d treasure '%s' exists in catalog" % [i, tid])
		check(stages.size() >= 3, "voyage %d has >= 3 stages" % i)

		if i > 0:
			check(shape != prev_shape,
				"no consecutive shape repeat at index %d (got %s twice)" % [i, shape])
			check(target_id != prev_island,
				"no consecutive island repeat at index %d (got %s twice)" % [i, target_id])

		shape_counts[shape] = int(shape_counts.get(shape, 0)) + 1
		island_counts[target_id] = int(island_counts.get(target_id, 0)) + 1
		generated_shapes.append(shape)
		generated_islands.append(target_id)
		prev_shape = shape
		prev_island = target_id

	# All 7 voyage shapes must appear across 60 voyages.
	check_eq(VoyageComposer.SHAPES.size(), 7, "7 canonical voyage shapes defined")
	for s in VoyageComposer.SHAPES:
		check(int(shape_counts.get(s, 0)) > 0,
			"voyage shape '%s' appeared at least once in 60 voyages" % s)
	check(island_counts.size() >= 8,
		"voyages spread widely across archipelago (%d distinct islands)" % island_counts.size())

	# Deterministic seeding reproduces identical sequence.
	var replay := VoyageComposer.new(0x5C00D2E1)
	for i in 10:
		var rv := replay.compose_voyage(roster, 1 + (i % 5), &"", &"", &"port_scoundrel")
		check_eq(rv["shape"], generated_shapes[i], "seeded replay matches shape at %d" % i)
		check_eq(rv["target_island_id"], generated_islands[i], "seeded replay matches target at %d" % i)

	# Outpost board offer generation covers all 3 companies cleanly.
	var offers := replay.generate_board_offers(roster, 3, {"gilded_compass": 4, "iron_tide": 2})
	check_eq(offers.size(), 3, "generate_board_offers returns 3 contracts")
	var offer_companies: Array[StringName] = []
	for o in offers:
		offer_companies.append(o["company_id"])
	check(offer_companies.has(&"gilded_compass"), "offers include Gilded Compass")
	check(offer_companies.has(&"iron_tide"), "offers include Iron Tide")
	check(offer_companies.has(&"sunken_archive"), "offers include Sunken Archive")

	# Authored Story Chapters 1..3 load cleanly with escalating arcs.
	var expected_targets: Array[StringName] = [&"cutlass_cay", &"coral_spire", &"ironwatch_fort"]
	var expected_shapes: Array[StringName] = [&"buried_hoard", &"riddle_trail", &"fort_siege"]
	var seen_story_ids: Dictionary = {}
	var prev_diff := 0
	for ch in range(1, VoyageComposer.STORY_CHAPTER_COUNT + 1):
		var story := composer.get_story_voyage(ch, roster)
		check(bool(story.get("is_story", false)), "chapter %d is_story true" % ch)
		check_eq(int(story.get("story_chapter", 0)), ch, "chapter %d story_chapter matches" % ch)
		check(String(story.get("title", "")) != "", "chapter %d has title" % ch)
		check(not seen_story_ids.has(story["id"]), "chapter %d has unique id" % ch)
		seen_story_ids[story["id"]] = true
		check_eq(story["target_island_id"], expected_targets[ch - 1], "chapter %d target island" % ch)
		check_eq(story["shape"], expected_shapes[ch - 1], "chapter %d shape" % ch)
		check(int(story["difficulty"]) > prev_diff, "chapter %d difficulty escalates" % ch)
		prev_diff = int(story["difficulty"])
		var stages: Array = story.get("stages", [])
		check(stages.size() >= 4, "chapter %d has multi-beat stage list" % ch)
		var payoff: Dictionary = story.get("payoff", {})
		for tid in payoff.get("treasures", []):
			check(TreasureCatalog.has_treasure(tid), "chapter %d treasure '%s' valid" % [ch, tid])


func test_story_campaign_live_archipelago_alignment() -> void:
	var composer := VoyageComposer.new(0x7B5702)

	# Live 11-island Archipelago roster: Chapter 2 leads into Smuggler's Cove Grotto,
	# Chapter 3 targets Ironwatch Fort with fort_siege + ghost_ship ambush.
	var arch := Archipelago.new()
	add_child(arch)
	await physics_frames(1)
	var live_map := arch.get_map_data()
	check_eq(live_map.size(), 11, "live Archipelago exposes 11 islands")

	var live_ch1 := composer.get_story_voyage(1, live_map)
	check_eq(live_ch1["target_island_id"], &"cutlass_cay", "live Chapter 1 targets cutlass_cay")
	check_eq(live_ch1["shape"], &"buried_hoard", "live Chapter 1 shape is buried_hoard")

	var live_ch2 := composer.get_story_voyage(2, live_map)
	check(bool(live_ch2.get("is_story", false)), "live Chapter 2 is_story true")
	check_eq(int(live_ch2.get("story_chapter", 0)), 2, "live Chapter 2 chapter index == 2")
	check_eq(live_ch2["target_island_id"], &"smugglers_cove", "live Chapter 2 resolves smugglers_cove")
	check_eq(String(live_ch2["target_island_name"]), "Smuggler's Cove", "live Chapter 2 targets Smuggler's Cove")
	check_eq(live_ch2["shape"], &"riddle_trail", "live Chapter 2 shape is riddle_trail")
	var live_ch2_site: Dictionary = live_ch2.get("site", {})
	check_eq(live_ch2_site.get("island_id", &""), &"smugglers_cove", "live Chapter 2 site matches smugglers_cove")

	var live_ch3 := composer.get_story_voyage(3, live_map)
	check(bool(live_ch3.get("is_story", false)), "live Chapter 3 is_story true")
	check_eq(int(live_ch3.get("story_chapter", 0)), 3, "live Chapter 3 chapter index == 3")
	check_eq(live_ch3["target_island_id"], &"ironwatch_fort", "live Chapter 3 resolves ironwatch_fort")
	check_eq(live_ch3["shape"], &"fort_siege", "live Chapter 3 shape is fort_siege")
	var live_ch3_comp: Dictionary = live_ch3.get("complication", {})
	check_eq(live_ch3_comp.get("threat_archetype", &""), &"ghost_ship",
		"live Chapter 3 complication threat_archetype is ghost_ship")

	# Backward compatibility: default_archipelago_roster() keeps coral_spire for Chapter 2.
	var default_roster := VoyageComposer.default_archipelago_roster()
	var def_ch2 := composer.get_story_voyage(2, default_roster)
	check_eq(def_ch2["target_island_id"], &"coral_spire",
		"default_archipelago_roster() Chapter 2 preserves coral_spire")
	var def_ch3 := composer.get_story_voyage(3, default_roster)
	check_eq(def_ch3["target_island_id"], &"ironwatch_fort",
		"default_archipelago_roster() Chapter 3 preserves ironwatch_fort")
	check_eq(def_ch3["shape"], &"fort_siege",
		"default_archipelago_roster() Chapter 3 shape is fort_siege")
	check_eq((def_ch3.get("complication", {}) as Dictionary).get("threat_archetype", &""), &"ghost_ship",
		"default_archipelago_roster() Chapter 3 threat_archetype is ghost_ship")

	# Custom minimal roster lacking coral_spire & smugglers_cove falls back to first landmark.
	var custom_roster: Array[Dictionary] = [
		{"id": &"port_scoundrel", "name": "Port Scoundrel", "kind": &"outpost", "position": Vector3.ZERO, "landmarks": ["Pier"]},
		{"id": &"cutlass_cay", "name": "Cutlass Cay", "kind": &"treasure_island", "position": Vector3(200, 0, -200), "landmarks": ["Palm"]},
		{"id": &"emerald_spire", "name": "Emerald Spire", "kind": &"landmark", "position": Vector3(-500, 0, 100), "landmarks": ["Needles", "Saddle", "East Cove"]},
	]
	var fallback_ch2 := composer.get_story_voyage(2, custom_roster)
	check_eq(fallback_ch2["target_island_id"], &"emerald_spire",
		"Chapter 2 falls back to first landmark when coral_spire and smugglers_cove absent")

	arch.queue_free()
	await physics_frames(2)


func test_fort_siege_reef_treasures_and_shanty_showcase() -> void:
	_save_weather()
	var saved_amp := Sea.amp_scale
	var saved_profile := Game.profile.data.duplicate(true)
	Net.start_single_player()

	# 1. Verify live Main scene spawns sunken underwater coral reef dive treasures & Fort Siege activation.
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_node := main_packed.instantiate() as Node3D
	add_child(main_node)
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	await physics_frames(4)

	var entities := main_node.get_node_or_null(^"Entities")
	check(entities != null, "Main Entities root exists")
	var atoll_loot := entities.get_node_or_null(^"SunkenReefTreasure_crescent_atoll") as Carryable
	var shoal_loot := entities.get_node_or_null(^"SunkenReefTreasure_wreckers_shoal") as Carryable
	check(atoll_loot != null, "Crescent Atoll sunken reef treasure spawned")
	check(shoal_loot != null, "Wrecker's Shoal sunken reef treasure spawned")
	if atoll_loot != null and shoal_loot != null:
		check(atoll_loot.global_position.y <= -2.30 and atoll_loot.global_position.y >= -4.90,
			"Crescent Atoll loot seated on shallow seabed (y=%.2f)" % atoll_loot.global_position.y)
		check(shoal_loot.global_position.y <= -2.30 and shoal_loot.global_position.y >= -4.90,
			"Wrecker's Shoal loot seated on shallow seabed (y=%.2f)" % shoal_loot.global_position.y)
		check(atoll_loot.freeze and shoal_loot.freeze, "sunken reef treasures stay seated until picked up")
		check_eq(shoal_loot.get_meta(&"treasure_id"), &"wayfarer_chest", "Wrecker's Shoal sunken treasure is wayfarer_chest")
		check(TreasureCatalog.has_treasure(atoll_loot.get_meta(&"treasure_id")),
			"Crescent Atoll sunken treasure uses valid catalog id")
		var atoll_bubbles := atoll_loot.get_node_or_null(^"ReefBubbleColumn") as GPUParticles3D
		var shoal_bubbles := shoal_loot.get_node_or_null(^"ReefBubbleColumn") as GPUParticles3D
		check(atoll_bubbles != null and atoll_bubbles.emitting, "Crescent Atoll sunken loot emits bubble column")
		check(shoal_bubbles != null and shoal_bubbles.emitting, "Wrecker's Shoal sunken loot emits bubble column")

		# Picking up sunken loot stops & frees the bubble column and unfreezes on drop.
		var player: Pawn = main_node.get(&"player_pawn") as Pawn
		check(player.pick_up(atoll_loot), "player can pick up sunken reef treasure")
		await physics_frames(2)
		check(not is_instance_valid(atoll_bubbles), "bubble column frees cleanly after pickup")
		player.drop_carried(0.0)
		check(not atoll_loot.freeze, "dropped reef treasure restores buoyancy")

	# Activate Story Chapter 3 (Fort Siege) -> verifies Ironwatch Fort Bastion & 4 batteries + vault chest.
	var arch: Archipelago = main_node.get(&"archipelago") as Archipelago
	var vm: VoyageManager = main_node.get(&"voyage_manager") as VoyageManager
	var fort := arch.get_island_by_id("ironwatch_fort")
	var bastion := fort.get_node_or_null(^"FortBastion") as Node3D
	check(bastion != null and not bool(bastion.get(&"is_siege_beacon_active")),
		"Ironwatch Fort bastion starts calm before siege")
	var ch3 := vm.start_story_voyage(3, arch.get_map_data())
	await physics_frames(2)
	check_eq(ch3.get("shape", &""), &"fort_siege", "Story Chapter 3 starts as fort_siege")
	check(bool(bastion.get(&"is_siege_beacon_active")), "FortBastion Signal Brazier activates for Fort Siege voyage")
	var bats: Array = bastion.call(&"get_batteries")
	check_eq(bats.size(), 4, "Ironwatch Fort has 4 coastal batteries")
	for bat in bats:
		check(bool(bat.get(&"siege_active")), "FortBattery activated for Fort Siege voyage")
	var found_vault := false
	for child in entities.get_children():
		if child is Carryable and child.get_meta(&"treasure_id", &"") == &"sovereign_chest":
			if (child as Node3D).global_position.distance_to(bastion.global_position) < 2.0:
				found_vault = true
				break
	check(found_vault, "Fort Siege voyage places Sovereign's Strongbox on bastion terrace")

	Audio.stop_shanty(0.01)
	Audio.stop_music(0.01)
	main_node.queue_free()
	await physics_frames(3)

	# 2. Verify crew_showcase shot=shanty equips all 3 crew instruments on solid main deck at sunset.
	var crew_packed := load("res://scenes/showcase/crew_showcase.tscn") as PackedScene
	var crew_node := crew_packed.instantiate() as Node3D
	crew_node.set(&"_shot", "shanty")
	add_child(crew_node)
	await physics_frames(12)
	check_near(Weather.time_of_day, 17.65, 0.01, "shanty showcase sets golden sunset time_of_day = 17.65")
	var brains := crew_node.find_children("*", "CrewBrain", true, false)
	check_eq(brains.size(), 3, "shanty showcase spawns all 3 AI crewmates")
	var seen_instruments: Array[String] = []
	for b_node in brains:
		var cb := b_node as CrewBrain
		check_eq(cb.current_task, &"shanty", "%s enters shanty task" % cb.crew_name())
		var loc := cb.pawn.platform_local_position()
		check(loc.y >= 1.0 and loc.y <= 1.35,
			"%s stands solidly on main deck (y=%.2f)" % [cb.crew_name(), loc.y])
		var inst := cb.get_held_shanty_instrument()
		check(inst != null, "%s holds sculpted 3D shanty instrument" % cb.crew_name())
		if inst != null:
			seen_instruments.append(inst.name)
	check(seen_instruments.has("ShantyInstrument_hurdy_gurdy"), "Barnaby holds hurdy-gurdy")
	check(seen_instruments.has("ShantyInstrument_whistle"), "Maren holds bosun whistle")
	check(seen_instruments.has("ShantyInstrument_instrument"), "Pip holds concertina")

	Audio.stop_shanty(0.01)
	crew_node.queue_free()
	await physics_frames(3)
	Sea.amp_scale = saved_amp
	Game.profile.data = saved_profile
	_restore_weather()


# ---------------------------------------------------------------------------
# 4. VoyageManager vertical-slice starter flow
# ---------------------------------------------------------------------------

func test_voyage_manager_vertical_slice_flow() -> void:
	var roster := VoyageComposer.default_archipelago_roster()
	var vm := VoyageManager.new()
	var prof := Profile.new()
	vm.profile = prof
	vm.post_notices = true
	add_child(vm)

	var started_events: Array[Dictionary] = []
	var stage_events: Array[Dictionary] = []
	var completed_events: Array[Dictionary] = []
	var failed_events: Array[Dictionary] = []
	var offers_events: Array = []
	var notices: Array[String] = []

	var on_notice := func(text: String) -> void:
		notices.append(text)
	Game.notice.connect(on_notice)

	vm.voyage_started.connect(func(v: Dictionary) -> void:
		started_events.append(v)
	)
	vm.voyage_stage_changed.connect(func(idx: int, obj: String) -> void:
		stage_events.append({"index": idx, "objective": obj})
	)
	vm.voyage_completed.connect(func(v: Dictionary, s: Dictionary) -> void:
		completed_events.append({"voyage": v, "summary": s})
	)
	vm.voyage_failed.connect(func(v: Dictionary, reason: String) -> void:
		failed_events.append({"voyage": v, "reason": reason})
	)
	vm.available_voyages_changed.connect(func(list: Array[Dictionary]) -> void:
		offers_events.append(list)
	)

	# Outpost board offers populate cleanly.
	var offers := vm.refresh_offers(roster, 3, &"port_scoundrel")
	check_eq(offers.size(), 3, "refresh_offers generates 3 board offers")
	check_eq(offers_events.size(), 1, "available_voyages_changed emitted")

	# Step 1: Start starter Story Voyage ("The Salt-King's Ledger").
	var starter := vm.start_starter_voyage(roster)
	check(vm.has_active_voyage(), "starter voyage is active")
	check_eq(String(starter["title"]), "The Salt-King's Ledger", "starter title matches Chapter 1")
	check_eq(vm.current_stage_index, 0, "starts at stage 0 (sail_to)")
	check_eq(vm.get_current_stage()["kind"], &"sail_to", "stage 0 kind is sail_to")
	check(not vm.is_hauling_home(), "not hauling home before boarding treasure")
	check_eq(started_events.size(), 1, "voyage_started fired")
	check_eq(stage_events.size(), 1, "initial voyage_stage_changed fired")

	# Unrelated island arrival charts discovery without advancing target stage.
	vm.notify_island_arrived(&"gull_roost")
	check(prof.data["discoveries"].has("gull_roost"), "unrelated island charted in profile")
	check_eq(vm.current_stage_index, 0, "wrong island does not advance sail_to stage")

	# Step 2: Arrive at target island (Cutlass Cay).
	vm.notify_island_arrived(&"cutlass_cay")
	check(prof.data["discoveries"].has("cutlass_cay"), "Cutlass Cay discovered in profile")
	check_eq(vm.current_stage_index, 1, "island arrival advances to stage 1 (dig_treasure)")
	check_eq(vm.get_current_stage()["kind"], &"dig_treasure", "stage 1 kind is dig_treasure")

	# Step 3: Unearth the Salt-King's Ledger Coffer.
	var chest := TreasureCatalog.create_treasure_carryable(&"ledger_coffer")
	vm.notify_treasure_unearthed(chest)
	check_eq(vm.current_stage_index, 2, "unearthing chest advances to stage 2 (board_treasure)")
	check_eq(vm.get_current_stage()["kind"], &"board_treasure", "stage 2 kind is board_treasure")

	# Step 4: Board the chest onto the sloop.
	vm.notify_treasure_boarded(chest)
	check(vm.is_hauling_home(), "is_hauling_home becomes true once treasure is aboard")
	check_eq(vm.current_stage_index, 3, "boarding chest advances to stage 3 (sell_treasure)")
	check_eq(vm.get_current_stage()["kind"], &"sell_treasure", "stage 3 kind is sell_treasure")

	# Replication snapshot mid-voyage round-trips cleanly.
	var snap := vm.get_state()
	var mirror := VoyageManager.new()
	mirror.apply_state(snap)
	check_eq(mirror.current_stage_index, 3, "replicated stage index matches")
	check(mirror.is_hauling_home(), "replicated hauling_home matches")
	mirror.free()

	# Step 5: Sell the Ledger Coffer at Port Scoundrel -> completes voyage!
	vm.tick(45.0)
	var sale := vm.notify_treasure_sold(chest)
	check(bool(sale["ok"]), "notify_treasure_sold succeeded")
	check_eq(int(sale["gold_awarded"]), 950, "Ledger Coffer sold for 950 gold")
	check_eq(int(sale["renown_awarded"]), 140, "Ledger Coffer awarded 140 renown")

	check(not vm.has_active_voyage(), "voyage cleared after completion")
	check_eq(vm.current_stage_index, -1, "stage index resets to -1 on completion")
	check(not vm.is_hauling_home(), "hauling_home resets on completion")
	check_eq(vm.completed_count, 1, "completed_count incremented to 1")
	check_eq(completed_events.size(), 1, "voyage_completed emitted once")

	var summary: Dictionary = completed_events[0]["summary"]
	check_eq(int(summary["story_chapter"]), 1, "summary records story chapter 1")
	check_eq(int(summary["bonus_gold"]), 250, "summary includes 250 bonus gold")
	check_eq(int(summary["bonus_renown"]), 60, "summary includes 60 bonus renown")
	check_eq(int(summary["total_gold_earned"]), 1200, "total_gold_earned = 950 + 250")
	check_eq(int(summary["total_renown_earned"]), 200, "total_renown_earned = 140 + 60")
	check_eq(int(summary["chests_sold"]), 1, "summary chests_sold == 1")
	check(bool(summary["on_time"]), "starter voyage completed on time")
	check_eq(int(prof.data["gold"]), 1200, "profile holds 1200 gold total")
	check_eq(Economy.get_company_renown(prof, &"sunken_archive"), 200, "Sunken Archive renown == 200")
	check_eq(Economy.get_company_rank(prof, &"sunken_archive"), 2, "Sunken Archive promoted to Rank 2")
	check_eq(int(prof.data["stats"]["voyages_completed"]), 1, "profile voyages_completed == 1")
	check(notices.size() >= 5, "diegetic notices posted across voyage milestones")

	# Verify multi-step riddle progression & timed charter deadline failure.
	vm.start_story_voyage(2, roster)
	vm.notify_island_arrived(&"coral_spire")
	check_eq(vm.get_current_stage()["kind"], &"solve_riddle", "Chapter 2 reaches solve_riddle")
	vm.notify_clue_solved(0)
	check_eq(vm.stage_progress, 1, "clue 1 increments stage_progress")
	vm.notify_clue_solved(1)
	check_eq(vm.stage_progress, 2, "clue 2 increments stage_progress")
	vm.notify_clue_solved(2)
	check_eq(vm.get_current_stage()["kind"], &"dig_treasure", "clue 3 advances solve_riddle -> dig_treasure")
	vm.abandon_voyage("Test cancel.")
	check_eq(failed_events.size(), 1, "abandon_voyage emits voyage_failed")
	check(not vm.has_active_voyage(), "active_voyage cleared after abandon")

	var cargo_voy := vm.composer.compose_voyage(roster, 1, &"gilded_compass", &"cargo_run", &"port_scoundrel")
	var limit: float = float(cargo_voy["complication"]["time_limit_sec"])
	vm.start_voyage(cargo_voy)
	vm.tick(limit * 1.1)
	check(vm.has_active_voyage(), "slightly overdue cargo charter warns before failing")
	vm.tick(limit * 0.5)
	check(not vm.has_active_voyage(), "expired timed cargo charter auto-fails")
	check_eq(failed_events.size(), 2, "deadline expiration emitted voyage_failed")

	Game.notice.disconnect(on_notice)
	chest.free()
	vm.queue_free()
	await physics_frames(1)


# ---------------------------------------------------------------------------
# 5. WorldDirector 30-min pacing, cargo risk, warnings >= 250 m, Weather storm,
#    and 60% shipwreck salvage recovery
# ---------------------------------------------------------------------------

func test_world_director_pacing_cargo_risk_and_salvage() -> void:
	_save_weather()

	# Part A: Simulate 30 minutes (1800 s) of calm vs high-cargo sailing.
	var calm_stats := _simulate_sailing_session(0x701A01, 0, 0, 1800.0)
	var rich_stats := _simulate_sailing_session(0x701A01, 1400, 2, 1800.0)

	check(int(calm_stats["total_events"]) >= 12,
		"calm 30-min sail produces regular sightings (got %d)" % int(calm_stats["total_events"]))
	check(int(calm_stats["flotsam"]) >= 6,
		"calm 30-min sail has steady flotsam encounters (got %d)" % int(calm_stats["flotsam"]))
	check(int(calm_stats["major_events"]) >= 5,
		"calm 30-min sail has regular major events (got %d)" % int(calm_stats["major_events"]))
	check(float(calm_stats["max_drought"]) <= WorldDirector.MAX_DROUGHT_SECONDS + 2.0,
		"calm max drought %.1f s <= MAX_DROUGHT_SECONDS" % float(calm_stats["max_drought"]))

	check(int(rich_stats["total_events"]) >= 15,
		"high-cargo 30-min sail produces regular sightings (got %d)" % int(rich_stats["total_events"]))
	check(int(rich_stats["major_events"]) > int(calm_stats["major_events"]),
		"high cargo compresses major event pacing (%d vs %d)" % [
			int(rich_stats["major_events"]), int(calm_stats["major_events"])])
	check(int(rich_stats["rivals"]) > int(calm_stats["rivals"]),
		"high cargo raises rival intercept count (%d vs %d)" % [
			int(rich_stats["rivals"]), int(calm_stats["rivals"])])

	var calm_rival_rate := float(calm_stats["rivals"]) / maxf(1.0, float(calm_stats["major_events"]))
	var rich_rival_rate := float(rich_stats["rivals"]) / maxf(1.0, float(rich_stats["major_events"]))
	check(rich_rival_rate > calm_rival_rate,
		"high cargo raises rival share of major events (%.2f vs %.2f)" % [rich_rival_rate, calm_rival_rate])

	# Every major threat warning across both 30-min simulations must be >= 250 m.
	check(float(calm_stats["min_major_warning_dist"]) >= 250.0,
		"calm major warnings >= 250 m (min %.1f m)" % float(calm_stats["min_major_warning_dist"]))
	check(float(rich_stats["min_major_warning_dist"]) >= 250.0,
		"high-cargo major warnings >= 250 m (min %.1f m)" % float(rich_stats["min_major_warning_dist"]))
	check(bool(calm_stats["all_bearings_valid"]) and bool(rich_stats["all_bearings_valid"]),
		"all sighting warnings include valid compass bearings")
	check_near(float(calm_stats["sailing_distance"]), 1800.0 * 8.0, 20.0,
		"sailing_distance tracks distance travelled")

	# Part B: Safe harbor suppresses hostile spawns; deep swimming triggers shark pack.
	var dir := WorldDirector.new(0x5A1E22)
	dir.post_notices = false
	dir.weather_integration = true
	add_child(dir)

	var harbor_events := 0
	var outposts := [Vector3(0.0, 0.0, 0.0)]
	for _s in 240:
		var evts := dir.step(1.0, {
			"ship_pos": Vector3(60.0, 0.0, -40.0),
			"ship_velocity": Vector3(0.0, 0.0, -6.0),
			"outpost_positions": outposts,
			"cargo_value": 1500,
		})
		harbor_events += evts.size()
	check_eq(harbor_events, 0, "safe harbor suppresses world events")

	var shark_spawns: Array[Dictionary] = []
	dir.spawn_shark_pack.connect(func(center: Vector3, count: int) -> void:
		shark_spawns.append({"center": center, "count": count})
	)
	for _s in 16:
		dir.step(1.0, {
			"ship_pos": Vector3(800.0, 0.0, -800.0),
			"ship_velocity": Vector3.ZERO,
			"pawn_swimming_deep": true,
			"swimmer_pos": Vector3(810.0, 0.0, -810.0),
			"outpost_positions": outposts,
		})
	check_eq(shark_spawns.size(), 1, "prolonged deep swimming spawns a shark pack")

	# Part C: Storm cell uses Weather.set_storm_cell() and cleans up on expiry.
	Weather.clear_storm_cell(0.0)
	check_near(Weather.storm_intensity, 0.0, 0.001, "Weather storm cell cleared before trigger")
	var storm_signals: Array[Dictionary] = []
	dir.spawn_storm_cell.connect(func(center: Vector3, radius: float, vel: Vector3) -> void:
		storm_signals.append({"center": center, "radius": radius, "velocity": vel})
	)
	var storm_evt := dir.trigger_event(&"storm_cell", {
		"ship_pos": Vector3(1200.0, 0.0, -1200.0),
		"ship_forward": Vector3(0.0, 0.0, -1.0),
	})
	check(not storm_evt.is_empty(), "trigger_event(storm_cell) returns event")
	check_eq(storm_signals.size(), 1, "spawn_storm_cell signal emitted")
	check(float(storm_evt["distance"]) >= 250.0, "storm cell sighting >= 250 m")

	var scenter: Vector3 = storm_signals[0]["center"]
	var sradius: float = float(storm_signals[0]["radius"])
	var svel: Vector3 = storm_signals[0]["velocity"]
	check(Weather.storm_intensity >= 0.8, "Weather.set_storm_cell sets storm_intensity >= 0.8")
	check_near(Weather.storm_center.x, scenter.x, 0.05, "Weather.storm_center.x matches")
	check_near(Weather.storm_center.z, scenter.z, 0.05, "Weather.storm_center.z matches")
	check_near(Weather.storm_radius, sradius, 0.05, "Weather.storm_radius matches")
	check_near(Weather.storm_velocity.x, svel.x, 0.05, "Weather.storm_velocity.x matches")
	check_near(Weather.storm_velocity.z, svel.z, 0.05, "Weather.storm_velocity.z matches")
	check(Weather.local_storminess(scenter) >= 0.8, "local_storminess elevated inside storm cell")

	# Aging past storm cell duration (210 s) calls Weather.clear_storm_cell.
	dir.step(220.0, {
		"ship_pos": Vector3(1200.0, 0.0, -1200.0),
		"in_safe_harbor": true,
	})
	Weather.advance(20.0)
	check_near(Weather.storm_intensity, 0.0, 0.001, "expired storm cell clears Weather storm cell")

	# Part D: record_ship_wreck() preserves ~60% salvageable cargo and outpost restore transform.
	var recorded_wrecks: Array[Dictionary] = []
	var salvaged_events: Array[Dictionary] = []
	dir.wreck_recorded.connect(func(w: Dictionary) -> void:
		recorded_wrecks.append(w)
	)
	dir.wreck_salvaged.connect(func(wid: String, items: Array) -> void:
		salvaged_events.append({"id": wid, "items": items})
	)
	dir.set_last_outpost(&"rumrunners_haven", Vector3(1180.0, 0.0, -340.0))
	dir.cargo_value_aboard = 1840

	var multi_cargo := [
		TreasureCatalog.get_entry(&"sovereign_chest"),   # 700
		TreasureCatalog.get_entry(&"corsair_chest"),     # 420
		TreasureCatalog.get_entry(&"drowned_skull"),     # 360
		TreasureCatalog.get_entry(&"wayfarer_chest"),    # 240
		TreasureCatalog.get_entry(&"driftwood_chest"),   # 120 -> total 1840
	]
	var wreck := dir.record_ship_wreck(Vector3(350.0, 0.0, -900.0), multi_cargo)
	check_eq(recorded_wrecks.size(), 1, "wreck_recorded emitted")
	check_eq(int(wreck["total_lost_value"]), 1840, "total_lost_value sums all cargo")
	check_near(float(wreck["salvage_ratio"]), 0.60, 0.08,
		"multi-item wreck preserves ~60%% cargo value (got %.3f)" % float(wreck["salvage_ratio"]))
	check(not (wreck["items"] as Array).is_empty(), "wreck preserves salvageable items")
	check_eq(dir.cargo_value_aboard, 0, "cargo_value_aboard cleared on sinking")
	check_eq(wreck["restore_outpost_id"], &"rumrunners_haven", "restore outpost matches last visited")
	var restore_tf: Transform3D = wreck["restore_transform"]
	check_near(restore_tf.origin.x, 1180.0, 0.1, "restore x aligns with outpost")
	check_near(restore_tf.origin.z, -368.0, 0.1, "restore z offset clear of wharf")
	check_eq(dir.get_active_wrecks().size(), 1, "active wreck tracked before claim")

	var recovered := dir.claim_wreck_salvage(String(wreck["id"]))
	check_eq(recovered.size(), (wreck["items"] as Array).size(), "claim_wreck_salvage returns preserved items")
	check_eq(salvaged_events.size(), 1, "wreck_salvaged emitted")
	check_eq(dir.get_active_wrecks().size(), 0, "claimed wreck no longer active")
	check(dir.claim_wreck_salvage(String(wreck["id"])).is_empty(), "wreck cannot be double-claimed")

	# Single-item wreck and skewed 2-item wreck both preserve ~60% value.
	var single_wreck := dir.record_ship_wreck(Vector3(400.0, 0.0, -600.0),
		[TreasureCatalog.get_entry(&"sovereign_chest")])
	check_near(float(single_wreck["salvage_ratio"]), 0.60, 0.02,
		"single-item wreck preserves 60%% value")
	var skewed_wreck := dir.record_ship_wreck(Vector3(450.0, 0.0, -620.0), [
		TreasureCatalog.get_entry(&"weeping_bilge_chest"),  # 1100
		TreasureCatalog.get_entry(&"driftwood_chest"),      # 120 -> total 1220
	])
	check_near(float(skewed_wreck["salvage_ratio"]), 0.60, 0.02,
		"skewed 2-item wreck discounts cleanly to 60%% value")

	dir.queue_free()
	await physics_frames(1)
	_restore_weather()


func _simulate_sailing_session(seed_value: int, cargo_value: int,
		voyage_count: int, duration_sec: float) -> Dictionary:
	var dir := WorldDirector.new(seed_value)
	dir.post_notices = false
	dir.weather_integration = false
	dir.voyage_count = voyage_count

	var totals := {
		"total_events": 0,
		"major_events": 0,
		"rivals": 0,
		"ghosts": 0,
		"storms": 0,
		"flotsam": 0,
		"min_major_warning_dist": 999999.0,
		"all_bearings_valid": true,
		"max_drought": 0.0,
		"sailing_distance": 0.0,
	}

	dir.sighting_warning.connect(func(msg: String, _pos: Vector3, kind: StringName,
			bearing: String, dist: float) -> void:
		if msg == "" or not WorldDirector.COMPASS_POINTS.has(bearing):
			totals["all_bearings_valid"] = false
		if kind == &"rival_ship" or kind == &"ghost_ship" or kind == &"storm_cell":
			totals["min_major_warning_dist"] = minf(float(totals["min_major_warning_dist"]), dist)
	)
	dir.spawn_rival_ship.connect(func(_pos: Vector3, _arch: StringName, _ship: Node) -> void:
		totals["rivals"] = int(totals["rivals"]) + 1
		totals["major_events"] = int(totals["major_events"]) + 1
	)
	dir.spawn_ghost_ship.connect(func(_pos: Vector3) -> void:
		totals["ghosts"] = int(totals["ghosts"]) + 1
		totals["major_events"] = int(totals["major_events"]) + 1
	)
	dir.spawn_storm_cell.connect(func(_c: Vector3, _r: float, _v: Vector3) -> void:
		totals["storms"] = int(totals["storms"]) + 1
		totals["major_events"] = int(totals["major_events"]) + 1
	)
	dir.spawn_flotsam_barrels.connect(func(_pos: Vector3, _count: int) -> void:
		totals["flotsam"] = int(totals["flotsam"]) + 1
	)

	var dt := 1.0
	var steps := int(duration_sec / dt)
	var pos := Vector3(500.0, 0.0, -500.0)
	var vel := Vector3(0.0, 0.0, -8.0)
	var drought := 0.0

	for _i in steps:
		pos += vel * dt
		var evts := dir.step(dt, {
			"ship_pos": pos,
			"ship_velocity": vel,
			"ship_forward": Vector3(0.0, 0.0, -1.0),
			"cargo_value": cargo_value,
			"in_safe_harbor": false,
		})
		if evts.is_empty():
			drought += dt
			totals["max_drought"] = maxf(float(totals["max_drought"]), drought)
		else:
			drought = 0.0
			totals["total_events"] = int(totals["total_events"]) + evts.size()

	totals["sailing_distance"] = dir.sailing_distance
	dir.free()
	return totals


func test_fort_vault_sculpted_gate_locking_swing_and_teardown() -> void:
	Net.start_single_player()
	var vault_gd: GDScript = preload("res://src/world/fort_vault.gd")
	var vault: Node3D = vault_gd.new() as Node3D
	add_child(vault)

	# 1. Verify sculpted zero-primitive ArrayMesh frame + double gates + golden treasury glow light.
	var frame_mi := vault.get_node_or_null(^"VaultArchFrame") as MeshInstance3D
	var left_piv := vault.get_node_or_null(^"LeftGatePivot") as Node3D
	var right_piv := vault.get_node_or_null(^"RightGatePivot") as Node3D
	var left_mi := vault.get_node_or_null(^"LeftGatePivot/LeftGateMesh") as MeshInstance3D
	var right_mi := vault.get_node_or_null(^"RightGatePivot/RightGateMesh") as MeshInstance3D
	var glow := vault.get_node_or_null(^"VaultTreasuryGlow") as OmniLight3D

	check(frame_mi != null and frame_mi.mesh is ArrayMesh, "FortVault builds sculpted ArrayMesh stone arch frame")
	check(left_mi != null and left_mi.mesh is ArrayMesh, "FortVault builds sculpted LeftGateMesh ArrayMesh")
	check(right_mi != null and right_mi.mesh is ArrayMesh, "FortVault builds sculpted RightGateMesh ArrayMesh")
	check(glow != null and not glow.shadow_enabled and glow.omni_range >= 9.0, "FortVault has shadowless golden VaultTreasuryGlow OmniLight3D")

	var total_tris := 0
	var primitive_hits := 0
	for mi in _collect_mesh_instances(vault):
		if mi.mesh != null:
			var m := mi.mesh
			if m is BoxMesh or m is CylinderMesh or m is CapsuleMesh or m is SphereMesh or m is PrismMesh:
				primitive_hits += 1
			total_tris += _count_mesh_triangles(m)
	check_eq(primitive_hits, 0, "FortVault contains zero raw primitive meshes")
	check(total_tris >= 3000, "FortVault has rich sculpted flat-faceted geometry (%d tris)" % total_tris)

	# 2. Verify locked state blocks passage & set_siege_cleared(true) updates interactable prompt.
	check_eq(bool(vault.get(&"is_locked")), true, "FortVault starts locked")
	check_eq(bool(vault.get(&"is_open")), false, "FortVault starts closed")
	check(bool(vault.call(&"is_blocking")), "FortVault StaticBody3D blocks passage while locked")
	var it := vault.get(&"interactable") as Interactable
	check(it != null and it.prompt == "Unlock Ironwatch Fort Vault", "locked FortVault interactable prompt matches")

	vault.call(&"set_siege_cleared", true)
	check_eq(bool(vault.get(&"is_locked")), false, "set_siege_cleared(true) clears lock flag")
	check_eq(it.prompt, "Open Ironwatch Fort Vault", "unlocked FortVault prompt updates to Open")
	check(bool(vault.call(&"is_blocking")), "FortVault still blocks until open_vault() runs")

	# 3. Verify open_vault() disables collision, emits vault_opened exactly once, and swings gates ±108°.
	var opened_count := [0]
	vault.connect(&"vault_opened", func(_v: Node, _opener: Node) -> void: opened_count[0] += 1)
	check(bool(vault.call(&"open_vault")), "open_vault() returns true on first call")
	check(not bool(vault.call(&"open_vault")), "second open_vault() is a no-op")
	check_eq(opened_count[0], 1, "vault_opened emits exactly once")
	check_eq(bool(vault.get(&"is_open")), true, "FortVault marked open")
	check(not bool(vault.call(&"is_blocking")), "FortVault collision blocker disabled immediately on open_vault()")

	# Step full 1.35 s smooth opening curve.
	for _i in 30:
		vault.call(&"step_animation", 0.05)
	check_near(left_piv.rotation.y, -deg_to_rad(108.0), 0.02, "LeftGatePivot swings smoothly inward to -108 deg")
	check_near(right_piv.rotation.y, deg_to_rad(108.0), 0.02, "RightGatePivot swings smoothly inward to +108 deg")

	# 4. Zero-leak teardown.
	vault.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(vault), "FortVault freed cleanly with zero leaks")


func test_fort_vault_siege_battery_unlock_flow_and_main_zero_primitives() -> void:
	Net.start_single_player()
	var holder := Node3D.new()
	add_child(holder)

	var vault_gd: GDScript = preload("res://src/world/fort_vault.gd")
	var vault := vault_gd.new() as Node3D
	vault.name = "FortVault"
	holder.add_child(vault)

	var bat_a := FortBattery.new()
	bat_a.enable_effects = false
	bat_a.siege_active = true
	holder.add_child(bat_a)

	var bat_b := FortBattery.new()
	bat_b.enable_effects = false
	bat_b.siege_active = true
	holder.add_child(bat_b)

	var batteries: Array[FortBattery] = [bat_a, bat_b]
	var sync_unlock := func(_b: FortBattery) -> void:
		for bat in batteries:
			if not bat.destroyed:
				return
		vault.call(&"set_siege_cleared", true)
		vault.call(&"open_vault")
	bat_a.battery_destroyed.connect(sync_unlock)
	bat_b.battery_destroyed.connect(sync_unlock)
	vault.call(&"set_siege_cleared", false)

	check(bool(vault.get(&"is_locked")) and bool(vault.call(&"is_blocking")),
		"FortVault remains locked and blocking while coastal batteries survive")

	# Destroying only 1 of 2 batteries must keep the vault sealed.
	bat_a.take_damage(200.0)
	check(bat_a.destroyed, "first FortBattery destroyed cleanly")
	check(bool(vault.get(&"is_locked")) and not bool(vault.get(&"is_open")),
		"vault stays locked until ALL coastal batteries are silenced")

	# Destroying the final battery unlocks and opens the vault automatically.
	bat_b.take_damage(200.0)
	check(bat_b.destroyed, "second FortBattery destroyed cleanly")
	check(not bool(vault.get(&"is_locked")) and bool(vault.get(&"is_open")),
		"silencing all coastal batteries unlocks and opens FortVault")
	check(not bool(vault.call(&"is_blocking")), "opened FortVault clears gate collision blocker")

	holder.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(holder), "siege vault test nodes tear down cleanly")

	# Verify scenes/main.gd contains zero raw primitive meshes and exposes Wave 13D–16D showcase shots & FlotsamCluster wiring.
	var main_src := FileAccess.get_file_as_string("res://scenes/main.gd")
	check(main_src.length() > 1000, "loaded scenes/main.gd source cleanly")
	for prim: String in ["BoxMesh.new", "SphereMesh.new", "CylinderMesh.new", "CapsuleMesh.new", "PrismMesh.new"]:
		check(not main_src.contains(prim), "scenes/main.gd must contain zero raw %s placeholders" % prim)
	check(main_src.contains("\"company_fleet\":"), "scenes/main.gd registers shot=company_fleet")
	check(main_src.contains("\"fort_vault\":"), "scenes/main.gd registers shot=fort_vault")
	check(main_src.contains("\"dolphins\":"), "scenes/main.gd registers shot=dolphins")
	check(main_src.contains("\"night_sail\":"), "scenes/main.gd registers shot=night_sail")
	check(main_src.contains("\"cabin\":"), "scenes/main.gd registers shot=cabin")
	check(main_src.contains("\"flotsam\":"), "scenes/main.gd registers shot=flotsam")
	check(main_src.contains("\"deck_duel\":"), "scenes/main.gd registers shot=deck_duel")
	check(main_src.contains("\"night_lighthouse\":"), "scenes/main.gd registers shot=night_lighthouse")
	check(main_src.contains("\"whale_breach\":"), "scenes/main.gd registers shot=whale_breach")
	check(not main_src.contains(".set_livery("), "scenes/main.gd uses CharacterVisual.set_tint (zero nonexistent set_livery calls)")
	check(main_src.contains("b_cv.set_tint("), "shot=deck_duel tints Barnaby via CharacterVisual.set_tint")
	check(main_src.contains("sync_cabin_renown"), "scenes/main.gd wires live sync_cabin_renown updates")
	check(main_src.contains("flotsam_cluster.gd") and main_src.contains("flotsam_salvaged"),
		"scenes/main.gd wires FlotsamCluster & flotsam_salvaged rewards cleanly")
	var nameplate_src := FileAccess.get_file_as_string("res://src/ship/ship_nameplate.gd")
	check(nameplate_src.contains("EMISSION_OP_MULTIPLY"),
		"ship_nameplate.gd uses EMISSION_OP_MULTIPLY so dark mahogany stays rich at night")

	# Verify tightened ShipBellInteractable reach (<= 1.8 m) & Ship.set_ship_name() API with zero leaks.
	var sloop_scene := preload("res://src/ship/sloop.tscn")
	var test_ship := sloop_scene.instantiate() as Ship
	test_ship.enable_effects = false
	add_child(test_ship)
	await get_tree().process_frame
	check(test_ship.ship_bell_interactable != null and test_ship.ship_bell_interactable.reach <= 1.8,
		"ShipBellInteractable reach tightened <= 1.8 m (got %.2f)" % (
			test_ship.ship_bell_interactable.reach if test_ship.ship_bell_interactable != null else -1.0))
	test_ship.set_ship_name("The Crimson Cutlass")
	check_eq(test_ship.ship_name, "The Crimson Cutlass", "Ship.set_ship_name() updates ship_name cleanly")
	test_ship.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func test_cargo_hazard_vfx_and_zero_primitive_doubloons_digsite() -> void:
	Net.start_single_player()
	var holder := Node3D.new()
	holder.name = "Wave22BTestHolder"
	add_child(holder)

	# 1. Cursed Weeping Bilge Chest spawns WeepingDrips GPUParticles3D with WeakRef-cached sculpted teardrop ArrayMesh.
	var weep_a := TreasureCatalog.create_treasure_carryable(&"weeping_bilge_chest", Vector3(0.0, 0.0, 0.0))
	var weep_b := TreasureCatalog.create_treasure_carryable(&"weeping_bilge_chest", Vector3(2.0, 0.0, 0.0))
	holder.add_child(weep_a)
	holder.add_child(weep_b)
	var drips_a := weep_a.get_node(^"Visual").get_node_or_null(^"WeepingDrips") as GPUParticles3D
	var drips_b := weep_b.get_node(^"Visual").get_node_or_null(^"WeepingDrips") as GPUParticles3D
	check(drips_a != null and drips_a.emitting, "weeping_bilge_chest spawns emitting WeepingDrips GPUParticles3D")
	check_eq(drips_a.amount, 10, "WeepingDrips spawns 10 glowing beads")
	check_eq(drips_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "WeepingDrips disables shadows")
	check(drips_a.draw_pass_1 is ArrayMesh and not (drips_a.draw_pass_1 is PrimitiveMesh),
		"WeepingDrips uses sculpted teardrop ArrayMesh (zero PrimitiveMesh)")
	check_eq(drips_a.draw_pass_1, drips_b.draw_pass_1, "WeepingDrips shares WeakRef-cached teardrop ArrayMesh")
	var drop_tris := _count_mesh_triangles(drips_a.draw_pass_1)
	check(drop_tris >= 24, "sculpted teardrop bead has faceted volume (%d tris)" % drop_tris)

	# Non-cursed chests must NOT spawn WeepingDrips.
	var plain := TreasureCatalog.create_treasure_carryable(&"wayfarer_chest", Vector3(4.0, 0.0, 0.0))
	holder.add_child(plain)
	check(plain.get_node(^"Visual").get_node_or_null(^"WeepingDrips") == null,
		"non-cursed chest does not spawn WeepingDrips")

	# 2. Fragile cargo visual distress activates below 0.85 integrity via apply_fragile_damage() / sync_fragile_visual().
	var fragile := TreasureCatalog.create_treasure_carryable(&"spice_crate", Vector3(6.0, 0.0, 0.0))
	holder.add_child(fragile)
	check(fragile.get_node(^"Visual").get_node_or_null(^"FragileDistress") == null,
		"intact fragile crate has no distress motes at 100% integrity")
	var d_small := TreasureCatalog.apply_fragile_damage(fragile, 0.08)  # 0.92 >= 0.85
	check(bool(d_small.get("damaged", false)) and not bool(fragile.get_meta(&"distress_active", false)),
		"fragile cargo stays calm above 0.85 integrity")
	var d_heavy := TreasureCatalog.apply_fragile_damage(fragile, 0.30)  # 0.62 < 0.85
	check(bool(d_heavy.get("damaged", false)) and bool(fragile.get_meta(&"distress_active", false)),
		"apply_fragile_damage() below 0.85 triggers fragile distress state")
	var distress := fragile.get_node(^"Visual").get_node_or_null(^"FragileDistress") as GPUParticles3D
	check(distress != null and distress.emitting and distress.visible,
		"FragileDistress amber warning GPUParticles3D activates cleanly")
	check(distress.draw_pass_1 is ArrayMesh and not (distress.draw_pass_1 is PrimitiveMesh),
		"FragileDistress uses sculpted diamond ArrayMesh (zero PrimitiveMesh)")
	var distress_tris := _count_mesh_triangles(distress.draw_pass_1)
	check(distress_tris >= 16, "sculpted amber distress mote has faceted diamond form (%d tris)" % distress_tris)

	# 3. MerchantStall uses statically cached sculpted Octagonal Embossed Spanish Doubloon ArrayMesh (zero CylinderMesh).
	var stall_a := MerchantStall.new()
	var stall_b := MerchantStall.new()
	holder.add_child(stall_a)
	holder.add_child(stall_b)
	var coin_p_a := stall_a.get_node_or_null(^"GoldCoinBurst") as CPUParticles3D
	var coin_p_b := stall_b.get_node_or_null(^"GoldCoinBurst") as CPUParticles3D
	check(coin_p_a != null and coin_p_a.mesh is ArrayMesh and not (coin_p_a.mesh is PrimitiveMesh),
		"MerchantStall GoldCoinBurst uses sculpted octagonal doubloon ArrayMesh (zero CylinderMesh)")
	check_eq(coin_p_a.mesh, coin_p_b.mesh, "MerchantStalls share statically cached doubloon ArrayMesh")
	var coin_mat := coin_p_a.material_override as StandardMaterial3D
	check(coin_mat != null and coin_mat.vertex_color_use_as_albedo and coin_mat.vertex_color_is_srgb,
		"MerchantStall doubloon uses sRGB vertex-colored gold PBR material")
	var doubloon_tris := _count_mesh_triangles(coin_p_a.mesh)
	check(doubloon_tris >= 80, "Octagonal Embossed Spanish Doubloon has chamfered rim & crown boss (%d tris)" % doubloon_tris)

	# 4. DigSite uses statically cached sculpted Earth Clods & 4-Point Diamond Gold Sparkles (zero BoxMesh).
	var site_a := DigSite.new()
	var site_b := DigSite.new()
	holder.add_child(site_a)
	holder.add_child(site_b)
	var dirt_a := site_a.get_node_or_null(^"DirtPuffParticles") as CPUParticles3D
	var dirt_b := site_b.get_node_or_null(^"DirtPuffParticles") as CPUParticles3D
	var gold_a := site_a.get_node_or_null(^"TreasureGlintParticles") as CPUParticles3D
	var gold_b := site_b.get_node_or_null(^"TreasureGlintParticles") as CPUParticles3D
	check(dirt_a != null and dirt_a.mesh is ArrayMesh and not (dirt_a.mesh is PrimitiveMesh),
		"DigSite DirtPuffParticles uses sculpted Earth Clod ArrayMesh (zero BoxMesh)")
	check(gold_a != null and gold_a.mesh is ArrayMesh and not (gold_a.mesh is PrimitiveMesh),
		"DigSite TreasureGlintParticles uses sculpted 4-Point Diamond Gold Sparkle ArrayMesh (zero BoxMesh)")
	check_eq(dirt_a.mesh, dirt_b.mesh, "DigSites share statically cached earth clod ArrayMesh")
	check_eq(gold_a.mesh, gold_b.mesh, "DigSites share statically cached gold sparkle ArrayMesh")
	var clod_mat := dirt_a.material_override as StandardMaterial3D
	var spark_mat := gold_a.material_override as StandardMaterial3D
	check(clod_mat != null and clod_mat.vertex_color_is_srgb, "DigSite clod uses sRGB vertex color material")
	check(spark_mat != null and spark_mat.vertex_color_is_srgb, "DigSite sparkle uses sRGB vertex color material")
	var clod_tris := _count_mesh_triangles(dirt_a.mesh)
	var spark_tris := _count_mesh_triangles(gold_a.mesh)
	check(clod_tris >= 24 and spark_tris >= 16,
		"DigSite sculpted particle tris (clod=%d, sparkle=%d)" % [clod_tris, spark_tris])
	print("    Wave 22B sculpted particle meshes: WeepingDroplet=%d, FragileMote=%d, SpanishDoubloon=%d, EarthClod=%d, GoldSparkle=%d tris" % [
		drop_tris, distress_tris, doubloon_tris, clod_tris, spark_tris])

	# 5. Clean zero-leak teardown releases all static caches cleanly to null!
	holder.queue_free()
	await physics_frames(3)
	TreasureCatalog.clear_mesh_cache()
	check_eq(MerchantStall._active_stalls, 0, "all MerchantStalls exited cleanly")
	check(MerchantStall._doubloon_mesh == null and MerchantStall._doubloon_mat == null,
		"MerchantStall releases static doubloon cache cleanly to null")
	check_eq(DigSite._active_dig_sites, 0, "all DigSites exited cleanly")
	check(DigSite._clod_mesh == null and DigSite._clod_mat == null \
			and DigSite._sparkle_mesh == null and DigSite._sparkle_mat == null,
		"DigSite releases static clod & sparkle caches cleanly to null")


func test_victory_flare_sculpted_launch_burst_and_teardown() -> void:
	Net.start_single_player()
	var flare_gd: GDScript = preload("res://src/world/victory_flare.gd")
	var holder := Node3D.new()
	holder.name = "VictoryFlareTestHolder"
	add_child(holder)

	# 1. Launch flare & inspect zero-primitive sculpted Rocket, 16-tri 4-Point Star & 8-tri Diamond ArrayMeshes!
	var flare: Node3D = flare_gd.call(&"launch", holder, Vector3(0.0, 2.0, 0.0), Color(1.0, 0.84, 0.28)) as Node3D
	check(flare != null and flare.is_in_group(&"victory_flares"), "VictoryFlare.launch spawns node in group victory_flares")

	var rocket_mi := flare.get_node_or_null(^"RocketRoot/RocketMesh") as MeshInstance3D
	var star_gp := flare.get_node_or_null(^"StarburstParticles") as GPUParticles3D
	var ember_gp := flare.get_node_or_null(^"EmberCascadeParticles") as GPUParticles3D
	var light := flare.get_node_or_null(^"ApexFlashLight") as OmniLight3D

	check(rocket_mi != null and rocket_mi.mesh is ArrayMesh and not (rocket_mi.mesh is PrimitiveMesh),
		"VictoryFlare builds sculpted Brass Signal Rocket ArrayMesh (zero primitives)")
	check(star_gp != null and star_gp.draw_pass_1 is ArrayMesh and not (star_gp.draw_pass_1 is PrimitiveMesh),
		"StarburstParticles uses sculpted 4-Point Star ArrayMesh (zero primitives)")
	check(ember_gp != null and ember_gp.draw_pass_1 is ArrayMesh and not (ember_gp.draw_pass_1 is PrimitiveMesh),
		"EmberCascadeParticles uses sculpted Diamond Spark ArrayMesh (zero primitives)")
	check(light != null and not light.shadow_enabled, "VictoryFlare mounts shadowless ApexFlashLight OmniLight3D")

	var rocket_tris: int = int(flare.call(&"get_rocket_triangle_count"))
	var star_tris: int = _count_mesh_triangles(star_gp.draw_pass_1) if star_gp != null else 0
	var diamond_tris: int = _count_mesh_triangles(ember_gp.draw_pass_1) if ember_gp != null else 0
	print("    VictoryFlare sculpted meshes: Rocket=%d, StarSpark=%d, DiamondEmber=%d tris" % [
		rocket_tris, star_tris, diamond_tris])
	check(rocket_tris >= 240, "Brass Signal Rocket has rich sculpted silhouette (%d tris)" % rocket_tris)
	check_eq(star_tris, 16, "4-point faceted celebration star-spark has exact 16 tris")
	check_eq(diamond_tris, 8, "faceted diamond ember-spark has exact 8 tris")

	# 2. Step RISING -> BURST (emits burst_detonated once at ~22-26 m apex) -> DONE auto-cleanup!
	var burst_positions: Array[Vector3] = []
	flare.connect(&"burst_detonated", func(pos: Vector3) -> void: burst_positions.append(pos))
	flare.call(&"step_flare", 0.50)
	check(flare.global_position.y > 10.0, "VictoryFlare climbs rapidly during RISING (y=%.1f m)" % flare.global_position.y)
	check_eq(burst_positions.size(), 0, "flare has not detonated before apex")

	flare.call(&"step_flare", 0.85)
	check_eq(burst_positions.size(), 1, "burst_detonated emits exactly once upon reaching apex")
	check(burst_positions[0].y >= 22.0 and burst_positions[0].y <= 32.0,
		"VictoryFlare detonates cleanly at celebratory altitude (y=%.1f m)" % burst_positions[0].y)
	check(not (flare.get_node(^"RocketRoot") as Node3D).visible, "RocketRoot hides on burst detonation")
	check(star_gp.emitting and ember_gp.emitting, "both sculpted starburst particle layers emit on detonation")
	check(light.light_energy >= 6.0 and light.omni_range >= 35.0,
		"ApexFlashLight flashes brightly at detonation (energy=%.1f)" % light.light_energy)

	# Decay smoothly to DONE and auto-queue_free!
	flare.call(&"step_flare", 1.10)
	check(light.light_energy < 3.5 and light.light_energy > 0.1,
		"ApexFlashLight decays smoothly mid-burst (energy=%.2f)" % light.light_energy)
	flare.call(&"step_flare", 1.25)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(flare), "VictoryFlare auto-frees cleanly upon reaching DONE")

	# 3. Verify force_burst_apex() + zero-leak static cache teardown!
	var flare2: Node3D = flare_gd.call(&"launch", holder, Vector3(12.0, 2.0, -8.0), Color(0.28, 0.96, 0.68)) as Node3D
	var burst2 := [false]
	flare2.connect(&"burst_detonated", func(_p: Vector3) -> void: burst2[0] = true)
	flare2.call(&"force_burst_apex")
	check(burst2[0] and flare2.global_position.y >= 24.0, "force_burst_apex snaps to apex and detonates cleanly")

	holder.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(flare2), "second VictoryFlare freed cleanly on parent teardown")
	check_eq(int(flare_gd.get(&"_active_flares")), 0, "all VictoryFlares exited cleanly")
	check(flare_gd.get(&"_rocket_mesh") == null and flare_gd.get(&"_star_mesh") == null \
			and flare_gd.get(&"_diamond_mesh") == null and flare_gd.get(&"_rocket_mat") == null,
		"VictoryFlare releases all static mesh & material caches cleanly to null")




