extends TestCase
## Headless combat tests: melee 3-hit combos, block & timed parry stagger, shield-bearer
## flanking & heavy guard-break, powder-keg detonation, ranged weapons, Tidecaller kiting,
## shark attack, and Drowned Sloop naval AI broadside + salvage.

const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const SPEEDUP := 6

var _root: Node3D
var _saved_weather: Dictionary
var _saved_amp: float = 1.0


func _fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEEDUP if on else 1)
	Engine.time_scale = float(SPEEDUP) if on else 1.0
	Engine.max_physics_steps_per_frame = 8 * (SPEEDUP if on else 1)


func _begin() -> void:
	_saved_weather = Weather.get_state()
	_saved_amp = Sea.amp_scale
	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.set_weather(0.0, 10.0, 0.0)
	Sea.amp_scale = 0.0
	_fast(true)
	_root = Node3D.new()
	add_child(_root)


func _end() -> void:
	_root.queue_free()
	_root = null
	await physics_frames(2)
	_fast(false)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp


func _ground() -> StaticBody3D:
	var g := StaticBody3D.new()
	g.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80.0, 1.0, 80.0)
	cs.shape = bx
	g.add_child(cs)
	_root.add_child(g)
	g.global_position = Vector3(0.0, 4.5, 0.0)
	return g


func _fighter(pos: Vector3, faction: StringName, yaw: float = 0.0) -> Array:
	var p := PAWN_SCENE.instantiate() as Pawn
	var cc := CombatComponent.new()
	cc.name = "CombatComponent"
	cc.faction = faction
	p.add_child(cc)
	_root.add_child(p)
	p.global_position = pos
	p.look_yaw = yaw
	return [p, cc]


func test_melee_combo_block_parry_stagger_and_dodge() -> void:
	_begin()
	_ground()
	var a := _fighter(Vector3(0.0, 5.05, 0.0), &"player", 0.0)
	var b := _fighter(Vector3(0.0, 5.05, -1.6), &"drowned", PI)
	var pa: Pawn = a[0]; var cca: CombatComponent = a[1]
	var pb: Pawn = b[0]; var ccb: CombatComponent = b[1]
	await physics_frames(10)

	# 1. Timed parry: B starts blocking right as A swings -> A is staggered and B takes 0 damage!
	var parried_flag := [false]
	ccb.parried.connect(func(_atk: Pawn) -> void: parried_flag[0] = true)
	var hp_b0 := pb.health
	ccb.set_blocking(true)
	cca.primary_attack()
	await physics_frames(18)
	check(parried_flag[0], "timed block within PARRY_WINDOW must parry incoming melee strike")
	check_near(pb.health, hp_b0, 0.01, "parrying defender takes zero damage")
	check(cca.is_staggered(), "parried attacker must be staggered")

	# 2. Staggered target takes 1.5x damage!
	ccb.set_blocking(false)
	var hp_a0 := pa.health
	ccb.primary_attack()
	await physics_frames(20)
	var dmg_staggered := hp_a0 - pa.health
	print("    staggered hit damage: %.1f (base 18.0 * 1.5 = 27.0)" % dmg_staggered)
	check(dmg_staggered > 24.0, "staggered target must take bonus damage (got %.1f)" % dmg_staggered)

	# 3. Wait for stagger to clear, test dodge i-frames!
	await physics_frames(120)
	var hp_a1 := pa.health
	cca.dodge_step(Vector3.RIGHT)
	check(cca.is_invulnerable(), "dodge grants brief i-frames")
	var res := cca.receive_melee_hit(ccb, 30.0, false, false)
	check_eq(res, &"dodged", "dodge i-frames negate incoming melee hit")
	check_near(pa.health, hp_a1, 0.01, "dodged hit deals 0 damage")
	await _end()


func test_shield_bearer_and_powder_carrier_and_ranged() -> void:
	_begin()
	_ground()
	var hero_pair := _fighter(Vector3(0.0, 5.05, 0.0), &"player", 0.0)
	var hero: Pawn = hero_pair[0]; var hcc: CombatComponent = hero_pair[1]

	# Shield-bearer blocks frontal light slash, but heavy slash breaks its guard!
	var shield := EnemyBrain.spawn_enemy(&"drowned_shield", Vector3(0.0, 5.05, -1.7), _root)
	shield.look_yaw = PI
	var scc: CombatComponent = shield.get_node(^"CombatComponent")
	await physics_frames(10)
	var shp0 := shield.health
	var light_res := scc.receive_melee_hit(hcc, 20.0, false, false)
	check_eq(light_res, &"blocked", "shield-bearer blocks frontal light melee")
	check_near(shield.health, shp0, 0.01, "blocked light hit deals 0 damage")
	var heavy_res := scc.receive_melee_hit(hcc, 44.0, true, false)
	check_eq(heavy_res, &"hit", "heavy slash breaks shield guard")
	check(shield.health < shp0 - 15.0, "guard-broken shield-bearer takes damage")
	check(scc.is_staggered(), "guard-broken shield-bearer is staggered")
	shield.queue_free()
	await physics_frames(2)

	# Powder-carrier: shooting it with flintlock pistol detonates its keg and blasts nearby enemies!
	var powder := EnemyBrain.spawn_enemy(&"drowned_powder", Vector3(0.0, 5.05, -9.0), _root)
	var bystander := EnemyBrain.spawn_enemy(&"drowned_cutlass", Vector3(2.2, 5.05, -9.0), _root)
	var keg_blown := [false]
	(powder.get_node(^"EnemyBrain") as EnemyBrain).keg_detonated.connect(func(_p: Vector3, _r: float) -> void:
		keg_blown[0] = true
	)
	await physics_frames(4)
	var aim := (powder.global_position + Vector3.UP * 1.1) - hero.eye_position()
	hero.look_yaw = atan2(-aim.x, -aim.z)
	hero.look_pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
	hcc.equip_weapon(&"pistol")
	var bystander_hp0 := bystander.health
	hcc.primary_attack()
	await physics_frames(6)
	print("    powder keg blown=%s powder dead=%s bystander hp %.1f -> %.1f" % [
		str(keg_blown[0]), str(powder.dead), bystander_hp0, bystander.health])
	check(keg_blown[0] and powder.dead, "shooting powder carrier must detonate its keg")
	check(bystander.health < bystander_hp0 - 30.0, "keg blast must damage nearby enemies")
	await _end()


func test_tidecaller_kiting_and_shark_predator() -> void:
	_begin()
	_ground()
	var hero_pair := _fighter(Vector3(0.0, 5.05, 0.0), &"player", 0.0)
	var hero: Pawn = hero_pair[0]
	var tc := EnemyBrain.spawn_enemy(&"tidecaller", Vector3(0.0, 5.05, -4.5), _root)
	await physics_frames(80)
	var dist := hero.global_position.distance_to(tc.global_position)
	print("    tidecaller kited from 4.5 m -> %.2f m" % dist)
	check(dist > 5.5, "tidecaller should reposition backward when player is too close")

	# Shark orbits and bites a swimmer in open water.
	var swimmer_pair := _fighter(Vector3(35.0, -1.35, 35.0), &"player", 0.0)
	var swimmer: Pawn = swimmer_pair[0]
	await physics_frames(15)
	var shark := Shark.new()
	shark.circle_radius = 4.0
	_root.add_child(shark)
	shark.global_position = Vector3(39.0, -0.35, 35.0)
	shark._state_timer = 0.2
	var hp0 := swimmer.health
	for _i in 220:
		await physics_frames(1)
		if swimmer.health < hp0:
			break
	print("    shark bite: swimmer hp %.1f -> %.1f" % [hp0, swimmer.health])
	check(swimmer.health < hp0, "shark must charge and bite swimmer in open water")
	await _end()


func test_drowned_sloop_ai_broadside_and_salvage() -> void:
	_begin()
	var player_ship := SLOOP_SCENE.instantiate() as Ship
	player_ship.enable_effects = false
	player_ship.faction = &"player"
	_root.add_child(player_ship)
	player_ship.global_position = Vector3(0.0, 0.0, 0.0)

	var foe := AIShipBrain.spawn_enemy_sloop(&"drowned_sloop", Vector3(44.0, 0.0, -2.0), _root, player_ship)
	foe.enable_effects = false
	foe.rotation.y = 0.0  # parallel to player so port cannon faces player ship!
	var ai_brain: AIShipBrain = foe.get_node(^"AIShipBrain")
	ai_brain._fire_delay = 0.1

	var fired := [false]
	foe.cannon_fired.connect(func(_side: StringName, _b: Cannonball) -> void: fired[0] = true)
	for _i in 120:
		await physics_frames(1)
		if fired[0]:
			break
	check(fired[0], "Drowned Sloop AI must fire broadside cannons when target is in arc")

	# Sink the enemy sloop and verify salvage chests/skulls spawn on the waves!
	var salvage_count := [0]
	ai_brain.salvage_dropped.connect(func(_pos: Vector3, items: Array) -> void:
		salvage_count[0] = items.size()
	)
	foe.add_water(1.2)
	await physics_frames(10)
	print("    enemy sunk: is_sinking=%s salvage_items=%d" % [str(foe.is_sinking), salvage_count[0]])
	check(foe.is_sinking and salvage_count[0] >= 2, "sinking enemy ship must spawn floating salvage loot")
	await _end()
