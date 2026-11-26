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
const FLARE_BURN_DURATION := 9.0
const FLARE_MAX_LIFETIME := 11.5
const CHAINSHOT_BREACH_RADIUS := 0.18
const CHAINSHOT_SAIL_DAMAGE := 14.0
const FIREBOMB_SPLASH_DAMAGE := 12.0
const FIREBOMB_SPLASH_RADIUS := 4.2

## World-space velocity (m/s).
var velocity: Vector3 = Vector3.ZERO
## Linear aerodynamic drag coefficient (1/s).
@export var drag: float = 0.012
## Breach radius passed to `Ship.apply_hull_damage()`.
@export var hull_damage_radius: float = 0.45
## Sculpted ordnance variant: &"iron", &"heavy", &"swivel", &"chainshot", &"firebomb", or &"flare".
@export var ordnance_style: StringName = &"iron"
## Damage dealt on a direct hit to a `Pawn`.
@export var pawn_damage: float = 55.0
## Impulse magnitude applied to a struck `RigidBody3D` ship hull (N*s).
@export var hull_impact_impulse: float = 6500.0
## Toggle cinematic water-geyser & hull splinter/ember particle VFX.
@export var enable_effects: bool = true

## Shooter references ignored during the initial SELF_IGNORE_TIME window.
var shooter_ship: Node3D = null
var shooter_pawn: Node = null

## Optional Godot 4.8 Trail3D smoke/tracer ribbon attached to the ball (gracefully skipped on Godot 4.7.x).
var trail: Node3D = null
## Signal flare illumination OmniLight3D (only active when ordnance_style resolves to &"flare").
var flare_light: OmniLight3D = null
## Warm flickering travel OmniLight3D (only active when ordnance_style resolves to &"firebomb").
var firebomb_light: OmniLight3D = null

var _ball_mesh: MeshInstance3D = null
var _ball_mat: StandardMaterial3D = null
var _core_glow_mat: StandardMaterial3D = null
var _resolved_style: StringName = &"iron"
var _base_muzzle_emission: float = 0.35
var _age: float = 0.0
var _flare_floating: bool = false
var _flare_burn_elapsed: float = 0.0
var _impacted: bool = false
var _cleanup_timer: float = 0.0
var _spawned_vfx: Array[Node] = []
var _ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ray_result: Variant = ClassDB.instantiate(&"PhysicsIntersectRayResult3D") if ClassDB.class_exists(&"PhysicsIntersectRayResult3D") else null
var _exclude_rids: Array[RID] = []

static var _active_cannonballs: int = 0
static var _ball_meshes: Dictionary = {}
static var _firebomb_mesh: ArrayMesh = null
static var _splinter_mesh: ArrayMesh = null
static var _splinter_mat: StandardMaterial3D = null
static var _foam_puff_tex: ImageTexture = null
static var _streak_tex: ImageTexture = null
static var _flash_tex: GradientTexture2D = null


## Release all statically cached sculpted ordnance meshes, splinter mesh, and VFX textures.
static func clear_shared_cache() -> void:
	if _splinter_mesh != null and _splinter_mesh.get_surface_count() > 0:
		_splinter_mesh.surface_set_material(0, null)
	_ball_meshes.clear()
	_firebomb_mesh = null
	_splinter_mesh = null
	_splinter_mat = null
	_foam_puff_tex = null
	_streak_tex = null
	_flash_tex = null


## Return the resolved ordnance variant (&"iron", &"heavy", &"swivel", &"chainshot", &"firebomb", or &"flare").
func get_resolved_ordnance_style() -> StringName:
	return _resolved_style


func _enter_tree() -> void:
	_active_cannonballs += 1


func _exit_tree() -> void:
	for fx in _spawned_vfx:
		if fx != null and is_instance_valid(fx):
			for child in fx.find_children("*", "GPUParticles3D", true, false):
				var gp := child as GPUParticles3D
				if gp != null:
					gp.emitting = false
					gp.draw_pass_1 = null
					gp.process_material = null
			fx.queue_free()
	_spawned_vfx.clear()
	if _ball_mesh != null and is_instance_valid(_ball_mesh):
		if _ball_mesh.mesh != null:
			for si in _ball_mesh.mesh.get_surface_count():
				_ball_mesh.set_surface_override_material(si, null)
		_ball_mesh.material_override = null
		_ball_mesh.mesh = null
	_ball_mesh = null
	_ball_mat = null
	_core_glow_mat = null
	if flare_light != null and is_instance_valid(flare_light):
		flare_light.visible = false
	flare_light = null
	if firebomb_light != null and is_instance_valid(firebomb_light):
		firebomb_light.visible = false
	firebomb_light = null
	if trail != null and is_instance_valid(trail):
		trail.set(&"emitting", false)
		trail.set(&"color_gradient", null)
		trail.set(&"width_curve", null)
	trail = null
	_ray_params = null
	_ray_result = null
	_exclude_rids.clear()
	_active_cannonballs = maxi(0, _active_cannonballs - 1)
	if _active_cannonballs == 0:
		clear_shared_cache()


func _ready() -> void:
	_resolved_style = _resolve_ordnance_style()
	if _resolved_style == &"flare":
		drag = maxf(drag, 0.28)
	_build_visuals()
	_ray_params.collision_mask = HIT_MASK
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true
	_refresh_exclusions()


func _resolve_ordnance_style() -> StringName:
	if ordnance_style == &"heavy" or ordnance_style == &"swivel" \
			or ordnance_style == &"chainshot" or ordnance_style == &"firebomb" \
			or ordnance_style == &"flare":
		return ordnance_style
	if ordnance_style == &"iron":
		if hull_damage_radius >= 0.52:
			return &"heavy"
		if hull_damage_radius <= 0.40:
			return &"swivel"
	return &"iron"


func _build_visuals() -> void:
	_ball_mesh = MeshInstance3D.new()
	_ball_mesh.name = "IronBall"
	_ball_mesh.mesh = get_ball_mesh(_resolved_style)

	_ball_mat = StandardMaterial3D.new()
	_ball_mat.vertex_color_use_as_albedo = true
	_ball_mat.vertex_color_is_srgb = true
	_ball_mat.emission_enabled = true

	var trail_width := 0.26
	var trail_life := 0.45
	var trail_c0 := Color(0.96, 0.92, 0.84, 0.78)
	var trail_c1 := Color(0.76, 0.77, 0.78, 0.45)
	var trail_c2 := Color(0.55, 0.58, 0.62, 0.0)

	match _resolved_style:
		&"heavy":
			# Reinforced culverin siege ball: heavier iron sheen + blazing orange-gold core seams & fiery-amber trail.
			_ball_mat.metallic = 0.80
			_ball_mat.roughness = 0.36
			_ball_mat.emission = Color(1.0, 0.48, 0.10)
			_base_muzzle_emission = 0.48
			_ball_mat.emission_energy_multiplier = _base_muzzle_emission
			_ball_mesh.set_surface_override_material(0, _ball_mat)

			_core_glow_mat = StandardMaterial3D.new()
			_core_glow_mat.vertex_color_use_as_albedo = true
			_core_glow_mat.vertex_color_is_srgb = true
			_core_glow_mat.albedo_color = Color(1.0, 0.68, 0.22)
			_core_glow_mat.metallic = 0.15
			_core_glow_mat.roughness = 0.28
			_core_glow_mat.emission_enabled = true
			_core_glow_mat.emission = Color(1.0, 0.50, 0.10)
			_core_glow_mat.emission_energy_multiplier = 2.65
			if _ball_mesh.mesh.get_surface_count() > 1:
				_ball_mesh.set_surface_override_material(1, _core_glow_mat)

			trail_width = 0.36
			trail_life = 0.54
			trail_c0 = Color(1.0, 0.66, 0.20, 0.88)
			trail_c1 = Color(0.84, 0.40, 0.14, 0.56)
			trail_c2 = Color(0.36, 0.30, 0.28, 0.0)
		&"swivel":
			# Quick-Breech Swivel: sleek faceted burnished-bronze shot + crisp brass-ivory ribbon.
			_ball_mat.metallic = 0.86
			_ball_mat.roughness = 0.24
			_ball_mat.emission = Color(1.0, 0.78, 0.34)
			_base_muzzle_emission = 0.28
			_ball_mat.emission_energy_multiplier = _base_muzzle_emission
			_ball_mesh.set_surface_override_material(0, _ball_mat)

			trail_width = 0.19
			trail_life = 0.38
			trail_c0 = Color(1.0, 0.96, 0.82, 0.80)
			trail_c1 = Color(0.92, 0.84, 0.64, 0.44)
			trail_c2 = Color(0.72, 0.68, 0.60, 0.0)
		&"chainshot":
			# Twin whirling forged-iron spheres joined by heavy forged chain links for rigging & sail damage.
			_ball_mat.metallic = 0.82
			_ball_mat.roughness = 0.34
			_ball_mat.emission = Color(1.0, 0.55, 0.16)
			_base_muzzle_emission = 0.34
			_ball_mat.emission_energy_multiplier = _base_muzzle_emission
			_ball_mesh.set_surface_override_material(0, _ball_mat)

			trail_width = 0.32
			trail_life = 0.48
			trail_c0 = Color(0.92, 0.94, 0.98, 0.82)
			trail_c1 = Color(0.68, 0.72, 0.78, 0.48)
			trail_c2 = Color(0.42, 0.46, 0.52, 0.0)
		&"firebomb":
			# Bulbous molten-amber incendiary glass flask with braided fuse neck, glowing core & travel light.
			_ball_mat.metallic = 0.24
			_ball_mat.roughness = 0.18
			_ball_mat.emission = Color(1.0, 0.44, 0.08)
			_base_muzzle_emission = 0.85
			_ball_mat.emission_energy_multiplier = _base_muzzle_emission
			_ball_mesh.set_surface_override_material(0, _ball_mat)

			_core_glow_mat = StandardMaterial3D.new()
			_core_glow_mat.vertex_color_use_as_albedo = true
			_core_glow_mat.vertex_color_is_srgb = true
			_core_glow_mat.albedo_color = Color(1.0, 0.76, 0.26)
			_core_glow_mat.metallic = 0.08
			_core_glow_mat.roughness = 0.22
			_core_glow_mat.emission_enabled = true
			_core_glow_mat.emission = Color(1.0, 0.50, 0.10)
			_core_glow_mat.emission_energy_multiplier = 3.8
			if _ball_mesh.mesh.get_surface_count() > 1:
				_ball_mesh.set_surface_override_material(1, _core_glow_mat)

			firebomb_light = OmniLight3D.new()
			firebomb_light.name = "FirebombLight"
			firebomb_light.light_color = Color(1.0, 0.52, 0.14)
			firebomb_light.light_energy = 2.6
			firebomb_light.omni_range = 14.0
			firebomb_light.omni_attenuation = 1.4
			firebomb_light.shadow_enabled = false
			add_child(firebomb_light)

			trail_width = 0.30
			trail_life = 0.62
			trail_c0 = Color(1.0, 0.68, 0.18, 0.90)
			trail_c1 = Color(0.96, 0.32, 0.06, 0.56)
			trail_c2 = Color(0.28, 0.22, 0.20, 0.0)
		&"flare":
			# Glowing brass & crimson-gold marine illumination signal shell with wide-range OmniLight3D.
			_ball_mat.metallic = 0.84
			_ball_mat.roughness = 0.24
			_ball_mat.emission = Color(1.0, 0.52, 0.18)
			_base_muzzle_emission = 0.65
			_ball_mat.emission_energy_multiplier = _base_muzzle_emission
			_ball_mesh.set_surface_override_material(0, _ball_mat)

			_core_glow_mat = StandardMaterial3D.new()
			_core_glow_mat.vertex_color_use_as_albedo = true
			_core_glow_mat.vertex_color_is_srgb = true
			_core_glow_mat.albedo_color = Color(1.0, 0.78, 0.32)
			_core_glow_mat.metallic = 0.10
			_core_glow_mat.roughness = 0.20
			_core_glow_mat.emission_enabled = true
			_core_glow_mat.emission = Color(1.0, 0.42, 0.14)
			_core_glow_mat.emission_energy_multiplier = 4.2
			if _ball_mesh.mesh.get_surface_count() > 1:
				_ball_mesh.set_surface_override_material(1, _core_glow_mat)

			flare_light = OmniLight3D.new()
			flare_light.name = "FlareLight"
			flare_light.light_color = Color(1.0, 0.62, 0.28)
			flare_light.light_energy = 5.5
			flare_light.omni_range = 65.0
			flare_light.omni_attenuation = 1.2
			flare_light.shadow_enabled = false
			add_child(flare_light)

			trail_width = 0.28
			trail_life = 0.85
			trail_c0 = Color(1.0, 0.46, 0.18, 0.90)
			trail_c1 = Color(1.0, 0.72, 0.32, 0.52)
			trail_c2 = Color(0.65, 0.44, 0.36, 0.0)
		_:
			# Cast-Iron Nine-Pounder: hammered iron shot with raised equatorial seam & warm hot-forge muzzle rim.
			_ball_mat.metallic = 0.76
			_ball_mat.roughness = 0.38
			_ball_mat.emission = Color(1.0, 0.45, 0.12)
			_base_muzzle_emission = 0.35
			_ball_mat.emission_energy_multiplier = _base_muzzle_emission
			_ball_mesh.set_surface_override_material(0, _ball_mat)

	add_child(_ball_mesh)

	if ClassDB.class_exists(&"Trail3D"):
		var t_obj: Variant = ClassDB.instantiate(&"Trail3D")
		if t_obj is Node3D:
			trail = t_obj as Node3D
			trail.name = "SmokeTrail"
			trail.set(&"limit_mode", ClassDB.class_get_integer_constant(&"Trail3D", &"LIMIT_MODE_LIFETIME"))
			trail.set(&"lifetime", trail_life)
			trail.set(&"min_section_length", 0.14)
			trail.set(&"width", trail_width)
			trail.set(&"mesh_alignment", ClassDB.class_get_integer_constant(&"Trail3D", &"MESH_ALIGNMENT_BILLBOARD"))
			trail.set(&"material_mode", ClassDB.class_get_integer_constant(&"Trail3D", &"MATERIAL_MODE_MIX"))
			if trail is GeometryInstance3D:
				(trail as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var width_curve := Curve.new()
			width_curve.add_point(Vector2(0.0, 1.0))
			width_curve.add_point(Vector2(0.55, 0.65))
			width_curve.add_point(Vector2(1.0, 0.12))
			trail.set(&"width_curve", width_curve)
			var grad := Gradient.new()
			grad.set_color(0, trail_c0)
			grad.add_point(0.35, trail_c1)
			grad.set_color(grad.get_point_count() - 1, trail_c2)
			trail.set(&"color_gradient", grad)
			trail.set(&"emitting", true)
			add_child(trail)


func _refresh_exclusions() -> void:
	_exclude_rids.clear()
	if _age < SELF_IGNORE_TIME:
		if shooter_ship is CollisionObject3D and is_instance_valid(shooter_ship):
			_exclude_rids.append((shooter_ship as CollisionObject3D).get_rid())
		if shooter_pawn is CollisionObject3D and is_instance_valid(shooter_pawn):
			_exclude_rids.append((shooter_pawn as CollisionObject3D).get_rid())
	if _ray_params != null:
		_ray_params.exclude = _exclude_rids


func _physics_process(delta: float) -> void:
	if _impacted:
		_cleanup_timer -= delta
		if _cleanup_timer <= 0.0:
			queue_free()
		return

	_age += delta
	var life_limit := FLARE_MAX_LIFETIME if _resolved_style == &"flare" else MAX_LIFETIME
	if _age >= life_limit:
		_finish_without_impact()
		return

	# Spin faceted ordnance mid-flight & update muzzle / flare / firebomb illumination glow.
	if _ball_mesh != null:
		if _resolved_style == &"chainshot":
			_ball_mesh.rotate_y(delta * 26.0)
			_ball_mesh.rotate_x(delta * 8.5)
		elif _resolved_style == &"firebomb":
			_ball_mesh.rotate_x(delta * 10.5)
			_ball_mesh.rotate_z(delta * 7.8)
		elif _resolved_style == &"flare":
			_ball_mesh.rotate_z(delta * 6.5)
		else:
			_ball_mesh.rotate_x(delta * 7.2)
			_ball_mesh.rotate_y(delta * 4.1)

	if _resolved_style == &"flare":
		if not _flare_floating and (velocity.y <= 2.2 or _age >= 0.9):
			_flare_floating = true
		var burn_env := 1.0
		if _flare_floating:
			_flare_burn_elapsed += delta
			if _flare_burn_elapsed >= FLARE_BURN_DURATION:
				_finish_without_impact()
				return
			if _flare_burn_elapsed > FLARE_BURN_DURATION - 1.2:
				burn_env = clampf((FLARE_BURN_DURATION - _flare_burn_elapsed) / 1.2, 0.0, 1.0)
			# Parachute-soft float near apex to bathe dark seas in warm crimson-gold light.
			velocity.x *= maxf(0.0, 1.0 - 2.4 * delta)
			velocity.z *= maxf(0.0, 1.0 - 2.4 * delta)
			velocity.y = move_toward(velocity.y, -1.65, 14.0 * delta)
		else:
			velocity.y -= GRAVITY * delta
			velocity *= maxf(0.0, 1.0 - drag * delta)
		var pulse := 0.93 + 0.07 * sin(_age * 19.0)
		if flare_light != null and is_instance_valid(flare_light):
			flare_light.light_energy = 5.5 * burn_env * pulse
		if _ball_mat != null:
			_ball_mat.emission_energy_multiplier = _base_muzzle_emission * burn_env
		if _core_glow_mat != null:
			_core_glow_mat.emission_energy_multiplier = 4.2 * burn_env * pulse
	elif _resolved_style == &"firebomb":
		var flick := 0.86 + 0.14 * sin(_age * 24.0) * cos(_age * 13.0)
		if firebomb_light != null and is_instance_valid(firebomb_light):
			firebomb_light.light_energy = 2.6 * flick
		if _core_glow_mat != null:
			_core_glow_mat.emission_energy_multiplier = 3.8 * flick
		velocity.y -= GRAVITY * delta
		velocity *= maxf(0.0, 1.0 - drag * delta)
	else:
		if _age < 0.35 and _ball_mat != null:
			_ball_mat.emission_energy_multiplier = maxf(0.0, _base_muzzle_emission * (1.0 - _age / 0.35))
		velocity.y -= GRAVITY * delta
		velocity *= maxf(0.0, 1.0 - drag * delta)

	var from := global_position
	var to := from + velocity * delta

	var world := get_world_3d()
	var solid_hit_pos := Vector3.ZERO
	var solid_hit_normal := Vector3.UP
	var solid_hit_col: Object = null
	var has_solid_hit := false
	if world != null and _ray_params != null:
		_refresh_exclusions()
		_ray_params.from = from
		_ray_params.to = to
		var space := world.direct_space_state
		if _ray_result != null and space.has_method(&"intersect_ray_into"):
			if bool(space.call(&"intersect_ray_into", _ray_params, _ray_result)):
				has_solid_hit = true
				solid_hit_pos = _ray_result.get(&"position") as Vector3
				solid_hit_normal = _ray_result.get(&"normal") as Vector3
				solid_hit_col = _ray_result.get(&"collider") as Object
		else:
			var hit := space.intersect_ray(_ray_params)
			if not hit.is_empty():
				has_solid_hit = true
				solid_hit_pos = hit["position"] as Vector3
				solid_hit_normal = hit["normal"] as Vector3
				solid_hit_col = hit["collider"] as Object

	if _resolved_style != &"flare":
		var seg_end := solid_hit_pos if has_solid_hit else to
		var keg_hit := _find_direct_powder_keg_hit(from, seg_end)
		if not keg_hit.is_empty():
			var hit_keg := keg_hit["keg"] as PowderKeg
			var hit_kpos := keg_hit["pos"] as Vector3
			var hit_knorm := -velocity.normalized() if velocity.length_squared() > 0.01 else Vector3.UP
			_on_solid_hit(hit_kpos, hit_knorm, hit_keg)
			return

	if has_solid_hit:
		_on_solid_hit(solid_hit_pos, solid_hit_normal, solid_hit_col)
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

	if _resolved_style == &"flare":
		# Signal flares illuminate dark waters and never punch hull breaches or inflict combat damage.
		if ship_target != null:
			target = ship_target
		if _spawn_dust_burst(hit_pos, hit_normal, Color(1.0, 0.56, 0.22)):
			cleanup_delay = 0.8
		Audio.play_sfx(&"splash_small", hit_pos, -3.0)
		_mark_impacted(hit_pos, target, cleanup_delay)
		return

	if _resolved_style == &"firebomb":
		# Firebombs shatter on impact: ignite deck fire + adjacent zone and deal light 12.0 splash scorch
		# instead of punching a deep iron cannon hole!
		var burn_ship: Node3D = ship_target
		if burn_ship == null and target is Pawn and (target as Pawn).platform is Node3D:
			burn_ship = _find_ship((target as Pawn).platform)
		if burn_ship != null:
			target = burn_ship
		if Net.is_host():
			if burn_ship != null and burn_ship.has_method(&"ignite_deck_fire"):
				burn_ship.call(&"ignite_deck_fire", hit_pos, true)
			if burn_ship is RigidBody3D:
				var rb_fb := burn_ship as RigidBody3D
				var fb_dir := velocity.normalized() if velocity.length_squared() > 0.01 else -hit_normal
				var fb_rel := hit_pos - rb_fb.global_position
				fb_rel.y = clampf(fb_rel.y, -1.5, 1.5)
				rb_fb.apply_impulse(fb_dir * hull_impact_impulse * 0.22, fb_rel)
			if target != null and target.has_meta("leviathan"):
				var lev_fb: Variant = target.get_meta("leviathan")
				if lev_fb != null and is_instance_valid(lev_fb) and (lev_fb as Object).has_method(&"damage_tentacle"):
					var t_idx_fb := int(target.get_meta("tentacle_index", -1))
					(lev_fb as Object).call(&"damage_tentacle", t_idx_fb, FIREBOMB_SPLASH_DAMAGE)
			_apply_firebomb_splash_scorch(hit_pos, collider as Node)
			_detonate_nearby_powder_kegs(hit_pos, FIREBOMB_SPLASH_RADIUS)
		if _spawn_dust_burst(hit_pos, hit_normal, Color(1.0, 0.46, 0.10)):
			cleanup_delay = 0.9
		Audio.play_sfx(&"hull_impact", hit_pos, -1.5)
		_mark_impacted(hit_pos, target, cleanup_delay)
		return

	if target is PowderKeg:
		if Net.is_host():
			(target as PowderKeg).detonate(shooter_pawn)
			_detonate_nearby_powder_kegs(hit_pos, 3.2)
		if _spawn_dust_burst(hit_pos, hit_normal, Color(1.0, 0.56, 0.16)):
			cleanup_delay = 0.85
		_mark_impacted(hit_pos, target, cleanup_delay)
		return

	if ship_target != null:
		target = ship_target
		var is_chain := _resolved_style == &"chainshot"
		if Net.is_host():
			if is_chain and ship_target.has_method(&"apply_sail_damage"):
				ship_target.call(&"apply_sail_damage", CHAINSHOT_SAIL_DAMAGE)
			if ship_target.has_method(&"apply_hull_damage"):
				var breach_r := CHAINSHOT_BREACH_RADIUS if is_chain else hull_damage_radius
				ship_target.call(&"apply_hull_damage", hit_pos, breach_r)
			if ship_target is RigidBody3D:
				var rb := ship_target as RigidBody3D
				var imp_dir := velocity.normalized() if velocity.length_squared() > 0.01 else -hit_normal
				var rel_pos := hit_pos - rb.global_position
				# Keep vertical lever arm modest so a hit rocks the ship cleanly without flipping it.
				rel_pos.y = clampf(rel_pos.y, -1.5, 1.5)
				var imp_scale := 0.55 if is_chain else 1.0
				rb.apply_impulse(imp_dir * hull_impact_impulse * imp_scale, rel_pos)
			_detonate_nearby_powder_kegs(hit_pos, 3.2)
		if _spawn_splinter_burst(hit_pos, hit_normal):
			cleanup_delay = 1.15
		if is_chain:
			Audio.play_sfx(&"sail_flap", hit_pos, 0.0)
		else:
			Audio.play_sfx(&"hull_impact", hit_pos)
	elif target != null and target.has_meta("leviathan"):
		var lev: Variant = target.get_meta("leviathan")
		if Net.is_host() and lev != null and is_instance_valid(lev) and (lev as Object).has_method(&"damage_tentacle"):
			var t_idx := int(target.get_meta("tentacle_index", -1))
			(lev as Object).call(&"damage_tentacle", t_idx, pawn_damage)
		if Net.is_host():
			_detonate_nearby_powder_kegs(hit_pos, 3.2)
		if _spawn_dust_burst(hit_pos, hit_normal, Color(0.24, 0.72, 0.68)):
			cleanup_delay = 0.8
		Audio.play_sfx(&"hit_flesh", hit_pos)
	elif target != null and target.has_method(&"apply_damage"):
		if Net.is_host():
			target.call(&"apply_damage", pawn_damage, shooter_pawn)
			_detonate_nearby_powder_kegs(hit_pos, 3.2)
		if _spawn_dust_burst(hit_pos, hit_normal, Color(0.85, 0.72, 0.56)):
			cleanup_delay = 0.8
		Audio.play_sfx(&"hit_flesh", hit_pos)
	else:
		if Net.is_host():
			_detonate_nearby_powder_kegs(hit_pos, 3.2)
		if _spawn_dust_burst(hit_pos, hit_normal, Color(0.76, 0.74, 0.68)):
			cleanup_delay = 0.8
		Audio.play_sfx(&"hull_impact", hit_pos, -4.0)

	_mark_impacted(hit_pos, target, cleanup_delay)


func _find_direct_powder_keg_hit(from: Vector3, to: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var tree := get_tree()
	if tree == null:
		return {}
	var kegs := tree.get_nodes_in_group(&"powder_kegs")
	if kegs.is_empty():
		return {}
	var best_keg: PowderKeg = null
	var best_pos := Vector3.ZERO
	var best_d2 := INF
	const HIT_R_SQ := 0.46 * 0.46
	for node in kegs:
		if not is_instance_valid(node) or not (node is PowderKeg):
			continue
		var keg := node as PowderKeg
		if keg.exploded:
			continue
		var kpos := keg.global_position + Vector3(0.0, PowderKeg.KEG_CENTER_Y, 0.0)
		var closest := Geometry3D.get_closest_point_to_segment(kpos, from, to)
		if closest.distance_squared_to(kpos) <= HIT_R_SQ:
			var dist_from_sq := from.distance_squared_to(closest)
			if dist_from_sq < best_d2:
				best_d2 = dist_from_sq
				best_keg = keg
				best_pos = closest
	if best_keg != null:
		return {"keg": best_keg, "pos": best_pos}
	return {}


func _detonate_nearby_powder_kegs(blast_origin: Vector3, radius: float) -> int:
	if not Net.is_host() or not is_inside_tree():
		return 0
	var tree := get_tree()
	if tree == null:
		return 0
	var kegs := tree.get_nodes_in_group(&"powder_kegs")
	if kegs.is_empty():
		return 0
	var r_sq := radius * radius
	var blown := 0
	for node in kegs:
		if not is_instance_valid(node) or not (node is PowderKeg):
			continue
		var keg := node as PowderKeg
		if keg.exploded:
			continue
		var kpos := keg.global_position + Vector3(0.0, PowderKeg.KEG_CENTER_Y, 0.0)
		if kpos.distance_squared_to(blast_origin) <= r_sq:
			var res := keg.detonate(shooter_pawn)
			if not res.is_empty():
				blown += 1
	return blown


func _apply_firebomb_splash_scorch(hit_pos: Vector3, direct_node: Node = null) -> void:
	if not Net.is_host() or not is_inside_tree():
		return
	var r_sq := FIREBOMB_SPLASH_RADIUS * FIREBOMB_SPLASH_RADIUS
	var seen: Dictionary = {}
	var candidates: Array[Node3D] = []
	if direct_node is Node3D and is_instance_valid(direct_node):
		candidates.append(direct_node as Node3D)
	var tree := get_tree()
	if tree != null:
		for grp: StringName in [&"pawn", &"pawns"]:
			for n in tree.get_nodes_in_group(grp):
				if n is Node3D and is_instance_valid(n):
					candidates.append(n as Node3D)
		for cb in tree.get_nodes_in_group(&"crew_brains"):
			var p := cb.get_parent() as Node3D
			if p != null and is_instance_valid(p):
				candidates.append(p)
		for cc in tree.get_nodes_in_group(&"combatants"):
			var p2 := cc.get_parent() as Node3D
			if p2 != null and is_instance_valid(p2):
				candidates.append(p2)
	var parent_node := get_parent()
	if parent_node != null:
		for ch in parent_node.get_children():
			if ch is Pawn and is_instance_valid(ch):
				candidates.append(ch as Node3D)
	for cand: Node3D in candidates:
		if cand == null or not is_instance_valid(cand):
			continue
		var iid := cand.get_instance_id()
		if seen.has(iid):
			continue
		seen[iid] = true
		if cand == shooter_pawn and _age < SELF_IGNORE_TIME:
			continue
		var is_dead: Variant = cand.get(&"dead")
		if is_dead is bool and bool(is_dead):
			continue
		if cand != direct_node and cand.global_position.distance_squared_to(hit_pos) > r_sq:
			continue
		if cand.has_method(&"take_damage"):
			cand.call(&"take_damage", FIREBOMB_SPLASH_DAMAGE)
		elif cand.has_method(&"apply_damage"):
			cand.call(&"apply_damage", FIREBOMB_SPLASH_DAMAGE, shooter_pawn)


func _on_water_hit(hit_pos: Vector3) -> void:
	global_position = hit_pos
	if Net.is_host() and _resolved_style != &"flare":
		var keg_r := FIREBOMB_SPLASH_RADIUS if _resolved_style == &"firebomb" else 3.2
		_detonate_nearby_powder_kegs(hit_pos, keg_r)
	if Ocean.current != null:
		Ocean.current.add_foam(hit_pos, 3.2, 0.95)
	var spawned := _spawn_splash_burst(hit_pos)
	Audio.play_sfx(&"splash_small" if (_resolved_style == &"flare" or _resolved_style == &"firebomb") else &"splash_large", hit_pos)
	_mark_impacted(hit_pos, null, 1.65 if spawned else 0.5)


func _mark_impacted(hit_pos: Vector3, target: Node, cleanup_delay: float = 0.5) -> void:
	_impacted = true
	_cleanup_timer = cleanup_delay
	if _ball_mesh != null:
		_ball_mesh.visible = false
	if flare_light != null and is_instance_valid(flare_light):
		flare_light.light_energy = 0.0
		flare_light.visible = false
	if firebomb_light != null and is_instance_valid(firebomb_light):
		firebomb_light.light_energy = 0.0
		firebomb_light.visible = false
	if trail != null:
		trail.set(&"emitting", false)
	impacted.emit(hit_pos, target)


func _finish_without_impact() -> void:
	_impacted = true
	_cleanup_timer = 0.1
	if _ball_mesh != null:
		_ball_mesh.visible = false
	if flare_light != null and is_instance_valid(flare_light):
		flare_light.light_energy = 0.0
		flare_light.visible = false
	if firebomb_light != null and is_instance_valid(firebomb_light):
		firebomb_light.light_energy = 0.0
		firebomb_light.visible = false
	if trail != null:
		trail.set(&"emitting", false)


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

	splinters.draw_pass_1 = get_splinter_mesh()
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


# ==============================================================================
# Sculpted Flat-Faceted Ordnance & Jagged Oak Splinter Builders (0 Primitives)
# ==============================================================================

## Return (and statically cache) the sculpted ArrayMesh for `&"iron"`, `&"heavy"`, `&"swivel"`, `&"chainshot"`, `&"firebomb"`, or `&"flare"`.
static func get_ball_mesh(style: StringName = &"iron") -> ArrayMesh:
	var key := style if (style == &"heavy" or style == &"swivel" \
			or style == &"chainshot" or style == &"firebomb" or style == &"flare") else &"iron"
	if key == &"firebomb" and _firebomb_mesh != null:
		return _firebomb_mesh
	if _ball_meshes.has(key):
		var cached := _ball_meshes[key] as ArrayMesh
		if cached != null:
			return cached
	var built: ArrayMesh
	match key:
		&"heavy":
			built = _build_heavy_ball_mesh()
		&"swivel":
			built = _build_swivel_ball_mesh()
		&"chainshot":
			built = _build_chainshot_mesh()
		&"firebomb":
			built = _build_firebomb_mesh()
			_firebomb_mesh = built
		&"flare":
			built = _build_flare_mesh()
		_:
			built = _build_iron_ball_mesh()
	_ball_meshes[key] = built
	return built


## Return (and statically cache) the sculpted jagged broken oak plank shard ArrayMesh.
static func get_splinter_mesh() -> ArrayMesh:
	if _splinter_mesh != null:
		return _splinter_mesh
	if _splinter_mat == null:
		_splinter_mat = StandardMaterial3D.new()
		_splinter_mat.vertex_color_use_as_albedo = true
		_splinter_mat.vertex_color_is_srgb = true
		_splinter_mat.roughness = 0.84
		_splinter_mat.metallic = 0.02
	_splinter_mesh = _build_splinter_mesh()
	if _splinter_mesh.get_surface_count() > 0:
		_splinter_mesh.surface_set_material(0, _splinter_mat)
	return _splinter_mesh


static func _build_iron_ball_mesh() -> ArrayMesh:
	# Hammered 12-facet cast-iron Nine-Pounder (r = 0.115 m) with raised equatorial casting seam & warm forge rim.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_hi := Color(0.28, 0.29, 0.33)
	var col_mid := Color(0.15, 0.16, 0.19)
	var col_lo := Color(0.08, 0.085, 0.105)
	var col_seam := Color(0.42, 0.26, 0.18)
	_add_hammered_sphere(st, 0.115, 12, 6, 0.036, 1.0, col_hi, col_mid, col_lo)
	_add_forged_band(st, Basis.IDENTITY, 0.114, 0.123, 0.014, 12, col_seam, col_hi, col_lo)
	st.generate_normals()
	return st.commit()


static func _build_heavy_ball_mesh() -> ArrayMesh:
	# Bolder Heavy Culverin siege shot (r = 0.140 m): hammered iron + beveled criss-cross forged iron bands
	# + 6 corner rivets (Surface 0) and hot orange-gold glowing core seams (Surface 1).
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_hi := Color(0.26, 0.27, 0.31)
	var col_mid := Color(0.13, 0.14, 0.17)
	var col_lo := Color(0.07, 0.075, 0.095)
	var col_band_hi := Color(0.36, 0.34, 0.33)
	var col_band_mid := Color(0.20, 0.20, 0.22)

	_add_hammered_sphere(iron_st, 0.140, 12, 6, 0.032, 2.7, col_hi, col_mid, col_lo)
	# Criss-cross beveled forged iron siege bands around equator & two orthogonal meridians.
	var band_bases: Array[Basis] = [
		Basis.IDENTITY,
		Basis(Vector3.RIGHT, PI * 0.5),
		Basis(Vector3.FORWARD, PI * 0.5),
	]
	for bb in band_bases:
		_add_forged_band(iron_st, bb, 0.138, 0.154, 0.022, 12, col_band_hi, col_band_mid, col_lo)

	# 6 forged iron rivet bosses capping the criss-cross intersections along +/-X, +/-Y, +/-Z.
	for dir: Vector3 in [
		Vector3.RIGHT, Vector3.LEFT,
		Vector3.UP, Vector3.DOWN,
		Vector3.BACK, Vector3.FORWARD,
	]:
		_add_faceted_rivet(iron_st, dir * 0.148, dir, 0.022, 0.014, col_band_hi, col_band_mid, col_lo)

	# Surface 1: recessed hot orange-gold glowing core seams peeking beside the forged bands!
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_glow_hi := Color(1.0, 0.92, 0.56)
	var col_glow_mid := Color(1.0, 0.58, 0.16)
	var col_glow_lo := Color(0.90, 0.28, 0.06)
	for bb in band_bases:
		for y_off: float in [-0.025, 0.025]:
			_add_offset_seam_ring(glow_st, bb, 0.139, 0.1445, y_off, 0.006, 12,
				col_glow_hi, col_glow_mid, col_glow_lo)

	iron_st.generate_normals()
	var mesh := iron_st.commit()
	glow_st.generate_normals()
	glow_st.commit(mesh)
	return mesh


static func _build_swivel_ball_mesh() -> ArrayMesh:
	# Sleek Quick-Breech Swivel shot (r = 0.098 m): faceted burnished-bronze sphere with machined brass collar.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_hi := Color(0.96, 0.78, 0.34)
	var col_mid := Color(0.76, 0.55, 0.20)
	var col_lo := Color(0.42, 0.27, 0.09)
	_add_hammered_sphere(st, 0.098, 12, 6, 0.014, 4.1, col_hi, col_mid, col_lo)
	_add_forged_band(st, Basis.IDENTITY, 0.097, 0.104, 0.011, 12, col_hi, col_mid, col_lo)
	st.generate_normals()
	return st.commit()


static func _build_chainshot_mesh() -> ArrayMesh:
	# Twin hammered cast-iron spheres (r = 0.088 m at x = +/-0.195 m) connected by a heavy
	# interlocking forged-iron chain link bar built strictly via SurfaceTool (0 primitives).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_hi := Color(0.32, 0.34, 0.38)
	var col_mid := Color(0.16, 0.17, 0.21)
	var col_lo := Color(0.08, 0.09, 0.11)
	var col_link_hi := Color(0.42, 0.43, 0.46)
	var col_link_mid := Color(0.24, 0.25, 0.28)

	for sx: float in [-1.0, 1.0]:
		var ctr := Vector3(sx * 0.195, 0.0, 0.0)
		_add_hammered_sphere_at(st, ctr, 0.088, 10, 5, 0.038, 1.7 + sx, col_hi, col_mid, col_lo)
		# Heavy forged shackle eye lug anchoring the chain into each iron shot.
		_add_ordnance_tube(st, Vector3(sx * 0.115, 0.0, 0.0), Vector3(sx * 0.085, 0.0, 0.0),
			0.030, 0.024, 6, col_link_hi, col_lo)

	# Central forged chain link bar with 3 alternating horizontal/vertical heavy chain rings.
	_add_ordnance_tube(st, Vector3(-0.110, 0.0, 0.0), Vector3(0.110, 0.0, 0.0),
		0.018, 0.018, 6, col_link_hi, col_link_mid)
	for li in 3:
		var lx := -0.072 + float(li) * 0.072
		var rot_x := 0.0 if (li % 2 == 0) else PI * 0.5
		_add_chain_link_ring(st, Vector3(lx, 0.0, 0.0), Basis(Vector3.RIGHT, rot_x),
			0.044, 0.028, 0.013, col_link_hi, col_link_mid, col_lo)

	st.generate_normals()
	return st.commit()


static func _build_flare_mesh() -> ArrayMesh:
	# Glowing brass & crimson-gold marine illumination signal shell:
	# Surface 0 = turned brass casing, nose cone & 4 stabilizing tail fins;
	# Surface 1 = blazing crimson-gold magnesium burn ports & tail flame star.
	var body_st := SurfaceTool.new()
	body_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_brass_hi := Color(0.98, 0.80, 0.32)
	var col_brass_mid := Color(0.76, 0.56, 0.18)
	var col_brass_lo := Color(0.42, 0.28, 0.09)
	var col_crim := Color(0.84, 0.18, 0.14)

	# Turned brass flare canister aligned along Z (-0.17 nose -> +0.16 tail).
	var profile: Array[Vector2] = [
		Vector2(0.0, -0.175),
		Vector2(0.042, -0.145),
		Vector2(0.072, -0.095),
		Vector2(0.082, -0.080),
		Vector2(0.074, -0.065),
		Vector2(0.074, 0.085),
		Vector2(0.084, 0.100),
		Vector2(0.070, 0.145),
		Vector2(0.048, 0.165),
		Vector2(0.0, 0.165),
	]
	_add_z_lathe(body_st, profile, 10, col_brass_hi, col_brass_mid, col_brass_lo)

	# Four swept crimson-brass stabilizing tail fins around the rear barrel.
	for k in 4:
		var ang := float(k) * PI * 0.5
		var d := Vector3(cos(ang), sin(ang), 0.0)
		var p := Vector3(-sin(ang), cos(ang), 0.0) * 0.010
		var r_in := 0.068
		var r_out := 0.122
		var z0 := 0.055
		var z1 := 0.155
		var mid := d * ((r_in + r_out) * 0.5) + Vector3(0.0, 0.0, (z0 + z1) * 0.5)
		var a0 := d * r_in + Vector3(0.0, 0.0, z0) + p
		var a1 := d * r_in + Vector3(0.0, 0.0, z0) - p
		var b0 := d * r_out + Vector3(0.0, 0.0, z1 - 0.015) + p
		var b1 := d * r_out + Vector3(0.0, 0.0, z1 - 0.015) - p
		var c0 := d * r_in + Vector3(0.0, 0.0, z1) + p
		var c1 := d * r_in + Vector3(0.0, 0.0, z1) - p
		_emit_outward_tri(body_st, a0, b0, c0, mid, col_crim, col_brass_hi, col_crim)
		_emit_outward_tri(body_st, a1, c1, b1, mid, col_crim, col_crim, col_brass_hi)
		_emit_outward_quad(body_st, a0, a1, b1, b0, mid, col_brass_hi, col_brass_hi, col_crim, col_crim)
		_emit_outward_quad(body_st, b0, b1, c1, c0, mid, col_crim, col_crim, col_brass_lo, col_brass_lo)

	# Surface 1: blazing crimson-gold magnesium core rings & star exhaust plume!
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_g_hi := Color(1.0, 0.94, 0.62)
	var col_g_mid := Color(1.0, 0.52, 0.18)
	var col_g_lo := Color(0.92, 0.18, 0.10)
	for gz: float in [-0.025, 0.035]:
		_add_z_lathe(glow_st, [
			Vector2(0.072, gz - 0.018),
			Vector2(0.088, gz),
			Vector2(0.072, gz + 0.018),
		], 10, col_g_hi, col_g_mid, col_g_lo)
	# Blazing faceted diamond tail flare star behind exhaust nozzle.
	_add_hammered_sphere_at(glow_st, Vector3(0.0, 0.0, 0.195), 0.062, 8, 4, 0.0, 0.0,
		col_g_hi, col_g_mid, col_g_lo)

	body_st.generate_normals()
	var mesh := body_st.commit()
	glow_st.generate_normals()
	glow_st.commit(mesh)
	return mesh


static func _build_firebomb_mesh() -> ArrayMesh:
	# Bulbous faceted molten-amber incendiary glass flask with diagonal hemp-rope harness,
	# brass neck collar & curved braided fuse (Surface 0) + blazing molten core seams & fuse spark (Surface 1).
	var body_st := SurfaceTool.new()
	body_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_glass_hi := Color(0.96, 0.56, 0.14)
	var col_glass_mid := Color(0.76, 0.28, 0.06)
	var col_glass_lo := Color(0.38, 0.12, 0.04)
	var col_rope_hi := Color(0.56, 0.41, 0.22)
	var col_rope_mid := Color(0.36, 0.24, 0.12)
	var col_rope_lo := Color(0.18, 0.12, 0.06)
	var col_brass_hi := Color(0.88, 0.68, 0.24)
	var col_brass_lo := Color(0.42, 0.28, 0.10)

	# 1. Turned bulbous faceted amber glass flask aligned along Y (-0.128 base -> +0.168 flared lip).
	var flask_profile: Array[Vector2] = [
		Vector2(0.0, -0.128),
		Vector2(0.068, -0.118),
		Vector2(0.118, -0.072),
		Vector2(0.138, -0.008),
		Vector2(0.126, 0.056),
		Vector2(0.078, 0.102),
		Vector2(0.044, 0.128),
		Vector2(0.052, 0.150),
		Vector2(0.042, 0.164),
		Vector2(0.0, 0.164),
	]
	_add_y_lathe(body_st, flask_profile, 14, col_glass_hi, col_glass_mid, col_glass_lo)

	# 2. Forged brass neck collar rim + twin diagonal braided-hemp harness bands hugging the flask belly.
	var neck_collar: Array[Vector2] = [
		Vector2(0.045, 0.124),
		Vector2(0.060, 0.130),
		Vector2(0.062, 0.144),
		Vector2(0.052, 0.152),
	]
	_add_y_lathe(body_st, neck_collar, 12, col_brass_hi, col_brass_lo, col_rope_lo)
	var harness_bases: Array[Basis] = [
		Basis(Vector3.RIGHT, 0.58) * Basis(Vector3.FORWARD, 0.32),
		Basis(Vector3.RIGHT, -0.58) * Basis(Vector3.FORWARD, -0.32),
	]
	for hb: Basis in harness_bases:
		_add_forged_band(body_st, hb, 0.126, 0.143, 0.015, 12, col_rope_hi, col_rope_mid, col_rope_lo)

	# 3. Curving braided rope fuse neck rising from the flask cork (+0.155 -> +0.255).
	var fuse_pts: Array[Vector3] = [
		Vector3(0.0, 0.152, 0.0),
		Vector3(0.012, 0.184, 0.006),
		Vector3(0.036, 0.212, 0.014),
		Vector3(0.068, 0.228, 0.008),
		Vector3(0.096, 0.222, -0.006),
		Vector3(0.114, 0.204, -0.016),
	]
	for fi in range(fuse_pts.size() - 1):
		var c0 := col_rope_hi if (fi % 2 == 0) else col_rope_mid
		_add_ordnance_tube(body_st, fuse_pts[fi], fuse_pts[fi + 1], 0.017, 0.015, 6, c0, col_rope_lo)

	# Surface 1: incandescent molten-amber interior fire ribs & blazing faceted fuse-tip ember spark!
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_g_hi := Color(1.0, 0.96, 0.68)
	var col_g_mid := Color(1.0, 0.56, 0.12)
	var col_g_lo := Color(0.94, 0.22, 0.05)

	for gy: float in [-0.038, 0.024]:
		_add_offset_seam_ring(glow_st, Basis.IDENTITY, 0.130, 0.144, gy, 0.014, 12,
			col_g_hi, col_g_mid, col_g_lo)
	_add_hammered_sphere_at(glow_st, fuse_pts[fuse_pts.size() - 1], 0.038, 8, 4, 0.18, 1.3,
		col_g_hi, col_g_mid, col_g_lo)

	body_st.generate_normals()
	var mesh := body_st.commit()
	glow_st.generate_normals()
	glow_st.commit(mesh)
	return mesh


static func _add_y_lathe(st: SurfaceTool, profile: Array[Vector2], segs: int,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	if profile.size() < 2:
		return
	var y_mid := (profile[0].y + profile[profile.size() - 1].y) * 0.5
	var ref_c := Vector3(0.0, y_mid, 0.0)
	for pi in range(profile.size() - 1):
		var r0 := profile[pi].x
		var y0 := profile[pi].y
		var r1 := profile[pi + 1].x
		var y1 := profile[pi + 1].y
		var t0 := float(pi) / maxf(float(profile.size() - 1), 1.0)
		var t1 := float(pi + 1) / maxf(float(profile.size() - 1), 1.0)
		var c0 := col_lo.lerp(col_mid, t0 * 2.0) if t0 < 0.5 else col_mid.lerp(col_hi, (t0 - 0.5) * 2.0)
		var c1 := col_lo.lerp(col_mid, t1 * 2.0) if t1 < 0.5 else col_mid.lerp(col_hi, (t1 - 0.5) * 2.0)
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 <= 0.0004 and r1 > 0.0004:
				_emit_outward_tri(st, p00, p01, p11, ref_c, c0, c1, c1)
			elif r1 <= 0.0004 and r0 > 0.0004:
				_emit_outward_tri(st, p00, p10, p01, ref_c, c0, c0, c1)
			elif r0 > 0.0004 and r1 > 0.0004:
				_emit_outward_quad(st, p00, p10, p11, p01, ref_c, c0, c0, c1, c1)


static func _add_hammered_sphere_at(st: SurfaceTool, center: Vector3, radius: float, segs: int, rings: int,
		dent_amp: float, seed_phase: float,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var grid: Array[Array] = []
	for ri in range(rings + 1):
		var v_frac := float(ri) / float(rings)
		var phi := v_frac * PI
		var sy := cos(phi)
		var sr := sin(phi)
		var row: Array[Vector3] = []
		for si in segs:
			var theta := TAU * float(si) / float(segs)
			var dir := Vector3(cos(theta) * sr, sy, sin(theta) * sr)
			var dent := 1.0 + dent_amp * sin(theta * 3.0 + phi * 4.0 + seed_phase) * cos(theta * 2.0 - phi * 3.0) * sr
			row.append(center + dir * (radius * dent))
		grid.append(row)

	for ri in rings:
		for si in segs:
			var si1 := (si + 1) % segs
			var p00: Vector3 = grid[ri][si] as Vector3
			var p01: Vector3 = grid[ri][si1] as Vector3
			var p10: Vector3 = grid[ri + 1][si] as Vector3
			var p11: Vector3 = grid[ri + 1][si1] as Vector3
			var avg_y := ((p00.y + p01.y + p10.y + p11.y) * 0.25 - center.y) / maxf(radius, 0.001)
			var jitter := 0.08 * sin(float(ri * 7 + si * 13) + seed_phase)
			var shade := clampf(0.5 + 0.5 * avg_y + jitter, 0.0, 1.0)
			var fc := col_lo.lerp(col_mid, clampf(shade * 2.0, 0.0, 1.0)) if shade < 0.5 \
				else col_mid.lerp(col_hi, clampf((shade - 0.5) * 2.0, 0.0, 1.0))
			if ri == 0:
				_emit_outward_tri(st, p00, p11, p10, center, col_hi, fc, fc)
			elif ri == rings - 1:
				_emit_outward_tri(st, p00, p01, p10, center, fc, fc, col_lo)
			else:
				_emit_outward_quad(st, p00, p01, p11, p10, center, fc, fc, fc, fc)


static func _add_ordnance_tube(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float,
		segs: int, col_hi: Color, col_lo: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-10:
		return
	var dir := axis.normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.RIGHT
	var u := dir.cross(up_ref).normalized()
	var v := dir.cross(u).normalized()
	var mid := (p0 + p1) * 0.5
	for s in segs:
		var a0 := TAU * float(s) / float(segs)
		var a1 := TAU * float(s + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var c0 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d0.y, 0.0, 1.0))
		var c1 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d1.y, 0.0, 1.0))
		_emit_outward_quad(st, p0 + d0 * r0, p0 + d1 * r0, p1 + d1 * r1, p1 + d0 * r1, mid, c0, c1, c1, c0)
		_emit_outward_tri(st, p0, p0 + d0 * r0, p0 + d1 * r0, mid, col_lo, c0, c1)
		_emit_outward_tri(st, p1, p1 + d1 * r1, p1 + d0 * r1, mid, col_hi, c1, c0)


static func _add_chain_link_ring(st: SurfaceTool, center: Vector3, rot_basis: Basis,
		rx: float, ry: float, tube_r: float, col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	const LOOP_SEGS := 8
	var pts: Array[Vector3] = []
	for i in LOOP_SEGS:
		var a := TAU * float(i) / float(LOOP_SEGS)
		pts.append(center + rot_basis * Vector3(cos(a) * rx, sin(a) * ry, 0.0))
	for i in LOOP_SEGS:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % LOOP_SEGS]
		var col0 := col_hi if i % 2 == 0 else col_mid
		_add_ordnance_tube(st, p0, p1, tube_r, tube_r, 5, col0, col_lo)


static func _add_z_lathe(st: SurfaceTool, profile: Array[Vector2], segs: int,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	if profile.size() < 2:
		return
	var z_mid := (profile[0].y + profile[profile.size() - 1].y) * 0.5
	var ref_c := Vector3(0.0, 0.0, z_mid)
	for pi in range(profile.size() - 1):
		var r0 := profile[pi].x
		var z0 := profile[pi].y
		var r1 := profile[pi + 1].x
		var z1 := profile[pi + 1].y
		var t0 := float(pi) / maxf(float(profile.size() - 1), 1.0)
		var t1 := float(pi + 1) / maxf(float(profile.size() - 1), 1.0)
		var c0 := col_hi.lerp(col_mid, t0) if t0 < 0.5 else col_mid.lerp(col_lo, (t0 - 0.5) * 2.0)
		var c1 := col_hi.lerp(col_mid, t1) if t1 < 0.5 else col_mid.lerp(col_lo, (t1 - 0.5) * 2.0)
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p00 := Vector3(cos(a0) * r0, sin(a0) * r0, z0)
			var p10 := Vector3(cos(a1) * r0, sin(a1) * r0, z0)
			var p01 := Vector3(cos(a0) * r1, sin(a0) * r1, z1)
			var p11 := Vector3(cos(a1) * r1, sin(a1) * r1, z1)
			if r0 <= 0.0004 and r1 > 0.0004:
				_emit_outward_tri(st, p00, p01, p11, ref_c, c0, c1, c1)
			elif r1 <= 0.0004 and r0 > 0.0004:
				_emit_outward_tri(st, p00, p10, p01, ref_c, c0, c0, c1)
			elif r0 > 0.0004 and r1 > 0.0004:
				_emit_outward_quad(st, p00, p10, p11, p01, ref_c, c0, c0, c1, c1)


static func _build_splinter_mesh() -> ArrayMesh:
	# Asymmetric tapered jagged broken oak plank shard (honey-oak inner grain vs weathered dark exterior oak).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_honey_hi := Color(0.84, 0.62, 0.32)
	var col_honey_mid := Color(0.68, 0.46, 0.21)
	var col_bark_mid := Color(0.36, 0.21, 0.10)
	var col_bark_dark := Color(0.20, 0.12, 0.06)

	# 5 longitudinal stations along Z from fractured heel (-0.21) to tapered jagged needle tip (+0.23).
	# Each station defines a 6-vertex beveled plank section [top_l, top_r, right_mid, bot_r, bot_l, left_mid].
	var stations: Array[Array] = [
		[-0.205, -0.022, 0.028, 0.016, -0.015, 0.004],
		[-0.105, -0.036, 0.038, 0.021, -0.019, 0.002],
		[0.015, -0.033, 0.035, 0.020, -0.018, -0.003],
		[0.130, -0.020, 0.022, 0.014, -0.012, -0.006],
		[0.228, -0.003, 0.005, 0.004, -0.003, -0.002],
	]
	var rings: Array[Array] = []
	for s in stations:
		var z: float = float(s[0])
		var xl: float = float(s[1])
		var xr: float = float(s[2])
		var yt: float = float(s[3])
		var yb: float = float(s[4])
		var shear_x: float = float(s[5])
		var bev_x := (xr - xl) * 0.18
		var bev_y := (yt - yb) * 0.22
		rings.append([
			Vector3(xl + bev_x + shear_x, yt, z),
			Vector3(xr - bev_x + shear_x, yt, z),
			Vector3(xr + shear_x, yt - bev_y, z),
			Vector3(xr - bev_x + shear_x, yb, z),
			Vector3(xl + bev_x + shear_x, yb, z),
			Vector3(xl + shear_x, yb + bev_y, z),
		])

	# Face colors around the 6-vertex plank section: top = weathered dark hull oak, sides & underside = fresh snapped honey-oak!
	var seg_cols: Array[Color] = [
		col_bark_mid,   # 0->1 top weathered plank exterior
		col_bark_dark,  # 1->2 upper-right chamfer
		col_honey_hi,   # 2->3 fractured right wood grain
		col_honey_mid,  # 3->4 exposed honey-oak underside
		col_honey_hi,   # 4->5 fractured left wood grain
		col_bark_dark,  # 5->0 upper-left chamfer
	]

	for i in rings.size() - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var z_mid := (float(stations[i][0]) + float(stations[i + 1][0])) * 0.5
		var ref_ctr := Vector3(0.0, 0.0, z_mid)
		for k in 6:
			var k1 := (k + 1) % 6
			var c_seg := seg_cols[k]
			var c_tip := c_seg.lerp(col_honey_hi, 0.25 if i >= 2 else 0.0)
			_emit_outward_quad(st, r0[k] as Vector3, r0[k1] as Vector3, r1[k1] as Vector3, r1[k] as Vector3,
				ref_ctr, c_seg, c_seg, c_tip, c_tip)

	# Jagged fractured heel tip (-Z) and sharp spear splinter tip (+Z).
	var heel_apex := Vector3(-0.008, -0.004, -0.245)
	var heel_ring: Array = rings[0]
	var heel_ref := Vector3(0.0, 0.0, -0.15)
	for k in 6:
		var k1 := (k + 1) % 6
		_emit_outward_tri(st, heel_ring[k] as Vector3, heel_ring[k1] as Vector3, heel_apex,
			heel_ref, col_honey_mid, col_honey_hi, col_honey_hi)

	var tip_apex := Vector3(0.002, 0.001, 0.248)
	var tip_ring: Array = rings[rings.size() - 1]
	var tip_ref := Vector3(0.0, 0.0, 0.16)
	for k in 6:
		var k1 := (k + 1) % 6
		_emit_outward_tri(st, tip_ring[k] as Vector3, tip_ring[k1] as Vector3, tip_apex,
			tip_ref, col_honey_hi, col_honey_hi, col_honey_mid)

	# Secondary snapped side-splinter tooth jutting off the heel fracture for unmistakable silhouette.
	var tooth_base := Vector3(0.022, 0.004, -0.145)
	var tooth_tip := Vector3(0.042, 0.012, -0.228)
	var tb0 := tooth_base + Vector3(-0.008, 0.008, 0.0)
	var tb1 := tooth_base + Vector3(0.008, 0.008, 0.0)
	var tb2 := tooth_base + Vector3(0.008, -0.008, 0.0)
	var tb3 := tooth_base + Vector3(-0.008, -0.008, 0.0)
	var t_ref := (tooth_base + tooth_tip) * 0.5
	_emit_outward_tri(st, tb0, tb1, tooth_tip, t_ref, col_bark_mid, col_honey_hi, col_honey_hi)
	_emit_outward_tri(st, tb1, tb2, tooth_tip, t_ref, col_honey_hi, col_honey_mid, col_honey_hi)
	_emit_outward_tri(st, tb2, tb3, tooth_tip, t_ref, col_honey_mid, col_honey_mid, col_honey_hi)
	_emit_outward_tri(st, tb3, tb0, tooth_tip, t_ref, col_honey_hi, col_bark_mid, col_honey_hi)
	_emit_outward_quad(st, tb0, tb3, tb2, tb1, t_ref, col_honey_mid, col_honey_mid, col_honey_mid, col_honey_mid)

	st.generate_normals()
	return st.commit()


static func _add_hammered_sphere(st: SurfaceTool, radius: float, segs: int, rings: int,
		dent_amp: float, seed_phase: float,
		col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var grid: Array[Array] = []
	for ri in range(rings + 1):
		var v_frac := float(ri) / float(rings)
		var phi := v_frac * PI
		var sy := cos(phi)
		var sr := sin(phi)
		var row: Array[Vector3] = []
		for si in segs:
			var theta := TAU * float(si) / float(segs)
			var dir := Vector3(cos(theta) * sr, sy, sin(theta) * sr)
			# Deterministic hammered hand-forged dimples along the facets (poles stay seamless).
			var dent := 1.0 + dent_amp * sin(theta * 3.0 + phi * 4.0 + seed_phase) * cos(theta * 2.0 - phi * 3.0) * sr
			row.append(dir * (radius * dent))
		grid.append(row)

	for ri in rings:
		for si in segs:
			var si1 := (si + 1) % segs
			var p00: Vector3 = grid[ri][si] as Vector3
			var p01: Vector3 = grid[ri][si1] as Vector3
			var p10: Vector3 = grid[ri + 1][si] as Vector3
			var p11: Vector3 = grid[ri + 1][si1] as Vector3
			var avg_y := (p00.y + p01.y + p10.y + p11.y) * 0.25 / maxf(radius, 0.001)
			var jitter := 0.08 * sin(float(ri * 7 + si * 13) + seed_phase)
			var shade := clampf(0.5 + 0.5 * avg_y + jitter, 0.0, 1.0)
			var fc := col_lo.lerp(col_mid, clampf(shade * 2.0, 0.0, 1.0)) if shade < 0.5 \
				else col_mid.lerp(col_hi, clampf((shade - 0.5) * 2.0, 0.0, 1.0))
			if ri == 0:
				_emit_outward_tri(st, p00, p11, p10, Vector3.ZERO, col_hi, fc, fc)
			elif ri == rings - 1:
				_emit_outward_tri(st, p00, p01, p10, Vector3.ZERO, fc, fc, col_lo)
			else:
				_emit_outward_quad(st, p00, p01, p11, p10, Vector3.ZERO, fc, fc, fc, fc)


static func _add_forged_band(st: SurfaceTool, rot_basis: Basis, r_in: float, r_out: float, half_h: float,
		segs: int, col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var h_bev := half_h * 0.58
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var u0 := Vector3(cos(a0), 0.0, sin(a0))
		var u1 := Vector3(cos(a1), 0.0, sin(a1))

		var b0 := rot_basis * (u0 * r_in + Vector3(0.0, -half_h, 0.0))
		var b1 := rot_basis * (u1 * r_in + Vector3(0.0, -half_h, 0.0))
		var lo0 := rot_basis * (u0 * r_out + Vector3(0.0, -h_bev, 0.0))
		var lo1 := rot_basis * (u1 * r_out + Vector3(0.0, -h_bev, 0.0))
		var hi0 := rot_basis * (u0 * r_out + Vector3(0.0, h_bev, 0.0))
		var hi1 := rot_basis * (u1 * r_out + Vector3(0.0, h_bev, 0.0))
		var t0 := rot_basis * (u0 * r_in + Vector3(0.0, half_h, 0.0))
		var t1 := rot_basis * (u1 * r_in + Vector3(0.0, half_h, 0.0))

		_emit_outward_quad(st, b0, b1, lo1, lo0, Vector3.ZERO, col_lo, col_lo, col_mid, col_mid)
		_emit_outward_quad(st, lo0, lo1, hi1, hi0, Vector3.ZERO, col_mid, col_mid, col_hi, col_hi)
		_emit_outward_quad(st, hi0, hi1, t1, t0, Vector3.ZERO, col_hi, col_hi, col_mid, col_mid)


static func _add_offset_seam_ring(st: SurfaceTool, rot_basis: Basis, r_in: float, r_out: float,
		y_center: float, half_h: float, segs: int, col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var rad_scale := sqrt(maxf(0.1, 1.0 - (y_center / maxf(r_out, 0.001)) * (y_center / maxf(r_out, 0.001))))
	var ri := r_in * rad_scale
	var ro := r_out * rad_scale
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var u0 := Vector3(cos(a0), 0.0, sin(a0))
		var u1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0 := rot_basis * (u0 * ri + Vector3(0.0, y_center - half_h, 0.0))
		var b1 := rot_basis * (u1 * ri + Vector3(0.0, y_center - half_h, 0.0))
		var m0 := rot_basis * (u0 * ro + Vector3(0.0, y_center, 0.0))
		var m1 := rot_basis * (u1 * ro + Vector3(0.0, y_center, 0.0))
		var t0 := rot_basis * (u0 * ri + Vector3(0.0, y_center + half_h, 0.0))
		var t1 := rot_basis * (u1 * ri + Vector3(0.0, y_center + half_h, 0.0))
		_emit_outward_quad(st, b0, b1, m1, m0, Vector3.ZERO, col_lo, col_lo, col_hi, col_hi)
		_emit_outward_quad(st, m0, m1, t1, t0, Vector3.ZERO, col_hi, col_hi, col_mid, col_mid)


static func _add_faceted_rivet(st: SurfaceTool, base_pos: Vector3, dir: Vector3,
		radius: float, height: float, col_hi: Color, col_mid: Color, col_lo: Color) -> void:
	var n := dir.normalized()
	var ref_v := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := n.cross(ref_v).normalized()
	var v := n.cross(u).normalized()
	var apex := base_pos + n * height
	var ring: Array[Vector3] = []
	for k in 4:
		var ang := float(k) * PI * 0.5
		ring.append(base_pos + (u * cos(ang) + v * sin(ang)) * radius)
	for k in 4:
		var k1 := (k + 1) % 4
		_emit_outward_tri(st, ring[k], ring[k1], apex, Vector3.ZERO, col_lo, col_mid, col_hi)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
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
