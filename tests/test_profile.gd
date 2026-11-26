extends TestCase

const PATH := "user://test_profile.json"

func test_roundtrip() -> void:
	var p := Profile.new()
	p.add_gold(350)
	check(p.spend_gold(100))
	check(not p.spend_gold(1000), "cannot overspend")
	p.add_renown("chartwrights", 5)
	p.unlock("hull_stout")
	check(p.discover("gull_rock"))
	check(not p.discover("gull_rock"), "second discovery is not new")
	p.bump_stat("chests_sold")
	check_eq(p.save(PATH), OK)
	var q := Profile.new()
	check(q.load_from(PATH))
	check_eq(int(q.data["gold"]), 250)
	check_eq(int(q.data["renown"]["chartwrights"]), 5)
	check(q.has_unlock("hull_stout"))
	check_eq(int(q.data["stats"]["chests_sold"]), 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func test_old_and_corrupt_files() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"gold": 12, "future_key": [1,2]}')
	f.close()
	var p := Profile.new()
	check(p.load_from(PATH))
	check_eq(int(p.data["gold"]), 12)
	check(p.data.has("stats"), "missing keys take defaults")
	check(p.data.has("future_key"), "unknown keys are preserved")
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("not json {")
	f.close()
	var q := Profile.new()
	check(not q.load_from(PATH))
	check_eq(int(q.data["gold"]), 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_hull_livery_persistence_and_ship_application() -> void:
	var sloop_scene: PackedScene = preload("res://src/ship/sloop.tscn")
	var livery_path := "user://test_hull_livery_profile.json"
	var p := Profile.new()
	check_eq(Economy.get_equipped(p, &"hull_livery"), &"", "default hull_livery is empty for backward compatibility")

	var liveries := Economy.get_unlocks_by_slot(&"hull_livery")
	check_eq(liveries.size(), 4, "Economy registers 4 hull_livery cosmetics")

	# Rank-gating check: Sovereign Pitch & Gold requires Gilded Compass Rank 4.
	p.add_gold(1500)
	var blocked := Economy.purchase_unlock(p, &"hull_obsidian_sovereign")
	check(not bool(blocked.get("ok", false)), "rank-4 hull livery blocked at rank 1")

	# Purchase Rank-1 Admiral's Azure Hull immediately.
	var buy_azure := Economy.purchase_unlock(p, &"hull_royal_azure")
	check(bool(buy_azure.get("ok", false)), "Rank-1 Admiral's Azure Hull purchases cleanly")
	check(Economy.equip_loadout(p, &"hull_livery", &"hull_royal_azure"), "equip hull_royal_azure")
	check_eq(Economy.get_equipped(p, &"hull_livery"), &"hull_royal_azure")

	# Reach Gilded Compass Rank 4 (600 renown) and purchase + equip Sovereign Pitch & Gold.
	p.add_renown("gilded_compass", Economy.rank_threshold(4))
	var buy_sov := Economy.purchase_unlock(p, &"hull_obsidian_sovereign")
	check(bool(buy_sov.get("ok", false)), "Rank-4 Sovereign Pitch & Gold purchases after rank-up")
	check(Economy.equip_loadout(p, &"hull_livery", &"hull_obsidian_sovereign"), "equip hull_obsidian_sovereign")
	check_eq(Economy.get_ship_modifiers(p).get("hull_livery_id"), &"hull_obsidian_sovereign",
		"get_ship_modifiers exposes hull_livery_id")

	# Save & reload into a fresh Profile to verify full JSON persistence.
	check_eq(p.save(livery_path), OK, "profile saves hull_livery loadout cleanly")
	var loaded := Profile.new()
	check(loaded.load_from(livery_path), "profile reloads hull_livery loadout cleanly")
	check(loaded.has_unlock("hull_obsidian_sovereign"), "reloaded profile retains hull_obsidian_sovereign unlock")
	check_eq(Economy.get_equipped(loaded, &"hull_livery"), &"hull_obsidian_sovereign",
		"reloaded profile restores equipped hull_livery")
	check_eq(Economy.get_ship_modifiers(loaded).get("hull_livery_id"), &"hull_obsidian_sovereign",
		"reloaded get_ship_modifiers preserves hull_livery_id")

	# Apply full 4-param livery to a real Sloop via ShipwrightMenu.apply_economy_to_ship().
	Net.start_single_player()
	var sloop := sloop_scene.instantiate() as Ship
	sloop.enable_effects = false
	sloop.start_anchored = true
	add_child(sloop)
	await physics_frames(1)

	ShipwrightMenu.apply_economy_to_ship(sloop, loaded)
	var expected_entry := Economy.get_unlock(&"hull_obsidian_sovereign")
	var expected_hull_tint: Color = expected_entry["tint"] as Color
	var expected_glow: Color = expected_entry["glow_accent"] as Color
	check(sloop._livery_hull_tint != Color.WHITE, "applied hull livery sets non-default hull_tint on Ship")
	check(sloop._livery_hull_tint.is_equal_approx(expected_hull_tint),
		"Ship receives exact hull_tint from equipped hull_livery")
	check(sloop._livery_glow_accent.is_equal_approx(expected_glow),
		"Ship receives exact glow_accent from equipped hull_livery")

	# Verify ShipwrightMenu renders the Hull Paint slot & ink-bordered 18x18 cosmetic swatch chips!
	var menu := ShipwrightMenu.new()
	add_child(menu)
	menu.refresh()
	for uid_str: String in ["hull_royal_azure", "hull_obsidian_sovereign", "sail_sunburst", "flag_crimson_gull"]:
		var swatch := menu.find_child("Swatch_" + uid_str, true, false) as PanelContainer
		check(swatch != null, "ShipwrightMenu builds ink-bordered swatch chip for %s" % uid_str)
		if swatch != null:
			var rect := swatch.get_node_or_null(^"SwatchColor") as ColorRect
			check(rect != null and rect.custom_minimum_size == Vector2(18.0, 18.0),
				"Swatch %s renders 18x18 ColorRect" % uid_str)
			if rect != null:
				var u_tint: Color = Economy.get_unlock(StringName(uid_str))["tint"] as Color
				check(rect.color.is_equal_approx(u_tint), "Swatch %s matches unlock tint color" % uid_str)

	menu.queue_free()
	sloop.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(livery_path))
	await physics_frames(2)


func test_company_heraldic_sail_liveries_and_emblem_modes() -> void:
	var sloop_scene: PackedScene = preload("res://src/ship/sloop.tscn")
	var sail_path := "user://test_heraldic_sails_profile.json"
	var p := Profile.new()

	check_eq(int(Economy.get_ship_modifiers(p).get("sail_emblem_mode", -1)), 0,
		"default sail_emblem_mode is 0 when no sail cosmetic is equipped")

	var sail_cosmetics := Economy.get_unlocks_by_slot(&"sail_cosmetic")
	check_eq(sail_cosmetics.size(), 5, "Economy registers 5 sail_cosmetic liveries (2 classic + 3 company flagships)")

	# Verify exact metadata & emblem_mode contracts for all 5 sail liveries.
	var expected_modes := {
		&"sail_gilded_compass": 4,
		&"sail_sunken_archive": 5,
		&"sail_midnight_wave": 5,
		&"sail_iron_tide": 6,
		&"sail_sunburst": 7,
	}
	for uid: StringName in expected_modes.keys():
		var entry := Economy.get_unlock(uid)
		check(not entry.is_empty(), "Economy registers sail livery %s" % String(uid))
		check_eq(entry.get("slot"), &"sail_cosmetic", "%s lives in sail_cosmetic slot" % String(uid))
		check_eq(int(entry.get("emblem_mode", -1)), int(expected_modes[uid]),
			"%s reports emblem_mode %d" % [String(uid), int(expected_modes[uid])])

	# Unlock gold + renown across all 3 trading companies to test purchase, equip, and modifier reporting.
	p.add_gold(4000)
	p.add_renown("gilded_compass", Economy.rank_threshold(3))
	p.add_renown("sunken_archive", Economy.rank_threshold(3))
	p.add_renown("iron_tide", Economy.rank_threshold(3))

	Net.start_single_player()
	var sloop := sloop_scene.instantiate() as Ship
	sloop.enable_effects = false
	sloop.start_anchored = true
	add_child(sloop)
	await physics_frames(1)

	for uid: StringName in [&"sail_gilded_compass", &"sail_sunken_archive", &"sail_iron_tide", &"sail_sunburst"]:
		var buy_res := Economy.purchase_unlock(p, uid)
		check(bool(buy_res.get("ok", false)), "purchase %s succeeds" % String(uid))
		check(Economy.equip_loadout(p, &"sail_cosmetic", uid), "equip %s succeeds" % String(uid))
		var mods := Economy.get_ship_modifiers(p)
		var want_mode: int = int(expected_modes[uid])
		check_eq(int(mods.get("sail_emblem_mode", -1)), want_mode,
			"get_ship_modifiers exposes sail_emblem_mode=%d for %s" % [want_mode, String(uid)])

		var applied := ShipwrightMenu.apply_economy_to_ship(sloop, p)
		check_eq(int(applied.get("sail_emblem_mode", -1)), want_mode,
			"apply_economy_to_ship returns sail_emblem_mode=%d for %s" % [want_mode, String(uid)])
		check(sloop._livery_sail_tint.is_equal_approx(Color.WHITE),
			"heraldic emblem mode %d keeps sail_tint crisp Color.WHITE" % want_mode)
		var ship_mode: Variant = sloop.get(&"_livery_sail_emblem_mode")
		if ship_mode is int:
			check_eq(int(ship_mode), want_mode,
				"Ship receives sail_emblem_mode=%d via apply_livery()" % want_mode)

	# Save & reload equipped flagship sail into fresh Profile.
	check(Economy.equip_loadout(p, &"sail_cosmetic", &"sail_iron_tide"), "equip sail_iron_tide before save")
	check_eq(p.save(sail_path), OK, "profile saves flagship sail loadout cleanly")
	var loaded := Profile.new()
	check(loaded.load_from(sail_path), "profile reloads flagship sail loadout cleanly")
	check_eq(Economy.get_equipped(loaded, &"sail_cosmetic"), &"sail_iron_tide",
		"reloaded profile restores equipped sail_iron_tide")
	check_eq(int(Economy.get_ship_modifiers(loaded).get("sail_emblem_mode", -1)), 6,
		"reloaded profile restores sail_emblem_mode=6")

	# Verify ShipwrightMenu renders ink-bordered color swatches for all 3 company flagship sails.
	var menu := ShipwrightMenu.new()
	add_child(menu)
	menu.refresh()
	for uid_str: String in ["sail_gilded_compass", "sail_sunken_archive", "sail_iron_tide"]:
		var swatch := menu.find_child("Swatch_" + uid_str, true, false) as PanelContainer
		check(swatch != null, "ShipwrightMenu builds swatch chip for %s" % uid_str)
		if swatch != null:
			var rect := swatch.get_node_or_null(^"SwatchColor") as ColorRect
			var u_tint: Color = Economy.get_unlock(StringName(uid_str))["tint"] as Color
			check(rect != null and rect.color.is_equal_approx(u_tint),
				"Swatch %s renders unlock tint color" % uid_str)

	menu.queue_free()
	sloop.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sail_path))
	await physics_frames(2)


func test_crew_uniform_cosmetics_persistence_and_live_retinting() -> void:
	var pawn_scene: PackedScene = preload("res://src/characters/pawn.tscn")
	var uniform_path := "user://test_crew_uniform_profile.json"
	var p := Profile.new()

	check_eq(Economy.get_equipped(p, &"crew_uniform"), &"",
		"default crew_uniform is empty for backward compatibility")
	check_eq(Economy.get_ship_modifiers(p).get("crew_uniform_id"), &"",
		"default get_ship_modifiers exposes empty crew_uniform_id")

	var uniforms := Economy.get_unlocks_by_slot(&"crew_uniform")
	check_eq(uniforms.size(), 4, "Economy registers 4 crew_uniform cosmetics")
	for uid: StringName in [
		&"crew_gilded_admiral",
		&"crew_crimson_corsair",
		&"crew_archive_mystic",
		&"crew_sovereign_velvet",
	]:
		var u := Economy.get_unlock(uid)
		check(not u.is_empty(), "Economy registers %s" % String(uid))
		check(u.get("tint") is Color and u.get("accent_tint") is Color,
			"%s defines primary tint and accent_tint" % String(uid))

	# Rank-gating check: Sovereign Velvet & Gold requires Gilded Compass Rank 4.
	p.add_gold(2000)
	var blocked := Economy.purchase_unlock(p, &"crew_sovereign_velvet")
	check(not bool(blocked.get("ok", false)), "Rank-4 crew_sovereign_velvet blocked at Rank 1")

	# Rank-1 Gilded Admiral Coats purchases and equips immediately.
	var buy_adm := Economy.purchase_unlock(p, &"crew_gilded_admiral")
	check(bool(buy_adm.get("ok", false)), "Rank-1 crew_gilded_admiral purchases cleanly")
	check(Economy.equip_loadout(p, &"crew_uniform", &"crew_gilded_admiral"), "equip crew_gilded_admiral")

	# Reach Gilded Compass Rank 4 and purchase + equip Sovereign Velvet & Gold.
	p.add_renown("gilded_compass", Economy.rank_threshold(4))
	var buy_sov := Economy.purchase_unlock(p, &"crew_sovereign_velvet")
	check(bool(buy_sov.get("ok", false)), "Rank-4 crew_sovereign_velvet purchases after rank-up")
	check(Economy.equip_loadout(p, &"crew_uniform", &"crew_sovereign_velvet"), "equip crew_sovereign_velvet")
	check_eq(Economy.get_ship_modifiers(p).get("crew_uniform_id"), &"crew_sovereign_velvet",
		"get_ship_modifiers exposes crew_uniform_id")

	# Save & reload JSON persistence check.
	check_eq(p.save(uniform_path), OK, "profile saves crew_uniform loadout cleanly")
	var loaded := Profile.new()
	check(loaded.load_from(uniform_path), "profile reloads crew_uniform loadout cleanly")
	check(loaded.has_unlock("crew_sovereign_velvet"), "reloaded profile keeps crew_sovereign_velvet unlock")
	check_eq(Economy.get_equipped(loaded, &"crew_uniform"), &"crew_sovereign_velvet",
		"reloaded profile restores equipped crew_uniform")

	# Live re-tinting across 3 crewmates with subtle per-persona variation & clean restore!
	Net.start_single_player()
	var personas: Array[StringName] = [&"helmsman", &"lookout", &"carpenter"]
	var pawns: Array[Pawn] = []
	var brains: Array[CrewBrain] = []
	var visuals: Array[CharacterVisual] = []
	var defaults_p: Array[Color] = []
	var defaults_a: Array[Color] = []

	for i in personas.size():
		var cp := pawn_scene.instantiate() as Pawn
		add_child(cp)
		var cv := cp.get_node(^"Visual/CharacterVisual") as CharacterVisual
		cv.set_archetype(personas[i])
		var orig_p := cv._primary_tint
		var orig_a := cv._secondary_tint
		var br := CrewBrain.new()
		br.persona_id = personas[i]
		cp.add_child(br)
		pawns.append(cp)
		brains.append(br)
		visuals.append(cv)
		defaults_p.append(orig_p)
		defaults_a.append(orig_a)
	await physics_frames(1)

	ShipwrightMenu.apply_economy_to_ship(null, loaded, brains)
	var sov_entry := Economy.get_unlock(&"crew_sovereign_velvet")
	var sov_p: Color = sov_entry["tint"] as Color
	var sov_a: Color = sov_entry["accent_tint"] as Color
	check(visuals[0]._primary_tint.is_equal_approx(sov_p) and visuals[0]._secondary_tint.is_equal_approx(sov_a),
		"helmsman receives exact Sovereign Velvet primary & accent tints")
	check(visuals[1]._primary_tint.is_equal_approx(sov_p.lightened(0.10)),
		"lookout receives subtle lightened uniform coat variation")
	check(visuals[2]._primary_tint.is_equal_approx(sov_p.darkened(0.10)),
		"carpenter receives subtle deepened uniform coat variation")
	check(not visuals[0]._primary_tint.is_equal_approx(visuals[1]._primary_tint),
		"crewmates retain subtle individual tonal distinction")

	# Clearing crew_uniform back to default restores each persona's original palette!
	check(Economy.equip_loadout(loaded, &"crew_uniform", &""), "clear crew_uniform to default")
	ShipwrightMenu.apply_economy_to_ship(null, loaded, brains)
	for i in visuals.size():
		check(visuals[i]._primary_tint.is_equal_approx(defaults_p[i])
				and visuals[i]._secondary_tint.is_equal_approx(defaults_a[i]),
			"clearing crew_uniform restores persona %d default tints" % i)

	# Verify ShipwrightMenu renders dual-tone primary + accent swatch chips for crew uniforms.
	var menu := ShipwrightMenu.new()
	add_child(menu)
	menu.refresh()
	for uid_str: String in [
		"crew_gilded_admiral",
		"crew_crimson_corsair",
		"crew_archive_mystic",
		"crew_sovereign_velvet",
	]:
		var sw := menu.find_child("Swatch_" + uid_str, true, false) as PanelContainer
		var sw_acc := menu.find_child("SwatchAccent_" + uid_str, true, false) as PanelContainer
		check(sw != null and sw_acc != null, "ShipwrightMenu builds dual-tone swatch chips for %s" % uid_str)
		if sw != null and sw_acc != null:
			var r_p := sw.get_node_or_null(^"SwatchColor") as ColorRect
			var r_a := sw_acc.get_node_or_null(^"SwatchAccentColor") as ColorRect
			var u := Economy.get_unlock(StringName(uid_str))
			check(r_p != null and r_p.color.is_equal_approx(u["tint"] as Color),
				"Primary swatch matches %s tint" % uid_str)
			check(r_a != null and r_a.color.is_equal_approx(u["accent_tint"] as Color),
				"Accent swatch matches %s accent_tint" % uid_str)

	menu.queue_free()
	for cp in pawns:
		cp.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(uniform_path))
	await physics_frames(2)


func test_tool_variant_sidegrades_persistence_and_inventory_effects() -> void:
	var pawn_scene: PackedScene = preload("res://src/characters/pawn.tscn")
	var sloop_scene: PackedScene = preload("res://src/ship/sloop.tscn")
	var tool_path := "user://test_tool_variant_profile.json"
	var p := Profile.new()

	check_eq(Economy.get_equipped(p, &"tool_variant"), &"",
		"default tool_variant is empty for backward compatibility")
	var base_mods := Economy.get_ship_modifiers(p)
	check_eq(base_mods.get("tool_variant_id"), &"", "default tool_variant_id is empty")
	check_near(float(base_mods.get("spyglass_zoom_scale", 0.0)), 1.0, 0.001)
	check_near(float(base_mods.get("sighting_range_scale", 0.0)), 1.0, 0.001)
	check_near(float(base_mods.get("dig_power", 0.0)), 1.0, 0.001)
	check_near(float(base_mods.get("bail_power_scale", 0.0)), 1.0, 0.001)

	var variants := Economy.get_unlocks_by_slot(&"tool_variant")
	check_eq(variants.size(), 3, "Economy registers 3 tool_variant sidegrades")

	# Rank gating: Rank-2 master shovel & cooper bucket blocked at Rank 1; Rank-1 spyglass allowed.
	p.add_gold(2000)
	check(not bool(Economy.purchase_unlock(p, &"tool_master_shovel").get("ok", false)),
		"Rank-2 tool_master_shovel blocked at Rank 1")
	check(not bool(Economy.purchase_unlock(p, &"tool_cooper_bucket").get("ok", false)),
		"Rank-2 tool_cooper_bucket blocked at Rank 1")
	check(bool(Economy.purchase_unlock(p, &"tool_gilded_spyglass").get("ok", false)),
		"Rank-1 tool_gilded_spyglass purchases cleanly")
	check(Economy.equip_loadout(p, &"tool_variant", &"tool_gilded_spyglass"), "equip tool_gilded_spyglass")

	# Save & reload Profile JSON round-trip.
	check_eq(p.save(tool_path), OK, "profile saves tool_variant cleanly")
	var loaded := Profile.new()
	check(loaded.load_from(tool_path), "profile reloads tool_variant cleanly")
	check_eq(Economy.get_equipped(loaded, &"tool_variant"), &"tool_gilded_spyglass",
		"reloaded profile restores equipped tool_variant")

	# Unlock Rank 2 across Sunken Archive & Iron Tide for shovel + bucket testing.
	loaded.add_renown("sunken_archive", Economy.rank_threshold(2))
	loaded.add_renown("iron_tide", Economy.rank_threshold(2))
	check(bool(Economy.purchase_unlock(loaded, &"tool_master_shovel").get("ok", false)),
		"purchase tool_master_shovel after Rank 2")
	check(bool(Economy.purchase_unlock(loaded, &"tool_cooper_bucket").get("ok", false)),
		"purchase tool_cooper_bucket after Rank 2")

	# Set up live Pawn + PlayerController + Inventory to verify real gameplay effects!
	Net.start_single_player()
	var captain := pawn_scene.instantiate() as Pawn
	var ctrl := PlayerController.new()
	ctrl.input_enabled = false
	captain.add_child(ctrl)
	var inv := Inventory.new()
	inv.input_enabled = false
	captain.add_child(inv)
	add_child(captain)
	await physics_frames(1)

	# 1. Navigator's Far-Spyglass: tighter telephoto FOV (~12.96 deg) & +35% sighting range.
	check(Economy.equip_loadout(loaded, &"tool_variant", &"tool_gilded_spyglass"), "equip far-spyglass")
	ShipwrightMenu.apply_economy_to_ship(null, loaded, [], null, inv)
	check_near(inv.spyglass_zoom_scale, 0.72, 0.001, "far-spyglass sets spyglass_zoom_scale=0.72")
	check_near(inv.sighting_range_scale, 1.35, 0.001, "far-spyglass sets sighting_range_scale=1.35")
	inv.equip(&"spyglass", true)
	inv.set_secondary_held(true)
	for _f in range(30):
		inv.call(&"_process", 0.05)
	check(ctrl.camera != null and ctrl.camera.fov < Inventory.SPYGLASS_FOV - 3.5,
		"far-spyglass tightens zoomed camera FOV below base 18 deg (got %.2f)" % (ctrl.camera.fov if ctrl.camera != null else 99.0))
	inv.set_secondary_held(false)

	# 2. Iron-Edged Relic Shovel: unearths a 3-hit DigSite in 2 crisp digs!
	check(Economy.equip_loadout(loaded, &"tool_variant", &"tool_master_shovel"), "equip master shovel")
	ShipwrightMenu.apply_economy_to_ship(null, loaded, [], null, inv)
	check_eq(inv.dig_power, 2, "master shovel sets dig_power = 2")
	check_near(inv.spyglass_zoom_scale, 1.0, 0.001, "switching variant resets spyglass_zoom_scale to 1.0")
	var site := DigSite.new()
	site.treasure_id = &"driftwood_chest"
	site.position = Vector3(4.0, 0.0, 0.0)
	add_child(site)
	captain.global_position = Vector3(3.2, 0.0, 0.0)
	inv.equip(&"shovel", true)
	var dig1 := inv.use_shovel()
	check(bool(dig1.get("hit", false)), "master shovel dig 1 hits DigSite")
	check_eq(site.dig_count, 2, "master shovel advances DigSite by 2 strikes on dig 1")
	check(not site.is_unearthed, "DigSite still needs 1 more strike after dig 1")
	var dig2 := inv.use_shovel()
	check(bool(dig2.get("hit", false)) and bool(dig2.get("unearthed", false)),
		"master shovel unearths 3-hit DigSite cleanly in 2 digs!")
	check(site.is_unearthed and site.spawned_chest != null, "unearthed chest spawned cleanly")
	if site.spawned_chest != null and is_instance_valid(site.spawned_chest):
		site.spawned_chest.queue_free()
	site.queue_free()

	# 3. Copper-Banded Heavy Bailer: bails +40% more bilge water per scoop!
	check(Economy.equip_loadout(loaded, &"tool_variant", &"tool_cooper_bucket"), "equip cooper bucket")
	ShipwrightMenu.apply_economy_to_ship(null, loaded, [], null, inv)
	check_near(inv.bail_power_scale, 1.40, 0.001, "cooper bucket sets bail_power_scale = 1.40")
	check_eq(inv.dig_power, 1, "switching variant resets dig_power to 1")
	var sloop := sloop_scene.instantiate() as Ship
	sloop.enable_effects = false
	sloop.start_anchored = true
	sloop.position = Vector3(20.0, 0.0, 0.0)
	add_child(sloop)
	await physics_frames(1)
	sloop.water_level = 0.60
	captain.global_position = sloop.global_position + Vector3(0.0, 1.1, 0.0)
	inv.equip(&"bucket", true)
	var bail_res := inv.use_bucket()
	check_eq(bail_res.get("action"), &"bail", "cooper bucket bails flooded sloop")
	check_near(float(bail_res.get("removed", 0.0)), Inventory.BAIL_AMOUNT * 1.40, 0.005,
		"cooper bucket removes +40%% bilge water per scoop (%.3f)" % float(bail_res.get("removed", 0.0)))

	# 4. Verify ShipwrightMenu renders all 3 Tool Variant cards in its Shipwright tab!
	var menu := ShipwrightMenu.new()
	add_child(menu)
	menu.refresh()
	for uid_str: String in ["tool_gilded_spyglass", "tool_master_shovel", "tool_cooper_bucket"]:
		check(menu.find_child("UnlockBtn_" + uid_str, true, false) != null,
			"ShipwrightMenu renders Tool Variant button for %s" % uid_str)

	menu.queue_free()
	sloop.queue_free()
	captain.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tool_path))
	await physics_frames(2)




