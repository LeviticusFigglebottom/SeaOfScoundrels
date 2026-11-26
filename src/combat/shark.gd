class_name Shark
extends Node3D
## Stylized ocean shark predator: circles swimmers with its dorsal fin slicing the
## surface, telegraphs a high-speed lunge bite, and retreats briefly after attacking.

signal bit_target(target: Pawn, damage: float)

enum State { CIRCLE, CHARGE, RETREAT }

@export var max_health: float = 80.0
@export var circle_radius: float = 8.5
@export var swim_speed: float = 5.2
@export var charge_speed: float = 9.4
@export var bite_damage: float = 28.0

var health: float = 80.0
var dead: bool = false
var faction: StringName = &"beast"
var target: Pawn = null
var state: State = State.CIRCLE

var _angle: float = 0.0
var _state_timer: float = 3.5
var _tail_phase: float = 0.0
var _tail_node: Node3D = null
var _jaw_node: Node3D = null
var _center: Vector3 = Vector3.ZERO


func _ready() -> void:
	health = max_health
	_center = global_position
	add_to_group(&"sharks")
	add_to_group(&"beasts")
	_build_mesh()
	_build_hitbox()


func _build_hitbox() -> void:
	var body := StaticBody3D.new()
	body.name = "SharkHitbox"
	body.collision_layer = Pawn.LAYER_PAWN
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 2.6
	cs.shape = cap
	cs.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	body.add_child(cs)
	add_child(body)


func _build_mesh() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.24, 0.34, 0.42)
	body_mat.roughness = 0.40
	var belly_mat := StandardMaterial3D.new()
	belly_mat.albedo_color = Color(0.78, 0.84, 0.86)
	belly_mat.roughness = 0.52
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.06, 0.08)
	eye_mat.roughness = 0.15

	# Chunky stylized fuselage (-Z nose).
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.42
	cap.height = 2.6
	cap.radial_segments = 10
	cap.rings = 4
	body.mesh = cap
	body.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	body.scale = Vector3(1.0, 1.0, 0.85)
	body.material_override = body_mat
	add_child(body)

	var belly := MeshInstance3D.new()
	var bcap := CapsuleMesh.new()
	bcap.radius = 0.34
	bcap.height = 2.1
	belly.mesh = bcap
	belly.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	belly.position = Vector3(0.0, -0.14, 0.0)
	belly.material_override = belly_mat
	add_child(belly)

	# Glossy predator eyes & snapping lower jaw.
	for sg: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var esph := SphereMesh.new()
		esph.radius = 0.06
		esph.height = 0.12
		esph.radial_segments = 8
		esph.rings = 4
		eye.mesh = esph
		eye.position = Vector3(sg * 0.28, 0.08, -0.82)
		eye.material_override = eye_mat
		add_child(eye)

	_jaw_node = Node3D.new()
	_jaw_node.position = Vector3(0.0, -0.14, -0.78)
	add_child(_jaw_node)
	var jaw := MeshInstance3D.new()
	var jbox := BoxMesh.new()
	jbox.size = Vector3(0.36, 0.12, 0.48)
	jaw.mesh = jbox
	jaw.position = Vector3(0.0, -0.04, -0.16)
	jaw.material_override = belly_mat
	_jaw_node.add_child(jaw)

	# Iconic dorsal fin breaking the surface.
	var fin := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.10, 0.72, 0.65)
	fin.mesh = prism
	fin.position = Vector3(0.0, 0.52, 0.1)
	fin.rotation_degrees = Vector3(-16.0, 0.0, 0.0)
	fin.material_override = body_mat
	add_child(fin)

	# Pectoral fins.
	for sg: float in [-1.0, 1.0]:
		var pfin := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.85, 0.07, 0.38)
		pfin.mesh = pbox
		pfin.position = Vector3(sg * 0.55, -0.12, -0.25)
		pfin.rotation_degrees = Vector3(0.0, sg * 24.0, -sg * 16.0)
		pfin.material_override = body_mat
		add_child(pfin)

	# Sweeping tail pivot.
	_tail_node = Node3D.new()
	_tail_node.position = Vector3(0.0, 0.0, 1.25)
	add_child(_tail_node)
	var tail := MeshInstance3D.new()
	var tprism := PrismMesh.new()
	tprism.size = Vector3(0.10, 0.95, 0.55)
	tail.mesh = tprism
	tail.position = Vector3(0.0, 0.05, 0.32)
	tail.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	tail.material_override = body_mat
	_tail_node.add_child(tail)


func apply_damage(amount: float, _from: Node = null) -> void:
	if not Net.is_host() or dead:
		return
	health -= amount
	Audio.play_sfx(&"hit_flesh", global_position)
	if health <= 0.0:
		dead = true
		queue_free()
		return
	# Taking a hit scares the shark into a brief retreat!
	state = State.RETREAT
	_state_timer = 3.2


func _physics_process(delta: float) -> void:
	if dead:
		return
	_tail_phase += delta * (11.0 if state == State.CHARGE else 6.5)
	if _tail_node != null:
		_tail_node.rotation.y = sin(_tail_phase) * 0.45
	if _jaw_node != null:
		var want_jaw := 0.42 if state == State.CHARGE else 0.04
		_jaw_node.rotation.x = lerpf(_jaw_node.rotation.x, want_jaw, clampf(delta * 8.0, 0.0, 1.0))

	if not Net.is_host():
		return

	if target == null or not is_instance_valid(target) or target.dead or not target.is_swimming():
		target = _find_swimmer()

	var center := target.global_position if target != null else _center
	_state_timer -= delta

	var goal := global_position
	var spd := swim_speed
	match state:
		State.CIRCLE:
			_angle += (swim_speed / maxf(circle_radius, 2.0)) * delta
			goal = center + Vector3(cos(_angle) * circle_radius, 0.0, sin(_angle) * circle_radius)
			if target != null and _state_timer <= 0.0:
				state = State.CHARGE
				_state_timer = 2.8
				Audio.play_sfx(&"splash_small", global_position, 1.0)
		State.CHARGE:
			spd = charge_speed
			if target != null:
				goal = target.global_position
				if global_position.distance_to(target.global_position) < 1.65:
					target.apply_damage(bite_damage, self)
					Audio.play_sfx(&"splash_large", global_position, -2.0)
					bit_target.emit(target, bite_damage)
					state = State.RETREAT
					_state_timer = 3.6
			if _state_timer <= 0.0:
				state = State.RETREAT
				_state_timer = 2.5
		State.RETREAT:
			var away := (global_position - center)
			away.y = 0.0
			var dir := away.normalized() if away.length_squared() > 0.01 else Vector3.RIGHT
			goal = center + dir * (circle_radius + 4.0)
			if _state_timer <= 0.0:
				state = State.CIRCLE
				_state_timer = 3.5

	var step := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if step.length_squared() > 0.01:
		var fwd := step.normalized()
		global_position += fwd * spd * delta
		var target_yaw := atan2(-fwd.x, -fwd.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 5.0, 0.0, 1.0))

	# Ride just under the visible wave surface so the dorsal fin slices the water!
	var surf := Sea.height(global_position.x, global_position.z)
	var depth_off := -0.35 if state == State.CIRCLE else -0.22
	global_position.y = lerpf(global_position.y, surf + depth_off, clampf(delta * 8.0, 0.0, 1.0))
	if Ocean.current != null:
		if state == State.CHARGE:
			Ocean.current.add_foam(global_position, 1.15, 0.42)
		else:
			Ocean.current.add_foam(global_position, 0.65, 0.14)


func _find_swimmer() -> Pawn:
	var best: Pawn = null
	var best_d := 65.0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc != null and cc.pawn != null and not cc.pawn.dead and cc.pawn.is_swimming():
			var d := global_position.distance_to(cc.pawn.global_position)
			if d < best_d:
				best_d = d
				best = cc.pawn
	return best
