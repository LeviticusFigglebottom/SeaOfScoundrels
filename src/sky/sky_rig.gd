extends Node3D
## Drop-in sky: instance sky_rig.tscn anywhere in a scene and it owns the
## WorldEnvironment, sun and moon lights, sky shader, fog, rain and lightning.
## Everything follows the `Weather` autoload; this node holds no state of its
## own, so it is safe on every peer.
##
## Each frame it publishes linear-RGB global shader uniforms for other shaders:
##   sun_dir            unit vector towards the dominant light (sun by day, moon by night)
##   sun_color          that light's colour times its energy
##   sky_horizon_color  sky colour at the horizon (also the fog colour)
##   sky_zenith_color   sky colour overhead
##   ambient_color      ambient light colour times its energy

const Palette := preload("res://src/sky/sky_palette.gd")
const SKY_SHADER := preload("res://src/sky/sky.gdshader")
const RAIN_SHADER := preload("res://src/sky/rain.gdshader")
const BOLT_SHADER := preload("res://src/sky/lightning_bolt.gdshader")
const NOISE_TEX := preload("res://assets/generated/sky/cloud_noise.png")

# Must match the constants in sky.gdshader.
const SHAPE_SCALE := 0.42
const BIG_SCALE := 0.11
const DETAIL_SCALE := 1.25
## Lowest elevation (sine) the directional lights are allowed, so shadows near
## sunset stay finite.
const MIN_LIGHT_HEIGHT := 0.10

## Height of the cloud layer in metres: sets how fast wind carries clouds overhead.
@export var cloud_height: float = 650.0
## Directional shadow range in metres.
@export var shadow_distance: float = 260.0
## Rain streaks at full downpour.
@export var rain_particles: int = 5000
## Draw lightning bolts (the flash itself always shows).
@export var show_bolts: bool = true

var environment: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material: ShaderMaterial
## The palette computed this frame (see sky_palette.gd), for debugging and tools.
var palette: Dictionary = {}

var _flash_light: DirectionalLight3D
var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _rain_material: ShaderMaterial
var _bolt: MeshInstance3D
var _bolt_material: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_rain()
	_build_bolt()
	Weather.lightning_struck.connect(_on_lightning_struck)
	_update(true)

func _process(_delta: float) -> void:
	_update(false)


# --- Construction -------------------------------------------------------

func _build_environment() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter(&"noise_tex", NOISE_TEX)
	var sky := Sky.new()
	sky.sky_material = sky_material
	# The sky changes every frame; realtime mode spreads the radiance update out.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.35
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.5
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_sky_affect = 0.0
	environment.fog_sun_scatter = 0.12
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.1

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	add_child(we)

func _build_lights() -> void:
	sun = _make_light("Sun")
	moon = _make_light("Moon")
	moon.light_specular = 0.6
	_flash_light = _make_light("LightningFlash")
	_flash_light.shadow_enabled = false
	_flash_light.light_energy = 0.0
	_flash_light.visible = false

func _make_light(light_name: String) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = light_name
	l.shadow_enabled = true
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	l.directional_shadow_max_distance = shadow_distance
	l.directional_shadow_blend_splits = true
	l.shadow_blur = 1.4
	# The sky shader draws its own discs; keep the engine's lights out of it.
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(l)
	return l

func _build_rain() -> void:
	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process.emission_box_extents = Vector3(24.0, 1.0, 24.0)
	_rain_process.gravity = Vector3.ZERO
	_rain_process.spread = 2.5
	_rain_process.initial_velocity_min = 24.0
	_rain_process.initial_velocity_max = 30.0
	_rain_process.scale_min = 0.7
	_rain_process.scale_max = 1.3

	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	var streak := QuadMesh.new()
	streak.size = Vector2(0.035, 1.1)
	streak.material = _rain_material

	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_particles
	_rain.lifetime = 1.0
	_rain.preprocess = 1.0
	_rain.local_coords = false
	_rain.process_material = _rain_process
	_rain.draw_pass_1 = streak
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_rain.visibility_aabb = AABB(Vector3(-60, -50, -60), Vector3(120, 80, 120))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.emitting = false
	add_child(_rain)

func _build_bolt() -> void:
	_bolt_material = ShaderMaterial.new()
	_bolt_material.shader = BOLT_SHADER
	_bolt = MeshInstance3D.new()
	_bolt.name = "LightningBolt"
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.material_override = _bolt_material
	_bolt.visible = false
	_bolt.top_level = true
	add_child(_bolt)


# --- Per-frame update ---------------------------------------------------

func _update(first: bool) -> void:
	var sun_dir: Vector3 = Weather.sun_direction()
	var moon_dir: Vector3 = Weather.moon_direction()
	var phase: float = Weather.moon_phase()
	var moon_lit := 0.5 - 0.5 * cos(phase * TAU)
	var evening := smoothstep(11.0, 13.0, Weather.time_of_day)
	var cover: float = Weather.cloud_cover()
	var storm: float = clampf(Weather.storminess, 0.0, 1.0)
	var flash: float = Weather.lightning_flash
	var p := Palette.compute(sun_dir.y, moon_dir.y, evening, moon_lit, cover, storm)
	palette = p

	# Lights. Both may be on through twilight; only the stronger casts shadows.
	var sun_energy: float = p["sun_energy"]
	var moon_energy: float = p["moon_energy"]
	var sun_is_key := sun_energy >= moon_energy
	var sun_light_dir := _raised(sun_dir)
	var moon_light_dir := _raised(moon_dir)
	_aim(sun, sun_light_dir)
	_aim(moon, moon_light_dir)
	sun.light_color = p["sun_color"]
	sun.light_energy = sun_energy
	sun.visible = sun_energy > 0.004
	sun.shadow_enabled = sun_is_key
	moon.light_color = p["moon_color"]
	moon.light_energy = moon_energy
	moon.visible = moon_energy > 0.004
	moon.shadow_enabled = not sun_is_key

	_flash_light.visible = flash > 0.01
	if _flash_light.visible:
		_aim(_flash_light, (Weather.lightning_direction + Vector3(0.0, 0.8, 0.0)).normalized())
		_flash_light.light_color = p["flash_color"]
		_flash_light.light_energy = flash * 1.8

	# Environment.
	var horizon: Color = p["horizon"]
	var ambient: Color = p["ambient"]
	var flash_col: Color = p["flash_color"]
	var ambient_energy: float = p["ambient_energy"]
	environment.ambient_light_color = ambient.lerp(flash_col, minf(flash * 0.5, 1.0))
	environment.ambient_light_energy = ambient_energy + flash * 0.6
	environment.fog_light_color = horizon
	environment.fog_density = p["fog_density"]

	# Sky shader.
	var m := sky_material
	m.set_shader_parameter(&"zenith_color", _lin(p["zenith"]))
	m.set_shader_parameter(&"mid_color", _lin(p["mid"]))
	m.set_shader_parameter(&"horizon_color", _lin(horizon))
	m.set_shader_parameter(&"glow_color", _lin(p["glow"]))
	m.set_shader_parameter(&"glow_strength", p["glow_strength"])
	m.set_shader_parameter(&"sun_halo_color", _lin(p["sun_halo"]))
	m.set_shader_parameter(&"sun_dir", sun_dir)
	m.set_shader_parameter(&"sun_disc_color", _lin(p["sun_disc"]))
	m.set_shader_parameter(&"sun_visibility", lerpf(1.0, 0.25, storm))
	m.set_shader_parameter(&"moon_dir", moon_dir)
	m.set_shader_parameter(&"moon_color", _lin(Color(0.86, 0.91, 1.0)))
	m.set_shader_parameter(&"moon_phase", phase)
	m.set_shader_parameter(&"moon_visibility", smoothstep(-0.02, -0.14, sun_dir.y) * 0.75 + 0.25)
	m.set_shader_parameter(&"star_intensity", p["star_intensity"])
	# Stars wheel around the same axis the sun circles.
	var day_angle: float = (Weather.time_of_day - 6.0) / 24.0 * TAU
	m.set_shader_parameter(&"star_basis", Basis(Vector3(0.0, 0.0, 1.0), -day_angle))
	m.set_shader_parameter(&"cloud_cover", cover)
	m.set_shader_parameter(&"cloud_lit_color", _lin(p["cloud_lit"]))
	m.set_shader_parameter(&"cloud_shade_color", _lin(p["cloud_shade"]))
	m.set_shader_parameter(&"cloud_rim_color", _lin(p["cloud_rim"]))
	m.set_shader_parameter(&"light_dir", sun_dir if sun_is_key else moon_dir)
	m.set_shader_parameter(&"light_amount", clampf(absf(sun_energy - moon_energy) / 0.12, 0.0, 1.0))
	m.set_shader_parameter(&"storm", storm)
	m.set_shader_parameter(&"flash", flash)
	m.set_shader_parameter(&"flash_dir", Weather.lightning_direction)
	m.set_shader_parameter(&"flash_color", _lin(flash_col))
	# Cloud drift: wind carries the layer; wrapped per layer to stay precise.
	var drift: Vector2 = Weather.cloud_offset / cloud_height
	var churn: float = Weather.clock * 0.0025
	m.set_shader_parameter(&"scroll_shape", _wrap(drift * SHAPE_SCALE))
	m.set_shader_parameter(&"scroll_big", _wrap(Vector2(drift.y, drift.x) * BIG_SCALE * 0.8))
	m.set_shader_parameter(&"scroll_detail", _wrap(drift * DETAIL_SCALE * 1.12 + Vector2(churn, -churn)))
	var cirrus := Vector2(drift.x * 0.8 + drift.y * 0.6, drift.y * 0.8 - drift.x * 0.6)
	m.set_shader_parameter(&"scroll_cirrus", _wrap(cirrus * Vector2(0.1, 0.24) * 0.4))

	# Globals for everyone else's shaders (linear RGB).
	var key_dir := sun_light_dir if sun_is_key else moon_light_dir
	var key_col: Vector3 = _lin(p["sun_color"]) * sun_energy if sun_is_key \
			else _lin(p["moon_color"]) * moon_energy
	key_col += _lin(flash_col) * flash * 1.5
	RenderingServer.global_shader_parameter_set(&"sun_dir", key_dir)
	RenderingServer.global_shader_parameter_set(&"sun_color", key_col)
	RenderingServer.global_shader_parameter_set(&"sky_horizon_color", _lin(horizon))
	RenderingServer.global_shader_parameter_set(&"sky_zenith_color", _lin(p["zenith"]))
	RenderingServer.global_shader_parameter_set(&"ambient_color",
			_lin(environment.ambient_light_color) * environment.ambient_light_energy)

	_update_rain(flash, first)
	_bolt_material.set_shader_parameter(&"intensity", flash)
	if _bolt.visible and flash <= 0.01:
		_bolt.visible = false

func _update_rain(flash: float, first: bool) -> void:
	var rain: float = Weather.rain_intensity()
	_rain.emitting = rain > 0.01
	_rain.visible = _rain.emitting
	if not _rain.emitting:
		return
	_rain.amount_ratio = clampf(rain, 0.05, 1.0)
	var wind: Vector3 = Weather.wind_vector()
	var fall := Vector3(wind.x * 0.55, -26.0, wind.z * 0.55)
	_rain_process.direction = fall.normalized()
	_rain_material.set_shader_parameter(&"opacity", lerpf(0.22, 0.5, rain))
	_rain_material.set_shader_parameter(&"flash", flash)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		# Spawn above and upwind so streaks cross the view on their way down.
		var ahead := -cam.global_basis.z
		ahead.y = 0.0
		var at := cam.global_position + ahead * 8.0 + Vector3(0.0, 13.0, 0.0) \
				- Vector3(fall.x, 0.0, fall.z) * 0.5
		_rain.global_position = at
		if first:
			_rain.restart()

func _on_lightning_struck(direction: Vector3, distance: float, _intensity: float) -> void:
	if not show_bolts:
		return
	var cam := get_viewport().get_camera_3d()
	var origin := cam.global_position if cam != null else global_position
	origin.y = 0.0
	_bolt.mesh = _make_bolt_mesh(origin + direction * distance, direction, distance)
	_bolt.global_transform = Transform3D.IDENTITY
	_bolt.visible = true


# --- Helpers ------------------------------------------------------------

static func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)

static func _wrap(v: Vector2) -> Vector2:
	return Vector2(fposmod(v.x, 1.0), fposmod(v.y, 1.0))

static func _raised(dir: Vector3) -> Vector3:
	## Keep a light direction above the horizon so shadows never run to infinity.
	var d := dir
	d.y = maxf(d.y, MIN_LIGHT_HEIGHT)
	return d.normalized()

static func _aim(light: DirectionalLight3D, towards_light: Vector3) -> void:
	var up := Vector3.UP if absf(towards_light.y) < 0.99 else Vector3.RIGHT
	light.global_basis = Basis.looking_at(-towards_light, up)

func _make_bolt_mesh(foot: Vector3, direction: Vector3, distance: float) -> ArrayMesh:
	## A jagged ribbon from the cloud base to the sea with a few forks, built
	## facing the viewer. Width grows with distance so far bolts stay readable.
	_rng.randomize()
	var side := direction.cross(Vector3.UP).normalized()
	var top := foot + Vector3(0.0, _rng.randf_range(520.0, 760.0), 0.0) \
			+ side * _rng.randf_range(-160.0, 160.0)
	var width := clampf(distance * 0.007, 1.5, 18.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := _jagged(top, foot, side, 6, 0.16)
	_ribbon(st, trunk, side, width, 1.0)
	for i in _rng.randi_range(2, 4):
		var at: int = _rng.randi_range(4, trunk.size() - 12)
		var from: Vector3 = trunk[at]
		var reach := (from.y - foot.y) * _rng.randf_range(0.25, 0.55)
		var to := from + Vector3(0.0, -reach, 0.0) \
				+ side * reach * _rng.randf_range(0.35, 0.9) * (1.0 if _rng.randf() > 0.5 else -1.0)
		_ribbon(st, _jagged(from, to, side, 4, 0.2), side, width * 0.5, 0.55)
	return st.commit()

func _jagged(a: Vector3, b: Vector3, side: Vector3, levels: int, roughness: float) -> PackedVector3Array:
	## Midpoint displacement between a and b, sideways as seen by the viewer.
	var pts := PackedVector3Array([a, b])
	var spread := a.distance_to(b) * roughness
	for _l in levels:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			var mid := (pts[i] + pts[i + 1]) * 0.5
			mid += side * _rng.randf_range(-spread, spread)
			mid.y += _rng.randf_range(-spread, spread) * 0.25
			next.append(pts[i])
			next.append(mid)
		next.append(pts[pts.size() - 1])
		pts = next
		spread *= 0.52
	return pts

func _ribbon(st: SurfaceTool, pts: PackedVector3Array, side: Vector3, width: float, strength: float) -> void:
	var col := Color(strength, strength, strength)
	for i in pts.size() - 1:
		# Taper towards the tip.
		var w0 := width * lerpf(1.0, 0.45, float(i) / float(pts.size()))
		var w1 := width * lerpf(1.0, 0.45, float(i + 1) / float(pts.size()))
		var a0 := pts[i] - side * w0
		var a1 := pts[i] + side * w0
		var b0 := pts[i + 1] - side * w1
		var b1 := pts[i + 1] + side * w1
		for v: Array in [[a0, 0.0], [a1, 1.0], [b0, 0.0], [a1, 1.0], [b1, 1.0], [b0, 0.0]]:
			st.set_color(col)
			st.set_uv(Vector2(v[1], 0.0))
			st.add_vertex(v[0])
