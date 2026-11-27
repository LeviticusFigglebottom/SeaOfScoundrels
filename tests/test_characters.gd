extends TestCase
## Pass Q4B regression tests for AnimationDriver:
## - Q1A waist-to-chest helm grip & zero idle wheel sawing + expressive active steering
## - Dedicated seated &"rowboat_oars" rowing stroke pose
## - Living "sea-legs" Ship roll/pitch counter-balance without breaking grounded foot contact
## - Walk turn-lean banking with head turn-lead & subtle idle Captain glance
## - Crisp asymmetric multi-phase curves & full recovery across all ACTION_DURATIONS actions

const PAWN_SCENE := preload("res://src/characters/pawn.tscn")
const SLOOP_SCENE := preload("res://src/ship/sloop.tscn")


func _check_skeleton_valid(sk: Skeleton3D, ctx: String) -> void:
	check(sk != null, "%s: skeleton missing" % ctx)
	if sk == null:
		return
	for i in sk.get_bone_count():
		var q := sk.get_bone_pose_rotation(i)
		var p := sk.get_bone_pose_position(i)
		check(q.is_finite(), "%s: bone %d rot not finite: %s" % [ctx, i, q])
		check(absf(q.length() - 1.0) < 0.015, "%s: bone %d rot not unit (len %.4f)" % [ctx, i, q.length()])
		check(p.is_finite(), "%s: bone %d pos not finite: %s" % [ctx, i, p])


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
	drv.demo_turn_rate = 0.0


func test_q4b_helm_height_sea_legs_turn_lean_and_expressive_actions() -> void:
	var vis := CharacterVisual.new()
	var drv := AnimationDriver.new()
	drv.manual_mode = true
	vis.add_child(drv)
	add_child(vis)
	vis.set_archetype(&"helmsman")
	drv.bind(vis, null)
	var sk := vis.skeleton
	check(sk != null, "Q4B: helmsman skeleton bound")
	if sk == null:
		vis.queue_free()
		await physics_frames(2)
		return

	var b_hips := sk.find_bone("Hips")
	var b_chest := sk.find_bone("Chest")
	var b_head := sk.find_bone("Head")
	var b_hl := sk.find_bone("Hand_L")
	var b_hr := sk.find_bone("Hand_R")
	var b_sh_l := sk.find_bone("Shin_L")
	var b_sh_r := sk.find_bone("Shin_R")
	var b_ft_l := sk.find_bone("Foot_L")
	var b_ft_r := sk.find_bone("Foot_R")
	var rest_an_l := sk.get_bone_global_rest(b_ft_l).origin.y
	var rest_an_r := sk.get_bone_global_rest(b_ft_r).origin.y

	# ------------------------------------------------------------------
	# 1. &"helm": waist-to-chest grip height, ZERO idle wheel sawing, expressive active steering
	# ------------------------------------------------------------------
	_reset_demo(drv)
	drv.demo_mode = Pawn.Mode.STATION
	drv.demo_station_kind = &"helm"
	drv.demo_steer = 0.0
	drv.update_pose(0.0, true)

	var min_hl_y := INF
	var max_hl_y := -INF
	var min_hr_y := INF
	var max_hr_y := -INF
	var min_head_x := INF
	var max_head_x := -INF
	var max_hand_lr_diff := 0.0
	var avg_hand_z := 0.0
	var idle_samples := 80
	for _i in idle_samples:
		drv.update_pose(0.03, false)
		_check_skeleton_valid(sk, "helm_idle")
		var hl := sk.get_bone_global_pose(b_hl).origin
		var hr := sk.get_bone_global_pose(b_hr).origin
		var fl := sk.get_bone_global_pose(b_ft_l).origin
		var fr := sk.get_bone_global_pose(b_ft_r).origin
		var hd_fwd_x := -sk.get_bone_global_pose(b_head).basis.z.x
		min_hl_y = minf(min_hl_y, hl.y)
		max_hl_y = maxf(max_hl_y, hl.y)
		min_hr_y = minf(min_hr_y, hr.y)
		max_hr_y = maxf(max_hr_y, hr.y)
		min_head_x = minf(min_head_x, hd_fwd_x)
		max_head_x = maxf(max_head_x, hd_fwd_x)
		max_hand_lr_diff = maxf(max_hand_lr_diff, absf(hl.y - hr.y))
		avg_hand_z += 0.5 * (hl.z + hr.z)
		check(absf(fl.y - rest_an_l) < 0.015 and absf(fr.y - rest_an_r) < 0.015,
			"Q4B helm idle feet stay grounded (L=%.4f R=%.4f rest=%.4f)" % [fl.y, fr.y, rest_an_l])
	avg_hand_z /= float(idle_samples)
	var mid_hand_y := 0.25 * (min_hl_y + max_hl_y + min_hr_y + max_hr_y)
	check(mid_hand_y >= 0.80 and mid_hand_y <= 1.18,
		"Q4B helm hands sit at Q1A waist-to-chest wheel height (avg_y=%.3f)" % mid_hand_y)
	check(avg_hand_z < -0.25,
		"Q4B helm hands reach forward to wheel rim (avg_z=%.3f)" % avg_hand_z)
	check((max_hl_y - min_hl_y) < 0.045 and (max_hr_y - min_hr_y) < 0.045,
		"Q4B helm idle does not saw erratically (dL=%.4f dR=%.4f)" % [max_hl_y - min_hl_y, max_hr_y - min_hr_y])
	check(max_hand_lr_diff < 0.025,
		"Q4B helm idle holds steady balanced wheel grip (max |L-R|=%.4f)" % max_hand_lr_diff)
	check((max_head_x - min_head_x) > 0.02,
		"Q4B helm idle gently scans the horizon (span=%.4f)" % (max_head_x - min_head_x))

	# Active steering +/- 0.8 produces clear opposing arm & chest-twist response!
	drv.demo_steer = 0.8
	for _i in 25:
		drv.update_pose(0.03, false)
		_check_skeleton_valid(sk, "helm_steer_pos")
	var hl_pos := sk.get_bone_global_pose(b_hl).origin
	var hr_pos := sk.get_bone_global_pose(b_hr).origin
	var chest_fwd_pos := -sk.get_bone_global_pose(b_chest).basis.z

	drv.demo_steer = -0.8
	for _i in 25:
		drv.update_pose(0.03, false)
		_check_skeleton_valid(sk, "helm_steer_neg")
	var hl_neg := sk.get_bone_global_pose(b_hl).origin
	var hr_neg := sk.get_bone_global_pose(b_hr).origin
	var chest_fwd_neg := -sk.get_bone_global_pose(b_chest).basis.z

	check(hl_pos.y > hr_pos.y + 0.06,
		"Q4B helm steer +0.8 raises left hand above right (L=%.3f R=%.3f)" % [hl_pos.y, hr_pos.y])
	check(hr_neg.y > hl_neg.y + 0.06,
		"Q4B helm steer -0.8 raises right hand above left (L=%.3f R=%.3f)" % [hl_neg.y, hr_neg.y])
	check(chest_fwd_pos.x > 0.06 and chest_fwd_neg.x < -0.06,
		"Q4B helm steer twists chest expressively in opposite directions (pos.x=%.3f neg.x=%.3f)" % [chest_fwd_pos.x, chest_fwd_neg.x])

	# ------------------------------------------------------------------
	# 2. &"rowboat_oars": seated rowing stroke animates smoothly without NaN/Inf
	# ------------------------------------------------------------------
	_reset_demo(drv)
	drv.demo_mode = Pawn.Mode.STATION
	drv.demo_station_kind = &"rowboat_oars"
	drv.update_pose(0.0, true)

	var min_row_hand_z := INF
	var max_row_hand_z := -INF
	var min_row_chest_z := INF
	var max_row_chest_z := -INF
	var max_row_hips_y := -INF
	for _i in 64:
		drv.update_pose(0.03, false)
		_check_skeleton_valid(sk, "rowboat_oars")
		var hips_p := sk.get_bone_global_pose(b_hips).origin
		var kn_r := sk.get_bone_global_pose(b_sh_r).origin
		var hr := sk.get_bone_global_pose(b_hr).origin
		var chest_up := sk.get_bone_global_pose(b_chest).basis.y
		max_row_hips_y = maxf(max_row_hips_y, hips_p.y)
		min_row_hand_z = minf(min_row_hand_z, hr.z)
		max_row_hand_z = maxf(max_row_hand_z, hr.z)
		min_row_chest_z = minf(min_row_chest_z, chest_up.z)
		max_row_chest_z = maxf(max_row_chest_z, chest_up.z)
		check(kn_r.z < hips_p.z - 0.16,
			"Q4B rowboat_oars maintains seated forward knee bend (kn=%.3f hips=%.3f)" % [kn_r.z, hips_p.z])
	check(max_row_hips_y < 0.64,
		"Q4B rowboat_oars lowers hips into seated thwart pose (max_y=%.3f)" % max_row_hips_y)
	check((max_row_hand_z - min_row_hand_z) > 0.10,
		"Q4B rowboat_oars pulls hands smoothly through rowing stroke (range=%.3f m)" % (max_row_hand_z - min_row_hand_z))
	check((max_row_chest_z - min_row_chest_z) > 0.12,
		"Q4B rowboat_oars rocks torso from catch reach to lean-back pull (range=%.3f)" % (max_row_chest_z - min_row_chest_z))

	# ------------------------------------------------------------------
	# 3. All ACTION_DURATIONS actions: finite unit quats, anatomical bends, clean recovery
	# ------------------------------------------------------------------
	var actions := AnimationDriver.get_action_names()
	check_eq(actions.size(), AnimationDriver.ACTION_DURATIONS.size(),
		"Q4B get_action_names matches ACTION_DURATIONS")
	for act in actions:
		_reset_demo(drv)
		drv.update_pose(0.0, true)
		var dur := float(AnimationDriver.ACTION_DURATIONS[act])
		drv.play_action(act)
		check(drv.is_playing_action() and drv.get_current_action() == act,
			"Q4B action %s started" % act)
		var steps := int(ceil((dur + 0.08) / 0.025))
		for _s in steps:
			drv.update_pose(0.025, false)
			_check_skeleton_valid(sk, "q4b_action_%s" % act)
			var fl := sk.get_bone_global_pose(b_ft_l).origin
			var fr := sk.get_bone_global_pose(b_ft_r).origin
			check(fl.y >= rest_an_l - 0.025 and fr.y >= rest_an_r - 0.025,
				"Q4B action %s keeps boot soles above deck floor (L=%.4f R=%.4f rest=%.4f)" % [act, fl.y, fr.y, rest_an_l])
			var hips_z := sk.get_bone_global_pose(b_hips).origin.z
			var kn_l_z := sk.get_bone_global_pose(b_sh_l).origin.z
			var kn_r_z := sk.get_bone_global_pose(b_sh_r).origin.z
			check(kn_l_z <= hips_z + 0.06 and kn_r_z <= hips_z + 0.06,
				"Q4B action %s keeps knees bending anatomically forward (L=%.3f R=%.3f hips=%.3f)" % [act, kn_l_z, kn_r_z, hips_z])
		check(not drv.is_playing_action(),
			"Q4B action %s completed and recovered cleanly" % act)

	# Verify upgraded asymmetric multi-phase actions distinguish windup -> snap strike -> recovery!
	for punch_act: StringName in [&"slash_1", &"slash_2", &"slash_3", &"heavy", &"dig", &"hammer", &"bail", &"drink"]:
		_reset_demo(drv)
		drv.hold_action(punch_act, 0.16)
		drv.update_pose(0.016, true)
		var p_wind := sk.get_bone_global_pose(b_hr).origin
		drv.hold_action(punch_act, 0.56)
		drv.update_pose(0.016, true)
		var p_peak := sk.get_bone_global_pose(b_hr).origin
		check(p_wind.distance_to(p_peak) > 0.08,
			"Q4B action %s has crisp windup->strike travel (dist=%.3f m)" % [punch_act, p_wind.distance_to(p_peak)])

	vis.queue_free()
	await physics_frames(2)

	# ------------------------------------------------------------------
	# 4. Live Pawn on rolled Ship: Sea-Legs counter-balance, grounded feet,
	#    walk turn-lean banking, and subtle idle Captain glance!
	# ------------------------------------------------------------------
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	ship.freeze = true
	add_child(ship)
	ship.global_position = Vector3.ZERO
	ship.rotation = Vector3.ZERO

	var crew_pawn := PAWN_SCENE.instantiate() as Pawn
	add_child(crew_pawn)
	var deck_local := Vector3(0.0, 2.02 * Ship.DEFAULT_HULL_SCALE, 3.6 * Ship.DEFAULT_HULL_SCALE)
	crew_pawn.board(ship, deck_local)
	crew_pawn.look_yaw = 0.0
	await physics_frames(6)

	var p_cv := crew_pawn.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
	var p_drv := crew_pawn.get_node_or_null(^"Visual/AnimationDriver") as AnimationDriver
	check(p_cv != null and p_drv != null and p_drv.skeleton != null,
		"Q4B live ship crew pawn has CharacterVisual & AnimationDriver")
	if p_cv != null and p_drv != null and p_drv.skeleton != null:
		var p_sk := p_drv.skeleton
		var pb_chest := p_sk.find_bone("Chest")
		var pb_head := p_sk.find_bone("Head")
		var pb_ft_l := p_sk.find_bone("Foot_L")
		var pb_ft_r := p_sk.find_bone("Foot_R")
		var p_rest_l := p_sk.get_bone_global_rest(pb_ft_l).origin.y
		var p_rest_r := p_sk.get_bone_global_rest(pb_ft_r).origin.y

		# Level ship baseline
		ship.rotation = Vector3.ZERO
		crew_pawn.look_yaw = 0.0
		crew_pawn.velocity = Vector3.ZERO
		p_drv.update_pose(0.0, true)
		for _i in 20:
			p_drv.update_pose(0.03, false)
		var chest_up_level := p_sk.get_bone_global_pose(pb_chest).basis.y

		# Starboard roll (deck_up tilts toward +X -> torso counter-rolls uphill toward -X)
		ship.rotation = Vector3(0.0, 0.0, -0.26)
		for _i in 28:
			p_drv.update_pose(0.03, false)
			_check_skeleton_valid(p_sk, "sea_legs_stbd")
		var chest_up_stbd := p_sk.get_bone_global_pose(pb_chest).basis.y
		var fl_stbd := p_sk.get_bone_global_pose(pb_ft_l).origin
		var fr_stbd := p_sk.get_bone_global_pose(pb_ft_r).origin
		check(chest_up_stbd.x < chest_up_level.x - 0.04,
			"Q4B sea-legs counter-rolls torso uphill on starboard roll (stbd.x=%.4f level.x=%.4f)" % [chest_up_stbd.x, chest_up_level.x])
		check(absf(fl_stbd.y - p_rest_l) < 0.015 and absf(fr_stbd.y - p_rest_r) < 0.015,
			"Q4B sea-legs preserves grounded foot contact on starboard roll (L=%.4f R=%.4f rest=%.4f)" % [fl_stbd.y, fr_stbd.y, p_rest_l])

		# Port roll (deck_up tilts toward -X -> torso counter-rolls uphill toward +X)
		ship.rotation = Vector3(0.0, 0.0, 0.26)
		for _i in 32:
			p_drv.update_pose(0.03, false)
			_check_skeleton_valid(p_sk, "sea_legs_port")
		var chest_up_port := p_sk.get_bone_global_pose(pb_chest).basis.y
		var fl_port := p_sk.get_bone_global_pose(pb_ft_l).origin
		var fr_port := p_sk.get_bone_global_pose(pb_ft_r).origin
		check(chest_up_port.x > chest_up_level.x + 0.04,
			"Q4B sea-legs counter-rolls torso uphill on port roll (port.x=%.4f level.x=%.4f)" % [chest_up_port.x, chest_up_level.x])
		check(absf(fl_port.y - p_rest_l) < 0.015 and absf(fr_port.y - p_rest_r) < 0.015,
			"Q4B sea-legs preserves grounded foot contact on port roll (L=%.4f R=%.4f rest=%.4f)" % [fl_port.y, fr_port.y, p_rest_l])

		# Walk turn-lean banking & head turn lead on level deck
		ship.rotation = Vector3.ZERO
		crew_pawn.look_yaw = 0.0
		p_drv.update_pose(0.0, true)
		for _i in 22:
			crew_pawn.look_yaw = wrapf(crew_pawn.look_yaw + 0.06, -PI, PI)
			crew_pawn.velocity = crew_pawn.facing() * 3.6
			p_drv.update_pose(0.03, false)
			_check_skeleton_valid(p_sk, "turn_lean_left")
		var turn_bank_left_x := p_sk.get_bone_global_pose(pb_chest).basis.y.x
		var head_lead_left_x := -p_sk.get_bone_global_pose(pb_head).basis.z.x

		for _i in 30:
			crew_pawn.look_yaw = wrapf(crew_pawn.look_yaw - 0.06, -PI, PI)
			crew_pawn.velocity = crew_pawn.facing() * 3.6
			p_drv.update_pose(0.03, false)
			_check_skeleton_valid(p_sk, "turn_lean_right")
		var turn_bank_right_x := p_sk.get_bone_global_pose(pb_chest).basis.y.x
		var head_lead_right_x := -p_sk.get_bone_global_pose(pb_head).basis.z.x

		check(turn_bank_left_x < turn_bank_right_x - 0.04,
			"Q4B walk turn-lean banks chest into left/right turns (left.x=%.4f right.x=%.4f)" % [turn_bank_left_x, turn_bank_right_x])
		check(head_lead_left_x < head_lead_right_x - 0.08,
			"Q4B walk turn-lean leads head into left/right turns (left.x=%.4f right.x=%.4f)" % [head_lead_left_x, head_lead_right_x])

		# Subtle idle Captain glance toward nearest &"player" Pawn within 7.5 m
		crew_pawn.velocity = Vector3.ZERO
		crew_pawn.look_yaw = 0.0
		var cap_pawn := PAWN_SCENE.instantiate() as Pawn
		cap_pawn.add_to_group(&"player")
		add_child(cap_pawn)
		cap_pawn.global_position = crew_pawn.global_position + Vector3(-2.6, 0.0, -3.2)
		for _i in 35:
			p_drv.update_pose(0.03, false)
			_check_skeleton_valid(p_sk, "captain_glance_left")
		var glance_left_x := -p_sk.get_bone_global_pose(pb_head).basis.z.x

		cap_pawn.global_position = crew_pawn.global_position + Vector3(2.6, 0.0, -3.2)
		for _i in 45:
			p_drv.update_pose(0.03, false)
			_check_skeleton_valid(p_sk, "captain_glance_right")
		var glance_right_x := -p_sk.get_bone_global_pose(pb_head).basis.z.x

		check(glance_left_x < -0.18 and glance_right_x > 0.18,
			"Q4B idle crewmate smoothly glances toward nearby Captain (L.x=%.3f R.x=%.3f)" % [glance_left_x, glance_right_x])

		cap_pawn.queue_free()

	crew_pawn.queue_free()
	ship.queue_free()
	await physics_frames(4)
	ShipDamageVisuals.clear_shared_cache()


func _count_mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var tris := 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var idx_var: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx_var is PackedInt32Array and not (idx_var as PackedInt32Array).is_empty():
			tris += int(float((idx_var as PackedInt32Array).size()) / 3.0)
		else:
			var v_var: Variant = arrays[Mesh.ARRAY_VERTEX]
			if v_var is PackedVector3Array:
				tris += int(float((v_var as PackedVector3Array).size()) / 3.0)
	return tris


func test_q10a_sculpted_character_rigs_smooth_anatomy_pbr_and_sockets() -> void:
	var rig_specs: Array[Dictionary] = [
		{
			"key": &"pirate",
			"path": "res://assets/generated/characters/pirate.glb",
			"min_tris": 16000,
			"meshes": [
				"Body", "Hat_Tricorne", "Hat_Bandana", "Hat_Cap",
				"Coat_Captain", "Vest_Crew", "Beard_Full", "Eyepatch", "Belt_Sash",
			],
			"mats": [
				"mat_cloth_primary", "mat_cloth_secondary", "mat_cloth_base",
				"mat_leather", "mat_skin", "mat_hair", "mat_brass",
			],
			"min_pbr": 5,
		},
		{
			"key": &"drowned",
			"path": "res://assets/generated/characters/drowned.glb",
			"min_tris": 15000,
			"meshes": [
				"Drowned_Body", "Drowned_Bandana", "Drowned_CaptainHat",
				"Drowned_Coat", "Drowned_Shield", "Drowned_PowderKeg",
			],
			"mats": [
				"mat_cloth_primary", "mat_cloth_secondary", "mat_leather",
				"mat_brass", "mat_iron", "mat_bone", "mat_coral",
				"mat_emissive_sea", "mat_emissive_keg",
			],
			"min_pbr": 6,
		},
		{
			"key": &"tidecaller",
			"path": "res://assets/generated/characters/tidecaller.glb",
			"min_tris": 7500,
			"meshes": ["Tidecaller_Body"],
			"mats": [
				"mat_cloth_primary", "mat_cloth_secondary", "mat_leather",
				"mat_bone", "mat_coral", "mat_emissive_sea",
			],
			"min_pbr": 4,
		},
	]

	for spec in rig_specs:
		var rig_key: StringName = spec["key"]
		var glb_path: String = spec["path"]
		var sc := load(glb_path) as PackedScene
		check(sc != null, "Q10A: failed to load %s" % glb_path)
		if sc == null:
			continue
		var inst := sc.instantiate() as Node3D
		add_child(inst)

		# 1. Exact 19-bone skeleton & rest heights preserved
		var skels := inst.find_children("*", "Skeleton3D", true, false)
		check_eq(skels.size(), 1, "Q10A %s: expected 1 Skeleton3D" % rig_key)
		if skels.size() == 1:
			var sk := skels[0] as Skeleton3D
			check_eq(sk.get_bone_count(), 19, "Q10A %s: 19-bone rig preserved" % rig_key)
			for bname in CharacterVisual.EXPECTED_BONES:
				var bi := sk.find_bone(bname)
				check(bi >= 0, "Q10A %s: missing bone %s" % [rig_key, bname])
				if bi >= 0:
					var rest := sk.get_bone_global_rest(bi)
					check(rest.origin.is_finite(), "Q10A %s: bone %s rest finite" % [rig_key, bname])
			var head_y := sk.get_bone_global_rest(sk.find_bone("Head")).origin.y
			check(head_y >= 1.45 and head_y <= 1.56,
				"Q10A %s: Head rest height preserved (got %.3f m)" % [rig_key, head_y])

		# 2. Exact variant meshes, upgraded sculpted triangle budgets, bounds, PBR maps & tangents
		var found_meshes: Dictionary = {}
		var found_mats: Dictionary = {}
		var pbr_mats: Dictionary = {}
		var total_tris := 0
		var bad_tangents := 0
		var missing_pbr_tangents := 0
		var non_unit_normals := 0
		var combined := AABB()
		var has_bounds := false

		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			found_meshes[String(mi.name)] = true
			total_tris += _count_mesh_tris(mi.mesh)
			var bb := mi.mesh.get_aabb()
			combined = bb if not has_bounds else combined.merge(bb)
			has_bounds = true

			for si in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(si)
				var tang_var: Variant = arrays[Mesh.ARRAY_TANGENT] if not arrays.is_empty() else null
				var has_tangents := (tang_var is PackedFloat32Array) and not (tang_var as PackedFloat32Array).is_empty()
				if has_tangents:
					for tv: float in (tang_var as PackedFloat32Array):
						if not is_finite(tv):
							bad_tangents += 1
							break
				var norm_var: Variant = arrays[Mesh.ARRAY_NORMAL] if not arrays.is_empty() else null
				if norm_var is PackedVector3Array:
					for nv: Vector3 in (norm_var as PackedVector3Array):
						if not nv.is_finite() or absf(nv.length() - 1.0) > 0.05:
							non_unit_normals += 1
							break

				var mat: Material = mi.mesh.surface_get_material(si)
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					if not std.resource_name.is_empty():
						found_mats[std.resource_name] = true
					if std.normal_enabled and std.normal_texture != null and std.roughness_texture != null:
						var mid := std.resource_name if not std.resource_name.is_empty() else str(std.get_instance_id())
						pbr_mats[mid] = true
						check(std.albedo_texture != null,
							"Q10A %s: PBR mat %s has albedo_texture" % [rig_key, mid])
						if not has_tangents:
							missing_pbr_tangents += 1

		var want_meshes: Array = spec["meshes"]
		check_eq(found_meshes.size(), want_meshes.size(),
			"Q10A %s: exact mesh variant count (%d vs %d)" % [rig_key, found_meshes.size(), want_meshes.size()])
		for wm: String in want_meshes:
			check(found_meshes.has(wm), "Q10A %s: missing expected variant mesh %s" % [rig_key, wm])

		var min_tris: int = spec["min_tris"]
		check(total_tris >= min_tris,
			"Q10A %s: upgraded sculpted triangle budget (%d >= %d)" % [rig_key, total_tris, min_tris])
		check(has_bounds, "Q10A %s: has valid mesh bounds" % rig_key)
		check(combined.position.y >= -0.05 and combined.position.y <= 0.05,
			"Q10A %s: boot/foot soles planted near y=0 (got %.4f)" % [rig_key, combined.position.y])
		check(combined.size.y >= 1.55 and combined.size.y <= 2.02,
			"Q10A %s: overall standing height in [1.55, 2.02] (got %.3f m)" % [rig_key, combined.size.y])

		for want_mat: String in (spec["mats"] as Array):
			check(found_mats.has(want_mat),
				"Q10A %s: missing expected material %s (found: %s)" % [rig_key, want_mat, str(found_mats.keys())])
		check(pbr_mats.size() >= int(spec["min_pbr"]),
			"Q10A %s: expected >= %d distinct PBR materials (got %d)" % [rig_key, int(spec["min_pbr"]), pbr_mats.size()])
		check_eq(missing_pbr_tangents, 0, "Q10A %s: all PBR surfaces carry tangents" % rig_key)
		check_eq(bad_tangents, 0, "Q10A %s: all tangents are finite" % rig_key)
		check_eq(non_unit_normals, 0, "Q10A %s: all sculpted vertex normals are finite unit vectors" % rig_key)

		inst.queue_free()

	# 3. Runtime CharacterVisual sockets, archetype toggles & AnimationDriver pose health across all 3 rigs
	var cv := CharacterVisual.new()
	var drv := AnimationDriver.new()
	drv.manual_mode = true
	cv.add_child(drv)
	add_child(cv)
	await physics_frames(1)

	for arch: StringName in [&"captain", &"helmsman", &"lookout", &"drowned_captain", &"drowned_shield", &"drowned_powder", &"tidecaller"]:
		cv.set_archetype(arch)
		drv.bind(cv, null)
		drv.update_pose(0.016, true)
		_check_skeleton_valid(cv.skeleton, "q10a_%s" % arch)
		check(cv.hand_right != null and cv.hand_right.bone_name == "Hand_R", "Q10A %s: HandRight socket preserved" % arch)
		check(cv.hand_left != null and cv.hand_left.bone_name == "Hand_L", "Q10A %s: HandLeft socket preserved" % arch)
		check(cv.head_socket != null and cv.head_socket.bone_name == "Head", "Q10A %s: HeadSocket preserved" % arch)
		check(cv.back_socket != null and cv.back_socket.bone_name == "Chest", "Q10A %s: BackSocket preserved" % arch)
		check(cv.carry_anchor != null, "Q10A %s: CarryAnchor preserved" % arch)
		var bb := cv.get_bounds()
		check(bb.size.y >= 1.55 and bb.size.y <= 2.02,
			"Q10A %s: active archetype height %.3f m in [1.55, 2.02]" % [arch, bb.size.y])

	cv.queue_free()
	await physics_frames(2)

