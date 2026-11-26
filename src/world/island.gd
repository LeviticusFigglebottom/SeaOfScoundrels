class_name Island
extends Node3D
## Procedural island node carrying terrain heightfield queries, dig sites,
## mooring metadata, simplified coastline contours for maps, live foliage wind
## updates, and warm ambient lantern/campfire flicker.

const GROUP := &"islands"
const FIREFLY_CULL_DIST := 95.0

@export var island_id: String = ""
@export var display_name: String = ""
@export var archetype: StringName = &"treasure_peak"
@export var kind: StringName = &"treasure_island"
@export var island_radius: float = 60.0
@export var seabed_radius: float = 125.0
@export var peak_height: float = 48.0
@export var is_outpost: bool = false
@export var landmarks: Array[String] = []

## Alias matching VoyageComposer's duck-typed island node extractor.
var island_name: String:
	get:
		return display_name
	set(v):
		display_name = v

## Local-space candidate points on walkable sand/turf for buried treasure.
var dig_points: Array[Vector3] = []
## Local-space walkable spawn points for island enemies (Drowned, crabs, etc.).
var enemy_spawns: Array[Vector3] = []
## Local-space safe deep-water mooring transform (origin at waterline, -Z seaward).
var mooring_transform: Transform3D = Transform3D.IDENTITY
## Simplified coastline polygon in local XZ (y = 0 contour) for maps & charts.
var contour_points: PackedVector2Array = PackedVector2Array()

var _height_grid: PackedFloat32Array = PackedFloat32Array()
var _grid_res: int = 0
var _grid_half: float = 120.0
var _sea_floor_y: float = -20.0

var _foliage_materials: Array[ShaderMaterial] = []
var _flicker_lights: Array[Dictionary] = []
var _fireflies: GPUParticles3D = null
var _flicker_time: float = 0.0
var _wind_accum: float = 0.25
var _dig_sites_root: Node3D = null

static var _active_firefly_emitters: int = 0
static var _firefly_glow_tex: ImageTexture = null


func _enter_tree() -> void:
	add_to_group(GROUP)


static func get_firefly_glow_texture() -> ImageTexture:
	if _firefly_glow_tex != null:
		return _firefly_glow_tex
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var halo := exp(-r * r * 5.2) * smoothstep(1.0, 0.25, r)
			var core := exp(-r * r * 24.0)
			var alpha := clampf(halo * 0.85 + core * 0.75, 0.0, 1.0)
			var lum := clampf(0.82 + core * 0.18, 0.0, 1.0)
			img.set_pixel(x, y, Color(lum, lum, lum * 0.92, alpha))
	_firefly_glow_tex = ImageTexture.create_from_image(img)
	return _firefly_glow_tex


func _process(delta: float) -> void:
	_flicker_time += delta
	_wind_accum += delta
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var has_cam := cam != null
	var cam_pos := cam.global_position if has_cam else Vector3.ZERO
	var dist_sq := global_position.distance_squared_to(cam_pos) if has_cam else 0.0

	var foliage_cull := maxf(380.0, island_radius + 260.0)
	if not _foliage_materials.is_empty() and _wind_accum >= 0.16 and dist_sq <= foliage_cull * foliage_cull:
		_wind_accum = 0.0
		var wind := Weather.wind_vector()
		var spd := wind.length()
		var dir2 := Vector2(wind.x, wind.z)
		if dir2.length_squared() > 0.0001:
			dir2 = dir2.normalized()
		else:
			dir2 = Vector2(0.707, -0.707)
		for mat in _foliage_materials:
			if mat != null:
				mat.set_shader_parameter(&"wind_dir", dir2)
				mat.set_shader_parameter(&"wind_speed", spd)

	var flicker_cull := maxf(160.0, island_radius + 95.0)
	if not _flicker_lights.is_empty() and dist_sq <= flicker_cull * flicker_cull:
		for entry in _flicker_lights:
			var light: OmniLight3D = entry.get("light")
			if light == null or not is_instance_valid(light):
				continue
			var base_e: float = float(entry["base_energy"])
			var amp: float = float(entry["amp"])
			var phase: float = float(entry["phase"])
			var wave := sin(_flicker_time * 5.3 + phase) * 0.6 + sin(_flicker_time * 11.7 + phase * 1.9) * 0.4
			light.light_energy = maxf(0.1, base_e * (1.0 + wave * amp))

	if _fireflies != null:
		update_night_ambience(cam_pos, has_cam)


## Bind the exact terrain height grid built by `IslandGenerator`.
func set_height_grid(grid: PackedFloat32Array, grid_res: int, grid_half: float,
		sea_floor_y: float = -20.0) -> void:
	_height_grid = grid
	_grid_res = grid_res
	_grid_half = grid_half
	_sea_floor_y = sea_floor_y


func register_foliage_material(mat: ShaderMaterial) -> void:
	if mat != null and not _foliage_materials.has(mat):
		_foliage_materials.append(mat)


func register_flicker_light(light: OmniLight3D, base_energy: float,
		amp: float = 0.14, phase: float = 0.0) -> void:
	if light == null:
		return
	_flicker_lights.append({
		"light": light,
		"base_energy": base_energy,
		"amp": amp,
		"phase": phase,
	})


func register_fireflies(node: GPUParticles3D) -> void:
	_fireflies = node
	if node != null:
		if not node.tree_entered.is_connected(_on_fireflies_entered_tree):
			node.tree_entered.connect(_on_fireflies_entered_tree)
		if not node.tree_exiting.is_connected(_on_fireflies_exiting_tree):
			node.tree_exiting.connect(_on_fireflies_exiting_tree.bind(node))
		if node.is_inside_tree():
			_on_fireflies_entered_tree()
	update_night_ambience(Vector3.ZERO, false)


static func _on_fireflies_entered_tree() -> void:
	_active_firefly_emitters += 1


static func _on_fireflies_exiting_tree(node: GPUParticles3D) -> void:
	if node != null and is_instance_valid(node):
		node.emitting = false
		node.visible = false
		if node.draw_pass_1 is QuadMesh:
			var qm := node.draw_pass_1 as QuadMesh
			if qm.material is StandardMaterial3D:
				(qm.material as StandardMaterial3D).albedo_texture = null
			qm.material = null
		if node.process_material is ParticleProcessMaterial:
			var pm := node.process_material as ParticleProcessMaterial
			pm.color_ramp = null
			pm.scale_curve = null
		node.draw_pass_1 = null
		node.process_material = null
	_active_firefly_emitters = maxi(0, _active_firefly_emitters - 1)
	if _active_firefly_emitters == 0:
		_firefly_glow_tex = null


## Gate IslandFireflies smoothly by Weather.daylight() and radius-scaled camera distance (0.00 ms GPU cost in daylight/open sea).
func update_night_ambience(cam_pos: Vector3, has_cam: bool) -> void:
	if _fireflies == null or not is_instance_valid(_fireflies):
		return
	var night_strength := clampf((0.45 - Weather.daylight()) / 0.35, 0.0, 1.0)
	var firefly_cull := maxf(FIREFLY_CULL_DIST, island_radius + 45.0)
	var within_range := (not has_cam) or global_position.distance_squared_to(cam_pos) <= firefly_cull * firefly_cull
	if night_strength <= 0.01 or not within_range:
		_fireflies.emitting = false
		_fireflies.visible = false
	else:
		_fireflies.visible = true
		_fireflies.emitting = true
		_fireflies.amount_ratio = clampf(night_strength, 0.2, 1.0)


## Exact local terrain elevation matching the triangulated terrain collider.
func surface_height(local_x: float, local_z: float) -> float:
	if _grid_res <= 0 or _height_grid.is_empty():
		return _sea_floor_y
	var span := _grid_half * 2.0
	var gx := (local_x + _grid_half) / span * float(_grid_res)
	var gz := (local_z + _grid_half) / span * float(_grid_res)
	if gx < 0.0 or gx > float(_grid_res) or gz < 0.0 or gz > float(_grid_res):
		return _sea_floor_y
	var ix := mini(int(floorf(gx)), _grid_res - 1)
	var iz := mini(int(floorf(gz)), _grid_res - 1)
	var fx := clampf(gx - float(ix), 0.0, 1.0)
	var fz := clampf(gz - float(iz), 0.0, 1.0)
	var stride := _grid_res + 1
	var h00 := _height_grid[iz * stride + ix]
	var h10 := _height_grid[iz * stride + ix + 1]
	var h01 := _height_grid[(iz + 1) * stride + ix]
	var h11 := _height_grid[(iz + 1) * stride + ix + 1]
	# Match IslandGenerator's diagonal split: (0,0)-(1,0)-(1,1) and (0,0)-(1,1)-(0,1).
	if fx >= fz:
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)


## Approximate smooth terrain normal in island-local space.
func surface_normal(local_x: float, local_z: float, step: float = 1.5) -> Vector3:
	var hx0 := surface_height(local_x - step, local_z)
	var hx1 := surface_height(local_x + step, local_z)
	var hz0 := surface_height(local_x, local_z - step)
	var hz1 := surface_height(local_x, local_z + step)
	return Vector3(hx0 - hx1, 2.0 * step, hz0 - hz1).normalized()


## Terrain elevation at a world-space point (works before or after entering tree).
func world_surface_height(world_pos: Vector3) -> float:
	var xform := global_transform if is_inside_tree() else transform
	var lp := xform.affine_inverse() * world_pos
	var h := surface_height(lp.x, lp.z)
	return (xform * Vector3(lp.x, h, lp.z)).y


## Positive water depth below sea level (Y = 0) at `world_pos`, in metres.
## Returns 0.0 for dry land at or above Y = 0.
func seabed_depth(world_pos: Vector3) -> float:
	return maxf(0.0, -world_surface_height(world_pos))


## Proximity to this island's surf / shoreline in 0..1 (1 at the waterline/beach,
## 0 in deep open water past the seabed skirt). Used for surf ambience and navigation.
func shore_factor(world_pos: Vector3) -> float:
	var xform := global_transform if is_inside_tree() else transform
	var lp := xform.affine_inverse() * world_pos
	var dist_xz := Vector2(lp.x, lp.z).length()
	if dist_xz > seabed_radius + 35.0:
		return 0.0
	var h := surface_height(lp.x, lp.z)
	if h <= -13.5:
		return 0.0
	if h < 0.0:
		# Smooth swell from deep water (-13.5 m) to full surf right at the shallows (-1.2..0 m).
		return clampf(smoothstep(-13.5, -1.2, h), 0.0, 1.0)
	# On land: strongest right on the beach (0..4 m), gently softening high up inland cliffs.
	return lerpf(1.0, 0.35, clampf(smoothstep(4.0, 26.0, h), 0.0, 1.0))


## World-space mooring transform for a sloop arriving at this island.
func get_world_mooring_transform() -> Transform3D:
	var xform := global_transform if is_inside_tree() else transform
	return xform * mooring_transform


## Return all `DigSite` nodes currently belonging to this island.
func get_dig_sites() -> Array[DigSite]:
	var out: Array[DigSite] = []
	for node in find_children("*", "DigSite", true, false):
		var ds := node as DigSite
		if ds != null and is_instance_valid(ds):
			out.append(ds)
	return out


## Spawn and ground-snap a `DigSite` at `local_pos` (island-local XZ; Y snapped).
func spawn_dig_site(local_pos: Vector3, p_treasure_id: StringName = &"wayfarer_chest") -> DigSite:
	if _dig_sites_root == null:
		_dig_sites_root = get_node_or_null(^"DigSites") as Node3D
		if _dig_sites_root == null:
			_dig_sites_root = Node3D.new()
			_dig_sites_root.name = "DigSites"
			add_child(_dig_sites_root)
	var site := DigSite.new()
	site.name = "DigSite_%d" % _dig_sites_root.get_child_count()
	site.treasure_id = p_treasure_id
	var y := surface_height(local_pos.x, local_pos.z)
	site.position = Vector3(local_pos.x, y, local_pos.z)
	_dig_sites_root.add_child(site)
	return site


## Map and voyage metadata dictionary for `Archipelago.get_map_data()`.
func get_map_entry() -> Dictionary:
	var pos := global_position if is_inside_tree() else position
	return {
		"id": StringName(island_id),
		"island_id": island_id,
		"name": display_name,
		"display_name": display_name,
		"kind": kind,
		"archetype": archetype,
		"is_outpost": is_outpost,
		"position": pos,
		"radius": island_radius,
		"peak_height": peak_height,
		"landmarks": landmarks.duplicate(),
		"contour_points": contour_points,
		"mooring_transform": mooring_transform,
		"dig_points": dig_points.duplicate(),
	}
