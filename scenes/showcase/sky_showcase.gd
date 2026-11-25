extends Node3D
## Sky and weather showcase: a flat sea, a raft of primitives for scale and
## shadows, cone "islands" out to the horizon, and a scripted camera.
##
## User args (after `--`), all optional:
##   time=17.5      hour of day to start at (default 10)
##   storm=0.8      storminess 0..1 (default 0)
##   cloud=0.4      fair-weather cloudiness 0..1
##   wind=8 heading=35   wind speed (m/s) and heading (degrees, 0 = towards -Z)
##   day=2          day number (moon phase)
##   look=sun       sun | moon | away | <yaw degrees>; default sun (night: moon)
##   pitch=10 fov=75 pan=6   camera pitch, field of view, degrees panned over the clip
##   timelapse=1 secs=3  sweep a full day over `secs` seconds (camera faces south)
##   to_storm=1 secs=3   start as set, then brew up to a full storm over `secs`
##   strike=0.3     force a lightning strike at this many seconds (sheet=1: inside the cloud only)
##   freeze=1       stop the clock (default when not a timelapse)
##   from=17.6 to=19.2   sweep the clock between two hours over `secs` (fine dusk timelapse)
##   quality=low|medium|high   cloud quality (default medium)
##   cell=0,-3000,1800,1   a storm cell: centre x, z, radius, intensity (lightning lands in it)
##   cam=0,3.6,11   camera position; truck=400,0  metres the camera travels over the clip (x, z)
##   front=overcast|storm|...  start as set, then let that preset roll in over `secs`
##   evo=40         cloud evolution seconds per second (watch billows boil; default 1)
##   shelter=1      a roofed hut over the raft, flagged as a rain shelter; inside=1 puts the camera in it
## Example: tools/capture.sh res://scenes/showcase/sky_showcase.tscn dusk 2 5 -- time=18.2 cloud=0.5

const SkyRig := preload("res://src/sky/sky_rig.tscn")
const GROUND_SHADER := preload("res://scenes/showcase/sky_showcase_ground.gdshader")

var _args := {}
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 9.0
var _pan := 6.0
var _secs := 3.0
var _t := 0.0
var _strike_at := -1.0
var _cam_pos := Vector3.ZERO
var _cam_set := false
var _truck := Vector3.ZERO
var _sweep := Vector2(-1.0, -1.0)
var _evo := 1.0
var _rig: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	Net.start_single_player()
	_secs = _f("secs", 3.0)
	var timelapse := _f("timelapse", 0.0) > 0.0
	Weather.time_of_day = _f("time", 5.0 if timelapse else 10.0)
	Weather.day = int(_f("day", 0.0))
	Weather.set_weather(_f("storm", 0.0), _f("wind", 8.0), deg_to_rad(_f("heading", 35.0)), 0.0, _f("cloud", 0.4))
	Weather.clear_storm_cell()
	if _args.has("cell"):
		var c := _v("cell")
		Weather.set_storm_cell(Vector3(c[0], 0.0, c[1]), c[2] if c.size() > 2 else 1800.0, c[3] if c.size() > 3 else 1.0)
	Weather.cloud_offset = Vector2(310.0, 120.0)
	Weather.lightning_enabled = false
	Weather.day_length_seconds = _secs if timelapse else (0.0 if _f("freeze", 1.0) > 0.0 else 1440.0)
	if _args.has("from"):
		_sweep = Vector2(_f("from", 17.5), _f("to", 19.5))
		Weather.time_of_day = _sweep.x
		Weather.day_length_seconds = 0.0
	_evo = _f("evo", 1.0)
	_strike_at = _f("strike", 0.25 if maxf(Weather.base_storminess, Weather.storm_intensity) > Weather.LIGHTNING_THRESHOLD else -1.0)
	if _args.has("cam"):
		var c := _v("cam")
		_cam_pos = Vector3(c[0], c[1], c[2])
		_cam_set = true
	if _args.has("truck"):
		var t := _v("truck")
		_truck = Vector3(t[0], 0.0, t[1])
	if _f("inside", 0.0) > 0.0:
		_cam_pos = Vector3(-1.0, 1.9, 1.6)
		_cam_set = true

	_build_world()
	if _f("shelter", 0.0) > 0.0:
		_build_shelter()
	_rig = SkyRig.instantiate()
	_rig.splashes_follow_sea = false
	_rig.cloud_quality = {"low": 0, "medium": 1, "high": 2}.get(_args.get("quality", "medium"), 1)
	add_child(_rig)

	_cam = Camera3D.new()
	_cam.far = 9000.0
	_cam.fov = _f("fov", 75.0)
	add_child(_cam)
	_cam.make_current()
	_pitch = _f("pitch", 9.0)
	_pan = _f("pan", 6.0)
	var look: String = _args.get("look", "south" if timelapse else "auto")
	var night: bool = Weather.sun_height() < -0.08
	match look:
		"auto":
			_yaw = _yaw_towards(Weather.moon_direction() if night else Weather.sun_direction()) + 16.0
		"sun":
			_yaw = _yaw_towards(Weather.sun_direction())
		"moon":
			_yaw = _yaw_towards(Weather.moon_direction())
		"away":
			_yaw = _yaw_towards(-Weather.sun_direction())
		"south":
			_yaw = 180.0
			_pan = 0.0
			_cam.fov = _f("fov", 95.0)
			_pitch = _f("pitch", 16.0)
		_:
			_yaw = look.to_float()
	_aim_camera()
	Weather.set_focus(_cam.position)
	# Weather that rolls in starts once the focus is known (the front is anchored there).
	if _f("to_storm", 0.0) > 0.0:
		Weather.set_weather(1.0, 22.0, Weather.wind_heading, _secs)
	elif _args.has("front"):
		Weather.set_preset(StringName(_args["front"]), _secs)

func _process(delta: float) -> void:
	_t += delta
	if _sweep.x >= 0.0:
		Weather.time_of_day = lerpf(_sweep.x, _sweep.y, clampf(_t / _secs, 0.0, 1.0))
	if _evo != 1.0:
		Weather.cloud_evolution += delta * (_evo - 1.0)
	if _strike_at >= 0.0 and _t >= _strike_at:
		_strike_at = -1.0
		var sheet := _f("sheet", 0.0) > 0.0
		if Weather.storm_intensity > 0.0 and not _args.has("strike_near"):
			var side := (-_cam.global_basis.x) * Weather.storm_radius * 0.25
			Weather.strike_lightning_at(Weather.storm_center + side, 1.0, sheet)
		else:
			var fwd := -_cam.global_basis.z
			fwd.y = 0.0
			var at := _cam.global_position + fwd.normalized().rotated(Vector3.UP, 0.22) * _f("strike_near", 900.0)
			Weather.strike_lightning_at(at, 1.0, sheet)
	_aim_camera()

func _aim_camera() -> void:
	var f := clampf(_t / _secs, 0.0, 1.0)
	var yaw := _yaw + _pan * (f - 0.5)
	_cam.rotation_degrees = Vector3(_pitch, yaw, 0.0)
	if _cam_set:
		_cam.position = _cam_pos + _truck * f
		return
	# Stand back from the raft along the view so it sits in the foreground.
	var back := Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
	_cam.position = back * 11.0 + Vector3(0.0, 3.6, 0.0) + _truck * f

func _f(key: String, fallback: float) -> float:
	return String(_args[key]).to_float() if _args.has(key) else fallback

func _v(key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in String(_args[key]).split(","):
		out.append(part.to_float())
	return out

static func _yaw_towards(dir: Vector3) -> float:
	## Camera yaw (degrees) that faces a world direction; yaw 0 looks down -Z.
	return rad_to_deg(atan2(-dir.x, -dir.z))

func _build_world() -> void:
	var sea := PlaneMesh.new()
	sea.size = Vector2(18000.0, 18000.0)
	_add(sea, Vector3.ZERO, Color(0.03, 0.2, 0.3), 0.55, true)
	# Raft.
	var deck := BoxMesh.new()
	deck.size = Vector3(11.0, 0.5, 9.0)
	_add(deck, Vector3(0.0, 0.25, 0.0), Color(0.5, 0.33, 0.2), 0.8)
	var mast := CylinderMesh.new()
	mast.top_radius = 0.16
	mast.bottom_radius = 0.22
	mast.height = 9.0
	_add(mast, Vector3(-2.2, 5.0, -1.5), Color(0.4, 0.27, 0.17), 0.8)
	var sail := BoxMesh.new()
	sail.size = Vector3(4.6, 3.6, 0.08)
	_add(sail, Vector3(-2.2, 6.6, -1.3), Color(0.93, 0.88, 0.76), 0.9)
	var crate := BoxMesh.new()
	crate.size = Vector3(1.1, 1.1, 1.1)
	_add(crate, Vector3(2.2, 1.05, -1.0), Color(0.62, 0.42, 0.22), 0.8)
	_add(crate, Vector3(3.2, 1.05, 0.3), Color(0.7, 0.2, 0.16), 0.8).rotation.y = 0.5
	_add(crate, Vector3(2.6, 2.15, -0.4), Color(0.62, 0.42, 0.22), 0.8).rotation.y = 0.25
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.42
	barrel.bottom_radius = 0.42
	barrel.height = 1.1
	_add(barrel, Vector3(0.4, 1.05, 1.2), Color(0.45, 0.3, 0.2), 0.7)
	var ball := SphereMesh.new()
	ball.radius = 0.55
	ball.height = 1.1
	_add(ball, Vector3(-0.9, 1.05, 2.4), Color(0.85, 0.85, 0.88), 0.35)
	# Islands marching out to the horizon, all around, to judge fog and depth.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 22:
		var cone := CylinderMesh.new()
		var dist := 90.0 * pow(1.26, i) + 40.0
		var h := dist * rng.randf_range(0.07, 0.16)
		cone.top_radius = h * 0.12
		cone.bottom_radius = h * rng.randf_range(0.9, 1.6)
		cone.height = h
		var az := i * 2.399 + 0.4
		_add(cone, Vector3(sin(az) * dist, h * 0.5 - 0.5, cos(az) * dist),
				Color(0.36, 0.5, 0.28).lerp(Color(0.5, 0.42, 0.34), rng.randf()), 0.9, true)

func _build_shelter() -> void:
	## A hut on the raft: four posts, a roof, and an Area3D in group `shelter`
	## covering the space underneath, which keeps the rain out of it.
	var post := BoxMesh.new()
	post.size = Vector3(0.2, 2.6, 0.2)
	for corner: Vector2 in [Vector2(-3.4, 0.2), Vector2(1.4, 0.2), Vector2(-3.4, 3.6), Vector2(1.4, 3.6)]:
		_add(post, Vector3(corner.x, 1.8, corner.y), Color(0.4, 0.27, 0.17), 0.8)
	var roof := BoxMesh.new()
	roof.size = Vector3(5.6, 0.18, 4.2)
	_add(roof, Vector3(-1.0, 3.15, 1.9), Color(0.55, 0.22, 0.16), 0.9)
	var area := Area3D.new()
	area.add_to_group(&"shelter")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.6, 2.7, 4.2)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3(-1.0, 1.8, 1.9)
	add_child(area)

func _add(mesh: Mesh, at: Vector3, colour: Color, roughness: float, ground: bool = false) -> MeshInstance3D:
	var mat: Material
	if ground:
		# Sea and islands take cloud shadows through cloud_shadow.gdshaderinc.
		var sm := ShaderMaterial.new()
		sm.shader = GROUND_SHADER
		sm.set_shader_parameter(&"albedo", colour)
		sm.set_shader_parameter(&"roughness", roughness)
		mat = sm
	else:
		var std := StandardMaterial3D.new()
		std.albedo_color = colour
		std.roughness = roughness
		mat = std
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi
