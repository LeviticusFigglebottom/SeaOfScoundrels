class_name Ladder
extends Area3D
## A climb area. Works on land and on ships (make it a descendant of the ship
## body: the climber is then carried with the ship).
##
## Local frame: origin at the foot of the ladder on the wall surface, +Y up
## along the rungs, +Z pointing OUT of the wall (the climber hangs on the +Z
## side, facing -Z). Hull ladders should start about 1.5 m below the waterline
## so swimmers can reach them, and end at the height of the deck (or rail) the
## climber steps onto.
##
## Pawns find ladders through the `ladders` group and a geometric test, not
## through area overlap signals, so climbing is deterministic on moving ships.

const LAYER := 1 << 6
const GROUP := &"ladders"

@export var height: float = 3.0
@export var width: float = 0.8
## Distance of the climber's centreline from the wall.
@export var standoff: float = 0.4
## Where the climber is put when stepping off the top, relative to the top
## point (0, height, 0). -Z is into the wall, i.e. onto the deck.
@export var exit_offset: Vector3 = Vector3(0.0, 0.08, -0.75)
## How far below the foot a swimmer can still grab the lowest rung.
@export var reach_below: float = 1.7

func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false

func _ready() -> void:
	add_to_group(GROUP)
	if get_child_count() == 0:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, height, standoff * 2.0)
		cs.shape = box
		cs.position = Vector3(0.0, height * 0.5, standoff)
		add_child(cs)

## Horizontal world direction pointing into the wall.
func into_dir() -> Vector3:
	var d := -global_transform.basis.z
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD

## The rideable body (group `ship`) this ladder is fixed to, or null.
func get_platform() -> PhysicsBody3D:
	var n := get_parent()
	while n != null:
		if n is PhysicsBody3D and n.is_in_group(&"ship"):
			return n
		n = n.get_parent()
	return null
