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
