class_name MapTableView
extends Node3D
## Live diegetic parchment nautical chart rendered onto a SubViewport texture
## and mounted directly on top of a Ship's wooden `MapTable` mesh.
##
## Displays parchment gridlines, decorative compass rose, live wind-direction feather,
## all archipelago islands (discovered named in sepia ink, undiscovered as faint
## silhouettes), player ship silhouette + live heading arrow, sepia course-bearing
## rhumb line & compass readout, active voyage crimson dashed circle, active Weather
## storm cell swirl, live Leviathan & Fort Siege threat stamps, salvage wreck X
## markers, and interactive player-placed pins.
## Throttled to redraw every 0.15 s so it stays ultra-cheap at runtime.

signal marker_placed(world_pos: Vector3)
signal view_changed(center: Vector2, span: float)

const UPDATE_INTERVAL := 0.15
const FAR_UPDATE_INTERVAL := 1.25
const FAR_CAMERA_DIST := 7.5
const ISLAND_CACHE_INTERVAL := 1.5
const CHART_RES := Vector2i(1024, 680)
const CHART_WIDTH_M := 1.08
const CHART_DEPTH_M := 0.70
const SHIP_TABLE_TOP_Y := 0.874
const BRIGANTINE_TABLE_TOP_Y := 0.897
const MIN_SPAN := 900.0
const MAX_SPAN := 4400.0
const ZOOM_STEP_IN := 0.84
const ZOOM_STEP_OUT := 1.19
const GRID_CELL_M := 400.0
const GRID_COLS := 8
const GRID_ROWS := 8
const GRID_ORIGIN_XZ := Vector2(-1600.0, -1600.0)
const COURSE_RAY_LENGTH_M := 550.0
const MAX_TRAIL_POINTS := 48
const PIN_TOGGLE_RADIUS_M := 90.0
const FORT_CLUSTER_RADIUS_M := 160.0
const MPS_TO_KNOTS := 1.94384
const DEFAULT_CARTOUCHE_NAME := "SV SCOUNDREL"

const COMPASS_16: Array[String] = [
	"N", "NNE", "NE", "ENE",
	"E", "ESE", "SE", "SSE",
	"S", "SSW", "SW", "WSW",
	"W", "WNW", "NW", "NNW",
]

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
var _cache_accum: float = 0.0
var _dirty: bool = true
var _storm_phase: float = 0.0
var _mounted_ship: Ship = null
var _table_station: Station = null
var _station_player_active: bool = false
var _jump_was_down: bool = false


func _enter_tree() -> void:
	add_to_group(&"map_tables")
	if _surface_mat != null and _viewport != null and is_instance_valid(_viewport):
		var vp_tex := _viewport.get_texture()
		_surface_mat.albedo_texture = vp_tex
		_surface_mat.emission_texture = vp_tex
		_dirty = true


func _ready() -> void:
	_auto_detect_parent_ship()
	_build_viewport()
	_build_surface_mesh()
	_refresh_islands_cache()
	refresh_now()


func _exit_tree() -> void:
	if _surface_mat != null:
		_surface_mat.albedo_texture = null
		_surface_mat.emission_texture = null
	if _canvas != null and is_instance_valid(_canvas):
		_canvas._chart_font = null
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Mount this MapTableView cleanly onto `ship`'s `MapTable` node in `sloop.glb`.
## Returns true if mounted onto a valid Ship.
func mount_to_ship(ship: Ship) -> bool:
	if ship == null:
		return false
	_mounted_ship = ship
	tracked_ship = ship
	_table_station = ship.get_station(&"map_table")
	surface_height_y = BRIGANTINE_TABLE_TOP_Y if ship.ship_class == &"brigantine" else SHIP_TABLE_TOP_Y

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


## Zoom the chart span by `factor` (< 1 zooms in, > 1 zooms out), clamped to [MIN_SPAN, MAX_SPAN].
func zoom_by(factor: float) -> void:
	if factor <= 0.0:
		return
	var next_span := clampf(view_span * factor, MIN_SPAN, MAX_SPAN)
	if is_equal_approx(next_span, view_span):
		return
	view_span = next_span
	_dirty = true
	view_changed.emit(view_center, view_span)


## Smoothly zoom the chart view inward (smaller world span), clamped to [MIN_SPAN, MAX_SPAN].
func zoom_in(step_factor: float = ZOOM_STEP_IN) -> void:
	zoom_by(clampf(step_factor, 0.25, 0.99))


## Smoothly zoom the chart view outward (larger world span), clamped to [MIN_SPAN, MAX_SPAN].
func zoom_out(step_factor: float = ZOOM_STEP_OUT) -> void:
	zoom_by(clampf(step_factor, 1.01, 4.0))


## Place an ink pin marker on the nautical chart at `world_pos`.
func place_marker(world_pos: Vector3) -> void:
	markers.append(world_pos)
	_dirty = true
	marker_placed.emit(world_pos)


## Drop a pin at `world_pos`, or clear the nearest existing pin within `toggle_radius_m`.
## Returns true when a new pin was dropped, or false when an existing nearby pin was cleared.
func toggle_marker_at(world_pos: Vector3, toggle_radius_m: float = PIN_TOGGLE_RADIUS_M) -> bool:
	var nearest_idx := -1
	var nearest_d := toggle_radius_m
	var p2 := Vector2(world_pos.x, world_pos.z)
	for i in markers.size():
		var m2 := Vector2(markers[i].x, markers[i].z)
		var d := p2.distance_to(m2)
		if d <= nearest_d:
			nearest_d = d
			nearest_idx = i
	if nearest_idx >= 0:
		markers.remove_at(nearest_idx)
		_dirty = true
		return false
	place_marker(world_pos)
	return true


## Remove all player-placed chart markers.
func clear_markers() -> void:
	markers.clear()
	_dirty = true


## True when at least one player-placed chart pin marker is active.
func has_active_pin() -> bool:
	return not markers.is_empty()


## Return the newest player-placed chart pin world position, or Vector3.ZERO when unset.
func get_active_pin() -> Vector3:
	if markers.is_empty():
		return Vector3.ZERO
	return markers[markers.size() - 1]


## Convert a world XZ position to a strict-ASCII nautical grid square ("A1".."H8")
## aligned to fixed 400 m cells spanning the archipelago.
static func world_to_grid_coord(world_pos: Vector3) -> String:
	if not world_pos.is_finite():
		return "E5"
	var col := clampi(floori((world_pos.x - GRID_ORIGIN_XZ.x) / GRID_CELL_M), 0, GRID_COLS - 1)
	var row := clampi(floori((world_pos.z - GRID_ORIGIN_XZ.y) / GRID_CELL_M), 0, GRID_ROWS - 1)
	return "%s%d" % [char(65 + col), row + 1]


## Format the 16-point compass bearing and horizontal distance between two world positions.
## Uses Sea of Scoundrels world axes (-Z North, +X East), e.g. "NNE  480 m".
static func format_course_bearing(from_pos: Vector3, to_pos: Vector3) -> String:
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.5:
		return "N  0 m"
	var ang := fposmod(atan2(dx, -dz), TAU)
	var idx := int(roundf(ang / (TAU / 16.0))) % 16
	return "%s  %d m" % [COMPASS_16[idx], int(roundf(dist))]


## Format strict-ASCII compass bearing, distance, and nautical grid square for a plotted
## course or chart pin (e.g. "NE 420 m (E3)").
static func format_pin_course_tag(from_pos: Vector3, to_pos: Vector3) -> String:
	var grid := world_to_grid_coord(to_pos)
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.5:
		return "N 0 m (%s)" % grid
	var ang := fposmod(atan2(dx, -dz), TAU)
	var idx := int(roundf(ang / (TAU / 16.0))) % 16
	return "%s %d m (%s)" % [COMPASS_16[idx], int(roundf(dist)), grid]


## Format a vessel name as a strict-ASCII uppercase chart cartouche banner (e.g. "SV ABYSSAL DAWN").
static func format_ship_cartouche(raw_name: String) -> String:
	var ascii := ""
	var prev_space := false
	for i in raw_name.length():
		var code := raw_name.unicode_at(i)
		if code >= 32 and code <= 126:
			var ch := char(code)
			if ch == " ":
				if not prev_space and not ascii.is_empty():
					ascii += " "
				prev_space = true
			else:
				ascii += ch
				prev_space = false
	var upper := ascii.strip_edges().to_upper()
	if upper.is_empty():
		return DEFAULT_CARTOUCHE_NAME
	if upper.begins_with("SV "):
		var rest := upper.substr(3).strip_edges()
		return DEFAULT_CARTOUCHE_NAME if rest.is_empty() else ("SV " + rest)
	return "SV " + upper


## Format live wind speed (m/s -> knots) and heading (rad, -Z North, +X East) as strict ASCII,
## e.g. "WIND 19 kt NNE".
static func format_wind_medallion(wind_spd_mps: float, heading_rad: float) -> String:
	var knots := int(roundf(maxf(wind_spd_mps, 0.0) * MPS_TO_KNOTS))
	var ang := fposmod(heading_rad, TAU)
	var idx := int(roundf(ang / (TAU / 16.0))) % 16
	return "WIND %d kt %s" % [knots, COMPASS_16[idx]]


## Return the live strict-ASCII Captain's custom ship name displayed in the chart cartouche.
func get_ship_cartouche_text() -> String:
	var ship_ref: Node3D = tracked_ship if (tracked_ship != null and is_instance_valid(tracked_ship)) else _mounted_ship
	if ship_ref != null and is_instance_valid(ship_ref):
		var raw_v: Variant = ship_ref.get(&"ship_name")
		if raw_v is String and not (raw_v as String).strip_edges().is_empty():
			return format_ship_cartouche(raw_v as String)
	if Game != null and Game.profile != null and Game.profile.has_method(&"get_ship_name"):
		var prof_name := String(Game.profile.call(&"get_ship_name"))
		if not prof_name.strip_edges().is_empty():
			return format_ship_cartouche(prof_name)
	return DEFAULT_CARTOUCHE_NAME


## Return the live strict-ASCII wind knots & 16-point compass readout shown under the wind medallion.
func get_wind_medallion_text() -> String:
	if Weather != null:
		return format_wind_medallion(Weather.local_wind_speed(), Weather.wind_heading)
	var snap := get_last_snapshot()
	return format_wind_medallion(float(snap.get("wind_speed", 8.0)), float(snap.get("wind_heading", 0.0)))


## Return the latest rendered chart draw snapshot (useful for telemetry and tests).
func get_last_snapshot() -> Dictionary:
	return _canvas.snapshot if _canvas != null else {}


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
	_cache_accum = 0.0
	_dirty = false
	_refresh_islands_cache()
	_redraw_chart()


func _redraw_chart() -> void:
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
	_cache_accum += delta
	var interval := UPDATE_INTERVAL
	var offscreen_far := false
	if not _dirty and not _station_player_active and is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var to_table := global_position - cam.global_position
			var dist_sq := to_table.length_squared()
			var facing_away := dist_sq > 1.0 and to_table.normalized().dot(-cam.global_basis.z) < -0.15
			if dist_sq > FAR_CAMERA_DIST * FAR_CAMERA_DIST or facing_away:
				offscreen_far = true
				interval = FAR_UPDATE_INTERVAL
	if offscreen_far:
		if _viewport != null and _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _dirty or _update_accum >= interval:
		_update_accum = 0.0
		var need_cache := _dirty or _islands_cache.is_empty() or _cache_accum >= ISLAND_CACHE_INTERVAL
		_dirty = false
		if need_cache:
			_cache_accum = 0.0
			_refresh_islands_cache()
		_redraw_chart()


func _unhandled_input(event: InputEvent) -> void:
	if not _station_player_active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_in(0.88)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_out(1.14)
				get_viewport().set_input_as_handled()


func _poll_table_station_controls(delta: float) -> void:
	var prev_active := _station_player_active
	_station_player_active = false
	if _table_station == null or not is_instance_valid(_table_station):
		_jump_was_down = false
		if prev_active:
			_dirty = true
		return
	var occ := _table_station.occupant
	if occ == null or not is_instance_valid(occ):
		_jump_was_down = false
		if prev_active:
			_dirty = true
		return
	# Only let the local player pan/zoom/pin the table when standing at Station_MapTable.
	var has_pc := false
	for c in occ.get_children():
		if c is PlayerController and (c as PlayerController).input_enabled and not (c as PlayerController).look_paused:
			has_pc = true
			break
	if not has_pc:
		_jump_was_down = false
		if prev_active:
			_dirty = true
		return

	_station_player_active = true
	if not prev_active:
		_dirty = true

	var ax := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward")
	)
	if ax.length_squared() > 0.01:
		pan(ax * view_span * 0.45 * delta)
	if Input.is_action_pressed(&"primary") or Input.is_action_pressed(&"item_next"):
		zoom_in(clampf(1.0 - 0.90 * delta, 0.5, 0.99))
	elif Input.is_action_pressed(&"secondary") or Input.is_action_pressed(&"item_prev"):
		zoom_out(1.0 + 0.90 * delta)

	var jump_down := Input.is_action_pressed(&"jump")
	if jump_down and not _jump_was_down:
		var added := toggle_marker_at(Vector3(view_center.x, 0.0, view_center.y))
		var pin_sfx := &"map_rustle" if Audio.has_sound(&"map_rustle") else (&"ui_select" if added else &"ui_back")
		Audio.play_sfx(pin_sfx, global_position, -4.0)
	_jump_was_down = jump_down


func _auto_detect_parent_ship() -> void:
	var anc := get_parent()
	while anc != null:
		if anc is Ship:
			_mounted_ship = anc as Ship
			if tracked_ship == null:
				tracked_ship = _mounted_ship
			_table_station = _mounted_ship.get_station(&"map_table")
			if is_zero_approx(surface_height_y):
				surface_height_y = BRIGANTINE_TABLE_TOP_Y if _mounted_ship.ship_class == &"brigantine" else SHIP_TABLE_TOP_Y
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
	_surface_mat.albedo_color = Color(0.92, 0.87, 0.78)
	_surface_mat.roughness = 0.90
	_surface_mat.metallic = 0.0
	var vp_tex := _viewport.get_texture()
	_surface_mat.albedo_texture = vp_tex
	# Subtle warm readability glow so the map table stays crisp without washing out in sunlight.
	_surface_mat.emission_enabled = true
	_surface_mat.emission = Color(0.96, 0.88, 0.72)
	_surface_mat.emission_texture = vp_tex
	_surface_mat.emission_energy_multiplier = 0.06

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
	# Solid beveled dark-oak backing tray sized to completely enclose both sloop & brigantine baked static maps.
	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	ToolMeshes._append_beveled_box(st_wood, Vector3(CHART_WIDTH_M + 0.18, 0.032, CHART_DEPTH_M + 0.14), 0.006,
		Transform3D(Basis.IDENTITY, Vector3(0.01, -0.017, 0.0)))
	st_wood.generate_normals()
	var board := MeshInstance3D.new()
	board.name = "ChartBacking"
	board.mesh = st_wood.commit()
	board.material_override = ToolMeshes._make_mat(ToolMeshes.COL_OAK_DARK, 0.80, 0.04)
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
		var is_outpost: bool = bool(d.get("is_outpost", false)) or (d["kind"] == &"outpost")
		var explicit_disc := bool(d.get("discovered", false))
		d["is_outpost"] = is_outpost
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
			var kind := StringName(String(d.get("kind", &"treasure_island")))
			var archetype := StringName(String(d.get("archetype", &"")))
			var is_outpost := bool(d.get("is_outpost", false)) or (kind == &"outpost")
			var contour_v: Variant = d.get("contour", d.get("contour_points", PackedVector2Array()))
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
				"kind": kind,
				"archetype": archetype,
				"is_outpost": is_outpost,
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
			var kind := StringName(String(kind_v if kind_v != null else &"treasure_island"))
			var arch_v: Variant = n.get(&"archetype")
			var archetype := StringName(String(arch_v if arch_v != null else &""))
			var out_v: Variant = n.get(&"is_outpost")
			var is_outpost := (out_v is bool and bool(out_v)) or (kind == &"outpost")
			var rad_v: Variant = n.get(&"radius")
			var pos := (n as Node3D).global_position if n is Node3D and n.is_inside_tree() else Vector3.ZERO
			out.append({
				"id": id,
				"name": String(nm_v if nm_v != null else n.name),
				"kind": kind,
				"archetype": archetype,
				"is_outpost": is_outpost,
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
	var heading_ray_end := Vector3.INF
	if tracked_ship != null and is_instance_valid(tracked_ship):
		ship_pos = tracked_ship.global_position
		var fwd := -tracked_ship.global_basis.z
		ship_heading = atan2(fwd.x, fwd.z)
		heading_ray_end = Vector3(
			ship_pos.x + sin(ship_heading) * COURSE_RAY_LENGTH_M,
			0.0,
			ship_pos.z + cos(ship_heading) * COURSE_RAY_LENGTH_M
		)

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

	# Determine active course-bearing target (newest player pin overrides voyage target).
	var course_target := Vector3.INF
	var course_from_pin := false
	if not markers.is_empty():
		course_target = markers[markers.size() - 1]
		course_from_pin = true
	elif target_pos.is_finite():
		course_target = target_pos
	var course_bearing_text := ""
	var course_grid_coord := ""
	if ship_pos.is_finite() and course_target.is_finite():
		course_grid_coord = world_to_grid_coord(course_target)
		course_bearing_text = format_pin_course_tag(ship_pos, course_target)

	# Scan live world entities: Leviathans, FortBatteries, SunkenShipwrecks, Megalodons, Rival Ships.
	var leviathans: Array[Vector3] = []
	var fort_sieges: Array[Vector3] = []
	var sunken_shipwrecks: Array[Vector3] = []
	var megalodons: Array[Vector3] = []
	var rival_ships: Array[Dictionary] = []
	if is_inside_tree():
		var seen_lev: Dictionary = {}
		for grp: StringName in [&"world_events", &"leviathan", &"bosses"]:
			for node in get_tree().get_nodes_in_group(grp):
				if not (node is Node3D) or not is_instance_valid(node):
					continue
				if node.is_in_group(&"megalodons"):
					continue
				var nid := node.get_instance_id()
				if seen_lev.has(nid):
					continue
				var is_lev := (node is Leviathan) \
					or node.is_in_group(&"leviathan") \
					or node.is_in_group(&"bosses")
				if not is_lev:
					continue
				if node.has_method(&"is_defeated") and bool(node.call(&"is_defeated")):
					continue
				var dead_v: Variant = node.get(&"dead")
				if dead_v is bool and bool(dead_v):
					continue
				seen_lev[nid] = true
				leviathans.append((node as Node3D).global_position)

		for node in get_tree().get_nodes_in_group(&"sunken_shipwrecks"):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			if node.has_method(&"is_cleared") and bool(node.call(&"is_cleared")):
				continue
			var clr_v: Variant = node.get(&"cleared")
			if clr_v is bool and bool(clr_v):
				continue
			var clr_priv: Variant = node.get(&"_cleared")
			if clr_priv is bool and bool(clr_priv):
				continue
			sunken_shipwrecks.append((node as Node3D).global_position)

		for node in get_tree().get_nodes_in_group(&"megalodons"):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			if node.has_method(&"is_defeated") and bool(node.call(&"is_defeated")):
				continue
			var dead_m: Variant = node.get(&"dead")
			if dead_m is bool and bool(dead_m):
				continue
			megalodons.append((node as Node3D).global_position)

		for node in get_tree().get_nodes_in_group(&"ship"):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			if node == tracked_ship or node == _mounted_ship:
				continue
			var sink_v: Variant = node.get(&"is_sinking")
			if sink_v is bool and bool(sink_v):
				continue
			var fac_v: Variant = node.get(&"faction")
			var fac := StringName(String(fac_v)) if fac_v != null else &"corsair"
			if fac == &"player":
				continue
			var n3 := node as Node3D
			var rfwd := -n3.global_basis.z
			rival_ships.append({
				"pos": n3.global_position,
				"heading": atan2(rfwd.x, rfwd.z),
				"faction": fac,
			})

		var active_bats: Array[Vector3] = []
		for node in get_tree().get_nodes_in_group(&"fort_batteries"):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			var dest_v: Variant = node.get(&"destroyed")
			if dest_v is bool and bool(dest_v):
				continue
			var dead_b: Variant = node.get(&"dead")
			if dead_b is bool and bool(dead_b):
				continue
			var siege_v: Variant = node.get(&"siege_active")
			var act_v: Variant = node.get(&"is_active")
			var is_sieging := (siege_v is bool and bool(siege_v)) or (act_v is bool and bool(act_v))
			if not is_sieging:
				continue
			active_bats.append((node as Node3D).global_position)

		var cluster_sums: Array[Vector3] = []
		var cluster_counts: Array[int] = []
		for bpos in active_bats:
			var merged := false
			for ci in cluster_sums.size():
				var cen := cluster_sums[ci] / float(cluster_counts[ci])
				if Vector2(bpos.x - cen.x, bpos.z - cen.z).length() <= FORT_CLUSTER_RADIUS_M:
					cluster_sums[ci] += bpos
					cluster_counts[ci] += 1
					merged = true
					break
			if not merged:
				cluster_sums.append(bpos)
				cluster_counts.append(1)
		for ci in cluster_sums.size():
			fort_sieges.append(cluster_sums[ci] / float(cluster_counts[ci]))

	var wind_hdg := Weather.wind_heading if Weather != null else 0.0
	var wind_spd := Weather.local_wind_speed() if Weather != null else 8.0
	return {
		"view_center": view_center,
		"view_span": view_span,
		"islands": _islands_cache,
		"ship_pos": ship_pos,
		"ship_heading": ship_heading,
		"heading_ray_end": heading_ray_end,
		"heading_ray_length_m": COURSE_RAY_LENGTH_M,
		"ship_cartouche_text": get_ship_cartouche_text(),
		"trail": _trail.duplicate(),
		"target_pos": target_pos,
		"target_label": target_label,
		"course_target": course_target,
		"course_from_pin": course_from_pin,
		"course_bearing_text": course_bearing_text,
		"course_grid_coord": course_grid_coord,
		"markers": markers.duplicate(),
		"wrecks": wrecks,
		"sunken_shipwrecks": sunken_shipwrecks,
		"megalodons": megalodons,
		"rival_ships": rival_ships,
		"leviathans": leviathans,
		"fort_sieges": fort_sieges,
		"station_occupied": _station_player_active,
		"storm_intensity": Weather.storm_intensity if Weather != null else 0.0,
		"storm_center": Weather.storm_center if Weather != null else Vector3.ZERO,
		"storm_radius": Weather.storm_radius if Weather != null else 0.0,
		"storm_phase": _storm_phase,
		"wind_heading": wind_hdg,
		"wind_speed": wind_spd,
		"wind_medallion_text": format_wind_medallion(wind_spd, wind_hdg),
	}


# ==============================================================================
# Inner SubViewport 2D parchment chart renderer
# ==============================================================================

class _ChartCanvas extends Control:
	const COL_PARCHMENT := Color(0.84, 0.76, 0.59)
	const COL_RULER_VELLUM := Color(0.80, 0.71, 0.53, 0.97)
	const COL_VIGNETTE := Color(0.62, 0.49, 0.31, 0.42)
	const COL_GRID := Color(0.42, 0.31, 0.18, 0.36)
	const COL_GRID_SUB := Color(0.42, 0.31, 0.18, 0.14)
	const COL_RHUMB := Color(0.45, 0.34, 0.20, 0.16)
	const COL_INK := Color(0.14, 0.08, 0.04, 0.98)
	const COL_INK_SOFT := Color(0.28, 0.19, 0.11, 0.84)
	const COL_COURSE_RAY := Color(0.26, 0.15, 0.07, 0.82)
	const COL_LAND := Color(0.69, 0.65, 0.41, 0.96)
	const COL_LAND_CORE := Color(0.52, 0.56, 0.33, 0.90)
	const COL_GHOST_LAND := Color(0.71, 0.62, 0.46, 0.52)
	const COL_COAST_WASH := Color(0.34, 0.50, 0.48, 0.40)
	const COL_CRIMSON := Color(0.76, 0.10, 0.08, 0.98)
	const COL_VOLCANO_LAVA := Color(0.88, 0.22, 0.08, 0.96)
	const COL_GOLD := Color(0.86, 0.64, 0.18, 1.0)
	const COL_STORM := Color(0.22, 0.28, 0.36, 0.68)
	const COL_MEGA_FIN := Color(0.16, 0.22, 0.28, 0.96)
	const COL_MEGA_SCAR := Color(0.18, 0.62, 0.64, 0.92)
	const COL_GHOST_TEAL := Color(0.18, 0.58, 0.54, 0.94)

	const FRAME_OUTER := 10.0
	const FRAME_INNER := 30.0
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

		# 1. Warm aged parchment sheet & subtle inner vignette bands.
		draw_rect(Rect2(Vector2.ZERO, size), COL_PARCHMENT, true)
		var vig := 44.0
		draw_rect(Rect2(FRAME_INNER, FRAME_INNER, w - FRAME_INNER * 2.0, vig - FRAME_INNER), COL_VIGNETTE, true)
		draw_rect(Rect2(FRAME_INNER, h - vig, w - FRAME_INNER * 2.0, vig - FRAME_INNER), COL_VIGNETTE, true)
		draw_rect(Rect2(FRAME_INNER, vig, vig - FRAME_INNER, h - vig * 2.0), COL_VIGNETTE, true)
		draw_rect(Rect2(w - vig, vig, vig - FRAME_INNER, h - vig * 2.0), COL_VIGNETTE, true)

		# 2. Fixed world-space 400 m nautical latitude/longitude gridlines (A-H x 1-8).
		var vc: Vector2 = snapshot["view_center"]
		var span: float = float(snapshot["view_span"])
		var aspect := h / maxf(w, 1.0)
		_draw_nautical_grid_lines(vc, span, aspect, w, h)

		# 3. Faint rhumb lines radiating from the decorative compass rose.
		var rose_c := Vector2(w - 108.0, h - 110.0)
		for i in 16:
			var a := float(i) / 16.0 * TAU
			draw_line(rose_c, rose_c + Vector2(cos(a), sin(a)) * 1200.0, COL_RHUMB, 1.0, true)

		# 4. Active storm cell swirl (if Weather.storm_intensity > 0).
		var storm_phase: float = float(snapshot.get("storm_phase", 0.0))
		var storm_int: float = float(snapshot.get("storm_intensity", 0.0))
		if storm_int > 0.01:
			var sc: Vector3 = snapshot["storm_center"]
			var sr: float = float(snapshot["storm_radius"]) * _world_scale()
			var spx := _w2c(Vector2(sc.x, sc.z))
			_draw_storm_swirl(spx, maxf(sr, 28.0), storm_int, storm_phase)

		# 5. Archipelago islands (discovered named in sepia ink + Outpost/Fort/Volcano icons;
		#    undiscovered rendered as soft hand-sketched silhouettes).
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

		# 7. Living-world chart markers: Salvage Wrecks, Sunken Shipwrecks, Megalodons,
		#    Leviathans, Fort Sieges, and Rival Ships.
		for wp: Vector3 in snapshot.get("wrecks", []):
			var wpx := _w2c(Vector2(wp.x, wp.z))
			_draw_wreck_marker(wpx, font)

		for swp: Vector3 in snapshot.get("sunken_shipwrecks", []):
			var swpx := _w2c(Vector2(swp.x, swp.z))
			_draw_sunken_shipwreck_icon(swpx, font)

		for megp: Vector3 in snapshot.get("megalodons", []):
			var megpx := _w2c(Vector2(megp.x, megp.z))
			_draw_megalodon_icon(megpx, font, storm_phase)

		for lpos: Vector3 in snapshot.get("leviathans", []):
			var lpx := _w2c(Vector2(lpos.x, lpos.z))
			_draw_leviathan_sigil(lpx, font)

		for fpos: Vector3 in snapshot.get("fort_sieges", []):
			var fpx := _w2c(Vector2(fpos.x, fpos.z))
			_draw_fort_siege_stamp(fpx, font)

		for rdict: Dictionary in snapshot.get("rival_ships", []):
			var rpos: Vector3 = rdict.get("pos", Vector3.INF)
			if rpos.is_finite():
				var rpx := _w2c(Vector2(rpos.x, rpos.z))
				_draw_rival_ship_marker(rpx, float(rdict.get("heading", 0.0)), rdict.get("faction", &"corsair") as StringName)

		# 8. Live Ship Heading Course Ray (~550 m sepia-ink dashed sightline ahead of bow).
		var spos: Vector3 = snapshot.get("ship_pos", Vector3.INF)
		var ray_end: Vector3 = snapshot.get("heading_ray_end", Vector3.INF)
		if spos.is_finite() and ray_end.is_finite():
			var ship_px_r := _w2c(Vector2(spos.x, spos.z))
			var ray_px := _w2c(Vector2(ray_end.x, ray_end.z))
			_draw_heading_course_ray(ship_px_r, ray_px, px_per_m)

		# 9. Course-bearing rhumb line (crimson-gold dashed line for player Chart Pin,
		#    sepia dashed line for voyage target) with midpoint bearing, distance & grid square.
		var ctarget: Vector3 = snapshot.get("course_target", Vector3.INF)
		var bearing_txt := String(snapshot.get("course_bearing_text", ""))
		if spos.is_finite() and ctarget.is_finite() and bearing_txt != "":
			var ship_px_c := _w2c(Vector2(spos.x, spos.z))
			var tgt_px_c := _w2c(Vector2(ctarget.x, ctarget.z))
			_draw_course_bearing_line(ship_px_c, tgt_px_c, bearing_txt, bool(snapshot.get("course_from_pin", false)), font)

		# 10. Player-placed chart pin markers.
		for mp: Vector3 in snapshot.get("markers", []):
			var mpx := _w2c(Vector2(mp.x, mp.z))
			_draw_pin_marker(mpx)

		# 11. Ship wake breadcrumb trail + Player ship silhouette & live heading arrow!
		var trail: Array = snapshot.get("trail", [])
		for i in range(trail.size() - 1):
			var a := _w2c(trail[i] as Vector2)
			var b := _w2c(trail[i + 1] as Vector2)
			draw_line(a, b, Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.32), 2.0, true)

		if spos.is_finite():
			var ship_px := _w2c(Vector2(spos.x, spos.z))
			_draw_ship_marker(ship_px, float(snapshot.get("ship_heading", 0.0)))

		# 12. Brass-divider center plotting reticle when player is actively inspecting Station_MapTable.
		if bool(snapshot.get("station_occupied", false)):
			_draw_plotting_reticle(size * 0.5, font)

		# 13. Ornate ship-name cartouche, wind-knot medallion, compass rose,
		#     and crisp vellum nautical coordinate frame (A-H top/bottom, 1-8 left/right).
		_draw_ship_cartouche(
			String(snapshot.get("ship_cartouche_text", DEFAULT_CARTOUCHE_NAME)),
			font
		)
		_draw_wind_feather(
			Vector2(w - 238.0, h - 104.0),
			float(snapshot.get("wind_heading", 0.0)),
			float(snapshot.get("wind_speed", 8.0)),
			String(snapshot.get("wind_medallion_text", "WIND 16 kt N")),
			font
		)
		_draw_compass_rose(rose_c, 52.0, font)
		_draw_chart_border_and_headers(vc, span, aspect, w, h, font)

	func _draw_nautical_grid_lines(vc: Vector2, span: float, aspect: float, w: float, h: float) -> void:
		var half_w := span * 0.5
		var half_h := half_w * aspect
		var cell := GRID_CELL_M
		# Optional faint half-cell (200 m) sub-grid lines when zoomed closely in.
		if span <= 1500.0:
			var sub_step := cell * 0.5
			var sx0 := floorf((vc.x - half_w) / sub_step) * sub_step
			var sx := sx0
			while sx <= vc.x + half_w:
				if absf(fposmod(sx - GRID_ORIGIN_XZ.x, cell)) > 1.0:
					var spx := _w2c(Vector2(sx, vc.y)).x
					if spx > FRAME_INNER and spx < w - FRAME_INNER:
						draw_line(Vector2(spx, FRAME_INNER), Vector2(spx, h - FRAME_INNER), COL_GRID_SUB, 1.0, true)
				sx += sub_step
			var sz0 := floorf((vc.y - half_h) / sub_step) * sub_step
			var sz := sz0
			while sz <= vc.y + half_h:
				if absf(fposmod(sz - GRID_ORIGIN_XZ.y, cell)) > 1.0:
					var spy := _w2c(Vector2(vc.x, sz)).y
					if spy > FRAME_INNER and spy < h - FRAME_INNER:
						draw_line(Vector2(FRAME_INNER, spy), Vector2(w - FRAME_INNER, spy), COL_GRID_SUB, 1.0, true)
				sz += sub_step

		# Primary fixed 400 m latitude/longitude lines aligned to GRID_ORIGIN_XZ.
		var x_start := floorf((vc.x - half_w - GRID_ORIGIN_XZ.x) / cell) * cell + GRID_ORIGIN_XZ.x
		var gx := x_start
		while gx <= vc.x + half_w:
			var px := _w2c(Vector2(gx, vc.y)).x
			if px > FRAME_INNER and px < w - FRAME_INNER:
				draw_line(Vector2(px, FRAME_INNER), Vector2(px, h - FRAME_INNER), COL_GRID, 1.25, true)
			gx += cell

		var z_start := floorf((vc.y - half_h - GRID_ORIGIN_XZ.y) / cell) * cell + GRID_ORIGIN_XZ.y
		var gz := z_start
		while gz <= vc.y + half_h:
			var py := _w2c(Vector2(vc.x, gz)).y
			if py > FRAME_INNER and py < h - FRAME_INNER:
				draw_line(Vector2(FRAME_INNER, py), Vector2(w - FRAME_INNER, py), COL_GRID, 1.25, true)
			gz += cell

	func _draw_chart_border_and_headers(vc: Vector2, span: float, aspect: float, w: float, h: float, font: Font) -> void:
		var band := FRAME_INNER - FRAME_OUTER
		# Clean aged parchment border mask frames the inner chart neatly and keeps headers readable.
		draw_rect(Rect2(0.0, 0.0, w, FRAME_OUTER), COL_PARCHMENT, true)
		draw_rect(Rect2(0.0, h - FRAME_OUTER, w, FRAME_OUTER), COL_PARCHMENT, true)
		draw_rect(Rect2(0.0, FRAME_OUTER, FRAME_OUTER, h - FRAME_OUTER * 2.0), COL_PARCHMENT, true)
		draw_rect(Rect2(w - FRAME_OUTER, FRAME_OUTER, FRAME_OUTER, h - FRAME_OUTER * 2.0), COL_PARCHMENT, true)

		# Inner 20 px nautical coordinate ruler strip on all four edges.
		draw_rect(Rect2(FRAME_OUTER, FRAME_OUTER, w - FRAME_OUTER * 2.0, band), COL_RULER_VELLUM, true)
		draw_rect(Rect2(FRAME_OUTER, h - FRAME_INNER, w - FRAME_OUTER * 2.0, band), COL_RULER_VELLUM, true)
		draw_rect(Rect2(FRAME_OUTER, FRAME_INNER, band, h - FRAME_INNER * 2.0), COL_RULER_VELLUM, true)
		draw_rect(Rect2(w - FRAME_INNER, FRAME_INNER, band, h - FRAME_INNER * 2.0), COL_RULER_VELLUM, true)

		# Cell boundary divider ticks along all four ruler strips.
		var half_w := span * 0.5
		var half_h := half_w * aspect
		var cell := GRID_CELL_M
		var x_start := floorf((vc.x - half_w - GRID_ORIGIN_XZ.x) / cell) * cell + GRID_ORIGIN_XZ.x
		var gx := x_start
		while gx <= vc.x + half_w:
			var px := _w2c(Vector2(gx, vc.y)).x
			if px > FRAME_INNER and px < w - FRAME_INNER:
				draw_line(Vector2(px, FRAME_OUTER), Vector2(px, FRAME_INNER), COL_INK_SOFT, 1.4, true)
				draw_line(Vector2(px, h - FRAME_INNER), Vector2(px, h - FRAME_OUTER), COL_INK_SOFT, 1.4, true)
			gx += cell

		var z_start := floorf((vc.y - half_h - GRID_ORIGIN_XZ.y) / cell) * cell + GRID_ORIGIN_XZ.y
		var gz := z_start
		while gz <= vc.y + half_h:
			var py := _w2c(Vector2(vc.x, gz)).y
			if py > FRAME_INNER and py < h - FRAME_INNER:
				draw_line(Vector2(FRAME_OUTER, py), Vector2(FRAME_INNER, py), COL_INK_SOFT, 1.4, true)
				draw_line(Vector2(w - FRAME_INNER, py), Vector2(w - FRAME_OUTER, py), COL_INK_SOFT, 1.4, true)
			gz += cell

		# Crisp strict-ASCII A..H column headers (top & bottom) and 1..8 row headers (left & right).
		if font != null:
			var fs := 13
			for col in GRID_COLS:
				var world_cx := GRID_ORIGIN_XZ.x + (float(col) + 0.5) * cell
				var mid_x := _w2c(Vector2(world_cx, vc.y)).x
				if mid_x > FRAME_INNER + 8.0 and mid_x < w - FRAME_INNER - 8.0:
					var letter := char(65 + col)
					var lw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					draw_string(font, Vector2(mid_x - lw * 0.5, FRAME_OUTER + 15.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_INK)
					draw_string(font, Vector2(mid_x - lw * 0.5, h - FRAME_OUTER - 5.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_INK)

			for row in GRID_ROWS:
				var world_cz := GRID_ORIGIN_XZ.y + (float(row) + 0.5) * cell
				var mid_y := _w2c(Vector2(vc.x, world_cz)).y
				if mid_y > FRAME_INNER + 8.0 and mid_y < h - FRAME_INNER - 8.0:
					var num_lbl := str(row + 1)
					var nw := font.get_string_size(num_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					draw_string(font, Vector2(FRAME_OUTER + (band - nw) * 0.5, mid_y + 4.5), num_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_INK)
					draw_string(font, Vector2(w - FRAME_INNER + (band - nw) * 0.5, mid_y + 4.5), num_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_INK)

		# Corner ornamental nautical squares & crisp double sepia ink border.
		var corner_rects: Array[Rect2] = [
			Rect2(FRAME_OUTER, FRAME_OUTER, band, band),
			Rect2(w - FRAME_INNER, FRAME_OUTER, band, band),
			Rect2(FRAME_OUTER, h - FRAME_INNER, band, band),
			Rect2(w - FRAME_INNER, h - FRAME_INNER, band, band),
		]
		for cr in corner_rects:
			draw_rect(cr, Color(0.68, 0.56, 0.37, 0.85), true)
			draw_rect(cr, COL_INK, false, 1.5)
			var cc := cr.get_center()
			draw_circle(cc, 2.8, COL_GOLD)
			draw_arc(cc, 3.2, 0.0, TAU, 10, COL_INK, 1.0, true)

		draw_rect(Rect2(FRAME_OUTER, FRAME_OUTER, w - FRAME_OUTER * 2.0, h - FRAME_OUTER * 2.0), COL_INK, false, 2.8)
		draw_rect(Rect2(FRAME_INNER, FRAME_INNER, w - FRAME_INNER * 2.0, h - FRAME_INNER * 2.0), COL_INK_SOFT, false, 1.6)

	func _draw_island(isl: Dictionary, px_per_m: float, font: Font) -> void:
		var pos: Vector3 = isl["position"]
		var center := _w2c(Vector2(pos.x, pos.z))
		var r_world := maxf(float(isl.get("radius", 95.0)), 40.0)
		var r_px := clampf(r_world * px_per_m, 14.0, 120.0)
		var discovered := bool(isl.get("discovered", false))
		var nm: String = String(isl.get("name", "Island"))
		var id: StringName = isl.get("id", &"")
		var kind: StringName = isl.get("kind", &"treasure_island")
		var archetype: StringName = isl.get("archetype", &"")
		var is_outpost := bool(isl.get("is_outpost", false)) or (kind == &"outpost")
		var is_fort := (kind == &"fort") \
			or id == &"ironwatch_fort" \
			or id == &"sovereigns_bastion" \
			or archetype == &"fort_rock" \
			or archetype == &"grand_citadel"
		var is_volcano := (id == &"cinder_crag") \
			or (archetype == &"volcano_crag") \
			or (kind == &"volcano")

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
			draw_colored_polygon(inner, Color(0.45, 0.36, 0.28, 0.90) if is_volcano else COL_LAND_CORE)
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, COL_INK, 2.4, true)
			# Subtle charted coastline surveyor hachure ticks along discovered shorelines.
			var p_cnt := poly.size()
			var tick_stride := maxi(1, int(floorf(float(p_cnt) / 8.0)))
			var tick_col := Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.42)
			for ti in range(0, p_cnt, tick_stride):
				var out_v := (poly[ti] - center).normalized()
				draw_line(poly[ti], poly[ti] + out_v * 3.8, tick_col, 1.1, true)

			# Distinct hand-inked parchment symbols for Outposts, Sea Forts, and Volcanoes!
			if is_outpost:
				var star_off := Vector2(minf(r_px * 0.72 + 8.0, 28.0), -minf(r_px * 0.48 + 6.0, 20.0))
				_draw_outpost_lighthouse_star(center + star_off)
				_draw_outpost_anchor_medallion(center)
			elif is_fort:
				_draw_fort_bastion_icon(center)
			elif is_volcano:
				_draw_volcano_icon(center)

			if font != null and center.x >= -30.0 and center.x <= size.x + 30.0 and center.y >= -30.0 and center.y <= size.y + 30.0:
				_draw_island_label(font, nm, center, r_px, true)
		else:
			# Softer hand-sketched silhouette & dashed faded sepia coast for uncharted islands.
			var faded_fill := Color(COL_GHOST_LAND.r, COL_GHOST_LAND.g, COL_GHOST_LAND.b, 0.36)
			var faded_ink := Color(COL_INK_SOFT.r, COL_INK_SOFT.g, COL_INK_SOFT.b, 0.56)
			draw_colored_polygon(poly, faded_fill)
			_draw_dashed_polygon(poly, faded_ink, 1.4, 5.5, 4.5)
			# Soft cartographer's cross-sketch hint inside uncharted silhouette.
			var sk_r := minf(r_px * 0.35, 11.0)
			var sk_col := Color(COL_INK_SOFT.r, COL_INK_SOFT.g, COL_INK_SOFT.b, 0.28)
			draw_line(center + Vector2(-sk_r, -sk_r * 0.4), center + Vector2(sk_r * 0.4, -sk_r), sk_col, 1.0, true)
			draw_line(center + Vector2(-sk_r * 0.5, sk_r * 0.8), center + Vector2(sk_r * 0.8, -sk_r * 0.4), sk_col, 1.0, true)
			if font != null:
				draw_string(font, Vector2(center.x - 4.0, center.y + 5.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, faded_ink)

	func _draw_outpost_anchor_medallion(pos: Vector2) -> void:
		# Hand-inked brass-and-vellum harbor anchor medallion + miniature fluttering outpost pennant.
		draw_circle(pos, 10.5, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.92))
		draw_arc(pos, 10.5, 0.0, TAU, 20, COL_INK, 1.7, true)
		draw_arc(pos, 8.2, 0.0, TAU, 16, COL_GOLD, 1.1, true)
		# Miniature anchor shank, ring, stock crossbar, and curved lower flukes.
		draw_arc(pos + Vector2(0.0, -5.0), 1.8, 0.0, TAU, 10, COL_INK, 1.3, true)
		draw_line(pos + Vector2(0.0, -3.2), pos + Vector2(0.0, 5.4), COL_INK, 1.8, true)
		draw_line(pos + Vector2(-3.8, -1.6), pos + Vector2(3.8, -1.6), COL_INK, 1.5, true)
		draw_arc(pos + Vector2(0.0, 1.2), 5.0, 0.28, PI - 0.28, 12, COL_INK, 1.8, true)
		draw_line(pos + Vector2(-5.2, 2.2), pos + Vector2(-3.2, 1.2), COL_INK, 1.4, true)
		draw_line(pos + Vector2(5.2, 2.2), pos + Vector2(3.2, 1.2), COL_INK, 1.4, true)
		# Crisp miniature crimson-gold harbor pennant banner rising at upper-left of medallion.
		var mast_base := pos + Vector2(-9.5, 2.0)
		var mast_top := pos + Vector2(-9.5, -11.5)
		draw_line(mast_base, mast_top, COL_INK, 1.5, true)
		var flag := PackedVector2Array([
			mast_top,
			mast_top + Vector2(8.5, 2.2),
			mast_top + Vector2(6.0, 4.4),
			mast_top + Vector2(8.5, 6.4),
			mast_top + Vector2(0.0, 6.2),
		])
		draw_colored_polygon(flag, COL_CRIMSON)
		draw_line(mast_top, mast_top + Vector2(8.5, 2.2), COL_GOLD, 1.0, true)

	func _draw_fort_bastion_icon(pos: Vector2) -> void:
		# Crisp miniature crenellated Sea Fort bastion with corner turrets, gatehouse & crimson pennant.
		draw_circle(pos, 13.5, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.80))
		var stone := Color(0.50, 0.43, 0.33, 0.96)
		var keep := Rect2(pos.x - 9.0, pos.y - 4.0, 18.0, 11.0)
		draw_rect(keep, stone, true)
		# Flanking corner bastion towers.
		var left_t := Rect2(pos.x - 11.5, pos.y - 6.5, 5.0, 13.5)
		var right_t := Rect2(pos.x + 6.5, pos.y - 6.5, 5.0, 13.5)
		draw_rect(left_t, stone, true)
		draw_rect(right_t, stone, true)
		# Crenellated merlons crowning the battlement parapet.
		for mx: float in [-11.5, -6.5, -2.0, 2.5, 7.0]:
			draw_rect(Rect2(pos.x + mx, pos.y - 9.2, 3.2, 3.2), stone, true)
			draw_rect(Rect2(pos.x + mx, pos.y - 9.2, 3.2, 3.2), COL_INK, false, 1.2)
		draw_rect(keep, COL_INK, false, 1.7)
		draw_rect(left_t, COL_INK, false, 1.5)
		draw_rect(right_t, COL_INK, false, 1.5)
		# Dark arched portcullis gate & base foundation rule.
		draw_rect(Rect2(pos.x - 2.6, pos.y + 1.0, 5.2, 6.0), COL_INK, true)
		draw_circle(Vector2(pos.x, pos.y + 1.2), 2.6, COL_INK)
		draw_line(pos + Vector2(-13.0, 7.2), pos + Vector2(13.0, 7.2), COL_INK, 1.8, true)
		# Crimson war-standard pennant flying above the central parapet.
		var pole_b := pos + Vector2(0.0, -6.5)
		var pole_t := pos + Vector2(0.0, -15.5)
		draw_line(pole_b, pole_t, COL_INK, 1.5, true)
		draw_colored_polygon(PackedVector2Array([
			pole_t,
			pole_t + Vector2(8.5, 2.6),
			pole_t + Vector2(0.0, 5.2),
		]), COL_CRIMSON)

	func _draw_volcano_icon(pos: Vector2) -> void:
		# Crimson-ink volcanic stratovolcano caldera peak with magma glow & curling smoke wisps.
		draw_circle(pos, 14.5, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.74))
		# Rugged volcanic cone body with concave summit caldera notch.
		var cone := PackedVector2Array([
			pos + Vector2(-13.5, 9.0),
			pos + Vector2(-6.5, -4.5),
			pos + Vector2(-3.8, -7.2),
			pos + Vector2(0.0, -4.4),
			pos + Vector2(3.8, -7.2),
			pos + Vector2(6.5, -4.5),
			pos + Vector2(13.5, 9.0),
		])
		draw_colored_polygon(cone, Color(0.28, 0.20, 0.16, 0.94))
		var cone_ring := cone.duplicate()
		cone_ring.append(cone[0])
		draw_polyline(cone_ring, COL_INK, 1.8, true)
		# Eastern flank charcoal hachure strokes.
		draw_line(pos + Vector2(2.2, -2.5), pos + Vector2(8.2, 7.5), COL_INK, 1.3, true)
		draw_line(pos + Vector2(5.2, -1.0), pos + Vector2(10.8, 7.8), COL_INK, 1.2, true)
		# Crimson volcanic caldera glow & twin molten lava tongues spilling over the rim!
		var crater := PackedVector2Array([
			pos + Vector2(-3.6, -6.6),
			pos + Vector2(0.0, -3.5),
			pos + Vector2(3.6, -6.6),
			pos + Vector2(0.0, -8.2),
		])
		draw_colored_polygon(crater, COL_VOLCANO_LAVA)
		draw_line(pos + Vector2(-1.4, -4.4), pos + Vector2(-4.2, 2.2), COL_CRIMSON, 1.8, true)
		draw_line(pos + Vector2(1.2, -4.2), pos + Vector2(3.4, 3.0), COL_VOLCANO_LAVA, 1.6, true)
		draw_circle(pos + Vector2(0.0, -5.8), 2.1, COL_GOLD)
		# Curling inked ash/smoke wisps drifting above the summit caldera.
		var smoke_col := Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, 0.72)
		draw_polyline(PackedVector2Array([
			pos + Vector2(-1.0, -9.0),
			pos + Vector2(-3.5, -13.0),
			pos + Vector2(0.5, -16.5),
			pos + Vector2(5.2, -18.5),
		]), smoke_col, 1.6, true)
		draw_polyline(PackedVector2Array([
			pos + Vector2(2.0, -9.2),
			pos + Vector2(4.6, -12.6),
			pos + Vector2(8.6, -14.2),
		]), Color(COL_INK_SOFT.r, COL_INK_SOFT.g, COL_INK_SOFT.b, 0.70), 1.3, true)

	func _draw_outpost_lighthouse_star(pos: Vector2) -> void:
		# Warm golden lantern halo + unmistakable 8-ray crimson-gold lighthouse star stamp.
		draw_circle(pos, 10.5, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.30))
		draw_arc(pos, 7.6, 0.0, TAU, 16, Color(COL_INK_SOFT.r, COL_INK_SOFT.g, COL_INK_SOFT.b, 0.52), 1.0, true)
		for i in 8:
			var a := float(i) * (TAU / 8.0) - PI * 0.5
			var d := Vector2(cos(a), sin(a))
			var s := Vector2(-d.y, d.x)
			var is_major := (i % 2 == 0)
			var ray_len := 11.8 if is_major else 8.0
			var half_w := 2.4 if is_major else 1.7
			var col_a := COL_CRIMSON if is_major else COL_GOLD
			var col_b := COL_GOLD if is_major else COL_CRIMSON
			draw_colored_polygon(PackedVector2Array([pos, pos + d * ray_len, pos + s * half_w]), col_a)
			draw_colored_polygon(PackedVector2Array([pos, pos + d * ray_len, pos - s * half_w]), col_b)
		draw_circle(pos, 3.2, COL_INK)
		draw_circle(pos, 2.3, COL_GOLD)
		draw_circle(pos, 1.2, Color(1.0, 0.96, 0.84, 1.0))

	func _draw_dashed_polygon(poly: PackedVector2Array, col: Color, width: float, dash_len: float, gap_len: float) -> void:
		var n := poly.size()
		if n < 2:
			return
		var carry := 0.0
		var drawing := true
		for i in n:
			var p0 := poly[i]
			var p1 := poly[(i + 1) % n]
			var seg := p1 - p0
			var seg_len := seg.length()
			if seg_len < 0.1:
				continue
			var dir := seg / seg_len
			var pos := 0.0
			while pos < seg_len:
				var span_lim := (dash_len if drawing else gap_len) - carry
				var step := minf(span_lim, seg_len - pos)
				if drawing and step > 0.25:
					draw_line(p0 + dir * pos, p0 + dir * (pos + step), col, width, true)
				pos += step
				carry += step
				if carry >= (dash_len if drawing else gap_len) - 0.001:
					carry = 0.0
					drawing = not drawing

	func _draw_island_label(font: Font, nm: String, center: Vector2, r_px: float, charted: bool = true) -> void:
		var fs := 15
		var tsz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var tw := tsz.x
		var th := 16.0
		var margin_x := FRAME_INNER + 8.0
		var min_y := FRAME_INNER + 18.0
		var max_y := size.y - FRAME_INNER - 8.0
		var max_x := maxf(margin_x, size.x - margin_x - tw)

		# Avoid top-left paperweight, bottom-left ship cartouche, and bottom-right compass/wind medallion.
		var paperweight_rect := Rect2(0.0, 0.0, 182.0, 188.0)
		var cartouche_rect := Rect2(0.0, size.y - 102.0, 398.0, 102.0)
		var compass_rect := Rect2(size.x - 310.0, size.y - 202.0, 310.0, 202.0)

		var candidates: Array[Vector2] = [
			Vector2(center.x - tw * 0.5, center.y + r_px + 18.0),
			Vector2(center.x - tw * 0.5, center.y - r_px - 8.0),
			Vector2(center.x + r_px + 10.0, center.y + 5.0),
			Vector2(center.x - r_px - 10.0 - tw, center.y + 5.0),
			Vector2(paperweight_rect.end.x + 6.0, maxf(center.y + 5.0, min_y)),
		]
		var chosen := Vector2(clampf(candidates[0].x, margin_x, max_x), clampf(candidates[0].y, min_y, max_y))
		var found_clear := false
		for cand in candidates:
			var clamped := Vector2(clampf(cand.x, margin_x, max_x), clampf(cand.y, min_y, max_y))
			var box := Rect2(clamped.x - 3.0, clamped.y - th + 2.0, tw + 6.0, th + 2.0)
			if not box.intersects(paperweight_rect) and not box.intersects(compass_rect) and not box.intersects(cartouche_rect):
				chosen = clamped
				found_clear = true
				break

		if not found_clear:
			var box := Rect2(chosen.x - 3.0, chosen.y - th + 2.0, tw + 6.0, th + 2.0)
			if box.intersects(paperweight_rect):
				chosen.x = clampf(paperweight_rect.end.x + 6.0, margin_x, max_x)
			elif box.intersects(compass_rect):
				chosen.y = clampf(compass_rect.position.y - 8.0, min_y, max_y)
			elif box.intersects(cartouche_rect):
				chosen.y = clampf(cartouche_rect.position.y - 8.0, min_y, max_y)

		var tick_pad := 11.0 if charted else 0.0
		var halo_r := Rect2(chosen.x - 4.0, chosen.y - th + 2.0, tw + 8.0 + tick_pad, th + 3.0)
		draw_rect(halo_r, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.72), true)
		draw_string(font, chosen, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_INK)
		if charted:
			# Subtle hand-inked charted checkmark tick right beside discovered island names.
			var tx := chosen.x + tw + 3.5
			var ty := chosen.y - 5.5
			var tick_col := Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.76)
			draw_line(Vector2(tx, ty + 0.5), Vector2(tx + 2.4, ty + 3.0), tick_col, 1.5, true)
			draw_line(Vector2(tx + 2.4, ty + 3.0), Vector2(tx + 6.8, ty - 2.6), tick_col, 1.5, true)

	func _draw_ship_cartouche(title_text: String, font: Font) -> void:
		var lbl := title_text if not title_text.is_empty() else DEFAULT_CARTOUCHE_NAME
		var fs := 13
		var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else float(lbl.length()) * 8.0
		var box_w := clampf(tw + 40.0, 152.0, 332.0)
		var box_h := 34.0
		var left_x := 56.0
		var top_y := size.y - 76.0
		var rect := Rect2(left_x, top_y, box_w, box_h)
		var vellum := Color(0.89, 0.82, 0.65, 0.95)
		var tail_fill := Color(0.77, 0.68, 0.50, 0.94)
		var fold_shadow := Color(0.42, 0.30, 0.17, 0.55)

		# Tiny swallowtail scrolled ribbon tails tucking outward from both lower corners.
		var tail_drop := 5.0
		var tail_w := 17.0
		var tail_h := 22.0
		var left_tail := PackedVector2Array([
			Vector2(left_x + 4.0, top_y + box_h - tail_h + tail_drop),
			Vector2(left_x - tail_w, top_y + box_h - tail_h + tail_drop),
			Vector2(left_x - tail_w + 6.0, top_y + box_h - tail_h * 0.5 + tail_drop),
			Vector2(left_x - tail_w, top_y + box_h + tail_drop),
			Vector2(left_x + 4.0, top_y + box_h + tail_drop),
		])
		draw_colored_polygon(left_tail, tail_fill)
		var lt_ring := left_tail.duplicate()
		lt_ring.append(left_tail[0])
		draw_polyline(lt_ring, COL_INK, 1.5, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(left_x, top_y + box_h),
			Vector2(left_x + 7.0, top_y + box_h),
			Vector2(left_x + 4.0, top_y + box_h + tail_drop),
		]), fold_shadow)

		var rx := left_x + box_w
		var right_tail := PackedVector2Array([
			Vector2(rx - 4.0, top_y + box_h - tail_h + tail_drop),
			Vector2(rx + tail_w, top_y + box_h - tail_h + tail_drop),
			Vector2(rx + tail_w - 6.0, top_y + box_h - tail_h * 0.5 + tail_drop),
			Vector2(rx + tail_w, top_y + box_h + tail_drop),
			Vector2(rx - 4.0, top_y + box_h + tail_drop),
		])
		draw_colored_polygon(right_tail, tail_fill)
		var rt_ring := right_tail.duplicate()
		rt_ring.append(right_tail[0])
		draw_polyline(rt_ring, COL_INK, 1.5, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx, top_y + box_h),
			Vector2(rx - 7.0, top_y + box_h),
			Vector2(rx - 4.0, top_y + box_h + tail_drop),
		]), fold_shadow)

		# Main parchment cartouche body with ornate double ink border & rolled scroll curls.
		draw_rect(rect, vellum, true)
		draw_rect(rect, COL_INK, false, 2.1)
		draw_rect(Rect2(left_x + 3.5, top_y + 3.5, box_w - 7.0, box_h - 7.0), COL_INK_SOFT, false, 1.1)

		for sx: float in [left_x, rx]:
			draw_circle(Vector2(sx, top_y + 4.5), 3.6, vellum)
			draw_arc(Vector2(sx, top_y + 4.5), 3.6, 0.0, TAU, 12, COL_INK, 1.3, true)
			draw_circle(Vector2(sx, top_y + box_h - 4.5), 3.6, vellum)
			draw_arc(Vector2(sx, top_y + box_h - 4.5), 3.6, 0.0, TAU, 12, COL_INK, 1.3, true)

		# Tiny gold diamond end-flourishes framing the vessel name.
		var mid_y := top_y + box_h * 0.5
		for fx: float in [left_x + 12.0, rx - 12.0]:
			draw_colored_polygon(PackedVector2Array([
				Vector2(fx, mid_y - 3.2),
				Vector2(fx + 3.2, mid_y),
				Vector2(fx, mid_y + 3.2),
				Vector2(fx - 3.2, mid_y),
			]), COL_GOLD)
			draw_arc(Vector2(fx, mid_y), 3.4, 0.0, TAU, 4, COL_INK, 0.9, true)

		if font != null:
			var tx := left_x + (box_w - tw) * 0.5
			var ty := top_y + box_h * 0.5 + 4.5
			draw_string(font, Vector2(tx, ty), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_INK)

	func _draw_heading_course_ray(ship_px: Vector2, ray_end_px: Vector2, px_per_m: float) -> void:
		# Crisp sepia-ink dashed course sightline projecting ~550 m ahead of the bow
		# with graduated 100 m navigator ticks and an arrow chevron tip.
		var delta := ray_end_px - ship_px
		var total_len := delta.length()
		if total_len < 36.0:
			return
		var dir := delta / total_len
		var perp := Vector2(-dir.y, dir.x)
		var start_d := 33.0
		var dash_len := 9.0
		var gap_len := 6.0
		var d := start_d
		while d < total_len - 4.0:
			var seg_end := minf(d + dash_len, total_len - 4.0)
			var fade := lerpf(0.86, 0.44, clampf((d - start_d) / maxf(total_len - start_d, 1.0), 0.0, 1.0))
			var col := Color(COL_COURSE_RAY.r, COL_COURSE_RAY.g, COL_COURSE_RAY.b, fade)
			draw_line(ship_px + dir * d, ship_px + dir * seg_end, col, 1.9, true)
			d += dash_len + gap_len

		# Subtle 100 m graduated cross-tick marks along the heading projection.
		var step_px := 100.0 * px_per_m
		if step_px >= 14.0:
			var tick_d := step_px
			while tick_d < total_len - 10.0:
				if tick_d > start_d + 4.0:
					var tp := ship_px + dir * tick_d
					draw_line(tp - perp * 4.2, tp + perp * 4.2, Color(COL_COURSE_RAY.r, COL_COURSE_RAY.g, COL_COURSE_RAY.b, 0.62), 1.3, true)
				tick_d += step_px

		# Fine drafting chevron at the 550 m tip.
		var tip := ship_px + dir * total_len
		var tip_col := Color(COL_COURSE_RAY.r, COL_COURSE_RAY.g, COL_COURSE_RAY.b, 0.72)
		draw_line(tip, tip - dir * 8.0 + perp * 4.5, tip_col, 1.7, true)
		draw_line(tip, tip - dir * 8.0 - perp * 4.5, tip_col, 1.7, true)

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

	func _draw_rival_ship_marker(center: Vector2, heading_rad: float, faction: StringName) -> void:
		# Compact hand-inked rival vessel silhouette (crimson-sailed corsair/drowned or ghostly teal).
		var fwd := Vector2(sin(heading_rad), cos(heading_rad))
		var right := Vector2(fwd.y, -fwd.x)
		var is_ghost := (faction == &"ghost")
		var trim := COL_GHOST_TEAL if is_ghost else COL_CRIMSON
		var hull_col := Color(0.14, 0.24, 0.26, 0.92) if is_ghost else Color(0.24, 0.11, 0.08, 0.94)
		draw_line(center + fwd * 10.0, center + fwd * 18.0, trim, 1.9, true)
		var hull := PackedVector2Array([
			center + fwd * 11.0,
			center + fwd * 3.5 + right * 5.6,
			center - fwd * 8.2 + right * 4.8,
			center - fwd * 9.8,
			center - fwd * 8.2 - right * 4.8,
			center + fwd * 3.5 - right * 5.6,
		])
		draw_colored_polygon(hull, hull_col)
		var ring := hull.duplicate()
		ring.append(hull[0])
		draw_polyline(ring, trim, 1.4, true)
		draw_line(center + fwd * 1.5 - right * 8.2, center + fwd * 1.5 + right * 8.2, trim, 2.4, true)
		draw_circle(center + fwd * 1.5, 1.8, COL_PARCHMENT)

	func _draw_pin_marker(mpx: Vector2) -> void:
		# Crisp crimson-and-gold nautical chart tack medallion with cardinal sighting ticks.
		draw_circle(mpx, 14.0, Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, 0.14))
		draw_arc(mpx, 14.0, 0.0, TAU, 24, COL_CRIMSON, 2.6, true)
		draw_arc(mpx, 10.8, 0.0, TAU, 20, COL_GOLD, 1.4, true)
		for dir: Vector2 in [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]:
			draw_line(mpx + dir * 11.0, mpx + dir * 16.5, COL_CRIMSON, 1.6, true)
		draw_circle(mpx, 5.2, COL_INK)
		draw_circle(mpx, 4.2, COL_CRIMSON)
		draw_circle(mpx + Vector2(-1.2, -1.2), 1.4, COL_GOLD)

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

	func _draw_sunken_shipwreck_icon(pos: Vector2, font: Font) -> void:
		# Hand-inked tilted miniature listing hull & snapped mast cross icon for active SunkenShipwrecks.
		draw_circle(pos, 15.0, Color(COL_COAST_WASH.r, COL_COAST_WASH.g, COL_COAST_WASH.b, 0.34))
		draw_arc(pos, 14.5, 0.0, TAU, 20, Color(COL_INK_SOFT.r, COL_INK_SOFT.g, COL_INK_SOFT.b, 0.45), 1.0, true)
		# Listing broken timber hull tilted ~24 deg above a wavy sea-ink waterline.
		var hull := PackedVector2Array([
			pos + Vector2(-11.0, 1.5),
			pos + Vector2(-8.0, 6.2),
			pos + Vector2(8.5, 3.8),
			pos + Vector2(11.5, -2.5),
			pos + Vector2(3.0, -1.0),
			pos + Vector2(-3.5, 2.0),
		])
		draw_colored_polygon(hull, Color(0.32, 0.21, 0.12, 0.94))
		var hull_ring := hull.duplicate()
		hull_ring.append(hull[0])
		draw_polyline(hull_ring, COL_INK, 1.6, true)
		# Tilted snapped mainmast & cross-yardarm forming an unmistakable nautical shipwreck cross.
		var mast_b := pos + Vector2(-1.0, 2.5)
		var mast_t := pos + Vector2(5.5, -13.0)
		draw_line(mast_b, mast_t, COL_INK, 2.2, true)
		var yard_c := mast_b.lerp(mast_t, 0.62)
		var yard_d := Vector2(1.0, 0.42).normalized()
		draw_line(yard_c - yard_d * 8.5, yard_c + yard_d * 8.5, COL_INK, 1.8, true)
		# Tattered crimson distress pennant + wavy waterline ripples below the listing hull.
		draw_colored_polygon(PackedVector2Array([
			mast_t,
			mast_t + Vector2(6.5, 2.5),
			mast_t + Vector2(-0.8, 4.2),
		]), COL_CRIMSON)
		draw_polyline(PackedVector2Array([
			pos + Vector2(-13.0, 7.5),
			pos + Vector2(-6.5, 5.5),
			pos + Vector2(0.0, 7.8),
			pos + Vector2(6.5, 5.5),
			pos + Vector2(13.0, 7.5),
		]), COL_INK_SOFT, 1.5, true)
		if font != null:
			var lbl := "SHIPWRECK"
			var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var px := pos.x - tw * 0.5
			var py := pos.y + 21.0
			draw_rect(Rect2(px - 3.5, py - 10.0, tw + 7.0, 12.5), Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.78), true)
			draw_string(font, Vector2(px, py), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_INK)

	func _draw_megalodon_icon(pos: Vector2, font: Font, phase: float) -> void:
		# Menacing hand-inked apex shark dorsal fin & swirling abyssal wake rings for AncientMegalodon.
		draw_circle(pos, 19.5, Color(0.18, 0.26, 0.30, 0.22))
		_draw_dashed_circle(pos, 19.5, Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, 0.62), 1.6, 12)
		# Two curved stalking wake swirl arcs around the fin.
		for arm in 2:
			var pts := PackedVector2Array()
			var base_a := phase * 0.7 + float(arm) * PI
			for step in 10:
				var t := float(step) / 9.0
				var r := 9.5 + t * 8.5
				var a := base_a + t * 2.1
				pts.append(pos + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts, Color(COL_MEGA_FIN.r, COL_MEGA_FIN.g, COL_MEGA_FIN.b, 0.58), 1.8, true)
		# Bold curved battle-notched dorsal fin rising above broken wave spray.
		var fin := PackedVector2Array([
			pos + Vector2(-10.5, 6.5),
			pos + Vector2(-4.5, -5.5),
			pos + Vector2(5.5, -13.5),
			pos + Vector2(3.8, -4.2),
			pos + Vector2(6.6, -2.6),
			pos + Vector2(4.2, 0.8),
			pos + Vector2(9.2, 6.5),
		])
		draw_colored_polygon(fin, COL_MEGA_FIN)
		var fin_ring := fin.duplicate()
		fin_ring.append(fin[0])
		draw_polyline(fin_ring, COL_INK, 1.9, true)
		# Iconic turquoise/crimson battle-scar hash marks etched on the fin flank.
		draw_line(pos + Vector2(-2.2, -3.5), pos + Vector2(2.6, -1.5), COL_MEGA_SCAR, 1.6, true)
		draw_line(pos + Vector2(-3.8, 0.5), pos + Vector2(1.4, 2.6), COL_CRIMSON, 1.5, true)
		draw_polyline(PackedVector2Array([
			pos + Vector2(-13.5, 7.5),
			pos + Vector2(-6.0, 5.2),
			pos + Vector2(0.5, 7.6),
			pos + Vector2(7.5, 5.2),
			pos + Vector2(13.5, 7.5),
		]), COL_CRIMSON, 1.7, true)
		if font != null:
			var lbl := "MEGALODON"
			var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var px := pos.x - tw * 0.5
			var py := pos.y + 31.0
			draw_rect(Rect2(px - 4.0, py - 11.0, tw + 8.0, 14.0), Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.82), true)
			draw_string(font, Vector2(px, py), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_CRIMSON)

	func _draw_course_bearing_line(from_px: Vector2, to_px: Vector2, label_txt: String, is_pin: bool, font: Font) -> void:
		var delta := to_px - from_px
		var total_len := delta.length()
		if total_len < 32.0:
			return
		var dir := delta / total_len
		var perp := Vector2(-dir.y, dir.x)
		var line_col := Color(0.72, 0.12, 0.09, 0.92) if is_pin else Color(0.32, 0.17, 0.08, 0.84)
		var gold_col := Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.90)
		var start_d := 22.0
		var end_d := total_len - 18.0
		var dash_len := 10.0
		var gap_len := 7.0
		var d := start_d
		var dash_idx := 0
		while d < end_d:
			var seg_end := minf(d + dash_len, end_d)
			var p0 := from_px + dir * d
			var p1 := from_px + dir * seg_end
			if is_pin:
				# Crimson-gold dual-tone dashed rhumb line for active player Chart Pins!
				draw_line(p0, p1, line_col, 2.8, true)
				if dash_idx % 2 == 0:
					draw_line(p0.lerp(p1, 0.18), p0.lerp(p1, 0.82), gold_col, 1.2, true)
			else:
				draw_line(p0, p1, line_col, 2.1, true)
			d += dash_len + gap_len
			dash_idx += 1
		# Subtle navigator's divider tick notches along longer plotted courses.
		var tick_d := start_d + 72.0
		while tick_d < end_d - 36.0:
			var tp := from_px + dir * tick_d
			var tick_col := gold_col if is_pin else Color(line_col.r, line_col.g, line_col.b, 0.65)
			draw_line(tp - perp * 4.5, tp + perp * 4.5, tick_col, 1.5, true)
			tick_d += 88.0

		if font == null:
			return
		var fs := 13
		var tsz := font.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var tw := tsz.x
		var th := 15.0
		# Offset label gently perpendicular to the dashed rhumb line, clamped inside chart margins.
		var mid := from_px.lerp(to_px, 0.5)
		var side := -1.0 if perp.y > 0.0 else 1.0
		var lbl_center := mid + perp * (15.0 * side)
		var bx := clampf(lbl_center.x - tw * 0.5, FRAME_INNER + 10.0, maxf(FRAME_INNER + 10.0, size.x - FRAME_INNER - 10.0 - tw))
		var by := clampf(lbl_center.y + th * 0.35, FRAME_INNER + 20.0, size.y - FRAME_INNER - 10.0)
		var pill := Rect2(bx - 6.0, by - th + 1.0, tw + 12.0, th + 5.0)
		draw_rect(pill, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.92), true)
		if is_pin:
			draw_rect(pill, line_col, false, 1.8)
			draw_rect(Rect2(pill.position + Vector2(2.0, 2.0), pill.size - Vector2(4.0, 4.0)), gold_col, false, 1.0)
		else:
			draw_rect(pill, Color(line_col.r, line_col.g, line_col.b, 0.65), false, 1.3)
		draw_string(font, Vector2(bx, by), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, line_col)

	func _draw_wind_feather(center: Vector2, heading_rad: float, wind_spd: float, wind_text: String, font: Font) -> void:
		var r := 28.0
		draw_circle(center, r, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.86))
		draw_arc(center, r, 0.0, TAU, 28, COL_INK, 1.7, true)
		draw_arc(center, r - 4.0, 0.0, TAU, 24, Color(COL_INK_SOFT.r, COL_INK_SOFT.g, COL_INK_SOFT.b, 0.50), 1.0, true)

		# Weather.mean_wind_vector = (sin(h), 0, -cos(h)) -> 2D chart direction (sin(h), -cos(h)).
		var dir := Vector2(sin(heading_rad), -cos(heading_rad))
		var perp := Vector2(-dir.y, dir.x)
		var tail := center - dir * 18.0
		var tip := center + dir * 19.0
		draw_line(tail, tip - dir * 5.0, COL_INK, 2.2, true)
		var head := PackedVector2Array([
			tip,
			tip - dir * 10.0 + perp * 5.2,
			tip - dir * 7.2,
			tip - dir * 10.0 - perp * 5.2,
		])
		draw_colored_polygon(head, COL_INK)
		draw_circle(center, 2.2, COL_GOLD)

		# Nautical feather barbs scaled by live Weather.wind_speed (1..5 barbs; crimson accent in gales).
		var barbs := clampi(int(roundf(wind_spd / 4.2)), 1, 5)
		var gale := wind_spd >= 15.5
		for i in barbs:
			var t := float(i) * 4.0
			var root_pt := tail + dir * (1.5 + t)
			var barb_len := 8.2 - float(i) * 0.6
			var b_col := COL_CRIMSON if (gale and i == 0) else COL_INK_SOFT
			var wing_dir := (-dir * 0.72 + perp * 0.69).normalized()
			var wing_dir_r := (-dir * 0.72 - perp * 0.69).normalized()
			draw_line(root_pt, root_pt + wing_dir * barb_len, b_col, 1.7, true)
			draw_line(root_pt, root_pt + wing_dir_r * barb_len, b_col, 1.7, true)

		if font != null:
			var lbl := wind_text if not wind_text.is_empty() else "WIND 0 kt N"
			var fs := 11
			var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var px := center.x - tw * 0.5
			var py := center.y + r + 15.0
			var pill := Rect2(px - 6.0, py - 11.5, tw + 12.0, 15.5)
			var border_col := COL_CRIMSON if gale else Color(COL_INK_SOFT.r, COL_INK_SOFT.g, COL_INK_SOFT.b, 0.72)
			draw_rect(pill, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.90), true)
			draw_rect(pill, border_col, false, 1.2)
			draw_string(font, Vector2(px, py), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_CRIMSON if gale else COL_INK)

	func _draw_plotting_reticle(center: Vector2, font: Font) -> void:
		var col_brass := Color(0.56, 0.36, 0.12, 0.72)
		var col_ink := Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.56)
		_draw_dashed_circle(center, 15.0, col_brass, 1.5, 12)
		for dir: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(center + dir * 7.0, center + dir * 22.0, col_ink, 1.5, true)
		draw_circle(center, 2.0, COL_CRIMSON)
		if font != null:
			var hint := "[WASD] Pan | [E/C/Wheel] Zoom | [Space] Pin"
			var tw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var px := center.x - tw * 0.5
			var py := size.y - 42.0
			draw_rect(Rect2(px - 7.0, py - 12.0, tw + 14.0, 16.5), Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.86), true)
			draw_string(font, Vector2(px, py), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_INK_SOFT)

	func _draw_leviathan_sigil(pos: Vector2, font: Font) -> void:
		var verm_sepia := Color(0.64, 0.14, 0.12, 0.94)
		var wash := Color(0.26, 0.12, 0.16, 0.24)
		draw_circle(pos, 23.0, wash)
		_draw_dashed_circle(pos, 24.0, Color(verm_sepia.r, verm_sepia.g, verm_sepia.b, 0.58), 1.6, 14)
		# Six curled sea-monster tentacle star arms spiraling from the abyssal crown.
		for arm in 6:
			var base_a := float(arm) / 6.0 * TAU - PI * 0.5
			var pts := PackedVector2Array()
			for step in 9:
				var t := float(step) / 8.0
				var r := 5.5 + t * 18.0
				var curl := sin(t * PI * 1.35) * 0.34 + t * t * 0.42
				var a := base_a + curl
				pts.append(pos + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts, verm_sepia if arm % 2 == 0 else COL_INK, 2.3, true)
		draw_circle(pos, 6.2, COL_INK)
		draw_circle(pos, 3.2, COL_GOLD)
		draw_circle(pos, 1.4, COL_CRIMSON)
		if font != null:
			var lbl := "LEVIATHAN"
			var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var px := pos.x - tw * 0.5
			var py := pos.y + 37.0
			draw_rect(Rect2(px - 4.0, py - 12.0, tw + 8.0, 15.0), Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.80), true)
			draw_string(font, Vector2(px, py), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, verm_sepia)

	func _draw_fort_siege_stamp(pos: Vector2, font: Font) -> void:
		var r := 17.5
		draw_circle(pos, r, Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.86))
		draw_arc(pos, r, 0.0, TAU, 8, COL_CRIMSON, 2.4, true)
		draw_arc(pos, r - 3.5, 0.0, TAU, 8, Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.65), 1.1, true)
		# Crossed-cannons crimson siege emblem.
		for ang_deg: float in [-38.0, 38.0]:
			var a := deg_to_rad(ang_deg)
			var d := Vector2(cos(a), sin(a))
			var p := Vector2(-d.y, d.x)
			var barrel := PackedVector2Array([
				pos - d * 11.5 - p * 2.8,
				pos + d * 11.5 - p * 1.8,
				pos + d * 11.5 + p * 1.8,
				pos - d * 11.5 + p * 2.8,
			])
			draw_colored_polygon(barrel, COL_INK)
			draw_circle(pos - d * 12.5, 2.3, COL_CRIMSON)
			draw_circle(pos + d * 12.6, 2.0, COL_GOLD)
		draw_circle(pos, 2.6, COL_CRIMSON)
		if font != null:
			var lbl := "FORT SIEGE"
			var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var px := pos.x - tw * 0.5
			var py := pos.y + 32.0
			draw_rect(Rect2(px - 4.0, py - 12.0, tw + 8.0, 15.0), Color(COL_PARCHMENT.r, COL_PARCHMENT.g, COL_PARCHMENT.b, 0.80), true)
			draw_string(font, Vector2(px, py), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_CRIMSON)

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
				var lp := center + d * (r + 13.0) + Vector2(-5.0, 5.0)
				draw_string(font, lp, labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c_hi)
		draw_circle(center, 4.8, COL_GOLD)
