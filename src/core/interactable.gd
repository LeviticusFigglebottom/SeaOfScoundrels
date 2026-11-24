class_name Interactable
extends Area3D
## Something a pawn can use: a station handle, a carryable, a door, a lever.
##
## Lives on collision layer 4 (interactables). Controllers find it with a ray or
## a view-cone search (group `interactables`) and give it to `Pawn.focus`;
## `Pawn.interact()` then calls `interact(pawn)` on the host, which emits
## `interacted`. Game objects connect to that signal.
##
## Station link: if this node's parent (or the node in `target`) looks like a
## Station (has `occupy` and `drive`), the pawn occupies it on interact.

signal interacted(pawn: Node)

const LAYER := 1 << 3
const GROUP := &"interactables"

## Text for the HUD, e.g. "Take the helm".
@export var prompt: String = "Use"
@export var enabled: bool = true
## Maximum distance from the pawn's eyes, metres.
@export var reach: float = 2.8
## Optional explicit owner object (station, container...). Defaults to the parent.
var target: Node = null

func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true

func _enter_tree() -> void:
	add_to_group(GROUP)

## The object this handle belongs to.
func get_target() -> Node:
	return target if target != null else get_parent()

func can_interact(pawn: Node) -> bool:
	if not enabled or not is_inside_tree() or not is_visible_in_tree():
		return false
	if pawn is Node3D:
		var from: Vector3 = pawn.global_position + Vector3.UP * 1.4
		if from.distance_to(global_position) > reach + 1.0:
			return false
	return true

## Host-side use. Later this is the body of an RPC sent by the pawn's owner.
func interact(pawn: Node) -> void:
	if not Net.is_host() or not can_interact(pawn):
		return
	interacted.emit(pawn)

## Build a simple spherical handle in code.
static func create(p_prompt: String, radius: float = 0.5) -> Interactable:
	var it := Interactable.new()
	it.prompt = p_prompt
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	cs.shape = sh
	it.add_child(cs)
	return it
