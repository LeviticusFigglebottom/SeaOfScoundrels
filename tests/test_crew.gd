extends TestCase
## Headless tests for AI CrewBrain: survival priority (patch & bail), captain orders
## (helm, trim, anchor, cannons), lookout callouts, shanty joining, and co-op yield.

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
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
	Audio.stop_shanty(0.01)
	_root.queue_free()
	_root = null
	await physics_frames(2)
	_fast(false)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp


func _make_crew(s: Ship, captain: Pawn, persona: StringName, local_pos: Vector3) -> Array:
	var p := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(p)
	p.board(s, local_pos)
	var brain := CrewBrain.new()
	brain.setup(s, captain, persona)
	p.add_child(brain)
	return [p, brain]


func test_survival_priority_patches_breach_and_bails_hold() -> void:
	_begin()
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	await physics_frames(20)

	var pair := _make_crew(s, null, &"carpenter", Vector3(0.0, 1.12, 1.8))
	var brain: CrewBrain = pair[1]
	# Even when ordered to trim sails, a hull breach must preempt everything!
	s.set_sail_target(1.0)
	s.sail_set = 1.0
	s.sail_trim = 1.1
	brain.give_order(&"trim")
	await physics_frames(10)

	var slot := s.apply_hull_damage(s.global_transform * Vector3(2.0, -0.45, 0.4), 0.5)
	s.water_level = 0.25
	check_eq(s.open_hole_count(), 1, "breach created")

	var patched := false
	for _i in 650:
		await physics_frames(1)
		if s.open_hole_count() == 0:
			patched = true
			break
	print("    crew patched breach slot %d: %s, water_level=%.3f" % [slot, str(patched), s.water_level])
	check(patched, "AI crewmate must navigate to hold and patch open breach")

	# Now crewmate should bail the remaining bilge water down near zero.
	var water_before := s.water_level
	for _i in 500:
		await physics_frames(1)
		if s.water_level < 0.03:
			break
	print("    crew bailed water from %.3f -> %.3f" % [water_before, s.water_level])
	check(s.water_level < water_before - 0.12, "AI crewmate must bail hold water after patching")
	await _end()


func test_autonomous_trim_and_anchor_orders() -> void:
	_begin()
	Weather.set_weather(0.0, 11.0, 0.6)
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	await physics_frames(20)

	var pair := _make_crew(s, null, &"helmsman", Vector3(0.5, 1.12, 0.5))
	var brain: CrewBrain = pair[1]

	# Sail is raised but trimmed way off ideal; crewmate should autonomously trim it.
	s.set_sail_target(1.0)
	s.sail_set = 1.0
	s.set_trim_target(0.9)
	s.sail_trim = 0.9
	var err_before := absf(s.sail_trim - s.ideal_sail_trim())
	check(err_before > 0.6, "initial trim should be far from ideal")

	for _i in 450:
		await physics_frames(1)
		if absf(s.sail_trim - s.ideal_sail_trim()) < 0.14:
			break
	var err_after := absf(s.sail_trim - s.ideal_sail_trim())
	print("    autonomous trim error: %.2f -> %.2f rad" % [err_before, err_after])
	check(err_after < 0.22, "AI crewmate should trim sails close to ideal wind angle")

	# Captain orders drop anchor -> crewmate runs to capstan and drops it.
	brain.give_order(&"anchor_drop")
	for _i in 450:
		await physics_frames(1)
		if s.anchor_down and s.anchor_progress > 0.9:
			break
	check(s.anchor_down and s.anchor_progress > 0.9, "anchor_drop order must drop anchor")

	# Captain orders raise anchor -> crewmate winds it back up.
	brain.give_order(&"anchor_raise")
	for _i in 520:
		await physics_frames(1)
		if not s.anchor_down and s.anchor_progress < 0.1:
			break
	check(not s.anchor_down and s.anchor_progress < 0.1, "anchor_raise order must raise anchor")
	await _end()


func test_lookout_callouts_cannon_gunnery_and_shanty() -> void:
	_begin()
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	var enemy := SLOOP_SCENE.instantiate() as Ship
	enemy.enable_effects = false
	enemy.faction = &"drowned"
	_root.add_child(enemy)
	enemy.global_position = Vector3(36.0, 0.0, -1.5)

	var fake_island := Node3D.new()
	fake_island.name = "CutlassCay"
	fake_island.add_to_group(&"islands")
	fake_island.set_meta("display_name", "Cutlass Cay")
	_root.add_child(fake_island)
	fake_island.global_position = Vector3(0.0, 0.0, -260.0)
	await physics_frames(15)

	var pair := _make_crew(s, null, &"lookout", Vector3(1.1, 1.12, -1.5))
	var pawn: Pawn = pair[0]
	var brain: CrewBrain = pair[1]

	var spoken: Array[StringName] = []
	brain.callout_spoken.connect(func(_sp: String, _txt: String, cat: StringName) -> void:
		spoken.append(cat)
	)
	var fired := [false]
	s.cannon_fired.connect(func(_side: StringName, _b: Cannonball) -> void: fired[0] = true)

	for _i in 320:
		await physics_frames(1)
		if fired[0] and spoken.has(&"sail_sighted") and spoken.has(&"land_ho"):
			break
	print("    lookout callouts=%s cannon_fired=%s" % [str(spoken), str(fired[0])])
	check(spoken.has(&"land_ho"), "crewmate must call out nearby island")
	check(spoken.has(&"sail_sighted"), "crewmate must call out hostile ship")
	check(fired[0], "crewmate must man cannon and fire on hostile sloop in broadside")

	# Remove enemy & verify shanty join + co-op yield.
	enemy.queue_free()
	await physics_frames(5)
	brain.give_order(&"shanty")
	await physics_frames(20)
	check(Audio.is_shanty_playing(), "shanty order starts/joins shanty")

	brain.yield_to_human_player()
	check(pawn.station == null, "yielding to human releases station")
	await _end()


func test_shanty_instrument_meshes_and_tool_count() -> void:
	check_eq(ToolMeshes.get_tool_ids().size(), 11, "canonical ALL_TOOLS count must remain exactly 11")
	check_eq(ToolMeshes.get_display_name(&"hurdy_gurdy"), "Hurdy-Gurdy", "hurdy_gurdy display name")
	check_eq(ToolMeshes.get_display_name(&"whistle"), "Bosun's Whistle", "whistle display name")

	var hg := ToolMeshes.build_tool(&"hurdy_gurdy")
	check(hg != null, "hurdy_gurdy builds non-null node")
	var hg_verts := 0
	for m in hg.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		check(mi.mesh != null and not (mi.mesh is PrimitiveMesh), "hurdy_gurdy uses sculpted ArrayMesh, not PrimitiveMesh")
		if mi.mesh != null:
			hg_verts += mi.mesh.get_faces().size()
	check(hg_verts >= 36, "hurdy_gurdy must have rich sculpted geometry (got %d verts)" % hg_verts)
	var crank := hg.get_node_or_null(^"CrankHandle") as Node3D
	check(crank != null, "hurdy_gurdy exposes rotating CrankHandle child")
	ToolMeshes.set_hurdy_gurdy_crank(hg, 1.35)
	if crank != null:
		check_near(crank.rotation.x, 1.35, 0.001, "set_hurdy_gurdy_crank rotates CrankHandle around X")
	hg.free()

	var wh := ToolMeshes.build_tool(&"whistle")
	check(wh != null, "whistle builds non-null node")
	var wh_verts := 0
	for m in wh.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		check(mi.mesh != null and not (mi.mesh is PrimitiveMesh), "whistle uses sculpted ArrayMesh, not PrimitiveMesh")
		if mi.mesh != null:
			wh_verts += mi.mesh.get_faces().size()
	check(wh_verts >= 36, "whistle must have rich sculpted geometry (got %d verts)" % wh_verts)
	check(wh.get_node_or_null(^"OakBarrel") != null, "whistle has OakBarrel mesh")
	check(wh.get_node_or_null(^"BrassFittings") != null, "whistle has BrassFittings mesh")
	check(wh.get_node_or_null(^"FingerHoles") != null, "whistle has FingerHoles mesh")
	check(wh.get_node_or_null(^"BraidedLanyard") != null, "whistle has BraidedLanyard mesh")
	wh.free()


func test_crew_shanty_3d_instrument_attach_animate_and_detach() -> void:
	_begin()
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	await physics_frames(15)

	var barnaby_pair := _make_crew(s, null, &"helmsman", Vector3(-0.8, 2.02, 4.6))
	var maren_pair := _make_crew(s, null, &"lookout", Vector3(0.0, 1.12, -2.5))
	var pip_pair := _make_crew(s, null, &"carpenter", Vector3(0.9, 1.12, -0.4))

	var barnaby_pawn: Pawn = barnaby_pair[0]
	var barnaby: CrewBrain = barnaby_pair[1]
	var maren_pawn: Pawn = maren_pair[0]
	var maren: CrewBrain = maren_pair[1]
	var pip_pawn: Pawn = pip_pair[0]
	var pip: CrewBrain = pip_pair[1]

	await physics_frames(4)
	check(barnaby.get_held_shanty_instrument() == null, "no instrument held before shanty")

	barnaby.give_order(&"shanty")
	maren.give_order(&"shanty")
	pip.give_order(&"shanty")
	await physics_frames(12)

	var b_vis := barnaby_pawn.get_node(^"Visual/CharacterVisual") as CharacterVisual
	var m_vis := maren_pawn.get_node(^"Visual/CharacterVisual") as CharacterVisual
	var p_vis := pip_pawn.get_node(^"Visual/CharacterVisual") as CharacterVisual

	var b_inst := barnaby.get_held_shanty_instrument()
	var m_inst := maren.get_held_shanty_instrument()
	var p_inst := pip.get_held_shanty_instrument()

	check(b_inst != null and b_inst.get_parent() == b_vis.hand_right, "Barnaby attaches hurdy-gurdy to hand_right")
	check(m_inst != null and m_inst.get_parent() == m_vis.hand_right, "Maren attaches whistle to hand_right")
	check(p_inst != null and p_inst.get_parent() == p_vis.hand_right, "Pip attaches concertina to hand_right")
	check(b_inst != null and b_inst.get_node_or_null(^"CrankHandle") != null, "Barnaby holds hurdy-gurdy with CrankHandle")
	check(m_inst != null and m_inst.get_node_or_null(^"BraidedLanyard") != null, "Maren holds bosun's whistle")
	check(p_inst != null and p_inst.get_node_or_null(^"Bellows") != null, "Pip holds concertina with Bellows")

	var b_motes := barnaby_pawn.get_node_or_null(^"ShantyMotes") as GPUParticles3D
	check(b_motes != null and b_motes.amount == 8 and b_motes.emitting, "shanty spawns subtle 8-mote GPUParticles3D")

	# Verify live rhythmic animation advances crank angle while playing.
	var crank := b_inst.get_node_or_null(^"CrankHandle") as Node3D if b_inst != null else null
	var crank_before := crank.rotation.x if crank != null else 0.0
	await physics_frames(18)
	var crank_after := crank.rotation.x if crank != null else 0.0
	check(absf(crank_after - crank_before) > 0.05, "hurdy-gurdy crank rotates rhythmically during shanty")

	# Switching orders detaches & frees both 3D instrument and golden motes cleanly
	# (even while Pip keeps playing her concertina!).
	barnaby.give_order(&"helm")
	maren.give_order(&"follow")
	await physics_frames(6)
	check(barnaby.get_held_shanty_instrument() == null, "Barnaby clears held instrument on order switch")
	check(maren.get_held_shanty_instrument() == null, "Maren clears held instrument on order switch")
	check(not is_instance_valid(b_inst), "Barnaby's detached hurdy-gurdy is freed")
	check(not is_instance_valid(b_motes), "Barnaby's shanty motes are freed")
	check_eq(b_vis.hand_right.get_child_count(), 0, "Barnaby hand_right socket has zero dangling children")

	# Freeing Pip while actively playing exercises _exit_tree() teardown cleanly.
	var p_motes := pip_pawn.get_node_or_null(^"ShantyMotes") as GPUParticles3D
	check(p_motes != null, "Pip has active ShantyMotes prior to tree exit")
	pip_pawn.queue_free()
	await physics_frames(4)
	check(not is_instance_valid(p_inst), "Pip's concertina freed cleanly on _exit_tree()")
	check(not is_instance_valid(p_motes), "Pip's shanty motes freed cleanly on _exit_tree()")
	await _end()


func test_castaway_raft_sculpted_geometry_npc_and_rescue() -> void:
	_begin()
	var raft := CastawayRaft.new()
	_root.add_child(raft)
	raft.global_position = Vector3(14.0, 0.0, -10.0)
	await physics_frames(4)
	for _i in 4:
		await get_tree().process_frame

	# Verify zero primitive placeholders across the entire CastawayRaft hierarchy.
	var all_meshes := raft.find_children("*", "MeshInstance3D", true, false)
	check(all_meshes.size() >= 8, "CastawayRaft builds multi-part sculpted hierarchy (got %d meshes)" % all_meshes.size())
	var total_verts := 0
	for m in all_meshes:
		var mi := m as MeshInstance3D
		check(mi.mesh != null, "raft mesh '%s' non-null" % mi.name)
		if mi.mesh != null:
			check(not (mi.mesh is PrimitiveMesh), "raft mesh '%s' must not be a PrimitiveMesh placeholder" % mi.name)
			if mi.visible:
				total_verts += mi.mesh.get_faces().size()
	check(total_verts >= 600, "CastawayRaft has rich multi-log & rigging geometry (got %d verts)" % total_verts)
	check(raft.deck_logs_mesh != null and raft.deck_logs_mesh.mesh.get_faces().size() >= 300,
		"7 sculpted driftwood logs have rich vertex-colored faces")
	check(raft.cross_spars_mesh != null, "raft has transverse cross-spars")
	check(raft.lashings_mesh != null, "raft has hemp rope lashings")
	check(raft.mast_mesh != null, "raft has bamboo/driftwood signal mast & cross-yard")
	check(raft.pennant_mesh != null, "raft has tattered crimson-orange distress pennant")
	check(raft.supply_prop != null, "raft has corner supply barrel prop")

	# Verify real lit hanging oil lantern from ToolMeshes.
	check(raft.lantern_node != null, "raft hangs real ToolMeshes lantern")
	var lan_light := raft.lantern_node.get_node_or_null(^"LanternLight") as OmniLight3D if raft.lantern_node != null else null
	check(lan_light != null and lan_light.visible and lan_light.light_energy > 1.0, "hanging lantern is lit")

	# Verify castaway CharacterVisual & lazily bound AnimationDriver.
	check(raft.castaway_visual != null and raft.castaway_visual.archetype == &"carpenter",
		"castaway uses carpenter CharacterVisual archetype")
	check(raft.castaway_visual != null and raft.castaway_visual.skeleton != null,
		"castaway CharacterVisual has loaded 19-bone skeleton")
	check(raft.castaway_driver != null and raft.castaway_driver.visual == raft.castaway_visual,
		"castaway AnimationDriver binds lazily to CharacterVisual")

	# Verify Rescue Interactable & host-authoritative rescued signal.
	var rescue_it := raft.get_rescue_interactable()
	check(rescue_it != null, "raft exposes rescue Interactable")
	check_eq(rescue_it.prompt, "Rescue Castaway", "rescue interactable prompt")
	check_near(rescue_it.reach, 4.5, 0.01, "rescue interactable reach is 4.5 m")

	var rescuer := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(rescuer)
	rescuer.global_position = raft.global_position + Vector3(1.8, 0.2, 0.0)
	await physics_frames(2)

	var rescue_events: Array[Array] = []
	raft.rescued.connect(func(r: CastawayRaft, who: Node) -> void:
		rescue_events.append([r, who])
	)
	rescue_it.interact(rescuer)
	check_eq(rescue_events.size(), 1, "rescue interaction emits rescued(raft, rescuer) once")
	if rescue_events.size() == 1:
		check(rescue_events[0][0] == raft and rescue_events[0][1] == rescuer, "rescued signal passes (raft, rescuer)")
	check(raft.is_rescued and not rescue_it.enabled, "rescue marks raft rescued and disables further interaction")
	rescue_it.interact(rescuer)
	check_eq(rescue_events.size(), 1, "rescue is idempotent and cannot double-fire")

	# Teardown check.
	raft.queue_free()
	await physics_frames(4)
	check(not is_instance_valid(raft), "CastawayRaft tears down cleanly with zero dangling refs")
	await _end()


func test_crew_follow_escort_engages_hostile_enemy_and_resumes_follow() -> void:
	_begin()
	# Build dry island ground platform well above sea level (top surface y = 20.0).
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(44.0, 1.0, 44.0)
	cs.shape = bx
	ground.add_child(cs)
	_root.add_child(ground)
	ground.global_position = Vector3(0.0, 19.5, 0.0)

	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.teleport(Vector3(0.0, 20.05, 0.0))

	var crew_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(crew_pawn)
	crew_pawn.teleport(Vector3(-1.8, 20.05, 1.4))
	var crew_cc := CombatComponent.new()
	crew_cc.name = "CombatComponent"
	crew_cc.faction = &"player"
	crew_cc.equipped_weapon = &"cutlass"
	crew_cc.enable_effects = false
	crew_pawn.add_child(crew_cc)
	var brain := CrewBrain.new()
	brain.setup(null, captain, &"lookout")
	crew_pawn.add_child(brain)

	var enemy := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(enemy)
	enemy.teleport(Vector3(7.5, 20.05, 0.0))
	enemy.max_health = 45.0
	enemy.health = 45.0
	var enemy_cc := CombatComponent.new()
	enemy_cc.name = "CombatComponent"
	enemy_cc.faction = &"drowned"
	enemy_cc.equipped_weapon = &"cutlass"
	enemy_cc.enable_effects = false
	enemy.add_child(enemy_cc)

	var battle_cries := [0]
	brain.callout_spoken.connect(func(_sp: String, _txt: String, cat: StringName) -> void:
		if cat == &"battle_cry":
			battle_cries[0] += 1
	)
	var hits_landed := [0]
	var total_dmg := [0.0]
	crew_cc.hit_landed.connect(func(_tgt: Pawn, dmg: float, _heavy: bool) -> void:
		hits_landed[0] += 1
		total_dmg[0] += dmg
	)

	await physics_frames(8)
	brain.give_order(&"follow")

	var spotted := false
	var min_enemy_dist := INF
	for _i in 420:
		await physics_frames(1)
		if brain.get_melee_target() == enemy:
			spotted = true
		min_enemy_dist = minf(min_enemy_dist, crew_pawn.global_position.distance_to(enemy.global_position))
		if enemy.dead:
			break

	print("    escort combat: spotted=%s min_dist=%.2f m hits=%d dmg=%.1f enemy_dead=%s cries=%d" % [
		str(spotted), min_enemy_dist, hits_landed[0], total_dmg[0], str(enemy.dead), battle_cries[0]
	])
	check(spotted, "crewmate on &'follow' spots nearby hostile drowned combatant")
	check(min_enemy_dist < 2.35, "crewmate closes into cutlass engagement range (min_dist=%.2f)" % min_enemy_dist)
	check(hits_landed[0] >= 1 and total_dmg[0] >= 15.0, "crewmate deals real melee damage via CombatComponent")
	check(enemy.dead, "crewmate defeats hostile drowned combatant cleanly")
	check_eq(battle_cries[0], 1, "persona battle-cry fires once with cooldown preventing spam")

	# Move captain across the beach and verify crewmate seamlessly resumes escorting.
	captain.teleport(Vector3(-8.5, 20.05, -2.0))
	for _i in 320:
		await physics_frames(1)
		if crew_pawn.global_position.distance_to(captain.global_position) < 3.0:
			break
	var dist_to_cap := crew_pawn.global_position.distance_to(captain.global_position)
	print("    after combat: dist_to_captain=%.2f m melee_target=%s order=%s" % [
		dist_to_cap, str(brain.get_melee_target()), String(brain.current_order)
	])
	check(brain.get_melee_target() == null, "melee target clears once threats are defeated")
	check_eq(brain.current_order, &"follow", "crewmate keeps &'follow' order intact")
	check(dist_to_cap < 3.2, "crewmate seamlessly resumes following captain (dist=%.2f m)" % dist_to_cap)
	await _end()


