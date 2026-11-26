extends TestCase
## Headless tests for the Abyssal Leviathan world-event boss.

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")


func test_leviathan_slams_hull_and_drops_salvage_on_defeat() -> void:
	Net.start_single_player()
	Sea.amp_scale = 0.0
	var root := Node3D.new()
	add_child(root)

	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	root.add_child(ship)

	var lev := Leviathan.new()
	lev.target_ship = ship
	root.add_child(lev)
	await physics_frames(4)
	check_eq(lev.living_tentacles(), Leviathan.TENTACLE_COUNT, "all 4 tentacles alive")

	# Force a tentacle slam -> must breach the ship's hull!
	lev._tentacles[0]["slam_cd"] = 0.01
	await physics_frames(4)
	check(ship.open_hole_count() >= 1, "Leviathan tentacle slam must breach target ship hull")

	# Defeat all 4 tentacles -> emits leviathan_defeated and spawns floating salvage!
	var salvage_count := [0]
	lev.leviathan_defeated.connect(func(_p: Vector3, items: Array) -> void:
		salvage_count[0] = items.size()
	)
	for i in Leviathan.TENTACLE_COUNT:
		lev.damage_tentacle(i, 120.0)
	check_eq(lev.living_tentacles(), 0, "all tentacles defeated")
	check(salvage_count[0] >= 2, "defeating Leviathan must spawn floating Sunken Archive salvage")

	root.queue_free()
	await physics_frames(2)
