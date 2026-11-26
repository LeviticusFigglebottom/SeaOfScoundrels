class_name DolphinPod
extends Node3D
## Fair-weather pod of sculpted, bow-riding bottlenose/spinner dolphins that
## escort sailing ships with choreographed parabolic wave leaps, ballistic pitch
## & joyful roll, vertical mammalian tail-fluke strokes, and sparkling sea spray.

const GROUP_DOLPHINS := &"dolphins"
const GROUP_BEASTS := &"beasts"

# Painterly Bottlenose / Spinner Dolphin palette (authored in sRGB).
const COL_DORSAL := Color(0.176, 0.427, 0.478)       # Silver-teal dorsal back (#2d6d7a)
const COL_DORSAL_HI := Color(0.245, 0.525, 0.580)    # Sunlit dorsal highlight
const COL_FLANK_BAND := Color(0.455, 0.655, 0.695)   # Sweeping lateral spinner band
const COL_BELLY := Color(0.910, 0.929, 0.918)        # Warm pearl-cream belly (#e8edea)
const COL_BELLY_WARM := Color(0.945, 0.935, 0.895)   # Subtle sunlit throat cream
const COL_FIN_TIP := Color(0.130, 0.325, 0.375)      # Deep teal dorsal/flipper edge
const COL_SMILE_LINE := Color(0.105, 0.220, 0.265)   # Joyful curved smile & blowhole
const COL_EYE_DARK := Color(0.035, 0.045, 0.060)     # Wet obsidian glossy eye

# Staggered bow-riding formation slots relative to ship (-Z bow, +X starboard):
# [offset: Vector3, phase_offset: float, leap_height: float, body_scale: float, roll_dir: float]
const POD_SLOTS: Array[Array] = [
	[Vector3(-5.2, 0.0, -4.5), 0.00, 2.18, 1.04, -1.0],
	[Vector3(5.4, 0.0, -6.2), 2.15, 2.32, 0.98, 1.0],
	[Vector3(8.2, 0.0, -2.5), 4.25, 1.92, 0.90, 1.0],
	[Vector3(-8.0, 0.0, -1.8), 1.12, 1.98, 0.93, -1.0],
	[Vector3(2.8, 0.0, -9.0), 3.25, 2.24, 0.96, 1.0],
]

# Statically cached procedural ArrayMeshes & materials shared across all active pods.
static var _active_pods: int = 0
static var _body_mesh: ArrayMesh = null
static var _tail_mesh: ArrayMesh = null
static var _skin_mat: StandardMaterial3D = null
static var _eye_mat: StandardMaterial3D = null
static var _spray_tex: ImageTexture = null
static var _spray_mat: StandardMaterial3D = null
static var _spray_quad: QuadMesh = null

@export var pod_count: int = 3
@export var lifetime: float = 28.0
@export var enable_effects: bool = true

var follow_ship: Node3D = null
var age: float = 0.0

var _dolphins: Array[Dictionary] = []  # {root, body_mi, tail_pivot, tail_mi, slot_offset, phase, freq, leap_h, roll_dir, was_airborne, spray}
var _standalone_dist: float = 0.0
var _sfx_cooldown: float = 0.0
var _phase_forced: bool = false


## Spawn a bow-riding pod alongside `ship` (or cruising cleanly along -Z when `ship == null`).
static func spawn_alongside(parent: Node, ship: Node3D, count: int = 3, duration: float = 28.0) -> DolphinPod:
	var pod := DolphinPod.new()
	pod.name = "DolphinPod"
	pod.follow_ship = ship
	pod.pod_count = clampi(count, 1, POD_SLOTS.size())
	pod.lifetime = maxf(4.0, duration)
	if ship != null and is_instance_valid(ship):
		pod.position = ship.global_position if ship.is_inside_tree() else ship.position
	if parent != null:
		parent.add_child(pod)
	return pod


## Release all statically cached dolphin meshes, materials, and spray assets cleanly.
static func clear_shared_cache() -> void:
	if _spray_quad != null:
		_spray_quad.material = null
	if _spray_mat != null:
		_spray_mat.albedo_texture = null
	_body_mesh = null
	_tail_mesh = null
	_skin_mat = null
	_eye_mat = null
	_spray_tex = null
	_spray_mat = null
	_spray_quad = null


func _enter_tree() -> void:
	_active_pods += 1
	add_to_group(GROUP_DOLPHINS)
	add_to_group(GROUP_BEASTS)


func _ready() -> void:
	_ensure_shared_assets()
	_build_pod()
	_update_dolphins(0.0, false)


func _exit_tree() -> void:
	for d: Dictionary in _dolphins:
		for mi_key: String in ["body_mi", "tail_mi"]:
			var mi := d.get(mi_key) as MeshInstance3D
			if mi != null and is_instance_valid(mi):
				if mi.mesh != null:
					for si in mi.mesh.get_surface_count():
						mi.set_surface_override_material(si, null)
				mi.mesh = null
				mi.material_override = null
		var sp := d.get("spray") as GPUParticles3D
		if sp != null and is_instance_valid(sp):
			sp.emitting = false
			sp.visible = false
			var pm := sp.process_material as ParticleProcessMaterial
			if pm != null:
				pm.color_ramp = null
			sp.draw_pass_1 = null
			sp.process_material = null
	_dolphins.clear()
	follow_ship = null
	_active_pods = maxi(0, _active_pods - 1)
	if _active_pods == 0:
		clear_shared_cache()


func _physics_process(delta: float) -> void:
	age += delta
	_sfx_cooldown = maxf(0.0, _sfx_cooldown - delta)
	if not _phase_forced:
		if follow_ship == null or not is_instance_valid(follow_ship):
			_standalone_dist += 6.5 * delta
	_update_dolphins(delta, true)
	if age >= lifetime:
		queue_free()


## Return the root `Node3D` of every sculpted dolphin currently in the pod.
func get_dolphin_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for d: Dictionary in _dolphins:
		var root := d.get("root") as Node3D
		if root != null and is_instance_valid(root):
			out.append(root)
	return out


## Deterministically pose the pod at `phase_rad` (e.g. `PI * 0.5` for a mid-air leap apex)
## with picturesque staggered offsets across podmates, updating transforms & tail bend immediately.
func force_leap_phase(phase_rad: float) -> void:
	_phase_forced = true
	var stagger: Array[float] = [0.0, -0.46, 0.42, -0.72, 0.66]
	for i in _dolphins.size():
		var d: Dictionary = _dolphins[i]
		var stg: float = stagger[i % stagger.size()]
		d["phase"] = phase_rad + stg
		d["tail_phase"] = (phase_rad + stg) * 3.8
	_update_dolphins(0.0, false)


# ==============================================================================
# Pod Construction & Choreographed Wave-Leap Animation
# ==============================================================================

func _build_pod() -> void:
	var count := clampi(pod_count, 1, POD_SLOTS.size())
	for i in count:
		var slot: Array = POD_SLOTS[i]
		var slot_offset: Vector3 = slot[0] as Vector3
		var phase_off: float = float(slot[1])
		var leap_h: float = float(slot[2])
		var body_scale: float = float(slot[3])
		var roll_dir: float = float(slot[4])

		var d_root := Node3D.new()
		d_root.name = "Dolphin_%d" % i
		d_root.scale = Vector3.ONE * body_scale
		add_child(d_root)

		var body_mi := MeshInstance3D.new()
		body_mi.name = "BodyMesh"
		body_mi.mesh = _body_mesh
		body_mi.set_surface_override_material(0, _skin_mat)
		if _body_mesh.get_surface_count() > 1:
			body_mi.set_surface_override_material(1, _eye_mat)
		d_root.add_child(body_mi)

		var tail_pivot := Node3D.new()
		tail_pivot.name = "TailPivot"
		tail_pivot.position = Vector3(0.0, 0.0, 0.70)
		d_root.add_child(tail_pivot)

		var tail_mi := MeshInstance3D.new()
		tail_mi.name = "TailFlukeMesh"
		tail_mi.mesh = _tail_mesh
		tail_mi.material_override = _skin_mat
		tail_pivot.add_child(tail_mi)

		var spray: GPUParticles3D = null
		if enable_effects:
			spray = _make_splash_emitter(i)
			add_child(spray)

		_dolphins.append({
			"root": d_root,
			"body_mi": body_mi,
			"tail_pivot": tail_pivot,
			"tail_mi": tail_mi,
			"slot_offset": slot_offset,
			"phase": phase_off,
			"tail_phase": phase_off * 2.5,
			"freq": 1.85 + float(i) * 0.06,
			"leap_h": leap_h,
			"roll_dir": roll_dir,
			"was_airborne": sin(phase_off) > 0.0,
			"spray": spray,
		})


func _update_dolphins(delta: float, emit_splashes: bool) -> void:
	if _dolphins.is_empty():
		return

	# Resolve reference heading frame from follow_ship or pod's own transform.
	var ref_origin := global_position if is_inside_tree() else position
	var ref_fwd := -global_basis.z if is_inside_tree() else -transform.basis.z
	var cruise_speed := 6.5

	if follow_ship != null and is_instance_valid(follow_ship):
		ref_origin = follow_ship.global_position if follow_ship.is_inside_tree() else follow_ship.position
		var ship_b := follow_ship.global_basis if follow_ship.is_inside_tree() else follow_ship.transform.basis
		ref_fwd = -ship_b.z
		if follow_ship is RigidBody3D:
			var vel: Vector3 = (follow_ship as RigidBody3D).linear_velocity
			cruise_speed = clampf(Vector2(vel.x, vel.z).length(), 4.8, 12.0)
		elif follow_ship.has_method("forward_speed"):
			cruise_speed = clampf(absf(float(follow_ship.call("forward_speed"))), 4.8, 12.0)
	else:
		ref_origin += Vector3(ref_fwd.x, 0.0, ref_fwd.z).normalized() * _standalone_dist

	ref_fwd.y = 0.0
	if ref_fwd.length_squared() < 0.0001:
		ref_fwd = Vector3.FORWARD
	else:
		ref_fwd = ref_fwd.normalized()
	var ref_right := Vector3(-ref_fwd.z, 0.0, ref_fwd.x)
	var heading_yaw := atan2(-ref_fwd.x, -ref_fwd.z)

	# Smooth final 3-second dive-out beneath the waves as pod lifetime expires.
	var dive_out := 0.0
	if lifetime > 3.5 and age > lifetime - 3.0:
		var u := clampf((age - (lifetime - 3.0)) / 3.0, 0.0, 1.0)
		dive_out = u * u * (3.0 - 2.0 * u)

	var inv_pod := global_transform.affine_inverse() if is_inside_tree() else transform.affine_inverse()

	for d: Dictionary in _dolphins:
		var d_root := d["root"] as Node3D
		var tail_pivot := d["tail_pivot"] as Node3D
		if d_root == null or not is_instance_valid(d_root):
			continue

		var omega: float = float(d["freq"])
		var phase: float = float(d["phase"])
		if delta > 0.0:
			phase += omega * delta
			d["phase"] = phase
		var s := sin(phase)
		var ds := cos(phase) * omega
		var leap_h: float = float(d["leap_h"]) * (1.0 - dive_out)

		# Playful lateral bow-wave weave & slight fore-aft surge.
		var slot_off: Vector3 = d["slot_offset"] as Vector3
		var weave_x := sin(phase * 0.5) * 0.55
		var surge_z := cos(phase) * 0.60
		var world_xz := ref_origin + ref_right * (slot_off.x + weave_x) + ref_fwd * (-slot_off.z + surge_z)
		var wave_y := Sea.height(world_xz.x, world_xz.z) if Sea != null else 0.0

		var rel_y: float
		var vy: float
		if s > 0.0 and leap_h > 0.05:
			rel_y = pow(s, 0.88) * leap_h
			vy = 0.88 * pow(maxf(s, 0.06), -0.12) * ds * leap_h
		else:
			rel_y = s * 0.95
			vy = ds * 0.95
		rel_y -= dive_out * 4.5
		if dive_out > 0.05:
			vy -= dive_out * 1.6

		var world_pos := Vector3(world_xz.x, wave_y + rel_y, world_xz.z)
		var local_pos := inv_pod * world_pos
		d_root.position = local_pos

		# Realistic ballistic pitch tangent (nose up on breach, level at apex, nose-first dive!)
		# plus joyful slight axial roll during airborne arc.
		var pitch_rad := clampf(atan2(vy, cruise_speed), -0.78, 0.78)
		var roll_dir: float = float(d["roll_dir"])
		var roll_rad := roll_dir * (0.26 * maxf(s, 0.0) * sin(phase * 2.0) + 0.07 * sin(phase))
		var weave_yaw := -cos(phase * 0.5) * 0.06
		var world_basis := Basis(Vector3.UP, heading_yaw + weave_yaw) \
			* Basis(Vector3.RIGHT, pitch_rad) \
			* Basis(Vector3.FORWARD, roll_rad)
		var pod_b_inv := global_basis.inverse() if is_inside_tree() else transform.basis.inverse()
		d_root.basis = pod_b_inv * world_basis

		# Mammalian vertical tail-fluke oscillation (faster/wider power kicks underwater!).
		var airborne := rel_y > 0.08
		var tail_rate := 5.8 if airborne else 10.5
		var tail_phase: float = float(d["tail_phase"]) + tail_rate * delta
		d["tail_phase"] = tail_phase
		var tail_amp := 0.22 if airborne else 0.44
		if tail_pivot != null and is_instance_valid(tail_pivot):
			tail_pivot.rotation.x = sin(tail_phase) * tail_amp

		# Breach & re-entry splash rings + feathered water droplets + crisp splash SFX!
		var was_air: bool = bool(d["was_airborne"])
		d["was_airborne"] = airborne
		if emit_splashes and dive_out < 0.35 and airborne != was_air:
			var splash_w := Vector3(world_xz.x, wave_y + 0.04, world_xz.z)
			if Ocean.current != null:
				Ocean.current.add_foam(splash_w, 1.35, 0.72)
			if _sfx_cooldown <= 0.0:
				_sfx_cooldown = 0.42
				Audio.play_sfx(&"splash_small", splash_w, -5.0, 0.14)
			var sp := d.get("spray") as GPUParticles3D
			if sp != null and is_instance_valid(sp):
				sp.position = inv_pod * splash_w
				sp.visible = true
				sp.restart()
				sp.emitting = true


func _make_splash_emitter(idx: int) -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc.emission_ring_axis = Vector3.UP
	proc.emission_ring_radius = 0.42
	proc.emission_ring_inner_radius = 0.08
	proc.emission_ring_height = 0.08
	proc.direction = Vector3.UP
	proc.spread = 38.0
	proc.initial_velocity_min = 2.4
	proc.initial_velocity_max = 4.6
	proc.gravity = Vector3(0.0, -9.8, 0.0)
	proc.scale_min = 0.55
	proc.scale_max = 1.15

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.99, 1.0, 0.0),
		Color(0.94, 0.98, 1.0, 0.72),
		Color(0.86, 0.95, 0.99, 0.36),
		Color(0.82, 0.94, 0.98, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 16
	ramp.gradient = grad
	proc.color_ramp = ramp

	var gp := GPUParticles3D.new()
	gp.name = "DolphinSplash_%d" % idx
	gp.amount = 14
	gp.lifetime = 0.62
	gp.one_shot = true
	gp.explosiveness = 0.88
	gp.local_coords = false
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-2.5, -1.0, -2.5), Vector3(5.0, 4.0, 5.0))
	gp.process_material = proc
	gp.draw_pass_1 = _spray_quad
	gp.emitting = false
	gp.visible = false
	return gp


# ==============================================================================
# Shared Sculpted Flat-Faceted Bottlenose Dolphin Meshes (Zero Raw Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _skin_mat == null:
		_skin_mat = StandardMaterial3D.new()
		_skin_mat.vertex_color_use_as_albedo = true
		_skin_mat.vertex_color_is_srgb = true
		_skin_mat.roughness = 0.30
		_skin_mat.metallic = 0.04
		_skin_mat.clearcoat_enabled = true
		_skin_mat.clearcoat = 0.45
		_skin_mat.clearcoat_roughness = 0.18

	if _eye_mat == null:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.vertex_color_use_as_albedo = true
		_eye_mat.vertex_color_is_srgb = true
		_eye_mat.roughness = 0.08
		_eye_mat.metallic = 0.08
		_eye_mat.clearcoat_enabled = true
		_eye_mat.clearcoat = 0.92
		_eye_mat.clearcoat_roughness = 0.06

	if _spray_tex == null:
		_spray_tex = _make_droplet_texture()
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
		_spray_quad.size = Vector2(0.26, 0.26)
		_spray_quad.material = _spray_mat

	if _body_mesh == null:
		_body_mesh = _build_dolphin_body_mesh()
	if _tail_mesh == null:
		_tail_mesh = _build_dolphin_tail_mesh()


static func _make_droplet_texture() -> ImageTexture:
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var r := sqrt(nx * nx + ny * ny)
			var w := clampf(1.0 - r, 0.0, 1.0)
			var alpha := w * w * smoothstep(0.0, 0.45, w)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static func _build_dolphin_body_mesh() -> ArrayMesh:
	var skin_st := SurfaceTool.new()
	skin_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eye_st := SurfaceTool.new()
	eye_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Streamlined Bottlenose / Spinner Dolphin fusiform torso (-Z rostrum snout -> +Z peduncle).
	# Each station: [z, rx, ry_top, ry_bot, y_offset]
	const RAD_SEGS := 18
	var stations: Array[Array] = [
		[-1.14, 0.014, 0.012, 0.010, -0.042],  # Rounded rostrum snout tip
		[-1.03, 0.044, 0.028, 0.026, -0.040],  # Tapered bottlenose beak
		[-0.91, 0.072, 0.044, 0.040, -0.032],  # Beak-to-melon smile crease base
		[-0.81, 0.132, 0.140, 0.078, 0.004],   # Iconic rounded dolphin melon forehead!
		[-0.66, 0.188, 0.196, 0.134, 0.022],   # Expressive cheek & eye brow
		[-0.44, 0.232, 0.240, 0.190, 0.026],   # Sleek pectoral shoulders
		[-0.18, 0.252, 0.264, 0.214, 0.024],   # Broad hydrodynamic mid-torso
		[0.08, 0.238, 0.254, 0.200, 0.020],    # Dorsal-fin crown
		[0.34, 0.185, 0.204, 0.154, 0.012],    # Tapering flank
		[0.56, 0.120, 0.146, 0.104, 0.004],    # Aft waist
		[0.74, 0.068, 0.094, 0.068, 0.000],    # Caudal peduncle joint (overlaps TailPivot at 0.70)
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
			var py := y_off + (sa * ry_top if sa >= 0.0 else sa * ry_bot)
			var px := ca * rx
			ring.append(Vector3(px, py, z))
			cols.append(_dolphin_skin_color(z, sa))
		rings.append(ring)
		ring_cols.append(cols)

	# Loft torso stations cleanly with outward normals.
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
			_emit_outward_quad(skin_st, r0[k], r1[k], r1[nk], r0[nk], ctr, c0[k], c1[k], c1[nk], c0[nk])

	# Cap rostrum snout tip (-Z) and peduncle joint (+Z).
	var nose_tip := Vector3(0.0, -0.042, -1.168)
	var tail_cap := Vector3(0.0, 0.0, 0.76)
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	var last_r: Array = rings[rings.size() - 1]
	var last_c: Array = ring_cols[ring_cols.size() - 1]
	for k in RAD_SEGS:
		var nk := (k + 1) % RAD_SEGS
		_emit_outward_tri(skin_st, nose_tip, first_r[nk], first_r[k], Vector3(0.0, -0.042, -1.04),
			COL_DORSAL, first_c[nk], first_c[k])
		_emit_outward_tri(skin_st, tail_cap, last_r[k], last_r[nk], Vector3(0.0, 0.0, 0.62),
			COL_DORSAL, last_c[k], last_c[nk])

	# 2. Charming curved dolphin smile line on both cheeks + subtle blowhole crescent on melon!
	for sx: float in [-1.0, 1.0]:
		var smile_pts: Array[Vector3] = [
			Vector3(sx * 0.036, -0.044, -1.06),
			Vector3(sx * 0.068, -0.040, -0.94),
			Vector3(sx * 0.118, -0.024, -0.82),
			Vector3(sx * 0.158, -0.008, -0.73),
		]
		for si in range(smile_pts.size() - 1):
			_append_tapered_prism(skin_st, smile_pts[si], smile_pts[si + 1], 0.009, 0.008, 4,
				COL_SMILE_LINE, COL_SMILE_LINE)
	# Crescent blowhole inset atop the melon crown.
	_append_tapered_prism(skin_st, Vector3(-0.024, 0.214, -0.65), Vector3(0.024, 0.214, -0.65),
		0.009, 0.009, 4, COL_SMILE_LINE, COL_SMILE_LINE)

	# 3. Iconic curved falcate dorsal fin rising off the back (swept sickle trailing edge!).
	var dorsal_stations: Array[Array] = [
		[0.24, -0.10, 0.30, 0.040, COL_DORSAL],
		[0.34, -0.01, 0.28, 0.031, COL_DORSAL],
		[0.44, 0.09, 0.29, 0.022, COL_DORSAL_HI],
		[0.52, 0.20, 0.33, 0.013, COL_FIN_TIP],
		[0.57, 0.30, 0.37, 0.006, COL_FIN_TIP],
	]
	_append_vertical_fin(skin_st, dorsal_stations)

	# 4. Swept hydrofoil pectoral flippers (±X) countershaded teal top / pearl-cream underside!
	for sx: float in [-1.0, 1.0]:
		var pec_stations: Array[Array] = [
			[sx * 0.19, -0.045, -0.44, -0.18, 0.028, COL_DORSAL, COL_BELLY],
			[sx * 0.32, -0.088, -0.35, -0.14, 0.021, COL_DORSAL, COL_BELLY],
			[sx * 0.45, -0.132, -0.23, -0.08, 0.014, COL_DORSAL_HI, COL_BELLY],
			[sx * 0.56, -0.165, -0.10, -0.01, 0.008, COL_FIN_TIP, COL_FLANK_BAND],
			[sx * 0.62, -0.182, -0.01, 0.04, 0.004, COL_FIN_TIP, COL_FIN_TIP],
		]
		_append_horizontal_wing(skin_st, pec_stations, sx)

	# 5. Expressive wet obsidian glossy dolphin eyes on Surface 1 (clearcoat material!).
	for sx: float in [-1.0, 1.0]:
		var eye_pos := Vector3(sx * 0.168, 0.020, -0.695)
		_append_faceted_ellipsoid(eye_st, eye_pos, Vector3(0.022, 0.026, 0.032), COL_EYE_DARK)

	skin_st.generate_normals()
	var mesh := skin_st.commit()
	eye_st.generate_normals()
	eye_st.commit(mesh)
	return mesh


static func _build_dolphin_tail_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Articulated muscular caudal peduncle stock overlapping torso by 4 cm (z = -0.04 .. +0.34).
	const PED_SEGS := 10
	var ped_stations: Array[Array] = [
		[-0.04, 0.072, 0.098, 0.072],
		[0.08, 0.056, 0.078, 0.058],
		[0.20, 0.042, 0.056, 0.044],
		[0.32, 0.036, 0.034, 0.030],
		[0.41, 0.016, 0.014, 0.014],
	]
	var rings: Array[Array] = []
	var rcols: Array[Array] = []
	for row in ped_stations:
		var z := float(row[0])
		var rx := float(row[1])
		var ry_t := float(row[2])
		var ry_b := float(row[3])
		var ring: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in PED_SEGS:
			var a := float(k) / float(PED_SEGS) * TAU
			var sa := sin(a)
			var py := sa * ry_t if sa >= 0.0 else sa * ry_b
			ring.append(Vector3(cos(a) * rx, py, z))
			cols.append(COL_DORSAL if sa >= -0.15 else COL_FLANK_BAND.lerp(COL_BELLY, clampf((-sa - 0.15) * 1.4, 0.0, 1.0)))
		rings.append(ring)
		rcols.append(cols)

	for si in range(rings.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var c0: Array = rcols[si]
		var c1: Array = rcols[si + 1]
		var zm := 0.5 * (float(ped_stations[si][0]) + float(ped_stations[si + 1][0]))
		var ctr := Vector3(0.0, 0.0, zm)
		for k in PED_SEGS:
			var nk := (k + 1) % PED_SEGS
			_emit_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ctr, c0[k], c1[k], c1[nk], c0[nk])

	# Cap front and rear ends of peduncle cleanly.
	var front_c := Vector3(0.0, 0.0, -0.05)
	var rear_c := Vector3(0.0, 0.0, 0.425)
	var r_front: Array = rings[0]
	var r_rear: Array = rings[rings.size() - 1]
	for k in PED_SEGS:
		var nk := (k + 1) % PED_SEGS
		_emit_outward_tri(st, front_c, r_front[nk], r_front[k], Vector3(0.0, 0.0, 0.08),
			COL_DORSAL, COL_DORSAL, COL_DORSAL)
		_emit_outward_tri(st, rear_c, r_rear[k], r_rear[nk], Vector3(0.0, 0.0, 0.30),
			COL_FIN_TIP, COL_FIN_TIP, COL_FIN_TIP)

	# 2. Iconic horizontal crescent marine-mammal tail flukes with crisp central V-notch!
	for sx: float in [-1.0, 1.0]:
		var fluke_stations: Array[Array] = [
			[sx * 0.025, 0.000, 0.24, 0.42, 0.024, COL_DORSAL, COL_FLANK_BAND],
			[sx * 0.135, 0.002, 0.28, 0.49, 0.017, COL_DORSAL, COL_BELLY],
			[sx * 0.265, 0.004, 0.36, 0.54, 0.012, COL_DORSAL_HI, COL_BELLY],
			[sx * 0.385, 0.006, 0.46, 0.59, 0.007, COL_FIN_TIP, COL_FLANK_BAND],
			[sx * 0.455, 0.008, 0.55, 0.61, 0.003, COL_FIN_TIP, COL_FIN_TIP],
		]
		_append_horizontal_wing(st, fluke_stations, sx)

	st.generate_normals()
	return st.commit()


static func _dolphin_skin_color(z: float, sin_a: float) -> Color:
	# Sweeping countershading: silver-teal dorsal cape + curved spinner lateral band + pearl-cream belly.
	var cape_dip := -0.10 + 0.16 * clampf((z + 0.35) / 1.15, 0.0, 1.0)
	if sin_a > 0.72:
		return COL_DORSAL.lerp(COL_DORSAL_HI, clampf((sin_a - 0.72) * 3.0, 0.0, 1.0))
	if sin_a > cape_dip + 0.18:
		return COL_DORSAL
	if sin_a > cape_dip - 0.20:
		var u := clampf((sin_a - (cape_dip - 0.20)) / 0.38, 0.0, 1.0)
		return COL_BELLY.lerp(COL_FLANK_BAND, smoothstep(0.0, 0.55, u)).lerp(COL_DORSAL, smoothstep(0.55, 1.0, u))
	if z < -0.20 and sin_a < -0.55:
		return COL_BELLY_WARM
	return COL_BELLY


# ==============================================================================
# Flat-Faceted `SurfaceTool` Sculpting Helpers (`set_smooth_group(-1)`)
# ==============================================================================

static func _append_vertical_fin(st: SurfaceTool, stations: Array[Array]) -> void:
	# Each station: [y, z_lead, z_trail, half_x, col]
	var profiles: Array[Array] = []
	var pcols: Array[Color] = []
	for row in stations:
		var y := float(row[0])
		var z0 := float(row[1])
		var z1 := float(row[2])
		var hx := float(row[3])
		var zm := lerpf(z0, z1, 0.36)
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
			_emit_outward_quad(st, p0[k], p1[k], p1[nk], p0[nk], ctr, c0, c1, c1, c0)

	# Cap fin tip cleanly.
	var tip_p: Array = profiles[profiles.size() - 1]
	var tip_c := pcols[pcols.size() - 1]
	var tip_ctr: Vector3 = ((tip_p[0] as Vector3) + (tip_p[2] as Vector3)) * 0.5 + Vector3(0.0, 0.015, 0.0)
	var ref_lo: Vector3 = tip_ctr - Vector3(0.0, 0.08, 0.0)
	for k in 4:
		var nk := (k + 1) % 4
		_emit_outward_tri(st, tip_ctr, tip_p[k], tip_p[nk], ref_lo, tip_c, tip_c, tip_c)


static func _append_horizontal_wing(st: SurfaceTool, stations: Array[Array], side_sgn: float) -> void:
	# Each station: [x, y, z_lead, z_trail, half_y, col_top, col_bot]
	var profiles: Array[Array] = []
	var top_cols: Array[Color] = []
	var bot_cols: Array[Color] = []
	for row in stations:
		var x := float(row[0])
		var y := float(row[1])
		var z0 := float(row[2])
		var z1 := float(row[3])
		var hy := float(row[4])
		var zm := lerpf(z0, z1, 0.35)
		profiles.append([
			Vector3(x, y, z0),
			Vector3(x, y + hy, zm),
			Vector3(x, y, z1),
			Vector3(x, y - hy, zm),
		])
		top_cols.append(row[5] as Color)
		bot_cols.append(row[6] as Color)

	for i in range(profiles.size() - 1):
		var p0: Array = profiles[i]
		var p1: Array = profiles[i + 1]
		var ctr: Vector3 = ((p0[0] as Vector3) + (p0[2] as Vector3) + (p1[0] as Vector3) + (p1[2] as Vector3)) * 0.25
		var c0s: Array[Color] = [top_cols[i], top_cols[i], bot_cols[i], bot_cols[i]]
		var c1s: Array[Color] = [top_cols[i + 1], top_cols[i + 1], bot_cols[i + 1], bot_cols[i + 1]]
		for k in 4:
			var nk := (k + 1) % 4
			_emit_outward_quad(st, p0[k], p1[k], p1[nk], p0[nk], ctr, c0s[k], c1s[k], c1s[nk], c0s[nk])

	# Cap wing/fluke outer tip cleanly.
	var tip_p: Array = profiles[profiles.size() - 1]
	var tip_c := top_cols[top_cols.size() - 1]
	var tip_ctr: Vector3 = ((tip_p[0] as Vector3) + (tip_p[2] as Vector3)) * 0.5 + Vector3(side_sgn * 0.015, 0.0, 0.0)
	var ref_in: Vector3 = tip_ctr - Vector3(side_sgn * 0.08, 0.0, 0.0)
	for k in 4:
		var nk := (k + 1) % 4
		_emit_outward_tri(st, tip_ctr, tip_p[k], tip_p[nk], ref_in, tip_c, tip_c, tip_c)


static func _append_tapered_prism(st: SurfaceTool, p0: Vector3, p1: Vector3,
		r0: float, r1: float, sides: int, c0: Color, c1: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-8:
		return
	var dir := axis.normalized()
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.85 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := u.cross(dir).normalized()
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for k in sides:
		var a := float(k) / float(sides) * TAU
		var radial := u * cos(a) + v * sin(a)
		ring0.append(p0 + radial * r0)
		ring1.append(p1 + radial * r1)
	var mid := (p0 + p1) * 0.5
	for k in sides:
		var nk := (k + 1) % sides
		_emit_outward_quad(st, ring0[k], ring1[k], ring1[nk], ring0[nk], mid, c0, c1, c1, c0)


static func _append_faceted_ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, col: Color) -> void:
	const LON := 8
	const LAT := 4
	var rings: Array[Array] = []
	for li in range(1, LAT):
		var phi := PI * float(li) / float(LAT)
		var ring: Array[Vector3] = []
		for ki in LON:
			var theta := TAU * float(ki) / float(LON)
			ring.append(center + Vector3(
				sin(phi) * cos(theta) * radii.x,
				cos(phi) * radii.y,
				sin(phi) * sin(theta) * radii.z
			))
		rings.append(ring)
	var north := center + Vector3(0.0, radii.y, 0.0)
	var south := center - Vector3(0.0, radii.y, 0.0)
	for ki in LON:
		var nki := (ki + 1) % LON
		_emit_outward_tri(st, north, rings[0][ki], rings[0][nki], center, col, col, col)
		_emit_outward_tri(st, south, rings[rings.size() - 1][nki], rings[rings.size() - 1][ki], center, col, col, col)
	for li in range(rings.size() - 1):
		for ki in LON:
			var nki := (ki + 1) % LON
			_emit_outward_quad(st, rings[li][ki], rings[li + 1][ki], rings[li + 1][nki], rings[li][nki],
				center, col, col, col, col)


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
