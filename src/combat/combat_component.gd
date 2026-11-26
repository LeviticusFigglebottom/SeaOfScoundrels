class_name CombatComponent
extends Node
## Weighty melee and ranged combat component. Attach as a child of any `Pawn`.
##
## Features:
## - Light 3-hit melee combo chain with lunge momentum, windup, active, and recovery windows.
## - Heavy charged slash that breaks guards and deals heavy stagger.
## - Block + generous timed parry window (first 0.24 s): parrying sparks, rings, refunds
##   stamina, and staggers the attacker for 1.65 s (taking 1.5x damage).
## - Directional dodge step with brief i-frames and stamina cost.
## - Distinct weapons: Cutlass, Boarding Axe, Flintlock Pistol, Blunderbuss, Tide Staff.
## - Host-authoritative hit resolution with Godot 4.8 non-allocating `intersect_ray_into`.

signal attack_started(kind: StringName)
signal hit_landed(target: Pawn, damage: float, was_heavy: bool)
signal blocked(attacker: Pawn)
signal parried(attacker: Pawn)
signal staggered(duration: float)
signal ranged_fired(weapon: StringName, origin: Vector3, hit_pos: Vector3)
signal weapon_changed(weapon: StringName)

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, BLOCKING, STAGGERED, DODGING, RELOADING }

const PARRY_WINDOW := 0.24
const STAGGER_DURATION := 1.65
const DODGE_DURATION := 0.28
const DODGE_IFRAMES := 0.24
const STAMINA_REGEN_DELAY := 0.65
const STAMINA_REGEN_RATE := 30.0

const WEAPONS := {
	&"cutlass": {
		"type": &"melee", "light_dmg": [18.0, 20.0, 28.0], "heavy_dmg": 44.0,
		"reach": 2.45, "arc_cos": 0.25, "windup": 0.14, "active": 0.14, "recovery": 0.22,
		"heavy_windup": 0.34, "heavy_recovery": 0.36, "cleaves_shield": false, "lunge": 4.2,
	},
	&"boarding_axe": {
		"type": &"melee", "light_dmg": [28.0, 34.0, 42.0], "heavy_dmg": 58.0,
		"reach": 2.35, "arc_cos": 0.30, "windup": 0.22, "active": 0.16, "recovery": 0.30,
		"heavy_windup": 0.44, "heavy_recovery": 0.46, "cleaves_shield": true, "lunge": 3.4,
	},
	&"pistol": {
		"type": &"ranged", "damage": 45.0, "range": 42.0, "pellets": 1, "spread_deg": 0.8,
		"reload": 1.65, "knockback": 3.5, "ammo_max": 6,
	},
	&"blunderbuss": {
		"type": &"ranged", "damage": 13.0, "range": 16.0, "pellets": 6, "spread_deg": 11.0,
		"reload": 2.15, "knockback": 7.5, "ammo_max": 5,
	},
	&"tide_staff": {
		"type": &"ranged", "damage": 24.0, "range": 34.0, "pellets": 1, "spread_deg": 1.8,
		"reload": 1.9, "knockback": 4.0, "ammo_max": 99,
	},
}

@export var faction: StringName = &"player"
@export var equipped_weapon: StringName = &"cutlass"
@export var max_stamina: float = 100.0
## True for shield-bearing enemies (blocks frontal light strikes unless flanked/heavy/staggered).
@export var has_shield: bool = false
## Outgoing damage multiplier (buffed by Drowned Captain rally!).
var damage_multiplier: float = 1.0

var pawn: Pawn = null
var state: State = State.IDLE
var stamina: float = 100.0
var ammo: int = 6
var combo_step: int = 0
var is_blocking: bool = false

var _state_timer: float = 0.0
var _block_elapsed: float = 0.0
var _combo_reset_timer: float = 0.0
var _stamina_delay: float = 0.0
var _iframe_timer: float = 0.0
var _attack_is_heavy: bool = false
var _hit_this_swing: Dictionary = {}
var _dodge_dir: Vector3 = Vector3.ZERO
var _buff_timer: float = 0.0
var _ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ray_result: PhysicsIntersectRayResult3D = PhysicsIntersectRayResult3D.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	pawn = get_parent() as Pawn
	assert(pawn != null, "CombatComponent must be a child of a Pawn")
	stamina = max_stamina
	_rng.randomize()
	_ray_params.collision_mask = Pawn.LAYER_WORLD | Pawn.LAYER_SHIP | Pawn.LAYER_PAWN
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true
	add_to_group(&"combatants")


func equip_weapon(weapon_id: StringName) -> void:
	if not WEAPONS.has(weapon_id) or equipped_weapon == weapon_id:
		return
	equipped_weapon = weapon_id
	var spec: Dictionary = WEAPONS[weapon_id]
	if spec["type"] == &"ranged":
		ammo = int(spec.get("ammo_max", 6))
	weapon_changed.emit(weapon_id)


func refill_ammo() -> void:
	var spec: Dictionary = WEAPONS.get(equipped_weapon, {})
	ammo = int(spec.get("ammo_max", 6))


func apply_rally_buff(duration: float = 8.0, mult: float = 1.35) -> void:
	_buff_timer = maxf(_buff_timer, duration)
	damage_multiplier = maxf(damage_multiplier, mult)


func is_staggered() -> bool:
	return state == State.STAGGERED


func is_in_parry_window() -> bool:
	return state == State.BLOCKING and _block_elapsed <= PARRY_WINDOW


func is_invulnerable() -> bool:
	return _iframe_timer > 0.0


# ------------------------------------------------------------------ player / AI actions

## Host only. Start a light melee strike or fire the equipped ranged weapon.
func primary_attack() -> bool:
	if not Net.is_host() or pawn == null or pawn.dead or pawn.station != null:
		return false
	if state == State.STAGGERED or state == State.DODGING or state == State.RELOADING:
		return false
	var spec: Dictionary = WEAPONS.get(equipped_weapon, WEAPONS[&"cutlass"])
	if spec["type"] == &"ranged":
		return _fire_ranged(spec)
	if state != State.IDLE and state != State.BLOCKING and not (state == State.RECOVERY and _state_timer < 0.14):
		return false
	is_blocking = false
	_attack_is_heavy = false
	combo_step = (combo_step % 3) + 1
	_combo_reset_timer = 1.1
	_hit_this_swing.clear()
	state = State.WINDUP
	_state_timer = float(spec["windup"])
	var anim := StringName("slash_%d" % combo_step)
	_play_anim(anim, float(spec["windup"]) + float(spec["active"]) + float(spec["recovery"]))
	attack_started.emit(anim)
	return true


## Host only. Heavy charged melee strike (breaks shields/blocks, high stagger).
func heavy_attack() -> bool:
	if not Net.is_host() or pawn == null or pawn.dead or pawn.station != null:
		return false
	if state != State.IDLE and state != State.BLOCKING:
		return false
	var spec: Dictionary = WEAPONS.get(equipped_weapon, WEAPONS[&"cutlass"])
	if spec["type"] != &"melee":
		return primary_attack()
	if not _spend_stamina(24.0):
		return false
	is_blocking = false
	_attack_is_heavy = true
	combo_step = 0
	_hit_this_swing.clear()
	state = State.WINDUP
	_state_timer = float(spec["heavy_windup"])
	_play_anim(&"heavy", float(spec["heavy_windup"]) + float(spec["active"]) + float(spec["heavy_recovery"]))
	attack_started.emit(&"heavy")
	return true


## Host only. Hold or release block; first PARRY_WINDOW seconds act as a timed parry.
func set_blocking(on: bool) -> void:
	if not Net.is_host() or pawn == null or pawn.dead:
		return
	if on:
		if state == State.IDLE:
			state = State.BLOCKING
			is_blocking = true
			_block_elapsed = 0.0
			_play_anim(&"block", 0.35)
	else:
		is_blocking = false
		if state == State.BLOCKING:
			state = State.IDLE


## Host only. Quick directional dodge step with brief i-frames.
func dodge_step(world_dir: Vector3 = Vector3.ZERO) -> bool:
	if not Net.is_host() or pawn == null or pawn.dead or pawn.station != null:
		return false
	if state == State.STAGGERED or state == State.DODGING:
		return false
	if not _spend_stamina(22.0):
		return false
	is_blocking = false
	var d := Vector3(world_dir.x, 0.0, world_dir.z)
	if d.length_squared() < 0.01:
		d = -pawn.facing()
	_dodge_dir = d.normalized()
	state = State.DODGING
	_state_timer = DODGE_DURATION
	_iframe_timer = DODGE_IFRAMES
	_play_anim(&"dodge", DODGE_DURATION)
	return true


## Host only. Force stagger state (e.g. after being parried or hit by a guard-break).
func apply_stagger(duration: float = STAGGER_DURATION) -> void:
	if not Net.is_host() or pawn == null or pawn.dead:
		return
	is_blocking = false
	state = State.STAGGERED
	_state_timer = maxf(_state_timer, duration)
	_play_anim(&"stagger", duration)
	staggered.emit(duration)


## Host only. Receive an incoming melee strike from `attacker_cc`.
## Returns &"parried", &"blocked", &"dodged", or &"hit".
func receive_melee_hit(attacker_cc: CombatComponent, raw_damage: float, is_heavy: bool, cleaves_shield: bool) -> StringName:
	if not Net.is_host() or pawn == null or pawn.dead:
		return &"dodged"
	if is_invulnerable():
		return &"dodged"

	var attacker_pawn := attacker_cc.pawn if attacker_cc != null else null
	var frontal := true
	if attacker_pawn != null:
		var to_atk := attacker_pawn.global_position - pawn.global_position
		to_atk.y = 0.0
		if to_atk.length_squared() > 0.001:
			frontal = to_atk.normalized().dot(pawn.facing()) > 0.15

	# 1. Timed Parry (beats light and heavy strikes when facing attacker!).
	if frontal and is_in_parry_window():
		stamina = minf(max_stamina, stamina + 26.0)
		_play_anim(&"parry", 0.35)
		Audio.play_sfx(&"parry_ring", pawn.eye_position())
		_spawn_parry_sparks(pawn.eye_position() + pawn.facing() * 0.65)
		if attacker_cc != null:
			attacker_cc.apply_stagger(STAGGER_DURATION)
		parried.emit(attacker_pawn)
		return &"parried"

	# 2. Active Block or Shield-bearer passive frontal guard.
	var guarding := frontal and not is_staggered() and (state == State.BLOCKING or has_shield)
	if guarding:
		if is_heavy or cleaves_shield:
			# Guard broken!
			Audio.play_sfx(&"sword_clash", pawn.eye_position())
			apply_stagger(1.1)
			pawn.apply_damage(raw_damage * 0.55, attacker_pawn)
			return &"hit"
		if state == State.BLOCKING and stamina < 14.0:
			# Out of stamina -> guard breaks!
			stamina = 0.0
			apply_stagger(1.0)
			pawn.apply_damage(raw_damage * 0.5, attacker_pawn)
			return &"hit"
		if state == State.BLOCKING:
			_spend_stamina(16.0)
		Audio.play_sfx(&"sword_clash", pawn.eye_position())
		_spawn_parry_sparks(pawn.eye_position() + pawn.facing() * 0.55, Color(1.0, 0.82, 0.4))
		blocked.emit(attacker_pawn)
		return &"blocked"

	# 3. Clean Hit (1.5x damage if currently staggered!).
	var mult := 1.5 if is_staggered() else 1.0
	var dmg := raw_damage * mult
	pawn.apply_damage(dmg, attacker_pawn)
	Audio.play_sfx(&"hit_flesh", pawn.eye_position())
	if attacker_pawn != null:
		var push := pawn.global_position - attacker_pawn.global_position
		push.y = 0.0
		if push.length_squared() > 0.001:
			pawn.velocity += push.normalized() * (5.5 if is_heavy else 2.8)
	if is_heavy and not pawn.dead:
		apply_stagger(0.75)
	return &"hit"


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if pawn == null or pawn.dead:
		return
	_iframe_timer = maxf(0.0, _iframe_timer - delta)
	_stamina_delay = maxf(0.0, _stamina_delay - delta)
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			damage_multiplier = 1.0
	if _combo_reset_timer > 0.0:
		_combo_reset_timer -= delta
		if _combo_reset_timer <= 0.0:
			combo_step = 0
	if _stamina_delay <= 0.0 and state != State.BLOCKING and state != State.DODGING:
		stamina = minf(max_stamina, stamina + STAMINA_REGEN_RATE * delta)

	if not Net.is_host():
		return

	match state:
		State.WINDUP:
			_state_timer -= delta
			if _state_timer <= 0.0:
				var spec: Dictionary = WEAPONS.get(equipped_weapon, WEAPONS[&"cutlass"])
				state = State.ACTIVE
				_state_timer = float(spec["active"])
				# Forward lunge momentum on melee release!
				var lunge := float(spec.get("lunge", 3.5)) * (1.35 if _attack_is_heavy else 1.0)
				pawn.velocity += pawn.facing() * lunge
				Audio.play_sfx(&"sword_swing", pawn.eye_position())
				_check_melee_hits(spec)
		State.ACTIVE:
			var spec: Dictionary = WEAPONS.get(equipped_weapon, WEAPONS[&"cutlass"])
			_check_melee_hits(spec)
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.RECOVERY
				_state_timer = float(spec["heavy_recovery"] if _attack_is_heavy else spec["recovery"])
		State.RECOVERY, State.STAGGERED, State.RELOADING:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.IDLE
		State.BLOCKING:
			_block_elapsed += delta
			if not is_blocking:
				state = State.IDLE
		State.DODGING:
			pawn.velocity.x = _dodge_dir.x * 8.6
			pawn.velocity.z = _dodge_dir.z * 8.6
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.IDLE
		State.IDLE:
			pass


func _check_melee_hits(spec: Dictionary) -> void:
	var reach := float(spec["reach"]) * (1.15 if _attack_is_heavy else 1.0)
	var arc_cos := float(spec["arc_cos"])
	var cleave := bool(spec.get("cleaves_shield", false))
	var dmg: float = float(spec["heavy_dmg"]) if _attack_is_heavy else float((spec["light_dmg"] as Array)[clampi(combo_step - 1, 0, 2)])
	dmg *= damage_multiplier

	var my_pos := pawn.global_position + Vector3.UP * 1.0
	var fwd := pawn.facing()

	for node in get_tree().get_nodes_in_group(&"combatants"):
		var other_cc := node as CombatComponent
		if other_cc == null or other_cc == self or other_cc.faction == faction:
			continue
		var other_pawn := other_cc.pawn
		if other_pawn == null or other_pawn.dead:
			continue
		var oid := other_pawn.get_instance_id()
		if _hit_this_swing.has(oid):
			continue
		var delta_v := (other_pawn.global_position + Vector3.UP * 1.0) - my_pos
		if absf(delta_v.y) > 1.75:
			continue
		var flat := Vector3(delta_v.x, 0.0, delta_v.z)
		var dist := flat.length()
		if dist > reach:
			continue
		if dist > 0.25 and flat.normalized().dot(fwd) < arc_cos:
			continue
		_hit_this_swing[oid] = true
		var outcome := other_cc.receive_melee_hit(self, dmg, _attack_is_heavy, cleave)
		if outcome == &"hit":
			hit_landed.emit(other_pawn, dmg, _attack_is_heavy)
		elif outcome == &"parried":
			# Immediately stop swinging if parried!
			return


func _fire_ranged(spec: Dictionary) -> bool:
	if ammo <= 0:
		Audio.play_sfx(&"lantern_click", pawn.eye_position(), -4.0)
		return false
	ammo -= 1
	state = State.RELOADING
	_state_timer = float(spec["reload"])

	var origin := pawn.eye_position()
	var base_dir := pawn.view_dir()
	var max_range := float(spec["range"])
	var pellets := int(spec["pellets"])
	var spread := deg_to_rad(float(spec["spread_deg"]))
	var dmg := float(spec["damage"]) * damage_multiplier
	var kb := float(spec["knockback"])

	_play_anim(&"fire_pistol", 0.45)
	if equipped_weapon == &"tide_staff":
		Audio.play_sfx(&"splash_small", origin, 2.0)
	else:
		Audio.play_sfx(&"pistol_shot", origin)

	var world := pawn.get_world_3d()
	var last_hit := origin + base_dir * max_range
	_ray_params.exclude = [pawn.get_rid()]

	for _p in pellets:
		var dir := base_dir
		if spread > 0.001:
			var rx := _rng.randf_range(-spread, spread)
			var ry := _rng.randf_range(-spread, spread)
			dir = (dir + pawn.global_basis.x * rx + Vector3.UP * ry).normalized()
		var end := origin + dir * max_range
		var hit_pos := end
		if world != null:
			_ray_params.from = origin
			_ray_params.to = end
			if world.direct_space_state.intersect_ray_into(_ray_params, _ray_result):
				hit_pos = _ray_result.position
				var col := _ray_result.collider
				if col is Pawn:
					var target_p := col as Pawn
					var target_cc := _combat_of(target_p)
					if target_cc == null or target_cc.faction != faction:
						if target_cc == null or not target_cc.is_invulnerable():
							target_p.apply_damage(dmg, pawn)
							target_p.velocity += dir * kb
							Audio.play_sfx(&"hit_flesh", hit_pos)
							hit_landed.emit(target_p, dmg, false)
							# Shooting a Powder-Carrier detonates its keg!
							var brain := target_p.get_node_or_null(^"EnemyBrain")
							if brain != null and brain.has_method(&"on_shot_hit"):
								brain.call(&"on_shot_hit", pawn)
		last_hit = hit_pos

	_spawn_muzzle_puff(origin + base_dir * 0.6, Color(0.35, 0.95, 0.88, 0.85) if equipped_weapon == &"tide_staff" else Color(0.95, 0.88, 0.72, 0.78))
	ranged_fired.emit(equipped_weapon, origin, last_hit)
	attack_started.emit(equipped_weapon)
	return true


func _spend_stamina(cost: float) -> bool:
	if stamina < cost:
		return false
	stamina -= cost
	_stamina_delay = STAMINA_REGEN_DELAY
	return true


func _play_anim(action: StringName, duration: float) -> void:
	if pawn == null:
		return
	var drv := pawn.get_node_or_null(^"Visual/AnimationDriver")
	if drv == null:
		drv = pawn.get_node_or_null(^"AnimationDriver")
	if drv != null and drv.has_method(&"play_action"):
		drv.call(&"play_action", action, duration)


static func _combat_of(p: Pawn) -> CombatComponent:
	for c in p.get_children():
		if c is CombatComponent:
			return c as CombatComponent
	return null


func _spawn_parry_sparks(pos: Vector3, tint: Color = Color(1.0, 0.62, 0.14)) -> void:
	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.96
	p.amount = 18
	p.lifetime = 0.35
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 110.0
	proc.initial_velocity_min = 3.0
	proc.initial_velocity_max = 7.5
	proc.gravity = Vector3(0.0, -12.0, 0.0)
	p.process_material = proc
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 0.035, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	box.material = mat
	p.draw_pass_1 = box
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func _spawn_muzzle_puff(pos: Vector3, tint: Color) -> void:
	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 10
	p.lifetime = 0.45
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.direction = pawn.view_dir()
	proc.spread = 28.0
	proc.initial_velocity_min = 1.5
	proc.initial_velocity_max = 4.5
	proc.gravity = Vector3(0.0, 1.2, 0.0)
	p.process_material = proc
	var sp := SphereMesh.new()
	sp.radius = 0.12
	sp.height = 0.24
	sp.radial_segments = 6
	sp.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sp.material = mat
	p.draw_pass_1 = sp
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
