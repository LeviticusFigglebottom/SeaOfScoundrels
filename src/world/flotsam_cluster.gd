class_name FlotsamCluster
extends Node3D
## Sculpted open-sea shipwreck flotsam debris cluster: weathered splintered oak
## deck planks, a snapped tarred mast spar, tangled hemp netting loops, twin
## painted red-and-cream cork fishing floats, and an interactive salvageable
## cargo barrel bobbing naturally in real `Sea.height()` waves.

signal flotsam_salvaged(cluster: FlotsamCluster, pawn: Node, loot: Dictionary)

const GROUP := &"flotsam"
const BARREL_PROP_PATH := "res://assets/generated/props/barrel_prop.glb"
const FOAM_RIPPLE_INTERVAL := 1.25
const GLINT_MIN_DIST := 5.5
const GLINT_MAX_DIST := 155.0
const GLINT_HEIGHT_OFFSET := 1.06

# Painterly sea-soaked shipwreck timber, tarred spar, hemp rope & painted float palette (sRGB).
const COL_OAK_BLEACHED := Color(0.56, 0.43, 0.28)
const COL_OAK_MID := Color(0.42, 0.30, 0.18)
const COL_OAK_WET := Color(0.24, 0.17, 0.10)
const COL_SPLINTER := Color(0.68, 0.54, 0.35)
const COL_SPAR_TAR := Color(0.22, 0.16, 0.11)
const COL_SPAR_HI := Color(0.35, 0.26, 0.18)
const COL_HEMP_HI := Color(0.70, 0.60, 0.41)
const COL_HEMP_DARK := Color(0.46, 0.38, 0.24)
const COL_IRON_BAND := Color(0.22, 0.23, 0.26)
const COL_FLOAT_CRIMSON := Color(0.84, 0.18, 0.15)
const COL_FLOAT_CREAM := Color(0.95, 0.90, 0.77)
const COL_FLOAT_CORK := Color(0.62, 0.46, 0.28)
const COL_GLINT_CORE := Color(1.00, 0.96, 0.80, 1.0)
const COL_GLINT_MID := Color(0.98, 0.72, 0.22, 1.0)
const COL_GLINT_WAIST := Color(0.72, 0.44, 0.10, 1.0)

static var _active_clusters: int = 0
static var _debris_mesh: ArrayMesh = null
static var _fallback_barrel_mesh: ArrayMesh = null
static var _glint_mesh: ArrayMesh = null
static var _wood_mat: StandardMaterial3D = null
static var _accent_mat: StandardMaterial3D = null
static var _glint_mat: StandardMaterial3D = null

@export var seed_val: int = 1

var salvaged: bool = false
var interactable: Interactable = null
var base_x: float = 0.0
var base_z: float = 0.0

var _debris_mi: MeshInstance3D = null
var _barrel_root: Node3D = null
var _glint_mi: MeshInstance3D = null
var _bob_clock: float = 0.0
var _base_yaw: float = 0.0
var _foam_accum: float = 0.0
var _glint_clock: float = 0.0
var _glint_phase: float = 0.0


## Spawn a buoyant shipwreck flotsam debris cluster at `world_pos`.
static func spawn_at(parent: Node, world_pos: Vector3, p_seed: int = 1) -> FlotsamCluster:
	var cluster := FlotsamCluster.new()
	cluster.name = "FlotsamCluster_%d" % absi(p_seed)
	cluster.seed_val = p_seed
	cluster.base_x = world_pos.x
	cluster.base_z = world_pos.z
	var sy := Sea.height(world_pos.x, world_pos.z) if Sea != null else world_pos.y
	cluster.position = Vector3(world_pos.x, sy, world_pos.z)
	if parent != null:
		parent.add_child(cluster)
		cluster.global_position = Vector3(world_pos.x, sy, world_pos.z)
	return cluster


## Release all statically cached flotsam debris meshes & materials cleanly.
static func clear_shared_cache() -> void:
	_debris_mesh = null
	_fallback_barrel_mesh = null
	_glint_mesh = null
	_wood_mat = null
	_accent_mat = null
	_glint_mat = null


func _enter_tree() -> void:
	_active_clusters += 1
	add_to_group(GROUP)


func _exit_tree() -> void:
	_release_refs()
	_active_clusters = maxi(0, _active_clusters - 1)
	if _active_clusters == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_refs()


func _release_refs() -> void:
	if _debris_mi != null and is_instance_valid(_debris_mi):
		if _debris_mi.mesh != null:
			for si in _debris_mi.mesh.get_surface_count():
				_debris_mi.set_surface_override_material(si, null)
		_debris_mi.mesh = null
		_debris_mi.material_override = null
	if _glint_mi != null and is_instance_valid(_glint_mi):
		_glint_mi.mesh = null
		_glint_mi.material_override = null
	_debris_mi = null
	_barrel_root = null
	_glint_mi = null


func _ready() -> void:
	if base_x == 0.0 and base_z == 0.0:
		base_x = global_position.x
		base_z = global_position.z
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xF1075A
	_base_yaw = rng.randf_range(0.0, TAU)
	_bob_clock = rng.randf_range(0.0, TAU)
	_foam_accum = rng.randf_range(0.0, FOAM_RIPPLE_INTERVAL)
	_glint_phase = rng.randf_range(0.0, TAU)
	rotation.y = _base_yaw

	_ensure_shared_assets()
	_build_visuals()
	_build_salvage_glint()
	_build_interactable()
	step_buoyancy(0.0)
	if salvaged:
		if _glint_mi != null and is_instance_valid(_glint_mi):
			_glint_mi.visible = false
		set_process(false)
	else:
		tick_glint(0.0)


func _process(delta: float) -> void:
	tick_glint(delta)


func _physics_process(delta: float) -> void:
	step_buoyancy(delta)


# ==============================================================================
# Public API & Wave Buoyancy
# ==============================================================================

## Return the sculpted additive SalvageGlint MeshInstance3D floating above the cargo barrel.
func get_salvage_glint_node() -> MeshInstance3D:
	return _glint_mi


## Update distance-gated open-sea salvage glint twinkle (5.5..155.0 m).
func tick_glint(delta: float, cam_dist_override: float = -1.0) -> void:
	if _glint_mi == null or not is_instance_valid(_glint_mi):
		return
	if salvaged:
		_glint_mi.visible = false
		return

	var dist := cam_dist_override
	if dist < 0.0:
		var vp := get_viewport() if is_inside_tree() else null
		var cam := vp.get_camera_3d() if vp != null else null
		if cam != null:
			dist = global_position.distance_to(cam.global_position)
		else:
			dist = 40.0

	if dist < GLINT_MIN_DIST or dist > GLINT_MAX_DIST:
		_glint_mi.visible = false
		return

	_glint_mi.visible = true
	_glint_clock += maxf(delta, 0.0)

	var tw := 0.5 + 0.5 * sin(_glint_clock * 2.9 + _glint_phase)
	var shimmer := 0.5 + 0.5 * sin(_glint_clock * 6.4 + _glint_phase * 1.7)
	var pulse := 0.52 + 0.58 * pow(tw, 2.5) + 0.14 * shimmer
	var near_fade := clampf((dist - GLINT_MIN_DIST) / 4.5, 0.28, 1.0)
	var far_fade := clampf((GLINT_MAX_DIST - dist) / 22.0, 0.28, 1.0)
	var range_boost := lerpf(0.85, 1.80, clampf((dist - GLINT_MIN_DIST) / (GLINT_MAX_DIST - GLINT_MIN_DIST), 0.0, 1.0))
	var glint_scale := pulse * near_fade * far_fade * range_boost
	_glint_mi.scale = Vector3.ONE * glint_scale


## Host-authoritative idempotent salvage action; returns loot dict once, else empty dict.
func salvage(pawn: Node = null) -> Dictionary:
	if not Net.is_host() or salvaged:
		return {}
	salvaged = true
	if interactable != null:
		interactable.enabled = false
	if _barrel_root != null and is_instance_valid(_barrel_root):
		_barrel_root.visible = false
	if _glint_mi != null and is_instance_valid(_glint_mi):
		_glint_mi.visible = false
	set_process(false)
	var loot := {
		"cannonballs": 6,
		"planks": 4,
		"gold": 35,
	}
	Audio.play_sfx(&"coin_jingle", global_position)
	flotsam_salvaged.emit(self, pawn, loot)
	return loot


## Update buoyant wave height, pitch/roll slope matching, gentle barrel rock, and bobbing ocean foam ripple.
func step_buoyancy(delta: float) -> void:
	_bob_clock += delta
	var sea_y := Sea.height(base_x, base_z) if Sea != null else 0.0
	var sx0 := Sea.height(base_x - 1.4, base_z) if Sea != null else sea_y
	var sx1 := Sea.height(base_x + 1.4, base_z) if Sea != null else sea_y
	var sz0 := Sea.height(base_x, base_z - 1.4) if Sea != null else sea_y
	var sz1 := Sea.height(base_x, base_z + 1.4) if Sea != null else sea_y

	var slope_x := clampf((sx1 - sx0) / 2.8, -0.22, 0.22)
	var slope_z := clampf((sz1 - sz0) / 2.8, -0.22, 0.22)
	var pitch := clampf(-slope_z + sin(_bob_clock * 1.45) * 0.04, -0.26, 0.26)
	var roll := clampf(slope_x + cos(_bob_clock * 1.18) * 0.04, -0.26, 0.26)
	var yaw := _base_yaw + sin(_bob_clock * 0.22) * 0.12

	# Ride proudly on top of wave chop (+0.105 m) so horizontal planks stay cleanly above
	# ocean.gdshader's shallow beach-wash foam threshold while the oak barrel floats half-submerged.
	var target_pos := Vector3(base_x, sea_y + 0.105 + sin(_bob_clock * 1.9) * 0.024, base_z)
	if is_inside_tree():
		global_position = target_pos
	else:
		position = target_pos
	rotation = Vector3(pitch, yaw, roll)

	if _barrel_root != null and is_instance_valid(_barrel_root) and _barrel_root.visible:
		_barrel_root.position.y = -0.26 + sin(_bob_clock * 2.3 + 0.8) * 0.04
		_barrel_root.rotation = Vector3(
			0.18 + sin(_bob_clock * 1.8) * 0.09,
			0.38,
			-0.14 + cos(_bob_clock * 1.5) * 0.09
		)
		if _glint_mi != null and is_instance_valid(_glint_mi):
			_glint_mi.position.y = _barrel_root.position.y + GLINT_HEIGHT_OFFSET

	if delta > 0.0:
		_foam_accum += delta
		if _foam_accum >= FOAM_RIPPLE_INTERVAL:
			_foam_accum = fmod(_foam_accum, FOAM_RIPPLE_INTERVAL)
			if Ocean.current != null and is_inside_tree():
				Ocean.current.add_foam(global_position, 1.45, 0.34)


func _on_interacted(pawn: Node) -> void:
	salvage(pawn)


# ==============================================================================
# Scene Hierarchy & Sculpted Debris Ring (Zero Raw Primitives)
# ==============================================================================

func _build_visuals() -> void:
	_debris_mi = MeshInstance3D.new()
	_debris_mi.name = "ShipwreckDebrisMesh"
	_debris_mi.mesh = _debris_mesh
	_debris_mi.set_surface_override_material(0, _wood_mat)
	if _debris_mesh.get_surface_count() > 1:
		_debris_mi.set_surface_override_material(1, _accent_mat)
	add_child(_debris_mi)

	# Interactive salvageable cargo barrel floating at the cluster heart.
	_barrel_root = Node3D.new()
	_barrel_root.name = "CargoBarrel"
	_barrel_root.position = Vector3(0.0, -0.26, 0.0)
	add_child(_barrel_root)

	if ResourceLoader.exists(BARREL_PROP_PATH):
		var barrel_scene := load(BARREL_PROP_PATH) as PackedScene
		if barrel_scene != null:
			var inst := barrel_scene.instantiate() as Node3D
			if inst != null:
				inst.name = "BarrelModel"
				for col_node in inst.find_children("col_*", "MeshInstance3D", true, false):
					if col_node.get_parent() != null:
						col_node.get_parent().remove_child(col_node)
					col_node.free()
				_barrel_root.add_child(inst)
				return

	var fb := MeshInstance3D.new()
	fb.name = "SculptedOakBarrel"
	fb.mesh = _fallback_barrel_mesh
	fb.set_surface_override_material(0, _wood_mat)
	if _fallback_barrel_mesh.get_surface_count() > 1:
		fb.set_surface_override_material(1, _accent_mat)
	_barrel_root.add_child(fb)


func _build_salvage_glint() -> void:
	_glint_mi = MeshInstance3D.new()
	_glint_mi.name = "SalvageGlint"
	_glint_mi.mesh = _glint_mesh
	_glint_mi.material_override = _glint_mat
	_glint_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_glint_mi.position = Vector3(0.0, -0.26 + GLINT_HEIGHT_OFFSET, 0.0)
	add_child(_glint_mi)


func _build_interactable() -> void:
	interactable = Interactable.create("Salvage flotsam supplies", 1.25)
	interactable.name = "FlotsamInteractable"
	interactable.position = Vector3(0.0, 0.52, 0.0)
	interactable.reach = 3.2
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)


static func _ensure_shared_assets() -> void:
	if _wood_mat == null:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.vertex_color_use_as_albedo = true
		_wood_mat.vertex_color_is_srgb = true
		_wood_mat.roughness = 0.78
		_wood_mat.metallic = 0.04
	if _accent_mat == null:
		_accent_mat = StandardMaterial3D.new()
		_accent_mat.vertex_color_use_as_albedo = true
		_accent_mat.vertex_color_is_srgb = true
		_accent_mat.roughness = 0.42
		_accent_mat.metallic = 0.24
	if _glint_mat == null:
		_glint_mat = StandardMaterial3D.new()
		_glint_mat.vertex_color_use_as_albedo = true
		_glint_mat.vertex_color_is_srgb = true
		_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_glint_mat.billboard_keep_scale = true
		_glint_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_glint_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _debris_mesh == null:
		_debris_mesh = _build_debris_ring_mesh()
	if _fallback_barrel_mesh == null:
		_fallback_barrel_mesh = _build_fallback_barrel_mesh()
	if _glint_mesh == null:
		_glint_mesh = _build_salvage_glint_mesh()


static func _build_salvage_glint_mesh() -> ArrayMesh:
	# Sculpted exact 24-triangle 4-point star flare ArrayMesh (zero QuadMesh / zero VRAM textures).
	# Warm golden-amber core -> amber inner star waist -> Color(0, 0, 0, 1) additive-feathered tips.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SPOKES := 8
	const NORM := Vector3(0.0, 0.0, 1.0)
	const COL_TIP := Color(0.0, 0.0, 0.0, 1.0)
	var center := Vector3.ZERO
	var inner_pts: Array[Vector3] = []
	var outer_pts: Array[Vector3] = []
	var inner_cols: Array[Color] = []

	for i in SPOKES:
		var ang := float(i) / float(SPOKES) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		var is_major := (i % 2 == 0)
		var r_in := 0.165 if is_major else 0.072
		var r_out := (0.64 if (i == 2 or i == 6) else 0.54) if is_major else 0.18
		inner_pts.append(Vector3(ca * r_in, sa * r_in, 0.0))
		outer_pts.append(Vector3(ca * r_out, sa * r_out, 0.0))
		inner_cols.append(COL_GLINT_MID if is_major else COL_GLINT_WAIST)

	for i in SPOKES:
		var ni := (i + 1) % SPOKES
		var in_a := inner_pts[i]
		var in_b := inner_pts[ni]
		var out_a := outer_pts[i]
		var out_b := outer_pts[ni]
		var col_a := inner_cols[i]
		var col_b := inner_cols[ni]

		# Inner bright star heart (8 tris).
		st.set_normal(NORM); st.set_color(COL_GLINT_CORE); st.add_vertex(center)
		st.set_normal(NORM); st.set_color(col_b); st.add_vertex(in_b)
		st.set_normal(NORM); st.set_color(col_a); st.add_vertex(in_a)

		# Outer symmetric ray flare feathering cleanly to black tips (16 tris).
		if i % 2 == 0:
			st.set_normal(NORM); st.set_color(col_a); st.add_vertex(in_a)
			st.set_normal(NORM); st.set_color(COL_TIP); st.add_vertex(out_b)
			st.set_normal(NORM); st.set_color(COL_TIP); st.add_vertex(out_a)

			st.set_normal(NORM); st.set_color(col_a); st.add_vertex(in_a)
			st.set_normal(NORM); st.set_color(col_b); st.add_vertex(in_b)
			st.set_normal(NORM); st.set_color(COL_TIP); st.add_vertex(out_b)
		else:
			st.set_normal(NORM); st.set_color(col_b); st.add_vertex(in_b)
			st.set_normal(NORM); st.set_color(COL_TIP); st.add_vertex(out_b)
			st.set_normal(NORM); st.set_color(COL_TIP); st.add_vertex(out_a)

			st.set_normal(NORM); st.set_color(col_a); st.add_vertex(in_a)
			st.set_normal(NORM); st.set_color(col_b); st.add_vertex(in_b)
			st.set_normal(NORM); st.set_color(COL_TIP); st.add_vertex(out_a)

	return st.commit()


static func _build_debris_ring_mesh() -> ArrayMesh:
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accent_st := SurfaceTool.new()
	accent_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Six weathered splintered oak deck planks drifting in an organic asymmetric shipwreck cluster
	# (paired torn deck boards lashed parallel, skewed overlapping cross-strake, tangential hull board,
	# and varied broken lengths 1.18..2.32 m — zero symmetrical radial wheel-spoke ring!).
	# Row: [pos, yaw_rad, length, width, thick, tilt_x, tilt_z]
	var planks: Array[Array] = [
		[Vector3(-0.88, 0.025, 0.88), 0.28, 2.32, 0.30, 0.084, 0.04, -0.05],
		[Vector3(-0.56, 0.020, 1.24), 0.32, 1.86, 0.28, 0.080, 0.05, -0.04],
		[Vector3(-1.18, 0.048, 0.48), 1.14, 1.28, 0.25, 0.072, -0.06, 0.07],
		[Vector3(1.12, 0.022, -0.74), -0.18, 2.18, 0.29, 0.084, -0.04, 0.05],
		[Vector3(0.96, 0.018, 0.42), 0.78, 1.18, 0.23, 0.074, 0.06, 0.04],
		[Vector3(0.58, 0.044, 1.06), -0.92, 1.64, 0.26, 0.076, -0.05, -0.06],
	]
	for pi in planks.size():
		var p: Array = planks[pi]
		var pos: Vector3 = p[0] as Vector3
		var rot := Basis.from_euler(Vector3(float(p[5]), float(p[1]), float(p[6])))
		_append_splintered_plank(wood_st, accent_st, pos, rot, float(p[2]), float(p[3]), float(p[4]), pi)

	# 2. Snapped tarred mast spar (~2.85 m) floating tangentially along the aft-starboard edge!
	var spar_a := Vector3(-1.42, 0.06, -1.52)
	var spar_b := Vector3(1.38, 0.04, -1.24)
	var spar_dir := (spar_b - spar_a).normalized()
	_append_tapered_tube(wood_st, spar_a, spar_b, 0.145, 0.118, 8, COL_SPAR_TAR, COL_SPAR_HI)
	# Jagged splintered wood break shards jutting from the snapped end of the mast spar.
	var spar_up := Vector3.UP
	var spar_side := spar_dir.cross(spar_up).normalized()
	var shard_specs: Array[Array] = [
		[0.06, 0.05, 0.34, 0.042],
		[-0.05, 0.04, 0.28, 0.038],
		[0.02, -0.06, 0.24, 0.036],
		[-0.07, -0.03, 0.31, 0.040],
	]
	for sh in shard_specs:
		var base_pt := spar_b + spar_side * float(sh[0]) + spar_up * float(sh[1])
		var tip_pt := base_pt + spar_dir * float(sh[2]) + spar_side * (float(sh[0]) * 0.35)
		_append_cone_shard(wood_st, base_pt, tip_pt, float(sh[3]), COL_SPLINTER, COL_SPAR_TAR)

	# Two rusted iron mast-hoop bands clasping the snapped spar + coiled rope lashing.
	for frac: float in [0.22, 0.72]:
		var bp0 := spar_a.lerp(spar_b, frac - 0.025)
		var bp1 := spar_a.lerp(spar_b, frac + 0.025)
		_append_tapered_tube(accent_st, bp0, bp1, 0.152, 0.152, 8, COL_IRON_BAND, COL_IRON_BAND.lightened(0.14))

	# 3. Weathered hemp netting loops & tethering lines draped across the spar & lashed planks!
	var rope_paths: Array[Array] = [
		[
			Vector3(-1.08, 0.07, -1.46),
			Vector3(-1.24, 0.06, -0.62),
			Vector3(-1.18, 0.09, 0.44),
			Vector3(-0.88, 0.08, 0.92),
		],
		[
			Vector3(0.84, 0.08, -1.30),
			Vector3(1.14, 0.07, -0.74),
			Vector3(1.06, 0.06, 0.36),
			Vector3(0.64, 0.09, 1.02),
		],
		[
			Vector3(-1.28, 0.08, 0.96),
			Vector3(-0.62, 0.08, 1.24),
			Vector3(0.12, 0.07, 1.18),
			Vector3(0.68, 0.08, 0.98),
		],
		# Cross-webbed netting diagonals near the spar for unmistakable fishing-net silhouette.
		[Vector3(-0.92, 0.09, -1.42), Vector3(-0.38, 0.05, -0.92), Vector3(0.24, 0.07, -1.34)],
		[Vector3(-0.64, 0.06, -1.12), Vector3(-1.02, 0.06, -0.44), Vector3(-0.78, 0.07, 0.22)],
	]
	for path in rope_paths:
		for ri in range(path.size() - 1):
			_append_tapered_tube(
				wood_st, path[ri] as Vector3, path[ri + 1] as Vector3,
				0.024, 0.024, 5, COL_HEMP_DARK, COL_HEMP_HI
			)

	# 4. Twin painted crimson-and-cream cork fishing floats tethered to the debris netting!
	_append_cork_float(accent_st, wood_st, Vector3(-0.96, 0.02, -0.48), 0.165, Vector3(0.18, 0.4, -0.14))
	_append_cork_float(accent_st, wood_st, Vector3(1.16, 0.02, -0.12), 0.155, Vector3(-0.14, 1.2, 0.20))

	wood_st.generate_normals()
	var mesh := wood_st.commit()
	accent_st.generate_normals()
	accent_st.commit(mesh)
	return mesh


static func _append_splintered_plank(wood_st: SurfaceTool, accent_st: SurfaceTool,
		center: Vector3, rot: Basis, length: float, width: float, thick: float, idx: int) -> void:
	# Main weathered beveled oak plank body along local X.
	_append_oriented_beveled_box(
		wood_st, center, rot, Vector3(length, thick, width), 0.016,
		COL_OAK_BLEACHED, COL_OAK_MID, COL_OAK_WET
	)
	# Splintered broken tooth shards on both +/-X plank ends.
	for sx: float in [-1.0, 1.0]:
		var teeth := 2 if ((idx + int(sx > 0.0)) % 2 == 0) else 3
		for ti in teeth:
			var frac := (float(ti) + 0.5) / float(teeth) - 0.5
			var z_off := frac * (width * 0.72)
			var tooth_len := 0.16 + float((idx + ti) % 3) * 0.075
			var base_pt := center + rot * Vector3(sx * (length * 0.48), 0.0, z_off)
			var tip_pt := center + rot * Vector3(sx * (length * 0.48 + tooth_len), 0.008, z_off * 0.92)
			_append_cone_shard(wood_st, base_pt, tip_pt, thick * 0.46, COL_SPLINTER, COL_OAK_MID)

	# Two rusted iron deck spikes on top face of plank.
	for nx: float in [-length * 0.34, length * 0.34]:
		var nail_p := center + rot * Vector3(nx, thick * 0.5, 0.0)
		var nail_t := nail_p + rot * Vector3(0.0, 0.022, 0.0)
		_append_tapered_tube(accent_st, nail_p, nail_t, 0.015, 0.012, 5, COL_IRON_BAND, COL_IRON_BAND)


static func _append_cork_float(accent_st: SurfaceTool, wood_st: SurfaceTool,
		center: Vector3, radius: float, euler: Vector3) -> void:
	var rot := Basis.from_euler(euler)
	# Sculpted 10-sided lathe painted crimson top / cream waist / cork belly buoy float.
	var profile: Array[Array] = [
		[-1.00, 0.00, COL_FLOAT_CORK],
		[-0.86, 0.52, COL_FLOAT_CORK],
		[-0.45, 0.90, COL_FLOAT_CORK],
		[-0.18, 0.99, COL_FLOAT_CREAM],
		[0.18, 0.99, COL_FLOAT_CREAM],
		[0.24, 0.97, COL_FLOAT_CRIMSON],
		[0.64, 0.78, COL_FLOAT_CRIMSON],
		[0.92, 0.40, COL_FLOAT_CRIMSON],
		[1.04, 0.00, COL_FLOAT_CRIMSON],
	]
	var segs := 10
	for ri in range(profile.size() - 1):
		var y0: float = float(profile[ri][0]) * radius
		var r0: float = float(profile[ri][1]) * radius
		var c0: Color = profile[ri][2] as Color
		var y1: float = float(profile[ri + 1][0]) * radius
		var r1: float = float(profile[ri + 1][1]) * radius
		var c1: Color = profile[ri + 1][2] as Color
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var p00 := center + rot * Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := center + rot * Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := center + rot * Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := center + rot * Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 > 0.0005 and r1 > 0.0005:
				_emit_outward_tri(accent_st, p00, c0, p10, c1, p11, c1, center)
				_emit_outward_tri(accent_st, p00, c0, p11, c1, p01, c0, center)
			elif r0 <= 0.0005 and r1 > 0.0005:
				_emit_outward_tri(accent_st, p00, c0, p10, c1, p11, c1, center)
			elif r0 > 0.0005 and r1 <= 0.0005:
				_emit_outward_tri(accent_st, p00, c0, p10, c1, p01, c0, center)

	# Hemp rope waist lashing collar hugging the cork float equator.
	var rope_r := radius * 1.03
	for k in segs:
		var a0 := float(k) / float(segs) * TAU
		var a1 := float(k + 1) / float(segs) * TAU
		var q0 := center + rot * Vector3(cos(a0) * rope_r, 0.0, sin(a0) * rope_r)
		var q1 := center + rot * Vector3(cos(a1) * rope_r, 0.0, sin(a1) * rope_r)
		_append_tapered_tube(wood_st, q0, q1, 0.017, 0.017, 4, COL_HEMP_DARK, COL_HEMP_HI)


static func _build_fallback_barrel_mesh() -> ArrayMesh:
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Sculpted bilge-bellied oak cargo barrel with twin iron hoops (used only if barrel_prop.glb missing).
	var rings: Array[Array] = [
		[0.00, 0.00, COL_OAK_WET],
		[0.01, 0.28, COL_OAK_WET],
		[0.18, 0.34, COL_OAK_MID],
		[0.44, 0.37, COL_OAK_BLEACHED],
		[0.70, 0.34, COL_OAK_MID],
		[0.86, 0.28, COL_OAK_BLEACHED],
		[0.88, 0.24, COL_OAK_WET],
		[0.84, 0.00, COL_OAK_WET],
	]
	var segs := 10
	var center := Vector3(0.0, 0.44, 0.0)
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
				_emit_outward_tri(wood_st, p00, c0, p10, c1, p11, c1, center)
				_emit_outward_tri(wood_st, p00, c0, p11, c1, p01, c0, center)
			elif r0 <= 0.0005 and r1 > 0.0005:
				_emit_outward_tri(wood_st, p00, c0, p10, c1, p11, c1, center)
			elif r0 > 0.0005 and r1 <= 0.0005:
				_emit_outward_tri(wood_st, p00, c0, p10, c1, p01, c0, center)

	for hy: float in [0.22, 0.66]:
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var hr := 0.355
			_append_tapered_tube(
				iron_st, Vector3(cos(a0) * hr, hy, sin(a0) * hr),
				Vector3(cos(a1) * hr, hy, sin(a1) * hr), 0.016, 0.016, 4, COL_IRON_BAND, COL_IRON_BAND
			)

	wood_st.generate_normals()
	var mesh := wood_st.commit()
	iron_st.generate_normals()
	iron_st.commit(mesh)
	return mesh


# ==============================================================================
# Flat-Faceted `SurfaceTool` Helpers (`set_smooth_group(-1)`)
# ==============================================================================

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


static func _emit_dir_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, expected_normal: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(expected_normal) < 0.0:
		_emit_flat_tri(st, a, ca, c, cc, b, cb)
	else:
		_emit_flat_tri(st, a, ca, b, cb, c, cc)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var centroid := (a + b + c) / 3.0
	_emit_dir_tri(st, a, ca, b, cb, c, cc, centroid - ref_center)


static func _append_oriented_beveled_box(st: SurfaceTool, center: Vector3, rot: Basis,
		size: Vector3, bevel: float, col_top: Color, col_mid: Color, col_bot: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var bv := minf(bevel, minf(hx, minf(hy, hz)) * 0.45)
	var ix := hx - bv
	var iy := hy - bv
	var iz := hz - bv

	var ys: Array[float] = [-hy, -iy, iy, hy]
	var xzs: Array[Vector2] = [Vector2(ix, iz), Vector2(hx, hz), Vector2(hx, hz), Vector2(ix, iz)]
	var cols: Array[Color] = [col_bot, col_bot.lerp(col_mid, 0.5), col_mid.lerp(col_top, 0.5), col_top]

	var rings: Array[Array] = []
	for li in 4:
		var ry := ys[li]
		var rx := xzs[li].x
		var rz := xzs[li].y
		var cx := maxf(rx - bv * 0.5, 0.001)
		var cz := maxf(rz - bv * 0.5, 0.001)
		var raw_pts: Array[Vector3] = [
			Vector3(-cx, ry, -rz),
			Vector3(cx, ry, -rz),
			Vector3(rx, ry, -cz),
			Vector3(rx, ry, cz),
			Vector3(cx, ry, rz),
			Vector3(-cx, ry, rz),
			Vector3(-rx, ry, cz),
			Vector3(-rx, ry, -cz),
		]
		var ring: Array[Vector3] = []
		for rp in raw_pts:
			ring.append(center + rot * rp)
		rings.append(ring)

	for li in 3:
		var r0: Array = rings[li]
		var r1: Array = rings[li + 1]
		var c0 := cols[li]
		var c1 := cols[li + 1]
		for k in 8:
			var nk := (k + 1) % 8
			_emit_outward_tri(st, r0[k], c0, r1[k], c1, r1[nk], c1, center)
			_emit_outward_tri(st, r0[k], c0, r1[nk], c1, r0[nk], c0, center)

	var top_c := center + rot * Vector3(0.0, hy, 0.0)
	var bot_c := center + rot * Vector3(0.0, -hy, 0.0)
	var top_n := rot * Vector3.UP
	var bot_n := rot * Vector3.DOWN
	var top_r: Array = rings[3]
	var bot_r: Array = rings[0]
	for k in 8:
		var nk := (k + 1) % 8
		_emit_dir_tri(st, top_c, col_top, top_r[k], col_top, top_r[nk], col_top, top_n)
		_emit_dir_tri(st, bot_c, col_bot, bot_r[nk], col_bot, bot_r[k], col_bot, bot_n)


static func _append_tapered_tube(st: SurfaceTool, p0: Vector3, p1: Vector3,
		r0: float, r1: float, segs: int, c0: Color, c1: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-10:
		return
	var an := axis.normalized()
	var ref := Vector3.UP if absf(an.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx := an.cross(ref).normalized()
	var by := an.cross(bx).normalized()
	var mid := (p0 + p1) * 0.5
	for k in segs:
		var a0 := float(k) / float(segs) * TAU
		var a1 := float(k + 1) / float(segs) * TAU
		var d0 := bx * cos(a0) + by * sin(a0)
		var d1 := bx * cos(a1) + by * sin(a1)
		var v00 := p0 + d0 * r0
		var v01 := p0 + d1 * r0
		var v10 := p1 + d0 * r1
		var v11 := p1 + d1 * r1
		_emit_outward_tri(st, v00, c0, v10, c1, v11, c1, mid)
		_emit_outward_tri(st, v00, c0, v11, c1, v01, c0, mid)
		_emit_outward_tri(st, p0, c0, v00, c0, v01, c0, mid)
		_emit_outward_tri(st, p1, c1, v11, c1, v10, c1, mid)


static func _append_cone_shard(st: SurfaceTool, base: Vector3, tip: Vector3,
		radius: float, col_tip: Color, col_base: Color) -> void:
	var axis := tip - base
	if axis.length_squared() < 1e-10:
		return
	var an := axis.normalized()
	var ref := Vector3.UP if absf(an.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx := an.cross(ref).normalized()
	var by := an.cross(bx).normalized()
	var segs := 5
	var ctr := base.lerp(tip, 0.35)
	for k in segs:
		var a0 := float(k) / float(segs) * TAU
		var a1 := float(k + 1) / float(segs) * TAU
		var p0 := base + (bx * cos(a0) + by * sin(a0)) * radius
		var p1 := base + (bx * cos(a1) + by * sin(a1)) * radius
		_emit_outward_tri(st, p0, col_base, p1, col_base, tip, col_tip, ctr)
		_emit_outward_tri(st, base, col_base, p1, col_base, p0, col_base, ctr)
