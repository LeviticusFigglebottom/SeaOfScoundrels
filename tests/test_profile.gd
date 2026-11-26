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

