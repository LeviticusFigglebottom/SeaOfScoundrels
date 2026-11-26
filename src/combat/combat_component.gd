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
signal target_hit(target: Node, damage: float, was_heavy: bool)
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
const SLASH_ARC_DURATION := 0.19
const SLASH_ARC_SEGMENTS := 16
const HITSTOP_LIGHT := 0.024
const HITSTOP_HEAVY := 0.042

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
## Toggle combat spark/muzzle particle VFX & camera recoil punch.
@export var enable_effects: bool = true
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
var _recoil_pulse: float = 0.0
var _recoil_strength: float = 0.0
var _recoil_sign: float = 1.0
var _hitstop_timer: float = 0.0
var _player_controller: PlayerController = null
var _inventory: Node = null
var _ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ray_result: PhysicsIntersectRayResult3D = PhysicsIntersectRayResult3D.new()
var _shape_params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _melee_sphere: SphereShape3D = SphereShape3D.new()
var _rng := RandomNumberGenerator.new()
var _active_vfx: Array[Node] = []
var _slash_arcs: Array[Dictionary] = []

static var _active_combatants: int = 0
static var _spark_tex: ImageTexture = null
static var _flash_tex: GradientTexture2D = null
static var _ember_tex: ImageTexture = null
static var _slash_arc_mesh: ArrayMesh = null


func _init() -> void:
	# Run after PlayerController (0) and Inventory (10) so visual recoil layers cleanly.
	process_priority = 15


func _enter_tree() -> void:
	_active_combatants += 1


func _exit_tree() -> void:
	_cleanup_all_vfx()
	_active_combatants = maxi(0, _active_combatants - 1)
	if _active_combatants == 0:
		clear_shared_vfx_cache()


## Release all statically cached CombatComponent VFX meshes & textures cleanly.
static func clear_shared_vfx_cache() -> void:
	_spark_tex = null
	_flash_tex = null
	_ember_tex = null
	_slash_arc_mesh = null


func _ready() -> void:
	pawn = get_parent() as Pawn
	assert(pawn != null, "CombatComponent must be a child of a Pawn")
	stamina = max_stamina
	_rng.randomize()
	_ray_params.collision_mask = Pawn.LAYER_WORLD | Pawn.LAYER_SHIP | Pawn.LAYER_PAWN
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true
	_shape_params.shape = _melee_sphere
	_shape_params.collision_mask = Pawn.LAYER_PAWN | (1 << 5)
	_shape_params.collide_with_areas = false
	_shape_params.collide_with_bodies = true
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


## Remaining deterministic visual micro-hitstop duration in seconds (never touches Engine.time_scale).
func get_hitstop_remaining() -> float:
	return _hitstop_timer


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

	var clash_pos := pawn.eye_position() + pawn.facing() * 0.60
	if attacker_pawn != null:
		clash_pos = (pawn.eye_position() + attacker_pawn.eye_position()) * 0.5 + Vector3.DOWN * 0.15

	# 1. Timed Parry (beats light and heavy strikes when facing attacker!).
	if frontal and is_in_parry_window():
		stamina = minf(max_stamina, stamina + 26.0)
		_play_anim(&"parry", 0.35)
		Audio.play_sfx(&"parry_ring", pawn.eye_position())
		_spawn_clash_vfx(clash_pos, &"parried")
		_trigger_hitstop(HITSTOP_HEAVY, 0.30, 1.0)
		if attacker_cc != null:
			attacker_cc._trigger_hitstop(HITSTOP_HEAVY, 0.26, 0.80)
			attacker_cc.apply_stagger(STAGGER_DURATION)
		parried.emit(attacker_pawn)
		return &"parried"

	# 2. Active Block or Shield-bearer passive frontal guard.
	var guarding := frontal and not is_staggered() and (state == State.BLOCKING or has_shield)
	if guarding:
		if is_heavy or cleaves_shield:
			# Guard broken!
			Audio.play_sfx(&"sword_clash", pawn.eye_position())
			_spawn_clash_vfx(clash_pos, &"heavy")
			_trigger_hitstop(HITSTOP_HEAVY, 0.24, 0.85)
			if attacker_cc != null:
				attacker_cc._trigger_hitstop(HITSTOP_HEAVY, 0.28, 0.90)
			apply_stagger(1.1)
			pawn.apply_damage(raw_damage * 0.55, attacker_pawn)
			return &"hit"
		if state == State.BLOCKING and stamina < 14.0:
			# Out of stamina -> guard breaks!
			stamina = 0.0
			_spawn_clash_vfx(clash_pos, &"heavy")
			_trigger_hitstop(HITSTOP_HEAVY, 0.22, 0.75)
			if attacker_cc != null:
				attacker_cc._trigger_hitstop(HITSTOP_HEAVY, 0.24, 0.80)
			apply_stagger(1.0)
			pawn.apply_damage(raw_damage * 0.5, attacker_pawn)
			return &"hit"
		if state == State.BLOCKING:
			_spend_stamina(16.0)
		Audio.play_sfx(&"sword_clash", pawn.eye_position())
		_spawn_clash_vfx(clash_pos, &"blocked")
		_trigger_recoil_pulse(0.45)
		blocked.emit(attacker_pawn)
		return &"blocked"

	# 3. Clean Hit (1.5x damage if currently staggered!).
	var mult := 1.5 if is_staggered() else 1.0
	var dmg := raw_damage * mult
	pawn.apply_damage(dmg, attacker_pawn)
	Audio.play_sfx(&"hit_flesh", pawn.eye_position())
	var is_combo_finisher := attacker_cc != null and not is_heavy and attacker_cc.combo_step == 3
	var is_big_hit := is_heavy or is_combo_finisher
	if is_big_hit:
		_spawn_clash_vfx(clash_pos, &"heavy")
	_trigger_hitstop(
		HITSTOP_HEAVY if is_big_hit else HITSTOP_LIGHT,
		0.24 if is_heavy else (0.20 if is_combo_finisher else 0.16),
		0.65 if is_heavy else (0.45 if is_combo_finisher else 0.32)
	)
	if attacker_cc != null:
		attacker_cc._trigger_hitstop(
			HITSTOP_HEAVY if is_big_hit else HITSTOP_LIGHT,
			0.28 if is_heavy else (0.22 if is_combo_finisher else 0.16),
			0.88 if is_heavy else (0.60 if is_combo_finisher else 0.42)
		)
	if attacker_pawn != null:
		var push := pawn.global_position - attacker_pawn.global_position
		push.y = 0.0
		if push.length_squared() > 0.001:
			pawn.velocity += push.normalized() * (5.5 if is_heavy else 2.8)
	if is_heavy and not pawn.dead:
		apply_stagger(0.75)
	return &"hit"


# ------------------------------------------------------------------ simulation

func _process(delta: float) -> void:
	var in_hitstop := _hitstop_timer > 0.0
	if in_hitstop:
		_hitstop_timer = maxf(0.0, _hitstop_timer - delta)
	# Briefly slow active slash-arc sweep during visual hitstop so the blade visually bites on impact.
	_tick_slash_arcs(delta * 0.18 if in_hitstop else delta)

	if _recoil_pulse <= 0.0005 and not in_hitstop:
		_recoil_strength = 0.0
		return
	if in_hitstop:
		# Hold recoil kick at peak tension during the micro-hitstop window, then snap into recovery.
		_recoil_pulse = maxf(_recoil_pulse, 0.56)
	else:
		_recoil_pulse = maxf(0.0, _recoil_pulse - delta * 7.2)

	if not _can_spawn_vfx() or pawn == null or _is_reduced_motion():
		return

	var kick := sin(_recoil_pulse * PI) * _recoil_strength
	var pc := _get_player_controller()
	if pc != null and pc.camera != null:
		var xf := pc.camera.transform
		xf.basis = xf.basis * Basis(Vector3.RIGHT, 0.026 * kick) * Basis(Vector3.BACK, 0.032 * _recoil_sign * kick)
		xf.origin += xf.basis.z * (0.028 * kick)
		pc.camera.transform = xf

	# Layer crisp weapon-tension recoil jolt onto the first-person viewmodel (after Inventory._process).
	var inv := _get_inventory()
	if inv != null:
		var fp_node: Variant = inv.get(&"fp_tool_node")
		if fp_node is Node3D and is_instance_valid(fp_node):
			var fp3 := fp_node as Node3D
			var tense := 1.15 if in_hitstop else 1.0
			fp3.position += Vector3(-0.024 * _recoil_sign * kick * tense, 0.018 * kick * tense, 0.055 * kick * tense)
			fp3.rotation_degrees += Vector3(9.5 * kick * tense, -7.0 * _recoil_sign * kick * tense, -11.0 * _recoil_sign * kick * tense)

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
				_spawn_slash_arc(_current_slash_arc_style())
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

	# 1. CombatComponent pawns & duck-typed nodes registered in group `combatants`.
	for node in get_tree().get_nodes_in_group(&"combatants"):
		if node is CombatComponent:
			var other_cc := node as CombatComponent
			if other_cc == self or other_cc.faction == faction:
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
				target_hit.emit(other_pawn, dmg, _attack_is_heavy)
			elif outcome == &"parried":
				# Immediately stop swinging if parried!
				return
		elif node is Node3D:
			_try_melee_hit_damageable(node as Node3D, my_pos, fwd, reach + 0.35, arc_cos, dmg, cleave)

	# 2. Physics-backed non-Pawn targets (IslandCrab, ReefEel, Leviathan tentacles, etc.).
	var world := pawn.get_world_3d()
	if world != null:
		_melee_sphere.radius = reach + 0.45
		_shape_params.transform = Transform3D(Basis.IDENTITY, my_pos + fwd * (reach * 0.45))
		_shape_params.exclude = [pawn.get_rid()]
		var hits := world.direct_space_state.intersect_shape(_shape_params, 16)
		for h: Dictionary in hits:
			var col: Object = h.get("collider", null)
			if col == null:
				continue
			if col is Node and (col as Node).has_meta("leviathan"):
				_try_melee_hit_leviathan(col as Node, my_pos, fwd, reach + 0.85, arc_cos, dmg)
				continue
			var target_node := _resolve_damageable(col)
			if target_node is Node3D:
				if target_node is Pawn and _combat_of(target_node as Pawn) != null:
					continue
				_try_melee_hit_damageable(target_node as Node3D, my_pos, fwd, reach + 0.45, arc_cos, dmg, cleave)

	# 3. Wildlife/beast nodes in common groups (e.g. Shark, IslandCrab, ReefEel).
	for grp: StringName in [&"sharks", &"wildlife", &"beasts", &"enemies"]:
		for node in get_tree().get_nodes_in_group(grp):
			if not (node is Node3D):
				continue
			if node is Pawn and _combat_of(node as Pawn) != null:
				continue
			_try_melee_hit_damageable(node as Node3D, my_pos, fwd, reach + 0.65, arc_cos, dmg, cleave)


func _try_melee_hit_damageable(
	target: Node3D,
	my_pos: Vector3,
	fwd: Vector3,
	eff_reach: float,
	arc_cos: float,
	dmg: float,
	cleave: bool
) -> bool:
	if target == null or target == pawn or not target.has_method(&"apply_damage"):
		return false
	if not _is_hostile_target(target):
		return false
	var tid := target.get_instance_id()
	if _hit_this_swing.has(tid):
		return false
	var target_center := target.global_position + Vector3.UP * 0.45
	var delta_v := target_center - my_pos
	if absf(delta_v.y) > 2.0:
		return false
	var flat := Vector3(delta_v.x, 0.0, delta_v.z)
	var dist := flat.length()
	if dist > eff_reach:
		return false
	if dist > 0.35 and flat.normalized().dot(fwd) < arc_cos:
		return false
	_hit_this_swing[tid] = true

	var landed := true
	if target.has_method(&"receive_melee_hit"):
		var outcome: Variant = target.call(&"receive_melee_hit", self, dmg, _attack_is_heavy, cleave)
		landed = StringName(outcome) == &"hit"
	else:
		_call_apply_damage(target, dmg, pawn)
		Audio.play_sfx(&"hit_flesh", target_center)
		if target is CharacterBody3D and flat.length_squared() > 0.001:
			(target as CharacterBody3D).velocity += flat.normalized() * (5.2 if _attack_is_heavy else 2.6)

	if landed:
		var is_big := _attack_is_heavy or combo_step == 3
		if is_big:
			_spawn_clash_vfx(my_pos.lerp(target_center, 0.65), &"heavy")
		_trigger_hitstop(
			HITSTOP_HEAVY if is_big else HITSTOP_LIGHT,
			0.26 if _attack_is_heavy else (0.22 if combo_step == 3 else 0.16),
			0.88 if _attack_is_heavy else (0.58 if combo_step == 3 else 0.42)
		)
		if target is Pawn:
			hit_landed.emit(target as Pawn, dmg, _attack_is_heavy)
		target_hit.emit(target, dmg, _attack_is_heavy)
	return landed


func _try_melee_hit_leviathan(
	hitbox: Node,
	my_pos: Vector3,
	fwd: Vector3,
	eff_reach: float,
	arc_cos: float,
	dmg: float
) -> bool:
	var tid := hitbox.get_instance_id()
	if _hit_this_swing.has(tid):
		return false
	var lev: Variant = hitbox.get_meta("leviathan")
	if lev == null or not is_instance_valid(lev) or not (lev as Object).has_method(&"damage_tentacle"):
		return false
	var hit_pos := (hitbox as Node3D).global_position if hitbox is Node3D else my_pos + fwd
	var flat := Vector3(hit_pos.x - my_pos.x, 0.0, hit_pos.z - my_pos.z)
	var dist := flat.length()
	if dist > eff_reach or (dist > 0.4 and flat.normalized().dot(fwd) < arc_cos):
		return false
	_hit_this_swing[tid] = true
	var t_idx := int(hitbox.get_meta("tentacle_index", -1))
	(lev as Object).call(&"damage_tentacle", t_idx, dmg)
	var is_big := _attack_is_heavy or combo_step == 3
	if is_big:
		_spawn_clash_vfx(my_pos.lerp(hit_pos, 0.6), &"heavy")
	_trigger_hitstop(
		HITSTOP_HEAVY if is_big else HITSTOP_LIGHT,
		0.28 if _attack_is_heavy else 0.18,
		0.88 if _attack_is_heavy else 0.48
	)
	if lev is Node:
		target_hit.emit(lev as Node, dmg, _attack_is_heavy)
	return true


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
		var struck_entity := false
		if world != null:
			_ray_params.from = origin
			_ray_params.to = end
			if world.direct_space_state.intersect_ray_into(_ray_params, _ray_result):
				hit_pos = _ray_result.position
				var col := _ray_result.collider
				if col is Pawn:
					struck_entity = true
					var target_p := col as Pawn
					var target_cc := _combat_of(target_p)
					if target_cc == null or target_cc.faction != faction:
						if target_cc == null or not target_cc.is_invulnerable():
							target_p.apply_damage(dmg, pawn)
							target_p.velocity += dir * kb
							Audio.play_sfx(&"hit_flesh", hit_pos)
							hit_landed.emit(target_p, dmg, false)
							target_hit.emit(target_p, dmg, false)
							# Shooting a Powder-Carrier detonates its keg!
							var brain := target_p.get_node_or_null(^"EnemyBrain")
							if brain != null and brain.has_method(&"on_shot_hit"):
								brain.call(&"on_shot_hit", pawn)
				elif col is Node and (col as Node).has_meta("leviathan"):
					var lev: Variant = (col as Node).get_meta("leviathan")
					if lev != null and is_instance_valid(lev) and (lev as Object).has_method(&"damage_tentacle"):
						struck_entity = true
						var t_idx := int((col as Node).get_meta("tentacle_index", -1))
						(lev as Object).call(&"damage_tentacle", t_idx, dmg)
						if lev is Node:
							target_hit.emit(lev as Node, dmg, false)
				else:
					var dmg_node := _resolve_damageable(col)
					if dmg_node != null and _is_hostile_target(dmg_node):
						struck_entity = true
						_call_apply_damage(dmg_node, dmg, pawn)
						if dmg_node is CharacterBody3D:
							(dmg_node as CharacterBody3D).velocity += dir * kb
						Audio.play_sfx(&"hit_flesh", hit_pos)
						target_hit.emit(dmg_node, dmg, false)
		if not struck_entity:
			hit_pos = _check_ranged_soft_targets(origin, dir, origin.distance_to(hit_pos), dmg, kb)
		last_hit = hit_pos

	_spawn_muzzle_puff(origin + base_dir * 0.6, Color(0.35, 0.95, 0.88, 0.85) if equipped_weapon == &"tide_staff" else Color(0.95, 0.88, 0.72, 0.78))
	ranged_fired.emit(equipped_weapon, origin, last_hit)
	attack_started.emit(equipped_weapon)
	return true


func _check_ranged_soft_targets(origin: Vector3, dir: Vector3, max_dist: float, dmg: float, kb: float) -> Vector3:
	var best_node: Node3D = null
	var best_t := max_dist
	for grp: StringName in [&"sharks", &"wildlife", &"beasts", &"combatants"]:
		for node in get_tree().get_nodes_in_group(grp):
			if not (node is Node3D) or node is CollisionObject3D:
				continue
			if not node.has_method(&"apply_damage") or not _is_hostile_target(node):
				continue
			var n3 := node as Node3D
			var to_n := n3.global_position - origin
			var t := to_n.dot(dir)
			if t <= 0.15 or t >= best_t:
				continue
			var closest := origin + dir * t
			if closest.distance_squared_to(n3.global_position) <= 1.25 * 1.25:
				best_t = t
				best_node = n3
	if best_node != null:
		var hit_pos := origin + dir * best_t
		_call_apply_damage(best_node, dmg, pawn)
		if best_node is CharacterBody3D:
			(best_node as CharacterBody3D).velocity += dir * kb
		Audio.play_sfx(&"hit_flesh", hit_pos)
		target_hit.emit(best_node, dmg, false)
		return hit_pos
	return origin + dir * max_dist


func _is_hostile_target(node: Node) -> bool:
	if node == null or node == pawn:
		return false
	var dead_val: Variant = node.get(&"dead")
	if dead_val is bool and dead_val:
		return false
	var fac_val: Variant = node.get(&"faction")
	if fac_val != null:
		var tfac := StringName(String(fac_val))
		if tfac != &"" and tfac == faction:
			return false
	return true


static func _resolve_damageable(obj: Object) -> Node:
	if not (obj is Node):
		return null
	# Prefer the outermost damageable ancestor within 3 hops so hitbox proxies
	# (e.g. ReefEel.EelHitbox) resolve cleanly to their owning entity with one ID.
	var found: Node = null
	var n := obj as Node
	for _depth in 3:
		if n == null:
			break
		if n.has_method(&"apply_damage"):
			found = n
		n = n.get_parent()
	return found


static func _call_apply_damage(target: Node, amount: float, attacker: Node) -> void:
	if target == null or not target.has_method(&"apply_damage"):
		return
	for m: Dictionary in target.get_method_list():
		if StringName(m["name"]) == &"apply_damage":
			var args: Array = m["args"]
			if args.size() <= 1:
				target.call(&"apply_damage", amount)
			else:
				target.call(&"apply_damage", amount, attacker)
			return
	target.call(&"apply_damage", amount, attacker)


func _spend_stamina(cost: float) -> bool:
	if stamina < cost:
		return false
	stamina -= cost
	_stamina_delay = STAMINA_REGEN_DELAY
	return true


func _trigger_recoil_pulse(strength: float) -> void:
	if not enable_effects or _is_reduced_motion():
		return
	_recoil_pulse = 1.0
	_recoil_strength = maxf(_recoil_strength, clampf(strength, 0.2, 1.3))
	_recoil_sign = -_recoil_sign


func _trigger_hitstop(duration: float, trauma: float, recoil_strength: float) -> void:
	if not enable_effects or _is_reduced_motion():
		return
	_hitstop_timer = maxf(_hitstop_timer, duration)
	_trigger_recoil_pulse(recoil_strength)
	var pc := _get_player_controller()
	if pc != null:
		pc.add_camera_trauma(trauma)


func _is_reduced_motion() -> bool:
	var pc := _get_player_controller()
	if pc != null and pc.bob_amount <= 0.001:
		return true
	return false


func _get_player_controller() -> PlayerController:
	if pawn == null or not is_instance_valid(pawn):
		return null
	if _player_controller == null or not is_instance_valid(_player_controller):
		_player_controller = null
		for c in pawn.get_children():
			if c is PlayerController:
				_player_controller = c as PlayerController
				break
	return _player_controller


func _get_inventory() -> Node:
	if pawn == null or not is_instance_valid(pawn):
		return null
	if _inventory == null or not is_instance_valid(_inventory):
		_inventory = null
		for c in pawn.get_children():
			if c.get_script() != null and c.has_method(&"get_resolved_tool_id"):
				_inventory = c
				break
	return _inventory


func _can_spawn_vfx() -> bool:
	return enable_effects and is_inside_tree()


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


static func _get_spark_texture() -> ImageTexture:
	if _spark_tex != null:
		return _spark_tex
	var sz := 24
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := absf(float(x) - half) / half
			var dy := absf(float(y) - half) / half
			var core := clampf(1.0 - sqrt(dx * dx * 3.2 + dy * dy * 1.15), 0.0, 1.0)
			var a := pow(core, 1.75)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


static func _get_flash_texture() -> GradientTexture2D:
	if _flash_tex != null:
		return _flash_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.28, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.99, 0.92, 1.0),
		Color(1.0, 0.90, 0.52, 0.72),
		Color(1.0, 0.62, 0.16, 0.22),
		Color(1.0, 0.45, 0.05, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.gradient = grad
	_flash_tex = tex
	return _flash_tex


static func _get_ember_texture() -> ImageTexture:
	if _ember_tex != null:
		return _ember_tex
	var sz := 24
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	# Soft glowing elliptical fiery ember mote for atmospheric floating swordfight embers.
	for y in sz:
		for x in sz:
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var d := sqrt(dx * dx * 1.15 + dy * dy * 1.65)
			var alpha := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			var bright := lerpf(0.75, 1.0, alpha)
			img.set_pixel(x, y, Color(1.0, bright, bright * 0.88, alpha))
	_ember_tex = ImageTexture.create_from_image(img)
	return _ember_tex


func _cleanup_vfx_node(fx_node: Node) -> void:
	_active_vfx.erase(fx_node)
	if fx_node == null or not is_instance_valid(fx_node):
		return
	for child in fx_node.get_children():
		if child is GPUParticles3D:
			var gp := child as GPUParticles3D
			gp.emitting = false
			if gp.draw_pass_1 is QuadMesh:
				var qm := gp.draw_pass_1 as QuadMesh
				if qm.material is StandardMaterial3D:
					(qm.material as StandardMaterial3D).albedo_texture = null
				qm.material = null
			if gp.process_material is ParticleProcessMaterial:
				var pm := gp.process_material as ParticleProcessMaterial
				pm.color_ramp = null
				pm.scale_curve = null
			gp.draw_pass_1 = null
			gp.process_material = null
	fx_node.queue_free()


func _cleanup_all_vfx() -> void:
	var pending := _active_vfx.duplicate()
	_active_vfx.clear()
	for fx in pending:
		_cleanup_vfx_node(fx)
	var pending_arcs := _slash_arcs.duplicate()
	_slash_arcs.clear()
	for entry in pending_arcs:
		_cleanup_slash_arc_entry(entry)


# ==============================================================================
# Sculpted 1-DC Sweeping `BladeSlashArc` & Boarding-Axe Cleave VFX
# ==============================================================================

## Build or return the statically cached 16-segment curved crescent BladeSlashArc ArrayMesh.
static func _get_slash_arc_mesh() -> ArrayMesh:
	if _slash_arc_mesh != null:
		return _slash_arc_mesh
	_slash_arc_mesh = _build_slash_arc_mesh()
	return _slash_arc_mesh


static func _build_slash_arc_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const ARC_RAD := deg_to_rad(132.0)
	const HALF_ARC := ARC_RAD * 0.5
	const MAX_CHORD := 0.38
	var segs := SLASH_ARC_SEGMENTS

	var ring_out: Array[Vector3] = []
	var ring_mid: Array[Vector3] = []
	var ring_in: Array[Vector3] = []
	var col_out: Array[Color] = []
	var col_mid: Array[Color] = []
	var col_in: Array[Color] = []

	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var theta := lerpf(-HALF_ARC, HALF_ARC, u)
		var s := sin(theta)
		var c := cos(theta)
		# Razor-tapered crescent envelope: thickest (0.38 m) in center, sharp tips at both ends.
		var env := pow(sin(u * PI), 0.78)
		var r_out := lerpf(1.26, 1.58, sin(u * PI * 0.74 + 0.12))
		var chord := MAX_CHORD * env
		var r_in := r_out - chord
		var r_mid := lerpf(r_in, r_out, 0.70)
		# Subtle 3D ribbon camber gives depth from both elevated and eye-level duel cameras.
		var y_out := 0.008 * env
		var y_mid := 0.032 * env
		var y_in := -0.018 * env

		ring_out.append(Vector3(s * r_out, y_out, -c * r_out))
		ring_mid.append(Vector3(s * r_mid, y_mid, -c * r_mid))
		ring_in.append(Vector3(s * r_in, y_in, -c * r_in))

		# White-hot leading outer blade rim -> luminous mid body -> soft zero-alpha trailing wake.
		var tip_fade := pow(sin(u * PI), 0.52)
		var momentum := lerpf(0.46, 1.0, u)
		col_out.append(Color(1.0, 1.0, 0.98, clampf(tip_fade * (0.55 + 0.45 * momentum), 0.0, 1.0)))
		col_mid.append(Color(1.0, 0.94, 0.84, clampf(tip_fade * (0.44 + 0.42 * momentum), 0.0, 0.92)))
		col_in.append(Color(0.95, 0.80, 0.64, 0.0))

	for i in segs:
		var ni := i + 1
		var u0 := float(i) / float(segs)
		var u1 := float(ni) / float(segs)
		if i == 0:
			# Sharp trailing tip wedge (2 non-degenerate triangles).
			_add_arc_tri(st, ring_out[0], ring_out[1], ring_mid[1], col_out[0], col_out[1], col_mid[1],
				Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.7))
			_add_arc_tri(st, ring_out[0], ring_mid[1], ring_in[1], col_out[0], col_mid[1], col_in[1],
				Vector2(u0, 0.5), Vector2(u1, 0.7), Vector2(u1, 0.0))
		elif i == segs - 1:
			# Sharp leading tip wedge (2 non-degenerate triangles).
			_add_arc_tri(st, ring_out[i], ring_out[ni], ring_mid[i], col_out[i], col_out[ni], col_mid[i],
				Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u0, 0.7))
			_add_arc_tri(st, ring_mid[i], ring_out[ni], ring_in[i], col_mid[i], col_out[ni], col_in[i],
				Vector2(u0, 0.7), Vector2(u1, 0.5), Vector2(u0, 0.0))
		else:
			# Outer bright blade strip (2 triangles).
			_add_arc_tri(st, ring_out[i], ring_out[ni], ring_mid[ni], col_out[i], col_out[ni], col_mid[ni],
				Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.7))
			_add_arc_tri(st, ring_out[i], ring_mid[ni], ring_mid[i], col_out[i], col_mid[ni], col_mid[i],
				Vector2(u0, 1.0), Vector2(u1, 0.7), Vector2(u0, 0.7))
			# Inner translucent wake strip (2 triangles).
			_add_arc_tri(st, ring_mid[i], ring_mid[ni], ring_in[ni], col_mid[i], col_mid[ni], col_in[ni],
				Vector2(u0, 0.7), Vector2(u1, 0.7), Vector2(u1, 0.0))
			_add_arc_tri(st, ring_mid[i], ring_in[ni], ring_in[i], col_mid[i], col_in[ni], col_in[i],
				Vector2(u0, 0.7), Vector2(u1, 0.0), Vector2(u0, 0.0))

	st.generate_normals()
	return st.commit()


static func _add_arc_tri(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3,
	ca: Color, cb: Color, cc: Color,
	uva: Vector2, uvb: Vector2, uvc: Vector2
) -> void:
	st.set_color(ca); st.set_uv(uva); st.add_vertex(a)
	st.set_color(cb); st.set_uv(uvb); st.add_vertex(b)
	st.set_color(cc); st.set_uv(uvc); st.add_vertex(c)


func _current_slash_arc_style() -> StringName:
	if equipped_weapon == &"boarding_axe":
		return &"axe_heavy" if _attack_is_heavy else &"axe_light"
	if _attack_is_heavy:
		return &"heavy"
	if combo_step == 2:
		return &"light_2"
	if combo_step == 3:
		return &"light_3"
	return &"light_1"


static func _slash_arc_style_spec(style: StringName, combo_hint: int = 1) -> Dictionary:
	match style:
		&"light_2":
			return {
				"tint": Color(1.0, 0.94, 0.78, 0.92),
				"scale": Vector3(1.04, 1.0, 1.04),
				"tilt_deg": -26.0,
				"flip_x": -1.0,
				"start_yaw_deg": 42.0,
				"end_yaw_deg": -44.0,
				"forward_offset": 0.14,
			}
		&"light_3":
			return {
				"tint": Color(1.0, 0.86, 0.44, 0.98),
				"scale": Vector3(1.20, 1.12, 1.20),
				"tilt_deg": 0.0,
				"flip_x": 1.0,
				"start_yaw_deg": -52.0,
				"end_yaw_deg": 56.0,
				"forward_offset": 0.22,
			}
		&"heavy":
			return {
				"tint": Color(1.0, 0.96, 0.68, 1.0),
				"scale": Vector3(1.32, 1.24, 1.32),
				"tilt_deg": 12.0,
				"flip_x": 1.0,
				"start_yaw_deg": -54.0,
				"end_yaw_deg": 58.0,
				"forward_offset": 0.26,
			}
		&"axe_light":
			var flip := -1.0 if combo_hint == 2 else 1.0
			var tilt := 0.0 if combo_hint == 3 else (20.0 * flip)
			return {
				"tint": Color(1.0, 0.56, 0.18, 0.96),
				"scale": Vector3(1.38, 1.45, 1.38),
				"tilt_deg": tilt,
				"flip_x": flip,
				"start_yaw_deg": -46.0 * flip,
				"end_yaw_deg": 52.0 * flip,
				"forward_offset": 0.20,
			}
		&"axe_heavy":
			return {
				"tint": Color(1.0, 0.36, 0.10, 1.0),
				"scale": Vector3(1.55, 1.65, 1.55),
				"tilt_deg": 0.0,
				"flip_x": 1.0,
				"start_yaw_deg": -58.0,
				"end_yaw_deg": 62.0,
				"forward_offset": 0.28,
			}
		_:
			# &"light_1"
			return {
				"tint": Color(1.0, 0.95, 0.80, 0.92),
				"scale": Vector3(1.0, 1.0, 1.0),
				"tilt_deg": 26.0,
				"flip_x": 1.0,
				"start_yaw_deg": -42.0,
				"end_yaw_deg": 44.0,
				"forward_offset": 0.14,
			}


func _create_slash_arc_instance(
	world_pos: Vector3,
	arc_basis: Basis,
	style: StringName,
	follow_pawn: bool,
	freeze_in_place: bool
) -> MeshInstance3D:
	var host: Node = pawn.get_parent() if (pawn != null and is_instance_valid(pawn)) else get_parent()
	if host == null:
		return null

	var spec := _slash_arc_style_spec(style, combo_step)
	var tint: Color = spec["tint"]
	var base_scale: Vector3 = spec["scale"]
	var tilt_rad := deg_to_rad(float(spec["tilt_deg"]))
	var flip_x := float(spec["flip_x"])
	var start_yaw := deg_to_rad(float(spec["start_yaw_deg"]))
	var end_yaw := deg_to_rad(float(spec["end_yaw_deg"]))
	var fwd_off := float(spec["forward_offset"])

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = tint

	var mi := MeshInstance3D.new()
	mi.name = "BladeSlashArc"
	mi.mesh = _get_slash_arc_mesh()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"slash_style", style)
	mi.set_meta(&"base_tint", tint)
	mi.set_meta(&"base_scale", base_scale)
	host.add_child(mi)

	var tilted_basis := arc_basis.orthonormalized() * Basis(Vector3.FORWARD, tilt_rad)
	var init_yaw := lerpf(start_yaw, end_yaw, 0.52) if freeze_in_place else start_yaw
	var init_scale := Vector3(base_scale.x * flip_x, base_scale.y, base_scale.z)
	var init_pos := world_pos - arc_basis.orthonormalized().z * fwd_off
	mi.global_transform = Transform3D((tilted_basis * Basis(Vector3.UP, init_yaw)).scaled(init_scale), init_pos)

	_slash_arcs.append({
		"node": mi,
		"mat": mat,
		"style": style,
		"base_basis": tilted_basis,
		"base_scale": base_scale,
		"tint": tint,
		"flip_x": flip_x,
		"start_yaw": start_yaw,
		"end_yaw": end_yaw,
		"forward_offset": fwd_off,
		"elapsed": 0.0,
		"duration": SLASH_ARC_DURATION,
		"follow_pawn": follow_pawn,
		"frozen": freeze_in_place,
	})
	return mi


func _spawn_slash_arc(style: StringName) -> MeshInstance3D:
	if not _can_spawn_vfx() or pawn == null:
		return null
	var origin := pawn.global_position + Vector3.UP * 1.18
	var yaw_basis := Basis(Vector3.UP, pawn.look_yaw)
	return _create_slash_arc_instance(origin, yaw_basis, style, true, false)


## Spawn a sculpted BladeSlashArc at `world_pos`/`arc_basis` for showcases or scripted clashes.
## When `freeze_in_place` is true, the arc holds mid-sweep at full glow and still cleans up cleanly on `_exit_tree()`.
func spawn_showcase_slash_arc(
	world_pos: Vector3,
	arc_basis: Basis,
	style: StringName = &"heavy",
	freeze_in_place: bool = false
) -> MeshInstance3D:
	if not is_inside_tree():
		return null
	return _create_slash_arc_instance(world_pos, arc_basis, style, false, freeze_in_place)


func _tick_slash_arcs(delta: float) -> void:
	if _slash_arcs.is_empty():
		return
	for i in range(_slash_arcs.size() - 1, -1, -1):
		var entry: Dictionary = _slash_arcs[i]
		var mi := entry.get("node", null) as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			_slash_arcs.remove_at(i)
			continue
		if bool(entry.get("frozen", false)):
			continue
		var elapsed := float(entry["elapsed"]) + delta
		var dur := float(entry["duration"])
		if elapsed >= dur:
			_cleanup_slash_arc_entry(entry)
			_slash_arcs.remove_at(i)
			continue
		entry["elapsed"] = elapsed
		var t := clampf(elapsed / maxf(dur, 0.001), 0.0, 1.0)
		var sweep_t := 1.0 - pow(1.0 - t, 2.4)
		var base_b: Basis = entry["base_basis"]
		var cur_yaw := lerpf(float(entry["start_yaw"]), float(entry["end_yaw"]), sweep_t)
		var base_sc: Vector3 = entry["base_scale"]
		var expand := 1.0 + 0.14 * sweep_t
		var cur_scale := Vector3(base_sc.x * float(entry["flip_x"]) * expand, base_sc.y, base_sc.z * expand)
		var pos := mi.global_position
		if bool(entry["follow_pawn"]) and pawn != null and is_instance_valid(pawn):
			pos = pawn.global_position + Vector3.UP * 1.18 + pawn.facing() * float(entry["forward_offset"])
		mi.global_transform = Transform3D((base_b * Basis(Vector3.UP, cur_yaw)).scaled(cur_scale), pos)

		var mat := entry.get("mat", null) as StandardMaterial3D
		if mat != null:
			var tint: Color = entry["tint"]
			var alpha_env := smoothstep(0.0, 0.12, t) * pow(1.0 - t, 1.65)
			mat.albedo_color = Color(tint.r, tint.g, tint.b, tint.a * alpha_env)


func _cleanup_slash_arc_entry(entry: Dictionary) -> void:
	var mi := entry.get("node", null) as MeshInstance3D
	if mi != null and is_instance_valid(mi):
		mi.material_override = null
		mi.mesh = null
		mi.queue_free()
	entry.clear()


func _spawn_parry_sparks(pos: Vector3, _tint: Color = Color(1.0, 0.94, 0.72), intense: bool = true) -> void:
	_spawn_clash_vfx(pos, &"parried" if intense else &"blocked")


func _spawn_clash_vfx(pos: Vector3, style: StringName = &"parried") -> void:
	if not _can_spawn_vfx():
		return
	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return

	var is_parry := (style == &"parried")
	var is_heavy := (style == &"heavy")
	var fx_root := Node3D.new()
	fx_root.name = "ClashSparks"
	fx_root.set_meta(&"clash_style", style)
	host.add_child(fx_root)
	fx_root.global_position = pos

	# 1. White-hot radial metallic spark streaks bursting outward from the steel-on-steel clash.
	var sparks := GPUParticles3D.new()
	sparks.name = "SparkStreaks"
	sparks.one_shot = true
	sparks.explosiveness = 0.96
	sparks.amount = 32 if is_parry else (24 if is_heavy else 16)
	sparks.lifetime = 0.40 if is_parry else (0.34 if is_heavy else 0.28)
	sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.visibility_aabb = AABB(Vector3(-3.5, -3.5, -3.5), Vector3(7.0, 7.0, 7.0))

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 160.0 if is_parry else (140.0 if is_heavy else 115.0)
	proc.initial_velocity_min = 4.6 if is_parry else (3.8 if is_heavy else 3.0)
	proc.initial_velocity_max = 11.4 if is_parry else (9.4 if is_heavy else 7.4)
	proc.damping_min = 1.8
	proc.damping_max = 3.6
	proc.gravity = Vector3(0.0, -13.5, 0.0)
	proc.scale_min = 0.68
	proc.scale_max = 1.40 if is_parry else (1.22 if is_heavy else 1.04)

	var mid_tint := Color(1.0, 0.94, 0.56) if is_parry else (Color(1.0, 0.86, 0.42) if is_heavy else Color(1.0, 0.78, 0.34))
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.26, 0.70, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.99, 0.94, 1.0),
		Color(mid_tint.r, mid_tint.g, mid_tint.b, 0.96),
		Color(1.0, 0.52, 0.10, 0.65),
		Color(0.92, 0.22, 0.04, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 24
	ramp.gradient = grad
	proc.color_ramp = ramp
	sparks.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.050, 0.33) if is_parry else (Vector2(0.044, 0.27) if is_heavy else Vector2(0.036, 0.20))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_spark_texture()
	quad.material = mat
	sparks.draw_pass_1 = quad
	fx_root.add_child(sparks)
	sparks.restart()
	sparks.emitting = true

	# 2. Concept-art glowing floating fiery orange-crimson combat embers drifting lazily across the air!
	var embers := GPUParticles3D.new()
	embers.name = "CombatEmbers"
	embers.one_shot = true
	embers.explosiveness = 0.82
	embers.amount = 22 if is_parry else (16 if is_heavy else 10)
	embers.lifetime = 0.92 if is_parry else (0.82 if is_heavy else 0.70)
	embers.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.visibility_aabb = AABB(Vector3(-4.0, -2.5, -4.0), Vector3(8.0, 6.0, 8.0))

	var e_proc := ParticleProcessMaterial.new()
	e_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	e_proc.emission_sphere_radius = 0.28 if is_parry else 0.18
	e_proc.direction = Vector3(0.0, 0.55, 0.0).normalized()
	e_proc.spread = 155.0
	e_proc.initial_velocity_min = 0.65 if is_parry else 0.45
	e_proc.initial_velocity_max = 2.15 if is_parry else (1.75 if is_heavy else 1.35)
	e_proc.damping_min = 1.6
	e_proc.damping_max = 3.2
	e_proc.gravity = Vector3(0.0, 0.26, 0.0)
	e_proc.turbulence_enabled = true
	e_proc.turbulence_noise_strength = 0.85
	e_proc.turbulence_noise_scale = 2.4
	e_proc.turbulence_influence_min = 0.25
	e_proc.turbulence_influence_max = 0.55
	e_proc.angle_min = 0.0
	e_proc.angle_max = 360.0
	e_proc.angular_velocity_min = -45.0
	e_proc.angular_velocity_max = 45.0
	e_proc.scale_min = 0.65
	e_proc.scale_max = 1.35 if is_parry else 1.12

	var e_curve := Curve.new()
	e_curve.add_point(Vector2(0.0, 0.55))
	e_curve.add_point(Vector2(0.22, 1.10))
	e_curve.add_point(Vector2(0.75, 0.85))
	e_curve.add_point(Vector2(1.0, 0.15))
	var e_curve_tex := CurveTexture.new()
	e_curve_tex.curve = e_curve
	e_proc.scale_curve = e_curve_tex

	var e_grad := Gradient.new()
	e_grad.offsets = PackedFloat32Array([0.0, 0.18, 0.62, 1.0])
	e_grad.colors = PackedColorArray([
		Color(1.0, 0.88, 0.42, 0.0),
		Color(1.0, 0.56, 0.12, 0.96) if not is_parry else Color(1.0, 0.72, 0.18, 1.0),
		Color(0.98, 0.22, 0.05, 0.78),
		Color(0.72, 0.06, 0.02, 0.0),
	])
	var e_ramp := GradientTexture1D.new()
	e_ramp.width = 24
	e_ramp.gradient = e_grad
	e_proc.color_ramp = e_ramp
	embers.process_material = e_proc

	var e_quad := QuadMesh.new()
	e_quad.size = Vector2(0.085, 0.058)
	var e_mat := StandardMaterial3D.new()
	e_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	e_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	e_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	e_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	e_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	e_mat.vertex_color_use_as_albedo = true
	e_mat.albedo_texture = _get_ember_texture()
	e_quad.material = e_mat
	embers.draw_pass_1 = e_quad
	fx_root.add_child(embers)
	embers.restart()
	embers.emitting = true

	# 3. Core flash: distinct huge golden starburst for timed parries vs compact amber glint for blocks.
	var flash := GPUParticles3D.new()
	flash.name = "ParryStarburst" if is_parry else "ClashFlash"
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.amount = 2 if is_parry else 1
	flash.lifetime = 0.22 if is_parry else (0.16 if is_heavy else 0.11)
	flash.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fproc := ParticleProcessMaterial.new()
	fproc.gravity = Vector3.ZERO
	fproc.initial_velocity_min = 0.0
	fproc.initial_velocity_max = 0.0
	var fcurve := Curve.new()
	fcurve.add_point(Vector2(0.0, 0.38))
	fcurve.add_point(Vector2(0.24, 1.45 if is_parry else 1.10))
	fcurve.add_point(Vector2(1.0, 0.12))
	var fcurve_tex := CurveTexture.new()
	fcurve_tex.curve = fcurve
	fproc.scale_curve = fcurve_tex
	var fgrad := Gradient.new()
	fgrad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	fgrad.colors = PackedColorArray([
		Color(1.0, 0.99, 0.90, 1.0),
		Color(1.0, 0.80, 0.24, 0.92) if is_parry else Color(1.0, 0.68, 0.22, 0.72),
		Color(0.95, 0.32, 0.05, 0.0),
	])
	var framp := GradientTexture1D.new()
	framp.width = 16
	framp.gradient = fgrad
	fproc.color_ramp = framp
	flash.process_material = fproc

	var fquad := QuadMesh.new()
	fquad.size = Vector2(0.95, 0.95) if is_parry else (Vector2(0.58, 0.58) if is_heavy else Vector2(0.30, 0.30))
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.vertex_color_use_as_albedo = true
	fmat.albedo_texture = _get_flash_texture()
	fquad.material = fmat
	flash.draw_pass_1 = fquad
	fx_root.add_child(flash)
	flash.restart()
	flash.emitting = true

	_active_vfx.append(fx_root)
	var cleanup := Timer.new()
	cleanup.wait_time = 1.08 if is_parry else (0.96 if is_heavy else 0.85)
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.timeout.connect(_cleanup_vfx_node.bind(fx_root))
	fx_root.add_child(cleanup)


func _spawn_muzzle_puff(pos: Vector3, tint: Color) -> void:
	if not _can_spawn_vfx():
		return
	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return
	var fx_root := Node3D.new()
	fx_root.name = "MuzzlePuffVFX"
	host.add_child(fx_root)
	fx_root.global_position = pos

	var p := GPUParticles3D.new()
	p.name = "MuzzlePuff"
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 10
	p.lifetime = 0.45
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.direction = pawn.view_dir()
	proc.spread = 28.0
	proc.initial_velocity_min = 1.5
	proc.initial_velocity_max = 4.5
	proc.gravity = Vector3(0.0, 1.2, 0.0)
	var mgrad := Gradient.new()
	mgrad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	mgrad.colors = PackedColorArray([
		Color(tint.r, tint.g, tint.b, tint.a),
		Color(tint.r, tint.g, tint.b, tint.a * 0.65),
		Color(tint.r, tint.g, tint.b, 0.0),
	])
	var mramp := GradientTexture1D.new()
	mramp.width = 16
	mramp.gradient = mgrad
	proc.color_ramp = mramp
	p.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.30, 0.30)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_flash_texture()
	quad.material = mat
	p.draw_pass_1 = quad
	fx_root.add_child(p)
	p.restart()
	p.emitting = true

	_active_vfx.append(fx_root)
	var cleanup := Timer.new()
	cleanup.wait_time = 0.55
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.timeout.connect(_cleanup_vfx_node.bind(fx_root))
	fx_root.add_child(cleanup)
