class_name MockDeck
extends RigidBody3D
## Throwaway stand-in for the real Ship, for pawn tests and the pawn showcase.
##
## A RigidBody3D on layer 2 in group `ship`, like the real one, but driven
## along a scripted path: it sails forward, yaws, rolls, pitches and heaves
## (optionally on top of the real `Sea` surface). Each tick it sets the
## velocities that reach the next pose, so pawns see exactly what they would
## see from a simulated hull: a body whose transform changes in the physics
## step.
##
## Layout follows the sloop numbers in ARCHITECTURE.md: main deck y = 1.1,
## quarterdeck (z > 3) y = 2.0, hold floor y = -0.6, beam 4.4, length 13.
## Port side has stairs to the quarterdeck, starboard a ramp. A hatch with a
## ramp leads down to the hold. Hull ladders are amidships on both sides.

@export var speed: float = 0.0
@export var yaw_rate: float = 0.0
@export var roll_deg: float = 0.0
@export var roll_period: float = 6.0
@export var pitch_deg: float = 0.0
@export var pitch_period: float = 4.3
@export var heave: float = 0.0
@export var heave_period: float = 5.0
## Add the real sea surface height and slope at the hull's position.
@export var follow_sea: bool = false
@export var build_visuals: bool = true

const DECK_Y := 1.1
const QUARTER_Y := 2.0
const HOLD_Y := -0.6

var t: float = 0.0
var heading: float = 0.0
var path_pos: Vector3 = Vector3.ZERO
var ladder_port: Ladder
var ladder_starboard: Ladder

var _wood := Color(0.55, 0.36, 0.2)
var _wood_dark := Color(0.36, 0.23, 0.13)
var _wood_light := Color(0.7, 0.52, 0.32)
var _mats := {}

func _ready() -> void:
	add_to_group(&"ship")
	collision_layer = 1 << 1
	collision_mask = 0
	mass = 9000.0
	gravity_scale = 0.0
	custom_integrator = true
	can_sleep = false
	path_pos = global_position
	heading = global_rotation.y
	_build()

func deck_point(local: Vector3) -> Vector3:
	return global_transform * local

func pose_at(time: float) -> Transform3D:
	var roll := deg_to_rad(roll_deg) * sin(TAU * time / roll_period)
	var pitch := deg_to_rad(pitch_deg) * sin(TAU * time / pitch_period + 0.7)
	var y := heave * sin(TAU * time / heave_period + 1.3)
	if follow_sea:
		y += Sea.height(path_pos.x, path_pos.z) * 0.8
		var n := Sea.normal(path_pos.x, path_pos.z, 3.0)
		var fwd := Basis(Vector3.UP, heading) * Vector3.FORWARD
		var right := Basis(Vector3.UP, heading) * Vector3.RIGHT
		pitch += -asin(clampf(n.dot(fwd), -0.5, 0.5)) * 0.7
		roll += -asin(clampf(n.dot(right), -0.5, 0.5)) * 0.7
	var b := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(b, Vector3(path_pos.x, path_pos.y + y, path_pos.z))

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	t += dt
	heading += yaw_rate * dt
	path_pos += Basis(Vector3.UP, heading) * Vector3.FORWARD * speed * dt
	var target := pose_at(t)
	var cur := state.transform
	state.linear_velocity = (target.origin - cur.origin) / dt
	var q := (target.basis * cur.basis.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	var axis := Vector3(q.x, q.y, q.z)
	state.angular_velocity = axis.normalized() * angle / dt if axis.length_squared() > 1e-12 else Vector3.ZERO

# ------------------------------------------------------------------- build

func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		_mats[c] = m
	return _mats[c]

## Box given by its min and max corners in hull space.
func _box(a: Vector3, b: Vector3, color: Color, rot: Basis = Basis.IDENTITY, solid: bool = true) -> void:
	var size := (b - a).abs()
	var centre := (a + b) * 0.5
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = Transform3D(rot, centre)
		add_child(cs)
	if build_visuals:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _mat(color)
		mi.transform = Transform3D(rot, centre)
		add_child(mi)

## Sloped slab whose top surface runs from `lo` to `hi` (points on its centreline).
func _ramp(lo: Vector3, hi: Vector3, width: float, color: Color) -> void:
	var run := hi - lo
	var length := run.length()
	var ang := atan2(run.y, absf(run.z))
	var rot := Basis(Vector3.RIGHT, -ang if run.z > 0.0 else ang)
	var thick := 0.12
	var centre := (lo + hi) * 0.5 - rot.y * thick * 0.5
	var size := Vector3(width, thick, length)
	_box(centre - size * 0.5, centre + size * 0.5, color, rot)
	# _box computes centre from corners; rotation is about that centre.

func _build() -> void:
	var hw := 2.2
	# Hold floor and hull sides.
	_box(Vector3(-hw, HOLD_Y - 0.2, -6.5), Vector3(hw, HOLD_Y, 6.5), _wood_dark)
	_box(Vector3(-hw, HOLD_Y, -6.5), Vector3(-hw + 0.1, DECK_Y, 6.5), _wood_dark)
	_box(Vector3(hw - 0.1, HOLD_Y, -6.5), Vector3(hw, DECK_Y, 6.5), _wood_dark)
	_box(Vector3(-hw, HOLD_Y, -6.5), Vector3(hw, DECK_Y, -6.4), _wood_dark)
	# Main deck, 0.1 thick, with a hatch at x -0.6..0.6, z -3.2..-0.4.
	var d0 := DECK_Y - 0.1
	_box(Vector3(-hw, d0, -6.5), Vector3(-0.6, DECK_Y, 3.0), _wood)
	_box(Vector3(0.6, d0, -6.5), Vector3(hw, DECK_Y, 3.0), _wood)
	_box(Vector3(-0.6, d0, -6.5), Vector3(0.6, DECK_Y, -3.2), _wood)
	_box(Vector3(-0.6, d0, -0.4), Vector3(0.6, DECK_Y, 3.0), _wood)
	# Companion ramp from the deck down to the hold floor, descending forward.
	_ramp(Vector3(0.0, HOLD_Y, -3.0), Vector3(0.0, DECK_Y, -0.4), 1.2, _wood_light)
	# Quarterdeck block.
	_box(Vector3(-hw, HOLD_Y, 3.0), Vector3(hw, QUARTER_Y, 6.5), _wood)
	# Port stairs: 4 steps of 0.225 m.
	for i in 4:
		var z0 := 1.8 + 0.3 * i
		_box(Vector3(-2.1, DECK_Y, z0), Vector3(-1.1, DECK_Y + 0.225 * (i + 1), 3.0), _wood_light)
	# Starboard ramp.
	_ramp(Vector3(1.6, DECK_Y, 1.2), Vector3(1.6, QUARTER_Y, 3.0), 1.0, _wood_light)
	# Rails 0.8 m high, with gaps at the ladders (z -0.5..0.5).
	var rc := Color(0.3, 0.2, 0.12)
	for sx in [-1.0, 1.0]:
		var x0: float = sx * hw
		var x1: float = sx * (hw - 0.1)
		_box(Vector3(x0, DECK_Y, -6.5), Vector3(x1, DECK_Y + 0.8, -0.5), rc)
		_box(Vector3(x0, DECK_Y, 0.5), Vector3(x1, DECK_Y + 0.8, 3.0), rc)
		_box(Vector3(x0, QUARTER_Y, 3.0), Vector3(x1, QUARTER_Y + 0.8, 6.5), rc)
	_box(Vector3(-hw, DECK_Y, -6.5), Vector3(hw, DECK_Y + 0.8, -6.4), rc)
	_box(Vector3(-hw, QUARTER_Y, 6.4), Vector3(hw, QUARTER_Y + 0.8, 6.5), rc)
	# Mast (visual reference only, thin collision).
	_box(Vector3(-0.15, DECK_Y, -4.65), Vector3(0.15, DECK_Y + 9.0, -4.35), Color(0.45, 0.3, 0.16))
	_box(Vector3(-2.6, DECK_Y + 7.0, -4.55), Vector3(2.6, DECK_Y + 7.15, -4.45), Color(0.45, 0.3, 0.16), Basis.IDENTITY, false)
	# Hull ladders, foot 1.5 m below the waterline, top at deck level.
	ladder_starboard = _ladder(Vector3(hw + 0.02, -1.5, 0.0), PI * 0.5)
	ladder_port = _ladder(Vector3(-hw - 0.02, -1.5, 0.0), -PI * 0.5)

func _ladder(pos: Vector3, yaw: float) -> Ladder:
	var l := Ladder.new()
	l.height = DECK_Y - pos.y
	l.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(l)
	if build_visuals:
		var c := Color(0.85, 0.75, 0.5)
		for sx in [-0.3, 0.3]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.06, l.height, 0.06)
			mi.mesh = bm
			mi.material_override = _mat(c)
			mi.position = Vector3(sx, l.height * 0.5, 0.05)
			l.add_child(mi)
		var n := int(l.height / 0.3)
		for i in n:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.05, 0.05)
			mi.mesh = bm
			mi.material_override = _mat(c)
			mi.position = Vector3(0.0, 0.15 + 0.3 * i, 0.05)
			l.add_child(mi)
	return l
