class_name BotController
extends Node
## Scripted controller for tests and captures: feeds a list of steps into the
## parent Pawn's intent fields. Not an AI; see CrewBrain for that.
##
## Each step is a Dictionary. `frame` (a Node3D, usually the ship) makes
## positions and directions relative to that node; without it they are world.
##   {goto = Vector3, frame =, tol = 0.25, sprint = false, timeout = 8.0}
##   {move = Vector3 direction, time = 1.0, frame =, sprint = false, jump = false}
##   {wait = seconds}
##   {jump = true}                      one jump press (can be combined with move)
##   {look = yaw_radians, pitch = 0.0, frame =}   then continues
##   {interact = true} {leave = true} {drop = true}
##   {drive = Vector2, time = 1.0, primary = false, secondary = false}
##   {call = Callable}

signal finished

var pawn: Pawn
var steps: Array = []
var index: int = 0
var loop: bool = false
var done: bool = false
## Face the direction of travel.
var auto_face: bool = true
var turn_rate: float = 7.0

var _t: float = 0.0
var _started: bool = false

func _init() -> void:
	process_physics_priority = -10

func _ready() -> void:
	pawn = get_parent() as Pawn

func run(p_steps: Array, p_loop: bool = false) -> void:
	steps = p_steps
	loop = p_loop
	index = 0
	done = steps.is_empty()
	_t = 0.0
	_started = false

func _next() -> void:
	index += 1
	_t = 0.0
	_started = false
	if index >= steps.size():
		if loop and not steps.is_empty():
			index = 0
		else:
			done = true
			finished.emit()

func _dir(v: Vector3, frame: Node3D) -> Vector3:
	var d := frame.global_transform.basis * v if frame != null else v
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.000001 else Vector3.ZERO

func _face(dir: Vector3, delta: float) -> void:
	if not auto_face or dir.length_squared() < 0.01:
		return
	var want := atan2(-dir.x, -dir.z)
	var diff := wrapf(want - pawn.look_yaw, -PI, PI)
	pawn.look_yaw += clampf(diff, -turn_rate * delta, turn_rate * delta)

func _physics_process(delta: float) -> void:
	if pawn == null:
		return
	pawn.wish_dir = Vector3.ZERO
	pawn.wish_sprint = false
	pawn.wish_jump = false
	if done or index >= steps.size():
		return
	var s: Dictionary = steps[index]
	var frame: Node3D = s.get("frame")
	var first := not _started
	_started = true
	_t += delta
	if s.has("look"):
		var base := 0.0
		if frame != null:
			var f := -frame.global_transform.basis.z
			base = atan2(-f.x, -f.z)
		pawn.look_yaw = base + float(s.look)
		pawn.look_pitch = float(s.get("pitch", 0.0))
		if not (s.has("move") or s.has("goto") or s.has("wait")):
			_next()
			return
	if s.has("call"):
		(s["call"] as Callable).call()
		_next()
	elif s.has("interact"):
		pawn.interact()
		_next()
	elif s.has("leave"):
		pawn.leave_station()
		_next()
	elif s.has("drop"):
		pawn.drop_carried()
		_next()
	elif s.has("drive"):
		pawn.drive_station(s.drive, s.get("primary", false), s.get("secondary", false), delta)
		if _t >= float(s.get("time", 1.0)):
			_next()
	elif s.has("goto"):
		var target: Vector3 = s.goto
		if frame != null:
			target = frame.global_transform * target
		var to := target - pawn.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < float(s.get("tol", 0.25)) or _t > float(s.get("timeout", 8.0)):
			_next()
			return
		var dir := to / dist
		pawn.wish_dir = dir * minf(1.0, dist / 0.25 + 0.35)
		pawn.wish_sprint = s.get("sprint", false)
		pawn.wish_jump = s.get("jump", false) and first
		_face(dir, delta)
	elif s.has("move"):
		var dir := _dir(s.move, frame)
		pawn.wish_dir = dir
		pawn.wish_sprint = s.get("sprint", false)
		pawn.wish_jump = s.get("jump", false) and first
		if not s.has("look"):
			_face(dir, delta)
		if _t >= float(s.get("time", 1.0)):
			_next()
	elif s.has("jump"):
		pawn.wish_jump = true
		_next()
	elif s.has("wait"):
		if _t >= float(s.wait):
			_next()
	else:
		_next()
