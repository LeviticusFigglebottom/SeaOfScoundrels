class_name Ocean
extends Node3D
## Drop-in ocean: renders the sea from the camera to the horizon and owns the
## underwater view and breaking-crest spray. Instance `ocean.tscn` anywhere;
## it follows the active camera.
##
## Geometry is one mesh of concentric square rings (a clipmap baked into a
## single draw call): cell size doubles each ring, rims are stitched so there
## are no T-junction cracks, and a skirt runs to the horizon. The node moves in
## whole steps of `snap` metres, a multiple of the cell size of every ring that
## still carries waves, so vertices never swim. Heights come from the shared
## wave function (`Sea` autoload / waves.gdshaderinc) and nothing else.

signal camera_submerged_changed(submerged: bool)

## What each level buys (see docs/ARCHITECTURE.md for cost notes):
##  LOW     44k triangles, no foam simulation (two analytic foam looks instead),
##          no breaking-crest spray, single-phase ripples, no refraction offset,
##          caustics, rain rings or sun shafts.
##  MEDIUM  90k triangles, 256 px foam simulation, breaking-crest spray, dual-phase
##          wave-coupled flow ripples & webbing, 8-step sun shafts under water.
##  HIGH    151k triangles, 512 px foam simulation, full breaking-crest spray,
##          extra rain layer, 14-step shafts.
enum Quality { LOW, MEDIUM, HIGH }

const QUALITY_GRID := [56, 80, 104]       # cells across the innermost square
const QUALITY_FOAM_RES := [0, 256, 512]   # foam field resolution, 0 = off
const QUALITY_SHAFT_STEPS := [0, 8, 14]
## Side of the foam field's wrapping tile, metres.
const FOAM_TILE := 256.0
## Maximum simultaneous ship hull cutout volumes passed to the ocean shader.
const MAX_HULL_MASKS := 8

@export var quality: Quality = Quality.HIGH:
	set(v):
		quality = v
		if is_node_ready():
			_apply_quality()
## Cell size of the innermost square, metres.
@export var base_cell: float = 0.5
## Number of rings around the innermost square; each doubles the cell size.
@export var rings: int = 8
## The mesh moves in steps of base_cell * 2^snap_level metres.
@export var snap_level: int = 4
## Optional camera override; defaults to the viewport's active 3D camera.
@export var camera: Camera3D
## Set false to hide the underwater pass (e.g. for a map render).
@export var underwater_enabled: bool = true
## Rain rings on the surface, 0..1. Negative = follow Weather.rain_intensity()
## when the Weather autoload has it.
@export var rain_intensity: float = -1.0
## Crests foam where the wave Jacobian drops below `foam_crest_start` and are
## solid white at `foam_crest_full`.
@export var foam_crest_start: float = 0.91
@export var foam_crest_full: float = 0.66

const SHADER := preload("res://src/ocean/ocean.gdshader")
const DETAIL_TEX := preload("res://assets/generated/ocean/water_detail.png")
const FOAM_TEX := preload("res://assets/generated/ocean/foam.png")

## The ocean most recently added to the tree (there is normally exactly one).
static var current: Ocean

var material: ShaderMaterial
## Metres the camera is below the water surface (negative when above).
var camera_depth: float = -1000.0
var camera_submerged: bool = false
## Simulated foam, or null at LOW quality.
var foam_field: FoamField
## Breaking-crest spray emitter (active at MEDIUM and HIGH quality).
var crest_spray: CrestSpray

var _surface: MeshInstance3D
var _underwater: Node
var _hull_masks: Array[Dictionary] = []

func _enter_tree() -> void:
	current = self
	add_to_group(&"ocean")

func _exit_tree() -> void:
	if current == self:
		current = null

func _ready() -> void:
	process_priority = 100  # after cameras have moved this frame
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"detail_tex", DETAIL_TEX)
	material.set_shader_parameter(&"foam_tex", FOAM_TEX)
	material.set_shader_parameter(&"mesh_base_cell", base_cell)
	material.set_shader_parameter(&"foam_crest_start", foam_crest_start)
	material.set_shader_parameter(&"foam_crest_full", foam_crest_full)
	Sea.bind_material(material)

	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	_surface.material_override = material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.custom_aabb = AABB(Vector3(-1e6, -200, -1e6), Vector3(2e6, 400, 2e6))
	_surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_surface)

	crest_spray = CrestSpray.new()
	crest_spray.name = "CrestSpray"
	add_child(crest_spray)
	crest_spray.setup(self)

	_underwater = get_node_or_null(^"Underwater")
	if _underwater != null:
		_underwater.call(&"setup", self)
	_apply_quality()
	_sync_hull_masks(Vector3.ZERO)
	_follow(0.0)

func _apply_quality() -> void:
	var grid: int = QUALITY_GRID[quality]
	_surface.mesh = build_mesh(grid, base_cell, rings)
	# Cell size as a function of distance: ring L (cell base*2^L) spans
	# half-extents grid/4 .. grid/2 cells, so cell/distance is 2/grid..4/grid.
	material.set_shader_parameter(&"mesh_cell_per_metre", 2.7 / float(grid))
	material.set_shader_parameter(&"quality", int(quality))
	material.set_shader_parameter(&"uw_shaft_steps", QUALITY_SHAFT_STEPS[quality])
	if _underwater != null:
		_underwater.call(&"set_shaft_steps", QUALITY_SHAFT_STEPS[quality])
	if crest_spray != null:
		crest_spray.set_quality(int(quality))
	if foam_field != null:
		foam_field.queue_free()
		foam_field = null
	var res: int = QUALITY_FOAM_RES[quality]
	if res > 0:
		foam_field = FoamField.new(res, FOAM_TILE)
		foam_field.name = "FoamField"
		add_child(foam_field)
		material.set_shader_parameter(&"foam_field", foam_field.get_texture())
		material.set_shader_parameter(&"foam_field_size", FOAM_TILE)
	material.set_shader_parameter(&"foam_field_on", 1.0 if res > 0 else 0.0)

func _process(delta: float) -> void:
	_follow(delta)

## Whiten the water: wakes, splashes, cannonball impacts, oar strokes. The foam
## sticks to the water, rides the waves and fades over several seconds. Call it
## every frame for a continuous trail (e.g. at a ship's bow and stern, strength
## scaled by speed). `radius` in metres, `strength` 0..1 per call.
## No effect at LOW quality or further than about 100 m from the camera.
func add_foam(world_pos: Vector3, radius: float, strength: float = 1.0) -> void:
	if foam_field == null:
		return
	foam_field.stamp(Sea.rest_point(world_pos.x, world_pos.z), radius, strength)

## Register a ship hull cutout volume so ocean water is discarded inside the
## dry hold and underwater fog does not trigger below deck. Pass the model's
## `mask_water` MeshInstance3D when available (defaults to sloop dimensions).
func register_hull_mask(hull_owner: Node3D, mask_mesh: MeshInstance3D = null, flood_level: float = 0.0) -> void:
	if hull_owner == null:
		return
	_prune_hull_masks()
	var ext := _hull_extents(hull_owner, mask_mesh)
	var clamped_flood := clampf(flood_level, 0.0, 1.0)
	for entry in _hull_masks:
		if entry["owner"] == hull_owner:
			entry["size"] = ext["size"]
			entry["offset"] = ext["offset"]
			entry["flood"] = clamped_flood
			_sync_hull_masks(_camera_or_origin())
			return
	_hull_masks.append({
		"owner": hull_owner,
		"size": ext["size"],
		"offset": ext["offset"],
		"flood": clamped_flood,
	})
	_sync_hull_masks(_camera_or_origin())

## Update the 0..1 hold flood level of a registered ship hull cutout.
func update_hull_mask(hull_owner: Node3D, flood_level: float) -> void:
	if hull_owner == null:
		return
	var clamped_flood := clampf(flood_level, 0.0, 1.0)
	for entry in _hull_masks:
		if entry["owner"] == hull_owner:
			entry["flood"] = clamped_flood
			_sync_hull_masks(_camera_or_origin())
			return

## Remove a previously registered ship hull cutout volume.
func unregister_hull_mask(hull_owner: Node3D) -> void:
	if hull_owner == null:
		return
	for i in range(_hull_masks.size() - 1, -1, -1):
		if _hull_masks[i]["owner"] == hull_owner:
			_hull_masks.remove_at(i)
	_sync_hull_masks(_camera_or_origin())

## True if `world_pos` lies inside a registered ship's dry hold interior
## (above its current bilge flood level). Prevents false underwater fog below deck.
func is_point_in_dry_hull(world_pos: Vector3) -> bool:
	for entry in _hull_masks:
		var hull_owner: Variant = entry["owner"]
		if not is_instance_valid(hull_owner):
			continue
		var flood: float = entry["flood"]
		if flood >= 0.95:
			continue
		var inv := _hull_inv_transform(entry)
		var lp := inv * world_pos
		var sz: Vector4 = entry["size"]
		var flood_water_y := lerpf(-0.95, 1.15, flood)
		if lp.y <= flood_water_y or lp.y < sz.z or lp.y > sz.w:
			continue
		var w := _hull_half_beam(lp.z, lp.y, sz)
		if w > 0.0 and absf(lp.x) < w:
			return true
	return false

func active_camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null

func _follow(delta: float) -> void:
	var cam := active_camera()
	if cam == null:
		return
	var cp := cam.global_position
	var snap := base_cell * float(1 << snap_level)
	global_transform = Transform3D(Basis.IDENTITY,
			Vector3(roundf(cp.x / snap) * snap, 0.0, roundf(cp.z / snap) * snap))
	# Fade smoothly into the hazy sky horizon before the far plane.
	var far := cam.far
	material.set_shader_parameter(&"horizon_fade_start", far * 0.35)
	material.set_shader_parameter(&"horizon_fade_end", far * 0.92)
	_sync_hull_masks(cp)

	# weather
	var wind := Weather.wind_vector()
	var wd := Vector2(wind.x, wind.z)
	if wd.length_squared() > 0.0001:
		material.set_shader_parameter(&"wind_dir", wd.normalized())
	var rain := rain_intensity
	if rain < 0.0:
		rain = float(Weather.call(&"rain_intensity")) if Weather.has_method(&"rain_intensity") else 0.0
	material.set_shader_parameter(&"rain_intensity", clampf(rain, 0.0, 1.0))

	if foam_field != null and delta > 0.0:
		foam_field.step(delta, Sea.rest_point(cp.x, cp.z), foam_crest_start, foam_crest_full)

	var in_dry_hull := is_point_in_dry_hull(cp)
	camera_depth = -1000.0 if in_dry_hull else (Sea.height(cp.x, cp.z) - cp.y)
	var sub := (not in_dry_hull) and camera_depth > 0.0
	material.set_shader_parameter(&"uw_cam_depth", camera_depth)
	if _underwater != null:
		_underwater.call(&"update", cam, camera_depth if (underwater_enabled and not in_dry_hull) else -1000.0)
	if crest_spray != null:
		crest_spray.update(delta, cam, sub, foam_crest_start)
	if sub != camera_submerged:
		camera_submerged = sub
		camera_submerged_changed.emit(sub)

func _camera_or_origin() -> Vector3:
	var cam := active_camera()
	return cam.global_position if cam != null else Vector3.ZERO

func _prune_hull_masks() -> void:
	for i in range(_hull_masks.size() - 1, -1, -1):
		if not is_instance_valid(_hull_masks[i]["owner"]):
			_hull_masks.remove_at(i)

func _sync_hull_masks(ref_pos: Vector3) -> void:
	if material == null:
		return
	_prune_hull_masks()
	var ordered: Array[Dictionary] = _hull_masks.duplicate()
	if ordered.size() > MAX_HULL_MASKS:
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var oa: Node3D = a["owner"]
			var ob: Node3D = b["owner"]
			var pa := oa.global_position if oa.is_inside_tree() else oa.position
			var pb := ob.global_position if ob.is_inside_tree() else ob.position
			return pa.distance_squared_to(ref_pos) < pb.distance_squared_to(ref_pos)
		)
	var count := mini(ordered.size(), MAX_HULL_MASKS)
	var invs: Array[Transform3D] = []
	var sizes := PackedVector4Array()
	var floods := PackedFloat32Array()
	for i in count:
		var entry := ordered[i]
		invs.append(_hull_inv_transform(entry))
		sizes.append(entry["size"] as Vector4)
		floods.append(float(entry["flood"]))
	while invs.size() < MAX_HULL_MASKS:
		invs.append(Transform3D.IDENTITY)
		sizes.append(Vector4.ZERO)
		floods.append(1.0)
	material.set_shader_parameter(&"hull_mask_count", count)
	material.set_shader_parameter(&"hull_mask_inv", invs)
	material.set_shader_parameter(&"hull_mask_size", sizes)
	material.set_shader_parameter(&"hull_mask_flood", floods)

static func _hull_inv_transform(entry: Dictionary) -> Transform3D:
	var hull_owner: Node3D = entry["owner"]
	var base_xf := hull_owner.global_transform if hull_owner.is_inside_tree() else hull_owner.transform
	var off: Vector3 = entry["offset"]
	return (base_xf * Transform3D(Basis.IDENTITY, off)).affine_inverse()

## Tapered boat-shaped interior half-beam matching `is_inside_hull_mask()` in ocean.gdshader.
static func _hull_half_beam(local_z: float, local_y: float, sz: Vector4) -> float:
	var zn := local_z / maxf(sz.y, 0.1)
	if zn < -1.0 or zn > 1.0:
		return 0.0
	var w: float
	if zn < 0.0:
		var t := -zn
		w = sz.x * pow(maxf(0.0, 1.0 - pow(t, 2.35)), 0.72)
	else:
		var t := zn
		var st := lerpf(0.98, 0.44, clampf((local_y + 0.50) / 0.65, 0.0, 1.0))
		w = sz.x * (1.0 - st * t * t * t)
	var yh := clampf((local_y - sz.z) / maxf(-sz.z, 0.25), 0.0, 1.0)
	return w * lerpf(0.62, 1.0, sqrt(yh))

static func _hull_extents(hull_owner: Node3D, mask_mesh: MeshInstance3D) -> Dictionary:
	# Default sloop interior dimensions matching gen_sloop.py's mask_water.
	var size := Vector4(2.02, 6.20, -1.20, 1.95)
	var offset := Vector3.ZERO
	if mask_mesh != null and mask_mesh.mesh != null:
		var aabb := mask_mesh.mesh.get_aabb()
		if aabb.size.x > 0.1 and aabb.size.z > 0.1:
			var rel := _relative_transform(hull_owner, mask_mesh)
			var local_aabb := _transform_aabb(rel, aabb)
			var hx := maxf(local_aabb.size.x * 0.5 - 0.08, 0.45)
			var hz := maxf(local_aabb.size.z * 0.5, 0.8)
			var y_min := -1.20
			var y_max := 1.95
			if local_aabb.size.y >= 0.25:
				y_min = local_aabb.position.y
				y_max = local_aabb.end.y
			size = Vector4(hx, hz, y_min, y_max)
			var ctr := local_aabb.get_center()
			offset = Vector3(ctr.x, 0.0, ctr.z)
	return {"size": size, "offset": offset}

static func _relative_transform(hull_owner: Node3D, target: Node3D) -> Transform3D:
	if hull_owner.is_inside_tree() and target.is_inside_tree():
		return hull_owner.global_transform.affine_inverse() * target.global_transform
	var acc := Transform3D.IDENTITY
	var cur: Node = target
	while cur != null and cur != hull_owner:
		if cur is Node3D:
			acc = (cur as Node3D).transform * acc
		cur = cur.get_parent()
	return acc if cur == hull_owner else Transform3D.IDENTITY

static func _transform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
	var p := aabb.position
	var s := aabb.size
	var out := AABB(xf * p, Vector3.ZERO)
	for ix in 2:
		for iy in 2:
			for iz in 2:
				out = out.expand(xf * (p + Vector3(s.x * ix, s.y * iy, s.z * iz)))
	return out

## Triangle count of the generated surface (for budgets and tests).
func triangle_count() -> int:
	return _surface.mesh.surface_get_array_index_len(0) / 3 if _surface else 0

## Builds the ring mesh. Level 0 is a full grid x grid square of `cell` metres;
## level L >= 1 is a square annulus with cells of cell * 2^L. The outer rim of
## every level collapses its odd vertices onto the coarser neighbour's lattice,
## which makes the whole mesh watertight. UV.x = 1 marks skirt vertices.
static func build_mesh(n: int, cell: float, ring_count: int) -> ArrayMesh:
	assert(n % 8 == 0, "grid must be a multiple of 8")
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var lookup: Dictionary = {}
	var half := n >> 1
	var quarter := n >> 2
	var key_span := (half << ring_count) * 2 + 8

	var vertex_at := func(ix: int, iz: int, skirt: bool) -> int:
		# ix, iz in units of the base cell.
		var key := (ix + key_span) + (iz + key_span) * key_span * 4 + (1 << 60 if skirt else 0)
		var found: Variant = lookup.get(key)
		if found != null:
			return found
		var idx := verts.size()
		verts.append(Vector3(ix * cell, 0.0, iz * cell))
		uvs.append(Vector2(1.0 if skirt else 0.0, 0.0))
		lookup[key] = idx
		return idx

	for level in ring_count + 1:
		var s := 1 << level
		var stitch := level < ring_count
		for j in range(-half, half):
			for i in range(-half, half):
				if level > 0 and i >= -quarter and i < quarter and j >= -quarter and j < quarter:
					continue
				var c: Array[int] = []
				for corner: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
					var ci := corner.x
					var cj := corner.y
					if stitch:
						# Odd vertices on the outer rim slide to the even neighbour.
						if absi(cj) == half and (ci & 1) != 0:
							ci -= 1
						if absi(ci) == half and (cj & 1) != 0:
							cj -= 1
					c.append(vertex_at.call(ci * s, cj * s, false))
				# Alternate the diagonal so the tessellation has no grain.
				var tris: Array[int]
				if (i + j) & 1 == 0:
					tris = [c[0], c[1], c[2], c[0], c[2], c[3]]
				else:
					tris = [c[0], c[1], c[3], c[1], c[2], c[3]]
				for t in 2:
					var a := tris[t * 3]
					var b := tris[t * 3 + 1]
					var d := tris[t * 3 + 2]
					if a != b and b != d and a != d:
						indices.append(a)
						indices.append(b)
						indices.append(d)

	# Skirt from the outermost rim to the horizon (pushed out in the shader).
	var s_out := 1 << ring_count
	var rim: Array[Vector2i] = []
	for i in range(-half, half):
		rim.append(Vector2i(i, -half))
	for j in range(-half, half):
		rim.append(Vector2i(half, j))
	for i in range(half, -half, -1):
		rim.append(Vector2i(i, half))
	for j in range(half, -half, -1):
		rim.append(Vector2i(-half, j))
	for r in rim.size():
		var p0 := rim[r]
		var p1 := rim[(r + 1) % rim.size()]
		var a := vertex_at.call(p0.x * s_out, p0.y * s_out, false) as int
		var b := vertex_at.call(p1.x * s_out, p1.y * s_out, false) as int
		var a2 := vertex_at.call(p0.x * s_out, p0.y * s_out, true) as int
		var b2 := vertex_at.call(p1.x * s_out, p1.y * s_out, true) as int
		indices.append_array(PackedInt32Array([a, a2, b2, a, b2, b]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
