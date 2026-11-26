class_name SupplyBarrel
extends Node3D
## Bonus island supply barrel: one-press take-all container fulfilling docs/DESIGN.md.
##
## Uses the sculpted `barrel_prop.glb` coopered oak barrel (or a flat-faceted lathed
## oak `ArrayMesh` fallback if absent) crowned with a sculpted golden-brass Supply Tag
## & crimson-wax seal lid emblem (`ArrayMesh`, zero raw primitives). Once looted via
## `take_all(pawn)`, the golden lid emblem hides cleanly so captains can tell at a
## glance which island barrels still hold bonus cannonballs, planks, and rations.

signal supplies_taken(barrel: SupplyBarrel, pawn: Node, loot: Dictionary)

const GROUP := &"supply_barrels"
const BARREL_GLB_PATH := "res://assets/generated/props/barrel_prop.glb"
const LID_HEIGHT_Y := 0.86

# Painterly pirate brass, crimson wax seal, and coopered oak fallback palette.
const COL_BRASS_HI := Color(0.96, 0.80, 0.30)
const COL_BRASS_MID := Color(0.80, 0.60, 0.18)
const COL_BRASS_DARK := Color(0.50, 0.36, 0.11)
const COL_WAX_HI := Color(0.84, 0.18, 0.14)
const COL_WAX_LO := Color(0.46, 0.08, 0.07)
const COL_ROPE := Color(0.74, 0.60, 0.38)
const COL_OAK_LIGHT := Color(0.50, 0.34, 0.19)
const COL_OAK_DARK := Color(0.30, 0.19, 0.10)
const COL_IRON := Color(0.18, 0.19, 0.21)

@export var cannonballs: int = 6
@export var planks: int = 3
@export var heal_bonus: float = 18.0

var looted: bool = false
var interactable: Interactable = null

var _barrel_root: Node3D = null
var _emblem_mi: MeshInstance3D = null
var _fallback_mi: MeshInstance3D = null
var _col_body: StaticBody3D = null

# Statically shared meshes & materials released cleanly when the last barrel exits tree.
static var _active_barrels: int = 0
static var _barrel_scene: PackedScene = null
static var _fallback_barrel_mesh: ArrayMesh = null
static var _emblem_mesh: ArrayMesh = null
static var _brass_mat: StandardMaterial3D = null
static var _wood_mat: StandardMaterial3D = null


func _enter_tree() -> void:
	add_to_group(GROUP)
	_active_barrels += 1


func _ready() -> void:
	_ensure_shared_assets()
	_build_visual_and_collision()
	interactable = Interactable.create(_build_prompt(), 1.1)
	interactable.name = "Interactable"
	interactable.reach = 2.8
	interactable.position = Vector3(0.0, 0.52, 0.0)
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	if looted:
		_apply_looted_visuals()


func _exit_tree() -> void:
	if interactable != null and is_instance_valid(interactable):
		if interactable.interacted.is_connected(_on_interacted):
			interactable.interacted.disconnect(_on_interacted)
	if _emblem_mi != null and is_instance_valid(_emblem_mi):
		_emblem_mi.material_override = null
		_emblem_mi.mesh = null
	if _fallback_mi != null and is_instance_valid(_fallback_mi):
		_fallback_mi.material_override = null
		_fallback_mi.mesh = null
	_emblem_mi = null
	_fallback_mi = null
	_barrel_root = null
	_col_body = null
	_active_barrels = maxi(0, _active_barrels - 1)
	if _active_barrels == 0:
		clear_shared_cache()


## Release statically cached meshes & materials cleanly (also called automatically when count hits 0).
static func clear_shared_cache() -> void:
	_barrel_scene = null
	_fallback_barrel_mesh = null
	_emblem_mesh = null
	_brass_mat = null
	_wood_mat = null


## Host-authoritative idempotent one-press take-all. Returns loot payload or `{}` if already looted.
func take_all(pawn: Node = null) -> Dictionary:
	if not Net.is_host() or looted:
		return {}
	looted = true
	_apply_looted_visuals()
	Audio.play_sfx(&"chest_thump", global_position, -3.5)

	var healed := 0.0
	if pawn is Pawn:
		var p := pawn as Pawn
		if not p.dead and p.health < p.max_health and heal_bonus > 0.0:
			var before_hp := p.health
			p.heal(heal_bonus)
			healed = maxf(0.0, p.health - before_hp)

	var loot := {
		"cannonballs": cannonballs,
		"planks": planks,
		"healed": healed,
	}
	supplies_taken.emit(self, pawn, loot)
	return loot


func _on_interacted(pawn: Node) -> void:
	take_all(pawn)


func _build_prompt() -> String:
	return "Take all supplies (+%d balls, +%d planks)" % [cannonballs, planks]


func _apply_looted_visuals() -> void:
	if _emblem_mi != null and is_instance_valid(_emblem_mi):
		_emblem_mi.visible = false
	if interactable != null and is_instance_valid(interactable):
		interactable.enabled = false
		interactable.prompt = "Empty supply barrel"


func _build_visual_and_collision() -> void:
	_barrel_root = Node3D.new()
	_barrel_root.name = "BarrelVisual"
	add_child(_barrel_root)

	_col_body = StaticBody3D.new()
	_col_body.name = "BarrelCollider"
	_col_body.collision_layer = 1
	_col_body.collision_mask = 0
	add_child(_col_body)

	var extracted_col := false
	if _barrel_scene != null:
		var inst := _barrel_scene.instantiate() as Node3D
		if inst != null:
			inst.name = "BarrelProp"
			_barrel_root.add_child(inst)
			for node in inst.find_children("col_*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				if mi == null:
					continue
				mi.visible = false
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if mi.mesh != null:
					var faces := mi.mesh.get_faces()
					if faces.size() >= 3:
						var shape := ConvexPolygonShape3D.new()
						shape.points = faces
						var cs := CollisionShape3D.new()
						cs.name = "Col_" + mi.name
						cs.shape = shape
						cs.transform = mi.transform
						_col_body.add_child(cs)
						extracted_col = true
	else:
		_fallback_mi = MeshInstance3D.new()
		_fallback_mi.name = "BarrelFallbackMesh"
		_fallback_mi.mesh = _fallback_barrel_mesh
		_fallback_mi.material_override = _wood_mat
		_barrel_root.add_child(_fallback_mi)

	if not extracted_col:
		var cyl_col := CollisionShape3D.new()
		cyl_col.name = "Col_BarrelHull"
		var sh := CylinderShape3D.new()
		sh.radius = 0.31
		sh.height = 0.88
		cyl_col.shape = sh
		cyl_col.position = Vector3(0.0, 0.44, 0.0)
		_col_body.add_child(cyl_col)

	# Crown barrel lid with sculpted golden-brass Supply Tag & crimson seal emblem.
	_emblem_mi = MeshInstance3D.new()
	_emblem_mi.name = "SupplyTagEmblem"
	_emblem_mi.mesh = _emblem_mesh
	_emblem_mi.material_override = _brass_mat
	_emblem_mi.position = Vector3(0.0, LID_HEIGHT_Y, 0.0)
	_barrel_root.add_child(_emblem_mi)


# ==============================================================================
# Statically Cached Sculpted Flat-Faceted ArrayMeshes (Zero Raw Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _barrel_scene == null and ResourceLoader.exists(BARREL_GLB_PATH):
		_barrel_scene = load(BARREL_GLB_PATH) as PackedScene
	if _brass_mat == null:
		_brass_mat = StandardMaterial3D.new()
		_brass_mat.vertex_color_use_as_albedo = true
		_brass_mat.roughness = 0.32
		_brass_mat.metallic = 0.72
	if _emblem_mesh == null:
		_emblem_mesh = _build_supply_emblem_mesh()
	if _barrel_scene == null:
		if _wood_mat == null:
			_wood_mat = StandardMaterial3D.new()
			_wood_mat.vertex_color_use_as_albedo = true
			_wood_mat.roughness = 0.84
			_wood_mat.metallic = 0.06
		if _fallback_barrel_mesh == null:
			_fallback_barrel_mesh = _build_fallback_barrel_mesh()


static func _build_supply_emblem_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	# 1. Beveled 12-sided golden-brass lid medallion resting flush on the oak lid.
	_append_lathe_profile(st, [
		Vector2(0.0, 0.002),
		Vector2(0.148, 0.002),
		Vector2(0.156, 0.012),
		Vector2(0.144, 0.024),
		Vector2(0.114, 0.024),
		Vector2(0.106, 0.018),
		Vector2(0.0, 0.018),
	], 12, COL_BRASS_HI, COL_BRASS_DARK)

	# 2. Central 4-point sculpted nautical compass star boss rising above the medallion.
	var star_top := Vector3(0.0, 0.046, 0.0)
	var star_pts := 8
	var ring_verts: Array[Vector3] = []
	for i in star_pts:
		var a := float(i) / float(star_pts) * TAU
		var r := 0.098 if i % 2 == 0 else 0.036
		ring_verts.append(Vector3(cos(a) * r, 0.020, sin(a) * r))
	for i in star_pts:
		var a := ring_verts[i]
		var b := ring_verts[(i + 1) % star_pts]
		var col := COL_BRASS_HI if i % 2 == 0 else COL_BRASS_MID
		_add_tri(st, star_top, a, b, col)

	# 3. Twin beveled brass locking straps spanning across the recessed lid + rivets.
	for sx: float in [-1.0, 1.0]:
		_append_beveled_box(
			st, Vector3(sx * 0.165, 0.012, 0.0), Vector3(0.14, 0.016, 0.048), 0.004,
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_DARK
		)
		_append_lathe_profile(st, [
			Vector2(0.0, 0.020),
			Vector2(0.014, 0.020),
			Vector2(0.010, 0.028),
			Vector2(0.0, 0.030),
		], 6, COL_BRASS_HI, COL_BRASS_MID, Vector3(sx * 0.21, 0.0, 0.0))

	# 4. Crimson-wax & gold hanging supply seal ribbon draped cleanly over the front rim.
	_append_beveled_box(
		st, Vector3(0.0, 0.018, -0.195), Vector3(0.044, 0.014, 0.13), 0.003,
		COL_ROPE, COL_ROPE, COL_BRASS_DARK
	)
	_append_beveled_box(
		st, Vector3(0.0, -0.042, -0.264), Vector3(0.056, 0.132, 0.020), 0.004,
		COL_WAX_HI, COL_WAX_HI, COL_WAX_LO
	)
	# Wax seal medallion disc on front face of the hanging supply ribbon.
	_append_beveled_box(
		st, Vector3(0.0, -0.052, -0.278), Vector3(0.072, 0.072, 0.018), 0.008,
		COL_BRASS_HI, COL_WAX_HI, COL_WAX_LO
	)

	st.generate_normals()
	return st.commit()


static func _build_fallback_barrel_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_append_lathe_profile(st, [
		Vector2(0.0, 0.02),
		Vector2(0.23, 0.02),
		Vector2(0.255, 0.0),
		Vector2(0.275, 0.06),
		Vector2(0.315, 0.30),
		Vector2(0.315, 0.58),
		Vector2(0.275, 0.82),
		Vector2(0.255, 0.88),
		Vector2(0.23, 0.86),
		Vector2(0.0, 0.86),
	], 12, COL_OAK_LIGHT, COL_OAK_DARK)
	for hoop: Array in [[0.10, 0.29], [0.30, 0.32], [0.58, 0.32], [0.78, 0.29]]:
		var hy: float = float(hoop[0])
		var hr: float = float(hoop[1])
		_append_lathe_profile(st, [
			Vector2(hr - 0.01, hy - 0.024),
			Vector2(hr + 0.006, hy - 0.020),
			Vector2(hr + 0.006, hy + 0.020),
			Vector2(hr - 0.01, hy + 0.024),
		], 12, COL_IRON, COL_IRON)
	st.generate_normals()
	return st.commit()


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(c)


static func _append_lathe_profile(
	st: SurfaceTool,
	profile: Array[Vector2],
	segs: int,
	col_top: Color,
	col_bot: Color,
	offset: Vector3 = Vector3.ZERO
) -> void:
	for pi in range(profile.size() - 1):
		var r0 := profile[pi].x
		var y0 := profile[pi].y
		var r1 := profile[pi + 1].x
		var y1 := profile[pi + 1].y
		var t := float(pi) / maxf(float(profile.size() - 2), 1.0)
		var col := col_bot.lerp(col_top, t)
		for s in segs:
			var a0 := float(s) / float(segs) * TAU
			var a1 := float(s + 1) / float(segs) * TAU
			var p00 := offset + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := offset + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := offset + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := offset + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 > 0.0005:
				_add_tri(st, p00, p10, p01, col)
			if r1 > 0.0005:
				_add_tri(st, p10, p11, p01, col)


static func _append_beveled_box(
	st: SurfaceTool,
	center: Vector3,
	dims: Vector3,
	bevel: float,
	col_top: Color,
	col_side: Color,
	col_bot: Color
) -> void:
	var hx := dims.x * 0.5
	var hy := dims.y * 0.5
	var hz := dims.z * 0.5
	var bx := maxf(0.001, hx - bevel)
	var bz := maxf(0.001, hz - bevel)
	var ty := center.y + hy
	var by := center.y - hy
	var t0 := Vector3(center.x - bx, ty, center.z - bz)
	var t1 := Vector3(center.x + bx, ty, center.z - bz)
	var t2 := Vector3(center.x + bx, ty, center.z + bz)
	var t3 := Vector3(center.x - bx, ty, center.z + bz)
	var b0 := Vector3(center.x - hx, by, center.z - hz)
	var b1 := Vector3(center.x + hx, by, center.z - hz)
	var b2 := Vector3(center.x + hx, by, center.z + hz)
	var b3 := Vector3(center.x - hx, by, center.z + hz)
	# Top & bottom caps.
	_add_tri(st, t0, t1, t2, col_top)
	_add_tri(st, t0, t2, t3, col_top)
	_add_tri(st, b0, b2, b1, col_bot)
	_add_tri(st, b0, b3, b2, col_bot)
	# Four beveled side faces.
	var quads: Array[Array] = [
		[b0, b1, t1, t0],
		[b1, b2, t2, t1],
		[b2, b3, t3, t2],
		[b3, b0, t0, t3],
	]
	for q in quads:
		_add_tri(st, q[0] as Vector3, q[1] as Vector3, q[2] as Vector3, col_side)
		_add_tri(st, q[0] as Vector3, q[2] as Vector3, q[3] as Vector3, col_side)
