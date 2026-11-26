class_name FortBattery
extends Node3D
## Stylized coastal fort sea-battery cannon emplacement for Sea of Scoundrels.
##
## Features a procedural beveled oak wheeled naval garrison carriage, multi-ring
## lathe cast-iron barrel with cascabel, astragal bands, trunnions, and recessed
## bore, plus a stacked 4-ball iron shot pyramid. When `siege_active` is true on
## the host, smoothly tracks approaching player ships within its seaward yaw arc,
## computes ballistic lead, ignites a readable 1.35 s breech priming fuse spark
## and warning smoke telegraph, and fires real `Cannonball` projectiles with
## recoil kick and feathered radial billboard muzzle VFX. Destructible by player
## cannonballs, firearms, or melee strikes, and manually fireable via Interactable.

signal battery_fired(ball: Cannonball)
signal battery_destroyed(battery: FortBattery)

const GROUP := &"fort_batteries"
const MUZZLE_SPEED := 52.0
const TELEGRAPH_DURATION := 1.35
const MANUAL_RELOAD_TIME := 3.0
const MIN_PITCH := -0.45
const MAX_PITCH := 0.62
const YAW_TURN_RATE := 1.15
const PITCH_TURN_RATE := 0.95
const TELEGRAPH_TURN_SCALE := 0.35
const ALIGN_FIRE_TOLERANCE := 0.24
const MIN_ENGAGE_DIST := 14.0
const TRUNNION_HEIGHT := 0.88
const TRUNNION_Z := -0.18
const MUZZLE_TIP_Z := -1.62
const BREECH_VENT_LOCAL := Vector3(0.0, 0.255, 0.56)

# Painterly stylized fort-gun material palette.
const COL_OAK_LIGHT := Color(0.50, 0.33, 0.19)
const COL_OAK_MID := Color(0.39, 0.25, 0.14)
const COL_OAK_DARK := Color(0.24, 0.15, 0.08)
const COL_OAK_SCORCH := Color(0.14, 0.11, 0.09)
const COL_IRON_HIGHLIGHT := Color(0.26, 0.27, 0.30)
const COL_IRON_BASE := Color(0.15, 0.16, 0.18)
const COL_IRON_DARK := Color(0.08, 0.085, 0.10)
const COL_IRON_BORE := Color(0.03, 0.03, 0.035)
const COL_IRON_BAND := Color(0.30, 0.28, 0.24)
const COL_IRON_SCORCH := Color(0.10, 0.09, 0.09)

@export var siege_active: bool = false
@export var fire_range: float = 220.0
@export var reload_time: float = 6.5
@export var max_health: float = 80.0
@export var health: float = 80.0
@export var destroyed: bool = false
@export var base_forward_yaw: float = 0.0
@export var max_yaw_arc: float = 1.05
@export var faction: StringName = &"drowned"
@export var enable_effects: bool = true

## Duck-typed alias for CombatComponent hostility filtering.
var dead: bool:
	get:
		return destroyed

var interactable: Interactable = null

var _base_pivot: Node3D = null
var _carriage_pivot: Node3D = null
var _barrel_pivot: Node3D = null
var _quoin_mesh: MeshInstance3D = null
var _carriage_mesh: MeshInstance3D = null
var _barrel_mesh: MeshInstance3D = null
var _hitbox: BatteryHitbox = null
var _oak_mat: StandardMaterial3D = null
var _iron_mat: StandardMaterial3D = null

var _fuse_orb: MeshInstance3D = null
var _fuse_mat: StandardMaterial3D = null
var _fuse_light: OmniLight3D = null
var _fuse_particles: GPUParticles3D = null
var _smolder_particles: GPUParticles3D = null
var _spawned_vfx: Array[Node] = []

var _aim_yaw: float = 0.0
var _aim_pitch: float = 0.08
var _reload_timer: float = 0.0
var _telegraph_timer: float = 0.0
var _recoil: float = 0.0
var _damage_flash: float = 0.0
var _clock: float = 0.0
var _tracked_ship: Ship = null

static var _smoke_puff_tex: ImageTexture = null
static var _spark_streak_tex: ImageTexture = null
static var _flash_radial_tex: GradientTexture2D = null


## Physics hitbox proxy on layers 1 (world static) & 2 so ship cannonballs,
## pistols/blunderbusses, and melee strikes damage the emplacement cleanly.
class BatteryHitbox:
	extends StaticBody3D

	var owner_battery: FortBattery = null

	func take_damage(amount: float, from: Node = null) -> void:
		if owner_battery != null and is_instance_valid(owner_battery):
			owner_battery.take_damage(amount, from)

	func apply_damage(amount: float, from: Node = null) -> void:
		take_damage(amount, from)


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(&"combatants")


func _exit_tree() -> void:
	if _fuse_particles != null and is_instance_valid(_fuse_particles):
		_fuse_particles.emitting = false
	if _smolder_particles != null and is_instance_valid(_smolder_particles):
		_smolder_particles.emitting = false
	for fx in _spawned_vfx:
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
	_spawned_vfx.clear()


func _ready() -> void:
	health = clampf(health, 0.0, max_health)
	if health <= 0.0:
		destroyed = true
	_build_emplacement()
	_apply_visual_state(0.0)


# ============================================================ public API

## True during the 1.35 s glowing priming-fuse warning window right before firing.
func is_telegraphing() -> bool:
	return _telegraph_timer > 0.0 and not destroyed


## Enable or disable autonomous Fort Siege tracking and firing.
func set_siege_active(active: bool) -> void:
	siege_active = active
	if not active:
		_cancel_telegraph()
		_tracked_ship = null


## Restore a silenced sea-battery to full fighting condition (host-authoritative).
func repair_battery() -> void:
	if not Net.is_host():
		return
	destroyed = false
	health = max_health
	_reload_timer = 0.0
	_telegraph_timer = 0.0
	_recoil = 0.0
	_damage_flash = 0.0
	_aim_yaw = 0.0
	_aim_pitch = 0.08
	_set_telegraph_visuals(false)
	if _smolder_particles != null and is_instance_valid(_smolder_particles):
		_smolder_particles.emitting = false
	if _oak_mat != null:
		_oak_mat.albedo_color = Color.WHITE
	if _iron_mat != null:
		_iron_mat.albedo_color = Color.WHITE
		_iron_mat.emission_enabled = false
	if interactable != null:
		interactable.enabled = true
		interactable.prompt = "Fire Fort Cannon"
	_apply_visual_state(0.0)


## Host-authoritative damage intake from ship cannonballs, firearms, or melee.
func take_damage(amount: float, _from: Node = null) -> void:
	if not Net.is_host() or destroyed or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_damage_flash = 1.0
	_recoil = maxf(_recoil, 0.14)
	var hit_pos := global_position + Vector3.UP * 0.9
	Audio.play_sfx(&"hull_impact", hit_pos, -2.0)
	if health <= 0.0:
		_silence_battery()


## Duck-typed alias called by `Cannonball` and `CombatComponent`.
func apply_damage(amount: float, from: Node = null) -> void:
	take_damage(amount, from)


## Host-authoritative firing of a real `Cannonball` down the barrel's current line.
func fire_battery(shooter_pawn: Node = null) -> Cannonball:
	if not Net.is_host() or destroyed or not is_inside_tree():
		return null
	if _barrel_pivot == null:
		return null

	_cancel_telegraph()
	var muzzle_dir := get_aim_direction()
	var muzzle_pos := get_muzzle_world_position() + muzzle_dir * 0.28

	var ball := Cannonball.new()
	ball.name = "FortCannonball"
	ball.shooter_ship = _hitbox
	ball.shooter_pawn = shooter_pawn
	ball.hull_damage_radius = 0.45
	ball.enable_effects = enable_effects
	var spawn_parent := get_parent() if get_parent() != null else self
	spawn_parent.add_child(ball)
	ball.global_position = muzzle_pos
	ball.velocity = muzzle_dir * MUZZLE_SPEED

	_recoil = 0.44
	_spawn_muzzle_vfx(muzzle_pos, muzzle_dir)
	Audio.play_sfx(&"cannon_fire", muzzle_pos)
	battery_fired.emit(ball)
	return ball


func get_muzzle_world_position() -> Vector3:
	if _barrel_pivot != null and is_inside_tree():
		return _barrel_pivot.global_transform * Vector3(0.0, 0.0, MUZZLE_TIP_Z)
	return global_position + Vector3.UP * TRUNNION_HEIGHT


func get_aim_direction() -> Vector3:
	if _barrel_pivot != null and is_inside_tree():
		return (-_barrel_pivot.global_basis.z).normalized()
	var b := Basis(Vector3.UP, base_forward_yaw + _aim_yaw) * Basis(Vector3.RIGHT, _aim_pitch)
	return (-b.z).normalized()


# ============================================================ simulation

func _physics_process(delta: float) -> void:
	_clock += delta
	_recoil = move_toward(_recoil, 0.0, 0.92 * delta)
	_damage_flash = move_toward(_damage_flash, 0.0, 3.6 * delta)

	if not destroyed and Net.is_host():
		_tick_host_ai(delta)

	_apply_visual_state(delta)
	_prune_finished_vfx()


func _tick_host_ai(delta: float) -> void:
	_reload_timer = maxf(0.0, _reload_timer - delta)

	if not siege_active:
		if _telegraph_timer > 0.0:
			_cancel_telegraph()
		_tracked_ship = null
		return

	var target := _find_nearest_player_ship()
	_tracked_ship = target
	if target == null:
		if _telegraph_timer > 0.0:
			_cancel_telegraph()
		return

	var solution := _solve_ballistic_aim(target)
	if not bool(solution["valid"]):
		if _telegraph_timer > 0.0:
			_cancel_telegraph()
		return

	var desired_yaw: float = float(solution["yaw"])
	var desired_pitch: float = float(solution["pitch"])
	var slew_scale := TELEGRAPH_TURN_SCALE if _telegraph_timer > 0.0 else 1.0
	_aim_yaw = move_toward(_aim_yaw, desired_yaw, YAW_TURN_RATE * slew_scale * delta)
	_aim_pitch = move_toward(_aim_pitch, desired_pitch, PITCH_TURN_RATE * slew_scale * delta)

	if _telegraph_timer > 0.0:
		_telegraph_timer = maxf(0.0, _telegraph_timer - delta)
		if _telegraph_timer <= 0.0:
			_reload_timer = reload_time
			fire_battery(null)
	elif _reload_timer <= 0.0 and absf(_aim_yaw - desired_yaw) <= ALIGN_FIRE_TOLERANCE:
		_begin_telegraph()


func _begin_telegraph() -> void:
	_telegraph_timer = TELEGRAPH_DURATION
	_set_telegraph_visuals(true)
	if _barrel_pivot != null and is_inside_tree():
		var breech_world := _barrel_pivot.global_transform * BREECH_VENT_LOCAL
		Audio.play_sfx(&"lantern_click", breech_world, -2.0)


func _cancel_telegraph() -> void:
	_telegraph_timer = 0.0
	_set_telegraph_visuals(false)


func _find_nearest_player_ship() -> Ship:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Ship = null
	var best_d2 := fire_range * fire_range
	var min_d2 := MIN_ENGAGE_DIST * MIN_ENGAGE_DIST
	var my_pos := global_position

	for node in tree.get_nodes_in_group(&"ship"):
		var s := node as Ship
		if s == null or not is_instance_valid(s):
			continue
		if s.faction != &"player" or s.is_sinking:
			continue
		var d2 := my_pos.distance_squared_to(s.global_position)
		if d2 > best_d2 or d2 < min_d2:
			continue
		var local_p := to_local(s.global_position)
		var bearing := atan2(-local_p.x, -local_p.z)
		var rel_yaw := wrapf(bearing - base_forward_yaw, -PI, PI)
		if absf(rel_yaw) > max_yaw_arc:
			continue
		best_d2 = d2
		best = s
	return best


func _solve_ballistic_aim(target: Ship) -> Dictionary:
	var muzzle_pos := get_muzzle_world_position()
	var aim_pos := target.global_position + Vector3(0.0, 1.35, 0.0)
	var dist0 := muzzle_pos.distance_to(aim_pos)
	var flight_t := clampf(dist0 / MUZZLE_SPEED, 0.0, 5.5)

	# 2-step ballistic lead against moving hull velocity.
	var lead_pos := aim_pos + target.linear_velocity * flight_t
	var dist1 := muzzle_pos.distance_to(lead_pos)
	flight_t = clampf(dist1 / MUZZLE_SPEED, 0.0, 5.5)
	lead_pos = aim_pos + target.linear_velocity * flight_t

	var local_lead := to_local(lead_pos)
	var target_yaw := atan2(-local_lead.x, -local_lead.z)
	var rel_yaw := wrapf(target_yaw - base_forward_yaw, -PI, PI)
	if absf(rel_yaw) > max_yaw_arc:
		return {"valid": false, "yaw": 0.0, "pitch": 0.08}

	var dx := lead_pos.x - muzzle_pos.x
	var dz := lead_pos.z - muzzle_pos.z
	var dist_xz := sqrt(dx * dx + dz * dz)
	var dy := lead_pos.y - muzzle_pos.y
	if dist_xz < 2.0:
		return {"valid": false, "yaw": 0.0, "pitch": 0.08}

	# Solve low-arc ballistic trajectory: a*u^2 - dist_xz*u + (dy + a) = 0, u = tan(pitch).
	var g := Cannonball.GRAVITY
	var a := 0.5 * g * dist_xz * dist_xz / (MUZZLE_SPEED * MUZZLE_SPEED)
	var disc := dist_xz * dist_xz - 4.0 * a * (dy + a)
	var pitch := 0.50
	if disc >= 0.0 and a > 0.0001:
		var u := (dist_xz - sqrt(disc)) / (2.0 * a)
		pitch = atan(u)
	# Subtle linear drag compensation matching Cannonball.drag (~0.012).
	pitch += clampf(flight_t * 0.016, 0.0, 0.08)
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	return {"valid": true, "yaw": rel_yaw, "pitch": pitch}


func _silence_battery() -> void:
	destroyed = true
	_cancel_telegraph()
	if interactable != null:
		interactable.enabled = false
		interactable.prompt = "Battery Silenced"
	if _oak_mat != null:
		_oak_mat.albedo_color = Color(0.55, 0.50, 0.46)
	if _iron_mat != null:
		_iron_mat.albedo_color = Color(0.62, 0.58, 0.56)
	if _smolder_particles != null and is_instance_valid(_smolder_particles) and _effects_enabled():
		_smolder_particles.emitting = true
	Audio.play_sfx(&"hull_impact", global_position + Vector3.UP * 0.9, 2.0)
	if Game != null:
		Game.post_notice("Fort sea-battery silenced!")
	battery_destroyed.emit(self)


func _on_interacted(pawn: Node) -> void:
	if not Net.is_host() or destroyed:
		return
	if _reload_timer > 0.0:
		Audio.play_sfx(&"lantern_click", global_position + Vector3.UP * 0.9, -4.0)
		return
	# Ensure manual seaward shot clears the parapet nicely if aimed steeply downward.
	if _aim_pitch < 0.04:
		_aim_pitch = 0.12
		_apply_visual_state(0.0)
	_reload_timer = MANUAL_RELOAD_TIME
	fire_battery(pawn)


# ============================================================ visuals & animation

func _apply_visual_state(_delta: float) -> void:
	if _base_pivot != null:
		_base_pivot.rotation.y = base_forward_yaw
	if _carriage_pivot != null:
		if destroyed:
			_carriage_pivot.rotation = Vector3(0.0, _aim_yaw + 0.14, 0.06)
			_carriage_pivot.position = Vector3(0.0, 0.0, 0.24)
		else:
			_carriage_pivot.rotation = Vector3(0.0, _aim_yaw, 0.0)
			# Recoil pushes carriage inboard along local +Z (opposite -Z muzzle).
			var back := Basis(Vector3.UP, _aim_yaw).z
			_carriage_pivot.position = back * (_recoil * 0.72)
	if _barrel_pivot != null:
		if destroyed:
			_barrel_pivot.rotation = Vector3(-0.44, 0.08, 0.20)
			_barrel_pivot.position = Vector3(0.0, TRUNNION_HEIGHT - 0.10, TRUNNION_Z + 0.12)
		else:
			_barrel_pivot.rotation = Vector3(_aim_pitch, 0.0, 0.0)
			_barrel_pivot.position = Vector3(0.0, TRUNNION_HEIGHT, TRUNNION_Z + _recoil * 0.28)
	if _quoin_mesh != null:
		var q_t := clampf((_aim_pitch - MIN_PITCH) / (MAX_PITCH - MIN_PITCH), 0.0, 1.0)
		_quoin_mesh.position = Vector3(0.0, 0.56, lerpf(0.24, 0.44, q_t))

	if _iron_mat != null:
		if _damage_flash > 0.01:
			_iron_mat.emission_enabled = true
			_iron_mat.emission = Color(1.0, 0.52, 0.16)
			_iron_mat.emission_energy_multiplier = _damage_flash * 1.4
		elif destroyed:
			_iron_mat.emission_enabled = true
			_iron_mat.emission = Color(0.85, 0.24, 0.05)
			_iron_mat.emission_energy_multiplier = 0.14 + 0.08 * sin(_clock * 4.2)
		else:
			_iron_mat.emission_enabled = false

	if _telegraph_timer > 0.0 and not destroyed:
		var urgency := 1.0 - clampf(_telegraph_timer / TELEGRAPH_DURATION, 0.0, 1.0)
		var pulse := 0.75 + 0.35 * sin(_clock * (18.0 + urgency * 24.0))
		if _fuse_orb != null:
			_fuse_orb.visible = true
			var sc := lerpf(0.85, 1.45, urgency) * pulse
			_fuse_orb.scale = Vector3.ONE * sc
		if _fuse_mat != null:
			_fuse_mat.emission_energy_multiplier = lerpf(3.2, 6.8, urgency) * pulse
		if _fuse_light != null:
			_fuse_light.visible = true
			_fuse_light.light_energy = lerpf(2.8, 6.2, urgency) * pulse


func _set_telegraph_visuals(active: bool) -> void:
	if _fuse_orb != null:
		_fuse_orb.visible = active
	if _fuse_light != null:
		_fuse_light.visible = active
	if _fuse_particles != null and is_instance_valid(_fuse_particles):
		_fuse_particles.emitting = active and _effects_enabled()


# ============================================================ procedural emplacement mesh

func _build_emplacement() -> void:
	_oak_mat = StandardMaterial3D.new()
	_oak_mat.vertex_color_use_as_albedo = true
	_oak_mat.vertex_color_is_srgb = true
	_oak_mat.roughness = 0.86
	_oak_mat.metallic = 0.04

	_iron_mat = StandardMaterial3D.new()
	_iron_mat.vertex_color_use_as_albedo = true
	_iron_mat.vertex_color_is_srgb = true
	_iron_mat.roughness = 0.42
	_iron_mat.metallic = 0.78

	_base_pivot = Node3D.new()
	_base_pivot.name = "BasePivot"
	_base_pivot.rotation.y = base_forward_yaw
	add_child(_base_pivot)

	# 1. Chamfered octagonal timber-and-iron traverse pad grounded cleanly at y = 0.
	var pad_mi := MeshInstance3D.new()
	pad_mi.name = "TraversePad"
	pad_mi.mesh = _build_pad_mesh()
	pad_mi.material_override = _oak_mat
	_base_pivot.add_child(pad_mi)

	# 2. Stacked pyramid of 4 dark cast-iron cannonballs in a beveled oak shot garland.
	var stack_root := _build_cannonball_stack()
	stack_root.position = Vector3(1.12, 0.06, 0.48)
	_base_pivot.add_child(stack_root)

	# 3. Rotating wheeled garrison carriage pivot.
	_carriage_pivot = Node3D.new()
	_carriage_pivot.name = "CarriagePivot"
	_base_pivot.add_child(_carriage_pivot)

	_carriage_mesh = MeshInstance3D.new()
	_carriage_mesh.name = "OakGarrisonCarriage"
	_carriage_mesh.mesh = _build_carriage_mesh()
	_carriage_mesh.material_override = _oak_mat
	_carriage_pivot.add_child(_carriage_mesh)

	var hardware_mi := MeshInstance3D.new()
	hardware_mi.name = "CarriageIronHardware"
	hardware_mi.mesh = _build_carriage_iron_mesh()
	hardware_mi.material_override = _iron_mat
	_carriage_pivot.add_child(hardware_mi)

	# 4 beveled iron-rimmed spoked oak truck wheels.
	var wheel_front_wood := _build_wheel_wood_mesh(0.245, 0.13)
	var wheel_front_rim := _build_wheel_iron_mesh(0.245, 0.13)
	var wheel_rear_wood := _build_wheel_wood_mesh(0.215, 0.12)
	var wheel_rear_rim := _build_wheel_iron_mesh(0.215, 0.12)
	var wheel_specs: Array[Array] = [
		["Wheel_FL", Vector3(-0.52, 0.255, -0.58), true],
		["Wheel_FR", Vector3(0.52, 0.255, -0.58), true],
		["Wheel_RL", Vector3(-0.52, 0.225, 0.56), false],
		["Wheel_RR", Vector3(0.52, 0.225, 0.56), false],
	]
	for spec in wheel_specs:
		var holder := Node3D.new()
		holder.name = String(spec[0])
		holder.position = spec[1] as Vector3
		var is_front: bool = bool(spec[2])
		var w_mi := MeshInstance3D.new()
		w_mi.name = "Wood"
		w_mi.mesh = wheel_front_wood if is_front else wheel_rear_wood
		w_mi.material_override = _oak_mat
		holder.add_child(w_mi)
		var r_mi := MeshInstance3D.new()
		r_mi.name = "IronRim"
		r_mi.mesh = wheel_front_rim if is_front else wheel_rear_rim
		r_mi.material_override = _iron_mat
		holder.add_child(r_mi)
		_carriage_pivot.add_child(holder)

	# Tapered oak elevation wedge (quoin) sliding under the breech.
	_quoin_mesh = MeshInstance3D.new()
	_quoin_mesh.name = "ElevationQuoin"
	_quoin_mesh.mesh = _build_quoin_mesh()
	_quoin_mesh.material_override = _oak_mat
	_quoin_mesh.position = Vector3(0.0, 0.56, 0.34)
	_carriage_pivot.add_child(_quoin_mesh)

	# 4. Elevating cast-iron barrel pivot.
	_barrel_pivot = Node3D.new()
	_barrel_pivot.name = "BarrelPivot"
	_barrel_pivot.position = Vector3(0.0, TRUNNION_HEIGHT, TRUNNION_Z)
	_carriage_pivot.add_child(_barrel_pivot)

	_barrel_mesh = MeshInstance3D.new()
	_barrel_mesh.name = "CastIronBarrel"
	_barrel_mesh.mesh = _build_barrel_mesh()
	_barrel_mesh.material_override = _iron_mat
	_barrel_pivot.add_child(_barrel_mesh)

	# 5. Priming fuse telegraph orb, light, and particles at the breech touchhole.
	_build_telegraph_and_smolder_vfx()

	# 6. Destructible hitbox on layers 1 (world static) & 2 (cannonball + combat rays).
	_hitbox = BatteryHitbox.new()
	_hitbox.name = "BatteryHitbox"
	_hitbox.owner_battery = self
	_hitbox.collision_layer = 1 | (1 << 1)
	_hitbox.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "HitboxShape"
	var box := BoxShape3D.new()
	box.size = Vector3(1.55, 1.35, 2.35)
	cs.shape = box
	cs.position = Vector3(0.0, 0.72, -0.25)
	_hitbox.add_child(cs)
	_base_pivot.add_child(_hitbox)

	# 7. Player-capturable Interactable behind the breech.
	interactable = Interactable.create("Fire Fort Cannon", 1.15)
	interactable.name = "FireFortCannonInteractable"
	interactable.position = Vector3(0.0, 1.02, 0.68)
	interactable.reach = 3.2
	interactable.enabled = not destroyed
	interactable.target = self
	interactable.interacted.connect(_on_interacted)
	_base_pivot.add_child(interactable)


func _build_telegraph_and_smolder_vfx() -> void:
	_fuse_mat = StandardMaterial3D.new()
	_fuse_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fuse_mat.albedo_color = Color(1.0, 0.84, 0.34)
	_fuse_mat.emission_enabled = true
	_fuse_mat.emission = Color(1.0, 0.56, 0.12)
	_fuse_mat.emission_energy_multiplier = 4.5

	_fuse_orb = MeshInstance3D.new()
	_fuse_orb.name = "PrimingFuseSpark"
	var sph := SphereMesh.new()
	sph.radius = 0.115
	sph.height = 0.23
	sph.radial_segments = 10
	sph.rings = 5
	_fuse_orb.mesh = sph
	_fuse_orb.material_override = _fuse_mat
	_fuse_orb.position = BREECH_VENT_LOCAL + Vector3(0.0, 0.07, 0.0)
	_fuse_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fuse_orb.visible = false
	_barrel_pivot.add_child(_fuse_orb)

	_fuse_light = OmniLight3D.new()
	_fuse_light.name = "PrimingFuseLight"
	_fuse_light.light_color = Color(1.0, 0.58, 0.16)
	_fuse_light.light_energy = 4.0
	_fuse_light.omni_range = 10.0
	_fuse_light.omni_attenuation = 1.5
	_fuse_light.shadow_enabled = false
	_fuse_light.position = BREECH_VENT_LOCAL + Vector3(0.0, 0.24, 0.0)
	_fuse_light.visible = false
	_barrel_pivot.add_child(_fuse_light)

	if DisplayServer.get_name() == "headless":
		return

	# Crackling amber priming-fuse warning smoke & ember spout.
	_fuse_particles = GPUParticles3D.new()
	_fuse_particles.name = "PrimingFusePuff"
	_fuse_particles.amount = 22
	_fuse_particles.lifetime = 0.72
	_fuse_particles.emitting = false
	_fuse_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	_fuse_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fuse_particles.position = BREECH_VENT_LOCAL + Vector3(0.0, 0.06, 0.0)
	var fp := ParticleProcessMaterial.new()
	fp.direction = Vector3.UP
	fp.spread = 36.0
	fp.initial_velocity_min = 1.4
	fp.initial_velocity_max = 3.8
	fp.gravity = Vector3(0.0, 1.2, 0.0)
	fp.scale_min = 0.45
	fp.scale_max = 1.05
	fp.scale_curve = _make_scale_curve([Vector2(0.0, 0.4), Vector2(0.35, 1.0), Vector2(1.0, 1.45)])
	fp.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.18, 0.58, 1.0]),
		PackedColorArray([
			Color(1.0, 0.88, 0.44, 0.96),
			Color(1.0, 0.52, 0.14, 0.86),
			Color(0.76, 0.70, 0.64, 0.52),
			Color(0.55, 0.54, 0.54, 0.0),
		])
	)
	_fuse_particles.process_material = fp
	var f_quad := QuadMesh.new()
	f_quad.size = Vector2(0.42, 0.42)
	var f_mat := StandardMaterial3D.new()
	f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	f_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	f_mat.vertex_color_use_as_albedo = true
	f_mat.albedo_texture = _get_smoke_puff_texture()
	f_quad.material = f_mat
	_fuse_particles.draw_pass_1 = f_quad
	_barrel_pivot.add_child(_fuse_particles)

	# Dark smoldering smoke plume emitted once the battery is destroyed/silenced.
	_smolder_particles = GPUParticles3D.new()
	_smolder_particles.name = "SmolderPlume"
	_smolder_particles.amount = 18
	_smolder_particles.lifetime = 1.85
	_smolder_particles.emitting = destroyed and enable_effects
	_smolder_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	_smolder_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smolder_particles.position = Vector3(0.0, 0.72, -0.10)
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3.UP
	sp.spread = 24.0
	sp.initial_velocity_min = 0.85
	sp.initial_velocity_max = 1.95
	sp.gravity = Vector3(0.0, 0.65, 0.0)
	sp.scale_min = 0.75
	sp.scale_max = 1.55
	sp.scale_curve = _make_scale_curve([Vector2(0.0, 0.45), Vector2(0.45, 1.15), Vector2(1.0, 1.75)])
	sp.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.16, 0.60, 1.0]),
		PackedColorArray([
			Color(0.85, 0.34, 0.10, 0.0),
			Color(0.26, 0.22, 0.20, 0.72),
			Color(0.18, 0.18, 0.19, 0.44),
			Color(0.14, 0.14, 0.16, 0.0),
		])
	)
	_smolder_particles.process_material = sp
	var s_quad := QuadMesh.new()
	s_quad.size = Vector2(0.85, 0.85)
	s_quad.material = f_mat
	_smolder_particles.draw_pass_1 = s_quad
	_base_pivot.add_child(_smolder_particles)


func _build_pad_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Octagonal beveled planked deck pad (radius 1.48 m, thickness 0.075 m).
	var sides := 8
	var r_bot := 1.52
	var r_top := 1.42
	var h := 0.075
	var center_top := Vector3(0.0, h, 0.0)
	var c_center := COL_OAK_LIGHT.lerp(COL_OAK_MID, 0.3)
	var c_rim := COL_OAK_MID
	var c_side := COL_OAK_DARK
	for i in sides:
		var a0 := TAU * float(i) / float(sides) + PI / 8.0
		var a1 := TAU * float(i + 1) / float(sides) + PI / 8.0
		var b0 := Vector3(cos(a0) * r_bot, -0.06, sin(a0) * r_bot)
		var b1 := Vector3(cos(a1) * r_bot, -0.06, sin(a1) * r_bot)
		var t0 := Vector3(cos(a0) * r_top, h, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, h, sin(a1) * r_top)
		_st_tri(st, center_top, t0, t1, c_center, c_rim, c_rim)
		_st_quad(st, b0, b1, t1, t0, c_side, c_side, c_rim, c_rim)
	st.generate_normals()
	return st.commit()


func _build_carriage_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Stepped naval garrison side cheeks (4 classical rear steps + curved trunnion notch).
	# Profile in (z, y) ordered counter-clockwise when viewed from +X.
	var cheek_poly: Array[Vector2] = [
		Vector2(-0.88, 0.24),  # Front breast bottom
		Vector2(0.84, 0.20),   # Rear tail bottom
		Vector2(0.86, 0.44),   # Step 1 rear rise
		Vector2(0.62, 0.44),   # Step 1 tread
		Vector2(0.60, 0.58),   # Step 2 rise
		Vector2(0.36, 0.58),   # Step 2 tread
		Vector2(0.34, 0.72),   # Step 3 rise
		Vector2(0.08, 0.72),   # Step 3 tread
		Vector2(0.04, 0.90),   # Front top rear of trunnion
		Vector2(-0.08, 0.90),  # Rear edge of trunnion cradle
		Vector2(-0.18, 0.79),  # Bottom of trunnion cradle
		Vector2(-0.28, 0.90),  # Front edge of trunnion cradle
		Vector2(-0.78, 0.90),  # Front top horn
		Vector2(-0.88, 0.66),  # Front breast bevel
	]
	for side_sgn: float in [-1.0, 1.0]:
		var cx := side_sgn * 0.36
		_add_extruded_zy_profile(st, cheek_poly, cx - 0.075, cx + 0.075, COL_OAK_LIGHT, COL_OAK_MID, COL_OAK_DARK)

	# Heavy breast transom, bed plank, stool bed, and front/rear axletrees.
	_add_beveled_box(st, Vector3(0.0, 0.54, -0.68), Vector3(0.66, 0.44, 0.20), 0.03, COL_OAK_LIGHT, COL_OAK_MID, COL_OAK_DARK)
	_add_beveled_box(st, Vector3(0.0, 0.35, 0.06), Vector3(0.64, 0.14, 1.46), 0.025, COL_OAK_LIGHT, COL_OAK_MID, COL_OAK_DARK)
	_add_beveled_box(st, Vector3(0.0, 0.47, 0.34), Vector3(0.56, 0.12, 0.58), 0.02, COL_OAK_LIGHT, COL_OAK_MID, COL_OAK_DARK)
	# Front & rear axletrees spanning out to truck wheels.
	_add_beveled_box(st, Vector3(0.0, 0.255, -0.58), Vector3(1.16, 0.16, 0.18), 0.025, COL_OAK_MID, COL_OAK_DARK, COL_OAK_DARK)
	_add_beveled_box(st, Vector3(0.0, 0.225, 0.56), Vector3(1.14, 0.15, 0.17), 0.025, COL_OAK_MID, COL_OAK_DARK, COL_OAK_DARK)

	st.generate_normals()
	return st.commit()


func _build_carriage_iron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Iron trunnion cap-squares + front/rear cheek tie bolts + rear breech rings.
	for side_sgn: float in [-1.0, 1.0]:
		var cx := side_sgn * 0.36
		# Cap-square strap bridging over each trunnion cradle.
		_add_beveled_box(st, Vector3(cx, 0.945, TRUNNION_Z), Vector3(0.175, 0.065, 0.30), 0.015,
			COL_IRON_HIGHLIGHT, COL_IRON_BASE, COL_IRON_DARK)
		# Cheek reinforcement rivets & side breeching ring boss.
		_add_beveled_box(st, Vector3(cx + side_sgn * 0.085, 0.52, 0.42), Vector3(0.04, 0.14, 0.14), 0.01,
			COL_IRON_HIGHLIGHT, COL_IRON_BASE, COL_IRON_DARK)
		_add_beveled_box(st, Vector3(cx + side_sgn * 0.085, 0.62, -0.52), Vector3(0.04, 0.12, 0.12), 0.01,
			COL_IRON_HIGHLIGHT, COL_IRON_BASE, COL_IRON_DARK)

	# Heavy rear iron breech ring loop.
	var ring_segs := 10
	var r_maj := 0.11
	var r_min := 0.022
	var ring_c := Vector3(0.0, 0.36, 0.89)
	for i in ring_segs:
		var a0 := TAU * float(i) / float(ring_segs)
		var a1 := TAU * float(i + 1) / float(ring_segs)
		var p0 := ring_c + Vector3(cos(a0) * r_maj, sin(a0) * r_maj, 0.0)
		var p1 := ring_c + Vector3(cos(a1) * r_maj, sin(a1) * r_maj, 0.0)
		_add_tube_segment(st, p0, p1, r_min, 6, COL_IRON_HIGHLIGHT, COL_IRON_DARK)

	st.generate_normals()
	return st.commit()


func _build_wheel_wood_mesh(radius: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	var hw := width * 0.5
	var r_in := radius * 0.86
	# Thick chamfered oak wheel disc.
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var y0 := sin(a0) * r_in
		var z0 := cos(a0) * r_in
		var y1 := sin(a1) * r_in
		var z1 := cos(a1) * r_in
		# Left (-X) and right (+X) wooden faces with recessed hub shading.
		_st_tri(st, Vector3(-hw, 0.0, 0.0), Vector3(-hw, y1, z1), Vector3(-hw, y0, z0),
			COL_OAK_DARK, COL_OAK_MID, COL_OAK_LIGHT)
		_st_tri(st, Vector3(hw, 0.0, 0.0), Vector3(hw, y0, z0), Vector3(hw, y1, z1),
			COL_OAK_DARK, COL_OAK_LIGHT, COL_OAK_MID)
	# 4 chunky carved spoke ribs across the wheel faces.
	for s_idx in 4:
		var ang := float(s_idx) * (PI * 0.5)
		var dir := Vector3(0.0, sin(ang), cos(ang))
		_add_beveled_box(st, dir * (radius * 0.42), Vector3(width + 0.018, 0.055, 0.055), 0.01,
			COL_OAK_LIGHT, COL_OAK_MID, COL_OAK_DARK)
	st.generate_normals()
	return st.commit()


func _build_wheel_iron_mesh(radius: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	var hw := width * 0.5 + 0.008
	var r_in := radius * 0.85
	var r_out := radius
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var ol0 := Vector3(-hw, s0 * r_out, c0 * r_out)
		var ol1 := Vector3(-hw, s1 * r_out, c1 * r_out)
		var or0 := Vector3(hw, s0 * r_out, c0 * r_out)
		var or1 := Vector3(hw, s1 * r_out, c1 * r_out)
		var il0 := Vector3(-hw, s0 * r_in, c0 * r_in)
		var il1 := Vector3(-hw, s1 * r_in, c1 * r_in)
		var ir0 := Vector3(hw, s0 * r_in, c0 * r_in)
		var ir1 := Vector3(hw, s1 * r_in, c1 * r_in)
		# Outer iron tread.
		_st_quad(st, ol0, ol1, or1, or0, COL_IRON_HIGHLIGHT, COL_IRON_BASE, COL_IRON_BASE, COL_IRON_HIGHLIGHT)
		# Side iron tire cheeks.
		_st_quad(st, il0, il1, ol1, ol0, COL_IRON_BASE, COL_IRON_BASE, COL_IRON_HIGHLIGHT, COL_IRON_HIGHLIGHT)
		_st_quad(st, ir0, or0, or1, ir1, COL_IRON_BASE, COL_IRON_HIGHLIGHT, COL_IRON_HIGHLIGHT, COL_IRON_BASE)
	# Protruding iron axle hub cap & linchpin.
	_add_beveled_box(st, Vector3.ZERO, Vector3(width + 0.085, 0.095, 0.095), 0.02,
		COL_IRON_HIGHLIGHT, COL_IRON_BASE, COL_IRON_DARK)
	st.generate_normals()
	return st.commit()


func _build_quoin_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wedge_poly: Array[Vector2] = [
		Vector2(-0.22, 0.0),
		Vector2(0.24, 0.0),
		Vector2(0.24, 0.16),
		Vector2(-0.22, 0.045),
	]
	_add_extruded_zy_profile(st, wedge_poly, -0.14, 0.14, COL_OAK_LIGHT, COL_OAK_MID, COL_OAK_DARK)
	st.generate_normals()
	return st.commit()


func _build_barrel_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Multi-ring lathe profile along local Z (+Z breech/cascabel -> -Z muzzle & deep bore).
	# Each station: [z, radius, tint_color]
	var stations: Array[Array] = [
		[0.95, 0.004, COL_IRON_HIGHLIGHT],     # Cascabel knob tip
		[0.92, 0.072, COL_IRON_HIGHLIGHT],     # Cascabel pommel
		[0.85, 0.088, COL_IRON_BASE],
		[0.78, 0.056, COL_IRON_DARK],          # Cascabel neck
		[0.72, 0.155, COL_IRON_BASE],          # Breech ogee
		[0.64, 0.238, COL_IRON_BASE],
		[0.58, 0.278, COL_IRON_BAND],          # Base reinforcing astragal ring
		[0.52, 0.254, COL_IRON_BASE],          # First reinforce start
		[0.08, 0.228, COL_IRON_BASE],          # First reinforce end
		[0.03, 0.252, COL_IRON_BAND],          # First reinforce astragal band
		[-0.02, 0.222, COL_IRON_BASE],         # Second reinforce start
		[-0.52, 0.194, COL_IRON_BASE],         # Second reinforce end
		[-0.57, 0.214, COL_IRON_BAND],         # Chase astragal band
		[-0.62, 0.184, COL_IRON_BASE],         # Chase start
		[-1.34, 0.156, COL_IRON_BASE],         # Chase neck
		[-1.44, 0.196, COL_IRON_BAND],         # Muzzle astragal ring
		[-1.53, 0.216, COL_IRON_HIGHLIGHT],    # Tulip muzzle swell
		[MUZZLE_TIP_Z, 0.188, COL_IRON_DARK],  # Muzzle face outer rim
		[MUZZLE_TIP_Z, 0.118, COL_IRON_BORE],  # Muzzle bore inner lip
		[-1.08, 0.112, COL_IRON_BORE],         # Recessed dark bore depth
		[-1.06, 0.004, COL_IRON_BORE],         # Bore back cap
	]

	var radial_segs := 14
	for si in stations.size() - 1:
		var z0: float = float(stations[si][0])
		var r0: float = float(stations[si][1])
		var c0: Color = stations[si][2] as Color
		var z1: float = float(stations[si + 1][0])
		var r1: float = float(stations[si + 1][1])
		var c1: Color = stations[si + 1][2] as Color
		for ri in radial_segs:
			var a0 := TAU * float(ri) / float(radial_segs)
			var a1 := TAU * float(ri + 1) / float(radial_segs)
			var p00 := Vector3(cos(a0) * r0, sin(a0) * r0, z0)
			var p01 := Vector3(cos(a1) * r0, sin(a1) * r0, z0)
			var p10 := Vector3(cos(a0) * r1, sin(a0) * r1, z1)
			var p11 := Vector3(cos(a1) * r1, sin(a1) * r1, z1)
			# Slight top highlight / bottom crevice shade for painterly depth.
			var s0 := clampf(0.84 + 0.26 * sin(a0), 0.72, 1.12)
			var s1 := clampf(0.84 + 0.26 * sin(a1), 0.72, 1.12)
			var col00 := Color(c0.r * s0, c0.g * s0, c0.b * s0)
			var col01 := Color(c0.r * s1, c0.g * s1, c0.b * s1)
			var col10 := Color(c1.r * s0, c1.g * s0, c1.b * s0)
			var col11 := Color(c1.r * s1, c1.g * s1, c1.b * s1)
			_st_quad(st, p00, p01, p11, p10, col00, col01, col11, col10)

	# Forged cylindrical trunnions projecting laterally at z = 0 (pivot origin).
	_add_tube_segment(st, Vector3(-0.46, -0.02, 0.0), Vector3(0.46, -0.02, 0.0), 0.082, 10,
		COL_IRON_HIGHLIGHT, COL_IRON_DARK)

	# Small raised touchhole / vent priming boss atop the breech.
	_add_beveled_box(st, Vector3(0.0, 0.25, 0.56), Vector3(0.11, 0.055, 0.13), 0.015,
		COL_IRON_BAND, COL_IRON_BASE, COL_IRON_DARK)

	st.generate_normals()
	return st.commit()


func _build_cannonball_stack() -> Node3D:
	var root := Node3D.new()
	root.name = "CannonballPyramid"

	# Triangular chamfered oak shot garland frame cradling the 3 base balls.
	var garland_st := SurfaceTool.new()
	garland_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb_r := 0.34
	for i in 3:
		var a0 := TAU * float(i) / 3.0 + PI * 0.5
		var a1 := TAU * float(i + 1) / 3.0 + PI * 0.5
		var p0 := Vector3(cos(a0) * curb_r, 0.035, sin(a0) * curb_r)
		var p1 := Vector3(cos(a1) * curb_r, 0.035, sin(a1) * curb_r)
		_add_tube_segment(garland_st, p0, p1, 0.045, 6, COL_OAK_LIGHT, COL_OAK_DARK)
	garland_st.generate_normals()
	var curb_mi := MeshInstance3D.new()
	curb_mi.name = "ShotGarland"
	curb_mi.mesh = garland_st.commit()
	curb_mi.material_override = _oak_mat
	root.add_child(curb_mi)

	# Pyramid of 4 dark cast-iron cannonballs (3 equilateral base + 1 top).
	var ball_r := 0.125
	var base_ring := ball_r * 1.18
	var top_y := ball_r + ball_r * 1.633
	var ball_positions: Array[Vector3] = [
		Vector3(cos(0.0) * base_ring, ball_r, sin(0.0) * base_ring),
		Vector3(cos(TAU / 3.0) * base_ring, ball_r, sin(TAU / 3.0) * base_ring),
		Vector3(cos(TAU * 2.0 / 3.0) * base_ring, ball_r, sin(TAU * 2.0 / 3.0) * base_ring),
		Vector3(0.0, top_y, 0.0),
	]
	var sph := SphereMesh.new()
	sph.radius = ball_r
	sph.height = ball_r * 2.0
	sph.radial_segments = 10
	sph.rings = 6
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.12, 0.125, 0.14)
	ball_mat.metallic = 0.78
	ball_mat.roughness = 0.38
	for bi in ball_positions.size():
		var bm := MeshInstance3D.new()
		bm.name = "IronShot_%d" % bi
		bm.mesh = sph
		bm.material_override = ball_mat
		bm.position = ball_positions[bi]
		root.add_child(bm)

	return root


# ============================================================ muzzle VFX & textures

func _effects_enabled() -> bool:
	return enable_effects and is_inside_tree() and DisplayServer.get_name() != "headless"


func _spawn_muzzle_vfx(pos: Vector3, dir: Vector3) -> void:
	if not _effects_enabled():
		return
	var host := get_parent() if get_parent() != null else self

	var fx_root := Node3D.new()
	fx_root.name = "FortMuzzleVFX"
	host.add_child(fx_root)
	fx_root.global_position = pos
	_spawned_vfx.append(fx_root)

	# 1. Billowing feathered radial billboard black-powder smoke cloud.
	var smoke := GPUParticles3D.new()
	smoke.name = "MuzzleSmoke"
	smoke.one_shot = true
	smoke.explosiveness = 0.92
	smoke.amount = 26
	smoke.lifetime = 1.25
	smoke.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 12.0, 16.0))
	var s_proc := ParticleProcessMaterial.new()
	s_proc.direction = dir
	s_proc.spread = 32.0
	s_proc.initial_velocity_min = 3.8
	s_proc.initial_velocity_max = 12.5
	s_proc.damping_min = 3.2
	s_proc.damping_max = 6.2
	s_proc.gravity = Vector3(0.0, 1.5, 0.0)
	s_proc.scale_min = 0.95
	s_proc.scale_max = 2.15
	s_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.42), Vector2(0.32, 1.18), Vector2(1.0, 1.85)])
	s_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.14, 0.56, 1.0]),
		PackedColorArray([
			Color(0.98, 0.92, 0.80, 0.0),
			Color(0.88, 0.85, 0.80, 0.82),
			Color(0.68, 0.68, 0.69, 0.44),
			Color(0.54, 0.56, 0.58, 0.0),
		])
	)
	smoke.process_material = s_proc
	var s_quad := QuadMesh.new()
	s_quad.size = Vector2(1.45, 1.45)
	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	s_mat.vertex_color_use_as_albedo = true
	s_mat.albedo_texture = _get_smoke_puff_texture()
	s_quad.material = s_mat
	smoke.draw_pass_1 = s_quad
	fx_root.add_child(smoke)
	smoke.emitting = true

	# 2. Blazing additive radial golden muzzle flash.
	var flash := GPUParticles3D.new()
	flash.name = "MuzzleFlash"
	flash.one_shot = true
	flash.explosiveness = 0.98
	flash.amount = 6
	flash.lifetime = 0.24
	flash.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var f_proc := ParticleProcessMaterial.new()
	f_proc.direction = dir
	f_proc.spread = 22.0
	f_proc.initial_velocity_min = 1.5
	f_proc.initial_velocity_max = 5.5
	f_proc.gravity = Vector3.ZERO
	f_proc.scale_min = 1.05
	f_proc.scale_max = 1.85
	f_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.65), Vector2(0.28, 1.35), Vector2(1.0, 0.12)])
	flash.process_material = f_proc
	var f_quad := QuadMesh.new()
	f_quad.size = Vector2(1.65, 1.65)
	var f_mat := StandardMaterial3D.new()
	f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	f_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	f_mat.albedo_texture = _get_flash_radial_texture()
	f_quad.material = f_mat
	flash.draw_pass_1 = f_quad
	fx_root.add_child(flash)
	flash.emitting = true

	# 3. Hot burning powder spark streaks.
	var sparks := GPUParticles3D.new()
	sparks.name = "MuzzleSparks"
	sparks.one_shot = true
	sparks.explosiveness = 0.96
	sparks.amount = 24
	sparks.lifetime = 0.52
	sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var e_proc := ParticleProcessMaterial.new()
	e_proc.direction = dir
	e_proc.spread = 34.0
	e_proc.initial_velocity_min = 8.0
	e_proc.initial_velocity_max = 18.0
	e_proc.damping_min = 2.5
	e_proc.damping_max = 5.0
	e_proc.gravity = Vector3(0.0, -9.5, 0.0)
	e_proc.scale_min = 0.65
	e_proc.scale_max = 1.35
	e_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.30, 0.72, 1.0]),
		PackedColorArray([
			Color(1.0, 0.98, 0.84, 1.0),
			Color(1.0, 0.64, 0.16, 0.92),
			Color(0.95, 0.28, 0.05, 0.50),
			Color(0.70, 0.10, 0.02, 0.0),
		])
	)
	sparks.process_material = e_proc
	var e_quad := QuadMesh.new()
	e_quad.size = Vector2(0.08, 0.34)
	var e_mat := StandardMaterial3D.new()
	e_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	e_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	e_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	e_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	e_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	e_mat.vertex_color_use_as_albedo = true
	e_mat.albedo_texture = _get_spark_streak_texture()
	e_quad.material = e_mat
	sparks.draw_pass_1 = e_quad
	fx_root.add_child(sparks)
	sparks.emitting = true

	var cleanup := Timer.new()
	cleanup.wait_time = 1.45
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.timeout.connect(fx_root.queue_free)
	fx_root.add_child(cleanup)


func _prune_finished_vfx() -> void:
	if _spawned_vfx.is_empty():
		return
	var i := _spawned_vfx.size() - 1
	while i >= 0:
		if _spawned_vfx[i] == null or not is_instance_valid(_spawned_vfx[i]):
			_spawned_vfx.remove_at(i)
		i -= 1


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


static func _get_smoke_puff_texture() -> ImageTexture:
	if _smoke_puff_tex != null:
		return _smoke_puff_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	var lobes: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.88),
		Vector3(-0.24, -0.10, 0.56),
		Vector3(0.25, -0.06, 0.54),
		Vector3(0.04, 0.24, 0.52),
		Vector3(-0.14, 0.22, 0.44),
	]
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var density := 0.0
			for lobe in lobes:
				var dx := nx - lobe.x
				var dy := ny - lobe.y
				var r := sqrt(dx * dx + dy * dy) / lobe.z
				if r < 1.0:
					var w := 1.0 - r * r
					density = maxf(density, w * w)
			var outer := clampf(1.0 - sqrt(nx * nx + ny * ny), 0.0, 1.0)
			var alpha := clampf(density * smoothstep(0.0, 0.42, outer), 0.0, 1.0)
			var shade := lerpf(0.88, 1.0, density)
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	_smoke_puff_tex = ImageTexture.create_from_image(img)
	return _smoke_puff_tex


static func _get_spark_streak_texture() -> ImageTexture:
	if _spark_streak_tex != null:
		return _spark_streak_tex
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := absf(float(x) - half) / half
			var dy := absf(float(y) - half) / half
			var d := sqrt(dx * dx * 2.8 + dy * dy * 1.05)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.65)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_spark_streak_tex = ImageTexture.create_from_image(img)
	return _spark_streak_tex


static func _get_flash_radial_texture() -> GradientTexture2D:
	if _flash_radial_tex != null:
		return _flash_radial_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.24, 0.60, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.88, 1.0),
		Color(1.0, 0.74, 0.24, 0.84),
		Color(0.95, 0.36, 0.06, 0.28),
		Color(0.80, 0.14, 0.02, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.width = 48
	tex.height = 48
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.gradient = grad
	_flash_radial_tex = tex
	return _flash_radial_tex


# ============================================================ SurfaceTool geometry builders

static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


static func _st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_st_tri(st, a, b, c, ca, cb, cc)
	_st_tri(st, a, c, d, ca, cc, cd)


static func _add_beveled_box(st: SurfaceTool, center: Vector3, size: Vector3, bevel: float,
		col_top: Color, col_side: Color, col_bot: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var bx := minf(bevel, hx * 0.45)
	var by := minf(bevel, hy * 0.45)
	var bz := minf(bevel, hz * 0.45)
	# Top chamfered cap & bottom chamfered base with crisp beveled rim slopes.
	var t_in := [
		center + Vector3(-hx + bx, hy, -hz + bz),
		center + Vector3(hx - bx, hy, -hz + bz),
		center + Vector3(hx - bx, hy, hz - bz),
		center + Vector3(-hx + bx, hy, hz - bz),
	]
	var t_out := [
		center + Vector3(-hx, hy - by, -hz),
		center + Vector3(hx, hy - by, -hz),
		center + Vector3(hx, hy - by, hz),
		center + Vector3(-hx, hy - by, hz),
	]
	var b_out := [
		center + Vector3(-hx, -hy + by, -hz),
		center + Vector3(hx, -hy + by, -hz),
		center + Vector3(hx, -hy + by, hz),
		center + Vector3(-hx, -hy + by, hz),
	]
	var b_in := [
		center + Vector3(-hx + bx, -hy, -hz + bz),
		center + Vector3(hx - bx, -hy, -hz + bz),
		center + Vector3(hx - bx, -hy, hz - bz),
		center + Vector3(-hx + bx, -hy, hz - bz),
	]
	# Top & bottom flat faces (CW looking from outside -> Godot front face).
	_st_quad(st, t_in[0], t_in[1], t_in[2], t_in[3], col_top, col_top, col_top, col_top)
	_st_quad(st, b_in[0], b_in[3], b_in[2], b_in[1], col_bot, col_bot, col_bot, col_bot)
	var col_bev := col_top.lerp(col_side, 0.45)
	for i in 4:
		var j := (i + 1) % 4
		# Upper bevel
		_st_quad(st, t_out[i], t_out[j], t_in[j], t_in[i], col_bev, col_bev, col_top, col_top)
		# Vertical side
		_st_quad(st, b_out[i], b_out[j], t_out[j], t_out[i], col_bot, col_bot, col_side, col_side)
		# Lower bevel
		_st_quad(st, b_in[i], b_in[j], b_out[j], b_out[i], col_bot, col_bot, col_bot, col_bot)


static func _add_extruded_zy_profile(st: SurfaceTool, poly_zy: Array[Vector2],
		x_min: float, x_max: float, col_top: Color, col_mid: Color, col_bot: Color) -> void:
	var n := poly_zy.size()
	if n < 3:
		return
	var min_y := INF
	var max_y := -INF
	var packed := PackedVector2Array()
	packed.resize(n)
	for i in n:
		var p := poly_zy[i]
		packed[i] = p
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var span_y := maxf(max_y - min_y, 0.001)

	# Exact ear-clipping triangulation handles concave steps & trunnion cradles cleanly.
	var tris := Geometry2D.triangulate_polygon(packed)
	for ti in range(0, tris.size(), 3):
		var a := packed[tris[ti]]
		var b := packed[tris[ti + 1]]
		var c := packed[tris[ti + 2]]
		# Ensure (a, b, c) is CCW in (z, y) so +X face (c - a) x (b - a) points along +X.
		var area2 := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if area2 < 0.0:
			var tmp := b
			b = c
			c = tmp
		var ca := col_bot.lerp(col_top, clampf((a.y - min_y) / span_y, 0.0, 1.0))
		var cb := col_bot.lerp(col_top, clampf((b.y - min_y) / span_y, 0.0, 1.0))
		var cc := col_bot.lerp(col_top, clampf((c.y - min_y) / span_y, 0.0, 1.0))
		# +X face
		_st_tri(st,
			Vector3(x_max, a.y, a.x),
			Vector3(x_max, b.y, b.x),
			Vector3(x_max, c.y, c.x),
			ca, cb, cc)
		# -X face
		_st_tri(st,
			Vector3(x_min, a.y, a.x),
			Vector3(x_min, c.y, c.x),
			Vector3(x_min, b.y, b.x),
			ca, cc, cb)

	# Perimeter rim wall around the extruded cheek profile.
	for i in n:
		var j := (i + 1) % n
		var p0 := poly_zy[i]
		var p1 := poly_zy[j]
		var c0 := col_bot.lerp(col_top, clampf((p0.y - min_y) / span_y, 0.0, 1.0)).lerp(col_mid, 0.3)
		var c1 := col_bot.lerp(col_top, clampf((p1.y - min_y) / span_y, 0.0, 1.0)).lerp(col_mid, 0.3)
		_st_quad(st,
			Vector3(x_min, p0.y, p0.x),
			Vector3(x_min, p1.y, p1.x),
			Vector3(x_max, p1.y, p1.x),
			Vector3(x_max, p0.y, p0.x),
			c0, c1, c1, c0)


static func _add_tube_segment(st: SurfaceTool, a: Vector3, b: Vector3, radius: float,
		segs: int, col_hi: Color, col_lo: Color) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.0001:
		return
	var dir := axis / length
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	for i in segs:
		var ang0 := TAU * float(i) / float(segs)
		var ang1 := TAU * float(i + 1) / float(segs)
		var off0 := (u * cos(ang0) + v * sin(ang0)) * radius
		var off1 := (u * cos(ang1) + v * sin(ang1)) * radius
		var shade0 := clampf(0.5 + 0.5 * off0.normalized().y, 0.0, 1.0)
		var shade1 := clampf(0.5 + 0.5 * off1.normalized().y, 0.0, 1.0)
		var c0 := col_lo.lerp(col_hi, shade0)
		var c1 := col_lo.lerp(col_hi, shade1)
		_st_quad(st, a + off0, b + off0, b + off1, a + off1, c0, c0, c1, c1)
		_st_tri(st, a, a + off0, a + off1, col_lo, c0, c1)
		_st_tri(st, b, b + off1, b + off0, col_hi, c1, c0)
