extends Node3D
## Pawn showcase: a mock ship deck in swell, a bot-driven pawn, two cameras.
##
##   tools/capture.sh res://scenes/showcase/pawn_showcase.tscn pawn_deck 4 8 -- shot=deck
##
## User args (after `--`):
##   shot=deck        laps of the deck, stairs to the quarterdeck, ramp, jumps (observer camera)
##   shot=overboard   vault the rail, swim to the hull ladder, climb back aboard (observer camera)
##   shot=firstperson the deck lap seen through the PlayerController camera
##   shot=hold        down the companion ramp into the hold and back
##   cam=fp|observer  override the camera
##   skip=<seconds>   fast-forward the simulation (4x) before settling to real time; approximate
##   storm=<0..1>     sea state (default 0.45)
## Without args (run by hand) you get shot=deck; press C to swap cameras.

const PAWN := preload("res://src/characters/pawn.tscn")

var deck: MockDeck
var pawn: Pawn
var bot: BotController
var player: PlayerController
var observer: Camera3D
var shot := "deck"
var use_fp := false
var skip := 0.0

var _skip_left := 0.0
var _cam_z := 0.0

func _ready() -> void:
	Net.start_single_player()
	var cam_arg := ""
	var storm := 0.45
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = a.trim_prefix("shot=")
		elif a.begins_with("cam="):
			cam_arg = a.trim_prefix("cam=")
		elif a.begins_with("skip="):
			skip = float(a.trim_prefix("skip="))
		elif a.begins_with("storm="):
			storm = float(a.trim_prefix("storm="))
	use_fp = shot == "firstperson"
	if cam_arg != "":
		use_fp = cam_arg == "fp"
	Weather.storminess = storm
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	_build_world()

	deck = MockDeck.new()
	deck.follow_sea = true
	deck.roll_deg = 9.0
	deck.pitch_deg = 3.0
	if shot == "overboard":
		deck.speed = 0.0
		deck.yaw_rate = 0.03
		deck.roll_deg = 6.0
	else:
		deck.speed = 6.0
		deck.yaw_rate = 0.07
	add_child(deck)

	pawn = PAWN.instantiate()
	add_child(pawn)
	pawn.board(deck, Vector3(1.4, 1.12, -2.0))
	bot = BotController.new()
	pawn.add_child(bot)
	player = PlayerController.new()
	player.input_enabled = false
	player.capture_mouse = false
	player.make_current = false
	pawn.add_child(player)

	observer = Camera3D.new()
	observer.fov = 60.0
	observer.far = 4000.0
	add_child(observer)
	_update_observer(1.0)
	_apply_camera()

	match shot:
		"overboard":
			bot.run(_overboard_steps())
		"hold":
			bot.run(_hold_steps(), true)
		_:
			bot.run(_deck_steps(), true)

	_set_fast(false)
	if skip > 0.0:
		_skip_left = skip
		_set_fast(true)

func _set_fast(on: bool) -> void:
	# More ticks per frame with the same 1/60 s step.
	var k := 4 if on else 1
	Engine.physics_ticks_per_second = 60 * k
	Engine.time_scale = float(k)
	Engine.max_physics_steps_per_frame = 400 if on else 30

func _deck_steps() -> Array:
	var d := deck
	return [
		{goto = Vector3(1.4, 0, -5.4), frame = d},
		{goto = Vector3(-1.5, 0, -5.4), frame = d},
		{goto = Vector3(-1.6, 0, 1.0), frame = d},
		{goto = Vector3(-1.6, 0, 4.4), frame = d},          # up the stairs
		{goto = Vector3(0.0, 0, 5.4), frame = d},
		{wait = 0.4},
		{jump = true}, {wait = 0.9},
		{goto = Vector3(1.6, 0, 4.2), frame = d},
		{goto = Vector3(1.6, 0, 0.6), frame = d},           # down the ramp
		{goto = Vector3(1.4, 0, -2.0), frame = d, sprint = true},
		{jump = true}, {wait = 0.8},
	]

func _hold_steps() -> Array:
	var d := deck
	return [
		{goto = Vector3(0.0, 0, 0.3), frame = d},
		{goto = Vector3(0.0, 0, -3.1), frame = d},
		{goto = Vector3(1.4, 0, -4.8), frame = d},
		{wait = 0.6},
		{goto = Vector3(0.0, 0, -3.0), frame = d},
		{goto = Vector3(0.0, 0, 0.6), frame = d},
		{goto = Vector3(1.4, 0, -2.0), frame = d},
	]

func _overboard_steps() -> Array:
	var d := deck
	return [
		{goto = Vector3(0.9, 0, -3.6), frame = d},
		{wait = 0.6},
		{move = Vector3(1, 0, 0), time = 0.12, frame = d, sprint = true},
		{move = Vector3(1, 0, 0), time = 0.9, frame = d, sprint = true, jump = true},
		{wait = 1.6},
		{goto = Vector3(3.6, 0, -1.5), frame = d, timeout = 10.0},
		{goto = Vector3(3.3, 0, 0.0), frame = d, timeout = 10.0},
		{goto = Vector3(1.0, 0, 0.0), frame = d, timeout = 8.0},   # grab the ladder, climb, step aboard
		{goto = Vector3(1.4, 0, -2.0), frame = d},
		{wait = 2.0},
	]

func _build_world() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(500, 500)
	mesh.subdivide_width = 250
	mesh.subdivide_depth = 250
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/placeholder_ocean.gdshader")
	Sea.bind_material(mat)
	var sea := MeshInstance3D.new()
	sea.name = "SeaPlane"
	sea.mesh = mesh
	sea.material_override = mat
	sea.extra_cull_margin = 20.0
	add_child(sea)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)

func _apply_camera() -> void:
	if use_fp:
		player.camera.make_current()
	else:
		observer.make_current()
	var v := pawn.get_node_or_null(^"Visual") as Node3D
	if v != null:
		v.visible = not use_fp

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
		use_fp = not use_fp
		_apply_camera()

func _physics_process(delta: float) -> void:
	if _skip_left > 0.0:
		_skip_left -= delta
		if _skip_left <= 0.0:
			_set_fast(false)

func _process(delta: float) -> void:
	# Keep the sea plane under the action (snapped so the mesh does not swim).
	var sp := get_node(^"SeaPlane") as Node3D
	sp.position = Vector3(snappedf(deck.global_position.x, 2.0), 0.0, snappedf(deck.global_position.z, 2.0))
	_update_observer(delta)

## Chase camera that follows the ship's position and heading but NOT its roll,
## pitch or heave, so the deck's motion (and whether the pawn stays planted on
## it) is plain to see.
func _update_observer(blend: float) -> void:
	var yaw := Basis(Vector3.UP, deck.heading)
	var off := Vector3(5.5, 5.0, 3.5)
	var look := Vector3(0.0, 1.6, 0.0)
	if shot == "overboard":
		off = Vector3(9.0, 3.6, 2.5)
		look = Vector3(2.2, 0.6, -1.2)
	elif shot == "hold":
		off = Vector3(0.0, 8.0, 2.0)
		look = Vector3(0.0, 0.0, -2.5)
	var base := Vector3(deck.path_pos.x, 0.0, deck.path_pos.z)
	if shot == "deck" or shot == "firstperson":
		# Slide along the ship with the pawn, still without roll or heave.
		var pl := deck.global_transform.affine_inverse() * pawn.global_position
		_cam_z = lerpf(_cam_z, clampf(pl.z, -4.0, 4.0), clampf(blend * 2.0, 0.0, 1.0))
		off.z += _cam_z
		look.z += _cam_z
	observer.global_position = base + yaw * off
	observer.look_at(base + yaw * look, Vector3.UP)
