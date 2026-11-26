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
## Toggle cinematic water-geyser & hull splinter/ember particle VFX.
@export var enable_effects: bool = true

## Shooter references ignored during the initial SELF_IGNORE_TIME window.
var shooter_ship: Node3D = null
var shooter_pawn: Node = null

## Godot 4.8 Trail3D smoke/tracer ribbon attached to the ball.
var trail: Trail3D = null

var _ball_mesh: MeshInstance3D = null
var _age: float = 0.0
var _impacted: bool = false
var _cleanup_timer: float = 0.0
var _spawned_vfx: Array[Node] = []
var _ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ray_result: PhysicsIntersectRayResult3D = PhysicsIntersectRayResult3D.new()
var _exclude_rids: Array[RID] = []

static var _foam_puff_tex: ImageTexture = null
static var _streak_tex: ImageTexture = null
static var _flash_tex: GradientTexture2D = null


func _exit_tree() -> void:
	for fx in _spawned_vfx:
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
	_spawned_vfx.clear()


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
	var cleanup_delay := 0.5

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
		if _spawn_splinter_burst(hit_pos, hit_normal):
			cleanup_delay = 1.15
		Audio.play_sfx(&"hull_impact", hit_pos)
	elif target != null and target.has_meta("leviathan"):
		var lev: Variant = target.get_meta("leviathan")
		if Net.is_host() and lev != null and is_instance_valid(lev) and (lev as Object).has_method(&"damage_tentacle"):
			var t_idx := int(target.get_meta("tentacle_index", -1))
			(lev as Object).call(&"damage_tentacle", t_idx, pawn_damage)
		if _spawn_dust_burst(hit_pos, hit_normal, Color(0.24, 0.72, 0.68)):
			cleanup_delay = 0.8
		Audio.play_sfx(&"hit_flesh", hit_pos)
	elif target != null and target.has_method(&"apply_damage"):
		if Net.is_host():
			target.call(&"apply_damage", pawn_damage, shooter_pawn)
		if _spawn_dust_burst(hit_pos, hit_normal, Color(0.85, 0.72, 0.56)):
			cleanup_delay = 0.8
		Audio.play_sfx(&"hit_flesh", hit_pos)
	else:
		if _spawn_dust_burst(hit_pos, hit_normal, Color(0.76, 0.74, 0.68)):
			cleanup_delay = 0.8
		Audio.play_sfx(&"hull_impact", hit_pos, -4.0)

	_mark_impacted(hit_pos, target, cleanup_delay)


func _on_water_hit(hit_pos: Vector3) -> void:
	global_position = hit_pos
	if Ocean.current != null:
		Ocean.current.add_foam(hit_pos, 3.2, 0.95)
	var spawned := _spawn_splash_burst(hit_pos)
	Audio.play_sfx(&"splash_large", hit_pos)
	_mark_impacted(hit_pos, null, 1.65 if spawned else 0.5)


func _mark_impacted(hit_pos: Vector3, target: Node, cleanup_delay: float = 0.5) -> void:
	_impacted = true
	_cleanup_timer = cleanup_delay
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


func _effects_enabled() -> bool:
	if not enable_effects or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return false
	if shooter_ship != null and is_instance_valid(shooter_ship):
		var ship_fx: Variant = shooter_ship.get(&"enable_effects")
		if ship_fx is bool and not ship_fx:
			return false
	return true


func _attach_vfx(fx_root: Node3D, world_pos: Vector3, auto_free_sec: float) -> void:
	add_child(fx_root)
	fx_root.global_position = world_pos
	_spawned_vfx.append(fx_root)
	var cleanup := Timer.new()
	cleanup.wait_time = auto_free_sec
	cleanup.one_shot = true
	cleanup.autostart = true
	cleanup.timeout.connect(fx_root.queue_free)
	fx_root.add_child(cleanup)


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


static func _get_foam_puff_texture() -> ImageTexture:
	if _foam_puff_tex != null:
		return _foam_puff_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	# Multi-lobe feathered cloud silhouette so foam plumes billow softly without hard edges.
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
	_foam_puff_tex = ImageTexture.create_from_image(img)
	return _foam_puff_tex


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
			var d := sqrt(dx * dx * 2.8 + dy * dy * 1.05)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.65)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_streak_tex = ImageTexture.create_from_image(img)
	return _streak_tex


static func _get_flash_texture() -> GradientTexture2D:
	if _flash_tex != null:
		return _flash_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.88, 1.0),
		Color(1.0, 0.72, 0.22, 0.80),
		Color(0.95, 0.34, 0.06, 0.25),
		Color(0.80, 0.14, 0.02, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.width = 48
	tex.height = 48
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.gradient = grad
	_flash_tex = tex
	return _flash_tex


func _spawn_splash_burst(pos: Vector3) -> bool:
	if not _effects_enabled():
		return false

	var fx_root := Node3D.new()
	fx_root.name = "WaterGeyserPlume"

	# 1. Tall dramatic rising feathered white-foam geyser column.
	var col_p := GPUParticles3D.new()
	col_p.name = "GeyserColumn"
	col_p.one_shot = true
	col_p.explosiveness = 0.86
	col_p.amount = 36
	col_p.lifetime = 1.48
	col_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	col_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	col_p.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 18.0, 16.0))

	var col_proc := ParticleProcessMaterial.new()
	col_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	col_proc.emission_ring_radius = 0.55
	col_proc.emission_ring_inner_radius = 0.12
	col_proc.emission_ring_height = 0.22
	col_proc.emission_ring_axis = Vector3.UP
	col_proc.direction = Vector3.UP
	col_proc.spread = 11.0
	col_proc.initial_velocity_min = 9.5
	col_proc.initial_velocity_max = 18.5
	col_proc.damping_min = 1.2
	col_proc.damping_max = 2.4
	col_proc.gravity = Vector3(0.0, -16.5, 0.0)
	col_proc.scale_min = 1.05
	col_proc.scale_max = 2.45
	col_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.55), Vector2(0.32, 1.25), Vector2(1.0, 1.75)])
	col_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.12, 0.55, 1.0]),
		PackedColorArray([
			Color(0.95, 0.99, 1.0, 0.0),
			Color(0.94, 0.99, 1.0, 0.84),
			Color(0.84, 0.96, 0.98, 0.56),
			Color(0.76, 0.92, 0.96, 0.0),
		])
	)
	col_p.process_material = col_proc

	var col_quad := QuadMesh.new()
	col_quad.size = Vector2(1.45, 2.05)
	var col_mat := StandardMaterial3D.new()
	col_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	col_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	col_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	col_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	col_mat.vertex_color_use_as_albedo = true
	col_mat.albedo_texture = _get_foam_puff_texture()
	col_quad.material = col_mat
	col_p.draw_pass_1 = col_quad
	fx_root.add_child(col_p)
	col_p.emitting = true

	# 2. Radiating sparkling water droplet spray fan.
	var drop_p := GPUParticles3D.new()
	drop_p.name = "DropletSpray"
	drop_p.one_shot = true
	drop_p.explosiveness = 0.94
	drop_p.amount = 48
	drop_p.lifetime = 1.28
	drop_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	drop_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drop_p.visibility_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 16.0, 24.0))

	var drop_proc := ParticleProcessMaterial.new()
	drop_proc.direction = Vector3.UP
	drop_proc.spread = 38.0
	drop_proc.initial_velocity_min = 7.5
	drop_proc.initial_velocity_max = 16.0
	drop_proc.gravity = Vector3(0.0, -20.0, 0.0)
	drop_proc.scale_min = 0.55
	drop_proc.scale_max = 1.25
	drop_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.14, 0.65, 1.0]),
		PackedColorArray([
			Color(0.98, 1.0, 1.0, 0.95),
			Color(0.90, 0.98, 1.0, 0.85),
			Color(0.78, 0.94, 0.97, 0.45),
			Color(0.72, 0.90, 0.95, 0.0),
		])
	)
	drop_p.process_material = drop_proc

	var drop_quad := QuadMesh.new()
	drop_quad.size = Vector2(0.18, 0.72)
	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	drop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	drop_mat.vertex_color_use_as_albedo = true
	drop_mat.albedo_texture = _get_streak_texture()
	drop_quad.material = drop_mat
	drop_p.draw_pass_1 = drop_quad
	fx_root.add_child(drop_p)
	drop_p.emitting = true

	# 3. Frothy sea-level splash crown anchoring the column into the ocean foam ring.
	var crown_p := GPUParticles3D.new()
	crown_p.name = "SplashCrown"
	crown_p.one_shot = true
	crown_p.explosiveness = 0.95
	crown_p.amount = 20
	crown_p.lifetime = 0.92
	crown_p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	crown_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown_p.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 8.0, 16.0))

	var crown_proc := ParticleProcessMaterial.new()
	crown_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	crown_proc.emission_ring_radius = 1.15
	crown_proc.emission_ring_inner_radius = 0.45
	crown_proc.emission_ring_height = 0.15
	crown_proc.emission_ring_axis = Vector3.UP
	crown_proc.direction = Vector3.UP
	crown_proc.spread = 68.0
	crown_proc.initial_velocity_min = 3.2
	crown_proc.initial_velocity_max = 7.2
	crown_proc.damping_min = 2.0
	crown_proc.damping_max = 4.0
	crown_proc.gravity = Vector3(0.0, -11.0, 0.0)
	crown_proc.scale_min = 0.9
	crown_proc.scale_max = 1.85
	crown_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.65), Vector2(0.4, 1.3), Vector2(1.0, 1.65)])
	crown_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.15, 0.65, 1.0]),
		PackedColorArray([
			Color(0.95, 0.99, 1.0, 0.0),
			Color(0.92, 0.98, 1.0, 0.72),
			Color(0.82, 0.95, 0.97, 0.36),
			Color(0.75, 0.92, 0.96, 0.0),
		])
	)
	crown_p.process_material = crown_proc
	crown_p.draw_pass_1 = col_quad
	fx_root.add_child(crown_p)
	crown_p.emitting = true

	_attach_vfx(fx_root, pos, 1.6)
	return true


func _spawn_splinter_burst(pos: Vector3, normal: Vector3) -> bool:
	if not _effects_enabled():
		return false

	var dir := normal if normal.length_squared() > 0.01 else Vector3.UP
	var fx_root := Node3D.new()
	fx_root.name = "HullImpactBurst"

	# 1. Fiery velocity-aligned ember spark shower.
	var embers := GPUParticles3D.new()
	embers.name = "EmberSparks"
	embers.one_shot = true
	embers.explosiveness = 0.96
	embers.amount = 34
	embers.lifetime = 0.68
	embers.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.visibility_aabb = AABB(Vector3(-8.0, -6.0, -8.0), Vector3(16.0, 14.0, 16.0))

	var e_proc := ParticleProcessMaterial.new()
	e_proc.direction = (dir + Vector3.UP * 0.25).normalized()
	e_proc.spread = 65.0
	e_proc.initial_velocity_min = 5.0
	e_proc.initial_velocity_max = 13.5
	e_proc.damping_min = 1.6
	e_proc.damping_max = 3.5
	e_proc.gravity = Vector3(0.0, -14.0, 0.0)
	e_proc.scale_min = 0.65
	e_proc.scale_max = 1.45
	e_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.25, 0.68, 1.0]),
		PackedColorArray([
			Color(1.0, 0.98, 0.82, 1.0),
			Color(1.0, 0.58, 0.12, 0.94),
			Color(0.92, 0.22, 0.04, 0.55),
			Color(0.65, 0.08, 0.02, 0.0),
		])
	)
	embers.process_material = e_proc

	var e_quad := QuadMesh.new()
	e_quad.size = Vector2(0.085, 0.36)
	var e_mat := StandardMaterial3D.new()
	e_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	e_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	e_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	e_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	e_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	e_mat.vertex_color_use_as_albedo = true
	e_mat.albedo_texture = _get_streak_texture()
	e_quad.material = e_mat
	embers.draw_pass_1 = e_quad
	fx_root.add_child(embers)
	embers.emitting = true

	# 2. Core fiery impact flash & dark timber powder smoke.
	var flash := GPUParticles3D.new()
	flash.name = "ImpactFlash"
	flash.one_shot = true
	flash.explosiveness = 0.98
	flash.amount = 6
	flash.lifetime = 0.30
	flash.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var f_proc := ParticleProcessMaterial.new()
	f_proc.direction = dir
	f_proc.spread = 45.0
	f_proc.initial_velocity_min = 0.6
	f_proc.initial_velocity_max = 2.4
	f_proc.gravity = Vector3(0.0, 1.5, 0.0)
	f_proc.scale_min = 0.85
	f_proc.scale_max = 1.45
	f_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.45), Vector2(0.30, 1.35), Vector2(1.0, 0.15)])
	flash.process_material = f_proc
	var f_quad := QuadMesh.new()
	f_quad.size = Vector2(1.35, 1.35)
	var f_mat := StandardMaterial3D.new()
	f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	f_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	f_mat.albedo_texture = _get_flash_texture()
	f_quad.material = f_mat
	flash.draw_pass_1 = f_quad
	fx_root.add_child(flash)
	flash.emitting = true

	var smoke := GPUParticles3D.new()
	smoke.name = "ImpactSmoke"
	smoke.one_shot = true
	smoke.explosiveness = 0.90
	smoke.amount = 12
	smoke.lifetime = 0.88
	smoke.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s_proc := ParticleProcessMaterial.new()
	s_proc.direction = (dir + Vector3.UP * 0.35).normalized()
	s_proc.spread = 48.0
	s_proc.initial_velocity_min = 1.8
	s_proc.initial_velocity_max = 5.2
	s_proc.damping_min = 2.0
	s_proc.damping_max = 4.0
	s_proc.gravity = Vector3(0.0, 1.6, 0.0)
	s_proc.scale_min = 0.75
	s_proc.scale_max = 1.55
	s_proc.scale_curve = _make_scale_curve([Vector2(0.0, 0.55), Vector2(0.45, 1.25), Vector2(1.0, 1.75)])
	s_proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.16, 0.65, 1.0]),
		PackedColorArray([
			Color(0.55, 0.44, 0.32, 0.0),
			Color(0.40, 0.35, 0.30, 0.62),
			Color(0.28, 0.26, 0.24, 0.32),
			Color(0.22, 0.22, 0.22, 0.0),
		])
	)
	smoke.process_material = s_proc
	var s_quad := QuadMesh.new()
	s_quad.size = Vector2(1.15, 1.15)
	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	s_mat.vertex_color_use_as_albedo = true
	s_mat.albedo_texture = _get_foam_puff_texture()
	s_quad.material = s_mat
	smoke.draw_pass_1 = s_quad
	fx_root.add_child(smoke)
	smoke.emitting = true

	# 3. Flying rotating oak timber splinters.
	var splinters := GPUParticles3D.new()
	splinters.name = "WoodSplinters"
	splinters.one_shot = true
	splinters.explosiveness = 0.95
	splinters.amount = 34
	splinters.lifetime = 0.98
	splinters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splinters.visibility_aabb = AABB(Vector3(-8.0, -6.0, -8.0), Vector3(16.0, 14.0, 16.0))

	var w_proc := ParticleProcessMaterial.new()
	w_proc.direction = (dir + Vector3.UP * 0.42).normalized()
	w_proc.spread = 54.0
	w_proc.initial_velocity_min = 4.5
	w_proc.initial_velocity_max = 12.0
	w_proc.angular_velocity_min = -14.0
	w_proc.angular_velocity_max = 14.0
	w_proc.gravity = Vector3(0.0, -16.0, 0.0)
	w_proc.scale_min = 0.55
	w_proc.scale_max = 1.55
	w_proc.scale_curve = _make_scale_curve([Vector2(0.0, 1.0), Vector2(0.75, 0.92), Vector2(1.0, 0.0)])
	splinters.process_material = w_proc

	var w_mesh := BoxMesh.new()
	w_mesh.size = Vector3(0.065, 0.038, 0.42)
	var w_mat := StandardMaterial3D.new()
	w_mat.albedo_color = Color(0.64, 0.41, 0.20)
	w_mat.roughness = 0.86
	w_mesh.material = w_mat
	splinters.draw_pass_1 = w_mesh
	fx_root.add_child(splinters)
	splinters.emitting = true

	_attach_vfx(fx_root, pos + dir * 0.12, 1.1)
	return true


func _spawn_dust_burst(pos: Vector3, normal: Vector3, tint: Color) -> bool:
	if not _effects_enabled():
		return false

	var dir := normal if normal.length_squared() > 0.01 else Vector3.UP
	var fx_root := Node3D.new()
	fx_root.name = "ImpactPuff"

	var p := GPUParticles3D.new()
	p.name = "DustCloud"
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 16
	p.lifetime = 0.68
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = (dir + Vector3.UP * 0.35).normalized()
	proc.spread = 52.0
	proc.initial_velocity_min = 2.0
	proc.initial_velocity_max = 6.5
	proc.gravity = Vector3(0.0, -8.0, 0.0)
	proc.scale_min = 0.55
	proc.scale_max = 1.25
	proc.color_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.2, 1.0]),
		PackedColorArray([
			Color(tint.r, tint.g, tint.b, 0.0),
			Color(tint.r, tint.g, tint.b, 0.74),
			Color(tint.r, tint.g, tint.b, 0.0),
		])
	)
	p.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.85)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_foam_puff_texture()
	quad.material = mat
	p.draw_pass_1 = quad
	fx_root.add_child(p)
	p.emitting = true

	_attach_vfx(fx_root, pos + dir * 0.1, 0.75)
	return true
