class_name EnemyBrain
extends Node
## Distinct enemy AI behaviours for the Drowned and Tidecaller factions.
##
## Archetypes (each has genuinely different tactical behaviour, never a reskin):
## - &"drowned_cutlass" : aggressive melee shambler; telegraphed slashes weak to parry.
## - &"drowned_shield"  : advances with barnacle buckler blocking frontal light strikes;
##                        must be flanked, heavy-attacked, or parried after its lunge.
## - &"drowned_powder"  : sprints carrying a lit explosive keg; shooting or letting it
##                        reach melee detonates a 6.5 m blast (damaging enemies too!).
## - &"drowned_captain" : tough leader; rallies & buffs nearby Drowned, mixes heavy
##                        cutlass combos with flintlock pistol volleys.
## - &"tidecaller"      : coral sea-cultist; keeps ranged distance (11..20 m), strafes
##                        away when rushed, casts water bolts & bubbling geyser hazards.

signal keg_detonated(pos: Vector3, radius: float)
signal rallied_allies(captain: Pawn, count: int)
signal enemy_defeated(archetype: StringName, pos: Vector3)

const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

@export var archetype: StringName = &"drowned_cutlass"
@export var aggro_range: float = 34.0
@export var leash_range: float = 65.0

var pawn: Pawn = null
var combat: CombatComponent = null
var home_pos: Vector3 = Vector3.ZERO
var target: Pawn = null

var _attack_cd: float = 0.0
var _special_cd: float = 4.0
var _rattle_cd: float = 3.0
var _strafe_sign: float = 1.0
var _keg_blown: bool = false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	process_physics_priority = -10


func _ready() -> void:
	name = "EnemyBrain"
	pawn = get_parent() as Pawn
	assert(pawn != null, "EnemyBrain must be a child of a Pawn")
	home_pos = pawn.global_position
	_rng.randomize()
	_strafe_sign = 1.0 if _rng.randf() > 0.5 else -1.0
	_ensure_combat()
	_configure_archetype()
	pawn.died.connect(_on_died)


func _ensure_combat() -> void:
	for c in pawn.get_children():
		if c is CombatComponent:
			combat = c as CombatComponent
			break
	if combat == null:
		combat = CombatComponent.new()
		combat.name = "CombatComponent"
		pawn.add_child(combat)


func _configure_archetype() -> void:
	var vis := pawn.get_node_or_null(^"Visual")
	if vis != null and vis.has_method(&"set_archetype"):
		vis.call(&"set_archetype", archetype)

	match archetype:
		&"drowned_shield":
			combat.faction = &"drowned"
			combat.has_shield = true
			combat.equip_weapon(&"cutlass")
			pawn.max_health = 115.0
			pawn.walk_speed = 2.9
			pawn.sprint_speed = 3.6
		&"drowned_powder":
			combat.faction = &"drowned"
			combat.equip_weapon(&"cutlass")
			pawn.max_health = 45.0
			pawn.walk_speed = 4.1
			pawn.sprint_speed = 5.4
		&"drowned_captain":
			combat.faction = &"drowned"
			combat.equip_weapon(&"boarding_axe")
			pawn.max_health = 185.0
			pawn.walk_speed = 3.4
			pawn.sprint_speed = 4.8
		&"tidecaller":
			combat.faction = &"tidecaller"
			combat.equip_weapon(&"tide_staff")
			pawn.max_health = 90.0
			pawn.walk_speed = 3.6
			pawn.sprint_speed = 4.9
		_:
			# &"drowned_cutlass"
			combat.faction = &"drowned"
			combat.equip_weapon(&"cutlass")
			pawn.max_health = 75.0
			pawn.walk_speed = 3.3
			pawn.sprint_speed = 4.6
	pawn.health = pawn.max_health


## Spawn a fully wired enemy Pawn with visual archetype, CombatComponent, and EnemyBrain.
static func spawn_enemy(p_archetype: StringName, world_pos: Vector3, parent: Node, board_ship: PhysicsBody3D = null) -> Pawn:
	var p := PAWN_SCENE.instantiate() as Pawn
	p.name = String(p_archetype).to_pascal_case()
	var cc := CombatComponent.new()
	cc.name = "CombatComponent"
	cc.faction = &"tidecaller" if p_archetype == &"tidecaller" else &"drowned"
	p.add_child(cc)
	var brain := EnemyBrain.new()
	brain.archetype = p_archetype
	p.add_child(brain)
	parent.add_child(p)
	if board_ship != null:
		p.board(board_ship, board_ship.global_transform.affine_inverse() * world_pos)
	else:
		p.global_position = world_pos
	brain.home_pos = p.global_position
	return p


## Called by CombatComponent when a ranged shot strikes this enemy (detonates powder keg!).
func on_shot_hit(shooter: Pawn) -> void:
	if archetype == &"drowned_powder" and not _keg_blown:
		detonate_keg(shooter)


## Detonate the Powder-Carrier's gunpowder keg with a 6.5 m blast radius.
func detonate_keg(trigger: Node = null) -> void:
	if not Net.is_host() or _keg_blown:
		return
	_keg_blown = true
	var blast_pos := pawn.global_position + Vector3.UP * 1.1
	const BLAST_RADIUS := 6.5
	Audio.play_sfx(&"cannon_fire", blast_pos, 2.0)

	# Damage all nearby pawns (including friendly Drowned — shooting a keg clears packs!).
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc == null or cc.pawn == null or cc.pawn == pawn or cc.pawn.dead:
			continue
		var d := blast_pos.distance_to(cc.pawn.global_position + Vector3.UP * 1.0)
		if d < BLAST_RADIUS:
			var falloff := 1.0 - (d / BLAST_RADIUS) * 0.65
			cc.pawn.apply_damage(85.0 * falloff, trigger if trigger != null else pawn)
			var push := (cc.pawn.global_position - blast_pos)
			push.y = 0.0
			if push.length_squared() > 0.001:
				cc.pawn.velocity += push.normalized() * 8.5 * falloff + Vector3.UP * 3.5

	# Also breach a nearby ship hull if detonated aboard or alongside!
	for snode in get_tree().get_nodes_in_group(&"ship"):
		var s := snode as Ship
		if s != null and s.global_position.distance_to(blast_pos) < 10.0:
			s.apply_hull_damage(blast_pos, 0.72)

	keg_detonated.emit(blast_pos, BLAST_RADIUS)
	pawn.apply_damage(999.0, trigger)


func _on_died() -> void:
	enemy_defeated.emit(archetype, pawn.global_position)


# ------------------------------------------------------------------ AI loop

func _physics_process(delta: float) -> void:
	if not Net.is_host() or pawn == null or pawn.dead:
		if pawn != null:
			pawn.wish_dir = Vector3.ZERO
			pawn.wish_sprint = false
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_special_cd = maxf(0.0, _special_cd - delta)
	_rattle_cd = maxf(0.0, _rattle_cd - delta)

	if combat != null and combat.is_staggered():
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		return

	target = _pick_target()
	if target == null:
		combat.set_blocking(false)
		var to_home := home_pos - pawn.global_position
		to_home.y = 0.0
		if to_home.length() > 3.0:
			var d := to_home.normalized()
			pawn.wish_dir = d * 0.6
			pawn.look_yaw = atan2(-d.x, -d.z)
		else:
			pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		return

	var to_t := target.global_position - pawn.global_position
	var flat := Vector3(to_t.x, 0.0, to_t.z)
	var dist := flat.length()
	var dir := flat.normalized() if dist > 0.01 else Vector3.FORWARD
	pawn.look_yaw = atan2(-dir.x, -dir.z)
	var dy := (target.eye_position().y - pawn.eye_position().y)
	pawn.look_pitch = clampf(atan2(dy, maxf(dist, 0.5)), -0.7, 0.7)

	if _rattle_cd <= 0.0 and dist < 16.0:
		_rattle_cd = _rng.randf_range(5.0, 9.0)
		Audio.play_sfx(&"skeleton_rattle", pawn.global_position, -6.0)

	match archetype:
		&"drowned_powder":
			_tick_powder_carrier(dir, dist)
		&"drowned_shield":
			_tick_shield_bearer(dir, dist)
		&"drowned_captain":
			_tick_captain(dir, dist)
		&"tidecaller":
			_tick_tidecaller(dir, dist)
		_:
			_tick_cutlasser(dir, dist)


func _tick_cutlasser(dir: Vector3, dist: float) -> void:
	if dist > 2.05:
		pawn.wish_dir = dir
		pawn.wish_sprint = dist > 5.0
	else:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		if _attack_cd <= 0.0:
			if combat.primary_attack():
				_attack_cd = _rng.randf_range(0.75, 1.15)


func _tick_shield_bearer(dir: Vector3, dist: float) -> void:
	if dist > 2.2:
		pawn.wish_dir = dir * 0.85
		pawn.wish_sprint = false
		combat.set_blocking(dist < 7.5)
	else:
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		if _attack_cd <= 0.0:
			combat.set_blocking(false)
			if combat.heavy_attack() or combat.primary_attack():
				_attack_cd = 1.65
		else:
			combat.set_blocking(true)


func _tick_powder_carrier(dir: Vector3, dist: float) -> void:
	pawn.wish_dir = dir
	pawn.wish_sprint = true
	if dist <= 2.15:
		detonate_keg(pawn)


func _tick_captain(dir: Vector3, dist: float) -> void:
	# Periodically rally nearby Drowned allies!
	if _special_cd <= 0.0:
		_special_cd = 10.0
		var buffed := 0
		for node in get_tree().get_nodes_in_group(&"combatants"):
			var cc := node as CombatComponent
			if cc != null and cc.faction == combat.faction and cc.pawn != null and not cc.pawn.dead:
				if cc.pawn.global_position.distance_to(pawn.global_position) < 18.0:
					cc.apply_rally_buff(7.0, 1.35)
					buffed += 1
		Audio.play_sfx(&"crew_shout", pawn.global_position, 1.0, 0.04)
		rallied_allies.emit(pawn, buffed)

	# Mix ranged pistol shot at mid-range with heavy axe melee up close.
	if dist > 8.5 and dist < 24.0 and _attack_cd <= 0.0:
		combat.equip_weapon(&"pistol")
		if combat.primary_attack():
			_attack_cd = 2.4
		pawn.wish_dir = dir * 0.7
		pawn.wish_sprint = false
	elif dist > 2.2:
		combat.equip_weapon(&"boarding_axe")
		pawn.wish_dir = dir
		pawn.wish_sprint = dist > 5.5
	else:
		combat.equip_weapon(&"boarding_axe")
		pawn.wish_dir = Vector3.ZERO
		pawn.wish_sprint = false
		if _attack_cd <= 0.0:
			var did := combat.heavy_attack() if _rng.randf() < 0.45 else combat.primary_attack()
			if did:
				_attack_cd = 1.05


func _tick_tidecaller(dir: Vector3, dist: float) -> void:
	var right := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
	if dist < 9.5:
		# Kite back & strafe to keep ranged advantage!
		pawn.wish_dir = (-dir * 0.8 + right * 0.5).normalized()
		pawn.wish_sprint = dist < 5.0
	elif dist > 20.0:
		pawn.wish_dir = (dir * 0.85 + right * 0.3).normalized()
		pawn.wish_sprint = false
	else:
		pawn.wish_dir = right * 0.65
		pawn.wish_sprint = false

	if _attack_cd <= 0.0 and dist < 30.0:
		combat.equip_weapon(&"tide_staff")
		if combat.primary_attack():
			_attack_cd = 2.1
			if _rng.randf() < 0.4:
				_strafe_sign = -_strafe_sign

	# Periodically summon a bubbling water geyser under the target.
	if _special_cd <= 0.0 and dist < 24.0:
		_special_cd = 7.5
		_summon_water_hazard(target.global_position)


func _summon_water_hazard(at: Vector3) -> void:
	var host := pawn.get_parent()
	if host == null:
		return
	Audio.play_sfx(&"splash_small", at, 1.0)
	# Brief telegraphed bubbling ring that bursts after 1.1 s.
	var ring := MeshInstance3D.new()
	ring.name = "TideHazard"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.8
	cyl.bottom_radius = 1.8
	cyl.height = 0.08
	ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.18, 0.92, 0.86, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	host.add_child(ring)
	ring.global_position = at + Vector3(0.0, 0.08, 0.0)
	var timer := get_tree().create_timer(1.1)
	var caster := pawn
	var caster_faction := combat.faction
	timer.timeout.connect(func() -> void:
		if is_instance_valid(ring):
			var p_pos := ring.global_position
			Audio.play_sfx(&"splash_large", p_pos, -4.0)
			if Net.is_host():
				for node in get_tree().get_nodes_in_group(&"combatants"):
					var cc := node as CombatComponent
					if cc != null and cc.faction != caster_faction and cc.pawn != null and not cc.pawn.dead:
						if cc.pawn.global_position.distance_to(p_pos) <= 2.1 and not cc.is_invulnerable():
							cc.pawn.apply_damage(22.0, caster)
							cc.pawn.velocity.y += 4.5
			ring.queue_free()
	)


func _pick_target() -> Pawn:
	var best: Pawn = null
	var best_d := aggro_range
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc == null or cc.faction == combat.faction or cc.pawn == null or cc.pawn.dead:
			continue
		if cc.pawn.global_position.distance_to(home_pos) > leash_range:
			continue
		var d := pawn.global_position.distance_to(cc.pawn.global_position)
		if d < best_d:
			best_d = d
			best = cc.pawn
	return best
