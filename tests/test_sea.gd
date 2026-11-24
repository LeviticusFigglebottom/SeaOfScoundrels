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
	check(float(w[2]) / float(w[1]) > 5.0)
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
	var tris := idx.size() / 3
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
