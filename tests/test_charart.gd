extends TestCase
## Headless verification for CharacterVisual, AnimationDriver, generated character GLBs, and pawn.tscn.

const PAWN_SCENE := preload("res://src/characters/pawn.tscn")
const GLB_PATHS := {
	&"pirate": "res://assets/generated/characters/pirate.glb",
	&"drowned": "res://assets/generated/characters/drowned.glb",
	&"tidecaller": "res://assets/generated/characters/tidecaller.glb",
}
const STATION_KINDS: Array[StringName] = [
	&"helm", &"sail_length", &"sail_angle", &"anchor", &"cannon", &"bilge", &"map_table",
]


func _check_skeleton_finite(sk: Skeleton3D, ctx: String) -> void:
	check(sk != null, "%s: skeleton missing" % ctx)
	if sk == null:
		return
	for i in sk.get_bone_count():
		var q := sk.get_bone_pose_rotation(i)
		var p := sk.get_bone_pose_position(i)
		check(q.is_finite(), "%s: bone %d rot not finite: %s" % [ctx, i, q])
		check(absf(q.length() - 1.0) < 0.015, "%s: bone %d rot not unit (len %.4f)" % [ctx, i, q.length()])
		check(p.is_finite(), "%s: bone %d pos not finite: %s" % [ctx, i, p])


func test_glbs_load_bones_and_bounds() -> void:
	for key: StringName in GLB_PATHS.keys():
		var sc: PackedScene = load(GLB_PATHS[key]) as PackedScene
		check(sc != null, "failed to load %s" % GLB_PATHS[key])
		if sc == null:
			continue
		var inst := sc.instantiate() as Node3D
		add_child(inst)

		var skels := inst.find_children("*", "Skeleton3D", true, false)
		check(skels.size() == 1, "%s expected 1 Skeleton3D, got %d" % [key, skels.size()])
		if skels.size() > 0:
			var sk := skels[0] as Skeleton3D
			check_eq(sk.get_bone_count(), 19, "%s bone count" % key)
			for bname in CharacterVisual.EXPECTED_BONES:
				check(sk.find_bone(bname) >= 0, "%s missing bone %s" % [key, bname])

		var combined := AABB()
		var first := true
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var bb := mi.mesh.get_aabb()
			combined = bb if first else combined.merge(bb)
			first = false
		check(not first, "%s has meshes" % key)
		check(combined.position.y >= -0.05 and combined.position.y <= 0.05, "%s feet near y=0 (got %.3f)" % [key, combined.position.y])
		check(combined.size.y >= 1.55 and combined.size.y <= 2.02, "%s height %.3f in [1.55, 2.02]" % [key, combined.size.y])

		inst.queue_free()
	await physics_frames(2)


func test_all_archetypes_and_sockets() -> void:
	var archs := CharacterVisual.get_archetype_names()
	check_eq(archs.size(), 11, "expected 11 archetypes (4 crew, 4 drowned, 1 tidecaller, 2 corsair)")

	var cv := CharacterVisual.new()
	add_child(cv)
	await physics_frames(1)

	# Attach a dummy prop to hand_right to verify migration across rig swaps.
	var prop := Node3D.new()
	prop.name = "TestSword"
	cv.hand_right.add_child(prop)

	for arch in archs:
		cv.set_archetype(arch)
		check_eq(cv.get_archetype(), arch, "archetype getter matches %s" % arch)
		check(cv.skeleton != null, "%s skeleton exists" % arch)
		check(cv.hand_right != null and cv.hand_right.bone_name == "Hand_R", "%s hand_right socket" % arch)
		check(cv.hand_left != null and cv.hand_left.bone_name == "Hand_L", "%s hand_left socket" % arch)
		check(cv.head_socket != null and cv.head_socket.bone_name == "Head", "%s head_socket" % arch)
		check(cv.back_socket != null and cv.back_socket.bone_name == "Chest", "%s back_socket" % arch)
		check(cv.carry_anchor != null, "%s carry_anchor exists" % arch)
		check(is_instance_valid(prop) and prop.get_parent() == cv.hand_right, "%s prop stayed attached to hand_right" % arch)

		var expected_meshes: Array = CharacterVisual.ARCHETYPES[arch]["meshes"]
		var active := cv.get_active_meshes()
		check_eq(active.size(), expected_meshes.size(), "%s active mesh count" % arch)
		for mi in cv.get_all_meshes():
			var should_show := expected_meshes.has(String(mi.name))
			check_eq(mi.visible, should_show, "%s mesh %s visibility" % [arch, mi.name])

		var bb := cv.get_bounds()
		check(bb.size.y >= 1.55 and bb.size.y <= 2.02, "%s bounds height %.3f m" % [arch, bb.size.y])

	cv.queue_free()
	await physics_frames(2)


func test_first_person_hidden_and_tint_isolation() -> void:
	var a := CharacterVisual.new()
	var b := CharacterVisual.new()
	add_child(a)
	add_child(b)
	a.set_archetype(&"captain")
	b.set_archetype(&"captain")

	var col_a1 := Color(0.92, 0.14, 0.12)
	var col_a2 := Color(0.96, 0.84, 0.18)
	var col_b1 := Color(0.10, 0.35, 0.88)
	var col_b2 := Color(0.18, 0.78, 0.32)
	a.set_tint(col_a1, col_a2)
	b.set_tint(col_b1, col_b2)

	var checked_primary := 0
	var checked_secondary := 0
	for mi in a.get_active_meshes():
		for si in mi.mesh.get_surface_count():
			var base_mat := mi.mesh.surface_get_material(si) as StandardMaterial3D
			var ov_mat := mi.get_surface_override_material(si) as StandardMaterial3D
			if base_mat.resource_name == "mat_cloth_primary":
				checked_primary += 1
				check(ov_mat != null and ov_mat != base_mat, "primary override is an instance duplicate")
				check(ov_mat.albedo_color.is_equal_approx(col_a1), "a primary tint matches")
				check(base_mat.albedo_color.is_equal_approx(Color.WHITE), "shared base primary material untouched")
			elif base_mat.resource_name == "mat_cloth_secondary":
				checked_secondary += 1
				check(ov_mat != null and ov_mat != base_mat, "secondary override is an instance duplicate")
				check(ov_mat.albedo_color.is_equal_approx(col_a2), "a secondary tint matches")
				check(base_mat.albedo_color.is_equal_approx(Color.WHITE), "shared base secondary material untouched")
	check(checked_primary > 0 and checked_secondary > 0, "found primary & secondary surfaces")

	for mi in b.get_active_meshes():
		for si in mi.mesh.get_surface_count():
			var base_mat := mi.mesh.surface_get_material(si) as StandardMaterial3D
			var ov_mat := mi.get_surface_override_material(si) as StandardMaterial3D
			if base_mat.resource_name == "mat_cloth_primary":
				check(ov_mat.albedo_color.is_equal_approx(col_b1), "b primary tint isolated from a")
			elif base_mat.resource_name == "mat_cloth_secondary":
				check(ov_mat.albedo_color.is_equal_approx(col_b2), "b secondary tint isolated from a")

	# First-person hide hides all meshes and persists cleanly across archetype switches.
	a.set_first_person_hidden(true)
	for mi in a.get_all_meshes():
		check(not mi.visible, "first-person hidden hides %s" % mi.name)
	a.set_archetype(&"helmsman")
	for mi in a.get_all_meshes():
		check(not mi.visible, "stays hidden after archetype switch (%s)" % mi.name)
	a.set_first_person_hidden(false)
	var expected_h: Array = CharacterVisual.ARCHETYPES[&"helmsman"]["meshes"]
	for mi in a.get_all_meshes():
		check_eq(mi.visible, expected_h.has(String(mi.name)), "restores only helmsman active meshes (%s)" % mi.name)

	a.queue_free()
	b.queue_free()
	await physics_frames(2)


func _reset_demo(drv: AnimationDriver) -> void:
	drv.stop_action()
	drv.demo_mode = Pawn.Mode.WALK
	drv.demo_velocity = Vector3.ZERO
	drv.demo_sprint = false
	drv.demo_crouched = false
	drv.demo_grounded = true
	drv.demo_carrying = false
	drv.demo_dead = false
	drv.demo_station_kind = &""
	drv.demo_look_pitch = 0.0
	drv.demo_steer = 0.0


func test_animation_driver_modes_actions_and_kinematics() -> void:
	var vis := CharacterVisual.new()
	var drv := AnimationDriver.new()
	drv.manual_mode = true
	vis.add_child(drv)
	add_child(vis)
	vis.set_archetype(&"captain")
	drv.bind(vis, null)
	var sk := vis.skeleton

	# 1. Idle pose: hands relaxed closer to sides than rest A-pose (rest |x|=0.52).
	_reset_demo(drv)
	drv.update_pose(0.016, true)
	_check_skeleton_finite(sk, "idle")
	var hd_r := sk.get_bone_global_pose(sk.find_bone("Hand_R")).origin
	var hd_l := sk.get_bone_global_pose(sk.find_bone("Hand_L")).origin
	check(absf(hd_r.x) < 0.42 and absf(hd_l.x) < 0.42, "idle arms lowered from A-pose (R=%s L=%s)" % [hd_r, hd_l])

	# 2. Walk & Sprint & Jump & Fall
	_reset_demo(drv)
	drv.demo_velocity = Vector3(0.0, 0.0, -3.5)
	for _i in 24:
		drv.update_pose(0.03, false)
		_check_skeleton_finite(sk, "walk")

	drv.demo_sprint = true
	drv.demo_velocity = Vector3(0.0, 0.0, -5.8)
	for _i in 24:
		drv.update_pose(0.03, false)
		_check_skeleton_finite(sk, "sprint")

	drv.demo_grounded = false
	drv.demo_velocity = Vector3(0.0, 5.0, -2.0)
	drv.update_pose(0.03, true)
	_check_skeleton_finite(sk, "jump_rise")
	drv.demo_velocity = Vector3(0.0, -6.0, -2.0)
	drv.update_pose(0.03, true)
	_check_skeleton_finite(sk, "jump_fall")

	# 3. Crouch kinematics: hips drop and knees bend forward (-Z)
	_reset_demo(drv)
	drv.demo_crouched = true
	for _i in 35:
		drv.update_pose(0.03, false)
	_check_skeleton_finite(sk, "crouch")
	var p_hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	var p_kn_r := sk.get_bone_global_pose(sk.find_bone("Shin_R")).origin
	check(p_hips.y < 0.65, "crouch lowers hips (y=%.3f)" % p_hips.y)
	check(p_kn_r.z < p_hips.z - 0.12, "crouch bends knees forward (knR=%s hips=%s)" % [p_kn_r, p_hips])

	# 4. Swim kinematics: horizontal belly-down torso when swimming forward
	_reset_demo(drv)
	drv.demo_mode = Pawn.Mode.SWIM
	drv.demo_velocity = Vector3.ZERO
	for _i in 15:
		drv.update_pose(0.03, false)
		_check_skeleton_finite(sk, "swim_tread")
	drv.demo_velocity = Vector3(0.0, 0.0, -2.4)
	for _i in 30:
		drv.update_pose(0.03, false)
		_check_skeleton_finite(sk, "swim_fwd")
	var sw_hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	var sw_head := sk.get_bone_global_pose(sk.find_bone("Head")).origin
	check(sw_head.z < sw_hips.z - 0.35, "swimming forward pitches torso horizontally (head=%s hips=%s)" % [sw_head, sw_hips])

	# 5. Ladder climbing
	_reset_demo(drv)
	drv.demo_mode = Pawn.Mode.LADDER
	drv.demo_velocity = Vector3(0.0, 2.2, 0.0)
	for _i in 24:
		drv.update_pose(0.03, false)
		_check_skeleton_finite(sk, "ladder")

	# 6. All 7 station kinds
	for kind in STATION_KINDS:
		_reset_demo(drv)
		drv.demo_mode = Pawn.Mode.STATION
		drv.demo_station_kind = kind
		for _i in 15:
			drv.update_pose(0.03, false)
			_check_skeleton_finite(sk, "station_%s" % kind)

	# 7. Carrying kinematics: both hands reach forward (-Z) supporting load
	_reset_demo(drv)
	drv.demo_carrying = true
	drv.update_pose(0.016, true)
	_check_skeleton_finite(sk, "carry")
	var c_hr := sk.get_bone_global_pose(sk.find_bone("Hand_R")).origin
	var c_hl := sk.get_bone_global_pose(sk.find_bone("Hand_L")).origin
	check(c_hr.z < -0.22 and c_hl.z < -0.22, "carry puts both hands forward (R=%s L=%s)" % [c_hr, c_hl])

	# 8. Look pitch tilts head up & down
	_reset_demo(drv)
	drv.demo_look_pitch = 0.85
	drv.update_pose(0.016, true)
	var fwd_up := -sk.get_bone_global_pose(sk.find_bone("Head")).basis.z
	drv.demo_look_pitch = -0.85
	drv.update_pose(0.016, true)
	var fwd_dn := -sk.get_bone_global_pose(sk.find_bone("Head")).basis.z
	check(fwd_up.y > 0.35 and fwd_dn.y < -0.35, "look_pitch tilts head up/down (up=%s dn=%s)" % [fwd_up, fwd_dn])

	# 9. Death collapse pose
	_reset_demo(drv)
	drv.demo_dead = true
	drv.update_pose(0.016, true)
	_check_skeleton_finite(sk, "dead")
	var dead_hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	check(dead_hips.y < 0.35, "standalone death drops hips near deck (y=%.3f)" % dead_hips.y)

	# 10. All 16 layered upper-body actions
	var actions := AnimationDriver.get_action_names()
	check_eq(actions.size(), 16, "expected 16 layered actions")
	for act in actions:
		_reset_demo(drv)
		drv.play_action(act, 0.30)
		check(drv.is_playing_action() and drv.get_current_action() == act, "action %s started" % act)
		for _step in 12:
			drv.update_pose(0.03, false)
			_check_skeleton_finite(sk, "action_%s" % act)
		check(not drv.is_playing_action(), "action %s completed cleanly" % act)

	# Spot-check iconic action silhouettes (aim_pistol forward, shout high overhead)
	_reset_demo(drv)
	drv.hold_action(&"aim_pistol", 0.5)
	drv.update_pose(0.016, true)
	var aim_hr := sk.get_bone_global_pose(sk.find_bone("Hand_R")).origin
	check(aim_hr.z < -0.35 and aim_hr.y > 1.05, "aim_pistol extends right hand forward (R=%s)" % aim_hr)

	_reset_demo(drv)
	drv.hold_action(&"shout", 0.5)
	drv.update_pose(0.016, true)
	var shout_hr := sk.get_bone_global_pose(sk.find_bone("Hand_R")).origin
	check(shout_hr.y > 1.50, "shout pumps right hand high overhead (R=%s)" % shout_hr)

	vis.queue_free()
	await physics_frames(2)


func test_pawn_scene_integration() -> void:
	var p: Pawn = PAWN_SCENE.instantiate() as Pawn
	add_child(p)
	await physics_frames(4)

	var visual_node := p.get_node_or_null(^"Visual") as Node3D
	var cv := p.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
	var drv := p.get_node_or_null(^"Visual/AnimationDriver") as AnimationDriver
	check(visual_node != null, "Pawn has Visual node")
	check(cv != null, "Pawn/Visual has CharacterVisual")
	check(drv != null, "Pawn/Visual has AnimationDriver")
	if cv != null and drv != null:
		check(drv.pawn == p, "AnimationDriver auto-discovered Pawn")
		check(drv.visual == cv, "AnimationDriver auto-discovered CharacterVisual")
		check(drv.skeleton == cv.skeleton and cv.skeleton != null, "AnimationDriver bound to skeleton")

		# Live archetype swap across different rigs rebinds skeleton cleanly!
		cv.set_archetype(&"drowned_captain")
		await physics_frames(2)
		check(drv.skeleton == cv.skeleton, "AnimationDriver rebound after rig swap to drowned")
		_check_skeleton_finite(cv.skeleton, "pawn_drowned_captain")

		cv.set_archetype(&"tidecaller")
		await physics_frames(2)
		check(drv.skeleton == cv.skeleton, "AnimationDriver rebound after rig swap to tidecaller")
		_check_skeleton_finite(cv.skeleton, "pawn_tidecaller")

		# Trigger action and damage/death cycle on live Pawn.
		drv.play_action(&"slash_1")
		await physics_frames(5)
		_check_skeleton_finite(cv.skeleton, "pawn_live_slash")

		p.apply_damage(999.0, null)
		await physics_frames(5)
		check(p.dead, "pawn died")
		_check_skeleton_finite(cv.skeleton, "pawn_dead")
		p.revive(Vector3.ZERO)
		await physics_frames(5)
		check(not p.dead, "pawn revived")
		_check_skeleton_finite(cv.skeleton, "pawn_revived")

	p.queue_free()
	await physics_frames(2)


func test_archetype_property_setter_no_recursion() -> void:
	# Before _ready(): setting archetype property then adding to tree builds cleanly once.
	var cv := CharacterVisual.new()
	var arch_signals := [0]
	var rig_signals := [0]
	cv.archetype_changed.connect(func(_a: StringName) -> void: arch_signals[0] += 1)
	cv.rig_changed.connect(func(_s: Skeleton3D) -> void: rig_signals[0] += 1)
	cv.archetype = &"lookout"
	add_child(cv)
	await physics_frames(1)
	check_eq(cv.archetype, &"lookout", "pre-ready property applied")
	check_eq(arch_signals[0], 1, "archetype_changed emitted once on ready")
	check_eq(rig_signals[0], 1, "rig_changed emitted once on ready")

	# After _ready(): setting property & calling set_archetype emit exactly once each (no recursion).
	cv.archetype = &"helmsman"
	check_eq(cv.archetype, &"helmsman")
	check_eq(arch_signals[0], 2, "same-rig property switch emits archetype_changed once")
	check_eq(rig_signals[0], 1, "same-rig switch does not reload rig")

	cv.set_archetype(&"drowned_powder")
	check_eq(cv.archetype, &"drowned_powder")
	check_eq(arch_signals[0], 3, "set_archetype emits archetype_changed once")
	check_eq(rig_signals[0], 2, "cross-rig switch emits rig_changed once")

	cv.queue_free()
	await physics_frames(2)


func test_charart_showcase_all_shots() -> void:
	var sc := load("res://scenes/showcase/charart_showcase.tscn") as PackedScene
	check(sc != null, "charart_showcase.tscn loads")
	if sc == null:
		return
	var inst := sc.instantiate() as Node3D
	add_child(inst)
	await physics_frames(2)
	for sh in ["lineup", "pirates", "enemies", "poses"]:
		inst.set(&"shot", sh)
		inst.call(&"_rebuild_shot")
		await physics_frames(2)
		var cast := inst.get_node_or_null(^"Cast")
		check(cast != null and cast.get_child_count() >= 4, "shot %s spawns cast (%d)" % [sh, cast.get_child_count() if cast else 0])
		if cast != null:
			for c in cast.get_children():
				var cv := c as CharacterVisual
				if cv != null:
					_check_skeleton_finite(cv.skeleton, "showcase_%s_%s" % [sh, cv.archetype])
	inst.queue_free()
	await physics_frames(2)
