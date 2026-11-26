class_name Cannonball
extends Node3D
## Ballistic iron cannonball projectile.
##
## Host-authoritative hit resolution using Godot 4.8 non-allocating swept rays
## (`PhysicsDirectSpaceState3D.intersect_ray_into`) each physics tick so high-
## velocity shots never tunnel through hulls, terrain, or pawns. Uses Godot 4.8
## `Trail3D` for a crisp smoke/tracer streak.

signal impacted(hit_pos: Vector3, target: Node)

## Collision layer 5 (projectiles) per docs/ARCHITECTURE.md.
const COLLISION_LAYER := 1 << 4
## Swept ray tests against world static (1), ships (2), and pawns (3).
const HIT_MASK := 1 | (1 << 1) | (1 << 2)
const GRAVITY := 9.81
const SELF_IGNORE_TIME := 0.2
const MAX_LIFETIME := 12.0

## World-space velocity (m/s).
var velocity: Vector3 = Vector3.ZERO
## Linear aerodynamic drag coefficient (1/s).
@export var drag: float = 0.012
## Breach radius passed to `Ship.apply_hull_damage()`.
@export var hull_damage_radius: float = 0.45
## Damage dealt on a direct hit to a `Pawn`.
@export var pawn_damage: float = 55.0
## Impulse magnitude applied to a struck `RigidBody3D` ship hull (N*s).
@export var hull_impact_impulse: float = 6500.0

## Shooter references ignored during the initial SELF_IGNORE_TIME window.
var shooter_ship: Node3D = null
var shooter_pawn: Node = null

## Godot 4.8 Trail3D smoke/tracer ribbon attached to the ball.
var trail: Trail3D = null

var _ball_mesh: MeshInstance3D = null
var _age: float = 0.0
var _impacted: bool = false
var _cleanup_timer: float = 0.0
var _ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ray_result: PhysicsIntersectRayResult3D = PhysicsIntersectRayResult3D.new()
var _exclude_rids: Array[RID] = []


func _ready() -> void:
	_build_visuals()
	_ray_params.collision_mask = HIT_MASK
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true
	_refresh_exclusions()


func _build_visuals() -> void:
	_ball_mesh = MeshInstance3D.new()
	_ball_mesh.name = "IronBall"
	var sphere := SphereMesh.new()
	sphere.radius = 0.115
	sphere.height = 0.23
	sphere.radial_segments = 12
	sphere.rings = 6
	_ball_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.115, 0.13)
	mat.metallic = 0.72
	mat.roughness = 0.42
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.12)
	mat.emission_energy_multiplier = 0.35
	_ball_mesh.material_override = mat
	add_child(_ball_mesh)

	trail = Trail3D.new()
	trail.name = "SmokeTrail"
	trail.limit_mode = Trail3D.LIMIT_MODE_LIFETIME
	trail.lifetime = 0.45
	trail.min_section_length = 0.14
	trail.width = 0.26
	trail.mesh_alignment = Trail3D.MESH_ALIGNMENT_BILLBOARD
	trail.material_mode = Trail3D.MATERIAL_MODE_MIX
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 1.0))
	width_curve.add_point(Vector2(0.55, 0.65))
	width_curve.add_point(Vector2(1.0, 0.12))
	trail.width_curve = width_curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.96, 0.92, 0.84, 0.78))
	grad.add_point(0.35, Color(0.76, 0.77, 0.78, 0.45))
	grad.set_color(grad.get_point_count() - 1, Color(0.55, 0.58, 0.62, 0.0))
	trail.color_gradient = grad
	trail.emitting = true
	add_child(trail)


func _refresh_exclusions() -> void:
	_exclude_rids.clear()
	if _age < SELF_IGNORE_TIME:
		if shooter_ship is CollisionObject3D and is_instance_valid(shooter_ship):
			_exclude_rids.append((shooter_ship as CollisionObject3D).get_rid())
		if shooter_pawn is CollisionObject3D and is_instance_valid(shooter_pawn):
			_exclude_rids.append((shooter_pawn as CollisionObject3D).get_rid())
	_ray_params.exclude = _exclude_rids


func _physics_process(delta: float) -> void:
	if _impacted:
		_cleanup_timer -= delta
		if _cleanup_timer <= 0.0:
			queue_free()
		return

	_age += delta
	if _age >= MAX_LIFETIME:
		_finish_without_impact()
		return

	# Fade initial hot-powder glow shortly after leaving the muzzle.
	if _age < 0.35 and _ball_mesh != null:
		var mat := _ball_mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = maxf(0.0, 0.35 * (1.0 - _age / 0.35))

	velocity.y -= GRAVITY * delta
	velocity *= maxf(0.0, 1.0 - drag * delta)

	var from := global_position
	var to := from + velocity * delta

	var world := get_world_3d()
	if world != null:
		_refresh_exclusions()
		_ray_params.from = from
		_ray_params.to = to
		if world.direct_space_state.intersect_ray_into(_ray_params, _ray_result):
			_on_solid_hit(_ray_result.position, _ray_result.normal, _ray_result.collider)
			return

	var sea_y := Sea.height(to.x, to.z)
	if to.y <= sea_y:
		var prev_above := from.y - Sea.height(from.x, from.z)
		var next_below := sea_y - to.y
		var frac := clampf(prev_above / maxf(prev_above + next_below, 0.001), 0.0, 1.0)
		var hit_pos := from.lerp(to, frac)
		hit_pos.y = Sea.height(hit_pos.x, hit_pos.z)
		_on_water_hit(hit_pos)
		return

	global_position = to


func _on_solid_hit(hit_pos: Vector3, hit_normal: Vector3, collider: Object) -> void:
	global_position = hit_pos
	var target: Node = collider as Node
	var ship_target := _find_ship(target)

	if ship_target != null:
		target = ship_target
		if Net.is_host():
			if ship_target.has_method(&"apply_hull_damage"):
				ship_target.call(&"apply_hull_damage", hit_pos, hull_damage_radius)
			if ship_target is RigidBody3D:
				var rb := ship_target as RigidBody3D
				var imp_dir := velocity.normalized() if velocity.length_squared() > 0.01 else -hit_normal
				var rel_pos := hit_pos - rb.global_position
				# Keep vertical lever arm modest so a hit rocks the ship cleanly without flipping it.
				rel_pos.y = clampf(rel_pos.y, -1.5, 1.5)
				rb.apply_impulse(imp_dir * hull_impact_impulse, rel_pos)
		_spawn_splinter_burst(hit_pos, hit_normal)
		Audio.play_sfx(&"hull_impact", hit_pos)
	elif target != null and target.has_method(&"apply_damage"):
		if Net.is_host():
			target.call(&"apply_damage", pawn_damage, shooter_pawn)
		_spawn_dust_burst(hit_pos, hit_normal, Color(0.85, 0.72, 0.56))
		Audio.play_sfx(&"hit_flesh", hit_pos)
	else:
		_spawn_dust_burst(hit_pos, hit_normal, Color(0.76, 0.74, 0.68))
		Audio.play_sfx(&"hull_impact", hit_pos, -4.0)

	_mark_impacted(hit_pos, target)


func _on_water_hit(hit_pos: Vector3) -> void:
	global_position = hit_pos
	if Ocean.current != null:
		Ocean.current.add_foam(hit_pos, 3.2, 0.95)
	_spawn_splash_burst(hit_pos)
	Audio.play_sfx(&"splash_large", hit_pos)
	_mark_impacted(hit_pos, null)


func _mark_impacted(hit_pos: Vector3, target: Node) -> void:
	_impacted = true
	_cleanup_timer = 0.5
	if _ball_mesh != null:
		_ball_mesh.visible = false
	if trail != null:
		trail.emitting = false
	impacted.emit(hit_pos, target)


func _finish_without_impact() -> void:
	_impacted = true
	_cleanup_timer = 0.1
	if _ball_mesh != null:
		_ball_mesh.visible = false
	if trail != null:
		trail.emitting = false


static func _find_ship(node: Node) -> Node3D:
	var n := node
	while n != null:
		if n is Node3D and (n.is_in_group(&"ship") or n.has_method(&"apply_hull_damage")):
			return n as Node3D
		n = n.get_parent()
	return null


func _spawn_splash_burst(pos: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return
	var p := GPUParticles3D.new()
	p.name = "WaterSplash"
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 28
	p.lifetime = 0.95
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 28.0
	proc.initial_velocity_min = 6.5
	proc.initial_velocity_max = 13.5
	proc.gravity = Vector3(0.0, -18.0, 0.0)
	proc.scale_min = 0.45
	proc.scale_max = 1.25
	proc.color = Color(0.86, 0.97, 0.98, 0.9)
	p.process_material = proc

	var mesh := SphereMesh.new()
	mesh.radius = 0.24
	mesh.height = 0.48
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.88, 0.97, 0.98, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.draw_pass_1 = mesh

	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func _spawn_splinter_burst(pos: Vector3, normal: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return
	var p := GPUParticles3D.new()
	p.name = "WoodSplinters"
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 24
	p.lifetime = 0.85
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var dir := normal if normal.length_squared() > 0.01 else Vector3.UP
	var proc := ParticleProcessMaterial.new()
	proc.direction = (dir + Vector3.UP * 0.4).normalized()
	proc.spread = 48.0
	proc.initial_velocity_min = 3.5
	proc.initial_velocity_max = 9.5
	proc.angular_velocity_min = -8.0
	proc.angular_velocity_max = 8.0
	proc.gravity = Vector3(0.0, -15.0, 0.0)
	proc.scale_min = 0.6
	proc.scale_max = 1.4
	p.process_material = proc

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.04, 0.34)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.68, 0.44, 0.24)
	mat.roughness = 0.85
	mesh.material = mat
	p.draw_pass_1 = mesh

	host.add_child(p)
	p.global_position = pos + dir * 0.1
	p.emitting = true
	p.finished.connect(p.queue_free)


func _spawn_dust_burst(pos: Vector3, normal: Vector3, tint: Color) -> void:
	var host := get_parent()
	if host == null:
		return
	var p := GPUParticles3D.new()
	p.name = "ImpactPuff"
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 16
	p.lifetime = 0.7
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var dir := normal if normal.length_squared() > 0.01 else Vector3.UP
	var proc := ParticleProcessMaterial.new()
	proc.direction = (dir + Vector3.UP * 0.35).normalized()
	proc.spread = 52.0
	proc.initial_velocity_min = 2.0
	proc.initial_velocity_max = 6.5
	proc.gravity = Vector3(0.0, -8.0, 0.0)
	proc.scale_min = 0.5
	proc.scale_max = 1.2
	p.process_material = proc

	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 6
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.95
	mesh.material = mat
	p.draw_pass_1 = mesh

	host.add_child(p)
	p.global_position = pos + dir * 0.1
	p.emitting = true
	p.finished.connect(p.queue_free)
