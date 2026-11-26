class_name MapTableView
extends Node3D
## Live diegetic parchment nautical chart rendered onto a SubViewport texture
## and mounted directly on top of a Ship's wooden `MapTable` mesh.
##
## Displays parchment gridlines, decorative compass rose, all archipelago islands
## (discovered named in sepia ink, undiscovered as faint silhouettes), player ship
## silhouette + live heading arrow, active voyage crimson dashed circle, active
## Weather storm cell swirl, salvage wreck X markers, and player-placed pins.
## Throttled to redraw every 0.15 s so it stays ultra-cheap at runtime.

signal marker_placed(world_pos: Vector3)
signal view_changed(center: Vector2, span: float)

const UPDATE_INTERVAL := 0.15
const CHART_RES := Vector2i(1024, 680)
const CHART_WIDTH_M := 1.08
const CHART_DEPTH_M := 0.70
const SHIP_TABLE_TOP_Y := 0.874
const MIN_SPAN := 420.0
const MAX_SPAN := 5600.0
const MAX_TRAIL_POINTS := 48

## Ship whose position/heading is plotted on the chart (auto-set by `mount_to_ship`).
var tracked_ship: Node3D = null
## Optional Archipelago node (providing `get_map_data()`), or Array of island dicts.
var archipelago_source: Variant = null
## Optional VoyageManager for automatic active-voyage target highlighting.
var voyage_manager: VoyageManager = null
## Optional WorldDirector for automatic salvage wreck X markers.
var world_director: WorldDirector = null

## Chart world-space XZ center and horizontal width (metres).
var view_center: Vector2 = Vector2(0.0, -450.0)
var view_span: float = 2900.0
## Player-placed chart markers (world positions).
var markers: Array[Vector3] = []
## Explicit active voyage target world position (Vector3.INF when unset).
var active_voyage_target: Vector3 = Vector3.INF
## Explicit salvage wreck world positions (merged with WorldDirector.salvage_wrecks).
var salvage_wrecks: Array[Vector3] = []

## Vertical offset of the chart surface in local space (0.874 m on sloop MapTable).
@export var surface_height_y: float = 0.0
## Include wooden frame molding and brass corner tacks around the parchment chart.
@export var build_frame: bool = true

var _viewport: SubViewport = null
var _canvas: _ChartCanvas = null
var _surface_mesh: MeshInstance3D = null
var _frame_root: Node3D = null
var _surface_mat: StandardMaterial3D = null
var _islands_cache: Array[Dictionary] = []
var _trail: Array[Vector2] = []
var _update_accum: float = 0.0
var _dirty: bool = true
var _storm_phase: float = 0.0
var _mounted_ship: Ship = null
var _table_station: Station = null


func _ready() -> void:
	_auto_detect_parent_ship()
	_build_viewport()
	_build_surface_mesh()
	_refresh_islands_cache()
	refresh_now()


## Mount this MapTableView cleanly onto `ship`'s `MapTable` node in `sloop.glb`.
## Returns true if mounted onto a valid Ship.
func mount_to_ship(ship: Ship) -> bool:
	if ship == null:
		return false
	_mounted_ship = ship
	tracked_ship = ship
	_table_station = ship.get_station(&"map_table")
	surface_height_y = SHIP_TABLE_TOP_Y

	var target_parent: Node = ship.find_child("MapTable", true, false)
	if target_parent == null:
		target_parent = ship.find_child("Station_MapTable", true, false)
	if target_parent == null:
		target_parent = ship
		position = Vector3(0.0, -0.85, 2.5)
	else:
		position = Vector3.ZERO
	rotation = Vector3.ZERO

	if get_parent() != target_parent:
		if get_parent() != null:
			get_parent().remove_child(self)
		target_parent.add_child(self)

	_apply_surface_height()
	view_center = Vector2(ship.global_position.x, ship.global_position.z - 420.0)
	_dirty = true
	if is_node_ready():
		refresh_now()
	return true


## Provide an Archipelago node (`get_map_data()`), Array of island dicts, or null for auto-discovery.
func set_archipelago_data(source: Variant) -> void:
	archipelago_source = source
	_refresh_islands_cache()
	_dirty = true


## Highlight an active voyage target on the chart with a crimson dashed ring.
func set_voyage_target(world_pos: Vector3) -> void:
	active_voyage_target = world_pos
	_dirty = true


## Pan the chart view center by `delta_world` (world XZ metres).
func pan(delta_world: Vector2) -> void:
	view_center += delta_world
	_dirty = true
	view_changed.emit(view_center, view_span)


## Zoom the chart span by `factor` (< 1 zooms in, > 1 zooms out).
func zoom_by(factor: float) -> void:
	if factor <= 0.0:
		return
	view_span = clampf(view_span * factor, MIN_SPAN, MAX_SPAN)
	_dirty = true
	view_changed.emit(view_center, view_span)


## Place an ink pin marker on the nautical chart at `world_pos`.
func place_marker(world_pos: Vector3) -> void:
	markers.append(world_pos)
	_dirty = true
	marker_placed.emit(world_pos)


## Remove all player-placed chart markers.
func clear_markers() -> void:
	markers.clear()
	_dirty = true


## Return the live SubViewport texture applied to the table surface.
func get_chart_texture() -> ViewportTexture:
	return _viewport.get_texture() if _viewport != null else null


## Return how many islands are currently plotted on the chart.
func get_island_count() -> int:
	return _islands_cache.size()


## Return normalized island entries currently rendered on the chart.
func get_plotted_islands() -> Array[Dictionary]:
	return _islands_cache


## Convert a world XZ position to SubViewport pixel coordinates.
func world_to_chart(world_pos: Vector3) -> Vector2:
	var half_w := view_span * 0.5
	var aspect := float(CHART_RES.y) / float(CHART_RES.x)
	var half_h := half_w * aspect
	var u := (world_pos.x - (view_center.x - half_w)) / maxf(view_span, 1.0)
	var v := (world_pos.z - (view_center.y - half_h)) / maxf(view_span * aspect, 1.0)
	return Vector2(u * float(CHART_RES.x), v * float(CHART_RES.y))


## Convert SubViewport pixel coordinates back to world XZ coordinates.
func chart_to_world(px: Vector2) -> Vector3:
	var aspect := float(CHART_RES.y) / float(CHART_RES.x)
	var u := px.x / float(CHART_RES.x) - 0.5
	var v := px.y / float(CHART_RES.y) - 0.5
	return Vector3(view_center.x + u * view_span, 0.0, view_center.y + v * (view_span * aspect))


## Return the tracked ship's current pixel coordinate on the chart (or Vector2.INF if untracked).
func get_ship_chart_pos() -> Vector2:
	if tracked_ship == null or not is_instance_valid(tracked_ship):
		return Vector2.INF
	return world_to_chart(tracked_ship.global_position)


## Force an immediate chart redraw right now (bypasses the 0.15 s throttle).
func refresh_now() -> void:
	_update_accum = 0.0
	_dirty = false
	_refresh_islands_cache()
	_record_trail_point()
	if _canvas != null:
		_canvas.snapshot = _build_draw_snapshot()
		_canvas.queue_redraw()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _process(delta: float) -> void:
	_storm_phase = fmod(_storm_phase + delta * 1.1, TAU)
	_poll_table_station_controls(delta)
	_update_accum += delta
	if _dirty or _update_accum >= UPDATE_INTERVAL:
		refresh_now()


func _poll_table_station_controls(delta: float) -> void:
	if _table_station == null or not is_instance_valid(_table_station):
		return
	var occ := _table_station.occupant
	if occ == null or not is_instance_valid(occ):
		return
	# Only let the local player pan/zoom the table when standing at Station_MapTable.
	var has_pc := false
	for c in occ.get_children():
		if c is PlayerController and (c as PlayerController).input_enabled and not (c as PlayerController).look_paused:
			has_pc = true
			break
	if not has_pc:
		return
	var ax := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward")
	)
	if ax.length_squared() > 0.01:
		pan(ax * view_span * 0.45 * delta)
	if Input.is_action_pressed(&"primary"):
		zoom_by(1.0 - 0.85 * delta)
	elif Input.is_action_pressed(&"secondary"):
		zoom_by(1.0 + 0.85 * delta)


func _auto_detect_parent_ship() -> void:
	var anc := get_parent()
	while anc != null:
		if anc is Ship:
			_mounted_ship = anc as Ship
			if tracked_ship == null:
				tracked_ship = _mounted_ship
			_table_station = _mounted_ship.get_station(&"map_table")
			if is_zero_approx(surface_height_y):
				surface_height_y = SHIP_TABLE_TOP_Y
			break
		anc = anc.get_parent()


func _build_viewport() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "ChartViewport"
	_viewport.size = CHART_RES
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	_canvas = _ChartCanvas.new()
	_canvas.name = "ChartCanvas"
	_canvas.size = Vector2(CHART_RES)
	_canvas.custom_minimum_size = Vector2(CHART_RES)
	_viewport.add_child(_canvas)


func _build_surface_mesh() -> void:
	if _surface_mesh != null:
		return
	_frame_root = Node3D.new()
	_frame_root.name = "ChartPlate"
	add_child(_frame_root)

	var pm := PlaneMesh.new()
	pm.size = Vector2(CHART_WIDTH_M, CHART_DEPTH_M)
	_surface_mat = StandardMaterial3D.new()
	_surface_mat.albedo_color = Color.WHITE
	_surface_mat.roughness = 0.82
	_surface_mat.metallic = 0.0
	var vp_tex := _viewport.get_texture()
	_surface_mat.albedo_texture = vp_tex
	# Subtle warm readability glow so the map table stays crisp in the candle-lit hold.
	_surface_mat.emission_enabled = true
	_surface_mat.emission = Color.WHITE
	_surface_mat.emission_texture = vp_tex
	_surface_mat.emission_energy_multiplier = 0.24

	_surface_mesh = MeshInstance3D.new()
	_surface_mesh.name = "ChartSurface"
	_surface_mesh.mesh = pm
	_surface_mesh.material_override = _surface_mat
	_surface_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame_root.add_child(_surface_mesh)

	if build_frame:
		_build_wooden_frame_and_tacks()
	_apply_surface_height()


func _build_wooden_frame_and_tacks() -> void:
	# Backing board & beveled oak molding sitting flush on the map table top (covers baked paper cleanly).
	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	ToolMeshes._append_beveled_box(st_wood, Vector3(CHART_WIDTH_M + 0.09, 0.026, CHART_DEPTH_M + 0.09), 0.005,
		Transform3D(Basis.IDENTITY, Vector3(0.0, -0.014, 0.0)))
	st_wood.generate_normals()
	var board := MeshInstance3D.new()
	board.name = "ChartBacking"
	board.mesh = st_wood.commit()
	board.material_override = ToolMeshes._make_mat(ToolMeshes.COL_OAK_DARK, 0.78, 0.04)
	_frame_root.add_child(board)

	# Four gleaming brass corner pins + nautical divider compass resting on the chart edge.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := CHART_WIDTH_M * 0.5 - 0.022
	var hz := CHART_DEPTH_M * 0.5 - 0.022
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			ToolMeshes._append_lathe(st_brass, [
				Vector2(0.0, 0.0),
				Vector2(0.012, 0.0),
				Vector2(0.012, 0.004),
				Vector2(0.007, 0.008),
				Vector2(0.0, 0.009),
			], 8, Transform3D(Basis.IDENTITY, Vector3(sx * hx, 0.0, sz * hz)))
	# Small decorative brass dividers lying on the right edge of the oak border.
	ToolMeshes._append_tube(st_brass, [Vector3(hx + 0.032, 0.007, -0.10), Vector3(hx + 0.015, 0.006, 0.06)], 0.0035, 6, true)
	ToolMeshes._append_tube(st_brass, [Vector3(hx + 0.032, 0.007, -0.10), Vector3(hx + 0.048, 0.006, 0.05)], 0.0035, 6, true)
	st_brass.generate_normals()
	var pins := MeshInstance3D.new()
	pins.name = "BrassPins"
	pins.mesh = st_brass.commit()
	pins.material_override = ToolMeshes._make_mat(ToolMeshes.COL_BRASS, 0.25, 0.88)
	_frame_root.add_child(pins)


func _apply_surface_height() -> void:
	if _frame_root != null:
		_frame_root.position.y = surface_height_y


func _refresh_islands_cache() -> void:
	var src: Variant = archipelago_source
	if src == null and is_inside_tree():
		var arch_nodes := get_tree().get_nodes_in_group(&"archipelago")
		if not arch_nodes.is_empty():
			src = arch_nodes[0]
		else:
			var isl_nodes := get_tree().get_nodes_in_group(&"islands")
			if not isl_nodes.is_empty():
				src = isl_nodes

	var raw_list: Array[Dictionary] = []
	if src is Object and (src as Object).has_method(&"get_map_data"):
		var data: Variant = (src as Object).call(&"get_map_data")
		if data is Array:
			raw_list = _normalize_island_array(data as Array)
	elif src is Array:
		raw_list = _normalize_island_array(src as Array)

	if raw_list.is_empty():
		raw_list = _normalize_island_array(VoyageComposer.default_archipelago_roster())

	var discovered_list: Array = []
	if Game != null and Game.profile != null and Game.profile.data.has("discoveries"):
		discovered_list = Game.profile.data["discoveries"] as Array

	for d in raw_list:
		var id_str := String(d["id"])
		var is_outpost: bool = (d["kind"] == &"outpost")
		var explicit_disc := bool(d.get("discovered", false))
		d["discovered"] = explicit_disc or is_outpost or discovered_list.has(id_str)

	_islands_cache = raw_list


func _normalize_island_array(arr: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in arr:
		if item is Dictionary:
			var d: Dictionary = item
			var id := StringName(String(d.get("id", d.get("island_id", "island_%d" % out.size()))))
			var pos_v: Variant = d.get("position", Vector3.ZERO)
			var pos := pos_v as Vector3 if pos_v is Vector3 else Vector3.ZERO
			var rad := float(d.get("radius", 95.0))
			var contour_v: Variant = d.get("contour", PackedVector2Array())
			var contour := PackedVector2Array()
			if contour_v is PackedVector2Array:
				contour = contour_v as PackedVector2Array
			elif contour_v is Array:
				for p in (contour_v as Array):
					if p is Vector2:
						contour.append(p as Vector2)
			out.append({
				"id": id,
				"name": String(d.get("name", d.get("display_name", String(id).replace("_", " ").capitalize()))),
				"kind": StringName(String(d.get("kind", &"treasure_island"))),
				"position": pos,
				"radius": rad,
				"contour": contour,
				"discovered": bool(d.get("discovered", false)),
			})
		elif item is Node:
			var n := item as Node
			var id_v: Variant = n.get(&"island_id")
			if id_v == null:
				id_v = n.get(&"id")
			var id := StringName(String(id_v if id_v != null else n.name))
			var nm_v: Variant = n.get(&"display_name")
			if nm_v == null:
				nm_v = n.get(&"island_name")
			if nm_v == null and n.has_meta("display_name"):
				nm_v = n.get_meta("display_name")
			var kind_v: Variant = n.get(&"kind")
			var rad_v: Variant = n.get(&"radius")
			var pos := (n as Node3D).global_position if n is Node3D and n.is_inside_tree() else Vector3.ZERO
			out.append({
				"id": id,
				"name": String(nm_v if nm_v != null else n.name),
				"kind": StringName(String(kind_v if kind_v != null else &"treasure_island")),
				"position": pos,
				"radius": float(rad_v) if (rad_v is float or rad_v is int) else 95.0,
				"contour": PackedVector2Array(),
				"discovered": bool(n.get(&"discovered")) if n.get(&"discovered") != null else false,
			})
	return out


func _record_trail_point() -> void:
	if tracked_ship == null or not is_instance_valid(tracked_ship):
		return
	var p := Vector2(tracked_ship.global_position.x, tracked_ship.global_position.z)
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(p) > 22.0:
		_trail.append(p)
		if _trail.size() > MAX_TRAIL_POINTS:
			_trail.remove_at(0)


func _build_draw_snapshot() -> Dictionary:
	var ship_pos := Vector3.INF
	var ship_heading := 0.0
	if tracked_ship != null and is_instance_valid(tracked_ship):
		ship_pos = tracked_ship.global_position
		var fwd := -tracked_ship.global_basis.z
		ship_heading = atan2(fwd.x, fwd.z)

	# Active voyage target (explicit or inferred from VoyageManager).
	var target_pos := active_voyage_target
	var target_label := ""
	if not target_pos.is_finite() and voyage_manager != null and voyage_manager.has_active_voyage():
		var v := voyage_manager.active_voyage
		var st := voyage_manager.get_current_stage()
		var tid := StringName(String(st.get("target_id", v.get("target_island_id", &""))))
		for isl in _islands_cache:
			if isl["id"] == tid:
				target_pos = isl["position"] as Vector3
				target_label = String(isl["name"])
				break

	# Merge explicit wrecks + WorldDirector salvage wrecks.
	var wrecks: Array[Vector3] = []
	for w in salvage_wrecks:
		wrecks.append(w)
	if world_director != null:
		for wdict in world_director.salvage_wrecks:
			var wp: Variant = wdict.get("position", null)
			if wp is Vector3:
				wrecks.append(wp as Vector3)

	return {
		"view_center": view_center,
		"view_span": view_span,
		"islands": _islands_cache,
		"ship_pos": ship_pos,
		"ship_heading": ship_heading,
		"trail": _trail.duplicate(),
		"target_pos": target_pos,
		"target_label": target_label,
		"markers": markers.duplicate(),
		"wrecks": wrecks,
		"storm_intensity": Weather.storm_intensity if Weather != null else 0.0,
		"storm_center": Weather.storm_center if Weather != null else Vector3.ZERO,
		"storm_radius": Weather.storm_radius if Weather != null else 0.0,
		"storm_phase": _storm_phase,
		"wind_heading": Weather.wind_heading if Weather != null else 0.0,
	}


# ==============================================================================
# Inner SubViewport 2D parchment chart renderer
# ==============================================================================

class _ChartCanvas extends Control:
	const COL_PARCHMENT := Color(0.89, 0.82, 0.67)
	const COL_VIGNETTE := Color(0.71, 0.59, 0.40, 0.45)
	const COL_GRID := Color(0.45, 0.35, 0.22, 0.30)
	const COL_RHUMB := Color(0.48, 0.37, 0.24, 0.16)
	const COL_INK := Color(0.22, 0.14, 0.09, 0.96)
	const COL_INK_SOFT := Color(0.36, 0.26, 0.16, 0.72)
	const COL_LAND := Color(0.75, 0.71, 0.49, 0.94)
	const COL_LAND_CORE := Color(0.62, 0.64, 0.42, 0.85)
	const COL_GHOST_LAND := Color(0.76, 0.68, 0.53, 0.46)
	const COL_COAST_WASH := Color(0.42, 0.56, 0.54, 0.34)
	const COL_CRIMSON := Color(0.78, 0.12, 0.10, 0.96)
	const COL_GOLD := Color(0.86, 0.65, 0.20, 1.0)
	const COL_STORM := Color(0.26, 0.32, 0.38, 0.62)

	const FONT_PATH := "res://assets/generated/ui/scoundrel_font.fnt"
	var snapshot: Dictionary = {}
	var _chart_font: Font = null

	func _get_font() -> Font:
		if _chart_font != null:
			return _chart_font
		if ResourceLoader.exists(FONT_PATH):
			var loaded := load(FONT_PATH) as Font
			if loaded != null:
				_chart_font = loaded
				return _chart_font
		_chart_font = ThemeDB.fallback_font
		return _chart_font

	func _w2c(world_xz: Vector2) -> Vector2:
		var vc: Vector2 = snapshot.get("view_center", Vector2.ZERO)
		var span: float = maxf(float(snapshot.get("view_span", 2800.0)), 1.0)
		var aspect := size.y / maxf(size.x, 1.0)
		var half_w := span * 0.5
		var half_h := half_w * aspect
		var u := (world_xz.x - (vc.x - half_w)) / span
		var v := (world_xz.y - (vc.y - half_h)) / (span * aspect)
		return Vector2(u * size.x, v * size.y)

	func _world_scale() -> float:
		var span: float = maxf(float(snapshot.get("view_span", 2800.0)), 1.0)
		return size.x / span

	func _draw() -> void:
		if snapshot.is_empty():
			return
		var font := _get_font()
		var w := size.x
		var h := size.y

		# 1. Warm aged parchment sheet & edge vignette bands.
		draw_rect(Rect2(Vector2.ZERO, size), COL_PARCHMENT, true)
		var edge := 38.0
		draw_rect(Rect2(0, 0, w, edge), COL_VIGNETTE, true)
		draw_rect(Rect2(0, h - edge, w, edge), COL_VIGNETTE, true)
		draw_rect(Rect2(0, edge, edge, h - edge * 2.0), COL_VIGNETTE, true)
		draw_rect(Rect2(w - edge, edge, edge, h - edge * 2.0), COL_VIGNETTE, true)

		# 2. Nautical latitude/longitude ink gridlines (400 m spacing) + margin indices.
		var vc: Vector2 = snapshot["view_center"]
		var span: float = float(snapshot["view_span"])
		var aspect := h / maxf(w, 1.0)
		var step := 400.0 if span > 1400.0 else 200.0
		var x_start := floorf((vc.x - span * 0.5) / step) * step
		var x_end := vc.x + span * 0.5
		var gx := x_start
		while gx <= x_end:
			var px := _w2c(Vector2(gx, vc.y)).x
			if px > 24.0 and px < w - 24.0:
				draw_line(Vector2(px, 24.0), Vector2(px, h - 24.0), COL_GRID, 1.2, true)
				if font != null:
					var letter := char(65 + posmod(int(roundf(gx / step)) + 8, 26))
					draw_string(font, Vector2(px - 5.0, 20.0), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, COL_INK_SOFT)
			gx += step

		var z_start := floorf((vc.y - span * aspect * 0.5) / step) * step
		var z_end := vc.y + span * aspect * 0.5
		var gz := z_start
		while gz <= z_end:
			var py := _w2c(Vector2(vc.x, gz)).y
			if py > 24.0 and py < h - 24.0:
				draw_line(Vector2(24.0, py), Vector2(w - 24.0, py), COL_GRID, 1.2, true)
				if font != null:
					var num_lbl := str(posmod(int(roundf(gz / step)) + 10, 20) + 1)
					draw_string(font, Vector2(7.0, py + 5.0), num_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_INK_SOFT)
			gz += step

		# 3. Faint rhumb lines radiating from the decorative compass rose.
		var rose_c := Vector2(w - 108.0, h - 104.0)
		for i in 16:
			var a := float(i) / 16.0 * TAU
			draw_line(rose_c, rose_c + Vector2(cos(a), sin(a)) * 1200.0, COL_RHUMB, 1.0, true)

		# 4. Active storm cell swirl (if Weather.storm_intensity > 0).
		var storm_int: float = float(snapshot.get("storm_intensity", 0.0))
		if storm_int > 0.01:
			var sc: Vector3 = snapshot["storm_center"]
			var sr: float = float(snapshot["storm_radius"]) * _world_scale()
			var spx := _w2c(Vector2(sc.x, sc.z))
			_draw_storm_swirl(spx, maxf(sr, 28.0), storm_int, float(snapshot.get("storm_phase", 0.0)))

		# 5. Archipelago islands (discovered named in sepia ink; undiscovered faint silhouettes).
		var px_per_m := _world_scale()
		var islands: Array = snapshot.get("islands", [])
		for isl: Dictionary in islands:
			_draw_island(isl, px_per_m, font)

		# 6. Active voyage target crimson dashed ring!
		var tpos: Vector3 = snapshot.get("target_pos", Vector3.INF)
		if tpos.is_finite():
			var tp := _w2c(Vector2(tpos.x, tpos.z))
			_draw_dashed_circle(tp, 44.0, COL_CRIMSON, 3.2, 18)
			_draw_dashed_circle(tp, 50.0, Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, 0.45), 1.5, 22)

		# 7. Salvage wreck X markers.
		for wp: Vector3 in snapshot.get("wrecks", []):
			var wpx := _w2c(Vector2(wp.x, wp.z))
			_draw_wreck_marker(wpx, font)

		# 8. Player-placed chart markers.
		for mp: Vector3 in snapshot.get("markers", []):
			var mpx := _w2c(Vector2(mp.x, mp.z))
			draw_arc(mpx, 14.0, 0.0, TAU, 24, COL_CRIMSON, 2.8, true)
			draw_circle(mpx, 4.5, COL_CRIMSON)

		# 9. Ship wake breadcrumb trail + Player ship silhouette & live heading arrow!
		var trail: Array = snapshot.get("trail", [])
		for i in range(trail.size() - 1):
			var a := _w2c(trail[i] as Vector2)
			var b := _w2c(trail[i + 1] as Vector2)
			draw_line(a, b, Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.32), 2.0, true)

		var spos: Vector3 = snapshot.get("ship_pos", Vector3.INF)
		if spos.is_finite():
			var ship_px := _w2c(Vector2(spos.x, spos.z))
			_draw_ship_marker(ship_px, float(snapshot.get("ship_heading", 0.0)))

		# 10. Decorative nautical compass rose & crisp double ink chart border.
		_draw_compass_rose(rose_c, 58.0, font)
		_draw_chart_border(w, h)

	func _draw_island(isl: Dictionary, px_per_m: float, font: Font) -> void:
		var pos: Vector3 = isl["position"]
		var center := _w2c(Vector2(pos.x, pos.z))
		var r_world := maxf(float(isl.get("radius", 95.0)), 40.0)
		var r_px := clampf(r_world * px_per_m, 14.0, 120.0)
		var discovered := bool(isl.get("discovered", false))
		var nm: String = String(isl.get("name", "Island"))
		var kind: StringName = isl.get("kind", &"treasure_island")

		var contour: PackedVector2Array = isl.get("contour", PackedVector2Array())
		if contour.size() < 3:
			contour = MapPainter.generate_fallback_contour(nm, r_world)
		var poly := PackedVector2Array()
		poly.resize(contour.size())
		var wash := PackedVector2Array()
		wash.resize(contour.size())
		var inner := PackedVector2Array()
		inner.resize(contour.size())
		var sc := r_px / r_world
		for i in contour.size():
			var d := contour[i] * sc
			poly[i] = center + d
			wash[i] = center + d * 1.18
			inner[i] = center + d * 0.58

		if discovered:
			draw_colored_polygon(wash, COL_COAST_WASH)
			draw_colored_polygon(poly, COL_LAND)
			draw_colored_polygon(inner, COL_LAND_CORE)
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, COL_INK, 2.2, true)
			# Small icon flourish for outposts and forts.
			if kind == &"outpost":
				draw_circle(center, 4.5, COL_GOLD)
				draw_arc(center, 6.5, 0.0, TAU, 14, COL_INK, 1.6, true)
			elif kind == &"fort":
				draw_rect(Rect2(center - Vector2(4.5, 4.5), Vector2(9.0, 9.0)), COL_CRIMSON, true)
			if font != null:
				var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
				draw_string(font, Vector2(center.x - tw * 0.5, center.y + r_px + 17.0),
					nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_INK)
		else:
			draw_colored_polygon(poly, COL_GHOST_LAND)
			var n := poly.size()
			for i in range(0, n, 2):
				draw_line(poly[i], poly[(i + 1) % n], COL_INK_SOFT, 1.5, true)
			if font != null:
				draw_string(font, Vector2(center.x - 4.0, center.y + 5.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_INK_SOFT)

	func _draw_ship_marker(center: Vector2, heading_rad: float) -> void:
		# heading_rad = atan2(fwd.x, fwd.z), so forward vector in 2D canvas is (sin(h), cos(h)).
		var fwd := Vector2(sin(heading_rad), cos(heading_rad))
		var right := Vector2(fwd.y, -fwd.x)
		# Heading sight arrow ahead of the bow.
		var arrow_tip := center + fwd * 30.0
		draw_line(center + fwd * 14.0, arrow_tip, COL_CRIMSON, 2.8, true)
		draw_line(arrow_tip, arrow_tip - fwd * 7.5 + right * 5.0, COL_CRIMSON, 2.6, true)
		draw_line(arrow_tip, arrow_tip - fwd * 7.5 - right * 5.0, COL_CRIMSON, 2.6, true)
		# Crisp top-down sloop silhouette.
		var hull := PackedVector2Array([
			center + fwd * 15.0,
			center + fwd * 5.0 + right * 7.5,
			center - fwd * 11.0 + right * 6.5,
			center - fwd * 13.0,
			center - fwd * 11.0 - right * 6.5,
			center + fwd * 5.0 - right * 7.5,
		])
		draw_colored_polygon(hull, COL_INK)
		var hull_ring := hull.duplicate()
		hull_ring.append(hull[0])
		draw_polyline(hull_ring, COL_GOLD, 1.8, true)
		# Cross-yard sail bar across midships.
		draw_line(center + fwd * 2.0 - right * 11.0, center + fwd * 2.0 + right * 11.0, COL_PARCHMENT, 3.0, true)
		draw_circle(center + fwd * 2.0, 2.5, COL_GOLD)

	func _draw_storm_swirl(center: Vector2, radius: float, intensity: float, phase: float) -> void:
		var col_fill := Color(COL_STORM.r, COL_STORM.g, COL_STORM.b, 0.16 * intensity)
		var col_line := Color(COL_STORM.r, COL_STORM.g, COL_STORM.b, 0.62 * intensity)
		draw_circle(center, radius, col_fill)
		_draw_dashed_circle(center, radius, col_line, 2.2, 24)
		# Three spiral cyclone arms swirling smoothly.
		for arm in 3:
			var pts := PackedVector2Array()
			var base_a := phase + float(arm) * TAU / 3.0
			for step in 16:
				var t := float(step) / 15.0
				var r := radius * 0.12 + t * radius * 0.78
				var a := base_a + t * 2.6
				pts.append(center + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts, col_line, 2.4, true)

	func _draw_wreck_marker(pos: Vector2, font: Font) -> void:
		var r := 9.0
		draw_line(pos + Vector2(-r, -r), pos + Vector2(r, r), COL_CRIMSON, 3.2, true)
		draw_line(pos + Vector2(-r, r), pos + Vector2(r, -r), COL_CRIMSON, 3.2, true)
		if font != null:
			draw_string(font, pos + Vector2(-22.0, 22.0), "WRECK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_CRIMSON)

	func _draw_dashed_circle(center: Vector2, radius: float, col: Color, width: float, dashes: int) -> void:
		var seg := TAU / float(dashes)
		for i in dashes:
			var a0 := float(i) * seg
			var a1 := a0 + seg * 0.58
			draw_arc(center, radius, a0, a1, 6, col, width, true)

	func _draw_compass_rose(center: Vector2, r: float, font: Font) -> void:
		draw_circle(center, r * 0.72, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.85))
		draw_arc(center, r * 0.72, 0.0, TAU, 36, COL_INK, 2.0, true)
		draw_arc(center, r * 0.56, 0.0, TAU, 36, COL_INK_SOFT, 1.2, true)
		# Intercardinal points.
		for i in 4:
			var a := (float(i) + 0.5) * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			var s := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([center, center + d * (r * 0.68), center + s * (r * 0.12)]), COL_INK_SOFT)
			draw_colored_polygon(PackedVector2Array([center, center + d * (r * 0.68), center - s * (r * 0.12)]), COL_PARCHMENT)
		# Cardinal points (North highlighted crimson!).
		var dirs := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
		var labels := ["N", "E", "S", "W"]
		for i in 4:
			var d: Vector2 = dirs[i]
			var s := Vector2(-d.y, d.x)
			var c_hi := COL_CRIMSON if i == 0 else COL_INK
			draw_colored_polygon(PackedVector2Array([center, center + d * r, center + s * (r * 0.18)]), c_hi)
			draw_colored_polygon(PackedVector2Array([center, center + d * r, center - s * (r * 0.18)]), COL_GOLD if i == 0 else COL_INK_SOFT)
			if font != null:
				var lp := center + d * (r + 14.0) + Vector2(-5.0, 5.0)
				draw_string(font, lp, labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c_hi)
		draw_circle(center, 5.0, COL_GOLD)

	func _draw_chart_border(w: float, h: float) -> void:
		draw_rect(Rect2(12.0, 12.0, w - 24.0, h - 24.0), COL_INK, false, 3.0)
		draw_rect(Rect2(22.0, 22.0, w - 44.0, h - 44.0), COL_INK_SOFT, false, 1.4)
