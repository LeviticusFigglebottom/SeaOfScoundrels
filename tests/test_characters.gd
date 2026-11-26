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
