extends Node3D
## AI Crew showcase: full crew of 3 original AI mates sailing, trimming, repairing,
## and fighting aboard the real Sloop on the real Ocean under the real SkyRig.
##
##   tools/capture.sh res://scenes/showcase/crew_showcase.tscn crew_sail 3 8 -- shot=sailing
##
## User args (after `--`):
##   shot=sailing|repair|broadside   (default sailing)

const SKY_RIG: PackedScene = preload("res://src/sky/sky_rig.tscn")
const OCEAN_SCENE: PackedScene = preload("res://src/ocean/ocean.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

var _shot: String = "sailing"
var _ship: Ship
var _cam: Camera3D
var _clock: float = 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			_shot = a.trim_prefix("shot=")

	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.time_of_day = 11.5
	Weather.set_weather(0.15, 11.0, 0.35, 0.0, 0.42)
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.15)
	Sea.time = 18.0

	add_child(SKY_RIG.instantiate())
	add_child(OCEAN_SCENE.instantiate())

	_ship = SLOOP_SCENE.instantiate() as Ship
	add_child(_ship)
	_ship.global_position = Vector3(0.0, Sea.height(0.0, 0.0), 0.0)
	_ship.set_sail_target(1.0)
	_ship.sail_set = 1.0
	_ship.set_trim_target(-0.7)
	_ship.sail_trim = -0.7
	_ship.linear_velocity = Vector3(0.0, 0.0, -4.5)

	var captain := PAWN_SCENE.instantiate() as Pawn
	add_child(captain)
	captain.board(_ship, Vector3(-0.6, 2.02, 4.9))

	var crew_defs: Array[Array] = [
		[&"helmsman", Vector3(0.0, 2.02, 5.7), &"helm"],
		[&"lookout", Vector3(0.7, 1.12, -1.6), &"auto"],
		[&"carpenter", Vector3(0.8, 1.12, 0.6), &"trim"],
	]
	for cd in crew_defs:
		var mate := PAWN_SCENE.instantiate() as Pawn
		add_child(mate)
		mate.board(_ship, cd[1])
		var brain := CrewBrain.new()
		brain.setup(_ship, captain, cd[0])
		mate.add_child(brain)
		if cd[2] != &"auto":
			brain.give_order(cd[2])

	if _shot == "repair":
		_ship.apply_hull_damage(_ship.global_transform * Vector3(2.0, -0.45, 0.4), 0.5)
		_ship.water_level = 0.25
	elif _shot == "broadside":
		var foe := SLOOP_SCENE.instantiate() as Ship
		foe.faction = &"drowned"
		add_child(foe)
		foe.global_position = Vector3(44.0, Sea.height(44.0, -4.0), -4.0)
		foe.apply_livery(Color(0.3, 0.36, 0.33), Color(0.2, 0.6, 0.45), Color(0.18, 0.95, 0.6))

	_cam = Camera3D.new()
	_cam.fov = 66.0
	_cam.near = 0.08
	_cam.far = 5000.0
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _process(delta: float) -> void:
	_clock += delta
	_update_camera()


func _update_camera() -> void:
	var xf := _ship.global_transform
	if _shot == "repair":
		var eye := xf * Vector3(-0.3, 0.65, 3.8)
		_cam.look_at_from_position(eye, xf * Vector3(0.4, -0.35, -0.5), Vector3.UP)
	else:
		var eye := xf * Vector3(-3.8, 4.6, 7.2)
		_cam.look_at_from_position(eye, xf * Vector3(0.2, 1.8, -1.8), Vector3.UP)
