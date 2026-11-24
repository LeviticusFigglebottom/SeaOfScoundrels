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
	for w in Sea.WAVE_TABLE:
		max_amp += float(w[1])
	check(absf(h0) <= max_amp * Sea.amp_scale + 0.001)

func test_no_self_intersection_at_storm() -> void:
	var s := 0.0
	for w in Sea.WAVE_TABLE:
		s += TAU / float(w[0]) * float(w[1]) * float(w[3])
	check(s * Sea.AMP_STORM < 1.0, "sum(k*A*steepness)*AMP_STORM = %f must be < 1" % (s * Sea.AMP_STORM))

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
	var long_amp := 0.0
	var all_amp := 0.0
	for w in Sea.WAVE_TABLE:
		all_amp += float(w[1])
		if float(w[0]) >= 60.0:
			long_amp += float(w[1])
	check(Sea.WAVE_TABLE.size() <= Sea.MAX_WAVES)
	check(long_amp / all_amp > 0.6, "long swell share %f" % (long_amp / all_amp))
	check(long_amp * Sea.AMP_CALM < 2.0, "calm swell too high")
	check(long_amp * Sea.AMP_STORM > 5.0, "storm swell too low")

func test_ocean_mesh_is_watertight_and_in_budget() -> void:
	var ocean_script: GDScript = load("res://src/ocean/ocean.gd")
	var mesh: ArrayMesh = ocean_script.build_mesh(96, 0.5, 8)
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
