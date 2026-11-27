class_name EnemyBrain
extends Node
## Distinct enemy AI behaviours for the Drowned, Tidecaller, and Corsair factions.
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
## - &"corsair_raider"  : third faction rival pirate; dodges incoming attacks, weaves
##                        mid-range flintlock shots with agile flanking cutlass lunges.
## - &"rival_captain"   : named rival corsair captain; parries telegraphed strikes,
##                        blasts with blunderbuss/pistol, and pushes aggressive boarding combos.

signal keg_detonated(pos: Vector3, radius: float)
signal rallied_allies(captain: Pawn, count: int)
signal enemy_defeated(archetype: StringName, pos: Vector3)

const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

const TIDE_VORTEX_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint_deep : source_color = vec3(0.04, 0.46, 0.56);
uniform vec3 tint_glow : source_color = vec3(0.24, 0.98, 0.90);
uniform vec3 tint_core : source_color = vec3(0.82, 1.0, 0.98);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}

	float p_ease = progress * progress;
	float angle = atan(p.y, p.x + 1e-6);
	float ang_mask = smoothstep(0.04, 0.16, r);
	float spin = TIME * mix(2.4, 5.8, progress);

	// Outer contracting danger-zone ring that tightens smoothly as detonation nears.
	float outer_r = mix(0.90, 0.62, p_ease);
	float d_outer = (r - outer_r) / mix(0.068, 0.045, progress);
	float outer_ring = exp(-d_outer * d_outer);

	// Counter-rotating notched coral-rune glyph ring inside the vortex.
	float rune_r = mix(0.64, 0.36, progress);
	float d_rune = (r - rune_r) / 0.055;
	float rune_band = exp(-d_rune * d_rune);
	float rune_glyphs = smoothstep(0.05, 0.38, sin(angle * 8.0 + spin * 1.35))
		* smoothstep(-0.2, 0.55, cos(angle * 4.0 - spin * 0.7));
	float rune_ring = rune_band * (0.35 + 0.85 * rune_glyphs * ang_mask);

	// Five-armed bioluminescent aquamarine spiral pulled inward toward the spout.
	float spiral_wave = sin(angle * 5.0 + r * 11.5 - spin * 1.9);
	float spiral = smoothstep(0.10, 0.88, spiral_wave * 0.5 + 0.5)
		* ang_mask * (1.0 - smoothstep(outer_r - 0.04, outer_r + 0.08, r));

	// Boiling central surge well intensifying sharply right before eruption.
	float d_core = r / mix(0.32, 0.24, progress);
	float center_well = exp(-d_core * d_core) * (0.32 + 0.88 * p_ease);

	// Subtle animated water-ripple caustics inside the danger circle.
	float ripple = 0.5 + 0.5 * sin(r * 22.0 - spin * 2.6 + sin(angle * 3.0) * 1.2 * ang_mask);
	float base_pool = (1.0 - smoothstep(outer_r * 0.65, outer_r + 0.05, r))
		* (0.22 + 0.16 * ripple);

	float pulse = 0.86 + 0.14 * sin(TIME * mix(7.0, 22.0, progress));
	float intensity = mix(0.75, 1.85, progress) * pulse;

	float pattern = clamp(base_pool + spiral * 0.52 + rune_ring * 0.85 + outer_ring * 0.95 + center_well * 0.90, 0.0, 1.5);
	vec3 col = mix(tint_deep, tint_glow, clamp(spiral * 0.6 + rune_ring * 0.75 + outer_ring * 0.8, 0.0, 1.0));
	col = mix(col, tint_core, clamp(center_well * 0.85 + outer_ring * p_ease * 0.7, 0.0, 1.0));

	float fade_in = smoothstep(0.0, 0.12, progress);
	float alpha = clamp(pattern * fade_in * mix(0.72, 0.96, progress), 0.0, 0.96);
	ALBEDO = col * intensity;
	ALPHA = alpha;
}
"""

const CAPTAIN_RALLY_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint_outer : source_color = vec3(0.10, 0.88, 0.64);
uniform vec3 tint_inner : source_color = vec3(0.54, 1.0, 0.82);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}

	float angle = atan(p.y, p.x + 1e-6);
	float ang_mask = smoothstep(0.06, 0.20, r);

	// Crisp expanding shockwave crest with inner harmonic echo and subtle war-cry rays.
	float d_wave = (r - 0.86) / mix(0.085, 0.052, progress);
	float wave_band = exp(-d_wave * d_wave);
	float d_echo = (r - 0.66) / 0.095;
	float inner_echo = exp(-d_echo * d_echo) * 0.48 * (1.0 - progress * 0.45);
	float trail = smoothstep(0.42, 0.86, r) * (1.0 - smoothstep(0.88, 1.0, r)) * 0.28;
	float rays = 0.82 + 0.18 * sin(angle * 12.0 - TIME * 5.0) * ang_mask;

	float fade_in = smoothstep(0.0, 0.08, progress);
	float rem = clamp(1.0 - progress, 0.0, 1.0);
	float fade_out = rem * sqrt(max(rem, 0.0));
	float strength = (wave_band * rays + inner_echo + trail) * fade_in * fade_out;

	vec3 col = mix(tint_outer, tint_inner, clamp(wave_band * 0.85, 0.0, 1.0));
	ALBEDO = col * strength * 1.65;
	ALPHA = clamp(strength, 0.0, 1.0);
}
"""

@export var archetype: StringName = &"drowned_cutlass"
@export var aggro_range: float = 34.0
@export var leash_range: float = 65.0
## Toggle signature combat VFX (powder-keg explosion, Tidecaller vortex/geyser, Captain rally ring).
@export var enable_effects: bool = true

var pawn: Pawn = null
var combat: CombatComponent = null
var home_pos: Vector3 = Vector3.ZERO
var target: Pawn = null

const ENEMY_AURA_HALO_WEDGES := 8
const ENEMY_AURA_HALO_INNER_R := 0.055
const ENEMY_AURA_HALO_OUTER_R := 0.24
const ENEMY_AURA_VISIBILITY_RANGE := 95.0
const COL_ENEMY_AURA_CORE := Color(1.00, 1.00, 1.00, 1.0)
const COL_ENEMY_AURA_MID := Color(0.32, 0.32, 0.32, 1.0)
const COL_ENEMY_AURA_RIM := Color(0.0, 0.0, 0.0, 1.0)

const DROWNED_EYE_HALO_POS := Vector3(0.0, 1.62, -0.14)
const DROWNED_EYE_DAY_ENERGY := 0.18
const DROWNED_EYE_NIGHT_ENERGY := 0.76
const DROWNED_EYE_SURGE_ENERGY := 1.32
const DROWNED_EYE_FLARE_DURATION := 0.85
const DROWNED_EYE_BASE_SCALE := 1.0
const DROWNED_EYE_SURGE_SCALE := 1.28
const COL_DROWNED_EYE_BASE := Color(0.16, 0.96, 0.62, 1.0)
const COL_DROWNED_EYE_SURGE := Color(0.46, 1.00, 0.78, 1.0)

const TIDECALLER_CAST_HALO_POS := Vector3(0.0, 1.92, -0.12)
const TIDECALLER_DAY_ENERGY := 0.28
const TIDECALLER_NIGHT_ENERGY := 0.68
const TIDECALLER_FLARE_ENERGY := 1.52
const TIDECALLER_FLARE_DURATION := 0.68
const TIDECALLER_BASE_SCALE := 1.45
const TIDECALLER_PEAK_SCALE := 2.35
const COL_TIDECALLER_BASE := Color(0.14, 0.92, 0.96, 1.0)
const COL_TIDECALLER_SURGE := Color(0.58, 1.00, 0.98, 1.0)

var _attack_cd: float = 0.0
var _special_cd: float = 4.0
var _rally_cd: float = 6.5
var _rattle_cd: float = 3.0
var _strafe_sign: float = 1.0
var _keg_blown: bool = false
var _rng := RandomNumberGenerator.new()
var _active_vfx: Array[Node] = []
var _stagger_stars: MeshInstance3D = null
var _strike_telegraph: MeshInstance3D = null
var _stagger_clock: float = 0.0
var _telegraph_elapsed: float = 0.0
var _telegraph_dur: float = 0.34
var _drowned_eye_halo: MeshInstance3D = null
var _drowned_eye_halo_mat: StandardMaterial3D = null
var _drowned_eye_halo_energy: float = 0.0
var _drowned_eye_flare_timer: float = 0.0
var _tidecaller_cast_halo: MeshInstance3D = null
var _tidecaller_cast_halo_mat: StandardMaterial3D = null
var _tidecaller_cast_halo_energy: float = 0.0
var _tidecaller_flare_timer: float = 0.0
var _aura_clock: float = 0.0

static var _active_brains: int = 0
static var _stagger_stars_mesh: ArrayMesh = null
static var _stagger_stars_mat: StandardMaterial3D = null
static var _telegraph_mesh: ArrayMesh = null
static var _telegraph_mat: StandardMaterial3D = null
static var _enemy_aura_halo_mesh: ArrayMesh = null
static var _fireball_tex: ImageTexture = null
static var _smoke_puff_tex: ImageTexture = null
static var _streak_tex: ImageTexture = null
static var _tide_vortex_shader: Shader = null
static var _captain_rally_shader: Shader = null
static var _barrel_shard_mesh: ArrayMesh = null
static var _barrel_shard_mat: StandardMaterial3D = null


func _init() -> void:
	process_physics_priority = -10


func _enter_tree() -> void:
	_active_brains += 1


func _exit_tree() -> void:
	# VFX live on host so explosions/geysers finish cleanly after pawn death;
	# each VFX node releases its own GPU resources on tree_exiting.
	_active_vfx.clear()
	if combat != null and is_instance_valid(combat) and combat.ranged_fired.is_connected(_on_combat_ranged_fired):
		combat.ranged_fired.disconnect(_on_combat_ranged_fired)
	for node_mi: MeshInstance3D in [_stagger_stars, _strike_telegraph, _drowned_eye_halo, _tidecaller_cast_halo]:
		if node_mi != null and is_instance_valid(node_mi):
			node_mi.visible = false
			node_mi.material_override = null
			node_mi.mesh = null
			if node_mi.get_parent() == null:
				node_mi.queue_free()
	_stagger_stars = null
	_strike_telegraph = null
	_drowned_eye_halo = null
	_drowned_eye_halo_mat = null
	_drowned_eye_halo_energy = 0.0
	_drowned_eye_flare_timer = 0.0
	_tidecaller_cast_halo = null
	_tidecaller_cast_halo_mat = null
	_tidecaller_cast_halo_energy = 0.0
	_tidecaller_flare_timer = 0.0
	_active_brains = maxi(0, _active_brains - 1)
	if _active_brains == 0:
		clear_shared_vfx_cache()


## Release all statically cached EnemyBrain VFX meshes, materials, textures & shaders cleanly.
static func clear_shared_vfx_cache() -> void:
	if _barrel_shard_mesh != null and _barrel_shard_mesh.get_surface_count() > 0:
		_barrel_shard_mesh.surface_set_material(0, null)
	_stagger_stars_mesh = null
	_stagger_stars_mat = null
	_telegraph_mesh = null
	_telegraph_mat = null
	_enemy_aura_halo_mesh = null
	_fireball_tex = null
	_smoke_puff_tex = null
	_streak_tex = null
	_tide_vortex_shader = null
	_captain_rally_shader = null
	_barrel_shard_mesh = null
	_barrel_shard_mat = null


func get_stagger_stars_node() -> MeshInstance3D:
	return _stagger_stars


func get_strike_telegraph_node() -> MeshInstance3D:
	return _strike_telegraph


## Return the sculpted 24-tri spectral emerald DrownedEyeHalo MeshInstance3D, or null for non-Drowned.
func get_drowned_eye_halo() -> MeshInstance3D:
	if _drowned_eye_halo != null and is_instance_valid(_drowned_eye_halo):
		return _drowned_eye_halo
	return null


## Return the current additive glow energy of DrownedEyeHalo (0.0 when hidden/dead or non-Drowned).
func get_drowned_eye_halo_energy() -> float:
	return _drowned_eye_halo_energy


## Return the sculpted 24-tri bioluminescent TidecallerCastHalo MeshInstance3D, or null for non-Tidecaller.
func get_tidecaller_cast_halo() -> MeshInstance3D:
	if _tidecaller_cast_halo != null and is_instance_valid(_tidecaller_cast_halo):
		return _tidecaller_cast_halo
	return null


## Return the current additive glow energy of TidecallerCastHalo (0.0 when hidden/dead or non-Tidecaller).
func get_tidecaller_cast_halo_energy() -> float:
	return _tidecaller_cast_halo_energy


func _ready() -> void:
	name = "EnemyBrain"
	pawn = get_parent() as Pawn
	assert(pawn != null, "EnemyBrain must be a child of a Pawn")
	home_pos = pawn.global_position
	_rng.randomize()
	_strafe_sign = 1.0 if _rng.randf() > 0.5 else -1.0
	_ensure_combat()
	_configure_archetype()
	_build_combat_telegraphs()
	_build_enemy_auras()
	if archetype == &"tidecaller" and combat != null and not combat.ranged_fired.is_connected(_on_combat_ranged_fired):
		combat.ranged_fired.connect(_on_combat_ranged_fired)
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
	var vis := pawn.get_node_or_null(^"Visual/CharacterVisual")
	if vis == null:
		vis = pawn.get_node_or_null(^"Visual")
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
		&"corsair_raider":
			combat.faction = &"corsair"
			combat.equip_weapon(&"cutlass")
			pawn.max_health = 95.0
			pawn.walk_speed = 3.9
			pawn.sprint_speed = 5.5
		&"rival_captain":
			combat.faction = &"corsair"
			combat.equip_weapon(&"cutlass")
			pawn.max_health = 210.0
			pawn.walk_speed = 4.0
			pawn.sprint_speed = 5.6
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
	if p_archetype == &"tidecaller":
		cc.faction = &"tidecaller"
	elif p_archetype == &"corsair_raider" or p_archetype == &"rival_captain":
		cc.faction = &"corsair"
	else:
		cc.faction = &"drowned"
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

	# Damage all nearby pawns (including friendly Drowned -- shooting a keg clears packs!).
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

	if enable_effects:
		_spawn_keg_explosion_vfx(blast_pos)

	keg_detonated.emit(blast_pos, BLAST_RADIUS)
	pawn.apply_damage(999.0, trigger)


func _on_died() -> void:
	_hide_combat_telegraphs()
	_hide_enemy_auras()
	enemy_defeated.emit(archetype, pawn.global_position)


# ------------------------------------------------------------------ AI loop

func _physics_process(delta: float) -> void:
	_tick_combat_telegraphs(delta)
	step_enemy_auras(delta)
	if not Net.is_host() or pawn == null or pawn.dead:
		if pawn != null:
			pawn.wish_dir = Vector3.ZERO
			pawn.wish_sprint = false
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_special_cd = maxf(0.0, _special_cd - delta)
	_rally_cd = maxf(0.0, _rally_cd - delta)
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
		if combat.faction == &"drowned":
			Audio.play_sfx(&"skeleton_rattle", pawn.global_position, -6.0)
		elif combat.faction == &"corsair":
			Audio.play_sfx(&"crew_shout", pawn.global_position, -5.0, 0.08)

	match archetype:
		&"drowned_powder":
			_tick_powder_carrier(dir, dist)
		&"drowned_shield":
			_tick_shield_bearer(dir, dist)
		&"drowned_captain":
			_tick_captain(dir, dist)
		&"tidecaller":
			_tick_tidecaller(dir, dist)
		&"corsair_raider":
			_tick_corsair_raider(dir, dist)
		&"rival_captain":
			_tick_rival_captain(dir, dist)
		_:
			_tick_cutlasser(dir, dist)


func _tick_corsair_raider(dir: Vector3, dist: float) -> void:
	var right := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
	# Agile flanker: weaves pistol shots at mid-range and dodges before lunging in.
	if dist > 6.5 and dist < 20.0 and _special_cd <= 0.0:
		combat.equip_weapon(&"pistol")
		if combat.primary_attack():
			_special_cd = 4.6
			_strafe_sign = -_strafe_sign
		pawn.wish_dir = (dir * 0.5 + right * 0.85).normalized()
		pawn.wish_sprint = false
	elif dist > 2.35:
		combat.equip_weapon(&"cutlass")
		pawn.wish_dir = (dir * 0.82 + right * 0.42).normalized()
		pawn.wish_sprint = dist > 5.0
	else:
		combat.equip_weapon(&"cutlass")
		pawn.wish_dir = right * 0.55
		pawn.wish_sprint = false
		if _special_cd <= 0.0 and _rng.randf() < 0.35:
			if combat.dodge_step(right):
				_special_cd = 3.2
		if _attack_cd <= 0.0:
			if combat.primary_attack():
				_attack_cd = _rng.randf_range(0.58, 0.92)


func _tick_rival_captain(dir: Vector3, dist: float) -> void:
	var right := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
	# Periodically rally nearby Corsair raiders with a crimson-gold war-cry shockwave.
	if _rally_cd <= 0.0:
		_rally_cd = 11.0
		_perform_captain_rally()
	# Tactically guards briefly to fish for parries when pressed, mixes blunderbuss & combos.
	if dist > 5.0 and dist < 14.0 and _special_cd <= 0.0:
		combat.set_blocking(false)
		combat.equip_weapon(&"blunderbuss")
		if combat.primary_attack():
			_special_cd = 5.4
			_strafe_sign = -_strafe_sign
		pawn.wish_dir = (dir * 0.7 + right * 0.5).normalized()
		pawn.wish_sprint = false
	elif dist > 2.3:
		combat.set_blocking(false)
		combat.equip_weapon(&"cutlass")
		pawn.wish_dir = (dir * 0.88 + right * 0.3).normalized()
		pawn.wish_sprint = dist > 5.2
	else:
		combat.equip_weapon(&"cutlass")
		pawn.wish_dir = right * 0.35
		pawn.wish_sprint = false
		if _attack_cd > 0.35:
			combat.set_blocking(true)
		elif _attack_cd <= 0.0:
			combat.set_blocking(false)
			var did := combat.heavy_attack() if _rng.randf() < 0.38 else combat.primary_attack()
			if did:
				_attack_cd = 0.88


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
		_perform_captain_rally()

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
			trigger_tidecaller_cast_flare()
			_attack_cd = 2.1
			if _rng.randf() < 0.4:
				_strafe_sign = -_strafe_sign

	# Periodically summon a bubbling water geyser under the target.
	if _special_cd <= 0.0 and dist < 24.0:
		_special_cd = 7.5
		_summon_water_hazard(target.global_position)


func _perform_captain_rally() -> void:
	var buffed := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc != null and cc.faction == combat.faction and cc.pawn != null and not cc.pawn.dead:
			if cc.pawn.global_position.distance_to(pawn.global_position) < 18.0:
				cc.apply_rally_buff(7.0, 1.35)
				if cc.faction == &"drowned" and cc.pawn != pawn:
					var ally_brain := cc.pawn.get_node_or_null(^"EnemyBrain") as EnemyBrain
					if ally_brain != null:
						ally_brain._trigger_drowned_eye_surge()
				buffed += 1
	if combat != null and combat.faction == &"drowned":
		_trigger_drowned_eye_surge()
	Audio.play_sfx(&"crew_shout", pawn.global_position, 1.0, 0.04)
	if enable_effects:
		_spawn_captain_rally_vfx(pawn.global_position)
	rallied_allies.emit(pawn, buffed)


func _summon_water_hazard(at: Vector3) -> void:
	var host := pawn.get_parent()
	if host == null:
		return
	if archetype == &"tidecaller":
		trigger_tidecaller_cast_flare()
	Audio.play_sfx(&"splash_small", at, 1.0)

	# Phase 1 (1.1 s Telegraph): ground-hugging shader coral-rune vortex + rising mist.
	var hazard := MeshInstance3D.new()
	hazard.name = "TideHazard"
	hazard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hazard.mesh = _build_xz_quad_mesh(Vector2(4.4, 4.4))

	var mat := ShaderMaterial.new()
	mat.shader = _get_tide_vortex_shader()
	mat.render_priority = 1
	mat.set_shader_parameter(&"progress", 0.0)
	hazard.material_override = mat

	var mist: GPUParticles3D = null
	if enable_effects:
		mist = GPUParticles3D.new()
		mist.name = "VortexMist"
		mist.emitting = false
		mist.one_shot = false
		mist.amount = 10
		mist.lifetime = 0.75
		mist.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mist.visibility_aabb = AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 4.5, 6.0))

		var m_proc := ParticleProcessMaterial.new()
		m_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		m_proc.emission_ring_radius = 1.45
		m_proc.emission_ring_inner_radius = 0.22
		m_proc.emission_ring_height = 0.12
		m_proc.emission_ring_axis = Vector3.UP
		m_proc.direction = Vector3.UP
		m_proc.spread = 18.0
		m_proc.initial_velocity_min = 0.9
		m_proc.initial_velocity_max = 2.4
		m_proc.gravity = Vector3(0.0, 0.8, 0.0)
		m_proc.scale_min = 0.45
		m_proc.scale_max = 0.95
		m_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.40), Vector2(0.45, 1.05), Vector2(1.0, 1.45)])
		m_proc.color_ramp = _make_color_ramp(
			PackedFloat32Array([0.0, 0.28, 0.72, 1.0]),
			PackedColorArray([
				Color(0.30, 0.96, 0.92, 0.0),
				Color(0.56, 0.99, 0.96, 0.68),
				Color(0.24, 0.88, 0.90, 0.34),
				Color(0.16, 0.74, 0.84, 0.0),
			])
		)
		mist.process_material = m_proc

		var m_mat := StandardMaterial3D.new()
		m_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		m_mat.vertex_color_use_as_albedo = true
		m_mat.render_priority = 2
		m_mat.albedo_texture = _get_smoke_puff_texture()
		mist.draw_pass_1 = _build_quad_card_mesh(Vector2(0.72, 0.72), m_mat)
		hazard.add_child(mist)

	host.add_child(hazard)
	hazard.global_position = at + Vector3(0.0, 0.08, 0.0)
	_bind_vfx_lifecycle(hazard)
	_track_vfx(hazard)

	if mist != null:
		mist.restart()
		mist.emitting = true

	var tw := hazard.create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_method(EnemyBrain._set_shader_progress.bind(mat), 0.0, 1.0, 1.1)

	var det_timer := Timer.new()
	det_timer.name = "DetonateTimer"
	det_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	det_timer.wait_time = 1.1
	det_timer.one_shot = true
	det_timer.autostart = true
	var caster_ref: WeakRef = weakref(pawn)
	var brain_ref: WeakRef = weakref(self)
	var caster_faction := combat.faction
	var spawn_vfx := enable_effects
	det_timer.timeout.connect(EnemyBrain._on_tide_hazard_detonate.bind(
		hazard, host, caster_ref, caster_faction, spawn_vfx, brain_ref
	))
	hazard.add_child(det_timer)


# ------------------------------------------------------------------ Signature Combat VFX

func _track_vfx(fx_node: Node) -> void:
	if fx_node == null or not is_instance_valid(fx_node):
		return
	_active_vfx.append(fx_node)
	fx_node.tree_exited.connect(_on_vfx_exited.bind(fx_node))


func _on_vfx_exited(fx_node: Node) -> void:
	_active_vfx.erase(fx_node)


static func _bind_vfx_lifecycle(fx_node: Node, auto_free_sec: float = -1.0) -> void:
	fx_node.tree_exiting.connect(EnemyBrain._release_vfx_resources.bind(fx_node))
	if auto_free_sec > 0.0:
		var cleanup := Timer.new()
		cleanup.name = "VfxCleanupTimer"
		cleanup.process_callback = Timer.TIMER_PROCESS_PHYSICS
		cleanup.wait_time = auto_free_sec
		cleanup.one_shot = true
		cleanup.autostart = true
		cleanup.timeout.connect(EnemyBrain._finish_vfx_node.bind(fx_node))
		fx_node.add_child(cleanup)


static func _release_vfx_resources(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is GPUParticles3D:
		var gp := node as GPUParticles3D
		gp.emitting = false
		if gp.draw_pass_1 is ArrayMesh and gp.draw_pass_1 != _barrel_shard_mesh:
			var am := gp.draw_pass_1 as ArrayMesh
			if am.get_surface_count() > 0:
				var sm := am.surface_get_material(0)
				if sm is StandardMaterial3D:
					(sm as StandardMaterial3D).albedo_texture = null
				am.surface_set_material(0, null)
		if gp.process_material is ParticleProcessMaterial:
			var pm := gp.process_material as ParticleProcessMaterial
			pm.color_ramp = null
			pm.scale_curve = null
		gp.material_override = null
		gp.draw_pass_1 = null
		gp.process_material = null
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = null
		mi.mesh = null
	for child in node.get_children():
		_release_vfx_resources(child)


static func _finish_vfx_node(fx_node: Node) -> void:
	if fx_node == null or not is_instance_valid(fx_node):
		return
	_release_vfx_resources(fx_node)
	fx_node.queue_free()


static func _set_shader_progress(value: float, mat: ShaderMaterial) -> void:
	if mat != null:
		mat.set_shader_parameter(&"progress", value)


static func _collect_player_controllers(node: Node, out: Array[PlayerController]) -> void:
	if node is PlayerController:
		out.append(node as PlayerController)
	for child in node.get_children():
		_collect_player_controllers(child, out)


static func _make_color_ramp(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture1D.new()
	tex.width = 32
	tex.gradient = grad
	return tex


static func _make_scale_curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	for pt in points:
		curve.add_point(pt)
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


static func _build_quad_card_mesh(size: Vector2, mat: Material = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	const NORM := Vector3(0.0, 0.0, 1.0)
	var v0 := Vector3(-hw, -hh, 0.0)
	var v1 := Vector3(hw, -hh, 0.0)
	var v2 := Vector3(hw, hh, 0.0)
	var v3 := Vector3(-hw, hh, 0.0)
	st.set_normal(NORM); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v0)
	st.set_normal(NORM); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v2)
	st.set_normal(NORM); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(v1)
	st.set_normal(NORM); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v0)
	st.set_normal(NORM); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(v3)
	st.set_normal(NORM); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v2)
	var mesh := st.commit()
	if mat != null:
		mesh.surface_set_material(0, mat)
	return mesh


static func _build_xz_quad_mesh(size: Vector2, mat: Material = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	const UP_NORM := Vector3(0.0, 1.0, 0.0)
	var v0 := Vector3(-hw, 0.0, -hd)
	var v1 := Vector3(hw, 0.0, -hd)
	var v2 := Vector3(hw, 0.0, hd)
	var v3 := Vector3(-hw, 0.0, hd)
	st.set_normal(UP_NORM); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(v0)
	st.set_normal(UP_NORM); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v1)
	st.set_normal(UP_NORM); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(v2)
	st.set_normal(UP_NORM); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(v0)
	st.set_normal(UP_NORM); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(v2)
	st.set_normal(UP_NORM); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v3)
	var mesh := st.commit()
	if mat != null:
		mesh.surface_set_material(0, mat)
	return mesh


static func _get_fireball_texture() -> ImageTexture:
	if _fireball_tex != null:
		return _fireball_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	# Radial Gaussian core blended with fiery billowing multi-lobe silhouette.
	var lobes: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.84),
		Vector3(-0.26, -0.14, 0.50),
		Vector3(0.28, -0.10, 0.48),
		Vector3(0.08, 0.28, 0.46),
		Vector3(-0.22, 0.22, 0.44),
		Vector3(0.22, 0.20, 0.42),
	]
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var rad := sqrt(nx * nx + ny * ny)
			var gauss := exp(-rad * rad * 3.6)
			var billow := 0.0
			for lobe in lobes:
				var dx := nx - lobe.x
				var dy := ny - lobe.y
				var r := sqrt(dx * dx + dy * dy) / lobe.z
				if r < 1.0:
					var w := 1.0 - r * r
					billow = maxf(billow, w * w)
			var outer_fade := smoothstep(0.0, 0.45, clampf(1.0 - rad, 0.0, 1.0))
			var alpha := clampf(lerpf(gauss, billow, 0.52) * outer_fade, 0.0, 1.0)
			var hot := lerpf(0.88, 1.0, clampf(gauss * 1.15, 0.0, 1.0))
			img.set_pixel(x, y, Color(hot, hot, hot, alpha))
	_fireball_tex = ImageTexture.create_from_image(img)
	return _fireball_tex


static func _get_smoke_puff_texture() -> ImageTexture:
	if _smoke_puff_tex != null:
		return _smoke_puff_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	var lobes: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.86),
		Vector3(-0.25, -0.10, 0.54),
		Vector3(0.24, -0.08, 0.52),
		Vector3(0.05, 0.24, 0.50),
		Vector3(-0.18, 0.20, 0.44),
		Vector3(0.20, 0.18, 0.40),
	]
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var rad := sqrt(nx * nx + ny * ny)
			var gauss := exp(-rad * rad * 3.2)
			var billow := 0.0
			for lobe in lobes:
				var dx := nx - lobe.x
				var dy := ny - lobe.y
				var r := sqrt(dx * dx + dy * dy) / lobe.z
				if r < 1.0:
					var w := 1.0 - r * r
					billow = maxf(billow, w * w)
			var outer_fade := smoothstep(0.0, 0.48, clampf(1.0 - rad, 0.0, 1.0))
			var density := clampf(lerpf(gauss, billow, 0.62) * outer_fade, 0.0, 1.0)
			var top_lit := clampf(0.92 - ny * 0.08 + density * 0.08, 0.80, 1.0)
			img.set_pixel(x, y, Color(top_lit, top_lit, top_lit, density))
	_smoke_puff_tex = ImageTexture.create_from_image(img)
	return _smoke_puff_tex


static func _get_streak_texture() -> ImageTexture:
	if _streak_tex != null:
		return _streak_tex
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := absf(float(x) - half) / half
			var dy := absf(float(y) - half) / half
			var d := sqrt(dx * dx * 3.0 + dy * dy * 1.05)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_streak_tex = ImageTexture.create_from_image(img)
	return _streak_tex


static func _get_tide_vortex_shader() -> Shader:
	if _tide_vortex_shader == null:
		_tide_vortex_shader = Shader.new()
		_tide_vortex_shader.code = TIDE_VORTEX_SHADER_CODE
	return _tide_vortex_shader


static func _get_captain_rally_shader() -> Shader:
	if _captain_rally_shader == null:
		_captain_rally_shader = Shader.new()
		_captain_rally_shader.code = CAPTAIN_RALLY_SHADER_CODE
	return _captain_rally_shader


## Spawn layered fiery powder-keg detonation burst, camera trauma, and ocean foam.
func _spawn_keg_explosion_vfx(blast_pos: Vector3) -> void:
	# Apply distance-attenuated camera shake trauma to any nearby PlayerController.
	var tree := get_tree()
	if tree != null and tree.root != null:
		var pcs: Array[PlayerController] = []
		_collect_player_controllers(tree.root, pcs)
		for pc in pcs:
			if not is_instance_valid(pc) or not pc.is_inside_tree():
				continue
			var ref_pos := pc.pawn.global_position if (pc.pawn != null and is_instance_valid(pc.pawn)) else pc.global_position
			var d := ref_pos.distance_to(blast_pos)
			if d <= 24.0:
				pc.add_camera_trauma(clampf((1.0 - d / 24.0) * 0.78, 0.18, 0.78))

	# Stamp boiling ocean foam ring when detonated near sea level.
	if blast_pos.y < 3.5 and Ocean.current != null:
		Ocean.current.add_foam(blast_pos, 5.2, 1.0)

	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return

	var fx_root := Node3D.new()
	fx_root.name = "KegExplosionVFX"

	# Layer 1: Blazing additive fireball core flash (0.38 s).
	var fireball := GPUParticles3D.new()
	fireball.name = "FireballCore"
	fireball.emitting = false
	fireball.one_shot = true
	fireball.explosiveness = 0.96
	fireball.amount = 22
	fireball.lifetime = 0.38
	fireball.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fireball.visibility_aabb = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 14.0, 16.0))

	var fb_proc := ParticleProcessMaterial.new()
	fb_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fb_proc.emission_sphere_radius = 0.45
	fb_proc.direction = Vector3.UP
	fb_proc.spread = 160.0
	fb_proc.initial_velocity_min = 2.8
	fb_proc.initial_velocity_max = 8.6
	fb_proc.damping_min = 6.5
	fb_proc.damping_max = 10.5
	fb_proc.gravity = Vector3(0.0, 2.2, 0.0)
	fb_proc.scale_min = 1.10
	fb_proc.scale_max = 2.10
	fb_proc.scale_curve = _make_scale_curve([
		Vector2(0.0, 0.45), Vector2(0.22, 1.65), Vector2(0.65, 1.85), Vector2(1.0, 0.35),
	])
	fb_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.26, 0.62, 1.0]),
		PackedColorArray([
			Color(1.0, 0.99, 0.88, 1.0),
			Color(1.0, 0.72, 0.18, 0.96),
			Color(0.95, 0.28, 0.05, 0.72),
			Color(0.55, 0.06, 0.02, 0.0),
		])
	)
	fireball.process_material = fb_proc

	var fb_mat := StandardMaterial3D.new()
	fb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fb_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fb_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fb_mat.vertex_color_use_as_albedo = true
	fb_mat.render_priority = 3
	fb_mat.albedo_texture = _get_fireball_texture()
	fireball.draw_pass_1 = _build_quad_card_mesh(Vector2(2.6, 2.6), fb_mat)
	fx_root.add_child(fireball)

	# Layer 2: Billowing gunpowder mushroom smoke plume (1.45 s, scale 0.6 -> 3.0).
	var smoke := GPUParticles3D.new()
	smoke.name = "GunpowderSmoke"
	smoke.emitting = false
	smoke.one_shot = true
	smoke.explosiveness = 0.88
	smoke.amount = 44
	smoke.lifetime = 1.45
	smoke.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-12.0, -4.0, -12.0), Vector3(24.0, 20.0, 24.0))

	var sm_proc := ParticleProcessMaterial.new()
	sm_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	sm_proc.emission_ring_radius = 0.95
	sm_proc.emission_ring_inner_radius = 0.12
	sm_proc.emission_ring_height = 0.42
	sm_proc.emission_ring_axis = Vector3.UP
	sm_proc.direction = Vector3.UP
	sm_proc.spread = 38.0
	sm_proc.initial_velocity_min = 2.6
	sm_proc.initial_velocity_max = 6.6
	sm_proc.damping_min = 3.2
	sm_proc.damping_max = 5.8
	sm_proc.gravity = Vector3(0.0, 2.6, 0.0)
	sm_proc.scale_min = 0.95
	sm_proc.scale_max = 1.55
	sm_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.60), Vector2(0.35, 1.85), Vector2(1.0, 3.0)])
	sm_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.10, 0.36, 0.74, 1.0]),
		PackedColorArray([
			Color(0.92, 0.46, 0.18, 0.0),
			Color(0.50, 0.32, 0.22, 0.92),
			Color(0.20, 0.20, 0.23, 0.84),
			Color(0.13, 0.14, 0.17, 0.44),
			Color(0.11, 0.13, 0.16, 0.0),
		])
	)
	smoke.process_material = sm_proc

	var sm_mat := StandardMaterial3D.new()
	sm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm_mat.vertex_color_use_as_albedo = true
	sm_mat.render_priority = 1
	sm_mat.albedo_texture = _get_smoke_puff_texture()
	smoke.draw_pass_1 = _build_quad_card_mesh(Vector2(2.05, 2.05), sm_mat)
	fx_root.add_child(smoke)

	# Layer 3A: Velocity-aligned golden ember spark streaks scattering radially (0.75 s).
	var sparks := GPUParticles3D.new()
	sparks.name = "EmberSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.explosiveness = 0.96
	sparks.amount = 44
	sparks.lifetime = 0.75
	sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.visibility_aabb = AABB(Vector3(-14.0, -8.0, -14.0), Vector3(28.0, 20.0, 28.0))

	var sp_proc := ParticleProcessMaterial.new()
	sp_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp_proc.emission_sphere_radius = 0.40
	sp_proc.direction = Vector3.UP
	sp_proc.spread = 115.0
	sp_proc.initial_velocity_min = 7.5
	sp_proc.initial_velocity_max = 17.5
	sp_proc.damping_min = 1.4
	sp_proc.damping_max = 3.2
	sp_proc.gravity = Vector3(0.0, -15.5, 0.0)
	sp_proc.scale_min = 0.70
	sp_proc.scale_max = 1.55
	sp_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.30, 0.72, 1.0]),
		PackedColorArray([
			Color(1.0, 0.98, 0.82, 1.0),
			Color(1.0, 0.64, 0.14, 0.96),
			Color(0.92, 0.24, 0.04, 0.56),
			Color(0.60, 0.08, 0.02, 0.0),
		])
	)
	sparks.process_material = sp_proc

	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sp_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sp_mat.vertex_color_use_as_albedo = true
	sp_mat.render_priority = 3
	sp_mat.albedo_texture = _get_streak_texture()
	sparks.draw_pass_1 = _build_quad_card_mesh(Vector2(0.10, 0.48), sp_mat)
	fx_root.add_child(sparks)

	# Layer 3B: Tumbling charred wooden keg barrel staves flying radially with gravity (0.75 s).
	var shards := GPUParticles3D.new()
	shards.name = "BarrelShards"
	shards.emitting = false
	shards.one_shot = true
	shards.explosiveness = 0.95
	shards.amount = 26
	shards.lifetime = 0.75
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shards.visibility_aabb = AABB(Vector3(-12.0, -8.0, -12.0), Vector3(24.0, 18.0, 24.0))

	var sh_proc := ParticleProcessMaterial.new()
	sh_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sh_proc.emission_sphere_radius = 0.42
	sh_proc.direction = Vector3.UP
	sh_proc.spread = 105.0
	sh_proc.initial_velocity_min = 5.5
	sh_proc.initial_velocity_max = 13.5
	sh_proc.angular_velocity_min = -16.0
	sh_proc.angular_velocity_max = 16.0
	sh_proc.gravity = Vector3(0.0, -17.5, 0.0)
	sh_proc.scale_min = 0.65
	sh_proc.scale_max = 1.45
	sh_proc.scale_curve = _make_scale_curve([Vector2(0.0, 1.0), Vector2(0.72, 0.92), Vector2(1.0, 0.0)])
	shards.process_material = sh_proc

	shards.draw_pass_1 = _get_barrel_shard_mesh()
	shards.material_override = _get_barrel_shard_material()
	fx_root.add_child(shards)

	host.add_child(fx_root)
	fx_root.global_position = blast_pos
	fireball.restart()
	smoke.restart()
	sparks.restart()
	shards.restart()
	fireball.emitting = true
	smoke.emitting = true
	sparks.emitting = true
	shards.emitting = true

	_bind_vfx_lifecycle(fx_root, 1.60)
	_track_vfx(fx_root)


static func _get_barrel_shard_material() -> StandardMaterial3D:
	if _barrel_shard_mat == null:
		_barrel_shard_mat = StandardMaterial3D.new()
		_barrel_shard_mat.albedo_color = Color.WHITE
		_barrel_shard_mat.vertex_color_use_as_albedo = true
		_barrel_shard_mat.vertex_color_is_srgb = true
		_barrel_shard_mat.roughness = 0.84
		_barrel_shard_mat.metallic = 0.18
		_barrel_shard_mat.emission_enabled = true
		_barrel_shard_mat.emission = Color(1.0, 0.34, 0.05)
		_barrel_shard_mat.emission_energy_multiplier = 0.32
	return _barrel_shard_mat


static func _get_barrel_shard_mesh() -> ArrayMesh:
	if _barrel_shard_mesh != null:
		return _barrel_shard_mesh
	# Sculpted flat-faceted Jagged Charred Barrel-Stave Shrapnel: curved broken oak stave
	# with splintered ember tips and a ripped wrought-iron barrel hoop fragment!
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_oak := Color(0.36, 0.21, 0.10)
	var col_char := Color(0.08, 0.06, 0.05)
	var col_ember := Color(0.95, 0.34, 0.05)
	var col_iron := Color(0.13, 0.13, 0.15)
	var col_iron_hi := Color(0.22, 0.21, 0.23)

	# 1. Curved tapered barrel stave body (5 stations along Z: -0.22 charred ember tip -> +0.22 splintered oak tip).
	# [z, x_left, x_right, y_arch, half_thick, col]
	var stave_rows: Array[Array] = [
		[-0.22, -0.012, 0.022, -0.008, 0.007, col_ember],
		[-0.12, -0.044, 0.046, 0.005, 0.014, col_char],
		[0.00, -0.050, 0.050, 0.012, 0.016, col_oak],
		[0.12, -0.042, 0.046, 0.004, 0.014, col_oak.darkened(0.18)],
		[0.22, -0.026, 0.014, -0.008, 0.006, col_char],
	]
	var s_rings: Array[Array] = []
	var s_cols: Array[Color] = []
	for row in stave_rows:
		var z := float(row[0])
		var xl := float(row[1])
		var xr := float(row[2])
		var ya := float(row[3])
		var ht := float(row[4])
		s_rings.append([
			Vector3(xl, ya + ht, z),
			Vector3(xr, ya + ht, z),
			Vector3(xr, ya - ht, z),
			Vector3(xl, ya - ht, z),
		])
		s_cols.append(row[5] as Color)

	for i in range(s_rings.size() - 1):
		var r0: Array = s_rings[i]
		var r1: Array = s_rings[i + 1]
		var c0 := s_cols[i]
		var c1 := s_cols[i + 1]
		var ctr: Vector3 = ((r0[0] as Vector3) + (r0[2] as Vector3) + (r1[0] as Vector3) + (r1[2] as Vector3)) * 0.25
		for k in 4:
			var nk := (k + 1) % 4
			_emit_shard_quad(st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3, ctr, c0, c1, c1, c0)

	# Cap jagged splinter ends cleanly with pointed triangular tips!
	var tip_front := Vector3(0.004, -0.010, -0.258)
	var tip_back := Vector3(-0.008, -0.010, 0.255)
	var rf: Array = s_rings[0]
	var rb: Array = s_rings[s_rings.size() - 1]
	for k in 4:
		var nk := (k + 1) % 4
		_emit_shard_tri(st, tip_front, rf[nk] as Vector3, rf[k] as Vector3, Vector3(0.0, 0.0, -0.12), col_ember, col_ember, col_ember)
		_emit_shard_tri(st, tip_back, rb[k] as Vector3, rb[nk] as Vector3, Vector3(0.0, 0.0, 0.12), col_char, col_char, col_char)

	# 2. Ripped bent wrought-iron barrel hoop strap clasping the stave mid-section!
	var hz0 := -0.036
	var hz1 := 0.028
	var h_pts: Array[Vector3] = [
		Vector3(-0.056, 0.032, hz0), Vector3(0.064, 0.036, hz0), Vector3(0.064, 0.022, hz0), Vector3(-0.056, 0.018, hz0),
		Vector3(-0.056, 0.032, hz1), Vector3(0.064, 0.036, hz1), Vector3(0.064, 0.022, hz1), Vector3(-0.056, 0.018, hz1),
	]
	var h_ctr := Vector3(0.004, 0.027, -0.004)
	_emit_shard_quad(st, h_pts[0], h_pts[1], h_pts[5], h_pts[4], h_ctr, col_iron_hi, col_iron_hi, col_iron_hi, col_iron_hi)
	_emit_shard_quad(st, h_pts[3], h_pts[7], h_pts[6], h_pts[2], h_ctr, col_iron, col_iron, col_iron, col_iron)
	_emit_shard_quad(st, h_pts[0], h_pts[4], h_pts[7], h_pts[3], h_ctr, col_iron, col_iron, col_iron, col_iron)
	_emit_shard_quad(st, h_pts[1], h_pts[2], h_pts[6], h_pts[5], h_ctr, col_iron_hi, col_iron, col_iron, col_iron_hi)
	_emit_shard_quad(st, h_pts[0], h_pts[3], h_pts[2], h_pts[1], h_ctr, col_iron, col_iron, col_iron, col_iron)
	_emit_shard_quad(st, h_pts[4], h_pts[5], h_pts[6], h_pts[7], h_ctr, col_iron, col_iron, col_iron, col_iron)

	st.generate_normals()
	_barrel_shard_mesh = st.commit()
	return _barrel_shard_mesh


static func _emit_shard_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_shard_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_shard_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_shard_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _on_tide_hazard_detonate(
	hazard: MeshInstance3D,
	host: Node,
	caster_ref: WeakRef,
	caster_faction: StringName,
	spawn_vfx: bool,
	brain_ref: WeakRef
) -> void:
	if not is_instance_valid(hazard) or not hazard.is_inside_tree():
		return
	var p_pos := hazard.global_position
	Audio.play_sfx(&"splash_large", p_pos, -4.0)
	var tree := hazard.get_tree()
	var caster_obj: Variant = caster_ref.get_ref()
	var caster_node: Node = caster_obj as Node if (caster_obj != null and is_instance_valid(caster_obj)) else null
	if Net.is_host() and tree != null:
		for node in tree.get_nodes_in_group(&"combatants"):
			var cc := node as CombatComponent
			if cc != null and cc.faction != caster_faction and cc.pawn != null and not cc.pawn.dead:
				if cc.pawn.global_position.distance_to(p_pos) <= 2.1 and not cc.is_invulnerable():
					cc.pawn.apply_damage(22.0, caster_node)
					cc.pawn.velocity.y += 4.5
	if spawn_vfx and is_instance_valid(host) and host.is_inside_tree():
		_spawn_tide_geyser_burst(host, p_pos, brain_ref)
	_finish_vfx_node(hazard)


## Phase 2 Eruption: tall feathered turquoise-white water-geyser spout + droplets + coral sparks.
static func _spawn_tide_geyser_burst(host: Node, p_pos: Vector3, brain_ref: WeakRef) -> void:
	if p_pos.y < 3.5 and Ocean.current != null:
		Ocean.current.add_foam(p_pos, 3.6, 0.9)

	var fx_root := Node3D.new()
	fx_root.name = "TideGeyserBurst"

	# 1. Tall upward-shooting feathered turquoise-white foam column (0.85 s).
	var col_p := GPUParticles3D.new()
	col_p.name = "GeyserFoamColumn"
	col_p.emitting = false
	col_p.one_shot = true
	col_p.explosiveness = 0.84
	col_p.amount = 40
	col_p.lifetime = 0.85
	col_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	col_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	col_p.visibility_aabb = AABB(Vector3(-6.0, -1.0, -6.0), Vector3(12.0, 16.0, 12.0))

	var col_proc := ParticleProcessMaterial.new()
	col_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	col_proc.emission_ring_radius = 0.68
	col_proc.emission_ring_inner_radius = 0.08
	col_proc.emission_ring_height = 0.22
	col_proc.emission_ring_axis = Vector3.UP
	col_proc.direction = Vector3.UP
	col_proc.spread = 10.0
	col_proc.initial_velocity_min = 11.5
	col_proc.initial_velocity_max = 20.5
	col_proc.damping_min = 1.8
	col_proc.damping_max = 3.4
	col_proc.gravity = Vector3(0.0, -16.5, 0.0)
	col_proc.scale_min = 0.90
	col_proc.scale_max = 1.95
	col_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.55), Vector2(0.32, 1.30), Vector2(1.0, 1.90)])
	col_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.12, 0.48, 1.0]),
		PackedColorArray([
			Color(0.86, 1.0, 0.99, 0.0),
			Color(0.68, 0.98, 0.96, 0.94),
			Color(0.16, 0.86, 0.86, 0.78),
			Color(0.08, 0.62, 0.76, 0.0),
		])
	)
	col_p.process_material = col_proc

	var col_mat := StandardMaterial3D.new()
	col_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	col_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	col_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	col_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	col_mat.vertex_color_use_as_albedo = true
	col_mat.render_priority = 2
	col_mat.albedo_texture = _get_smoke_puff_texture()
	col_p.draw_pass_1 = _build_quad_card_mesh(Vector2(1.35, 2.35), col_mat)
	fx_root.add_child(col_p)

	# 2. Outward-arcing sparkling water droplet streaks (0.85 s).
	var drops := GPUParticles3D.new()
	drops.name = "GeyserDroplets"
	drops.emitting = false
	drops.one_shot = true
	drops.explosiveness = 0.94
	drops.amount = 48
	drops.lifetime = 0.85
	drops.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.visibility_aabb = AABB(Vector3(-9.0, -2.0, -9.0), Vector3(18.0, 16.0, 18.0))

	var d_proc := ParticleProcessMaterial.new()
	d_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	d_proc.emission_ring_radius = 0.85
	d_proc.emission_ring_inner_radius = 0.20
	d_proc.emission_ring_height = 0.20
	d_proc.emission_ring_axis = Vector3.UP
	d_proc.direction = Vector3.UP
	d_proc.spread = 42.0
	d_proc.initial_velocity_min = 8.5
	d_proc.initial_velocity_max = 16.5
	d_proc.gravity = Vector3(0.0, -19.5, 0.0)
	d_proc.scale_min = 0.60
	d_proc.scale_max = 1.30
	d_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.25, 0.72, 1.0]),
		PackedColorArray([
			Color(0.92, 1.0, 1.0, 0.96),
			Color(0.56, 0.97, 0.98, 0.90),
			Color(0.18, 0.84, 0.90, 0.52),
			Color(0.10, 0.68, 0.82, 0.0),
		])
	)
	drops.process_material = d_proc

	var d_mat := StandardMaterial3D.new()
	d_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	d_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	d_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	d_mat.vertex_color_use_as_albedo = true
	d_mat.render_priority = 2
	d_mat.albedo_texture = _get_streak_texture()
	drops.draw_pass_1 = _build_quad_card_mesh(Vector2(0.16, 0.68), d_mat)
	fx_root.add_child(drops)

	# 3. Bioluminescent cyan coral-rune sparks erupting outward (0.80 s).
	var coral := GPUParticles3D.new()
	coral.name = "CoralSparks"
	coral.emitting = false
	coral.one_shot = true
	coral.explosiveness = 0.92
	coral.amount = 32
	coral.lifetime = 0.80
	coral.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	coral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coral.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 14.0, 16.0))

	var c_proc := ParticleProcessMaterial.new()
	c_proc.direction = Vector3.UP
	c_proc.spread = 58.0
	c_proc.initial_velocity_min = 6.5
	c_proc.initial_velocity_max = 13.5
	c_proc.damping_min = 1.8
	c_proc.damping_max = 3.5
	c_proc.gravity = Vector3(0.0, -10.5, 0.0)
	c_proc.scale_min = 0.75
	c_proc.scale_max = 1.45
	c_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.30, 0.74, 1.0]),
		PackedColorArray([
			Color(0.84, 1.0, 1.0, 1.0),
			Color(0.14, 1.0, 0.92, 0.98),
			Color(0.06, 0.74, 0.92, 0.60),
			Color(0.04, 0.44, 0.76, 0.0),
		])
	)
	coral.process_material = c_proc

	var c_mat := StandardMaterial3D.new()
	c_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	c_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	c_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	c_mat.vertex_color_use_as_albedo = true
	c_mat.render_priority = 3
	c_mat.albedo_texture = _get_streak_texture()
	coral.draw_pass_1 = _build_quad_card_mesh(Vector2(0.13, 0.56), c_mat)
	fx_root.add_child(coral)

	host.add_child(fx_root)
	fx_root.global_position = p_pos
	col_p.restart()
	drops.restart()
	coral.restart()
	col_p.emitting = true
	drops.emitting = true
	coral.emitting = true

	_bind_vfx_lifecycle(fx_root, 0.95)
	var brain_obj: Variant = brain_ref.get_ref()
	if brain_obj != null and is_instance_valid(brain_obj) and brain_obj is EnemyBrain:
		(brain_obj as EnemyBrain)._track_vfx(fx_root)


## Spawn ground-hugging expanding War-Cry Rally Shockwave Ring (0.9 m -> 11.5 m over 0.65 s).
func _spawn_captain_rally_vfx(at: Vector3) -> void:
	var host := pawn.get_parent() if pawn != null else null
	if host == null:
		return

	var ring := MeshInstance3D.new()
	ring.name = "CaptainRallyRing"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.mesh = _build_xz_quad_mesh(Vector2(2.0, 2.0))

	var is_corsair := archetype == &"rival_captain" or (combat != null and combat.faction == &"corsair")
	var tint_outer := Color(0.96, 0.24, 0.14) if is_corsair else Color(0.10, 0.88, 0.64)
	var tint_inner := Color(1.0, 0.82, 0.30) if is_corsair else Color(0.54, 1.0, 0.82)

	var mat := ShaderMaterial.new()
	mat.shader = _get_captain_rally_shader()
	mat.render_priority = 2
	mat.set_shader_parameter(&"progress", 0.0)
	mat.set_shader_parameter(&"tint_outer", tint_outer)
	mat.set_shader_parameter(&"tint_inner", tint_inner)
	ring.material_override = mat

	host.add_child(ring)
	ring.global_position = at + Vector3(0.0, 0.12, 0.0)
	ring.scale = Vector3(0.9, 1.0, 0.9)
	_bind_vfx_lifecycle(ring)
	_track_vfx(ring)

	var tw := ring.create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(ring, "scale", Vector3(11.5, 1.0, 11.5), 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(EnemyBrain._set_shader_progress.bind(mat), 0.0, 1.0, 0.65)
	tw.chain().tween_callback(EnemyBrain._finish_vfx_node.bind(ring))


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


# ==============================================================================
# Sculpted Parry-Stagger Dizzy Crown (`StaggerStars`) & Heavy-Strike Telegraph
# ==============================================================================

func _build_combat_telegraphs() -> void:
	if pawn == null:
		return
	_ensure_telegraph_assets()

	_stagger_stars = MeshInstance3D.new()
	_stagger_stars.name = "StaggerStars"
	_stagger_stars.mesh = _stagger_stars_mesh
	_stagger_stars.material_override = _stagger_stars_mat
	_stagger_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stagger_stars.position = Vector3(0.0, 2.08, 0.0)
	_stagger_stars.visible = false

	_strike_telegraph = MeshInstance3D.new()
	_strike_telegraph.name = "StrikeTelegraph"
	_strike_telegraph.mesh = _telegraph_mesh
	_strike_telegraph.material_override = _telegraph_mat
	_strike_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strike_telegraph.position = Basis(Vector3.UP, pawn.look_yaw) * Vector3(0.32, 1.55, -0.35)
	_strike_telegraph.visible = false

	if pawn.is_node_ready():
		pawn.add_child(_stagger_stars)
		pawn.add_child(_strike_telegraph)
	else:
		pawn.add_child.call_deferred(_stagger_stars)
		pawn.add_child.call_deferred(_strike_telegraph)


func _hide_combat_telegraphs() -> void:
	_stagger_clock = 0.0
	_telegraph_elapsed = 0.0
	if _stagger_stars != null and is_instance_valid(_stagger_stars):
		_stagger_stars.visible = false
	if _strike_telegraph != null and is_instance_valid(_strike_telegraph):
		_strike_telegraph.visible = false


func _tick_combat_telegraphs(delta: float) -> void:
	if pawn == null or pawn.dead or combat == null:
		_hide_combat_telegraphs()
		return

	# 1. Orbiting gold dizzy crown throughout the 1.5x parry/guard-break stagger window.
	if _stagger_stars != null and is_instance_valid(_stagger_stars):
		if combat.is_staggered():
			_stagger_stars.visible = true
			_stagger_clock += delta
			_stagger_stars.rotation.y += delta * 4.8
			_stagger_stars.rotation.z = sin(_stagger_clock * 5.2) * 0.16
			_stagger_stars.position.y = 2.08 + sin(_stagger_clock * 4.2) * 0.045
		elif _stagger_stars.visible:
			_stagger_stars.visible = false
			_stagger_clock = 0.0

	# 2. Crimson-gold parryable heavy-strike & lunge telegraph flash during WINDUP.
	if _strike_telegraph != null and is_instance_valid(_strike_telegraph):
		var show_flash := _is_melee_telegraph_active()
		if show_flash:
			if not _strike_telegraph.visible:
				_telegraph_elapsed = 0.0
				_telegraph_dur = maxf(combat._state_timer, 0.18)
			_strike_telegraph.visible = true
			_telegraph_elapsed += delta
			var u := clampf(_telegraph_elapsed / maxf(_telegraph_dur, 0.05), 0.0, 1.0)
			var sc: float
			if u < 0.55:
				sc = lerpf(0.35, 1.15, sin((u / 0.55) * PI * 0.5))
			else:
				sc = lerpf(1.15, 0.20, (u - 0.55) / 0.45)
			_strike_telegraph.position = Basis(Vector3.UP, pawn.look_yaw) * Vector3(0.32, 1.55, -0.35)
			_strike_telegraph.rotation = Vector3(0.0, pawn.look_yaw, _telegraph_elapsed * 5.5)
			_strike_telegraph.scale = Vector3.ONE * sc
		elif _strike_telegraph.visible:
			_strike_telegraph.visible = false
			_telegraph_elapsed = 0.0


static func _ensure_telegraph_assets() -> void:
	if _stagger_stars_mat == null:
		_stagger_stars_mat = StandardMaterial3D.new()
		_stagger_stars_mat.albedo_color = Color.WHITE
		_stagger_stars_mat.vertex_color_use_as_albedo = true
		_stagger_stars_mat.vertex_color_is_srgb = true
		_stagger_stars_mat.roughness = 0.25
		_stagger_stars_mat.metallic = 0.65
		_stagger_stars_mat.emission_enabled = true
		_stagger_stars_mat.emission = Color(1.0, 0.84, 0.28)
		_stagger_stars_mat.emission_energy_multiplier = 1.35

	if _stagger_stars_mesh == null:
		_stagger_stars_mesh = _build_stagger_stars_mesh()

	if _telegraph_mat == null:
		_telegraph_mat = StandardMaterial3D.new()
		_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_telegraph_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_telegraph_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_telegraph_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_telegraph_mat.albedo_color = Color(1.35, 0.92, 0.72, 0.96)
		_telegraph_mat.vertex_color_use_as_albedo = true
		_telegraph_mat.vertex_color_is_srgb = true
		_telegraph_mat.emission_enabled = true
		_telegraph_mat.emission = Color(1.0, 0.42, 0.14)
		_telegraph_mat.emission_energy_multiplier = 2.0

	if _telegraph_mesh == null:
		_telegraph_mesh = _build_telegraph_mesh()


static func _build_stagger_stars_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var gold_tip := Color(1.00, 0.96, 0.64)
	var gold_hi := Color(1.00, 0.86, 0.30)
	var gold_mid := Color(0.95, 0.68, 0.14)
	var gold_lo := Color(0.72, 0.42, 0.08)

	# 1. Three sculpted flat-faceted 5-point burnished-gold stars at 120 deg around 0.36 m halo.
	var halo_r := 0.36
	for si in 3:
		var ang := float(si) * (TAU / 3.0)
		var star_c := Vector3(cos(ang) * halo_r, sin(ang * 3.0) * 0.022, sin(ang) * halo_r)
		# Face outward tangentially with a playful 18-degree comic dizzy lean.
		var star_basis := Basis(Vector3.UP, -ang) * Basis(Vector3.RIGHT, deg_to_rad(18.0))
		_append_faceted_5point_star(st, star_c, star_basis, 0.095, 0.042, 0.026,
			gold_tip, gold_hi, gold_mid, gold_lo)

	# 2. Thin luminous gold-amber undulating dizzy ribbon ring (24 segs x 4-side diamond profile).
	var segs := 24
	var minor_w := 0.014
	var minor_h := 0.010
	var ring_pts: Array[Array] = []
	for i in segs:
		var a := float(i) / float(segs) * TAU
		var rad_dir := Vector3(cos(a), 0.0, sin(a))
		var center_p := rad_dir * halo_r + Vector3(0.0, sin(a * 3.0) * 0.022, 0.0)
		ring_pts.append([
			center_p + Vector3(0.0, minor_h, 0.0),
			center_p + rad_dir * minor_w,
			center_p - Vector3(0.0, minor_h, 0.0),
			center_p - rad_dir * minor_w,
		])
	var prof_cols: Array[Color] = [gold_tip, gold_hi, gold_lo, gold_mid]
	for i in segs:
		var ni := (i + 1) % segs
		var r0: Array = ring_pts[i]
		var r1: Array = ring_pts[ni]
		var a_mid := (float(i) + 0.5) / float(segs) * TAU
		var mid_c := Vector3(cos(a_mid) * halo_r, sin(a_mid * 3.0) * 0.022, sin(a_mid) * halo_r)
		for k in 4:
			var nk := (k + 1) % 4
			var fc0 := prof_cols[k]
			var fc1 := prof_cols[nk]
			_emit_outward_quad(st, r0[k] as Vector3, fc0, r1[k] as Vector3, fc0,
				r1[nk] as Vector3, fc1, r0[nk] as Vector3, fc1, mid_c)

	st.generate_normals()
	return st.commit()


static func _build_telegraph_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Three interlocking orthogonal flat-faceted 4-point crimson-gold starburst diamonds
	# so the parry flash pops crisply from front, flank, and deck-overhead camera angles.
	var col_core := Color(1.00, 0.96, 0.78)
	var col_mid := Color(1.00, 0.64, 0.18)
	var col_tip := Color(1.00, 0.24, 0.08)
	var planes: Array[Basis] = [
		Basis.IDENTITY,
		Basis(Vector3.UP, PI * 0.5),
		Basis(Vector3.RIGHT, PI * 0.5),
	]
	for b in planes:
		_append_4point_starburst(st, b, 0.34, 0.095, 0.036, col_core, col_mid, col_tip)

	st.generate_normals()
	return st.commit()


static func _append_faceted_5point_star(st: SurfaceTool, center: Vector3, rot: Basis,
		r_out: float, r_in: float, half_depth: float,
		col_tip: Color, col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var front_apex := center + rot * Vector3(0.0, 0.0, -half_depth)
	var back_apex := center + rot * Vector3(0.0, 0.0, half_depth)
	var ring: Array[Vector3] = []
	var ring_cols: Array[Color] = []
	for k in 10:
		var a := float(k) / 10.0 * TAU + PI * 0.5
		var is_tip := (k % 2 == 0)
		var rad := r_out if is_tip else r_in
		ring.append(center + rot * Vector3(cos(a) * rad, sin(a) * rad, 0.0))
		ring_cols.append(col_tip if is_tip else col_mid)
	for k in 10:
		var nk := (k + 1) % 10
		_emit_outward_tri(st, front_apex, col_hi, ring[k], ring_cols[k], ring[nk], ring_cols[nk], center)
		_emit_outward_tri(st, back_apex, col_lo, ring[nk], ring_cols[nk], ring[k], ring_cols[k], center)


static func _append_4point_starburst(st: SurfaceTool, rot: Basis, r_long: float,
		r_waist: float, half_depth: float, col_core: Color, col_mid: Color, col_tip: Color) -> void:
	var front_apex := rot * Vector3(0.0, 0.0, -half_depth)
	var back_apex := rot * Vector3(0.0, 0.0, half_depth)
	var ring: Array[Vector3] = []
	var ring_cols: Array[Color] = []
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var is_spike := (k % 2 == 0)
		var rad := r_long if is_spike else r_waist
		ring.append(rot * Vector3(cos(a) * rad, sin(a) * rad, 0.0))
		ring_cols.append(col_tip if is_spike else col_mid)
	for k in 8:
		var nk := (k + 1) % 8
		_emit_outward_tri(st, front_apex, col_core, ring[k], ring_cols[k], ring[nk], ring_cols[nk], Vector3.ZERO)
		_emit_outward_tri(st, back_apex, col_core, ring[nk], ring_cols[nk], ring[k], ring_cols[k], Vector3.ZERO)


static func _emit_flat_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-12:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		_emit_flat_tri(st, a, ca, c, cc, b, cb)
	else:
		_emit_flat_tri(st, a, ca, b, cb, c, cc)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, d: Vector3, cd: Color,
		ref_center: Vector3) -> void:
	_emit_outward_tri(st, a, ca, b, cb, c, cc, ref_center)
	_emit_outward_tri(st, a, ca, c, cc, d, cd, ref_center)


# ==============================================================================
# Nocturnal DrownedEyeHalo & Bioluminescent TidecallerCastHalo (Q26A)
# ==============================================================================

func _build_enemy_auras() -> void:
	if pawn == null or combat == null:
		return
	var mount: Node3D = pawn.get_node_or_null(^"Visual") as Node3D
	if mount == null:
		mount = pawn

	if combat.faction == &"drowned":
		var halo_mesh := _ensure_enemy_aura_halo_mesh()
		_drowned_eye_halo_mat = _make_enemy_aura_material()
		_drowned_eye_halo = MeshInstance3D.new()
		_drowned_eye_halo.name = "DrownedEyeHalo"
		_drowned_eye_halo.mesh = halo_mesh
		_drowned_eye_halo.material_override = _drowned_eye_halo_mat
		_drowned_eye_halo.position = DROWNED_EYE_HALO_POS if mount != pawn else Basis(Vector3.UP, pawn.look_yaw) * DROWNED_EYE_HALO_POS
		_drowned_eye_halo.scale = Vector3.ONE * DROWNED_EYE_BASE_SCALE
		_drowned_eye_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drowned_eye_halo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_drowned_eye_halo.visibility_range_end = ENEMY_AURA_VISIBILITY_RANGE
		_drowned_eye_halo.extra_cull_margin = 0.8
		if mount.is_node_ready():
			mount.add_child(_drowned_eye_halo)
		else:
			mount.add_child.call_deferred(_drowned_eye_halo)
	elif archetype == &"tidecaller":
		var halo_mesh := _ensure_enemy_aura_halo_mesh()
		_tidecaller_cast_halo_mat = _make_enemy_aura_material()
		_tidecaller_cast_halo = MeshInstance3D.new()
		_tidecaller_cast_halo.name = "TidecallerCastHalo"
		_tidecaller_cast_halo.mesh = halo_mesh
		_tidecaller_cast_halo.material_override = _tidecaller_cast_halo_mat
		_tidecaller_cast_halo.position = TIDECALLER_CAST_HALO_POS if mount != pawn else Basis(Vector3.UP, pawn.look_yaw) * TIDECALLER_CAST_HALO_POS
		_tidecaller_cast_halo.scale = Vector3.ONE * TIDECALLER_BASE_SCALE
		_tidecaller_cast_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tidecaller_cast_halo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_tidecaller_cast_halo.visibility_range_end = ENEMY_AURA_VISIBILITY_RANGE
		_tidecaller_cast_halo.extra_cull_margin = 1.0
		if mount.is_node_ready():
			mount.add_child(_tidecaller_cast_halo)
		else:
			mount.add_child.call_deferred(_tidecaller_cast_halo)

	step_enemy_auras(0.0)


func _hide_enemy_auras() -> void:
	_drowned_eye_flare_timer = 0.0
	_drowned_eye_halo_energy = 0.0
	if _drowned_eye_halo != null and is_instance_valid(_drowned_eye_halo):
		_drowned_eye_halo.visible = false
	if _drowned_eye_halo_mat != null:
		_drowned_eye_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)

	_tidecaller_flare_timer = 0.0
	_tidecaller_cast_halo_energy = 0.0
	if _tidecaller_cast_halo != null and is_instance_valid(_tidecaller_cast_halo):
		_tidecaller_cast_halo.visible = false
	if _tidecaller_cast_halo_mat != null:
		_tidecaller_cast_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)


func _on_combat_ranged_fired(weapon: StringName, _origin: Vector3, _hit_pos: Vector3) -> void:
	if archetype == &"tidecaller" and weapon == &"tide_staff":
		trigger_tidecaller_cast_flare()


func _trigger_drowned_eye_surge() -> void:
	if pawn == null or pawn.dead or _drowned_eye_halo == null or not is_instance_valid(_drowned_eye_halo):
		return
	_drowned_eye_flare_timer = DROWNED_EYE_FLARE_DURATION
	step_enemy_auras(0.0)


## Trigger a bioluminescent aquamarine cast flare (1.52 -> base, scale 1.45 -> 2.35 -> 1.45 over 0.68 s) on Tidecaller.
func trigger_tidecaller_cast_flare() -> void:
	if pawn == null or pawn.dead or _tidecaller_cast_halo == null or not is_instance_valid(_tidecaller_cast_halo):
		return
	_tidecaller_flare_timer = TIDECALLER_FLARE_DURATION
	step_enemy_auras(0.0)


func _is_melee_telegraph_active() -> bool:
	if combat == null or combat.state != CombatComponent.State.WINDUP:
		return false
	var is_heavy: bool = combat._attack_is_heavy
	var is_lunge: bool = archetype in [&"drowned_captain", &"rival_captain", &"corsair_raider"] \
			and combat.combo_step == 3
	return is_heavy or is_lunge


## Deterministically advance DrownedEyeHalo and TidecallerCastHalo nocturnal glow & surge animation.
func step_enemy_auras(delta: float) -> void:
	var dt := maxf(0.0, delta)
	if pawn == null or pawn.dead:
		_hide_enemy_auras()
		return

	_aura_clock += dt
	_drowned_eye_flare_timer = maxf(0.0, _drowned_eye_flare_timer - dt)
	_tidecaller_flare_timer = maxf(0.0, _tidecaller_flare_timer - dt)

	var daylight := clampf(Weather.daylight(), 0.0, 1.0) if Weather != null else 1.0
	var night := clampf(1.0 - daylight, 0.0, 1.0)
	var storm := clampf(Weather.storminess, 0.0, 1.0) if Weather != null else 0.0
	var gloom := clampf(night + storm * 0.25, 0.0, 1.0)

	if _drowned_eye_halo != null and is_instance_valid(_drowned_eye_halo):
		var simmer := 1.0 + 0.04 * sin(_aura_clock * 3.4)
		var base_e := lerpf(DROWNED_EYE_DAY_ENERGY, DROWNED_EYE_NIGHT_ENERGY, gloom) * simmer
		var surge := 0.0
		if _drowned_eye_flare_timer > 0.0:
			var frem := clampf(_drowned_eye_flare_timer / DROWNED_EYE_FLARE_DURATION, 0.0, 1.0)
			var hold := clampf(frem * 1.15, 0.0, 1.0)
			surge = hold * hold
		if _is_melee_telegraph_active():
			surge = 1.0
		var energy := lerpf(base_e, DROWNED_EYE_SURGE_ENERGY, surge)
		var halo_sc := lerpf(DROWNED_EYE_BASE_SCALE, DROWNED_EYE_SURGE_SCALE, surge)
		var tint := COL_DROWNED_EYE_BASE.lerp(COL_DROWNED_EYE_SURGE, surge)
		_drowned_eye_halo_energy = energy
		_drowned_eye_halo.visible = energy > 0.005
		_drowned_eye_halo.scale = Vector3.ONE * halo_sc
		if _drowned_eye_halo.get_parent() == pawn:
			_drowned_eye_halo.position = Basis(Vector3.UP, pawn.look_yaw) * DROWNED_EYE_HALO_POS
		if _drowned_eye_halo_mat != null:
			_drowned_eye_halo_mat.albedo_color = Color(
				tint.r * energy,
				tint.g * energy,
				tint.b * energy,
				1.0
			)
	else:
		_drowned_eye_halo_energy = 0.0

	if _tidecaller_cast_halo != null and is_instance_valid(_tidecaller_cast_halo):
		var simmer := 1.0 + 0.04 * sin(_aura_clock * 3.1 + 0.9)
		var base_e := lerpf(TIDECALLER_DAY_ENERGY, TIDECALLER_NIGHT_ENERGY, gloom) * simmer
		var energy := base_e
		var halo_sc := TIDECALLER_BASE_SCALE
		var tint := COL_TIDECALLER_BASE
		if _tidecaller_flare_timer > 0.0:
			var fu := 1.0 - clampf(_tidecaller_flare_timer / TIDECALLER_FLARE_DURATION, 0.0, 1.0)
			var frem := 1.0 - fu
			var flare_curve := frem * frem
			energy = lerpf(base_e, TIDECALLER_FLARE_ENERGY, flare_curve)
			halo_sc = lerpf(TIDECALLER_BASE_SCALE, TIDECALLER_PEAK_SCALE, sin(fu * PI))
			tint = COL_TIDECALLER_BASE.lerp(COL_TIDECALLER_SURGE, flare_curve)
		_tidecaller_cast_halo_energy = energy
		_tidecaller_cast_halo.visible = energy > 0.005
		_tidecaller_cast_halo.scale = Vector3.ONE * halo_sc
		if _tidecaller_cast_halo.get_parent() == pawn:
			_tidecaller_cast_halo.position = Basis(Vector3.UP, pawn.look_yaw) * TIDECALLER_CAST_HALO_POS
		if _tidecaller_cast_halo_mat != null:
			_tidecaller_cast_halo_mat.albedo_color = Color(
				tint.r * energy,
				tint.g * energy,
				tint.b * energy,
				1.0
			)
	else:
		_tidecaller_cast_halo_energy = 0.0


static func _make_enemy_aura_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	return mat


static func _ensure_enemy_aura_halo_mesh() -> ArrayMesh:
	if _enemy_aura_halo_mesh == null:
		_enemy_aura_halo_mesh = _build_enemy_aura_halo_mesh()
	return _enemy_aura_halo_mesh


static func _build_enemy_aura_halo_mesh() -> ArrayMesh:
	# Exact 24-tri 8-wedge soft-feathered additive billboard halo (INNER_R=0.055, OUTER_R=0.24)
	# with subdued mid-ring luminance (<= 0.36) fading smoothly to pure Color(0, 0, 0, 1) rim.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	var ctr := Vector3.ZERO
	for i in ENEMY_AURA_HALO_WEDGES:
		var a0 := TAU * float(i) / float(ENEMY_AURA_HALO_WEDGES)
		var a1 := TAU * float(i + 1) / float(ENEMY_AURA_HALO_WEDGES)
		var m0 := Vector3(cos(a0) * ENEMY_AURA_HALO_INNER_R, sin(a0) * ENEMY_AURA_HALO_INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * ENEMY_AURA_HALO_INNER_R, sin(a1) * ENEMY_AURA_HALO_INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * ENEMY_AURA_HALO_OUTER_R, sin(a0) * ENEMY_AURA_HALO_OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * ENEMY_AURA_HALO_OUTER_R, sin(a1) * ENEMY_AURA_HALO_OUTER_R, 0.0)
		# Inner luminous core wedge (8 tris).
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_CORE)
		st.add_vertex(ctr)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_MID)
		st.add_vertex(m0)
		# Outer soft-feathered skirt fading smoothly to pure black rim (16 tris).
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_ENEMY_AURA_RIM)
		st.add_vertex(o0)
	return st.commit()

