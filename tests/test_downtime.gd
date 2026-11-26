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


func test_fishing_visuals_rod_catenary_bobber_and_leaping_catch() -> void:
	Net.start_single_player()
	var rod := FishingLine.new()
	add_child(rod)

	# 1. Verify sculpted Bobber (multi-vertex ArrayMesh, NOT SphereMesh), FishingRod & FishingLineRibbon.
	var bobber := rod.get_node_or_null(^"Bobber") as MeshInstance3D
	var fish_rod := rod.get_node_or_null(^"FishingRod") as Node3D
	var line_rib := rod.get_node_or_null(^"FishingLineRibbon") as MeshInstance3D
	var splash := rod.get_node_or_null(^"FishingSplashParticles") as GPUParticles3D

	check(bobber != null, "Bobber node exists")
	check(bobber.mesh is ArrayMesh and not (bobber.mesh is SphereMesh), "Bobber uses sculpted ArrayMesh, not primitive SphereMesh")
	var bob_mesh := bobber.mesh as ArrayMesh
	check(bob_mesh.get_surface_count() >= 1, "Bobber ArrayMesh has geometry surface")
	var bob_arrays := bob_mesh.surface_get_arrays(0)
	var bob_verts: PackedVector3Array = bob_arrays[Mesh.ARRAY_VERTEX]
	var bob_cols: PackedColorArray = bob_arrays[Mesh.ARRAY_COLOR]
	check(bob_verts.size() >= 120, "Bobber ArrayMesh is multi-vertex sculpted float (%d verts)" % bob_verts.size())
	check_eq(bob_cols.size(), bob_verts.size(), "Bobber ArrayMesh carries vertex colors")

	check(fish_rod != null, "FishingRod exists")
	check(line_rib != null and line_rib.mesh is ImmediateMesh, "FishingLineRibbon exists with ImmediateMesh")
	check(splash != null and splash.amount == 10, "low-count splash particle emitter exists (amount = 10)")
	check(not bobber.visible and not fish_rod.visible and not line_rib.visible, "fishing visuals hidden in IDLE")

	# 2. cast_line() makes all three visuals visible and builds catenary geometry.
	check(rod.cast_line(Vector3.ZERO, Vector3.FORWARD, 10.0), "cast_line succeeds")
	check(bobber.visible and fish_rod.visible and line_rib.visible, "Bobber, FishingRod, and FishingLineRibbon visible after cast_line()")
	var imm := line_rib.mesh as ImmediateMesh
	check(imm.get_surface_count() >= 1, "catenary ImmediateMesh populated immediately on cast_line()")

	# 3. Stepping updates catenary geometry and flexes rod tip downward as line_tension rises.
	rod.step(0.05, Vector3.ZERO, false)
	var relaxed_tip := rod.get_rod_tip_world_pos()
	var relaxed_aabb := imm.get_aabb()
	check(relaxed_aabb.size.length() > 5.0, "catenary line AABB spans rod tip to bobber")

	# Trigger bite and reel during fight to build tension past 0.72 warning threshold.
	rod._bite_timer = 0.01
	rod.step(0.05, Vector3.ZERO, false)
	check_eq(rod.state, FishingLine.State.HOOKED)
	for _i in 18:
		rod.fish_fighting = true
		rod._fight_timer = 2.0
		rod.step(0.05, Vector3.ZERO, true)
		if rod.line_tension >= 0.78:
			break
	check(rod.line_tension >= 0.72, "reeling during fight raises line_tension into warning zone (%.2f)" % rod.line_tension)
	var taut_tip := rod.get_rod_tip_world_pos()
	check(taut_tip.y < relaxed_tip.y - 0.45, "rod tip flexes visibly downward under tension (%.2f -> %.2f)" % [relaxed_tip.y, taut_tip.y])
	check(imm.get_surface_count() >= 1, "catenary line ribbon remains cleanly updated under tension")

	# Verify painted bobber stays clearly visible near the waterline while fighting & rod bends monotonically.
	var fight_surf := Sea.height(rod.bobber_pos.x, rod.bobber_pos.z)
	check(rod.bobber_pos.y >= fight_surf - 0.10, "fighting bobber stays near waterline so crimson dome remains visible (dy=%.3f)" % (rod.bobber_pos.y - fight_surf))
	var mid_piv := fish_rod.get_node_or_null(^"RodMidPivot") as Node3D
	var tip_piv := fish_rod.get_node_or_null(^"RodMidPivot/RodTipPivot") as Node3D
	check(mid_piv != null and tip_piv != null, "RodMidPivot and RodTipPivot exist")
	if mid_piv != null and tip_piv != null:
		check(mid_piv.rotation.x < -0.10 and tip_piv.rotation.x < mid_piv.rotation.x,
			"rod flex distributes smoothly and monotonically from mid (%.2f) to tip (%.2f)" % [mid_piv.rotation.x, tip_piv.rotation.x])
		check(absf(mid_piv.rotation.x) < 0.42, "mid-ferrule bend avoids sharp elbow kink (%.2f rad)" % mid_piv.rotation.x)

	# 4. cancel_cast() hides all fishing visuals and clears the ImmediateMesh.
	rod.cancel_cast()
	check(not bobber.visible and not fish_rod.visible and not line_rib.visible, "cancel_cast() hides Bobber, FishingRod, and FishingLineRibbon")
	check_eq(imm.get_surface_count(), 0, "cancel_cast() clears catenary line geometry")

	# 5. Catching a fish spawns the sculpted LeapingCatchFish, arcs upward, and auto-cleans after 0.85 s.
	check(rod.cast_line(Vector3.ZERO, Vector3.FORWARD, 8.0), "second cast succeeds")
	rod._bite_timer = 0.01
	rod.step(0.05, Vector3.ZERO, false)
	rod.fish_fighting = false
	rod._fight_timer = 5.0
	rod.distance_out = 1.25
	rod.step(0.05, Vector3.ZERO, true)
	check_eq(rod.state, FishingLine.State.IDLE, "catch returns rod to IDLE")

	var leap := rod.get_node_or_null(^"LeapingCatchFish") as MeshInstance3D
	check(leap != null and is_instance_valid(leap), "LeapingCatchFish spawns on fish_caught")
	check(leap.mesh is ArrayMesh and (leap.mesh as ArrayMesh).get_surface_count() >= 2, "LeapingCatchFish has sculpted body + glossy eyes surfaces")
	var start_y := leap.global_position.y
	rod.step(0.40, Vector3.ZERO, false)
	check(is_instance_valid(leap) and leap.global_position.y > start_y + 1.0, "LeapingCatchFish arcs upward out of the water")
	rod.step(0.55, Vector3.ZERO, false)
	await get_tree().process_frame
	check(not is_instance_valid(leap) and rod.get_node_or_null(^"LeapingCatchFish") == null, "LeapingCatchFish auto-cleans after 0.85 s arc")

	# 6. Verify all 5 species build distinct sculpted palettes and multi-surface meshes.
	var dorsal_colors: Array[Color] = []
	for sp in FishingLine.SPECIES:
		var pal := FishingLine._get_species_palette(StringName(sp["id"]))
		var dcol: Color = pal["dorsal"]
		check(not dorsal_colors.has(dcol), "species %s has unique dorsal tint" % String(sp["id"]))
		dorsal_colors.append(dcol)
		var sp_mesh := FishingLine._build_fish_mesh(pal)
		check(sp_mesh != null and sp_mesh.get_surface_count() == 2, "species %s mesh has body + eyes" % String(sp["id"]))

	# 7. Teardown mid-leap cleans up all visuals with ZERO leaks.
	check(rod.cast_line(Vector3.ZERO, Vector3.FORWARD, 8.0), "third cast succeeds")
	rod._bite_timer = 0.01
	rod.step(0.05, Vector3.ZERO, false)
	rod.fish_fighting = false
	rod._fight_timer = 5.0
	rod.distance_out = 1.25
	rod.step(0.05, Vector3.ZERO, true)
	var leap2 := rod.get_node_or_null(^"LeapingCatchFish") as MeshInstance3D
	check(leap2 != null and is_instance_valid(leap2), "second LeapingCatchFish spawned before teardown")
	rod.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(rod) and not is_instance_valid(leap2), "FishingLine and active LeapingCatchFish freed with zero leaks")


func test_cooking_stove_sculpted_hearth_food_steam_and_teardown() -> void:
	Net.start_single_player()
	var stove := CookingStove.new()
	add_child(stove)

	# 1. Verify sculpted Cast-Iron Naval Galley Hearth, CoalBed, HearthLight & Copper-Rimmed Skillet.
	var hearth := stove.get_node_or_null(^"GalleyHearth") as MeshInstance3D
	var coals := stove.get_node_or_null(^"CoalBed") as MeshInstance3D
	var light := stove.get_node_or_null(^"HearthLight") as OmniLight3D
	var skillet := stove.get_node_or_null(^"FryingSkillet") as MeshInstance3D
	var food := stove.get_node_or_null(^"SizzlingFood") as MeshInstance3D
	var steam := stove.get_node_or_null(^"CookingSteam") as GPUParticles3D

	check(hearth != null and hearth.mesh is ArrayMesh, "GalleyHearth built as sculpted ArrayMesh")
	var hearth_am := hearth.mesh as ArrayMesh
	check(hearth_am.get_surface_count() >= 2, "GalleyHearth has cast-iron + brass trim surfaces")
	var hearth_aabb := hearth_am.get_aabb()
	check(hearth_aabb.position.y >= -0.02 and hearth_aabb.position.y <= 0.02, "GalleyHearth legs rest firmly at y = 0 (%.3f)" % hearth_aabb.position.y)
	check(hearth_aabb.end.y >= 1.38 and hearth_aabb.end.y <= 1.55, "GalleyHearth chimney flue rises cleanly to ~1.45 m (%.2f m)" % hearth_aabb.end.y)

	check(coals != null and coals.mesh is ArrayMesh, "CoalBed built as sculpted ArrayMesh")
	var coal_mat := coals.material_override as StandardMaterial3D
	check(coal_mat != null and coal_mat.emission_enabled, "CoalBed has glowing emissive material")

	check(light != null and not light.shadow_enabled, "HearthLight OmniLight3D exists with shadow_enabled = false")
	check(light.omni_range >= 2.0 and light.light_energy > 0.25, "HearthLight provides subtle warm hold firelight")

	check(skillet != null and skillet.mesh is ArrayMesh, "FryingSkillet built as sculpted ArrayMesh")
	check((skillet.mesh as ArrayMesh).get_surface_count() >= 2, "FryingSkillet has seasoned iron + hammered copper rim surfaces")

	check(food != null and food.mesh is ArrayMesh and not (food.mesh is CapsuleMesh), "SizzlingFood uses sculpted ArrayMesh, not CapsuleMesh")
	check(not food.visible, "SizzlingFood hidden when stove is empty")

	check(steam != null and steam is GPUParticles3D, "CookingSteam is a feathered billboard GPUParticles3D")
	check(not steam.emitting and not steam.visible, "CookingSteam idle when stove is empty")
	var steam_quad := steam.draw_pass_1 as QuadMesh
	var steam_mat := (steam_quad.material as StandardMaterial3D) if steam_quad != null else null
	check(steam_mat != null and steam_mat.albedo_texture is ImageTexture, "CookingSteam uses procedural radial puff ImageTexture")

	# 2. Verify ZERO raw primitives (BoxMesh/CylinderMesh/CapsuleMesh/SphereMesh/PrismMesh) anywhere under CookingStove.
	var primitive_hits := 0
	for child in stove.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			var m := mi.mesh
			if m is BoxMesh or m is CylinderMesh or m is CapsuleMesh or m is SphereMesh or m is PrismMesh:
				primitive_hits += 1
	check_eq(primitive_hits, 0, "CookingStove contains zero raw primitive meshes")

	# 3. Fish cooking lifecycle: raw -> golden cooked -> burnt (color, roughness, steam tint & mesh check).
	check(stove.place_food({"id": &"azure_snapper", "name": "Azure Snapper", "heal": 35.0}), "place fish onto skillet")
	check(food.visible and steam.emitting, "SizzlingFood visible & CookingSteam emitting while cooking fish")
	var fish_am := food.mesh as ArrayMesh
	check(fish_am != null and fish_am.get_surface_count() >= 1, "fish SizzlingFood has sculpted ArrayMesh surface")
	var fish_verts: PackedVector3Array = fish_am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(fish_verts.size() >= 180, "sculpted fish mesh is detailed flat-faceted geometry (%d verts)" % fish_verts.size())

	var fmat := food.material_override as StandardMaterial3D
	check(fmat != null and fmat.roughness < 0.45, "raw fish starts moist and glossy")
	var raw_col := fmat.albedo_color
	var steam_proc := steam.process_material as ParticleProcessMaterial
	var raw_ramp := (steam_proc.color_ramp as GradientTexture1D).gradient
	check(raw_ramp.colors[1].r > 0.85, "raw steam emits soft warm-white wisps")

	stove.step(CookingStove.COOK_TIME + 0.5)
	check_eq(stove.cook_state, &"cooked", "fish transitions to cooked")
	var cooked_col := fmat.albedo_color
	check(cooked_col.r > 0.75 and cooked_col.b < raw_col.b - 0.15, "cooked fish shifts to appetizing golden-brown glaze")

	stove.step(CookingStove.BURN_TIME - CookingStove.COOK_TIME + 1.0)
	check_eq(stove.cook_state, &"burnt", "fish transitions to burnt")
	check(fmat.albedo_color.r < 0.25 and fmat.roughness > 0.85, "burnt fish shifts to matte charred charcoal")
	var burnt_ramp := (steam_proc.color_ramp as GradientTexture1D).gradient
	check(burnt_ramp.colors[1].r < 0.25 and burnt_ramp.colors[1].a > 0.50, "burnt steam shifts to thicker dark charcoal smoke")

	var taken := stove.take_food()
	check_eq(taken["cooked_state"], &"burnt")
	check(not food.visible and not steam.emitting, "taking food hides SizzlingFood and stops CookingSteam")

	# 4. Crab cooking swaps to distinct sculpted Spiced Island Crab Claw / Shell ArrayMesh.
	check(stove.place_food({"id": &"island_crab_claw", "name": "Island Crab Claw", "heal": 45.0}), "place crab onto skillet")
	var crab_am := food.mesh as ArrayMesh
	check(crab_am != null and crab_am != fish_am, "crab item switches SizzlingFood to distinct sculpted crab ArrayMesh")
	var crab_verts: PackedVector3Array = crab_am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(crab_verts.size() >= 180, "sculpted crab mesh is detailed flat-faceted geometry (%d verts)" % crab_verts.size())
	stove.step(CookingStove.COOK_TIME + 0.5)
	check_eq(stove.cook_state, &"cooked", "crab transitions cleanly to cooked")

	# 5. Optional build_hearth = false skips stove hardware while retaining food + steam.
	var bare_pan := CookingStove.new()
	bare_pan.build_hearth = false
	add_child(bare_pan)
	check(bare_pan.get_node_or_null(^"GalleyHearth") == null, "build_hearth = false skips GalleyHearth")
	check(bare_pan.get_node_or_null(^"SizzlingFood") is MeshInstance3D, "build_hearth = false retains SizzlingFood")
	check(bare_pan.get_node_or_null(^"CookingSteam") is GPUParticles3D, "build_hearth = false retains CookingSteam")

	# 6. Verify sculpted stowed 3-joint bamboo fishing rod & carved oak/brass rail holder cleat from main.gd.
	var main_gd := load("res://scenes/main.gd") as GDScript
	check(main_gd != null, "loaded scenes/main.gd for stowed rod check")
	if main_gd != null:
		var stowed_rod := main_gd.call(&"_build_stowed_fishing_rod_mesh") as ArrayMesh
		var rod_origin := Vector3(0.02, 0.68, 0.24)
		var rod_basis := Basis.from_euler(Vector3(deg_to_rad(38.0), 0.0, deg_to_rad(8.0)))
		var rail_cleat := main_gd.call(&"_build_fishing_rail_cleat_mesh", rod_origin, rod_basis) as ArrayMesh
		check(stowed_rod != null and stowed_rod.get_surface_count() >= 2, "stowed FishingRodProp has bamboo/cork + brass hardware surfaces")
		var rod_aabb := stowed_rod.get_aabb()
		check(rod_aabb.size.y >= 1.9, "stowed bamboo rod spans ~2.0 m length (%.2f m)" % rod_aabb.size.y)
		check(rail_cleat != null and rail_cleat.get_surface_count() >= 2, "FishingRailCleat has carved oak + brass socket/cleat surfaces")
		var cleat_aabb := rail_cleat.get_aabb()
		check(cleat_aabb.position.y >= -0.02 and cleat_aabb.position.y <= 0.02, "FishingRailCleat rests firmly on deck at y = 0 (%.3f)" % cleat_aabb.position.y)

	# 7. Teardown while actively cooking frees all nodes & particle resources cleanly with zero leaks.
	stove.queue_free()
	bare_pan.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(stove) and not is_instance_valid(steam) and not is_instance_valid(hearth), "CookingStove, hearth, and CookingSteam freed with zero leaks")
	check(not is_instance_valid(bare_pan), "bare CookingStove freed cleanly")


