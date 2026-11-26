class_name ReefEel
extends Node3D
## Undulating 7-segment stylized sea-green & gold-spotted moray/reef eel that ambushes
## swimmers in coastal reef shallows.
##
## Lurks beneath `Sea.height()` at 1.5..8.0 m depth, detects swimming `Pawn` targets,
## coils with glowing amber eyes and wide snapping jaws, darts forward with sinusoidal
## body undulation (`sin(phase - seg_idx * 0.7)`), bites for 16.0 damage on a fair
## 3.2 s cooldown, and retreats back to its reef crevice after striking or taking damage.

signal damaged(amount: float, from: Node)
signal ambush_started(eel: ReefEel, target: Pawn)
signal bit_target(target: Pawn, damage: float)
signal defeated(eel: ReefEel, pos: Vector3)

enum State { LURK, COIL, DART, RETREAT, DEAD }

const GROUP := &"beasts"
const EEL_GROUP := &"reef_eels"
const SEGMENT_COUNT := 7
const MIN_REEF_DEPTH := 1.5
const MAX_REEF_DEPTH := 8.0
const COIL_DURATION := 0.42
const DART_MAX_DURATION := 2.4
const RETREAT_DURATION := 2.8
const DEATH_DESPAWN_DELAY := 5.0

# Painterly tropical moray palette (deep sea-green skin, warm gold spots, chartreuse crest).
const COL_SKIN_DARK := Color(0.08, 0.32, 0.27)
const COL_SKIN_EMERALD := Color(0.14, 0.48, 0.38)
const COL_SKIN_BELLY := Color(0.46, 0.65, 0.46)
const COL_GOLD_SPOT := Color(0.93, 0.74, 0.20)
const COL_FIN_BASE := Color(0.18, 0.56, 0.38)
const COL_FIN_CREST := Color(0.56, 0.84, 0.34)
const COL_GULLET := Color(0.58, 0.14, 0.16)
const COL_FANG_IVORY := Color(0.96, 0.92, 0.80)
const COL_EYE_AMBER := Color(1.0, 0.76, 0.14)

@export var max_health: float = 35.0
@export var faction: StringName = &"beast"
@export var lair_origin: Vector3 = Vector3.ZERO
@export var lair_radius: float = 18.0
@export_range(1.5, 8.0, 0.1) var lurk_depth: float = 3.2
@export var lurk_speed: float = 3.4
@export var ambush_speed: float = 10.5
@export var bite_damage: float = 16.0
@export var bite_cooldown: float = 3.2

var health: float = 35.0
var dead: bool = false
var target: Pawn = null
var state: State = State.LURK

## Ordered chain of 7 articulated moray segments (`Segment_0` head .. `Segment_6` tail).
var segments: Array[Node3D] = []
## Articulated snapping lower jaw child of `Segment_0`.
var lower_jaw: Node3D = null

var _hitbox: EelHitbox = null
var _skin_mat: StandardMaterial3D = null
var _eye_mat: StandardMaterial3D = null

var _swim_phase: float = 0.0
var _clock: float = 0.0
var _patrol_angle: float = 0.0
var _state_timer: float = 0.0
var _bite_cd: float = 0.0
var _jaw_snap_timer: float = 0.0
var _hit_flash: float = 0.0
var _death_timer: float = 0.0
var _origin_locked: bool = false
var _rng := RandomNumberGenerator.new()


## Hittable physics proxy forwarding ranged/cannonball damage straight to its ReefEel.
class EelHitbox:
	extends StaticBody3D

	var owner_eel: ReefEel = null

	func apply_damage(amount: float, from: Node = null) -> void:
		if owner_eel != null and is_instance_valid(owner_eel):
			owner_eel.apply_damage(amount, from)

	func receive_melee_hit(attacker_cc: CombatComponent, raw_damage: float,
			is_heavy: bool, cleaves_shield: bool) -> StringName:
		if owner_eel != null and is_instance_valid(owner_eel):
			return owner_eel.receive_melee_hit(attacker_cc, raw_damage, is_heavy, cleaves_shield)
		return &"dodged"


## Spawn a coastal ReefEel lurking beneath the waves at `world_pos`.
static func spawn_at(parent: Node, world_pos: Vector3, p_lair_radius: float = 18.0,
		p_lurk_depth: float = 3.2) -> ReefEel:
	var eel := ReefEel.new()
	eel.name = "ReefEel"
	eel.lair_radius = maxf(p_lair_radius, 5.0)
	eel.lurk_depth = clampf(p_lurk_depth, MIN_REEF_DEPTH, MAX_REEF_DEPTH)
	var surf := Sea.height(world_pos.x, world_pos.z)
	var spawn_pos := Vector3(world_pos.x, surf - eel.lurk_depth, world_pos.z)
	eel.lair_origin = spawn_pos
	eel._origin_locked = true
	if parent != null:
		parent.add_child(eel)
	eel.global_position = spawn_pos
	return eel


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(EEL_GROUP)


func _ready() -> void:
	health = max_health
	lurk_depth = clampf(lurk_depth, MIN_REEF_DEPTH, MAX_REEF_DEPTH)

	var seed_val := hash(Vector3i(
		int(roundf(global_position.x * 3.0)),
		int(roundf(global_position.y * 3.0)),
		int(roundf(global_position.z * 3.0))
	))
	_rng.seed = seed_val if seed_val != 0 else 0xEE14EEF
	_patrol_angle = _rng.randf() * TAU
	_swim_phase = _rng.randf() * TAU

	if not _origin_locked and lair_origin == Vector3.ZERO:
		var surf := Sea.height(global_position.x, global_position.z)
		lair_origin = Vector3(global_position.x, surf - lurk_depth, global_position.z)
		_origin_locked = global_position != Vector3.ZERO

	_build_anatomy()
	_build_hitbox()
	_update_undulation(0.0)


# ------------------------------------------------------------------ combat API

func eye_position() -> Vector3:
	return global_position + Vector3(0.0, 0.12, 0.0)


## Host-authoritative damage entry point. Wounded eels immediately retreat to their crevice.
func apply_damage(amount: float, from: Node = null) -> void:
	if not Net.is_host() or dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_hit_flash = 0.24
	Audio.play_sfx(&"hit_flesh", global_position)
	damaged.emit(amount, from)

	if health <= 0.0:
		_die()
		return

	# Taking damage drives the ambush predator back into its reef crevice!
	state = State.RETREAT
	_state_timer = RETREAT_DURATION
	_bite_cd = maxf(_bite_cd, 2.0)


## Duck-typed melee hit receiver matching `CombatComponent.receive_melee_hit()`.
func receive_melee_hit(attacker_cc: CombatComponent, raw_damage: float,
		_is_heavy: bool, _cleaves_shield: bool) -> StringName:
	if not Net.is_host() or dead:
		return &"dodged"
	var attacker_pawn: Pawn = attacker_cc.pawn if attacker_cc != null else null
	apply_damage(raw_damage, attacker_pawn)
	return &"hit"


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if not _origin_locked and lair_origin == Vector3.ZERO and global_position != Vector3.ZERO:
		var surf_init := Sea.height(global_position.x, global_position.z)
		lair_origin = Vector3(global_position.x, surf_init - lurk_depth, global_position.z)
		_origin_locked = true

	_clock += delta
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_jaw_snap_timer = maxf(0.0, _jaw_snap_timer - delta)
	_update_material_glow()

	if dead:
		_death_timer += delta
		_animate_death(delta)
		if Net.is_host() and _death_timer >= DEATH_DESPAWN_DELAY:
			queue_free()
		return

	if Net.is_host():
		_tick_ai(delta)

	_update_undulation(delta)


func _tick_ai(delta: float) -> void:
	_bite_cd = maxf(0.0, _bite_cd - delta)
	_state_timer = maxf(0.0, _state_timer - delta)

	var surf := Sea.height(global_position.x, global_position.z)
	var reef_y := surf - clampf(lurk_depth, MIN_REEF_DEPTH, MAX_REEF_DEPTH)

	match state:
		State.LURK:
			# Lazy coastal reef figure-8 patrol under the turquoise shallows.
			_patrol_angle = wrapf(_patrol_angle + delta * 0.45, 0.0, TAU)
			var patrol_r := minf(lair_radius * 0.38, 6.2)
			var goal_x := lair_origin.x + cos(_patrol_angle) * patrol_r
			var goal_z := lair_origin.z + sin(_patrol_angle * 2.0) * (patrol_r * 0.55)
			var bob_y := clampf(reef_y + sin(_clock * 1.1) * 0.25, surf - MAX_REEF_DEPTH, surf - MIN_REEF_DEPTH)
			_swim_toward(Vector3(goal_x, bob_y, goal_z), lurk_speed, delta, 4.0)

			target = _find_swimmer()
			if target != null and _bite_cd <= 0.0:
				state = State.COIL
				_state_timer = COIL_DURATION
				ambush_started.emit(self, target)

		State.COIL:
			if target == null or not is_instance_valid(target) or target.dead or not target.is_swimming():
				state = State.LURK
				return
			# Coil tightly while tracking the swimmer's bearing before darting out!
			var aim := target.global_position - global_position
			var flat_aim := Vector3(aim.x, 0.0, aim.z)
			if flat_aim.length_squared() > 0.001:
				var yaw_goal := atan2(-flat_aim.x, -flat_aim.z)
				rotation.y = lerp_angle(rotation.y, yaw_goal, clampf(delta * 9.0, 0.0, 1.0))
			var coil_y := clampf(lerpf(global_position.y, minf(target.global_position.y + 0.4, surf - 0.5), delta * 3.0),
				surf - MAX_REEF_DEPTH, surf - 0.45)
			global_position.y = coil_y
			if _state_timer <= 0.0:
				state = State.DART
				_state_timer = DART_MAX_DURATION
				Audio.play_sfx(&"splash_small", global_position, -1.5, 0.12)

		State.DART:
			if target == null or not is_instance_valid(target) or target.dead or not target.is_swimming():
				state = State.RETREAT
				_state_timer = RETREAT_DURATION * 0.8
				return
			var lair_dist := Vector2(global_position.x - lair_origin.x, global_position.z - lair_origin.z).length()
			if lair_dist > lair_radius * 1.45 or _state_timer <= 0.0:
				state = State.RETREAT
				_state_timer = RETREAT_DURATION
				return

			var bite_aim := target.global_position + Vector3(0.0, 0.65, 0.0)
			var target_surf := Sea.height(bite_aim.x, bite_aim.z)
			bite_aim.y = minf(bite_aim.y, target_surf - 0.25)
			_swim_toward(bite_aim, ambush_speed, delta, 9.0)

			if Ocean.current != null and (surf - global_position.y) < 1.15:
				Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 0.95, 0.42)

			if global_position.distance_to(bite_aim) <= 1.85:
				_execute_bite(target)

		State.RETREAT:
			var retreat_goal := Vector3(lair_origin.x, reef_y, lair_origin.z)
			_swim_toward(retreat_goal, lurk_speed * 2.15, delta, 6.5)
			if _state_timer <= 0.0 or global_position.distance_to(retreat_goal) <= 1.4:
				state = State.LURK

		State.DEAD:
			pass


func _swim_toward(goal: Vector3, spd: float, delta: float, turn_rate: float) -> void:
	var to_goal := goal - global_position
	var dist := to_goal.length()
	if dist <= 0.02:
		return
	var dir := to_goal / dist
	var step_len := minf(spd * delta, dist)
	global_position += dir * step_len
	# Never breach above the water surface!
	var max_y := Sea.height(global_position.x, global_position.z) - 0.22
	if global_position.y > max_y:
		global_position.y = max_y

	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() > 0.0004:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * turn_rate, 0.0, 1.0))
	var target_pitch := clampf(atan2(dir.y, maxf(flat.length(), 0.25)), -0.52, 0.52)
	rotation.x = lerpf(rotation.x, target_pitch, clampf(delta * 6.0, 0.0, 1.0))


func _execute_bite(victim: Pawn) -> void:
	_jaw_snap_timer = 0.35
	_bite_cd = bite_cooldown
	state = State.RETREAT
	_state_timer = RETREAT_DURATION

	var victim_cc := _combat_of(victim)
	if victim_cc != null and victim_cc.is_invulnerable():
		return

	victim.apply_damage(bite_damage, self)
	Audio.play_sfx(&"splash_large", global_position, -3.0)
	Audio.play_sfx(&"hit_flesh", victim.eye_position())
	if Ocean.current != null:
		var surf := Sea.height(victim.global_position.x, victim.global_position.z)
		Ocean.current.add_foam(Vector3(victim.global_position.x, surf, victim.global_position.z), 1.6, 0.72)
	bit_target.emit(victim, bite_damage)


func _find_swimmer() -> Pawn:
	var best: Pawn = null
	var best_d := lair_radius

	if target != null and is_instance_valid(target) and not target.dead and target.is_swimming():
		var td_lair := Vector2(target.global_position.x - lair_origin.x, target.global_position.z - lair_origin.z).length()
		if td_lair <= lair_radius:
			best = target
			best_d = global_position.distance_to(target.global_position)

	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc == null or cc.faction == faction or cc.pawn == null or cc.pawn.dead:
			continue
		if not cc.pawn.is_swimming():
			continue
		var p_pos := cc.pawn.global_position
		if Vector2(p_pos.x - lair_origin.x, p_pos.z - lair_origin.z).length() > lair_radius:
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
	_death_timer = 0.0
	if _hitbox != null:
		_hitbox.collision_layer = 0
	defeated.emit(self, global_position)


# ------------------------------------------------------------------ sinusoidal undulation

func _update_undulation(delta: float) -> void:
	var freq := 4.8
	var amp_scale := 1.0
	var z_compress := 1.0
	match state:
		State.COIL:
			freq = 9.2
			amp_scale = 1.65
			z_compress = 0.78
		State.DART:
			freq = 13.8
			amp_scale = 1.25
			z_compress = 1.02
		State.RETREAT:
			freq = 11.5
			amp_scale = 1.15
		_:
			pass

	_swim_phase += delta * freq

	var z_cursor := 0.0
	for seg_idx in segments.size():
		var seg := segments[seg_idx]
		if seg == null:
			continue
		var frac := float(seg_idx) / float(maxi(segments.size() - 1, 1))
		var wave := sin(_swim_phase - float(seg_idx) * 0.7)
		var wave_deriv := cos(_swim_phase - float(seg_idx) * 0.7)
		var seg_amp := lerpf(0.05, 0.36, frac) * amp_scale

		seg.position = Vector3(wave * seg_amp, sin(_swim_phase * 0.5 - float(seg_idx) * 0.45) * 0.04 * frac, z_cursor)
		seg.rotation = Vector3(0.0, -wave_deriv * lerpf(0.10, 0.42, frac) * amp_scale, wave * 0.14 * frac)
		z_cursor += lerpf(0.56, 0.44, frac) * z_compress

	# Articulated snapping jaw motion (gapes menacingly on coil/dart, snaps shut on bite!).
	if lower_jaw != null:
		var jaw_angle := -0.10 - absf(sin(_clock * 2.2)) * 0.08
		if _jaw_snap_timer > 0.0:
			jaw_angle = 0.04
		elif state == State.COIL:
			jaw_angle = -0.54
		elif state == State.DART:
			jaw_angle = -0.46 + sin(_swim_phase * 1.4) * 0.12
		lower_jaw.rotation.x = lerpf(lower_jaw.rotation.x, jaw_angle, clampf(delta * 16.0, 0.0, 1.0) if delta > 0.0 else 1.0)


func _animate_death(delta: float) -> void:
	rotation.z = lerpf(rotation.z, PI, clampf(delta * 2.2, 0.0, 1.0))
	global_position.y -= delta * 0.45
	_swim_phase += delta * 2.0 * maxf(0.0, 1.0 - _death_timer * 0.35)
	for seg_idx in segments.size():
		var seg := segments[seg_idx]
		if seg != null:
			var frac := float(seg_idx) / float(maxi(segments.size() - 1, 1))
			seg.position.x = sin(_swim_phase - float(seg_idx) * 0.7) * 0.14 * frac


func _update_material_glow() -> void:
	if _skin_mat != null:
		if _hit_flash > 0.0:
			_skin_mat.emission_enabled = true
			_skin_mat.emission = Color(0.95, 0.78, 0.28)
			_skin_mat.emission_energy_multiplier = (_hit_flash / 0.24) * 1.2
		else:
			_skin_mat.emission_enabled = false
			_skin_mat.emission_energy_multiplier = 0.0
	if _eye_mat != null:
		var energy := 0.2 if dead else (3.4 if (state == State.COIL or state == State.DART) else 1.8)
		_eye_mat.emission_energy_multiplier = energy


# ------------------------------------------------------------------ procedural anatomy

func _build_hitbox() -> void:
	_hitbox = EelHitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.owner_eel = self
	_hitbox.collision_layer = Pawn.LAYER_PAWN
	_hitbox.collision_mask = 0
	_hitbox.set_meta(&"beast", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 3.2
	cs.shape = cap
	cs.position = Vector3(0.0, 0.0, 1.2)
	cs.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_hitbox.add_child(cs)
	add_child(_hitbox)


func _build_anatomy() -> void:
	_skin_mat = StandardMaterial3D.new()
	_skin_mat.vertex_color_use_as_albedo = true
	_skin_mat.vertex_color_is_srgb = true
	_skin_mat.roughness = 0.36
	_skin_mat.metallic = 0.04

	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = COL_EYE_AMBER
	_eye_mat.roughness = 0.12
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.62, 0.08)
	_eye_mat.emission_energy_multiplier = 1.8

	segments.clear()

	# Segment 0: Moray head with dorsal crest, glowing amber eyes, and snapping jaws!
	var head := Node3D.new()
	head.name = "Segment_0"
	var head_mi := MeshInstance3D.new()
	head_mi.name = "UpperJaw"
	head_mi.mesh = _build_head_upper_mesh()
	head_mi.material_override = _skin_mat
	head.add_child(head_mi)

	lower_jaw = Node3D.new()
	lower_jaw.name = "LowerJaw"
	lower_jaw.position = Vector3(0.0, -0.06, -0.10)
	var jaw_mi := MeshInstance3D.new()
	jaw_mi.name = "LowerJawMesh"
	jaw_mi.mesh = _build_lower_jaw_mesh()
	jaw_mi.material_override = _skin_mat
	lower_jaw.add_child(jaw_mi)
	head.add_child(lower_jaw)

	# Glowing amber moray eyes peering from brow sockets.
	var eye_mesh := _build_eye_mesh()
	for sg: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "EyeL" if sg < 0.0 else "EyeR"
		eye.mesh = eye_mesh
		eye.position = Vector3(sg * 0.165, 0.10, -0.34)
		eye.material_override = _eye_mat
		head.add_child(eye)

	add_child(head)
	segments.append(head)

	# Segments 1..5: Muscular undulating sea-green & gold-spotted moray body segments.
	for i in range(1, SEGMENT_COUNT - 1):
		var frac := float(i) / float(SEGMENT_COUNT - 1)
		var seg := Node3D.new()
		seg.name = "Segment_%d" % i
		var mi := MeshInstance3D.new()
		mi.name = "BodyMesh"
		mi.mesh = _build_body_segment_mesh(i, frac)
		mi.material_override = _skin_mat
		seg.add_child(mi)
		add_child(seg)
		segments.append(seg)

	# Segment 6: Laterally compressed ribbon moray tail with flowing dorsal/ventral fin!
	var tail := Node3D.new()
	tail.name = "Segment_%d" % (SEGMENT_COUNT - 1)
	var tail_mi := MeshInstance3D.new()
	tail_mi.name = "TailMesh"
	tail_mi.mesh = _build_tail_segment_mesh()
	tail_mi.material_override = _skin_mat
	tail.add_child(tail_mi)
	add_child(tail)
	segments.append(tail)


static func _build_head_upper_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Chunky sculpted moray skull & snout (-Z forward, +Z neck join).
	# Format: [z, y_center, rx, ry_top, ry_bot, col_top, col_bot]
	var stations: Array[Array] = [
		[-0.62, 0.03, 0.11, 0.09, 0.04, COL_SKIN_EMERALD, COL_GULLET],
		[-0.44, 0.06, 0.17, 0.13, 0.05, COL_SKIN_EMERALD, COL_GULLET],
		[-0.22, 0.08, 0.21, 0.16, 0.10, COL_SKIN_DARK, COL_SKIN_BELLY],
		[0.06, 0.04, 0.24, 0.22, 0.18, COL_SKIN_EMERALD, COL_SKIN_BELLY],
		[0.32, 0.02, 0.23, 0.23, 0.20, COL_SKIN_DARK, COL_SKIN_BELLY],
	]
	_append_eel_loft(st, stations, 8, 0)

	# Prominent sculpted dorsal fin crest sweeping behind the eyes.
	_append_dorsal_crest(st, -0.18, 0.34, 0.22, 0.24, 0.17, 0.24)

	# Chunky ivory upper fangs curving backward along the upper jaw rim.
	for sg: float in [-1.0, 1.0]:
		for f_i in 3:
			var fz := -0.56 + float(f_i) * 0.12
			var base := Vector3(sg * (0.09 + float(f_i) * 0.025), 0.00, fz)
			_append_fang(st, base, base + Vector3(-sg * 0.015, -0.09, 0.03), 0.022)

	# Gold leopard moray spot plaques along cheek and nape.
	_append_spot_plaque(st, Vector3(-0.21, 0.10, 0.02), Vector3(0.05, 0.055, 0.085))
	_append_spot_plaque(st, Vector3(0.21, 0.09, 0.12), Vector3(0.05, 0.055, 0.085))
	_append_spot_plaque(st, Vector3(-0.15, 0.16, -0.18), Vector3(0.04, 0.045, 0.065))

	return st.commit()


static func _build_lower_jaw_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Articulated mandible extending forward from pivot (0, -0.06, -0.10) to snout tip.
	var stations: Array[Array] = [
		[-0.50, -0.01, 0.095, 0.035, 0.055, COL_GULLET, COL_SKIN_BELLY],
		[-0.30, -0.02, 0.145, 0.042, 0.075, COL_GULLET, COL_SKIN_BELLY],
		[-0.08, -0.02, 0.175, 0.050, 0.090, COL_GULLET, COL_SKIN_EMERALD],
		[0.06, -0.01, 0.165, 0.048, 0.085, COL_SKIN_DARK, COL_SKIN_BELLY],
	]
	_append_eel_loft(st, stations, 8, 99)

	# Upward-pointing lower ivory fangs interlocking with upper jaw!
	for sg: float in [-1.0, 1.0]:
		for f_i in 3:
			var fz := -0.45 + float(f_i) * 0.12
			var base := Vector3(sg * (0.075 + float(f_i) * 0.022), 0.015, fz)
			_append_fang(st, base, base + Vector3(-sg * 0.012, 0.085, 0.025), 0.020)

	return st.commit()


static func _build_body_segment_mesh(seg_idx: int, frac: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var r_front_x := lerpf(0.24, 0.11, frac)
	var r_back_x := lerpf(0.22, 0.09, frac)
	var r_front_y := lerpf(0.24, 0.17, frac)
	var r_back_y := lerpf(0.23, 0.15, frac)
	var top_col := COL_SKIN_EMERALD if seg_idx % 2 == 1 else COL_SKIN_DARK

	var stations: Array[Array] = [
		[-0.30, 0.0, r_front_x, r_front_y, r_front_y * 0.85, top_col, COL_SKIN_BELLY],
		[0.00, 0.01, (r_front_x + r_back_x) * 0.54, (r_front_y + r_back_y) * 0.54, (r_front_y + r_back_y) * 0.44, COL_SKIN_EMERALD, COL_SKIN_BELLY],
		[0.30, 0.0, r_back_x, r_back_y, r_back_y * 0.85, COL_SKIN_DARK, COL_SKIN_BELLY],
	]
	_append_eel_loft(st, stations, 8, seg_idx)

	# Continuous undulating frilled dorsal fin crest along top spine!
	var fin_h := lerpf(0.24, 0.18, frac)
	_append_dorsal_crest(st, -0.31, 0.31, r_front_y * 0.92, r_back_y * 0.92, fin_h, fin_h * 0.95)

	# Stylized raised gold-ochre moray spots alternating left/right down the flanks.
	var side_a := -1.0 if seg_idx % 2 == 0 else 1.0
	_append_spot_plaque(st, Vector3(side_a * r_front_x * 0.96, r_front_y * 0.25, -0.08), Vector3(0.045, 0.065, 0.095))
	_append_spot_plaque(st, Vector3(-side_a * r_back_x * 0.94, r_back_y * 0.12, 0.12), Vector3(0.04, 0.055, 0.085))

	return st.commit()


static func _build_tail_segment_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Laterally flattened eel ribbon tail tapering to a sleek whip blade.
	var stations: Array[Array] = [
		[-0.26, 0.0, 0.10, 0.16, 0.14, COL_SKIN_EMERALD, COL_SKIN_BELLY],
		[0.05, 0.0, 0.065, 0.14, 0.12, COL_SKIN_DARK, COL_FIN_BASE],
		[0.40, 0.0, 0.032, 0.11, 0.09, COL_FIN_BASE, COL_FIN_CREST],
		[0.74, 0.0, 0.012, 0.04, 0.03, COL_FIN_CREST, COL_FIN_CREST],
	]
	_append_eel_loft(st, stations, 6, 7)
	_append_dorsal_crest(st, -0.26, 0.68, 0.14, 0.04, 0.18, 0.08)
	return st.commit()


static func _build_eye_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3.ZERO
	var r := Vector3(0.048, 0.044, 0.052)
	var px := Vector3(r.x, 0.0, 0.0)
	var nx := Vector3(-r.x, 0.0, 0.0)
	var py := Vector3(0.0, r.y, 0.0)
	var ny := Vector3(0.0, -r.y, 0.0)
	var pz := Vector3(0.0, 0.0, r.z)
	var nz := Vector3(0.0, 0.0, -r.z)
	_add_outward_tri(st, py, px, nz, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	_add_outward_tri(st, py, nz, nx, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	_add_outward_tri(st, py, nx, pz, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	_add_outward_tri(st, py, pz, px, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	_add_outward_tri(st, ny, nz, px, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	_add_outward_tri(st, ny, nx, nz, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	_add_outward_tri(st, ny, pz, nx, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	_add_outward_tri(st, ny, px, pz, c, COL_EYE_AMBER, COL_EYE_AMBER, COL_EYE_AMBER)
	return st.commit()


static func _append_eel_loft(st: SurfaceTool, stations: Array[Array], segs: int, pattern_seed: int) -> void:
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	var centers: Array[Vector3] = []

	for s_i in stations.size():
		var row: Array = stations[s_i]
		var z: float = float(row[0])
		var yc: float = float(row[1])
		var rx: float = float(row[2])
		var ry_top: float = float(row[3])
		var ry_bot: float = float(row[4])
		var col_top: Color = row[5]
		var col_bot: Color = row[6]
		var ring: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			var sa := sin(a)
			var ry := ry_top if sa >= 0.0 else ry_bot
			ring.append(Vector3(cos(a) * rx, yc + sa * ry, z))
			var base_c := col_bot.lerp(col_top, clampf(sa * 0.5 + 0.5, 0.0, 1.0))
			# Sprinkle bold gold moray spots onto dorsal/flank facets deterministically.
			if sa > -0.15 and ((k + s_i + pattern_seed) % 5 == 0):
				base_c = base_c.lerp(COL_GOLD_SPOT, 0.78)
			cols.append(base_c)
		rings.append(ring)
		ring_cols.append(cols)
		centers.append(Vector3(0.0, yc, z))

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = ring_cols[j]
		var c1: Array = ring_cols[j + 1]
		var ctr := (centers[j] + centers[j + 1]) * 0.5
		for k in segs:
			var nk := (k + 1) % segs
			_add_outward_quad_grad(st, r1[nk], r0[nk], r0[k], r1[k], ctr,
				c1[nk], c0[nk], c0[k], c1[k])

	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	var f_ref := centers[0] + Vector3(0.0, 0.0, 0.08)
	var f_tip := centers[0] + Vector3(0.0, 0.0, -0.03)
	for k in segs:
		var nk := (k + 1) % segs
		_add_outward_tri(st, f_tip, first_r[k], first_r[nk], f_ref, first_c[k], first_c[k], first_c[nk])

	var last_i := rings.size() - 1
	var last_r: Array = rings[last_i]
	var last_c: Array = ring_cols[last_i]
	var b_ref := centers[last_i] + Vector3(0.0, 0.0, -0.08)
	var b_tip := centers[last_i] + Vector3(0.0, 0.0, 0.03)
	for k in segs:
		var nk := (k + 1) % segs
		_add_outward_tri(st, b_tip, last_r[nk], last_r[k], b_ref, last_c[k], last_c[nk], last_c[k])


static func _append_dorsal_crest(st: SurfaceTool, z0: float, z1: float,
		y0: float, y1: float, h0: float, h1: float) -> void:
	var zm := (z0 + z1) * 0.5
	var ym := (y0 + y1) * 0.5
	var hm := (h0 + h1) * 0.56
	var w := 0.028

	var bl0 := Vector3(-w, y0, z0)
	var br0 := Vector3(w, y0, z0)
	var blm := Vector3(-w, ym, zm)
	var brm := Vector3(w, ym, zm)
	var bl1 := Vector3(-w, y1, z1)
	var br1 := Vector3(w, y1, z1)

	var t0 := Vector3(0.0, y0 + h0, z0 + 0.04)
	var tm := Vector3(0.0, ym + hm, zm)
	var t1 := Vector3(0.0, y1 + h1, z1 - 0.03)
	var ctr := Vector3(0.0, ym + hm * 0.25, zm)

	_add_outward_quad_grad(st, t0, tm, blm, bl0, ctr, COL_FIN_CREST, COL_FIN_CREST, COL_FIN_BASE, COL_FIN_BASE)
	_add_outward_quad_grad(st, tm, t1, bl1, blm, ctr, COL_FIN_CREST, COL_FIN_CREST, COL_FIN_BASE, COL_FIN_BASE)
	_add_outward_quad_grad(st, tm, t0, br0, brm, ctr, COL_FIN_CREST, COL_FIN_CREST, COL_FIN_BASE, COL_FIN_BASE)
	_add_outward_quad_grad(st, t1, tm, brm, br1, ctr, COL_FIN_CREST, COL_FIN_CREST, COL_FIN_BASE, COL_FIN_BASE)
	_add_outward_tri(st, t0, bl0, br0, ctr, COL_FIN_CREST, COL_FIN_BASE, COL_FIN_BASE)
	_add_outward_tri(st, t1, br1, bl1, ctr, COL_FIN_CREST, COL_FIN_BASE, COL_FIN_BASE)


static func _append_fang(st: SurfaceTool, base: Vector3, tip: Vector3, radius: float) -> void:
	var axis := tip - base
	if axis.length_squared() < 1e-6:
		return
	var dir := axis.normalized()
	var ref := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.85 else Vector3.FORWARD
	var u := dir.cross(ref).normalized()
	var v := u.cross(dir).normalized()
	var segs := 4
	var ring: Array[Vector3] = []
	for i in segs:
		var a := float(i) / float(segs) * TAU
		ring.append(base + (u * cos(a) + v * sin(a)) * radius)
	var ctr := base.lerp(tip, 0.3)
	for i in segs:
		var ni := (i + 1) % segs
		_add_outward_tri(st, tip, ring[i], ring[ni], ctr, COL_FANG_IVORY, COL_FANG_IVORY, COL_FANG_IVORY)


static func _append_spot_plaque(st: SurfaceTool, center: Vector3, half_ext: Vector3) -> void:
	var px := center + Vector3(half_ext.x, 0.0, 0.0)
	var nx := center + Vector3(-half_ext.x, 0.0, 0.0)
	var py := center + Vector3(0.0, half_ext.y, 0.0)
	var ny := center + Vector3(0.0, -half_ext.y, 0.0)
	var pz := center + Vector3(0.0, 0.0, half_ext.z)
	var nz := center + Vector3(0.0, 0.0, -half_ext.z)
	var deep := COL_GOLD_SPOT.darkened(0.15)
	_add_outward_tri(st, py, px, nz, center, COL_GOLD_SPOT, COL_GOLD_SPOT, COL_GOLD_SPOT)
	_add_outward_tri(st, py, nz, nx, center, COL_GOLD_SPOT, COL_GOLD_SPOT, COL_GOLD_SPOT)
	_add_outward_tri(st, py, nx, pz, center, COL_GOLD_SPOT, COL_GOLD_SPOT, COL_GOLD_SPOT)
	_add_outward_tri(st, py, pz, px, center, COL_GOLD_SPOT, COL_GOLD_SPOT, COL_GOLD_SPOT)
	_add_outward_tri(st, ny, nz, px, center, deep, COL_GOLD_SPOT, COL_GOLD_SPOT)
	_add_outward_tri(st, ny, nx, nz, center, deep, COL_GOLD_SPOT, COL_GOLD_SPOT)
	_add_outward_tri(st, ny, pz, nx, center, deep, COL_GOLD_SPOT, COL_GOLD_SPOT)
	_add_outward_tri(st, ny, px, pz, center, deep, COL_GOLD_SPOT, COL_GOLD_SPOT)


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
