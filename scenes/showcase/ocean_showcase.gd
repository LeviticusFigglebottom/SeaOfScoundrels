extends Node3D
## Self-contained ocean showcase with repeatable scripted shots.
##
##   tools/capture.sh res://scenes/showcase/ocean_showcase.tscn calm 3 8 -- shot=calm
##
## User args (after `--`), all optional:
##   shot=calm|storm|sunset|night|underwater|shore|waterline|aerial|swell|wake|fair_deck|hull   (default calm)
##   quality=low|medium|high   Ocean.quality (default high)
##   rain=<0..1>     rain rings (default: 0.8 in the storm shot, else 0)
##   amp=<float>     override Sea.amp_scale
##   flood=<0..1>    hold flood level for shot=hull (default 0)
##   t=<seconds>     starting wave time
##   scale=<0.25..1> 3D render scale (faster software captures)
##   clock=<seconds> start the scripted camera this far into its move
##   wire=1          wireframe ocean (mesh inspection)

const ISLAND_POS := Vector3(150.0, 0.0, -150.0)
const SKY_RIG_SCENE := preload("res://src/sky/sky_rig.tscn")
const SLOOP_SCENE := preload("res://assets/generated/ship/sloop.glb")

var _args: Dictionary = {}
var _shot: String = "calm"
var _cam: Camera3D
var _floaters: Array[Dictionary] = []
var _sloop: Node3D
var _clock: float = 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _lagoon: bool = false

# Per-shot look: sun elevation/azimuth (degrees), colours, storminess.
const LOOKS := {
	"noon": {
		"elev": 52.0, "azim": 35.0, "storm": 0.0,
		"sun": Color(1.0, 0.96, 0.86), "sun_energy": 1.25,
		"horizon": Color(0.52, 0.76, 0.93), "zenith": Color(0.07, 0.30, 0.74),
		"ambient": Color(0.42, 0.55, 0.68),
	},
	"sunset": {
		"elev": 5.5, "azim": 0.0, "storm": 0.5,
		"sun": Color(1.0, 0.50, 0.18), "sun_energy": 1.3,
		"horizon": Color(1.0, 0.56, 0.26), "zenith": Color(0.20, 0.22, 0.50),
		"ambient": Color(0.40, 0.33, 0.44),
	},
	"night": {
		# the moon is the key light at night; the sky rig feeds it through sun_dir/sun_color
		"elev": 24.0, "azim": 8.0, "storm": 0.25,
		"sun": Color(0.62, 0.74, 1.0), "sun_energy": 0.42,
		"horizon": Color(0.07, 0.11, 0.21), "zenith": Color(0.012, 0.022, 0.07),
		"ambient": Color(0.07, 0.10, 0.19),
	},
	"storm": {
		"elev": 28.0, "azim": 60.0, "storm": 1.0,
		"sun": Color(0.78, 0.84, 0.80), "sun_energy": 0.9,
		"horizon": Color(0.47, 0.55, 0.53), "zenith": Color(0.13, 0.18, 0.21),
		"ambient": Color(0.34, 0.42, 0.43),
	},
}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_shot = _args.get("shot", "calm")
	Net.start_single_player()
	Weather.day_length_seconds = 0.0

	var ocean: Ocean = $Ocean
	var storm := 0.0
	if _shot == "fair_deck":
		_build_real_sky_rig(12.6, 0.42, 0.0, 10.5, 0.52)
		_build_horizon_islands()
		storm = 0.0
	elif _shot == "hull":
		_build_real_sky_rig(12.2, 0.32, 0.0, 8.5, 0.45)
		_build_sloop(ocean, float(_args.get("flood", "0.0")))
		storm = 0.12
	else:
		var look_name := "noon"
		if _shot == "sunset" or _shot == "night":
			look_name = _shot
		elif _shot == "storm":
			look_name = "storm"
		_build_sky(LOOKS[look_name])
		_build_island()
		_build_floaters()
		storm = float(LOOKS[look_name]["storm"])
		if _shot == "swell" or _shot == "wake":
			storm = 0.3
		if _shot == "storm":
			Weather.wind_speed = 22.0
			Weather.wind_heading = 1.0

	ocean.rain_intensity = float(_args.get("rain", "0.8" if _shot == "storm" else "0.0"))
	ocean.quality = {"low": Ocean.Quality.LOW, "medium": Ocean.Quality.MEDIUM}.get(_args.get("quality", "high"), Ocean.Quality.HIGH)
	Weather.storminess = storm
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	if _shot == "shore" or _shot == "underwater" or _shot == "waterline":
		# a sheltered lagoon: less swell than the open sea's calm, so the rocks
		# and the beach keep a steady waterline
		Sea.amp_scale = 0.4
		Sea.set_physics_process(false)
		_lagoon = true
	if _args.has("amp"):
		Sea.amp_scale = float(_args["amp"])
		Weather.storminess = inverse_lerp(Sea.AMP_CALM, Sea.AMP_STORM, Sea.amp_scale)
	Sea.time = float(_args.get("t", "40.0"))
	_clock = float(_args.get("clock", "0.0"))

	_cam = Camera3D.new()
	_cam.fov = 65.0
	_cam.near = 0.08
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	if _args.has("scale"):
		get_viewport().scaling_3d_scale = float(_args["scale"])
	if _args.get("wire", "0") == "1":
		RenderingServer.set_debug_generate_wireframes(true)
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	_update_floaters()
	_update_sloop()
	_update_camera()

func _process(delta: float) -> void:
	_clock += delta
	if _lagoon:
		Sea.time += delta  # Sea's own tick is off so it does not ease amp_scale back
	_update_floaters()
	_update_sloop()
	_update_camera()

# --- sky and light ----------------------------------------------------------

func _build_real_sky_rig(hour: float, cloudiness: float, storm: float, wind_spd: float, wind_hdg: float) -> void:
	Weather.time_of_day = hour
	Weather.set_weather(storm, wind_spd, wind_hdg, 0.0, cloudiness)
	var rig := SKY_RIG_SCENE.instantiate()
	add_child(rig)

func _build_sky(look: Dictionary) -> void:
	var elev := deg_to_rad(float(look["elev"]))
	var azim := deg_to_rad(float(look["azim"]))
	# azimuth 0 = sun over -Z (straight ahead of the default camera)
	var dir := Vector3(sin(azim) * cos(elev), sin(elev), -cos(azim) * cos(elev)).normalized()
	var sun_c: Color = look["sun"]
	var energy: float = look["sun_energy"]
	var hor: Color = look["horizon"]
	var zen: Color = look["zenith"]
	var amb: Color = look["ambient"]
	RenderingServer.global_shader_parameter_set(&"sun_dir", dir)
	RenderingServer.global_shader_parameter_set(&"sun_color", Vector3(sun_c.r, sun_c.g, sun_c.b) * energy)
	RenderingServer.global_shader_parameter_set(&"sky_horizon_color", Vector3(hor.r, hor.g, hor.b))
	RenderingServer.global_shader_parameter_set(&"sky_zenith_color", Vector3(zen.r, zen.g, zen.b))
	RenderingServer.global_shader_parameter_set(&"ambient_color", Vector3(amb.r, amb.g, amb.b))
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_params", Vector4(1e9, 1e9, 0.0001, 1.0))

	_sun = DirectionalLight3D.new()
	_sun.light_color = sun_c
	_sun.light_energy = energy
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)
	_sun.look_at_from_position(dir * 50.0, Vector3.ZERO)

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://scenes/showcase/showcase_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = amb
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

# --- props --------------------------------------------------------------------

func _build_horizon_islands() -> void:
	# Distant stylized sea stacks & island silhouettes along the hazy horizon
	# for fair_deck horizon depth readability.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.38, 0.44)
	mat.roughness = 0.95
	var stacks := [
		[Vector3(-420.0, -4.0, -780.0), Vector3(110.0, 95.0, 85.0), 0.25],
		[Vector3(-560.0, -6.0, -1450.0), Vector3(70.0, 125.0, 70.0), 0.7],
		[Vector3(140.0, -5.0, -1750.0), Vector3(95.0, 80.0, 90.0), -0.4],
		[Vector3(880.0, -5.0, -1350.0), Vector3(160.0, 62.0, 110.0), 0.9],
	]
	for entry: Array in stacks:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.14
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		cyl.radial_segments = 7
		cyl.rings = 2
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = mat
		var pos: Vector3 = entry[0]
		var sc: Vector3 = entry[1]
		mi.position = Vector3(pos.x, pos.y + sc.y * 0.42, pos.z)
		mi.scale = sc
		mi.rotation.y = float(entry[2])
		add_child(mi)

func _build_sloop(ocean: Ocean, flood_level: float) -> void:
	_sloop = SLOOP_SCENE.instantiate() as Node3D
	_sloop.name = "Sloop"
	add_child(_sloop)
	var mask_mesh: MeshInstance3D = null
	var stack: Array[Node] = [_sloop]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var n := node.name
		if n == "mask_water" and node is MeshInstance3D:
			mask_mesh = node as MeshInstance3D
			mask_mesh.visible = false
		elif n.begins_with("col_") or n.begins_with("Hole_") or n.begins_with("HolePatch_") or n == "Sail_Furled":
			if node is Node3D:
				(node as Node3D).visible = false
		for child in node.get_children():
			stack.append(child)
	_update_sloop()
	ocean.register_hull_mask(_sloop, mask_mesh, flood_level)

func _update_sloop() -> void:
	if _sloop == null:
		return
	var x := 0.0
	var z := -12.0
	var yaw := 0.32
	var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var span := 4.8
	var beam := 1.9
	var hc := Sea.height(x, z)
	var hf := Sea.height(x + fwd.x * span, z + fwd.z * span)
	var hb := Sea.height(x - fwd.x * span, z - fwd.z * span)
	var hr := Sea.height(x + right.x * beam, z + right.z * beam)
	var hl := Sea.height(x - right.x * beam, z - right.z * beam)
	var f3 := (fwd * span * 2.0 + Vector3.UP * (hf - hb)).normalized()
	var r3 := (right * beam * 2.0 + Vector3.UP * (hr - hl)).normalized()
	var up := r3.cross(f3).normalized()
	r3 = f3.cross(up).normalized()
	var y := (hc + hf + hb + hr + hl) / 5.0 - 0.18
	_sloop.global_transform = Transform3D(Basis(r3, up, -f3), Vector3(x, y, z))

func _island_height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var ang := atan2(z, x)
	var wob := 1.0 + 0.16 * sin(ang * 3.0 + 0.7) + 0.09 * sin(ang * 5.0 - 1.3)
	var rr := r / wob
	# gentle beach through the waterline, a low hump in the middle
	var h := 3.2 * (1.0 - pow(rr / 30.0, 1.6))
	if rr > 30.0:
		h = -(rr - 30.0) * 0.16 - pow(maxf(rr - 55.0, 0.0) * 0.08, 2.0)
	h += 0.25 * sin(x * 0.31 + 1.0) * sin(z * 0.27 - 0.5) + 0.08 * sin(x * 1.1) * sin(z * 0.9)
	return maxf(h, -40.0)

func _build_island() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 96
	var size := 220.0
	var sand := Color(0.93, 0.83, 0.58)
	var wet := Color(0.70, 0.60, 0.40)
	var grass := Color(0.36, 0.60, 0.22)
	var deep := Color(0.55, 0.52, 0.40)
	for j in n + 1:
		for i in n + 1:
			var x := (float(i) / n - 0.5) * size
			var z := (float(j) / n - 0.5) * size
			var h := _island_height(x, z)
			var c := sand
			if h > 1.5:
				c = sand.lerp(grass, smoothstep(1.5, 2.3, h))
			elif h < 0.25:
				c = wet.lerp(deep, smoothstep(0.0, -6.0, h)) if h < 0.0 else sand.lerp(wet, smoothstep(0.25, 0.0, h))
			st.set_color(c)
			st.add_vertex(Vector3(x, h, z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + n + 2)
			st.add_index(a); st.add_index(a + n + 2); st.add_index(a + n + 1)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.name = "Island"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = ISLAND_POS
	add_child(mi)

	# rocks breaking the surface off the beach
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.34, 0.32, 0.31)
	rock_mat.roughness = 0.9
	var spots := [
		[Vector3(-40.0, -0.6, 8.0), Vector3(3.2, 2.4, 2.6)],
		[Vector3(-45.5, -0.9, 13.0), Vector3(1.8, 1.7, 2.1)],
		[Vector3(-36.0, -0.3, 22.0), Vector3(2.4, 1.5, 3.0)],
		[Vector3(-52.0, -1.2, 2.0), Vector3(2.0, 2.6, 1.8)],
	]
	for s: Array in spots:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 9
		sphere.rings = 5
		var rock := MeshInstance3D.new()
		rock.mesh = sphere
		rock.material_override = rock_mat
		rock.position = ISLAND_POS + (s[0] as Vector3)
		rock.scale = s[1]
		rock.rotation = Vector3(0.3, (s[0] as Vector3).x, 0.2)
		add_child(rock)

func _add_floater(mesh: Mesh, color: Color, pos: Vector3, draught: float, span: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	_floaters.append({"node": mi, "x": pos.x, "z": pos.z, "draught": draught, "span": span, "yaw": pos.y})

func _build_floaters() -> void:
	var crate := BoxMesh.new()
	crate.size = Vector3(1.3, 1.3, 1.3)
	_add_floater(crate, Color(0.62, 0.40, 0.20), Vector3(-2.5, 0.4, -9.0), -0.25, 0.6)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.42
	barrel.bottom_radius = 0.42
	barrel.height = 1.1
	_add_floater(barrel, Color(0.50, 0.30, 0.16), Vector3(3.5, 1.1, -14.0), -0.15, 0.5)
	# a sloop-sized hulk for scale in the big-sea shots
	var hulk := BoxMesh.new()
	hulk.size = Vector3(4.4, 3.6, 13.0)
	_add_floater(hulk, Color(0.45, 0.27, 0.15), Vector3(-16.0, 0.6, -46.0), 0.3, 5.0)
	var mast := CylinderMesh.new()
	mast.top_radius = 0.16
	mast.bottom_radius = 0.22
	mast.height = 14.0
	_add_floater(mast, Color(0.55, 0.38, 0.22), Vector3(-16.0, 0.6, -46.0), -8.0, 5.0)

func _update_floaters() -> void:
	for f in _floaters:
		var span: float = f["span"]
		var yaw: float = f["yaw"]
		var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))
		if _shot == "wake" and span > 4.0:
			# the hulk sails off and feeds the ocean's foam hook, like a ship would
			var dt := get_process_delta_time()
			f["x"] += fwd.x * 6.0 * dt
			f["z"] += fwd.z * 6.0 * dt
			var c := Vector3(f["x"], 0.0, f["z"])
			var side := Vector3(-fwd.z, 0.0, fwd.x)
			var oc: Ocean = $Ocean
			oc.add_foam(c - fwd * 7.0, 2.6, 0.5)                 # churned wake astern
			oc.add_foam(c + fwd * 6.0 + side * 2.0, 1.3, 0.35)   # bow wave, each side
			oc.add_foam(c + fwd * 6.0 - side * 2.0, 1.3, 0.35)
		var x: float = f["x"]
		var z: float = f["z"]
		var right := Vector3(fwd.z, 0.0, -fwd.x) * -1.0
		var hc := Sea.height(x, z)
		var hf := Sea.height(x + fwd.x * span, z + fwd.z * span)
		var hb := Sea.height(x - fwd.x * span, z - fwd.z * span)
		var hr := Sea.height(x + right.x * span * 0.5, z + right.z * span * 0.5)
		var hl := Sea.height(x - right.x * span * 0.5, z - right.z * span * 0.5)
		var f3 := (fwd * span * 2.0 + Vector3.UP * (hf - hb)).normalized()
		var r3 := (right * span + Vector3.UP * (hr - hl)).normalized()
		var up := r3.cross(f3).normalized()
		r3 = f3.cross(up).normalized()
		var node: MeshInstance3D = f["node"]
		var y := (hc + hf + hb + hr + hl) / 5.0
		node.global_transform = Transform3D(Basis(r3, up, -f3), Vector3(x, y, z) - up * float(f["draught"]))

# --- cameras ------------------------------------------------------------------

func _look(from: Vector3, to: Vector3) -> void:
	_cam.look_at_from_position(from, to, Vector3.UP)

func _update_camera() -> void:
	var t := _clock
	match _shot:
		"fair_deck":
			# Deck-height fair-weather noon view with real SkyRig, looking across
			# sunlit rolling swells toward the bright hazy horizon & distant islands.
			var p := Vector3(2.0 + t * 1.1, 0.0, 6.0 - t * 0.8)
			p.y = Sea.height(p.x, p.z) + 2.45
			_look(p, Vector3(p.x - 2.0, p.y - 2.1, p.z - 28.0))
		"hull":
			# Inspect the sloop's dry hold cutout (`mask_water`) and waterline collar:
			# sweeps from looking into the open hatch down into the dry hold below sea level.
			if _sloop != null:
				var xf := _sloop.global_transform
				var phase := clampf(t / 2.5, 0.0, 1.0)
				var from_local := Vector3(0.0, 2.7, 3.6).lerp(Vector3(0.0, 0.25, 1.6), phase)
				var target_local := Vector3(0.0, -0.55, -0.6).lerp(Vector3(0.0, -0.45, -2.5), phase)
				_look(xf * from_local, xf * target_local)
			else:
				_look(Vector3(0, 3, 6), Vector3(0, 0, -12))
		"calm":
			# eye height of a sailor on deck, slow drift
			var p := Vector3(1.5 + t * 0.6, 0.0, 4.0)
			p.y = Sea.height(p.x, p.z) + 2.6
			_look(p, Vector3(-3.0 + t * 0.4, 0.4, -30.0))
		"swell":
			var p := Vector3(6.0, 0.0, 10.0 - t * 1.0)
			p.y = Sea.height(p.x, p.z) + 3.0
			_look(p, Vector3(-14.0, 1.0, -46.0))
		"storm":
			var p := Vector3(4.0 + t * 0.8, 0.0, -8.0)
			p.y = Sea.height(p.x, p.z) + 3.4
			_look(p, Vector3(-16.0, Sea.height(-16.0, -46.0) + 2.0, -46.0))
			_cam.rotate_object_local(Vector3.FORWARD, 0.05 * sin(t * 0.9))
		"sunset":
			var p := Vector3(-1.0 + t * 0.5, 0.0, 6.0)
			p.y = Sea.height(p.x, p.z) + 2.2
			_look(p, Vector3(-4.0, 2.0, -60.0))
		"shore":
			var p := ISLAND_POS + Vector3(-60.0 + t * 1.2, 0.0, 30.0 - t * 0.4)
			p.y = 4.2
			_look(p, ISLAND_POS + Vector3(-36.0, 0.0, 12.0))
		"underwater":
			# over the island's slope, looking up towards the sun and the surface
			var p := ISLAND_POS + Vector3(-57.0 + t * 0.5, -2.6 + t * 0.1, 22.0)
			_look(p, ISLAND_POS + Vector3(-45.0, 3.2 + t * 0.2, 12.0))
		"waterline":
			# lens bobbing through the surface
			var p := ISLAND_POS + Vector3(-50.0, 0.0, 24.0)
			p.y = Sea.height(p.x, p.z) + 0.10 * sin(t * 1.3) - 0.02
			_look(p, ISLAND_POS + Vector3(-38.0, p.y + 0.3, 8.0))
		"night":
			var p := Vector3(-1.0 + t * 0.5, 0.0, 6.0)
			p.y = Sea.height(p.x, p.z) + 2.6
			_look(p, Vector3(-4.0, 2.0, -60.0))
		"wake":
			# follow the hulk from astern and above
			var hx: float = _floaters[2]["x"]
			var hz: float = _floaters[2]["z"]
			var yaw: float = _floaters[2]["yaw"]
			var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))
			var p := Vector3(hx, 0.0, hz) - fwd * 34.0 + Vector3(9.0, 0.0, 0.0)
			p.y = Sea.height(p.x, p.z) + 11.0
			_look(p, Vector3(hx, 1.0, hz) - fwd * 6.0)
		"aerial":
			var p := Vector3(0.0, 90.0 + t * 30.0, 60.0)
			_look(p, Vector3(0.0, 0.0, -260.0))
		_:
			push_error("unknown shot '%s'" % _shot)
			_look(Vector3(0, 3, 6), Vector3(0, 0, -20))
