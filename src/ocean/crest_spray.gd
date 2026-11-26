class_name CrestSpray
extends Node3D
## Lightweight breaking-crest mist & spray puffs for `Ocean`.
##
## Samples the shared `Sea` wave set around the camera each frame to find real
## breaking wave crests (low Jacobian + raised peak) and emits billboard mist
## and droplet puffs via `GPUParticles3D.emit_particle()` that inherit orbital
## and wind velocity, glow warm when backlit, and scale with wind & storminess.
## Active at Ocean.Quality.MEDIUM and HIGH; completely disabled at LOW.

const SHADER := preload("res://src/ocean/crest_spray.gdshader")
const FOAM_TEX := preload("res://assets/generated/ocean/foam.png")

const QUALITY_AMOUNT := [0, 112, 224]
const QUALITY_PROBES := [0, 20, 36]
const QUALITY_RANGE := [0.0, 68.0, 92.0]

var material: ShaderMaterial
var particles: GPUParticles3D

var _ocean: Node3D
var _process_mat: ParticleProcessMaterial
var _quality: int = 2
var _rng := RandomNumberGenerator.new()
var _emit_accum: float = 0.0
var _warmed: bool = false

func setup(ocean: Node3D) -> void:
	_ocean = ocean
	_rng.seed = 0x59AA7
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"foam_tex", FOAM_TEX)

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.gravity = Vector3(0.0, -2.5, 0.0)
	_process_mat.damping_min = 0.85
	_process_mat.damping_max = 1.65
	_process_mat.scale_min = 1.0
	_process_mat.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.48))
	curve.add_point(Vector2(0.35, 1.15))
	curve.add_point(Vector2(1.0, 1.95))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	_process_mat.scale_curve = curve_tex

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = material

	particles = GPUParticles3D.new()
	particles.name = "SprayParticles"
	particles.amount = QUALITY_AMOUNT[2]
	particles.lifetime = 1.55
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
	# Gentle wind acceleration on active puffs so spray shears downwind off crests.
	_process_mat.gravity = Vector3(wind.x * 0.14, lerpf(-2.4, -1.7, storm), wind.z * 0.14)

	var hs := Sea.significant_height()
	if hs < 0.65:
		return  # flat or sheltered lagoon: no open-ocean breaking spray

	# Emission budget scales smoothly with quality, wind speed, and storminess.
	var base_rate := lerpf(18.0, 72.0, storm) * wind_factor * (0.62 if _quality == 1 else 1.0)
	if not _warmed:
		_warmed = true
		_emit_accum = minf(base_rate * 0.35, 16.0)
	else:
		_emit_accum = minf(_emit_accum + delta * base_rate, 14.0)
	var to_emit := int(_emit_accum)
	if to_emit <= 0:
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
	var jac_thr := minf(crest_start + lerpf(0.035, 0.01, storm), 0.96)
	var min_h := maxf(0.32, hs * lerpf(0.20, 0.14, storm))
	var emitted := 0
	var emit_flags := (
		GPUParticles3D.EMIT_FLAG_POSITION
		| GPUParticles3D.EMIT_FLAG_ROTATION_SCALE
		| GPUParticles3D.EMIT_FLAG_VELOCITY
		| GPUParticles3D.EMIT_FLAG_COLOR
	)

	for _i in probes:
		if emitted >= to_emit:
			break
		# Bias 85% of probes into the camera's forward cone so visible crests stay lively.
		var r := lerpf(6.0, max_dist, pow(_rng.randf(), 1.35))
		var ang := _rng.randf_range(-1.25, 1.25) if _rng.randf() < 0.85 else _rng.randf_range(-PI, PI)
		var dir2 := fwd_xz * cos(ang) + right_xz * sin(ang)
		var rx := cp.x + dir2.x * r
		var rz := cp.z + dir2.y * r
		var dj := Sea.displacement_and_jacobian(rx, rz)
		if dj.w > jac_thr or dj.y < min_h:
			continue
		var wp := Vector3(rx + dj.x, dj.y + 0.14, rz + dj.z)
		if _ocean != null and _ocean.call(&"is_point_in_dry_hull", wp):
			continue
		var pinch := clampf((jac_thr - dj.w) / maxf(jac_thr - 0.58, 0.12), 0.0, 1.0)
		var orb := Sea.orbital_velocity(rx, rz)
		var up_speed := lerpf(1.4, 3.8, storm) * (0.65 + 0.65 * pinch) * _rng.randf_range(0.75, 1.25)
		var vel := Vector3(
			orb.x * 0.55 + wind.x * 0.36 + _rng.randf_range(-0.6, 0.6),
			up_speed,
			orb.y * 0.55 + wind.z * 0.36 + _rng.randf_range(-0.6, 0.6)
		)
		var sz := lerpf(1.35, 3.6, storm) * lerpf(0.75, 1.35, pinch) * _rng.randf_range(0.78, 1.28)
		var strength := lerpf(0.32, 0.68, storm) * lerpf(0.65, 1.15, pinch) * clampf(wind_factor, 0.5, 1.2)
		var mist_mix := lerpf(0.18, 0.55, storm) * _rng.randf_range(0.6, 1.2)
		var xform := Transform3D(Basis.from_scale(Vector3.ONE * sz), wp)
		var col := Color(_rng.randf(), clampf(strength, 0.12, 0.85), clampf(mist_mix, 0.0, 1.0), 1.0)
		particles.emit_particle(xform, vel, col, Color(0.0, 0.0, 0.0, 0.0), emit_flags)
		emitted += 1

	_emit_accum = maxf(_emit_accum - float(emitted), 0.0)
