extends Node3D
## Combat showcase: deck melee duels (parry/stagger/powder-keg), Tidecaller ranged duel,
## and naval broadside engagement between Player Sloop and Drowned Sloop.
##
##   tools/capture.sh res://scenes/showcase/combat_showcase.tscn combat_duel 3 8 -- shot=melee
##
## User args (after `--`):
##   shot=melee|naval|tidecaller   (default melee)

const SKY_RIG: PackedScene = preload("res://src/sky/sky_rig.tscn")
const OCEAN_SCENE: PackedScene = preload("res://src/ocean/ocean.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

var _shot: String = "melee"
var _ship: Ship
var _foe_ship: Ship = null
var _hero: Pawn
var _hero_cc: CombatComponent
var _cam: Camera3D
var _clock: float = 0.0
var _step: int = 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			_shot = a.trim_prefix("shot=")

	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.time_of_day = 15.5
	Weather.set_weather(0.18, 10.0, 0.3, 0.0, 0.45)
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.18)
	Sea.time = 10.0

	add_child(SKY_RIG.instantiate())
	add_child(OCEAN_SCENE.instantiate())

	_ship = SLOOP_SCENE.instantiate() as Ship
	add_child(_ship)
	_ship.global_position = Vector3(0.0, Sea.height(0.0, 0.0), 0.0)

	_hero = PAWN_SCENE.instantiate() as Pawn
	_hero_cc = CombatComponent.new()
	_hero_cc.name = "CombatComponent"
	_hero_cc.faction = &"player"
	_hero.add_child(_hero_cc)
	add_child(_hero)
	_hero.board(_ship, Vector3(-1.05, 1.12, 0.35) if _shot != "tidecaller" else Vector3(-0.95, 1.12, 1.2))

	if _shot == "naval":
		_ship.set_sail_target(0.85)
		_ship.sail_set = 0.85
		_ship.linear_velocity = Vector3(0.0, 0.0, -5.0)
		_foe_ship = AIShipBrain.spawn_enemy_sloop(&"drowned_sloop", Vector3(48.0, 0.0, -14.0), self, _ship)
	else:
		_ship.set_anchor(true)
		_ship.anchor_progress = 1.0
		var arch := &"tidecaller" if _shot == "tidecaller" else &"drowned_cutlass"
		EnemyBrain.spawn_enemy(arch, _ship.global_transform * Vector3(0.85, 1.12, -2.2), self, _ship)
		if _shot == "melee":
			EnemyBrain.spawn_enemy(&"drowned_shield", _ship.global_transform * Vector3(-0.85, 1.12, -2.8), self, _ship)
			EnemyBrain.spawn_enemy(&"drowned_captain", _ship.global_transform * Vector3(0.15, 1.12, -3.7), self, _ship)

	_cam = Camera3D.new()
	_cam.fov = 66.0
	_cam.near = 0.08
	_cam.far = 5000.0
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _process(delta: float) -> void:
	_clock += delta
	if _shot == "melee":
		if _step == 0 and _clock > 0.6:
			_step = 1
			_hero_cc.set_blocking(true)
		elif _step == 1 and _clock > 1.3:
			_step = 2
			_hero_cc.set_blocking(false)
			_hero_cc.primary_attack()
		elif _step == 2 and _clock > 2.0:
			_step = 3
			_hero_cc.heavy_attack()
	_update_camera()


func _update_camera() -> void:
	var xf := _ship.global_transform
	if _shot == "naval":
		var eye := xf.origin + Vector3(-24.0, 12.0, 26.0)
		var mid := (xf.origin + _foe_ship.global_position) * 0.5 if _foe_ship != null else xf.origin
		_cam.look_at_from_position(eye, mid + Vector3(0.0, 2.0, 0.0), Vector3.UP)
	else:
		var eye := xf * Vector3(2.4, 3.25, 2.65)
		_cam.look_at_from_position(eye, xf * Vector3(-0.2, 1.75, -1.6), Vector3.UP)
