class_name VictoryFlare
extends Node3D
## Sculpted Brass Mariner's Celebration Signal Flare Rocket & 3-Layer Starburst.
##
## Launches skyward in a festive golden-crimson spiral trailing an additive spark
## ribbon (`FlareTrail`), then detonates cleanly at ~24 m apex into a radial burst
## of sculpted 16-tri 4-point star-sparks, an inner cascade of sculpted 8-tri
## faceted diamond embers, and a warm celebratory apex OmniLight3D casting golden
## radiance over sails & harbour water below. Zero raw PrimitiveMeshes; zero leaks!

signal burst_detonated(apex_pos: Vector3)

enum State { RISING, BURST, DONE }

const GROUP := &"victory_flares"
const RISE_DURATION := 1.25
const BURST_DURATION := 2.20
const INITIAL_VY := 22.0
const RISE_DRAG := 3.6
const APEX_LIGHT_ENERGY := 6.5
const APEX_LIGHT_RANGE := 38.0
const TRAIL_MAX_POINTS := 18
const HALO_VISIBILITY_RANGE := 900.0
const TAIL_HALO_POS := Vector3(0.0, -0.22, 0.0)
const STARBURST_HALO_START_SCALE := 1.2
const STARBURST_HALO_END_SCALE := 11.5
const STARBURST_HALO_PEAK_ENERGY := 1.75

# Painterly nautical brass, crimson lacquer & incandescent spark palette (sRGB).
const COL_BRASS_HI := Color(0.95, 0.78, 0.30)
const COL_BRASS_MID := Color(0.76, 0.57, 0.19)
const COL_BRASS_DARK := Color(0.46, 0.32, 0.11)
const COL_CRIMSON_HI := Color(0.88, 0.20, 0.16)
const COL_CRIMSON_DARK := Color(0.54, 0.10, 0.08)
const COL_IRON_BAND := Color(0.22, 0.23, 0.27)
const COL_FUSE_GLOW := Color(1.0, 0.88, 0.42)
const COL_HALO_CORE := Color(1.00, 1.00, 0.98, 1.0)
const COL_HALO_MID := Color(0.46, 0.44, 0.40, 1.0)
const COL_HALO_RIM := Color(0.00, 0.00, 0.00, 1.0)

# Statically cached zero-primitive procedural ArrayMeshes & materials shared across flares.
static var _active_flares: int = 0
static var _rocket_mesh: ArrayMesh = null
static var _star_mesh: ArrayMesh = null
static var _diamond_mesh: ArrayMesh = null
static var _halo_mesh: ArrayMesh = null
static var _rocket_mat: StandardMaterial3D = null
static var _spark_mat: StandardMaterial3D = null
static var _trail_mat: StandardMaterial3D = null

@export var accent_color: Color = Color(1.0, 0.84, 0.28)
@export var auto_despawn: bool = true
@export var enable_effects: bool = true

var state: State = State.RISING
var elapsed: float = 0.0
var burst_elapsed: float = 0.0
var launch_origin: Vector3 = Vector3.ZERO
var apex_position: Vector3 = Vector3.ZERO

var _rocket_root: Node3D = null
var _rocket_mi: MeshInstance3D = null
var _tail_halo_mi: MeshInstance3D = null
var _tail_halo_mat: StandardMaterial3D = null
var _starburst_halo_mi: MeshInstance3D = null
var _starburst_halo_mat: StandardMaterial3D = null
var _starburst_halo_energy: float = 0.0
var _trail_mi: MeshInstance3D = null
var _trail_imm: ImmediateMesh = null
var _star_burst: GPUParticles3D = null
var _ember_cascade: GPUParticles3D = null
var _apex_light: OmniLight3D = null

var _trail_points: Array[Vector3] = []
var _vy: float = INITIAL_VY
var _altitude: float = 0.0
var _detonated: bool = false


## Launch a sculpted Mariner's Celebration Flare from `world_pos` tinted by `p_accent_color`.
static func launch(parent: Node, world_pos: Vector3, p_accent_color: Color = Color(1.0, 0.84, 0.28)) -> VictoryFlare:
	var flare: VictoryFlare = new()
	flare.name = "VictoryFlare"
	flare.accent_color = p_accent_color
	flare.launch_origin = world_pos
	flare.position = world_pos
	if parent != null:
		parent.add_child(flare)
		flare.global_position = world_pos
	return flare


## Release all statically cached VictoryFlare meshes & materials cleanly.
static func clear_shared_cache() -> void:
	_rocket_mesh = null
	_star_mesh = null
	_diamond_mesh = null
	_halo_mesh = null
	_rocket_mat = null
	_spark_mat = null
	_trail_mat = null


func _enter_tree() -> void:
	_active_flares += 1
	add_to_group(GROUP)


func _ready() -> void:
	_ensure_shared_assets()
	if launch_origin == Vector3.ZERO and position != Vector3.ZERO:
		launch_origin = global_position if is_inside_tree() else position
	_build_nodes()
	_trail_points.append(global_position if is_inside_tree() else position)
	_rebuild_trail_mesh()


func _exit_tree() -> void:
	if _rocket_mi != null and is_instance_valid(_rocket_mi):
		_rocket_mi.mesh = null
		_rocket_mi.material_override = null
	if _tail_halo_mi != null and is_instance_valid(_tail_halo_mi):
		_tail_halo_mi.visible = false
		_tail_halo_mi.mesh = null
		_tail_halo_mi.material_override = null
	if _starburst_halo_mi != null and is_instance_valid(_starburst_halo_mi):
		_starburst_halo_mi.visible = false
		_starburst_halo_mi.mesh = null
		_starburst_halo_mi.material_override = null
	if _trail_imm != null:
		_trail_imm.clear_surfaces()
	if _trail_mi != null and is_instance_valid(_trail_mi):
		_trail_mi.mesh = null
		_trail_mi.material_override = null
	for gp: GPUParticles3D in [_star_burst, _ember_cascade]:
		if gp != null and is_instance_valid(gp):
			gp.emitting = false
			gp.visible = false
			var pm := gp.process_material as ParticleProcessMaterial
			if pm != null:
				pm.color_ramp = null
				pm.scale_curve = null
			gp.draw_pass_1 = null
			gp.process_material = null
			gp.material_override = null
	_trail_points.clear()
	_rocket_root = null
	_rocket_mi = null
	_tail_halo_mi = null
	_tail_halo_mat = null
	_starburst_halo_mi = null
	_starburst_halo_mat = null
	_starburst_halo_energy = 0.0
	_trail_mi = null
	_trail_imm = null
	_star_burst = null
	_ember_cascade = null
	_apex_light = null
	_active_flares = maxi(0, _active_flares - 1)
	if _active_flares == 0:
		clear_shared_cache()


func _physics_process(delta: float) -> void:
	step_flare(delta)


# ==============================================================================
# Public Simulation & Inspection API
# ==============================================================================

## Advance flare climb, apex detonation, starburst decay & auto-despawn deterministically.
func step_flare(delta: float) -> void:
	if state == State.DONE:
		return
	var dt := maxf(delta, 0.0)

	if state == State.RISING:
		elapsed += dt
		_vy = maxf(6.5, _vy - RISE_DRAG * dt)
		_altitude += _vy * dt
		var spiral_r := 0.24 * clampf(elapsed / RISE_DURATION, 0.0, 1.0)
		var spiral_ang := elapsed * 7.5
		var cur_w := launch_origin + Vector3(cos(spiral_ang) * spiral_r, _altitude, sin(spiral_ang) * spiral_r)
		if is_inside_tree():
			global_position = cur_w
		else:
			position = cur_w
		if _rocket_root != null and is_instance_valid(_rocket_root):
			_rocket_root.rotation = Vector3(sin(spiral_ang) * 0.08, elapsed * 6.4, -cos(spiral_ang) * 0.08)
		_update_tail_halo(elapsed)
		if _apex_light != null and is_instance_valid(_apex_light):
			_apex_light.light_energy = 1.65 + sin(elapsed * 28.0) * 0.25
			_apex_light.omni_range = 10.5
		_trail_points.append(cur_w)
		if _trail_points.size() > TRAIL_MAX_POINTS:
			_trail_points.pop_front()
		_rebuild_trail_mesh()

		if elapsed >= RISE_DURATION:
			_detonate_burst()
	elif state == State.BURST:
		burst_elapsed += dt
		var u := clampf(burst_elapsed / BURST_DURATION, 0.0, 1.0)
		var decay := pow(1.0 - u, 1.85)
		if _apex_light != null and is_instance_valid(_apex_light):
			_apex_light.light_energy = APEX_LIGHT_ENERGY * decay
			_apex_light.omni_range = APEX_LIGHT_RANGE
		_update_starburst_halo(u, decay)
		if burst_elapsed >= BURST_DURATION:
			state = State.DONE
			if _apex_light != null and is_instance_valid(_apex_light):
				_apex_light.light_energy = 0.0
				_apex_light.visible = false
			_starburst_halo_energy = 0.0
			if _starburst_halo_mi != null and is_instance_valid(_starburst_halo_mi):
				_starburst_halo_mi.visible = false
			if _starburst_halo_mat != null:
				_starburst_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
			if auto_despawn:
				queue_free()


## Snap immediately to the ~24 m celebratory burst apex (ideal for deterministic showcases & tests).
func force_burst_apex() -> void:
	elapsed = RISE_DURATION
	_altitude = 24.0
	var apex_w := launch_origin + Vector3(0.0, _altitude, 0.0)
	if is_inside_tree():
		global_position = apex_w
	else:
		position = apex_w
	_detonate_burst()
	if _star_burst != null and is_instance_valid(_star_burst):
		_star_burst.preprocess = 0.32
		_star_burst.restart()
		_star_burst.emitting = true
	if _ember_cascade != null and is_instance_valid(_ember_cascade):
		_ember_cascade.preprocess = 0.28
		_ember_cascade.restart()
		_ember_cascade.emitting = true


## Return exact triangle count of the sculpted Brass Mariner's Signal Rocket ArrayMesh.
func get_rocket_triangle_count() -> int:
	_ensure_shared_assets()
	return _count_mesh_tris(_rocket_mesh)


## Return the incandescent sputtering RocketTailHalo MeshInstance3D mounted under RocketRoot.
func get_tail_halo_node() -> MeshInstance3D:
	return _tail_halo_mi


## Return the expanding celebratory FlareStarburstHalo MeshInstance3D mounted under VictoryFlare.
func get_starburst_halo_node() -> MeshInstance3D:
	return _starburst_halo_mi


## Return current FlareStarburstHalo additive energy (0.0 while rising or done; peaks ~1.75 on burst).
func get_starburst_halo_energy() -> float:
	return _starburst_halo_energy


static func _count_mesh_tris(m: ArrayMesh) -> int:
	if m == null:
		return 0
	var total := 0
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		total += floori(float(verts.size()) / 3.0)
	return total


# ==============================================================================
# Burst Detonation & Node Construction
# ==============================================================================

func _detonate_burst() -> void:
	if _detonated:
		return
	_detonated = true
	state = State.BURST
	burst_elapsed = 0.0
	apex_position = global_position if is_inside_tree() else position

	if _rocket_root != null and is_instance_valid(_rocket_root):
		_rocket_root.visible = false
	if _tail_halo_mi != null and is_instance_valid(_tail_halo_mi):
		_tail_halo_mi.visible = false
	if _tail_halo_mat != null:
		_tail_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	if _trail_imm != null:
		_trail_imm.clear_surfaces()
	if _trail_mi != null and is_instance_valid(_trail_mi):
		_trail_mi.visible = false

	if _apex_light != null and is_instance_valid(_apex_light):
		_apex_light.visible = true
		_apex_light.light_color = accent_color.lerp(Color(1.0, 0.92, 0.68), 0.45)
		_apex_light.light_energy = APEX_LIGHT_ENERGY
		_apex_light.omni_range = APEX_LIGHT_RANGE

	_update_starburst_halo(0.0, 1.0)

	if _star_burst != null and is_instance_valid(_star_burst):
		_star_burst.visible = true
		_star_burst.restart()
		_star_burst.emitting = true
	if _ember_cascade != null and is_instance_valid(_ember_cascade):
		_ember_cascade.visible = true
		_ember_cascade.restart()
		_ember_cascade.emitting = true

	Audio.play_sfx(&"cannon_fire", apex_position, -5.0)
	burst_detonated.emit(apex_position)


func _update_tail_halo(t: float) -> void:
	if _tail_halo_mi == null or not is_instance_valid(_tail_halo_mi):
		return
	var sputter := clampf(0.5 + 0.5 * (sin(t * 29.0) * 0.65 + cos(t * 47.0) * 0.35), 0.0, 1.0)
	var tail_scale := lerpf(0.65, 0.95, sputter)
	var tail_energy := lerpf(0.88, 1.28, sputter)
	var tail_tint := Color(1.0, 0.82, 0.36).lerp(accent_color, 0.35)
	_tail_halo_mi.visible = true
	_tail_halo_mi.scale = Vector3.ONE * tail_scale
	if _tail_halo_mat != null:
		_tail_halo_mat.albedo_color = Color(
			tail_tint.r * tail_energy,
			tail_tint.g * tail_energy,
			tail_tint.b * tail_energy,
			1.0
		)


func _update_starburst_halo(u: float, decay: float) -> void:
	_starburst_halo_energy = maxf(0.0, STARBURST_HALO_PEAK_ENERGY * decay)
	if _starburst_halo_mi == null or not is_instance_valid(_starburst_halo_mi):
		return
	if _starburst_halo_energy <= 0.001 or u >= 1.0:
		_starburst_halo_energy = 0.0
		_starburst_halo_mi.visible = false
		if _starburst_halo_mat != null:
			_starburst_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		return
	var expand := 1.0 - pow(1.0 - u, 2.0)
	var cur_scale := lerpf(STARBURST_HALO_START_SCALE, STARBURST_HALO_END_SCALE, expand)
	_starburst_halo_mi.visible = true
	_starburst_halo_mi.scale = Vector3.ONE * cur_scale
	if _starburst_halo_mat != null:
		_starburst_halo_mat.albedo_color = Color(
			accent_color.r * _starburst_halo_energy,
			accent_color.g * _starburst_halo_energy,
			accent_color.b * _starburst_halo_energy,
			1.0
		)


static func _make_halo_material() -> StandardMaterial3D:
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


func _build_nodes() -> void:
	# 1. Sculpted Brass Mariner's Signal Rocket visual.
	_rocket_root = Node3D.new()
	_rocket_root.name = "RocketRoot"
	add_child(_rocket_root)

	_rocket_mi = MeshInstance3D.new()
	_rocket_mi.name = "RocketMesh"
	_rocket_mi.mesh = _rocket_mesh
	_rocket_mi.material_override = _rocket_mat
	_rocket_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rocket_root.add_child(_rocket_mi)

	# 1b. Incandescent sputtering RocketTailHalo beneath the fuse nozzle while RISING.
	_tail_halo_mat = _make_halo_material()
	_tail_halo_mi = MeshInstance3D.new()
	_tail_halo_mi.name = "RocketTailHalo"
	_tail_halo_mi.position = TAIL_HALO_POS
	_tail_halo_mi.mesh = _halo_mesh
	_tail_halo_mi.material_override = _tail_halo_mat
	_tail_halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail_halo_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_tail_halo_mi.visibility_range_end = HALO_VISIBILITY_RANGE
	_tail_halo_mi.extra_cull_margin = 1.5
	_rocket_root.add_child(_tail_halo_mi)
	_update_tail_halo(0.0)

	# 1c. Expanding celebratory FlareStarburstHalo (hidden while RISING, blossoms on detonation).
	_starburst_halo_mat = _make_halo_material()
	_starburst_halo_mi = MeshInstance3D.new()
	_starburst_halo_mi.name = "FlareStarburstHalo"
	_starburst_halo_mi.position = Vector3.ZERO
	_starburst_halo_mi.scale = Vector3.ONE * STARBURST_HALO_START_SCALE
	_starburst_halo_mi.mesh = _halo_mesh
	_starburst_halo_mi.material_override = _starburst_halo_mat
	_starburst_halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_starburst_halo_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_starburst_halo_mi.visibility_range_end = HALO_VISIBILITY_RANGE
	_starburst_halo_mi.extra_cull_margin = 6.0
	_starburst_halo_mi.visible = false
	_starburst_halo_energy = 0.0
	add_child(_starburst_halo_mi)

	# 2. Additive golden-crimson rising spark ribbon (`ImmediateMesh`, zero primitives).
	_trail_imm = ImmediateMesh.new()
	_trail_mi = MeshInstance3D.new()
	_trail_mi.name = "FlareTrail"
	_trail_mi.top_level = true
	_trail_mi.mesh = _trail_imm
	_trail_mi.material_override = _trail_mat
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail_mi)

	# 3. Apex celebratory OmniLight3D (doubles as subtle warm tail glow while rising!).
	_apex_light = OmniLight3D.new()
	_apex_light.name = "ApexFlashLight"
	_apex_light.light_color = Color(1.0, 0.78, 0.34)
	_apex_light.light_energy = 1.65
	_apex_light.omni_range = 10.5
	_apex_light.omni_attenuation = 1.25
	_apex_light.shadow_enabled = false
	add_child(_apex_light)

	if enable_effects:
		_star_burst = _make_starburst_particles()
		add_child(_star_burst)
		_ember_cascade = _make_ember_cascade_particles()
		add_child(_ember_cascade)


func _make_starburst_particles() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.25
	proc.direction = Vector3.UP
	proc.spread = 180.0
	proc.initial_velocity_min = 7.5
	proc.initial_velocity_max = 15.5
	proc.damping_min = 1.4
	proc.damping_max = 2.4
	proc.gravity = Vector3(0.0, -3.8, 0.0)
	proc.angular_velocity_min = -120.0
	proc.angular_velocity_max = 120.0
	proc.scale_min = 0.75
	proc.scale_max = 1.45

	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.45))
	sc.add_point(Vector2(0.18, 1.25))
	sc.add_point(Vector2(0.68, 0.85))
	sc.add_point(Vector2(1.0, 0.08))
	var sc_tex := CurveTexture.new()
	sc_tex.curve = sc
	proc.scale_curve = sc_tex

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.99, 0.90, 1.0),
		Color(accent_color.r, accent_color.g, accent_color.b, 0.98),
		Color(1.0, 0.64, 0.16, 0.72),
		Color(0.95, 0.28, 0.06, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 24
	ramp.gradient = grad
	proc.color_ramp = ramp

	var gp := GPUParticles3D.new()
	gp.name = "StarburstParticles"
	gp.one_shot = true
	gp.explosiveness = 0.96
	gp.amount = 44
	gp.lifetime = 1.95
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-24.0, -20.0, -24.0), Vector3(48.0, 44.0, 48.0))
	gp.process_material = proc
	gp.draw_pass_1 = _star_mesh
	gp.material_override = _spark_mat
	gp.emitting = false
	gp.visible = false
	return gp


func _make_ember_cascade_particles() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc.emission_ring_axis = Vector3.UP
	proc.emission_ring_radius = 1.65
	proc.emission_ring_inner_radius = 0.55
	proc.emission_ring_height = 0.6
	proc.direction = Vector3.UP
	proc.spread = 150.0
	proc.initial_velocity_min = 3.2
	proc.initial_velocity_max = 7.4
	proc.damping_min = 0.9
	proc.damping_max = 1.8
	proc.gravity = Vector3(0.0, -5.4, 0.0)
	proc.scale_min = 0.65
	proc.scale_max = 1.30

	var mid_col := accent_color.lerp(Color(1.0, 0.58, 0.14), 0.50)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.28, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.72, 1.0),
		Color(mid_col.r, mid_col.g, mid_col.b, 0.95),
		Color(1.0, 0.36, 0.08, 0.62),
		Color(0.75, 0.10, 0.02, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 24
	ramp.gradient = grad
	proc.color_ramp = ramp

	var gp := GPUParticles3D.new()
	gp.name = "EmberCascadeParticles"
	gp.one_shot = true
	gp.explosiveness = 0.90
	gp.amount = 28
	gp.lifetime = 2.15
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-22.0, -24.0, -22.0), Vector3(44.0, 40.0, 44.0))
	gp.process_material = proc
	gp.draw_pass_1 = _diamond_mesh
	gp.material_override = _spark_mat
	gp.emitting = false
	gp.visible = false
	return gp


func _rebuild_trail_mesh() -> void:
	if _trail_imm == null:
		return
	_trail_imm.clear_surfaces()
	var n := _trail_points.size()
	if n < 2:
		return
	# Crossed dual additive ribbons (X and Z widths) so the rising golden-crimson trail reads from every angle.
	_trail_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		for i in range(n - 1):
			var u0 := float(i) / float(n - 1)
			var u1 := float(i + 1) / float(n - 1)
			var w0 := lerpf(0.02, 0.14, u0)
			var w1 := lerpf(0.02, 0.14, u1)
			var c0 := Color(1.0, lerpf(0.28, 0.92, u0), lerpf(0.08, 0.45, u0), u0 * 0.85)
			var c1 := Color(1.0, lerpf(0.28, 0.92, u1), lerpf(0.08, 0.45, u1), u1 * 0.92)
			var p0 := _trail_points[i]
			var p1 := _trail_points[i + 1]
			var a0 := p0 - axis * w0
			var b0 := p0 + axis * w0
			var a1 := p1 - axis * w1
			var b1 := p1 + axis * w1
			_trail_imm.surface_set_color(c0)
			_trail_imm.surface_add_vertex(a0)
			_trail_imm.surface_set_color(c1)
			_trail_imm.surface_add_vertex(a1)
			_trail_imm.surface_set_color(c1)
			_trail_imm.surface_add_vertex(b1)
			_trail_imm.surface_set_color(c0)
			_trail_imm.surface_add_vertex(a0)
			_trail_imm.surface_set_color(c1)
			_trail_imm.surface_add_vertex(b1)
			_trail_imm.surface_set_color(c0)
			_trail_imm.surface_add_vertex(b0)
	_trail_imm.surface_end()


# ==============================================================================
# Shared Sculpted Zero-Primitive Procedural ArrayMeshes
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _rocket_mat == null:
		_rocket_mat = StandardMaterial3D.new()
		_rocket_mat.vertex_color_use_as_albedo = true
		_rocket_mat.vertex_color_is_srgb = true
		_rocket_mat.roughness = 0.34
		_rocket_mat.metallic = 0.68
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.vertex_color_is_srgb = true
	if _trail_mat == null:
		_trail_mat = StandardMaterial3D.new()
		_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_mat.vertex_color_use_as_albedo = true
		_trail_mat.vertex_color_is_srgb = true
	if _rocket_mesh == null:
		_rocket_mesh = _build_rocket_mesh()
	if _star_mesh == null:
		_star_mesh = _build_star_spark_mesh()
	if _diamond_mesh == null:
		_diamond_mesh = _build_diamond_spark_mesh()
	if _halo_mesh == null:
		_halo_mesh = _build_halo_mesh()


static func _build_halo_mesh() -> ArrayMesh:
	# Exact 48-tri 16-wedge radial-gradient billboard disc (diameter 1.0 m -> scale = world meters)
	# grading incandescent white core -> feathered mid -> pure Color(0, 0, 0, 1) black rim
	# with exact finite unit (0, 0, 1) normals for zero box/circle edge under additive blend.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const INNER_R := 0.22
	const OUTER_R := 0.50
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	var ctr := Vector3.ZERO
	for i in WEDGES:
		var a0 := TAU * float(i) / float(WEDGES)
		var a1 := TAU * float(i + 1) / float(WEDGES)
		var m0 := Vector3(cos(a0) * INNER_R, sin(a0) * INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * INNER_R, sin(a1) * INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)
		# Inner incandescent core wedge (16 tris)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_CORE)
		st.add_vertex(ctr)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		# Outer feathered skirt quad fading to pure black (32 tris)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o0)
	return st.commit()


static func _build_rocket_mesh() -> ArrayMesh:
	# Sculpted Brass Mariner's Signal Rocket: pointed crimson-brass nose cone, ribbed brass barrel,
	# 4 angled tail stabilizer fins, and glowing incandescent fuse tail cap!
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Lathe profile: [y, radius, color]
	var rings: Array[Array] = [
		[-0.46, 0.000, COL_FUSE_GLOW],
		[-0.44, 0.058, COL_FUSE_GLOW],
		[-0.38, 0.082, COL_IRON_BAND],
		[-0.32, 0.098, COL_BRASS_DARK],
		[-0.24, 0.114, COL_BRASS_MID],
		[-0.18, 0.122, COL_IRON_BAND],
		[-0.14, 0.114, COL_BRASS_HI],
		[0.02, 0.116, COL_BRASS_MID],
		[0.14, 0.124, COL_IRON_BAND],
		[0.18, 0.114, COL_BRASS_HI],
		[0.24, 0.118, COL_CRIMSON_DARK],
		[0.44, 0.072, COL_CRIMSON_HI],
		[0.62, 0.026, COL_BRASS_HI],
		[0.70, 0.000, COL_BRASS_HI],
	]
	var segs := 10
	var ctr := Vector3(0.0, 0.12, 0.0)
	for ri in range(rings.size() - 1):
		var y0: float = float(rings[ri][0])
		var r0: float = float(rings[ri][1])
		var c0: Color = rings[ri][2] as Color
		var y1: float = float(rings[ri + 1][0])
		var r1: float = float(rings[ri + 1][1])
		var c1: Color = rings[ri + 1][2] as Color
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 > 0.0005 and r1 > 0.0005:
				_emit_outward_tri(st, p00, c0, p10, c1, p11, c1, ctr)
				_emit_outward_tri(st, p00, c0, p11, c1, p01, c0, ctr)
			elif r0 <= 0.0005 and r1 > 0.0005:
				_emit_outward_tri(st, p00, c0, p10, c1, p11, c1, ctr)
			elif r0 > 0.0005 and r1 <= 0.0005:
				_emit_outward_tri(st, p00, c0, p10, c1, p01, c0, ctr)

	# 4 angled tail stabilizer fins mounted at 90-degree intervals around the lower barrel!
	for fi in 4:
		var ang := float(fi) * PI * 0.5 + PI * 0.25
		var rad := Vector3(cos(ang), 0.0, sin(ang))
		var tan_v := Vector3(-sin(ang), 0.0, cos(ang))
		var fin_t := 0.016
		var r_in := 0.092
		var r_out := 0.245
		var top_in := rad * r_in + Vector3(0.0, -0.02, 0.0)
		var bot_in := rad * r_in + Vector3(0.0, -0.34, 0.0)
		var top_out := rad * r_out + Vector3(0.0, -0.22, 0.0)
		var bot_out := rad * r_out + Vector3(0.0, -0.44, 0.0)
		var f_ctr := (top_in + bot_in + top_out + bot_out) * 0.25
		var front_pts: Array[Vector3] = [
			top_in + tan_v * fin_t, bot_in + tan_v * fin_t,
			bot_out + tan_v * fin_t, top_out + tan_v * fin_t,
		]
		var back_pts: Array[Vector3] = [
			top_in - tan_v * fin_t, bot_in - tan_v * fin_t,
			bot_out - tan_v * fin_t, top_out - tan_v * fin_t,
		]
		# Two main fin faces + 4 beveled perimeter edge strips.
		_emit_outward_tri(st, front_pts[0], COL_CRIMSON_HI, front_pts[1], COL_CRIMSON_DARK, front_pts[2], COL_BRASS_HI, f_ctr)
		_emit_outward_tri(st, front_pts[0], COL_CRIMSON_HI, front_pts[2], COL_BRASS_HI, front_pts[3], COL_BRASS_HI, f_ctr)
		_emit_outward_tri(st, back_pts[0], COL_CRIMSON_HI, back_pts[2], COL_BRASS_HI, back_pts[1], COL_CRIMSON_DARK, f_ctr)
		_emit_outward_tri(st, back_pts[0], COL_CRIMSON_HI, back_pts[3], COL_BRASS_HI, back_pts[2], COL_BRASS_HI, f_ctr)
		for ei in 4:
			var nei := (ei + 1) % 4
			_emit_outward_tri(st, front_pts[ei], COL_BRASS_MID, back_pts[ei], COL_BRASS_DARK, back_pts[nei], COL_BRASS_DARK, f_ctr)
			_emit_outward_tri(st, front_pts[ei], COL_BRASS_MID, back_pts[nei], COL_BRASS_DARK, front_pts[nei], COL_BRASS_MID, f_ctr)

	st.generate_normals()
	return st.commit()


static func _build_star_spark_mesh() -> ArrayMesh:
	# Sculpted 16-triangle 4-point faceted celebration star-spark (zero raw PrimitiveMesh!).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tip_r := 0.36
	var waist_r := 0.105
	var spine_z := 0.085
	var ring: Array[Vector3] = [
		Vector3(0.0, tip_r, 0.0),
		Vector3(waist_r, waist_r, 0.0),
		Vector3(tip_r, 0.0, 0.0),
		Vector3(waist_r, -waist_r, 0.0),
		Vector3(0.0, -tip_r, 0.0),
		Vector3(-waist_r, -waist_r, 0.0),
		Vector3(-tip_r, 0.0, 0.0),
		Vector3(-waist_r, waist_r, 0.0),
	]
	var front := Vector3(0.0, 0.0, spine_z)
	var back := Vector3(0.0, 0.0, -spine_z)
	var col_core := Color(1.0, 1.0, 0.96, 1.0)
	var col_tip := Color(1.0, 0.92, 0.68, 1.0)
	for i in 8:
		var ni := (i + 1) % 8
		var ci := col_tip if (i % 2 == 0) else col_core
		var cni := col_tip if (ni % 2 == 0) else col_core
		_emit_outward_tri(st, front, col_core, ring[i], ci, ring[ni], cni, Vector3.ZERO)
		_emit_outward_tri(st, back, col_core, ring[ni], cni, ring[i], ci, Vector3.ZERO)

	st.generate_normals()
	return st.commit()


static func _build_diamond_spark_mesh() -> ArrayMesh:
	# Sculpted 8-triangle elongated faceted diamond spark for cascading embers.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rx := 0.11
	var ry := 0.24
	var top := Vector3(0.0, ry, 0.0)
	var bot := Vector3(0.0, -ry, 0.0)
	var eq: Array[Vector3] = [
		Vector3(rx, 0.0, 0.0),
		Vector3(0.0, 0.0, rx),
		Vector3(-rx, 0.0, 0.0),
		Vector3(0.0, 0.0, -rx),
	]
	var c_hi := Color(1.0, 0.98, 0.88, 1.0)
	var c_mid := Color(1.0, 0.86, 0.56, 1.0)
	for i in 4:
		var ni := (i + 1) % 4
		_emit_outward_tri(st, top, c_hi, eq[i], c_mid, eq[ni], c_mid, Vector3.ZERO)
		_emit_outward_tri(st, bot, c_hi, eq[ni], c_mid, eq[i], c_mid, Vector3.ZERO)

	st.generate_normals()
	return st.commit()


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
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
