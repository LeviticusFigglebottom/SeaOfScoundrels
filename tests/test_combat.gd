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


class _MockIsland extends Node3D:
	var island_radius: float = 30.0


func test_ghost_ship_phase_shift_and_faction_emblems() -> void:
	_begin()
	var player_ship := SLOOP_SCENE.instantiate() as Ship
	player_ship.enable_effects = false
	player_ship.faction = &"player"
	_root.add_child(player_ship)
	player_ship.global_position = Vector3(0.0, 0.0, 0.0)

	var ghost := AIShipBrain.spawn_enemy_sloop(&"ghost_ship", Vector3(58.0, 0.0, 0.0), _root, player_ship)
	ghost.enable_effects = false
	var corsair := AIShipBrain.spawn_enemy_sloop(&"corsair_sloop", Vector3(0.0, 0.0, -90.0), _root, player_ship)
	corsair.enable_effects = false
	var drowned := AIShipBrain.spawn_enemy_sloop(&"drowned_sloop", Vector3(95.0, 0.0, -90.0), _root, player_ship)
	drowned.enable_effects = false
	await physics_frames(4)

	# 1. Verify Ghost Ship uses ghost_hull.gdshader on hull surfaces and all faction emblem_modes match.
	check(not ghost._ghost_hull_mats.is_empty(), "Ghost Ship must populate _ghost_hull_mats")
	for gm in ghost._ghost_hull_mats:
		check_eq(gm.shader, Ship.GHOST_HULL_SHADER, "Ghost hull material must use ghost_hull.gdshader")
	var hull_mesh := ghost._n("Hull") as MeshInstance3D
	check(hull_mesh != null, "Ghost Ship has Hull MeshInstance3D")
	if hull_mesh != null:
		var ov := hull_mesh.get_surface_override_material(0) as ShaderMaterial
		check(ov != null and ov.shader == Ship.GHOST_HULL_SHADER, "Ghost Hull surface override uses ghost_hull.gdshader")

	check(not player_ship._sail_mats.is_empty(), "Player ship has sail ShaderMaterials")
	check_eq(int(player_ship._sail_mats[0].get_shader_parameter(&"emblem_mode")), 0, "Player sail emblem_mode == 0")
	check_eq(int(corsair._sail_mats[0].get_shader_parameter(&"emblem_mode")), 1, "Corsair sail emblem_mode == 1")
	check_eq(int(drowned._sail_mats[0].get_shader_parameter(&"emblem_mode")), 2, "Drowned sail emblem_mode == 2")
	check_eq(int(ghost._sail_mats[0].get_shader_parameter(&"emblem_mode")), 3, "Ghost sail emblem_mode == 3")

	# 2. Place an obstructing mock island near the nominal opposite-beam spot to test island-safe fallback.
	var mock_island := _MockIsland.new()
	mock_island.island_radius = 30.0
	mock_island.add_to_group(&"islands")
	_root.add_child(mock_island)
	mock_island.global_position = Vector3(-58.0, 0.0, 45.0)

	# Anchor player ship so it stays near origin for deterministic flank checks.
	player_ship.set_anchor(true)
	player_ship.anchor_progress = 1.0
	ghost.global_position = Vector3(58.0, 0.0, 0.0)
	var brain := ghost.get_node(^"AIShipBrain") as AIShipBrain
	brain._fire_delay = 99.0

	var shifted := [false]
	var shift_from := [Vector3.ZERO]
	var shift_to := [Vector3.ZERO]
	brain.phase_shifted.connect(func(from_pos: Vector3, to_pos: Vector3) -> void:
		shifted[0] = true
		shift_from[0] = from_pos
		shift_to[0] = to_pos
	)

	var started := brain.trigger_phase_shift()
	check(started, "trigger_phase_shift() must start phase shift on a solid Ghost Ship")
	check_eq(brain._phase_state, &"fading_out", "phase state enters fading_out")

	var saw_fading_out_alpha := false
	var saw_fading_in := false
	for _i in 320:
		await physics_frames(1)
		if brain._phase_state == &"fading_out" and ghost._spectral_phase < 0.75:
			saw_fading_out_alpha = true
		if brain._phase_state == &"fading_in":
			saw_fading_in = true
		if shifted[0] and brain._phase_state == &"solid":
			break

	var dist_to_island := Vector2(
		shift_to[0].x - mock_island.global_position.x,
		shift_to[0].z - mock_island.global_position.z
	).length()
	print("    ghost phase shift: from=%s to=%s island_clear=%.1f m state=%s alpha=%.2f" % [
		str(shift_from[0]), str(shift_to[0]), dist_to_island, String(brain._phase_state), ghost._spectral_phase])

	check(saw_fading_out_alpha, "phase_alpha must dissolve downward during fading_out")
	check(shifted[0], "phase_shifted signal must emit on teleport")
	check(saw_fading_in, "phase state must pass through fading_in")
	check_eq(brain._phase_state, &"solid", "Ghost Ship must return to solid state after materializing")
	check_near(ghost._spectral_phase, 1.0, 0.01, "phase_alpha must restore to 1.0")
	check_near(float(ghost._ghost_hull_mats[0].get_shader_parameter(&"phase_alpha")), 1.0, 0.01, "ghost hull shader phase_alpha restored to 1.0")
	check(ghost.visible, "Ghost Ship must be visible again after fading in")
	check(shift_to[0].x < -10.0, "Ghost Ship must relocate onto opposite (-X) flank (got x=%.1f)" % shift_to[0].x)
	check(dist_to_island > mock_island.island_radius + 55.0, "phase destination must clear islands by > radius + 55 m (got %.1f m)" % dist_to_island)

	# 3. Verify upgraded muzzle VFX uses feathered QuadMesh (no SphereMesh) and cleans up cleanly on _exit_tree().
	var fx_ship := SLOOP_SCENE.instantiate() as Ship
	fx_ship.enable_effects = true
	_root.add_child(fx_ship)
	fx_ship.global_position = Vector3(-180.0, 0.0, -180.0)
	await physics_frames(2)
	var ball := fx_ship.fire_cannon(&"starboard")
	check(ball != null, "fx_ship fires starboard cannon")
	check_eq(fx_ship._active_muzzle_vfx.size(), 1, "active muzzle VFX node tracked for cleanup")
	var fx_root := fx_ship._active_muzzle_vfx[0]
	var smoke_gp := fx_root.get_node_or_null(^"CannonSmoke") as GPUParticles3D
	check(smoke_gp != null and smoke_gp.draw_pass_1 is QuadMesh, "cannon smoke uses billboarded QuadMesh instead of SphereMesh")
	var flash_gp := fx_root.get_node_or_null(^"MuzzleFlashCore") as GPUParticles3D
	check(flash_gp != null and flash_gp.draw_pass_1 is QuadMesh, "cannon muzzle flash spawns additive QuadMesh core")
	fx_ship.queue_free()
	if ball != null:
		ball.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(fx_root), "muzzle VFX node is cleanly freed on ship _exit_tree() with zero leaks")
	await _end()


func test_enemy_signature_combat_vfx_and_teardown() -> void:
	_begin()
	_ground()

	# Near player with PlayerController (inside 24 m trauma radius) and far player (outside 24 m).
	var hero_pair := _fighter(Vector3(0.0, 5.05, 0.0), &"player", 0.0)
	var hero: Pawn = hero_pair[0]
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	pc.input_enabled = false
	pc.capture_mouse = false
	pc.make_current = false
	pc.bob_amount = 0.028
	hero.add_child(pc)

	var far_pair := _fighter(Vector3(36.0, 5.05, 0.0), &"player", 0.0)
	var far_hero: Pawn = far_pair[0]
	var pc_far := PlayerController.new()
	pc_far.name = "PlayerController"
	pc_far.input_enabled = false
	pc_far.capture_mouse = false
	pc_far.make_current = false
	pc_far.bob_amount = 0.028
	far_hero.add_child(pc_far)
	await physics_frames(4)

	# 1. Powder-Carrier detonate_keg() spawns KegExplosionVFX (3+ particle layers, no SphereMesh!),
	#    triggers nearby PlayerController camera trauma, and self-cleans even after pawn is freed.
	var powder := EnemyBrain.spawn_enemy(&"drowned_powder", Vector3(0.0, 5.05, -8.0), _root)
	var powder_brain := powder.get_node(^"EnemyBrain") as EnemyBrain
	await physics_frames(2)
	check_near(pc.get_camera_trauma(), 0.0, 0.001, "camera trauma starts at 0 before keg blast")
	powder_brain.detonate_keg(hero)

	var keg_fx := _root.get_node_or_null(^"KegExplosionVFX") as Node3D
	check(keg_fx != null, "detonate_keg() must spawn KegExplosionVFX on host")
	var keg_layers := 0
	var keg_has_sphere := false
	if keg_fx != null:
		for ch in keg_fx.get_children():
			if ch is GPUParticles3D:
				keg_layers += 1
				var gp := ch as GPUParticles3D
				if gp.draw_pass_1 is SphereMesh:
					keg_has_sphere = true
			elif ch is MeshInstance3D and (ch as MeshInstance3D).mesh is SphereMesh:
				keg_has_sphere = true
		var fb := keg_fx.get_node_or_null(^"FireballCore") as GPUParticles3D
		var sm := keg_fx.get_node_or_null(^"GunpowderSmoke") as GPUParticles3D
		var sp := keg_fx.get_node_or_null(^"EmberSparks") as GPUParticles3D
		check(fb != null and fb.draw_pass_1 is QuadMesh, "FireballCore uses billboarded QuadMesh")
		if fb != null and fb.draw_pass_1 is QuadMesh:
			var fb_mat := (fb.draw_pass_1 as QuadMesh).material as StandardMaterial3D
			check(fb_mat != null and fb_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "FireballCore uses additive blend")
			check(fb_mat != null and fb_mat.albedo_texture is ImageTexture, "FireballCore uses cached feathered ImageTexture")
		check(sm != null and sm.draw_pass_1 is QuadMesh, "GunpowderSmoke uses feathered QuadMesh")
		check(sp != null and sp.draw_pass_1 is QuadMesh and sp.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY,
			"EmberSparks uses velocity-aligned QuadMesh streaks")
	check(keg_layers >= 3, "KegExplosionVFX must contain at least 3 GPUParticles3D layers (got %d)" % keg_layers)
	check(not keg_has_sphere, "KegExplosionVFX must contain zero raw SphereMesh primitives")
	var trauma_near := pc.get_camera_trauma()
	var trauma_far := pc_far.get_camera_trauma()
	print("    keg blast: layers=%d trauma_near=%.3f trauma_far=%.3f" % [keg_layers, trauma_near, trauma_far])
	check(trauma_near > 0.35 and trauma_near <= 0.78, "nearby PlayerController receives distance-attenuated trauma (got %.3f)" % trauma_near)
	check_near(trauma_far, 0.0, 0.001, "PlayerController outside 24 m receives zero keg trauma")

	# Free dead powder carrier immediately; host-owned explosion must still self-clean cleanly.
	powder.queue_free()
	await physics_frames(105)
	check(not is_instance_valid(keg_fx), "KegExplosionVFX self-frees cleanly after burst completes")

	# 2. Tidecaller _summon_water_hazard() creates shader-driven TideHazard vortex (no CylinderMesh!)
	#    and erupts TideGeyserBurst on 1.1 s timeout, then cleans up with zero leaks.
	var tc := EnemyBrain.spawn_enemy(&"tidecaller", Vector3(12.0, 5.05, -6.0), _root)
	var tc_brain := tc.get_node(^"EnemyBrain") as EnemyBrain
	await physics_frames(2)
	tc_brain._summon_water_hazard(Vector3(12.0, 5.05, -1.0))

	var hazard := _root.get_node_or_null(^"TideHazard") as MeshInstance3D
	check(hazard != null, "Tidecaller spawns TideHazard node on host")
	if hazard != null:
		check(hazard.mesh is QuadMesh and not (hazard.mesh is CylinderMesh),
			"TideHazard uses ground-hugging QuadMesh rather than raw CylinderMesh")
		var hmat := hazard.material_override as ShaderMaterial
		check(hmat != null and hmat.shader != null, "TideHazard uses inline coral-rune ShaderMaterial")
		var mist := hazard.get_node_or_null(^"VortexMist") as GPUParticles3D
		check(mist != null and mist.amount == 10 and mist.draw_pass_1 is QuadMesh,
			"TideHazard includes bubbling rising mist GPUParticles3D (amount = 10)")

	# Advance halfway through 1.1 s telegraph and verify shader progress advances.
	await physics_frames(30)
	if is_instance_valid(hazard) and hazard.material_override is ShaderMaterial:
		var prog := float((hazard.material_override as ShaderMaterial).get_shader_parameter(&"progress"))
		check(prog > 0.25 and prog < 0.95, "TideHazard vortex shader progress animates smoothly (got %.2f)" % prog)

	# Advance past 1.1 s detonation -> TideHazard frees and TideGeyserBurst erupts!
	await physics_frames(44)
	check(not is_instance_valid(hazard), "TideHazard frees cleanly upon detonation")
	var geyser := _root.get_node_or_null(^"TideGeyserBurst") as Node3D
	check(geyser != null, "TideHazard detonation erupts TideGeyserBurst on host")
	var geyser_layers := 0
	var geyser_has_sphere := false
	if geyser != null:
		for ch in geyser.get_children():
			if ch is GPUParticles3D:
				geyser_layers += 1
				var gp := ch as GPUParticles3D
				if gp.draw_pass_1 is SphereMesh:
					geyser_has_sphere = true
		check(geyser.get_node_or_null(^"GeyserFoamColumn") is GPUParticles3D, "TideGeyserBurst has GeyserFoamColumn")
		check(geyser.get_node_or_null(^"GeyserDroplets") is GPUParticles3D, "TideGeyserBurst has GeyserDroplets")
		check(geyser.get_node_or_null(^"CoralSparks") is GPUParticles3D, "TideGeyserBurst has CoralSparks")
	check(geyser_layers >= 3 and not geyser_has_sphere, "TideGeyserBurst has 3 feathered particle layers and zero SphereMesh")

	await physics_frames(64)
	check(not is_instance_valid(geyser), "TideGeyserBurst self-frees cleanly after eruption")
	check(tc_brain._active_vfx.is_empty(), "Tidecaller _active_vfx is empty after teardown")

	# 3. Captain rally spawns CaptainRallyRing (verdigris-emerald for Drowned, crimson-gold for Rival)
	#    and expands smoothly 0.9 m -> 11.5 m before freeing cleanly.
	var cap := EnemyBrain.spawn_enemy(&"drowned_captain", Vector3(-6.0, 5.05, -4.0), _root)
	var ally := EnemyBrain.spawn_enemy(&"drowned_cutlass", Vector3(-4.0, 5.05, -4.0), _root)
	var cap_brain := cap.get_node(^"EnemyBrain") as EnemyBrain
	var ally_cc := ally.get_node(^"CombatComponent") as CombatComponent
	var rallied_seen := [false]
	cap_brain.rallied_allies.connect(func(_c: Pawn, _cnt: int) -> void: rallied_seen[0] = true)
	cap_brain._special_cd = 0.0
	await physics_frames(3)
	check(rallied_seen[0], "Drowned Captain emits rallied_allies on rally tick")
	check(ally_cc.damage_multiplier > 1.2, "Drowned Captain rally buffs nearby ally damage")

	var rally_ring := _root.get_node_or_null(^"CaptainRallyRing") as MeshInstance3D
	check(rally_ring != null, "Captain rally spawns CaptainRallyRing on host")
	var start_scale := 0.0
	if rally_ring != null:
		check(rally_ring.mesh is QuadMesh, "CaptainRallyRing uses ground-hugging QuadMesh")
		var rmat := rally_ring.material_override as ShaderMaterial
		check(rmat != null and rmat.shader != null, "CaptainRallyRing uses inline ShaderMaterial")
		if rmat != null:
			var dc_tint: Color = rmat.get_shader_parameter(&"tint_outer")
			check(dc_tint.g > dc_tint.r, "Drowned Captain rally ring uses eerie verdigris-emerald tint")
		start_scale = rally_ring.scale.x
	await physics_frames(18)
	var mid_scale := rally_ring.scale.x if is_instance_valid(rally_ring) else 0.0
	print("    captain rally ring scale: start=%.2f -> mid=%.2f" % [start_scale, mid_scale])
	check(mid_scale > 4.0 and mid_scale <= 11.55, "CaptainRallyRing expands smoothly toward 11.5 m (got %.2f)" % mid_scale)
	await physics_frames(30)
	check(not is_instance_valid(rally_ring), "CaptainRallyRing self-frees cleanly after 0.65 s")
	check(cap_brain._active_vfx.is_empty(), "Captain _active_vfx is empty after ring self-free")

	# Rival Captain crimson-gold rally ring + early host teardown stress test (zero leaks!).
	var sub_host := Node3D.new()
	sub_host.name = "TeardownHost"
	_root.add_child(sub_host)
	var rival := EnemyBrain.spawn_enemy(&"rival_captain", Vector3(-10.0, 5.05, -4.0), sub_host)
	var rival_brain := rival.get_node(^"EnemyBrain") as EnemyBrain
	var sub_powder := EnemyBrain.spawn_enemy(&"drowned_powder", Vector3(-12.0, 5.05, -6.0), sub_host)
	var sub_powder_brain := sub_powder.get_node(^"EnemyBrain") as EnemyBrain
	var sub_tc := EnemyBrain.spawn_enemy(&"tidecaller", Vector3(-14.0, 5.05, -6.0), sub_host)
	var sub_tc_brain := sub_tc.get_node(^"EnemyBrain") as EnemyBrain
	await physics_frames(2)

	rival_brain._perform_captain_rally()
	sub_powder_brain.detonate_keg(hero)
	sub_tc_brain._summon_water_hazard(Vector3(-14.0, 5.05, -2.0))

	var rival_ring := sub_host.get_node_or_null(^"CaptainRallyRing") as MeshInstance3D
	var sub_keg := sub_host.get_node_or_null(^"KegExplosionVFX") as Node3D
	var sub_haz := sub_host.get_node_or_null(^"TideHazard") as MeshInstance3D
	check(rival_ring != null and sub_keg != null and sub_haz != null,
		"All 3 enemy signature VFX spawn cleanly on sub_host before mid-flight teardown")
	if rival_ring != null and rival_ring.material_override is ShaderMaterial:
		var rc_tint: Color = (rival_ring.material_override as ShaderMaterial).get_shader_parameter(&"tint_outer")
		check(rc_tint.r > rc_tint.g, "Rival Captain rally ring uses warm crimson-gold tint")

	# Immediately tear down host mid-flight and confirm GPU particle/mesh resources release cleanly.
	sub_host.queue_free()
	await physics_frames(3)
	check(not is_instance_valid(rival_ring) and not is_instance_valid(sub_keg) and not is_instance_valid(sub_haz),
		"Early host teardown cleanly frees all active signature VFX with zero leaks")
	await _end()


func test_clash_sparks_and_floating_combat_embers_teardown() -> void:
	_begin()
	_ground()

	var atk_pair := _fighter(Vector3(0.0, 5.05, 0.0), &"player", 0.0)
	var def_pair := _fighter(Vector3(0.0, 5.05, -1.6), &"drowned", PI)
	var atk_cc: CombatComponent = atk_pair[1]
	var def_cc: CombatComponent = def_pair[1]
	atk_cc.enable_effects = true
	def_cc.enable_effects = true
	await physics_frames(4)

	# 1. Active block clash spawns warm steel-amber SparkStreaks + drifting CombatEmbers + compact ClashFlash.
	def_cc.set_blocking(true)
	def_cc._block_elapsed = CombatComponent.PARRY_WINDOW + 0.15
	var block_res := def_cc.receive_melee_hit(atk_cc, 20.0, false, false)
	check_eq(block_res, &"blocked", "late block returns &" + "blocked")
	check_eq(def_cc._active_vfx.size(), 1, "blocked clash tracks ClashSparks VFX node")
	var block_fx := def_cc._active_vfx[0]
	var block_streaks := block_fx.get_node_or_null(^"SparkStreaks") as GPUParticles3D
	var block_embers := block_fx.get_node_or_null(^"CombatEmbers") as GPUParticles3D
	var block_flash := block_fx.get_node_or_null(^"ClashFlash") as GPUParticles3D
	check(block_streaks != null and block_streaks.emitting, "blocked clash emits velocity-aligned SparkStreaks")
	check(block_embers != null and block_embers.emitting and block_embers.lifetime >= 0.65,
		"blocked clash emits drifting CombatEmbers (lifetime=%.2f)" % (block_embers.lifetime if block_embers != null else 0.0))
	check(block_flash != null and block_fx.get_node_or_null(^"ParryStarburst") == null,
		"blocked clash uses compact ClashFlash distinct from ParryStarburst")

	# 2. Timed parry clash spawns larger golden SparkStreaks + ParryStarburst + vivid floating CombatEmbers!
	def_cc.set_blocking(false)
	def_cc.set_blocking(true)
	def_cc._block_elapsed = 0.05
	var parry_res := def_cc.receive_melee_hit(atk_cc, 24.0, false, false)
	check_eq(parry_res, &"parried", "timed parry returns &" + "parried")
	check_eq(def_cc._active_vfx.size(), 2, "parried clash tracks second ClashSparks VFX node")
	var parry_fx := def_cc._active_vfx[1]
	var parry_streaks := parry_fx.get_node_or_null(^"SparkStreaks") as GPUParticles3D
	var parry_embers := parry_fx.get_node_or_null(^"CombatEmbers") as GPUParticles3D
	var parry_star := parry_fx.get_node_or_null(^"ParryStarburst") as GPUParticles3D
	check(parry_streaks != null and parry_streaks.amount > block_streaks.amount,
		"parried clash emits denser golden SparkStreaks (%d > %d)" % [
			parry_streaks.amount if parry_streaks != null else 0, block_streaks.amount])
	check(parry_embers != null and parry_embers.amount > block_embers.amount and parry_embers.lifetime >= 0.85,
		"parried clash emits richer longer-lived CombatEmbers")
	check(parry_star != null and parry_star.draw_pass_1 is QuadMesh and (parry_star.draw_pass_1 as QuadMesh).size.x >= 0.90,
		"parried clash emits distinct large golden ParryStarburst")

	# 3. 3rd-hit combo finisher also triggers heavy spark + floating ember burst.
	def_cc.set_blocking(false)
	atk_cc.state = CombatComponent.State.IDLE
	atk_cc.combo_step = 3
	var fin_res := def_cc.receive_melee_hit(atk_cc, 28.0, false, false)
	check_eq(fin_res, &"hit", "3rd-hit combo finisher lands cleanly")
	check_eq(def_cc._active_vfx.size(), 3, "combo finisher spawns heavy spark & ember burst")
	var fin_fx := def_cc._active_vfx[2]
	check(fin_fx.get_node_or_null(^"CombatEmbers") is GPUParticles3D, "combo finisher includes drifting CombatEmbers")

	# 4. Mid-burst teardown frees every active ClashSparks node cleanly with ZERO leaks!
	await _end()
	check(not is_instance_valid(block_fx) and not is_instance_valid(parry_fx) and not is_instance_valid(fin_fx),
		"CombatComponent _exit_tree() cleanly frees all active clash spark & ember VFX with zero leaks")



