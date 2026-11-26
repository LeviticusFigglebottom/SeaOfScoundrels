extends TestCase
## Headless tests for src/sky/sky_rig.gd: Storm lightning-strike ocean impact
## surge VFX, wave-conformal ShaderMaterial binding, Ocean foam scar stamping,
## sheet-lightning filtering, and clean teardown.

const SKY_RIG_SCENE := preload("res://src/sky/sky_rig.tscn")


class MockOcean:
	extends Ocean

	var foam_calls: Array[Dictionary] = []

	func _ready() -> void:
		pass

	func add_foam(world_pos: Vector3, radius: float, strength: float = 1.0) -> void:
		foam_calls.append({
			"pos": world_pos,
			"radius": radius,
			"strength": strength,
		})


var _saved_weather: Dictionary = {}


func _save_weather() -> void:
	_saved_weather = Weather.get_state()
	Weather.lightning_enabled = false
	Weather.day_length_seconds = 0.0


func _restore_weather() -> void:
	if _saved_weather.is_empty():
		return
	Weather.set_weather(
		float(_saved_weather["storm"]),
		float(_saved_weather["wind_speed"]),
		float(_saved_weather["wind_heading"]),
		0.0,
		float(_saved_weather["cloudiness"])
	)
	Weather.clear_storm_cell(0.0)
	Weather.set_focus(Vector3.ZERO)
	Weather.apply_state(_saved_weather)
	Weather.lightning_enabled = true


func test_lightning_ocean_impact_surge_lifecycle() -> void:
	_save_weather()
	Net.start_single_player()
	Weather.set_focus(Vector3(12.0, 2.0, 8.0))
	Weather.set_weather(1.0, 20.0, 0.0, 0.0, 1.0)

	var mock_ocean := MockOcean.new()
	add_child(mock_ocean)
	check(Ocean.current == mock_ocean, "MockOcean registered as Ocean.current")

	var rig := SKY_RIG_SCENE.instantiate() as Node3D
	rig.set(&"track_camera_focus", false)
	add_child(rig)
	await physics_frames(1)

	var impact := rig.get_node_or_null(^"LightningImpact") as MeshInstance3D
	check(impact != null, "SkyRig builds LightningImpact MeshInstance3D")
	check(impact.top_level, "LightningImpact uses top_level world positioning")
	check_eq(impact.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"LightningImpact disables shadow casting")
	check(impact.extra_cull_margin >= 16000.0, "LightningImpact has horizon-safe extra_cull_margin")
	check(not impact.visible, "LightningImpact starts hidden before any strike")
	check(impact.mesh is ArrayMesh, "LightningImpact uses sculpted multi-part ArrayMesh")
	check(impact.material_override is ShaderMaterial, "LightningImpact uses ShaderMaterial")

	var impact_mesh := impact.mesh as ArrayMesh
	var tri_count := _count_mesh_triangles(impact_mesh)
	check(tri_count >= 1000, "LightningImpact combines disc, crown & plume geometry (%d tris)" % tri_count)

	var impact_mat := impact.material_override as ShaderMaterial
	check(int(impact_mat.get_shader_parameter(&"sea_wave_count")) > 0,
		"LightningImpact material bound to Sea Gerstner waves")

	# 1. Trigger a real non-sheet sea strike via Weather.strike_lightning().
	Weather.strike_lightning(Vector3(0.0, 0.0, -1.0), 180.0, 1.0)
	var foot: Vector3 = Weather.lightning_position
	var expected_y: float = Sea.height(foot.x, foot.z)

	check(not Weather.lightning_is_sheet, "strike_lightning creates a sea-reaching bolt")
	check(impact.visible, "non-sheet strike activates LightningImpact")
	check_near(impact.global_position.x, foot.x, 0.01, "impact X matches bolt foot")
	check_near(impact.global_position.z, foot.z, 0.01, "impact Z matches bolt foot")
	check_near(impact.global_position.y, expected_y, 0.02, "impact Y rides Sea.height at bolt foot")
	check_near(float(impact_mat.get_shader_parameter(&"progress")), 0.0, 0.001,
		"impact surge starts at progress = 0.0")
	var near_radius := float(impact_mat.get_shader_parameter(&"ring_radius"))
	var near_height := float(impact_mat.get_shader_parameter(&"plume_height"))
	check(near_radius >= 20.0 and near_radius <= 34.0,
		"close strike shockwave target radius in ~20..34 m (got %.2f)" % near_radius)
	check(near_height >= 14.0 and near_height <= 24.0,
		"close strike spray crown peak height in ~14..24 m (got %.2f)" % near_height)

	# Verify live Ocean.current foam scar stamped at the strike foot.
	check_eq(mock_ocean.foam_calls.size(), 1, "sea strike stamps Ocean.current.add_foam once")
	if mock_ocean.foam_calls.size() == 1:
		var fc: Dictionary = mock_ocean.foam_calls[0]
		var fp: Vector3 = fc["pos"] as Vector3
		check_near(fp.x, foot.x, 0.01, "foam scar X aligns with bolt foot")
		check_near(fp.z, foot.z, 0.01, "foam scar Z aligns with bolt foot")
		check_near(fp.y, expected_y, 0.02, "foam scar Y aligns with Sea.height")
		check_near(float(fc["radius"]), 7.5, 0.01, "foam scar radius is 7.5 m")
		check_near(float(fc["strength"]), 1.0, 0.01, "foam scar strength is 1.0")

	# 2. Smoothly advance through the 0.95 s lifetime and verify monotonic progress & auto-hide.
	var prev_prog := 0.0
	for step_i in range(4):
		Weather.advance(0.20)
		rig.call(&"_process", 0.20)
		var prog := float(impact_mat.get_shader_parameter(&"progress"))
		check(impact.visible, "LightningImpact remains visible at step %d (t=%.2f s)" % [step_i, (step_i + 1) * 0.20])
		check(prog > prev_prog and prog < 1.0,
			"impact progress advances monotonically (%.3f -> %.3f)" % [prev_prog, prog])
		prev_prog = prog

	# One more 0.25 s step crosses IMPACT_DURATION (0.95 s -> total 1.05 s) and hides cleanly.
	Weather.advance(0.25)
	rig.call(&"_process", 0.25)
	check(not impact.visible, "LightningImpact hides automatically after ~1.0 s")
	check_near(float(impact_mat.get_shader_parameter(&"progress")), 1.0, 0.001,
		"completed impact clamps progress to 1.0")

	# 3. Verify distant storm strikes scale gently so horizon impacts stay readable.
	Weather.strike_lightning(Vector3(1.0, 0.0, 0.0), 1100.0, 1.0)
	check(impact.visible, "distant strike activates LightningImpact")
	var far_radius := float(impact_mat.get_shader_parameter(&"ring_radius"))
	var far_height := float(impact_mat.get_shader_parameter(&"plume_height"))
	check(far_radius > near_radius,
		"distant strike scales ring_radius up for horizon readability (%.1f > %.1f)" % [far_radius, near_radius])
	check(far_height > near_height,
		"distant strike scales plume_height up for horizon readability (%.1f > %.1f)" % [far_height, near_height])

	rig.queue_free()
	mock_ocean.queue_free()
	await physics_frames(2)
	check(Ocean.current == null, "MockOcean cleans up Ocean.current cleanly")
	_restore_weather()


func test_lightning_impact_ignores_sheet_and_disabled_bolts() -> void:
	_save_weather()
	Net.start_single_player()
	Weather.set_focus(Vector3.ZERO)

	var mock_ocean := MockOcean.new()
	add_child(mock_ocean)
	var rig := SKY_RIG_SCENE.instantiate() as Node3D
	rig.set(&"track_camera_focus", false)
	add_child(rig)
	await physics_frames(1)

	var impact := rig.get_node_or_null(^"LightningImpact") as MeshInstance3D
	var bolt := rig.get_node_or_null(^"LightningBolt") as MeshInstance3D
	check(impact != null and bolt != null, "LightningBolt and LightningImpact present")

	# Sheet lightning (in-cloud flash, lightning_is_sheet = true) must NOT trigger sea impact or foam.
	Weather.strike_lightning_at(Vector3(60.0, 0.0, -240.0), 1.0, true)
	check(Weather.lightning_is_sheet, "sheet strike sets Weather.lightning_is_sheet = true")
	check(not bolt.visible, "sheet lightning hides LightningBolt")
	check(not impact.visible, "sheet lightning ignores LightningImpact")
	check_eq(mock_ocean.foam_calls.size(), 0, "sheet lightning does not stamp Ocean foam")

	# Disabling show_bolts also suppresses both bolt and ocean impact surge.
	rig.set(&"show_bolts", false)
	Weather.strike_lightning(Vector3(0.0, 0.0, -1.0), 140.0, 1.0)
	check(not bolt.visible, "show_bolts=false keeps LightningBolt hidden")
	check(not impact.visible, "show_bolts=false keeps LightningImpact hidden")
	check_eq(mock_ocean.foam_calls.size(), 0, "show_bolts=false does not stamp Ocean foam")

	rig.queue_free()
	mock_ocean.queue_free()
	await physics_frames(2)
	_restore_weather()


func _count_mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	if mesh == null:
		return 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if raw_idx is PackedInt32Array and not (raw_idx as PackedInt32Array).is_empty():
			total += floori(float((raw_idx as PackedInt32Array).size()) / 3.0)
		else:
			var raw_verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if raw_verts is PackedVector3Array:
				total += floori(float((raw_verts as PackedVector3Array).size()) / 3.0)
	return total


func test_post_storm_sunbreak_and_sunshower_rainbow_lifecycle() -> void:
	_save_weather()
	Net.start_single_player()
	Weather.set_focus(Vector3.ZERO)

	# 1. Verify sky_body.gdshaderinc defines rainbow uniform, anti-solar angle & dual optical bows.
	var inc_text := FileAccess.get_file_as_string("res://src/sky/sky_body.gdshaderinc")
	check(inc_text.contains("uniform float rainbow_strength"),
		"sky_body.gdshaderinc declares uniform float rainbow_strength")
	check(inc_text.contains("anti_ang") and inc_text.contains("bow_prim") and inc_text.contains("bow_sec"),
		"sky_body.gdshaderinc implements anti-solar primary 42-deg & secondary 51-deg bow optics")
	for sh_path: String in ["res://src/sky/sky_low.gdshader", "res://src/sky/sky_medium.gdshader", "res://src/sky/sky_high.gdshader"]:
		check(load(sh_path) is Shader, "sky shader %s loads cleanly with rainbow include" % sh_path)

	var rig := SKY_RIG_SCENE.instantiate() as Node3D
	rig.set(&"track_camera_focus", false)
	add_child(rig)
	await physics_frames(1)
	var sky_mat := rig.get(&"sky_material") as ShaderMaterial
	check(sky_mat != null, "SkyRig exposes sky_material")

	# 2. Midnight must keep rainbow_strength strictly 0.0 even during rain.
	Weather.time_of_day = 0.0
	Weather.set_weather(0.54, 12.0, 0.0, 0.0, 0.6)
	rig.call(&"_process", 0.05)
	check_near(float(rig.get(&"current_rainbow_strength")), 0.0, 0.001, "midnight suppresses rainbow")
	check_near(float(sky_mat.get_shader_parameter(&"rainbow_strength")), 0.0, 0.001, "midnight shader rainbow_strength == 0")

	# 3. Clear dry midday must also keep rainbow_strength == 0.0.
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 6.0, 0.0, 0.0, 0.15)
	rig.call(&"_process", 0.05)
	check_near(float(rig.get(&"current_rainbow_strength")), 0.0, 0.001, "clear dry midday has 0 rainbow")

	# 4. Afternoon coastal sun-shower (time_of_day = 16.5, moderate rain/storm) activates rainbow > 0.15!
	Weather.time_of_day = 16.5
	Weather.set_weather(0.54, 11.0, 0.0, 0.0, 0.55)
	rig.call(&"_process", 0.05)
	var shower_str := float(rig.get(&"current_rainbow_strength"))
	check(shower_str > 0.15, "afternoon coastal sun-shower activates rainbow (got %.3f)" % shower_str)
	check_near(float(sky_mat.get_shader_parameter(&"rainbow_strength")), shower_str, 0.001,
		"sky shader rainbow_strength matches SkyRig.current_rainbow_strength")

	# 5. Post-storm sunbreak: heavy storm (0.85) clears to sunny 0.18 -> triggers 75s clearing rainbow!
	Weather.set_weather(0.85, 20.0, 0.0, 0.0, 1.0)
	rig.call(&"_process", 0.10)
	check_near(float(rig.get(&"current_rainbow_strength")), 0.0, 0.001, "heavy overcast storm suppresses rainbow")

	Weather.set_weather(0.18, 9.0, 0.0, 0.0, 0.35)
	rig.call(&"_process", 0.10)
	var sunbreak_str := float(rig.get(&"current_rainbow_strength"))
	check(sunbreak_str > 0.70, "post-storm sunbreak triggers vivid rainbow (got %.3f)" % sunbreak_str)

	# Advance 68 s into the 75 s window -> smoothly fading in final 15 s; then past 75 s -> 0.0!
	rig.call(&"_process", 68.0)
	var fading_str := float(rig.get(&"current_rainbow_strength"))
	check(fading_str > 0.05 and fading_str < sunbreak_str * 0.75,
		"post-storm rainbow fades smoothly over final 15 s (%.3f < %.3f)" % [fading_str, sunbreak_str])
	rig.call(&"_process", 10.0)
	check_near(float(rig.get(&"current_rainbow_strength")), 0.0, 0.001,
		"post-storm rainbow clears cleanly after 75 s window")

	# 6. rainbow_override overrides deterministically and resets cleanly when set back to -1.0!
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 6.0, 0.0, 0.0, 0.15)
	rig.set(&"rainbow_override", 0.85)
	rig.call(&"_process", 0.05)
	check_near(float(rig.get(&"current_rainbow_strength")), 0.85, 0.001, "rainbow_override forces 0.85 cleanly")
	check_near(float(sky_mat.get_shader_parameter(&"rainbow_strength")), 0.85, 0.001, "shader receives rainbow_override")
	rig.set(&"rainbow_override", -1.0)
	rig.call(&"_process", 0.05)
	check_near(float(rig.get(&"current_rainbow_strength")), 0.0, 0.001, "rainbow_override = -1.0 restores automatic mode")

	rig.queue_free()
	await physics_frames(2)
	_restore_weather()

