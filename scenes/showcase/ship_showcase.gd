extends Node3D
## Ship showcase: real Sloop sailing on the real Ocean under the real SkyRig.
##
##   tools/capture.sh res://scenes/showcase/ship_showcase.tscn ship_sail 3 8 -- shot=sailing
##
## User args (after `--`):
##   shot=sailing|storm|sunset|damage|broadside|helm|hold   (default sailing)
##   time=<0..24>   override time of day
##   storm=<0..1>   override weather storminess
##   livery=player|drowned|ghost   optional ship livery

const SKY_RIG: PackedScene = preload("res://src/sky/sky_rig.tscn")
const OCEAN_SCENE: PackedScene = preload("res://src/ocean/ocean.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

var _args: Dictionary = {}
var _shot: String = "sailing"
var _ship: Ship
var _target_ship: Ship = null
var _pawn: Pawn = null
var _cam: Camera3D
var _clock: float = 0.0
var _fired: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_shot = String(_args.get("shot", "sailing"))

	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false

	var time_h := 11.2
	var storm := 0.12
	var wind_spd := 10.5
	var wind_hdg := 0.25
	match _shot:
		"storm":
			time_h = 15.0
			storm = 0.95
			wind_spd = 21.0
			wind_hdg = 0.75
		"sunset":
			time_h = 17.85
			storm = 0.22
			wind_spd = 9.5
			wind_hdg = 0.4
		"damage", "hold":
			time_h = 13.0
			storm = 0.28
			wind_spd = 9.0
		"broadside":
			time_h = 14.5
			storm = 0.18
			wind_spd = 9.5

	if _args.has("time"):
		time_h = float(_args["time"])
	if _args.has("storm"):
		storm = float(_args["storm"])

	Weather.time_of_day = time_h
	Weather.set_weather(storm, wind_spd, wind_hdg, 0.0, lerpf(0.38, 1.0, storm))
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	Sea.time = 24.0

	add_child(SKY_RIG.instantiate())
	add_child(OCEAN_SCENE.instantiate())

	_ship = SLOOP_SCENE.instantiate() as Ship
	add_child(_ship)
	_ship.global_position = Vector3(0.0, Sea.height(0.0, 0.0), 0.0)
	_ship.set_sail_target(1.0)
	_ship.sail_set = 1.0
	_ship.set_trim_target(_ship.ideal_sail_trim())
	_ship.sail_trim = _ship.trim_target
	_ship.linear_velocity = Vector3(0.0, 0.0, -5.8)

	var liv := String(_args.get("livery", "player"))
	if liv == "drowned":
		_ship.apply_livery(Color(0.32, 0.38, 0.34), Color(0.18, 0.55, 0.42), Color(0.16, 0.95, 0.62))
	elif liv == "ghost":
		_ship.apply_livery(Color(0.45, 0.92, 0.88), Color(0.35, 0.95, 0.9), Color(0.25, 0.98, 0.85))

	if _shot == "damage" or _shot == "hold":
		_ship.apply_hull_damage(_ship.global_transform * Vector3(2.0, -0.35, 0.4), 0.55)
		_ship.apply_hull_damage(_ship.global_transform * Vector3(-2.0, -0.35, -1.2), 0.55)
		_ship.apply_hull_damage(_ship.global_transform * Vector3(1.9, -0.3, -2.5), 0.5)
		_ship.patch_hole(0)
		_ship.water_level = 0.26

	if _shot == "broadside":
		_target_ship = SLOOP_SCENE.instantiate() as Ship
		_target_ship.faction = &"drowned"
		add_child(_target_ship)
		_target_ship.global_position = Vector3(38.0, Sea.height(38.0, -6.0), -6.0)
		_target_ship.apply_livery(Color(0.3, 0.36, 0.33), Color(0.2, 0.6, 0.46), Color(0.18, 0.95, 0.6))
		_target_ship.set_sail_target(0.6)
		_target_ship.sail_set = 0.6
		_ship.aim_cannon(&"starboard", 0.0, 0.09)

	_pawn = PAWN_SCENE.instantiate() as Pawn
	add_child(_pawn)
	var helm_st := _ship.get_station(&"helm")
	if helm_st != null:
		_pawn.board(_ship, Vector3(0.0, 2.02, 5.9))
		_pawn.enter_station(helm_st)

	_cam = Camera3D.new()
	_cam.fov = 66.0
	_cam.near = 0.08
	_cam.far = 6000.0
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _process(delta: float) -> void:
	_clock += delta
	if _shot == "broadside" and not _fired and _clock > 0.45:
		_fired = true
		_ship.fire_cannon(&"starboard", _pawn)
	_update_camera()


func _update_camera() -> void:
	var xf := _ship.global_transform
	var pos := xf.origin
	# Ship bow faces local -Z (xf.basis.z points aft), so atan2(z.x, z.z) aligns with ship yaw.
	var yaw := Basis(Vector3.UP, atan2(xf.basis.z.x, xf.basis.z.z))
	match _shot:
		"helm":
			# Over-the-shoulder helm framing showing Captain gripping wheel, deck, sail, and horizon.
			var eye := xf * Vector3(0.85, 3.65, 7.1)
			var look := xf * Vector3(-0.15, 2.85, -10.0)
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"hold":
			var eye := xf * Vector3(-0.35, 0.68, 4.3)
			var look := xf * Vector3(0.2, -0.3, -1.8)
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"damage":
			var eye := pos + yaw * Vector3(11.0, 3.0, 2.0)
			_cam.look_at_from_position(eye, pos + Vector3(0.0, 0.8, 0.0), Vector3.UP)
		"broadside":
			var eye := pos + yaw * Vector3(-11.0, 6.5, 16.0)
			_cam.look_at_from_position(eye, pos + Vector3(18.0, 1.5, -4.0), Vector3.UP)
		"storm":
			var ang := 0.58 + _clock * 0.12
			var eye := pos + yaw * Vector3(sin(ang) * 23.5, 5.8, -cos(ang) * 23.5)
			eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 2.4)
			_cam.look_at_from_position(eye, pos + Vector3(0.0, 4.2, -1.0), Vector3.UP)
		_:
			# Quarter-bow hero view showing figurehead, bow wave, billowing sail, and pennant.
			var ang := 0.66 + _clock * 0.10
			var eye := pos + yaw * Vector3(sin(ang) * 22.5, 4.8, -cos(ang) * 22.5)
			eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 2.2)
			_cam.look_at_from_position(eye, pos + Vector3(0.0, 4.8, -1.0), Vector3.UP)
