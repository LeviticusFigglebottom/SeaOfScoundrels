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
##   strike=0.3     force a lightning strike at this many seconds
##   freeze=1       stop the clock (default when not a timelapse)
## Example: tools/capture.sh res://scenes/showcase/sky_showcase.tscn dusk 2 5 -- time=18.2 cloud=0.5

const SkyRig := preload("res://src/sky/sky_rig.tscn")

var _args := {}
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 9.0
var _pan := 6.0
var _secs := 3.0
var _t := 0.0
var _strike_at := -1.0


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
	Weather.storminess = _f("storm", 0.0)
	Weather.cloudiness = _f("cloud", 0.4)
	Weather.wind_speed = _f("wind", 8.0)
	Weather.wind_heading = deg_to_rad(_f("heading", 35.0))
	Weather.cloud_offset = Vector2(310.0, 120.0)
	Weather.lightning_enabled = false
	Weather.day_length_seconds = _secs if timelapse else (0.0 if _f("freeze", 1.0) > 0.0 else 1440.0)
	if _f("to_storm", 0.0) > 0.0:
		Weather.set_weather(1.0, 22.0, Weather.wind_heading, _secs)
	_strike_at = _f("strike", 0.25 if Weather.storminess > Weather.LIGHTNING_THRESHOLD else -1.0)

	_build_world()
	add_child(SkyRig.instantiate())

	_cam = Camera3D.new()
	_cam.far = 6000.0
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

func _process(delta: float) -> void:
	_t += delta
	if _strike_at >= 0.0 and _t >= _strike_at:
		_strike_at = -1.0
		var fwd := -_cam.global_basis.z
		Weather.strike_lightning(fwd.rotated(Vector3.UP, 0.22), 900.0)
	_aim_camera()

func _aim_camera() -> void:
	var yaw := _yaw + _pan * (clampf(_t / _secs, 0.0, 1.0) - 0.5)
	_cam.rotation_degrees = Vector3(_pitch, yaw, 0.0)
	# Stand back from the raft along the view so it sits in the foreground.
	var back := Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
	_cam.position = back * 11.0 + Vector3(0.0, 3.6, 0.0)

func _f(key: String, fallback: float) -> float:
	return String(_args[key]).to_float() if _args.has(key) else fallback

static func _yaw_towards(dir: Vector3) -> float:
	## Camera yaw (degrees) that faces a world direction; yaw 0 looks down -Z.
	return rad_to_deg(atan2(-dir.x, -dir.z))

func _build_world() -> void:
	var sea := PlaneMesh.new()
	sea.size = Vector2(12000.0, 12000.0)
	_add(sea, Vector3.ZERO, Color(0.03, 0.2, 0.3), 0.55)
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
				Color(0.36, 0.5, 0.28).lerp(Color(0.5, 0.42, 0.34), rng.randf()), 0.9)

func _add(mesh: Mesh, at: Vector3, colour: Color, roughness: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi
