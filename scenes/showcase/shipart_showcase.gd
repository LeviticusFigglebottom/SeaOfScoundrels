extends Node3D
## Ship art showcase: loads the generated sloop, lights it, and runs a scripted camera.
## User args (after `--`): shot=orbit|deck|helm|hold|bow|far|collision|stern|top|cannon|bowdeck|side|free (eye=x,y,z look=x,y,z)  col=hide|solid|wire
## lod=1 (show sloop_lod.glb instead)  furled=1 (Sail_Furled instead of Sail)  damage=1 (show Hole_* and HolePatch_01..05)
## r=<orbit radius> h=<orbit height> dist=<far distance> fov=<far fov> ssao=0|1
## dur=<seconds for one camera pass, default 2>  capsules=0|1 (frozen 1.75 m Pawns as scale figures)  water=0|1
## print=1 dumps node positions (to verify station markers and pivots).

const SLOOP := "res://assets/generated/ship/sloop.glb"
const FLOOR := -0.85
var shot := "orbit"
var col_mode := ""
var dur := 2.0
var t := 0.0
var cam: Camera3D
var ship: Node3D
var opts := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	shot = opts.get("shot", "orbit")
	dur = float(opts.get("dur", "2"))
	col_mode = opts.get("col", "solid" if shot == "collision" else "hide")
	var path := SLOOP if opts.get("lod", "0") == "0" else "res://assets/generated/ship/sloop_lod.glb"
	ship = (load(path) as PackedScene).instantiate()
	add_child(ship)
	var furled: bool = opts.get("furled", "0") == "1"
	var damage: bool = opts.get("damage", "0") == "1"
	for n in ship.get_children():
		var nm := String(n.name)
		if nm.begins_with("mask_"):
			n.visible = false
		elif nm == "Sail_Furled":
			n.visible = furled
		elif nm == "Sail":
			n.visible = not furled
		elif nm.begins_with("HolePatch_"):
			n.visible = damage and nm.right(2).to_int() <= 5
		elif nm.begins_with("Hole_"):
			n.visible = damage
	_setup_collision_view()
	_setup_env()
	if opts.get("water", "0" if shot == "hold" else "1") == "1":
		_add_water()
	if opts.get("capsules", "1") == "1":
		for p in [Vector3(0.9, 1.1, -2.6), Vector3(0.0, 2.0, 5.95), Vector3(0.4, FLOOR, 3.7), Vector3(-0.82, FLOOR, 0.5), Vector3(1.4, 1.55, 3.25), Vector3(-1.5, 1.1, 2.0)]:
			_add_capsule(p)
	for n in ship.get_children():
		if n.name.begins_with("Lantern_"):
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.72, 0.4)
			l.light_energy = 1.6 if String(n.name).contains("Hold") else 0.6
			l.omni_range = 7.0
			l.shadow_enabled = String(n.name) == "Lantern_Hold"
			l.shadow_bias = 0.12
			l.shadow_normal_bias = 2.0
			n.add_child(l)
	if opts.get("print", "0") == "1":
		for n in ship.get_children():
			if not n.name.begins_with("col_"):
				var fwd: Vector3 = -(n as Node3D).global_transform.basis.z
				print("%-26s pos %s  fwd %s  %s" % [n.name, (n as Node3D).global_position.snapped(Vector3.ONE * 0.001), fwd.snapped(Vector3.ONE * 0.01), n.get_class()])
		var tris := 0
		for n in ship.find_children("*", "MeshInstance3D", true, false):
			if not (n.name.begins_with("col_") or n.name.begins_with("mask_")):
				var m: Mesh = n.mesh
				for s in m.get_surface_count():
					tris += m.surface_get_array_index_len(s) / 3 if m.surface_get_array_index_len(s) > 0 else m.surface_get_array_len(s) / 3
		print("visual triangles in Godot: ", tris)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.08
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	_update_camera()

func _setup_collision_view() -> void:
	var i := 0
	for n in ship.find_children("col_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		i += 1
		if col_mode == "hide":
			mi.visible = false
			continue
		var m := StandardMaterial3D.new()
		var c := Color.from_hsv(fmod(i * 0.137, 1.0), 0.75, 1.0)
		if col_mode == "wire":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = c
			var im := ImmediateMesh.new()
			var arr := mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			im.surface_begin(Mesh.PRIMITIVE_LINES, m)
			for k in range(0, idx.size(), 3):
				for e in 3:
					im.surface_add_vertex(v[idx[k + e]])
					im.surface_add_vertex(v[idx[k + (e + 1) % 3]])
			im.surface_end()
			mi.mesh = im
		else:
			m.albedo_color = Color(c.r, c.g, c.b, 0.55 if shot != "collision" else 1.0)
			if shot != "collision":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = m
	if shot == "collision" and opts.get("ghost", "0") == "0":
		for n in ship.get_children():
			if n is MeshInstance3D and not n.name.begins_with("col_"):
				n.visible = false

func _setup_env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.62, 0.8, 0.95)
	sky_mat.ground_bottom_color = Color(0.05, 0.22, 0.3)
	sky_mat.ground_horizon_color = Color(0.5, 0.75, 0.82)
	sky_mat.sun_angle_max = 12.0
	sky_mat.sky_curve = 0.06
	sky_mat.ground_curve = 0.05
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.ssao_enabled = opts.get("ssao", "1") == "1"
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.3
	env.fog_enabled = false
	env.fog_light_color = Color(0.7, 0.82, 0.9)
	env.fog_density = 0.00025
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -140, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.04
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 60, 0)
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.light_energy = 0.35
	add_child(fill)

func _add_water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.55, 0.6, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.55
	m.metallic = 0.0
	mi.material_override = m
	add_child(mi)

func _add_capsule(p: Vector3) -> void:
	# a real Pawn (1.75 m), frozen: scale figure only
	var pawn: Node3D = (load("res://src/characters/pawn.tscn") as PackedScene).instantiate()
	add_child(pawn)
	pawn.set_physics_process(false)
	pawn.set_process(false)
	pawn.position = p

func _process(delta: float) -> void:
	_update_camera()
	t += delta

func _look(from: Vector3, to: Vector3, fov := 70.0) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, to, Vector3.UP)

func _update_camera() -> void:
	var f := fmod(t / dur, 1.0)
	var a := f * TAU
	match shot:
		"orbit", "collision":
			var r := float(opts.get("r", "19"))
			_look(Vector3(sin(a) * r, float(opts.get("h", "7.5")), cos(a) * r), Vector3(0, 5.6, -1.2), 55.0)
		"free":  # eye=x,y,z look=x,y,z
			var e: PackedStringArray = String(opts.get("eye", "0,3,10")).split(",")
			var l: PackedStringArray = String(opts.get("look", "0,1,0")).split(",")
			_look(Vector3(float(e[0]), float(e[1]), float(e[2])), Vector3(float(l[0]), float(l[1]), float(l[2])), float(opts.get("fov", "75")))
		"side":
			_look(Vector3(lerpf(10.0, -10.0, f), 2.2, lerpf(-4.0, 4.0, f)), Vector3(0, 0.6, 0), 60.0)
		"cannon":
			var eye5 := Vector3(lerpf(-0.3, 0.6, f), 1.1 + 1.62, lerpf(-0.2, -3.0, f))
			_look(eye5, Vector3(1.5, 1.55, -1.6), 75.0)
		"bowdeck":
			var eye6 := Vector3(lerpf(-0.6, 0.6, f), 1.1 + 1.62, -2.6)
			_look(eye6, Vector3(0, 1.9, -5.6), 80.0)
		"top":
			_look(Vector3(0.01, 30, 0.5), Vector3(0, 0, 0), 40.0)
		"deck":
			var yaw := lerpf(-1.2, 1.2, f)
			var eye := Vector3(-0.9, 1.1 + 1.62, 2.3)
			_look(eye, eye + Vector3(sin(yaw), -0.22, -cos(yaw)), 80.0)
		"helm":
			var yaw2 := lerpf(-0.6, 0.6, f)
			var eye2 := Vector3(0.0, 2.0 + 1.62, 6.0)
			_look(eye2, eye2 + Vector3(sin(yaw2), -0.3, -cos(yaw2)), 80.0)
		"hold":
			# first half: standing in the stern nook looking forward past the map table;
			# second half: crouched by the mast looking aft at the table and stern windows
			var eye3 := Vector3(-0.3, FLOOR + 1.6, 4.9)
			if f < 0.5:
				var y3 := lerpf(-0.45, 0.45, f * 2.0)
				_look(eye3, eye3 + Vector3(sin(y3), -0.3, -cos(y3)), 85.0)
			else:
				var eye4 := Vector3(0.85, FLOOR + 1.6, -1.6)
				var y4 := lerpf(-0.6, 0.3, f * 2.0 - 1.0)
				_look(eye4, eye4 + Vector3(sin(y4), -0.12, cos(y4)), 85.0)
		"bow":
			_look(Vector3(lerpf(5.5, -5.5, f), 3.2, -12.0), Vector3(0, 2.3, -7.0), 50.0)
		"stern":
			_look(Vector3(lerpf(-5.0, 5.0, f), 3.5, 13.5), Vector3(0, 1.8, 6.5), 50.0)
		"far":
			var d: float = [120.0, 300.0, 1000.0][mini(int(f * 3.0), 2)]
			if opts.has("dist"):
				d = float(opts["dist"])
			var dir := Vector3(0.75, 0.0, 0.66).normalized()
			_look(dir * d + Vector3(0, 6, 0), Vector3(0, 6, 0), float(opts.get("fov", "50")))
