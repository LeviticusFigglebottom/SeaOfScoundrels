class_name PowderKeg
extends Carryable
## Interactive carryable, lightable, defusable, shootable, and chain-detonating
## Gunpowder Keg hull bomb.
##
## Features:
## - 100% sculpted flat-faceted crimson-and-iron coopered oak cask `ArrayMesh`
##   (>= 640 triangles, zero `PrimitiveMesh`es, zero extra VRAM via WeakRef-cached
##   shared ship BC7 PBR normal/roughness maps with object-space triplanar mapping).
## - Sizzling 4.5 s host-authoritative fuse (`ignite_fuse` / `extinguish_fuse`)
##   with shortening braided fuse cord, glowing ember tip, unshadowed flickering
##   `OmniLight3D`, and sculpted 16-tri diamond spark `CPUParticles3D`.
## - Devastating multi-target detonation: punches 3 distinct hull breaches + ignites
##   `ShipFire` deck flames + rocks nearby ships, deals quadratic blast damage +
##   knockback to pawns/enemies/wildlife, damages Leviathan tentacles, chains into
##   adjacent `PowderKeg`s, and spawns 100% zero-primitive blast VFX & camera trauma.
## - Automatically sellable unexploded at `MerchantStall` for 220g / 30 Iron Tide
##   Renown via metadata; refuses hand-in while fuse is lit or exploded.

signal fuse_lit(keg: PowderKeg, lighter: Node)
signal fuse_extinguished(keg: PowderKeg)
signal detonated(keg: PowderKeg, blast_pos: Vector3, trigger: Node)

const GROUP := &"powder_kegs"
const FUSE_DURATION := 4.5
const BLAST_RADIUS := 7.2
const MAX_PAWN_DAMAGE := 95.0
const HULL_BREACH_COUNT := 3
const HULL_BREACH_RADIUS := 0.58
const CHAIN_BLAST_RADIUS := 7.8
const LEVIATHAN_DAMAGE := 110.0
const GOLD_VALUE := 220
const RENOWN_VALUE := 30

const KEG_HEIGHT := 0.68
const KEG_RADIUS := 0.26
const KEG_CENTER_Y := 0.34
const FUSE_BASE_Y := 0.652
const BLAST_VFX_DURATION := 1.65

const PBR_NORMAL_PATHS: Array[String] = [
	"res://assets/generated/textures/ship/ship_hull_normal.png",
	"res://assets/generated/textures/ship_oak_normal.png",
	"res://assets/generated/textures/ship_paint_normal.png",
]
const PBR_ROUGH_PATHS: Array[String] = [
	"res://assets/generated/textures/ship/ship_hull_roughness.png",
	"res://assets/generated/textures/ship_oak_rough.png",
	"res://assets/generated/textures/ship_paint_rough.png",
]

# sRGB-calibrated painterly nautical palette.
const COL_RED_HI := Color(0.78, 0.14, 0.12)
const COL_RED_MID := Color(0.58, 0.10, 0.09)
const COL_RED_DARK := Color(0.36, 0.06, 0.06)
const COL_SEAM_OAK := Color(0.16, 0.08, 0.05)
const COL_OAK_HEAD := Color(0.46, 0.30, 0.16)
const COL_OAK_DARK := Color(0.28, 0.17, 0.09)
const COL_BUNG := Color(0.64, 0.46, 0.26)
const COL_IRON_DARK := Color(0.15, 0.16, 0.18)
const COL_IRON_HI := Color(0.30, 0.31, 0.34)
const COL_RIVET := Color(0.40, 0.40, 0.42)
const COL_PLAQUE_BG := Color(0.14, 0.05, 0.05)
const COL_GOLD_TRIM := Color(0.95, 0.73, 0.22)
const COL_SKULL_IVORY := Color(0.95, 0.90, 0.78)
const COL_ROPE_HI := Color(0.74, 0.60, 0.38)
const COL_ROPE_LO := Color(0.48, 0.37, 0.22)
const COL_BRASS_HI := Color(0.88, 0.68, 0.26)
const COL_BRASS_LO := Color(0.54, 0.38, 0.12)
const COL_FUSE_HALO_WARM := Color(1.00, 0.76, 0.34)
const COL_FUSE_HALO_DANGER := Color(1.00, 0.34, 0.22)
const COL_FUSE_HALO_HOT := Color(1.00, 0.88, 0.78)
const FUSE_HALO_VISIBILITY_RANGE := 110.0

## Remaining seconds until detonation once the fuse is lit.
var fuse_remaining: float = FUSE_DURATION
## True once this keg has detonated (strictly idempotent guard).
var exploded: bool = false
## Toggle visual explosion particles, flash light, and sculpted shockwave VFX.
@export var enable_effects: bool = true

var _fuse_lit: bool = false
var _lighter: Node = null
var _sizzle_tick_accum: float = 0.0
var _anim_clock: float = 0.0
var _cleanup_timer: float = 0.0
var _blast_elapsed: float = 0.0

var _visual_root: Node3D = null
var _keg_mi: MeshInstance3D = null
var _fuse_cord_mi: MeshInstance3D = null
var _ember_pivot: Node3D = null
var _ember_mi: MeshInstance3D = null
var _fuse_halo_mi: MeshInstance3D = null
var _fuse_halo_mat: StandardMaterial3D = null
var _fuse_halo_energy: float = 0.0
var _fuse_halo_phase: float = 0.0
var _fuse_light: OmniLight3D = null
var _spark_particles: CPUParticles3D = null

var _blast_vfx_root: Node3D = null
var _blast_fireball_mi: MeshInstance3D = null
var _blast_fireball_mat: StandardMaterial3D = null
var _blast_shockwave_mi: MeshInstance3D = null
var _blast_shockwave_mat: StandardMaterial3D = null
var _blast_light: OmniLight3D = null
var _blast_splinters: CPUParticles3D = null
var _blast_smoke: CPUParticles3D = null

# Ref-counted static sculpted ArrayMesh & shared PBR caches (0 extra VRAM, 0 leaks).
static var _active_kegs: int = 0
static var _pbr_tex_cache: Dictionary = {}  # String path -> WeakRef(Texture2D)
static var _keg_mesh: ArrayMesh = null
static var _fuse_cord_mesh: ArrayMesh = null
static var _ember_mesh: ArrayMesh = null
static var _fuse_halo_mesh: ArrayMesh = null
static var _spark_mesh: ArrayMesh = null
static var _fireball_mesh: ArrayMesh = null
static var _shockwave_mesh: ArrayMesh = null
static var _splinter_mesh: ArrayMesh = null
static var _smoke_puff_mesh: ArrayMesh = null
static var _keg_mat: StandardMaterial3D = null
static var _ember_mat: StandardMaterial3D = null
static var _spark_mat: StandardMaterial3D = null
static var _splinter_mat: StandardMaterial3D = null
static var _smoke_puff_mat: StandardMaterial3D = null


## Spawn a carryable, lightable, shootable `PowderKeg` under `parent` at `world_pos`.
static func spawn_at(parent: Node, world_pos: Vector3) -> PowderKeg:
	var keg := PowderKeg.new()
	keg.name = "PowderKeg"
	keg.position = world_pos
	if parent != null:
		parent.add_child(keg)
		if keg.is_inside_tree():
			keg.global_position = world_pos
	return keg


## Release all statically cached sculpted meshes, PBR materials, and WeakRef textures cleanly.
static func clear_shared_cache() -> void:
	if _keg_mat != null:
		_keg_mat.normal_texture = null
		_keg_mat.roughness_texture = null
		_keg_mat.albedo_texture = null
	_keg_mesh = null
	_fuse_cord_mesh = null
	_ember_mesh = null
	_fuse_halo_mesh = null
	_spark_mesh = null
	_fireball_mesh = null
	_shockwave_mesh = null
	_splinter_mesh = null
	_smoke_puff_mesh = null
	_keg_mat = null
	_ember_mat = null
	_spark_mat = null
	_splinter_mat = null
	_smoke_puff_mat = null
	_pbr_tex_cache.clear()


func _enter_tree() -> void:
	_active_kegs += 1


func _ready() -> void:
	item_name = "Gunpowder Keg"
	mass = 12.0
	buoyancy = 1.65
	float_radius = 0.28
	carry_speed_factor = 0.70
	hold_offset = Vector3(0.0, 0.96, -0.58)

	set_meta(&"treasure_id", &"powder_keg")
	set_meta(&"treasure_name", "Gunpowder Keg")
	set_meta(&"base_gold_value", GOLD_VALUE)
	set_meta(&"gold_value", GOLD_VALUE)
	set_meta(&"renown_value", RENOWN_VALUE)
	set_meta(&"company_id", &"iron_tide")
	set_meta(&"tier", 2)

	add_to_group(GROUP)
	add_to_group(&"damageables")

	_ensure_collision()
	_ensure_visuals()

	if interactable == null:
		var it := Interactable.create("Pick up Gunpowder Keg", 0.58)
		it.name = "Interactable"
		it.position = Vector3(0.0, KEG_CENTER_Y, 0.0)
		add_child(it)

	super._ready()


func _exit_tree() -> void:
	_release_local_visuals()
	_active_kegs = maxi(0, _active_kegs - 1)
	if _active_kegs == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_local_visuals()


func _release_local_visuals() -> void:
	if _keg_mi != null and is_instance_valid(_keg_mi):
		_keg_mi.material_override = null
		_keg_mi.mesh = null
	if _fuse_cord_mi != null and is_instance_valid(_fuse_cord_mi):
		_fuse_cord_mi.material_override = null
		_fuse_cord_mi.mesh = null
	if _ember_mi != null and is_instance_valid(_ember_mi):
		_ember_mi.material_override = null
		_ember_mi.mesh = null
	if _fuse_halo_mi != null and is_instance_valid(_fuse_halo_mi):
		_fuse_halo_mi.material_override = null
		_fuse_halo_mi.mesh = null
	if _spark_particles != null and is_instance_valid(_spark_particles):
		_spark_particles.emitting = false
		_spark_particles.visible = false
		_spark_particles.material_override = null
	if _fuse_light != null and is_instance_valid(_fuse_light):
		_fuse_light.light_energy = 0.0
		_fuse_light.visible = false
	_release_blast_vfx()
	_keg_mi = null
	_fuse_cord_mi = null
	_ember_mi = null
	_fuse_halo_mi = null
	_fuse_halo_mat = null
	_fuse_halo_energy = 0.0
	_ember_pivot = null
	_fuse_light = null
	_spark_particles = null
	_visual_root = null
	_lighter = null


func _release_blast_vfx() -> void:
	if _blast_fireball_mi != null and is_instance_valid(_blast_fireball_mi):
		_blast_fireball_mi.material_override = null
		_blast_fireball_mi.mesh = null
	if _blast_shockwave_mi != null and is_instance_valid(_blast_shockwave_mi):
		_blast_shockwave_mi.material_override = null
		_blast_shockwave_mi.mesh = null
	if _blast_splinters != null and is_instance_valid(_blast_splinters):
		_blast_splinters.emitting = false
		_blast_splinters.visible = false
		_blast_splinters.material_override = null
	if _blast_smoke != null and is_instance_valid(_blast_smoke):
		_blast_smoke.emitting = false
		_blast_smoke.visible = false
		_blast_smoke.material_override = null
	if _blast_light != null and is_instance_valid(_blast_light):
		_blast_light.light_energy = 0.0
		_blast_light.visible = false
	_blast_fireball_mi = null
	_blast_fireball_mat = null
	_blast_shockwave_mi = null
	_blast_shockwave_mat = null
	_blast_splinters = null
	_blast_smoke = null
	_blast_light = null
	_blast_vfx_root = null


# ==============================================================================
# Carryable Overrides & Fuse State API
# ==============================================================================

## True while the sizzling countdown fuse is actively burning.
func is_fuse_lit() -> bool:
	return _fuse_lit


## Normalized fuse burn progress (0.0 unlit/full -> 1.0 imminent detonation).
func get_fuse_progress() -> float:
	if not _fuse_lit:
		return 0.0
	return clampf(1.0 - fuse_remaining / FUSE_DURATION, 0.0, 1.0)


## Return total sculpted triangle count across this keg's body + fuse meshes.
func get_triangle_count() -> int:
	_ensure_shared_assets()
	var total := 0
	if _keg_mesh != null:
		total += _count_mesh_tris(_keg_mesh)
	if _fuse_cord_mesh != null:
		total += _count_mesh_tris(_fuse_cord_mesh)
	if _ember_mesh != null:
		total += _count_mesh_tris(_ember_mesh)
	if _fuse_halo_mesh != null:
		total += _count_mesh_tris(_fuse_halo_mesh)
	return total


## Return the shared PBR material used on the sculpted keg body.
func get_keg_material() -> StandardMaterial3D:
	_ensure_shared_assets()
	return _keg_mat


## Return the mounted additive FuseGlowHalo MeshInstance3D on the fuse tip.
func get_fuse_halo_node() -> MeshInstance3D:
	return _fuse_halo_mi


## Return the current urgent countdown FuseGlowHalo energy (0.0 when unlit/snuffed/detonated).
func get_fuse_halo_energy() -> float:
	return _fuse_halo_energy


func attach_to(pawn: Node3D) -> void:
	if exploded:
		return
	super.attach_to(pawn)


func _restore_body() -> void:
	if exploded:
		return
	super._restore_body()


## Refuse selling or storing a live lit (or already exploded) gunpowder keg!
func hand_to(container: Node) -> bool:
	if is_fuse_lit() or exploded:
		return false
	return super.hand_to(container)


## Host only. Light the 4.5 s sizzling countdown fuse. Returns true if newly lit.
func ignite_fuse(lighter: Node = null) -> bool:
	if not Net.is_host() or exploded or _fuse_lit:
		return false
	_fuse_lit = true
	fuse_remaining = FUSE_DURATION
	_lighter = lighter
	_sizzle_tick_accum = 0.0
	_fuse_halo_phase = PI * 0.5
	_set_fuse_fx_active(true)
	_update_fuse_visuals(0.0)
	if Audio != null:
		var sfx_id := &"fuse_sizzle" if Audio.has_sound(&"fuse_sizzle") else &"lantern_click"
		Audio.play_sfx(sfx_id, global_position + Vector3(0.0, 0.72, 0.0), -2.0)
	fuse_lit.emit(self, lighter)
	return true


## Host only. Snuff an active burning fuse cleanly before it detonates.
func extinguish_fuse() -> bool:
	if not Net.is_host() or exploded or not _fuse_lit:
		return false
	_fuse_lit = false
	fuse_remaining = FUSE_DURATION
	_lighter = null
	_sizzle_tick_accum = 0.0
	_set_fuse_fx_active(false)
	_update_fuse_visuals(0.0)
	if Audio != null:
		Audio.play_sfx(&"splash_small", global_position + Vector3(0.0, 0.72, 0.0), -6.0)
	fuse_extinguished.emit(self)
	return true


## Any damage immediately detonates the gunpowder keg!
func apply_damage(_amount: float, source: Node = null) -> void:
	if not Net.is_host() or exploded:
		return
	detonate(source)


## Any melee strike immediately detonates the gunpowder keg!
func receive_melee_hit(attacker_cc: CombatComponent, _raw_damage: float,
		_is_heavy: bool = false, _cleaves_shield: bool = false) -> StringName:
	if not Net.is_host() or exploded:
		return &"dodged"
	var src: Node = attacker_cc
	if attacker_cc != null and attacker_cc.pawn != null:
		src = attacker_cc.pawn
	detonate(src)
	return &"hit"


# ==============================================================================
# Simulation & Visual Updates
# ==============================================================================

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if exploded:
		if _cleanup_timer > 0.0:
			_cleanup_timer -= delta
			if _cleanup_timer <= 0.0:
				queue_free()
		return

	if _fuse_lit and Net.is_host():
		fuse_remaining = maxf(0.0, fuse_remaining - delta)
		_sizzle_tick_accum += delta
		var tick_cadence := 0.28 if fuse_remaining < 1.5 else 0.55
		if _sizzle_tick_accum >= tick_cadence:
			_sizzle_tick_accum = 0.0
			if Audio != null:
				var sfx_id := &"fuse_sizzle" if Audio.has_sound(&"fuse_sizzle") else &"lantern_click"
				Audio.play_sfx(sfx_id, global_position + Vector3(0.0, 0.72, 0.0), -9.0)
		if fuse_remaining <= 0.0:
			detonate(_lighter)


func _process(delta: float) -> void:
	if exploded:
		if _blast_vfx_root != null and is_instance_valid(_blast_vfx_root):
			_tick_blast_vfx(delta)
		return
	if _fuse_lit:
		_update_fuse_visuals(delta)


func _set_fuse_fx_active(active: bool) -> void:
	if _ember_mi != null and is_instance_valid(_ember_mi):
		_ember_mi.visible = active
	if _fuse_halo_mi != null and is_instance_valid(_fuse_halo_mi):
		_fuse_halo_mi.visible = active
	if not active:
		_fuse_halo_energy = 0.0
		if _fuse_halo_mat != null:
			_fuse_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	if _fuse_light != null and is_instance_valid(_fuse_light):
		_fuse_light.visible = active
		if not active:
			_fuse_light.light_energy = 0.0
	if _spark_particles != null and is_instance_valid(_spark_particles):
		_spark_particles.emitting = active


func _update_fuse_visuals(delta: float) -> void:
	var dt := maxf(0.0, delta)
	_anim_clock += dt
	var frac := clampf(fuse_remaining / FUSE_DURATION, 0.06, 1.0) if _fuse_lit else 1.0
	var tip_rel := _fuse_curve_pos(1.0) - Vector3(0.0, FUSE_BASE_Y, 0.0)
	if _fuse_cord_mi != null and is_instance_valid(_fuse_cord_mi):
		_fuse_cord_mi.scale = Vector3.ONE * frac
	if _ember_pivot != null and is_instance_valid(_ember_pivot):
		_ember_pivot.position = Vector3(0.0, FUSE_BASE_Y, 0.0) + tip_rel * frac
		if _fuse_lit:
			var burn_t := clampf(1.0 - fuse_remaining / FUSE_DURATION, 0.0, 1.0)
			var urgent_t := clampf(1.0 - fuse_remaining / 1.2, 0.0, 1.0)
			var urgency := lerpf(16.0, 34.0, 1.0 - frac)
			var flick := 0.80 + 0.20 * sin(_anim_clock * urgency) * cos(_anim_clock * (urgency * 0.63))
			if _ember_mi != null and is_instance_valid(_ember_mi):
				_ember_mi.scale = Vector3.ONE * (0.85 + 0.30 * flick)
				_ember_mi.rotation.y += dt * 11.0
			if _fuse_light != null and is_instance_valid(_fuse_light):
				_fuse_light.light_energy = lerpf(1.75, 2.85, 1.0 - frac) * flick

			# Q16A urgent frantic FuseGlowHalo: 7 Hz -> 22 Hz, 0.42 m -> 0.92 m,
			# intensifying warm amber-orange (~0.85) -> scorching crimson-white (~1.85) in final 1.2 s!
			var pulse_hz := lerpf(7.0, 22.0, pow(burn_t, 1.35))
			_fuse_halo_phase = fposmod(_fuse_halo_phase + dt * TAU * pulse_hz, TAU * 64.0)
			var flick_w := clampf(0.50 + 0.42 * sin(_fuse_halo_phase) + 0.12 * sin(_fuse_halo_phase * 2.13 + 0.6), 0.0, 1.0)
			var halo_scale := lerpf(0.42, 0.82, burn_t) + lerpf(0.04, 0.14, maxf(burn_t, urgent_t)) * flick_w
			var halo_energy := lerpf(0.80, 1.24, burn_t) + 0.50 * urgent_t \
				+ lerpf(0.09, 0.22, maxf(burn_t, urgent_t)) * (flick_w - 0.35)
			_fuse_halo_energy = maxf(0.15, halo_energy)
			if _fuse_halo_mi != null and is_instance_valid(_fuse_halo_mi):
				_fuse_halo_mi.visible = true
				_fuse_halo_mi.scale = Vector3(halo_scale, halo_scale, halo_scale)
			if _fuse_halo_mat != null:
				var danger_tint := COL_FUSE_HALO_DANGER.lerp(COL_FUSE_HALO_HOT, flick_w * 0.85)
				var halo_tint := COL_FUSE_HALO_WARM.lerp(danger_tint, urgent_t)
				_fuse_halo_mat.albedo_color = Color(
					halo_tint.r * _fuse_halo_energy,
					halo_tint.g * _fuse_halo_energy,
					halo_tint.b * _fuse_halo_energy,
					1.0
				)
		else:
			_fuse_halo_energy = 0.0
			if _fuse_halo_mi != null and is_instance_valid(_fuse_halo_mi):
				_fuse_halo_mi.visible = false
			if _fuse_halo_mat != null:
				_fuse_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)


# ==============================================================================
# Host-Authoritative Multi-Target Detonation
# ==============================================================================

## Host only. Strictly idempotent catastrophic powder keg explosion.
## Returns summary dictionary: {pos, ships_breached, pawns_hit, kegs_chained, leviathan_hit}.
func detonate(trigger: Node = null) -> Dictionary:
	if not Net.is_host() or exploded:
		return {}
	exploded = true
	_fuse_lit = false
	fuse_remaining = 0.0

	var blast_pos := global_position + Vector3(0.0, KEG_CENTER_Y, 0.0)
	var prev_holder := holder
	holder = null
	if prev_holder != null and is_instance_valid(prev_holder) and prev_holder.has_method(&"release_carried"):
		prev_holder.call(&"release_carried", self)

	# Immediately neutralize body, visuals, and interaction before chaining/damage.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	if interactable != null and is_instance_valid(interactable):
		interactable.enabled = false
	_set_fuse_fx_active(false)
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.visible = false

	var ships_breached := _apply_ship_hull_blast(blast_pos)
	var pawns_hit := _apply_pawn_and_wildlife_blast(blast_pos, trigger, prev_holder)
	var leviathan_hit := _apply_leviathan_blast(blast_pos)
	var kegs_chained := _apply_chain_detonation(blast_pos, trigger)

	_apply_blast_feedback(blast_pos)

	var summary := {
		"pos": blast_pos,
		"ships_breached": ships_breached,
		"pawns_hit": pawns_hit,
		"kegs_chained": kegs_chained,
		"leviathan_hit": leviathan_hit,
	}
	detonated.emit(self, blast_pos, trigger)

	if enable_effects and DisplayServer.get_name() != "headless" and is_inside_tree():
		_spawn_blast_vfx(blast_pos)
		_cleanup_timer = BLAST_VFX_DURATION
	else:
		queue_free()

	return summary


func _apply_ship_hull_blast(blast_pos: Vector3) -> int:
	if not is_inside_tree():
		return 0
	var tree := get_tree()
	if tree == null:
		return 0
	var breached_ships := 0
	for snode in tree.get_nodes_in_group(&"ship"):
		if not (snode is Node3D) or not is_instance_valid(snode):
			continue
		var ship_n := snode as Node3D
		var hs_v: Variant = ship_n.get(&"hull_scale")
		var hs := float(hs_v) if (hs_v != null and float(hs_v) > 0.01) else 1.24
		if ship_n.global_position.distance_to(blast_pos) > BLAST_RADIUS + 12.0 * hs:
			continue
		var is_brig := ship_n.has_method(&"is_brigantine") and bool(ship_n.call(&"is_brigantine"))
		var half_beam := (2.6 if is_brig else 2.15) * hs
		var half_len := (8.5 if is_brig else 6.4) * hs
		var local_p := ship_n.global_transform.affine_inverse() * blast_pos
		var clamped := Vector3(
			clampf(local_p.x, -half_beam, half_beam),
			clampf(local_p.y, -1.5 * hs, 4.0 * hs),
			clampf(local_p.z, -half_len, half_len)
		)
		var hull_dist := local_p.distance_to(clamped)
		if hull_dist > BLAST_RADIUS:
			continue

		breached_ships += 1
		if ship_n.has_method(&"apply_hull_damage"):
			var sb := ship_n.global_basis
			var offsets: Array[Vector3] = [
				Vector3.ZERO,
				sb * Vector3(1.5 * hs, -0.35, 1.8 * hs),
				sb * Vector3(-1.5 * hs, -0.35, -1.8 * hs),
			]
			for bi in HULL_BREACH_COUNT:
				var off := offsets[bi % offsets.size()]
				ship_n.call(&"apply_hull_damage", blast_pos + off, HULL_BREACH_RADIUS)
		if ship_n.has_method(&"ignite_deck_fire"):
			ship_n.call(&"ignite_deck_fire", blast_pos, true)
		if ship_n is RigidBody3D:
			var rb := ship_n as RigidBody3D
			var away := rb.global_position - blast_pos
			if away.length_squared() < 0.04:
				away = Vector3(0.35, -0.5, 0.25)
			var falloff := clampf(1.0 - hull_dist / BLAST_RADIUS, 0.28, 1.0)
			var imp_dir := (away.normalized() + Vector3(0.0, -0.25, 0.0)).normalized()
			var rel_pos := blast_pos - rb.global_position
			rel_pos.y = clampf(rel_pos.y, -1.8, 2.2)
			rb.apply_impulse(imp_dir * 26000.0 * falloff, rel_pos)
	return breached_ships


func _apply_pawn_and_wildlife_blast(blast_pos: Vector3, trigger: Node, prev_holder: Node3D) -> int:
	if not is_inside_tree():
		return 0
	var candidates := _collect_blast_targets(prev_holder)
	var hit_count := 0
	var dmg_source: Node = trigger if trigger != null else self

	for cand: Node3D in candidates:
		if cand == null or not is_instance_valid(cand) or cand == self:
			continue
		if cand is PowderKeg:
			continue
		if not cand.has_method(&"apply_damage"):
			continue
		var is_dead: Variant = cand.get(&"dead")
		if is_dead is bool and bool(is_dead):
			continue
		var d_base := cand.global_position.distance_to(blast_pos)
		var d_mid := (cand.global_position + Vector3(0.0, 0.85, 0.0)).distance_to(blast_pos)
		var d := minf(d_base, d_mid)
		if d > BLAST_RADIUS:
			continue
		var u := clampf(1.0 - d / BLAST_RADIUS, 0.0, 1.0)
		var dmg := maxf(1.0, MAX_PAWN_DAMAGE * u * u)
		_call_apply_damage(cand, dmg, dmg_source)
		if cand is CharacterBody3D:
			var push := cand.global_position - blast_pos
			push.y = 0.0
			var dir := push.normalized() if push.length_squared() > 0.001 else Vector3.FORWARD
			var kb := lerpf(3.5, 12.5, u)
			(cand as CharacterBody3D).velocity += dir * kb + Vector3.UP * lerpf(2.0, 5.5, u)
		hit_count += 1
	return hit_count


func _collect_blast_targets(prev_holder: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var seen: Dictionary = {}
	var add_cand := func(n: Node) -> void:
		if n is Node3D and is_instance_valid(n):
			var iid := n.get_instance_id()
			if not seen.has(iid):
				seen[iid] = true
				out.append(n as Node3D)

	if prev_holder != null:
		add_cand.call(prev_holder)

	var tree := get_tree()
	if tree != null:
		for grp: StringName in [&"pawn", &"pawns", &"sharks", &"wildlife", &"beasts", &"enemies"]:
			for n in tree.get_nodes_in_group(grp):
				add_cand.call(n)
		for node in tree.get_nodes_in_group(&"combatants"):
			if node is CombatComponent:
				var p := (node as CombatComponent).pawn
				if p != null:
					add_cand.call(p)
			else:
				add_cand.call(node)
		for cb in tree.get_nodes_in_group(&"crew_brains"):
			var p2 := cb.get_parent()
			if p2 != null:
				add_cand.call(p2)

	var parent_node := get_parent()
	if parent_node != null:
		for ch in parent_node.get_children():
			if ch is Pawn:
				add_cand.call(ch)
	return out


func _apply_leviathan_blast(blast_pos: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var hit_any := false
	var struck_keys: Dictionary = {}
	var max_r := BLAST_RADIUS + 2.5

	for ev in tree.get_nodes_in_group(&"world_events"):
		if not is_instance_valid(ev) or not (ev is Node) or not ev.has_method(&"damage_tentacle"):
			continue
		var hitboxes := (ev as Node).find_children("TentacleHitbox_*", "StaticBody3D", true, false)
		for hb_n in hitboxes:
			if not (hb_n is Node3D) or not hb_n.has_meta("leviathan"):
				continue
			var hb := hb_n as Node3D
			var base_p := hb.global_position
			var top_p := base_p + Vector3(0.0, 10.4, 0.0)
			var closest := Geometry3D.get_closest_point_to_segment(blast_pos, base_p, top_p)
			if closest.distance_to(blast_pos) > max_r:
				continue
			var t_idx := int(hb.get_meta("tentacle_index", -1))
			if t_idx < 0:
				continue
			var key := "%d:%d" % [ev.get_instance_id(), t_idx]
			if struck_keys.has(key):
				continue
			struck_keys[key] = true
			if bool(ev.call(&"damage_tentacle", t_idx, LEVIATHAN_DAMAGE)):
				hit_any = true
	return hit_any


func _apply_chain_detonation(blast_pos: Vector3, trigger: Node) -> int:
	if not is_inside_tree():
		return 0
	var tree := get_tree()
	if tree == null:
		return 0
	var chained := 0
	var r_sq := CHAIN_BLAST_RADIUS * CHAIN_BLAST_RADIUS
	var candidates := tree.get_nodes_in_group(GROUP)
	for node in candidates:
		if node == self or not is_instance_valid(node) or not (node is PowderKeg):
			continue
		var other := node as PowderKeg
		if other.exploded:
			continue
		var other_pos := other.global_position + Vector3(0.0, KEG_CENTER_Y, 0.0)
		if other_pos.distance_squared_to(blast_pos) <= r_sq:
			var sub := other.detonate(trigger)
			if not sub.is_empty():
				chained += 1 + int(sub.get("kegs_chained", 0))
	return chained


func _apply_blast_feedback(blast_pos: Vector3) -> void:
	if Audio != null:
		Audio.play_sfx(&"cannon_fire", blast_pos, 4.0)

	# Stamp boiling ocean foam crater when detonating near the water surface.
	if Ocean.current != null:
		var sea_y := Sea.height(blast_pos.x, blast_pos.z)
		if blast_pos.y - sea_y < 5.0:
			var sea_pt := Vector3(blast_pos.x, sea_y, blast_pos.z)
			Ocean.current.add_foam(sea_pt, 5.2, 1.0)

	# Heavy distance-attenuated camera shake trauma on nearby PlayerControllers.
	var tree := get_tree()
	if tree != null and tree.root != null:
		var pcs: Array[PlayerController] = []
		_collect_player_controllers(tree.root, pcs)
		for pc: PlayerController in pcs:
			if not is_instance_valid(pc) or not pc.is_inside_tree():
				continue
			var ref_pos := pc.pawn.global_position if (pc.pawn != null and is_instance_valid(pc.pawn)) else pc.global_position
			var d := ref_pos.distance_to(blast_pos)
			if d <= 28.0:
				pc.add_camera_trauma(clampf((1.0 - d / 28.0) * 0.92, 0.22, 0.92))


static func _collect_player_controllers(node: Node, out: Array[PlayerController]) -> void:
	if node is PlayerController:
		out.append(node as PlayerController)
	for ch in node.get_children():
		_collect_player_controllers(ch, out)


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


# ==============================================================================
# Cinematic 100% Zero-Primitive Sculpted Blast VFX
# ==============================================================================

func _spawn_blast_vfx(blast_pos: Vector3) -> void:
	_ensure_shared_assets()
	_blast_elapsed = 0.0

	var root := Node3D.new()
	root.name = "PowderKegBlastVFX"
	root.top_level = true
	add_child(root)
	root.global_transform = Transform3D(Basis.IDENTITY, blast_pos)
	_blast_vfx_root = root

	# 1. Incandescent sculpted radial fireball core.
	_blast_fireball_mat = StandardMaterial3D.new()
	_blast_fireball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blast_fireball_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blast_fireball_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blast_fireball_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_blast_fireball_mat.vertex_color_use_as_albedo = true
	_blast_fireball_mat.vertex_color_is_srgb = true
	_blast_fireball_mat.albedo_color = Color(1.0, 0.96, 0.84, 0.95)

	var fb := MeshInstance3D.new()
	fb.name = "FireballCore"
	fb.mesh = _fireball_mesh
	fb.material_override = _blast_fireball_mat
	fb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fb.scale = Vector3.ONE * 0.45
	root.add_child(fb)
	_blast_fireball_mi = fb

	# 2. Expanding beveled shockwave pressure ring.
	_blast_shockwave_mat = StandardMaterial3D.new()
	_blast_shockwave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blast_shockwave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blast_shockwave_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blast_shockwave_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_blast_shockwave_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_blast_shockwave_mat.vertex_color_use_as_albedo = true
	_blast_shockwave_mat.vertex_color_is_srgb = true
	_blast_shockwave_mat.albedo_color = Color(1.0, 0.78, 0.36, 0.85)

	var ring := MeshInstance3D.new()
	ring.name = "ShockwaveRing"
	ring.mesh = _shockwave_mesh
	ring.material_override = _blast_shockwave_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.45, 1.0, 0.45)
	root.add_child(ring)
	_blast_shockwave_mi = ring

	# 3. Flying charred wooden stave splinters (sculpted ArrayMesh CPUParticles3D).
	var splinters := CPUParticles3D.new()
	splinters.name = "StaveSplinters"
	splinters.one_shot = true
	splinters.explosiveness = 0.95
	splinters.amount = 26
	splinters.lifetime = 0.95
	splinters.direction = Vector3.UP
	splinters.spread = 115.0
	splinters.initial_velocity_min = 6.5
	splinters.initial_velocity_max = 15.0
	splinters.angular_velocity_min = -14.0
	splinters.angular_velocity_max = 14.0
	splinters.gravity = Vector3(0.0, -16.5, 0.0)
	splinters.scale_amount_min = 0.65
	splinters.scale_amount_max = 1.35
	splinters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splinters.mesh = _splinter_mesh
	splinters.material_override = _splinter_mat
	root.add_child(splinters)
	splinters.emitting = true
	_blast_splinters = splinters

	# 4. Billowing sculpted faceted gunpowder smoke puffs (CPUParticles3D).
	var smoke := CPUParticles3D.new()
	smoke.name = "SmokePuffs"
	smoke.one_shot = true
	smoke.explosiveness = 0.88
	smoke.amount = 24
	smoke.lifetime = 1.45
	smoke.direction = Vector3.UP
	smoke.spread = 75.0
	smoke.initial_velocity_min = 2.8
	smoke.initial_velocity_max = 7.4
	smoke.damping_min = 2.5
	smoke.damping_max = 4.5
	smoke.gravity = Vector3(0.0, 2.4, 0.0)
	smoke.scale_amount_min = 0.65
	smoke.scale_amount_max = 1.75
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.mesh = _smoke_puff_mesh
	smoke.material_override = _smoke_puff_mat
	root.add_child(smoke)
	smoke.emitting = true
	_blast_smoke = smoke

	# 5. Brief blazing unshadowed detonation flash OmniLight3D.
	var flash := OmniLight3D.new()
	flash.name = "BlastFlashLight"
	flash.light_color = Color(1.0, 0.62, 0.18)
	flash.light_energy = 9.5
	flash.omni_range = 16.0
	flash.omni_attenuation = 1.3
	flash.shadow_enabled = false
	root.add_child(flash)
	_blast_light = flash


func _tick_blast_vfx(delta: float) -> void:
	_blast_elapsed += maxf(0.0, delta)
	var fb_t := clampf(_blast_elapsed / 0.42, 0.0, 1.0)
	if _blast_fireball_mi != null and is_instance_valid(_blast_fireball_mi):
		var fb_s := lerpf(0.45, 3.85, 1.0 - pow(1.0 - fb_t, 2.2))
		_blast_fireball_mi.scale = Vector3.ONE * fb_s
		_blast_fireball_mi.rotation.y += delta * 4.5
		_blast_fireball_mi.visible = fb_t < 1.0
		if _blast_fireball_mat != null:
			_blast_fireball_mat.albedo_color = Color(1.0, lerpf(0.95, 0.35, fb_t), lerpf(0.80, 0.08, fb_t), (1.0 - fb_t) * 0.95)

	var sw_t := clampf(_blast_elapsed / 0.52, 0.0, 1.0)
	if _blast_shockwave_mi != null and is_instance_valid(_blast_shockwave_mi):
		var sw_r := lerpf(0.45, BLAST_RADIUS * 1.12, 1.0 - pow(1.0 - sw_t, 2.0))
		_blast_shockwave_mi.scale = Vector3(sw_r, lerpf(1.1, 0.25, sw_t), sw_r)
		_blast_shockwave_mi.visible = sw_t < 1.0
		if _blast_shockwave_mat != null:
			_blast_shockwave_mat.albedo_color = Color(1.0, lerpf(0.82, 0.55, sw_t), lerpf(0.38, 0.25, sw_t), (1.0 - sw_t) * 0.82)

	var lt := clampf(_blast_elapsed / 0.36, 0.0, 1.0)
	if _blast_light != null and is_instance_valid(_blast_light):
		_blast_light.light_energy = 9.5 * (1.0 - lt) * (1.0 - lt)
		_blast_light.visible = lt < 1.0


# ==============================================================================
# Collision & Visual Hierarchy Construction
# ==============================================================================

func _ensure_collision() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			return
	var col := CollisionShape3D.new()
	col.name = "CollisionShape"
	var cyl := CylinderShape3D.new()
	cyl.height = KEG_HEIGHT
	cyl.radius = KEG_RADIUS
	col.shape = cyl
	col.position = Vector3(0.0, KEG_CENTER_Y, 0.0)
	add_child(col)


func _ensure_visuals() -> void:
	if _visual_root != null:
		return
	_ensure_shared_assets()

	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	add_child(_visual_root)

	_keg_mi = MeshInstance3D.new()
	_keg_mi.name = "KegBody"
	_keg_mi.mesh = _keg_mesh
	_keg_mi.material_override = _keg_mat
	_visual_root.add_child(_keg_mi)

	_fuse_cord_mi = MeshInstance3D.new()
	_fuse_cord_mi.name = "FuseCord"
	_fuse_cord_mi.mesh = _fuse_cord_mesh
	_fuse_cord_mi.material_override = _keg_mat
	_fuse_cord_mi.position = Vector3(0.0, FUSE_BASE_Y, 0.0)
	_visual_root.add_child(_fuse_cord_mi)

	_ember_pivot = Node3D.new()
	_ember_pivot.name = "FuseEmberPivot"
	_ember_pivot.position = _fuse_curve_pos(1.0)
	_visual_root.add_child(_ember_pivot)

	_ember_mi = MeshInstance3D.new()
	_ember_mi.name = "FuseEmber"
	_ember_mi.mesh = _ember_mesh
	_ember_mi.material_override = _ember_mat
	_ember_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ember_mi.visible = false
	_ember_pivot.add_child(_ember_mi)

	_fuse_halo_mat = StandardMaterial3D.new()
	_fuse_halo_mat.vertex_color_use_as_albedo = true
	_fuse_halo_mat.vertex_color_is_srgb = true
	_fuse_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fuse_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fuse_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_fuse_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fuse_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_fuse_halo_mat.billboard_keep_scale = true
	_fuse_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)

	_fuse_halo_mi = MeshInstance3D.new()
	_fuse_halo_mi.name = "FuseGlowHalo"
	_fuse_halo_mi.position = Vector3(0.0, 0.014, 0.0)
	_fuse_halo_mi.scale = Vector3.ONE * 0.42
	_fuse_halo_mi.mesh = _fuse_halo_mesh
	_fuse_halo_mi.material_override = _fuse_halo_mat
	_fuse_halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fuse_halo_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_fuse_halo_mi.visibility_range_end = FUSE_HALO_VISIBILITY_RANGE
	_fuse_halo_mi.extra_cull_margin = 1.0
	_fuse_halo_mi.visible = false
	_ember_pivot.add_child(_fuse_halo_mi)

	_fuse_light = OmniLight3D.new()
	_fuse_light.name = "FuseLight"
	_fuse_light.light_color = Color(1.0, 0.56, 0.16)
	_fuse_light.light_energy = 0.0
	_fuse_light.omni_range = 3.8
	_fuse_light.omni_attenuation = 1.45
	_fuse_light.shadow_enabled = false
	_fuse_light.visible = false
	_ember_pivot.add_child(_fuse_light)

	_spark_particles = CPUParticles3D.new()
	_spark_particles.name = "FuseSparks"
	_spark_particles.emitting = false
	_spark_particles.amount = 18
	_spark_particles.lifetime = 0.34
	_spark_particles.direction = Vector3(0.0, 1.0, 0.0)
	_spark_particles.spread = 65.0
	_spark_particles.initial_velocity_min = 1.4
	_spark_particles.initial_velocity_max = 3.2
	_spark_particles.gravity = Vector3(0.0, -7.5, 0.0)
	_spark_particles.scale_amount_min = 0.75
	_spark_particles.scale_amount_max = 1.35
	_spark_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark_particles.mesh = _spark_mesh
	_spark_particles.material_override = _spark_mat
	_ember_pivot.add_child(_spark_particles)


# ==============================================================================
# WeakRef Shared BC7 Ship PBR Texture & Material Cache (0 Extra VRAM)
# ==============================================================================

static func _load_pbr_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _pbr_tex_cache.has(path):
		var wr: Variant = _pbr_tex_cache[path]
		if wr is WeakRef:
			var obj: Variant = (wr as WeakRef).get_ref()
			if obj is Texture2D:
				return obj as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var loaded: Variant = ResourceLoader.load(path)
	if loaded is Texture2D:
		var tex := loaded as Texture2D
		_pbr_tex_cache[path] = weakref(tex)
		return tex
	return null


static func _load_first_pbr_tex(paths: Array[String]) -> Texture2D:
	for p: String in paths:
		var tex := _load_pbr_tex(p)
		if tex != null:
			return tex
	return null


static func _ensure_shared_assets() -> void:
	if _keg_mat == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.WHITE
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.72
		mat.metallic = 0.14
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = false
		mat.uv1_scale = Vector3(2.4, 2.4, 2.4)
		var ntex := _load_first_pbr_tex(PBR_NORMAL_PATHS)
		var rtex := _load_first_pbr_tex(PBR_ROUGH_PATHS)
		if ntex != null:
			mat.normal_enabled = true
			mat.normal_scale = 0.68
			mat.normal_texture = ntex
		if rtex != null:
			mat.roughness_texture = rtex
		_keg_mat = mat

	if _ember_mat == null:
		var em := StandardMaterial3D.new()
		em.albedo_color = Color.WHITE
		em.vertex_color_use_as_albedo = true
		em.vertex_color_is_srgb = true
		em.roughness = 0.25
		em.metallic = 0.0
		em.emission_enabled = true
		em.emission = Color(1.0, 0.52, 0.10)
		em.emission_energy_multiplier = 4.2
		_ember_mat = em

	if _spark_mat == null:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = Color.WHITE
		sm.vertex_color_use_as_albedo = true
		sm.vertex_color_is_srgb = true
		_spark_mat = sm

	if _splinter_mat == null:
		var spm := StandardMaterial3D.new()
		spm.albedo_color = Color.WHITE
		spm.vertex_color_use_as_albedo = true
		spm.vertex_color_is_srgb = true
		spm.roughness = 0.84
		spm.metallic = 0.16
		spm.emission_enabled = true
		spm.emission = Color(1.0, 0.34, 0.05)
		spm.emission_energy_multiplier = 0.35
		_splinter_mat = spm

	if _smoke_puff_mat == null:
		var skm := StandardMaterial3D.new()
		skm.albedo_color = Color(0.24, 0.23, 0.25, 0.78)
		skm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		skm.vertex_color_use_as_albedo = true
		skm.vertex_color_is_srgb = true
		skm.roughness = 0.96
		skm.metallic = 0.0
		_smoke_puff_mat = skm

	if _keg_mesh == null:
		_keg_mesh = _build_keg_mesh()
	if _fuse_cord_mesh == null:
		_fuse_cord_mesh = _build_fuse_cord_mesh()
	if _ember_mesh == null:
		_ember_mesh = _build_ember_mesh()
	if _fuse_halo_mesh == null:
		_fuse_halo_mesh = _build_fuse_halo_mesh()
	if _spark_mesh == null:
		_spark_mesh = _build_spark_mesh()
	if _fireball_mesh == null:
		_fireball_mesh = _build_fireball_mesh()
	if _shockwave_mesh == null:
		_shockwave_mesh = _build_shockwave_mesh()
	if _splinter_mesh == null:
		_splinter_mesh = _build_splinter_mesh()
	if _smoke_puff_mesh == null:
		_smoke_puff_mesh = _build_smoke_puff_mesh()


# ==============================================================================
# 100% Sculpted Zero-Primitive Crimson-and-Iron PowderKeg Geometry Builders
# ==============================================================================

static func _stave_radius(t: float) -> float:
	return 0.200 + 0.058 * sin(clampf(t, 0.0, 1.0) * PI)


static func _fuse_curve_pos(t: float) -> Vector3:
	var u := clampf(t, 0.0, 1.0)
	var x := 0.045 * sin(u * PI * 0.85)
	var y := FUSE_BASE_Y + 0.212 * sin(u * PI * 0.58)
	var z := -0.115 * (u * u)
	return Vector3(x, y, z)


static func _build_keg_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. 16 beveled coopered crimson-painted oak staves with deep recessed seams (576 tris).
	_add_coopered_staves(st, 16)

	# 2. Recessed top and bottom oak heads with beveled chime rims & plank ridges (192+ tris).
	_add_cask_heads(st, 16)

	# 3. 4 forged dark-iron barrel hoops + 24 raised square rivets (624 tris).
	var hoop_ts: Array[float] = [0.125, 0.315, 0.685, 0.875]
	for hi in hoop_ts.size():
		_add_iron_hoop(st, hoop_ts[hi], 0.036, 0.014, 16, float(hi) * 0.35)

	# 4. Bold ivory/gold skull-diamond warning emblems on front (-Z) & back (+Z) faces (132+ tris).
	_add_skull_emblem(st, -1.0)
	_add_skull_emblem(st, 1.0)

	# 5. Oak bung stopper on upper starboard stave (+X, y = 0.40) (32 tris).
	_add_bung_stopper(st)

	# 6. Twin braided hemp carrying rope handles + iron staple loops on port/stbd (208 tris).
	_add_shoulder_rope_loop(st, -1.0)
	_add_shoulder_rope_loop(st, 1.0)

	# 7. Turned brass top fuse grommet collar at center of recessed top head (32 tris).
	_add_fuse_grommet(st)

	st.generate_normals()
	return st.commit()


static func _add_coopered_staves(st: SurfaceTool, stave_count: int) -> void:
	var t_stations: Array[float] = [0.0, 0.10, 0.26, 0.50, 0.74, 0.90, 1.0]
	var step_ang := TAU / float(stave_count)
	var ref_center := Vector3(0.0, KEG_CENTER_Y, 0.0)

	for si in stave_count:
		var a_mid := (float(si) + 0.5) * step_ang
		var a_l0 := float(si) * step_ang
		var a_l1 := a_l0 + step_ang * 0.10
		var a_r0 := a_l0 + step_ang * 0.90
		var a_r1 := float(si + 1) * step_ang
		var angs: Array[float] = [a_l0, a_l1, a_r0, a_r1]
		var r_offs: Array[float] = [-0.0085, 0.0, 0.0, -0.0085]

		var stave_var := 0.5 + 0.5 * sin(float(si) * 2.37 + 0.4)
		var base_col := COL_RED_MID.lerp(COL_RED_HI, stave_var * 0.65)
		if absf(sin(a_mid)) < 0.45:
			# Subtle brighter crimson hazard belly highlight on front/back faces.
			base_col = base_col.lerp(COL_RED_HI, 0.28)

		for ti in range(t_stations.size() - 1):
			var t0 := t_stations[ti]
			var t1 := t_stations[ti + 1]
			var y0 := t0 * KEG_HEIGHT
			var y1 := t1 * KEG_HEIGHT
			var r0 := _stave_radius(t0)
			var r1 := _stave_radius(t1)
			var belly0 := sin(t0 * PI)
			var belly1 := sin(t1 * PI)
			var c_face0 := COL_RED_DARK.lerp(base_col, 0.35 + 0.65 * belly0)
			var c_face1 := COL_RED_DARK.lerp(base_col, 0.35 + 0.65 * belly1)

			for sub in 3:
				var aa := angs[sub]
				var ab := angs[sub + 1]
				var ra := r_offs[sub]
				var rb := r_offs[sub + 1]
				var p00 := Vector3(cos(aa) * (r0 + ra), y0, sin(aa) * (r0 + ra))
				var p01 := Vector3(cos(ab) * (r0 + rb), y0, sin(ab) * (r0 + rb))
				var p11 := Vector3(cos(ab) * (r1 + rb), y1, sin(ab) * (r1 + rb))
				var p10 := Vector3(cos(aa) * (r1 + ra), y1, sin(aa) * (r1 + ra))
				var ca0 := COL_SEAM_OAK if sub == 0 else c_face0
				var cb0 := COL_SEAM_OAK if sub == 2 else c_face0
				var ca1 := COL_SEAM_OAK if sub == 0 else c_face1
				var cb1 := COL_SEAM_OAK if sub == 2 else c_face1
				_emit_outward_quad(st, p00, p01, p11, p10, ref_center, ca0, cb0, cb1, ca1)


static func _add_cask_heads(st: SurfaceTool, segs: int) -> void:
	var r_outer := _stave_radius(1.0)
	var r_inner := r_outer - 0.028
	var top_rim_y := KEG_HEIGHT
	var top_head_y := KEG_HEIGHT - 0.044
	var bot_rim_y := 0.0
	var bot_head_y := 0.036

	var top_ctr := Vector3(0.0, top_head_y, 0.0)
	var bot_ctr := Vector3(0.0, bot_head_y, 0.0)
	var top_ref := Vector3(0.0, top_head_y - 0.25, 0.0)
	var bot_ref := Vector3(0.0, bot_head_y + 0.25, 0.0)
	var top_wall_ref := Vector3(0.0, top_head_y + 0.02, 0.0)

	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)

		# Top chime bevel lip (horizontal ring at y = KEG_HEIGHT).
		var to0 := Vector3(c0 * r_outer, top_rim_y, s0 * r_outer)
		var to1 := Vector3(c1 * r_outer, top_rim_y, s1 * r_outer)
		var ti0 := Vector3(c0 * r_inner, top_rim_y, s0 * r_inner)
		var ti1 := Vector3(c1 * r_inner, top_rim_y, s1 * r_inner)
		_emit_outward_quad(st, to0, to1, ti1, ti0, top_ref, COL_RED_DARK, COL_RED_DARK, COL_OAK_DARK, COL_OAK_DARK)

		# Top inner recessed chime wall (faces inward toward center axis).
		var th0 := Vector3(c0 * r_inner, top_head_y, s0 * r_inner)
		var th1 := Vector3(c1 * r_inner, top_head_y, s1 * r_inner)
		var inward_ref := Vector3((c0 + c1) * (r_outer + 0.12), top_wall_ref.y, (s0 + s1) * (r_outer + 0.12))
		_emit_outward_quad(st, ti0, ti1, th1, th0, inward_ref, COL_OAK_DARK, COL_OAK_DARK, COL_SEAM_OAK, COL_SEAM_OAK)

		# Top oak head disc.
		var plank_col := COL_OAK_HEAD if (i % 3 != 0) else COL_OAK_HEAD.darkened(0.14)
		_emit_outward_tri(st, top_ctr, th1, th0, top_ref, COL_OAK_HEAD, plank_col, plank_col)

		# Bottom chime bevel lip + recessed oak head.
		var bo0 := Vector3(c0 * r_outer, bot_rim_y, s0 * r_outer)
		var bo1 := Vector3(c1 * r_outer, bot_rim_y, s1 * r_outer)
		var bi0 := Vector3(c0 * r_inner, bot_rim_y, s0 * r_inner)
		var bi1 := Vector3(c1 * r_inner, bot_rim_y, s1 * r_inner)
		var bh0 := Vector3(c0 * r_inner, bot_head_y, s0 * r_inner)
		var bh1 := Vector3(c1 * r_inner, bot_head_y, s1 * r_inner)
		_emit_outward_quad(st, bo0, bi0, bi1, bo1, bot_ref, COL_RED_DARK, COL_OAK_DARK, COL_OAK_DARK, COL_RED_DARK)
		_emit_outward_quad(st, bi0, bh0, bh1, bi1, Vector3((c0 + c1) * (r_outer + 0.12), bot_head_y * 0.5, (s0 + s1) * (r_outer + 0.12)),
			COL_OAK_DARK, COL_SEAM_OAK, COL_SEAM_OAK, COL_OAK_DARK)
		_emit_outward_tri(st, bot_ctr, bh0, bh1, bot_ref, COL_OAK_DARK, COL_OAK_DARK, COL_OAK_DARK)

	# 3 subtle recessed plank seam strips across the top oak head for handcrafted detail.
	for pk in [-1, 0, 1]:
		var px := float(pk) * 0.068
		var half_len := sqrt(maxf(0.002, r_inner * r_inner - px * px)) * 0.90
		_add_box_prism(st, Vector3(px, top_head_y + 0.003, 0.0), Vector3(0.005, 0.004, half_len), Basis.IDENTITY, COL_SEAM_OAK, COL_OAK_DARK)


static func _add_iron_hoop(st: SurfaceTool, t_center: float, band_h: float, proud: float,
		segs: int, rivet_phase: float) -> void:
	var y_mid := t_center * KEG_HEIGHT
	var y_bot := y_mid - band_h * 0.5
	var y_top := y_mid + band_h * 0.5
	var r_in_b := _stave_radius(clampf(y_bot / KEG_HEIGHT, 0.0, 1.0)) - 0.003
	var r_in_t := _stave_radius(clampf(y_top / KEG_HEIGHT, 0.0, 1.0)) - 0.003
	var r_out_b := r_in_b + proud
	var r_out_t := r_in_t + proud
	var ref_c := Vector3(0.0, y_mid, 0.0)

	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var ib0 := Vector3(c0 * r_in_b, y_bot, s0 * r_in_b)
		var ib1 := Vector3(c1 * r_in_b, y_bot, s1 * r_in_b)
		var ob0 := Vector3(c0 * r_out_b, y_bot, s0 * r_out_b)
		var ob1 := Vector3(c1 * r_out_b, y_bot, s1 * r_out_b)
		var ot0 := Vector3(c0 * r_out_t, y_top, s0 * r_out_t)
		var ot1 := Vector3(c1 * r_out_t, y_top, s1 * r_out_t)
		var it0 := Vector3(c0 * r_in_t, y_top, s0 * r_in_t)
		var it1 := Vector3(c1 * r_in_t, y_top, s1 * r_in_t)

		var face_c := COL_IRON_DARK.lerp(COL_IRON_HI, 0.35 + 0.30 * float(i % 2))
		_emit_outward_quad(st, ob0, ob1, ot1, ot0, ref_c, COL_IRON_DARK, COL_IRON_DARK, face_c, face_c)
		_emit_outward_quad(st, ot0, ot1, it1, it0, ref_c, COL_IRON_HI, COL_IRON_HI, COL_IRON_DARK, COL_IRON_DARK)
		_emit_outward_quad(st, ib0, ib1, ob1, ob0, ref_c, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_DARK)

	# 6 forged raised square rivet studs around each iron hoop.
	const RIVET_COUNT := 6
	var r_riv := (r_out_b + r_out_t) * 0.5
	for ri in RIVET_COUNT:
		var ang := rivet_phase + TAU * float(ri) / float(RIVET_COUNT)
		var normal := Vector3(cos(ang), 0.0, sin(ang))
		var tang := Vector3(-sin(ang), 0.0, cos(ang))
		var rot := Basis(tang, Vector3.UP, normal)
		var center := normal * (r_riv + 0.0055) + Vector3(0.0, y_mid, 0.0)
		_add_beveled_rivet(st, center, rot, 0.011, 0.0075, COL_RIVET, COL_IRON_DARK)


static func _add_beveled_rivet(st: SurfaceTool, base_center: Vector3, rot: Basis,
		half_w: float, height: float, col_top: Color, col_side: Color) -> void:
	var b0 := base_center + rot * Vector3(-half_w, -half_w, 0.0)
	var b1 := base_center + rot * Vector3(half_w, -half_w, 0.0)
	var b2 := base_center + rot * Vector3(half_w, half_w, 0.0)
	var b3 := base_center + rot * Vector3(-half_w, half_w, 0.0)
	var tw := half_w * 0.58
	var t0 := base_center + rot * Vector3(-tw, -tw, height)
	var t1 := base_center + rot * Vector3(tw, -tw, height)
	var t2 := base_center + rot * Vector3(tw, tw, height)
	var t3 := base_center + rot * Vector3(-tw, tw, height)
	var ref_c := base_center + rot * Vector3(0.0, 0.0, -0.02)
	_emit_outward_quad(st, t0, t1, t2, t3, ref_c, col_top, col_top, col_top, col_top)
	_emit_outward_quad(st, b0, b1, t1, t0, ref_c, col_side, col_side, col_top, col_top)
	_emit_outward_quad(st, b1, b2, t2, t1, ref_c, col_side, col_side, col_top, col_top)
	_emit_outward_quad(st, b2, b3, t3, t2, ref_c, col_side, col_side, col_top, col_top)
	_emit_outward_quad(st, b3, b0, t0, t3, ref_c, col_side, col_side, col_top, col_top)


static func _add_skull_emblem(st: SurfaceTool, z_sign: float) -> void:
	# Curved relief warning diamond + bold ivory skull & crossbone bars on front (-Z) & back (+Z).
	var r_belly := _stave_radius(0.5)
	var ref_c := Vector3(0.0, KEG_CENTER_Y, 0.0)
	var project := func(lx: float, ly: float, lift: float) -> Vector3:
		var ty := clampf((KEG_CENTER_Y + ly) / KEG_HEIGHT, 0.05, 0.95)
		var rad := _stave_radius(ty) + lift
		var ang := lx / maxf(r_belly, 0.1)
		return Vector3(sin(ang) * rad * (-z_sign), KEG_CENTER_Y + ly, cos(ang) * rad * z_sign)

	# 1. Burnished gold diamond warning border & dark soot-crimson backing diamond.
	var outer_pts: Array[Vector2] = [
		Vector2(0.0, 0.118), Vector2(0.112, 0.0), Vector2(0.0, -0.118), Vector2(-0.112, 0.0)
	]
	var inner_pts: Array[Vector2] = [
		Vector2(0.0, 0.095), Vector2(0.090, 0.0), Vector2(0.0, -0.095), Vector2(-0.090, 0.0)
	]
	var ctr_bg: Vector3 = project.call(0.0, 0.0, 0.008)
	for i in 4:
		var i1 := (i + 1) % 4
		var o0: Vector3 = project.call(outer_pts[i].x, outer_pts[i].y, 0.006)
		var o1: Vector3 = project.call(outer_pts[i1].x, outer_pts[i1].y, 0.006)
		var in0: Vector3 = project.call(inner_pts[i].x, inner_pts[i].y, 0.009)
		var in1: Vector3 = project.call(inner_pts[i1].x, inner_pts[i1].y, 0.009)
		_emit_outward_quad(st, o0, o1, in1, in0, ref_c, COL_GOLD_TRIM, COL_GOLD_TRIM, COL_GOLD_TRIM, COL_GOLD_TRIM)
		_emit_outward_tri(st, ctr_bg, in0, in1, ref_c, COL_PLAQUE_BG, COL_PLAQUE_BG, COL_PLAQUE_BG)

	# 2. Crossed bone chevron bars behind skull.
	var bone_pairs: Array[Array] = [
		[Vector2(-0.058, -0.044), Vector2(0.058, 0.036)],
		[Vector2(0.058, -0.044), Vector2(-0.058, 0.036)],
	]
	for bp: Array in bone_pairs:
		var p0: Vector2 = bp[0] as Vector2
		var p1: Vector2 = bp[1] as Vector2
		var d := (p1 - p0).normalized()
		var n := Vector2(-d.y, d.x) * 0.0095
		var q0: Vector3 = project.call(p0.x - n.x, p0.y - n.y, 0.0115)
		var q1: Vector3 = project.call(p0.x + n.x, p0.y + n.y, 0.0115)
		var q2: Vector3 = project.call(p1.x + n.x, p1.y + n.y, 0.0115)
		var q3: Vector3 = project.call(p1.x - n.x, p1.y - n.y, 0.0115)
		_emit_outward_quad(st, q0, q1, q2, q3, ref_c, COL_SKULL_IVORY, COL_SKULL_IVORY, COL_SKULL_IVORY, COL_SKULL_IVORY)

	# 3. Bold octagonal ivory skull cranium + jawbone + dark recessed eye sockets.
	var skull_ctr: Vector3 = project.call(0.0, 0.020, 0.0165)
	var cranium_pts: Array[Vector2] = [
		Vector2(0.000, 0.062),
		Vector2(0.034, 0.052),
		Vector2(0.046, 0.024),
		Vector2(0.036, -0.004),
		Vector2(0.020, -0.014),
		Vector2(-0.020, -0.014),
		Vector2(-0.036, -0.004),
		Vector2(-0.046, 0.024),
		Vector2(-0.034, 0.052),
	]
	for k in cranium_pts.size():
		var k1 := (k + 1) % cranium_pts.size()
		var v0: Vector3 = project.call(cranium_pts[k].x, cranium_pts[k].y, 0.014)
		var v1: Vector3 = project.call(cranium_pts[k1].x, cranium_pts[k1].y, 0.014)
		_emit_outward_tri(st, skull_ctr, v0, v1, ref_c, COL_SKULL_IVORY, COL_SKULL_IVORY, COL_SKULL_IVORY)

	# Jawbone block below cranium.
	var j0: Vector3 = project.call(-0.022, -0.012, 0.0145)
	var j1: Vector3 = project.call(0.022, -0.012, 0.0145)
	var j2: Vector3 = project.call(0.018, -0.038, 0.014)
	var j3: Vector3 = project.call(-0.018, -0.038, 0.014)
	_emit_outward_quad(st, j0, j1, j2, j3, ref_c, COL_SKULL_IVORY, COL_SKULL_IVORY, COL_SKULL_IVORY.darkened(0.08), COL_SKULL_IVORY.darkened(0.08))

	# Twin dark eye sockets.
	for ex: float in [-0.018, 0.018]:
		var e0: Vector3 = project.call(ex, 0.026, 0.0175)
		var e1: Vector3 = project.call(ex + 0.011, 0.014, 0.0175)
		var e2: Vector3 = project.call(ex, 0.004, 0.0175)
		var e3: Vector3 = project.call(ex - 0.011, 0.014, 0.0175)
		_emit_outward_quad(st, e0, e1, e2, e3, ref_c, COL_PLAQUE_BG, COL_PLAQUE_BG, COL_PLAQUE_BG, COL_PLAQUE_BG)


static func _add_bung_stopper(st: SurfaceTool) -> void:
	# Tapered 8-sided cork/oak bung plug protruding on starboard upper stave (+X, y = 0.40).
	var t_y := 0.40 / KEG_HEIGHT
	var r_base := _stave_radius(t_y) - 0.005
	var center := Vector3(r_base, 0.40, 0.0)
	var axis := Vector3(1.0, 0.08, 0.0).normalized()
	var up := Vector3.UP
	var fwd := axis.cross(up).normalized()
	up = fwd.cross(axis).normalized()
	var segs := 8
	var r0 := 0.024
	var r1 := 0.019
	var len_b := 0.032
	var tip_c := center + axis * (len_b + 0.004)
	var ref_c := center - axis * 0.05

	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := fwd * cos(a0) + up * sin(a0)
		var d1 := fwd * cos(a1) + up * sin(a1)
		var p0 := center + d0 * r0
		var p1 := center + d1 * r0
		var q0 := center + axis * len_b + d0 * r1
		var q1 := center + axis * len_b + d1 * r1
		_emit_outward_quad(st, p0, p1, q1, q0, ref_c, COL_OAK_DARK, COL_OAK_DARK, COL_BUNG, COL_BUNG)
		_emit_outward_tri(st, tip_c, q0, q1, ref_c, COL_BUNG, COL_BUNG.darkened(0.10), COL_BUNG.darkened(0.10))


static func _add_shoulder_rope_loop(st: SurfaceTool, side_x: float) -> void:
	# Braided arched hemp carrying handle loop anchored on port (-X) or starboard (+X) side.
	const STEPS := 7
	const RAD_SEGS := 6
	var pts: Array[Vector3] = []
	for i in range(STEPS + 1):
		var u := float(i) / float(STEPS)
		var y := lerpf(0.455, 0.590, u)
		var r_wall := _stave_radius(y / KEG_HEIGHT) + 0.010
		var bow := sin(u * PI) * 0.058
		var z_sway := sin(u * PI) * 0.022 * side_x
		pts.append(Vector3(side_x * (r_wall + bow), y, z_sway))

	_add_braided_tube(st, pts, 0.013, RAD_SEGS, COL_ROPE_HI, COL_ROPE_LO)

	# Forged iron staple collars pinning top & bottom rope ends to the hoops.
	for end_pt: Vector3 in [pts[0], pts[STEPS]]:
		_add_box_prism(st, end_pt, Vector3(0.016, 0.015, 0.022), Basis.IDENTITY, COL_IRON_HI, COL_IRON_DARK)


static func _add_fuse_grommet(st: SurfaceTool) -> void:
	# 8-sided beveled brass fuse grommet collar centered on the recessed top head.
	const SEGS := 8
	var y_bot := KEG_HEIGHT - 0.044
	var y_top := FUSE_BASE_Y + 0.008
	var r_out := 0.036
	var r_top := 0.024
	var r_in := 0.014
	var ref_c := Vector3(0.0, y_bot - 0.03, 0.0)

	for i in SEGS:
		var a0 := TAU * float(i) / float(SEGS)
		var a1 := TAU * float(i + 1) / float(SEGS)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var b0 := Vector3(c0 * r_out, y_bot, s0 * r_out)
		var b1 := Vector3(c1 * r_out, y_bot, s1 * r_out)
		var t0 := Vector3(c0 * r_top, y_top, s0 * r_top)
		var t1 := Vector3(c1 * r_top, y_top, s1 * r_top)
		var i0 := Vector3(c0 * r_in, y_top, s0 * r_in)
		var i1 := Vector3(c1 * r_in, y_top, s1 * r_in)
		_emit_outward_quad(st, b0, b1, t1, t0, ref_c, COL_BRASS_LO, COL_BRASS_LO, COL_BRASS_HI, COL_BRASS_HI)
		_emit_outward_quad(st, t0, t1, i1, i0, ref_c, COL_BRASS_HI, COL_BRASS_HI, COL_SEAM_OAK, COL_SEAM_OAK)


static func _build_fuse_cord_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 8
	var pts: Array[Vector3] = []
	for i in range(STEPS + 1):
		var u := float(i) / float(STEPS)
		pts.append(_fuse_curve_pos(u) - Vector3(0.0, FUSE_BASE_Y, 0.0))
	_add_braided_tube(st, pts, 0.0095, 6, COL_ROPE_HI, COL_ROPE_LO, true)
	st.generate_normals()
	return st.commit()


static func _add_braided_tube(st: SurfaceTool, pts: Array[Vector3], radius: float, segs: int,
		col_hi: Color, col_lo: Color, char_tip: bool = false) -> void:
	if pts.size() < 2:
		return
	var rings: Array[Array] = []
	for i in pts.size():
		var tang: Vector3
		if i == 0:
			tang = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			tang = (pts[i] - pts[i - 1]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		if tang.length_squared() < 1e-6:
			tang = Vector3.UP
		var ref_up := Vector3.RIGHT if absf(tang.dot(Vector3.UP)) > 0.92 else Vector3.UP
		var side := tang.cross(ref_up).normalized()
		var up := side.cross(tang).normalized()
		var twist := float(i) * 0.72
		var ring: Array[Vector3] = []
		for k in segs:
			var a := TAU * float(k) / float(segs) + twist
			ring.append(pts[i] + (side * cos(a) + up * sin(a)) * radius)
		rings.append(ring)

	for i in range(pts.size() - 1):
		var ref_c := (pts[i] + pts[i + 1]) * 0.5
		var is_last := char_tip and (i >= pts.size() - 2)
		for k in segs:
			var k1 := (k + 1) % segs
			var strand_hi := ((i + k) % 2 == 0)
			var c0 := Color(0.14, 0.11, 0.09) if is_last else (col_hi if strand_hi else col_lo)
			var c1 := Color(0.24, 0.14, 0.08) if is_last else (col_lo if strand_hi else col_hi)
			_emit_outward_quad(st, rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k],
				ref_c, c0, c1, c1, c0)

	# Cap the far end cleanly.
	var last_idx := pts.size() - 1
	var tip_dir := (pts[last_idx] - pts[last_idx - 1]).normalized()
	var tip_pt := pts[last_idx] + tip_dir * (radius * 0.7)
	var cap_col := Color(0.12, 0.09, 0.08) if char_tip else col_lo
	for k in segs:
		var k1 := (k + 1) % segs
		_emit_outward_tri(st, tip_pt, rings[last_idx][k], rings[last_idx][k1], pts[last_idx - 1], cap_col, cap_col, cap_col)


static func _build_ember_mesh() -> ArrayMesh:
	# Glowing faceted incandescent ember bead + spiky mini-flame crown (24 tris).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 6
	var col_core := Color(1.0, 0.98, 0.84)
	var col_hot := Color(1.0, 0.64, 0.14)
	var col_edge := Color(0.95, 0.24, 0.04)

	var top := Vector3(0.0, 0.046, 0.0)
	var bot := Vector3(0.0, -0.022, 0.0)
	var ring_lo: Array[Vector3] = []
	var ring_hi: Array[Vector3] = []
	for k in SEGS:
		var a := TAU * float(k) / float(SEGS)
		var r_lo := 0.024 * (1.0 + 0.20 * float(k % 2))
		var r_hi := 0.017 * (1.0 + 0.25 * float((k + 1) % 2))
		ring_lo.append(Vector3(cos(a) * r_lo, 0.002, sin(a) * r_lo))
		ring_hi.append(Vector3(cos(a + 0.25) * r_hi, 0.022, sin(a + 0.25) * r_hi))

	for k in SEGS:
		var k1 := (k + 1) % SEGS
		_emit_outward_tri(st, bot, ring_lo[k1], ring_lo[k], Vector3.ZERO, col_edge, col_hot, col_hot)
		_emit_outward_quad(st, ring_lo[k], ring_lo[k1], ring_hi[k1], ring_hi[k], Vector3.ZERO, col_hot, col_hot, col_core, col_core)
		_emit_outward_tri(st, top, ring_hi[k], ring_hi[k1], Vector3.ZERO, col_core, col_core, col_hot)

	st.generate_normals()
	return st.commit()


static func _build_fuse_halo_mesh() -> ArrayMesh:
	# Exact 48-tri 16-wedge radial additive FuseGlowHalo disc (diameter 1.0 m -> scale = world meters)
	# with incandescent white-gold center -> blazing ember-orange mid -> pure Color(0, 0, 0, 1) rim
	# and exact finite unit (0, 0, 1) normals for zero box edge under additive billboard blend.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const INNER_R := 0.22
	const OUTER_R := 0.50
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	const COL_CORE := Color(1.00, 0.96, 0.78, 1.0)
	const COL_MID := Color(1.00, 0.48, 0.10, 1.0)
	const COL_RIM := Color(0.00, 0.00, 0.00, 1.0)

	var ctr := Vector3.ZERO
	for i in WEDGES:
		var a0 := TAU * float(i) / float(WEDGES)
		var a1 := TAU * float(i + 1) / float(WEDGES)
		var m0 := Vector3(cos(a0) * INNER_R, sin(a0) * INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * INNER_R, sin(a1) * INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)

		# Inner incandescent white-gold core wedge (16 tris)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_CORE)
		st.add_vertex(ctr)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_MID)
		st.add_vertex(m0)

		# Outer feathered skirt quad fading smoothly to pure black (32 tris)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_RIM)
		st.add_vertex(o0)

	return st.commit()


static func _build_spark_mesh() -> ArrayMesh:
	# Exact 16-triangle sculpted diamond bipyramid spark crystal (8 top + 8 bottom faces).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 8
	var col_core := Color(1.0, 0.98, 0.82)
	var col_tip := Color(1.0, 0.56, 0.10)
	var top := Vector3(0.0, 0.036, 0.0)
	var bot := Vector3(0.0, -0.028, 0.0)
	var ring: Array[Vector3] = []
	for k in SEGS:
		var a := TAU * float(k) / float(SEGS)
		ring.append(Vector3(cos(a) * 0.014, 0.0, sin(a) * 0.014))
	for k in SEGS:
		var k1 := (k + 1) % SEGS
		_emit_outward_tri(st, top, ring[k], ring[k1], Vector3.ZERO, col_tip, col_core, col_core)
		_emit_outward_tri(st, bot, ring[k1], ring[k], Vector3.ZERO, col_tip, col_core, col_core)
	st.generate_normals()
	return st.commit()


static func _build_fireball_mesh() -> ArrayMesh:
	# Sculpted spiky incandescent explosion polyhedron (zero PrimitiveMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const LON := 12
	const LAT := 6
	var col_white := Color(1.0, 0.98, 0.86)
	var col_gold := Color(1.0, 0.68, 0.16)
	var col_crimson := Color(0.95, 0.24, 0.04)

	var rings: Array[Array] = []
	for j in range(1, LAT):
		var phi := PI * float(j) / float(LAT)
		var ring: Array[Vector3] = []
		for i in LON:
			var theta := TAU * float(i) / float(LON)
			var spike := 1.0 + 0.24 * sin(theta * 3.0 + float(j) * 1.9) * cos(phi * 2.0)
			ring.append(Vector3(sin(phi) * cos(theta) * spike, cos(phi) * spike, sin(phi) * sin(theta) * spike))
		rings.append(ring)

	var north := Vector3(0.0, 1.18, 0.0)
	var south := Vector3(0.0, -1.08, 0.0)
	for i in LON:
		var i1 := (i + 1) % LON
		_emit_outward_tri(st, north, rings[0][i], rings[0][i1], Vector3.ZERO, col_white, col_gold, col_gold)
		_emit_outward_tri(st, south, rings[rings.size() - 1][i1], rings[rings.size() - 1][i], Vector3.ZERO, col_crimson, col_gold, col_gold)
	for r in range(rings.size() - 1):
		var c_a := col_white if r == 0 else col_gold
		var c_b := col_gold if r < rings.size() - 2 else col_crimson
		for i in LON:
			var i1 := (i + 1) % LON
			_emit_outward_quad(st, rings[r][i], rings[r][i1], rings[r + 1][i1], rings[r + 1][i], Vector3.ZERO, c_a, c_a, c_b, c_b)
	st.generate_normals()
	return st.commit()


static func _build_shockwave_mesh() -> ArrayMesh:
	# Sculpted expanding beveled pressure ring (24 segments, zero PrimitiveMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 24
	var r_in := 0.72
	var r_mid := 0.90
	var r_out := 1.00
	var h := 0.16
	var col_hot := Color(1.0, 0.86, 0.44)
	var col_rim := Color(1.0, 0.56, 0.16)
	var col_edge := Color(0.90, 0.76, 0.62)

	for i in SEGS:
		var a0 := TAU * float(i) / float(SEGS)
		var a1 := TAU * float(i + 1) / float(SEGS)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var p_in0 := Vector3(c0 * r_in, 0.0, s0 * r_in)
		var p_in1 := Vector3(c1 * r_in, 0.0, s1 * r_in)
		var p_top0 := Vector3(c0 * r_mid, h, s0 * r_mid)
		var p_top1 := Vector3(c1 * r_mid, h, s1 * r_mid)
		var p_out0 := Vector3(c0 * r_out, 0.0, s0 * r_out)
		var p_out1 := Vector3(c1 * r_out, 0.0, s1 * r_out)
		var p_bot0 := Vector3(c0 * r_mid, -h * 0.45, s0 * r_mid)
		var p_bot1 := Vector3(c1 * r_mid, -h * 0.45, s1 * r_mid)
		var ref_c := Vector3((c0 + c1) * 0.5 * r_mid, 0.0, (s0 + s1) * 0.5 * r_mid)
		_emit_outward_quad(st, p_in0, p_in1, p_top1, p_top0, ref_c, col_edge, col_edge, col_hot, col_hot)
		_emit_outward_quad(st, p_top0, p_top1, p_out1, p_out0, ref_c, col_hot, col_hot, col_rim, col_rim)
		_emit_outward_quad(st, p_out0, p_out1, p_bot1, p_bot0, ref_c, col_rim, col_rim, col_edge, col_edge)
		_emit_outward_quad(st, p_bot0, p_bot1, p_in1, p_in0, ref_c, col_edge, col_edge, col_edge, col_edge)
	st.generate_normals()
	return st.commit()


static func _build_splinter_mesh() -> ArrayMesh:
	# Sculpted jagged charred crimson-oak barrel stave splinter shrapnel.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[Array] = [
		[-0.22, -0.012, 0.020, -0.008, 0.007, Color(0.95, 0.34, 0.05)],
		[-0.10, -0.044, 0.046, 0.006, 0.014, COL_SEAM_OAK],
		[0.02, -0.048, 0.048, 0.012, 0.016, COL_RED_MID],
		[0.14, -0.036, 0.042, 0.004, 0.013, COL_RED_DARK],
		[0.24, -0.020, 0.012, -0.006, 0.006, COL_IRON_DARK],
	]
	var rings: Array[Array] = []
	var cols: Array[Color] = []
	for row: Array in rows:
		var z := float(row[0])
		var xl := float(row[1])
		var xr := float(row[2])
		var ya := float(row[3])
		var ht := float(row[4])
		rings.append([
			Vector3(xl, ya - ht, z),
			Vector3(xr, ya - ht, z),
			Vector3(xr, ya + ht, z),
			Vector3(xl, ya + ht, z),
		])
		cols.append(row[5] as Color)

	for i in range(rings.size() - 1):
		var c0 := cols[i]
		var c1 := cols[i + 1]
		var ref_c := Vector3(0.0, 0.0, (float(rows[i][0]) + float(rows[i + 1][0])) * 0.5)
		for k in 4:
			var k1 := (k + 1) % 4
			_emit_outward_quad(st, rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k], ref_c, c0, c0, c1, c1)
	_emit_outward_quad(st, rings[0][0], rings[0][3], rings[0][2], rings[0][1], Vector3.ZERO, cols[0], cols[0], cols[0], cols[0])
	var last := rings.size() - 1
	_emit_outward_quad(st, rings[last][0], rings[last][1], rings[last][2], rings[last][3], Vector3.ZERO, cols[last], cols[last], cols[last], cols[last])
	st.generate_normals()
	return st.commit()


static func _build_smoke_puff_mesh() -> ArrayMesh:
	# Sculpted faceted billowing gunpowder smoke puff polyhedron.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const LON := 8
	const LAT := 4
	var col_top := Color(0.42, 0.40, 0.42)
	var col_mid := Color(0.24, 0.23, 0.26)
	var col_bot := Color(0.14, 0.13, 0.15)
	var rings: Array[Array] = []
	for j in range(1, LAT):
		var phi := PI * float(j) / float(LAT)
		var ring: Array[Vector3] = []
		for i in LON:
			var theta := TAU * float(i) / float(LON)
			var puff := 0.52 * (1.0 + 0.18 * sin(theta * 2.0 + float(j) * 1.4))
			ring.append(Vector3(sin(phi) * cos(theta) * puff, cos(phi) * puff * 0.88, sin(phi) * sin(theta) * puff))
		rings.append(ring)
	var north := Vector3(0.0, 0.50, 0.0)
	var south := Vector3(0.0, -0.46, 0.0)
	for i in LON:
		var i1 := (i + 1) % LON
		_emit_outward_tri(st, north, rings[0][i], rings[0][i1], Vector3.ZERO, col_top, col_top, col_top)
		_emit_outward_tri(st, south, rings[rings.size() - 1][i1], rings[rings.size() - 1][i], Vector3.ZERO, col_bot, col_bot, col_bot)
	for r in range(rings.size() - 1):
		for i in LON:
			var i1 := (i + 1) % LON
			_emit_outward_quad(st, rings[r][i], rings[r][i1], rings[r + 1][i1], rings[r + 1][i], Vector3.ZERO, col_top, col_top, col_mid, col_mid)
	st.generate_normals()
	return st.commit()


static func _add_box_prism(st: SurfaceTool, center: Vector3, half: Vector3, rot: Basis,
		col_hi: Color, col_lo: Color) -> void:
	var corners: Array[Vector3] = [
		center + rot * Vector3(-half.x, -half.y, -half.z),
		center + rot * Vector3(half.x, -half.y, -half.z),
		center + rot * Vector3(half.x, -half.y, half.z),
		center + rot * Vector3(-half.x, -half.y, half.z),
		center + rot * Vector3(-half.x, half.y, -half.z),
		center + rot * Vector3(half.x, half.y, -half.z),
		center + rot * Vector3(half.x, half.y, half.z),
		center + rot * Vector3(-half.x, half.y, half.z),
	]
	_emit_outward_quad(st, corners[4], corners[5], corners[6], corners[7], center, col_hi, col_hi, col_hi, col_hi)
	_emit_outward_quad(st, corners[0], corners[3], corners[2], corners[1], center, col_lo, col_lo, col_lo, col_lo)
	_emit_outward_quad(st, corners[0], corners[1], corners[5], corners[4], center, col_lo, col_lo, col_hi, col_hi)
	_emit_outward_quad(st, corners[1], corners[2], corners[6], corners[5], center, col_lo, col_lo, col_hi, col_hi)
	_emit_outward_quad(st, corners[2], corners[3], corners[7], corners[6], center, col_lo, col_lo, col_hi, col_hi)
	_emit_outward_quad(st, corners[3], corners[0], corners[4], corners[7], center, col_lo, col_lo, col_hi, col_hi)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tmp_p := b
		b = c
		c = tmp_p
		var tmp_c := cb
		cb = cc
		cc = tmp_c
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _count_mesh_tris(mesh_res: ArrayMesh) -> int:
	if mesh_res == null:
		return 0
	var tris := 0
	for si in mesh_res.get_surface_count():
		var ilen := mesh_res.surface_get_array_index_len(si)
		if ilen > 0:
			tris += floori(float(ilen) / 3.0)
		else:
			tris += floori(float(mesh_res.surface_get_array_len(si)) / 3.0)
	return tris
