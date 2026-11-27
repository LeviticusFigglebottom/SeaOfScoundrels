class_name IslandCrab
extends CharacterBody3D
## Coral-armored giant island crab that guards beaches, dig sites, and coastal ruins.
##
## Features chunky faceted painterly anatomy (crimson-coral carapace with warm barnacle
## ridges, expressive black-bead eyestalks, 6 alternating-tripod scuttling legs, and two
## asymmetrical snapping pincers `ClawL`/`ClawR`), lateral sidestepping AI, a clear
## 0.55 s raised-claw telegraph before lunging, windup/parry stagger, and an edible
## cookable crab-claw drop on defeat.

signal damaged(amount: float, from: Node)
signal staggered(duration: float)
signal attack_telegraphed(crab: IslandCrab, target: Node3D)
signal lunge_struck(target: Node3D, damage: float)
signal defeated(crab: IslandCrab, pos: Vector3)
signal loot_dropped(item: Dictionary, pos: Vector3)

enum State {
	GUARD_IDLE,
	SIDESTEP,
	TELEGRAPH,
	LUNGE,
	RECOVER,
	STAGGERED,
	RETURN_HOME,
	DEAD,
}

const GROUP := &"beasts"
const CRAB_GROUP := &"island_crabs"
const GRAVITY := 22.0
const LUNGE_DURATION := 0.24
const RECOVER_DURATION := 0.72
const ATTACK_COOLDOWN := 1.45
const DEATH_DESPAWN_DELAY := 6.0

# Painterly tropical coral-crab palette.
const COL_SHELL_DEEP := Color(0.56, 0.10, 0.08)
const COL_SHELL_CORAL := Color(0.86, 0.24, 0.13)
const COL_SHELL_BRIGHT := Color(0.95, 0.44, 0.18)
const COL_BELLY_CREAM := Color(0.92, 0.80, 0.62)
const COL_BARNACLE_LIGHT := Color(0.89, 0.85, 0.73)
const COL_BARNACLE_CORE := Color(0.42, 0.30, 0.19)
const COL_CORAL_PINK := Color(0.95, 0.56, 0.45)
const COL_CLAW_TIP := Color(0.96, 0.89, 0.74)
const COL_LEG_JOINT := Color(0.92, 0.54, 0.22)
const COL_LEG_TIP := Color(0.32, 0.14, 0.09)
const COL_EYE_STALK := Color(0.88, 0.38, 0.16)
const COL_EYE_BLACK := Color(0.06, 0.06, 0.08)

# Crisp 4-point combat-telegraph danger glint constants (zero extra texture VRAM).
const TELEGRAPH_HALO_POS := Vector3(0.0, 0.56, -0.34)
const TELEGRAPH_HALO_VISIBILITY_RANGE := 75.0
const TELEGRAPH_SCALE_MIN := 0.28
const TELEGRAPH_SCALE_MAX := 0.62
const TELEGRAPH_ENERGY_MIN := 0.65
const TELEGRAPH_ENERGY_MAX := 1.55
const COL_TELEGRAPH_CORE := Color(1.00, 0.96, 0.72, 1.0)
const COL_TELEGRAPH_MID := Color(1.00, 0.52, 0.14, 1.0)
const COL_TELEGRAPH_WAIST := Color(0.96, 0.24, 0.10, 1.0)
const COL_TELEGRAPH_TIP := Color(0.00, 0.00, 0.00, 1.0)

static var _active_crabs: int = 0
static var _telegraph_halo_mesh: ArrayMesh = null

@export var max_health: float = 45.0
@export var faction: StringName = &"beast"
@export var guard_origin: Vector3 = Vector3.ZERO
@export var guard_radius: float = 12.0
@export var aggro_range: float = 14.0
@export var scuttle_speed: float = 3.8
@export var lunge_speed: float = 9.2
@export var lunge_damage: float = 14.0
@export var telegraph_duration: float = 0.55

var health: float = 45.0
var dead: bool = false
var target: Pawn = null
var state: State = State.GUARD_IDLE

## Articulated snapping pincer pivots (asymmetrical: ClawR crusher, ClawL cutter).
var claw_l: Node3D = null
var claw_r: Node3D = null

var _body_root: Node3D = null
var _snap_jaw_l: Node3D = null
var _snap_jaw_r: Node3D = null
var _eye_l: Node3D = null
var _eye_r: Node3D = null
var _legs: Array[Dictionary] = []
var _shell_mat: StandardMaterial3D = null
var _eye_mat: StandardMaterial3D = null
var _telegraph_halo_mi: MeshInstance3D = null
var _telegraph_halo_mat: StandardMaterial3D = null
var _telegraph_halo_energy: float = 0.0

var _state_timer: float = 0.0
var _attack_cd: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_timer: float = 1.8
var _patrol_angle: float = 0.0
var _gait_phase: float = 0.0
var _idle_phase: float = 0.0
var _hit_flash: float = 0.0
var _death_timer: float = 0.0
var _lunge_dir: Vector3 = Vector3.FORWARD
var _hit_this_lunge: bool = false
var _origin_locked: bool = false
var _rng := RandomNumberGenerator.new()


## Release statically cached sculpted telegraph halo assets cleanly.
static func clear_shared_cache() -> void:
	_telegraph_halo_mesh = null


## Spawn a coral-armored IslandCrab anchored at `world_pos`.
static func spawn_at(parent: Node, world_pos: Vector3, p_guard_radius: float = 12.0) -> IslandCrab:
	var crab := IslandCrab.new()
	crab.name = "IslandCrab"
	crab.guard_radius = maxf(p_guard_radius, 3.0)
	crab.guard_origin = world_pos
	crab._origin_locked = true
	if parent != null:
		parent.add_child(crab)
	crab.global_position = world_pos
	return crab


func _enter_tree() -> void:
	_active_crabs += 1
	add_to_group(GROUP)
	add_to_group(CRAB_GROUP)


func _exit_tree() -> void:
	_release_local_refs()
	_active_crabs = maxi(0, _active_crabs - 1)
	if _active_crabs == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_local_refs()


func _release_local_refs() -> void:
	if _telegraph_halo_mi != null and is_instance_valid(_telegraph_halo_mi):
		_telegraph_halo_mi.visible = false
		_telegraph_halo_mi.material_override = null
		_telegraph_halo_mi.set_mesh(null)
	_telegraph_halo_mi = null
	_telegraph_halo_mat = null
	_telegraph_halo_energy = 0.0


func _ready() -> void:
	health = max_health
	collision_layer = Pawn.LAYER_PAWN
	collision_mask = Pawn.LAYER_WORLD | Pawn.LAYER_SHIP
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	floor_snap_length = 0.35

	var seed_val := hash(Vector3i(
		int(roundf(global_position.x * 4.0)),
		int(roundf(global_position.y * 4.0)),
		int(roundf(global_position.z * 4.0))
	))
	_rng.seed = seed_val if seed_val != 0 else 0xC4AB5EA
	_strafe_sign = 1.0 if _rng.randf() > 0.5 else -1.0
	_patrol_angle = _rng.randf() * TAU

	if not _origin_locked and guard_origin == Vector3.ZERO:
		guard_origin = global_position
		_origin_locked = global_position != Vector3.ZERO

	_build_collision()
	_build_anatomy()
	_update_telegraph_halo()


# ------------------------------------------------------------------ combat API

func is_staggered() -> bool:
	return state == State.STAGGERED


func is_telegraphing() -> bool:
	return state == State.TELEGRAPH


## Return the additive 4-point ClawTelegraphHalo MeshInstance3D mounted above the raised pincers.
func get_telegraph_halo_node() -> MeshInstance3D:
	return _telegraph_halo_mi


## Return current ClawTelegraphHalo additive energy (0.0 when idle/staggered/dead).
func get_telegraph_halo_energy() -> float:
	return _telegraph_halo_energy


func facing() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))


func eye_position() -> Vector3:
	return global_position + Vector3(0.0, 0.72, 0.0)


## Host-authoritative damage entry point matching CombatComponent & Cannonball duck-typing.
func apply_damage(amount: float, from: Node = null) -> void:
	if not Net.is_host() or dead or amount <= 0.0:
		return
	var was_windup := state == State.TELEGRAPH
	var mult := 1.5 if state == State.STAGGERED else 1.0
	var dmg := amount * mult
	health = maxf(0.0, health - dmg)
	_hit_flash = 0.22
	Audio.play_sfx(&"hit_flesh", global_position + Vector3(0.0, 0.5, 0.0))
	damaged.emit(dmg, from)

	if from is Node3D:
		var away := global_position - (from as Node3D).global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			velocity += away.normalized() * 3.4

	if health <= 0.0:
		_die()
		return

	# Striking the crab cleanly during its raised-claw windup interrupts and staggers it!
	if was_windup:
		apply_stagger(1.35)


## Duck-typed melee hit receiver matching `CombatComponent.receive_melee_hit()`.
func receive_melee_hit(attacker_cc: CombatComponent, raw_damage: float,
		is_heavy: bool, _cleaves_shield: bool) -> StringName:
	if not Net.is_host() or dead:
		return &"dodged"
	var attacker_pawn: Pawn = attacker_cc.pawn if attacker_cc != null else null
	var was_windup := state == State.TELEGRAPH
	apply_damage(raw_damage, attacker_pawn)
	if not dead:
		if attacker_pawn != null:
			var push := global_position - attacker_pawn.global_position
			push.y = 0.0
			if push.length_squared() > 0.001:
				velocity += push.normalized() * (5.2 if is_heavy else 2.6)
		if is_heavy or was_windup:
			apply_stagger(1.5 if is_heavy else 1.35)
	return &"hit"


## Host-authoritative stagger (triggered by windup interrupt, heavy attack, or timed parry).
func apply_stagger(duration: float = 1.5) -> void:
	if not Net.is_host() or dead:
		return
	state = State.STAGGERED
	_state_timer = maxf(_state_timer, maxf(duration, 0.25))
	_hit_this_lunge = false
	velocity.x *= 0.25
	velocity.z *= 0.25
	_update_telegraph_halo()
	staggered.emit(duration)


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if not _origin_locked and guard_origin == Vector3.ZERO and global_position != Vector3.ZERO:
		guard_origin = global_position
		_origin_locked = true

	if dead:
		_death_timer += delta
		_animate_death(delta)
		_update_telegraph_halo()
		if Net.is_host() and _death_timer >= DEATH_DESPAWN_DELAY:
			queue_free()
		return

	_idle_phase += delta
	_hit_flash = maxf(0.0, _hit_flash - delta)

	if Net.is_host():
		_tick_ai(delta)
		_tick_motion(delta)

	_update_hit_flash()
	_animate_crab(delta)
	_update_telegraph_halo()


func _tick_ai(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = _rng.randf_range(1.4, 2.8)
		_strafe_sign = -_strafe_sign

	var from_home := Vector3(global_position.x - guard_origin.x, 0.0, global_position.z - guard_origin.z)
	var home_dist := from_home.length()

	if state == State.STAGGERED:
		_state_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		if _state_timer <= 0.0:
			state = State.GUARD_IDLE
		return

	if state == State.TELEGRAPH:
		_state_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		if target != null and is_instance_valid(target) and not target.dead:
			var aim := target.global_position - global_position
			aim.y = 0.0
			if aim.length_squared() > 0.001:
				_lunge_dir = aim.normalized()
				var yaw_goal := atan2(-_lunge_dir.x, -_lunge_dir.z)
				rotation.y = lerp_angle(rotation.y, yaw_goal, clampf(delta * 10.0, 0.0, 1.0))
		if _state_timer <= 0.0:
			state = State.LUNGE
			_state_timer = LUNGE_DURATION
			_hit_this_lunge = false
			Audio.play_sfx(&"sword_swing", global_position + Vector3(0.0, 0.6, 0.0), -3.0, 0.14)
		return

	if state == State.LUNGE:
		_state_timer -= delta
		velocity.x = _lunge_dir.x * lunge_speed
		velocity.z = _lunge_dir.z * lunge_speed
		if not _hit_this_lunge:
			_try_lunge_hit()
		if _state_timer <= 0.0:
			state = State.RECOVER
			_state_timer = RECOVER_DURATION
			_attack_cd = ATTACK_COOLDOWN
		return

	if state == State.RECOVER:
		_state_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
		if _state_timer <= 0.0:
			state = State.SIDESTEP if target != null and is_instance_valid(target) and not target.dead else State.GUARD_IDLE
		return

	# Refresh hostile target within guard perimeter.
	target = _find_target()
	if home_dist > guard_radius + 3.0 or (state == State.RETURN_HOME and home_dist > 2.2):
		state = State.RETURN_HOME
		var back := -from_home.normalized() if home_dist > 0.05 else Vector3.ZERO
		_move_horizontal(back * scuttle_speed, delta)
		_face_dir(back, delta * 5.0)
		if home_dist <= 2.2:
			state = State.GUARD_IDLE
		return

	if target == null:
		state = State.GUARD_IDLE
		# Gentle guard patrol around anchor so beaches feel alive.
		_patrol_angle = wrapf(_patrol_angle + delta * 0.42, 0.0, TAU)
		var patrol_r := minf(guard_radius * 0.35, 3.2)
		var patrol_pt := guard_origin + Vector3(cos(_patrol_angle) * patrol_r, 0.0, sin(_patrol_angle) * patrol_r)
		var to_pt := Vector3(patrol_pt.x - global_position.x, 0.0, patrol_pt.z - global_position.z)
		if to_pt.length() > 0.6:
			var pdir := to_pt.normalized()
			_move_horizontal(pdir * (scuttle_speed * 0.42), delta)
			# Crabs patrol facing slightly angled from travel direction.
			_face_dir(pdir.rotated(Vector3.UP, 0.55 * _strafe_sign), delta * 3.5)
		else:
			_move_horizontal(Vector3.ZERO, delta)
		return

	# Engage target: sideways crab scuttle around the intruder, then telegraph a pincer lunge!
	state = State.SIDESTEP
	var to_t := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
	var dist := to_t.length()
	var dir := to_t.normalized() if dist > 0.01 else facing()
	_face_dir(dir, delta * 9.0)

	if dist <= 2.9 and _attack_cd <= 0.0:
		state = State.TELEGRAPH
		_state_timer = telegraph_duration
		_lunge_dir = dir
		_hit_this_lunge = false
		_update_telegraph_halo()
		attack_telegraphed.emit(self, target)
		if Audio.has_sound(&"skeleton_rattle"):
			Audio.play_sfx(&"skeleton_rattle", global_position + Vector3(0.0, 0.6, 0.0), -6.0, 0.16)
		return

	var right := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
	var move_dir: Vector3
	if dist > 4.2:
		move_dir = (dir * 0.80 + right * 0.60).normalized()
	elif dist < 1.9:
		move_dir = (-dir * 0.45 + right * 0.88).normalized()
	else:
		move_dir = (dir * 0.38 + right * 0.92).normalized()

	# Keep out of deep water if shoreline slopes down.
	if Sea.depth(global_position + move_dir * 0.9) > 0.65:
		move_dir = -from_home.normalized() if home_dist > 0.2 else right

	_move_horizontal(move_dir * scuttle_speed, delta)


func _tick_motion(delta: float) -> void:
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -30.0)
	move_and_slide()


func _move_horizontal(desired: Vector3, delta: float) -> void:
	velocity.x = move_toward(velocity.x, desired.x, 20.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 20.0 * delta)


func _face_dir(dir: Vector3, rate: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(rate, 0.0, 1.0))


func _try_lunge_hit() -> void:
	var victim := _pick_lunge_victim()
	if victim == null:
		return
	_hit_this_lunge = true

	var target_cc := _combat_of(victim)
	if target_cc != null:
		if target_cc.is_invulnerable():
			return
		var to_crab := global_position - victim.global_position
		to_crab.y = 0.0
		var frontal := to_crab.length_squared() <= 0.001 or to_crab.normalized().dot(victim.facing()) > 0.15
		if frontal and target_cc.is_in_parry_window():
			target_cc.receive_melee_hit(null, lunge_damage, false, false)
			apply_stagger(1.75)
			return
		if frontal and not target_cc.is_staggered() and (target_cc.state == CombatComponent.State.BLOCKING or target_cc.has_shield):
			target_cc.receive_melee_hit(null, lunge_damage, false, false)
			return

	victim.apply_damage(lunge_damage, self)
	Audio.play_sfx(&"hit_flesh", victim.eye_position())
	var push := victim.global_position - global_position
	push.y = 0.0
	if push.length_squared() > 0.001:
		victim.velocity += push.normalized() * 3.6 + Vector3(0.0, 1.8, 0.0)
	lunge_struck.emit(victim, lunge_damage)


func _pick_lunge_victim() -> Pawn:
	if target != null and is_instance_valid(target) and not target.dead:
		var d_t := target.global_position - global_position
		var flat_t := Vector2(d_t.x, d_t.z).length()
		if flat_t <= 2.45 and absf(d_t.y) <= 1.65:
			return target
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc == null or cc.faction == faction or cc.pawn == null or cc.pawn.dead:
			continue
		var d := cc.pawn.global_position - global_position
		if Vector2(d.x, d.z).length() <= 2.45 and absf(d.y) <= 1.65:
			return cc.pawn
	return null


func _find_target() -> Pawn:
	var best: Pawn = null
	var best_d := aggro_range
	var max_from_home := guard_radius + 4.0

	if target != null and is_instance_valid(target) and not target.dead and not target.is_swimming():
		var td_home := Vector2(target.global_position.x - guard_origin.x, target.global_position.z - guard_origin.z).length()
		var td_me := global_position.distance_to(target.global_position)
		if td_home <= max_from_home and td_me <= aggro_range * 1.15:
			best = target
			best_d = td_me

	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc == null or cc.faction == faction or cc.pawn == null or cc.pawn.dead:
			continue
		if cc.pawn.is_swimming():
			continue
		var p_pos := cc.pawn.global_position
		if Vector2(p_pos.x - guard_origin.x, p_pos.z - guard_origin.z).length() > max_from_home:
			continue
		var d := global_position.distance_to(p_pos)
		if d < best_d:
			best_d = d
			best = cc.pawn
	return best


static func _combat_of(p: Pawn) -> CombatComponent:
	for c in p.get_children():
		if c is CombatComponent:
			return c as CombatComponent
	return null


func _die() -> void:
	dead = true
	health = 0.0
	state = State.DEAD
	collision_layer = 0
	velocity = Vector3.ZERO
	_death_timer = 0.0
	_update_telegraph_halo()

	var drop_pos := global_position + Vector3(0.0, 0.25, 0.0)
	var drop_item := {
		"id": &"giant_crab_claw",
		"name": "Giant Crab Claw",
		"heal": 42.0,
		"gold": 55,
		"cookable": true,
		"edible": true,
		"cooked_state": &"raw",
	}
	_spawn_crab_claw_pickup(drop_item, drop_pos)
	defeated.emit(self, global_position)
	loot_dropped.emit(drop_item, drop_pos)


func _spawn_crab_claw_pickup(item: Dictionary, world_pos: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return
	var pickup := Node3D.new()
	pickup.name = "CrabClawDrop"
	pickup.set_meta(&"food_item", item.duplicate())

	var mi := MeshInstance3D.new()
	mi.name = "ClawDropMesh"
	mi.mesh = _build_claw_drop_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.56
	mi.material_override = mat
	pickup.add_child(mi)

	var it := Interactable.create("Eat Giant Crab Claw", 0.55)
	it.position = Vector3(0.0, 0.16, 0.0)
	it.interacted.connect(func(p: Node) -> void:
		if p is Pawn:
			var pawn_node := p as Pawn
			pawn_node.heal(float(item.get("heal", 42.0)))
			Audio.play_sfx(&"grog_gulp", pawn_node.eye_position(), -2.0)
			Game.post_notice("Ate Giant Crab Claw (+%d health)!" % int(item.get("heal", 42.0)))
		pickup.queue_free()
	)
	pickup.add_child(it)

	host.add_child(pickup)
	pickup.global_position = world_pos


# ------------------------------------------------------------------ procedural animation

func _animate_crab(delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.15:
		_gait_phase += delta * (7.2 + horiz_speed * 2.4)

	var body_bob := sin(_idle_phase * 2.6) * 0.025 + absf(sin(_gait_phase)) * minf(horiz_speed * 0.015, 0.05)
	var body_pitch := 0.0
	var body_roll := sin(_gait_phase) * minf(horiz_speed * 0.018, 0.06)

	var claw_raise := 0.18 + sin(_idle_phase * 2.2) * 0.06
	var claw_flare := 0.16
	var jaw_open := 0.14 + maxf(0.0, sin(_idle_phase * 3.1)) * 0.12

	match state:
		State.TELEGRAPH:
			var t := clampf(1.0 - (_state_timer / maxf(telegraph_duration, 0.05)), 0.0, 1.0)
			var ease_t := 1.0 - pow(1.0 - t, 2.0)
			body_pitch = lerpf(0.08, 0.28, ease_t)
			body_bob += ease_t * 0.14
			claw_raise = lerpf(0.28, 1.08, ease_t)
			claw_flare = lerpf(0.18, 0.44, ease_t)
			jaw_open = lerpf(0.22, 0.68, ease_t)
		State.LUNGE:
			body_pitch = -0.22
			body_bob -= 0.05
			claw_raise = -0.24
			claw_flare = -0.18
			jaw_open = 0.02
		State.RECOVER:
			body_pitch = -0.06
			claw_raise = 0.05
			claw_flare = 0.10
			jaw_open = 0.10
		State.STAGGERED:
			body_pitch = -0.18
			body_roll = sin(_idle_phase * 18.0) * 0.22
			body_bob -= 0.10
			claw_raise = -0.34
			claw_flare = 0.52
			jaw_open = 0.42
		_:
			pass

	if _body_root != null:
		_body_root.position.y = body_bob
		_body_root.rotation = Vector3(body_pitch, 0.0, body_roll)

	if claw_l != null:
		claw_l.position = Vector3(-0.44, 0.44 + body_bob, -0.34)
		claw_l.rotation = Vector3(claw_raise * 0.92, claw_flare, 0.14 + body_roll * 0.5)
	if claw_r != null:
		claw_r.position = Vector3(0.46, 0.46 + body_bob, -0.34)
		claw_r.rotation = Vector3(claw_raise * 1.06, -claw_flare, -0.14 + body_roll * 0.5)

	if _snap_jaw_l != null:
		_snap_jaw_l.rotation.x = -jaw_open
	if _snap_jaw_r != null:
		_snap_jaw_r.rotation.x = -jaw_open * 1.12

	# Expressive eyestalk tilt (lean forward when lunging/telegraphing, tuck when staggered).
	var eye_pitch := -0.22 if state == State.STAGGERED else (0.18 if state == State.TELEGRAPH else sin(_idle_phase * 1.8) * 0.07)
	if _eye_l != null:
		_eye_l.rotation.x = eye_pitch
	if _eye_r != null:
		_eye_r.rotation.x = eye_pitch

	# Alternating tripod gait across the 6 articulated scuttling legs!
	var stride_amp := clampf(horiz_speed / maxf(scuttle_speed, 0.5), 0.0, 1.35)
	for entry in _legs:
		var piv := entry["pivot"] as Node3D
		if piv == null:
			continue
		var side_sign: float = float(entry["side"])
		var tripod_off: float = float(entry["tripod_phase"])
		var base_yaw: float = float(entry["base_yaw"])
		var phase := _gait_phase + tripod_off
		var sweep := sin(phase) * 0.34 * stride_amp
		var lift := maxf(0.0, cos(phase)) * 0.30 * stride_amp
		var idle_shift := sin(_idle_phase * 1.9 + tripod_off) * 0.03
		piv.rotation = Vector3(0.0, base_yaw + sweep * side_sign, side_sign * (lift + idle_shift))


func _animate_death(delta: float) -> void:
	var flip_t := clampf(_death_timer * 2.8, 0.0, 1.0)
	var flip_z := lerpf(0.0, PI, 1.0 - pow(1.0 - flip_t, 2.0))
	if _body_root != null:
		_body_root.rotation.z = flip_z
		_body_root.position.y = lerpf(0.0, 0.52, flip_t)
	if claw_l != null:
		claw_l.rotation.x = lerpf(claw_l.rotation.x, -0.45, clampf(delta * 5.0, 0.0, 1.0))
	if claw_r != null:
		claw_r.rotation.x = lerpf(claw_r.rotation.x, -0.52, clampf(delta * 5.0, 0.0, 1.0))
	for entry in _legs:
		var piv := entry["pivot"] as Node3D
		if piv != null:
			var twitch := sin(_death_timer * 14.0 + float(entry["tripod_phase"])) * maxf(0.0, 1.0 - _death_timer * 0.6) * 0.25
			piv.rotation.z = float(entry["side"]) * (0.45 + twitch)


func _update_hit_flash() -> void:
	if _shell_mat == null:
		return
	if _hit_flash > 0.0:
		_shell_mat.emission_enabled = true
		_shell_mat.emission = Color(1.0, 0.52, 0.24)
		_shell_mat.emission_energy_multiplier = (_hit_flash / 0.22) * 1.15
	elif state == State.TELEGRAPH:
		var pulse := 0.5 + 0.5 * sin(_idle_phase * 22.0)
		_shell_mat.emission_enabled = true
		_shell_mat.emission = Color(1.0, 0.36, 0.12)
		_shell_mat.emission_energy_multiplier = 0.28 + pulse * 0.24
	else:
		_shell_mat.emission_enabled = false
		_shell_mat.emission_energy_multiplier = 0.0


func _update_telegraph_halo() -> void:
	if _telegraph_halo_mi == null or not is_instance_valid(_telegraph_halo_mi):
		_telegraph_halo_energy = 0.0
		return

	if dead or state == State.DEAD or state == State.STAGGERED:
		_telegraph_halo_energy = 0.0
		_telegraph_halo_mi.visible = false
		if _telegraph_halo_mat != null:
			_telegraph_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		return

	if state == State.TELEGRAPH:
		var t := clampf(1.0 - (_state_timer / maxf(telegraph_duration, 0.05)), 0.0, 1.0)
		var ramp := smoothstep(0.0, 1.0, t)
		var pulse_boost := 0.07 * (0.5 + 0.5 * sin(_idle_phase * 28.0)) * (0.25 + 0.75 * t)
		var energy := lerpf(TELEGRAPH_ENERGY_MIN, TELEGRAPH_ENERGY_MAX - 0.07, ramp) + pulse_boost
		var halo_scale := lerpf(TELEGRAPH_SCALE_MIN, TELEGRAPH_SCALE_MAX, t)
		var tint := Color(1.00, 0.78, 0.36).lerp(Color(1.00, 0.38, 0.16), t)
		_telegraph_halo_energy = energy
		_telegraph_halo_mi.visible = true
		_telegraph_halo_mi.scale = Vector3.ONE * halo_scale
		if _telegraph_halo_mat != null:
			_telegraph_halo_mat.albedo_color = Color(
				tint.r * energy,
				tint.g * energy,
				tint.b * energy,
				1.0
			)
		return

	if state == State.LUNGE:
		var lt := clampf(_state_timer / maxf(LUNGE_DURATION, 0.05), 0.0, 1.0)
		var energy := 0.85 * lt * lt
		if energy > 0.01:
			_telegraph_halo_energy = energy
			_telegraph_halo_mi.visible = true
			_telegraph_halo_mi.scale = Vector3.ONE * lerpf(0.22, 0.50, lt)
			if _telegraph_halo_mat != null:
				_telegraph_halo_mat.albedo_color = Color(
					1.00 * energy,
					0.34 * energy,
					0.14 * energy,
					1.0
				)
			return

	_telegraph_halo_energy = 0.0
	_telegraph_halo_mi.visible = false
	if _telegraph_halo_mat != null:
		_telegraph_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)


# ------------------------------------------------------------------ procedural meshes

func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.62
	cyl.height = 0.82
	cs.shape = cyl
	cs.position = Vector3(0.0, 0.41, 0.0)
	add_child(cs)


func _build_anatomy() -> void:
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.vertex_color_use_as_albedo = true
	_shell_mat.vertex_color_is_srgb = true
	_shell_mat.roughness = 0.58
	_shell_mat.metallic = 0.04

	_eye_mat = StandardMaterial3D.new()
	_eye_mat.vertex_color_use_as_albedo = true
	_eye_mat.vertex_color_is_srgb = true
	_eye_mat.roughness = 0.12
	_eye_mat.metallic = 0.1

	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)

	# 1. Crimson-coral faceted carapace with warm barnacle ridges & serrated orbital brow.
	var carapace_mi := MeshInstance3D.new()
	carapace_mi.name = "Carapace"
	carapace_mi.mesh = _build_carapace_mesh()
	carapace_mi.material_override = _shell_mat
	_body_root.add_child(carapace_mi)

	# 2. Two expressive black-bead eyestalks protruding from frontal brow sockets.
	var eye_mesh := _build_eyestalk_mesh()
	_eye_l = Node3D.new()
	_eye_l.name = "EyeStalkL"
	_eye_l.position = Vector3(-0.18, 0.56, -0.37)
	_eye_l.rotation = Vector3(0.08, 0.16, 0.14)
	var el_mi := MeshInstance3D.new()
	el_mi.mesh = eye_mesh
	el_mi.material_override = _eye_mat
	_eye_l.add_child(el_mi)
	_body_root.add_child(_eye_l)

	_eye_r = Node3D.new()
	_eye_r.name = "EyeStalkR"
	_eye_r.position = Vector3(0.18, 0.56, -0.37)
	_eye_r.rotation = Vector3(0.08, -0.16, -0.14)
	var er_mi := MeshInstance3D.new()
	er_mi.mesh = eye_mesh
	er_mi.material_override = _eye_mat
	_eye_r.add_child(er_mi)
	_body_root.add_child(_eye_r)

	# 3. Six articulated scuttling legs (3 left, 3 right) wired for alternating tripod gait.
	_legs.clear()
	var leg_mesh_l := _build_leg_mesh(-1.0)
	var leg_mesh_r := _build_leg_mesh(1.0)
	var z_offsets: Array[float] = [-0.15, 0.06, 0.27]
	var yaw_offsets: Array[float] = [0.28, 0.0, -0.30]

	for idx in 3:
		for s_i in 2:
			var side_sign := -1.0 if s_i == 0 else 1.0
			var side_tag := "L" if s_i == 0 else "R"
			var piv := Node3D.new()
			piv.name = "Leg_%s%d" % [side_tag, idx]
			piv.position = Vector3(side_sign * 0.44, 0.36, z_offsets[idx])
			var base_yaw := -side_sign * yaw_offsets[idx]
			piv.rotation = Vector3(0.0, base_yaw, 0.0)
			var leg_mi := MeshInstance3D.new()
			leg_mi.mesh = leg_mesh_l if s_i == 0 else leg_mesh_r
			leg_mi.material_override = _shell_mat
			piv.add_child(leg_mi)
			_body_root.add_child(piv)

			# Alternating tripod: (L0, R1, L2) = 0 rad; (R0, L1, R2) = PI rad.
			var tripod_phase := 0.0 if ((idx + s_i) % 2 == 0) else PI
			_legs.append({
				"pivot": piv,
				"side": side_sign,
				"base_yaw": base_yaw,
				"tripod_phase": tripod_phase,
			})

	# 4. Two chunky asymmetrical snapping pincers (`ClawL` cutter, `ClawR` giant crusher).
	claw_l = _build_claw_assembly("ClawL", -1.0, 0.92)
	claw_l.position = Vector3(-0.44, 0.44, -0.34)
	add_child(claw_l)
	_snap_jaw_l = claw_l.get_node_or_null(^"SnapJaw") as Node3D

	claw_r = _build_claw_assembly("ClawR", 1.0, 1.24)
	claw_r.position = Vector3(0.46, 0.46, -0.34)
	add_child(claw_r)
	_snap_jaw_r = claw_r.get_node_or_null(^"SnapJaw") as Node3D

	# 5. Crisp 4-point amber-crimson combat telegraph star glint right above raised front pincers.
	_build_telegraph_halo()


func _build_telegraph_halo() -> void:
	if _telegraph_halo_mi != null or _body_root == null:
		return
	_ensure_shared_assets()

	_telegraph_halo_mat = StandardMaterial3D.new()
	_telegraph_halo_mat.vertex_color_use_as_albedo = true
	_telegraph_halo_mat.vertex_color_is_srgb = true
	_telegraph_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_telegraph_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_telegraph_halo_mat.billboard_keep_scale = true
	_telegraph_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_telegraph_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)

	_telegraph_halo_mi = MeshInstance3D.new()
	_telegraph_halo_mi.name = "ClawTelegraphHalo"
	_telegraph_halo_mi.position = TELEGRAPH_HALO_POS
	_telegraph_halo_mi.scale = Vector3.ONE * TELEGRAPH_SCALE_MIN
	_telegraph_halo_mi.mesh = _telegraph_halo_mesh
	_telegraph_halo_mi.material_override = _telegraph_halo_mat
	_telegraph_halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_halo_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_telegraph_halo_mi.visibility_range_end = TELEGRAPH_HALO_VISIBILITY_RANGE
	_telegraph_halo_mi.extra_cull_margin = 0.8
	_telegraph_halo_mi.visible = false
	_telegraph_halo_energy = 0.0
	_body_root.add_child(_telegraph_halo_mi)


static func _ensure_shared_assets() -> void:
	if _telegraph_halo_mesh == null:
		_telegraph_halo_mesh = _build_telegraph_halo_mesh()


static func _build_telegraph_halo_mesh() -> ArrayMesh:
	# Exact 24-triangle 4-point combat-telegraph star glint ArrayMesh (zero primitives / zero VRAM).
	# Incandescent pale-gold center -> crisp amber-crimson rays -> pure Color(0, 0, 0, 1) feathered tips.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SPOKES := 8
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	var center := Vector3.ZERO
	var inner_pts: Array[Vector3] = []
	var outer_pts: Array[Vector3] = []
	var inner_cols: Array[Color] = []

	for i in SPOKES:
		var ang := float(i) / float(SPOKES) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		var is_major := (i % 2 == 0)
		var r_in := 0.14 if is_major else 0.065
		var r_out := (0.52 if (i == 2 or i == 6) else 0.48) if is_major else 0.16
		inner_pts.append(Vector3(ca * r_in, sa * r_in, 0.0))
		outer_pts.append(Vector3(ca * r_out, sa * r_out, 0.0))
		inner_cols.append(COL_TELEGRAPH_MID if is_major else COL_TELEGRAPH_WAIST)

	for i in SPOKES:
		var ni := (i + 1) % SPOKES
		var in_a := inner_pts[i]
		var in_b := inner_pts[ni]
		var out_a := outer_pts[i]
		var out_b := outer_pts[ni]
		var col_a := inner_cols[i]
		var col_b := inner_cols[ni]

		# Inner bright star core (8 tris).
		st.set_normal(FRONT_NORMAL); st.set_color(COL_TELEGRAPH_CORE); st.add_vertex(center)
		st.set_normal(FRONT_NORMAL); st.set_color(col_b); st.add_vertex(in_b)
		st.set_normal(FRONT_NORMAL); st.set_color(col_a); st.add_vertex(in_a)

		# Outer symmetric tapered star rays feathering cleanly to black tips (16 tris).
		if i % 2 == 0:
			st.set_normal(FRONT_NORMAL); st.set_color(col_a); st.add_vertex(in_a)
			st.set_normal(FRONT_NORMAL); st.set_color(COL_TELEGRAPH_TIP); st.add_vertex(out_b)
			st.set_normal(FRONT_NORMAL); st.set_color(COL_TELEGRAPH_TIP); st.add_vertex(out_a)

			st.set_normal(FRONT_NORMAL); st.set_color(col_a); st.add_vertex(in_a)
			st.set_normal(FRONT_NORMAL); st.set_color(col_b); st.add_vertex(in_b)
			st.set_normal(FRONT_NORMAL); st.set_color(COL_TELEGRAPH_TIP); st.add_vertex(out_b)
		else:
			st.set_normal(FRONT_NORMAL); st.set_color(col_b); st.add_vertex(in_b)
			st.set_normal(FRONT_NORMAL); st.set_color(COL_TELEGRAPH_TIP); st.add_vertex(out_b)
			st.set_normal(FRONT_NORMAL); st.set_color(COL_TELEGRAPH_TIP); st.add_vertex(out_a)

			st.set_normal(FRONT_NORMAL); st.set_color(col_a); st.add_vertex(in_a)
			st.set_normal(FRONT_NORMAL); st.set_color(col_b); st.add_vertex(in_b)
			st.set_normal(FRONT_NORMAL); st.set_color(COL_TELEGRAPH_TIP); st.add_vertex(out_a)

	return st.commit()


func _build_claw_assembly(node_name: String, side_sign: float, claw_scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.scale = Vector3(claw_scale, claw_scale, claw_scale)

	var arm_mi := MeshInstance3D.new()
	arm_mi.name = "ClawPalm"
	arm_mi.mesh = _build_claw_palm_mesh(side_sign)
	arm_mi.material_override = _shell_mat
	root.add_child(arm_mi)

	var snap_jaw := Node3D.new()
	snap_jaw.name = "SnapJaw"
	snap_jaw.position = Vector3(side_sign * 0.14, -0.02, -0.42)
	var jaw_mi := MeshInstance3D.new()
	jaw_mi.name = "SnapJawMesh"
	jaw_mi.mesh = _build_claw_thumb_mesh(side_sign)
	jaw_mi.material_override = _shell_mat
	snap_jaw.add_child(jaw_mi)
	root.add_child(snap_jaw)

	return root


static func _build_carapace_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Domed hexagonal crustacean shell: 4 stacked rings (plastron, rim, dome, crown).
	var segs := 10
	var layers: Array[Array] = [
		[0.24, 0.42, 0.34, COL_BELLY_CREAM],
		[0.42, 0.58, 0.46, COL_SHELL_CORAL],
		[0.62, 0.46, 0.38, COL_SHELL_BRIGHT],
		[0.74, 0.24, 0.20, COL_SHELL_CORAL],
	]
	var rings: Array[Array] = []
	var cols: Array[Color] = []
	for layer in layers:
		var y: float = float(layer[0])
		var rx: float = float(layer[1])
		var rz: float = float(layer[2])
		var col: Color = layer[3]
		var ring: Array[Vector3] = []
		for i in segs:
			var a := float(i) / float(segs) * TAU
			# Flatten rear & pinch front corners for chunky crab carapace silhouette.
			var z_mod := 0.90 if sin(a) > 0.0 else 1.06
			var ridge := 1.0 + 0.05 * cos(a * 4.0)
			ring.append(Vector3(cos(a) * rx * ridge, y, sin(a) * rz * z_mod))
		rings.append(ring)
		cols.append(col)

	var shell_ctr := Vector3(0.0, 0.46, 0.0)
	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Color = cols[j]
		var c1: Color = cols[j + 1]
		for i in segs:
			var ni := (i + 1) % segs
			var dark_groove := c0.lerp(COL_SHELL_DEEP, 0.35 if (i % 2 == 0 and j == 1) else 0.0)
			_add_outward_quad_grad(st, r1[ni], r1[i], r0[i], r0[ni], shell_ctr, c1, c1, dark_groove, dark_groove)

	# Top crown dome cap & ventral plastron cap.
	var top_pt := Vector3(0.0, 0.78, -0.02)
	var top_r: Array = rings[rings.size() - 1]
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_tri(st, top_pt, top_r[i], top_r[ni], shell_ctr, COL_SHELL_BRIGHT, COL_SHELL_CORAL, COL_SHELL_CORAL)
	var bot_pt := Vector3(0.0, 0.21, 0.0)
	var bot_r: Array = rings[0]
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_tri(st, bot_pt, bot_r[ni], bot_r[i], shell_ctr, COL_BELLY_CREAM, COL_BELLY_CREAM, COL_BELLY_CREAM)

	# Frontal serrated brow teeth & chunky cream mouthparts (-Z face).
	for sx: float in [-0.28, -0.10, 0.10, 0.28]:
		_append_cone_spike(st, Vector3(sx, 0.49, -0.42), Vector3(sx * 1.12, 0.56, -0.54), 0.06, COL_SHELL_BRIGHT, COL_CORAL_PINK)
	_append_faceted_box(st, Vector3(0.0, 0.34, -0.42), Vector3(0.16, 0.07, 0.06), COL_BELLY_CREAM)

	# Lateral carapace spines for bold painterly silhouette!
	for sg: float in [-1.0, 1.0]:
		_append_cone_spike(st, Vector3(sg * 0.52, 0.45, -0.18), Vector3(sg * 0.70, 0.52, -0.24), 0.075, COL_SHELL_CORAL, COL_CORAL_PINK)
		_append_cone_spike(st, Vector3(sg * 0.55, 0.44, 0.08), Vector3(sg * 0.72, 0.50, 0.10), 0.07, COL_SHELL_CORAL, COL_SHELL_BRIGHT)

	# Warm barnacle ridges encrusted asymmetrically across the upper back carapace.
	var barnacles: Array[Array] = [
		[Vector3(-0.22, 0.67, 0.06), 0.095, 0.09],
		[Vector3(-0.08, 0.72, 0.14), 0.080, 0.08],
		[Vector3(0.18, 0.68, -0.05), 0.105, 0.10],
		[Vector3(0.28, 0.59, 0.16), 0.082, 0.08],
		[Vector3(0.02, 0.73, -0.16), 0.072, 0.07],
		[Vector3(-0.30, 0.58, -0.10), 0.068, 0.07],
	]
	for b in barnacles:
		_append_barnacle(st, b[0], float(b[1]), float(b[2]))

	return st.commit()


static func _build_eyestalk_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Coral-orange stalk extending up (+Y) with glossy black bead eye at top.
	_append_segment_prism(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.16, -0.03), 0.036, 0.030, COL_EYE_STALK, COL_SHELL_BRIGHT)
	_append_faceted_box(st, Vector3(0.0, 0.21, -0.045), Vector3(0.054, 0.054, 0.054), COL_EYE_BLACK)
	# Tiny white specular eye sparkle facet facing forward.
	_append_faceted_box(st, Vector3(0.022, 0.232, -0.092), Vector3(0.015, 0.015, 0.012), COL_CLAW_TIP)
	return st.commit()


static func _build_leg_mesh(side_sign: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Three-segment articulated crustacean leg: hip -> raised knee -> ankle -> pointed dactylus touching y = 0.
	var p0 := Vector3(0.0, 0.0, 0.0)
	var p1 := Vector3(side_sign * 0.28, 0.16, 0.0)
	var p2 := Vector3(side_sign * 0.46, -0.08, 0.0)
	var p3 := Vector3(side_sign * 0.54, -0.36, 0.0)
	_append_segment_prism(st, p0, p1, 0.072, 0.058, COL_SHELL_CORAL, COL_LEG_JOINT)
	_append_segment_prism(st, p1, p2, 0.056, 0.044, COL_LEG_JOINT, COL_SHELL_DEEP)
	_append_cone_spike(st, p2, p3, 0.042, COL_SHELL_DEEP, COL_LEG_TIP)
	return st.commit()


static func _build_claw_palm_mesh(side_sign: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Chunky armored forearm elbow -> giant beveled crusher palm -> upper fixed pincer blade.
	var elbow := Vector3(side_sign * 0.16, 0.02, -0.18)
	var wrist := Vector3(side_sign * 0.18, 0.06, -0.34)
	_append_segment_prism(st, Vector3.ZERO, elbow, 0.095, 0.105, COL_SHELL_DEEP, COL_SHELL_CORAL)
	_append_segment_prism(st, elbow, wrist, 0.105, 0.125, COL_SHELL_CORAL, COL_SHELL_BRIGHT)

	# Big chunky faceted palm (propodus) with cream-coral shading & barnacle stud.
	_append_faceted_box(st, Vector3(side_sign * 0.14, 0.07, -0.48), Vector3(0.145, 0.135, 0.18), COL_SHELL_CORAL)
	_append_barnacle(st, Vector3(side_sign * 0.20, 0.18, -0.45), 0.055, 0.048)

	# Fixed upper pincer prong curving inward (-side_sign) and forward (-Z).
	var upper_base := Vector3(side_sign * 0.14, 0.13, -0.60)
	var upper_mid := Vector3(side_sign * 0.07, 0.12, -0.78)
	var upper_tip := Vector3(-side_sign * 0.02, 0.04, -0.92)
	_append_segment_prism(st, upper_base, upper_mid, 0.088, 0.062, COL_SHELL_BRIGHT, COL_CLAW_TIP)
	_append_cone_spike(st, upper_mid, upper_tip, 0.058, COL_CLAW_TIP, COL_CLAW_TIP)

	# Serrated ivory crusher teeth along inner underside of upper prong.
	for t_i in 3:
		var frac := 0.25 + float(t_i) * 0.26
		var tooth_base := upper_base.lerp(upper_tip, frac) + Vector3(0.0, -0.04, 0.0)
		_append_cone_spike(st, tooth_base, tooth_base + Vector3(0.0, -0.055, -0.02), 0.024, COL_CLAW_TIP, COL_BELLY_CREAM)

	return st.commit()


static func _build_claw_thumb_mesh(side_sign: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Articulated lower movable thumb (dactylus) hinged at SnapJaw pivot.
	var j_base := Vector3(0.0, 0.0, 0.0)
	var j_mid := Vector3(-side_sign * 0.04, -0.04, -0.24)
	var j_tip := Vector3(-side_sign * 0.13, 0.05, -0.44)
	_append_segment_prism(st, j_base, j_mid, 0.068, 0.052, COL_SHELL_BRIGHT, COL_CLAW_TIP)
	_append_cone_spike(st, j_mid, j_tip, 0.048, COL_CLAW_TIP, COL_CLAW_TIP)
	return st.commit()


static func _build_claw_drop_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_faceted_box(st, Vector3(0.0, 0.10, 0.0), Vector3(0.14, 0.09, 0.18), COL_SHELL_CORAL)
	_append_cone_spike(st, Vector3(0.04, 0.11, -0.14), Vector3(-0.04, 0.13, -0.34), 0.06, COL_SHELL_BRIGHT, COL_CLAW_TIP)
	_append_cone_spike(st, Vector3(-0.04, 0.09, -0.12), Vector3(-0.11, 0.10, -0.28), 0.045, COL_CLAW_TIP, COL_BELLY_CREAM)
	return st.commit()


static func _append_barnacle(st: SurfaceTool, base: Vector3, radius: float, height: float) -> void:
	var segs := 6
	var top_r := radius * 0.45
	var bot_ring: Array[Vector3] = []
	var top_ring: Array[Vector3] = []
	for i in segs:
		var a := float(i) / float(segs) * TAU
		bot_ring.append(base + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		top_ring.append(base + Vector3(cos(a) * top_r, height, sin(a) * top_r))
	var ctr := base + Vector3(0.0, height * 0.4, 0.0)
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_quad_grad(st, top_ring[ni], top_ring[i], bot_ring[i], bot_ring[ni], ctr,
			COL_BARNACLE_LIGHT, COL_BARNACLE_LIGHT, COL_CORAL_PINK, COL_CORAL_PINK)
	var crater := base + Vector3(0.0, height * 0.65, 0.0)
	var cap_ref := base + Vector3(0.0, -0.2, 0.0)
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_tri(st, crater, top_ring[i], top_ring[ni], cap_ref,
			COL_BARNACLE_CORE, COL_BARNACLE_LIGHT, COL_BARNACLE_LIGHT)


static func _append_segment_prism(st: SurfaceTool, a: Vector3, b: Vector3,
		ra: float, rb: float, col_a: Color, col_b: Color) -> void:
	var axis := b - a
	if axis.length_squared() < 1e-6:
		return
	var dir := axis.normalized()
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.85 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := u.cross(dir).normalized()
	var segs := 6
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in segs:
		var ang := float(i) / float(segs) * TAU
		var off := u * cos(ang) + v * sin(ang)
		ring_a.append(a + off * ra)
		ring_b.append(b + off * rb)
	var ctr := (a + b) * 0.5
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_quad_grad(st, ring_b[ni], ring_b[i], ring_a[i], ring_a[ni], ctr, col_b, col_b, col_a, col_a)
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_tri(st, a, ring_a[ni], ring_a[i], ctr, col_a, col_a, col_a)
		_add_outward_tri(st, b, ring_b[i], ring_b[ni], ctr, col_b, col_b, col_b)


static func _append_cone_spike(st: SurfaceTool, base: Vector3, tip: Vector3,
		radius: float, base_col: Color, tip_col: Color) -> void:
	var axis := tip - base
	if axis.length_squared() < 1e-6:
		return
	var dir := axis.normalized()
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.85 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := u.cross(dir).normalized()
	var segs := 5
	var ring: Array[Vector3] = []
	for i in segs:
		var ang := float(i) / float(segs) * TAU
		ring.append(base + (u * cos(ang) + v * sin(ang)) * radius)
	var ctr := base.lerp(tip, 0.35)
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_tri(st, tip, ring[i], ring[ni], ctr, tip_col, base_col, base_col)
		_add_outward_tri(st, base, ring[ni], ring[i], ctr, base_col, base_col, base_col)


static func _append_faceted_box(st: SurfaceTool, center: Vector3, half_ext: Vector3, col: Color) -> void:
	var hx := half_ext.x
	var hy := half_ext.y
	var hz := half_ext.z
	var b0 := center + Vector3(-hx, -hy, -hz)
	var b1 := center + Vector3(hx, -hy, -hz)
	var b2 := center + Vector3(hx, -hy, hz)
	var b3 := center + Vector3(-hx, -hy, hz)
	var t0 := center + Vector3(-hx * 0.88, hy, -hz * 0.88)
	var t1 := center + Vector3(hx * 0.88, hy, -hz * 0.88)
	var t2 := center + Vector3(hx * 0.88, hy, hz * 0.88)
	var t3 := center + Vector3(-hx * 0.88, hy, hz * 0.88)
	var top_col := col.lightened(0.08)
	var bot_col := col.darkened(0.18)
	_add_outward_quad_grad(st, t0, t1, t2, t3, center, top_col, top_col, top_col, top_col)
	_add_outward_quad_grad(st, b3, b2, b1, b0, center, bot_col, bot_col, bot_col, bot_col)
	_add_outward_quad_grad(st, t0, t1, b1, b0, center, top_col, top_col, col, col)
	_add_outward_quad_grad(st, t1, t2, b2, b1, center, top_col, top_col, col, col)
	_add_outward_quad_grad(st, t2, t3, b3, b2, center, top_col, top_col, col, col)
	_add_outward_quad_grad(st, t3, t0, b0, b3, center, top_col, top_col, col, col)


static func _add_outward_quad_grad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_add_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tmp_v := b
		b = c
		c = tmp_v
		var tmp_c := cb
		cb = cc
		cc = tmp_c
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(ca); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc); st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(c)
