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


func test_q12b_cooking_hearth_halo_sizzle_motes_and_fishing_ripples_night_lure() -> void:
	Net.start_single_player()
	var saved_tod := Weather.time_of_day

	# --- 1. CookingStove (build_hearth = true): HearthFireHalo & SkilletSizzleMotes ---
	var stove := CookingStove.new()
	add_child(stove)

	var halo := stove.get_hearth_halo_node()
	check(halo != null and halo.name == &"HearthFireHalo", "CookingStove (build_hearth = true) mounts HearthFireHalo")
	check(halo.mesh is ArrayMesh, "HearthFireHalo uses sculpted procedural ArrayMesh")
	check_eq(halo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "HearthFireHalo has cast_shadow OFF")
	check(halo.position.distance_to(Vector3(-0.30, 0.30, 0.0)) < 0.01, "HearthFireHalo sits at -X firebox grate")
	var halo_am := halo.mesh as ArrayMesh
	var halo_arr := halo_am.surface_get_arrays(0)
	var halo_verts: PackedVector3Array = halo_arr[Mesh.ARRAY_VERTEX]
	var halo_norms: PackedVector3Array = halo_arr[Mesh.ARRAY_NORMAL]
	var halo_cols: PackedColorArray = halo_arr[Mesh.ARRAY_COLOR]
	check(halo_verts.size() >= 48, "HearthFireHalo has 16-wedge radial geometry (%d verts)" % halo_verts.size())
	check_eq(halo_norms.size(), halo_verts.size(), "HearthFireHalo carries explicit vertex normals")
	var halo_norms_ok := true
	var halo_has_black_rim := false
	for i in halo_norms.size():
		var n := halo_norms[i]
		if not n.is_finite() or absf(n.length() - 1.0) > 0.01 or n.z < 0.99:
			halo_norms_ok = false
			break
		if halo_cols[i].r < 0.01 and halo_cols[i].g < 0.01 and halo_cols[i].b < 0.01:
			halo_has_black_rim = true
	check(halo_norms_ok, "HearthFireHalo normals are all finite unit (0,0,1)")
	check(halo_has_black_rim, "HearthFireHalo fades cleanly to black at rim")
	var halo_mat := halo.material_override as StandardMaterial3D
	check(halo_mat != null and halo_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "HearthFireHalo uses additive blending")
	check(halo_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED and halo_mat.billboard_keep_scale, "HearthFireHalo uses scale-preserving billboard")
	check(halo_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and halo_mat.vertex_color_is_srgb, "HearthFireHalo disables depth draw & uses sRGB vertex colors")

	var motes := stove.get_sizzle_motes_node()
	check(motes != null and motes.name == &"SkilletSizzleMotes", "CookingStove mounts SkilletSizzleMotes MultiMeshInstance3D")
	check_eq(motes.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "SkilletSizzleMotes has cast_shadow OFF")
	check(motes.multimesh != null and motes.multimesh.instance_count == 14, "SkilletSizzleMotes has 14 instances")
	check(motes.multimesh.mesh is ArrayMesh, "SkilletSizzleMotes uses sculpted diamond ArrayMesh")
	var mote_verts: PackedVector3Array = (motes.multimesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check_eq(mote_verts.size(), 24, "SkilletSizzleMotes diamond mesh has exact 8 triangles (24 flat verts)")
	check(not motes.visible, "SkilletSizzleMotes stays hidden when stove is empty")

	# Verify ZERO raw primitives anywhere under CookingStove (MeshInstance3D & MultiMeshInstance3D).
	var stove_prims := 0
	for child in stove.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			var m := mi.mesh
			if m is BoxMesh or m is CylinderMesh or m is CapsuleMesh or m is SphereMesh or m is PrismMesh:
				stove_prims += 1
	check_eq(stove_prims, 0, "CookingStove still contains zero raw primitive meshes after Q12B")

	# Place food -> raw -> cooked -> burnt: verify distinct colors, rising height bands, and golden sheen pulse!
	check(stove.place_food({"id": &"azure_snapper", "name": "Azure Snapper", "heal": 35.0}), "place fish activates sizzle motes")
	stove.step(0.25)
	check(motes.visible, "SkilletSizzleMotes activates on place_food()")
	var col_raw := stove.get_sizzle_mode_color()
	var raw_pts := stove.get_sizzle_mote_positions()
	check_eq(raw_pts.size(), 14, "14 sizzle mote positions tracked")
	var raw_max_y := -1.0
	var raw_sum_y := 0.0
	for p in raw_pts:
		raw_max_y = maxf(raw_max_y, p.y)
		raw_sum_y += p.y
	var raw_mean_y := raw_sum_y / float(raw_pts.size())
	check(col_raw.b > 0.70, "raw sizzle droplets have warm-cream tint (b=%.2f)" % col_raw.b)
	check(raw_max_y >= 0.14 and raw_max_y <= 0.25, "raw sizzle droplets dance low 0.02..0.24 m (max=%.3f)" % raw_max_y)
	if DisplayServer.get_name() != "headless":
		check(motes.multimesh.get_instance_transform(0).origin.distance_to(raw_pts[0]) < 0.001, "GPU MultiMesh transform matches cached mote position")

	stove.step(CookingStove.COOK_TIME + 0.5)
	check_eq(stove.cook_state, &"cooked", "stove reaches cooked state")
	var col_cooked := stove.get_sizzle_mode_color()
	var cooked_pts := stove.get_sizzle_mote_positions()
	var cooked_max_y := -1.0
	var cooked_sum_y := 0.0
	for p in cooked_pts:
		cooked_max_y = maxf(cooked_max_y, p.y)
		cooked_sum_y += p.y
	var cooked_mean_y := cooked_sum_y / float(cooked_pts.size())
	check(col_cooked.r > 0.90 and col_cooked.g > 0.70 and col_cooked.b < 0.40, "cooked motes shift to savory gold (%.2f, %.2f, %.2f)" % [col_cooked.r, col_cooked.g, col_cooked.b])
	check(cooked_max_y > raw_max_y + 0.12 and cooked_mean_y > raw_mean_y + 0.08, "cooked golden aroma motes drift noticeably higher than raw (%.3f -> %.3f)" % [raw_max_y, cooked_max_y])
	var food_mi := stove.get_node_or_null(^"SizzlingFood") as MeshInstance3D
	var food_mat := (food_mi.material_override as StandardMaterial3D) if food_mi != null else null
	check(food_mat != null and food_mat.emission_enabled and food_mat.emission_energy_multiplier > 0.10, "cooked food shows gentle golden sheen glow pulse")

	stove.step(CookingStove.BURN_TIME - CookingStove.COOK_TIME + 1.0)
	check_eq(stove.cook_state, &"burnt", "stove reaches burnt state")
	var col_burnt := stove.get_sizzle_mode_color()
	var burnt_pts := stove.get_sizzle_mote_positions()
	var burnt_max_y := -1.0
	var burnt_sum_y := 0.0
	for p in burnt_pts:
		burnt_max_y = maxf(burnt_max_y, p.y)
		burnt_sum_y += p.y
	var burnt_mean_y := burnt_sum_y / float(burnt_pts.size())
	check(col_burnt.r > 0.90 and col_burnt.g < 0.45 and col_burnt.b < 0.15, "burnt motes shift to urgent orange-red burn warning embers (%.2f, %.2f, %.2f)" % [col_burnt.r, col_burnt.g, col_burnt.b])
	check(burnt_max_y > cooked_max_y + 0.08 and burnt_mean_y > cooked_mean_y + 0.05, "burnt embers shoot higher than cooked aroma motes (%.3f -> %.3f)" % [cooked_max_y, burnt_max_y])
	check(food_mat != null and not food_mat.emission_enabled, "burnt food clears golden sheen emission")

	stove.take_food()
	check(not motes.visible, "taking food hides SkilletSizzleMotes")

	# Bare-pan & campfire-tripod modes: no HearthFireHalo, SkilletSizzleMotes hidden when empty, zero raw primitives.
	var bare_pan := CookingStove.new()
	bare_pan.build_hearth = false
	add_child(bare_pan)
	check(bare_pan.get_hearth_halo_node() == null and bare_pan.get_node_or_null(^"HearthFireHalo") == null, "bare-pan CookingStove has no HearthFireHalo")
	check(bare_pan.get_sizzle_motes_node() != null and not bare_pan.get_sizzle_motes_node().visible, "bare-pan SkilletSizzleMotes stays hidden when empty")

	var tripod := CookingStove.new()
	tripod.build_hearth = false
	tripod.build_campfire_tripod = true
	add_child(tripod)
	check(tripod.get_hearth_halo_node() == null, "campfire-tripod CookingStove skips HearthFireHalo")
	check(tripod.get_sizzle_motes_node() != null and tripod.get_sizzle_motes_node().position.distance_to(CookingStove.TRIPOD_STEAM_POS) < 0.01, "campfire-tripod SkilletSizzleMotes sits cleanly above hanging skillet")

	# --- 2. FishingLine: BobberRippleRings & NightLureHalo ---
	var rod := FishingLine.new()
	add_child(rod)

	var ripples := rod.get_bobber_ripples_node()
	var night_lure := rod.get_night_lure_halo_node()
	check(ripples != null and ripples.name == &"BobberRippleRings", "FishingLine builds BobberRippleRings")
	check(ripples.top_level and ripples.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "BobberRippleRings is top_level and shadowless")
	check(ripples.mesh is ArrayMesh, "BobberRippleRings uses sculpted zero-primitive ArrayMesh")
	var rip_arr := (ripples.mesh as ArrayMesh).surface_get_arrays(0)
	var rip_norms: PackedVector3Array = rip_arr[Mesh.ARRAY_NORMAL]
	check(rip_norms.size() >= 144, "BobberRippleRings builds 2 concentric beveled rings (%d verts)" % rip_norms.size())
	var rip_norms_ok := true
	for n in rip_norms:
		if not n.is_finite() or absf(n.length() - 1.0) > 0.01 or n.y < 0.99:
			rip_norms_ok = false
			break
	check(rip_norms_ok, "BobberRippleRings normals are all finite upward unit (0,1,0)")

	check(night_lure != null and night_lure.name == &"NightLureHalo", "FishingLine builds NightLureHalo")
	check(night_lure.get_parent() != null and night_lure.get_parent().name == &"Bobber", "NightLureHalo attaches directly to Bobber")
	check(night_lure.position.distance_to(Vector3(0.0, FishingLine.BOBBER_SWIVEL_Y, 0.0)) < 0.005, "NightLureHalo sits at BOBBER_SWIVEL_Y")
	check(night_lure.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and night_lure.mesh is ArrayMesh, "NightLureHalo is shadowless sculpted ArrayMesh")
	var nl_mat := night_lure.material_override as StandardMaterial3D
	check(nl_mat != null and nl_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and nl_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED and nl_mat.billboard_keep_scale, "NightLureHalo uses additive scale-preserving billboard")
	check(not ripples.visible and not night_lure.visible, "BobberRippleRings and NightLureHalo hidden in State.IDLE")

	# Cast line at midday first -> ripples visible & expanding calmly, night lure very dim.
	Weather.time_of_day = 12.5
	check(rod.cast_line(Vector3.ZERO, Vector3.FORWARD, 10.0), "cast_line succeeds for Q12B test")
	check(ripples.visible, "BobberRippleRings visible on cast_line()")
	var s_init := rod.get_ripple_scale()
	var noon_lure := rod.get_night_lure_intensity()
	var expected_y := Sea.height(rod.bobber_pos.x, rod.bobber_pos.z) + 0.035
	check(absf(ripples.global_position.y - expected_y) < 0.02, "BobberRippleRings floats smoothly at Sea.height + 0.035")

	rod.step(0.30, Vector3.ZERO, false)
	var s_wait := rod.get_ripple_scale()
	check(s_wait > s_init + 0.12 and s_wait <= 1.36, "WAITING ripples expand calmly over step() (%.2f -> %.2f)" % [s_init, s_wait])

	# Compare nocturnal lure brightness at midnight (0.5) vs noon (12.5)!
	Weather.time_of_day = 0.5
	rod.step(0.05, Vector3.ZERO, false)
	var midnight_lure := rod.get_night_lure_intensity()
	check(midnight_lure > noon_lure * 4.0 and midnight_lure > 0.80, "NightLureHalo glows dramatically brighter at midnight (%.2f) than noon (%.2f)" % [midnight_lure, noon_lure])

	# Trigger bite (HOOKED & fish_fighting) -> ripples surge 2.6x faster and wider!
	rod._bite_timer = 0.01
	rod.step(0.05, Vector3.ZERO, false)
	check_eq(rod.state, FishingLine.State.HOOKED, "fish bites cleanly")
	rod.fish_fighting = true
	rod._fight_timer = 5.0
	rod.step(0.30, Vector3.ZERO, false)
	var s_fight := rod.get_ripple_scale()
	var hooked_midnight_lure := rod.get_night_lure_intensity()
	check(s_fight > s_wait + 0.35 and s_fight <= 2.16, "HOOKED fighting ripples surge faster & wider than WAITING (wait=%.2f, fight=%.2f)" % [s_wait, s_fight])
	check(hooked_midnight_lure > midnight_lure * 1.15, "NightLureHalo surges extra bright during a hooked bite (%.2f -> %.2f)" % [midnight_lure, hooked_midnight_lure])

	# cancel_cast() cleanly hides ripples & night lure.
	rod.cancel_cast()
	check(not ripples.visible and not night_lure.visible, "cancel_cast() hides BobberRippleRings and NightLureHalo")
	check_near(rod.get_ripple_scale(), 0.0, 0.001)
	check_near(rod.get_night_lure_intensity(), 0.0, 0.001)

	# Restore Weather.time_of_day and verify full teardown leaves 0 ObjectDB leaks!
	Weather.time_of_day = saved_tod
	stove.queue_free()
	bare_pan.queue_free()
	tripod.queue_free()
	rod.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(stove) and not is_instance_valid(halo) and not is_instance_valid(motes), "CookingStove + Q12B hearth halo & sizzle motes freed cleanly")
	check(not is_instance_valid(bare_pan) and not is_instance_valid(tripod), "bare-pan and campfire-tripod stoves freed cleanly")
	check(not is_instance_valid(rod) and not is_instance_valid(ripples) and not is_instance_valid(night_lure), "FishingLine + Q12B ripples & night lure halo freed cleanly")



