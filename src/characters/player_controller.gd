class_name PlayerController
extends Node3D
## Local player: turns input into the parent Pawn's intent and owns the
## first-person camera. Add it as a child of a Pawn.
##
## * Mouse look with a captured mouse; `pause` releases and re-captures it.
## * Camera at eye height with a subtle head bob and a landing dip. The camera
##   is a child of the pawn, so it moves with the deck in the same physics
##   tick as the ship and never lags or stutters against it. Ship yaw reaches
##   the view through `Pawn.look_yaw`; roll and pitch do not tilt the view
##   (the horizon stays level, the deck is seen to roll).
## * Picks the Interactable in view (ray first, then nearest inside a cone),
##   stores it in `Pawn.focus` and exposes `focus_prompt` for the HUD.
## * While the pawn crews a station, movement input goes to
##   `station.drive(axis, primary, secondary, delta)` and looking stays free;
##   `leave_station` steps away.
## * While hauling, `interact` or `secondary` drops (interact on a container
##   hands the load over).

@export var mouse_sensitivity: float = 0.0023
@export var capture_mouse: bool = true
## Read the keyboard and mouse. Off, the controller is only a camera (used by
## the showcase, where a bot drives the pawn).
@export var input_enabled: bool = true
@export var make_current: bool = true
@export var fov: float = 80.0
@export var bob_amount: float = 0.028
@export var interact_reach: float = 2.8
@export var focus_cone_deg: float = 22.0

const PITCH_LIMIT := 1.5

var pawn: Pawn
var camera: Camera3D
## Text for the HUD: what `interact` would do right now. Empty if nothing.
var focus_prompt: String = ""
## True while the mouse is released by `pause`.
var look_paused: bool = false

var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _dip: float = 0.0
var _dip_vel: float = 0.0
var _trauma: float = 0.0
var _trauma_clock: float = 0.0

func _init() -> void:
	# Run before the pawn so intent is applied in the same tick.
	process_physics_priority = -10

func _ready() -> void:
	pawn = get_parent() as Pawn
	assert(pawn != null, "PlayerController must be a child of a Pawn")
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = fov
	camera.near = 0.08
	camera.far = 4000.0
	add_child(camera)
	if make_current:
		camera.make_current()
	pawn.landed.connect(_on_landed)
	_capture(true)
	_update_camera(0.0)

func _exit_tree() -> void:
	if capture_mouse and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _capture(on: bool) -> void:
	if not capture_mouse or not input_enabled or DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func set_look_paused(paused: bool) -> void:
	look_paused = paused
	_capture(not paused)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and capture_mouse and input_enabled:
		set_look_paused(true)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed(&"pause"):
		set_look_paused(not look_paused)
	elif look_paused:
		if event is InputEventMouseButton and event.pressed:
			set_look_paused(false)
	elif event is InputEventMouseMotion:
		add_look(event.relative)

## Apply a look delta in mouse pixels (also usable for gamepad or tests).
func add_look(relative: Vector2) -> void:
	pawn.look_yaw = wrapf(pawn.look_yaw - relative.x * mouse_sensitivity, -PI, PI)
	pawn.look_pitch = clampf(pawn.look_pitch - relative.y * mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
	if pawn.station != null and is_instance_valid(pawn.station):
		var sk_v: Variant = pawn.station.get(&"kind")
		if sk_v != null and StringName(sk_v) == &"cannon":
			var st_ship: Variant = pawn.station.get(&"ship")
			if st_ship is Node and is_instance_valid(st_ship) and (st_ship as Node).has_method(&"aim_cannon_delta"):
				var mid_v: Variant = pawn.station.get(&"meta_id")
				var side: StringName = StringName(mid_v) if mid_v != null else &""
				(st_ship as Node).call(&"aim_cannon_delta", side, -relative.x * 0.0018, -relative.y * 0.0016)

func _physics_process(delta: float) -> void:
	_update_focus()
	if not input_enabled:
		return
	if look_paused or pawn.dead:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		pawn.wish_jump = false
		return
	var axis := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back"))
	if axis.length() > 1.0:
		axis = axis.normalized()
	var primary := Input.is_action_pressed(&"primary")
	var secondary := Input.is_action_pressed(&"secondary")
	if pawn.station != null:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		pawn.wish_jump = false
		if Input.is_action_just_pressed(&"leave_station") or Input.is_action_just_pressed(&"interact"):
			pawn.leave_station()
		else:
			pawn.drive_station(axis, primary, secondary, delta)
		return
	var b := Basis(Vector3.UP, pawn.look_yaw)
	pawn.wish_dir = b * Vector3(axis.x, 0.0, -axis.y)
	pawn.wish_sprint = Input.is_action_pressed(&"sprint") and axis.y > 0.1
	pawn.wish_jump = Input.is_action_pressed(&"jump")
	if Input.is_action_just_pressed(&"interact"):
		pawn.interact()
	elif pawn.carried != null and Input.is_action_just_pressed(&"secondary"):
		pawn.drop_carried()

# ------------------------------------------------------------------- focus

func _update_focus() -> void:
	var found: Interactable = null
	if not pawn.dead and pawn.station == null:
		found = _find_focus()
	pawn.focus = found
	if pawn.station != null:
		var ap := ""
		if pawn.station.has_method(&"get_active_prompt"):
			ap = String(pawn.station.call(&"get_active_prompt"))
		focus_prompt = ap if ap != "" else "Step away"
	elif pawn.carried != null:
		var cont := pawn._container_of(found)
		focus_prompt = found.prompt if cont != null else "Drop"
	elif found != null:
		var st := Pawn.station_of(found)
		if st != null and st.has_method(&"get_focus_prompt"):
			var fp := String(st.call(&"get_focus_prompt"))
			focus_prompt = fp if fp != "" else found.prompt
		else:
			focus_prompt = found.prompt
	else:
		focus_prompt = ""

func _find_focus() -> Interactable:
	var eye := pawn.eye_position()
	var dir := pawn.view_dir()
	var space := get_world_3d().direct_space_state
	# 1. Straight ray: the thing under the crosshair.
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * interact_reach,
		Pawn.LAYER_WORLD | Pawn.LAYER_SHIP | Interactable.LAYER, [pawn.get_rid()])
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.collider is Interactable:
		var it := hit.collider as Interactable
		if it.can_interact(pawn) and _usable(it):
			return it
	# 2. Nearest to the view axis inside a cone, with line of sight.
	var best: Interactable = null
	var best_score := cos(deg_to_rad(focus_cone_deg))
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := n as Interactable
		if it == null or not it.can_interact(pawn) or not _usable(it):
			continue
		var to := it.global_position - eye
		var dist := to.length()
		if dist > minf(interact_reach, it.reach) or dist < 0.05:
			continue
		var score := to.dot(dir) / dist
		if score <= best_score:
			continue
		var los := PhysicsRayQueryParameters3D.create(eye, it.global_position,
			Pawn.LAYER_WORLD | Pawn.LAYER_SHIP, [pawn.get_rid()])
		var block := space.intersect_ray(los)
		if not block.is_empty() and eye.distance_to(block.position) < dist - 0.3:
			continue
		best = it
		best_score = score
	return best

func _usable(it: Interactable) -> bool:
	# Hauling: only containers are worth pointing at.
	if pawn.carried != null:
		return pawn._container_of(it) != null
	return true

# ------------------------------------------------------------------ camera

## Add accessibility-gated camera shake trauma (0..1). Ignored when head-bob is disabled.
func add_camera_trauma(amount: float) -> void:
	if bob_amount <= 0.001:
		return
	_trauma = clampf(_trauma + maxf(amount, 0.0), 0.0, 1.0)

## Current normalized camera shake trauma (0..1).
func get_camera_trauma() -> float:
	return _trauma

func _on_landed(impact_speed: float) -> void:
	_dip_vel -= clampf(impact_speed * 0.11, 0.2, 1.3)

func _process(delta: float) -> void:
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	if pawn == null:
		return
	# Head bob follows distance walked RELATIVE to the deck.
	var rel := pawn.get_relative_velocity()
	var speed := Vector2(rel.x, rel.z).length()
	var walking := pawn.is_grounded() and speed > 0.4
	_bob_weight = move_toward(_bob_weight, 1.0 if walking else 0.0, delta * 5.0)
	if walking:
		_bob_phase = fmod(_bob_phase + speed * delta * 3.6, TAU)
	# Landing dip: a critically damped spring.
	_dip_vel += (-_dip * 180.0 - _dip_vel * 24.0) * delta
	_dip = clampf(_dip + _dip_vel * delta, -0.22, 0.05)
	var bob_y := sin(_bob_phase * 2.0) * bob_amount * _bob_weight
	var bob_x := cos(_bob_phase) * bob_amount * 0.6 * _bob_weight
	position = Vector3(0.0, pawn.current_eye_height + pawn.visual_offset_y, 0.0)
	var b := Basis(Vector3.UP, pawn.look_yaw) * Basis(Vector3.RIGHT, pawn.look_pitch)
	var cam_pos := Vector3(0.0, bob_y + _dip, 0.0) + b.x * bob_x
	_trauma = maxf(0.0, _trauma - delta * 1.85)
	if _trauma > 0.001 and bob_amount > 0.001:
		var sh := _trauma * _trauma
		_trauma_clock += delta * 26.0
		var t := _trauma_clock
		var shake_pitch := (sin(t * 1.13 + 0.4) * 0.65 + cos(t * 2.37) * 0.35) * 0.022 * sh
		var shake_roll := (cos(t * 1.41 + 1.1) * 0.65 + sin(t * 2.83) * 0.35) * 0.028 * sh
		var shake_x := (sin(t * 1.73 + 2.0) * 0.65 + cos(t * 3.11) * 0.35) * 0.045 * sh
		var shake_y := (cos(t * 1.29 + 0.7) * 0.65 + sin(t * 2.61) * 0.35) * 0.027 * sh
		b = b * Basis(Vector3.RIGHT, shake_pitch) * Basis(Vector3.BACK, shake_roll)
		cam_pos += b.x * shake_x + b.y * shake_y
	elif _trauma_clock > 10000.0:
		_trauma_clock = 0.0
	camera.transform = Transform3D(b, cam_pos)
