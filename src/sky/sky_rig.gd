extends Node3D
## Drop-in sky: instance sky_rig.tscn anywhere in a scene and it owns the
## WorldEnvironment, sun and moon lights, sky shader with volumetric clouds,
## cloud shadows, fog, rain, mist and lightning. Everything follows the
## `Weather` autoload; this node holds no replicated state, so it is safe on
## every peer.
##
## Each frame it publishes global shader uniforms for other shaders (linear RGB):
##   sun_dir            unit vector towards the dominant light (sun by day, moon by night)
##   sun_color          that light's colour times its energy (cloud shadow at the camera included)
##   sky_horizon_color  sky colour at the horizon (also the fog colour)
##   sky_zenith_color   sky colour overhead
##   ambient_color      ambient light colour times its energy
##   cloud_shadow_tex, cloud_shadow_params   see cloud_shadow.gdshaderinc
##
## Shelter from rain: put an Area3D in group `shelter` with a BoxShape3D
## CollisionShape3D around any covered space (below deck, under a roof). Rain,
## splashes and mist are not drawn inside the four nearest such boxes, and
## `camera_sheltered` tells audio whether the listener is under cover.

enum CloudQuality { LOW, MEDIUM, HIGH }

const Palette := preload("res://src/sky/sky_palette.gd")
const CloudField := preload("res://src/sky/cloud_field.gd")
const SKY_SHADERS: Array[Shader] = [
	preload("res://src/sky/sky_low.gdshader"),
	preload("res://src/sky/sky_medium.gdshader"),
	preload("res://src/sky/sky_high.gdshader"),
]
const SHADOW_BAKE_SHADER := preload("res://src/sky/cloud_shadow_bake.gdshader")
const RAIN_SHADER := preload("res://src/sky/rain.gdshader")
const SPLASH_SHADER := preload("res://src/sky/rain_splash.gdshader")
const MIST_SHADER := preload("res://src/sky/rain_mist.gdshader")
const CURTAIN_SHADER := preload("res://src/sky/rain_curtain.gdshader")
const BOLT_SHADER := preload("res://src/sky/lightning_bolt.gdshader")
const NOISE_TEX := preload("res://assets/generated/sky/cloud_noise.png")
const CLOUD_MAP := preload("res://assets/generated/sky/cloud_map.png")
const CLOUD_VOLUME := preload("res://assets/generated/sky/cloud_volume.png")

## Lowest elevation (sine) the directional lights are allowed, so shadows near
## sunset stay finite.
const MIN_LIGHT_HEIGHT := 0.10
## Side of the baked cloud shadow square in metres, and its resolution.
const SHADOW_EXTENT := 16000.0
const SHADOW_RES := 512
const MAX_SHELTERS := 4

## Cloud rendering cost: LOW marches at quarter resolution, MEDIUM at half,
## HIGH at full resolution with finer noise (the no-compromise look).
@export var cloud_quality: CloudQuality = CloudQuality.MEDIUM:
	set(v):
		cloud_quality = v
		if sky_material != null:
			sky_material.shader = SKY_SHADERS[v]
## Directional shadow range in metres.
@export var shadow_distance: float = 260.0
## Rain streaks at full downpour (near layer; the far layer adds 40% more).
@export var rain_particles: int = 5000
## Draw lightning bolts (the flash itself always shows).
@export var show_bolts: bool = true
## Keep `Weather.focus_position` on the active camera, so `Weather.storminess`
## is the weather where the player is. Turn off to set the focus yourself.
@export var track_camera_focus: bool = true
## Rain splashes ride the `Sea` wave surface. Turn off over a flat test sea.
@export var splashes_follow_sea: bool = true

var environment: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material: ShaderMaterial
## The palette computed this frame (see sky_palette.gd), for debugging and tools.
var palette: Dictionary = {}
## True while the camera is inside a `shelter` area.
var camera_sheltered: bool = false
## Fraction of the key light reaching the camera through the clouds this frame.
var light_at_camera: float = 1.0
## The clouds as a CPU-side function, for `cloud_light_at()`.
var cloud_field: RefCounted = CloudField.new()

var _flash_light: DirectionalLight3D
var _rain: GPUParticles3D
var _rain_far: GPUParticles3D
var _splash: GPUParticles3D
var _mist: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _rain_far_process: ParticleProcessMaterial
var _mist_process: ParticleProcessMaterial
var _rain_material: ShaderMaterial
var _rain_far_material: ShaderMaterial
var _splash_material: ShaderMaterial
var _mist_material: ShaderMaterial
var _weather_materials: Array[ShaderMaterial] = []
var _curtain: MeshInstance3D
var _curtain_material: ShaderMaterial
var _bolt: MeshInstance3D
var _bolt_material: ShaderMaterial
var _shadow_viewport: SubViewport
var _shadow_material: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_environment()
	_build_shadow_bake()
	_build_lights()
	_build_rain()
	_build_curtain()
	_build_bolt()
	Weather.lightning_struck.connect(_on_lightning_struck)
	_update(true)

func _process(_delta: float) -> void:
	_update(false)

func cloud_light_at(world_pos: Vector3) -> float:
	## Fraction of the key light (sun or moon) reaching a point near the ground
	## through the clouds: 1 in open sun, about 0.2 under thick cloud.
	return cloud_field.light_at(world_pos, _key_direction())


# --- Construction -------------------------------------------------------

func _build_environment() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADERS[cloud_quality]
	sky_material.set_shader_parameter(&"noise_tex", NOISE_TEX)
	sky_material.set_shader_parameter(&"cloud_map", CLOUD_MAP)
	sky_material.set_shader_parameter(&"cloud_volume", CLOUD_VOLUME)
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
	# Distant things take the colour of the sky behind them, not one flat fog
	# colour: warm towards a low sun, blue away from it.
	environment.fog_aerial_perspective = 0.45
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.1

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	add_child(we)

func _build_shadow_bake() -> void:
	_shadow_viewport = SubViewport.new()
	_shadow_viewport.name = "CloudShadowBake"
	_shadow_viewport.size = Vector2i(SHADOW_RES, SHADOW_RES)
	_shadow_viewport.disable_3d = true
	_shadow_viewport.transparent_bg = false
	_shadow_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = SHADOW_BAKE_SHADER
	_shadow_material.set_shader_parameter(&"cloud_map", CLOUD_MAP)
	_shadow_material.set_shader_parameter(&"cloud_volume", CLOUD_VOLUME)
	_shadow_material.set_shader_parameter(&"floor_light", CloudField.FLOOR_LIGHT)
	var rect := ColorRect.new()
	rect.size = Vector2(SHADOW_RES, SHADOW_RES)
	rect.material = _shadow_material
	_shadow_viewport.add_child(rect)
	add_child(_shadow_viewport)
	var tex := _shadow_viewport.get_texture()
	sky_material.set_shader_parameter(&"shadow_map", tex)
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_tex", tex.get_rid())

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
	# Near streaks: a box around the camera.
	_rain_process = _streak_process(Vector3(22.0, 1.0, 22.0), 24.0, 31.0)
	_rain_material = _weather_material(RAIN_SHADER)
	_rain = _streak_emitter("Rain", rain_particles, 1.0, _rain_process, _rain_material,
			Vector2(0.034, 1.15), AABB(Vector3(-60, -50, -60), Vector3(120, 80, 120)))
	# Far streaks: bigger, fainter, further out, so the rain has depth.
	_rain_far_process = _streak_process(Vector3(75.0, 2.0, 75.0), 26.0, 34.0)
	_rain_far_material = _weather_material(RAIN_SHADER)
	_rain_far = _streak_emitter("RainFar", int(rain_particles * 0.4), 1.6, _rain_far_process,
			_rain_far_material, Vector2(0.11, 4.2), AABB(Vector3(-160, -90, -160), Vector3(320, 140, 320)))

	# Splashes where drops hit the sea.
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(26.0, 0.0, 26.0)
	sp.gravity = Vector3.ZERO
	sp.initial_velocity_min = 0.0
	sp.initial_velocity_max = 0.0
	sp.scale_min = 0.5
	sp.scale_max = 1.3
	_splash_material = _weather_material(SPLASH_SHADER)
	_splash_material.set_shader_parameter(&"follow_sea", 1.0 if splashes_follow_sea else 0.0)
	Sea.bind_material(_splash_material)
	var ring := QuadMesh.new()
	ring.size = Vector2(1.0, 1.0)
	ring.material = _splash_material
	_splash = _emitter("RainSplash", 2600, 0.3, sp, ring, AABB(Vector3(-60, -12, -60), Vector3(120, 24, 120)))

	# Mist and spindrift torn off the surface by the wind.
	_mist_process = ParticleProcessMaterial.new()
	_mist_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mist_process.emission_box_extents = Vector3(70.0, 1.2, 70.0)
	_mist_process.gravity = Vector3(0.0, 0.25, 0.0)
	_mist_process.spread = 12.0
	_mist_process.scale_min = 0.7
	_mist_process.scale_max = 1.5
	_mist_material = _weather_material(MIST_SHADER)
	var puff := QuadMesh.new()
	puff.size = Vector2(16.0, 7.0)
	puff.material = _mist_material
	_mist = _emitter("RainMist", 110, 5.0, _mist_process, puff, AABB(Vector3(-180, -20, -180), Vector3(360, 60, 360)))

func _streak_process(extents: Vector3, v_min: float, v_max: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = Vector3.ZERO
	pm.spread = 3.0
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	return pm

func _streak_emitter(node_name: String, amount: int, lifetime: float, pm: ParticleProcessMaterial,
		mat: ShaderMaterial, size: Vector2, aabb: AABB) -> GPUParticles3D:
	var streak := QuadMesh.new()
	streak.size = size
	streak.material = mat
	var e := _emitter(node_name, amount, lifetime, pm, streak, aabb)
	e.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	return e

func _emitter(node_name: String, amount: int, lifetime: float, pm: ParticleProcessMaterial,
		mesh: Mesh, aabb: AABB) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.name = node_name
	e.amount = maxi(amount, 1)
	e.lifetime = lifetime
	e.preprocess = lifetime
	e.local_coords = false
	e.process_material = pm
	e.draw_pass_1 = mesh
	e.visibility_aabb = aabb
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.emitting = false
	e.visible = false
	add_child(e)
	return e

func _weather_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	_weather_materials.append(m)
	return m

func _build_curtain() -> void:
	## The storm cell's wall of rain: a unit open cylinder scaled to the cell.
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 64
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	_curtain_material = ShaderMaterial.new()
	_curtain_material.shader = CURTAIN_SHADER
	_curtain_material.set_shader_parameter(&"streak_tex", CLOUD_MAP)
	_curtain = MeshInstance3D.new()
	_curtain.name = "RainCurtain"
	_curtain.mesh = mesh
	_curtain.material_override = _curtain_material
	_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_curtain.top_level = true
	_curtain.visible = false
	add_child(_curtain)

func _update_curtain(flash_here: float) -> void:
	var cell_rain := smoothstep(0.4, 0.9, Weather.storm_intensity)
	_curtain.visible = cell_rain > 0.01
	if not _curtain.visible:
		return
	var radius: float = Weather.storm_radius * 0.82
	var height := CloudField.BASE_STORM + 220.0
	_curtain.global_transform = Transform3D(Basis.from_scale(Vector3(radius, height, radius)),
			Vector3(Weather.storm_center.x, height * 0.5 - 4.0, Weather.storm_center.z))
	var m := _curtain_material
	var wind: float = Weather.wind_vector().length()
	m.set_shader_parameter(&"tint", _lin(palette["storm_cloud_shade"]).lerp(_lin(palette["horizon"]), 0.1))
	m.set_shader_parameter(&"opacity", 0.9 * cell_rain)
	m.set_shader_parameter(&"around", maxf(roundf(radius * TAU / 420.0), 6.0))
	m.set_shader_parameter(&"slant", clampf(wind * 0.02, 0.0, 0.6))
	m.set_shader_parameter(&"fall", fposmod(Weather.clock * 0.09, 1.0))
	m.set_shader_parameter(&"flash", flash_here)

func _build_bolt() -> void:
	_bolt_material = ShaderMaterial.new()
	_bolt_material.shader = BOLT_SHADER
	_bolt = MeshInstance3D.new()
	_bolt.name = "LightningBolt"
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.material_override = _bolt_material
	_bolt.visible = false
	_bolt.top_level = true
	_bolt.extra_cull_margin = 16000.0
	add_child(_bolt)


# --- Per-frame update ---------------------------------------------------

func _update(first: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else global_position
	if track_camera_focus and cam != null:
		Weather.set_focus(cam_pos)

	var sun_dir: Vector3 = Weather.sun_direction()
	var moon_dir: Vector3 = Weather.moon_direction()
	var cover: float = Weather.cloud_cover()
	var storm: float = clampf(Weather.storminess, 0.0, 1.0)
	var flash: float = Weather.lightning_flash
	var flash_here: float = Weather.lightning_illumination(cam_pos)
	var p := Palette.compute(sun_dir.y, moon_dir.y, evening(Weather.time_of_day),
			Weather.moon_illumination(), cover, storm)
	palette = p

	# Lights. Both may be on through twilight; only the stronger casts shadows.
	var sun_energy: float = p["sun_energy"]
	var moon_energy: float = p["moon_energy"]
	var sun_is_key := sun_energy >= moon_energy
	var sun_light_dir := _raised(sun_dir)
	var moon_light_dir := _raised(moon_dir)
	var key_dir := sun_light_dir if sun_is_key else moon_light_dir
	# Cloud shadow where the camera is dims the light for everything nearby.
	light_at_camera = cloud_field.light_at(cam_pos, key_dir)
	_aim(sun, sun_light_dir)
	_aim(moon, moon_light_dir)
	sun.light_color = p["sun_color"]
	sun.light_energy = sun_energy * light_at_camera
	sun.visible = sun_energy > 0.004
	sun.shadow_enabled = sun_is_key
	moon.light_color = p["moon_color"]
	moon.light_energy = moon_energy * light_at_camera
	moon.visible = moon_energy > 0.004
	moon.shadow_enabled = not sun_is_key

	_flash_light.visible = flash_here > 0.004
	if _flash_light.visible:
		_aim(_flash_light, (Weather.lightning_direction + Vector3(0.0, 0.9, 0.0)).normalized())
		_flash_light.light_color = p["flash_color"]
		_flash_light.light_energy = flash_here * 2.6

	# Environment.
	var horizon: Color = p["horizon"]
	var ambient: Color = p["ambient"]
	var flash_col: Color = p["flash_color"]
	var ambient_energy: float = p["ambient_energy"]
	var rain: float = Weather.rain_intensity()
	environment.ambient_light_color = ambient.lerp(flash_col, minf(flash_here * 0.6, 1.0))
	environment.ambient_light_energy = ambient_energy + flash_here * 0.7
	environment.fog_light_color = horizon
	environment.fog_density = p["fog_density"]
	# Rain beats a layer of mist out of the sea surface.
	environment.fog_height = 14.0
	environment.fog_height_density = rain * 0.012

	_update_sky(p, sun_dir, moon_dir, sun_is_key, storm, cover, rain, flash)
	_update_shadow_bake(cam_pos, key_dir)

	# Globals for everyone else's shaders (linear RGB).
	var key_col: Vector3 = (_lin(p["sun_color"]) * sun_energy if sun_is_key
			else _lin(p["moon_color"]) * moon_energy) * light_at_camera
	key_col += _lin(flash_col) * flash_here * 2.0
	RenderingServer.global_shader_parameter_set(&"sun_dir", key_dir)
	RenderingServer.global_shader_parameter_set(&"sun_color", key_col)
	RenderingServer.global_shader_parameter_set(&"sky_horizon_color", _lin(horizon))
	RenderingServer.global_shader_parameter_set(&"sky_zenith_color", _lin(p["zenith"]))
	RenderingServer.global_shader_parameter_set(&"ambient_color",
			_lin(environment.ambient_light_color) * environment.ambient_light_energy)

	_update_shelters(cam_pos)
	_update_rain(cam, rain, flash_here, first)
	_update_curtain(flash_here)
	_bolt_material.set_shader_parameter(&"intensity", flash)
	if _bolt.visible and flash <= 0.01:
		_bolt.visible = false

func _update_sky(p: Dictionary, sun_dir: Vector3, moon_dir: Vector3,
		sun_is_key: bool, storm: float, cover: float, rain: float, flash: float) -> void:
	var m := sky_material
	var sun_energy: float = p["sun_energy"]
	var moon_energy: float = p["moon_energy"]
	m.set_shader_parameter(&"zenith_color", _lin(p["zenith"]))
	m.set_shader_parameter(&"mid_color", _lin(p["mid"]))
	m.set_shader_parameter(&"horizon_color", _lin(p["horizon"]))
	m.set_shader_parameter(&"glow_color", _lin(p["glow"]))
	m.set_shader_parameter(&"glow_strength", p["glow_strength"])
	m.set_shader_parameter(&"sun_halo_color", _lin(p["sun_halo"]))
	m.set_shader_parameter(&"sun_dir", sun_dir)
	m.set_shader_parameter(&"sun_disc_color", _lin(p["sun_disc"]))
	m.set_shader_parameter(&"sun_visibility", lerpf(1.0, 0.25, storm))
	m.set_shader_parameter(&"moon_dir", moon_dir)
	m.set_shader_parameter(&"moon_color", _lin(Color(0.86, 0.91, 1.0)))
	# A pale day moon; full strength once the sun is down.
	m.set_shader_parameter(&"moon_visibility", smoothstep(0.1, -0.14, sun_dir.y) * 0.72 + 0.28)
	m.set_shader_parameter(&"star_intensity", p["star_intensity"])
	# Stars wheel around the same axis the sun circles.
	var day_angle: float = (Weather.time_of_day - 6.0) / 24.0 * TAU
	m.set_shader_parameter(&"star_basis", Basis(Vector3(0.0, 0.0, 1.0), -day_angle))
	_set_meteor(m, p["star_intensity"])
	m.set_shader_parameter(&"cloud_lit_color", _lin(p["cloud_lit"]))
	m.set_shader_parameter(&"cloud_shade_color", _lin(p["cloud_shade"]))
	m.set_shader_parameter(&"cloud_rim_color", _lin(p["cloud_rim"]))
	m.set_shader_parameter(&"storm_lit_color", _lin(p["storm_cloud_lit"]))
	m.set_shader_parameter(&"storm_shade_color", _lin(p["storm_cloud_shade"]))
	m.set_shader_parameter(&"light_dir", sun_dir if sun_is_key else moon_dir)
	m.set_shader_parameter(&"light_amount", clampf(absf(sun_energy - moon_energy) / 0.12, 0.0, 1.0))
	m.set_shader_parameter(&"cloud_fog", float(p["cloud_fog"]))
	m.set_shader_parameter(&"storm", storm)
	m.set_shader_parameter(&"rain", rain)
	m.set_shader_parameter(&"rain_slant", clampf(Weather.wind_vector().length() * 0.035, 0.0, 1.2))
	m.set_shader_parameter(&"flash", flash)
	var bolt_at: Vector3 = Weather.lightning_position
	var base_alt := _cloud_base()
	m.set_shader_parameter(&"flash_pos", Vector3(bolt_at.x,
			base_alt + (900.0 if Weather.lightning_is_sheet else 420.0), bolt_at.z))
	m.set_shader_parameter(&"flash_color", _lin(p["flash_color"]))
	m.set_shader_parameter(&"cirrus_amount", 0.26 * (1.0 - smoothstep(0.5, 0.95, cover)))
	var drift: Vector2 = Weather.cloud_offset
	m.set_shader_parameter(&"cirrus_scroll", _wrap(
			Vector2(drift.x * 0.8 + drift.y * 0.6, drift.y * 0.8 - drift.x * 0.6) / 90000.0))
	m.set_shader_parameter(&"ray_strength", float(p["ray_strength"]))
	# Altitudes the march must cover: lower and deeper when anything is stormy.
	var in_front: bool = Weather.front_progress < 1.0
	var any_storm: float = maxf(maxf(Weather.base_storminess, Weather.storm_intensity),
			Weather.front_from.y if in_front else 0.0)
	var cl: float = maxf(Weather.cloudiness, Weather.front_from.x if in_front else 0.0)
	var heavy := smoothstep(0.2, 0.9, any_storm)
	var tower := clampf(0.2 + 0.9 * smoothstep(0.25, 0.75, cl) + 2.0 * any_storm, 0.0, 1.0)
	m.set_shader_parameter(&"slab_base", lerpf(CloudField.BASE_FAIR - 70.0, CloudField.BASE_STORM - 320.0, heavy))
	m.set_shader_parameter(&"slab_top", CloudField.BASE_FAIR + 450.0 + 2500.0 * tower)
	_set_field(m)

func _set_field(m: ShaderMaterial) -> void:
	## Everything cloud_field.gdshaderinc needs, for the sky and the shadow bake.
	m.set_shader_parameter(&"cloud_drift", Weather.cloud_offset)
	var evo: float = Weather.cloud_evolution
	m.set_shader_parameter(&"cloud_churn", Vector3(fposmod(evo * 0.0011, 1.0),
			fposmod(-evo * 0.0016, 1.0), fposmod(evo * 0.0007, 1.0)))
	m.set_shader_parameter(&"cloudiness", Weather.cloudiness)
	m.set_shader_parameter(&"storm_base", Weather.base_storminess)
	var c: Vector3 = Weather.storm_center
	m.set_shader_parameter(&"storm_cell", Vector4(c.x, c.z, maxf(Weather.storm_radius, 1.0), Weather.storm_intensity))
	var active: bool = Weather.front_progress < 1.0
	var h: float = Weather.front_heading
	m.set_shader_parameter(&"front_line", Vector4(sin(h), -cos(h), Weather.front_line(), 1.0 if active else 0.0))
	m.set_shader_parameter(&"front_origin", Vector2(Weather.front_origin.x, Weather.front_origin.z))
	m.set_shader_parameter(&"front_ahead", Weather.front_from)

func _update_shadow_bake(cam_pos: Vector3, key_dir: Vector3) -> void:
	# Snap the square to its texel grid so shadows do not swim as the camera moves.
	var texel := SHADOW_EXTENT / SHADOW_RES
	var centre := Vector2(snappedf(cam_pos.x, texel), snappedf(cam_pos.z, texel))
	var shift := CloudField.shadow_shift(key_dir)
	_set_field(_shadow_material)
	_shadow_material.set_shader_parameter(&"rect", Vector4(centre.x, centre.y, SHADOW_EXTENT, 0.0))
	_shadow_material.set_shader_parameter(&"shift", shift)
	_shadow_material.set_shader_parameter(&"cast_height", cloud_field.cast_height())
	sky_material.set_shader_parameter(&"shadow_rect", Vector4(centre.x, centre.y, 1.0 / SHADOW_EXTENT, 0.0))
	sky_material.set_shader_parameter(&"shadow_shift", shift)
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_params",
			Vector4(centre.x, centre.y, 1.0 / SHADOW_EXTENT, light_at_camera))

func _set_meteor(m: ShaderMaterial, stars: float) -> void:
	## An occasional shooting star, a pure function of the weather clock so every
	## peer sees the same one.
	const WINDOW := 9.0
	const DURATION := 0.7
	var slot := floorf(Weather.clock / WINDOW)
	var age: float = Weather.clock - slot * WINDOW
	if stars < 0.2 or _hash(slot * 12.9898) > 0.4 or age > DURATION:
		m.set_shader_parameter(&"meteor_head", Vector4.ZERO)
		return
	var az := _hash(slot * 78.233) * TAU
	var el := lerpf(0.5, 1.2, _hash(slot * 37.719))
	var start := Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))
	var travel_az := az + lerpf(-1.2, 1.2, _hash(slot * 9.17))
	var down := Vector3(sin(travel_az), -0.9, -cos(travel_az)).normalized()
	var f := age / DURATION
	var head := (start + down * 0.3 * f).normalized()
	var tail := (start + down * 0.3 * maxf(f - 0.35, 0.0)).normalized()
	m.set_shader_parameter(&"meteor_head", Vector4(head.x, head.y, head.z, sin(f * PI) * stars))
	m.set_shader_parameter(&"meteor_tail", tail)

func _update_shelters(cam_pos: Vector3) -> void:
	## Hand the nearest shelter boxes to the rain shaders, which drop anything inside.
	var found: Array = []
	for node in get_tree().get_nodes_in_group(&"shelter"):
		var area := node as Node3D
		if area == null:
			continue
		for child in area.get_children():
			var cs := child as CollisionShape3D
			if cs == null or cs.shape == null or cs.disabled:
				continue
			var half := _shape_half_extents(cs.shape)
			if half != Vector3.ZERO:
				found.append([cs.global_position.distance_squared_to(cam_pos),
						cs.global_transform.affine_inverse(), half])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var inverses: Array[Transform3D] = []
	var halves := PackedVector3Array()
	camera_sheltered = false
	for i in mini(found.size(), MAX_SHELTERS):
		var inv: Transform3D = found[i][1]
		var half: Vector3 = found[i][2]
		inverses.append(inv)
		halves.append(half)
		var local := inv * cam_pos
		if absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z:
			camera_sheltered = true
	var count := inverses.size()
	while inverses.size() < MAX_SHELTERS:
		inverses.append(Transform3D.IDENTITY)
		halves.append(Vector3.ZERO)
	for m in _weather_materials:
		m.set_shader_parameter(&"shelter_count", count)
		m.set_shader_parameter(&"shelter_inv", inverses)
		m.set_shader_parameter(&"shelter_half", halves)

static func _shape_half_extents(shape: Shape3D) -> Vector3:
	## Shelters are boxes; other shapes are treated as their bounding box.
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size * 0.5
	if shape is SphereShape3D:
		var r: float = (shape as SphereShape3D).radius
		return Vector3(r, r, r)
	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		return Vector3(c.radius, c.height * 0.5, c.radius)
	if shape is CapsuleShape3D:
		var k := shape as CapsuleShape3D
		return Vector3(k.radius, k.height * 0.5, k.radius)
	return Vector3.ZERO

func _update_rain(cam: Camera3D, rain: float, flash_here: float, first: bool) -> void:
	var on := rain > 0.01
	for e: GPUParticles3D in [_rain, _rain_far, _splash, _mist]:
		e.emitting = on
		e.visible = on
	if not on:
		return
	# Gusts thicken the rain and lean it over; lulls let it fall straighter.
	var wind: Vector3 = Weather.wind_vector()
	var gust: float = Weather.gust_factor()
	var density := clampf(rain * lerpf(0.55, 1.25, clampf(gust - 0.4, 0.0, 1.0)), 0.05, 1.0)
	_rain.amount_ratio = density
	_rain_far.amount_ratio = density
	_splash.amount_ratio = clampf(rain, 0.05, 1.0)
	_mist.amount_ratio = clampf(rain * wind.length() / 16.0, 0.1, 1.0)
	var fall := Vector3(wind.x * 0.75, -25.0, wind.z * 0.75)
	_rain_process.direction = fall.normalized()
	_rain_far_process.direction = fall.normalized()
	var blow := Vector3(wind.x, 0.0, wind.z)
	_mist_process.direction = blow.normalized() if blow.length() > 0.1 else Vector3.FORWARD
	_mist_process.initial_velocity_min = blow.length() * 0.45
	_mist_process.initial_velocity_max = blow.length() * 0.8
	var tint := _lin(palette["horizon"])
	for m in _weather_materials:
		m.set_shader_parameter(&"flash", flash_here)
		m.set_shader_parameter(&"tint", tint)
	_rain_material.set_shader_parameter(&"opacity", lerpf(0.2, 0.46, rain))
	_rain_far_material.set_shader_parameter(&"opacity", lerpf(0.07, 0.17, rain))
	_splash_material.set_shader_parameter(&"opacity", lerpf(0.18, 0.42, rain))
	_mist_material.set_shader_parameter(&"opacity", lerpf(0.03, 0.11, rain))
	if cam == null:
		return
	# Spawn above and upwind so streaks cross the view on their way down.
	var ahead := -cam.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var upwind := Vector3(fall.x, 0.0, fall.z)
	var at := cam.global_position
	_rain.global_position = at + ahead * 8.0 + Vector3(0.0, 13.0, 0.0) - upwind * 0.5
	_rain_far.global_position = at + ahead * 45.0 + Vector3(0.0, 24.0, 0.0) - upwind * 0.9
	_splash.global_position = Vector3(at.x, 0.0, at.z) + ahead * 16.0
	_mist.global_position = Vector3(at.x, 2.0, at.z) + ahead * 40.0 - _mist_process.direction * 20.0
	if first:
		for e: GPUParticles3D in [_rain, _rain_far, _splash, _mist]:
			e.restart()

func _on_lightning_struck(direction: Vector3, distance: float, _intensity: float) -> void:
	if not show_bolts or Weather.lightning_is_sheet:
		_bolt.visible = false
		return
	_bolt.mesh = _make_bolt_mesh(Weather.lightning_position, direction, distance, _cloud_base() + 140.0)
	_bolt.global_transform = Transform3D.IDENTITY
	_bolt.visible = true


# --- Helpers ------------------------------------------------------------

func _key_direction() -> Vector3:
	if palette.is_empty() or float(palette["sun_energy"]) >= float(palette["moon_energy"]):
		return _raised(Weather.sun_direction())
	return _raised(Weather.moon_direction())

func _cloud_base() -> float:
	## Altitude of the cloud base under the stormiest weather around.
	var stormy: float = maxf(Weather.base_storminess, Weather.storm_intensity)
	return lerpf(CloudField.BASE_FAIR, CloudField.BASE_STORM, smoothstep(0.2, 0.9, stormy))

static func evening(hour: float) -> float:
	## 0 through the morning, 1 through the evening. The swaps happen at noon
	## and in the dead of night, when dawn and dusk colours are the same.
	return smoothstep(11.0, 13.0, hour) * (1.0 - smoothstep(23.0, 24.0, hour))

static func _hash(x: float) -> float:
	return fposmod(sin(x) * 43758.5453, 1.0)

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

func _make_bolt_mesh(foot: Vector3, direction: Vector3, distance: float, top_alt: float) -> ArrayMesh:
	## A forked bolt from inside the cloud base to the sea: a jagged trunk, forks
	## that fork again, and a wide soft ribbon behind each for the glow. Ribbons
	## face the viewer; width grows with distance so far bolts stay readable.
	_rng.randomize()
	var side := direction.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.01 else Vector3.RIGHT
	var top := Vector3(foot.x, top_alt, foot.z) + side * _rng.randf_range(-220.0, 220.0) \
			+ direction * _rng.randf_range(-150.0, 150.0)
	var width := clampf(distance * 0.0032, 0.9, 11.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := _jagged(top, foot, side, direction, 6, 0.15)
	_ribbon(st, trunk, side, width * 9.0, 1.0, 1.0)
	_ribbon(st, trunk, side, width, 1.0, 0.0)
	for i in _rng.randi_range(3, 5):
		var at: int = _rng.randi_range(3, trunk.size() - 14)
		_fork(st, trunk[at], foot.y, side, direction, width * 0.55, 0.6, 2)
	return st.commit()

func _fork(st: SurfaceTool, from: Vector3, floor_y: float, side: Vector3, depth: Vector3,
		width: float, strength: float, levels: int) -> void:
	var reach := (from.y - floor_y) * _rng.randf_range(0.25, 0.6)
	var sway := side * reach * _rng.randf_range(0.3, 0.85) * (1.0 if _rng.randf() > 0.5 else -1.0) \
			+ depth * reach * _rng.randf_range(-0.3, 0.3)
	var pts := _jagged(from, from + Vector3(0.0, -reach, 0.0) + sway, side, depth, 4, 0.2)
	_ribbon(st, pts, side, width * 7.0, strength * 0.6, 1.0)
	_ribbon(st, pts, side, width, strength, 0.0)
	if levels > 1 and _rng.randf() < 0.75:
		_fork(st, pts[_rng.randi_range(4, pts.size() - 5)], floor_y, side, depth,
				width * 0.6, strength * 0.6, levels - 1)

func _jagged(a: Vector3, b: Vector3, side: Vector3, depth: Vector3, levels: int,
		roughness: float) -> PackedVector3Array:
	## Midpoint displacement between a and b, mostly sideways as seen by the viewer.
	var pts := PackedVector3Array([a, b])
	var spread := a.distance_to(b) * roughness
	for _l in levels:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			var mid := (pts[i] + pts[i + 1]) * 0.5
			mid += side * _rng.randf_range(-spread, spread)
			mid += depth * _rng.randf_range(-spread, spread) * 0.5
			mid.y += _rng.randf_range(-spread, spread) * 0.25
			next.append(pts[i])
			next.append(mid)
		next.append(pts[pts.size() - 1])
		pts = next
		spread *= 0.52
	return pts

func _ribbon(st: SurfaceTool, pts: PackedVector3Array, side: Vector3, width: float,
		strength: float, glow: float) -> void:
	## Colour: r = brightness, g = 1 for the glow ribbon, b = fade into the cloud at the top.
	var n := pts.size()
	for i in n - 1:
		# Taper towards the tip.
		var f0 := float(i) / float(n - 1)
		var f1 := float(i + 1) / float(n - 1)
		var w0 := width * lerpf(1.0, 0.4, f0)
		var w1 := width * lerpf(1.0, 0.4, f1)
		var c0 := Color(strength, glow, smoothstep(0.0, 0.12, f0))
		var c1 := Color(strength, glow, smoothstep(0.0, 0.12, f1))
		var a0 := pts[i] - side * w0
		var a1 := pts[i] + side * w0
		var b0 := pts[i + 1] - side * w1
		var b1 := pts[i + 1] + side * w1
		for v: Array in [[a0, 0.0, c0], [a1, 1.0, c0], [b0, 0.0, c1], [a1, 1.0, c0], [b1, 1.0, c1], [b0, 0.0, c1]]:
			st.set_color(v[2])
			st.set_uv(Vector2(v[1], 0.0))
			st.add_vertex(v[0])
