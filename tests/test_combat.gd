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


func test_enemy_stagger_stars_and_windup_telegraph_teardown() -> void:
	_begin()
	_ground()

	# Spawn two enemies so we verify static mesh/material sharing as well as stagger & heavy windup.
	var cap_pawn := EnemyBrain.spawn_enemy(&"drowned_captain", Vector3(0.0, 5.05, 0.0), _root)
	var cor_pawn := EnemyBrain.spawn_enemy(&"corsair_raider", Vector3(10.0, 5.05, 0.0), _root)
	var cap_brain := cap_pawn.get_node(^"EnemyBrain") as EnemyBrain
	var cor_brain := cor_pawn.get_node(^"EnemyBrain") as EnemyBrain
	cap_brain.aggro_range = 0.0
	cor_brain.aggro_range = 0.0
	await physics_frames(2)

	var stars := cap_brain.get_stagger_stars_node()
	var tele := cap_brain.get_strike_telegraph_node()
	var cor_stars := cor_brain.get_stagger_stars_node()
	var cor_tele := cor_brain.get_strike_telegraph_node()

	check(stars != null and cap_pawn.get_node_or_null(^"StaggerStars") == stars,
		"EnemyBrain attaches StaggerStars MeshInstance3D to Pawn")
	check(tele != null and cap_pawn.get_node_or_null(^"StrikeTelegraph") == tele,
		"EnemyBrain attaches StrikeTelegraph MeshInstance3D to Pawn")
	check(stars.mesh is ArrayMesh and not (stars.mesh is PrimitiveMesh),
		"StaggerStars uses sculpted ArrayMesh (zero PrimitiveMesh)")
	check(tele.mesh is ArrayMesh and not (tele.mesh is PrimitiveMesh),
		"StrikeTelegraph uses sculpted ArrayMesh (zero PrimitiveMesh)")
	check_eq(stars.mesh, cor_stars.mesh, "EnemyBrains share statically cached StaggerStars ArrayMesh")
	check_eq(tele.mesh, cor_tele.mesh, "EnemyBrains share statically cached StrikeTelegraph ArrayMesh")
	check_eq(stars.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"StaggerStars disables shadows")
	check_eq(tele.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"StrikeTelegraph disables shadows")
	var stars_mat := stars.material_override as StandardMaterial3D
	var tele_mat := tele.material_override as StandardMaterial3D
	check(stars_mat != null and stars_mat.vertex_color_use_as_albedo and stars_mat.vertex_color_is_srgb,
		"StaggerStars material enables sRGB vertex color albedo")
	check(tele_mat != null and tele_mat.vertex_color_use_as_albedo and tele_mat.vertex_color_is_srgb,
		"StrikeTelegraph material enables sRGB vertex color albedo")
	check(not stars.visible, "StaggerStars starts hidden while enemy is idle")
	check(not tele.visible, "StrikeTelegraph starts hidden while enemy is idle")

	var stars_tris := floori(float((stars.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()) / 3.0)
	var tele_tris := floori(float((tele.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()) / 3.0)
	check(stars_tris >= 180, "StaggerStars has 3 sculpted 5-point stars + dizzy ribbon (%d tris)" % stars_tris)
	check(tele_tris >= 32, "StrikeTelegraph has sculpted 4-point starburst diamond (%d tris)" % tele_tris)

	# 1. Trigger stagger -> StaggerStars becomes visible, orbits rapidly, then hides when stagger ends.
	cap_brain.combat.apply_stagger(0.32)
	await physics_frames(2)
	check(stars.visible, "StaggerStars becomes visible during stagger")
	var rot0 := stars.rotation.y
	await physics_frames(8)
	var rot1 := stars.rotation.y
	check(rot1 > rot0 + 0.35, "StaggerStars orbits smoothly during stagger (%.2f -> %.2f rad)" % [rot0, rot1])
	# Let the 0.32 s stagger expire (~20+ more frames at 60 Hz).
	await physics_frames(22)
	check(not cap_brain.combat.is_staggered(), "stagger expired cleanly")
	check(not stars.visible, "StaggerStars hides automatically when stagger expires")

	# 2. Death during active stagger hides StaggerStars immediately.
	cap_brain.combat.apply_stagger(1.2)
	await physics_frames(2)
	check(stars.visible, "StaggerStars re-activates on fresh stagger")
	cap_pawn.apply_damage(999.0)
	await physics_frames(1)
	check(cap_pawn.dead and not stars.visible, "StaggerStars hides immediately on enemy death")

	# 3. Heavy attack windup flashes StrikeTelegraph cleanly, then turns off once windup completes.
	cor_brain.combat.equip_weapon(&"cutlass")
	var started_heavy := cor_brain.combat.heavy_attack()
	check(started_heavy and cor_brain.combat.state == CombatComponent.State.WINDUP,
		"Corsair starts heavy attack WINDUP")
	await physics_frames(3)
	check(cor_tele.visible, "StrikeTelegraph flashes visibly during heavy WINDUP")
	check(cor_tele.scale.x >= 0.35, "StrikeTelegraph pulses scale cleanly (%.2f)" % cor_tele.scale.x)
	# Wait past heavy_windup (0.34 s ~ 21 physics frames) so state leaves WINDUP.
	await physics_frames(26)
	check(cor_brain.combat.state != CombatComponent.State.WINDUP, "heavy attack left WINDUP state")
	check(not cor_tele.visible, "StrikeTelegraph hides cleanly after WINDUP finishes")

	# 4. Free all EnemyBrains and verify static VFX caches release cleanly to null (0 leaks)!
	await _end()
	check_eq(EnemyBrain._active_brains, 0, "all EnemyBrains exited cleanly")
	check(EnemyBrain._stagger_stars_mesh == null and EnemyBrain._stagger_stars_mat == null,
		"StaggerStars static cache released cleanly to null")
	check(EnemyBrain._telegraph_mesh == null and EnemyBrain._telegraph_mat == null,
		"StrikeTelegraph static cache released cleanly to null")


func test_blade_slash_arc_boarding_axe_cleave_and_deterministic_hitstop() -> void:
	_begin()
	_fast(false)  # Keep Engine.time_scale strictly 1.0 for deterministic hitstop assertions.
	_ground()

	var atk_pair := _fighter(Vector3(0.0, 5.05, 0.0), &"player", 0.0)
	var def_pair := _fighter(Vector3(0.0, 5.05, -1.65), &"drowned", PI)
	var pa: Pawn = atk_pair[0]
	var atk_cc: CombatComponent = atk_pair[1]
	var pb: Pawn = def_pair[0]
	var def_cc: CombatComponent = def_pair[1]
	atk_cc.enable_effects = true
	def_cc.enable_effects = true

	var pc := PlayerController.new()
	pc.name = "PlayerController"
	pc.input_enabled = false
	pc.capture_mouse = false
	pc.make_current = false
	pc.bob_amount = 0.028
	pa.add_child(pc)
	await physics_frames(4)

	# 1. Verify statically cached sculpted 1-DC BladeSlashArc ArrayMesh (>= 32 tris, zero PrimitiveMesh, vertex colors).
	var arc_mesh_base: Mesh = CombatComponent._get_slash_arc_mesh()
	check(arc_mesh_base != null and arc_mesh_base is ArrayMesh and not (arc_mesh_base is PrimitiveMesh),
		"BladeSlashArc uses sculpted ArrayMesh with zero raw PrimitiveMesh")
	var arc_mesh := arc_mesh_base as ArrayMesh
	var surf_arrs := arc_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = surf_arrs[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = surf_arrs[Mesh.ARRAY_COLOR]
	var tri_count := floori(float(verts.size()) / 3.0)
	print("    BladeSlashArc sculpted triangles: %d (verts=%d)" % [tri_count, verts.size()])
	check(tri_count >= 32, "BladeSlashArc mesh must have >= 32 triangles (got %d)" % tri_count)
	check_eq(cols.size(), verts.size(), "BladeSlashArc encodes per-vertex colors for edge-to-wake fade")
	var saw_bright_edge := false
	var saw_translucent_wake := false
	for vc: Color in cols:
		if vc.a >= 0.85 and vc.r >= 0.95:
			saw_bright_edge = true
		if vc.a <= 0.05:
			saw_translucent_wake = true
	check(saw_bright_edge and saw_translucent_wake,
		"BladeSlashArc vertex colors taper from white-hot leading edge to translucent inner wake")

	# 2. Cutlass 3-hit combo light_1..light_3 spawn distinct BladeSlashArc instances that animate & self-clean.
	# Move defender temporarily out of range while inspecting combo arc spawning cleanly.
	pb.global_position = Vector3(12.0, 5.05, -12.0)
	atk_cc.equip_weapon(&"cutlass")
	var expected_styles: Array[StringName] = [&"light_1", &"light_2", &"light_3"]
	var combo_scales: Array[float] = []
	var combo_tints: Array[Color] = []

	for step_idx in 3:
		atk_cc.state = CombatComponent.State.IDLE
		atk_cc._state_timer = 0.0
		check(atk_cc.primary_attack(), "Cutlass combo step %d starts attack" % (step_idx + 1))
		for _f in 25:
			await physics_frames(1)
			if atk_cc.state == CombatComponent.State.ACTIVE and not atk_cc._slash_arcs.is_empty():
				break
		check_eq(atk_cc._slash_arcs.size(), 1, "Cutlass combo %d spawns BladeSlashArc on ACTIVE" % (step_idx + 1))
		var entry: Dictionary = atk_cc._slash_arcs[0]
		var arc_mi := entry["node"] as MeshInstance3D
		check(arc_mi != null and arc_mi.name == "BladeSlashArc", "spawned node is named BladeSlashArc")
		check_eq(arc_mi.mesh, arc_mesh, "BladeSlashArc reuses shared statically cached ArrayMesh")
		check_eq(arc_mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "BladeSlashArc disables shadows")
		check_eq(StringName(arc_mi.get_meta(&"slash_style")), expected_styles[step_idx],
			"Cutlass combo %d uses style %s" % [step_idx + 1, String(expected_styles[step_idx])])
		var mat := arc_mi.material_override as StandardMaterial3D
		check(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
			and mat.cull_mode == BaseMaterial3D.CULL_DISABLED
			and mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb,
			"BladeSlashArc uses unshaded additive double-sided sRGB vertex-color material")
		combo_scales.append((arc_mi.get_meta(&"base_scale") as Vector3).x)
		combo_tints.append(arc_mi.get_meta(&"base_tint") as Color)

		var rot_before := arc_mi.global_basis
		await physics_frames(4)
		if is_instance_valid(arc_mi):
			check(not arc_mi.global_basis.is_equal_approx(rot_before),
				"BladeSlashArc sweeps rotation smoothly during _process")
		for _w in 45:
			await physics_frames(1)
			if not is_instance_valid(arc_mi):
				break
		check(not is_instance_valid(arc_mi) and atk_cc._slash_arcs.is_empty(),
			"Cutlass combo %d BladeSlashArc self-cleans cleanly after 0.19 s" % (step_idx + 1))

	check(combo_scales[2] > combo_scales[0] + 0.15, "Cutlass combo-3 finisher arc is wider (%.2f vs %.2f)" % [combo_scales[2], combo_scales[0]])
	check(combo_tints[2].b < combo_tints[0].b - 0.20, "Cutlass combo-3 finisher shifts to warmer golden glow")

	# 3. Boarding Axe heavy cleave spawns bold fiery amber-crimson shockwave crescent (1.55x scale) & self-cleans.
	atk_cc.equip_weapon(&"boarding_axe")
	atk_cc.state = CombatComponent.State.IDLE
	atk_cc.stamina = atk_cc.max_stamina
	check(atk_cc.heavy_attack(), "Boarding Axe heavy attack starts cleanly")
	for _f in 45:
		await physics_frames(1)
		if atk_cc.state == CombatComponent.State.ACTIVE and not atk_cc._slash_arcs.is_empty():
			break
	check_eq(atk_cc._slash_arcs.size(), 1, "Boarding Axe heavy spawns BladeSlashArc on ACTIVE")
	var axe_arc := atk_cc._slash_arcs[0]["node"] as MeshInstance3D
	check(axe_arc != null and StringName(axe_arc.get_meta(&"slash_style")) == &"axe_heavy",
		"Boarding Axe heavy uses axe_heavy cleave style")
	var axe_tint: Color = axe_arc.get_meta(&"base_tint")
	var axe_scale: Vector3 = axe_arc.get_meta(&"base_scale")
	check(axe_tint.r > 0.92 and axe_tint.g < 0.50 and axe_tint.b < 0.20,
		"Boarding Axe heavy cleave uses fiery amber-crimson tint (%s)" % str(axe_tint))
	check(axe_scale.x >= 1.50 and axe_scale.x > combo_scales[2] + 0.25,
		"Boarding Axe heavy cleave is noticeably wider than Cutlass (%.2f vs %.2f)" % [axe_scale.x, combo_scales[2]])
	for _w in 45:
		await physics_frames(1)
		if not is_instance_valid(axe_arc):
			break
	check(not is_instance_valid(axe_arc) and atk_cc._slash_arcs.is_empty(),
		"Boarding Axe heavy BladeSlashArc self-cleans cleanly")

	# 4. Deterministic visual micro-hitstop on light hit & timed parry: NEVER alters Engine.time_scale!
	pb.global_position = Vector3(0.0, 5.05, -1.65)
	pb.health = pb.max_health
	pa.health = pa.max_health
	atk_cc.equip_weapon(&"cutlass")
	atk_cc.state = CombatComponent.State.IDLE
	atk_cc.combo_step = 1
	def_cc.state = CombatComponent.State.IDLE
	def_cc.set_blocking(false)
	pc._trauma = 0.0

	check_near(Engine.time_scale, 1.0, 0.0001, "Engine.time_scale starts at 1.0")
	var light_res := def_cc.receive_melee_hit(atk_cc, 18.0, false, false)
	check_eq(light_res, &"hit", "light melee strike connects cleanly")
	check(atk_cc.get_hitstop_remaining() > 0.0 and atk_cc.get_hitstop_remaining() <= 0.030,
		"light hit triggers ~0.024 s visual hitstop (got %.4f s)" % atk_cc.get_hitstop_remaining())
	check(pc.get_camera_trauma() >= 0.14, "light melee hit triggers subtle local camera trauma (got %.3f)" % pc.get_camera_trauma())
	check_near(Engine.time_scale, 1.0, 0.0001, "Engine.time_scale remains strictly 1.0 during light hitstop")

	# Wait for hitstop to decay cleanly to 0.
	await physics_frames(6)
	check_near(atk_cc.get_hitstop_remaining(), 0.0, 0.001, "visual hitstop snaps cleanly back to 0.0")

	# Timed parry triggers longer 0.042 s visual hitstop on both combatants while Engine.time_scale stays 1.0.
	def_cc.set_blocking(true)
	def_cc._block_elapsed = 0.04
	pc._trauma = 0.0
	var parry_res := def_cc.receive_melee_hit(atk_cc, 24.0, false, false)
	check_eq(parry_res, &"parried", "timed parry triggers cleanly")
	check(def_cc.get_hitstop_remaining() >= 0.035 and atk_cc.get_hitstop_remaining() >= 0.035,
		"timed parry triggers ~0.042 s visual hitstop (def=%.4f atk=%.4f)" % [
			def_cc.get_hitstop_remaining(), atk_cc.get_hitstop_remaining()])
	check(pc.get_camera_trauma() >= 0.22, "parry clash adds crisp impact camera trauma (got %.3f)" % pc.get_camera_trauma())
	check_near(Engine.time_scale, 1.0, 0.0001, "Engine.time_scale remains strictly 1.0 during parry hitstop")

	# Accessibility gate: reduced motion (bob_amount == 0.0) suppresses hitstop & camera trauma cleanly.
	await physics_frames(8)
	pc.bob_amount = 0.0
	pc._trauma = 0.0
	def_cc.set_blocking(false)
	def_cc.state = CombatComponent.State.IDLE
	atk_cc.state = CombatComponent.State.IDLE
	var rm_res := def_cc.receive_melee_hit(atk_cc, 20.0, true, false)
	check_eq(rm_res, &"hit", "heavy hit still resolves damage normally under reduced motion")
	check_near(atk_cc.get_hitstop_remaining(), 0.0, 0.0001, "reduced motion disables visual hitstop jolt on local player")
	check_near(pc.get_camera_trauma(), 0.0, 0.0001, "reduced motion keeps camera trauma at 0.0")

	# 5. Showcase frozen BladeSlashArc stays visible in place and frees cleanly with 0 static cache leaks!
	var frozen_arc := atk_cc.spawn_showcase_slash_arc(Vector3(0.0, 6.2, -0.8), Basis.IDENTITY, &"heavy", true)
	check(frozen_arc != null and frozen_arc.mesh == arc_mesh, "spawn_showcase_slash_arc spawns sculpted frozen arc")
	await physics_frames(18)
	check(is_instance_valid(frozen_arc) and frozen_arc.visible,
		"freeze_in_place showcase BladeSlashArc remains held at mid-clash glow across frames")

	await _end()
	check(not is_instance_valid(frozen_arc), "frozen showcase BladeSlashArc frees cleanly on _exit_tree()")
	check_eq(CombatComponent._active_combatants, 0, "all CombatComponents exited cleanly")
	check(CombatComponent._slash_arc_mesh == null, "BladeSlashArc static ArrayMesh cache released to null (0 leaks)")


class _RunningDarkTargetStub extends Node3D:
	var lanterns_lit: bool = false


func test_wave28_night_running_dark_reduces_ai_ship_aggro_range() -> void:
	_begin()
	var player_ship := SLOOP_SCENE.instantiate() as Ship
	player_ship.enable_effects = false
	player_ship.faction = &"player"
	_root.add_child(player_ship)
	player_ship.global_position = Vector3(0.0, 0.0, 0.0)

	# Place enemy sloop at 360 m: inside full 480 m aggro_range, outside night stealth 297.6 m!
	var foe := AIShipBrain.spawn_enemy_sloop(&"drowned_sloop", Vector3(360.0, 0.0, 0.0), _root, null)
	foe.enable_effects = false
	var ai_brain := foe.get_node(^"AIShipBrain") as AIShipBrain
	check(ai_brain != null, "enemy sloop exposes AIShipBrain")
	check_near(AIShipBrain.NIGHT_STEALTH_AGGRO_MULT, 0.62, 0.0001, "NIGHT_STEALTH_AGGRO_MULT is 0.62")

	var dark_stub := _RunningDarkTargetStub.new()
	dark_stub.lanterns_lit = false
	_root.add_child(dark_stub)
	var lit_stub := _RunningDarkTargetStub.new()
	lit_stub.lanterns_lit = true
	_root.add_child(lit_stub)

	var has_real_lanterns := player_ship.get(&"lanterns_lit") != null
	var full_range := ai_brain.aggro_range
	var stealth_range := full_range * AIShipBrain.NIGHT_STEALTH_AGGRO_MULT

	# 1. At noon (12:00), effective_aggro_range equals aggro_range regardless of lanterns.
	Weather.time_of_day = 12.0
	check(Weather.sun_height() > 0.0, "noon sun_height is positive")
	check_near(ai_brain.effective_aggro_range(player_ship), full_range, 0.01,
		"noon effective_aggro_range on real Ship equals aggro_range")
	check_near(ai_brain.effective_aggro_range(lit_stub), full_range, 0.01,
		"noon effective_aggro_range on lit ship equals aggro_range")
	check_near(ai_brain.effective_aggro_range(dark_stub), full_range, 0.01,
		"noon effective_aggro_range on dark ship still equals aggro_range")
	if has_real_lanterns:
		player_ship.set(&"lanterns_lit", false)
		check_near(ai_brain.effective_aggro_range(player_ship), full_range, 0.01,
			"noon effective_aggro_range ignores doused lanterns on real Ship")
		player_ship.set(&"lanterns_lit", true)

	# 2. At night (23:00), lit ships keep full aggro_range while dark ships drop to 0.62x!
	Weather.time_of_day = 23.0
	check(Weather.sun_height() < 0.0, "23:00 night sun_height is below horizon")
	check_near(ai_brain.effective_aggro_range(lit_stub), full_range, 0.01,
		"night effective_aggro_range stays full when lanterns_lit is true")
	check_near(ai_brain.effective_aggro_range(dark_stub), stealth_range, 0.01,
		"night effective_aggro_range drops to aggro_range * 0.62 when running dark (%.1f m)" % stealth_range)

	if has_real_lanterns:
		player_ship.set(&"lanterns_lit", true)
		check_near(ai_brain.effective_aggro_range(player_ship), full_range, 0.01,
			"night real Ship with lit lanterns keeps full aggro_range")
		check_eq(ai_brain._find_player_ship(), player_ship,
			"patrolling AI spots lit real Ship at 360 m at night")

		player_ship.set(&"lanterns_lit", false)
		check_near(ai_brain.effective_aggro_range(player_ship), stealth_range, 0.01,
			"night real Ship running dark drops aggro_range to 0.62x")
		check(ai_brain._find_player_ship() == null,
			"patrolling AI cannot spot dark real Ship at 360 m at night (stealth range %.1f m)" % stealth_range)

		# Moving inside 297.6 m lets the AI spot even a dark ship.
		player_ship.global_position = Vector3(140.0, 0.0, 0.0)
		check_eq(ai_brain._find_player_ship(), player_ship,
			"patrolling AI spots dark real Ship once it closes to 220 m")

	# 3. Chainshot sail-damage reaction check (is_sail_damaged + defensive evasive helm bias).
	check(not ai_brain.is_sail_damaged(), "undamaged enemy ship reports is_sail_damaged() == false")
	if foe.get(&"sail_damage_timer") != null:
		foe.set(&"sail_damage_timer", 5.0)
		check(ai_brain.is_sail_damaged(), "enemy ship with active sail_damage_timer reports is_sail_damaged() == true")
		ai_brain.target_ship = null
		await physics_frames(4)
		check(absf(foe.helm_target) >= AIShipBrain.SAIL_DAMAGE_EVASIVE_HELM_BIAS * 0.9,
			"sail-damaged enemy ship applies defensive evasive helm bias (helm=%.2f)" % foe.helm_target)

	await _end()


func test_wave31_ship_fire_scorches_pawns_spreads_and_storm_rain_extinguishes() -> void:
	_begin()
	Weather.set_weather(0.0, 6.0, 0.0)
	Sea.amp_scale = 0.0

	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	ship.faction = &"player"
	ship.start_anchored = true
	_root.add_child(ship)
	ship.global_position = Vector3(0.0, 0.0, 0.0)
	await physics_frames(6)

	var sf := ship.get_ship_fire()
	check(sf != null, "Ship mounts ShipFire component")
	var zone0_local := sf.get_zone_local_pos(0)

	# Place one Pawn standing inside the 1.85 m scorch zone and a bystander Pawn far aft (> 4 m away).
	var near_pawn := PAWN_SCENE.instantiate() as Pawn
	var far_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(near_pawn)
	_root.add_child(far_pawn)
	near_pawn.board(ship, zone0_local + Vector3(0.45, 0.02, 0.25))
	far_pawn.board(ship, ship.ship_point(Vector3(0.0, 2.02, 4.4)))
	await physics_frames(4)

	var ignited_zones: Array[int] = []
	var all_out_events := [0]
	sf.fire_ignited.connect(func(zi: int) -> void: ignited_zones.append(zi))
	sf.all_fires_out.connect(func() -> void: all_out_events[0] += 1)

	# 1. Ignite zone 0 in clear weather -> scorches standing Pawn within 1.85 m (3.0 HP / 0.5 s), spares distant Pawn!
	var hp_near0 := near_pawn.health
	var hp_far0 := far_pawn.health
	check(sf.ignite_zone(0, 1.0), "ShipFire ignites zone 0 at intensity 1.0")
	check_eq(sf.get_active_fire_count(), 1, "active fire count starts at 1")
	check(sf.get_fire_light() != null and sf.get_fire_light().visible,
		"shared unshadowed OmniLight3D lights up when fire burns")

	# Step 1.6 s in clear weather (3 scorch ticks -> ~9.0 fire damage to near_pawn).
	for _i in 16:
		sf.step_fire(0.1)
	var scorch_dmg := hp_near0 - near_pawn.health
	print("    Wave 31B ShipFire scorch: near_pawn took %.1f dmg (far_pawn=%.1f)" % [
		scorch_dmg, hp_far0 - far_pawn.health])
	check(scorch_dmg >= 6.0, "standing Pawn within 1.85 m is scorched by active flame (dmg=%.1f)" % scorch_dmg)
	check_near(far_pawn.health, hp_far0, 0.01, "bystander Pawn beyond 1.85 m takes zero scorch damage")

	# 2. Unchecked clear-weather fire spreads to a neighboring zone (~11.0 s) & chars a hull hole (~18.0 s)!
	# Move near_pawn safely away so it does not die while stepping spread/char timers.
	near_pawn.board(ship, ship.ship_point(Vector3(0.0, 2.02, 4.4)))
	for _i in 105:
		sf.step_fire(0.1)
	check(sf.get_active_fire_count() >= 2,
		"unchecked clear-weather fire spreads to adjacent zone after 11.0 s (active=%d)" % sf.get_active_fire_count())
	check(ignited_zones.size() >= 2, "fire_ignited signal fired for spread zone")

	for _i in 75:
		sf.step_fire(0.1)
	check(ship.open_hole_count() >= 1,
		"unchecked fire for 18.0 s chars a hull hole via apply_hull_damage() (open=%d)" % ship.open_hole_count())

	# 3. Heavy storm rain (Weather.storminess = 0.85) decays flames at -0.26/s and extinguishes cleanly!
	Weather.storminess = 0.85
	check(Weather.storminess > 0.55, "Weather.storminess set to heavy storm rain (%.2f)" % Weather.storminess)
	var inten_before := sf.get_zone_intensity(0)
	sf.step_fire(1.0)
	var inten_after_1s := sf.get_zone_intensity(0)
	check(inten_after_1s < inten_before - 0.20,
		"heavy storm rain decays active flame intensity at ~-0.26/s (%.2f -> %.2f)" % [inten_before, inten_after_1s])

	for _i in 40:
		sf.step_fire(0.15)
		if not sf.has_active_fire():
			break
	check(not sf.has_active_fire() and sf.get_active_fire_count() == 0,
		"heavy storm rain fully extinguishes all active deck fires")
	check(all_out_events[0] >= 1, "all_fires_out emitted once storm rain snuffs the last flame")
	check(not sf.get_fire_light().visible, "shared OmniLight3D hides cleanly once storm rain snuffs fires")

	await _end()
	ShipFire.clear_shared_cache()
	check_eq(ShipFire._active_instances, 0, "ShipFire._active_instances == 0 after combat teardown")
	check(ShipFire._flame_mesh == null and ShipFire._flame_mat == null,
		"ShipFire static cache released cleanly (0 leaks)")


class _MockKegContainer extends Node:
	var accepted_count: int = 0

	func accept_carryable(_item: Node) -> bool:
		accepted_count += 1
		return true


func test_wave34_powder_keg_sculpted_fuse_shoot_slash_fire_chain_and_hull_breach() -> void:
	_begin()
	_ground()

	# 1. Spawn PowderKeg: verify sculpted geometry (>= 640 tris, 0 PrimitiveMesh, shared BC7 PBR, 0 extra VRAM)
	#    and MerchantStall / TreasureCatalog sellable metadata (220g, 30 Iron Tide Renown).
	var keg := PowderKeg.spawn_at(_root, Vector3(0.0, 5.05, -2.5))
	await physics_frames(2)

	var tris := keg.get_triangle_count()
	print("    Wave 34B PowderKeg sculpted triangles: %d (body=%d cord=%d ember=%d spark=%d)" % [
		tris,
		PowderKeg._count_mesh_tris(PowderKeg._keg_mesh),
		PowderKeg._count_mesh_tris(PowderKeg._fuse_cord_mesh),
		PowderKeg._count_mesh_tris(PowderKeg._ember_mesh),
		PowderKeg._count_mesh_tris(PowderKeg._spark_mesh),
	])
	check(tris >= 640, "PowderKeg sculpted mesh must have >= 640 triangles (got %d)" % tris)
	check_eq(PowderKeg._count_mesh_tris(PowderKeg._spark_mesh), 16, "FuseSparks uses sculpted 16-tri diamond mesh")

	var primitive_count := 0
	for mi_n in keg.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_n as MeshInstance3D
		if mi.mesh is PrimitiveMesh:
			primitive_count += 1
	for cp_n in keg.find_children("*", "CPUParticles3D", true, false):
		var cp := cp_n as CPUParticles3D
		if cp.mesh is PrimitiveMesh:
			primitive_count += 1
	for static_m: Mesh in [
		PowderKeg._keg_mesh, PowderKeg._fuse_cord_mesh, PowderKeg._ember_mesh,
		PowderKeg._spark_mesh, PowderKeg._fireball_mesh, PowderKeg._shockwave_mesh,
		PowderKeg._splinter_mesh, PowderKeg._smoke_puff_mesh,
	]:
		check(static_m is ArrayMesh and not (static_m is PrimitiveMesh),
			"all PowderKeg body & blast VFX meshes are sculpted ArrayMeshes (zero PrimitiveMesh)")
	check_eq(primitive_count, 0, "PowderKeg node tree contains zero PrimitiveMeshes")

	var kmat := keg.get_keg_material()
	check(kmat != null and kmat.vertex_color_use_as_albedo and kmat.vertex_color_is_srgb,
		"PowderKeg material uses sRGB vertex-color albedo")
	check(kmat != null and kmat.uv1_triplanar and not kmat.uv1_world_triplanar,
		"PowderKeg material uses object-space triplanar mapping (uv1_world_triplanar == false)")
	check(kmat != null and kmat.normal_texture != null and not PowderKeg._pbr_tex_cache.is_empty(),
		"PowderKeg shares WeakRef-cached ship BC7 PBR textures (0 extra VRAM)")

	var info := TreasureCatalog.inspect_carryable(keg)
	check_eq(StringName(info.get("treasure_id", &"")), &"powder_keg", "metadata treasure_id == powder_keg")
	check_eq(int(info.get("gold_value", 0)), 220, "metadata gold_value == 220")
	check_eq(int(info.get("renown_value", 0)), 30, "metadata renown_value == 30")
	check_eq(StringName(info.get("company_id", &"")), &"iron_tide", "metadata company_id == iron_tide")

	# 2. Fuse lifecycle + PlayerController prompts + refuse hand_to while lit!
	var hero_pair := _fighter(Vector3(0.0, 5.05, 0.0), &"player", 0.0)
	var hero: Pawn = hero_pair[0]
	var hcc: CombatComponent = hero_pair[1]
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	pc.input_enabled = false
	pc.capture_mouse = false
	pc.make_current = false
	pc.bob_amount = 0.028
	hero.add_child(pc)

	var bystander_pair := _fighter(Vector3(0.0, 5.05, -5.2), &"drowned", PI)
	var bystander: Pawn = bystander_pair[0]
	await physics_frames(4)

	check(hero.pick_up(keg), "Pawn picks up PowderKeg cleanly")
	pc._update_focus()
	check_eq(pc.focus_prompt, "[LMB] Light Fuse  |  [F/RMB] Drop", "unlit carried PowderKeg shows strict ASCII light prompt")

	var lit_count := [0]
	var ext_count := [0]
	var det_count := [0]
	keg.fuse_lit.connect(func(_k: PowderKeg, _l: Node) -> void: lit_count[0] += 1)
	keg.fuse_extinguished.connect(func(_k: PowderKeg) -> void: ext_count[0] += 1)
	keg.detonated.connect(func(_k: PowderKeg, _p: Vector3, _t: Node) -> void: det_count[0] += 1)

	var fuse_light := keg.find_child("FuseLight", true, false) as OmniLight3D
	check(fuse_light != null and not fuse_light.visible and not fuse_light.shadow_enabled,
		"FuseLight starts hidden and unshadowed")

	check(keg.ignite_fuse(hero), "ignite_fuse() lights the 4.5 s countdown")
	check(keg.is_fuse_lit() and lit_count[0] == 1, "is_fuse_lit() == true and fuse_lit emitted")
	check_near(keg.fuse_remaining, PowderKeg.FUSE_DURATION, 0.05, "fuse_remaining starts at 4.5 s")
	check(fuse_light.visible, "FuseLight illuminates while fuse burns")

	pc._update_focus()
	check_eq(pc.focus_prompt, "[RMB] Defuse  |  [F] Drop (LIVE FUSE!)", "lit carried PowderKeg shows strict ASCII defuse prompt")
	for ch_idx in pc.focus_prompt.length():
		check(pc.focus_prompt.unicode_at(ch_idx) < 128, "focus_prompt stays strictly ASCII (< 128)")

	var mock_stall := _MockKegContainer.new()
	_root.add_child(mock_stall)
	check(not keg.hand_to(mock_stall), "hand_to() refuses selling a live lit PowderKeg")
	check_eq(mock_stall.accepted_count, 0, "container did not receive lit PowderKeg")

	check(keg.extinguish_fuse(), "extinguish_fuse() snuffs active fuse cleanly")
	check(not keg.is_fuse_lit() and ext_count[0] == 1, "fuse_extinguished emitted and fuse snuffed")
	check(not fuse_light.visible, "FuseLight hides once defused")

	# Verify an unlit PowderKeg CAN be handed to a container / merchant stall.
	var sell_keg := PowderKeg.spawn_at(_root, Vector3(8.0, 5.05, 0.0))
	await physics_frames(2)
	check(sell_keg.hand_to(mock_stall) and mock_stall.accepted_count == 1,
		"unlit PowderKeg hands over cleanly to MerchantStall/container")
	sell_keg.queue_free()

	# Drop keg near bystander, re-light, and step 4.6 s until detonation!
	hero.drop_carried(0.0)
	keg.global_position = Vector3(0.0, 5.05, -4.5)
	await physics_frames(2)
	var by_hp0 := bystander.health
	pc._trauma = 0.0
	check(keg.ignite_fuse(hero), "re-lighting dropped PowderKeg succeeds")
	for _step in 46:
		keg._physics_process(0.1)
		if keg.exploded:
			break
	check(keg.exploded and det_count[0] == 1, "stepping 4.6 s detonates lit PowderKeg and emits detonated")
	check(bystander.health < by_hp0 - 40.0, "PowderKeg blast deals heavy quadratic damage to nearby pawn (hp %.1f -> %.1f)" % [by_hp0, bystander.health])
	check(pc.get_camera_trauma() >= 0.40, "nearby PlayerController receives heavy blast trauma (%.2f)" % pc.get_camera_trauma())
	await physics_frames(2)

	# 3. Ship hull devastation: 3 hull breaches + ShipFire deck flames!
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	ship.start_anchored = true
	_root.add_child(ship)
	ship.global_position = Vector3(60.0, 0.0, 0.0)
	await physics_frames(6)
	check_eq(ship.open_hole_count(), 0, "fresh ship starts with 0 open hull holes")
	check(not ship.has_deck_fire(), "fresh ship starts with no deck fire")

	var deck_keg := PowderKeg.spawn_at(_root, ship.global_transform * ship.ship_point(Vector3(0.0, 1.25, -1.0)))
	await physics_frames(2)
	var ship_res := deck_keg.detonate(hero)
	check_eq(int(ship_res.get("ships_breached", 0)), 1, "detonating PowderKeg on Ship reports 1 ship breached")
	check(ship.open_hole_count() >= 3, "PowderKeg punches >= 3 hull breaches (got %d)" % ship.open_hole_count())
	check(ship.has_deck_fire(), "PowderKeg ignites ShipFire deck flames on breached Ship")
	await physics_frames(2)

	# 4. Flintlock ranged shot detonates PowderKeg + emits target_hit!
	var shot_keg := PowderKeg.spawn_at(_root, Vector3(5.5, 5.05, -6.0))
	shot_keg.freeze = true
	var shot_blown := [false]
	shot_keg.detonated.connect(func(_k: PowderKeg, _p: Vector3, _t: Node) -> void: shot_blown[0] = true)
	var shot_keg_id := shot_keg.get_instance_id()
	await physics_frames(4)
	var ranged_hit_ids: Array[int] = []
	var hit_cb := func(t: Node, _d: float, _h: bool) -> void:
		if t != null:
			ranged_hit_ids.append(t.get_instance_id())
	hcc.target_hit.connect(hit_cb)
	hero.global_position = Vector3(0.0, 5.05, 0.0)
	var aim := (shot_keg.global_position + Vector3(0.0, PowderKeg.KEG_CENTER_Y, 0.0)) - hero.eye_position()
	hero.look_yaw = atan2(-aim.x, -aim.z)
	hero.look_pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
	hcc.equip_weapon(&"pistol")
	hcc.state = CombatComponent.State.IDLE
	hcc.refill_ammo()
	check(hcc.primary_attack(), "Flintlock pistol fires at PowderKeg")
	check(shot_blown[0], "Flintlock pistol shot detonates PowderKeg immediately")
	check(ranged_hit_ids.has(shot_keg_id), "CombatComponent emits target_hit for shot PowderKeg")
	await physics_frames(2)

	# 5. Cutlass melee slash detonates PowderKeg!
	var slash_keg := PowderKeg.spawn_at(_root, Vector3(0.0, 5.05, -1.7))
	slash_keg.freeze = true
	var slash_blown := [false]
	slash_keg.detonated.connect(func(_k: PowderKeg, _p: Vector3, _t: Node) -> void: slash_blown[0] = true)
	var slash_keg_id := slash_keg.get_instance_id()
	await physics_frames(3)
	ranged_hit_ids.clear()
	hero.global_position = Vector3(0.0, 5.05, 0.0)
	hero.look_yaw = 0.0
	hero.look_pitch = 0.0
	hcc.equip_weapon(&"cutlass")
	hcc.state = CombatComponent.State.IDLE
	hcc._state_timer = 0.0
	check(hcc.primary_attack(), "Cutlass melee swing starts cleanly")
	await physics_frames(18)
	check(slash_blown[0], "Cutlass melee slash detonates PowderKeg immediately")
	check(ranged_hit_ids.has(slash_keg_id), "CombatComponent emits target_hit for slashed PowderKeg")
	hcc.target_hit.disconnect(hit_cb)

	# 6. ShipFire active zone detonates adjacent PowderKeg within 2.4 m!
	var sf := ship.get_ship_fire()
	sf.douse_all()
	var z0_world := sf.get_zone_world_pos(0)
	var fire_keg := PowderKeg.spawn_at(_root, z0_world + Vector3(1.1, 0.05, 0.0))
	fire_keg.freeze = true
	var fire_blown := [false]
	fire_keg.detonated.connect(func(_k: PowderKeg, _p: Vector3, _t: Node) -> void: fire_blown[0] = true)
	await physics_frames(2)
	check(sf.ignite_zone(0, 0.9), "ShipFire ignites zone 0 next to PowderKeg")
	for _f in 6:
		sf.step_fire(0.15)
		if fire_blown[0]:
			break
	check(fire_blown[0], "ShipFire active zone detonates adjacent PowderKeg within 2.4 m")
	await physics_frames(2)

	# 7. Cannonball impact detonates adjacent PowderKeg!
	var cb_keg := PowderKeg.spawn_at(_root, Vector3(18.0, 5.05, -6.0))
	cb_keg.freeze = true
	var cb_blown := [false]
	cb_keg.detonated.connect(func(_k: PowderKeg, _p: Vector3, _t: Node) -> void: cb_blown[0] = true)
	await physics_frames(2)
	var ball := Cannonball.new()
	ball.enable_effects = false
	ball.shooter_pawn = hero
	ball.velocity = Vector3(0.0, -24.0, 0.0)
	_root.add_child(ball)
	ball.global_position = Vector3(19.6, 5.45, -6.0)
	await physics_frames(8)
	check(cb_blown[0], "Cannonball ground/deck splash within 3.2 m detonates adjacent PowderKeg")
	if is_instance_valid(ball):
		ball.queue_free()
	await physics_frames(2)

	# 8. Chain detonation blows adjacent PowderKeg within CHAIN_BLAST_RADIUS without infinite recursion!
	var chain_a := PowderKeg.spawn_at(_root, Vector3(-16.0, 5.05, -6.0))
	var chain_b := PowderKeg.spawn_at(_root, Vector3(-11.5, 5.05, -6.0))
	var chain_far := PowderKeg.spawn_at(_root, Vector3(-28.0, 5.05, -6.0))
	chain_a.freeze = true
	chain_b.freeze = true
	chain_far.freeze = true
	var chain_a_blown := [false]
	var chain_b_blown := [false]
	chain_a.detonated.connect(func(_k: PowderKeg, _p: Vector3, _t: Node) -> void: chain_a_blown[0] = true)
	chain_b.detonated.connect(func(_k: PowderKeg, _p: Vector3, _t: Node) -> void: chain_b_blown[0] = true)
	await physics_frames(2)
	var chain_res := chain_a.detonate(hero)
	check(chain_a_blown[0] and chain_b_blown[0], "Chain detonation blows adjacent PowderKeg within 7.8 m")
	check_eq(int(chain_res.get("kegs_chained", 0)), 1, "chain_res reports exactly 1 chained keg without recursion")
	check(is_instance_valid(chain_far) and not chain_far.exploded, "distant PowderKeg outside 7.8 m remains intact")

	# 9. Clean teardown with PowderKeg.clear_shared_cache() and ZERO leaks!
	await _end()
	PowderKeg.clear_shared_cache()
	check_eq(PowderKeg._active_kegs, 0, "PowderKeg._active_kegs == 0 after teardown")
	check(PowderKeg._keg_mesh == null and PowderKeg._ember_mesh == null and PowderKeg._spark_mesh == null,
		"PowderKeg static meshes released cleanly to null (0 leaks)")
	check(PowderKeg._keg_mat == null and PowderKeg._ember_mat == null and PowderKeg._pbr_tex_cache.is_empty(),
		"PowderKeg static materials and WeakRef PBR cache released cleanly (0 leaks)")


func test_wave35_ancient_megalodon_sculpted_boss_charge_interrupt_bite_cannon_hit_spyglass_and_salvage() -> void:
	_begin()
	Weather.set_weather(0.0, 6.0, 0.0)
	Sea.amp_scale = 0.0

	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	ship.faction = &"player"
	ship.start_anchored = true
	_root.add_child(ship)
	ship.global_position = Vector3.ZERO
	await physics_frames(4)

	# 1. Spawn AncientMegalodon near ship and verify sculpted >= 2,200 tris, 0 PrimitiveMeshes,
	#    vertex_color_is_srgb == true, 0 extra VRAM textures, and finite unit normals!
	var mega := AncientMegalodon.spawn_near_ship(_root, ship, Vector3(AncientMegalodon.CIRCLE_RADIUS, 0.0, 0.0))
	await physics_frames(2)

	check(mega.is_in_group(AncientMegalodon.GROUP), "AncientMegalodon is in group &'megalodons'")
	check(mega.is_in_group(&"world_events"), "AncientMegalodon is in group &'world_events'")
	check(mega.is_in_group(&"beasts"), "AncientMegalodon is in group &'beasts'")
	check_eq(mega.state, AncientMegalodon.State.EMERGE, "AncientMegalodon starts in State.EMERGE")
	check_near(mega.health, AncientMegalodon.MAX_HEALTH, 0.01, "AncientMegalodon starts at 420 HP")

	var mesh_nodes := mega.find_children("*", "MeshInstance3D", true, false)
	check(mesh_nodes.size() >= 6, "AncientMegalodon builds full articulated sculpted mesh hierarchy (%d)" % mesh_nodes.size())
	var raw_prims := 0
	var bad_normals := 0
	var extra_vram_textures := 0
	var srgb_fail := 0
	var part_tris: Dictionary = {}
	var core_tris := 0
	var total_tris := 0

	for n in mesh_nodes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
		var am := mi.mesh as ArrayMesh
		check(am != null, "Megalodon mesh '%s' uses sculpted ArrayMesh" % mi.name)
		var mat := mi.material_override as StandardMaterial3D
		check(mat != null, "Megalodon mesh '%s' has StandardMaterial3D" % mi.name)
		if mat != null:
			if not mat.vertex_color_use_as_albedo or not mat.vertex_color_is_srgb:
				srgb_fail += 1
			if mat.albedo_texture != null or mat.normal_texture != null or mat.roughness_texture != null:
				extra_vram_textures += 1
		if am != null:
			var mi_tris := 0
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				mi_tris += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
			part_tris[String(mi.name)] = mi_tris
			total_tris += mi_tris
			if mi.name in [&"BodyMesh", &"JawMesh", &"TailMidMesh", &"TailFinMesh"]:
				core_tris += mi_tris

	check_eq(raw_prims, 0, "AncientMegalodon contains ZERO PrimitiveMeshes")
	check_eq(bad_normals, 0, "all sculpted AncientMegalodon normals are finite unit vectors")
	check_eq(srgb_fail, 0, "all AncientMegalodon materials use vertex_color_is_srgb == true")
	check_eq(extra_vram_textures, 0, "AncientMegalodon allocates ZERO extra VRAM textures")
	check(core_tris >= 2200, "Body/Jaw/TailMid/TailFin sculpted tris >= 2200 (got %d, total %d)" % [core_tris, total_tris])
	print("    Wave 35B Megalodon tris: Body=%d, Jaw=%d, TailMid=%d, TailFin=%d, ScarGlow=%d, TailScar=%d, Eyes=%d (core=%d, total=%d)" % [
		int(part_tris.get("BodyMesh", 0)),
		int(part_tris.get("JawMesh", 0)),
		int(part_tris.get("TailMidMesh", 0)),
		int(part_tris.get("TailFinMesh", 0)),
		int(part_tris.get("ScarGlow", 0)),
		int(part_tris.get("TailScarGlow", 0)),
		int(part_tris.get("EyesMesh", 0)),
		core_tris,
		total_tris,
	])

	# Verify hitbox layer & megalodon metadata.
	var hitbox := mega.get_node_or_null(^"MegalodonHitbox") as StaticBody3D
	check(hitbox != null, "MegalodonHitbox StaticBody3D exists")
	if hitbox != null:
		check_eq(hitbox.collision_layer, Pawn.LAYER_PAWN, "MegalodonHitbox sits on Pawn.LAYER_PAWN")
		check(hitbox.get_meta(&"megalodon") == mega, "MegalodonHitbox carries megalodon metadata")

	# 2. Attack lifecycle: EMERGE -> CIRCLE -> WINDUP -> CHARGE emits charge_telegraphed;
	#    dealing >= 95 damage via direct Cannonball hits during WINDUP/CHARGE triggers STAGGERED!
	var telegraphed := [0]
	var interrupted := [0]
	var bitten := [0]
	var bitten_breaches := [0]
	var defeated_salvage: Array = []
	var defeated_count := [0]

	mega.charge_telegraphed.connect(func(_m: AncientMegalodon, _s: Node3D) -> void:
		telegraphed[0] += 1
	)
	mega.charge_interrupted.connect(func(_m: AncientMegalodon, _a: Node) -> void:
		interrupted[0] += 1
	)
	mega.hull_bitten.connect(func(_m: AncientMegalodon, _s: Node3D, b: int) -> void:
		bitten[0] += 1
		bitten_breaches[0] += b
	)
	mega.megalodon_defeated.connect(func(_m: AncientMegalodon, _p: Vector3, salvage: Array) -> void:
		defeated_count[0] += 1
		defeated_salvage.append_array(salvage)
	)

	# Step through EMERGE (1.6 s) into CIRCLE.
	for _i in 24:
		mega.step_ai(0.1)
	check_eq(mega.state, AncientMegalodon.State.CIRCLE, "AncientMegalodon transitions EMERGE -> CIRCLE")
	var idle_scar_e := mega.get_scar_emission_energy()

	# Step through CIRCLE (13.5 s) into WINDUP -> charge_telegraphed emitted!
	for _i in 150:
		mega.step_ai(0.1)
		if mega.state == AncientMegalodon.State.WINDUP:
			break
	check_eq(mega.state, AncientMegalodon.State.WINDUP, "AncientMegalodon transitions CIRCLE -> WINDUP")
	check_eq(telegraphed[0], 1, "charge_telegraphed emitted on WINDUP entry")
	mega.step_ai(1.2)
	check(mega.get_scar_emission_energy() > idle_scar_e * 1.4,
		"bioluminescent scar glow intensifies dramatically during WINDUP (%.2f vs %.2f)" % [
			mega.get_scar_emission_energy(), idle_scar_e])

	# Step into CHARGE and fire 2 direct Cannonballs (2 * 55 = 110 >= 95) into MegalodonHitbox!
	for _i in 30:
		mega.step_ai(0.1)
		if mega.state == AncientMegalodon.State.CHARGE:
			break
	check_eq(mega.state, AncientMegalodon.State.CHARGE, "AncientMegalodon transitions WINDUP -> CHARGE")

	var hero_pair := _fighter(Vector3(0.0, 2.5, 0.0), &"player", 0.0)
	var hero: Pawn = hero_pair[0]
	var hp_before_shots := mega.health
	var cannon_hits := 0
	for _shot in 2:
		var m_pos := mega.global_position + Vector3(0.0, 1.0, 0.0)
		var from_ship := Vector3(ship.global_position.x, 2.2, ship.global_position.z)
		var to_m := (m_pos - from_ship).normalized()
		var ball := Cannonball.new()
		ball.enable_effects = false
		ball.shooter_ship = ship
		ball.shooter_pawn = hero
		ball.velocity = to_m * 75.0
		_root.add_child(ball)
		ball.global_position = Vector3(m_pos.x - to_m.x * 13.5, 1.8, m_pos.z - to_m.z * 13.5)
		var hit_flag := [false]
		ball.impacted.connect(func(_hp: Vector3, tgt: Node) -> void:
			if tgt == mega:
				hit_flag[0] = true
		)
		await physics_frames(12)
		if hit_flag[0]:
			cannon_hits += 1
		if is_instance_valid(ball):
			ball.queue_free()
		await physics_frames(1)

	check_eq(cannon_hits, 2, "both direct Cannonballs strike AncientMegalodon via MegalodonHitbox")
	check_near(mega.health, hp_before_shots - 110.0, 0.1, "two Cannonballs deal 110 damage to AncientMegalodon")
	check_eq(mega.state, AncientMegalodon.State.STAGGERED,
		"dealing >= 95 Cannonball damage during CHARGE interrupts into State.STAGGERED")
	check_eq(interrupted[0], 1, "charge_interrupted signal emitted on stagger")
	check_eq(ship.open_hole_count(), 0, "interrupted Megalodon charge inflicts 0 hull breaches")

	# 3. Unstopped CHARGE reaches the Ship, emits hull_bitten, and punches >= 2 hull breaches!
	#    Advance through STAGGERED -> RETREAT -> CIRCLE -> WINDUP -> CHARGE without interrupting.
	mega.global_position = Vector3(26.0, -0.5, 0.0)
	mega.state = AncientMegalodon.State.CHARGE
	mega._state_timer = AncientMegalodon.CHARGE_TIMEOUT
	mega._charge_damage_taken = 0.0
	for _i in 35:
		mega.step_ai(0.08)
		if bitten[0] >= 1:
			break
	check_eq(bitten[0], 1, "unstopped Megalodon CHARGE emits hull_bitten")
	check(bitten_breaches[0] >= AncientMegalodon.BITE_HULL_BREACHES,
		"hull_bitten reports >= %d breaches (got %d)" % [AncientMegalodon.BITE_HULL_BREACHES, bitten_breaches[0]])
	check(ship.open_hole_count() >= 2,
		"unstopped Megalodon bite punches >= 2 hull breaches on Ship (got %d)" % ship.open_hole_count())
	check_eq(mega.state, AncientMegalodon.State.RETREAT, "Megalodon enters State.RETREAT after biting hull")

	# 4. Verify Brass Spyglass identifies a live Ancient Megalodon at 900 m as "Ancient Megalodon"
	#    and ignores it once defeated!
	var inv := Inventory.new()
	inv.input_enabled = false
	hero.add_child(inv)
	hero.global_position = Vector3(0.0, 4.0, 0.0)
	await physics_frames(2)
	inv.equip(&"spyglass", true)
	inv.set_secondary_held(true)

	# Park the first mega out of the northern sighting cone and spawn a distant mega at 900 m North.
	mega.global_position = Vector3(0.0, -0.5, 40.0)
	var far_mega := AncientMegalodon.spawn_near_ship(_root, null, Vector3(0.0, 0.0, -900.0))
	far_mega.global_position = Vector3(0.0, -0.5, -900.0)
	far_mega.state = AncientMegalodon.State.CIRCLE
	await physics_frames(2)

	var aim_at := func(world_pt: Vector3) -> void:
		var delta_v := world_pt - hero.eye_position()
		var horiz := maxf(Vector2(delta_v.x, delta_v.z).length(), 0.001)
		hero.look_yaw = atan2(-delta_v.x, -delta_v.z)
		hero.look_pitch = atan2(delta_v.y, horiz)
		inv.call(&"_scan_spyglass_sighting")

	aim_at.call(far_mega.global_position + Vector3.UP * 3.5)
	check_eq(inv.spyglass_sighting, "Ancient Megalodon",
		"Brass Spyglass identifies live Megalodon at 900 m as 'Ancient Megalodon' (got '%s')" % inv.spyglass_sighting)
	check(inv.spyglass_sighting_dist >= 885.0 and inv.spyglass_sighting_dist <= 915.0,
		"Brass Spyglass reports ~900 m distance (got %.1f m)" % inv.spyglass_sighting_dist)

	# 5. Slaying the Megalodon (health <= 0) emits megalodon_defeated and spawns 4 high-tier Carryables!
	check(mega.apply_damage(mega.health + 25.0, hero), "lethal damage slays AncientMegalodon")
	check(mega.dead and mega.state == AncientMegalodon.State.DEFEATED,
		"slain Megalodon sets dead == true and State.DEFEATED")
	check_eq(defeated_count[0], 1, "megalodon_defeated signal emitted once on death")
	check_eq(defeated_salvage.size(), 4,
		"defeating AncientMegalodon spawns 4 floating high-tier treasure Carryables (got %d)" % defeated_salvage.size())
	var carryable_count := 0
	for item_v in defeated_salvage:
		if item_v is Carryable and is_instance_valid(item_v) and (item_v as Node).is_in_group(TreasureCatalog.TREASURE_GROUP):
			carryable_count += 1
	check_eq(carryable_count, 4, "all 4 Megalodon salvage drops are valid treasure Carryables")

	# Defeat far_mega and verify Brass Spyglass now ignores it!
	far_mega.apply_damage(far_mega.health + 50.0, hero)
	check(far_mega.dead, "far_mega marked dead on defeat")
	aim_at.call(far_mega.global_position + Vector3.UP * 3.5)
	check_eq(inv.spyglass_sighting, "", "Brass Spyglass ignores defeated AncientMegalodon")
	inv.set_secondary_held(false)

	# 6. Verify showcase pose helper runs cleanly with zero errors.
	var showcase_mega := AncientMegalodon.spawn_near_ship(_root, null, Vector3(120.0, 0.0, 120.0))
	showcase_mega.force_pose_for_showcase(0.85, 1.0)
	check(showcase_mega.get_scar_emission_energy() >= 5.0,
		"force_pose_for_showcase illuminates bioluminescent scar vents")

	# 7. Verify WorldDirector.force_spawn_megalodon() emits spawn_megalodon + strict-ASCII warning!
	var director := WorldDirector.new(0x35B01)
	director.post_notices = false
	director.weather_integration = false
	director.player_ship = ship
	_root.add_child(director)

	var wd_spawns: Array[Dictionary] = []
	var wd_warnings: Array[String] = []
	director.spawn_megalodon.connect(func(ctr: Vector3, tgt: Node) -> void:
		wd_spawns.append({"center": ctr, "target": tgt})
	)
	director.sighting_warning.connect(func(msg: String, _p: Vector3, kind: StringName, _b: String, _d: float) -> void:
		if kind == &"megalodon":
			wd_warnings.append(msg)
	)

	var wd_evt := director.force_spawn_megalodon(Vector3.FORWARD, ship)
	check(not wd_evt.is_empty(), "WorldDirector.force_spawn_megalodon returns event dictionary")
	check_eq(wd_spawns.size(), 1, "WorldDirector emits spawn_megalodon signal")
	check(wd_spawns[0]["target"] == ship, "spawn_megalodon forwards target ship reference")
	check_eq(wd_warnings.size(), 1, "WorldDirector emits megalodon sighting_warning")
	if not wd_warnings.is_empty():
		var wmsg := wd_warnings[0]
		check(wmsg.contains("Ancient Megalodon"), "sighting warning names Ancient Megalodon")
		var non_ascii := 0
		for ci in wmsg.length():
			if wmsg.unicode_at(ci) > 127:
				non_ascii += 1
		check_eq(non_ascii, 0, "WorldDirector Megalodon sighting warning is strict ASCII")

	# 8. Clean teardown with AncientMegalodon.clear_shared_cache() and ZERO leaks!
	await _end()
	AncientMegalodon.clear_shared_cache()
	check_eq(AncientMegalodon._active_megas, 0, "AncientMegalodon._active_megas == 0 after teardown")
	check(AncientMegalodon._mesh_cache.is_empty(), "AncientMegalodon._mesh_cache cleared cleanly")
	check(AncientMegalodon._hide_mat == null and AncientMegalodon._scar_mat == null and AncientMegalodon._eye_mat == null,
		"AncientMegalodon static materials released cleanly to null (0 leaks)")
