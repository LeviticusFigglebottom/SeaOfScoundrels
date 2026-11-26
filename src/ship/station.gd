class_name Station
extends Node3D
## Crewable ship station (helm, sail winches, capstan, cannons, map table, bilge).
##
## Players (`PlayerController`) and AI (`CrewBrain`) drive stations through the
## exact same interface: `can_occupy()`, `occupy()`, `drive()`, and `release()`.
## Occupancy mutations are host-authoritative (`Net.is_host()`).

signal occupied(pawn: Node)
signal released(pawn: Node)

## Station category: &"helm", &"sail_length", &"sail_angle", &"anchor",
## &"cannon", &"map_table", &"bilge", etc.
@export var kind: StringName = &""
## Prompt displayed by the HUD when a pawn focuses this station's handle.
@export var prompt: String = "Use station":
	set(v):
		prompt = v
		if interactable != null:
			interactable.prompt = v
## Local transform (relative to this Station node) where the occupant stands.
## -Z is the direction the occupant faces while crewing.
@export var stand_point: Transform3D = Transform3D.IDENTITY
## Local position of the focusable Interactable sphere.
@export var interact_offset: Vector3 = Vector3(0.0, 0.9, 0.0)
@export var interact_radius: float = 0.55
@export var interact_reach: float = 2.8

## Optional sub-identifier (e.g. &"port" or &"starboard" for cannons).
var meta_id: StringName = &""
## Current occupant (`Pawn` or test stand-in), or null when free.
var occupant: Node = null
## Focus handle found by controllers (layer 4, group `interactables`).
var interactable: Interactable = null
## Owning ship or structure.
var ship: Node3D = null
## Optional callback invoked by `drive()`: func(station, axis, primary, secondary, delta).
var drive_callback: Callable = Callable()


func _ready() -> void:
	_ensure_interactable()


## Configure this station in code (typically right after instantiating).
func configure(
	p_ship: Node3D,
	p_kind: StringName,
	p_prompt: String,
	p_stand: Transform3D,
	p_interact_offset: Vector3 = Vector3(0.0, 0.9, 0.0),
	p_radius: float = 0.55,
	p_meta_id: StringName = &"",
	p_reach: float = 2.8
) -> void:
	ship = p_ship
	kind = p_kind
	prompt = p_prompt
	stand_point = p_stand
	interact_offset = p_interact_offset
	interact_radius = p_radius
	meta_id = p_meta_id
	interact_reach = p_reach
	if is_node_ready():
		_ensure_interactable()


func _ensure_interactable() -> void:
	if interactable == null:
		interactable = Interactable.create(prompt, interact_radius)
		interactable.name = "Interactable"
		add_child(interactable)
	interactable.target = self
	interactable.prompt = prompt
	interactable.position = interact_offset
	interactable.reach = interact_reach
	interactable.enabled = not is_occupied()


## True when a valid occupant currently crews this station.
func is_occupied() -> bool:
	if occupant != null and not is_instance_valid(occupant):
		occupant = null
	return occupant != null


## World-space transform where the occupant stands.
func get_stand_global() -> Transform3D:
	return global_transform * stand_point


## Whether `pawn` is allowed to take this station right now.
func can_occupy(pawn: Node) -> bool:
	if pawn == null or not is_instance_valid(pawn) or not is_inside_tree():
		return false
	return not is_occupied()


## Host only. Assign `pawn` as this station's occupant.
func occupy(pawn: Node) -> void:
	if not Net.is_host():
		return
	if not can_occupy(pawn):
		return
	occupant = pawn
	if interactable != null:
		interactable.enabled = false
	occupied.emit(pawn)


## Host only. Release the current occupant.
func release() -> void:
	if not Net.is_host():
		return
	if occupant == null:
		if interactable != null:
			interactable.enabled = true
		return
	var prev := occupant
	occupant = null
	if interactable != null:
		interactable.enabled = true
	released.emit(prev)


## Host only. Called every physics tick by the occupant's controller.
func drive(axis: Vector2, primary: bool, secondary: bool, delta: float) -> void:
	if not Net.is_host():
		return
	if occupant != null and not is_instance_valid(occupant):
		release()
		return
	if drive_callback.is_valid():
		drive_callback.call(self, axis, primary, secondary, delta)
	elif ship != null and is_instance_valid(ship) and ship.has_method(&"_drive_station"):
		ship.call(&"_drive_station", self, axis, primary, secondary, delta)
