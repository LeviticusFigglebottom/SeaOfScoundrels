class_name DigSite
extends Node3D
## Buried treasure dig site on an island beach or clearing.
##
## Visuals pair `dig_mound.glb` with a rising buried `chest_treasure.glb` preview
## and sand-clod puff particles. Players may dig either via a Shovel tool calling
## `dig(world_pos, digger)` or directly through the attached `Interactable`.
## Three digs unearth a real `Carryable` chest via `TreasureCatalog`.

signal dug(dig_count: int, remaining: int, digger: Node)
signal unearthed(chest: Carryable)

const DIG_MOUND_SCENE: PackedScene = preload("res://assets/generated/props/dig_mound.glb")
const CHEST_PREVIEW_SCENE: PackedScene = preload("res://assets/generated/props/chest_treasure.glb")

const DIG_RADIUS := 2.4
const REQUIRED_DIGS := 3
const GROUP := &"dig_sites"

## Treasure catalogue ID spawned on unearthing (configurable by voyages).
@export var treasure_id: StringName = &"wayfarer_chest"

var dig_count: int = 0
var is_unearthed: bool = false
var spawned_chest: Carryable = null
var interactable: Interactable = null

var _mound_node: Node3D = null
var _chest_preview: Node3D = null
var _dirt_particles: CPUParticles3D = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_build_visuals()
	_build_particles()
	_build_interactable()


func _build_visuals() -> void:
	if _mound_node == null:
		_mound_node = DIG_MOUND_SCENE.instantiate() as Node3D
		_mound_node.name = "DigMound"
		add_child(_mound_node)

	if _chest_preview == null:
		_chest_preview = CHEST_PREVIEW_SCENE.instantiate() as Node3D
		_chest_preview.name = "BuriedChestPreview"
		_chest_preview.position = Vector3(0.0, -0.44, 0.0)
		_chest_preview.rotation = Vector3(0.08, 0.35, -0.06)
		_chest_preview.visible = false
		add_child(_chest_preview)


func _build_particles() -> void:
	if _dirt_particles != null:
		return
	var p := CPUParticles3D.new()
	p.name = "DirtPuffParticles"
	p.emitting = false
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.65
	p.explosiveness = 0.85
	p.position = Vector3(0.0, 0.22, 0.0)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 52.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.6
	p.gravity = Vector3(0.0, -11.5, 0.0)
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.19

	var clod := BoxMesh.new()
	clod.size = Vector3(0.85, 0.65, 0.85)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.76, 0.64, 0.40)
	mat.roughness = 0.92
	clod.material = mat
	p.mesh = clod

	add_child(p)
	_dirt_particles = p


func _build_interactable() -> void:
	if interactable != null:
		return
	interactable = Interactable.create("Dig for treasure", 1.05)
	interactable.name = "DigInteractable"
	interactable.position = Vector3(0.0, 0.35, 0.0)
	interactable.reach = 2.8
	interactable.target = self
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)


func _on_interacted(pawn: Node) -> void:
	var pos := global_position
	if pawn is Node3D:
		var p_pos := (pawn as Node3D).global_position
		if Vector2(p_pos.x - global_position.x, p_pos.z - global_position.z).length() <= DIG_RADIUS:
			pos = p_pos
	dig(pos, pawn)


## Perform a dig strike at `world_pos` (host-authoritative).
## Returns `{hit, digs, remaining, unearthed, chest, reason}`.
func dig(world_pos: Vector3, digger: Node = null) -> Dictionary:
	if not Net.is_host():
		return {
			"hit": false,
			"reason": "not_host",
			"digs": dig_count,
			"remaining": maxi(0, REQUIRED_DIGS - dig_count),
			"unearthed": is_unearthed,
			"chest": spawned_chest,
		}
	if is_unearthed:
		return {
			"hit": false,
			"reason": "already_unearthed",
			"digs": dig_count,
			"remaining": 0,
			"unearthed": true,
			"chest": spawned_chest,
		}

	var dist_xz := Vector2(world_pos.x - global_position.x, world_pos.z - global_position.z).length()
	if dist_xz > DIG_RADIUS:
		return {
			"hit": false,
			"reason": "out_of_range",
			"distance": dist_xz,
			"digs": dig_count,
			"remaining": maxi(0, REQUIRED_DIGS - dig_count),
			"unearthed": false,
			"chest": null,
		}

	dig_count += 1
	var remaining := maxi(0, REQUIRED_DIGS - dig_count)
	Audio.play_sfx(&"dig_sand", global_position)
	_trigger_dirt_puff()
	_update_mound_progress()

	if dig_count < REQUIRED_DIGS:
		if dig_count == REQUIRED_DIGS - 1:
			Audio.play_sfx(&"chest_thump", global_position, -6.0)
		if interactable != null:
			interactable.prompt = "Unearth treasure (1 left)" if remaining == 1 else "Dig for treasure (%d left)" % remaining
		dug.emit(dig_count, remaining, digger)
		return {
			"hit": true,
			"reason": "",
			"digs": dig_count,
			"remaining": remaining,
			"unearthed": false,
			"chest": null,
		}

	# Final strike: unearth the physical Carryable chest.
	is_unearthed = true
	if _chest_preview != null:
		_chest_preview.visible = false
	if interactable != null:
		interactable.enabled = false
		interactable.prompt = "Dug up"

	var resolved_id := _resolve_treasure_id(treasure_id)
	var spawn_pos := global_position + Vector3(0.0, 0.42, 0.0)
	var chest := TreasureCatalog.create_treasure_carryable(resolved_id, Vector3.ZERO)
	var host_parent := get_parent() if get_parent() != null else self
	host_parent.add_child(chest)
	chest.global_position = spawn_pos
	chest.linear_velocity = Vector3(0.0, 2.0, 0.0)
	spawned_chest = chest

	Audio.play_sfx(&"chest_thump", global_position)
	Audio.play_stinger(&"treasure_found")
	dug.emit(dig_count, 0, digger)
	unearthed.emit(chest)

	return {
		"hit": true,
		"reason": "",
		"digs": dig_count,
		"remaining": 0,
		"unearthed": true,
		"chest": chest,
	}


func _trigger_dirt_puff() -> void:
	if _dirt_particles != null:
		_dirt_particles.restart()
		_dirt_particles.emitting = true


func _update_mound_progress() -> void:
	if _mound_node != null:
		match dig_count:
			1:
				_mound_node.scale = Vector3(1.04, 0.80, 1.04)
			2:
				_mound_node.scale = Vector3(1.10, 0.54, 1.10)
			_:
				_mound_node.scale = Vector3(1.16, 0.24, 1.16)
				_mound_node.position.y = -0.06
	if _chest_preview != null and not is_unearthed:
		_chest_preview.visible = true
		if dig_count == 1:
			_chest_preview.position.y = -0.26
		elif dig_count >= 2:
			_chest_preview.position.y = -0.07


static func _resolve_treasure_id(tid: StringName) -> StringName:
	if TreasureCatalog.has_treasure(tid):
		return tid
	if tid == &"seafarer_chest":
		return &"wayfarer_chest"
	return &"wayfarer_chest"
