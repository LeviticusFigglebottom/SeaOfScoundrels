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

var visual: CharacterVisual = null
var pawn: Pawn = null
var skeleton: Skeleton3D = null

var _bone_count: int = 0
var _rest_pos: PackedVector3Array = PackedVector3Array()
var _rest_rot: Array[Quaternion] = []
var _par_grest_rot: Array[Quaternion] = []
var _cur_rot: Array[Quaternion] = []
var _target_rot: Array[Quaternion] = []
var _cur_hips_offset: Vector3 = Vector3.ZERO
var _target_hips_offset: Vector3 = Vector3.ZERO

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

	var st := _sample_state(dt)
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
				_pose_walk(dt, st)

		_apply_look_pitch(st)

		if st.carrying and st.mode != Pawn.Mode.STATION and st.mode != Pawn.Mode.LADDER:
			_carry_blend = 1.0 if snap else move_toward(_carry_blend, 1.0, dt * 8.0)
		else:
			_carry_blend = 0.0 if snap else move_toward(_carry_blend, 0.0, dt * 8.0)
		if _carry_blend > 0.001:
			_layer_carry(_carry_blend)

		_tick_and_layer_action(dt)

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
	_cur_rot.clear()
	_target_rot.clear()
	_cur_hips_offset = Vector3.ZERO
	_target_hips_offset = Vector3.ZERO
	if skeleton == null:
		return

	_bone_count = skeleton.get_bone_count()
	_rest_pos.resize(_bone_count)
	_rest_rot.resize(_bone_count)
	_par_grest_rot.resize(_bone_count)
	_cur_rot.resize(_bone_count)
	_target_rot.resize(_bone_count)

	for i in _bone_count:
		var rest := skeleton.get_bone_rest(i)
		var r_rot := rest.basis.orthonormalized().get_rotation_quaternion().normalized()
		_rest_pos[i] = rest.origin
		_rest_rot[i] = r_rot
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


func _sample_state(dt: float) -> _AnimState:
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
		st.grounded = pawn.is_grounded()
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
		if pawn.platform != null and is_instance_valid(pawn.platform):
			var h: Variant = pawn.platform.get(&"helm")
			if h is float or h is int:
				st.steer = clampf(float(h), -1.0, 1.0)

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
		st.vert_vel = demo_velocity.y
		st.fwd_speed = -demo_velocity.z
		st.right_speed = demo_velocity.x
		st.horiz_speed = Vector2(demo_velocity.x, demo_velocity.z).length()
		st.climb_vel = demo_velocity.y if absf(demo_velocity.y) > 0.01 else 1.8

	_land_dip = move_toward(_land_dip, 0.0, dt * 1.1)
	return st


# ------------------------------------------------------------------ bone pose helpers

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


# ------------------------------------------------------------------ locomotion modes

func _pose_walk(dt: float, st: _AnimState) -> void:
	var target_move := clampf(st.horiz_speed / (st.walk_ref * 0.72), 0.0, 1.0)
	var target_sprint := clampf((st.horiz_speed - st.walk_ref * 1.05) / maxf(st.sprint_ref - st.walk_ref, 0.5), 0.0, 1.0)
	if not st.sprint:
		target_sprint = 0.0
	var target_crouch := 1.0 if st.crouched else 0.0

	_move_blend = move_toward(_move_blend, target_move, dt * 8.0)
	_sprint_blend = move_toward(_sprint_blend, target_sprint, dt * 6.0)
	_crouch_blend = move_toward(_crouch_blend, target_crouch, dt * 9.0)

	if not st.grounded:
		_pose_airborne(st)
		return

	# Advance stride cycle proportionally to ground speed (reverses when backpedaling).
	var dir_sign := -1.0 if st.fwd_speed < -0.35 else 1.0
	var stride_rate := lerpf(2.35, 2.05, _sprint_blend)
	if _move_blend > 0.02:
		_walk_phase = fmod(_walk_phase + dir_sign * st.horiz_speed * stride_rate * dt + TAU * 4.0, TAU)

	var breath := sin(_time * 2.15)
	var sway := sin(_time * 0.95)
	var sp := sin(_walk_phase)
	var cp := cos(_walk_phase)
	var mv := _move_blend
	var spr := _sprint_blend
	var cr := _crouch_blend

	# ---- Hips bounce, lateral shift, crouch drop & landing compression ----
	var stride_bounce := (absf(sp) * lerpf(0.042, 0.072, spr) - lerpf(0.028, 0.048, spr)) * mv
	var crouch_drop := -0.36 * cr
	var idle_settle := -0.014 + breath * 0.006
	var hip_y := lerpf(idle_settle, stride_bounce, mv) + crouch_drop - _land_dip
	var hip_x := sway * 0.016 * (1.0 - mv) + sp * 0.024 * mv
	_target_hips_offset = Vector3(hip_x, hip_y, 0.0)

	var strafe_lean := clampf(st.right_speed / st.walk_ref, -1.0, 1.0) * 0.09
	var hips_pitch := -lerpf(0.02, lerpf(0.07, 0.14, spr), mv) - 0.14 * cr - _land_dip * 0.5
	var hips_yaw := sp * lerpf(0.08, 0.14, spr) * mv + sway * 0.03 * (1.0 - mv)
	var hips_roll := -sp * lerpf(0.048, 0.068, spr) * mv - strafe_lean
	_set_char_rot(_b_hips, _euler_char(hips_pitch, hips_yaw, hips_roll))

	# ---- Spine, Chest, Neck, Head ----
	var spine_pitch := -lerpf(0.0, lerpf(0.05, 0.16, spr), mv) - 0.22 * cr + breath * 0.018 * (1.0 - mv)
	var chest_pitch := -lerpf(0.0, lerpf(0.04, 0.12, spr), mv) - 0.18 * cr + breath * 0.026 * (1.0 - mv)
	var chest_yaw := -sp * lerpf(0.16, 0.28, spr) * mv - sway * 0.035 * (1.0 - mv)
	var chest_roll := sp * lerpf(0.035, 0.055, spr) * mv
	_set_char_rot(_b_spine, _euler_char(spine_pitch, chest_yaw * 0.45, chest_roll * 0.45))
	_set_char_rot(_b_chest, _euler_char(chest_pitch, chest_yaw * 0.55, chest_roll * 0.55))

	# Counter-pitch head/neck so eyes stay level during sprint & crouch.
	var head_counter := -(hips_pitch + spine_pitch + chest_pitch) * 0.72
	var head_scan := sin(_time * 0.62) * 0.06 * (1.0 - mv)
	_set_char_rot(_b_neck, _euler_char(head_counter * 0.38, -chest_yaw * 0.25, 0.0))
	_set_char_rot(_b_head, _euler_char(head_counter * 0.62 + breath * 0.015, head_scan - chest_yaw * 0.35, sway * 0.025 * (1.0 - mv)))

	# ---- Legs (Left & Right) ----
	var swing_amp := lerpf(0.56, 0.94, spr) * lerpf(1.0, 0.72, cr)
	var knee_lift := lerpf(0.76, 1.24, spr)
	var base_thigh_out := lerpf(0.08, 0.04, mv) + 0.08 * cr
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
	var arm_amp := lerpf(0.50, 0.96, spr) * lerpf(1.0, 0.65, cr)
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var s := -sp if side_i == 0 else sp # opposite to same-side leg
		var idle_fwd := 0.08 if side > 0.0 else 0.04
		var idle_out := 0.09 + breath * 0.016
		var idle_elb := 0.32 if side > 0.0 else 0.26

		var walk_fwd := s * arm_amp + lerpf(0.04, 0.24, spr) + 0.28 * cr
		var walk_out := lerpf(0.08, 0.16, spr) + 0.12 * cr
		var walk_inward := lerpf(0.04, 0.22, spr) * maxf(0.0, s) + 0.12 * cr
		var walk_elb := lerpf(0.32 + maxf(0.0, s) * 0.36, 1.28 + maxf(0.0, s) * 0.34, spr) + 0.65 * cr

		var fwd := lerpf(idle_fwd + 0.26 * cr, walk_fwd, mv)
		var out := lerpf(idle_out + 0.14 * cr, walk_out, mv)
		var inward := lerpf(0.12 * cr, walk_inward, mv)
		var elb := lerpf(idle_elb + 0.72 * cr, walk_elb, mv)
		var sh_l := breath * 0.025 * (1.0 - mv) + 0.05 * spr * mv
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
			var steer := st.steer if absf(st.steer) > 0.02 else sin(_time * 1.1) * 0.45
			_target_hips_offset = Vector3(0.0, -0.04, 0.0)
			_set_char_rot(_b_hips, _euler_char(-0.04, -steer * 0.08, -steer * 0.04))
			_set_char_rot(_b_spine, _euler_char(-0.05, -steer * 0.12, 0.0))
			_set_char_rot(_b_chest, _euler_char(-0.04 + breath * 0.02, -steer * 0.16, -steer * 0.05))
			_set_char_rot(_b_neck, _euler_char(0.06, steer * 0.12, 0.0))
			_set_char_rot(_b_head, _euler_char(0.06, steer * 0.14, 0.0))
			_set_leg(-1.0, 0.12, 0.16, 0.18, 0.06, 0.14)
			_set_leg(1.0, 0.06, 0.16, 0.16, 0.08, 0.14)
			# Hands gripping opposite wheel spokes, shifting up/down with helm angle
			_set_arm(-1.0, 1.08 + steer * 0.26, 0.16, 0.14, 0.48 - steer * 0.12, 0.12, -0.25)
			_set_arm(1.0, 1.08 - steer * 0.26, 0.16, 0.14, 0.48 + steer * 0.12, 0.12, -0.25)

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
	# Both arms forward & cupped upward supporting a chest/crate/barrel in front of torso.
	_mul_char_rot(_b_spine, _euler_char(0.08 * w, 0.0, 0.0))
	_mul_char_rot(_b_chest, _euler_char(0.06 * w, 0.0, 0.0))
	_set_arm(-1.0, 0.70, 0.18, 0.24, 1.24, 0.18, -0.35, 0.06, 0.10, w)
	_set_arm(1.0, 0.70, 0.18, 0.24, 1.24, 0.18, -0.35, 0.06, 0.10, w)


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
		var fade_in := smoothstep(0.0, 0.14, u)
		var fade_out := 1.0 - smoothstep(0.80, 1.0, u)
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
	# Energetic forehand cutlass cleave: high-right windup -> sweeping slash across to low-left!
	var sw := smoothstep(0.18, 0.62, u)
	var twist := lerpf(-0.48, 0.56, sw)
	var pitch := lerpf(0.06, -0.18, sw)
	_set_char_rot(_b_spine, _euler_char(pitch * 0.45, twist * 0.42, -0.06 * sw), w)
	_set_char_rot(_b_chest, _euler_char(pitch * 0.55, twist * 0.58, lerpf(-0.10, 0.14, sw)), w)
	_set_char_rot(_b_head, _euler_char(0.06, -twist * 0.45, 0.0), w)
	_set_arm(1.0, lerpf(1.65, 0.92, sw), lerpf(0.75, 0.14, sw), lerpf(-0.55, 0.88, sw), lerpf(1.10, 0.34, sw), lerpf(-0.25, 0.45, sw), lerpf(-0.4, 0.5, sw), 0.12, lerpf(-0.10, 0.22, sw), w)
	_set_arm(-1.0, lerpf(0.52, -0.25, sw), lerpf(0.28, 0.62, sw), lerpf(0.18, -0.25, sw), lerpf(0.95, 0.58, sw), 0.0, 0.0, 0.05, 0.0, w)


func _act_slash_2(u: float, w: float) -> void:
	# Snappy backhand return slash: coiled left-low -> whips across to high-right!
	var sw := smoothstep(0.16, 0.64, u)
	var twist := lerpf(0.54, -0.52, sw)
	_set_char_rot(_b_spine, _euler_char(-0.08, twist * 0.42, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lerpf(-0.12, 0.10, sw), twist * 0.58, lerpf(0.12, -0.14, sw)), w)
	_set_char_rot(_b_head, _euler_char(0.05, -twist * 0.48, 0.0), w)
	_set_arm(1.0, lerpf(0.88, 1.52, sw), lerpf(0.08, 0.88, sw), lerpf(0.92, -0.68, sw), lerpf(1.08, 0.28, sw), lerpf(0.35, -0.25, sw), lerpf(0.45, -0.45, sw), 0.14, lerpf(0.20, -0.14, sw), w)
	_set_arm(-1.0, lerpf(-0.12, 0.62, sw), lerpf(0.55, 0.32, sw), 0.08, 0.72, 0.0, 0.0, 0.04, 0.0, w)


func _act_slash_3(u: float, w: float) -> void:
	# Dramatic overhead lunging finisher cleave with full upper-body drive!
	var sw := smoothstep(0.24, 0.66, u)
	var twist := lerpf(-0.34, 0.62, sw)
	var lean := lerpf(0.16, -0.34, sw)
	_target_hips_offset += Vector3(0.0, lerpf(0.03, -0.10, sw) * w, lerpf(0.02, -0.06, sw) * w)
	_set_char_rot(_b_spine, _euler_char(lean * 0.45, twist * 0.40, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lean * 0.55, twist * 0.60, lerpf(-0.10, 0.16, sw)), w)
	_set_char_rot(_b_head, _euler_char(-lean * 0.55, -twist * 0.45, 0.0), w)
	_set_arm(1.0, lerpf(2.38, 0.58, sw), lerpf(0.38, 0.18, sw), lerpf(-0.22, 0.74, sw), lerpf(1.18, 0.24, sw), lerpf(-0.35, 0.55, sw), 0.25, lerpf(0.22, 0.04, sw), lerpf(-0.08, 0.24, sw), w)
	_set_arm(-1.0, lerpf(0.75, -0.42, sw), lerpf(0.42, 0.68, sw), lerpf(0.18, -0.30, sw), lerpf(0.82, 0.48, sw), 0.0, 0.0, 0.10, 0.0, w)


func _act_heavy(u: float, w: float) -> void:
	# Telegraphed high windup (0..0.44), explosive forward lunge cleave (0.44..0.72), heavy follow-through!
	var wind := smoothstep(0.0, 0.36, u)
	var strike := smoothstep(0.42, 0.68, u)
	var twist := lerpf(0.0, -0.72, wind) * (1.0 - strike) + 0.72 * strike
	var pitch := lerpf(0.0, 0.24, wind) * (1.0 - strike) - 0.38 * strike
	_target_hips_offset += Vector3(0.0, (0.04 * wind * (1.0 - strike) - 0.15 * strike) * w, 0.0)
	_set_char_rot(_b_spine, _euler_char(pitch * 0.45, twist * 0.42, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(pitch * 0.55, twist * 0.58, lerpf(-0.14, 0.18, strike)), w)
	_set_char_rot(_b_head, _euler_char(-pitch * 0.45, -twist * 0.55, 0.0), w)
	var r_fwd := lerpf(2.32, 0.48, strike)
	var r_out := lerpf(0.68, 0.12, strike)
	var r_in := lerpf(-0.62, 0.96, strike)
	var r_elb := lerpf(1.32, 0.22, strike)
	_set_arm(1.0, r_fwd, r_out, r_in, r_elb, lerpf(-0.40, 0.60, strike), 0.35, 0.22 * (1.0 - strike), lerpf(-0.16, 0.26, strike), w)
	_set_arm(-1.0, lerpf(1.15, -0.48, strike), lerpf(0.32, 0.78, strike), lerpf(0.35, -0.35, strike), lerpf(0.65, 0.42, strike), 0.0, 0.0, 0.10, 0.0, w)


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
	# Sideways duelist stance: right arm straight down -Z sighting along barrel!
	var steady := sin(u * TAU) * 0.015
	_set_char_rot(_b_spine, _euler_char(0.0, 0.22, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.02, 0.34, 0.0), w)
	_set_char_rot(_b_neck, _euler_char(0.0, -0.22, 0.0), w)
	_set_char_rot(_b_head, _euler_char(-0.04, -0.32, 0.10), w)
	_set_arm(1.0, 1.52 + steady, 0.06, 0.08, 0.14, -0.12, 0.0, 0.08, 0.16, w)
	_set_arm(-1.0, -0.18, 0.34, -0.16, 0.88, 0.0, 0.0, 0.0, -0.10, w)


func _act_fire_pistol(u: float, w: float) -> void:
	# Muzzle kick recoil upward & back from aimed pistol stance, then settles.
	var kick := pow(maxf(0.0, 1.0 - u * 1.35), 1.6) * smoothstep(0.0, 0.12, u)
	_set_char_rot(_b_spine, _euler_char(0.06 * kick, 0.22, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.12 * kick, 0.34 - 0.12 * kick, -0.06 * kick), w)
	_set_char_rot(_b_neck, _euler_char(0.05 * kick, -0.22, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.08 * kick, -0.30, 0.08), w)
	_set_arm(1.0, 1.52 + 0.56 * kick, 0.08 + 0.10 * kick, 0.06, 0.14 + 0.42 * kick, -0.35 * kick, 0.0, 0.14 * kick, 0.16 - 0.14 * kick, w)
	_set_arm(-1.0, -0.22, 0.38, -0.18, 0.92, 0.0, 0.0, 0.0, -0.10, w)


func _act_dig(u: float, w: float) -> void:
	# Two-handed shovel drive downward -> scoop & heave dirt up over left shoulder!
	var thrust := smoothstep(0.0, 0.35, u) * (1.0 - smoothstep(0.45, 0.78, u))
	var heave := smoothstep(0.42, 0.82, u)
	var lean := -0.44 * thrust + 0.12 * heave
	var twist := -0.22 * thrust + 0.46 * heave
	_target_hips_offset += Vector3(0.0, -0.16 * thrust * w, 0.0)
	_set_char_rot(_b_spine, _euler_char(lean * 0.48, twist * 0.45, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lean * 0.52, twist * 0.55, 0.08 * heave), w)
	_set_char_rot(_b_head, _euler_char(-lean * 0.35, -twist * 0.35, 0.0), w)
	_set_arm(1.0, lerpf(0.68, 1.38, heave), 0.16, lerpf(0.32, 0.52, heave), lerpf(0.55, 1.05, heave), 0.15, 0.0, 0.08, 0.12, w)
	_set_arm(-1.0, lerpf(0.54, 1.24, heave), 0.22, lerpf(0.36, -0.10, heave), lerpf(0.62, 0.82, heave), 0.15, 0.0, 0.06, 0.10, w)


func _act_hammer(u: float, w: float) -> void:
	# Energetic plank-repair hammering strike with right hand while left hand braces plank!
	var strike := smoothstep(0.28, 0.58, u)
	var rebound := smoothstep(0.62, 0.95, u)
	var swing := strike * (1.0 - 0.55 * rebound)
	_set_char_rot(_b_spine, _euler_char(-0.08 - 0.14 * swing, lerpf(-0.18, 0.16, swing), 0.0), w)
	_set_char_rot(_b_chest, _euler_char(-0.06 - 0.14 * swing, lerpf(-0.22, 0.20, swing), 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.08, 0.0, 0.0), w)
	_set_arm(1.0, lerpf(2.10, 0.94, swing), lerpf(0.26, 0.12, swing), lerpf(-0.12, 0.22, swing), lerpf(1.48, 0.42, swing), lerpf(-0.35, 0.40, swing), 0.0, 0.16 * (1.0 - swing), 0.10, w)
	_set_arm(-1.0, 0.98, 0.16, 0.22, 0.52, -0.25, 0.0, 0.0, 0.12, w)


func _act_bail(u: float, w: float) -> void:
	# Two-handed bucket scoop low in front -> energetic forward-upward water toss!
	var heave := smoothstep(0.34, 0.72, u)
	var lean := lerpf(-0.46, 0.14, heave)
	_target_hips_offset += Vector3(0.0, lerpf(-0.16, 0.03, heave) * w, 0.0)
	_set_char_rot(_b_spine, _euler_char(lean * 0.48, lerpf(-0.12, 0.24, heave), 0.0), w)
	_set_char_rot(_b_chest, _euler_char(lean * 0.52, lerpf(-0.14, 0.28, heave), 0.0), w)
	_set_char_rot(_b_head, _euler_char(-lean * 0.4, 0.0, 0.0), w)
	var af := lerpf(0.46, 1.56, heave)
	var ae := lerpf(0.42, 0.64, heave)
	_set_arm(-1.0, af, 0.16, 0.28, ae, lerpf(0.25, -0.30, heave), -0.25, 0.10 * heave, 0.12, w)
	_set_arm(1.0, af, 0.16, 0.28, ae, lerpf(0.25, -0.30, heave), -0.25, 0.10 * heave, 0.12, w)


func _act_drink(u: float, w: float) -> void:
	# Hearty tankard swig: raise mug to mouth, tilt head back in gulp, lower with flair!
	var lift := smoothstep(0.06, 0.30, u) * (1.0 - smoothstep(0.72, 0.94, u))
	var gulp := smoothstep(0.26, 0.46, u) * (1.0 - smoothstep(0.66, 0.84, u))
	_set_char_rot(_b_spine, _euler_char(0.10 * gulp, -0.06 * lift, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.12 * gulp, -0.10 * lift, -0.05 * lift), w)
	_set_char_rot(_b_neck, _euler_char(0.16 * gulp, 0.0, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.34 * gulp, 0.06 * lift, -0.06 * gulp), w)
	_set_arm(1.0, 0.96 + 0.36 * lift, 0.14 + 0.18 * gulp, 0.46 * lift, 1.52 + 0.42 * lift, -0.28 * gulp, -0.40 * lift, 0.12 * lift, 0.10 * lift, w)
	# Off-hand rests jauntily on hip!
	_set_arm(-1.0, 0.12, 0.42 * lift, -0.10, 1.15 * lift, 0.10, 0.0, 0.0, 0.0, w)


func _act_play_instrument(u: float, w: float) -> void:
	# Jaunty sea-shanty concertina/hurdy-gurdy groove with lively pumping hands & head bob!
	var beat := sin(u * TAU * 3.0)
	var bob := sin(u * TAU * 6.0)
	_set_char_rot(_b_spine, _euler_char(-0.04 + bob * 0.03, beat * 0.08, beat * 0.06), w)
	_set_char_rot(_b_chest, _euler_char(0.04 + bob * 0.04, beat * 0.12, beat * 0.08), w)
	_set_char_rot(_b_neck, _euler_char(bob * 0.06, -beat * 0.08, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.06 + bob * 0.10, -beat * 0.12, -beat * 0.12), w)
	# Concertina bellows squeeze & expand rhythm!
	var spread := 0.18 + beat * 0.14
	var inward := 0.36 - beat * 0.16
	_set_arm(-1.0, 0.72 + bob * 0.06, spread, inward, 1.38 + beat * 0.14, 0.15, -0.25, 0.06, 0.10, w)
	_set_arm(1.0, 0.72 - bob * 0.06, spread, inward, 1.38 + beat * 0.14, 0.15, -0.25, 0.06, 0.10, w)


func _act_shout(u: float, w: float) -> void:
	# Heroic pirate rally bellow: chest puffed high, right fist pumped overhead, left hand cupped to mouth!
	var roar := smoothstep(0.08, 0.32, u) * (1.0 - smoothstep(0.74, 0.96, u))
	var vibr := sin(u * TAU * 5.0) * 0.03 * roar
	_set_char_rot(_b_spine, _euler_char(0.14 * roar, -0.10 * roar, 0.0), w)
	_set_char_rot(_b_chest, _euler_char(0.18 * roar, -0.14 * roar, -0.06 * roar), w)
	_set_char_rot(_b_neck, _euler_char(0.14 * roar, 0.0, 0.0), w)
	_set_char_rot(_b_head, _euler_char(0.28 * roar + vibr, 0.08 * roar, 0.0), w)
	# Right arm pumped triumphantly skyward!
	_set_arm(1.0, 2.42 * roar + 0.25, 0.38 * roar + 0.10, -0.14, 0.42 + vibr * 2.0, 0.15, 0.0, 0.26 * roar, 0.0, w)
	# Left hand raised cupped beside mouth!
	_set_arm(-1.0, 1.18 * roar + 0.15, 0.22 * roar, 0.54 * roar, 1.72 * roar + 0.25, 0.20, -0.35, 0.12 * roar, 0.14 * roar, w)


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
