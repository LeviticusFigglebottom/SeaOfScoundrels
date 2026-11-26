class_name CookingStove
extends Node3D
## Galley stove or island campfire cooking pan: raw -> golden cooked -> burnt.
## Cooked fish/provisions restore full health plus a brief overheal top-up.

signal food_placed(item: Dictionary)
signal food_state_changed(cook_state: StringName, item: Dictionary)
signal food_taken(item: Dictionary, pawn: Node)

const COOK_TIME := 10.0
const BURN_TIME := 18.0

var cooking_item: Dictionary = {}
var elapsed: float = 0.0
var cook_state: StringName = &"empty"  # &"empty", &"raw", &"cooked", &"burnt"
var interactable: Interactable = null


func _ready() -> void:
	interactable = Interactable.create("Cook fish on pan", 0.7)
	interactable.position = Vector3(0.0, 0.4, 0.0)
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)


func place_food(item: Dictionary) -> bool:
	if not Net.is_host() or not cooking_item.is_empty():
		return false
	cooking_item = item.duplicate()
	elapsed = 0.0
	cook_state = &"raw"
	cooking_item["cooked_state"] = cook_state
	if interactable != null:
		interactable.prompt = "Take %s (cooking...)" % String(cooking_item.get("name", "Fish"))
	food_placed.emit(cooking_item)
	return true


func take_food(pawn: Node = null) -> Dictionary:
	if not Net.is_host() or cooking_item.is_empty():
		return {}
	var out := cooking_item.duplicate()
	out["cooked_state"] = cook_state
	cooking_item = {}
	elapsed = 0.0
	cook_state = &"empty"
	if interactable != null:
		interactable.prompt = "Cook fish on pan"
	if pawn is Pawn:
		var heal_amt := float(out.get("heal", 35.0))
		if out["cooked_state"] == &"cooked":
			heal_amt *= 1.85
		elif out["cooked_state"] == &"burnt":
			heal_amt *= 0.25
		(pawn as Pawn).heal(heal_amt)
		Audio.play_sfx(&"grog_gulp", (pawn as Pawn).eye_position(), -2.0)
	food_taken.emit(out, pawn)
	return out


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not Net.is_host() or cooking_item.is_empty():
		return
	elapsed += delta
	var next_state := &"raw"
	if elapsed >= BURN_TIME:
		next_state = &"burnt"
	elif elapsed >= COOK_TIME:
		next_state = &"cooked"
	if next_state != cook_state:
		cook_state = next_state
		cooking_item["cooked_state"] = cook_state
		var nm := String(cooking_item.get("name", "Fish"))
		if interactable != null:
			interactable.prompt = "Take %s %s" % [String(cook_state), nm]
		if cook_state == &"cooked":
			Game.post_notice("%s is golden and cooked!" % nm)
		elif cook_state == &"burnt":
			Game.post_notice("%s has burnt on the stove!" % nm)
		food_state_changed.emit(cook_state, cooking_item)


func _on_interacted(pawn: Node) -> void:
	if not cooking_item.is_empty():
		take_food(pawn)
	else:
		place_food({"id": &"azure_snapper", "name": "Azure Snapper", "heal": 35.0, "gold": 45})
