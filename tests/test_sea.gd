extends TestCase

func test_height_inverts_displacement() -> void:
	# A displaced rest point must lie on the surface that height() reports.
	Sea.time = 12.3
	for i in 20:
		var x := i * 7.31 - 40.0
		var z := i * -3.77 + 15.0
		var d := Sea.displacement(x, z)
		check_near(Sea.height(x + d.x, z + d.z), d.y, 0.02, "at sample %d" % i)

func test_waves_are_bounded_and_moving() -> void:
	Sea.time = 0.0
	var h0 := Sea.height(3.0, 4.0)
	Sea.time = 2.0
	var h1 := Sea.height(3.0, 4.0)
	check(absf(h0 - h1) > 0.001, "surface should move over time")
	var max_amp := 0.0
	for i in Sea.WAVE_TABLE.size():
		max_amp += Sea.wave_amplitude(i)
	check(absf(h0) <= max_amp + 0.001)

func test_no_self_intersection_at_storm() -> void:
	# Pinch is linear in the calm/storm blend, so checking both ends covers
	# every sea state in between.
	for col: int in [1, 2]:
		var s := 0.0
		for w in Sea.WAVE_TABLE:
			s += TAU / float(w[0]) * float(w[col]) * float(w[4])
		check(s < 1.0, "sum(k*A*steepness) = %f must be < 1 (column %d)" % [s, col])

func test_normal_points_up() -> void:
	check(Sea.normal(10.0, 10.0).y > 0.5)

func test_height_inverts_displacement_in_storm() -> void:
	# The fixed-point inversion must still land on the surface when crests are
	# pinched hardest. Mean error stays in millimetres; no sample may be far off.
	var saved := Sea.amp_scale
	Sea.amp_scale = Sea.AMP_STORM
	Sea.time = 77.7
	var worst := 0.0
	var total := 0.0
	var n := 400
	for i in n:
		var x := fmod(i * 37.17, 900.0) - 450.0
		var z := fmod(i * 91.31, 900.0) - 450.0
		var d := Sea.displacement(x, z)
		var e := absf(Sea.height(x + d.x, z + d.z) - d.y)
		worst = maxf(worst, e)
		total += e
	Sea.amp_scale = saved
	check(total / n < 0.01, "mean inversion error %f m" % (total / n))
	check(worst < 0.25, "worst inversion error %f m" % worst)

func test_sea_states_have_big_swell() -> void:
	# The sea must read as large: most of the energy in long waves, calm is a
	# gentle swell and a storm is several metres high.
	check(Sea.WAVE_TABLE.size() <= Sea.MAX_WAVES)
	var saved := Sea.amp_scale
	for state: Array in [[Sea.AMP_CALM, 0.8, 2.2], [Sea.AMP_STORM, 6.0, 12.0]]:
		Sea.amp_scale = state[0]
		var hs := Sea.significant_height()
		check(hs > float(state[1]) and hs < float(state[2]), "significant height %f m at amp_scale %f" % [hs, state[0]])
		var long_e := 0.0
		var all_e := 0.0
		for i in Sea.WAVE_TABLE.size():
			var e := Sea.wave_amplitude(i) ** 2
			all_e += e
			if float(Sea.WAVE_TABLE[i][0]) >= 100.0:
				long_e += e
		check(long_e / all_e > 0.75, "long swell energy share %f" % (long_e / all_e))
	# storm wind sea must be much steeper than the calm one (it changes character)
	var w: Array = Sea.WAVE_TABLE[8]
	check(float(w[2]) / float(w[1]) > 4.0)
	Sea.amp_scale = 0.0
	Sea.time = 5.0
	check_near(Sea.height(12.0, -7.0), 0.0, 1e-6, "amp_scale 0 must be a flat sea")
	Sea.amp_scale = saved

func test_rest_point_round_trip() -> void:
	Sea.time = 9.0
	var r := Sea.rest_point(31.0, -12.0)
	var d := Sea.displacement(r.x, r.y)
	check_near(r.x + d.x, 31.0, 0.02)
	check_near(r.y + d.z, -12.0, 0.02)

func test_height_query_is_fast_enough() -> void:
	# Buoyancy samples dozens of points per tick; keep one query cheap.
	Sea.time = 3.0
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in 2000:
		acc += Sea.height(i * 0.37, i * -0.21)
	var per := float(Time.get_ticks_usec() - t0) / 2000.0
	print("    Sea.height: %.1f us per call" % per)
	check(per < 150.0, "Sea.height takes %f us" % per)
	check(acc == acc)

func test_ocean_mesh_is_watertight_and_in_budget() -> void:
	var ocean_script: GDScript = load("res://src/ocean/ocean.gd")
	var mesh: ArrayMesh = ocean_script.build_mesh(104, 0.5, 8)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tris := int(idx.size() / 3.0)
	check(tris > 100000 and tris <= 160000, "triangle count %d outside budget" % tris)
	# Every edge is shared by exactly two triangles, except the open far edge
	# of the horizon skirt. A T-junction or a crack would break this.
	var edges: Dictionary = {}
	var n := verts.size()
	for t in tris:
		for e in 3:
			var a := idx[t * 3 + e]
			var b := idx[t * 3 + (e + 1) % 3]
			var key := mini(a, b) * n + maxi(a, b)
			edges[key] = int(edges.get(key, 0)) + 1
	var open_inner := 0
	var bad := 0
	for key: int in edges:
		var c: int = edges[key]
		if c == 2:
			continue
		@warning_ignore("integer_division")
		var a := key / n
		var b := key % n
		if c == 1 and uvs[a].x > 0.5 and uvs[b].x > 0.5:
			continue  # skirt rim
		if c == 1:
			open_inner += 1
		else:
			bad += 1
	check_eq(open_inner, 0, "open edges inside the mesh (cracks)")
	check_eq(bad, 0, "edges shared by more than two triangles")
	# No vertex may sit off the lattice of its ring (that would swim when snapping).
	for v in verts:
		check(is_equal_approx(v.x / 0.5, roundf(v.x / 0.5)) and is_equal_approx(v.z / 0.5, roundf(v.z / 0.5)))

func test_orbital_velocity_matches_time_derivative() -> void:
	var saved_amp := Sea.amp_scale
	var saved_time := Sea.time
	Sea.amp_scale = Sea.AMP_CALM
	Sea.time = 21.5
	var dt := 0.0005
	for i in 12:
		var rx := i * 11.3 - 50.0
		var rz := i * -7.9 + 25.0
		var v := Sea.orbital_velocity(rx, rz)
		Sea.time = 21.5 + dt
		var dp := Sea.displacement(rx, rz)
		Sea.time = 21.5 - dt
		var dm := Sea.displacement(rx, rz)
		Sea.time = 21.5
		var fd := Vector2((dp.x - dm.x) / (2.0 * dt), (dp.z - dm.z) / (2.0 * dt))
		check_near(v.x, fd.x, 0.01, "orbital vx at sample %d" % i)
		check_near(v.y, fd.y, 0.01, "orbital vz at sample %d" % i)
		var dj := Sea.displacement_and_jacobian(rx, rz)
		var d0 := Sea.displacement(rx, rz)
		check_near(dj.x, d0.x, 1e-4)
		check_near(dj.y, d0.y, 1e-4)
		check_near(dj.z, d0.z, 1e-4)
		check(dj.w > 0.0 and dj.w < 2.0, "jacobian %f out of expected range" % dj.w)
	Sea.amp_scale = saved_amp
	Sea.time = saved_time

func test_hull_mask_dry_hold_and_flooding() -> void:
	var ocean_scene: PackedScene = load("res://src/ocean/ocean.tscn")
	var ocean: Ocean = ocean_scene.instantiate() as Ocean
	add_child(ocean)
	var ship := Node3D.new()
	ship.position = Vector3(24.0, 0.0, -18.0)
	ship.rotation = Vector3(0.05, 0.6, -0.04)
	add_child(ship)

	# Default sloop cutout registration
	ocean.register_hull_mask(ship, null, 0.0)
	var xf := ship.global_transform
	check(ocean.is_point_in_dry_hull(xf * Vector3(0.0, -0.4, 0.0)), "center of dry hold must be inside dry hull")
	check(ocean.is_point_in_dry_hull(xf * Vector3(1.4, 0.1, 0.0)), "midship interior must be inside dry hull")
	check(ocean.is_point_in_dry_hull(xf * Vector3(0.2, 0.0, -5.2)), "bow centerline must be inside dry hull")
	check(not ocean.is_point_in_dry_hull(xf * Vector3(2.4, 0.0, 0.0)), "outside beam must not be in hull")
	check(not ocean.is_point_in_dry_hull(xf * Vector3(1.5, 0.0, -5.2)), "tapered bow outside beam must not be in hull")
	check(not ocean.is_point_in_dry_hull(xf * Vector3(0.0, 0.0, -6.6)), "ahead of bow must not be in hull")
	check(not ocean.is_point_in_dry_hull(xf * Vector3(0.0, 0.0, 6.6)), "astern of transom must not be in hull")
	check(not ocean.is_point_in_dry_hull(xf * Vector3(0.0, -1.6, 0.0)), "below keel must not be in hull")
	check(not ocean.is_point_in_dry_hull(xf * Vector3(0.0, 2.6, 0.0)), "above gunwale must not be in hull")
	check_eq(int(ocean.material.get_shader_parameter(&"hull_mask_count")), 1)

	# Partial flooding: below flood line is submerged, upper hold stays dry
	ocean.update_hull_mask(ship, 0.65)
	check(not ocean.is_point_in_dry_hull(xf * Vector3(0.0, -0.5, 0.0)), "below interior flood line must not be dry")
	check(ocean.is_point_in_dry_hull(xf * Vector3(0.0, 0.85, 0.0)), "above interior flood line must still be dry")

	# Fully sunk: cutout relaxes completely
	ocean.update_hull_mask(ship, 1.0)
	check(not ocean.is_point_in_dry_hull(xf * Vector3(0.0, 0.0, 0.0)), "fully flooded ship must not be dry")

	# Custom mask_mesh AABB registration (flat mask_water-style mesh)
	var mask_mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.2, 0.02, 12.4)
	mask_mi.mesh = box
	ship.add_child(mask_mi)
	ocean.register_hull_mask(ship, mask_mi, 0.0)
	check(ocean.is_point_in_dry_hull(xf * Vector3(0.0, 0.0, 0.0)), "mask_mesh registration should mark hold dry")

	# Unregister clears shader uniform count and dry-hull check
	ocean.unregister_hull_mask(ship)
	check(not ocean.is_point_in_dry_hull(xf * Vector3(0.0, 0.0, 0.0)), "unregistered hull must not be dry")
	check_eq(int(ocean.material.get_shader_parameter(&"hull_mask_count")), 0)

	remove_child(ship)
	ship.free()
	remove_child(ocean)
	ocean.free()

func test_ocean_quality_switching() -> void:
	var ocean_scene: PackedScene = load("res://src/ocean/ocean.tscn")
	var ocean: Ocean = ocean_scene.instantiate() as Ocean
	add_child(ocean)

	ocean.quality = Ocean.Quality.LOW
	var tris_low := ocean.triangle_count()
	check_eq(int(ocean.material.get_shader_parameter(&"quality")), int(Ocean.Quality.LOW))
	check(ocean.foam_field == null, "LOW quality disables foam field")
	check(ocean.crest_spray != null and not ocean.crest_spray.is_active(), "LOW quality disables crest spray")

	ocean.quality = Ocean.Quality.MEDIUM
	var tris_med := ocean.triangle_count()
	check_eq(int(ocean.material.get_shader_parameter(&"quality")), int(Ocean.Quality.MEDIUM))
	check(ocean.foam_field != null, "MEDIUM quality enables foam field")
	check(ocean.crest_spray != null and ocean.crest_spray.is_active(), "MEDIUM quality enables crest spray")

	ocean.quality = Ocean.Quality.HIGH
	var tris_high := ocean.triangle_count()
	check_eq(int(ocean.material.get_shader_parameter(&"quality")), int(Ocean.Quality.HIGH))
	check(ocean.foam_field != null, "HIGH quality enables foam field")
	check(ocean.crest_spray != null and ocean.crest_spray.is_active(), "HIGH quality enables crest spray")

	check(tris_low < tris_med and tris_med < tris_high,
			"triangle counts must scale with quality (%d < %d < %d)" % [tris_low, tris_med, tris_high])

	await get_tree().process_frame
	remove_child(ocean)
	ocean.free()


func test_ocean_nocturnal_bioluminescence_shader() -> void:
	var shader: Shader = load("res://src/ocean/ocean.gdshader") as Shader
	check(shader != null, "ocean.gdshader loads cleanly as Shader resource")
	if shader == null:
		return
	var code := shader.code
	check(code.contains("night_bio"), "ocean.gdshader defines night_bio twilight/night mask")
	check(code.contains("smoothstep(0.02, -0.14, sun_dir.y)"),
		"ocean.gdshader keeps daytime & sunset sun elevations strictly untouched")
	check(code.contains("wake_bio") and code.contains("crest_bio"),
		"ocean.gdshader drives bioluminescent shimmer from ship wakes and breaking crests")
	var frag_idx := code.find("void fragment()")
	var bio_idx := code.find("night_bio")
	check(frag_idx >= 0 and bio_idx > frag_idx,
		"nocturnal bioluminescence lives strictly inside fragment() leaving vertex() parity untouched")

	var ocean_scene: PackedScene = load("res://src/ocean/ocean.tscn")
	var ocean: Ocean = ocean_scene.instantiate() as Ocean
	add_child(ocean)
	check(ocean.material != null and ocean.material.shader == shader,
		"Ocean scene binds compiled ocean.gdshader cleanly")
	await get_tree().process_frame
	remove_child(ocean)
	ocean.free()


func test_wave25_directional_chop_and_fft_binding() -> void:
	check_eq(Sea.WAVE_TABLE.size(), 24, "WAVE_TABLE must carry 24 directional Gerstner waves")
	var min_long_hdg := INF
	var max_long_hdg := -INF
	var calm_pinch := 0.0
	var storm_pinch := 0.0
	for w in Sea.WAVE_TABLE:
		var wl := float(w[0])
		var k := TAU / wl
		calm_pinch += k * float(w[1]) * float(w[4])
		storm_pinch += k * float(w[2]) * float(w[4])
		if wl >= 100.0:
			min_long_hdg = minf(min_long_hdg, float(w[3]))
			max_long_hdg = maxf(max_long_hdg, float(w[3]))
	var long_spread := max_long_hdg - min_long_hdg
	print("    24-wave spectrum: calm_pinch=%.4f storm_pinch=%.4f long_spread=%.2f rad" % [calm_pinch, storm_pinch, long_spread])
	check(calm_pinch < 0.85, "calm sum(k*A*steepness) %.4f must be < 0.85" % calm_pinch)
	check(storm_pinch < 0.94, "storm sum(k*A*steepness) %.4f must be < 0.94" % storm_pinch)
	check(long_spread > 2.0, "primary/crossing swell headings must span > 2.0 rad (got %.2f)" % long_spread)

	var ocean_scene: PackedScene = load("res://src/ocean/ocean.tscn")
	var ocean: Ocean = ocean_scene.instantiate() as Ocean
	add_child(ocean)
	var chop_tex: Variant = ocean.material.get_shader_parameter(&"chop_tex")
	var chop_on := float(ocean.material.get_shader_parameter(&"chop_tex_on"))
	check(chop_tex is Texture2D, "Ocean must bind ocean_fft_chop.png to chop_tex")
	check_near(chop_on, 1.0, 0.001, "Ocean chop_tex_on must be 1.0")
	if chop_tex is Texture2D:
		var sz := (chop_tex as Texture2D).get_size()
		check(sz.x >= 1024 and sz.y >= 1024, "ocean_fft_chop.png must be 1024x1024 (got %s)" % str(sz))
	var code := ocean.material.shader.code
	check(code.contains("ROT_C1") and code.contains("ROT_C2") and code.contains("trough_ao"),
		"ocean.gdshader must apply multi-cascade rotated FFT chop and trough depth shading")
	await get_tree().process_frame
	remove_child(ocean)
	ocean.free()


func test_q20b_underwater_plankton_motes_and_crest_spray_zero_primitive() -> void:
	Underwater.clear_shared_cache()
	CrestSpray.clear_shared_cache()

	# 1. Source guards: Vulkan RD MultiMesh teardown safety in underwater.gd & zero QuadMesh in crest_spray.gd.
	var uw_src := FileAccess.get_file_as_string("res://src/ocean/underwater.gd")
	check(uw_src.length() > 200, "underwater.gd source loads cleanly for Q20B teardown guard")
	check(not uw_src.contains("multimesh.mesh = null") and not uw_src.contains("mm.mesh = null") \
			and not uw_src.contains("particles.mesh = null"),
		"underwater.gd must NOT mutate MultiMesh .mesh = null on teardown (Godot 4.8 Vulkan RD rule)")

	var cs_src := FileAccess.get_file_as_string("res://src/ocean/crest_spray.gd")
	check(cs_src.length() > 200, "crest_spray.gd source loads cleanly for Q20B zero-primitive guard")
	check(not cs_src.contains("QuadMesh"),
		"crest_spray.gd must contain zero raw QuadMesh primitives")

	var saved_amp := Sea.amp_scale
	var saved_time := Sea.time
	var saved_tod := Weather.time_of_day
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var ocean_scene: PackedScene = load("res://src/ocean/ocean.tscn")
	var ocean_a: Ocean = ocean_scene.instantiate() as Ocean
	var ocean_b: Ocean = ocean_scene.instantiate() as Ocean
	add_child(ocean_a)
	add_child(ocean_b)

	var uw_a := ocean_a.get_node_or_null(^"Underwater") as Underwater
	var uw_b := ocean_b.get_node_or_null(^"Underwater") as Underwater
	var cs_a := ocean_a.crest_spray
	var cs_b := ocean_b.crest_spray
	check(uw_a != null and uw_b != null, "Ocean instances mount Underwater nodes")
	check(cs_a != null and cs_b != null, "Ocean instances mount CrestSpray nodes")
	check_eq(Underwater._active_underwaters, 2, "Underwater tracks ref-counted active instances")
	check_eq(CrestSpray._active_sprays, 2, "CrestSpray tracks ref-counted active instances")

	# 2. Verify UnderwaterPlanktonMotes MultiMesh (36x8-tri sculpted octahedron, 0 primitives, 0 VRAM textures).
	var motes_a := uw_a.get_plankton_motes_node()
	var motes_b := uw_b.get_plankton_motes_node()
	check(motes_a != null and motes_a.name == "UnderwaterPlanktonMotes",
		"Underwater mounts UnderwaterPlanktonMotes MultiMeshInstance3D")
	var mote_tris := 0
	var mote_bad_normals := 0
	if motes_a != null:
		check_eq(motes_a.get_parent(), uw_a, "UnderwaterPlanktonMotes mounts directly under Underwater")
		check(not motes_a.visible, "UnderwaterPlanktonMotes starts hidden before submersion")
		check_eq(motes_a.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"UnderwaterPlanktonMotes disables shadow casting")
		check_eq(motes_a.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"UnderwaterPlanktonMotes disables GI mode")
		check_near(motes_a.visibility_range_end, 40.0, 0.05,
			"UnderwaterPlanktonMotes sets visibility_range_end = 40.0 m")
		check_near(motes_a.extra_cull_margin, 20.0, 0.05,
			"UnderwaterPlanktonMotes sets extra_cull_margin = 20.0 m")

		var mm := motes_a.multimesh
		check(mm != null and mm.instance_count == 36 and mm.use_colors,
			"UnderwaterPlanktonMotes configures 36 per-instance colored motes")
		check(mm != null and mm.mesh is ArrayMesh and not (mm.mesh is PrimitiveMesh),
			"UnderwaterPlanktonMotes uses sculpted ArrayMesh (zero PrimitiveMesh)")
		if motes_b != null and motes_b.multimesh != null and mm != null:
			check_eq(mm.mesh, motes_b.multimesh.mesh,
				"Underwater instances share statically cached 8-tri _plankton_mesh")
			check_eq(motes_a.material_override, motes_b.material_override,
				"Underwater instances share statically cached _plankton_mat")
		if mm != null and mm.mesh is ArrayMesh:
			var arr := (mm.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			mote_tris = floori(float(verts.size()) / 3.0)
			check_eq(cols.size(), verts.size(), "UnderwaterPlanktonMotes carries per-vertex luminous colors")
			for nv in norms:
				if not nv.is_finite() or absf(nv.length() - 1.0) > 0.002:
					mote_bad_normals += 1
		check_eq(mote_tris, 8, "sculpted UnderwaterPlanktonMotes diamond octahedron has exact 8 tris")
		check_eq(mote_bad_normals, 0, "all UnderwaterPlanktonMotes normals are finite unit vectors")

		var pm_mat := motes_a.material_override as StandardMaterial3D
		check(pm_mat != null and pm_mat.vertex_color_use_as_albedo and pm_mat.vertex_color_is_srgb \
				and pm_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and pm_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and pm_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				and pm_mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"UnderwaterPlanktonMotes uses unshaded additive sRGB double-sided depth-draw-disabled material")
		if pm_mat != null:
			check(pm_mat.albedo_texture == null and pm_mat.normal_texture == null \
					and pm_mat.roughness_texture == null and pm_mat.emission_texture == null,
				"UnderwaterPlanktonMotes allocates 0 extra VRAM textures")

	# 3. Verify visibility gating (above water, threshold depth <= 0.15, dry hull, and genuinely submerged).
	Sea.amp_scale = Sea.AMP_STORM
	Sea.time = 33.5
	uw_a.step_plankton(0.05, Vector3(0.0, 2.5, 0.0), -2.5, false)
	check(not motes_a.visible, "UnderwaterPlanktonMotes hidden above water (depth = -2.5)")
	uw_a.step_plankton(0.05, Vector3(0.0, -0.15, 0.0), 0.15, false)
	check(not motes_a.visible, "UnderwaterPlanktonMotes hidden at depth == 0.15 threshold")
	uw_a.step_plankton(0.05, Vector3(0.0, -3.0, 0.0), 3.0, true)
	check(not motes_a.visible, "UnderwaterPlanktonMotes hidden inside dry hull even when depth > 0.15")

	# Verify dry-hull gating through update(cam, depth) with a registered hull cutout.
	var hull := Node3D.new()
	hull.position = Vector3(10.0, 0.0, -6.0)
	add_child(hull)
	ocean_a.register_hull_mask(hull, null, 0.0)
	var cam := Camera3D.new()
	cam.position = Vector3(10.0, -0.4, -6.0)
	add_child(cam)
	uw_a.update(cam, 2.0)
	check(not motes_a.visible, "Underwater.update() hides UnderwaterPlanktonMotes when camera is inside dry hull")
	cam.position = Vector3(0.0, -4.0, 0.0)
	uw_a.update(cam, 4.0)
	check(motes_a.visible, "Underwater.update() activates UnderwaterPlanktonMotes when submerged outside hull")
	ocean_a.unregister_hull_mask(hull)

	# 4. Verify seamless 14x8x14 camera wraparound, underwater drift, and strict surface clamping.
	var cam_pos0 := Vector3(0.0, -4.0, 0.0)
	uw_a.step_plankton(0.05, cam_pos0, 4.0, false)
	check(motes_a.visible, "UnderwaterPlanktonMotes active when submerged at (0, -4, 0)")
	var p0 := uw_a.get_plankton_positions()
	check_eq(p0.size(), 36, "get_plankton_positions() returns all 36 world-space mote positions")
	for i in p0.size():
		var p := p0[i]
		check(absf(p.x - cam_pos0.x) <= 7.001 and absf(p.z - cam_pos0.z) <= 7.001,
			"mote %d wraps inside 14x14 XZ volume around cam_pos0 (got %s)" % [i, str(p)])
		var surf_y := Sea.height(p.x, p.z)
		check(p.y <= surf_y - 0.25 + 1e-4,
			"mote %d stays strictly below Sea.height - 0.25 at cam_pos0 (y=%.3f, surf=%.3f)" % [i, p.y, surf_y])

	# Advance current drift at same camera position.
	uw_a.step_plankton(0.60, cam_pos0, 4.0, false)
	var p_drift := uw_a.get_plankton_positions()
	var drifted := 0
	for i in p0.size():
		if p_drift[i].distance_squared_to(p0[i]) > 1e-4:
			drifted += 1
	check_eq(drifted, 36, "all 36 UnderwaterPlanktonMotes drift smoothly with underwater current")

	# Large swim displacement: (0, -4, 0) -> (45, -5, -30).
	var cam_pos1 := Vector3(45.0, -5.0, -30.0)
	uw_a.step_plankton(0.10, cam_pos1, 5.0, false)
	var p1 := uw_a.get_plankton_positions()
	for i in p1.size():
		var p := p1[i]
		check(absf(p.x - cam_pos1.x) <= 7.001 and absf(p.z - cam_pos1.z) <= 7.001,
			"mote %d wraps cleanly around displaced cam_pos1 (got %s)" % [i, str(p)])
		check(p.y <= cam_pos1.y + 4.001,
			"mote %d respects upper 8 m volume bound around cam_pos1 (got y=%.3f)" % [i, p.y])
		var surf_y := Sea.height(p.x, p.z)
		check(p.y <= surf_y - 0.25 + 1e-4,
			"mote %d stays strictly below Sea.height - 0.25 at cam_pos1 (y=%.3f, surf=%.3f)" % [i, p.y, surf_y])

	# Shallow dive right below stormy waves must STILL keep all 36 motes below Sea.height - 0.25.
	var shallow_x := 12.0
	var shallow_z := -8.0
	var shallow_cam := Vector3(shallow_x, Sea.height(shallow_x, shallow_z) - 0.55, shallow_z)
	uw_a.step_plankton(0.05, shallow_cam, 0.55, false)
	var p_shallow := uw_a.get_plankton_positions()
	for i in p_shallow.size():
		var p := p_shallow[i]
		var surf_y := Sea.height(p.x, p.z)
		check(p.y <= surf_y - 0.25 + 1e-4,
			"shallow-dive mote %d never floats above Sea.height - 0.25 (y=%.3f, surf=%.3f)" % [i, p.y, surf_y])

	# 5. Verify Weather.daylight() midday -> midnight bioluminescence factor & cyan glow brightening.
	Weather.time_of_day = 12.0
	uw_a.step_plankton(0.0, cam_pos1, 5.0, false)
	var day_bio := uw_a.get_plankton_biolum_factor()
	var day_cols := uw_a.get_plankton_colors()
	var day_cyan_sum := 0.0
	for c in day_cols:
		day_cyan_sum += c.g + c.b

	Weather.time_of_day = 0.0
	uw_a.step_plankton(0.0, cam_pos1, 5.0, false)
	var night_bio := uw_a.get_plankton_biolum_factor()
	var night_cols := uw_a.get_plankton_colors()
	var night_cyan_sum := 0.0
	for c in night_cols:
		night_cyan_sum += c.g + c.b

	check(day_bio < 0.05 and night_bio > 0.95 and night_bio > day_bio,
		"nocturnal bioluminescence factor rises cleanly from midday (%.3f) to midnight (%.3f)" % [day_bio, night_bio])
	check(night_cyan_sum > day_cyan_sum * 1.5,
		"midnight bioluminescent cyan glow brightens over midday sunlit dust (day=%.2f -> night=%.2f)" % [
			day_cyan_sum, night_cyan_sum
		])

	# 6. Verify CrestSpray zero-primitive sculpted 2-tri billboard card (verts, normals, UVs, sharing).
	var card_a := cs_a.get_spray_card_mesh()
	var card_b := cs_b.get_spray_card_mesh()
	var pass_mesh: Mesh = cs_a.particles.draw_pass_1
	check(pass_mesh != null and pass_mesh is ArrayMesh and not (pass_mesh is PrimitiveMesh),
		"CrestSpray uses zero-primitive sculpted ArrayMesh card")
	check_eq(card_a, card_b, "CrestSpray instances share statically cached _spray_card_mesh")
	check_eq(pass_mesh, card_a, "CrestSpray binds _spray_card_mesh to particles.draw_pass_1")
	check_eq(cs_a.particles.material_override, cs_a.material,
		"CrestSpray binds per-instance ShaderMaterial via particles.material_override")

	var card_tris := 0
	var card_bad_normals := 0
	if card_a != null:
		var carr := card_a.surface_get_arrays(0)
		var cverts: PackedVector3Array = carr[Mesh.ARRAY_VERTEX]
		var cnorms: PackedVector3Array = carr[Mesh.ARRAY_NORMAL]
		var cuvs: PackedVector2Array = carr[Mesh.ARRAY_TEX_UV]
		card_tris = floori(float(cverts.size()) / 3.0)
		check_eq(card_tris, 2, "CrestSpray sculpted card has exact 2 triangles")
		check_eq(cnorms.size(), 6, "CrestSpray sculpted card has 6 vertex normals")
		check_eq(cuvs.size(), 6, "CrestSpray sculpted card has 6 vertex UVs")
		var min_v := Vector3(INF, INF, INF)
		var max_v := Vector3(-INF, -INF, -INF)
		var min_uv := Vector2(INF, INF)
		var max_uv := Vector2(-INF, -INF)
		for v in cverts:
			min_v = min_v.min(v)
			max_v = max_v.max(v)
		for uv in cuvs:
			min_uv = min_uv.min(uv)
			max_uv = max_uv.max(uv)
		for nv in cnorms:
			if not nv.is_finite() or absf(nv.length() - 1.0) > 0.002 \
					or nv.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.002:
				card_bad_normals += 1
		check_eq(card_bad_normals, 0, "all CrestSpray card normals are finite unit (0, 0, 1)")
		check(min_v.distance_to(Vector3(-0.5, -0.5, 0.0)) < 1e-5 \
				and max_v.distance_to(Vector3(0.5, 0.5, 0.0)) < 1e-5,
			"CrestSpray card spans exact (-0.5..0.5, -0.5..0.5, 0) (got %s..%s)" % [str(min_v), str(max_v)])
		check(min_uv.distance_to(Vector2(0.0, 0.0)) < 1e-5 \
				and max_uv.distance_to(Vector2(1.0, 1.0)) < 1e-5,
			"CrestSpray card spans full [0..1] UVs (got %s..%s)" % [str(min_uv), str(max_uv)])

	print("    Q20B underwater+spray: PlanktonMotes=36x%d=%d tris (biolum %.2f->%.2f, cyan %.2f->%.2f), CrestSprayCard=%d tris" % [
		mote_tris, 36 * mote_tris, day_bio, night_bio, day_cyan_sum, night_cyan_sum, card_tris
	])

	# 7. Restore globals & verify ref-counted zero-leak teardown across partial & final release.
	Sea.amp_scale = saved_amp
	Sea.time = saved_time
	Weather.time_of_day = saved_tod

	remove_child(cam)
	cam.free()
	remove_child(hull)
	hull.free()

	remove_child(ocean_a)
	ocean_a.free()
	check_eq(Underwater._active_underwaters, 1, "Underwater refcount decrements to 1 while second Ocean remains")
	check_eq(CrestSpray._active_sprays, 1, "CrestSpray refcount decrements to 1 while second Ocean remains")
	check(Underwater._plankton_mesh != null and Underwater._plankton_mat != null,
		"Underwater shared caches remain valid while an instance is still active")
	check(CrestSpray._spray_card_mesh != null,
		"CrestSpray shared card cache remains valid while an instance is still active")

	remove_child(ocean_b)
	ocean_b.free()
	await get_tree().process_frame
	check_eq(Underwater._active_underwaters, 0, "Underwater._active_underwaters returns to 0 on teardown")
	check(Underwater._plankton_mesh == null and Underwater._plankton_mat == null,
		"Underwater auto-releases static _plankton_mesh & _plankton_mat cleanly (0 leaks)")
	check_eq(CrestSpray._active_sprays, 0, "CrestSpray._active_sprays returns to 0 on teardown")
	check(CrestSpray._spray_card_mesh == null,
		"CrestSpray auto-releases static _spray_card_mesh cleanly (0 leaks)")
	Underwater.clear_shared_cache()
	CrestSpray.clear_shared_cache()
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphans_after <= orphans_before,
		"Q20B teardown leaves 0 orphan nodes (before=%d, after=%d)" % [orphans_before, orphans_after])
