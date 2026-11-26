extends TestCase
## Headless tests for UserSettings (persistence, key rebinding, quality presets)
## and Downtime mechanics (FishingLine tension/catch & CookingStove raw->cooked->burnt).

const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")


func test_user_settings_roundtrip_and_key_rebind() -> void:
	var path := "user://test_settings_tmp.json"
	var s := UserSettings.new()
	s.data["ocean_quality"] = 1
	s.data["cloud_quality"] = 2
	s.data["fov"] = 88.0
	s.data["head_bob_enabled"] = false
	check(s.rebind_key(&"jump", KEY_K), "rebind jump to KEY_K")
	check_eq(s.save(path), OK, "settings save OK")

	var loaded := UserSettings.new()
	check(loaded.load_from(path), "settings load OK")
	check_eq(int(loaded.data["ocean_quality"]), 1)
	check_eq(int(loaded.data["cloud_quality"]), 2)
	check_near(float(loaded.data["fov"]), 88.0, 0.01)
	check_eq(bool(loaded.data["head_bob_enabled"]), false)
	loaded.apply_all()

	var has_k := false
	for ev in InputMap.action_get_events(&"jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_K:
			has_k = true
	check(has_k, "loaded keybind applied to InputMap")

	# Restore default jump key & clean temp file.
	s.rebind_key(&"jump", KEY_SPACE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_fishing_cast_hook_reel_and_catch() -> void:
	Net.start_single_player()
	var rod := FishingLine.new()
	add_child(rod)

	var caught := [false]
	rod.fish_caught.connect(func(_sp: Dictionary) -> void: caught[0] = true)
	check(rod.cast_line(Vector3.ZERO, Vector3.FORWARD, 8.0), "cast succeeds")
	check_eq(rod.state, FishingLine.State.WAITING)

	# Simulate until bite, then reel smartly only when fish is NOT fighting!
	for _i in 600:
		var reel := rod.state == FishingLine.State.HOOKED and not rod.fish_fighting
		rod.step(0.05, Vector3.ZERO, reel)
		if caught[0]:
			break
	check(caught[0] and rod.caught_fish.size() == 1, "smart tension reeling catches a fish")

	# Verify reckless reeling during fight snaps the line!
	var snapped_flag := [false]
	rod.line_snapped.connect(func(_sp: Dictionary) -> void: snapped_flag[0] = true)
	rod.cast_line(Vector3.ZERO, Vector3.FORWARD, 12.0)
	rod._bite_timer = 0.01
	for _i in 200:
		rod.step(0.05, Vector3.ZERO, true)
		if snapped_flag[0]:
			break
	check(snapped_flag[0], "reeling nonstop through a fight snaps the line")
	rod.queue_free()


func test_cooking_stove_raw_cooked_burnt_and_healing() -> void:
	Net.start_single_player()
	var stove := CookingStove.new()
	add_child(stove)
	var pawn := PAWN_SCENE.instantiate() as Pawn
	add_child(pawn)
	pawn.apply_damage(60.0)
	var hp_before := pawn.health

	check(stove.place_food({"id": &"reef_grouper", "name": "Reef Grouper", "heal": 40.0}), "place raw fish")
	check_eq(stove.cook_state, &"raw")
	stove.step(11.0)
	check_eq(stove.cook_state, &"cooked", "fish cooks golden after 10 s")

	var meal := stove.take_food(pawn)
	check_eq(meal["cooked_state"], &"cooked")
	check(pawn.health > hp_before + 50.0, "cooked fish heals generously")

	# Leave second fish too long -> burns.
	stove.place_food({"id": &"azure_snapper", "name": "Azure Snapper", "heal": 30.0})
	stove.step(20.0)
	check_eq(stove.cook_state, &"burnt", "overcooked fish burns cleanly")
	pawn.queue_free()
	stove.queue_free()
