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
var _food_mesh: MeshInstance3D = null
var _food_mat: StandardMaterial3D = null
var _steam_wisp: MeshInstance3D = null
var _steam_mat: StandardMaterial3D = null
var _steam_time: float = 0.0


func _ready() -> void:
	interactable = Interactable.create("Cook fish or crab on pan", 0.7)
	interactable.position = Vector3(0.0, 0.4, 0.0)
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	_build_food_visual()


func _build_food_visual() -> void:
	_food_mesh = MeshInstance3D.new()
	_food_mesh.name = "SizzlingFood"
	var cap := CapsuleMesh.new()
	cap.radius = 0.055
	cap.height = 0.24
	cap.radial_segments = 8
	cap.rings = 3
	_food_mesh.mesh = cap
	_food_mesh.position = Vector3(0.0, 0.75, 0.0)
	_food_mesh.rotation_degrees = Vector3(90.0, 18.0, 0.0)
	_food_mesh.scale = Vector3(1.15, 1.0, 0.52)
	_food_mat = StandardMaterial3D.new()
	_food_mat.albedo_color = Color(0.92, 0.56, 0.48)
	_food_mat.roughness = 0.45
	_food_mesh.material_override = _food_mat
	_food_mesh.visible = false
	add_child(_food_mesh)

	_steam_wisp = MeshInstance3D.new()
	_steam_wisp.name = "CookingSteam"
	var sc := CylinderMesh.new()
	sc.top_radius = 0.14
	sc.bottom_radius = 0.05
	sc.height = 0.34
	sc.radial_segments = 8
	_steam_wisp.mesh = sc
	_steam_wisp.position = Vector3(0.0, 0.96, 0.0)
	_steam_wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_steam_mat = StandardMaterial3D.new()
	_steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_steam_mat.albedo_color = Color(0.95, 0.94, 0.90, 0.24)
	_steam_wisp.material_override = _steam_mat
	_steam_wisp.visible = false
	add_child(_steam_wisp)


func _update_food_visual() -> void:
	if _food_mesh == null or _food_mat == null:
		return
	var active := not cooking_item.is_empty()
	_food_mesh.visible = active
	if _steam_wisp != null:
		_steam_wisp.visible = active
	if not active:
		return
	var is_crab := String(cooking_item.get("id", "")).contains("crab")
	if cook_state == &"raw":
		_food_mat.albedo_color = Color(0.88, 0.30, 0.22) if is_crab else Color(0.92, 0.56, 0.48)
		_food_mat.roughness = 0.38
		if _steam_mat != null:
			_steam_mat.albedo_color = Color(0.96, 0.95, 0.92, 0.18)
	elif cook_state == &"cooked":
		_food_mat.albedo_color = Color(0.86, 0.46, 0.16) if is_crab else Color(0.82, 0.54, 0.22)
		_food_mat.roughness = 0.48
		if _steam_mat != null:
			_steam_mat.albedo_color = Color(1.0, 0.94, 0.80, 0.32)
	else:
		_food_mat.albedo_color = Color(0.14, 0.11, 0.10)
		_food_mat.roughness = 0.92
		if _steam_mat != null:
			_steam_mat.albedo_color = Color(0.18, 0.17, 0.18, 0.45)


func place_food(item: Dictionary) -> bool:
	if not Net.is_host() or not cooking_item.is_empty():
		return false
	cooking_item = item.duplicate()
	elapsed = 0.0
	cook_state = &"raw"
	cooking_item["cooked_state"] = cook_state
	if interactable != null:
		interactable.prompt = "Take %s (cooking...)" % String(cooking_item.get("name", "Fish"))
	_update_food_visual()
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
		interactable.prompt = "Cook fish or crab on pan"
	_update_food_visual()
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
	if _steam_wisp != null and _steam_wisp.visible:
		_steam_time += delta
		_steam_wisp.position.y = 0.94 + sin(_steam_time * 3.2) * 0.04
		_steam_wisp.rotation.y = _steam_time * 0.9


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
		_update_food_visual()
		food_state_changed.emit(cook_state, cooking_item)


func _on_interacted(pawn: Node) -> void:
	if not cooking_item.is_empty():
		take_food(pawn)
	else:
		place_food({"id": &"azure_snapper", "name": "Azure Snapper", "heal": 35.0, "gold": 45})
