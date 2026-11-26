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


func test_ship_nameplate_persistence_painting_and_zero_leak_teardown() -> void:
	var sloop_scene: PackedScene = preload("res://src/ship/sloop.tscn")
	var brig_scene: PackedScene = preload("res://src/ship/brigantine.tscn")
	var name_path := "user://test_ship_name_profile.json"

	# 1. Profile default, sanitization, changed signal & save_to/load_from roundtrip.
	var p := Profile.new()
	check_eq(p.get_ship_name(), "The Gilded Scoundrel", "Profile defaults to The Gilded Scoundrel")
	check_eq(Profile.PRESET_SHIP_NAMES.size(), 8, "Profile provides 8 preset ship names")

	var changed_hits := [0]
	p.changed.connect(func() -> void: changed_hits[0] += 1)
	check_eq(p.set_ship_name("   "), "The Gilded Scoundrel", "whitespace falls back to default ship name")
	var sanitized := p.set_ship_name("  " + char(0x2605) + "A Very Long Pirate Vessel Name Beyond Limit!  ")
	check(sanitized.length() <= Profile.MAX_SHIP_NAME_LEN, "ship_name caps length <= 26 chars (%d)" % sanitized.length())
	check(not sanitized.contains(char(0x2605)), "ship_name strips non-ASCII glyphs")
	check_eq(p.set_ship_name("Crimson Compass"), "Crimson Compass", "set_ship_name stores clean ASCII name")
	check_eq(changed_hits[0], 3, "Profile.set_ship_name emits changed signal")

	check_eq(p.save_to(name_path), OK, "Profile.save_to persists ship_name cleanly")
	var loaded := Profile.new()
	check(loaded.load_from(name_path), "Profile.load_from reloads saved ship_name")
	check_eq(loaded.get_ship_name(), "Crimson Compass", "reloaded Profile preserves Crimson Compass")

	# 2. Mount ShipNameplate onto BOTH Sloop & Brigantine and verify zero-primitive meshes + 512x112 gold-leaf texture!
	Net.start_single_player()
	var sloop := sloop_scene.instantiate() as Ship
	sloop.enable_effects = false
	sloop.start_anchored = true
	add_child(sloop)

	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	brig.start_anchored = true
	brig.position = Vector3(26.0, 0.0, 0.0)
	add_child(brig)
	await physics_frames(1)

	var sloop_plate := ShipNameplate.mount_to_ship(sloop, loaded.get_ship_name())
	var brig_plate := ShipNameplate.mount_to_ship(brig, "Sovereign's Reckoning")
	check(sloop_plate != null and brig_plate != null, "ShipNameplate.mount_to_ship mounts on Sloop and Brigantine")
	check(sloop_plate.position.is_equal_approx(ShipNameplate.SLOOP_POS), "Sloop nameplate sits at exact stern frieze pos")
	check(brig_plate.position.is_equal_approx(ShipNameplate.BRIG_POS), "Brigantine nameplate sits at exact stern frieze pos")

	var raw_prims := 0
	var bad_normals := 0
	var srgb_missing := 0
	for plate: ShipNameplate in [sloop_plate, brig_plate]:
		for node in plate.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if mi.mesh is PrimitiveMesh:
				raw_prims += 1
			var am := mi.mesh as ArrayMesh
			if am != null:
				for si in am.get_surface_count():
					var arr := am.surface_get_arrays(si)
					var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
					for nv in norms:
						if not nv.is_finite() or nv.length_squared() < 0.5:
							bad_normals += 1
					var mat := mi.get_surface_override_material(si) as StandardMaterial3D
					if mat != null and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb:
						srgb_missing += 1
	check_eq(raw_prims, 0, "ShipNameplate contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "ShipNameplate mesh normals are all finite unit vectors")
	check_eq(srgb_missing, 0, "ShipNameplate vertex-colored frame materials enable vertex_color_is_srgb")

	# Inspect painted 512x112 ImageTexture for rich mahogany woodgrain + gleaming gold-leaf pixels!
	var tex1 := sloop_plate.get_plaque_texture()
	check(tex1 != null and tex1.get_width() == 512 and tex1.get_height() == 112,
		"ShipNameplate paints crisp 512x112 ImageTexture")
	if tex1 != null:
		var img := tex1.get_image()
		var gold_px := 0
		var wood_px := 0
		for py in range(0, 112, 2):
			for px in range(0, 512, 2):
				var c := img.get_pixel(px, py)
				if c.r > 0.72 and c.g > 0.52 and c.b < 0.68:
					gold_px += 1
				elif c.r > 0.08 and c.r < 0.45 and c.b < 0.16:
					wood_px += 1
		check(gold_px >= 250 and wood_px >= 4000,
			"plaque texture paints rich gold-on-mahogany lettering (gold_px=%d, wood_px=%d)" % [gold_px, wood_px])

	# Repaint cleanly on set_ship_name("Tidebreaker").
	sloop_plate.set_ship_name("Tidebreaker")
	check_eq(sloop_plate.current_name, "Tidebreaker", "set_ship_name updates current_name")
	check(sloop_plate.get_plaque_texture() != tex1, "set_ship_name repaints a fresh plaque ImageTexture")

	# 3. Verify ShipwrightMenu Ship Nameplate row & cycle_ship_name() integration!
	var saved_game_prof := Game.profile
	Game.profile = loaded
	var menu := ShipwrightMenu.new()
	add_child(menu)
	menu.bind(null, null, sloop, null, null)
	menu.refresh()
	check(menu.find_child("CycleShipNameButton", true, false) is Button,
		"ShipwrightMenu renders CycleShipNameButton")
	check(menu.find_child("ShipNameValueLabel", true, false) is Label,
		"ShipwrightMenu renders ShipNameValueLabel")

	var emitted_names: Array[String] = []
	menu.ship_name_changed.connect(func(nm: String) -> void: emitted_names.append(nm))
	var next_nm := menu.cycle_ship_name()
	check_eq(next_nm, "Abyssal Dawn", "cycle_ship_name advances from Crimson Compass -> Abyssal Dawn")
	check_eq(loaded.get_ship_name(), "Abyssal Dawn", "cycle_ship_name persists into Profile")
	check_eq(sloop_plate.current_name, "Abyssal Dawn", "cycle_ship_name updates moored ShipNameplate live")
	check_eq(emitted_names.size(), 1, "cycle_ship_name emits ship_name_changed signal")
	Game.profile = saved_game_prof

	menu.queue_free()
	sloop.queue_free()
	brig.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(name_path))
	await physics_frames(2)

	check(ShipNameplate._frame_mesh_sloop == null and ShipNameplate._frame_mesh_brig == null
		and ShipNameplate._plaque_mesh_sloop == null and ShipNameplate._wood_mat == null
		and ShipNameplate._brass_mat == null,
		"ShipNameplate releases all static mesh & material caches cleanly on teardown")


func test_profile_lifetime_stats_and_shipwright_captains_log_tab() -> void:
	var stats_path := "user://test_captains_log_profile.json"
	var legacy_path := "user://test_captains_log_legacy.json"

	# 1. Legacy profile.json missing gold_earned & bosses_defeated loads cleanly with 0 defaults.
	var lf := FileAccess.open(legacy_path, FileAccess.WRITE)
	lf.store_string('{"gold": 90, "stats": {"voyages_completed": 2, "chests_sold": 3, "times_sunk": 1}}')
	lf.close()
	var legacy_prof := Profile.new()
	check(legacy_prof.load_from(legacy_path), "legacy profile JSON loads cleanly")
	var lstats := legacy_prof.get_stats()
	check_eq(int(lstats.get("voyages_completed", -1)), 2, "legacy voyages_completed preserved")
	check_eq(int(lstats.get("chests_sold", -1)), 3, "legacy chests_sold preserved")
	check_eq(int(lstats.get("gold_earned", -1)), 0, "missing gold_earned defaults to 0")
	check_eq(int(lstats.get("bosses_defeated", -1)), 0, "missing bosses_defeated defaults to 0")

	# 2. New lifetime stat & discovery helpers persist cleanly across save_to() / load_from() roundtrip.
	var p := Profile.new()
	p.set_ship_name("Abyssal Dawn")
	p.data["ship_class"] = "brigantine"
	p.add_gold(850)
	p.add_renown("gilded_compass", 240)
	p.add_renown("iron_tide", 120)
	p.add_renown("sunken_archive", 310)
	p.record_voyage_completed()
	p.record_voyage_completed()
	p.record_chest_sold(420)
	p.record_chest_sold(315)
	p.record_boss_defeated()
	check(p.discover("port_scoundrel"), "discover port_scoundrel")
	check(p.discover("cutlass_cay"), "discover cutlass_cay")
	check_eq(p.get_discovery_count(), 2, "get_discovery_count returns 2")

	check_eq(p.save_to(stats_path), OK, "profile with lifetime stats saves via save_to()")
	var loaded := Profile.new()
	check(loaded.load_from(stats_path), "profile reloads lifetime stats cleanly")
	var rstats := loaded.get_stats()
	check_eq(int(rstats.get("voyages_completed", 0)), 2, "voyages_completed roundtrips")
	check_eq(int(rstats.get("chests_sold", 0)), 2, "chests_sold roundtrips")
	check_eq(int(rstats.get("gold_earned", 0)), 735, "gold_earned accumulates 420 + 315 = 735")
	check_eq(int(rstats.get("bosses_defeated", 0)), 1, "bosses_defeated roundtrips")
	check_eq(loaded.get_discovery_count(), 2, "discovery count roundtrips")

	# 3. Verify 4th Captain's Log tab in ShipwrightMenu renders Vessel Name, 3 Company ProgressBars & Discovery Ledger!
	var saved_game_prof := Game.profile
	Game.profile = loaded
	var menu := ShipwrightMenu.new()
	add_child(menu)
	menu.open_menu(ShipwrightMenu.TAB_LOG)
	await physics_frames(1)

	check_eq(menu.active_tab, ShipwrightMenu.TAB_LOG, "open_menu(TAB_LOG) switches to TAB_LOG")
	var tab_btn := menu.find_child("Tab_log", true, false) as Button
	check(tab_btn != null and tab_btn.text == "Captain's Log", "4th tab button labeled Captain's Log")

	var vessel_lbl := menu.find_child("LogVesselLabel", true, false) as Label
	check(vessel_lbl != null and vessel_lbl.text == "Abyssal Dawn  -  Brigantine",
		"LogVesselLabel displays ship name & class (got '%s')" % (vessel_lbl.text if vessel_lbl != null else ""))
	if vessel_lbl != null:
		for ci in vessel_lbl.text.length():
			check(vessel_lbl.text.unicode_at(ci) < 128, "LogVesselLabel text is strictly ASCII")

	for cid: String in ["gilded_compass", "iron_tide", "sunken_archive"]:
		var bar := menu.find_child("StandingBar_" + cid, true, false) as ProgressBar
		check(bar != null and bar.value > 0.0,
			"StandingBar_%s renders live renown progress (val=%.1f)" % [cid, bar.value if bar != null else -1.0])

	var chart_hdr := menu.find_child("ChartedWatersHeader", true, false) as Label
	check(chart_hdr != null and chart_hdr.text.begins_with("CHARTED WATERS: 2 / "),
		"ChartedWatersHeader counts 2 discovered islands (got '%s')" % (chart_hdr.text if chart_hdr != null else ""))
	var disc_grid := menu.find_child("DiscoveryLedgerGrid", true, false) as GridContainer
	check(disc_grid != null and disc_grid.columns == 2 and disc_grid.get_child_count() >= 10,
		"DiscoveryLedgerGrid builds 2-column archipelago checklist")
	var cutlass_row := menu.find_child("DiscoveryItem_cutlass_cay", true, false) as Label
	check(cutlass_row != null and cutlass_row.text.begins_with("[X] Cutlass Cay"),
		"discovered island Cutlass Cay marked [X] (got '%s')" % (cutlass_row.text if cutlass_row != null else ""))
	var fort_row := menu.find_child("DiscoveryItem_ironwatch_fort", true, false) as Label
	check(fort_row != null and fort_row.text.begins_with("[ ] Ironwatch Fort"),
		"uncharted island Ironwatch Fort marked [ ] (got '%s')" % (fort_row.text if fort_row != null else ""))

	menu.close_menu()
	menu.queue_free()
	Game.profile = saved_game_prof
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stats_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	await physics_frames(2)






