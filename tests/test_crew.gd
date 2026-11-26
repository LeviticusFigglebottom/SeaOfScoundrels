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


static func _ship_scale(s: Ship) -> float:
	if s != null and is_instance_valid(s):
		var hs: Variant = s.get(&"hull_scale")
		if hs != null and float(hs) > 0.01:
			return float(hs)
	return 1.0


func _make_crew(s: Ship, captain: Pawn, persona: StringName, local_pos: Vector3) -> Array:
	var p := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(p)
	p.board(s, local_pos * _ship_scale(s))
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

	var slot := s.apply_hull_damage(s.global_transform * (Vector3(2.0, -0.45, 0.4) * _ship_scale(s)), 0.5)
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


func test_crew_shanty_complementary_instrument_selection_and_handoff() -> void:
	_begin()
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	await physics_frames(12)

	# Captain with Inventory starting a shanty solo on Concertina.
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(s, Vector3(0.0, 2.02, 4.15) * _ship_scale(s))
	var cap_inv := Inventory.new()
	cap_inv.name = "Inventory"
	cap_inv.input_enabled = false
	captain.add_child(cap_inv)
	cap_inv.equip(&"instrument", true)
	cap_inv.set_shanty_instrument(&"concertina")
	cap_inv.set_playing_shanty(true)

	# Spawn 2-mate band (Barnaby=hurdy_gurdy, Maren=whistle) plus Pip (whose signature is concertina!).
	var barnaby_pair := _make_crew(s, captain, &"helmsman", Vector3(-0.9, 2.02, 4.7))
	var maren_pair := _make_crew(s, captain, &"lookout", Vector3(0.0, 1.12, -2.5))
	var barnaby: CrewBrain = barnaby_pair[1]
	var maren: CrewBrain = maren_pair[1]

	await physics_frames(10)
	check_eq(barnaby.get_active_shanty_instrument(), &"hurdy_gurdy",
		"Barnaby keeps signature hurdy_gurdy while Captain plays concertina")
	check_eq(maren.get_active_shanty_instrument(), &"whistle",
		"Maren keeps signature whistle while Captain plays concertina")
	check(barnaby.get_held_shanty_instrument().get_node_or_null(^"CrankHandle") != null,
		"Barnaby holds 3D Hurdy-Gurdy mesh")
	check(maren.get_held_shanty_instrument().get_node_or_null(^"BraidedLanyard") != null,
		"Maren holds 3D Bosun's Whistle mesh")

	# Captain switches mid-song to Hurdy-Gurdy -> Barnaby smoothly hands off to Concertina!
	cap_inv.set_shanty_instrument(&"hurdy_gurdy")
	await physics_frames(6)
	check_eq(barnaby.get_active_shanty_instrument(), &"concertina",
		"Barnaby hands off from hurdy_gurdy to unused concertina when Captain takes hurdy_gurdy")
	check_eq(maren.get_active_shanty_instrument(), &"whistle",
		"Maren stays on whistle during Barnaby's handoff")
	check(barnaby.get_held_shanty_instrument() != null \
		and barnaby.get_held_shanty_instrument().get_node_or_null(^"Bellows") != null,
		"Barnaby swaps 3D hand-held mesh cleanly to Concertina")
	check_near(float(Audio._stems[&"hurdy_gurdy"]["goal"]), 1.0, 0.01,
		"Captain's newly claimed hurdy_gurdy stem stays unmuted after Barnaby's handoff")
	check_near(float(Audio._stems[&"concertina"]["goal"]), 1.0, 0.01,
		"Barnaby's handed-off concertina stem is active")
	check_near(float(Audio._stems[&"whistle"]["goal"]), 1.0, 0.01,
		"Maren's whistle stem stays active for full 3-part harmony")

	# Captain switches again to Whistle -> Maren smoothly hands off to Hurdy-Gurdy!
	cap_inv.set_shanty_instrument(&"whistle")
	await physics_frames(6)
	check_eq(maren.get_active_shanty_instrument(), &"hurdy_gurdy",
		"Maren hands off from whistle to free hurdy_gurdy when Captain takes whistle")
	check(maren.get_held_shanty_instrument() != null \
		and maren.get_held_shanty_instrument().get_node_or_null(^"CrankHandle") != null,
		"Maren swaps 3D hand-held mesh cleanly to Hurdy-Gurdy")

	# Verify a newcomer whose persona prefers the Captain's active stem avoids doubling up on join.
	cap_inv.set_shanty_instrument(&"concertina")
	var pip_pair := _make_crew(s, captain, &"carpenter", Vector3(0.9, 1.12, -0.4))
	var pip: CrewBrain = pip_pair[1]
	await physics_frames(6)
	check(pip.get_active_shanty_instrument() != &"concertina" and pip.get_active_shanty_instrument() != &"",
		"Pip avoids doubling Captain's concertina on join (picked %s)" % pip.get_active_shanty_instrument())

	# Verify verse-wrap encore toast fires ONCE across the band and obeys 20 s cooldown.
	var encores: Array[String] = []
	for br: CrewBrain in [barnaby, maren, pip]:
		br.callout_spoken.connect(func(_sp: String, txt: String, cat: StringName) -> void:
			if cat == &"shanty_encore":
				encores.append(txt)
		)
	barnaby._trigger_shanty_encore_toast()
	maren._trigger_shanty_encore_toast()
	pip._trigger_shanty_encore_toast()
	check_eq(encores.size(), 1, "only 1 crewmate cheers an encore toast per shanty loop (shared 20 s cooldown)")

	# Clean teardown while jamming frees every instrument & mote with zero leaks.
	cap_inv.set_playing_shanty(false)
	await physics_frames(4)
	await _end()


func test_idle_crew_watch_posts_clearance_and_personal_space() -> void:
	_begin()
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	s.start_anchored = true
	_root.add_child(s)
	await physics_frames(15)

	var hs := _ship_scale(s)
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(s, Vector3(0.0, 2.02, 4.15) * hs)

	# Spawn all 3 crewmates (start Barnaby on quarterdeck to verify he relocates off the helm area!).
	var barnaby_pair := _make_crew(s, captain, &"helmsman", Vector3(-0.95, 2.02, 4.65))
	var maren_pair := _make_crew(s, captain, &"lookout", Vector3(0.0, 1.12, -3.75))
	var pip_pair := _make_crew(s, captain, &"carpenter", Vector3(1.55, 1.12, -0.95))
	var barnaby_p: Pawn = barnaby_pair[0]
	var maren_p: Pawn = maren_pair[0]
	var pip_p: Pawn = pip_pair[0]

	await physics_frames(280)

	# Every idle crewmate keeps >= 1.8 m horizontal clearance from the Captain at the helm!
	var cap_pos := captain.global_position
	for entry: Array in [["Barnaby", barnaby_p], ["Maren", maren_p], ["Pip", pip_p]]:
		var nm: String = entry[0]
		var cp: Pawn = entry[1]
		var d_flat := Vector2(cp.global_position.x - cap_pos.x, cp.global_position.z - cap_pos.z).length()
		var loc := cp.platform_local_position()
		check(cp.platform == s, "%s stays aboard ship at idle watch post" % nm)
		check(d_flat >= 1.8, "%s keeps >= 1.8 m clearance from Captain at helm (dist=%.2f m)" % [nm, d_flat])
		check(absf(loc.x) <= 1.90 * hs, "%s stays safely inside hull beam (x=%.2f)" % [nm, loc.x])

	# Barnaby moved off the quarterdeck onto the main deck port midships rail.
	var b_loc := barnaby_p.platform_local_position()
	check(CrewBrain._deck_band(b_loc.y / hs) == 1 and b_loc.x < -0.5 * hs,
		"Barnaby leaves quarterdeck to stand port midships on main deck (local=%s)" % str(b_loc))

	# Step Captain right beside Pip on the main deck and verify personal-space sidestep without going overboard!
	var pip_before := pip_p.platform_local_position()
	captain.board(s, Vector3(pip_before.x - 0.55, pip_before.y, pip_before.z))
	await physics_frames(120)
	var pip_after := pip_p.platform_local_position()
	var cap_after := captain.platform_local_position()
	var sep_after := Vector2(pip_after.x - cap_after.x, pip_after.z - cap_after.z).length()
	check(pip_p.platform == s, "Pip does not step overboard when yielding personal space")
	check(sep_after >= 1.35, "Pip sidesteps cleanly when Captain crowds personal space (sep=%.2f m)" % sep_after)
	await _end()


func test_crew_sea_of_thieves_sail_hoist_and_anchor_polarity() -> void:
	_begin()
	Weather.set_weather(0.0, 10.0, 0.0)
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	await physics_frames(15)

	var hs := _ship_scale(s)
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(s, Vector3(0.0, 2.02, 4.15) * hs)

	var pair := _make_crew(s, captain, &"helmsman", Vector3(-1.55, 1.12, 1.35))
	var helper_pair := _make_crew(s, captain, &"lookout", Vector3(0.0, 1.12, -3.75))
	var crew_p: Pawn = pair[0]
	var brain: CrewBrain = pair[1]
	var helper_p: Pawn = helper_pair[0]
	var helper_brain: CrewBrain = helper_pair[1]

	# 1. Verify set_sails lowers from 0.0 -> ~1.0 and raises back from 1.0 -> ~0.0 with Sea-of-Thieves polarity!
	s.set_sail_target(0.0)
	s.sail_set = 0.0
	brain.give_order(&"set_sails", 1.0)
	for _i in 450:
		await physics_frames(1)
		if s.sail_set > 0.85:
			break
	check(s.sail_set > 0.85, "AI crew lowers sails via Station_SailLength (got %.2f)" % s.sail_set)

	brain.give_order(&"set_sails", 0.0)
	for _i in 450:
		await physics_frames(1)
		if s.sail_set < 0.15:
			break
	check(s.sail_set < 0.15, "AI crew raises/furls sails via Station_SailLength (got %.2f)" % s.sail_set)

	# 2. Verify anchor_drop drops anchor and multi-hand capstan assist walks within 2.0 m when Captain occupies capstan!
	brain.give_order(&"anchor_drop")
	for _i in 450:
		await physics_frames(1)
		if s.anchor_down and s.anchor_progress > 0.9:
			break
	check(s.anchor_down and s.anchor_progress > 0.9, "AI crew drops anchor cleanly")

	var anchor_st := s.get_station(&"anchor")
	check(anchor_st != null and captain.enter_station(anchor_st), "Captain occupies Station_Anchor")
	helper_brain.give_order(&"anchor_raise")
	for _i in 320:
		await physics_frames(1)
		if helper_p.global_position.distance_to(anchor_st.global_position) <= 2.0:
			break
	var helper_dist := helper_p.global_position.distance_to(anchor_st.global_position)
	check(helper_dist <= 2.05, "AI crewmate walks within 2.0 m of capstan to assist Captain heave (dist=%.2f m)" % helper_dist)
	captain.leave_station()

	# 3. Verify AI crew occupies freed capstan and raises anchor cleanly!
	brain.give_order(&"anchor_raise")
	for _i in 520:
		await physics_frames(1)
		if not s.anchor_down and s.anchor_progress < 0.1:
			break
	check(not s.anchor_down and s.anchor_progress < 0.1, "AI crew heaves anchor up cleanly with Sea-of-Thieves polarity")
	check(crew_p.platform == s, "crewmate stays cleanly aboard after capstan work")
	await _end()


static func _is_strict_ascii(txt: String) -> bool:
	for i in txt.length():
		if txt.unicode_at(i) >= 128:
			return false
	return true


func test_wave28_sea_soundscape_and_crew_harpoon_stealth_callouts() -> void:
	_begin()
	Weather.set_weather(0.0, 12.0, 0.0)
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	s.start_anchored = true
	_root.add_child(s)
	await physics_frames(8)

	# 1. Verify all 4 SeaSoundscape SFX keys exist in AudioManager's manifest catalogue.
	for key: StringName in [SeaSoundscape.SFX_HULL_CREAK, SeaSoundscape.SFX_ROPE_CREAK,
			SeaSoundscape.SFX_SAIL_FLAP, SeaSoundscape.SFX_SAIL_FILL]:
		check(Audio.has_sound(key), "Audio manifest registers verified key '%s'" % String(key))

	# Freeze hull for deterministic telemetry stepping of SeaSoundscape.
	s.freeze = true
	s.rotation = Vector3.ZERO
	s.linear_velocity = Vector3.ZERO
	s.angular_velocity = Vector3.ZERO
	s.sail_set = 0.0
	s.sail_trim = 0.0

	var soundscape := SeaSoundscape.new()
	soundscape.set_physics_process(false)
	_root.add_child(soundscape)
	soundscape.bind_ship(s)

	# Calm flat stationary ship triggers nothing.
	soundscape.step(0.1)
	var idle_counts := soundscape.get_event_counts()
	check_eq(int(idle_counts[&"hull_creak"]), 0, "calm level ship triggers zero hull_creak")
	check_eq(int(idle_counts[&"rope_creak"]), 0, "calm stationary ship triggers zero rope_creak")
	check_eq(int(idle_counts[&"sail_flap"]), 0, "furled ship triggers zero sail_flap")
	check_eq(int(idle_counts[&"sail_fill"]), 0, "furled ship triggers zero sail_fill")
	check_eq(soundscape.last_sfx_triggered, &"", "last_sfx_triggered stays empty while idle")

	# 2. Sharp heel triggers &"hull_creak" and respects 4.5..8.0 s cooldown gating.
	s.rotation = Vector3(0.0, 0.0, 0.22)
	soundscape.step(0.05)
	check_eq(int(soundscape.get_event_counts()[&"hull_creak"]), 1,
		"sharp heel (0.22 rad >= 0.10) triggers hull_creak")
	check_eq(soundscape.last_sfx_triggered, &"hull_creak", "last_sfx_triggered records hull_creak")
	for _spam in 5:
		soundscape.step(0.5)  # 2.5 s total < 4.5 s min cooldown
	check_eq(int(soundscape.get_event_counts()[&"hull_creak"]), 1,
		"hull_creak cooldown prevents spam during sustained heel")
	soundscape.step(6.0)  # now >= 8.5 s elapsed > 8.0 s max cooldown
	check_eq(int(soundscape.get_event_counts()[&"hull_creak"]), 2,
		"hull_creak triggers again cleanly once cooldown expires")

	# Roll-velocity trigger even at near-zero heel angle.
	s.rotation = Vector3.ZERO
	s.angular_velocity = Vector3(0.0, 0.0, 0.30)
	soundscape.bind_ship(s)
	soundscape.step(0.05)
	check_eq(int(soundscape.get_event_counts()[&"hull_creak"]), 1,
		"brisk roll velocity (0.30 rad/s >= 0.18) triggers hull_creak")

	# 3. High forward speed under full sail triggers &"rope_creak" with 6.0..10.5 s cooldown.
	s.rotation = Vector3.ZERO
	s.angular_velocity = Vector3.ZERO
	Weather.set_weather(0.0, 12.0, 0.0)
	s.sail_set = 0.85
	s.sail_trim = s.ideal_sail_trim()
	s.linear_velocity = -s.global_basis.z * 6.0
	soundscape.bind_ship(s)
	soundscape.step(0.05)
	check_eq(int(soundscape.get_event_counts()[&"rope_creak"]), 1,
		"high speed (6.0 m/s >= 4.2) under full sail triggers rope_creak")
	check_eq(soundscape.last_sfx_triggered, &"rope_creak", "last_sfx_triggered records rope_creak")
	for _spam in 3:
		soundscape.step(1.0)  # 3.0 s < 6.0 s min cooldown
	check_eq(int(soundscape.get_event_counts()[&"rope_creak"]), 1,
		"rope_creak cooldown prevents spam")
	soundscape.step(8.0)  # 11.0 s > 10.5 s max cooldown
	check_eq(int(soundscape.get_event_counts()[&"rope_creak"]), 2,
		"rope_creak re-triggers after cooldown")

	# 4. Poorly trimmed sail catching headwind triggers &"sail_flap" (cooldown 3.8..6.2 s).
	s.linear_velocity = Vector3.ZERO
	s.sail_set = 0.72
	s.sail_trim = 0.0
	Weather.set_weather(0.0, 12.0, PI)  # Headwind against bow (-Z) -> wind_catch ~= 0.0 < 0.28
	soundscape.bind_ship(s)
	check(s.wind_catch() < 0.28, "headwind setup produces low wind_catch (got %.2f)" % s.wind_catch())
	soundscape.step(0.05)
	check_eq(int(soundscape.get_event_counts()[&"sail_flap"]), 1,
		"luffing headwind sail triggers sail_flap")
	check_eq(soundscape.last_sfx_triggered, &"sail_flap", "last_sfx_triggered records sail_flap")
	for _spam in 3:
		soundscape.step(0.8)  # 2.4 s < 3.8 s min cooldown
	check_eq(int(soundscape.get_event_counts()[&"sail_flap"]), 1,
		"sail_flap cooldown prevents spam")
	soundscape.step(4.2)  # 6.6 s > 6.2 s max cooldown
	check_eq(int(soundscape.get_event_counts()[&"sail_flap"]), 2,
		"sail_flap re-triggers cleanly after cooldown")

	# 5. Transitioning from low wind catch (< 0.60) into full billow (>= 0.84) triggers &"sail_fill" (4.0 s cd).
	Weather.set_weather(0.0, 12.0, 0.0)  # Fair tailwind astern
	s.sail_trim = s.ideal_sail_trim()
	check(s.wind_catch() >= 0.84, "fair tailwind setup produces full wind_catch (got %.2f)" % s.wind_catch())
	soundscape.step(0.05)
	check_eq(int(soundscape.get_event_counts()[&"sail_fill"]), 1,
		"transition from luffing into full billow triggers sail_fill")
	check_eq(soundscape.last_sfx_triggered, &"sail_fill", "last_sfx_triggered records sail_fill")
	# Quick drop and recovery within 4.0 s cooldown must be gated.
	Weather.set_weather(0.0, 12.0, PI)
	soundscape.step(0.5)
	Weather.set_weather(0.0, 12.0, 0.0)
	s.sail_trim = s.ideal_sail_trim()
	soundscape.step(0.5)
	check_eq(int(soundscape.get_event_counts()[&"sail_fill"]), 1,
		"sail_fill 4.0 s cooldown prevents rapid re-triggering")
	# After cooldown elapses, a fresh low->high transition snaps cleanly again.
	Weather.set_weather(0.0, 12.0, PI)
	soundscape.step(3.6)
	Weather.set_weather(0.0, 12.0, 0.0)
	s.sail_trim = s.ideal_sail_trim()
	soundscape.step(0.05)
	check_eq(int(soundscape.get_event_counts()[&"sail_fill"]), 2,
		"sail_fill re-triggers once 4.0 s cooldown has expired")

	# Disabled flag silences triggers and queue_free tears down cleanly with 0 leaks.
	soundscape.enabled = false
	soundscape.reset_state()
	s.rotation = Vector3(0.0, 0.0, 0.25)
	soundscape.step(0.1)
	check_eq(int(soundscape.get_event_counts()[&"hull_creak"]), 0, "disabled SeaSoundscape triggers nothing")
	soundscape.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(soundscape), "SeaSoundscape frees cleanly with zero leaks")

	# 6. Verify all Wave 28B CrewDialogue pools are strictly ASCII (< 128) across Barnaby, Maren, and Pip.
	for pid: StringName in [&"helmsman", &"lookout", &"carpenter"]:
		var bank: Dictionary = CrewDialogue.LINES[pid]
		for cat: StringName in [&"harpoon_haul", &"chainshot_hit", &"running_dark", &"lanterns_lit"]:
			var pool: Array = bank.get(cat, [])
			check(not pool.is_empty(), "CrewDialogue[%s][%s] has persona lines" % [String(pid), String(cat)])
			for line: String in pool:
				check(_is_strict_ascii(line), "strict ASCII line in %s/%s: %s" % [String(pid), String(cat), line])

	# 7. Verify CrewBrain harpoon, chainshot, and running-dark persona callouts & cooldowns.
	s.rotation = Vector3.ZERO
	s.freeze = false
	var barnaby_pair := _make_crew(s, null, &"helmsman", Vector3(-1.3, 1.12, 1.0))
	var maren_pair := _make_crew(s, null, &"lookout", Vector3(0.0, 1.12, -2.5))
	var pip_pair := _make_crew(s, null, &"carpenter", Vector3(1.3, 1.12, -0.5))
	var brains: Array[CrewBrain] = [barnaby_pair[1], maren_pair[1], pip_pair[1]]
	await physics_frames(4)

	for br: CrewBrain in brains:
		var spoken: Array[Dictionary] = []
		br.callout_spoken.connect(func(sp: String, txt: String, cat: StringName) -> void:
			spoken.append({"speaker": sp, "text": txt, "cat": cat})
		)
		check(br.celebrate_harpoon_haul("Corsair Chest"), "%s celebrates harpoon haul" % br.crew_name())
		check(not br.celebrate_harpoon_haul("Corsair Chest"), "%s harpoon callout gated by 6.0 s cooldown" % br.crew_name())
		check(br.callout_chainshot_hit(), "%s calls out chainshot hit" % br.crew_name())
		check(not br.callout_chainshot_hit(), "%s chainshot callout gated by 8.0 s cooldown" % br.crew_name())
		check(br.comment_running_dark(false), "%s comments when dousing lanterns" % br.crew_name())
		check(not br.comment_running_dark(false), "%s running-dark callout gated by 6.0 s cooldown" % br.crew_name())
		check(br.comment_running_dark(true), "%s comments when relighting lanterns" % br.crew_name())
		check(not br.comment_running_dark(true), "%s lanterns-lit callout gated by 6.0 s cooldown" % br.crew_name())

		check_eq(spoken.size(), 4, "%s emitted all 4 Wave 28B callout categories" % br.crew_name())
		if spoken.size() == 4:
			check_eq(spoken[0]["cat"], &"harpoon_haul", "%s category 0 is harpoon_haul" % br.crew_name())
			check((spoken[0]["text"] as String).contains("Corsair Chest"),
				"%s harpoon callout includes item label" % br.crew_name())
			check_eq(spoken[1]["cat"], &"chainshot_hit", "%s category 1 is chainshot_hit" % br.crew_name())
			check_eq(spoken[2]["cat"], &"running_dark", "%s category 2 is running_dark" % br.crew_name())
			check_eq(spoken[3]["cat"], &"lanterns_lit", "%s category 3 is lanterns_lit" % br.crew_name())
			for entry in spoken:
				check(_is_strict_ascii(String(entry["text"])),
					"emitted callout is strict ASCII: %s" % String(entry["text"]))

		# Exercise bind_ship() rebind + teardown safety.
		br.bind_ship(s)

	# Verify organic ship-signal handlers fire once across crew (live signal if 28A merged, direct handler fallback pre-merge).
	for br: CrewBrain in brains:
		br._callout_cooldowns.clear()
	var sig_count := [0]
	var dark_count := [0]
	for br: CrewBrain in brains:
		br.callout_spoken.connect(func(_sp: String, _txt: String, cat: StringName) -> void:
			if cat == &"harpoon_haul":
				sig_count[0] += 1
			elif cat == &"running_dark":
				dark_count[0] += 1
		)
	if s.has_signal(&"harpoon_loot_snagged"):
		s.emit_signal(&"harpoon_loot_snagged", "Wayfarer Chest", &"port")
	else:
		for br: CrewBrain in brains:
			br._on_ship_harpoon_loot_snagged("Wayfarer Chest", &"port")
	check_eq(sig_count[0], 1, "harpoon_loot_snagged triggers exactly one crew celebration across the crew")

	if s.has_signal(&"lanterns_toggled"):
		s.emit_signal(&"lanterns_toggled", false)
	else:
		for br: CrewBrain in brains:
			br._on_ship_lanterns_toggled(false)
	check_eq(dark_count[0], 1, "lanterns_toggled(false) triggers exactly one running-dark callout across the crew")

	await _end()


func test_q1b_crew_zero_jitter_hysteresis_and_deck_obstacle_routing() -> void:
	_begin()
	# Enable live waves and sailing wind so the ship rolls, pitches, and moves under way!
	Weather.set_weather(0.25, 12.0, 0.35)
	Sea.amp_scale = 0.65
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	s.start_anchored = false
	_root.add_child(s)
	s.set_sail_target(0.65)
	s.sail_set = 0.65
	await physics_frames(20)

	var hs := _ship_scale(s)
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(s, Vector3(0.0, 2.02, 4.15) * hs)

	# Spawn idle crewmate at starboard main-deck clearing, let settle, then crowd closely with Captain!
	var pip_pair := _make_crew(s, captain, &"carpenter", Vector3(1.35, 1.12, -0.80))
	var pip_p: Pawn = pip_pair[0]
	var pip_brain: CrewBrain = pip_pair[1]
	# Ensure ship has no active tasks distracting Pip from idle behavior.
	pip_brain.hold_fire = true
	await physics_frames(20)

	# Walk Captain right up next to Pip (0.55 m away) on the rolling moving ship and observe 180 ticks (3.0 s).
	var pip_start := pip_p.platform_local_position()
	captain.board(s, Vector3(pip_start.x - 0.55, pip_start.y, pip_start.z))

	var vel_reversals := 0
	var yaw_flips := 0
	var last_move_dir := Vector2.ZERO
	var have_prev_yaw := false
	var prev_local_yaw := 0.0
	var settled_max_speed := 0.0

	for tick in 180:
		await physics_frames(1)
		var inv_b := s.global_basis.inverse()
		var rel_l := inv_b * pip_p.get_relative_velocity()
		var v2 := Vector2(rel_l.x, rel_l.z)
		var spd := v2.length()
		if spd > 0.35:
			var cur_dir := v2 / spd
			if last_move_dir.length_squared() > 0.5 and last_move_dir.dot(cur_dir) < -0.25:
				vel_reversals += 1
			last_move_dir = cur_dir
		if tick >= 150:
			settled_max_speed = maxf(settled_max_speed, spd)

		var fwd_l := inv_b * pip_p.facing()
		var cur_local_yaw := atan2(-fwd_l.x, -fwd_l.z)
		if have_prev_yaw:
			var dy := absf(angle_difference(prev_local_yaw, cur_local_yaw))
			if dy > PI * 0.5:
				yaw_flips += 1
		prev_local_yaw = cur_local_yaw
		have_prev_yaw = true

	var pip_end := pip_p.platform_local_position()
	var cap_end := captain.platform_local_position()
	var final_sep := Vector2(pip_end.x - cap_end.x, pip_end.z - cap_end.z).length()
	print("    Q1B hysteresis on rolling ship (180 ticks): final_sep=%.2f m, vel_reversals=%d, yaw_flips=%d, settled_spd=%.3f m/s" % [
		final_sep, vel_reversals, yaw_flips, settled_max_speed
	])
	check(pip_p.platform == s, "crewmate stays cleanly aboard rolling moving ship while sidestepping")
	check(final_sep >= 1.90,
		"crewmate smoothly sidesteps to >= 1.9 m clearance from Captain (got %.2f m)" % final_sep)
	check(vel_reversals <= 1,
		"personal-space hysteresis must have <= 1 velocity reversal over 3 s (got %d)" % vel_reversals)
	check_eq(yaw_flips, 0,
		"smooth look_yaw must have zero >90 deg single-tick yaw flips (got %d)" % yaw_flips)
	check(settled_max_speed < 0.20,
		"crewmate settles calmly after yielding personal space (final 0.5 s max speed=%.3f m/s)" % settled_max_speed)

	# 2. Order a crewmate across the Sloop main deck straight through the mainmast line:
	#    (0, 1.1, -2.6) -> (0, 1.1, 1.2) and also straight through mast+hatch -> (0, 1.1, 2.45).
	Sea.amp_scale = 0.0
	s.set_sail_target(0.0)
	s.sail_set = 0.0
	captain.board(s, Vector3(0.0, 2.02, 4.4) * hs)

	var nav_pair := _make_crew(s, captain, &"lookout", Vector3(0.0, 1.12, -2.6))
	var nav_p: Pawn = nav_pair[0]
	var nav_brain: CrewBrain = nav_pair[1]
	nav_brain.set_physics_process(false)
	nav_brain._reset_nav_state()
	await physics_frames(4)

	var mast_center := Vector2(0.0, -1.0 * hs)
	var goal_mid := Vector3(0.0, 1.1, 1.2) * hs
	var arrived_mid := false
	var min_mast_dist := INF
	var stayed_main_deck := true
	for _i in 320:
		nav_brain._last_delta = 1.0 / 60.0
		if nav_brain._navigate_ship_local(goal_mid, 0.90 * hs):
			arrived_mid = true
			break
		await physics_frames(1)
		var loc := nav_p.platform_local_position()
		min_mast_dist = minf(min_mast_dist, Vector2(loc.x, loc.z).distance_to(mast_center))
		if CrewBrain._deck_band(loc.y / hs) != 1:
			stayed_main_deck = false

	# Also continue straight to aft centerline (0, 1.1, 2.45) and back to fore (0, 1.1, -2.6) across mast+hatch!
	var goal_aft := Vector3(0.0, 1.1, 2.45) * hs
	var arrived_aft := false
	for _i in 240:
		nav_brain._last_delta = 1.0 / 60.0
		if nav_brain._navigate_ship_local(goal_aft, 0.65 * hs):
			arrived_aft = true
			break
		await physics_frames(1)
		var loc := nav_p.platform_local_position()
		min_mast_dist = minf(min_mast_dist, Vector2(loc.x, loc.z).distance_to(mast_center))
		if CrewBrain._deck_band(loc.y / hs) != 1:
			stayed_main_deck = false

	print("    Q1B Sloop mast-line route: arrived_mid=%s arrived_aft=%s min_mast_r=%.2f m stayed_main_deck=%s" % [
		str(arrived_mid), str(arrived_aft), min_mast_dist, str(stayed_main_deck)
	])
	check(nav_p.platform == s, "crewmate stays aboard Sloop during main-deck mast routing")
	check(arrived_mid, "crewmate routes cleanly across mainmast line (0,1.1,-2.6)->(0,1.1,1.2)")
	check(arrived_aft, "crewmate routes cleanly aft past open hatch to (0,1.1,2.45)")
	check(min_mast_dist >= 0.42,
		"crewmate must stay clear of mainmast (min r=%.2f m, require >= 0.42 m)" % min_mast_dist)
	check(stayed_main_deck, "crewmate stays on main deck without falling into open hatch")

	# 3. Verify all 3 watch spots on BOTH Sloop and Brigantine are clear of masts, capstans, and open hatch.
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	if brig_scene != null:
		var brig := brig_scene.instantiate() as Ship
		brig.enable_effects = false
		brig.start_anchored = true
		_root.add_child(brig)
		brig.global_position = Vector3(80.0, 0.0, 0.0)
		await physics_frames(4)
		var bhs := _ship_scale(brig)
		for pid: StringName in [&"helmsman", &"lookout", &"carpenter"]:
			nav_brain.persona_id = pid
			nav_brain.ship = s
			var sl_spot := nav_brain._idle_watch_spot()
			check(CrewBrain._is_local_point_clear(sl_spot, 1, hs, false, true),
				"Sloop %s watch post is clear of all deck obstacles (%s)" % [String(pid), str(sl_spot)])
			nav_brain.ship = brig
			var br_spot := nav_brain._idle_watch_spot()
			check(CrewBrain._is_local_point_clear(br_spot, 1, bhs, true, true),
				"Brigantine %s watch post is clear of masts/capstan/hatch (%s)" % [String(pid), str(br_spot)])
		# Verify Brigantine fore-to-aft route bypasses both foremast and mainmast!
		var b_route := nav_brain._plan_ship_route(
			Vector3(0.0, 1.25, -5.6) * bhs,
			Vector3(0.0, 1.25, 2.2) * bhs
		)
		check(b_route.size() >= 3, "Brigantine fore-to-aft route inserts clean side-aisle waypoints (got %d)" % b_route.size())

	await _end()
