class_name Carryable
extends RigidBody3D
## Base for anything hauled by hand: chests, cannonballs, crates, planks.
##
## A rigid body on collision layer 6. A pawn picks it up through the built-in
## `Interactable`; while held it is frozen, has no collision and is placed in
## front of the holder by the pawn every physics tick. It floats, using `Sea`.
## It can be dropped (`Pawn.drop_carried`) or handed to a container
## (`hand_to(container)`; the container implements
## `accept_carryable(item) -> bool`).
##
## State changes run on the host only.

signal picked_up(pawn: Node)
signal dropped(pawn: Node)
signal stored(container: Node)

const LAYER := 1 << 5
const MASK := 1 | 2 | (1 << 5)

@export var item_name: String = "Crate"
## Buoyant force over weight when fully submerged. Above 1 floats, below sinks.
@export var buoyancy: float = 1.7
## Half height used for the submersion estimate, metres.
@export var float_radius: float = 0.25
## Multiplier on the holder's sprint speed.
@export var carry_speed_factor: float = 0.72
## Hold position relative to the holder's feet, in the holder's facing frame.
@export var hold_offset: Vector3 = Vector3(0.0, 1.0, -0.62)

var holder: Node3D = null
var stored_in: Node = null
var interactable: Interactable = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _ready() -> void:
	collision_layer = LAYER
	collision_mask = MASK
	for c in get_children():
		if c is Interactable:
			interactable = c
	if interactable == null:
		interactable = Interactable.create("Pick up " + item_name, 0.55)
		add_child(interactable)
	interactable.interacted.connect(_on_interacted)

func _on_interacted(pawn: Node) -> void:
	if pawn != null and pawn.has_method("pick_up"):
		pawn.pick_up(self)

func is_held() -> bool:
	return holder != null

## Called by the holder (host only). Use `Pawn.pick_up(item)` from game code.
func attach_to(pawn: Node3D) -> void:
	if not Net.is_host():
		return
	holder = pawn
	stored_in = null
	visible = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	interactable.enabled = false
	picked_up.emit(pawn)

## Called by the holder (host only). Use `Pawn.drop_carried()` from game code.
func detach(world_velocity: Vector3 = Vector3.ZERO) -> void:
	if not Net.is_host():
		return
	var was := holder
	holder = null
	_restore_body()
	linear_velocity = world_velocity
	angular_velocity = Vector3.ZERO
	dropped.emit(was)

## Give the item to a container (barrel, hold rack, merchant). Returns false if
## the container refuses. On success the item is hidden and inert until
## `take_out()`; the container owns what happens next.
func hand_to(container: Node) -> bool:
	if not Net.is_host() or container == null or not container.has_method("accept_carryable"):
		return false
	if not container.accept_carryable(self):
		return false
	var was := holder
	holder = null
	if was != null and was.has_method("release_carried"):
		was.release_carried(self)
	stored_in = container
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	interactable.enabled = false
	visible = false
	stored.emit(container)
	return true

## Put a stored item back into the world.
func take_out(world_position: Vector3) -> void:
	if not Net.is_host():
		return
	stored_in = null
	visible = true
	global_position = world_position
	_restore_body()
	linear_velocity = Vector3.ZERO

func _restore_body() -> void:
	freeze = false
	collision_layer = LAYER
	collision_mask = MASK
	interactable.enabled = true

func _physics_process(delta: float) -> void:
	if freeze or not Net.is_host():
		return
	var bottom_depth := Sea.depth(global_position) + float_radius
	if bottom_depth <= 0.0:
		return
	var frac := clampf(bottom_depth / (2.0 * float_radius), 0.0, 1.0)
	apply_central_force(Vector3.UP * mass * _gravity * buoyancy * frac)
	apply_central_force(-linear_velocity * mass * 2.5 * frac)
	angular_velocity *= maxf(0.0, 1.0 - 2.0 * delta * frac)
