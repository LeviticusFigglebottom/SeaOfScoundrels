class_name AnimationDriver
extends Node
## Procedural skeletal animation driver for CharacterVisual.
##
## Drives a 19-bone CharacterVisual skeleton from an ancestor Pawn (or standalone demo
## parameters for showcases/tests) using rest-pose-aware character-space rotations and
## anatomical elbow/knee hinges so limbs swing naturally without twisting backwards.

const ACTION_DURATIONS := {
	&"slash_1": 0.42,
	&"slash_2": 0.42,
	&"slash_3": 0.54,
	&"heavy": 0.80,
	&"block": 0.48,
	&"parry": 0.36,
	&"stagger": 0.56,
	&"aim_pistol": 0.65,
	&"fire_pistol": 0.36,
	&"dig": 0.74,
	&"hammer": 0.48,
	&"bail": 0.66,
	&"drink": 1.15,
	&"play_instrument": 1.60,
	&"shout": 0.88,
	&"dodge": 0.40,
}

## Optional explicit path to CharacterVisual. Auto-discovered if empty.
@export var visual_path: NodePath
## Optional explicit path to Pawn. Auto-discovered from ancestors if empty.
@export var pawn_path: NodePath
## When true, reads `demo_*` fields instead of a parent Pawn (useful for showcases & tests).
@export var manual_mode: bool = false

# ---- standalone / showcase override state ----
var demo_mode: int = Pawn.Mode.WALK
var demo_velocity: Vector3 = Vector3.ZERO
var demo_sprint: bool = false
var demo_crouched: bool = false
var demo_grounded: bool = true
var demo_carrying: bool = false
var demo_dead: bool = false
var demo_station_kind: StringName = &""
var demo_look_pitch: float = 0.0
var demo_steer: float = 0.0
var demo_turn_rate: float = 0.0

var visual: CharacterVisual = null
var pawn: Pawn = null
var skeleton: Skeleton3D = null

var _bone_count: int = 0
var _rest_pos: PackedVector3Array = PackedVector3Array()
var _rest_rot: Array[Quaternion] = []
var _par_grest_rot: Array[Quaternion] = []
var _grest_rot: Array[Quaternion] = []
var _cur_rot: Array[Quaternion] = []
var _target_rot: Array[Quaternion] = []
var _cur_hips_offset: Vector3 = Vector3.ZERO
var _target_hips_offset: Vector3 = Vector3.ZERO
var _rest_ankle_y_l: float = 0.09
var _rest_ankle_y_r: float = 0.09

# Cached 19-bone indices
var _b_hips: int = -1
var _b_spine: int = -1
var _b_chest: int = -1
var _b_neck: int = -1
var _b_head: int = -1
var _b_sh_l: int = -1
var _b_ua_l: int = -1
var _b_fa_l: int = -1
var _b_hand_l: int = -1
var _b_sh_r: int = -1
var _b_ua_r: int = -1
var _b_fa_r: int = -1
var _b_hand_r: int = -1
var _b_thigh_l: int = -1
var _b_shin_l: int = -1
var _b_foot_l: int = -1
var _b_thigh_r: int = -1
var _b_shin_r: int = -1
var _b_foot_r: int = -1

# Continuous animation timers & smooth blends
var _time: float = 0.0
var _walk_phase: float = 0.0
var _swim_phase: float = 0.0
var _ladder_phase: float = 0.0
var _station_phase: float = 0.0
var _prev_pawn_y: float = 0.0
var _have_prev_y: bool = false
var _prev_yaw: float = 0.0
var _have_prev_yaw: bool = false
var _prev_yaw_plat_id: int = 0
var _turn_rate: float = 0.0
var _ship_roll: float = 0.0
var _ship_pitch: float = 0.0
var _gaze_yaw: float = 0.0
var _gaze_pitch: float = 0.0
var _move_blend: float = 0.0
var _sprint_blend: float = 0.0
var _crouch_blend: float = 0.0
var _carry_blend: float = 0.0
var _swim_move_blend: float = 0.0
var _land_dip: float = 0.0
var _was_grounded: bool = true

# Layered upper-body action state
var _action: StringName = &""
var _action_time: float = 0.0
var _action_dur: float = 0.0
var _action_hold: bool = false
var _action_hold_u: float = 0.5


func _ready() -> void:
	_discover_targets()
	if skeleton != null:
		update_pose(0.0, true)


## Bind explicitly to a CharacterVisual and optional Pawn.
func bind(target_visual: CharacterVisual, target_pawn: Pawn = null) -> void:
	if visual != null and visual.rig_changed.is_connected(_on_rig_changed):
		visual.rig_changed.disconnect(_on_rig_changed)
	if pawn != null and pawn.landed.is_connected(_on_pawn_landed):
		pawn.landed.disconnect(_on_pawn_landed)
	visual = target_visual
	pawn = target_pawn
	_have_prev_y = false
	_have_prev_yaw = false
	_prev_yaw_plat_id = 0
	_turn_rate = 0.0
	_ship_roll = 0.0
	_ship_pitch = 0.0
	_gaze_yaw = 0.0
	_gaze_pitch = 0.0
	if visual != null:
		if not visual.rig_changed.is_connected(_on_rig_changed):
			visual.rig_changed.connect(_on_rig_changed)
		_bind_skeleton(visual.skeleton)
	else:
		_bind_skeleton(null)
	if pawn != null and not pawn.landed.is_connected(_on_pawn_landed):
		pawn.landed.connect(_on_pawn_landed)


## All supported layered action names.
static func get_action_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for k: StringName in ACTION_DURATIONS.keys():
		names.append(k)
	return names


## Trigger a layered upper-body action animation. Pass `duration <= 0.0` for default timing.
func play_action(action: StringName, duration: float = 0.0) -> void:
	if not ACTION_DURATIONS.has(action):
		push_warning("AnimationDriver: unknown action '%s'." % String(action))
		return
	_action = action
	_action_time = 0.0
	_action_dur = duration if duration > 0.0 else float(ACTION_DURATIONS[action])
	_action_hold = false


## Hold an action frozen at normalized phase `phase_01` (0..1) until cleared (for showcases).
func hold_action(action: StringName, phase_01: float = 0.5) -> void:
	if not ACTION_DURATIONS.has(action):
		push_warning("AnimationDriver: unknown action '%s'." % String(action))
		return
	_action = action
	_action_dur = float(ACTION_DURATIONS[action])
	_action_hold = true
	_action_hold_u = clampf(phase_01, 0.0, 1.0)
	_action_time = _action_hold_u * _action_dur


## Clear any active layered action.
func stop_action() -> void:
	_action = &""
	_action_time = 0.0
	_action_dur = 0.0
	_action_hold = false


func get_current_action() -> StringName:
	return _action


func is_playing_action() -> bool:
	return _action != &""


## Immediately snap skeleton bones to the current target pose without smoothing lag.
func snap_pose() -> void:
	update_pose(0.0, true)


func _process(delta: float) -> void:
	if visual == null:
		_discover_targets()
	if visual != null and visual.skeleton != skeleton:
		_bind_skeleton(visual.skeleton)
	if skeleton == null:
		return
	update_pose(delta, false)


## Advance procedural animation by `delta` seconds and apply poses to the bound Skeleton3D.
func update_pose(delta: float, snap: bool = false) -> void:
	if skeleton == null or _bone_count == 0:
		return
	var dt := clampf(delta, 0.0, 0.1)
	_time += dt

	var st := _sample_state(dt, snap)
	_reset_targets_to_rest()

	if st.dead:
		_pose_death(st.parent_pitched)
	else:
		match st.mode:
			Pawn.Mode.SWIM:
				_pose_swim(dt, st)
			Pawn.Mode.LADDER:
				_pose_ladder(dt, st)
			Pawn.Mode.STATION:
				_pose_station(dt, st)
			_:
				_pose_walk(dt, st, snap)

		_apply_look_pitch(st)

		if st.carrying and st.mode != Pawn.Mode.STATION and st.mode != Pawn.Mode.LADDER:
			_carry_blend = 1.0 if snap else move_toward(_carry_blend, 1.0, dt * 8.0)
		else:
			_carry_blend = 0.0 if snap else move_toward(_carry_blend, 0.0, dt * 8.0)
		if _carry_blend > 0.001:
			_layer_carry(_carry_blend)

		_tick_and_layer_action(dt)
		_apply_grounded_leg_flexion(st)

	_compensate_parent_scale(st)
	_update_carry_anchor(st)

	var blend_rate := 24.0 if _action != &"" else 15.0
	var alpha := 1.0 if snap else (1.0 - exp(-blend_rate * dt))
	_cur_hips_offset = _cur_hips_offset.lerp(_target_hips_offset, alpha)
	if not _cur_hips_offset.is_finite():
		_cur_hips_offset = Vector3.ZERO

	for i in _bone_count:
		var q := _safe_slerp(_cur_rot[i], _target_rot[i], alpha)
		_cur_rot[i] = q
		skeleton.set_bone_pose_rotation(i, q)

	if _b_hips >= 0:
		skeleton.set_bone_pose_position(_b_hips, _rest_pos[_b_hips] + _cur_hips_offset)


# ------------------------------------------------------------------ discovery & binding

func _discover_targets() -> void:
	var found_vis: CharacterVisual = null
	if not visual_path.is_empty():
		found_vis = get_node_or_null(visual_path) as CharacterVisual
	if found_vis == null and get_parent() is CharacterVisual:
		found_vis = get_parent() as CharacterVisual
	if found_vis == null and get_parent() != null:
		for sib in get_parent().get_children():
			if sib is CharacterVisual:
				found_vis = sib as CharacterVisual
				break
	if found_vis == null and get_parent() != null:
		var vis_list := get_parent().find_children("*", "CharacterVisual", true, false)
		if vis_list.size() > 0:
			found_vis = vis_list[0] as CharacterVisual

	var found_pawn: Pawn = null
	if not pawn_path.is_empty():
		found_pawn = get_node_or_null(pawn_path) as Pawn
	if found_pawn == null:
		var anc := get_parent()
		while anc != null:
			if anc is Pawn:
				found_pawn = anc as Pawn
				break
			anc = anc.get_parent()

	bind(found_vis, found_pawn)


func _on_rig_changed(new_skeleton: Skeleton3D) -> void:
	_bind_skeleton(new_skeleton)
	if skeleton != null:
		update_pose(0.0, true)


func _on_pawn_landed(impact_speed: float) -> void:
	_land_dip = clampf(impact_speed * 0.032, 0.04, 0.24)


func _bind_skeleton(sk: Skeleton3D) -> void:
	skeleton = sk
	_bone_count = 0
	_rest_pos.clear()
	_rest_rot.clear()
	_par_grest_rot.clear()
	_grest_rot.clear()
	_cur_rot.clear()
	_target_rot.clear()
	_cur_hips_offset = Vector3.ZERO
	_target_hips_offset = Vector3.ZERO
	_rest_ankle_y_l = 0.09
	_rest_ankle_y_r = 0.09
	if skeleton == null:
		return

	_bone_count = skeleton.get_bone_count()
	_rest_pos.resize(_bone_count)
	_rest_rot.resize(_bone_count)
	_par_grest_rot.resize(_bone_count)
	_grest_rot.resize(_bone_count)
	_cur_rot.resize(_bone_count)
	_target_rot.resize(_bone_count)

	for i in _bone_count:
		var rest := skeleton.get_bone_rest(i)
		var r_rot := rest.basis.orthonormalized().get_rotation_quaternion().normalized()
		_rest_pos[i] = rest.origin
		_rest_rot[i] = r_rot
		_grest_rot[i] = skeleton.get_bone_global_rest(i).basis.orthonormalized().get_rotation_quaternion().normalized()
		_cur_rot[i] = r_rot
		_target_rot[i] = r_rot
		var par := skeleton.get_bone_parent(i)
		if par >= 0:
			_par_grest_rot[i] = skeleton.get_bone_global_rest(par).basis.orthonormalized().get_rotation_quaternion().normalized()
		else:
			_par_grest_rot[i] = Quaternion.IDENTITY

	_b_hips = skeleton.find_bone("Hips")
	_b_spine = skeleton.find_bone("Spine")
	_b_chest = skeleton.find_bone("Chest")
	_b_neck = skeleton.find_bone("Neck")
	_b_head = skeleton.find_bone("Head")
	_b_sh_l = skeleton.find_bone("Shoulder_L")
	_b_ua_l = skeleton.find_bone("UpperArm_L")
	_b_fa_l = skeleton.find_bone("Forearm_L")
	_b_hand_l = skeleton.find_bone("Hand_L")
	_b_sh_r = skeleton.find_bone("Shoulder_R")
	_b_ua_r = skeleton.find_bone("UpperArm_R")
	_b_fa_r = skeleton.find_bone("Forearm_R")
	_b_hand_r = skeleton.find_bone("Hand_R")
	_b_thigh_l = skeleton.find_bone("Thigh_L")
	_b_shin_l = skeleton.find_bone("Shin_L")
	_b_foot_l = skeleton.find_bone("Foot_L")
	_b_thigh_r = skeleton.find_bone("Thigh_R")
	_b_shin_r = skeleton.find_bone("Shin_R")
	_b_foot_r = skeleton.find_bone("Foot_R")
	if _b_foot_l >= 0:
		_rest_ankle_y_l = skeleton.get_bone_global_rest(_b_foot_l).origin.y
	if _b_foot_r >= 0:
		_rest_ankle_y_r = skeleton.get_bone_global_rest(_b_foot_r).origin.y


# ------------------------------------------------------------------ state sampling

class _AnimState:
	var mode: int = Pawn.Mode.WALK
	var horiz_speed: float = 0.0
	var fwd_speed: float = 0.0
	var right_speed: float = 0.0
	var vert_vel: float = 0.0
	var sprint: bool = false
	var crouched: bool = false
	var grounded: bool = true
	var carrying: bool = false
	var dead: bool = false
	var station_kind: StringName = &""
	var look_pitch: float = 0.0
	var steer: float = 0.0
	var climb_vel: float = 0.0
	var parent_pitched: bool = false
	var parent_scale_y: float = 1.0
	var walk_ref: float = 3.6
	var sprint_ref: float = 5.8
	var ship_roll: float = 0.0
	var ship_pitch: float = 0.0
	var turn_rate: float = 0.0
	var row_effort: float = 1.0
	var row_turn: float = 0.0


func _sample_state(dt: float, snap: bool = false) -> _AnimState:
	var st := _AnimState.new()
	if visual != null:
		var vp := visual.get_parent() as Node3D
		if vp != null and vp != pawn:
			st.parent_pitched = absf(vp.rotation.x) > 0.5
			st.parent_scale_y = vp.scale.y

	if not manual_mode and pawn != null and is_instance_valid(pawn):
		st.mode = pawn.mode
		st.dead = pawn.dead
		st.crouched = pawn.crouched
		st.grounded = pawn.is_grounded() or st.mode == Pawn.Mode.STATION
		st.carrying = pawn.carried != null
		st.sprint = pawn.wish_sprint
		st.look_pitch = pawn.look_pitch
		st.walk_ref = maxf(pawn.walk_speed, 0.5)
		st.sprint_ref = maxf(pawn.sprint_speed, st.walk_ref + 0.5)

		var rel_v := pawn.get_relative_velocity()
		st.vert_vel = rel_v.y
		var hv := Vector3(rel_v.x, 0.0, rel_v.z)
		st.horiz_speed = hv.length()
		var fwd := pawn.facing()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		st.fwd_speed = hv.dot(fwd)
		st.right_speed = hv.dot(right)

		if pawn.station != null and is_instance_valid(pawn.station):
			var k: Variant = pawn.station.get(&"kind")
			if k is StringName:
				st.station_kind = k
			elif k != null:
				st.station_kind = StringName(str(k))
			if st.station_kind == &"rowboat_oars":
				var st_ship: Variant = pawn.station.get(&"ship")
				if st_ship is Node and is_instance_valid(st_ship):
					var pe: Variant = (st_ship as Node).get(&"_port_oar_effort")
					var se: Variant = (st_ship as Node).get(&"_stbd_oar_effort")
					if (pe is float or pe is int) and (se is float or se is int):
						var pf := float(pe)
						var sf := float(se)
						st.row_effort = clampf(maxf(absf(pf), absf(sf)), 0.0, 1.0)
						st.row_turn = clampf((pf - sf) * 0.5, -1.0, 1.0)

		var target_ship_roll := 0.0
		var target_ship_pitch := 0.0
		var plat_id := 0
		var cur_yaw := pawn.look_yaw
		if pawn.platform != null and is_instance_valid(pawn.platform):
			plat_id = pawn.platform.get_instance_id()
			var h: Variant = pawn.platform.get(&"helm")
			if h is float or h is int:
				st.steer = clampf(float(h), -1.0, 1.0)
			if pawn.platform is Ship:
				var deck_up_raw := pawn.platform.global_transform.basis.y
				if deck_up_raw.length_squared() > 1e-6:
					var deck_up := deck_up_raw.normalized()
					var up_y := maxf(deck_up.y, 0.15)
					target_ship_roll = clampf(atan2(deck_up.dot(right), up_y), -0.65, 0.65)
					target_ship_pitch = clampf(atan2(deck_up.dot(fwd), up_y), -0.65, 0.65)
			var pfwd := -pawn.platform.global_transform.basis.z
			if pfwd.x * pfwd.x + pfwd.z * pfwd.z > 1e-4:
				var plat_yaw := atan2(-pfwd.x, -pfwd.z)
				cur_yaw = wrapf(cur_yaw - plat_yaw, -PI, PI)

		var deck_alpha := 1.0 if (snap or dt <= 0.0001) else (1.0 - exp(-6.5 * dt))
		_ship_roll = lerpf(_ship_roll, target_ship_roll, deck_alpha)
		_ship_pitch = lerpf(_ship_pitch, target_ship_pitch, deck_alpha)
		st.ship_roll = _ship_roll
		st.ship_pitch = _ship_pitch

		if snap or not _have_prev_yaw or plat_id != _prev_yaw_plat_id:
			_prev_yaw = cur_yaw
			_have_prev_yaw = true
			_prev_yaw_plat_id = plat_id
			_turn_rate = 0.0
		elif dt > 0.0001:
			var dyaw := angle_difference(_prev_yaw, cur_yaw)
			var raw_rate := clampf(dyaw / dt, -8.0, 8.0)
			var turn_alpha := 1.0 - exp(-9.0 * dt)
			_turn_rate = lerpf(_turn_rate, raw_rate, turn_alpha)
			_prev_yaw = cur_yaw
		st.turn_rate = _turn_rate

		if _have_prev_y and dt > 0.0001:
			st.climb_vel = (pawn.global_position.y - _prev_pawn_y) / dt
		_prev_pawn_y = pawn.global_position.y
		_have_prev_y = true

		if st.grounded and not _was_grounded and st.mode == Pawn.Mode.WALK:
			_land_dip = maxf(_land_dip, 0.08)
		_was_grounded = st.grounded
	else:
		st.mode = demo_mode
		st.dead = demo_dead
		st.crouched = demo_crouched
		st.grounded = demo_grounded
		st.carrying = demo_carrying
		st.sprint = demo_sprint
		st.station_kind = demo_station_kind
		st.look_pitch = demo_look_pitch
		st.steer = demo_steer
		st.turn_rate = demo_turn_rate
		st.row_effort = 1.0
		st.row_turn = clampf(demo_steer, -1.0, 1.0)
		st.vert_vel = demo_velocity.y
		st.fwd_speed = -demo_velocity.z
		st.right_speed = demo_velocity.x
		st.horiz_speed = Vector2(demo_velocity.x, demo_velocity.z).length()
		st.climb_vel = demo_velocity.y if absf(demo_velocity.y) > 0.01 else 1.8
		_ship_roll = 0.0
		_ship_pitch = 0.0
		_turn_rate = demo_turn_rate

	_land_dip = move_toward(_land_dip, 0.0, dt * 1.1)
	return st


func _find_nearby_player_pawn(max_dist: float) -> Pawn:
	if pawn == null or not is_instance_valid(pawn) or not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var my_pos := pawn.global_position
	var max_d2 := max_dist * max_dist
	var best: Pawn = null
	var best_d2 := max_d2

	# Primary O(1)-group path: any Pawn in group &"player".
	for node in tree.get_nodes_in_group(&"player"):
		var candidate: Pawn = null
		if node is Pawn:
			candidate = node as Pawn
		elif node != null and node.get_parent() is Pawn:
			candidate = node.get_parent() as Pawn
		if candidate == null or candidate == pawn or not is_instance_valid(candidate) or candidate.dead:
			continue
		var d2 := my_pos.distance_squared_to(candidate.global_position)
		if d2 > 0.12 and d2 < best_d2:
			best_d2 = d2
			best = candidate
	if best != null:
		return best

	# Live-scene fallback: sibling CrewBrain captain ref or active PlayerController camera Pawn.
	for ch in pawn.get_children():
		var cap_v: Variant = ch.get(&"captain")
		if cap_v is Pawn:
			var cap := cap_v as Pawn
			if cap != pawn and is_instance_valid(cap) and not cap.dead:
				var d2 := my_pos.distance_squared_to(cap.global_position)
				if d2 > 0.12 and d2 < best_d2:
					return cap
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null and is_instance_valid(cam):
			var pc := cam.get_parent()
			if pc != null and pc.get_parent() is Pawn:
				var cam_pawn := pc.get_parent() as Pawn
				if cam_pawn != pawn and is_instance_valid(cam_pawn) and not cam_pawn.dead:
					var d2 := my_pos.distance_squared_to(cam_pawn.global_position)
					if d2 > 0.12 and d2 < best_d2:
						return cam_pawn
	return null


# ------------------------------------------------------------------ bone pose helpers

## Fast-out anticipation ramp (0 -> 1 over [0, 1]).
static func _ease_out_pow(t: float, p: float = 2.2) -> float:
	var c := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, p)


## Crisp asymmetric strike snap (0 -> 1 over [t0, t1]) with punchy mid-swing whip.
static func _snap_step(u: float, t0: float, t1: float) -> float:
	var t := clampf((u - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
	var a := pow(t, 1.55)
	var b := pow(1.0 - t, 2.85)
	return clampf(a / maxf(a + b, 1e-6), 0.0, 1.0)


## Early-peaking post-impact follow-through pulse (0 -> peak -> 0 over [t0, t1]).
static func _follow_pulse(u: float, t0: float, t1: float, peak: float = 1.0) -> float:
	if u <= t0 or u >= t1:
		return 0.0
	var t := clampf((u - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
	var rise := pow(t, 0.65)
	var fall := pow(1.0 - t, 1.65)
	return clampf(rise * fall * 3.93, 0.0, 1.0) * peak


func _reset_targets_to_rest() -> void:
	for i in _bone_count:
		_target_rot[i] = _rest_rot[i]
	_target_hips_offset = Vector3.ZERO


static func _safe_slerp(a: Quaternion, b: Quaternion, t: float) -> Quaternion:
	var qa := a.normalized() if a.is_finite() and a.length_squared() > 1e-8 else Quaternion.IDENTITY
	var qb := b.normalized() if b.is_finite() and b.length_squared() > 1e-8 else Quaternion.IDENTITY
	if qa.dot(qb) < 0.0:
		qb = -qb
	var q := qa.slerp(qb, clampf(t, 0.0, 1.0))
	if not q.is_finite() or q.length_squared() < 1e-8:
		return Quaternion.IDENTITY
	return q.normalized()


static func _quat_from_to(from_v: Vector3, to_v: Vector3, fallback_axis: Vector3 = Vector3.RIGHT) -> Quaternion:
	if from_v.length_squared() < 1e-10 or to_v.length_squared() < 1e-10:
		return Quaternion.IDENTITY
	var u := from_v.normalized()
	var v := to_v.normalized()
	var d := clampf(u.dot(v), -1.0, 1.0)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ax := fallback_axis.normalized() if fallback_axis.length_squared() > 1e-6 else Vector3.RIGHT
		return Quaternion(ax, PI)
	var c := u.cross(v)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()


static func _euler_char(pitch: float, yaw: float, roll: float) -> Quaternion:
	return Basis.from_euler(Vector3(pitch, yaw, roll), EULER_ORDER_YXZ).get_rotation_quaternion().normalized()


func _set_char_rot(idx: int, char_delta: Quaternion, w: float = 1.0, local_delta: Quaternion = Quaternion.IDENTITY) -> void:
	if idx < 0 or idx >= _bone_count:
		return
	var gp := _par_grest_rot[idx]
	var q := (gp.inverse() * char_delta * gp * _rest_rot[idx] * local_delta).normalized()
	if not q.is_finite():
		q = _rest_rot[idx]
	if w >= 0.999:
		_target_rot[idx] = q
	elif w > 0.0001:
		_target_rot[idx] = _safe_slerp(_target_rot[idx], q, w)


func _mul_char_rot(idx: int, char_delta: Quaternion) -> void:
	if idx < 0 or idx >= _bone_count:
		return
	var gp := _par_grest_rot[idx]
	var local_d := (gp.inverse() * char_delta * gp).normalized()
	var q := (local_d * _target_rot[idx]).normalized()
	if q.is_finite():
		_target_rot[idx] = q


func _set_arm(
	side: float,
	fwd: float,
	out: float,
	inward_yaw: float,
	elbow_bend: float,
	wrist_pitch: float = 0.0,
	forearm_twist: float = 0.0,
	sh_lift: float = 0.0,
	sh_fwd: float = 0.0,
	w: float = 1.0
) -> void:
	var sh_idx := _b_sh_l if side < 0.0 else _b_sh_r
	var ua_idx := _b_ua_l if side < 0.0 else _b_ua_r
	var fa_idx := _b_fa_l if side < 0.0 else _b_fa_r
	var hd_idx := _b_hand_l if side < 0.0 else _b_hand_r

	var sh_char := _euler_char(0.0, side * sh_fwd, side * sh_lift)
	_set_char_rot(sh_idx, sh_char, w)

	# Adduct ~28 deg inward from A-pose to relaxed neutral hang, then apply anatomical angles.
	var q_neutral := Quaternion(Vector3.BACK, -side * 0.48)
	var ua_char := (
		Quaternion(Vector3.UP, side * inward_yaw)
		* Quaternion(Vector3.RIGHT, fwd)
		* Quaternion(Vector3.BACK, side * out)
		* q_neutral
	).normalized()
	_set_char_rot(ua_idx, ua_char, w)

	var fa_local := (
		Quaternion(Vector3.LEFT, clampf(elbow_bend, -0.18, 2.45))
		* Quaternion(Vector3.UP, side * forearm_twist)
	).normalized()
	_set_char_rot(fa_idx, Quaternion.IDENTITY, w, fa_local)

	var hd_local := Quaternion(Vector3.LEFT, clampf(wrist_pitch, -1.1, 1.1))
	_set_char_rot(hd_idx, Quaternion.IDENTITY, w, hd_local)


func _set_leg(
	side: float,
	thigh_fwd: float,
	thigh_out: float,
	knee_bend: float,
	foot_up: float = 0.0,
	turn_out: float = 0.09,
	w: float = 1.0
) -> void:
	var th_idx := _b_thigh_l if side < 0.0 else _b_thigh_r
	var sh_idx := _b_shin_l if side < 0.0 else _b_shin_r
	var ft_idx := _b_foot_l if side < 0.0 else _b_foot_r

	var th_char := (
		Quaternion(Vector3.UP, -side * turn_out)
		* Quaternion(Vector3.BACK, side * thigh_out)
		* Quaternion(Vector3.RIGHT, thigh_fwd)
	).normalized()
	_set_char_rot(th_idx, th_char, w)

	var sh_char := Quaternion(Vector3.RIGHT, -clampf(knee_bend, 0.0, 2.35))
	_set_char_rot(sh_idx, sh_char, w)

	var ft_char := Quaternion(Vector3.RIGHT, clampf(foot_up, -1.2, 1.1))
	_set_char_rot(ft_idx, ft_char, w)


func _apply_grounded_leg_flexion(st: _AnimState) -> void:
	# Whenever a grounded pose drops the hips (block, heavy, stagger, dig, bail, crouch,
	# stations, etc.), flex any leg whose ankle sinks below its rest floor height using exact
	# 2-bone analytical kinematics with a forward knee pole so knees always bend anatomically
	# backward (never inverted) and boot soles plant flat at y = 0.0.
	if st.dead or not st.grounded:
		return
	if st.mode == Pawn.Mode.SWIM or st.mode == Pawn.Mode.LADDER:
		return
	if st.station_kind == &"sit" or st.station_kind == &"seat" or st.station_kind == &"rowboat_oars":
		return
	if _target_hips_offset.y >= -0.002 or _b_hips < 0:
		return

	var hips_par := skeleton.get_bone_parent(_b_hips)
	var par_gpos := Vector3.ZERO
	var par_grot := Quaternion.IDENTITY
	if hips_par >= 0:
		var par_grest := skeleton.get_bone_global_rest(hips_par)
		par_gpos = par_grest.origin
		par_grot = par_grest.basis.orthonormalized().get_rotation_quaternion().normalized()
	var p_hips := par_gpos + par_grot * (_rest_pos[_b_hips] + _target_hips_offset)
	var q_hips_g := (par_grot * _target_rot[_b_hips]).normalized()
	var c_hips := (q_hips_g * _grest_rot[_b_hips].inverse()).normalized()

	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var th_idx := _b_thigh_l if side_i == 0 else _b_thigh_r
		var sh_idx := _b_shin_l if side_i == 0 else _b_shin_r
		var ft_idx := _b_foot_l if side_i == 0 else _b_foot_r
		if th_idx < 0 or sh_idx < 0 or ft_idx < 0:
			continue

		var rest_an_y := _rest_ankle_y_l if side_i == 0 else _rest_ankle_y_r
		var p_hip := p_hips + q_hips_g * _rest_pos[th_idx]
		var q_th_g := (q_hips_g * _target_rot[th_idx]).normalized()
		var p_kn := p_hip + q_th_g * _rest_pos[sh_idx]
		var q_sh_g := (q_th_g * _target_rot[sh_idx]).normalized()
		var p_an := p_kn + q_sh_g * _rest_pos[ft_idx]

		var sink := rest_an_y - p_an.y
		if sink <= 0.002 or p_hip.y <= rest_an_y + 0.08:
			continue

		var l1 := _rest_pos[sh_idx].length()
		var l2 := _rest_pos[ft_idx].length()
		if l1 < 0.05 or l2 < 0.05:
			continue

		var target_an := Vector3(p_an.x, rest_an_y, p_an.z)
		var to_target := target_an - p_hip
		var raw_dist := to_target.length()
		if raw_dist < 1e-4:
			continue
		var d_min := absf(l1 - l2) + 0.06
		var d_max := l1 + l2 - 0.0005
		var d := clampf(raw_dist, d_min, d_max)
		var u := to_target / raw_dist

		# Anatomical forward knee pole (-Z in pelvis heading with gentle outward turnout).
		var fwd_hint := c_hips * Vector3(side * 0.14, 0.0, -1.0)
		fwd_hint.y = 0.0
		if fwd_hint.length_squared() < 1e-6:
			fwd_hint = Vector3(side * 0.14, 0.0, -1.0)
		else:
			fwd_hint = fwd_hint.normalized()

		var bend_dir := fwd_hint - u * fwd_hint.dot(u)
		if bend_dir.length_squared() < 1e-6:
			bend_dir = Vector3(0.0, 0.0, -1.0)
		else:
			bend_dir = bend_dir.normalized()

		var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / maxf(2.0 * l1 * d, 1e-5), -1.0, 1.0)
		var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
		var p_kn_new := p_hip + u * (l1 * cos_a) + bend_dir * (l1 * sin_a)
		var p_an_eff := p_hip + u * d

		var dq_th := _quat_from_to(p_kn - p_hip, p_kn_new - p_hip)
		var q_th_g_new := (dq_th * q_th_g).normalized()
		var new_th_local := (q_hips_g.inverse() * q_th_g_new).normalized()
		if new_th_local.is_finite():
			_target_rot[th_idx] = new_th_local

		var q_sh_g_mid := (q_th_g_new * _target_rot[sh_idx]).normalized()
		var mid_sh_vec := q_sh_g_mid * _rest_pos[ft_idx]
		var dq_sh := _quat_from_to(mid_sh_vec, p_an_eff - p_kn_new)
		var q_sh_g_new := (dq_sh * q_sh_g_mid).normalized()
		var new_sh_local := (q_th_g_new.inverse() * q_sh_g_new).normalized()
		if new_sh_local.is_finite():
			_target_rot[sh_idx] = new_sh_local

		# Counter-pitch ankle so boot sole stays level on the deck at y = 0.0.
		var q_ft_g_mid := (q_sh_g_new * _target_rot[ft_idx]).normalized()
		var c_ft_mid := (q_ft_g_mid * _grest_rot[ft_idx].inverse()).normalized()
		var dq_shin_added := (q_sh_g_new * q_sh_g.inverse()).normalized()
		var dq_ft_counter := dq_shin_added.inverse()
		var dq_ft_flat := _quat_from_to(c_ft_mid * Vector3.UP, Vector3.UP)
		var flat_w := smoothstep(0.003, 0.025, sink)
		var dq_ft := _safe_slerp(dq_ft_counter, dq_ft_flat, flat_w)
		var q_ft_g_new := (dq_ft * q_ft_g_mid).normalized()
		var new_ft_local := (q_sh_g_new.inverse() * q_ft_g_new).normalized()
		if new_ft_local.is_finite():
			_target_rot[ft_idx] = new_ft_local


# ------------------------------------------------------------------ locomotion modes

func _pose_walk(dt: float, st: _AnimState, snap: bool = false) -> void:
	var target_move := clampf(st.horiz_speed / (st.walk_ref * 0.72), 0.0, 1.0)
	var target_sprint := clampf((st.horiz_speed - st.walk_ref * 1.05) / maxf(st.sprint_ref - st.walk_ref, 0.5), 0.0, 1.0)
	if not st.sprint:
		target_sprint = 0.0
	var target_crouch := 1.0 if st.crouched else 0.0

	_move_blend = move_toward(_move_blend, target_move, dt * 8.0)
	_sprint_blend = move_toward(_sprint_blend, target_sprint, dt * 6.0)
	_crouch_blend = move_toward(_crouch_blend, target_crouch, dt * 9.0)

	if not st.grounded:
		var air_decay := 1.0 if snap else (1.0 - exp(-4.5 * dt))
		_gaze_yaw = lerpf(_gaze_yaw, 0.0, air_decay)
		_gaze_pitch = lerpf(_gaze_pitch, 0.0, air_decay)
		_pose_airborne(st)
		return

	# Advance stride cycle proportionally to ground speed (reverses when backpedaling).
	var dir_sign := -1.0 if st.fwd_speed < -0.35 else 1.0
	var stride_rate := lerpf(2.35, 2.05, _sprint_blend)
	if _move_blend > 0.02:
		_walk_phase = fmod(_walk_phase + dir_sign * st.horiz_speed * stride_rate * dt + TAU * 4.0, TAU)

	# Organic multi-harmonic idle breathing & unhurried pirate weight-shift sway.
	var breath := (sin(_time * 1.9) + 0.35 * sin(_time * 3.8)) * 0.78
	var sway := sin(_time * 0.65)
	var sp := sin(_walk_phase)
	var cp := cos(_walk_phase)
	var mv := _move_blend
	var spr := _sprint_blend
	var cr := _crouch_blend
	var idle_w := 1.0 - mv

	# Living "sea legs" deck counter-balance & walk turn-lean banking.
	var sea_roll := clampf(st.ship_roll * 0.68, -0.14, 0.14)
	var sea_pitch := clampf(st.ship_pitch * 0.42, -0.10, 0.10)
	var sea_crouch := minf(absf(st.ship_roll) + absf(st.ship_pitch) * 0.6, 0.45) * 0.045
	var turn_scale := mv * lerpf(0.68, 1.0, spr)
	var turn_bank := clampf(st.turn_rate * 0.055, -0.10, 0.10) * turn_scale
	var head_turn_lead := clampf(st.turn_rate * 0.095, -0.18, 0.18) * turn_scale

	# ---- Hips bounce, lateral weight-shift, crouch drop & landing compression ----
	var stride_bounce := (absf(sp) * lerpf(0.042, 0.072, spr) - lerpf(0.028, 0.048, spr)) * mv
	var crouch_drop := -0.36 * cr
	var idle_settle := -0.018 + breath * 0.005 - sea_crouch
	var hip_y := lerpf(idle_settle, stride_bounce - sea_crouch * 0.5, mv) + crouch_drop - _land_dip
	var hip_x := sway * 0.022 * idle_w + sp * 0.024 * mv
	_target_hips_offset = Vector3(hip_x, hip_y, 0.0)

	var strafe_lean := clampf(st.right_speed / st.walk_ref, -1.0, 1.0) * 0.09
	var hips_pitch := -lerpf(0.02, lerpf(0.07, 0.14, spr), mv) - 0.14 * cr - _land_dip * 0.5 + sea_pitch * 0.15
	var hips_yaw := sp * lerpf(0.08, 0.14, spr) * mv + sway * 0.032 * idle_w
	var hips_roll := (
		-sp * lerpf(0.048, 0.068, spr) * mv
		- strafe_lean
		+ turn_bank * 0.45
		+ sway * 0.016 * idle_w
		- sea_roll * 0.14 * idle_w
	)
	_set_char_rot(_b_hips, _euler_char(hips_pitch, hips_yaw, hips_roll))

	# ---- Spine, Chest, Neck, Head ----
	var spine_pitch := -lerpf(0.0, lerpf(0.05, 0.16, spr), mv) - 0.22 * cr + breath * 0.020 * idle_w + sea_pitch * 0.45
	var chest_pitch := -lerpf(0.0, lerpf(0.04, 0.12, spr), mv) - 0.18 * cr + breath * 0.028 * idle_w + sea_pitch * 0.55
	var chest_yaw := -sp * lerpf(0.16, 0.28, spr) * mv - sway * 0.038 * idle_w
	var chest_roll := sp * lerpf(0.035, 0.055, spr) * mv
	var torso_roll_extra := sea_roll + turn_bank * 0.55 - sway * 0.020 * idle_w
	_set_char_rot(_b_spine, _euler_char(spine_pitch, chest_yaw * 0.45, chest_roll * 0.45 + torso_roll_extra * 0.45))
	_set_char_rot(_b_chest, _euler_char(chest_pitch, chest_yaw * 0.55, chest_roll * 0.55 + torso_roll_extra * 0.55))

	# Subtle idle Captain glance (within 7.5 m) or calm horizon scan when stationary.
	var want_gaze_yaw := 0.0
	var want_gaze_pitch := 0.0
	var horizon_scan := (sin(_time * 0.62) * 0.065 + sin(_time * 0.27) * 0.030) * idle_w
	if mv < 0.12 and not st.dead and _action == &"":
		want_gaze_yaw = horizon_scan
		if not manual_mode and pawn != null and is_instance_valid(pawn):
			var target_p := _find_nearby_player_pawn(7.5)
			if target_p != null:
				var to_tgt := target_p.eye_position() - pawn.eye_position()
				var fwd_v := pawn.facing()
				var right_v := Vector3(-fwd_v.z, 0.0, fwd_v.x)
				var f_comp := to_tgt.dot(fwd_v)
				var r_comp := to_tgt.dot(right_v)
				var raw_yaw := atan2(-r_comp, f_comp)
				if absf(raw_yaw) < 1.85:
					var h_dist := sqrt(f_comp * f_comp + r_comp * r_comp)
					want_gaze_yaw = clampf(raw_yaw, -0.45, 0.45)
					want_gaze_pitch = clampf(atan2(to_tgt.y, maxf(h_dist, 0.25)), -0.20, 0.20)
	var gaze_alpha := 1.0 if snap else (1.0 - exp(-4.5 * dt))
	_gaze_yaw = lerpf(_gaze_yaw, want_gaze_yaw, gaze_alpha)
	_gaze_pitch = lerpf(_gaze_pitch, want_gaze_pitch, gaze_alpha)
	var eff_gaze_yaw := clampf(_gaze_yaw, -0.45, 0.45) * idle_w
	var eff_gaze_pitch := clampf(_gaze_pitch, -0.20, 0.20) * idle_w

	# Counter-pitch head/neck so eyes stay level during sprint, crouch, & swells while leading turns.
	var head_counter := -(hips_pitch + spine_pitch + chest_pitch) * 0.72
	var head_roll_stab := -sea_roll * 0.35 + sway * 0.024 * idle_w
	_set_char_rot(_b_neck, _euler_char(
		head_counter * 0.38 + eff_gaze_pitch * 0.38,
		-chest_yaw * 0.25 + eff_gaze_yaw * 0.38 + head_turn_lead * 0.38,
		head_roll_stab * 0.35
	))
	_set_char_rot(_b_head, _euler_char(
		head_counter * 0.62 + breath * 0.015 * idle_w + eff_gaze_pitch * 0.62,
		-chest_yaw * 0.35 + eff_gaze_yaw * 0.62 + head_turn_lead * 0.62,
		head_roll_stab * 0.65
	))

	# ---- Legs (Left & Right, widening stance subtly on rolling ship decks) ----
	var swing_amp := lerpf(0.56, 0.94, spr) * lerpf(1.0, 0.72, cr)
	var knee_lift := lerpf(0.76, 1.24, spr)
	var sea_stance := minf(0.18 * absf(st.ship_roll), 0.075)
	var base_thigh_out := lerpf(0.08, 0.04, mv) + 0.08 * cr + sea_stance
	var base_knee := 0.08 + 1.38 * cr + _land_dip * 2.2
	var base_thigh_fwd := 0.04 + 0.74 * cr + _land_dip * 1.1

	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var s := sp if side_i == 0 else -sp
		var c := cp if side_i == 0 else -cp
		var th_fwd := base_thigh_fwd + s * swing_amp * mv
		var lift := maxf(0.0, c) * knee_lift * mv
		var kn_bend := base_knee + lift + maxf(0.0, -s) * 0.22 * mv
		var ft_up := (0.64 * cr + _land_dip * 1.0) - s * 0.24 * mv + maxf(0.0, c) * 0.16 * mv
		var turnout := lerpf(0.12, 0.05, mv) + 0.06 * cr
		_set_leg(side, th_fwd, base_thigh_out, kn_bend, ft_up, turnout)

	# ---- Arms (jaunty counter-swing, athletic sprint pump, guarded crouch) ----
	var is_powder := visual != null and visual.get_archetype() == &"drowned_powder"
	var arm_amp := lerpf(0.50, 0.96, spr) * lerpf(1.0, 0.65, cr)
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var s := -sp if side_i == 0 else sp # opposite to same-side leg
		var idle_fwd := 0.14 if side > 0.0 else -0.02
		var idle_out := (0.06 if side > 0.0 else 0.10) + breath * 0.015 + sea_stance * 0.45
		var idle_elb := 0.42 if side > 0.0 else 0.30

		var walk_fwd := s * arm_amp + lerpf(0.04, 0.24, spr) + 0.28 * cr
		var walk_out := lerpf(0.08, 0.16, spr) + 0.12 * cr
		var walk_inward := lerpf(0.04, 0.22, spr) * maxf(0.0, s) + 0.12 * cr
		var walk_elb := lerpf(0.32 + maxf(0.0, s) * 0.36, 1.28 + maxf(0.0, s) * 0.34, spr) + 0.65 * cr

		var fwd := lerpf(idle_fwd + 0.26 * cr, walk_fwd, mv)
		var out := lerpf(idle_out + 0.14 * cr, walk_out, mv)
		var inward := lerpf((0.06 if side > 0.0 else 0.02) + 0.12 * cr, walk_inward, mv)
		var elb := lerpf(idle_elb + 0.72 * cr, walk_elb, mv)
		var sh_l := breath * 0.028 * idle_w + 0.05 * spr * mv
		if is_powder and side > 0.0:
			# Powder-Carrier braces his right arm up to hold the explosive keg on his right shoulder!
			_set_arm(1.0, 1.18 + s * 0.06 * mv, 0.42, 0.24, 1.72, -0.18, 0.15, 0.16, 0.08)
		else:
			_set_arm(side, fwd, out, inward, elb, 0.0, 0.0, sh_l, s * 0.08 * mv)


func _pose_airborne(st: _AnimState) -> void:
	var rise := clampf(st.vert_vel / 6.5, -1.0, 1.0)
	var up_t := smoothstep(-0.2, 0.7, rise)
	var flap := sin(_time * 8.0) * 0.12 * (1.0 - up_t)

	_target_hips_offset = Vector3(0.0, lerpf(-0.04, 0.08, up_t), 0.0)
	_set_char_rot(_b_hips, _euler_char(lerpf(-0.14, 0.08, up_t), 0.0, 0.0))
	_set_char_rot(_b_spine, _euler_char(lerpf(-0.12, 0.06, up_t), 0.0, 0.0))
	_set_char_rot(_b_chest, _euler_char(lerpf(-0.08, 0.08, up_t), 0.06, 0.0))
	_set_char_rot(_b_neck, _euler_char(0.08, 0.0, 0.0))
	_set_char_rot(_b_head, _euler_char(lerpf(-0.12, 0.14, up_t), 0.0, 0.0))

	# Rising: athletic tucked front leg & trailing rear leg. Falling: bracing spread legs.
	_set_leg(-1.0, lerpf(0.32 + flap, 0.76, up_t), 0.12, lerpf(0.55, 1.18, up_t), lerpf(-0.25, -0.35, up_t))
	_set_leg(1.0, lerpf(-0.12 - flap, -0.26, up_t), 0.12, lerpf(0.35, 0.56, up_t), -0.30)

	# Arms flung wide & high for jump energy / windmilling balance on fall.
	_set_arm(-1.0, lerpf(0.38, 0.92, up_t), lerpf(0.86 + flap, 0.52, up_t), -0.10, lerpf(0.52, 0.74, up_t), 0.0, 0.0, 0.16)
	_set_arm(1.0, lerpf(0.28, 0.68, up_t), lerpf(0.88 - flap, 0.58, up_t), -0.10, lerpf(0.48, 0.62, up_t), 0.0, 0.0, 0.16)


func _pose_swim(dt: float, st: _AnimState) -> void:
	var moving := clampf(st.horiz_speed / 1.4, 0.0, 1.0)
	_swim_move_blend = move_toward(_swim_move_blend, moving, dt * 4.5)
	var freq := lerpf(3.4, 6.2 if st.sprint else 4.8, _swim_move_blend)
	_swim_phase = fmod(_swim_phase + freq * dt, TAU)

	var m := _swim_move_blend
	var s := sin(_swim_phase)
	var kick_s := sin(_swim_phase * 2.0)

	# Horizontal belly-down pitch when swimming forward, upright bobbing when treading water.
	var pitch_body := lerpf(-0.26, -1.24, m)
	var roll_body := s * 0.24 * m
	_target_hips_offset = Vector3(0.0, lerpf(0.04 + sin(_time * 2.4) * 0.04, 0.24, m), 0.0)
	_set_char_rot(_b_hips, _euler_char(pitch_body, 0.0, roll_body))
	_set_char_rot(_b_spine, _euler_char(lerpf(0.06, 0.10, m), -s * 0.10 * m, -roll_body * 0.25))
	_set_char_rot(_b_chest, _euler_char(lerpf(0.08, 0.14, m), -s * 0.16 * m, -roll_body * 0.25))

	# Keep head tilted up above water surface!
	var head_up := lerpf(0.18, 0.86, m)
	_set_char_rot(_b_neck, _euler_char(head_up * 0.42, 0.0, 0.0))
	_set_char_rot(_b_head, _euler_char(head_up * 0.58, -s * 0.12 * m, 0.0))

	# Alternating freestyle crawl arm strokes blended with treading-water sculling.
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var ph := _swim_phase if side_i == 0 else (_swim_phase + PI)
		var sp_a := sin(ph)
		var cp_a := cos(ph)

		# Crawl: reach overhead (+2.25) -> pull down through water (-0.25) -> elbow-bent recovery out wide
		var crawl_fwd := 0.95 + sp_a * 1.28
		var crawl_out := 0.34 + maxf(0.0, cp_a) * 0.72
		var crawl_elb := 0.32 + maxf(0.0, cp_a) * 0.95
		var crawl_in := maxf(0.0, -cp_a) * 0.26

		# Tread: sculling wide in front
		var tread_fwd := 0.46 + sp_a * 0.28
		var tread_out := 0.68 + cp_a * 0.24
		var tread_elb := 0.58 + maxf(0.0, -sp_a) * 0.25

		_set_arm(
			side,
			lerpf(tread_fwd, crawl_fwd, m),
			lerpf(tread_out, crawl_out, m),
			lerpf(0.10, crawl_in, m),
			lerpf(tread_elb, crawl_elb, m),
			-0.18,
			0.0,
			0.14 * m
		)

	# Alternating flutter kick (swimming) / scissor tread kick (stationary).
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var ks := kick_s if side_i == 0 else -kick_s
		var tread_k := s if side_i == 0 else -s
		var th_fwd := lerpf(0.28 + tread_k * 0.38, -0.06 + ks * 0.32, m)
		var kn_bend := lerpf(0.62 + maxf(0.0, -tread_k) * 0.45, 0.26 + maxf(0.0, -ks) * 0.42, m)
		var ft_up := lerpf(-0.35, -0.62, m)
		_set_leg(side, th_fwd, 0.08, kn_bend, ft_up, 0.04)


func _pose_ladder(dt: float, st: _AnimState) -> void:
	var climb_speed := st.climb_vel
	if absf(climb_speed) > 0.08:
		_ladder_phase = fmod(_ladder_phase + climb_speed * 3.6 * dt + TAU * 4.0, TAU)

	var s := sin(_ladder_phase)
	var c := cos(_ladder_phase)

	_target_hips_offset = Vector3(s * 0.035, -0.06 + absf(c) * 0.04, 0.03)
	_set_char_rot(_b_hips, _euler_char(-0.10, s * 0.08, -s * 0.06))
	_set_char_rot(_b_spine, _euler_char(-0.08, -s * 0.06, s * 0.04))
	_set_char_rot(_b_chest, _euler_char(-0.06, -s * 0.12, s * 0.05))
	_set_char_rot(_b_neck, _euler_char(0.14, 0.0, 0.0))
	_set_char_rot(_b_head, _euler_char(0.22, 0.0, 0.0))

	# Alternating hand reach high -> pull low; opposite foot steps up!
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var ph := s if side_i == 0 else -s
		var arm_fwd := 1.72 + ph * 0.62
		var arm_elb := 0.85 - ph * 0.50
		_set_arm(side, arm_fwd, 0.16, 0.14, arm_elb, 0.25, 0.0, 0.12 + maxf(0.0, ph) * 0.14)

		# Opposite leg rises when hand reaches
		var leg_ph := -ph
		var th_fwd := 0.56 + leg_ph * 0.44
		var kn_bend := 0.88 + leg_ph * 0.52
		var ft_up := 0.25 + leg_ph * 0.18
		_set_leg(side, th_fwd, 0.12, kn_bend, ft_up, 0.06)


func _pose_station(dt: float, st: _AnimState) -> void:
	_station_phase = fmod(_station_phase + dt * 3.6, TAU)
	var breath := sin(_time * 2.0)

	match st.station_kind:
		&"helm":
			var steer_active := smoothstep(0.02, 0.10, absf(st.steer))
			var helm_turn := clampf(st.steer, -1.0, 1.0) * steer_active
			var calm_breath := sin(_time * 1.8) * 0.04 * (1.0 - steer_active * 0.65)
			var horizon_scan := (sin(_time * 0.52) * 0.11 + sin(_time * 1.15) * 0.03) * (1.0 - steer_active * 0.85)
			var sea_roll := clampf(st.ship_roll * 0.45, -0.10, 0.10)
			var sea_stance := minf(absf(st.ship_roll) * 0.18, 0.06)

			_target_hips_offset = Vector3(-helm_turn * 0.032, -0.042 - absf(helm_turn) * 0.018 + calm_breath * 0.08, 0.0)
			_set_char_rot(_b_hips, _euler_char(-0.04, -helm_turn * 0.10, -helm_turn * 0.045))
			_set_char_rot(_b_spine, _euler_char(-0.05 + calm_breath * 0.22, -helm_turn * 0.14, -helm_turn * 0.03 + sea_roll * 0.45))
			_set_char_rot(_b_chest, _euler_char(-0.04 + calm_breath * 0.35, -helm_turn * 0.20, -helm_turn * 0.07 + sea_roll * 0.55))
			_set_char_rot(_b_neck, _euler_char(0.05, helm_turn * 0.14 + horizon_scan * 0.40, -sea_roll * 0.25))
			_set_char_rot(_b_head, _euler_char(0.05 + calm_breath * 0.18, helm_turn * 0.20 + horizon_scan * 0.60, -sea_roll * 0.35))
			_set_leg(-1.0, 0.12, 0.16 + sea_stance, 0.18, 0.06, 0.14)
			_set_leg(1.0, 0.06, 0.16 + sea_stance, 0.16, 0.08, 0.14)
			# Hands reach forward & slightly down to grip Q1A waist-to-chest wheel handles (0.843 m hub);
			# calm confident hold with sea-breathing on steady course, expressive weight-shifted turn when steering!
			var arm_out := 0.20 + absf(helm_turn) * 0.05
			_set_arm(
				-1.0,
				0.86 + helm_turn * 0.30 + calm_breath * 0.40,
				arm_out,
				0.14 + helm_turn * 0.07,
				0.56 - helm_turn * 0.16 - calm_breath * 0.30,
				0.08,
				-0.28,
				helm_turn * 0.10 + calm_breath * 0.18,
				helm_turn * 0.12
			)
			_set_arm(
				1.0,
				0.86 - helm_turn * 0.30 + calm_breath * 0.40,
				arm_out,
				0.14 - helm_turn * 0.07,
				0.56 + helm_turn * 0.16 - calm_breath * 0.30,
				0.08,
				-0.28,
				-helm_turn * 0.10 + calm_breath * 0.18,
				-helm_turn * 0.12
			)

		&"rowboat_oars":
			# Seated dinghy rowing stroke: forward catch reach -> weighty lean-back pull -> feathered recovery!
			var effort := clampf(st.row_effort, 0.0, 1.0)
			var cycle_u := clampf(_station_phase / TAU, 0.0, 1.0)
			var drive := _snap_step(cycle_u, 0.16, 0.50) * (1.0 - smoothstep(0.56, 0.96, cycle_u))
			var pull := lerpf(0.38 + breath * 0.05, drive, effort)
			var row_turn := clampf(st.row_turn, -1.0, 1.0)
			var l_pull := clampf(pull + row_turn * 0.22, 0.0, 1.0)
			var r_pull := clampf(pull - row_turn * 0.22, 0.0, 1.0)

			_target_hips_offset = Vector3(0.0, -0.34, 0.04 + pull * 0.04)
			var torso_pitch := lerpf(-0.24, 0.16, pull)
			var torso_yaw := -row_turn * 0.14
			_set_char_rot(_b_hips, _euler_char(torso_pitch * 0.25, torso_yaw * 0.25, 0.0))
			_set_char_rot(_b_spine, _euler_char(torso_pitch * 0.42, torso_yaw * 0.35, 0.0))
			_set_char_rot(_b_chest, _euler_char(torso_pitch * 0.48 + breath * 0.015, torso_yaw * 0.45, 0.0))
			var head_lvl := -(torso_pitch * 1.15) * 0.65
			_set_char_rot(_b_neck, _euler_char(head_lvl * 0.40, -torso_yaw * 0.35, 0.0))
			_set_char_rot(_b_head, _euler_char(head_lvl * 0.60, -torso_yaw * 0.45 + sin(_time * 0.55) * 0.05, 0.0))
			# Seated knee bend planted cleanly on rowboat duckboards.
			_set_leg(-1.0, 1.32, 0.18, 1.38, 0.14, 0.12)
			_set_leg(1.0, 1.32, 0.18, 1.38, 0.14, 0.12)
			_set_arm(
				-1.0,
				lerpf(1.22, 0.48, l_pull),
				lerpf(0.22, 0.34, l_pull),
				lerpf(0.08, -0.04, l_pull),
				lerpf(0.28, 1.40, l_pull),
				lerpf(-0.16, 0.22, l_pull),
				-0.25,
				lerpf(0.02, 0.08, l_pull),
				lerpf(0.14, -0.12, l_pull)
			)
			_set_arm(
				1.0,
				lerpf(1.22, 0.48, r_pull),
				lerpf(0.22, 0.34, r_pull),
				lerpf(0.08, -0.04, r_pull),
				lerpf(0.28, 1.40, r_pull),
				lerpf(-0.16, 0.22, r_pull),
				-0.25,
				lerpf(0.02, 0.08, r_pull),
				lerpf(0.14, -0.12, r_pull)
			)

		&"sail_length":
			# Hand-over-hand vertical halyard hauling
			var s := sin(_station_phase * 1.35)
			_target_hips_offset = Vector3(0.0, -0.07 + absf(s) * 0.03, 0.0)
			_set_char_rot(_b_hips, _euler_char(0.04, 0.18, 0.0))
			_set_char_rot(_b_spine, _euler_char(0.06 + s * 0.06, -0.08, 0.0))
			_set_char_rot(_b_chest, _euler_char(0.08, s * 0.16, s * 0.06))
			_set_char_rot(_b_neck, _euler_char(0.18, 0.0, 0.0))
			_set_char_rot(_b_head, _euler_char(0.28, -0.08, 0.0))
			_set_leg(-1.0, 0.28, 0.14, 0.34, 0.08, 0.10)
			_set_leg(1.0, -0.18, 0.14, 0.28, 0.10, 0.14)
			_set_arm(-1.0, 1.38 + s * 0.72, 0.12, 0.28, 0.92 - s * 0.48, 0.20, -0.30, maxf(0.0, s) * 0.16)
			_set_arm(1.0, 1.38 - s * 0.72, 0.12, 0.28, 0.92 + s * 0.48, 0.20, -0.30, maxf(0.0, -s) * 0.16)

		&"sail_angle":
			# Diagonal brace-line tug leaning back
			var s := sin(_station_phase * 1.2)
			_target_hips_offset = Vector3(0.0, -0.10, 0.04)
			_set_char_rot(_b_hips, _euler_char(0.10, -0.22, 0.0))
			_set_char_rot(_b_spine, _euler_char(0.12 - s * 0.06, 0.12, 0.0))
			_set_char_rot(_b_chest, _euler_char(0.10, 0.16 + s * 0.22, -0.05))
			_set_char_rot(_b_neck, _euler_char(-0.08, -0.10, 0.0))
			_set_char_rot(_b_head, _euler_char(-0.06, -0.12, 0.0))
			_set_leg(-1.0, 0.36, 0.16, 0.46, 0.10, 0.12)
			_set_leg(1.0, -0.24, 0.16, 0.34, 0.12, 0.16)
			_set_arm(-1.0, 0.92 + s * 0.42, 0.18, 0.24, 0.72 - s * 0.45, 0.15, -0.20)
			_set_arm(1.0, 0.92 - s * 0.42, 0.18, 0.24, 0.72 + s * 0.45, 0.15, -0.20)

		&"anchor":
			# Bracing & pushing capstan bar with heavy march
			var s := sin(_station_phase * 1.15)
			var c := cos(_station_phase * 1.15)
			_target_hips_offset = Vector3(0.0, -0.14 + absf(s) * 0.04, -0.04)
			_set_char_rot(_b_hips, _euler_char(-0.18, 0.0, -s * 0.04))
			_set_char_rot(_b_spine, _euler_char(-0.22, 0.0, 0.0))
			_set_char_rot(_b_chest, _euler_char(-0.14, -s * 0.08, 0.0))
			_set_char_rot(_b_neck, _euler_char(0.18, 0.0, 0.0))
			_set_char_rot(_b_head, _euler_char(0.24, 0.0, 0.0))
			_set_leg(-1.0, 0.24 + s * 0.42, 0.12, 0.48 + maxf(0.0, c) * 0.35, 0.18)
			_set_leg(1.0, 0.24 - s * 0.42, 0.12, 0.48 + maxf(0.0, -c) * 0.35, 0.18)
			_set_arm(-1.0, 1.38, 0.14, 0.08, 0.28, -0.35, 0.0, 0.08, 0.14)
			_set_arm(1.0, 1.38, 0.14, 0.08, 0.28, -0.35, 0.0, 0.08, 0.14)

		&"cannon":
			# Low combat-ready gunnery crouch behind breech
			_target_hips_offset = Vector3(0.0, -0.19 + breath * 0.008, 0.0)
			_set_char_rot(_b_hips, _euler_char(-0.14, -0.22, 0.0))
			_set_char_rot(_b_spine, _euler_char(-0.16, 0.12, 0.0))
			_set_char_rot(_b_chest, _euler_char(-0.12 + breath * 0.02, 0.18, 0.0))
			_set_char_rot(_b_neck, _euler_char(0.16, -0.06, 0.0))
			_set_char_rot(_b_head, _euler_char(0.24, -0.04, 0.06))
			_set_leg(-1.0, 0.56, 0.18, 0.92, 0.34, 0.14)
			_set_leg(1.0, 0.34, 0.20, 0.82, 0.40, 0.20)
			_set_arm(-1.0, 1.05, 0.14, 0.16, 0.52, 0.12)
			_set_arm(1.0, 0.58, 0.34, -0.12, 1.15, 0.15)

		&"bilge":
			# Rhythmic stoop-and-heave bailing cycle
			var s := sin(_station_phase * 1.3)
			var dip := smoothstep(-0.2, 0.85, -s)
			_target_hips_offset = Vector3(0.0, -0.08 - dip * 0.16, 0.0)
			_set_char_rot(_b_hips, _euler_char(-0.10 - dip * 0.22, s * 0.14, 0.0))
			_set_char_rot(_b_spine, _euler_char(-0.14 - dip * 0.26, s * 0.18, 0.0))
			_set_char_rot(_b_chest, _euler_char(-0.10 - dip * 0.20, s * 0.22, -s * 0.06))
			_set_char_rot(_b_neck, _euler_char(0.14 + dip * 0.16, 0.0, 0.0))
			_set_char_rot(_b_head, _euler_char(0.12 + dip * 0.18, -s * 0.12, 0.0))
			_set_leg(-1.0, 0.24 + dip * 0.32, 0.16, 0.42 + dip * 0.48, 0.18 + dip * 0.16)
			_set_leg(1.0, 0.16 + dip * 0.28, 0.16, 0.38 + dip * 0.44, 0.18 + dip * 0.16)
			var a_fwd := lerpf(1.22, 0.54, dip)
			var a_elb := lerpf(0.74, 0.34, dip)
			_set_arm(-1.0, a_fwd, 0.14, 0.28, a_elb, 0.18)
			_set_arm(1.0, a_fwd, 0.14, 0.28, a_elb, 0.18)

		&"map_table":
			# Leaning forward over chart table, scanning map
			var scan := sin(_time * 0.85) * 0.18
			_target_hips_offset = Vector3(0.0, -0.06, 0.0)
			_set_char_rot(_b_hips, _euler_char(-0.10, 0.0, 0.0))
			_set_char_rot(_b_spine, _euler_char(-0.22, scan * 0.18, 0.0))
			_set_char_rot(_b_chest, _euler_char(-0.20 + breath * 0.015, scan * 0.22, 0.0))
			_set_char_rot(_b_neck, _euler_char(-0.14, scan * 0.30, 0.0))
			_set_char_rot(_b_head, _euler_char(-0.28, scan * 0.45, scan * 0.08))
			_set_leg(-1.0, 0.16, 0.14, 0.26, 0.10, 0.12)
			_set_leg(1.0, 0.08, 0.14, 0.22, 0.10, 0.12)
			_set_arm(-1.0, 0.82, 0.26, 0.06, 0.34, -0.45)
			_set_arm(1.0, 0.86, 0.24, 0.10, 0.38, -0.45)

		_:
			# Generic alert station stance
			_target_hips_offset = Vector3(0.0, -0.04, 0.0)
			_set_char_rot(_b_hips, _euler_char(-0.04, 0.0, 0.0))
			_set_char_rot(_b_spine, _euler_char(-0.04, 0.0, 0.0))
			_set_char_rot(_b_chest, _euler_char(-0.02 + breath * 0.02, 0.0, 0.0))
			_set_leg(-1.0, 0.10, 0.14, 0.16, 0.06)
			_set_leg(1.0, 0.04, 0.14, 0.14, 0.06)
			_set_arm(-1.0, 0.86, 0.16, 0.16, 0.65)
			_set_arm(1.0, 0.86, 0.16, 0.16, 0.65)


func _pose_death(parent_already_pitched: bool) -> void:
	if parent_already_pitched:
		# Pawn._post_tick already rotated Visual by -PI/2 around X and lifted it +0.3 m.
		_target_hips_offset = Vector3(0.0, -0.04, 0.10)
		_set_char_rot(_b_hips, _euler_char(0.04, 0.08, -0.06))
	else:
		# Standalone collapse straight down onto the deck.
		_target_hips_offset = Vector3(0.0, -0.74, 0.0)
		_set_char_rot(_b_hips, _euler_char(-1.46, 0.10, -0.08))

	_set_char_rot(_b_spine, _euler_char(-0.08, 0.06, -0.08))
	_set_char_rot(_b_chest, _euler_char(-0.06, 0.10, -0.06))
	_set_char_rot(_b_neck, _euler_char(-0.12, 0.18, -0.14))
	_set_char_rot(_b_head, _euler_char(-0.16, 0.34, -0.24))

	_set_leg(-1.0, 0.18, 0.22, 0.42, -0.35, 0.28)
	_set_leg(1.0, 0.04, 0.16, 0.16, -0.45, 0.24)
	_set_arm(-1.0, 0.14, 0.88, -0.18, 0.36, -0.20, 0.25)
	_set_arm(1.0, 0.26, 0.62, -0.08, 0.64, -0.15, -0.20)


# ------------------------------------------------------------------ overlays

func _apply_look_pitch(st: _AnimState) -> void:
	var p := clampf(st.look_pitch, -1.05, 1.05)
	if absf(p) < 0.001:
		return
	var scale := 0.35 if st.mode == Pawn.Mode.SWIM else 1.0
	var sp := p * scale
	_mul_char_rot(_b_spine, _euler_char(sp * 0.14, 0.0, 0.0))
	_mul_char_rot(_b_chest, _euler_char(sp * 0.18, 0.0, 0.0))
	_mul_char_rot(_b_neck, _euler_char(sp * 0.18, 0.0, 0.0))
	_mul_char_rot(_b_head, _euler_char(sp * 0.48, 0.0, 0.0))


func _layer_carry(w: float) -> void:
	# Both arms cupped forward at waist/chest height physically gripping the carried chest.
	_mul_char_rot(_b_spine, _euler_char(0.08 * w, 0.0, 0.0))
	_mul_char_rot(_b_chest, _euler_char(0.06 * w, 0.0, 0.0))
	_set_arm(-1.0, 0.38, 0.20, 0.22, 1.02, 0.16, -0.32, 0.04, 0.08, w)
	_set_arm(1.0, 0.38, 0.20, 0.22, 1.02, 0.16, -0.32, 0.04, 0.08, w)


# ------------------------------------------------------------------ layered actions (16)

func _tick_and_layer_action(dt: float) -> void:
	if _action == &"":
		return
	var u: float
	var env: float
	if _action_hold:
		u = _action_hold_u
		env = 1.0
	else:
		_action_time += dt
		if _action_time >= _action_dur:
			stop_action()
			return
		u = clampf(_action_time / maxf(_action_dur, 0.001), 0.0, 1.0)
		var fade_in := smoothstep(0.0, 0.10, u)
		var fade_out := 1.0 - smoothstep(0.78, 1.0, u)
		env = fade_in * fade_out
	if env <= 0.001:
		return

	match _action:
		&"slash_1":
			_act_slash_1(u, env)
		&"slash_2":
			_act_slash_2(u, env)
		&"slash_3":
			_act_slash_3(u, env)
		&"heavy":
			_act_heavy(u, env)
		&"block":
			_act_block(u, env)
		&"parry":
			_act_parry(u, env)
		&"stagger":
			_act_stagger(u, env)
		&"aim_pistol":
			_act_aim_pistol(u, env)
		&"fire_pistol":
			_act_fire_pistol(u, env)
		&"dig":
			_act_dig(u, env)
		&"hammer":
			_act_hammer(u, env)
		&"bail":
			_act_bail(u, env)
		&"drink":
			_act_drink(u, env)
		&"play_instrument":
			_act_play_instrument(u, env)
		&"shout":
			_act_shout(u, env)
		&"dodge":
			_act_dodge(u, env)


func _act_slash_1(u: float, w: float) -> void:
	# Multi-phase forehand cleave: coiled high-right windup -> snappy diagonal whip -> follow-through -> recovery!
	var coil := _ease_out_pow(u / 0.22, 2.0)
	var sw := _snap_step(u, 0.20, 0.48)
	var ft := _follow_pulse(u, 0.44, 0.76, 1.0)
	var rec := smoothstep(0.72, 1.0, u)
	var drive := clampf(sw + ft * 0.14 - rec * 0.22, 0.0, 1.16)
	var wind_hold := coil * (1.0 - sw)
	var twist := lerpf(-0.54 * coil, 0.60, drive)
	var pitch := lerpf(0.08 * coil, -0.20, drive)
	_target_hips_offset += Vector3(0.0, (0.015 * wind_hold - 0.045 * sw * (1.0 - rec * 0.5)) * w, -0.025 * sw * (1.0 - rec * 0.5) * w)
	_set_char_rot(_b_spine, _euler_char(pitch * 0.45, twist * 0.42, lerpf(-0.04 * coil, -0.06, drive)), w)
	_set_char_rot(_b_chest, _euler_char(pitch * 0.55, twist * 0.58, lerpf(-0.12 * coil, 0.16, drive)), w)
	_set_char_rot(_b_head, _euler_char(0.06, -twist * 0.45, 0.0), w)
	_set_arm(
		1.0,
		lerpf(1.72, 0.88, drive),
		lerpf(0.80, 0.12, drive),
		lerpf(-0.62, 0.92, drive),
		clampf(lerpf(1.16, 0.30, sw) + ft * 0.12 + rec * 0.18, 0.24, 1.35),
		lerpf(-0.32, 0.50, drive),
		lerpf(-0.45, 0.55, drive),
		0.14 * (1.0 - sw * 0.4),
		lerpf(-0.14, 0.24, drive),
		w
	)
	_set_arm(-1.0, lerpf(0.56, -0.28, drive), lerpf(0.28, 0.66, drive), lerpf(0.20, -0.26, drive), lerpf(0.98, 0.56, drive), 0.0, 0.0, 0.06, 0.0, w)


func _act_slash_2(u: float, w: float) -> void:
	# Multi-phase backhand return: tight left-low coil -> whipping backhand snap -> high-right follow-through -> recovery!
	var coil := _ease_out_pow(u / 0.20, 2.0)
	var sw := _snap_step(u, 0.18, 0.46)
	var ft := _follow_pulse(u, 0.42, 0.76, 1.0)
	var rec := smoothstep(0.72, 1.0, u)
	var drive := clampf(sw + ft * 0.14 - rec * 0.22, 0.0, 1.16)
	var twist := lerpf(0.58 * coil, -0.56, drive)
	_target_hips_offset += Vector3(0.0, (-0.035 * coil * (1.0 - sw) - 0.025 * sw * (1.0 - rec * 0.5)) * w, 0.0)
	_set_char_rot(_b_spine, _euler_char(lerpf(-0.10 * coil, 0.04, drive), twist * 0.42, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lerpf(-0.14 * coil, 0.12, drive), twist * 0.58, lerpf(0.14 * coil, -0.16, drive)), w)
	_set_char_rot(_b_head, _euler_char(0.05, -twist * 0.48, 0.0), w)
	_set_arm(
		1.0,
		lerpf(0.84, 1.56, drive),
		lerpf(0.08, 0.92, drive),
		lerpf(0.96, -0.72, drive),
		clampf(lerpf(1.14, 0.26, sw) + ft * 0.10 + rec * 0.20, 0.24, 1.32),
		lerpf(0.40, -0.32, drive),
		lerpf(0.48, -0.50, drive),
		0.14,
		lerpf(0.22, -0.16, drive),
		w
	)
	_set_arm(-1.0, lerpf(-0.14, 0.66, drive), lerpf(0.56, 0.30, drive), 0.08, 0.74, 0.0, 0.0, 0.04, 0.0, w)


func _act_slash_3(u: float, w: float) -> void:
	# Multi-phase overhead finisher: soaring gather -> explosive vertical chop -> heavy lunge squash -> smooth rise!
	var wind := _ease_out_pow(u / 0.26, 2.1)
	var sw := _snap_step(u, 0.24, 0.52)
	var ft := _follow_pulse(u, 0.48, 0.80, 1.0)
	var rec := smoothstep(0.76, 1.0, u)
	var drive := clampf(sw + ft * 0.12 - rec * 0.24, 0.0, 1.14)
	var twist := lerpf(-0.38 * wind, 0.66, drive)
	var lean := lerpf(0.20 * wind, -0.36, drive)
	var hip_y := (0.035 * wind * (1.0 - sw) - (0.11 * sw + 0.035 * ft) * (1.0 - rec * 0.45)) * w
	var hip_z := (0.02 * wind * (1.0 - sw) - 0.065 * sw * (1.0 - rec * 0.45)) * w
	_target_hips_offset += Vector3(0.0, hip_y, hip_z)
	_set_char_rot(_b_spine, _euler_char(lean * 0.45, twist * 0.40, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lean * 0.55, twist * 0.60, lerpf(-0.12 * wind, 0.18, drive)), w)
	_set_char_rot(_b_head, _euler_char(-lean * 0.55, -twist * 0.45, 0.0), w)
	_set_arm(
		1.0,
		lerpf(2.42, 0.52, drive),
		lerpf(0.40, 0.16, drive),
		lerpf(-0.24, 0.78, drive),
		clampf(lerpf(1.24, 0.22, sw) + ft * 0.10 + rec * 0.24, 0.22, 1.38),
		lerpf(-0.40, 0.60, drive),
		0.26,
		lerpf(0.24, 0.04, drive),
		lerpf(-0.10, 0.26, drive),
		w
	)
	_set_arm(-1.0, lerpf(0.80, -0.46, drive), lerpf(0.42, 0.72, drive), lerpf(0.20, -0.32, drive), lerpf(0.86, 0.46, drive), 0.0, 0.0, 0.10, 0.0, w)


func _act_heavy(u: float, w: float) -> void:
	# Multi-phase telegraphed power cleave: deep coil (0..0.38) -> apex poise -> explosive lunge cleave (0.40..0.64) -> weighty follow-through -> recovery!
	var wind := _ease_out_pow(u / 0.36, 2.2)
	var strike := _snap_step(u, 0.40, 0.64)
	var ft := _follow_pulse(u, 0.60, 0.88, 1.0)
	var rec := smoothstep(0.80, 1.0, u)
	var drive := clampf(strike + ft * 0.12 - rec * 0.24, 0.0, 1.14)
	var twist := lerpf(0.0, -0.76, wind) * (1.0 - strike) + 0.76 * drive
	var pitch := lerpf(0.0, 0.26, wind) * (1.0 - strike) - 0.40 * drive
	var hip_y := (0.045 * wind * (1.0 - strike) - (0.15 * strike + 0.04 * ft) * (1.0 - rec * 0.45)) * w
	_target_hips_offset += Vector3(0.0, hip_y, -0.05 * strike * (1.0 - rec * 0.45) * w)
	_set_char_rot(_b_spine, _euler_char(pitch * 0.45, twist * 0.42, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(pitch * 0.55, twist * 0.58, lerpf(-0.16 * wind, 0.20, drive)), w)
	_set_char_rot(_b_head, _euler_char(-pitch * 0.45, -twist * 0.55, 0.0), w)
	var r_fwd := lerpf(2.30, 0.44, drive)
	var r_out := lerpf(0.90, 0.12, drive)
	var r_in := lerpf(-0.72, 0.98, drive)
	var r_elb := clampf(lerpf(1.30, 0.20, strike) + ft * 0.10 + rec * 0.24, 0.20, 1.40)
	_set_arm(1.0, r_fwd, r_out, r_in, r_elb, lerpf(-0.44, 0.64, drive), 0.36, 0.24 * (1.0 - strike), lerpf(-0.18, 0.28, drive), w)
	_set_arm(-1.0, lerpf(1.18, -0.50, drive), lerpf(0.32, 0.80, drive), lerpf(0.36, -0.36, drive), lerpf(0.68, 0.42, drive), 0.0, 0.0, 0.10, 0.0, w)


func _act_block(u: float, w: float) -> void:
	# Classic swashbuckler cross-guard blade raised diagonally across chest/brow!
	var brace := 1.0 + sin(u * PI) * 0.08
	_target_hips_offset += Vector3(0.0, -0.08 * w, 0.0)
	_set_char_rot(_b_spine, _euler_char(-0.12, -0.26, 0.06), w)
	_set_char_rot(_b_chest, _euler_char(-0.10, -0.28, 0.06), w)
	_set_char_rot(_b_head, _euler_char(0.14, 0.36, -0.06), w)
	_set_arm(1.0, 1.32 * brace, 0.18, 0.64, 1.56, -0.25, -0.45, 0.16, 0.18, w)
	_set_arm(-1.0, 0.88, 0.32, 0.42, 1.18, 0.10, 0.20, 0.10, 0.12, w)


func _act_parry(u: float, w: float) -> void:
	# Crisp upward-outward blade deflection burst from guard!
	var pop := smoothstep(0.12, 0.48, u)
	var twist := lerpf(0.28, -0.46, pop)
	_set_char_rot(_b_spine, _euler_char(lerpf(-0.10, 0.08, pop), twist * 0.4, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lerpf(-0.08, 0.12, pop), twist * 0.6, -0.10 * pop), w)
	_set_char_rot(_b_head, _euler_char(0.06, -twist * 0.5, 0.0), w)
	_set_arm(1.0, lerpf(1.26, 1.88, pop), lerpf(0.16, 0.82, pop), lerpf(0.68, -0.58, pop), lerpf(1.52, 0.44, pop), -0.35, -0.35, 0.20, 0.12, w)
	_set_arm(-1.0, lerpf(0.84, 0.25, pop), lerpf(0.28, 0.64, pop), 0.10, lerpf(1.12, 0.62, pop), 0.0, 0.0, 0.08, 0.0, w)


func _act_stagger(u: float, w: float) -> void:
	# Sharp recoil knockback — chest jolts back, head snaps up, arms fling wide off-balance!
	var peak := sin(smoothstep(0.0, 0.85, u) * PI)
	_target_hips_offset += Vector3(0.0, -0.06 * peak * w, 0.09 * peak * w)
	_set_char_rot(_b_hips, _euler_char(0.16 * peak, 0.14 * peak, -0.10 * peak), w)
	_set_char_rot(_b_spine, _euler_char(0.26 * peak, 0.18 * peak, -0.12 * peak), w)
	_set_char_rot(_b_chest, _euler_char(0.32 * peak, 0.22 * peak, -0.10 * peak), w)
	_set_char_rot(_b_neck, _euler_char(0.22 * peak, 0.0, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.30 * peak, -0.24 * peak, 0.18 * peak), w)
	_set_arm(-1.0, 0.42 * peak, 0.96 * peak, -0.22, 0.55, -0.25, 0.0, 0.22 * peak, -0.14 * peak, w)
	_set_arm(1.0, 0.52 * peak, 0.92 * peak, -0.28, 0.48, -0.25, 0.0, 0.20 * peak, -0.16 * peak, w)


func _act_aim_pistol(u: float, w: float) -> void:
	# Sideways duelist stance: right arm counter-rotated so barrel aims straight down character -Z!
	var steady := sin(u * TAU) * 0.015
	_set_char_rot(_b_spine, _euler_char(0.0, 0.22, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.02, 0.34, 0.0), w)
	_set_char_rot(_b_neck, _euler_char(0.0, -0.22, 0.0), w)
	_set_char_rot(_b_head, _euler_char(-0.04, -0.32, 0.10), w)
	_set_arm(1.0, 1.52 + steady, 0.06, -0.48, 0.14, -0.12, 0.0, 0.08, 0.16, w)
	_set_arm(-1.0, -0.18, 0.34, -0.16, 0.88, 0.0, 0.0, 0.0, -0.10, w)


func _act_fire_pistol(u: float, w: float) -> void:
	# Muzzle kick recoil upward & back from aimed pistol stance, then settles.
	var kick := pow(maxf(0.0, 1.0 - u * 1.35), 1.6) * smoothstep(0.0, 0.12, u)
	_set_char_rot(_b_spine, _euler_char(0.06 * kick, 0.22, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.12 * kick, 0.34 - 0.12 * kick, -0.06 * kick), w)
	_set_char_rot(_b_neck, _euler_char(0.05 * kick, -0.22, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.08 * kick, -0.30, 0.08), w)
	_set_arm(1.0, 1.52 + 0.56 * kick, 0.08 + 0.10 * kick, -0.48, 0.14 + 0.42 * kick, -0.35 * kick, 0.0, 0.14 * kick, 0.16 - 0.14 * kick, w)
	_set_arm(-1.0, -0.22, 0.38, -0.18, 0.92, 0.0, 0.0, 0.0, -0.10, w)


func _act_dig(u: float, w: float) -> void:
	# Multi-phase shovel dig: poised lift -> crisp downward stab -> brief load -> snappy shoulder heave -> recovery!
	var prep := _ease_out_pow(u / 0.16, 2.0)
	var stab := _snap_step(u, 0.14, 0.34)
	var heave := _snap_step(u, 0.46, 0.72)
	var ft := _follow_pulse(u, 0.68, 0.92, 1.0)
	var rec := smoothstep(0.84, 1.0, u)
	var plunge := stab * (1.0 - heave)
	var toss := clampf(heave + ft * 0.14 - rec * 0.25, 0.0, 1.15)
	var lean := 0.06 * prep * (1.0 - stab) - 0.48 * plunge + 0.14 * toss
	var twist := -0.26 * plunge + 0.50 * toss
	_target_hips_offset += Vector3(0.0, (-0.18 * plunge + 0.025 * toss * (1.0 - rec)) * w, -0.04 * plunge * w)
	_set_char_rot(_b_spine, _euler_char(lean * 0.48, twist * 0.45, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lean * 0.52, twist * 0.55, 0.09 * toss), w)
	_set_char_rot(_b_head, _euler_char(-lean * 0.35, -twist * 0.35, 0.0), w)
	_set_arm(
		1.0,
		lerpf(lerpf(0.92, 0.62, stab), 1.44, toss),
		0.16 + 0.04 * ft,
		lerpf(0.32, 0.56, toss),
		clampf(lerpf(0.76, 0.48, stab) * (1.0 - toss) + 1.08 * toss, 0.36, 1.24),
		lerpf(0.24, -0.22, toss),
		0.0,
		0.08 + 0.08 * toss,
		lerpf(0.14, 0.06, toss),
		w
	)
	_set_arm(
		-1.0,
		lerpf(lerpf(0.78, 0.48, stab), 1.28, toss),
		0.22 + 0.05 * ft,
		lerpf(0.38, -0.14, toss),
		clampf(lerpf(0.74, 0.54, stab) * (1.0 - toss) + 0.86 * toss, 0.38, 1.12),
		lerpf(0.20, -0.18, toss),
		0.0,
		0.06 + 0.06 * toss,
		0.10,
		w
	)


func _act_hammer(u: float, w: float) -> void:
	# Multi-phase plank-repair hammering: high cocked backswing -> fast snap nail strike -> crisp rebound -> reset!
	var cock := _ease_out_pow(u / 0.24, 2.0)
	var hit := _snap_step(u, 0.24, 0.44)
	var bounce := _follow_pulse(u, 0.44, 0.72, 1.0)
	var rec := smoothstep(0.72, 1.0, u)
	var drive := clampf(hit - bounce * 0.22 - rec * 0.34, 0.0, 1.06)
	var backswing := cock * (1.0 - hit)
	_target_hips_offset += Vector3(0.0, (-0.038 * hit * (1.0 - bounce * 0.45) * (1.0 - rec * 0.6)) * w, 0.0)
	_set_char_rot(_b_spine, _euler_char(-0.06 + 0.08 * backswing - 0.16 * drive, lerpf(-0.22 * cock, 0.18, drive), 0.0), w)
	_set_char_rot(_b_chest, _euler_char(-0.05 + 0.10 * backswing - 0.16 * drive, lerpf(-0.26 * cock, 0.22, drive), lerpf(-0.06 * backswing, 0.06, drive)), w)
	_set_char_rot(_b_head, _euler_char(0.08, 0.0, 0.0), w)
	_set_arm(
		1.0,
		lerpf(2.18, 0.90, drive),
		lerpf(0.28, 0.12, drive),
		lerpf(-0.16, 0.24, drive),
		clampf(lerpf(1.56, 0.40, drive) + bounce * 0.16, 0.34, 1.66),
		lerpf(-0.44, 0.48, drive),
		0.0,
		0.18 * (1.0 - drive),
		lerpf(-0.06, 0.14, drive),
		w
	)
	_set_arm(-1.0, 0.98 + bounce * 0.05, 0.16, 0.22, 0.52 + bounce * 0.06, -0.25, 0.0, 0.0, 0.12, w)


func _act_bail(u: float, w: float) -> void:
	# Multi-phase bucket bail: brisk low bilge scoop -> loaded pause -> explosive water fling -> flick follow-through -> recovery!
	var stoop := _ease_out_pow(u / 0.26, 2.0)
	var heave := _snap_step(u, 0.36, 0.66)
	var ft := _follow_pulse(u, 0.62, 0.88, 1.0)
	var rec := smoothstep(0.80, 1.0, u)
	var toss := clampf(heave + ft * 0.14 - rec * 0.24, 0.0, 1.14)
	var lean := lerpf(-0.48 * stoop, 0.16, toss)
	var hip_y := (lerpf(-0.18 * stoop, 0.035, toss) + 0.018 * ft) * (1.0 - rec * 0.4) * w
	_target_hips_offset += Vector3(0.0, hip_y, -0.03 * stoop * (1.0 - heave) * w)
	_set_char_rot(_b_spine, _euler_char(lean * 0.48, lerpf(-0.14 * stoop, 0.26, toss), 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lean * 0.52, lerpf(-0.16 * stoop, 0.30, toss), 0.0), w)
	_set_char_rot(_b_head, _euler_char(-lean * 0.40, 0.0, 0.0), w)
	var af := lerpf(0.42, 1.62, toss)
	var ae := clampf(lerpf(0.38, 0.66, heave) + ft * 0.14, 0.34, 0.95)
	var wp := lerpf(0.28, -0.40, toss)
	_set_arm(-1.0, af, 0.16 + 0.04 * ft, 0.28, ae, wp, -0.25, 0.12 * toss, 0.12, w)
	_set_arm(1.0, af, 0.16 + 0.04 * ft, 0.28, ae, wp, -0.25, 0.12 * toss, 0.12, w)


func _act_drink(u: float, w: float) -> void:
	# Multi-phase tankard swig: brisk lift to lips -> hearty head-back gulp with swallow nods -> jaunty flourish lower!
	var lift := _snap_step(u, 0.04, 0.24) * (1.0 - smoothstep(0.70, 0.94, u))
	var gulp := _snap_step(u, 0.22, 0.38) * (1.0 - smoothstep(0.64, 0.82, u))
	var gulp_t := clampf((u - 0.26) / 0.42, 0.0, 1.0)
	var swig_nod := sin(gulp_t * TAU * 1.5) * 0.075 * gulp
	var flourish := _follow_pulse(u, 0.72, 0.96, 1.0)
	_set_char_rot(_b_spine, _euler_char(0.11 * gulp - 0.04 * flourish, -0.07 * lift, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.13 * gulp - 0.05 * flourish, -0.11 * lift, -0.05 * lift), w)
	_set_char_rot(_b_neck, _euler_char(0.17 * gulp + swig_nod * 0.45, 0.0, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.36 * gulp + swig_nod, 0.06 * lift, -0.06 * gulp), w)
	_set_arm(
		1.0,
		0.94 + 0.38 * lift + 0.08 * flourish,
		0.14 + 0.20 * gulp + 0.12 * flourish,
		0.48 * lift - 0.10 * flourish,
		clampf(1.48 + 0.46 * lift - 0.30 * flourish, 0.35, 2.02),
		-0.32 * gulp + swig_nod * 0.8 + 0.14 * flourish,
		-0.42 * lift,
		0.13 * lift,
		0.10 * lift,
		w
	)
	# Off-hand rests jauntily on hip!
	_set_arm(-1.0, 0.12, 0.42 * lift, -0.10, clampf(0.28 + 0.90 * lift, 0.24, 1.28), 0.10, 0.0, 0.0, 0.0, w)


func _act_play_instrument(u: float, w: float) -> void:
	# Jaunty sea-shanty groove with lively pumping hands & head bob!
	var beat := sin(u * TAU * 3.0)
	var bob := sin(u * TAU * 6.0)
	_set_char_rot(_b_spine, _euler_char(-0.04 + bob * 0.03, beat * 0.08, beat * 0.06), w)
	_set_char_rot(_b_chest, _euler_char(0.04 + bob * 0.04, beat * 0.12, beat * 0.08), w)
	_set_char_rot(_b_neck, _euler_char(bob * 0.06, -beat * 0.08, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.06 + bob * 0.10, -beat * 0.12, -beat * 0.12), w)
	var held_kind := _detect_held_shanty_instrument()
	if held_kind == &"hurdy_gurdy":
		# Lower chest/waist hurdy-gurdy hold (~11 cm lower hand clearance below jaw/beard)
		# with left hand cradling the keybox and right hand turning the crank!
		var crank_y := cos(u * TAU * 3.0)
		_set_arm(-1.0, 0.50 + bob * 0.04, 0.14, 0.42, 1.12 + beat * 0.05, 0.24, -0.22, 0.0, 0.08, w)
		_set_arm(1.0, 0.52 + crank_y * 0.06, 0.18 + beat * 0.06, 0.34 - beat * 0.05, 1.14 + beat * 0.10, 0.28, -0.28, 0.0, 0.08, w)
	elif held_kind == &"whistle":
		# Keep bosun's whistle poised near lip/chin height.
		var spread := 0.18 + beat * 0.12
		var inward := 0.36 - beat * 0.12
		_set_arm(-1.0, 0.72 + bob * 0.06, spread, inward, 1.38 + beat * 0.12, 0.15, -0.25, 0.06, 0.10, w)
		_set_arm(1.0, 0.72 - bob * 0.06, spread, inward, 1.38 + beat * 0.12, 0.15, -0.25, 0.06, 0.10, w)
	else:
		# Concertina bellows squeeze & expand rhythm comfortably across mid-chest!
		var spread := 0.18 + beat * 0.14
		var inward := 0.36 - beat * 0.16
		_set_arm(-1.0, 0.66 + bob * 0.06, spread, inward, 1.30 + beat * 0.14, 0.15, -0.25, 0.04, 0.10, w)
		_set_arm(1.0, 0.66 - bob * 0.06, spread, inward, 1.30 + beat * 0.14, 0.15, -0.25, 0.04, 0.10, w)


func _detect_held_shanty_instrument() -> StringName:
	if visual == null or visual.hand_right == null or not is_instance_valid(visual.hand_right):
		return &"concertina"
	for child in visual.hand_right.get_children():
		var lname := String(child.name).to_lower()
		if lname.contains("hurdy_gurdy"):
			return &"hurdy_gurdy"
		if lname.contains("whistle"):
			return &"whistle"
	return &"concertina"


func _act_shout(u: float, w: float) -> void:
	# Heroic pirate rally bellow: chest puffed high, right fist pumped overhead, left hand cupped clear beside jaw!
	var roar := smoothstep(0.08, 0.32, u) * (1.0 - smoothstep(0.74, 0.96, u))
	var vibr := sin(u * TAU * 5.0) * 0.03 * roar
	_set_char_rot(_b_spine, _euler_char(0.14 * roar, -0.10 * roar, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.18 * roar, -0.14 * roar, -0.06 * roar), w)
	_set_char_rot(_b_neck, _euler_char(0.14 * roar, 0.0, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.28 * roar + vibr, 0.08 * roar, 0.0), w)
	# Right arm pumped triumphantly skyward!
	_set_arm(1.0, 2.42 * roar + 0.25, 0.38 * roar + 0.10, -0.14, 0.42 + vibr * 2.0, 0.15, 0.0, 0.26 * roar, 0.0, w)
	# Left hand raised cupped cleanly beside mouth (clear of jaw & coat lapel)!
	_set_arm(-1.0, 1.12 * roar + 0.15, 0.28 * roar, 0.34 * roar, 1.42 * roar + 0.22, 0.20, -0.30, 0.12 * roar, 0.10 * roar, w)


func _act_dodge(u: float, w: float) -> void:
	# Explosive low evasive duck-and-twist sidestep!
	var dip := sin(smoothstep(0.0, 1.0, u) * PI)
	_target_hips_offset += Vector3(0.0, -0.34 * dip * w, 0.0)
	_set_char_rot(_b_hips, _euler_char(-0.24 * dip, 0.32 * dip, -0.16 * dip), w)
	_set_char_rot(_b_spine, _euler_char(-0.26 * dip, 0.24 * dip, -0.12 * dip), w)
	_set_char_rot(_b_chest, _euler_char(-0.20 * dip, 0.28 * dip, -0.10 * dip), w)
	_set_char_rot(_b_head, _euler_char(0.36 * dip, -0.45 * dip, 0.14 * dip), w)
	_set_leg(-1.0, 0.72 * dip, 0.24 * dip, 1.38 * dip, 0.56 * dip, 0.14, w)
	_set_leg(1.0, 0.42 * dip, 0.28 * dip, 1.18 * dip, 0.48 * dip, 0.18, w)
	_set_arm(-1.0, 0.65 * dip, 0.32 * dip, 0.42 * dip, 1.48 * dip, 0.0, 0.0, 0.10 * dip, 0.14 * dip, w)
	_set_arm(1.0, 0.42 * dip, 0.46 * dip, 0.26 * dip, 1.35 * dip, 0.0, 0.0, 0.10 * dip, 0.10 * dip, w)


# ------------------------------------------------------------------ parent scale & carry anchor

func _compensate_parent_scale(st: _AnimState) -> void:
	# Pawn._post_tick squashes Visual.scale.y during crouch; undo that squash on
	# CharacterVisual so the real skeletal knee-bend crouch keeps true proportions.
	if visual == null or manual_mode:
		return
	var psy := st.parent_scale_y
	if psy > 0.25 and absf(psy - 1.0) > 0.002:
		visual.scale.y = 1.0 / psy
	elif absf(visual.scale.y - 1.0) > 0.0001:
		visual.scale.y = 1.0


func _update_carry_anchor(st: _AnimState) -> void:
	if visual == null or visual.carry_anchor == null:
		return
	var base := CharacterVisual.DEFAULT_CARRY_LOCAL
	var bob := _cur_hips_offset.y * 0.65
	var crouch_off := -0.32 if st.crouched else 0.0
	visual.carry_anchor.position = Vector3(base.x, base.y + bob + crouch_off, base.z)
