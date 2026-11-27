class_name MantaRay
extends Node3D
## Majestic, peaceful underwater sculpted Giant Reef Manta Ray.
##
## Glides serenely along curving figure-8 / elliptical turquoise lagoon orbits
## (-1.8 m .. -4.8 m, strictly submerged <= -1.2 m) with articulated undulating
## swept pectoral wings, cephalic head lobes, turquoise-spotted indigo-slate
## shoulder chevrons, pale cream belly, and a long tapered whip tail.
##
## Uses strictly sculpted flat-faceted `SurfaceTool` `ArrayMesh`es (`0` raw
## primitives, `vertex_color_is_srgb = true`), ref-counted static mesh/material
## caching, 85 m visibility culling, and 88 m CPU skip gating (0.00 ms far cost).

const GROUP := &"manta_rays"
const GROUP_BEASTS := &"beasts"
const VISIBILITY_END := 85.0
const VISIBILITY_MARGIN := 14.0
const CPU_CULL_DIST := 88.0
const MAX_MANTA_Y := -1.2
const MOORING_CLEAR_RADIUS := 10.5
const PIER_CLEAR_RADIUS := 6.0

# Trailing underwater wingtip micro-bubble constants (zero runtime allocations).
const BUBBLE_COUNT := 12
const BUBBLES_PER_WING := 6
const WINGTIP_PIVOT_X := 1.83
const WINGTIP_PIVOT_Y := 0.10
const WINGTIP_PIVOT_Z := 0.28
const BUBBLE_CEILING_WORLD_Y := MAX_MANTA_Y + 0.9

# Painterly tropical giant reef manta palette (authored in sRGB).
const COL_BACK_DEEP := Color(0.10, 0.16, 0.26)
const COL_BACK_SLATE := Color(0.15, 0.25, 0.36)
const COL_CHEVRON := Color(0.76, 0.90, 0.94)
const COL_SPOT_TURQ := Color(0.24, 0.82, 0.86)
const COL_BELLY_CREAM := Color(0.93, 0.92, 0.86)
const COL_BELLY_GILL := Color(0.74, 0.78, 0.82)
const COL_TAIL_DARK := Color(0.09, 0.13, 0.21)
const COL_EYE := Color(0.06, 0.07, 0.10)
const COL_BUBBLE_TOP := Color(0.96, 1.00, 1.00, 1.0)
const COL_BUBBLE_MID := Color(0.74, 0.97, 0.99, 1.0)
const COL_BUBBLE_BOT := Color(0.48, 0.88, 0.95, 1.0)

static var _active_mantas: int = 0
static var _body_mesh: ArrayMesh = null
static var _wing_left_mesh: ArrayMesh = null
static var _wing_right_mesh: ArrayMesh = null
static var _manta_mat: StandardMaterial3D = null
static var _bubble_mesh: ArrayMesh = null
static var _bubble_mat: StandardMaterial3D = null

@export var orbit_radius: float = 13.5
@export var orbit_speed: float = 0.24
@export var figure_eight_blend: float = 0.42
@export var min_depth_y: float = -4.6
@export var max_depth_y: float = -1.85
@export var seed_val: int = 211

var _glide_root: Node3D = null
var _body_mi: MeshInstance3D = null
var _left_wing_pivot: Node3D = null
var _right_wing_pivot: Node3D = null
var _left_wing_mi: MeshInstance3D = null
var _right_wing_mi: MeshInstance3D = null
var _bubbles_mmi: MultiMeshInstance3D = null
var _clock: float = 0.0
var _phase_offset: float = 0.0
var _prev_local_pos: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _has_prev: bool = false
var _built: bool = false
var _bubbles_initialized: bool = false

# Preallocated per-bubble buffers (zero steady-state heap allocations in step_glide).
var _bubble_origin: PackedVector3Array = PackedVector3Array()
var _bubble_pos: PackedVector3Array = PackedVector3Array()
var _bubble_age: PackedFloat32Array = PackedFloat32Array()
var _bubble_lifetime: PackedFloat32Array = PackedFloat32Array()
var _bubble_rise_speed: PackedFloat32Array = PackedFloat32Array()
var _bubble_phase: PackedFloat32Array = PackedFloat32Array()
var _bubble_helix_r: PackedFloat32Array = PackedFloat32Array()
var _bubble_helix_freq: PackedFloat32Array = PackedFloat32Array()
var _bubble_scale: PackedFloat32Array = PackedFloat32Array()


## Release all statically cached MantaRay meshes and materials cleanly.
static func clear_shared_cache() -> void:
	_body_mesh = null
	_wing_left_mesh = null
	_wing_right_mesh = null
	_manta_mat = null
	_bubble_mesh = null
	_bubble_mat = null


## Deterministically spawn a gliding `MantaRay` over a shallow turquoise reef lagoon
## around `island` (routing gracefully above its primary `CoralReef` bed when present).
static func populate_for_island(island: Island, rng_seed: int = 0) -> MantaRay:
	if island == null:
		return null

	var rng := RandomNumberGenerator.new()
	var s := rng_seed if rng_seed != 0 else (island.island_id.hash() ^ 0x4A47A911)
	if s == 0:
		s = 0x4A47A911
	rng.seed = s

	var chosen_xz := Vector2.ZERO
	var chosen_seabed := -3.8
	var found := false

	var mooring_xz := Vector2(island.mooring_transform.origin.x, island.mooring_transform.origin.z)
	var has_pier := island is Outpost
	var pier_a := Vector2.ZERO
	var pier_b := Vector2.ZERO
	if has_pier:
		var op := island as Outpost
		pier_a = Vector2(op.dock_local_transform.origin.x, op.dock_local_transform.origin.z)
		pier_b = Vector2(op.dock_pier_end_local.x, op.dock_pier_end_local.z)

	var orb_r := rng.randf_range(11.5, 16.5)

	# 1. Anchor gracefully across the island's primary CoralReef bed so divers spot the Manta
	#    gliding right over the vibrant staghorn/brain corals and reef fish!
	var reef := island.get_node_or_null(^"CoralReef") as CoralReef
	if reef != null:
		var pts := reef.get_placed_transforms()
		for pi in mini(pts.size(), 16):
			var p: Vector3 = pts[pi].origin
			var pxz := Vector2(p.x, p.z)
			if not _is_clear_of_harbour(pxz, mooring_xz, has_pier, pier_a, pier_b):
				continue
			var bed_y := island.surface_height(p.x, p.z)
			if bed_y <= -2.1 and bed_y >= -6.5:
				# Offset center slightly seaward so the inner arc sweeps smoothly above the coral bed.
				var out_dir := pxz.normalized() if pxz.length_squared() > 0.01 else Vector2(0.0, -1.0)
				chosen_xz = pxz + out_dir * (orb_r * 0.45)
				chosen_seabed = minf(bed_y, island.surface_height(chosen_xz.x, chosen_xz.y))
				found = true
				break

	# 2. Fallback deterministic reef shelf sweep (-2.4 m .. -6.5 m).
	if not found:
		var r_min := maxf(8.0, island.island_radius * 0.72)
		var r_max := maxf(r_min + 8.0, island.seabed_radius * 0.90)
		for _attempt in 140:
			var ang := rng.randf() * TAU
			var rad := lerpf(r_min, r_max, rng.randf())
			var pxz := Vector2(cos(ang) * rad, sin(ang) * rad)
			if not _is_clear_of_harbour(pxz, mooring_xz, has_pier, pier_a, pier_b):
				continue
			var bed_y := island.surface_height(pxz.x, pxz.y)
			if bed_y <= -2.4 and bed_y >= -6.5:
				chosen_xz = pxz
				chosen_seabed = bed_y
				found = true
				break

	if not found:
		return null

	var manta := MantaRay.new()
	manta.name = "MantaRay"
	manta.seed_val = s
	manta.orbit_radius = orb_r
	manta.orbit_speed = rng.randf_range(0.20, 0.29)
	manta.figure_eight_blend = rng.randf_range(0.32, 0.58)
	var center_y := clampf(chosen_seabed + 1.85, -4.4, -2.25)
	manta.position = Vector3(chosen_xz.x, center_y, chosen_xz.y)
	manta.min_depth_y = clampf(center_y - 0.65, -4.8, -2.5)
	manta.max_depth_y = clampf(center_y + 0.55, -3.5, -1.8)
	island.add_child(manta)
	return manta


static func _is_clear_of_harbour(pt: Vector2, mooring_xz: Vector2,
		has_pier: bool, pier_a: Vector2, pier_b: Vector2) -> bool:
	if pt.distance_to(mooring_xz) < MOORING_CLEAR_RADIUS:
		return false
	if has_pier:
		var ab := pier_b - pier_a
		var ab_len2 := ab.length_squared()
		var t := clampf((pt - pier_a).dot(ab) / ab_len2, 0.0, 1.0) if ab_len2 > 0.001 else 0.0
		if pt.distance_to(pier_a + ab * t) < PIER_CLEAR_RADIUS:
			return false
	return true


func _enter_tree() -> void:
	_active_mantas += 1
	add_to_group(GROUP)
	add_to_group(GROUP_BEASTS)


func _exit_tree() -> void:
	_release_local_refs()
	_active_mantas = maxi(0, _active_mantas - 1)
	if _active_mantas == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_local_refs()


func _release_local_refs() -> void:
	for mi: MeshInstance3D in [_body_mi, _left_wing_mi, _right_wing_mi]:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	if _bubbles_mmi != null and is_instance_valid(_bubbles_mmi):
		_bubbles_mmi.visible = false
		_bubbles_mmi.material_override = null
		_bubbles_mmi.multimesh = null
	_body_mi = null
	_left_wing_mi = null
	_right_wing_mi = null
	_left_wing_pivot = null
	_right_wing_pivot = null
	_glide_root = null
	_bubbles_mmi = null
	_bubbles_initialized = false
	_built = false


func _ready() -> void:
	_ensure_built()


func _physics_process(delta: float) -> void:
	if not _built:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		if global_position.distance_squared_to(cam.global_position) > CPU_CULL_DIST * CPU_CULL_DIST:
			return
	step_glide(delta)


## Advance the Manta Ray along its wide curving lagoon glide path and articulate
## its undulating pectoral wings, vertical heave surge, gentle turn banking, and
## trailing underwater wingtip micro-bubbles.
func step_glide(delta: float) -> void:
	if not _built or _glide_root == null:
		return
	var dt := maxf(delta, 0.0)
	_clock += dt

	var t := _clock * orbit_speed + _phase_offset
	var r := maxf(orbit_radius, 4.0)
	var fb := clampf(figure_eight_blend, 0.0, 1.0)

	# Smooth blend of elliptical lagoon glide and graceful figure-8 sweep.
	var ex := cos(t) * r
	var ez := sin(t) * r * 0.68
	var fx := sin(t) * r * 1.06
	var fz := sin(t) * cos(t) * r * 1.18
	var lx := lerpf(ex, fx, fb)
	var lz := lerpf(ez, fz, fb)

	# Wing-flap cycle (2.15 rad/s) + subtle upward heave surge on each downstroke.
	var flap_phase := _clock * 2.15 + _phase_offset
	var wing_angle := sin(flap_phase) * 0.38
	var heave := -cos(flap_phase) * 0.16
	var slow_depth := sin(t * 0.85) * 0.38

	var origin_y := global_position.y if is_inside_tree() else position.y
	var desired_world_y := clampf(origin_y + slow_depth + heave, min_depth_y, minf(max_depth_y, MAX_MANTA_Y))
	var ly := desired_world_y - origin_y
	var next_local := Vector3(lx, ly, lz)

	# Analytic tangent direction for smooth orientation even on dt == 0 prime frame.
	var t_ahead := t + 0.04
	var ax := lerpf(cos(t_ahead) * r, sin(t_ahead) * r * 1.06, fb)
	var az := lerpf(sin(t_ahead) * r * 0.68, sin(t_ahead) * cos(t_ahead) * r * 1.18, fb)
	var ay := clampf(origin_y + sin(t_ahead * 0.85) * 0.38 + heave, min_depth_y, minf(max_depth_y, MAX_MANTA_Y)) - origin_y
	var tang := Vector3(ax - lx, ay - ly, az - lz)
	if _has_prev and dt > 0.0001 and (next_local - _prev_local_pos).length_squared() > 1e-6:
		tang = next_local - _prev_local_pos

	var flat_t := Vector2(tang.x, tang.z)
	var yaw := atan2(-flat_t.x, -flat_t.y) if flat_t.length_squared() > 1e-6 else _prev_yaw
	var horiz := maxf(flat_t.length(), 0.001)
	var pitch := clampf(atan2(tang.y, horiz) + cos(flap_phase) * 0.045, -0.32, 0.32)

	var bank_roll := 0.0
	if _has_prev and dt > 0.0001:
		var yaw_rate := angle_difference(_prev_yaw, yaw) / dt
		bank_roll = clampf(-yaw_rate * 0.42, -0.32, 0.32)

	_prev_local_pos = next_local
	_prev_yaw = yaw
	_has_prev = true

	_glide_root.position = next_local
	_glide_root.rotation = Vector3(pitch, yaw, bank_roll)

	# Articulated pectoral wing undulation (downstroke + subtle hydrodynamic feather twist).
	var wing_twist := cos(flap_phase) * 0.09
	if _left_wing_pivot != null:
		_left_wing_pivot.rotation = Vector3(wing_twist, 0.0, -wing_angle)
	if _right_wing_pivot != null:
		_right_wing_pivot.rotation = Vector3(wing_twist, 0.0, wing_angle)

	_step_wingtip_bubbles(dt, origin_y)


func _step_wingtip_bubbles(dt: float, origin_y: float) -> void:
	if _bubbles_mmi == null or not is_instance_valid(_bubbles_mmi):
		return
	var mm := _bubbles_mmi.multimesh
	if mm == null or _bubble_origin.size() != BUBBLE_COUNT:
		return
	if _left_wing_pivot == null or _right_wing_pivot == null:
		return

	var glide_xf := _glide_root.transform
	var port_tip := glide_xf * (_left_wing_pivot.transform * Vector3(-WINGTIP_PIVOT_X, WINGTIP_PIVOT_Y, WINGTIP_PIVOT_Z))
	var stbd_tip := glide_xf * (_right_wing_pivot.transform * Vector3(WINGTIP_PIVOT_X, WINGTIP_PIVOT_Y, WINGTIP_PIVOT_Z))
	var max_local_y := minf(BUBBLE_CEILING_WORLD_Y, -0.15) - origin_y

	# On the initial prime frame (step_glide(0.0) in _ready), seed all 12 bubbles across
	# staggered trail phases right behind both moving wingtips so showcases frame full trails!
	if not _bubbles_initialized:
		var trail_dir := glide_xf.basis.z
		var td_len2 := trail_dir.length_squared()
		if td_len2 > 1e-6:
			trail_dir /= sqrt(td_len2)
		else:
			trail_dir = Vector3.BACK
		var approx_speed := clampf(maxf(orbit_radius, 4.0) * orbit_speed * 0.72, 1.4, 3.4)
		for i in BUBBLE_COUNT:
			var is_stbd := i >= BUBBLES_PER_WING
			var slot := i % BUBBLES_PER_WING
			var tip := stbd_tip if is_stbd else port_tip
			var frac := (float(slot) + 0.18) / float(BUBBLES_PER_WING)
			var life := _bubble_lifetime[i]
			var init_age := frac * life
			_bubble_age[i] = init_age
			_bubble_origin[i] = tip + trail_dir * (approx_speed * init_age)
		_bubbles_initialized = true
	elif dt > 0.0:
		for i in BUBBLE_COUNT:
			var life := _bubble_lifetime[i]
			var next_age := _bubble_age[i] + dt
			if next_age >= life:
				next_age = fposmod(next_age, life)
				_bubble_origin[i] = stbd_tip if (i >= BUBBLES_PER_WING) else port_tip
			_bubble_age[i] = next_age

	for i in BUBBLE_COUNT:
		var age := _bubble_age[i]
		var life := _bubble_lifetime[i]
		var u := clampf(age / life, 0.0, 1.0)
		var base_p := _bubble_origin[i]
		var ang := _bubble_phase[i] + _clock * _bubble_helix_freq[i] + u * TAU * 1.15
		var h_rad := _bubble_helix_r[i] * (0.25 + 0.75 * u)
		var bx := base_p.x + cos(ang) * h_rad
		var bz := base_p.z + sin(ang) * h_rad
		var by := minf(base_p.y + _bubble_rise_speed[i] * age, max_local_y)
		var pos := Vector3(bx, by, bz)
		_bubble_pos[i] = pos

		var fade_in := smoothstep(0.0, 0.14, u)
		var fade_out := 1.0 - smoothstep(0.74, 1.0, u)
		var env := clampf(fade_in * fade_out, 0.0, 1.0)
		var s := _bubble_scale[i] * lerpf(0.28, 1.0, env)
		var b_basis := Basis(Vector3.UP, ang * 0.5) * Basis.from_scale(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b_basis, pos))

		var glint := 0.90 + 0.10 * sin(_clock * 5.2 + _bubble_phase[i])
		mm.set_instance_color(i, Color(0.86 * glint, 0.98 * glint, 1.00 * glint, clampf(0.82 * env, 0.0, 1.0)))


func get_glide_world_position() -> Vector3:
	if _glide_root == null:
		return global_position if is_inside_tree() else position
	var xf := global_transform if is_inside_tree() else transform
	return xf * _glide_root.position


func get_wing_pivots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _left_wing_pivot != null:
		out.append(_left_wing_pivot)
	if _right_wing_pivot != null:
		out.append(_right_wing_pivot)
	return out


func get_mesh_instances() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in [_body_mi, _left_wing_mi, _right_wing_mi]:
		if mi != null:
			out.append(mi)
	return out


## Return the sculpted MultiMeshInstance3D rendering trailing underwater wingtip micro-bubbles.
func get_wingtip_bubbles_node() -> MultiMeshInstance3D:
	return _bubbles_mmi


## Return the current local-space positions of all 12 trailing wingtip micro-bubbles.
func get_wingtip_bubble_positions() -> PackedVector3Array:
	return _bubble_pos.duplicate()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_ensure_shared_assets()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x4A7A0013
	_phase_offset = rng.randf() * TAU

	_glide_root = Node3D.new()
	_glide_root.name = "GlideRoot"
	add_child(_glide_root)

	_body_mi = _make_part("BodyMesh", _body_mesh)
	_glide_root.add_child(_body_mi)

	_left_wing_pivot = Node3D.new()
	_left_wing_pivot.name = "LeftWingPivot"
	_left_wing_pivot.position = Vector3(-0.22, 0.0, -0.04)
	_glide_root.add_child(_left_wing_pivot)
	_left_wing_mi = _make_part("LeftWingMesh", _wing_left_mesh)
	_left_wing_pivot.add_child(_left_wing_mi)

	_right_wing_pivot = Node3D.new()
	_right_wing_pivot.name = "RightWingPivot"
	_right_wing_pivot.position = Vector3(0.22, 0.0, -0.04)
	_glide_root.add_child(_right_wing_pivot)
	_right_wing_mi = _make_part("RightWingMesh", _wing_right_mesh)
	_right_wing_pivot.add_child(_right_wing_mi)

	_build_wingtip_bubbles(rng)
	step_glide(0.0)


func _build_wingtip_bubbles(rng: RandomNumberGenerator) -> void:
	_bubble_origin.resize(BUBBLE_COUNT)
	_bubble_pos.resize(BUBBLE_COUNT)
	_bubble_age.resize(BUBBLE_COUNT)
	_bubble_lifetime.resize(BUBBLE_COUNT)
	_bubble_rise_speed.resize(BUBBLE_COUNT)
	_bubble_phase.resize(BUBBLE_COUNT)
	_bubble_helix_r.resize(BUBBLE_COUNT)
	_bubble_helix_freq.resize(BUBBLE_COUNT)
	_bubble_scale.resize(BUBBLE_COUNT)
	_bubbles_initialized = false

	for i in BUBBLE_COUNT:
		_bubble_origin[i] = Vector3.ZERO
		_bubble_pos[i] = Vector3.ZERO
		_bubble_age[i] = 0.0
		_bubble_lifetime[i] = rng.randf_range(1.6, 2.4)
		_bubble_rise_speed[i] = rng.randf_range(0.55, 0.85)
		_bubble_phase[i] = rng.randf() * TAU
		_bubble_helix_r[i] = rng.randf_range(0.045, 0.115)
		_bubble_helix_freq[i] = rng.randf_range(2.8, 4.6)
		_bubble_scale[i] = rng.randf_range(0.68, 1.32)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = false
	mm.mesh = _bubble_mesh
	mm.instance_count = BUBBLE_COUNT
	for i in BUBBLE_COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_color(i, Color(0.86, 0.98, 1.00, 0.0))

	_bubbles_mmi = MultiMeshInstance3D.new()
	_bubbles_mmi.name = "WingtipBubbles"
	_bubbles_mmi.multimesh = mm
	_bubbles_mmi.material_override = _bubble_mat
	_bubbles_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubbles_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_bubbles_mmi.visibility_range_end = VISIBILITY_END
	_bubbles_mmi.visibility_range_end_margin = VISIBILITY_MARGIN
	_bubbles_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var r_box := maxf(orbit_radius, 4.0) * 1.25 + 5.0
	_bubbles_mmi.custom_aabb = AABB(Vector3(-r_box, -6.0, -r_box), Vector3(r_box * 2.0, 12.0, r_box * 2.0))
	add_child(_bubbles_mmi)


static func _make_part(node_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _manta_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VISIBILITY_END
	mi.visibility_range_end_margin = VISIBILITY_MARGIN
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


# ==============================================================================
# Sculpted Flat-Faceted Giant Reef Manta Ray (`SurfaceTool`, Zero Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _manta_mat == null:
		_manta_mat = StandardMaterial3D.new()
		_manta_mat.albedo_color = Color.WHITE
		_manta_mat.vertex_color_use_as_albedo = true
		_manta_mat.vertex_color_is_srgb = true
		_manta_mat.roughness = 0.28
		_manta_mat.metallic = 0.08
		_manta_mat.clearcoat_enabled = true
		_manta_mat.clearcoat = 0.45
		_manta_mat.clearcoat_roughness = 0.22

	if _bubble_mat == null:
		_bubble_mat = StandardMaterial3D.new()
		_bubble_mat.albedo_color = Color(0.92, 1.00, 1.00, 0.78)
		_bubble_mat.vertex_color_use_as_albedo = true
		_bubble_mat.vertex_color_is_srgb = true
		_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bubble_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_bubble_mat.cull_mode = BaseMaterial3D.CULL_BACK

	if _body_mesh == null:
		_body_mesh = _build_body_mesh()
	if _wing_left_mesh == null:
		_wing_left_mesh = _build_pectoral_wing_mesh(-1.0)
	if _wing_right_mesh == null:
		_wing_right_mesh = _build_pectoral_wing_mesh(1.0)
	if _bubble_mesh == null:
		_bubble_mesh = _build_bubble_mesh()


static func _build_bubble_mesh() -> ArrayMesh:
	# Sculpted exact 12-triangle 6-sided bipyramid underwater micro-bubble (zero SphereMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 6
	const R_EQ := 0.052
	const R_POLE := 0.044
	var top := Vector3(0.0, R_POLE, 0.0)
	var bot := Vector3(0.0, -R_POLE, 0.0)
	var ring: Array[Vector3] = []
	for s in SIDES:
		var ang := float(s) / float(SIDES) * TAU
		ring.append(Vector3(cos(ang) * R_EQ, 0.0, sin(ang) * R_EQ))
	for s in SIDES:
		var ns := (s + 1) % SIDES
		_emit_outward_tri(st, ring[s], COL_BUBBLE_MID, top, COL_BUBBLE_TOP, ring[ns], COL_BUBBLE_MID, Vector3.ZERO)
		_emit_outward_tri(st, ring[ns], COL_BUBBLE_MID, bot, COL_BUBBLE_BOT, ring[s], COL_BUBBLE_MID, Vector3.ZERO)
	st.generate_normals()
	return st.commit()


static func _build_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Central diamond hydrofoil torso (-Z nose, +Z tail, arched indigo-slate back & cream belly).
	# Station: [z, rx, ry_top, ry_bot, top_col, side_col, bot_col]
	var torso_stations: Array[Array] = [
		[-0.84, 0.22, 0.045, 0.032, COL_BACK_DEEP, COL_BACK_SLATE, COL_BELLY_CREAM],
		[-0.62, 0.31, 0.115, 0.068, COL_CHEVRON, COL_BACK_SLATE, COL_BELLY_CREAM],
		[-0.26, 0.34, 0.145, 0.088, COL_BACK_SLATE, COL_SPOT_TURQ, COL_BELLY_GILL],
		[0.14, 0.31, 0.125, 0.074, COL_BACK_DEEP, COL_BACK_SLATE, COL_BELLY_GILL],
		[0.48, 0.21, 0.088, 0.052, COL_BACK_DEEP, COL_BACK_SLATE, COL_BELLY_CREAM],
		[0.74, 0.11, 0.054, 0.034, COL_TAIL_DARK, COL_BACK_DEEP, COL_BELLY_CREAM],
		[0.92, 0.048, 0.034, 0.024, COL_TAIL_DARK, COL_TAIL_DARK, COL_BELLY_GILL],
	]
	_append_lofted_tube(st, torso_stations, 8, true, false)

	# 2. Long graceful tapered whip tail extending from z = +0.90 to z = +2.35!
	var tail_stations: Array[Array] = [
		[0.90, 0.048, 0.034, 0.024, COL_TAIL_DARK, COL_TAIL_DARK, COL_BELLY_GILL],
		[1.18, 0.034, 0.026, 0.020, COL_TAIL_DARK, COL_TAIL_DARK, COL_BACK_DEEP],
		[1.52, 0.022, 0.018, 0.014, COL_TAIL_DARK, COL_TAIL_DARK, COL_TAIL_DARK],
		[1.88, 0.013, 0.011, 0.009, COL_TAIL_DARK, COL_TAIL_DARK, COL_TAIL_DARK],
		[2.20, 0.006, 0.006, 0.005, COL_TAIL_DARK, COL_TAIL_DARK, COL_TAIL_DARK],
		[2.38, 0.002, 0.002, 0.002, COL_TAIL_DARK, COL_TAIL_DARK, COL_TAIL_DARK],
	]
	_append_lofted_tube(st, tail_stations, 6, false, true, 0.045)

	# 3. Twin curved forward-sweeping cephalic head lobes ("manta horns") flanking mouth.
	for sgn: float in [-1.0, 1.0]:
		var lobe_pts: Array[Array] = [
			[Vector3(sgn * 0.22, 0.005, -0.78), 0.052, 0.046],
			[Vector3(sgn * 0.27, 0.002, -0.96), 0.046, 0.040],
			[Vector3(sgn * 0.25, -0.004, -1.14), 0.034, 0.028],
			[Vector3(sgn * 0.18, -0.008, -1.28), 0.016, 0.014],
		]
		_append_swept_lobe(st, lobe_pts, 6, COL_BACK_DEEP, COL_CHEVRON, COL_BELLY_CREAM)

	# 4. Small swept pelvic fins flanking tail base + small dorsal finlet.
	for sgn: float in [-1.0, 1.0]:
		var p_root_f := Vector3(sgn * 0.14, 0.000, 0.56)
		var p_root_b := Vector3(sgn * 0.06, -0.004, 0.86)
		var p_tip := Vector3(sgn * 0.34, -0.010, 0.96)
		var p_mid := Vector3(sgn * 0.22, 0.014, 0.74)
		_emit_outward_tri(st, p_root_f, COL_BACK_SLATE, p_mid, COL_SPOT_TURQ, p_root_b, COL_BACK_DEEP, Vector3(sgn * 0.16, -0.04, 0.74))
		_emit_outward_tri(st, p_mid, COL_SPOT_TURQ, p_tip, COL_BACK_DEEP, p_root_b, COL_BACK_DEEP, Vector3(sgn * 0.16, -0.04, 0.74))
		_emit_outward_tri(st, p_root_f, COL_BELLY_CREAM, p_root_b, COL_BELLY_CREAM, p_tip, COL_BELLY_GILL, Vector3(sgn * 0.16, 0.04, 0.74))

	# Small dorsal finlet at tail root.
	var df_f := Vector3(0.0, 0.056, 0.62)
	var df_b := Vector3(0.0, 0.036, 0.86)
	var df_top := Vector3(0.0, 0.155, 0.82)
	var df_l := Vector3(-0.016, 0.048, 0.74)
	var df_r := Vector3(0.016, 0.048, 0.74)
	var df_c := Vector3(0.0, 0.05, 0.74)
	_emit_outward_tri(st, df_f, COL_BACK_SLATE, df_top, COL_CHEVRON, df_l, COL_BACK_DEEP, df_c)
	_emit_outward_tri(st, df_b, COL_TAIL_DARK, df_l, COL_BACK_DEEP, df_top, COL_CHEVRON, df_c)
	_emit_outward_tri(st, df_f, COL_BACK_SLATE, df_r, COL_BACK_DEEP, df_top, COL_CHEVRON, df_c)
	_emit_outward_tri(st, df_b, COL_TAIL_DARK, df_top, COL_CHEVRON, df_r, COL_BACK_DEEP, df_c)

	# 5. Subtle outer corner eyes at base of cephalic lobes.
	for sgn: float in [-1.0, 1.0]:
		var ec := Vector3(sgn * 0.275, 0.020, -0.78)
		var apex := ec + Vector3(sgn * 0.018, 0.008, -0.006)
		var er := 0.022
		var e_ring: Array[Vector3] = [
			ec + Vector3(0.0, er, 0.0),
			ec + Vector3(0.0, 0.0, -er),
			ec + Vector3(0.0, -er, 0.0),
			ec + Vector3(0.0, 0.0, er),
		]
		for k in 4:
			var nk := (k + 1) % 4
			_emit_outward_tri(st, apex, COL_EYE, e_ring[k], COL_EYE, e_ring[nk], COL_EYE, Vector3(0.0, 0.02, -0.78))

	st.generate_normals()
	return st.commit()


static func _build_pectoral_wing_mesh(side_sgn: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Swept diamond hydrofoil pectoral wing in wing-pivot local space (span 0.0 -> 1.56 m).
	# Section: [span_x, z_lead, z_trail, thick_top, thick_bot, y_dihedral, dorsal_col, chevron_col]
	var sections: Array[Array] = [
		[0.00, -0.70, 0.56, 0.115, 0.072, 0.000, COL_BACK_SLATE, COL_CHEVRON],
		[0.28, -0.62, 0.48, 0.095, 0.060, 0.018, COL_CHEVRON, COL_SPOT_TURQ],
		[0.58, -0.48, 0.40, 0.072, 0.044, 0.032, COL_SPOT_TURQ, COL_BACK_SLATE],
		[0.92, -0.28, 0.34, 0.048, 0.030, 0.048, COL_BACK_SLATE, COL_BACK_DEEP],
		[1.24, -0.08, 0.30, 0.028, 0.018, 0.066, COL_BACK_DEEP, COL_BACK_DEEP],
		[1.46, 0.10, 0.28, 0.014, 0.010, 0.088, COL_BACK_DEEP, COL_TAIL_DARK],
		[1.60, 0.22, 0.30, 0.004, 0.004, 0.105, COL_TAIL_DARK, COL_TAIL_DARK],
	]

	# 8-point hydrofoil cross-section per spanwise station.
	var foil_rings: Array[Array] = []
	var foil_cols: Array[Array] = []
	for s_row: Array in sections:
		var sx: float = side_sgn * float(s_row[0])
		var zl: float = float(s_row[1])
		var zt: float = float(s_row[2])
		var tt: float = float(s_row[3])
		var tb: float = float(s_row[4])
		var dy: float = float(s_row[5])
		var d_col: Color = s_row[6] as Color
		var c_col: Color = s_row[7] as Color
		var chord := zt - zl

		var pts: Array[Vector3] = [
			Vector3(sx, dy, zl),                                    # 0: leading edge
			Vector3(sx, dy + tt * 0.78, zl + chord * 0.24),         # 1: upper front
			Vector3(sx, dy + tt * 1.00, zl + chord * 0.50),         # 2: upper crown
			Vector3(sx, dy + tt * 0.56, zl + chord * 0.78),         # 3: upper aft
			Vector3(sx, dy, zt),                                    # 4: trailing edge
			Vector3(sx, dy - tb * 0.52, zl + chord * 0.74),         # 5: lower aft
			Vector3(sx, dy - tb * 1.00, zl + chord * 0.44),         # 6: lower belly
			Vector3(sx, dy - tb * 0.74, zl + chord * 0.20),         # 7: lower front
		]
		var cols: Array[Color] = [
			COL_BACK_DEEP,
			c_col,
			d_col,
			COL_BACK_SLATE,
			COL_BACK_DEEP,
			COL_BELLY_GILL,
			COL_BELLY_CREAM,
			COL_BELLY_CREAM,
		]
		foil_rings.append(pts)
		foil_cols.append(cols)

	for si in range(sections.size() - 1):
		var r0: Array = foil_rings[si]
		var r1: Array = foil_rings[si + 1]
		var c0: Array = foil_cols[si]
		var c1: Array = foil_cols[si + 1]
		var mid_x := side_sgn * (float(sections[si][0]) + float(sections[si + 1][0])) * 0.5
		var mid_z := (float(sections[si][1]) + float(sections[si][2]) + float(sections[si + 1][1]) + float(sections[si + 1][2])) * 0.25
		var mid_y := (float(sections[si][5]) + float(sections[si + 1][5])) * 0.5
		var mid_c := Vector3(mid_x, mid_y, mid_z)
		for k in 8:
			var nk := (k + 1) % 8
			_emit_outward_quad(st,
				r0[k] as Vector3, c0[k] as Color,
				r1[k] as Vector3, c1[k] as Color,
				r1[nk] as Vector3, c1[nk] as Color,
				r0[nk] as Vector3, c0[nk] as Color,
				mid_c)

	# Cap wingtip and root cleanly so no holes ever show when wings flex.
	var last_i := foil_rings.size() - 1
	var tip_c := Vector3(side_sgn * 1.63, 0.108, 0.26)
	var tip_ref := Vector3(side_sgn * 1.35, 0.08, 0.22)
	var root_c := Vector3(0.0, 0.0, -0.07)
	var root_ref := Vector3(side_sgn * 0.30, 0.0, -0.07)
	for k in 8:
		var nk := (k + 1) % 8
		_emit_outward_tri(st, tip_c, COL_TAIL_DARK,
			foil_rings[last_i][k] as Vector3, foil_cols[last_i][k] as Color,
			foil_rings[last_i][nk] as Vector3, foil_cols[last_i][nk] as Color,
			tip_ref)
		_emit_outward_tri(st, root_c, COL_BACK_DEEP,
			foil_rings[0][nk] as Vector3, foil_cols[0][nk] as Color,
			foil_rings[0][k] as Vector3, foil_cols[0][k] as Color,
			root_ref)

	st.generate_normals()
	return st.commit()


static func _append_lofted_tube(st: SurfaceTool, stations: Array[Array], segs: int,
		cap_front: bool, cap_back: bool, arch_y: float = 0.0) -> void:
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	for si in stations.size():
		var row: Array = stations[si]
		var z: float = float(row[0])
		var rx: float = float(row[1])
		var ry_t: float = float(row[2])
		var ry_b: float = float(row[3])
		var c_top: Color = row[4] as Color
		var c_side: Color = row[5] as Color
		var c_bot: Color = row[6] as Color
		var u := float(si) / float(maxi(1, stations.size() - 1))
		var cy := sin(u * PI) * arch_y
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			var ca := cos(a)
			var sa := sin(a)
			var py := cy + sa * (ry_t if sa >= 0.0 else ry_b)
			pts.append(Vector3(ca * rx, py, z))
			var col := c_side.lerp(c_top, sa) if sa >= 0.0 else c_side.lerp(c_bot, -sa)
			cols.append(col)
		rings.append(pts)
		ring_cols.append(cols)

	for si in range(stations.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var c0: Array = ring_cols[si]
		var c1: Array = ring_cols[si + 1]
		var mid_z := (float(stations[si][0]) + float(stations[si + 1][0])) * 0.5
		var mid_c := Vector3(0.0, arch_y * 0.4, mid_z)
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_quad(st,
				r0[k] as Vector3, c0[k] as Color,
				r1[k] as Vector3, c1[k] as Color,
				r1[nk] as Vector3, c1[nk] as Color,
				r0[nk] as Vector3, c0[nk] as Color,
				mid_c)

	if cap_front:
		var fc := Vector3(0.0, 0.0, float(stations[0][0]) - 0.03)
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_tri(st, fc, COL_BACK_DEEP,
				rings[0][k] as Vector3, ring_cols[0][k] as Color,
				rings[0][nk] as Vector3, ring_cols[0][nk] as Color,
				Vector3(0.0, 0.0, float(stations[0][0]) + 0.15))
	if cap_back:
		var li := rings.size() - 1
		var bc := Vector3(0.0, 0.0, float(stations[li][0]) + 0.03)
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_tri(st, bc, COL_TAIL_DARK,
				rings[li][nk] as Vector3, ring_cols[li][nk] as Color,
				rings[li][k] as Vector3, ring_cols[li][k] as Color,
				Vector3(0.0, 0.0, float(stations[li][0]) - 0.15))


static func _append_swept_lobe(st: SurfaceTool, pts_spec: Array[Array], segs: int,
		col_outer: Color, col_inner: Color, col_bot: Color) -> void:
	var rings: Array[Array] = []
	var cols: Array[Array] = []
	for si in pts_spec.size():
		var c: Vector3 = pts_spec[si][0] as Vector3
		var rx: float = float(pts_spec[si][1])
		var ry: float = float(pts_spec[si][2])
		var r_pts: Array[Vector3] = []
		var r_cls: Array[Color] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			r_pts.append(c + Vector3(cos(a) * rx, sin(a) * ry, 0.0))
			var col := col_outer if sin(a) > 0.2 else (col_bot if sin(a) < -0.2 else col_inner)
			r_cls.append(col)
		rings.append(r_pts)
		cols.append(r_cls)

	for si in range(pts_spec.size() - 1):
		var c0: Vector3 = pts_spec[si][0] as Vector3
		var c1: Vector3 = pts_spec[si + 1][0] as Vector3
		var mid := (c0 + c1) * 0.5
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_quad(st,
				rings[si][k] as Vector3, cols[si][k] as Color,
				rings[si + 1][k] as Vector3, cols[si + 1][k] as Color,
				rings[si + 1][nk] as Vector3, cols[si + 1][nk] as Color,
				rings[si][nk] as Vector3, cols[si][nk] as Color,
				mid)

	var li := pts_spec.size() - 1
	var tip: Vector3 = (pts_spec[li][0] as Vector3) + Vector3(0.0, 0.0, -0.04)
	var ref_c: Vector3 = pts_spec[li - 1][0] as Vector3
	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, tip, col_outer,
			rings[li][k] as Vector3, cols[li][k] as Color,
			rings[li][nk] as Vector3, cols[li][nk] as Color,
			ref_c)


static func _emit_flat_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-12:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		_emit_flat_tri(st, a, ca, c, cc, b, cb)
	else:
		_emit_flat_tri(st, a, ca, b, cb, c, cc)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, d: Vector3, cd: Color,
		ref_center: Vector3) -> void:
	_emit_outward_tri(st, a, ca, b, cb, c, cc, ref_center)
	_emit_outward_tri(st, a, ca, c, cc, d, cd, ref_center)
