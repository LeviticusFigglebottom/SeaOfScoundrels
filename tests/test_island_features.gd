extends TestCase
## Headless contract tests for Wave 24B dynamic living island features:
##   - Live cliffside `IslandWaterfall` (`waterfall.gdshader`, parabolic sheet, plunge foam, mist, 240 m culling)
##   - Active `VolcanicFumarole` (sculpted obsidian chimney, magma throat, periodic geyser cycle, 190 m culling)

const WaterfallCls := preload("res://src/world/island_waterfall.gd")
const FumaroleCls := preload("res://src/world/island_fumarole.gd")


func test_island_waterfall_sculpted_shader_culling_and_zero_leaks() -> void:
	var root := Node3D.new()
	add_child(root)

	var wf := WaterfallCls.create(18.0, 4.5)
	root.add_child(wf)
	await physics_frames(1)

	check(wf.is_in_group(&"island_waterfalls"), "IslandWaterfall registers in island_waterfalls group")
	check(wf.waterfall_sheet != null and wf.plunge_pool_foam != null and wf.waterfall_mist != null,
		"IslandWaterfall builds WaterfallSheet, PlungePoolFoam, and WaterfallMist")

	var tris := wf.get_triangle_count()
	print("    IslandWaterfall sculpted tris: %d (sheet + plunge pool foam)" % tris)
	check(tris >= 200, "IslandWaterfall builds richly sculpted geometry (>= 200 tris, got %d)" % tris)

	# 1. Verify ZERO raw PrimitiveMeshes across every MeshInstance3D & GPUParticles3D, plus finite unit normals!
	var raw_prims := 0
	var bad_normals := 0
	for n in wf.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
		var am := mi.mesh as ArrayMesh
		check(am != null, "IslandWaterfall mesh '%s' uses sculpted ArrayMesh" % mi.name)
		if am != null:
			for si in am.get_surface_count():
				var norms: PackedVector3Array = am.surface_get_arrays(si)[Mesh.ARRAY_NORMAL]
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
	check(wf.waterfall_mist.draw_pass_1 is ArrayMesh and not (wf.waterfall_mist.draw_pass_1 is PrimitiveMesh),
		"WaterfallMist uses zero-primitive ArrayMesh billboard card")
	check_eq(raw_prims, 0, "IslandWaterfall contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "IslandWaterfall mesh normals are all finite unit vectors")

	# 2. Verify waterfall.gdshader binding & sRGB plunge foam material.
	var smat := wf.waterfall_sheet.material_override as ShaderMaterial
	check(smat != null and smat.shader == WaterfallCls.WATERFALL_SHADER,
		"WaterfallSheet binds waterfall.gdshader cleanly")
	var foam_mat := wf.plunge_pool_foam.material_override as StandardMaterial3D
	check(foam_mat != null and foam_mat.vertex_color_use_as_albedo and foam_mat.vertex_color_is_srgb,
		"PlungePoolFoam enables vertex_color_is_srgb = true")

	# 3. Verify explicit & camera distance culling toggle WaterfallMist cleanly!
	check(wf.waterfall_mist.emitting, "WaterfallMist emits while within distance range")
	wf.set_distance_active(false)
	check(not wf.waterfall_mist.emitting and not wf.waterfall_mist.visible,
		"set_distance_active(false) suspends WaterfallMist")
	wf.set_distance_active(true)
	check(wf.waterfall_mist.emitting and wf.waterfall_mist.visible,
		"set_distance_active(true) restores WaterfallMist")

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0.0, 0.0, 320.0)
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(not wf.waterfall_mist.emitting, "camera > 240 m auto-culls WaterfallMist")
	cam.global_position = Vector3(0.0, -6.0, -24.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(wf.waterfall_mist.emitting, "camera < 240 m auto-reactivates WaterfallMist")

	# 4. Zero-leak teardown releases all static caches cleanly to null!
	root.queue_free()
	await physics_frames(2)
	check_eq(WaterfallCls._active_waterfalls, 0, "all IslandWaterfalls exited cleanly")
	check(WaterfallCls._pool_foam_mesh == null and WaterfallCls._pool_foam_mat == null \
			and WaterfallCls._mist_tex == null and WaterfallCls._mist_mat == null \
			and WaterfallCls._mist_card_mesh == null,
		"IslandWaterfall releases all static pool & mist caches cleanly to null")


func test_volcanic_fumarole_sculpted_eruption_cycle_and_zero_leaks() -> void:
	var root := Node3D.new()
	add_child(root)

	var fum := FumaroleCls.create(1.2, 0.5)
	root.add_child(fum)
	await physics_frames(1)

	check(fum.is_in_group(&"volcanic_fumaroles"), "VolcanicFumarole registers in volcanic_fumaroles group")
	check(fum.chimney_mi != null and fum.steam_plume != null and fum.ember_sparks != null and fum.vent_light != null,
		"VolcanicFumarole builds FumaroleChimney, SteamPlume, EmberSparks, and VentLight")
	check(not fum.vent_light.shadow_enabled and is_equal_approx(fum.vent_light.omni_range, 10.0),
		"VentLight is shadowless with 10 m range")

	var tris := fum.get_triangle_count()
	print("    VolcanicFumarole sculpted chimney tris: %d" % tris)
	check(tris >= 120, "VolcanicFumarole builds sculpted basalt chimney (>= 120 tris, got %d)" % tris)

	# 1. Verify ZERO raw PrimitiveMeshes across chimney & both particle passes, finite unit normals & sRGB mats!
	check(fum.chimney_mi.mesh is ArrayMesh and not (fum.chimney_mi.mesh is PrimitiveMesh),
		"FumaroleChimney uses sculpted ArrayMesh")
	check(fum.steam_plume.draw_pass_1 is ArrayMesh and not (fum.steam_plume.draw_pass_1 is PrimitiveMesh),
		"SteamPlume uses zero-primitive ArrayMesh billboard card")
	check(fum.ember_sparks.draw_pass_1 is ArrayMesh and not (fum.ember_sparks.draw_pass_1 is PrimitiveMesh),
		"EmberSparks uses zero-primitive sculpted diamond ArrayMesh")

	var bad_normals := 0
	var am := fum.chimney_mi.mesh as ArrayMesh
	for si in am.get_surface_count():
		var norms: PackedVector3Array = am.surface_get_arrays(si)[Mesh.ARRAY_NORMAL]
		for nv in norms:
			if not nv.is_finite() or nv.length_squared() < 0.5:
				bad_normals += 1
		var smat := fum.chimney_mi.get_surface_override_material(si) as StandardMaterial3D
		check(smat != null and smat.vertex_color_use_as_albedo and smat.vertex_color_is_srgb,
			"FumaroleChimney surface %d uses sRGB vertex-colored material" % si)
	check_eq(bad_normals, 0, "FumaroleChimney normals are all finite unit vectors")

	# 2. Quiet simmering -> explicit trigger_eruption_pulse() -> subsides -> periodic auto-eruption!
	check(not fum.is_erupting(), "fumarole begins in quiet simmering phase")
	var idle_energy := fum.vent_light.light_energy
	check(not fum.ember_sparks.emitting, "EmberSparks stay idle between eruptions")

	fum.trigger_eruption_pulse()
	check(fum.is_erupting(), "trigger_eruption_pulse activates erupting state")
	check(fum.ember_sparks.emitting and fum.ember_sparks.visible, "EmberSparks burst during eruption pulse")
	check_near(fum.steam_plume.amount_ratio, 1.0, 0.01, "SteamPlume surges to full intensity during eruption")
	check(fum.vent_light.light_energy > idle_energy + 1.2,
		"VentLight surges warmly during eruption (%.2f > %.2f)" % [fum.vent_light.light_energy, idle_energy])

	# Step past the 2.0 s eruption pulse -> returns cleanly to simmering!
	fum.step_fumarole(2.2)
	check(not fum.is_erupting(), "eruption pulse subsides cleanly after 2.0 s")
	check(not fum.ember_sparks.emitting, "EmberSparks stop once eruption subsides")

	# Step through the periodic geyser cycle -> triggers next automatic eruption pulse!
	var saw_auto_eruption := false
	for _step in 20:
		fum.step_fumarole(0.5)
		if fum.is_erupting():
			saw_auto_eruption = true
			break
	check(saw_auto_eruption, "periodic volcanic cycle triggers automatic eruption pulse")

	# 3. Distance culling disables light & particles cleanly!
	fum.set_distance_active(false)
	check(not fum.vent_light.visible and not fum.steam_plume.emitting and not fum.ember_sparks.emitting,
		"set_distance_active(false) disables VentLight, SteamPlume & EmberSparks")

	# 4. Zero-leak teardown releases ALL static caches cleanly to null!
	root.queue_free()
	await physics_frames(2)
	check_eq(FumaroleCls._active_fumaroles, 0, "all VolcanicFumaroles exited cleanly")
	check(FumaroleCls._chimney_mesh == null and FumaroleCls._rock_mat == null \
			and FumaroleCls._throat_mat == null and FumaroleCls._steam_tex == null \
			and FumaroleCls._steam_mat == null and FumaroleCls._steam_card_mesh == null \
			and FumaroleCls._ember_diamond_mesh == null and FumaroleCls._ember_mat == null,
		"VolcanicFumarole releases all static chimney, steam & ember caches cleanly to null")
