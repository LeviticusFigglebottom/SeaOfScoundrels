class_name FishingLine
extends Node3D
## Low-stakes sailing downtime: cast a bobber into the real `Sea`, wait for a bite,
## manage line tension while reeling, and haul original sea fish aboard for cooking or sale.

signal cast_started(bobber_pos: Vector3)
signal fish_hooked(species: Dictionary)
signal fish_caught(species: Dictionary)
signal line_snapped(species: Dictionary)

enum State { IDLE, WAITING, HOOKED }

const SPECIES: Array[Dictionary] = [
	{"id": &"azure_snapper", "name": "Azure Snapper", "gold": 45, "heal": 30.0, "fight": 0.45, "storm_only": false, "night_only": false},
	{"id": &"gilded_mackerel", "name": "Gilded Mackerel", "gold": 65, "heal": 35.0, "fight": 0.55, "storm_only": false, "night_only": false},
	{"id": &"reef_grouper", "name": "Reef Grouper", "gold": 95, "heal": 45.0, "fight": 0.65, "storm_only": false, "night_only": false},
	{"id": &"lantern_fin", "name": "Moonlit Lantern-Fin", "gold": 150, "heal": 55.0, "fight": 0.72, "storm_only": false, "night_only": true},
	{"id": &"storm_eel", "name": "Tempest Ribbon-Eel", "gold": 210, "heal": 65.0, "fight": 0.85, "storm_only": true, "night_only": false},
]

var state: State = State.IDLE
var bobber_pos: Vector3 = Vector3.ZERO
var distance_out: float = 0.0
var line_tension: float = 0.0
var fish_fighting: bool = false
var hooked_species: Dictionary = {}
var caught_fish: Array[Dictionary] = []

var _bite_timer: float = 0.0
var _fight_timer: float = 0.0
var _bobber_mesh: MeshInstance3D = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_bobber_mesh = MeshInstance3D.new()
	_bobber_mesh.name = "Bobber"
	var sp := SphereMesh.new()
	sp.radius = 0.09
	sp.height = 0.18
	_bobber_mesh.mesh = sp
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.22, 0.16)
	mat.roughness = 0.4
	_bobber_mesh.material_override = mat
	_bobber_mesh.visible = false
	_bobber_mesh.top_level = true
	add_child(_bobber_mesh)


## Cast the line forward from `origin` along `forward` into the sea.
func cast_line(origin: Vector3, forward: Vector3, cast_dist: float = 11.0) -> bool:
	if state != State.IDLE:
		return false
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	if flat.length_squared() < 0.01:
		flat = Vector3.FORWARD
	bobber_pos = origin + flat * cast_dist
	bobber_pos.y = Sea.height(bobber_pos.x, bobber_pos.z)
	distance_out = cast_dist
	line_tension = 0.0
	fish_fighting = false
	hooked_species = {}
	state = State.WAITING
	_bite_timer = _rng.randf_range(3.0, 7.5)
	if _bobber_mesh != null:
		_bobber_mesh.visible = true
		_bobber_mesh.global_position = bobber_pos
	Audio.play_sfx(&"splash_small", bobber_pos)
	if Ocean.current != null:
		Ocean.current.add_foam(bobber_pos, 0.65, 0.45)
	cast_started.emit(bobber_pos)
	return true


func cancel_cast() -> void:
	state = State.IDLE
	line_tension = 0.0
	fish_fighting = false
	hooked_species = {}
	if _bobber_mesh != null:
		_bobber_mesh.visible = false


## Advance fishing simulation. Call each physics tick while holding a rod (`reeling = primary`).
func step(delta: float, caster_pos: Vector3, reeling: bool) -> void:
	if state == State.IDLE:
		return
	var surf := Sea.height(bobber_pos.x, bobber_pos.z)
	bobber_pos.y = surf - (0.14 if fish_fighting else 0.0)
	if _bobber_mesh != null:
		_bobber_mesh.global_position = bobber_pos

	if state == State.WAITING:
		_bite_timer -= delta
		if _bite_timer <= 0.0:
			hooked_species = _pick_species()
			state = State.HOOKED
			fish_fighting = true
			_fight_timer = _rng.randf_range(1.2, 2.2)
			Audio.play_sfx(&"splash_small", bobber_pos, 2.0)
			if Ocean.current != null:
				Ocean.current.add_foam(bobber_pos, 1.1, 0.75)
			fish_hooked.emit(hooked_species)
		return

	# State.HOOKED: toggle between fighting bursts and tired lulls!
	_fight_timer -= delta
	if _fight_timer <= 0.0:
		fish_fighting = not fish_fighting
		_fight_timer = _rng.randf_range(1.1, 2.1) if fish_fighting else _rng.randf_range(1.8, 3.0)

	var fight_pow := float(hooked_species.get("fight", 0.5))
	if reeling:
		if fish_fighting:
			line_tension += (0.55 + fight_pow * 0.65) * delta
			distance_out -= 0.7 * delta
		else:
			line_tension = maxf(0.0, line_tension - 0.18 * delta)
			distance_out -= 3.8 * delta
	else:
		line_tension = maxf(0.0, line_tension - 0.85 * delta)
		if fish_fighting:
			distance_out += 0.9 * fight_pow * delta

	# Pull bobber smoothly toward caster as distance_out shrinks.
	var to_bob := Vector3(bobber_pos.x - caster_pos.x, 0.0, bobber_pos.z - caster_pos.z)
	if to_bob.length_squared() > 0.01:
		var dir := to_bob.normalized()
		bobber_pos.x = caster_pos.x + dir.x * maxf(distance_out, 0.5)
		bobber_pos.z = caster_pos.z + dir.z * maxf(distance_out, 0.5)

	if line_tension >= 1.0:
		var lost := hooked_species
		cancel_cast()
		line_snapped.emit(lost)
	elif distance_out <= 1.2:
		var caught := hooked_species.duplicate()
		caught["cooked_state"] = &"raw"
		caught_fish.append(caught)
		cancel_cast()
		Audio.play_sfx(&"splash_small", caster_pos)
		Game.post_notice("Caught a %s!" % String(caught["name"]))
		fish_caught.emit(caught)


func _pick_species() -> Dictionary:
	var is_storm := Weather.storminess > 0.55
	var is_night := Weather.is_night()
	var pool: Array[Dictionary] = []
	for sp in SPECIES:
		if bool(sp["storm_only"]) and not is_storm:
			continue
		if bool(sp["night_only"]) and not is_night:
			continue
		pool.append(sp)
	if pool.is_empty():
		return SPECIES[0]
	return pool[_rng.randi_range(0, pool.size() - 1)]
