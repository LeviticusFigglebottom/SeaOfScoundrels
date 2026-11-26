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
	check(not lev.active, "defeated Leviathan marks active = false immediately")
	check(salvage_count[0] >= 2, "defeating Leviathan must spawn floating Sunken Archive salvage")

	# Verify central abyssal crown smoothly submerges during defeat retreat.
	var crown := lev.get_crown_node()
	check(crown != null, "Leviathan must have a central AbyssalCrown node")
	var crown_y_before := crown.global_position.y if crown != null else 0.0
	await physics_frames(10)
	if crown != null and is_instance_valid(crown):
		check(crown.global_position.y < crown_y_before - 0.15, "AbyssalCrown must submerge smoothly on defeat")

	root.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(lev), "Leviathan freed cleanly on teardown")


func test_leviathan_sculpted_tentacles_crown_and_ink_pool() -> void:
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
	await physics_frames(3)

	check(Leviathan.SEGMENT_COUNT >= 6 and Leviathan.SEGMENT_COUNT <= 8,
		"Leviathan tentacles must have 6-8 articulated segments")
	check_eq(lev._tentacles.size(), Leviathan.TENTACLE_COUNT, "tentacle dictionary count matches TENTACLE_COUNT")

	for i in Leviathan.TENTACLE_COUNT:
		var t: Dictionary = lev._tentacles[i]
		var segs: Array = t["segs"]
		check_eq(segs.size(), Leviathan.SEGMENT_COUNT, "tentacle %d has %d articulated segments" % [i, Leviathan.SEGMENT_COUNT])
		var base_seg: Node3D = segs[0]
		var tip_seg: Node3D = segs[segs.size() - 1]
		var base_body := base_seg.get_node_or_null(^"BodyMesh") as MeshInstance3D
		var tip_body := tip_seg.get_node_or_null(^"BodyMesh") as MeshInstance3D
		var base_veins := base_seg.get_node_or_null(^"BiolumVeins") as MeshInstance3D
		check(base_body != null and base_body.mesh is ArrayMesh, "base segment uses sculpted ArrayMesh")
		check(tip_body != null and tip_body.mesh is ArrayMesh, "tip segment uses sculpted ArrayMesh")
		check(base_veins != null and base_veins.mesh is ArrayMesh, "segment includes bioluminescent vein mesh")
		if base_body != null and base_body.mesh is ArrayMesh and tip_body != null and tip_body.mesh is ArrayMesh:
			var base_mesh := base_body.mesh as ArrayMesh
			check_eq(base_mesh.get_surface_count(), 3, "sculpted tentacle mesh has hide, dorsal fin, and sucker surfaces")
			var base_w := base_mesh.get_aabb().size.x
			var tip_w := (tip_body.mesh as ArrayMesh).get_aabb().size.x
			check(base_w >= 1.6, "muscular base diameter reflects ~0.95 m base radius")
			check(base_w > tip_w * 2.5, "tentacle tapers smoothly from thick base to whip tip")
		var hide_mat := t.get("hide_mat") as StandardMaterial3D
		var vein_mat := t.get("vein_mat") as StandardMaterial3D
		check(hide_mat != null and hide_mat.roughness <= 0.40, "dorsal hide has glossy wet roughness")
		check(vein_mat != null and vein_mat.emission_enabled, "bioluminescent veins have emission enabled")

	# Verify Central Abyssal Maw / Head Crown and glowing amber-aqua eyes.
	var crown := lev.get_crown_node()
	check(crown != null and crown.name == "AbyssalCrown", "central AbyssalCrown exists")
	if crown != null:
		check(crown.get_node_or_null(^"CrownMantle") is MeshInstance3D, "crown has sculpted mantle mesh")
		check(crown.get_node_or_null(^"CrownSpines") is MeshInstance3D, "crown has dorsal spine crest mesh")
		check(crown.get_node_or_null(^"AbyssalBeak") is MeshInstance3D, "crown has abyssal beak mesh")
		var eye_l := crown.get_node_or_null(^"EyeLeft")
		var eye_r := crown.get_node_or_null(^"EyeRight")
		check(eye_l != null and eye_r != null, "crown has pair of abyssal eyes")
		if eye_l != null:
			var iris := eye_l.get_node_or_null(^"AmberIris") as MeshInstance3D
			var rim := eye_l.get_node_or_null(^"AquaRim") as MeshInstance3D
			check(iris != null and (iris.material_override as StandardMaterial3D).emission_enabled,
				"eye amber iris emits glow")
			check(rim != null and (rim.material_override as StandardMaterial3D).emission_enabled,
				"eye aqua rim emits glow")

	# Verify wave-conformal bioluminescent ink pool ring.
	var ink_pool := lev.get_ink_pool_node()
	check(ink_pool != null and ink_pool.name == "InkPool", "bioluminescent InkPool mesh exists")
	if ink_pool != null:
		var ink_mat := ink_pool.material_override as ShaderMaterial
		check(ink_mat != null, "InkPool uses custom ShaderMaterial")
		if ink_mat != null:
			check(int(ink_mat.get_shader_parameter(&"sea_wave_count")) > 0,
				"InkPool shader is bound to shared Sea wave table")

	root.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(lev), "Leviathan visual hierarchy tears down cleanly")


func test_leviathan_bioluminescent_telegraph_and_spray_teardown() -> void:
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
	await physics_frames(3)

	# Put both tentacles 0 and 1 in calm idle state first.
	lev._tentacles[0]["slam_cd"] = 6.0
	lev._tentacles[1]["slam_cd"] = 6.0
	await physics_frames(2)
	check(not lev.is_tentacle_telegraphing(0), "tentacle 0 is idle when slam_cd > SLAM_WINDUP_TIME")
	var idle_energy := lev.get_tentacle_vein_energy(0)
	var segs0: Array = lev._tentacles[0]["segs"]
	var idle_base_pitch := (segs0[0] as Node3D).rotation.x

	# Advance tentacle 0 into slam windup telegraph while tentacle 1 stays idle.
	lev._tentacles[0]["slam_cd"] = 0.65
	lev._tentacles[1]["slam_cd"] = 6.0
	await physics_frames(2)
	check(lev.is_tentacle_telegraphing(0), "tentacle 0 enters telegraph state during slam windup")
	check(lev.get_tentacle_telegraph(0) > 0.5, "telegraph intensity rises past 0.5 near slam")
	check(not lev.is_tentacle_telegraphing(1), "tentacle 1 stays idle while tentacle 0 telegraphs")
	var tele_energy := lev.get_tentacle_vein_energy(0)
	var other_energy := lev.get_tentacle_vein_energy(1)
	check(tele_energy > idle_energy * 1.8, "bioluminescent veins brighten strongly during slam telegraph")
	check(tele_energy > other_energy * 1.5, "telegraph bioluminescent boost is independent per tentacle")
	check((segs0[0] as Node3D).rotation.x > idle_base_pitch + 0.08,
		"tentacle base rears backward into coiled strike posture during slam windup")

	# Trigger slam to spawn active GPUParticles3D spray bursts, then tear down mid-burst.
	lev._tentacles[0]["slam_cd"] = 0.01
	await physics_frames(3)
	check(lev.active_spray_burst_count() >= 1, "emerge and hull slam spawn feathered GPUParticles3D spray bursts")

	root.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(lev), "Leviathan with active spray bursts frees cleanly with zero errors")
