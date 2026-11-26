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

