extends TestCase
## Renders waves.gdshaderinc on the GPU and compares it with the CPU `Sea`.
## Needs a real renderer, so it is skipped under --headless; run it with
## tools/test_gpu.sh (software Vulkan under Xvfb works).

const SIZE := 32
const EXTENT := 300.0   # metres across the sampled square
const H_RANGE := 12.0   # heights are encoded as h / H_RANGE * 0.5 + 0.5

const PROBE_SHADER := "
shader_type canvas_item;
#include \"res://src/ocean/waves.gdshaderinc\"
uniform float extent;
uniform float h_range;
void fragment() {
	vec2 world = (UV - 0.5) * extent;
	vec3 d = sea_displacement(world);
	vec3 n; float j;
	sea_normal_jacobian(world, n, j);
	COLOR = vec4(sea_height(world) / h_range * 0.5 + 0.5, d.y / h_range * 0.5 + 0.5, n.y, 1.0);
}
"

func test_shader_matches_cpu() -> void:
	if DisplayServer.get_name() == "headless":
		print("    (skipped: no renderer; run tools/test_gpu.sh)")
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.use_hdr_2d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var shader := Shader.new()
	shader.code = PROBE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"extent", EXTENT)
	mat.set_shader_parameter(&"h_range", H_RANGE)
	Sea.bind_material(mat)
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	rect.material = mat
	vp.add_child(rect)

	var saved_amp := Sea.amp_scale
	var saved_time := Sea.time
	Sea.set_physics_process(false)  # freeze the clock while we compare
	for state: Array in [[Sea.AMP_CALM, 3.0], [1.3, 41.5], [Sea.AMP_STORM, 123.25]]:
		Sea.amp_scale = state[0]
		Sea.time = state[1]
		for _i in 3:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBAF)
		var worst_h := 0.0
		var worst_d := 0.0
		var worst_n := 0.0
		for py in SIZE:
			for px in SIZE:
				var x := ((px + 0.5) / SIZE - 0.5) * EXTENT
				var z := ((py + 0.5) / SIZE - 0.5) * EXTENT
				var c := img.get_pixel(px, py)
				worst_h = maxf(worst_h, absf((c.r - 0.5) * 2.0 * H_RANGE - Sea.height(x, z)))
				var d := Sea.displacement(x, z)
				worst_d = maxf(worst_d, absf((c.g - 0.5) * 2.0 * H_RANGE - d.y))
				# The shader's analytic normal belongs to rest point (x, z), which
				# sits at the displaced position on the real surface.
				worst_n = maxf(worst_n, absf(c.b - Sea.normal(x + d.x, z + d.z, 0.02).y))
		print("    amp %.2f: max |dh| %.4f m, |ddisp| %.4f m, |dn.y| %.4f" % [state[0], worst_h, worst_d, worst_n])
		check(worst_h < 0.03, "shader sea_height differs from Sea.height by %f m at amp %f" % [worst_h, state[0]])
		check(worst_d < 0.03, "shader displacement differs by %f m at amp %f" % [worst_d, state[0]])
		check(worst_n < 0.03, "shader normal differs by %f at amp %f" % [worst_n, state[0]])
	Sea.amp_scale = saved_amp
	Sea.time = saved_time
	Sea.set_physics_process(true)
	vp.queue_free()

const FLOW_PROBE_SHADER := "
shader_type canvas_item;
#include \"res://src/ocean/waves.gdshaderinc\"
uniform float extent;
uniform float v_range;
void fragment() {
	vec2 world = (UV - 0.5) * extent;
	vec3 n; float j; float lost_var; float h; float h_var; vec2 long_slope; vec2 flow_vel;
	sea_surface_lod_flow(world, sea_time, 0.0, n, j, lost_var, h, h_var, long_slope, flow_vel);
	COLOR = vec4(flow_vel.x / v_range * 0.5 + 0.5, flow_vel.y / v_range * 0.5 + 0.5, j * 0.25, 1.0);
}
"

func test_shader_flow_matches_cpu() -> void:
	if DisplayServer.get_name() == "headless":
		print("    (skipped: no renderer; run tools/test_gpu.sh)")
		return
	var v_range := 16.0
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.use_hdr_2d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var shader := Shader.new()
	shader.code = FLOW_PROBE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"extent", EXTENT)
	mat.set_shader_parameter(&"v_range", v_range)
	Sea.bind_material(mat)
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	rect.material = mat
	vp.add_child(rect)

	var saved_amp := Sea.amp_scale
	var saved_time := Sea.time
	Sea.set_physics_process(false)
	for state: Array in [[Sea.AMP_CALM, 17.5], [Sea.AMP_STORM, 88.25]]:
		Sea.amp_scale = state[0]
		Sea.time = state[1]
		for _i in 3:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBAF)
		var worst_vx := 0.0
		var worst_vz := 0.0
		var worst_j := 0.0
		for py in SIZE:
			for px in SIZE:
				var x := ((px + 0.5) / SIZE - 0.5) * EXTENT
				var z := ((py + 0.5) / SIZE - 0.5) * EXTENT
				var c := img.get_pixel(px, py)
				var cpu_v := Sea.orbital_velocity(x, z)
				var cpu_dj := Sea.displacement_and_jacobian(x, z)
				worst_vx = maxf(worst_vx, absf((c.r - 0.5) * 2.0 * v_range - cpu_v.x))
				worst_vz = maxf(worst_vz, absf((c.g - 0.5) * 2.0 * v_range - cpu_v.y))
				worst_j = maxf(worst_j, absf(c.b * 4.0 - cpu_dj.w))
		print("    flow amp %.2f: max |dvx| %.4f, |dvz| %.4f, |dj| %.4f" % [state[0], worst_vx, worst_vz, worst_j])
		check(worst_vx < 0.02, "shader flow_vel.x differs by %f at amp %f" % [worst_vx, state[0]])
		check(worst_vz < 0.02, "shader flow_vel.y differs by %f at amp %f" % [worst_vz, state[0]])
		check(worst_j < 0.02, "shader jacobian differs by %f at amp %f" % [worst_j, state[0]])
	Sea.amp_scale = saved_amp
	Sea.time = saved_time
	Sea.set_physics_process(true)
	vp.queue_free()

func test_ocean_and_spray_shaders_compile_and_render() -> void:
	if DisplayServer.get_name() == "headless":
		print("    (skipped: no renderer; run tools/test_gpu.sh)")
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 72)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.0, 6.0)
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, -30.0))
	cam.make_current()
	var ocean_scene: PackedScene = load("res://src/ocean/ocean.tscn")
	var ocean: Ocean = ocean_scene.instantiate() as Ocean
	ocean.camera = cam
	vp.add_child(ocean)
	var hull := Node3D.new()
	hull.position = Vector3(0.0, 0.0, -10.0)
	vp.add_child(hull)
	ocean.register_hull_mask(hull, null, 0.0)

	var saved_amp := Sea.amp_scale
	Sea.amp_scale = Sea.AMP_CALM
	for _i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	check(img != null and img.get_width() == 128, "ocean viewport rendered cleanly")
	# Ensure rendered ocean pixels are finite and non-black
	var center := img.get_pixel(64, 54)
	check(not is_nan(center.r) and not is_nan(center.g) and not is_nan(center.b), "ocean pixel must be finite")
	check(center.r + center.g + center.b > 0.01, "ocean pixel should be lit, got %s" % str(center))

	ocean.unregister_hull_mask(hull)
	Sea.amp_scale = saved_amp
	vp.queue_free()
