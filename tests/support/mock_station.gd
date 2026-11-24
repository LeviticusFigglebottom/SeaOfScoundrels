class_name MockStation
extends Node3D
## Minimal stand-in that follows the Station contract in ARCHITECTURE.md.
## Deliberately does NOT use `class_name Station`, which belongs to src/ship.

var kind: StringName = &"helm"
var occupant: Node = null
var prompt: String = "Take the helm"
## Local to this node: where the occupant stands (facing -Z).
var stand_point: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.7))

# Recorded for tests.
var value: float = 0.0
var last_axis: Vector2 = Vector2.ZERO
var primary_ticks: int = 0
var secondary_ticks: int = 0
var drive_calls: int = 0
var interactable: Interactable

func _ready() -> void:
	interactable = Interactable.create(prompt, 0.45)
	interactable.position = Vector3(0.0, 1.0, 0.0)
	add_child(interactable)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 1.0, 0.3)
	mi.mesh = bm
	mi.position = Vector3(0.0, 0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.7, 0.2)
	mi.material_override = m
	add_child(mi)

func can_occupy(_pawn: Node) -> bool:
	return occupant == null

func occupy(pawn: Node) -> void:
	if occupant == null:
		occupant = pawn

func release() -> void:
	occupant = null

func drive(axis: Vector2, primary: bool, secondary: bool, delta: float) -> void:
	drive_calls += 1
	last_axis = axis
	value = clampf(value + axis.x * delta, -1.0, 1.0)
	if primary:
		primary_ticks += 1
	if secondary:
		secondary_ticks += 1
