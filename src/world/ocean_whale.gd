class_name OceanWhale
extends Node3D
## Majestic 14-metre breaching Humpback Whale open-sea wonder.
## Executes a choreographed ballistic breach cycle (approach -> breach rise ->
## skyward apex twist -> colossal splash re-entry -> submerge), casting sunlit
## shadows across the waves with zero raw PrimitiveMeshes and leak-free cache teardown.

signal whale_splashed(world_pos: Vector3)

enum Phase { APPROACH, BREACH_RISE, APEX_TWIST, SPLASH_REENTRY, SUBMERGE, DONE }

const GROUP_WHALES := &"whales"
const GROUP_BEASTS := &"beasts"

const T_APPROACH_END := 1.4
const T_RISE_END := 3.0
const T_APEX_END := 4.5
const T_SPLASH_END := 5.9
const T_SUBMERGE_END := 8.0

# Painterly Humpback Whale countershading palette (authored in sRGB).
const COL_BACK_DARK := Color(0.082, 0.132, 0.212)      # Deep slate-indigo dorsal back
const COL_BACK_HI := Color(0.145, 0.222, 0.318)        # Sunlit oceanic slate highlight
const COL_FLANK := Color(0.195, 0.275, 0.365)          # Transition flank blue-slate
const COL_BELLY_CREAM := Color(0.885, 0.905, 0.870)    # Warm cream-ivory ventral pleats
const COL_PLEAT_GROOVE := Color(0.310, 0.382, 0.455)   # Shaded throat pleat grooves
const COL_FLIPPER_UNDER := Color(0.925, 0.945, 0.925)  # Iconic bright white Humpback wing underside
const COL_BARNACLE := Color(0.840, 0.855, 0.795)       # Pale sea-barnacle tubercle speckles
const COL_EYE_DARK := Color(0.030, 0.038, 0.052)       # Deep glossy whale eye

# Statically cached procedural ArrayMeshes, materials & spray texture shared across whales.
static var _active_whales: int = 0
static var _body_mesh: ArrayMesh = null
static var _flipper_l_mesh: ArrayMesh = null
static var _flipper_r_mesh: ArrayMesh = null
static var _fluke_mesh: ArrayMesh = null
static var _whale_mat: StandardMaterial3D = null
static var _spray_tex: ImageTexture = null
static var _spray_mat: StandardMaterial3D = null
static var _spray_quad: QuadMesh = null

@export var auto_despawn: bool = true
@export var enable_effects: bool = true

var phase: Phase = Phase.APPROACH
var elapsed: float = 0.0

var body_root: Node3D = null
var left_flipper_pivot: Node3D = null
var right_flipper_pivot: Node3D = null
var tail_pivot: Node3D = null

var _body_mi: MeshInstance3D = null
var _flipper_l_mi: MeshInstance3D = null
var _flipper_r_mi: MeshInstance3D = null
var _fluke_mi: MeshInstance3D = null
var _breach_spray: GPUParticles3D = null
var _splash_plume: GPUParticles3D = null

var _origin_xz: Vector2 = Vector2.ZERO
var _heading_yaw: float = 0.0
var _call_played: bool = false
var _rise_sprayed: bool = false
var _splash_fired: bool = false
var _forced_apex: bool = false


## Spawn a breaching Humpback Whale at `world_pos` heading along `heading_yaw`.
static func spawn_breach(parent: Node, world_pos: Vector3, heading_yaw: float = 0.0) -> OceanWhale:
	var whale := OceanWhale.new()
	whale.name = "OceanWhale"
	whale._origin_xz = Vector2(world_pos.x, world_pos.z)
	whale._heading_yaw = heading_yaw
	whale.position = Vector3(world_pos.x, -6.5, world_pos.z)
	if parent != null:
		parent.add_child(whale)
	return whale


## Release all statically cached whale meshes, materials, and spray textures cleanly.
static func clear_shared_cache() -> void:
	if _spray_quad != null:
		_spray_quad.material = null
	if _spray_mat != null:
		_spray_mat.albedo_texture = null
	_body_mesh = null
	_flipper_l_mesh = null
	_flipper_r_mesh = null
	_fluke_mesh = null
	_whale_mat = null
	_spray_tex = null
	_spray_mat = null
	_spray_quad = null


func _enter_tree() -> void:
	_active_whales += 1
	add_to_group(GROUP_WHALES)
	add_to_group(GROUP_BEASTS)


func _ready() -> void:
	_ensure_shared_assets()
	if _origin_xz == Vector2.ZERO and (absf(position.x) > 0.001 or absf(position.z) > 0.001):
		_origin_xz = Vector2(position.x, position.z)
	_build_rig()
	_apply_breach_pose(false)


func _exit_tree() -> void:
	for mi: MeshInstance3D in [_body_mi, _flipper_l_mi, _flipper_r_mi, _fluke_mi]:
		if mi != null and is_instance_valid(mi):
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					mi.set_surface_override_material(si, null)
			mi.mesh = null
			mi.material_override = null
	for gp: GPUParticles3D in [_breach_spray, _splash_plume]:
		if gp != null and is_instance_valid(gp):
			gp.emitting = false
			gp.visible = false
			var pm := gp.process_material as ParticleProcessMaterial
			if pm != null:
				pm.color_ramp = null
			gp.draw_pass_1 = null
			gp.process_material = null
	_body_mi = null
	_flipper_l_mi = null
	_flipper_r_mi = null
	_fluke_mi = null
	_breach_spray = null
	_splash_plume = null
	body_root = null
	left_flipper_pivot = null
	right_flipper_pivot = null
	tail_pivot = null
	_active_whales = maxi(0, _active_whales - 1)
	if _active_whales == 0:
		clear_shared_cache()


func _physics_process(delta: float) -> void:
	if _forced_apex:
		return
	step_breach(delta)


## Advance the ballistic ocean breach lifecycle by `delta` seconds (deterministic for tests & gameplay).
func step_breach(delta: float) -> void:
	if phase == Phase.DONE:
		return
	_forced_apex = false
	if not _call_played:
		_call_played = true
		if Audio.has_sound(&"whale_call"):
			Audio.play_sfx(&"whale_call", global_position if is_inside_tree() else position, 1.0)

	elapsed += maxf(0.0, delta)
	if elapsed < T_APPROACH_END:
		phase = Phase.APPROACH
	elif elapsed < T_RISE_END:
		phase = Phase.BREACH_RISE
	elif elapsed < T_APEX_END:
		phase = Phase.APEX_TWIST
	elif elapsed < T_SPLASH_END:
		phase = Phase.SPLASH_REENTRY
	elif elapsed < T_SUBMERGE_END:
		phase = Phase.SUBMERGE
	else:
		phase = Phase.DONE

	_apply_breach_pose(true)

	if phase == Phase.DONE and auto_despawn:
		queue_free()


## Snap directly into the iconic mid-breach soaring pose at `sea_y + 5.6 m` with wide-swept
## pectoral wings, erupting spray, and boiling foam ring beneath (ideal for showcase framing).
func force_breach_apex() -> void:
	_forced_apex = true
	elapsed = 3.25
	phase = Phase.APEX_TWIST
	var fwd := Vector3(-sin(_heading_yaw), 0.0, -cos(_heading_yaw))
	var wx := _origin_xz.x + fwd.x * 7.2
	var wz := _origin_xz.y + fwd.z * 7.2
	var sea_y := Sea.height(wx, wz) if Sea != null else 0.0

	var target_pos := Vector3(wx, sea_y + 5.6, wz)
	if is_inside_tree():
		global_position = target_pos
	else:
		position = target_pos

	if body_root != null:
		body_root.basis = Basis(Vector3.UP, _heading_yaw) \
			* Basis(Vector3.RIGHT, 0.58) \
			* Basis(Vector3.FORWARD, 0.72)
	if left_flipper_pivot != null:
		left_flipper_pivot.rotation = Vector3(-0.08, 0.14, -0.34)
	if right_flipper_pivot != null:
		right_flipper_pivot.rotation = Vector3(-0.08, -0.14, 0.34)
	if tail_pivot != null:
		tail_pivot.rotation = Vector3(-0.26, 0.0, 0.0)

	var surf_w := Vector3(wx, sea_y + 0.08, wz)
	if Ocean.current != null:
		Ocean.current.add_foam(surf_w, 6.5, 0.95)
		for ki in 4:
			var a := float(ki) * PI * 0.5 + 0.4
			Ocean.current.add_foam(surf_w + Vector3(cos(a) * 3.8, 0.0, sin(a) * 3.8), 3.4, 0.78)
	if _breach_spray != null and is_instance_valid(_breach_spray):
		_breach_spray.global_position = surf_w if is_inside_tree() else Vector3(0.0, -5.5, 0.0)
		_breach_spray.visible = true
		_breach_spray.restart()
		_breach_spray.emitting = true


# ==============================================================================
# Rig Construction & Ballistic Breach Choreography
# ==============================================================================

func _build_rig() -> void:
	body_root = Node3D.new()
	body_root.name = "WhaleBodyRoot"
	add_child(body_root)

	_body_mi = MeshInstance3D.new()
	_body_mi.name = "BodyMesh"
	_body_mi.mesh = _body_mesh
	_body_mi.material_override = _whale_mat
	_body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_body_mi.visibility_range_end = 420.0
	body_root.add_child(_body_mi)

	left_flipper_pivot = Node3D.new()
	left_flipper_pivot.name = "LeftFlipperPivot"
	left_flipper_pivot.position = Vector3(-1.45, -0.55, -2.20)
	body_root.add_child(left_flipper_pivot)

	_flipper_l_mi = MeshInstance3D.new()
	_flipper_l_mi.name = "LeftFlipperMesh"
	_flipper_l_mi.mesh = _flipper_l_mesh
	_flipper_l_mi.material_override = _whale_mat
	_flipper_l_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_flipper_l_mi.visibility_range_end = 420.0
	left_flipper_pivot.add_child(_flipper_l_mi)

	right_flipper_pivot = Node3D.new()
	right_flipper_pivot.name = "RightFlipperPivot"
	right_flipper_pivot.position = Vector3(1.45, -0.55, -2.20)
	body_root.add_child(right_flipper_pivot)

	_flipper_r_mi = MeshInstance3D.new()
	_flipper_r_mi.name = "RightFlipperMesh"
	_flipper_r_mi.mesh = _flipper_r_mesh
	_flipper_r_mi.material_override = _whale_mat
	_flipper_r_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_flipper_r_mi.visibility_range_end = 420.0
	right_flipper_pivot.add_child(_flipper_r_mi)

	tail_pivot = Node3D.new()
	tail_pivot.name = "TailPivot"
	tail_pivot.position = Vector3(0.0, 0.0, 5.20)
	body_root.add_child(tail_pivot)

	_fluke_mi = MeshInstance3D.new()
	_fluke_mi.name = "TailFlukeMesh"
	_fluke_mi.mesh = _fluke_mesh
	_fluke_mi.material_override = _whale_mat
	_fluke_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_fluke_mi.visibility_range_end = 420.0
	tail_pivot.add_child(_fluke_mi)

	if enable_effects:
		_breach_spray = _make_spray_emitter("BreachSpray", 26, 1.15, 2.2, 5.5, 10.5, 0.85)
		add_child(_breach_spray)
		_splash_plume = _make_spray_emitter("SplashPlume", 42, 1.65, 3.6, 8.0, 16.5, 1.35)
		add_child(_splash_plume)


func _apply_breach_pose(trigger_events: bool) -> void:
	var fwd := Vector3(-sin(_heading_yaw), 0.0, -cos(_heading_yaw))
	var travel := clampf(elapsed / T_SUBMERGE_END, 0.0, 1.0) * 18.0
	var wx := _origin_xz.x + fwd.x * travel
	var wz := _origin_xz.y + fwd.z * travel
	var sea_y := Sea.height(wx, wz) if Sea != null else 0.0

	var rel_y := -6.5
	var pitch := 0.30
	var roll := 0.0
	var flip_flap := 0.0
	var flip_sweep := 0.25
	var tail_pitch := 0.0

	if elapsed < T_APPROACH_END:
		var u := clampf(elapsed / T_APPROACH_END, 0.0, 1.0)
		rel_y = lerpf(-6.5, -1.5, smoothstep(0.0, 1.0, u))
		pitch = lerpf(0.26, 0.80, u)
		roll = 0.0
		flip_flap = -0.15
		flip_sweep = 0.38
		tail_pitch = sin(elapsed * 5.8) * 0.44
	elif elapsed < T_RISE_END:
		var u := clampf((elapsed - T_APPROACH_END) / (T_RISE_END - T_APPROACH_END), 0.0, 1.0)
		rel_y = lerpf(-1.5, 5.4, sin(u * PI * 0.5))
		pitch = lerpf(0.80, 0.52, u)
		roll = lerpf(0.0, 0.56, u * u)
		flip_flap = lerpf(-0.14, 0.28, u)
		flip_sweep = lerpf(0.38, 0.06, u)
		tail_pitch = sin(elapsed * 4.5) * 0.34 * (1.0 - 0.45 * u)
	elif elapsed < T_APEX_END:
		var u := clampf((elapsed - T_RISE_END) / (T_APEX_END - T_RISE_END), 0.0, 1.0)
		# Smooth ballistic crest peaking at sea_y + 6.2 m before rolling into plunge.
		var arc_boost := sin(u * PI) * 1.55
		rel_y = lerpf(5.4, 3.6, u) + arc_boost
		pitch = lerpf(0.52, -0.45, smoothstep(0.0, 1.0, u))
		roll = lerpf(0.56, deg_to_rad(135.0), smoothstep(0.0, 1.0, u))
		flip_flap = 0.28 + 0.14 * sin(u * PI)
		flip_sweep = -0.10
		tail_pitch = -0.22 + sin(u * PI) * 0.16
	elif elapsed < T_SPLASH_END:
		var u := clampf((elapsed - T_APEX_END) / (T_SPLASH_END - T_APEX_END), 0.0, 1.0)
		rel_y = lerpf(3.6, -3.2, u * u)
		pitch = lerpf(-0.45, -0.78, u)
		roll = lerpf(deg_to_rad(135.0), deg_to_rad(165.0), u)
		flip_flap = lerpf(0.28, -0.10, u)
		flip_sweep = lerpf(-0.08, 0.30, u)
		tail_pitch = lerpf(-0.20, 0.32, u)
	else:
		var u := clampf((elapsed - T_SPLASH_END) / (T_SUBMERGE_END - T_SPLASH_END), 0.0, 1.0)
		rel_y = lerpf(-3.2, -11.0, smoothstep(0.0, 1.0, u))
		pitch = lerpf(-0.78, -0.32, u)
		roll = lerpf(deg_to_rad(165.0), deg_to_rad(180.0), u)
		flip_flap = -0.12
		flip_sweep = 0.34
		tail_pitch = sin(u * TAU * 1.2) * 0.45

	var world_pos := Vector3(wx, sea_y + rel_y, wz)
	if is_inside_tree():
		global_position = world_pos
	else:
		position = world_pos

	if body_root != null:
		body_root.basis = Basis(Vector3.UP, _heading_yaw) \
			* Basis(Vector3.RIGHT, pitch) \
			* Basis(Vector3.FORWARD, roll)
	if left_flipper_pivot != null:
		left_flipper_pivot.rotation = Vector3(-0.06, flip_sweep, -flip_flap)
	if right_flipper_pivot != null:
		right_flipper_pivot.rotation = Vector3(-0.06, -flip_sweep, flip_flap)
	if tail_pivot != null:
		tail_pivot.rotation = Vector3(tail_pitch, 0.0, 0.0)

	if not trigger_events:
		return

	# Upward breach eruption spray & foam ring as the 14 m giant breaks the waves!
	if phase == Phase.BREACH_RISE and not _rise_sprayed and rel_y >= -0.2:
		_rise_sprayed = true
		var rise_w := Vector3(wx, sea_y + 0.06, wz)
		if Ocean.current != null:
			Ocean.current.add_foam(rise_w, 5.5, 0.9)
		Audio.play_sfx(&"splash_small", rise_w, 0.5)
		if _breach_spray != null and is_instance_valid(_breach_spray):
			_breach_spray.global_position = rise_w if is_inside_tree() else Vector3.ZERO
			_breach_spray.visible = true
			_breach_spray.restart()
			_breach_spray.emitting = true

	# Colossal splash re-entry impact: giant plume, radial boiling foam crater & whale_splashed signal!
	if phase == Phase.SPLASH_REENTRY and not _splash_fired and rel_y <= 0.5:
		_splash_fired = true
		var splash_w := Vector3(wx, sea_y + 0.08, wz)
		Audio.play_sfx(&"splash_large", splash_w, 1.5)
		if Ocean.current != null:
			Ocean.current.add_foam(splash_w, 9.0, 1.0)
			for ki in 6:
				var a := float(ki) / 6.0 * TAU
				Ocean.current.add_foam(splash_w + Vector3(cos(a) * 5.2, 0.0, sin(a) * 5.2), 4.6, 0.88)
		if _splash_plume != null and is_instance_valid(_splash_plume):
			_splash_plume.global_position = splash_w if is_inside_tree() else Vector3.ZERO
			_splash_plume.visible = true
			_splash_plume.restart()
			_splash_plume.emitting = true
		whale_splashed.emit(splash_w)


func _make_spray_emitter(node_name: String, amount_n: int, life_s: float, ring_r: float,
		vel_min: float, vel_max: float, quad_scale: float) -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc.emission_ring_axis = Vector3.UP
	proc.emission_ring_radius = ring_r
	proc.emission_ring_inner_radius = ring_r * 0.25
	proc.emission_ring_height = 0.25
	proc.direction = Vector3.UP
	proc.spread = 32.0
	proc.initial_velocity_min = vel_min
	proc.initial_velocity_max = vel_max
	proc.gravity = Vector3(0.0, -10.5, 0.0)
	proc.scale_min = quad_scale * 0.75
	proc.scale_max = quad_scale * 1.45

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.14, 0.70, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.99, 1.0, 0.0),
		Color(0.96, 0.99, 1.0, 0.82),
		Color(0.86, 0.95, 0.99, 0.42),
		Color(0.80, 0.92, 0.98, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 16
	ramp.gradient = grad
	proc.color_ramp = ramp

	var gp := GPUParticles3D.new()
	gp.name = node_name
	gp.top_level = true
	gp.amount = amount_n
	gp.lifetime = life_s
	gp.one_shot = true
	gp.explosiveness = 0.88
	gp.local_coords = false
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-12.0, -4.0, -12.0), Vector3(24.0, 22.0, 24.0))
	gp.process_material = proc
	gp.draw_pass_1 = _spray_quad
	gp.emitting = false
	gp.visible = false
	return gp


# ==============================================================================
# Shared Sculpted 14 m Humpback Whale ArrayMeshes (Zero Raw Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _whale_mat == null:
		_whale_mat = StandardMaterial3D.new()
		_whale_mat.vertex_color_use_as_albedo = true
		_whale_mat.vertex_color_is_srgb = true
		_whale_mat.roughness = 0.28
		_whale_mat.metallic = 0.04
		_whale_mat.clearcoat_enabled = true
		_whale_mat.clearcoat = 0.55
		_whale_mat.clearcoat_roughness = 0.16

	if _spray_tex == null:
		_spray_tex = _make_spray_puff_texture()
	if _spray_mat == null:
		_spray_mat = StandardMaterial3D.new()
		_spray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spray_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_spray_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_spray_mat.vertex_color_use_as_albedo = true
		_spray_mat.albedo_texture = _spray_tex
	if _spray_quad == null:
		_spray_quad = QuadMesh.new()
		_spray_quad.size = Vector2(1.4, 1.4)
		_spray_quad.material = _spray_mat

	if _body_mesh == null:
		_body_mesh = _build_whale_body_mesh()
	if _flipper_l_mesh == null:
		_flipper_l_mesh = _build_whale_flipper_mesh(-1.0)
	if _flipper_r_mesh == null:
		_flipper_r_mesh = _build_whale_flipper_mesh(1.0)
	if _fluke_mesh == null:
		_fluke_mesh = _build_whale_fluke_mesh()


static func _make_spray_puff_texture() -> ImageTexture:
	var sz := 48
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var r := sqrt(nx * nx + ny * ny)
			var w := clampf(1.0 - r, 0.0, 1.0)
			var alpha := w * w * smoothstep(0.0, 0.42, w)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static func _build_whale_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Streamlined 14 m Humpback fuselage (-Z rostrum snout -> +Z caudal peduncle).
	# Each station: [z, rx, ry_top, ry_bot, y_offset]
	const RAD_SEGS := 24
	var stations: Array[Array] = [
		[-6.95, 0.38, 0.20, 0.22, 0.06],   # Rounded rostrum snout tip
		[-6.25, 0.88, 0.40, 0.54, 0.04],   # Flared snout tip
		[-5.40, 1.32, 0.62, 0.96, 0.03],   # Arching upper jaw & lower mandible
		[-4.35, 1.64, 0.88, 1.28, 0.02],   # Deep pleated ventral throat pouch
		[-3.20, 1.84, 1.12, 1.48, 0.03],   # Eye-ridge brow & maximum head girth
		[-1.90, 1.96, 1.38, 1.56, 0.05],   # Massive pectoral shoulder chest
		[-0.50, 1.88, 1.48, 1.44, 0.06],   # Deep mid-torso
		[0.95, 1.60, 1.38, 1.20, 0.05],    # Dorsal hump rise
		[2.35, 1.22, 1.12, 0.92, 0.03],    # Muscular tapering flanks
		[3.65, 0.84, 0.86, 0.72, 0.01],    # Aft taper
		[4.60, 0.58, 0.66, 0.55, 0.00],    # Compressed caudal peduncle keel
		[5.35, 0.44, 0.54, 0.46, 0.00],    # Tail socket (overlaps TailPivot at z = 5.20)
	]

	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	for si in stations.size():
		var row: Array = stations[si]
		var z := float(row[0])
		var rx := float(row[1])
		var ry_top := float(row[2])
		var ry_bot := float(row[3])
		var y_off := float(row[4])
		var ring: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in RAD_SEGS:
			var a := float(k) / float(RAD_SEGS) * TAU
			var ca := cos(a)
			var sa := sin(a)
			# Sculpt physical fluted ventral throat pleats along the lower whale jaw & belly!
			var pleat_relief := 0.0
			var is_pleat_groove := false
			if z < 0.2 and sa < -0.20:
				var pleat_wave := sin(float(k) * PI)
				pleat_relief = pleat_wave * 0.045 * smoothstep(-0.20, -0.55, sa) * smoothstep(0.2, -1.8, z)
				is_pleat_groove = (k % 2 == 0)
			var py := y_off + (sa * ry_top if sa >= 0.0 else sa * (ry_bot + pleat_relief))
			var px := ca * rx
			ring.append(Vector3(px, py, z))
			cols.append(_whale_skin_color(z, sa, k, is_pleat_groove))
		rings.append(ring)
		ring_cols.append(cols)

	for si in range(rings.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var c0: Array = ring_cols[si]
		var c1: Array = ring_cols[si + 1]
		var zm := 0.5 * (float(stations[si][0]) + float(stations[si + 1][0]))
		var ym := 0.5 * (float(stations[si][4]) + float(stations[si + 1][4]))
		var ctr := Vector3(0.0, ym, zm)
		for k in RAD_SEGS:
			var nk := (k + 1) % RAD_SEGS
			_emit_outward_quad(st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3,
				ctr, c0[k] as Color, c1[k] as Color, c1[nk] as Color, c0[nk] as Color)

	# Cap snout (-Z) and peduncle (+Z) cleanly.
	var nose_tip := Vector3(0.0, 0.05, -7.12)
	var rear_cap := Vector3(0.0, 0.0, 5.48)
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	var last_r: Array = rings[rings.size() - 1]
	var last_c: Array = ring_cols[ring_cols.size() - 1]
	for k in RAD_SEGS:
		var nk := (k + 1) % RAD_SEGS
		_emit_outward_tri(st, nose_tip, first_r[nk] as Vector3, first_r[k] as Vector3,
			Vector3(0.0, 0.05, -6.2), COL_BACK_DARK, first_c[nk] as Color, first_c[k] as Color)
		_emit_outward_tri(st, rear_cap, last_r[k] as Vector3, last_r[nk] as Vector3,
			Vector3(0.0, 0.0, 4.6), COL_BACK_DARK, last_c[k] as Color, last_c[nk] as Color)

	# 2. Sculpted iconic Humpback dorsal hump & stubby curved dorsal fin (z = +0.85 .. +2.55).
	var dorsal_stations: Array[Array] = [
		[1.24, 0.85, 2.55, 0.24, COL_BACK_DARK],
		[1.56, 1.15, 2.40, 0.16, COL_BACK_HI],
		[1.82, 1.50, 2.38, 0.09, COL_BACK_HI],
		[1.98, 1.88, 2.46, 0.04, COL_BACK_DARK],
	]
	_append_vertical_fin(st, dorsal_stations)

	# 3. Characteristic Humpback rostrum tubercles & sea-barnacle chin clusters + eye ridges!
	var tubercle_spots: Array[Array] = [
		[Vector3(0.0, 0.28, -6.55), 0.14, COL_BARNACLE],
		[Vector3(-0.42, 0.34, -5.85), 0.13, COL_BACK_HI],
		[Vector3(0.42, 0.34, -5.85), 0.13, COL_BACK_HI],
		[Vector3(-0.76, 0.48, -4.95), 0.14, COL_BARNACLE],
		[Vector3(0.76, 0.48, -4.95), 0.14, COL_BARNACLE],
		[Vector3(0.0, -0.32, -6.45), 0.19, COL_BARNACLE],
		[Vector3(-0.55, -0.58, -5.70), 0.15, COL_BARNACLE],
		[Vector3(0.55, -0.58, -5.70), 0.15, COL_BARNACLE],
		[Vector3(-1.12, -0.22, -4.55), 0.15, COL_BARNACLE],
		[Vector3(1.12, -0.22, -4.55), 0.15, COL_BARNACLE],
	]
	for spec in tubercle_spots:
		_append_faceted_knob(st, spec[0] as Vector3, Vector3.ONE * float(spec[1]), spec[2] as Color)

	# Subtle raised brow ridges & dark obsidian whale eyes flanking the broad jaw corners.
	for sx: float in [-1.0, 1.0]:
		_append_faceted_knob(st, Vector3(sx * 1.66, 0.04, -3.55), Vector3(0.18, 0.16, 0.34), COL_BACK_HI)
		_append_faceted_knob(st, Vector3(sx * 1.76, -0.04, -3.55), Vector3(0.10, 0.11, 0.14), COL_EYE_DARK)

	st.generate_normals()
	return st.commit()


static func _build_whale_flipper_mesh(side_sgn: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Iconic 4.25 m long scalloped Humpback pectoral wing!
	# [x_local, y_local, z_lead, z_trail, half_y, col_top, col_bot]
	var stations: Array[Array] = [
		[0.00, 0.00, -0.55, 0.65, 0.22, COL_BACK_DARK, COL_FLIPPER_UNDER],
		[side_sgn * 0.75, -0.08, -0.35, 0.72, 0.18, COL_BACK_DARK, COL_FLIPPER_UNDER],
		[side_sgn * 1.55, -0.14, -0.05, 0.85, 0.15, COL_BACK_HI, COL_FLIPPER_UNDER],
		[side_sgn * 2.35, -0.18, 0.28, 1.02, 0.12, COL_BACK_DARK, COL_FLIPPER_UNDER],
		[side_sgn * 3.10, -0.20, 0.65, 1.24, 0.09, COL_BACK_HI, COL_FLIPPER_UNDER],
		[side_sgn * 3.78, -0.18, 1.08, 1.48, 0.06, COL_BARNACLE, COL_FLIPPER_UNDER],
		[side_sgn * 4.25, -0.14, 1.45, 1.66, 0.03, COL_FLIPPER_UNDER, COL_FLIPPER_UNDER],
	]
	_append_horizontal_wing(st, stations, side_sgn)

	# 5 characteristic white scalloped barnacle tubercles beading the flipper leading edge!
	for ti in 5:
		var frac := (float(ti) + 1.0) / 6.0
		var tx := side_sgn * lerpf(0.65, 3.65, frac)
		var ty := lerpf(-0.07, -0.18, frac)
		var tz := lerpf(-0.34, 1.02, frac) - 0.08
		_append_faceted_knob(st, Vector3(tx, ty, tz), Vector3(0.14, 0.09, 0.16), COL_BARNACLE)

	st.generate_normals()
	return st.commit()


static func _build_whale_fluke_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Muscular caudal peduncle stock overlapping torso socket by 25 cm (z_local = -0.25 .. +1.45).
	const PED_SEGS := 12
	var ped_stations: Array[Array] = [
		[-0.25, 0.45, 0.56, 0.48],
		[0.35, 0.34, 0.44, 0.36],
		[0.95, 0.24, 0.28, 0.24],
		[1.45, 0.14, 0.12, 0.12],
	]
	var rings: Array[Array] = []
	for row in ped_stations:
		var z := float(row[0])
		var rx := float(row[1])
		var ry_t := float(row[2])
		var ry_b := float(row[3])
		var ring: Array[Vector3] = []
		for k in PED_SEGS:
			var a := float(k) / float(PED_SEGS) * TAU
			var sa := sin(a)
			ring.append(Vector3(cos(a) * rx, sa * ry_t if sa >= 0.0 else sa * ry_b, z))
		rings.append(ring)

	for si in range(rings.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var zm := 0.5 * (float(ped_stations[si][0]) + float(ped_stations[si + 1][0]))
		var ctr := Vector3(0.0, 0.0, zm)
		for k in PED_SEGS:
			var nk := (k + 1) % PED_SEGS
			var c := COL_BACK_DARK if k < 6 else COL_FLANK
			_emit_outward_quad(st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3,
				ctr, c, c, c, c)

	var front_c := Vector3(0.0, 0.0, -0.32)
	var rear_c := Vector3(0.0, 0.0, 1.56)
	var r_f: Array = rings[0]
	var r_r: Array = rings[rings.size() - 1]
	for k in PED_SEGS:
		var nk := (k + 1) % PED_SEGS
		_emit_outward_tri(st, front_c, r_f[nk] as Vector3, r_f[k] as Vector3, Vector3(0.0, 0.0, 0.2),
			COL_BACK_DARK, COL_BACK_DARK, COL_BACK_DARK)
		_emit_outward_tri(st, rear_c, r_r[k] as Vector3, r_r[nk] as Vector3, Vector3(0.0, 0.0, 1.0),
			COL_BACK_DARK, COL_BACK_DARK, COL_BACK_DARK)

	# 2. Broad 4.7 m span horizontal scalloped Humpback tail flukes with central V-notch!
	for sx: float in [-1.0, 1.0]:
		var fluke_stations: Array[Array] = [
			[sx * 0.14, 0.00, 0.90, 1.62, 0.12, COL_BACK_DARK, COL_FLANK],
			[sx * 0.68, 0.02, 1.02, 1.98, 0.095, COL_BACK_DARK, COL_FLIPPER_UNDER],
			[sx * 1.28, 0.04, 1.24, 2.08, 0.072, COL_BACK_HI, COL_FLIPPER_UNDER],
			[sx * 1.85, 0.05, 1.56, 2.26, 0.048, COL_BACK_DARK, COL_BARNACLE],
			[sx * 2.35, 0.06, 1.98, 2.36, 0.022, COL_BARNACLE, COL_FLIPPER_UNDER],
		]
		_append_horizontal_wing(st, fluke_stations, sx)

	st.generate_normals()
	return st.commit()


static func _whale_skin_color(z: float, sin_a: float, seg_idx: int, is_pleat_groove: bool) -> Color:
	if sin_a > 0.55:
		# Occasional pale barnacle/scar speckle on dorsal ridge.
		if z < -2.0 and (seg_idx % 7 == 0):
			return COL_BACK_HI.lerp(COL_BARNACLE, 0.35)
		return COL_BACK_DARK.lerp(COL_BACK_HI, clampf((sin_a - 0.55) * 2.0, 0.0, 1.0))
	if sin_a > -0.14:
		return COL_BACK_DARK.lerp(COL_FLANK, clampf((-sin_a + 0.14) * 1.4, 0.0, 1.0))
	if z < 0.4:
		# Iconic cream-and-slate pleated Humpback ventral throat & chest!
		return COL_PLEAT_GROOVE if is_pleat_groove else COL_BELLY_CREAM
	return COL_FLANK.lerp(COL_BELLY_CREAM, clampf((-sin_a - 0.14) * 0.85, 0.0, 0.72))


# ==============================================================================
# Flat-Faceted `SurfaceTool` Helpers (`set_smooth_group(-1)`)
# ==============================================================================

static func _append_vertical_fin(st: SurfaceTool, stations: Array[Array]) -> void:
	var profiles: Array[Array] = []
	var pcols: Array[Color] = []
	for row in stations:
		var y := float(row[0])
		var z0 := float(row[1])
		var z1 := float(row[2])
		var hx := float(row[3])
		var zm := lerpf(z0, z1, 0.38)
		profiles.append([
			Vector3(0.0, y, z0),
			Vector3(hx, y, zm),
			Vector3(0.0, y, z1),
			Vector3(-hx, y, zm),
		])
		pcols.append(row[4] as Color)

	for i in range(profiles.size() - 1):
		var p0: Array = profiles[i]
		var p1: Array = profiles[i + 1]
		var c0 := pcols[i]
		var c1 := pcols[i + 1]
		var ctr: Vector3 = ((p0[0] as Vector3) + (p0[2] as Vector3) + (p1[0] as Vector3) + (p1[2] as Vector3)) * 0.25
		for k in 4:
			var nk := (k + 1) % 4
			_emit_outward_quad(st, p0[k] as Vector3, p1[k] as Vector3, p1[nk] as Vector3, p0[nk] as Vector3,
				ctr, c0, c1, c1, c0)

	var tip_p: Array = profiles[profiles.size() - 1]
	var tip_c := pcols[pcols.size() - 1]
	var tip_ctr: Vector3 = ((tip_p[0] as Vector3) + (tip_p[2] as Vector3)) * 0.5 + Vector3(0.0, 0.04, 0.0)
	var ref_lo: Vector3 = tip_ctr - Vector3(0.0, 0.20, 0.0)
	for k in 4:
		var nk := (k + 1) % 4
		_emit_outward_tri(st, tip_ctr, tip_p[k] as Vector3, tip_p[nk] as Vector3, ref_lo, tip_c, tip_c, tip_c)


static func _append_horizontal_wing(st: SurfaceTool, stations: Array[Array], side_sgn: float) -> void:
	# 6-facet beveled hydrofoil airfoil cross-section for silky sculpted wings & flukes!
	var profiles: Array[Array] = []
	var top_cols: Array[Color] = []
	var bot_cols: Array[Color] = []
	for row in stations:
		var x := float(row[0])
		var y := float(row[1])
		var z0 := float(row[2])
		var z1 := float(row[3])
		var hy := float(row[4])
		var za := lerpf(z0, z1, 0.28)
		var zb := lerpf(z0, z1, 0.66)
		profiles.append([
			Vector3(x, y, z0),
			Vector3(x, y + hy, za),
			Vector3(x, y + hy * 0.68, zb),
			Vector3(x, y, z1),
			Vector3(x, y - hy * 0.68, zb),
			Vector3(x, y - hy, za),
		])
		top_cols.append(row[5] as Color)
		bot_cols.append(row[6] as Color)

	for i in range(profiles.size() - 1):
		var p0: Array = profiles[i]
		var p1: Array = profiles[i + 1]
		var ctr: Vector3 = ((p0[0] as Vector3) + (p0[3] as Vector3) + (p1[0] as Vector3) + (p1[3] as Vector3)) * 0.25
		var ct0 := top_cols[i]
		var cb0 := bot_cols[i]
		var ct1 := top_cols[i + 1]
		var cb1 := bot_cols[i + 1]
		var c0s: Array[Color] = [ct0, ct0, ct0, cb0, cb0, cb0]
		var c1s: Array[Color] = [ct1, ct1, ct1, cb1, cb1, cb1]
		for k in 6:
			var nk := (k + 1) % 6
			_emit_outward_quad(st, p0[k] as Vector3, p1[k] as Vector3, p1[nk] as Vector3, p0[nk] as Vector3,
				ctr, c0s[k], c1s[k], c1s[nk], c0s[nk])

	var tip_p: Array = profiles[profiles.size() - 1]
	var tip_c := top_cols[top_cols.size() - 1]
	var tip_ctr: Vector3 = ((tip_p[0] as Vector3) + (tip_p[3] as Vector3)) * 0.5 + Vector3(side_sgn * 0.06, 0.0, 0.0)
	var ref_in: Vector3 = tip_ctr - Vector3(side_sgn * 0.25, 0.0, 0.0)
	for k in 6:
		var nk := (k + 1) % 6
		_emit_outward_tri(st, tip_ctr, tip_p[k] as Vector3, tip_p[nk] as Vector3, ref_in, tip_c, tip_c, tip_c)


static func _append_faceted_knob(st: SurfaceTool, center: Vector3, radii: Vector3, col: Color) -> void:
	# Compact 8-triangle octahedron tubercle/barnacle/eye knob.
	var px := center + Vector3(radii.x, 0.0, 0.0)
	var nx := center - Vector3(radii.x, 0.0, 0.0)
	var py := center + Vector3(0.0, radii.y, 0.0)
	var ny := center - Vector3(0.0, radii.y, 0.0)
	var pz := center + Vector3(0.0, 0.0, radii.z)
	var nz := center - Vector3(0.0, 0.0, radii.z)
	var col_lo := col.darkened(0.22)
	var ring: Array[Vector3] = [px, pz, nx, nz]
	for k in 4:
		var nk := (k + 1) % 4
		_emit_outward_tri(st, py, ring[k], ring[nk], center, col, col, col)
		_emit_outward_tri(st, ny, ring[nk], ring[k], center, col_lo, col_lo, col_lo)


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
