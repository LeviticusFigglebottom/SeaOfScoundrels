class_name CrestSpray
extends Node3D
## Lightweight breaking-crest spray fans & backlit droplet wisps for `Ocean`.
##
## Samples the shared `Sea` wave set around the camera each frame to locate real
## steep breaking wave ridges (low Jacobian + high peak) and emits clusters of
## wind-sheared droplet wisps via `GPUParticles3D.emit_particle()`.
## Inactive in sheltered lagoons/flat water and at Ocean.Quality.LOW.

const SHADER := preload("res://src/ocean/crest_spray.gdshader")
const FOAM_TEX := preload("res://assets/generated/ocean/foam.png")

const QUALITY_AMOUNT := [0, 128, 256]
const QUALITY_PROBES := [0, 28, 46]
const QUALITY_RANGE := [0.0, 62.0, 86.0]
const MIN_SPRAY_DEPTH := 5.0

var material: ShaderMaterial
var particles: GPUParticles3D

var _ocean: Node3D
var _process_mat: ParticleProcessMaterial
var _quality: int = 2
var _rng := RandomNumberGenerator.new()
var _emit_accum: float = 0.0
var _warmed: bool = false

func _exit_tree() -> void:
	_ocean = null
	if particles != null and is_instance_valid(particles):
		particles.emitting = false
		particles.visible = false

func setup(ocean: Node3D) -> void:
	_ocean = ocean
	_rng.seed = 0x59AA7
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"foam_tex", FOAM_TEX)

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.gravity = Vector3(0.0, -2.8, 0.0)
	_process_mat.damping_min = 1.0
	_process_mat.damping_max = 1.9
	_process_mat.scale_min = 1.0
	_process_mat.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.55))
	curve.add_point(Vector2(0.32, 1.10))
	curve.add_point(Vector2(1.0, 1.75))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	_process_mat.scale_curve = curve_tex

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = material

	particles = GPUParticles3D.new()
	particles.name = "SprayParticles"
	particles.amount = QUALITY_AMOUNT[2]
	particles.lifetime = 1.35
	particles.local_coords = false
	particles.emitting = false
	particles.process_material = _process_mat
	particles.draw_pass_1 = quad
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-120.0, -24.0, -120.0), Vector3(240.0, 56.0, 240.0))
	add_child(particles)

func set_quality(q: int) -> void:
	_quality = clampi(q, 0, 2)
	if particles == null:
		return
	var active := _quality > 0
	visible = active
	particles.visible = active
	if active:
		particles.amount = QUALITY_AMOUNT[_quality]
	else:
		particles.restart()
		_warmed = false

func is_active() -> bool:
	return _quality > 0 and visible

func update(delta: float, cam: Camera3D, submerged: bool, crest_start: float) -> void:
	if _quality <= 0 or particles == null or cam == null:
		return
	visible = not submerged
	particles.visible = not submerged
	if submerged:
		return

	var cp := cam.global_position
	# Keep the emitter's visibility bounds centred on the camera while particles live in world space.
	particles.global_position = Vector3(cp.x, 0.0, cp.z)

	var storm := Sea.sea_state()
	var wind := Weather.wind_vector()
	var wind_speed := wind.length()
	var wind_factor := clampf(wind_speed / 12.0, 0.25, 1.75)
	material.set_shader_parameter(&"storm_level", storm)
	# Wind shears active spray fans downwind while gravity arches droplets back to the sea.
	_process_mat.gravity = Vector3(wind.x * 0.18, lerpf(-2.8, -1.9, storm), wind.z * 0.18)

	var hs := Sea.significant_height()
	# Never spawn open-ocean crest spray in flat water or sheltered lagoons.
	if Sea.amp_scale < Sea.AMP_CALM * 0.85 or hs < 1.55:
		return

	# Cluster emission budget scales smoothly with quality, wind speed, and storminess.
	var cluster_rate := lerpf(7.5, 22.0, storm) * wind_factor * (0.60 if _quality == 1 else 1.0)
	if not _warmed:
		_warmed = true
		_emit_accum = minf(cluster_rate * 0.35, 5.0)
	else:
		_emit_accum = minf(_emit_accum + delta * cluster_rate, 5.0)
	var clusters_wanted := int(_emit_accum)
	if clusters_wanted <= 0:
		return

	var fwd := -cam.global_basis.z
	var fwd_xz := Vector2(fwd.x, fwd.z)
	if fwd_xz.length_squared() < 1e-4:
		fwd_xz = Vector2(0.0, -1.0)
	else:
		fwd_xz = fwd_xz.normalized()
	var right_xz := Vector2(-fwd_xz.y, fwd_xz.x)

	var probes: int = QUALITY_PROBES[_quality]
	var max_dist: float = QUALITY_RANGE[_quality]
	# Collect nearby islands once per frame for strict depth >= 5.0 m lagoon protection.
	var nearby_islands: Array[Island] = []
	var tree := get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group(&"islands"):
			var isl := node as Island
			if isl == null:
				continue
			var reach := isl.seabed_radius + max_dist + 16.0
			var dx := isl.global_position.x - cp.x
			var dz := isl.global_position.z - cp.z
			if dx * dx + dz * dz <= reach * reach:
				nearby_islands.append(isl)
	# Breaking-crest gate: steep pinched fair-weather & storm ridges throw backlit mist.
	var jac_thr := minf(crest_start, 0.90)
	var min_h := hs * 0.24
	var clusters_done := 0
	var emit_flags := (
		GPUParticles3D.EMIT_FLAG_POSITION
		| GPUParticles3D.EMIT_FLAG_ROTATION_SCALE
		| GPUParticles3D.EMIT_FLAG_VELOCITY
		| GPUParticles3D.EMIT_FLAG_COLOR
	)

	var wind_xz := Vector2(wind.x, wind.z)
	var wind_dir2 := wind_xz.normalized() if wind_xz.length_squared() > 0.01 else Vector2(0.56, -0.83)

	for _i in probes:
		if clusters_done >= clusters_wanted:
			break
		var r := lerpf(7.0, max_dist, pow(_rng.randf(), 1.35))
		var ang := _rng.randf_range(-1.20, 1.20) if _rng.randf() < 0.85 else _rng.randf_range(-PI, PI)
		var dir2 := fwd_xz * cos(ang) + right_xz * sin(ang)
		var rx := cp.x + dir2.x * r
		var rz := cp.z + dir2.y * r
		var dj := Sea.displacement_and_jacobian(rx, rz)
		if dj.w > jac_thr or dj.y < min_h:
			continue
		var wp := Vector3(rx + dj.x, dj.y + 0.08, rz + dj.z)
		if _ocean != null and _ocean.call(&"is_point_in_dry_hull", wp):
			continue
		if _is_shallow_lagoon(wp, nearby_islands):
			continue
		var pinch := clampf((jac_thr - dj.w) / maxf(jac_thr - 0.56, 0.12), 0.0, 1.0)
		var orb := Sea.orbital_velocity(rx, rz)
		var ridge_dir := orb.normalized() if orb.length_squared() > 0.04 else wind_dir2
		var ridge_tan := Vector2(-ridge_dir.y, ridge_dir.x)

		# Emit a fan of 3..5 smaller wind-sheared droplet wisps along the breaking ridge.
		var wisp_count := _rng.randi_range(3, 5)
		for k in wisp_count:
			var along := (float(k) - float(wisp_count - 1) * 0.5) * _rng.randf_range(0.45, 0.85)
			var drift := _rng.randf_range(-0.15, 0.45)
			var wisp_pos := wp + Vector3(
				ridge_tan.x * along + wind_dir2.x * drift,
				_rng.randf_range(-0.06, 0.18),
				ridge_tan.y * along + wind_dir2.y * drift
			)
			var up_speed := lerpf(0.95, 2.55, storm) * (0.65 + 0.55 * pinch) * _rng.randf_range(0.70, 1.30)
			var vel := Vector3(
				orb.x * 0.45 + wind.x * 0.48 + _rng.randf_range(-0.5, 0.5),
				up_speed,
				orb.y * 0.45 + wind.z * 0.48 + _rng.randf_range(-0.5, 0.5)
			)
			var sz := lerpf(
				_rng.randf_range(0.45, 1.35),
				_rng.randf_range(0.80, 2.20),
				storm
			) * lerpf(0.78, 1.18, pinch)
			var strength := lerpf(0.48, 0.78, storm) * lerpf(0.75, 1.12, pinch) * clampf(wind_factor, 0.55, 1.20)
			var mist_mix := lerpf(0.14, 0.48, storm) * _rng.randf_range(0.6, 1.25)
			var xform := Transform3D(Basis.from_scale(Vector3.ONE * sz), wisp_pos)
			var col := Color(_rng.randf(), clampf(strength, 0.18, 0.85), clampf(mist_mix, 0.0, 1.0), 1.0)
			particles.emit_particle(xform, vel, col, Color(0.0, 0.0, 0.0, 0.0), emit_flags)
		clusters_done += 1

	_emit_accum = maxf(_emit_accum - float(clusters_done), 0.0)


static func _is_shallow_lagoon(wp: Vector3, islands: Array[Island]) -> bool:
	for isl in islands:
		var dx := wp.x - isl.global_position.x
		var dz := wp.z - isl.global_position.z
		var r := isl.seabed_radius + 4.0
		if dx * dx + dz * dz <= r * r and isl.seabed_depth(wp) < MIN_SPRAY_DEPTH:
			return true
	return false
