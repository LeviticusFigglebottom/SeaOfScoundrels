class_name Pawn
extends CharacterBody3D
## A body with no brain. A controller (PlayerController, CrewBrain, EnemyBrain,
## a test bot) writes the intent fields every physics tick; the pawn moves.
##
## Riding ships. Any PhysicsBody3D in group `ship` is a rideable platform.
## While riding, the pawn remembers where it is in the platform's local frame
## (`_anchor_local`). Each tick it is first carried by the platform's transform
## change (position, and the yaw part applied to `look_yaw`), then its own
## motion is solved with `velocity` meaning velocity RELATIVE to the platform.
## The pawn is never parented to the ship and stays upright in world space.
## Jumping keeps the pawn in the platform frame while it is above the platform;
## once nothing of the platform is below it, it detaches and inherits the
## platform's velocity at that point.
##
## Requirement on platforms: their `collision_mask` must NOT contain the pawn
## layer (3). A CharacterBody3D is an infinite-mass kinematic body to the
## solver and would shove the ship. The pawn clears that bit when it boards.
##
## World-state changes (damage, pickups, station occupancy) go through small
## host-only methods that can become RPCs.

signal died
signal damaged(amount: float, from: Node)
signal jumped
signal landed(impact_speed: float)
signal mode_changed(mode: int)
signal station_changed(station: Node3D)
signal carried_changed(item: Node3D)

enum Mode { WALK, SWIM, LADDER, STATION }

const LAYER_WORLD := 1
const LAYER_SHIP := 1 << 1
const LAYER_PAWN := 1 << 2
const RIDEABLE_GROUP := &"ship"

# ---- intent, written by the controller each physics tick ----
## World-space horizontal move direction, length 0..1.
var wish_dir: Vector3 = Vector3.ZERO
var wish_sprint: bool = false
## Level-triggered; the pawn reacts to the rising edge (with a short buffer).
var wish_jump: bool = false
## Radians about +Y. 0 looks down -Z. Ship yaw is added while riding.
var look_yaw: float = 0.0
## Radians, positive looks up.
var look_pitch: float = 0.0

# ---- tuning ----
@export_group("Body")
@export var radius: float = 0.3
@export var stand_height: float = 1.75
@export var crouch_height: float = 1.25
@export var eye_height: float = 1.6
@export var max_health: float = 100.0
@export_group("Ground")
@export var walk_speed: float = 3.6
@export var sprint_speed: float = 5.8
@export var crouch_speed: float = 2.2
@export var ground_accel: float = 45.0
@export var ground_decel: float = 55.0
@export var air_accel: float = 9.0
@export var jump_speed: float = 6.8
@export var gravity: float = 22.0
@export var terminal_speed: float = 40.0
@export var step_height: float = 0.36
@export var snap_length: float = 0.35
@export_group("Water")
## Feet depth at which walking turns into swimming (chest height).
@export var swim_enter_depth: float = 1.25
@export var swim_exit_depth: float = 0.9
## Feet depth while floating: the head and shoulders stay out.
@export var swim_float_depth: float = 1.35
@export var swim_speed: float = 2.3
@export var swim_sprint_speed: float = 3.1
@export var swim_accel: float = 7.0
@export var max_dive_depth: float = 4.0
@export var wade_depth: float = 0.5
@export_group("Ladder")
@export var ladder_speed: float = 2.4
@export_group("Riding")
## While airborne, stay in the platform frame as long as the platform is
## within this distance straight below.
@export var air_ride_range: float = 12.0
## Keep the stored deck anchor while standing still, so solver corrections
## cannot accumulate into drift. Off only for measuring the raw solver.
@export var idle_anchor_lock: bool = true

# ---- state ----
var health: float = 100.0
var dead: bool = false
var mode: Mode = Mode.WALK
var crouched: bool = false
## The Interactable the controller is pointing at.
var focus: Interactable = null
## Station being crewed (duck-typed against the Station contract), or null.
var station: Node3D = null
## Object being hauled (normally a Carryable), or null.
var carried: Node3D = null
## Rideable body the pawn is currently carried by, or null.
var platform: PhysicsBody3D = null
var ladder: Ladder = null
## Vertical offset for visuals and cameras that smooths step-ups (decays to 0).
var visual_offset_y: float = 0.0
## Smoothed eye height above the feet (follows crouching).
var current_eye_height: float = 1.6
## True while soaring through the air after launching out of a ship cannon.
var cannon_launched: bool = false
var _cannon_air_time: float = 0.0

var _anchor_local: Vector3 = Vector3.ZERO
# While airborne over a platform the pawn is anchored to the deck point it is
# above, plus a world-vertical height. A jump then comes down on the spot it
# left even though the deck rolled underneath in the meantime.
var _air_h: float = 0.0
var _y_after_carry: float = 0.0
var _plat_prev_basis: Basis = Basis.IDENTITY
var _plat_point_velocity: Vector3 = Vector3.ZERO
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _jump_was: bool = false
var _crouch_timer: float = 0.0
var _ladder_t: float = 0.0
var _ladder_off: Vector3 = Vector3.ZERO
var _ladder_cooldown: float = 0.0
var _prev_surface: float = 0.0
var _have_prev_surface: bool = false
var _keep_anchor: bool = false
var _shape: CapsuleShape3D
var _shape_node: CollisionShape3D
var _visual: Node3D
var _col := KinematicCollision3D.new()

const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.14
const LAND_SIGNAL_SPEED := 2.5

func _ready() -> void:
	collision_layer = LAYER_PAWN
	collision_mask = LAYER_WORLD | LAYER_SHIP
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(55.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	# The pawn does its own platform carrying; switch the built-in one off.
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	safe_margin = 0.002
	health = max_health
	current_eye_height = eye_height
	_shape_node = get_node_or_null(^"CollisionShape3D")
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		_shape_node.name = "CollisionShape3D"
		add_child(_shape_node)
	_shape = CapsuleShape3D.new()
	_shape.radius = radius
	_shape_node.shape = _shape
	_set_shape_height(stand_height)
	_visual = get_node_or_null(^"Visual")

# ------------------------------------------------------------------ queries

func is_grounded() -> bool:
	if mode != Mode.WALK:
		return false
	if is_on_floor():
		return true
	return platform != null and _coyote > 0.0 and velocity.y <= 0.25

func is_swimming() -> bool:
	return mode == Mode.SWIM

func is_riding() -> bool:
	return platform != null

## Velocity relative to the platform (equals world velocity when not riding).
func get_relative_velocity() -> Vector3:
	return velocity

func get_world_velocity() -> Vector3:
	return velocity + (_plat_point_velocity if platform != null else Vector3.ZERO)

func eye_position() -> Vector3:
	return global_position + Vector3.UP * (current_eye_height + visual_offset_y)

## Horizontal unit vector the pawn is facing.
func facing() -> Vector3:
	return Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))

## Unit view vector including pitch.
func view_dir() -> Vector3:
	var cp := cos(look_pitch)
	return Vector3(-sin(look_yaw) * cp, sin(look_pitch), -cos(look_yaw) * cp)

## Position in the platform's local frame (feet), or world position.
func platform_local_position() -> Vector3:
	if platform == null:
		return global_position
	return platform.global_transform.affine_inverse() * global_position

## Where the pawn stands on its platform: the centre of the capsule's bottom
## sphere in the platform's local frame. This is the point that stays fixed on
## a tilting deck (the feet point under an upright body swings by up to
## radius * sin(tilt) around it without the pawn sliding at all).
func ride_local_position() -> Vector3:
	if platform == null:
		return _anchor_world()
	return platform.global_transform.affine_inverse() * _anchor_world()

## Put the pawn on a platform at a platform-local feet position, moving with
## it from the first tick (spawning crew on a ship under way).
func board(body: PhysicsBody3D, local_feet: Vector3) -> void:
	cannon_launched = false
	_cannon_air_time = 0.0
	_set_platform(null)
	if mode != Mode.WALK and mode != Mode.STATION:
		_set_mode(Mode.WALK)
	global_position = body.global_transform * local_feet
	velocity = Vector3.ZERO
	_set_platform(body)
	velocity = Vector3.ZERO
	_coyote = COYOTE_TIME
	if not crouched and _headroom_blocked():
		_crouch()

## Detach from the currently ridden platform, preserving world velocity.
func unboard() -> void:
	_set_platform(null)

## Launch this pawn ballistically out of a ship cannon.
func launch_from_cannon(launch_vel: Vector3) -> void:
	if station != null and Net.is_host():
		leave_station()
	else:
		station = null
	ladder = null
	_ladder_cooldown = maxf(_ladder_cooldown, 0.35)
	_set_platform(null)
	if crouched:
		crouched = false
		_set_shape_height(stand_height)
	velocity = launch_vel
	cannon_launched = true
	_cannon_air_time = 0.0
	_coyote = 0.0
	_jump_buffer = 0.0
	_set_mode(Mode.WALK)

## Depth of the feet below the sea surface as far as movement is concerned.
## A pawn riding a ship that is not sinking is dry, even in the hold below
## the waterline.
func water_depth() -> float:
	if platform != null and mode != Mode.SWIM:
		if platform.get(&"is_sinking") != true:
			return 0.0
	return Sea.depth(global_position)

## Move the pawn somewhere without physics. Forgets the platform.
func teleport(world_position: Vector3) -> void:
	cannon_launched = false
	_cannon_air_time = 0.0
	_set_platform(null)
	global_position = world_position
	velocity = Vector3.ZERO
	if mode == Mode.LADDER or mode == Mode.SWIM:
		_set_mode(Mode.WALK)

# ---------------------------------------------------------------- main tick

func _physics_process(delta: float) -> void:
	if dead:
		wish_dir = Vector3.ZERO
		wish_sprint = false
		wish_jump = false
	if wish_jump and not _jump_was:
		_jump_buffer = JUMP_BUFFER
	_jump_was = wish_jump
	_ladder_cooldown = maxf(0.0, _ladder_cooldown - delta)
	_keep_anchor = false
	_carry_with_platform(delta)
	match mode:
		Mode.STATION:
			_tick_station(delta)
		Mode.LADDER:
			_tick_ladder(delta)
		Mode.SWIM:
			_tick_swim(delta)
		_:
			_tick_walk(delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if platform != null and not _keep_anchor:
		_store_anchor()
	_post_tick(delta)

func _clean_wish() -> Vector3:
	var w := Vector3(wish_dir.x, 0.0, wish_dir.z)
	if not w.is_finite():
		return Vector3.ZERO
	var l := w.length()
	return w / l if l > 1.0 else w

# ------------------------------------------------------------ platform ride

func _anchor_world() -> Vector3:
	# The centre of the capsule's bottom sphere. It stays exactly `radius`
	# from a flat deck however the deck tilts under the upright capsule.
	return global_position + Vector3.UP * radius

func _store_anchor() -> void:
	if mode == Mode.WALK and not is_on_floor():
		_air_h += global_position.y - _y_after_carry
	else:
		_air_h = 0.0
	_anchor_local = platform.global_transform.affine_inverse() * (_anchor_world() - Vector3.UP * _air_h)

func _carry_with_platform(delta: float) -> void:
	if platform == null:
		return
	if not is_instance_valid(platform) or not platform.is_inside_tree():
		platform = null
		velocity += _plat_point_velocity
		return
	var xf := platform.global_transform
	var target := xf * _anchor_local + Vector3.UP * _air_h
	_plat_point_velocity = (target - _anchor_world()) / delta
	global_position = target - Vector3.UP * radius
	_y_after_carry = global_position.y
	# Rotate the view and the relative velocity with the deck. The facing
	# vector is carried like a line painted on the deck, then flattened.
	var d := xf.basis.orthonormalized() * _plat_prev_basis.inverse()
	var f := d * facing()
	if absf(f.x) + absf(f.z) > 0.001:
		var dyaw := wrapf(atan2(-f.x, -f.z) - look_yaw, -PI, PI)
		look_yaw = wrapf(look_yaw + dyaw, -PI, PI)
		velocity = velocity.rotated(Vector3.UP, dyaw)
	_plat_prev_basis = xf.basis.orthonormalized()

func _set_platform(p: PhysicsBody3D) -> void:
	if p == platform:
		return
	if platform != null:
		velocity += _plat_point_velocity
	platform = p
	_plat_point_velocity = Vector3.ZERO
	if p == null:
		return
	if p.collision_mask & LAYER_PAWN:
		push_warning("Pawn: platform '%s' collides with the pawn layer; clearing that mask bit so pawns cannot shove it." % p.name)
		p.collision_mask &= ~LAYER_PAWN
	_plat_point_velocity = _body_point_velocity(p, _anchor_world())
	velocity -= _plat_point_velocity
	_plat_prev_basis = p.global_transform.basis.orthonormalized()
	_air_h = 0.0
	_y_after_carry = global_position.y
	_store_anchor()

func _body_point_velocity(body: PhysicsBody3D, at: Vector3) -> Vector3:
	var st := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if st == null:
		return Vector3.ZERO
	return st.get_velocity_at_local_position(at - st.transform.origin)

static func rideable_of(node: Object) -> PhysicsBody3D:
	var n := node as Node
	while n != null:
		if n is PhysicsBody3D and n.is_in_group(RIDEABLE_GROUP):
			return n
		n = n.get_parent()
	return null

func _ray_down(length: float, mask: int) -> Dictionary:
	var from := _anchor_world()
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)

func _refresh_platform() -> void:
	var found: PhysicsBody3D = null
	if is_on_floor():
		var hit := _ray_down(radius + 0.5, LAYER_WORLD | LAYER_SHIP)
		if not hit.is_empty():
			found = rideable_of(hit.collider)
		else:
			var any := false
			for i in get_slide_collision_count():
				var c := get_slide_collision(i)
				if c.get_normal().y > 0.3:
					any = true
					found = rideable_of(c.get_collider())
					if found != null:
						break
			if not any:
				found = platform
	elif platform != null:
		var hit := _ray_down(air_ride_range, LAYER_SHIP)
		if not hit.is_empty() and rideable_of(hit.collider) == platform:
			found = platform
	_set_platform(found)

# -------------------------------------------------------------------- walk

func _tick_walk(delta: float) -> void:
	var depth := water_depth()
	if depth > swim_enter_depth:
		_enter_swim()
		_tick_swim(delta)
		return
	if _try_grab_ladder():
		_tick_ladder(delta)
		return
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_try_stand_up(delta)
	var grounded := is_on_floor()
	if cannon_launched:
		_cannon_air_time += delta
		if _cannon_air_time <= 0.25:
			grounded = false
	_coyote = COYOTE_TIME if grounded else maxf(0.0, _coyote - delta)
	var wish := _clean_wish()
	var moving := wish.length_squared() > 0.0001
	var speed := walk_speed
	if crouched:
		speed = crouch_speed
	elif wish_sprint:
		speed = sprint_speed
		if carried != null:
			var f: Variant = carried.get(&"carry_speed_factor")
			speed *= float(f) if f != null else 0.72
	if depth > wade_depth:
		speed *= lerpf(1.0, 0.5, clampf((depth - wade_depth) / (swim_enter_depth - wade_depth), 0.0, 1.0))
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if cannon_launched and not grounded:
		hv *= exp(-0.12 * delta)
		if moving:
			hv += wish * (2.4 * delta)
	elif grounded:
		hv = hv.move_toward(wish * speed, (ground_accel if moving else ground_decel) * delta)
	elif moving:
		hv = hv.move_toward(wish * speed, air_accel * delta)
	var vy := velocity.y
	if grounded:
		vy = minf(vy, 0.0)
		vy = 0.0
	elif cannon_launched:
		vy = maxf(vy - 9.81 * delta, -terminal_speed)
	else:
		vy = maxf(vy - gravity * delta, -terminal_speed)
	var jumping := false
	if _jump_buffer > 0.0 and _coyote > 0.0 and not dead:
		vy = jump_speed
		jumping = true
		_jump_buffer = 0.0
		_coyote = 0.0
		jumped.emit()
	velocity = Vector3(hv.x, vy, hv.z)
	var eff_snap := maxf(snap_length, 0.55) if platform != null else snap_length
	floor_snap_length = 0.0 if (jumping or vy > 0.0 or cannon_launched) else eff_snap
	if not jumping and not cannon_launched and (grounded or _coyote > 0.0) and vy <= 0.0:
		_try_step_up(hv, delta)
	var before := global_position
	var fall_speed := -vy
	move_and_slide()
	if is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0
	var was_cannon_landing := false
	if cannon_launched and is_on_floor() and _cannon_air_time > 0.25:
		cannon_launched = false
		_cannon_air_time = 0.0
		was_cannon_landing = true
	if is_on_floor() and not grounded and fall_speed > LAND_SIGNAL_SPEED:
		var impact := minf(fall_speed * 0.45, 7.5) if was_cannon_landing else fall_speed
		landed.emit(impact)
	_check_crouch_trigger(moving)
	_refresh_platform()
	# Dead zone: a pawn standing still on a platform keeps its stored anchor,
	# so tiny solver corrections can never add up to drift.
	if idle_anchor_lock and grounded and is_on_floor() and not moving and hv.length_squared() < 0.0004 \
			and global_position.distance_squared_to(before) < 0.0004:
		_keep_anchor = true

## Step up onto ledges up to `step_height` (stairs, coamings, hatch rims).
## Lifts the body to the step's height; the normal move then carries it on.
func _try_step_up(hv: Vector3, delta: float) -> bool:
	if hv.length_squared() < 0.09:
		return false
	var dir := hv.normalized()
	var motion := hv * delta
	var xf := global_transform
	if not test_move(xf, motion, _col):
		return false
	var n := _col.get_normal()
	if n.y > cos(floor_max_angle) or n.y < -0.2 or dir.dot(-n) < 0.15:
		return false
	if _col.get_position().y - global_position.y > step_height + 0.05:
		return false
	var up := step_height
	if test_move(xf, Vector3.UP * step_height, _col):
		up = maxf(_col.get_travel().y, 0.0)
	if up < 0.03:
		return false
	var xf2 := xf.translated(Vector3.UP * up)
	# Is there room to stand on top? Probe a body-radius ahead.
	var ahead := radius + 0.05
	if test_move(xf2, dir * ahead, _col):
		ahead = _col.get_travel().length()
		if ahead < maxf(motion.length(), 0.02):
			return false
	var xf3 := xf2.translated(dir * ahead)
	if not test_move(xf3, Vector3.DOWN * (up + 0.05), _col):
		return false
	if _col.get_normal().y < cos(floor_max_angle):
		return false
	var rise := up + _col.get_travel().y
	if rise < 0.03:
		return false
	global_position += Vector3.UP * (rise + 0.005)
	visual_offset_y -= rise
	_coyote = COYOTE_TIME
	return true

func _set_shape_height(h: float) -> void:
	_shape.height = h
	_shape_node.position = Vector3(0.0, h * 0.5, 0.0)

func _check_crouch_trigger(moving: bool) -> void:
	# Auto-crouch: walking into something that only blocks the upper body
	# (a low deck beam, the hold's ceiling) ducks under it.
	if crouched or mode != Mode.WALK:
		return
	if is_on_floor() and _headroom_blocked():
		_crouch()
		return
	if not moving:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y < 0.3 and c.get_position().y - global_position.y > crouch_height - 0.05:
			_crouch()
			return

func _crouch() -> void:
	crouched = true
	_crouch_timer = 0.35
	_set_shape_height(crouch_height)

func _headroom_blocked() -> bool:
	var from := global_position + Vector3.UP * (crouch_height - radius)
	var to := global_position + Vector3.UP * (stand_height + 0.02)
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_SHIP, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _try_stand_up(delta: float) -> void:
	if not crouched:
		return
	_crouch_timer -= delta
	if _crouch_timer > 0.0:
		return
	if not test_move(global_transform, Vector3.UP * (stand_height - crouch_height + 0.04)):
		crouched = false
		_set_shape_height(stand_height)

# -------------------------------------------------------------------- swim

func _enter_swim() -> void:
	var was_cannon := cannon_launched
	cannon_launched = false
	_cannon_air_time = 0.0
	_set_platform(null)
	_have_prev_surface = false
	if crouched:
		crouched = false
		_set_shape_height(stand_height)
	_set_mode(Mode.SWIM)
	if was_cannon:
		if Ocean.current != null:
			Ocean.current.add_foam(global_position, 4.6, 1.0)
		var splash_sfx := &"splash_big" if Audio.has_sound(&"splash_big") else &"splash_large"
		Audio.play_sfx(splash_sfx, global_position)

func _tick_swim(delta: float) -> void:
	var surface := Sea.height(global_position.x, global_position.z)
	var depth := surface - global_position.y
	if depth < swim_exit_depth:
		_set_mode(Mode.WALK)
		_tick_walk(delta)
		return
	if _try_grab_ladder():
		_tick_ladder(delta)
		return
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var wish := _clean_wish()
	var speed := swim_sprint_speed if wish_sprint else swim_speed
	if carried != null:
		speed *= 0.7
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * speed, swim_accel * delta)
	# Float: hold the feet at swim_float_depth, riding the surface up and down.
	var surface_vel := 0.0
	if _have_prev_surface:
		surface_vel = clampf((surface - _prev_surface) / delta, -6.0, 6.0)
	_prev_surface = surface
	_have_prev_surface = true
	var err := depth - swim_float_depth
	var v_target := surface_vel + clampf(err * 4.0, -3.0, 3.0)
	# Dive by swimming forward while looking down; surface by looking up or jump.
	var fwd := wish.dot(facing())
	if wish_jump:
		v_target = maxf(v_target, speed)
	elif fwd > 0.2 and look_pitch < -0.3 and depth < swim_float_depth + max_dive_depth:
		v_target = sin(look_pitch) * speed * fwd
		hv *= lerpf(1.0, cos(look_pitch), 0.5)
	var vy := move_toward(velocity.y, v_target, 26.0 * delta)
	velocity = Vector3(hv.x, vy, hv.z)
	move_and_slide()

# ------------------------------------------------------------------ ladder

## Host only. Latch directly onto `lad` (e.g. interactive `[F]` hull boarding ladders).
func grab_ladder(lad: Ladder) -> bool:
	if not Net.is_host() or dead or station != null:
		return false
	if lad == null or not is_instance_valid(lad) or not lad.is_inside_tree():
		return false
	if mode == Mode.LADDER and ladder == lad:
		return false
	cannon_launched = false
	_cannon_air_time = 0.0
	var xf := lad.global_transform
	var lp := xf.affine_inverse() * global_position
	var min_y := maxf(-lad.reach_below + 0.25, 0.05)
	var max_y := maxf(min_y, lad.height - 0.35)
	var rung_y := clampf(lp.y, min_y, max_y)
	var ideal_local := Vector3(0.0, rung_y, lad.standoff)
	var world_before := global_position
	global_position = xf * ideal_local
	ladder = lad
	_ladder_t = rung_y
	_ladder_cooldown = 0.0
	_set_platform(lad.get_platform())
	velocity = Vector3.ZERO
	var raw_off := xf.affine_inverse() * world_before - ideal_local
	raw_off.y = 0.0
	if raw_off.length() > 0.65:
		raw_off = raw_off.normalized() * 0.65
	_ladder_off = raw_off
	if crouched:
		crouched = false
		_set_shape_height(stand_height)
	var into := lad.into_dir()
	if absf(into.x) + absf(into.z) > 0.01:
		look_yaw = atan2(-into.x, -into.z)
	_set_mode(Mode.LADDER)
	Audio.play_sfx(&"rope_creak", global_position, -3.0)
	return true

func _try_grab_ladder() -> bool:
	if _ladder_cooldown > 0.0 or dead or not is_inside_tree():
		return false
	var wish := _clean_wish()
	if wish.length_squared() < 0.01:
		return false
	var is_ai_pawn := get_node_or_null(^"CrewBrain") != null or get_node_or_null(^"EnemyBrain") != null
	for node in get_tree().get_nodes_in_group(Ladder.GROUP):
		var l := node as Ladder
		if l == null or not l.is_inside_tree():
			continue
		if is_ai_pawn and not l.allow_ai_grab:
			continue
		var lp := l.global_transform.affine_inverse() * global_position
		var x_pad := 0.08 if l.require_direct_approach else 0.25
		if absf(lp.x) > l.width * 0.5 + x_pad:
			continue
		var toward := wish.dot(l.into_dir())
		# From the side: from the ground, a lower deck, or the water.
		var z_pad := 0.35 if l.require_direct_approach else 0.65
		var min_toward := 0.1 if mode == Mode.SWIM else (0.72 if l.require_direct_approach else 0.35)
		if lp.z > -0.1 and lp.z < l.standoff + z_pad and lp.y > -l.reach_below and lp.y < l.height - 0.35:
			if toward > min_toward:
				_mount_ladder(l, lp)
				return true
		# From the top: walking off the edge above the ladder, facing out.
		elif lp.y > l.height - 0.4 and lp.y < l.height + 0.6 and lp.z > -0.4 and lp.z < 0.3 \
				and toward < -0.6 and is_on_floor():
			lp.y = l.height - 0.3
			_mount_ladder(l, lp)
			return true
	return false

func _mount_ladder(l: Ladder, local_pos: Vector3) -> void:
	cannon_launched = false
	_cannon_air_time = 0.0
	ladder = l
	_ladder_t = local_pos.y
	var ideal := Vector3(0.0, _ladder_t, l.standoff)
	var world_before := global_position
	_set_platform(l.get_platform())
	velocity = Vector3.ZERO
	_ladder_off = l.global_transform.affine_inverse() * world_before - ideal
	_ladder_off.y = 0.0
	if crouched:
		crouched = false
		_set_shape_height(stand_height)
	_set_mode(Mode.LADDER)

func _leave_ladder(cooldown: float) -> void:
	ladder = null
	_ladder_cooldown = cooldown
	_set_mode(Mode.WALK)

func _tick_ladder(delta: float) -> void:
	if ladder == null or not is_instance_valid(ladder) or not ladder.is_inside_tree() or dead:
		_leave_ladder(0.3)
		return
	var into := ladder.into_dir()
	var climb := _clean_wish().dot(into)
	if absf(climb) < 0.2:
		climb = 0.0
	_ladder_off = _ladder_off.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
	if _jump_buffer > 0.0:
		_jump_buffer = 0.0
		velocity = -into * 2.6 + Vector3.UP * 3.2
		_leave_ladder(0.6)
		jumped.emit()
		return
	_ladder_t += climb * ladder_speed * delta
	var xf := ladder.global_transform
	if _ladder_t >= ladder.height:
		global_position = xf * (Vector3(0.0, ladder.height, 0.0) + ladder.exit_offset)
		velocity = Vector3.ZERO
		_leave_ladder(0.5)
		return
	global_position = xf * (Vector3(0.0, _ladder_t, ladder.standoff) + _ladder_off)
	velocity = Vector3.ZERO
	if climb < 0.0:
		var let_go := _ladder_t <= -ladder.reach_below
		if not let_go and Sea.depth(global_position) >= swim_float_depth:
			let_go = true
		if not let_go and _ladder_t < ladder.height - 1.0 \
				and test_move(global_transform, Vector3.DOWN * 0.08, _col) and _col.get_normal().y > 0.5:
			let_go = true
		if let_go:
			_leave_ladder(0.6)

# ----------------------------------------------------------------- station

## Find the station an interactable is the handle of (duck-typed).
static func station_of(it: Node) -> Node3D:
	if it == null:
		return null
	var candidates: Array = [it]
	if it.has_method("get_target"):
		candidates.append(it.get_target())
	candidates.append(it.get_parent())
	for c in candidates:
		if c is Node3D and c.has_method("occupy") and c.has_method("drive"):
			return c
	return null

## World transform of where the occupant of `st` stands. `Station.stand_point`
## is read as LOCAL to the station node. A station may instead provide
## `get_stand_global() -> Transform3D`.
static func station_stand_transform(st: Node3D) -> Transform3D:
	if st.has_method("get_stand_global"):
		return st.get_stand_global()
	var sp: Variant = st.get(&"stand_point")
	if sp is Transform3D:
		return st.global_transform * (sp as Transform3D)
	if sp is Node3D:
		return (sp as Node3D).global_transform
	return st.global_transform

## Host only. Occupy a station. Returns true on success.
func enter_station(st: Node3D) -> bool:
	if not Net.is_host() or dead or st == null or station != null:
		return false
	if st.get(&"occupant") != self:
		if st.has_method("can_occupy") and not st.can_occupy(self):
			return false
		st.occupy(self)
		var occ: Variant = st.get(&"occupant")
		if occ != null and occ != self:
			return false
	_adopt_station(st)
	return true

func _adopt_station(st: Node3D) -> void:
	cannon_launched = false
	_cannon_air_time = 0.0
	if carried != null:
		drop_carried()
	station = st
	ladder = null
	_set_platform(rideable_of(st))
	velocity = Vector3.ZERO
	if crouched:
		crouched = false
		_set_shape_height(stand_height)
	_set_mode(Mode.STATION)
	station_changed.emit(station)

## Host only. Step away from the station being crewed.
func leave_station() -> void:
	if station == null or not Net.is_host():
		return
	var st := station
	station = null
	if is_instance_valid(st) and st.get(&"occupant") == self:
		st.release()
	velocity = Vector3.ZERO
	_set_mode(Mode.WALK)
	station_changed.emit(null)

## Host only. Forward control input to the crewed station. Controllers call
## this every physics tick while `station` is set.
func drive_station(axis: Vector2, primary: bool, secondary: bool, delta: float) -> void:
	if station == null or dead or not Net.is_host():
		return
	if not is_instance_valid(station):
		station = null
		_set_mode(Mode.WALK)
		return
	station.drive(axis, primary, secondary, delta)

func _tick_station(delta: float) -> void:
	if station == null or not is_instance_valid(station) or not station.is_inside_tree():
		station = null
		_set_mode(Mode.WALK)
		station_changed.emit(null)
		return
	var occ: Variant = station.get(&"occupant")
	if occ != self:
		# Released from the other side (station destroyed, kicked out).
		station = null
		_set_mode(Mode.WALK)
		station_changed.emit(null)
		return
	var stand := station_stand_transform(station)
	# The platform carry already moved us with the ship; this only closes the
	# remaining gap to the stand point.
	global_position = global_position.lerp(stand.origin, 1.0 - exp(-16.0 * delta))
	velocity = Vector3.ZERO

# ------------------------------------------------------- interact and carry

## Use whatever the controller focused. While hauling, hands the load to a
## focused container or drops it.
func interact() -> void:
	if dead or station != null:
		return
	if focus != null and not is_instance_valid(focus):
		focus = null
	if carried != null:
		var container := _container_of(focus)
		if container != null and carried.has_method("hand_to") and carried.hand_to(container):
			return
		drop_carried()
		return
	if focus != null:
		host_interact(focus)

## Host side of `interact()`; the future RPC entry point.
func host_interact(target: Interactable) -> void:
	if not Net.is_host() or dead or target == null or not target.can_interact(self):
		return
	target.interact(self)
	var st := station_of(target)
	if st != null and station == null and is_instance_valid(st):
		if st.has_method(&"try_quick_use") and bool(st.call(&"try_quick_use", self)):
			return
		enter_station(st)

func _container_of(it: Interactable) -> Node:
	if it == null:
		return null
	for c in [it, it.get_target(), it.get_parent()]:
		if c != null and c.has_method("accept_carryable"):
			return c
	return null

## Host only. Start hauling `item` (normally a Carryable).
func pick_up(item: Node3D) -> bool:
	if not Net.is_host() or dead or item == null or carried != null or station != null:
		return false
	if item.get(&"holder") != null:
		return false
	carried = item
	if item.has_method("attach_to"):
		item.attach_to(self)
	_place_carried()
	carried_changed.emit(carried)
	return true

## Host only. Put the load down in front, keeping the pawn's world velocity.
func drop_carried(toss_speed: float = 1.2) -> void:
	if carried == null or not Net.is_host():
		return
	var item := carried
	carried = null
	if is_instance_valid(item) and item.has_method("detach"):
		item.detach(get_world_velocity() + facing() * toss_speed)
	carried_changed.emit(null)

## Called by the load when it leaves the pawn's hands some other way.
func release_carried(item: Node3D) -> void:
	if carried == item:
		carried = null
		carried_changed.emit(null)

func _place_carried() -> void:
	if carried == null:
		return
	if not is_instance_valid(carried):
		carried = null
		return
	var off: Variant = carried.get(&"hold_offset")
	var o: Vector3 = off if off is Vector3 else Vector3(0.0, 1.0, -0.62)
	var b := Basis(Vector3.UP, look_yaw)
	if crouched:
		o.y -= 0.35
	carried.global_transform = Transform3D(b, global_position + b * o)

# -------------------------------------------------------------------- health

## Host only. `from` is whoever caused it (may be null).
func apply_damage(amount: float, from: Node = null) -> void:
	if not Net.is_host() or dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	damaged.emit(amount, from)
	if health <= 0.0:
		_die()

## Host only.
func heal(amount: float) -> void:
	if not Net.is_host() or dead:
		return
	health = minf(max_health, health + amount)

func _die() -> void:
	dead = true
	cannon_launched = false
	_cannon_air_time = 0.0
	if station != null:
		leave_station()
	if carried != null:
		drop_carried(0.0)
	if mode == Mode.LADDER:
		_leave_ladder(1.0)
	focus = null
	died.emit()

## Host only. Bring a dead pawn back (respawn).
func revive(at: Vector3, new_health: float = -1.0) -> void:
	if not Net.is_host():
		return
	dead = false
	health = max_health if new_health <= 0.0 else minf(new_health, max_health)
	teleport(at)

# --------------------------------------------------------------------- misc

func _set_mode(m: Mode) -> void:
	if m == mode:
		return
	mode = m
	mode_changed.emit(mode)

func _post_tick(delta: float) -> void:
	visual_offset_y = lerpf(visual_offset_y, 0.0, 1.0 - exp(-14.0 * delta))
	if absf(visual_offset_y) < 0.001:
		visual_offset_y = 0.0
	var eh := eye_height - (stand_height - crouch_height) if crouched else eye_height
	current_eye_height = lerpf(current_eye_height, eh, 1.0 - exp(-12.0 * delta))
	_place_carried()
	if _visual != null:
		var yaw := look_yaw
		if mode == Mode.STATION and station != null:
			var fwd := -station_stand_transform(station).basis.z
			if absf(fwd.x) + absf(fwd.z) > 0.01:
				yaw = atan2(-fwd.x, -fwd.z)
		elif mode == Mode.LADDER and ladder != null:
			var into := ladder.into_dir()
			yaw = atan2(-into.x, -into.z)
		_visual.rotation = Vector3(-PI * 0.5 if dead else 0.0, yaw, 0.0)
		_visual.position = Vector3(0.0, visual_offset_y + (0.3 if dead else 0.0), 0.0)
		_visual.scale = Vector3(1.0, current_eye_height / eye_height, 1.0)
