extends Node3D
## Sea of Scoundrels — Full Playable Vertical Slice Main Scene.
##
## Assembles SkyRig, Ocean, 11-island Archipelago, Sloop/Brigantine Ship with
## live MapTableView, CookingStove & FishingLine, first-person Captain Pawn +
## Inventory + CombatComponent + 3 AI Crewmates (or Co-op peers), GameHUD,
## ShipwrightMenu, VoyageManager (Story Chapters + Procedural Contracts),
## WorldDirector living-sea events, and live Audio ambience & adaptive music.
##
## CLI user args (passed after `--`):
##   host | join=IP | port=N
##   time=H | storm=S | cloud=C | quality=low|med|high | ship=sloop|brigantine
##   shot=outpost_dock|sailing|island_approach|combat|storm|sunset|night|helm|map_table|hold|leviathan|fleet

const SKY_RIG_SCENE: PackedScene = preload("res://src/sky/sky_rig.tscn")
const OCEAN_SCENE: PackedScene = preload("res://src/ocean/ocean.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const BARREL_PROP_SCENE: PackedScene = preload("res://assets/generated/props/barrel_prop.glb")
const CRATE_PROP_SCENE: PackedScene = preload("res://assets/generated/props/crate_supply.glb")
const FORT_VAULT_SCRIPT: GDScript = preload("res://src/world/fort_vault.gd")

const BRIGANTINE_SCENE_PATH := "res://src/ship/brigantine.tscn"

const CREW_SPECS: Array[Dictionary] = [
	{"persona": &"helmsman", "local_pos": Vector3(-0.95, 2.00, 4.65)},
	{"persona": &"lookout", "local_pos": Vector3(0.0, 1.10, -3.20)},
	{"persona": &"carpenter", "local_pos": Vector3(1.05, 1.10, -0.35)},
]

const BRIGANTINE_CREW_SPECS: Array[Dictionary] = [
	{"persona": &"helmsman", "local_pos": Vector3(-1.15, 2.25, 6.20)},
	{"persona": &"lookout", "local_pos": Vector3(0.0, 1.25, -5.60)},
	{"persona": &"carpenter", "local_pos": Vector3(1.35, 1.25, -0.60)},
]

const PEER_TINTS: Array[Array] = [
	[Color(0.58, 0.16, 0.22), Color(0.90, 0.72, 0.24)],
	[Color(0.16, 0.46, 0.34), Color(0.86, 0.56, 0.18)],
	[Color(0.36, 0.22, 0.52), Color(0.88, 0.74, 0.30)],
]

# --- Live world & gameplay references ----------------------------------------

var sky_rig: Node3D = null
var ocean: Ocean = null
var archipelago: Archipelago = null
var player_ship: Ship = null
var map_table: MapTableView = null
var cooking_stove: CookingStove = null
var fishing_line: FishingLine = null
var fishing_interactable: Interactable = null

var player_pawn: Pawn = null
var player_controller: PlayerController = null
var player_combat: CombatComponent = null
var inventory: Inventory = null

var crew_pawns: Array[Pawn] = []
var crew_brains: Array[CrewBrain] = []

var hud: GameHUD = null
var shipwright_menu: ShipwrightMenu = null
var voyage_manager: VoyageManager = null
var world_director: WorldDirector = null
var user_settings: UserSettings = null

var active_enemies: Array[Pawn] = []
var enemy_ships: Array[Ship] = []
var active_sharks: Array[Shark] = []
var active_leviathans: Array[Leviathan] = []
var current_music_mood: StringName = &""
var active_shot_mode: String = ""

var _entities_root: Node3D = null
var _shot_camera: Camera3D = null
var _shot_track_ship: bool = false
var _shot_track_cam_local: Vector3 = Vector3.ZERO
var _shot_track_look_local: Vector3 = Vector3.ZERO
var _shot_track_world_target: Node3D = null
var _shot_track_world_blend: float = 0.0
var _shot_track_world_y_off: float = 3.2
var _shot_combat_timer: float = -1.0
var _bobbing_props: Array[Dictionary] = []   # {node, base_x, base_z, y_off, phase}
var _reef_bubble_emitters: Array[GPUParticles3D] = []
var _peer_pawns: Dictionary = {}             # int peer_id -> Pawn
var _peer_yielded_crew: Dictionary = {}      # int peer_id -> int crew index
var _wired_dig_sites: Dictionary = {}        # int instance_id -> true
var _boarded_chests: Dictionary = {}         # int instance_id -> true
var _spawned_voyage_id: String = ""
var _return_complication_fired: bool = false
var _fishing_pawn: Pawn = null

var _cargo_check_accum: float = 0.0
var _discovery_accum: float = 0.0
var _music_accum: float = 0.0
var _revive_timer: float = -1.0
var _ship_restoring: bool = false

# Parsed CLI options
var _cli_host: bool = false
var _cli_join_ip: String = ""
var _cli_port: int = Net.DEFAULT_PORT
var _cli_time: float = NAN
var _cli_storm: float = NAN
var _cli_cloud: float = NAN
var _cli_quality: String = ""
var _cli_ship_class: StringName = &"sloop"


func _ready() -> void:
	_parse_cli_args()
	_start_network_session()

	user_settings = UserSettings.new()
	user_settings.load_from()
	if _cli_ship_class == &"sloop" and Game != null and Game.profile != null:
		var saved_cls := String(Game.profile.data.get("ship_class", "sloop"))
		if saved_cls == "brigantine":
			_cli_ship_class = &"brigantine"

	_entities_root = Node3D.new()
	_entities_root.name = "Entities"
	add_child(_entities_root)

	_build_environment_and_world()
	_build_player_ship()
	_build_player_and_crew()
	_build_voyage_and_director()
	_build_ui()
	_wire_world_signals()

	# Apply persistent settings first, then explicit CLI overrides.
	user_settings.apply_all(self)
	_apply_cli_overrides()

	# Start Story Chapter 1 automatically if no voyage is currently active.
	if Net.is_host():
		var map_data := archipelago.get_map_data()
		voyage_manager.refresh_offers(map_data, 3, &"port_scoundrel")
		if not voyage_manager.has_active_voyage():
			voyage_manager.start_starter_voyage(map_data)
		# Ensure Cutlass Cay & active voyage are populated immediately.
		if voyage_manager.has_active_voyage():
			_prepare_active_voyage_world(voyage_manager.active_voyage)
		_update_cargo_value()

	if active_shot_mode != "":
		_apply_hero_shot(active_shot_mode)
	elif hud != null and DisplayServer.get_name() != "headless":
		var subtitle := "Port Scoundrel - Set Sail for Cutlass Cay"
		if voyage_manager != null and voyage_manager.has_active_voyage():
			var vt := String(voyage_manager.active_voyage.get("title", "")).strip_edges()
			if vt != "":
				subtitle = "Port Scoundrel - %s" % vt
		hud.show_voyage_title("SEA OF SCOUNDRELS", subtitle, 4.4)

	_update_live_audio(true)
	_update_adaptive_music(true)


func _exit_tree() -> void:
	for bp: GPUParticles3D in _reef_bubble_emitters:
		if bp != null and is_instance_valid(bp):
			bp.emitting = false
			bp.visible = false
			bp.draw_pass_1 = null
			bp.process_material = null
	_reef_bubble_emitters.clear()
	_disconnect_autoload_signals()
	if Net != null:
		Net.unregister_replicated_ship(&"player_sloop")
		Net.unregister_replicated_pawn(Net.local_id())
		for pid: int in _peer_pawns.keys():
			Net.unregister_replicated_pawn(pid)


# ==============================================================================
# CLI & Network Session
# ==============================================================================

func _parse_cli_args() -> void:
	for raw_arg in OS.get_cmdline_user_args():
		var a := String(raw_arg).strip_edges()
		if a == "host":
			_cli_host = true
		elif a.begins_with("join="):
			_cli_join_ip = a.trim_prefix("join=")
		elif a.begins_with("port="):
			_cli_port = maxi(1, int(a.trim_prefix("port=")))
		elif a.begins_with("time="):
			_cli_time = float(a.trim_prefix("time="))
		elif a.begins_with("storm="):
			_cli_storm = clampf(float(a.trim_prefix("storm=")), 0.0, 1.0)
		elif a.begins_with("cloud="):
			_cli_cloud = clampf(float(a.trim_prefix("cloud=")), 0.0, 1.0)
		elif a.begins_with("quality="):
			_cli_quality = a.trim_prefix("quality=").to_lower()
		elif a.begins_with("ship="):
			var s_arg := a.trim_prefix("ship=").to_lower()
			if s_arg == "brigantine":
				_cli_ship_class = &"brigantine"
			else:
				_cli_ship_class = &"sloop"
		elif a.begins_with("shot="):
			active_shot_mode = a.trim_prefix("shot=").to_lower()


func _start_network_session() -> void:
	if _cli_host:
		var err := Net.host(_cli_port)
		if err != OK:
			push_warning("Main: Net.host(%d) failed (%s), falling back to single-player." % [_cli_port, error_string(err)])
			Net.start_single_player()
	elif _cli_join_ip != "":
		var err := Net.join(_cli_join_ip, _cli_port)
		if err != OK:
			push_warning("Main: Net.join(%s, %d) failed (%s), falling back to single-player." % [_cli_join_ip, _cli_port, error_string(err)])
			Net.start_single_player()
	else:
		Net.start_single_player()


# ==============================================================================
# World, Ship, Crew, Voyage & UI Construction
# ==============================================================================

func _build_environment_and_world() -> void:
	# Fair morning sailing weather by default (overridden cleanly by CLI args or storms).
	if Net.is_host():
		Weather.time_of_day = 10.2
		Weather.set_weather(0.06, 9.0, -0.35, 0.0, 0.38)
		Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.06)

	sky_rig = SKY_RIG_SCENE.instantiate() as Node3D
	sky_rig.name = "SkyRig"
	add_child(sky_rig)

	ocean = OCEAN_SCENE.instantiate() as Ocean
	ocean.name = "Ocean"
	add_child(ocean)

	archipelago = Archipelago.new()
	archipelago.name = "Archipelago"
	archipelago.add_to_group(&"archipelago")
	add_child(archipelago)

	# Ensure Port Scoundrel starts discovered in the captain's chart log.
	if Game != null and Game.profile != null:
		Game.profile.discover("port_scoundrel")

	_populate_archipelago_wildlife()
	_spawn_sunken_reef_treasures()


func _populate_archipelago_wildlife() -> void:
	if archipelago == null or _entities_root == null:
		return
	var port := archipelago.get_outpost(0)
	if port != null:
		var port_gulls := SeabirdFlock.spawn_over(
			_entities_root, port.global_position + Vector3(0.0, 0.0, -24.0), 22.0, 18.0, 6)
		port_gulls.is_loot_marker = false

	for isl in archipelago.get_islands():
		if isl is Outpost:
			continue
		# Circling gulls above major treasure/wreck islands mark distant loot sites.
		if isl.island_id == "cutlass_cay" or isl.archetype == &"wreck_reef" or isl.archetype == &"atoll":
			var flock := SeabirdFlock.spawn_over(_entities_root, isl.global_position, 16.0, 19.0, 5)
			flock.is_loot_marker = true
		# Host-only guarding IslandCrabs on beaches & ReefEels in coastal shallows.
		if not Net.is_host():
			continue
		if not isl.dig_points.is_empty():
			var dp: Vector3 = isl.dig_points[0]
			var crab_local := dp + Vector3(4.2, 0.0, -2.5)
			crab_local.y = maxf(0.25, isl.surface_height(crab_local.x, crab_local.z)) + 0.08
			var crab := IslandCrab.new()
			crab.name = "IslandCrab_" + isl.island_id
			_entities_root.add_child(crab)
			crab.global_position = isl.global_transform * crab_local
			crab.guard_origin = crab.global_position
		if isl.island_id == "cutlass_cay" or isl.archetype == &"arch" or isl.archetype == &"wreck_reef":
			var eel_offset := Vector3(isl.island_radius + 12.0, 0.0, -8.0)
			var eel_world := isl.global_transform * eel_offset
			var eel := ReefEel.new()
			eel.name = "ReefEel_" + isl.island_id
			_entities_root.add_child(eel)
			eel.global_position = Vector3(eel_world.x, Sea.height(eel_world.x, eel_world.z) - 2.2, eel_world.z)
			eel.lair_origin = eel.global_position


func _spawn_sunken_reef_treasures() -> void:
	if not Net.is_host() or archipelago == null or _entities_root == null:
		return
	var atoll_tid: StringName = &"sunken_amphora" if TreasureCatalog.has_treasure(&"sunken_amphora") else &"archive_chalice"
	var reef_specs: Array[Dictionary] = [
		{"island_id": "crescent_atoll", "treasure_id": atoll_tid, "yaw": 0.45},
		{"island_id": "wreckers_shoal", "treasure_id": &"wayfarer_chest", "yaw": -0.72},
	]
	for spec in reef_specs:
		var isl := archipelago.get_island_by_id(String(spec["island_id"]))
		if isl == null:
			continue
		var local_pos := _find_reef_seabed_spot(isl)
		var world_pos := isl.global_transform * local_pos
		var tid: StringName = spec["treasure_id"]
		var item := TreasureCatalog.create_treasure_carryable(tid, world_pos)
		item.name = "SunkenReefTreasure_" + isl.island_id
		# Keep sunken booty cleanly seated on the coral seabed until a diver hauls it up.
		item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		item.freeze = true
		item.set_meta(&"sunken_reef_treasure", true)
		_entities_root.add_child(item)
		item.global_position = world_pos
		item.rotation = Vector3(0.07, float(spec["yaw"]), -0.05)
		if item.interactable != null:
			item.interactable.reach = 3.2

		var depth_m := maxf(1.8, -local_pos.y)
		var bubbles := _build_reef_bubble_column(depth_m)
		item.add_child(bubbles)
		_reef_bubble_emitters.append(bubbles)
		item.picked_up.connect(func(_pawn: Node) -> void:
			if is_instance_valid(bubbles):
				bubbles.emitting = false
				bubbles.visible = false
				bubbles.draw_pass_1 = null
				bubbles.process_material = null
				bubbles.queue_free()
		, CONNECT_ONE_SHOT)


func _find_reef_seabed_spot(isl: Island) -> Vector3:
	var moor_xz := Vector2(isl.mooring_transform.origin.x, isl.mooring_transform.origin.z)
	var reef := isl.get_node_or_null(^"CoralReef") as CoralReef
	var pts: Array[Transform3D] = reef.get_placed_transforms() if reef != null else []
	var occupied_xz: Array[Vector2] = []
	for xf in pts:
		occupied_xz.append(Vector2(xf.origin.x, xf.origin.z))

	# Prefer an open sandy seabed patch beside a placed coral cluster in -2.4 .. -4.8 m depth.
	var offsets: Array[Vector2] = [
		Vector2(2.3, 0.9),
		Vector2(-2.3, 0.9),
		Vector2(0.9, 2.3),
		Vector2(-0.9, -2.3),
		Vector2(2.6, -1.2),
		Vector2(-2.6, -1.2),
	]
	var scan_limit := mini(pts.size(), 48)
	for i in scan_limit:
		var base_xz := Vector2(pts[i].origin.x, pts[i].origin.z)
		for off in offsets:
			var cand := base_xz + off
			if cand.distance_to(moor_xz) < 10.0:
				continue
			var h := isl.surface_height(cand.x, cand.y)
			if h > -2.4 or h < -4.8:
				continue
			if isl.surface_normal(cand.x, cand.y).y < 0.78:
				continue
			var clear := true
			for occ in occupied_xz:
				if cand.distance_squared_to(occ) < 1.35 * 1.35:
					clear = false
					break
			if clear:
				return Vector3(cand.x, h + 0.04, cand.y)

	# Fallback: scan seaward shallow shelf annulus for a gentle sandy spot.
	var r_min := maxf(10.0, isl.island_radius * 0.72)
	var r_max := maxf(r_min + 6.0, isl.seabed_radius * 0.85)
	for ring in 6:
		var r := lerpf(r_min, r_max, float(ring) / 5.0)
		for step in 24:
			var ang := float(step) / 24.0 * TAU
			var cand := Vector2(cos(ang) * r, sin(ang) * r)
			if cand.distance_to(moor_xz) < 10.0:
				continue
			var h := isl.surface_height(cand.x, cand.y)
			if h <= -2.4 and h >= -4.8 and isl.surface_normal(cand.x, cand.y).y >= 0.75:
				return Vector3(cand.x, h + 0.04, cand.y)

	var fb_z := -(isl.island_radius + 8.0)
	var fb_h := clampf(isl.surface_height(0.0, fb_z), -4.8, -2.4)
	return Vector3(0.0, fb_h + 0.04, fb_z)


static func _build_reef_bubble_column(column_height: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "ReefBubbleColumn"
	p.position = Vector3(0.0, 0.28, 0.0)
	p.amount = 14
	p.lifetime = clampf(column_height / 0.85, 2.2, 5.2)
	p.preprocess = 2.0
	p.explosiveness = 0.08
	p.randomness = 0.35
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 120.0
	p.visibility_aabb = AABB(Vector3(-1.2, -0.5, -1.2), Vector3(2.4, column_height + 1.5, 2.4))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.24
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 14.0
	proc.initial_velocity_min = 0.65
	proc.initial_velocity_max = 1.05
	proc.gravity = Vector3(0.0, 0.08, 0.0)
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 0.18
	proc.turbulence_noise_scale = 2.8
	proc.turbulence_influence_min = 0.15
	proc.turbulence_influence_max = 0.35
	proc.scale_min = 0.45
	proc.scale_max = 1.15
	var sc_curve := Curve.new()
	sc_curve.add_point(Vector2(0.0, 0.35))
	sc_curve.add_point(Vector2(0.35, 1.0))
	sc_curve.add_point(Vector2(0.82, 0.92))
	sc_curve.add_point(Vector2(1.0, 0.20))
	var sc_tex := CurveTexture.new()
	sc_tex.curve = sc_curve
	proc.scale_curve = sc_tex
	var col_grad := Gradient.new()
	col_grad.offsets = PackedFloat32Array([0.0, 0.16, 0.76, 1.0])
	col_grad.colors = PackedColorArray([
		Color(0.84, 0.97, 1.0, 0.0),
		Color(0.86, 0.98, 1.0, 0.56),
		Color(0.82, 0.96, 1.0, 0.42),
		Color(0.92, 0.99, 1.0, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 24
	ramp.gradient = col_grad
	proc.color_ramp = ramp
	p.process_material = proc

	var radial := Gradient.new()
	radial.offsets = PackedFloat32Array([0.0, 0.34, 0.68, 0.86, 1.0])
	radial.colors = PackedColorArray([
		Color(0.96, 1.0, 1.0, 0.72),
		Color(0.82, 0.96, 1.0, 0.34),
		Color(0.88, 0.98, 1.0, 0.62),
		Color(0.94, 1.0, 1.0, 0.30),
		Color(0.94, 1.0, 1.0, 0.0),
	])
	var bubble_tex := GradientTexture2D.new()
	bubble_tex.width = 32
	bubble_tex.height = 32
	bubble_tex.fill = GradientTexture2D.FILL_RADIAL
	bubble_tex.fill_from = Vector2(0.5, 0.5)
	bubble_tex.fill_to = Vector2(0.5, 0.0)
	bubble_tex.gradient = radial

	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = bubble_tex
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = true
	return p


func _build_player_ship() -> void:
	var ship_scene := _resolve_ship_scene(_cli_ship_class)
	player_ship = ship_scene.instantiate() as Ship
	player_ship.name = "PlayerShip"
	player_ship.faction = &"player"
	player_ship.start_anchored = true
	add_child(player_ship)

	var home_outpost := archipelago.get_outpost(0)
	if home_outpost != null:
		var moor_xf := home_outpost.get_world_mooring_transform()
		moor_xf.origin.y = Sea.height(moor_xf.origin.x, moor_xf.origin.z)
		player_ship.global_transform = moor_xf
	else:
		player_ship.global_position = Vector3(0.0, Sea.height(0.0, -40.0), -40.0)

	# Mount live diegetic MapTableView in the ship hold.
	map_table = MapTableView.new()
	map_table.name = "MapTableView"
	map_table.mount_to_ship(player_ship)
	map_table.set_archipelago_data(_build_chart_map_data())

	# Mount CookingStove in the ship hold (starboard mid-aft, clear of map table & aisle).
	_mount_cooking_stove(player_ship)

	# Mount FishingLine & aft-rail interactable on the quarterdeck stern rail.
	_mount_fishing_station(player_ship)

	Net.register_replicated_ship(&"player_sloop", player_ship)


func _resolve_ship_scene(cls: StringName) -> PackedScene:
	if cls == &"brigantine" and ResourceLoader.exists(BRIGANTINE_SCENE_PATH):
		var loaded := load(BRIGANTINE_SCENE_PATH) as PackedScene
		if loaded != null:
			return loaded
	return SLOOP_SCENE


func _captain_deck_pos(target_ship: Ship) -> Vector3:
	if target_ship != null and target_ship.ship_class == &"brigantine":
		return Vector3(0.0, 2.25, 5.65)
	return Vector3(0.0, 2.00, 4.15)


func _crew_specs_for(target_ship: Ship) -> Array[Dictionary]:
	if target_ship != null and target_ship.ship_class == &"brigantine":
		return BRIGANTINE_CREW_SPECS
	return CREW_SPECS


func _mount_cooking_stove(target_ship: Ship) -> void:
	cooking_stove = CookingStove.new()
	cooking_stove.name = "CookingStove"
	cooking_stove.build_hearth = true
	if target_ship.ship_class == &"brigantine":
		cooking_stove.position = Vector3(1.65, -0.95, 1.85)
	else:
		cooking_stove.position = Vector3(1.25, -0.85, 0.85)
	target_ship.add_child(cooking_stove)

	# Intercept stove interaction when player holds freshly caught fish from FishingLine.
	if cooking_stove.interactable != null:
		cooking_stove.interactable.position = Vector3(-0.1, 0.65, 0.0)
		cooking_stove.interactable.reach = 2.8


func _mount_fishing_station(target_ship: Ship) -> void:
	fishing_line = FishingLine.new()
	fishing_line.name = "FishingLine"
	if target_ship.ship_class == &"brigantine":
		fishing_line.position = Vector3(-1.75, 2.25, 7.65)
	else:
		fishing_line.position = Vector3(-1.48, 2.0, 5.72)
	target_ship.add_child(fishing_line)

	# Sculpted carved oak & brass rail holder cleat + stowed 3-joint bamboo fishing rod.
	var holder_origin := Vector3(0.02, 0.68, 0.24)
	var rod_rot_deg := Vector3(38.0, 0.0, 8.0)
	var rod_basis := Basis.from_euler(Vector3(deg_to_rad(rod_rot_deg.x), 0.0, deg_to_rad(rod_rot_deg.z)))

	var oak_mat := StandardMaterial3D.new()
	oak_mat.vertex_color_use_as_albedo = true
	oak_mat.roughness = 0.72
	oak_mat.metallic = 0.04

	var brass_mat := StandardMaterial3D.new()
	brass_mat.vertex_color_use_as_albedo = true
	brass_mat.roughness = 0.28
	brass_mat.metallic = 0.84

	var cleat := MeshInstance3D.new()
	cleat.name = "FishingRailCleat"
	var cleat_mesh := _build_fishing_rail_cleat_mesh(holder_origin, rod_basis)
	cleat.mesh = cleat_mesh
	cleat.set_surface_override_material(0, oak_mat)
	if cleat_mesh.get_surface_count() > 1:
		cleat.set_surface_override_material(1, brass_mat)
	fishing_line.add_child(cleat)

	var rod_mat := StandardMaterial3D.new()
	rod_mat.vertex_color_use_as_albedo = true
	rod_mat.roughness = 0.44
	rod_mat.metallic = 0.12

	var rod := MeshInstance3D.new()
	rod.name = "FishingRodProp"
	var rod_mesh := _build_stowed_fishing_rod_mesh()
	rod.mesh = rod_mesh
	rod.position = holder_origin
	rod.rotation_degrees = rod_rot_deg
	rod.set_surface_override_material(0, rod_mat)
	if rod_mesh.get_surface_count() > 1:
		rod.set_surface_override_material(1, brass_mat)
	fishing_line.add_child(rod)

	fishing_interactable = Interactable.create("Cast fishing line", 0.85)
	fishing_interactable.name = "FishingInteractable"
	fishing_interactable.position = Vector3(0.0, 0.95, 0.0)
	fishing_interactable.reach = 2.8
	fishing_interactable.interacted.connect(_on_fishing_interacted)
	fishing_line.add_child(fishing_interactable)

	fishing_line.fish_caught.connect(_on_fish_caught)
	fishing_line.line_snapped.connect(_on_fishing_line_snapped)


static func _build_stowed_fishing_rod_mesh() -> ArrayMesh:
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 3-joint tapered bamboo shaft along local +Y (seated inside rail socket from -0.22 to +1.78 m).
	var butt_rings: Array[Array] = [
		[-0.190, 0.025, FishingLine.COL_CORK_GRIP_DARK],
		[-0.080, 0.030, FishingLine.COL_CORK_GRIP],
		[0.045, 0.029, FishingLine.COL_CORK_GRIP],
		[0.120, 0.025, FishingLine.COL_CORK_GRIP_DARK],
	]
	CookingStove._append_lathe_y(wood_st, butt_rings, 8)

	# Joint 1 bamboo (with dark bamboo nodes & thread lashings).
	var j1_rings: Array[Array] = [
		[0.160, 0.022, FishingLine.COL_LASHING],
		[0.195, 0.022, FishingLine.COL_LASHING],
		[0.205, 0.021, FishingLine.COL_BAMBOO],
		[0.345, 0.0195, FishingLine.COL_BAMBOO_HI],
		[0.360, 0.0225, FishingLine.COL_BAMBOO_NODE],
		[0.375, 0.0192, FishingLine.COL_BAMBOO],
		[0.545, 0.0180, FishingLine.COL_BAMBOO_HI],
		[0.560, 0.0205, FishingLine.COL_BAMBOO_NODE],
		[0.575, 0.0178, FishingLine.COL_BAMBOO],
		[0.585, 0.0190, FishingLine.COL_LASHING],
		[0.625, 0.0186, FishingLine.COL_LASHING],
		[0.635, 0.0174, FishingLine.COL_BAMBOO],
		[0.700, 0.0170, FishingLine.COL_BAMBOO],
	]
	CookingStove._append_lathe_y(wood_st, j1_rings, 8)

	# Joint 2 bamboo.
	var j2_rings: Array[Array] = [
		[0.742, 0.0165, FishingLine.COL_LASHING],
		[0.768, 0.0162, FishingLine.COL_LASHING],
		[0.776, 0.0156, FishingLine.COL_BAMBOO],
		[0.925, 0.0144, FishingLine.COL_BAMBOO_HI],
		[0.940, 0.0168, FishingLine.COL_BAMBOO_NODE],
		[0.955, 0.0142, FishingLine.COL_BAMBOO],
		[1.042, 0.0136, FishingLine.COL_BAMBOO_HI],
		[1.050, 0.0148, FishingLine.COL_LASHING],
		[1.084, 0.0144, FishingLine.COL_LASHING],
		[1.092, 0.0132, FishingLine.COL_BAMBOO],
		[1.145, 0.0128, FishingLine.COL_BAMBOO_HI],
		[1.160, 0.0150, FishingLine.COL_BAMBOO_NODE],
		[1.175, 0.0125, FishingLine.COL_BAMBOO],
		[1.280, 0.0120, FishingLine.COL_BAMBOO],
	]
	CookingStove._append_lathe_y(wood_st, j2_rings, 8)

	# Joint 3 slender bamboo tip.
	var j3_rings: Array[Array] = [
		[1.320, 0.0115, FishingLine.COL_LASHING],
		[1.344, 0.0112, FishingLine.COL_LASHING],
		[1.352, 0.0108, FishingLine.COL_BAMBOO],
		[1.462, 0.0096, FishingLine.COL_BAMBOO_HI],
		[1.470, 0.0108, FishingLine.COL_LASHING],
		[1.500, 0.0104, FishingLine.COL_LASHING],
		[1.508, 0.0092, FishingLine.COL_BAMBOO],
		[1.555, 0.0086, FishingLine.COL_BAMBOO_HI],
		[1.568, 0.0102, FishingLine.COL_BAMBOO_NODE],
		[1.580, 0.0082, FishingLine.COL_BAMBOO],
		[1.750, 0.0068, FishingLine.COL_BAMBOO],
	]
	CookingStove._append_lathe_y(wood_st, j3_rings, 8)

	# Brass butt pommel cap, reel seat collar, two 3-joint ferrules & tip-top ferrule.
	var brass_butt: Array[Array] = [
		[-0.222, 0.000, FishingLine.COL_BRASS_DARK],
		[-0.214, 0.027, FishingLine.COL_BRASS],
		[-0.190, 0.028, FishingLine.COL_BRASS_DARK],
	]
	CookingStove._append_lathe_y(brass_st, brass_butt, 8)
	var brass_seat: Array[Array] = [
		[0.118, 0.025, FishingLine.COL_BRASS_DARK],
		[0.125, 0.028, FishingLine.COL_BRASS],
		[0.155, 0.027, FishingLine.COL_BRASS],
		[0.162, 0.022, FishingLine.COL_BRASS_DARK],
	]
	CookingStove._append_lathe_y(brass_st, brass_seat, 8)
	var ferrule_1: Array[Array] = [
		[0.696, 0.0170, FishingLine.COL_BRASS_DARK],
		[0.704, 0.0195, FishingLine.COL_BRASS],
		[0.736, 0.0190, FishingLine.COL_BRASS],
		[0.744, 0.0165, FishingLine.COL_BRASS_DARK],
	]
	CookingStove._append_lathe_y(brass_st, ferrule_1, 8)
	var ferrule_2: Array[Array] = [
		[1.276, 0.0120, FishingLine.COL_BRASS_DARK],
		[1.284, 0.0142, FishingLine.COL_BRASS],
		[1.314, 0.0138, FishingLine.COL_BRASS],
		[1.322, 0.0115, FishingLine.COL_BRASS_DARK],
	]
	CookingStove._append_lathe_y(brass_st, ferrule_2, 8)
	var tip_cap: Array[Array] = [
		[1.748, 0.0068, FishingLine.COL_BRASS_DARK],
		[1.754, 0.0086, FishingLine.COL_BRASS],
		[1.780, 0.0072, FishingLine.COL_BRASS],
		[1.785, 0.000, FishingLine.COL_BRASS_DARK],
	]
	CookingStove._append_lathe_y(brass_st, tip_cap, 8)

	# Turned brass fishing reel drum + wound twine spool + starboard crank handle (at y = 0.14).
	var reel_c := Vector3(0.0, 0.140, 0.062)
	CookingStove._append_cylinder_between(
		brass_st, Vector3(0.0, 0.140, 0.020), reel_c + Vector3(0.0, 0.0, -0.022),
		0.011, 0.013, 6, FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
	)
	CookingStove._append_cylinder_between(
		brass_st, reel_c + Vector3(-0.032, 0.0, 0.0), reel_c + Vector3(-0.022, 0.0, 0.0),
		0.044, 0.046, 10, FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
	)
	CookingStove._append_cylinder_between(
		brass_st, reel_c + Vector3(0.022, 0.0, 0.0), reel_c + Vector3(0.032, 0.0, 0.0),
		0.046, 0.044, 10, FishingLine.COL_BRASS, FishingLine.COL_BRASS_DARK
	)
	CookingStove._append_cylinder_between(
		wood_st, reel_c + Vector3(-0.022, 0.0, 0.0), reel_c + Vector3(0.022, 0.0, 0.0),
		0.035, 0.035, 10, FishingLine.COL_SPOOL_TWINE, FishingLine.COL_SPOOL_TWINE
	)
	CookingStove._append_cylinder_between(
		brass_st, reel_c + Vector3(0.032, 0.0, 0.0), reel_c + Vector3(0.048, 0.0, 0.0),
		0.013, 0.010, 6, FishingLine.COL_BRASS, FishingLine.COL_BRASS_DARK
	)
	var crank_end := reel_c + Vector3(0.048, 0.026, 0.024)
	CookingStove._append_cylinder_between(
		brass_st, reel_c + Vector3(0.044, 0.0, 0.0), crank_end,
		0.0065, 0.0060, 6, FishingLine.COL_BRASS, FishingLine.COL_BRASS
	)
	CookingStove._append_cylinder_between(
		wood_st, crank_end, crank_end + Vector3(0.022, 0.0, 0.0),
		0.010, 0.0085, 6, FishingLine.COL_KNOB_OAK, FishingLine.COL_IVORY
	)

	# 3 tiny brass line-guide rings + gleaming tip-top brass eyelet along +Z underside.
	var guides: Array[Array] = [
		[0.605, 0.035, 0.018, 0.0036, 0.017],
		[1.067, 0.029, 0.015, 0.0033, 0.014],
		[1.485, 0.023, 0.012, 0.0029, 0.010],
	]
	for g in guides:
		var gy := float(g[0])
		var gz := float(g[1])
		var gr := float(g[2])
		var wr := float(g[3])
		var sr := float(g[4])
		var gc := Vector3(0.0, gy, gz)
		FishingLine._append_torus_ring(brass_st, gc, Vector3.UP, gr, wr, 8, 5, FishingLine.COL_BRASS)
		var base_pt := gc + Vector3(0.0, 0.0, -gr)
		CookingStove._append_cylinder_between(
			brass_st, Vector3(0.0, gy - 0.018, sr * 0.72), base_pt,
			wr * 0.9, wr * 0.8, 5, FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
		)
		CookingStove._append_cylinder_between(
			brass_st, Vector3(0.0, gy + 0.018, sr * 0.72), base_pt,
			wr * 0.9, wr * 0.8, 5, FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
		)
	FishingLine._append_torus_ring(
		brass_st, Vector3(0.0, 1.782, 0.012), Vector3.UP, 0.010, 0.0028, 8, 5, FishingLine.COL_BRASS
	)

	wood_st.generate_normals()
	var mesh := wood_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


static func _build_fishing_rail_cleat_mesh(rod_origin: Vector3, rod_basis: Basis) -> ArrayMesh:
	var oak_st := SurfaceTool.new()
	oak_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_oak_hi := Color(0.50, 0.33, 0.19)
	var col_oak_mid := Color(0.38, 0.24, 0.13)
	var col_oak_dark := Color(0.24, 0.15, 0.08)

	# Carved oak deck mounting plinth resting solidly on quarterdeck (y = 0.0) + 4 brass bolts.
	CookingStove._append_beveled_box(
		oak_st, Vector3(0.04, 0.022, 0.12), Vector3(0.22, 0.044, 0.24), 0.010,
		col_oak_hi, col_oak_mid, col_oak_dark
	)
	for bx: float in [-0.045, 0.125]:
		for bz: float in [0.035, 0.205]:
			CookingStove._append_rivet_dome(
				brass_st, Vector3(bx, 0.044, bz), Vector3.UP, 0.011, 0.007, FishingLine.COL_BRASS
			)

	# Stout carved oak stanchion timber rising to rail height + angled oak cradle knee brace.
	CookingStove._append_beveled_box(
		oak_st, Vector3(0.04, 0.34, 0.13), Vector3(0.115, 0.60, 0.125), 0.014,
		col_oak_hi, col_oak_mid, col_oak_dark
	)
	CookingStove._append_beveled_box(
		oak_st, Vector3(0.04, 0.65, 0.16), Vector3(0.135, 0.085, 0.19), 0.012,
		col_oak_hi, col_oak_mid, col_oak_dark
	)
	# Angled oak knee strut bracing the rod-socket cradle back into the post.
	CookingStove._append_cylinder_between(
		oak_st, Vector3(0.04, 0.38, 0.14), Vector3(0.03, 0.56, 0.21),
		0.032, 0.028, 6, col_oak_dark, col_oak_mid
	)

	# Flared brass rod-holder socket tube aligned cleanly with FishingRodProp's butt shaft.
	var ax := rod_basis.y.normalized()
	var sock_bot := rod_origin - ax * 0.25
	var sock_top := rod_origin + ax * 0.015
	CookingStove._append_cylinder_between(
		brass_st, sock_bot, sock_top, 0.036, 0.040, 10,
		FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
	)
	# Rolled flared brass mouth ring, dark hollow socket bore & two proud brass mounting clamp bands.
	FishingLine._append_torus_ring(brass_st, sock_top, ax, 0.041, 0.007, 10, 5, FishingLine.COL_BRASS)
	CookingStove._append_cylinder_between(
		oak_st, sock_top - ax * 0.003, sock_top + ax * 0.002, 0.031, 0.031, 10,
		CookingStove.COL_IRON_SOOT, CookingStove.COL_IRON_SOOT
	)
	FishingLine._append_torus_ring(brass_st, rod_origin - ax * 0.06, ax, 0.042, 0.006, 10, 5, FishingLine.COL_BRASS_DARK)
	FishingLine._append_torus_ring(brass_st, rod_origin - ax * 0.18, ax, 0.040, 0.006, 10, 5, FishingLine.COL_BRASS_DARK)
	# Riveted brass bracket strap linking the socket to the carved oak stanchion.
	CookingStove._append_cylinder_between(
		brass_st, Vector3(0.04, 0.63, 0.15), rod_origin - ax * 0.06,
		0.014, 0.014, 6, FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
	)
	CookingStove._append_cylinder_between(
		brass_st, Vector3(0.04, 0.52, 0.15), rod_origin - ax * 0.18,
		0.014, 0.014, 6, FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
	)

	# Double-horned nautical brass belaying cleat bolted on the inboard (+X) post face!
	var cl_base := Vector3(0.098, 0.46, 0.13)
	CookingStove._append_beveled_box(
		brass_st, cl_base, Vector3(0.018, 0.036, 0.082), 0.004,
		FishingLine.COL_BRASS, FishingLine.COL_BRASS, FishingLine.COL_BRASS_DARK
	)
	for cz: float in [-0.022, 0.022]:
		CookingStove._append_cylinder_between(
			brass_st, cl_base + Vector3(0.008, 0.0, cz), cl_base + Vector3(0.038, 0.0, cz * 0.85),
			0.008, 0.007, 6, FishingLine.COL_BRASS_DARK, FishingLine.COL_BRASS
		)
	CookingStove._append_cylinder_between(
		brass_st, cl_base + Vector3(0.038, 0.0, -0.072), cl_base + Vector3(0.038, 0.0, 0.072),
		0.007, 0.007, 6, FishingLine.COL_BRASS, FishingLine.COL_BRASS
	)
	CookingStove._append_cone_spike(
		brass_st, cl_base + Vector3(0.038, 0.0, -0.070), cl_base + Vector3(0.046, 0.008, -0.098),
		0.007, FishingLine.COL_BRASS, FishingLine.COL_BRASS_DARK
	)
	CookingStove._append_cone_spike(
		brass_st, cl_base + Vector3(0.038, 0.0, 0.070), cl_base + Vector3(0.046, 0.008, 0.098),
		0.007, FishingLine.COL_BRASS, FishingLine.COL_BRASS_DARK
	)

	oak_st.generate_normals()
	var mesh := oak_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


func _build_player_and_crew() -> void:
	# 1. Local Captain Pawn boarded on the quarterdeck facing the bow & Cutlass Cay.
	player_pawn = PAWN_SCENE.instantiate() as Pawn
	player_pawn.name = "PlayerCaptain"
	add_child(player_pawn)
	player_pawn.board(player_ship, _captain_deck_pos(player_ship))
	var bow_fwd := -player_ship.global_basis.z
	player_pawn.look_yaw = atan2(-bow_fwd.x, -bow_fwd.z)

	var p_cv := _character_visual_of(player_pawn)
	if p_cv != null:
		p_cv.set_archetype(&"captain")
		p_cv.set_first_person_hidden(true)

	player_controller = PlayerController.new()
	player_controller.name = "PlayerController"
	player_controller.make_current = true
	player_controller.capture_mouse = (active_shot_mode == "")
	player_controller.input_enabled = (active_shot_mode == "")
	player_pawn.add_child(player_controller)

	player_combat = CombatComponent.new()
	player_combat.name = "CombatComponent"
	player_combat.faction = &"player"
	player_combat.equipped_weapon = &"cutlass"
	player_pawn.add_child(player_combat)

	inventory = Inventory.new()
	inventory.name = "Inventory"
	inventory.input_enabled = (active_shot_mode == "")
	player_pawn.add_child(inventory)
	inventory.bind(player_pawn, player_controller, player_combat, p_cv)

	player_pawn.died.connect(_on_player_died)
	Net.register_replicated_pawn(Net.local_id(), player_pawn)

	# 2. Three AI Crewmates: Barnaby (helmsman), Maren (lookout), Pip (carpenter).
	crew_pawns.clear()
	crew_brains.clear()
	for spec in _crew_specs_for(player_ship):
		var persona: StringName = spec["persona"]
		var local_pos: Vector3 = spec["local_pos"]
		var cp := PAWN_SCENE.instantiate() as Pawn
		cp.name = "Crew_" + String(persona).capitalize()
		add_child(cp)
		cp.board(player_ship, local_pos)
		cp.look_yaw = player_pawn.look_yaw

		var c_cv := _character_visual_of(cp)
		if c_cv != null:
			c_cv.set_archetype(persona)

		var c_cc := CombatComponent.new()
		c_cc.name = "CombatComponent"
		c_cc.faction = &"player"
		c_cc.equipped_weapon = &"cutlass"
		cp.add_child(c_cc)

		var brain := CrewBrain.new()
		brain.name = "CrewBrain"
		brain.setup(player_ship, player_pawn, persona)
		cp.add_child(brain)

		crew_pawns.append(cp)
		crew_brains.append(brain)


func _build_voyage_and_director() -> void:
	voyage_manager = VoyageManager.new()
	voyage_manager.name = "VoyageManager"
	add_child(voyage_manager)

	world_director = WorldDirector.new()
	world_director.name = "WorldDirector"
	world_director.player_ship = player_ship
	world_director.enabled = true
	# Stepped explicitly from Main._physics_process so safe-harbour outposts & swimmers are supplied.
	world_director.set_physics_process(false)
	var home_outpost := archipelago.get_outpost(0)
	if home_outpost != null:
		world_director.set_last_outpost(StringName(home_outpost.island_id), home_outpost.global_position)
	add_child(world_director)

	# Wire MapTableView live references.
	if map_table != null:
		map_table.voyage_manager = voyage_manager
		map_table.world_director = world_director
		map_table.refresh_now()

	# Apply Economy sidegrades, liveries & crew traits from Game.profile.
	ShipwrightMenu.apply_economy_to_ship(player_ship, Game.profile, crew_brains, world_director)


func _build_ui() -> void:
	hud = GameHUD.new()
	hud.name = "GameHUD"
	hud.input_enabled = (active_shot_mode == "")
	add_child(hud)
	hud.bind(player_pawn, player_controller, inventory, player_combat, player_ship, voyage_manager, sky_rig)
	for b in crew_brains:
		hud.register_crew_brain(b)

	shipwright_menu = ShipwrightMenu.new()
	shipwright_menu.name = "ShipwrightMenu"
	add_child(shipwright_menu)
	shipwright_menu.bind(
		voyage_manager,
		archipelago,
		player_ship,
		player_controller,
		user_settings,
		inventory,
		map_table,
		crew_brains,
		world_director,
		self
	)
	shipwright_menu.menu_opened.connect(_on_shipwright_opened)
	shipwright_menu.menu_closed.connect(_on_shipwright_closed)
	shipwright_menu.voyage_accepted.connect(_on_voyage_started)
	shipwright_menu.ship_class_selected.connect(_on_ship_class_selected)
	shipwright_menu.settings_changed.connect(_on_settings_changed)


func _wire_world_signals() -> void:
	# Wire every Outpost's Voyage Board & Merchant Stall signals.
	for outpost in archipelago.get_outposts():
		var out_id := StringName(outpost.island_id)
		outpost.voyage_board_used.connect(func(_pawn: Node) -> void:
			_on_outpost_voyage_board_used(out_id)
		)
		outpost.treasure_sold.connect(_on_outpost_treasure_sold)

	# Wire every DigSite currently on every island + emergent beach MessageBottles.
	for isl in archipelago.get_islands():
		for ds in isl.get_dig_sites():
			_wire_dig_site(ds)
	_wire_message_bottles()

	# VoyageManager signals.
	voyage_manager.voyage_started.connect(_on_voyage_started)
	voyage_manager.voyage_completed.connect(_on_voyage_completed)

	# WorldDirector living-sea event signals.
	world_director.spawn_rival_ship.connect(_on_director_spawn_rival_ship)
	world_director.spawn_ghost_ship.connect(_on_director_spawn_ghost_ship)
	world_director.spawn_shark_pack.connect(_on_director_spawn_shark_pack)
	world_director.spawn_leviathan.connect(_on_director_spawn_leviathan)
	world_director.spawn_flotsam_barrels.connect(_on_director_spawn_flotsam)
	world_director.spawn_fort_siege.connect(_on_director_spawn_fort_siege)
	world_director.spawn_castaway.connect(_on_director_spawn_castaway)
	world_director.spawn_storm_cell.connect(_on_director_spawn_storm_cell)
	world_director.sighting_warning.connect(_on_director_sighting_warning)

	# Ship sinking -> zero-wipe salvage wreck & restore at last outpost.
	player_ship.sunk.connect(_on_player_ship_sunk)
	player_ship.hull_impacted.connect(_on_player_ship_hull_impacted)

	# Autoload signals (cleaned up in _exit_tree).
	if not Weather.thunder_heard.is_connected(_on_thunder_heard):
		Weather.thunder_heard.connect(_on_thunder_heard)
	if not Net.peer_joined.is_connected(_on_net_peer_joined):
		Net.peer_joined.connect(_on_net_peer_joined)
	if not Net.peer_left.is_connected(_on_net_peer_left):
		Net.peer_left.connect(_on_net_peer_left)
	if not Net.client_intent_received.is_connected(_on_net_client_intent):
		Net.client_intent_received.connect(_on_net_client_intent)


func _disconnect_autoload_signals() -> void:
	if Weather != null and Weather.thunder_heard.is_connected(_on_thunder_heard):
		Weather.thunder_heard.disconnect(_on_thunder_heard)
	if Net != null:
		if Net.peer_joined.is_connected(_on_net_peer_joined):
			Net.peer_joined.disconnect(_on_net_peer_joined)
		if Net.peer_left.is_connected(_on_net_peer_left):
			Net.peer_left.disconnect(_on_net_peer_left)
		if Net.client_intent_received.is_connected(_on_net_client_intent):
			Net.client_intent_received.disconnect(_on_net_client_intent)


func _apply_cli_overrides() -> void:
	if not is_nan(_cli_time):
		Weather.time_of_day = _cli_time
	if not is_nan(_cli_cloud):
		Weather.cloudiness = _cli_cloud
	if not is_nan(_cli_storm):
		Weather.storminess = _cli_storm
		Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, _cli_storm)
	if _cli_quality != "":
		var lv := 1
		if _cli_quality == "low":
			lv = 0
		elif _cli_quality == "high":
			lv = 2
		if ocean != null:
			ocean.quality = lv as Ocean.Quality
		if sky_rig != null:
			sky_rig.set(&"cloud_quality", lv)
	elif active_shot_mode != "":
		# Showcase captures always default to flagship quality regardless of local settings.json.
		if ocean != null:
			ocean.quality = Ocean.Quality.HIGH
		if sky_rig != null:
			sky_rig.set(&"cloud_quality", 2)


# ==============================================================================
# Frame & Physics Ticks
# ==============================================================================

func _process(delta: float) -> void:
	_tick_bobbing_props(delta)
	_tick_hero_shot_tracking(delta)
	_tick_boss_hud()
	_update_live_audio(false)
	_music_accum += delta
	if _music_accum >= 1.0:
		_music_accum = 0.0
		_update_adaptive_music(false)


func _tick_boss_hud() -> void:
	if hud == null or player_ship == null or not is_instance_valid(player_ship):
		return
	var origin := player_pawn.global_position if (player_pawn != null and is_instance_valid(player_pawn)) else player_ship.global_position
	for lev in active_leviathans:
		if lev != null and is_instance_valid(lev) and not lev.is_defeated():
			if lev.global_position.distance_to(origin) < 130.0:
				var ratio := lev.get_health_ratio()
				hud.set_boss_encounter("ABYSSAL LEVIATHAN", ratio, true)
				return
	for foe in active_enemies:
		if foe != null and is_instance_valid(foe) and not foe.dead:
			if foe.global_position.distance_to(origin) < 42.0:
				var cv := _character_visual_of(foe)
				var arch := cv.get_archetype() if cv != null else &""
				if arch == &"drowned_captain" or arch == &"rival_captain":
					var label := "RIVAL CORSAIR CAPTAIN" if arch == &"rival_captain" else "DROWNED CAPTAIN"
					hud.set_boss_encounter(label, clampf(foe.health / maxf(foe.max_health, 1.0), 0.0, 1.0), true)
					return
	hud.set_boss_encounter("", 0.0, false)


func _physics_process(delta: float) -> void:
	# Step fishing line if active.
	_tick_fishing(delta)

	if not Net.is_host():
		_send_local_client_intent()
		return

	# Player auto-revive back aboard ship if downed.
	if _revive_timer > 0.0:
		_revive_timer -= delta
		if _revive_timer <= 0.0:
			_revive_timer = -1.0
			_revive_player_aboard_ship()

	# Periodic island discovery, voyage arrival, cargo hazard & WorldDirector checks.
	_cargo_check_accum += delta
	if _cargo_check_accum >= 0.45:
		var dt := _cargo_check_accum
		_cargo_check_accum = 0.0
		_tick_aboard_treasures(dt)
		_check_return_complication()

	_discovery_accum += delta
	if _discovery_accum >= 0.60:
		_discovery_accum = 0.0
		_tick_discovery_and_arrivals()

	_tick_world_director(delta)


func _tick_world_director(delta: float) -> void:
	if world_director == null or not world_director.enabled:
		return
	if player_ship == null or not is_instance_valid(player_ship) or player_ship.is_sinking:
		return

	var swimming_deep := false
	var swimmer_pos := player_ship.global_position
	if player_pawn != null and is_instance_valid(player_pawn) and player_pawn.is_swimming():
		var near_isl := archipelago.nearest_island(player_pawn.global_position)
		if near_isl == null or near_isl.seabed_depth(player_pawn.global_position) > 6.0:
			swimming_deep = true
			swimmer_pos = player_pawn.global_position

	world_director.step(delta, {
		"ship_pos": player_ship.global_position,
		"ship_velocity": player_ship.linear_velocity,
		"ship_forward": -player_ship.global_basis.z,
		"ship_node": player_ship,
		"cargo_value": world_director.cargo_value_aboard,
		"outpost_positions": _outpost_positions_array(),
		"pawn_swimming_deep": swimming_deep,
		"swimmer_pos": swimmer_pos,
		"voyage_count": voyage_manager.completed_count if voyage_manager != null else 0,
	})


func _tick_discovery_and_arrivals() -> void:
	if archipelago == null or player_ship == null or not is_instance_valid(player_ship):
		return
	var check_points: Array[Vector3] = [player_ship.global_position]
	if player_pawn != null and is_instance_valid(player_pawn):
		check_points.append(player_pawn.global_position)

	for pt in check_points:
		var newly_found := archipelago.check_discovery(pt)
		if newly_found != null:
			_play_stinger_safe(&"discovery", &"ship_sighted")
			if map_table != null:
				map_table.set_archipelago_data(_build_chart_map_data())
				map_table.refresh_now()
			Game.save()

	# Check arrival at islands for voyage progression & last-outpost bookmarking.
	var near_isl := archipelago.nearest_island(player_ship.global_position)
	if near_isl != null:
		var d := Vector2(
			player_ship.global_position.x - near_isl.global_position.x,
			player_ship.global_position.z - near_isl.global_position.z
		).length()
		if d <= near_isl.island_radius + 75.0:
			if near_isl is Outpost:
				world_director.set_last_outpost(StringName(near_isl.island_id), near_isl.global_position)
				if player_ship.cannonballs_remaining < Ship.MAX_CANNONBALLS \
						or player_ship.planks_remaining < Ship.MAX_PLANKS:
					(near_isl as Outpost).restock_ship(player_ship)
			if voyage_manager != null and voyage_manager.has_active_voyage():
				voyage_manager.notify_island_arrived(StringName(near_isl.island_id))


func _tick_aboard_treasures(dt: float) -> void:
	var aboard := _collect_aboard_treasures()
	var res := TreasureCatalog.step_aboard_hazards(aboard, player_ship, dt)
	if world_director != null:
		world_director.cargo_value_aboard = int(res.get("total_cargo_value", 0))

	if voyage_manager != null and voyage_manager.has_active_voyage():
		for item in aboard:
			var iid: int = (item as Object).get_instance_id()
			if not _boarded_chests.has(iid):
				_boarded_chests[iid] = true
				voyage_manager.notify_treasure_boarded(item)


func _update_cargo_value() -> int:
	var aboard := _collect_aboard_treasures()
	var total := WorldDirector.sum_cargo_value(aboard)
	if world_director != null:
		world_director.cargo_value_aboard = total
	return total


func _collect_aboard_treasures() -> Array:
	var out: Array = []
	if player_ship == null or not is_instance_valid(player_ship) or not is_inside_tree():
		return out
	var inv_xf := player_ship.global_transform.affine_inverse()
	for node in get_tree().get_nodes_in_group(TreasureCatalog.TREASURE_GROUP):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if node.has_meta(&"_merchant_sold"):
			continue
		var holder: Variant = node.get(&"holder")
		if holder is Pawn and (holder as Pawn).platform == player_ship:
			out.append(node)
			continue
		var local_p := inv_xf * (node as Node3D).global_position
		if absf(local_p.x) <= 2.6 and absf(local_p.z) <= 7.0 and local_p.y >= -1.4 and local_p.y <= 3.6:
			out.append(node)
	return out


func _check_return_complication() -> void:
	if _return_complication_fired or voyage_manager == null or not voyage_manager.is_hauling_home():
		return
	var comp: Dictionary = voyage_manager.active_voyage.get("complication", {})
	if StringName(String(comp.get("trigger", &""))) != &"on_return":
		return
	if player_ship == null or player_ship.anchor_down:
		return
	var target_id := String(voyage_manager.active_voyage.get("target_island_id", ""))
	var target_isl := archipelago.get_island_by_id(target_id)
	if target_isl != null:
		var dist_from_isl := player_ship.global_position.distance_to(target_isl.global_position)
		if dist_from_isl < target_isl.island_radius + 70.0:
			return
	_return_complication_fired = true
	var threat := StringName(String(comp.get("threat_archetype", &"drowned_sloop")))
	if threat == &"drowned_sloop" or threat == &"ghost_ship" or threat == &"storm_cell":
		world_director.trigger_event(threat, {
			"ship_pos": player_ship.global_position,
			"ship_forward": -player_ship.global_basis.z,
			"ship_node": player_ship,
		})


# ==============================================================================
# Voyage World Setup & Gameplay Event Callbacks
# ==============================================================================

func _on_voyage_started(voyage: Dictionary) -> void:
	if not Net.is_host():
		return
	_prepare_active_voyage_world(voyage)


func _prepare_active_voyage_world(voyage: Dictionary) -> void:
	if voyage.is_empty() or archipelago == null:
		return
	var vid := String(voyage.get("id", ""))
	var already_built := (vid != "" and vid == _spawned_voyage_id)
	_spawned_voyage_id = vid
	_return_complication_fired = false

	var target_id := String(voyage.get("target_island_id", ""))
	var target_isl := archipelago.get_island_by_id(target_id)
	var payoff: Dictionary = voyage.get("payoff", {})
	var treasures: Array = payoff.get("treasures", [])
	var primary_tid: StringName = StringName(String(treasures[0])) if not treasures.is_empty() else &"wayfarer_chest"
	var shape := StringName(String(voyage.get("shape", &"buried_hoard")))

	var dig_local := Vector3.ZERO
	if target_isl != null:
		# Ensure target island has a live DigSite for dig/riddle/wreck voyages.
		var site_dict: Dictionary = voyage.get("site", {})
		var want_digs := int(site_dict.get("dig_count", 0))
		if want_digs > 0 or shape == &"buried_hoard" or shape == &"riddle_trail" or shape == &"wreck_salvage":
			var live_site := _ensure_island_dig_site(target_isl, primary_tid)
			if live_site != null:
				dig_local = live_site.position
		elif not target_isl.dig_points.is_empty():
			dig_local = target_isl.dig_points[0]

		# Activate Fort Bastion signal brazier & coastal sea-batteries + FortVault + Sovereign hoard.
		if shape == &"fort_siege":
			var bastion := target_isl.get_node_or_null(^"FortBastion") as Node3D
			if bastion != null:
				dig_local = bastion.position
				if bastion.has_method(&"set_siege_active"):
					bastion.call(&"set_siege_active", true)
				_ensure_fort_vault(bastion)
			if not already_built:
				var vault_world: Vector3
				if bastion != null:
					vault_world = bastion.global_transform * Vector3(0.0, 0.38, 0.0)
				else:
					var vault_local := target_isl.dig_points[0] if not target_isl.dig_points.is_empty() else Vector3.ZERO
					vault_local.y = target_isl.surface_height(vault_local.x, vault_local.z) + 0.35
					vault_world = target_isl.global_transform * vault_local
				var vault_chest := TreasureCatalog.create_treasure_carryable(primary_tid, vault_world)
				_entities_root.add_child(vault_chest)
				vault_chest.global_position = vault_world

		# Spawn island guardians once per voyage start.
		if not already_built:
			_spawn_voyage_guardians(target_isl, voyage)

		# Sync held treasure map & MapTableView.
		if inventory != null:
			inventory.set_treasure_map(
				target_isl.display_name,
				target_isl.contour_points,
				dig_local,
				target_isl.island_radius
			)
		if map_table != null:
			map_table.set_voyage_target(target_isl.global_position)
			map_table.refresh_now()

	if not already_built:
		if shape == &"cargo_run":
			_spawn_cargo_run_crates(voyage)
		elif shape == &"open_sea_hunt":
			var hunt_pos: Vector3 = voyage.get("target_position", Vector3(300.0, 0.0, -300.0))
			var threat := StringName(String(voyage.get("complication", {}).get("threat_archetype", &"drowned_sloop")))
			_spawn_enemy_vessel(threat, hunt_pos)


func _ensure_island_dig_site(isl: Island, tid: StringName) -> DigSite:
	for ds in isl.get_dig_sites():
		if not ds.is_unearthed:
			ds.treasure_id = tid
			_wire_dig_site(ds)
			return ds
	var pt := isl.dig_points[0] if not isl.dig_points.is_empty() else Vector3(0.0, 0.0, 12.0)
	var created := isl.spawn_dig_site(pt, tid)
	_wire_dig_site(created)
	return created


func _wire_dig_site(ds: DigSite) -> void:
	if ds == null or not is_instance_valid(ds):
		return
	var iid := ds.get_instance_id()
	if _wired_dig_sites.has(iid):
		return
	_wired_dig_sites[iid] = true
	ds.unearthed.connect(_on_dig_site_unearthed)


func _spawn_voyage_guardians(isl: Island, voyage: Dictionary) -> void:
	var site_info: Dictionary = voyage.get("site", {})
	var faction := StringName(String(site_info.get("enemy_faction", &"drowned")))
	if faction == &"none" or faction == &"sharks":
		return

	var archetypes: Array[StringName] = []
	if String(voyage.get("id", "")) == "story_ch1_salt_kings_ledger" or isl.island_id == "cutlass_cay":
		# Story Chapter 1 guarantees all 4 distinct Drowned archetypes on Cutlass Cay!
		archetypes = [&"drowned_cutlass", &"drowned_shield", &"drowned_powder", &"drowned_captain"]
	elif faction == &"tidecallers":
		archetypes = [&"tidecaller", &"drowned_cutlass", &"tidecaller"]
	else:
		archetypes = [&"drowned_cutlass", &"drowned_shield", &"drowned_powder"]
		if bool(site_info.get("has_captain", false)):
			archetypes.append(&"drowned_captain")

	var spawns := isl.enemy_spawns
	for i in archetypes.size():
		var local_pt := Vector3(float(i - 1) * 4.5, 0.0, 10.0)
		if not spawns.is_empty():
			local_pt = spawns[i % spawns.size()]
		local_pt.y = isl.surface_height(local_pt.x, local_pt.z) + 0.15
		var world_pt := isl.global_transform * local_pt
		_spawn_enemy_pawn(archetypes[i], world_pt)


func _spawn_cargo_run_crates(voyage: Dictionary) -> void:
	var origin_id := String(voyage.get("origin_outpost_id", "port_scoundrel"))
	var origin_outpost := archipelago.get_island_by_id(origin_id) as Outpost
	var spawn_base := player_ship.global_transform * Vector3(0.0, 1.35, -1.6)
	if origin_outpost != null:
		spawn_base = origin_outpost.get_world_pier_end() + Vector3(0.0, 1.4, 0.0)
	var treasures: Array = voyage.get("payoff", {}).get("treasures", [&"spice_crate"])
	for i in mini(treasures.size(), 2):
		var pos := spawn_base + Vector3(float(i) * 0.9, 0.2, 0.0)
		var crate := TreasureCatalog.create_treasure_carryable(&"spice_crate", pos)
		_entities_root.add_child(crate)
		crate.global_position = pos


func _on_dig_site_unearthed(chest: Carryable) -> void:
	if not Net.is_host():
		return
	if voyage_manager != null and voyage_manager.has_active_voyage():
		voyage_manager.notify_treasure_unearthed(chest)
	_update_cargo_value()


func _on_outpost_treasure_sold(item: Node, gold: int, renown: int) -> void:
	if not Net.is_host():
		return
	var base := TreasureCatalog.inspect_carryable(item)
	var fallback_nm: Variant = item.get(&"item_name") if item != null and is_instance_valid(item) else "Treasure"
	var sale_receipt := {
		"ok": true,
		"treasure_id": base.get("treasure_id", &"plain_cargo"),
		"name": String(base.get("name", String(fallback_nm))),
		"company_id": base.get("company_id", &"gilded_compass"),
		"gold_awarded": gold,
		"renown_awarded": renown,
		"rank_up_notice": "",
	}
	if voyage_manager != null:
		voyage_manager.notify_treasure_sold(sale_receipt)
	_update_cargo_value()
	Game.save()
	if shipwright_menu != null and shipwright_menu.is_open:
		shipwright_menu.refresh()


func _on_voyage_completed(_voyage: Dictionary, summary: Dictionary) -> void:
	if not Net.is_host():
		return
	Audio.play_stinger(&"victory")
	if map_table != null:
		map_table.set_voyage_target(Vector3.INF)
		map_table.refresh_now()
	if bool(summary.get("is_story", false)) and shipwright_menu != null:
		var next_ch := mini(VoyageComposer.STORY_CHAPTER_COUNT, int(summary.get("story_chapter", 1)) + 1)
		shipwright_menu.selected_story_chapter = next_ch
	Game.save()


# ==============================================================================
# WorldDirector Living-Sea Spawners & Ship Sinking Salvage
# ==============================================================================

func _on_director_spawn_rival_ship(spawn_pos: Vector3, archetype: StringName, _target: Node) -> void:
	_spawn_enemy_vessel(archetype, spawn_pos)


func _on_director_spawn_ghost_ship(spawn_pos: Vector3) -> void:
	_spawn_enemy_vessel(&"ghost_ship", spawn_pos)


func _on_director_spawn_shark_pack(center: Vector3, count: int) -> void:
	if not Net.is_host():
		return
	for i in maxi(1, count):
		var ang := float(i) / float(maxi(1, count)) * TAU
		var pos := Vector3(center.x + cos(ang) * 9.0, Sea.height(center.x, center.z) - 0.35, center.z + sin(ang) * 9.0)
		var shark := Shark.new()
		shark.name = "Shark_%d" % i
		_entities_root.add_child(shark)
		shark.global_position = pos
		active_sharks.append(shark)


func _on_director_spawn_leviathan(center: Vector3, target: Node) -> void:
	if not Net.is_host():
		return
	var lev := Leviathan.new()
	lev.target_ship = target as Ship if target is Ship else player_ship
	lev.position = Vector3(center.x, 0.0, center.z)
	_entities_root.add_child(lev)
	lev.global_position = Vector3(center.x, 0.0, center.z)
	active_leviathans.append(lev)


func _on_director_spawn_flotsam(pos: Vector3, count: int) -> void:
	if not Net.is_host():
		return
	# Spawn bobbing salvage barrels/crates plus one real floating treasure chest!
	for i in maxi(1, count):
		var ang := float(i) / float(maxi(1, count)) * TAU + 0.3
		var rad := 2.4 + float(i % 2) * 2.2
		var bx := pos.x + cos(ang) * rad
		var bz := pos.z + sin(ang) * rad
		var prop_scene := BARREL_PROP_SCENE if (i % 2 == 0) else CRATE_PROP_SCENE
		var barrel := prop_scene.instantiate() as Node3D
		barrel.name = "FlotsamBarrel_%d" % i
		_entities_root.add_child(barrel)
		barrel.global_position = Vector3(bx, Sea.height(bx, bz) - 0.15, bz)
		var it := Interactable.create("Salvage flotsam supplies", 1.2)
		it.position = Vector3(0.0, 0.55, 0.0)
		it.interacted.connect(func(_p: Node) -> void:
			if not Net.is_host():
				return
			if player_ship != null and is_instance_valid(player_ship):
				player_ship.cannonballs_remaining = mini(Ship.MAX_CANNONBALLS, player_ship.cannonballs_remaining + 6)
				player_ship.planks_remaining = mini(Ship.MAX_PLANKS, player_ship.planks_remaining + 4)
			Game.profile.add_gold(35)
			Audio.play_sfx(&"coin_jingle", barrel.global_position)
			Game.post_notice("Salvaged supplies & 35 gold from flotsam!")
			barrel.queue_free()
		)
		barrel.add_child(it)
		_bobbing_props.append({"node": barrel, "x": bx, "z": bz, "y_off": -0.18, "phase": float(i) * 1.3})

	var chest_pos := Vector3(pos.x, Sea.height(pos.x, pos.z) + 0.25, pos.z)
	var chest := TreasureCatalog.create_treasure_carryable(&"driftwood_chest", chest_pos)
	_entities_root.add_child(chest)
	chest.global_position = chest_pos

	# Circling gulls mark floating flotsam from the horizon ("gulls that mark loot").
	var flotsam_gulls := SeabirdFlock.spawn_over(_entities_root, Vector3(pos.x, 0.0, pos.z), 11.0, 14.0, 5)
	flotsam_gulls.is_loot_marker = true


func _on_director_spawn_fort_siege(fort_pos: Vector3, _bearing: String) -> void:
	if not Net.is_host():
		return
	var fort := archipelago.get_island_by_id("ironwatch_fort")
	if fort == null:
		fort = archipelago.nearest_island(fort_pos)
	if fort == null:
		return

	var defenders: Array[StringName] = [
		&"drowned_cutlass",
		&"drowned_shield",
		&"drowned_powder",
		&"tidecaller",
		&"drowned_captain",
	]
	for i in defenders.size():
		var local_pt := Vector3(float(i - 2) * 3.8, 0.0, 8.0)
		if not fort.enemy_spawns.is_empty():
			local_pt = fort.enemy_spawns[i % fort.enemy_spawns.size()]
		local_pt.y = fort.surface_height(local_pt.x, local_pt.z) + 0.15
		_spawn_enemy_pawn(defenders[i], fort.global_transform * local_pt)

	# Activate Ironwatch Fort's blazing Signal Brazier, coastal batteries & locked FortVault gate!
	var bastion := fort.get_node_or_null(^"FortBastion") as Node3D
	if bastion != null:
		if bastion.has_method(&"set_siege_active"):
			bastion.call(&"set_siege_active", true)
		_ensure_fort_vault(bastion)

	# Place Sovereign Chest hoard on the fort courtyard dais behind the barred FortVault gate!
	var vault_world: Vector3
	if bastion != null:
		vault_world = bastion.global_transform * Vector3(0.0, 0.38, 0.0)
	else:
		var vault_local := fort.dig_points[0] if not fort.dig_points.is_empty() else Vector3.ZERO
		vault_local.y = fort.surface_height(vault_local.x, vault_local.z) + 0.35
		vault_world = fort.global_transform * vault_local
	var vault_chest := TreasureCatalog.create_treasure_carryable(&"sovereign_chest", vault_world)
	_entities_root.add_child(vault_chest)
	vault_chest.global_position = vault_world


func _ensure_fort_vault(bastion: Node3D) -> Node3D:
	if bastion == null or not is_instance_valid(bastion):
		return null
	var vault := bastion.get_node_or_null(^"FortVault") as Node3D
	if vault == null:
		vault = FORT_VAULT_SCRIPT.new() as Node3D
		vault.name = "FortVault"
		# Fits flush inside FortBastion Bay 0 stone gateway (WALL_R = 11.4, courtyard floor y = 0.06).
		vault.position = Vector3(0.0, 0.06, -11.4)
		bastion.add_child(vault)

	var bats := _collect_bastion_batteries(bastion)
	var alive_count := 0
	for bat in bats:
		if not bat.destroyed:
			alive_count += 1
		if not bat.has_meta(&"fort_vault_wired"):
			bat.set_meta(&"fort_vault_wired", true)
			bat.battery_destroyed.connect(func(_b: FortBattery) -> void:
				_check_fort_vault_unlock(bastion, vault)
			)

	if vault.has_method(&"set_siege_cleared"):
		vault.call(&"set_siege_cleared", alive_count == 0)
	return vault


func _check_fort_vault_unlock(bastion: Node3D, vault: Node3D) -> void:
	if not Net.is_host() or bastion == null or not is_instance_valid(bastion):
		return
	if vault == null or not is_instance_valid(vault):
		return
	for bat in _collect_bastion_batteries(bastion):
		if not bat.destroyed:
			return
	if vault.has_method(&"set_siege_cleared"):
		vault.call(&"set_siege_cleared", true)
	if vault.has_method(&"open_vault"):
		vault.call(&"open_vault")


static func _collect_bastion_batteries(bastion: Node3D) -> Array[FortBattery]:
	var out: Array[FortBattery] = []
	if bastion == null or not is_instance_valid(bastion):
		return out
	var raw_bats: Variant = bastion.get(&"batteries")
	if raw_bats is Array:
		for item in (raw_bats as Array):
			if item is FortBattery and is_instance_valid(item) and not out.has(item as FortBattery):
				out.append(item as FortBattery)
	for child in bastion.get_children():
		if child is FortBattery and is_instance_valid(child) and not out.has(child as FortBattery):
			out.append(child as FortBattery)
	return out


func _wire_message_bottles() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for bottle in tree.get_nodes_in_group(&"message_bottles"):
		if bottle == null or not is_instance_valid(bottle):
			continue
		if bottle.has_meta(&"bottle_wired") or not bottle.has_signal(&"bottle_collected"):
			continue
		bottle.set_meta(&"bottle_wired", true)
		var arg_count := 2
		for sig_info in bottle.get_signal_list():
			var sd: Dictionary = sig_info as Dictionary
			if StringName(sd.get("name", &"")) == &"bottle_collected":
				arg_count = (sd.get("args", []) as Array).size()
				break
		if arg_count == 1:
			bottle.connect(&"bottle_collected", func(a: Variant) -> void:
				_on_message_bottle_collected(bottle, a, null)
			)
		elif arg_count == 3:
			bottle.connect(&"bottle_collected", func(a: Variant, b: Variant, c: Variant) -> void:
				var clue_v: Variant = b if b is Dictionary else a
				_on_message_bottle_collected(bottle, clue_v, c as Node)
			)
		else:
			bottle.connect(&"bottle_collected", func(a: Variant, b: Variant) -> void:
				var clue_v: Variant = a if a is Dictionary else b
				var col_n: Node = b as Node if b is Node else (a as Node if a is Node else null)
				_on_message_bottle_collected(bottle, clue_v, col_n)
			)


func _on_message_bottle_collected(bottle: Node, clue_arg: Variant, _collector: Node) -> void:
	if not Net.is_host() or archipelago == null:
		return
	var clue: Dictionary = {}
	if clue_arg is Dictionary:
		clue = clue_arg as Dictionary
	elif bottle != null and is_instance_valid(bottle):
		if bottle.has_method(&"get_clue"):
			var c_res: Variant = bottle.call(&"get_clue")
			if c_res is Dictionary:
				clue = c_res as Dictionary
		elif bottle.get(&"clue") is Dictionary:
			clue = bottle.get(&"clue") as Dictionary
		else:
			clue = {
				"target_island_id": String(bottle.get(&"target_island_id")),
				"treasure_id": bottle.get(&"treasure_id"),
			}

	var target_id := String(clue.get("target_island_id", ""))
	var target_isl := archipelago.get_island_by_id(target_id) if target_id != "" else null
	if target_isl == null:
		target_isl = archipelago.get_island_by_id("cutlass_cay")
	if target_isl == null:
		for isl in archipelago.get_islands():
			if not (isl is Outpost):
				target_isl = isl
				break
	if target_isl == null:
		return

	var tid := StringName(String(clue.get("treasure_id", &"captains_skull")))
	if not TreasureCatalog.has_treasure(tid):
		tid = &"archive_chalice"

	# Pick an unused dig_points spot on the target island (or a clean offset beach clearing).
	var existing_sites := target_isl.get_dig_sites()
	var chosen_spot := Vector3.ZERO
	var found_unused := false
	for cand in target_isl.dig_points:
		var busy := false
		for ds in existing_sites:
			if ds != null and is_instance_valid(ds) and ds.position.distance_to(cand) < 2.6:
				busy = true
				break
		if not busy:
			chosen_spot = cand
			found_unused = true
			break
	if not found_unused:
		var base_pt := target_isl.dig_points[0] if not target_isl.dig_points.is_empty() else Vector3(0.0, 0.0, 12.0)
		chosen_spot = base_pt + Vector3(3.4, 0.0, -2.2)
		chosen_spot.y = target_isl.surface_height(chosen_spot.x, chosen_spot.z)

	var bonus_site := target_isl.spawn_dig_site(chosen_spot, tid)
	_wire_dig_site(bonus_site)

	var t_entry := TreasureCatalog.get_entry(tid)
	var t_name := String(t_entry.get("name", "Buried Hoard"))
	var company_str := String(t_entry.get("company_id", &"gilded_compass"))
	if Game != null and Game.profile != null:
		Game.profile.add_renown(company_str, 35)
		Game.save()
	Audio.play_stinger(&"discovery")
	Game.post_notice("Message in a Bottle! Rumor of a buried %s on %s!" % [t_name, target_isl.display_name])


func _on_director_spawn_castaway(pos: Vector3) -> void:
	if not Net.is_host():
		return
	var raft := CastawayRaft.new()
	raft.name = "CastawayRaft"
	_entities_root.add_child(raft)
	raft.global_position = Vector3(pos.x, Sea.height(pos.x, pos.z), pos.z)

	# Circling gulls draw the captain's eye to the drifting castaway from afar.
	var raft_gulls := SeabirdFlock.spawn_over(_entities_root, Vector3(pos.x, 0.0, pos.z), 10.0, 13.0, 4)
	raft_gulls.is_loot_marker = true

	raft.rescued.connect(func(r: CastawayRaft, _rescuer: Node) -> void:
		if not Net.is_host():
			return
		Game.profile.add_gold(150)
		Game.save()
		Audio.play_sfx(&"coin_jingle", r.global_position)
		Game.post_notice("Castaway rescued! 'Bless ye, Cap'n - take 150 gold & beware Ironwatch Fort!'")
		if is_instance_valid(raft_gulls):
			raft_gulls.queue_free()
		r.queue_free()
	)


func _on_director_spawn_storm_cell(_center: Vector3, _radius: float, _velocity: Vector3) -> void:
	if map_table != null:
		map_table.refresh_now()


func _on_director_sighting_warning(_msg: String, _pos: Vector3, event_kind: StringName,
		_bearing: String, _dist: float) -> void:
	if event_kind == &"rival_ship" or event_kind == &"ghost_ship":
		Audio.play_stinger(&"ship_sighted")
	elif event_kind == &"leviathan" or event_kind == &"fort_siege":
		Audio.play_stinger(&"danger")


func _on_player_ship_sunk() -> void:
	if not Net.is_host() or _ship_restoring:
		return
	_ship_restoring = true
	var wreck_pos := player_ship.global_position
	var aboard := _collect_aboard_treasures()

	# Record ~60% salvage wreck through WorldDirector (never a wipe!).
	var wreck := world_director.record_ship_wreck(wreck_pos, aboard, _outpost_positions_dict())

	# Remove old aboard treasure instances before spawning floating wreck salvage.
	for item in aboard:
		if is_instance_valid(item):
			var holder: Variant = item.get(&"holder")
			if holder is Pawn:
				(holder as Pawn).release_carried(item as Node3D)
			(item as Node).queue_free()

	_spawn_wreck_salvage_marker(wreck)

	if Game != null and Game.profile != null:
		Game.profile.bump_stat("times_sunk", 1)
		Game.save()

	# Restore ship cleanly at the last visited Outpost mooring!
	_restore_player_ship_at_outpost(StringName(String(wreck.get("restore_outpost_id", &"port_scoundrel"))))
	if map_table != null:
		map_table.refresh_now()
	_ship_restoring = false


func _spawn_wreck_salvage_marker(wreck: Dictionary) -> void:
	var wpos: Vector3 = wreck.get("position", Vector3.ZERO)
	var items: Array = wreck.get("items", [])

	# Sculpted Nautical Iron Salvage Bell-Buoy + glowing beacon + circling gulls.
	var buoy := Node3D.new()
	buoy.name = "SalvageBuoy_" + String(wreck.get("id", "wreck"))
	_entities_root.add_child(buoy)
	buoy.global_position = Vector3(wpos.x, Sea.height(wpos.x, wpos.z), wpos.z)
	var wreck_gulls := SeabirdFlock.spawn_over(_entities_root, Vector3(wpos.x, 0.0, wpos.z), 13.0, 15.0, 6)
	wreck_gulls.is_loot_marker = true

	var hull_mat := StandardMaterial3D.new()
	hull_mat.vertex_color_use_as_albedo = true
	hull_mat.metallic = 0.42
	hull_mat.roughness = 0.46

	var bronze_mat := StandardMaterial3D.new()
	bronze_mat.vertex_color_use_as_albedo = true
	bronze_mat.metallic = 0.85
	bronze_mat.roughness = 0.28

	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.vertex_color_use_as_albedo = true
	beacon_mat.albedo_color = Color(1.0, 0.82, 0.36)
	beacon_mat.roughness = 0.16
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.60, 0.14)
	beacon_mat.emission_energy_multiplier = 2.6

	var buoy_mi := MeshInstance3D.new()
	buoy_mi.name = "SalvageBuoyMesh"
	var buoy_mesh := _build_salvage_buoy_mesh()
	buoy_mi.mesh = buoy_mesh
	buoy_mi.set_surface_override_material(0, hull_mat)
	if buoy_mesh.get_surface_count() > 1:
		buoy_mi.set_surface_override_material(1, bronze_mat)
	if buoy_mesh.get_surface_count() > 2:
		buoy_mi.set_surface_override_material(2, beacon_mat)
	buoy.add_child(buoy_mi)

	var beacon_light := OmniLight3D.new()
	beacon_light.name = "SalvageBeaconLight"
	beacon_light.position = Vector3(0.0, 1.92, 0.0)
	beacon_light.light_color = Color(1.0, 0.66, 0.22)
	beacon_light.light_energy = 1.1
	beacon_light.omni_range = 10.0
	beacon_light.omni_attenuation = 1.4
	beacon_light.shadow_enabled = false
	buoy.add_child(beacon_light)

	_bobbing_props.append({"node": buoy, "x": wpos.x, "z": wpos.z, "y_off": 0.0, "phase": 0.2})

	for i in items.size():
		var info: Dictionary = items[i]
		var tid := StringName(String(info.get("treasure_id", &"wayfarer_chest")))
		var ang := float(i) / float(maxi(1, items.size())) * TAU
		var sx := wpos.x + cos(ang) * 3.0
		var sz := wpos.z + sin(ang) * 3.0
		var chest := TreasureCatalog.create_treasure_carryable(tid, Vector3(sx, Sea.height(sx, sz) + 0.35, sz))
		if info.has("gold_value"):
			chest.set_meta(&"gold_value", int(info["gold_value"]))
		chest.set_meta(&"salvaged_from_wreck", true)
		_entities_root.add_child(chest)
		chest.global_position = Vector3(sx, Sea.height(sx, sz) + 0.35, sz)


static func _build_salvage_buoy_mesh() -> ArrayMesh:
	var hull_st := SurfaceTool.new()
	hull_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bronze_st := SurfaceTool.new()
	bronze_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var beacon_st := SurfaceTool.new()
	beacon_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_crimson_dark := Color(0.64, 0.12, 0.10)
	var col_crimson := Color(0.84, 0.17, 0.14)
	var col_crimson_hi := Color(0.92, 0.24, 0.18)
	var col_cream := Color(0.94, 0.89, 0.76)
	var col_cream_shade := Color(0.82, 0.76, 0.63)
	var col_bronze_hi := Color(0.88, 0.66, 0.26)
	var col_bronze_mid := Color(0.70, 0.48, 0.17)
	var col_bronze_dark := Color(0.42, 0.27, 0.10)
	var col_amber_core := Color(1.00, 0.94, 0.68)
	var col_amber_mid := Color(1.00, 0.70, 0.22)
	var col_amber_deep := Color(0.92, 0.44, 0.10)

	# 1. Riveted flared crimson-and-cream maritime conical iron float hull (r ~ 0.52 m at waterline).
	var hull_rings: Array[Array] = [
		[-0.340, 0.000, CookingStove.COL_IRON_DARK],
		[-0.300, 0.210, CookingStove.COL_IRON_DARK],
		[-0.045, 0.505, CookingStove.COL_IRON_MID],
		[-0.025, 0.542, CookingStove.COL_IRON_DARK],
		[0.025, 0.546, CookingStove.COL_IRON_HI],
		[0.080, 0.540, CookingStove.COL_IRON_DARK],
		[0.090, 0.518, col_crimson_dark],
		[0.275, 0.464, col_crimson],
		[0.285, 0.468, col_cream_shade],
		[0.360, 0.438, col_cream],
		[0.435, 0.408, col_cream_shade],
		[0.445, 0.404, col_crimson],
		[0.565, 0.342, col_crimson_hi],
		[0.592, 0.312, col_crimson_dark],
		[0.595, 0.185, CookingStove.COL_IRON_MID],
		[0.625, 0.175, CookingStove.COL_IRON_HI],
		[0.625, 0.000, CookingStove.COL_IRON_DARK],
	]
	CookingStove._append_lathe_y(hull_st, hull_rings, 10)

	# Rivets around the waterline iron fender skirt band & brass bolts on the upper crown deck.
	for r_i in 10:
		var ang := TAU * float(r_i) / 10.0
		var rdir := Vector3(cos(ang), 0.0, sin(ang))
		CookingStove._append_rivet_dome(
			hull_st, Vector3(0.0, 0.028, 0.0) + rdir * 0.544, rdir, 0.016, 0.010, CookingStove.COL_RIVET
		)
	for b_i in 8:
		var ang := TAU * float(b_i) / 8.0
		var pos := Vector3(cos(ang) * 0.255, 0.594, sin(ang) * 0.255)
		CookingStove._append_rivet_dome(bronze_st, pos, Vector3.UP, 0.014, 0.009, col_bronze_hi)

	# 2. 4 angled cast-iron lattice tower struts rising from y = 0.56 to y = 1.75 m with cross-braces.
	var strut_bot_y := 0.56
	var strut_top_y := 1.75
	var strut_bot_r := 0.305
	var strut_top_r := 0.148
	var corners_bot: Array[Vector3] = []
	var corners_mid1: Array[Vector3] = []
	var corners_mid2: Array[Vector3] = []
	var corners_top: Array[Vector3] = []
	for ci in 4:
		var ang := PI * 0.25 + float(ci) * PI * 0.5
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var p_bot := Vector3(0.0, strut_bot_y, 0.0) + d * strut_bot_r
		var p_top := Vector3(0.0, strut_top_y, 0.0) + d * strut_top_r
		corners_bot.append(p_bot)
		corners_mid1.append(p_bot.lerp(p_top, 0.34))
		corners_mid2.append(p_bot.lerp(p_top, 0.71))
		corners_top.append(p_top)
		# Bolted cast-iron deck footpad + main lattice corner leg.
		CookingStove._append_cylinder_between(
			hull_st, p_bot - Vector3(0.0, 0.025, 0.0), p_bot + Vector3(0.0, 0.045, 0.0),
			0.036, 0.026, 6, CookingStove.COL_IRON_DARK, CookingStove.COL_IRON_HI
		)
		CookingStove._append_cylinder_between(
			hull_st, p_bot, p_top, 0.022, 0.017, 6,
			CookingStove.COL_IRON_DARK, CookingStove.COL_IRON_HI
		)

	for ci in 4:
		var ni := (ci + 1) % 4
		# Mid-level horizontal tie rings & lower-bay diagonal X-bracing struts.
		CookingStove._append_cylinder_between(
			hull_st, corners_mid1[ci], corners_mid1[ni], 0.014, 0.014, 5,
			CookingStove.COL_IRON_MID, CookingStove.COL_IRON_HI
		)
		CookingStove._append_cylinder_between(
			hull_st, corners_mid2[ci], corners_mid2[ni], 0.013, 0.013, 5,
			CookingStove.COL_IRON_MID, CookingStove.COL_IRON_HI
		)
		CookingStove._append_cylinder_between(
			hull_st, corners_bot[ci] + Vector3(0.0, 0.04, 0.0), corners_mid1[ni], 0.0095, 0.0095, 5,
			CookingStove.COL_IRON_DARK, CookingStove.COL_IRON_MID
		)
		CookingStove._append_cylinder_between(
			hull_st, corners_bot[ni] + Vector3(0.0, 0.04, 0.0), corners_mid1[ci], 0.0095, 0.0095, 5,
			CookingStove.COL_IRON_DARK, CookingStove.COL_IRON_MID
		)

	# Upper bell-yoke crossbeam spanning cleanly inside the lattice at y = 1.42 m.
	var yoke_a := corners_mid2[0].lerp(corners_mid2[3], 0.5)
	var yoke_b := corners_mid2[1].lerp(corners_mid2[2], 0.5)
	CookingStove._append_cylinder_between(
		hull_st, yoke_a, yoke_b, 0.016, 0.016, 6,
		CookingStove.COL_IRON_DARK, CookingStove.COL_IRON_HI
	)

	# 3. Hanging sculpted bronze maritime warning bell suspended inside the lattice tower.
	var bell_rings: Array[Array] = [
		[1.425, 0.000, col_bronze_dark],
		[1.422, 0.036, col_bronze_mid],
		[1.375, 0.032, col_bronze_dark],
		[1.355, 0.068, col_bronze_hi],
		[1.300, 0.080, col_bronze_mid],
		[1.175, 0.092, col_bronze_mid],
		[1.075, 0.140, col_bronze_hi],
		[1.032, 0.152, col_bronze_hi],
		[1.022, 0.146, col_bronze_dark],
		[1.030, 0.124, col_bronze_dark],
		[1.140, 0.072, col_bronze_dark],
		[1.290, 0.048, col_bronze_dark],
		[1.300, 0.000, col_bronze_dark],
	]
	CookingStove._append_lathe_y(bronze_st, bell_rings, 10)
	# Hanging clapper stem & bronze clapper ball peeking below the bell lip.
	CookingStove._append_cylinder_between(
		bronze_st, Vector3(0.0, 1.30, 0.0), Vector3(0.0, 0.99, 0.0),
		0.010, 0.009, 5, col_bronze_dark, col_bronze_mid
	)
	var clapper_rings: Array[Array] = [
		[0.958, 0.000, col_bronze_dark],
		[0.972, 0.024, col_bronze_mid],
		[0.992, 0.028, col_bronze_hi],
		[1.012, 0.018, col_bronze_mid],
		[1.018, 0.000, col_bronze_dark],
	]
	CookingStove._append_lathe_y(bronze_st, clapper_rings, 6)

	# 4. Top iron lantern gallery deck, 4 cage guard bars, weatherhood cap & emissive amber beacon!
	var gallery_rings: Array[Array] = [
		[1.720, 0.000, CookingStove.COL_IRON_DARK],
		[1.725, 0.165, CookingStove.COL_IRON_DARK],
		[1.750, 0.228, CookingStove.COL_IRON_HI],
		[1.782, 0.222, CookingStove.COL_IRON_HI],
		[1.786, 0.148, CookingStove.COL_IRON_MID],
		[1.786, 0.000, CookingStove.COL_IRON_DARK],
	]
	CookingStove._append_lathe_y(hull_st, gallery_rings, 8)
	for ci in 4:
		var ang := PI * 0.25 + float(ci) * PI * 0.5
		var rdir := Vector3(cos(ang), 0.0, sin(ang))
		CookingStove._append_cylinder_between(
			hull_st, Vector3(0.0, 1.78, 0.0) + rdir * 0.158, Vector3(0.0, 2.065, 0.0) + rdir * 0.152,
			0.011, 0.011, 5, CookingStove.COL_IRON_DARK, CookingStove.COL_IRON_HI
		)
	var hood_rings: Array[Array] = [
		[2.055, 0.140, CookingStove.COL_IRON_DARK],
		[2.060, 0.222, CookingStove.COL_IRON_HI],
		[2.085, 0.214, CookingStove.COL_IRON_MID],
		[2.175, 0.095, CookingStove.COL_IRON_HI],
		[2.225, 0.036, CookingStove.COL_IRON_DARK],
		[2.240, 0.000, CookingStove.COL_IRON_HI],
	]
	CookingStove._append_lathe_y(hull_st, hood_rings, 8)
	# Gleaming brass lantern finial orb & lightning spire.
	var finial_rings: Array[Array] = [
		[2.225, 0.028, col_bronze_dark],
		[2.255, 0.038, col_bronze_hi],
		[2.285, 0.024, col_bronze_mid],
		[2.345, 0.000, col_bronze_hi],
	]
	CookingStove._append_lathe_y(bronze_st, finial_rings, 6)

	# Emissive faceted Fresnel amber oil beacon crystal nestled inside the iron lantern cage.
	var crystal_rings: Array[Array] = [
		[1.786, 0.000, col_amber_deep],
		[1.790, 0.092, col_amber_deep],
		[1.845, 0.118, col_amber_mid],
		[1.920, 0.130, col_amber_core],
		[1.995, 0.116, col_amber_mid],
		[2.052, 0.088, col_amber_deep],
		[2.056, 0.000, col_amber_deep],
	]
	CookingStove._append_lathe_y(beacon_st, crystal_rings, 8)

	hull_st.generate_normals()
	var mesh := hull_st.commit()
	bronze_st.generate_normals()
	bronze_st.commit(mesh)
	beacon_st.generate_normals()
	beacon_st.commit(mesh)
	return mesh


func _restore_player_ship_at_outpost(outpost_id: StringName) -> void:
	if player_ship == null or not is_instance_valid(player_ship):
		return
	var target_outpost := archipelago.get_island_by_id(String(outpost_id)) as Outpost
	if target_outpost == null:
		target_outpost = archipelago.get_outpost(0)
	var moor_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -40.0))
	if target_outpost != null:
		moor_xf = target_outpost.get_world_mooring_transform()
	moor_xf.origin.y = Sea.height(moor_xf.origin.x, moor_xf.origin.z)

	var clean_holes: Array[int] = []
	for _i in Ship.HOLE_SLOTS:
		clean_holes.append(0)
	player_ship.apply_net_state({
		"origin": moor_xf.origin,
		"quat": moor_xf.basis.get_rotation_quaternion(),
		"lin_vel": Vector3.ZERO,
		"ang_vel": Vector3.ZERO,
		"helm": 0.0,
		"helm_target": 0.0,
		"sail_set": 0.0,
		"sail_target": 0.0,
		"sail_trim": 0.0,
		"trim_target": 0.0,
		"anchor_down": true,
		"anchor_progress": 1.0,
		"water_level": 0.0,
		"is_sinking": false,
		"holes": clean_holes,
		"cannonballs": Ship.MAX_CANNONBALLS,
		"planks": Ship.MAX_PLANKS,
	})
	ShipwrightMenu.apply_economy_to_ship(player_ship, Game.profile, crew_brains, world_director)

	# Re-board captain and active crewmates cleanly on the restored ship.
	if player_pawn != null and is_instance_valid(player_pawn):
		if player_pawn.station != null:
			player_pawn.leave_station()
		var cap_spawn := player_ship.global_transform * Vector3(0.0, 2.02, 4.15)
		if player_pawn.dead:
			player_pawn.revive(cap_spawn)
		else:
			player_pawn.heal(player_pawn.max_health)
		player_pawn.board(player_ship, Vector3(0.0, 2.02, 4.15))

	for i in crew_pawns.size():
		var cp := crew_pawns[i]
		if cp != null and is_instance_valid(cp) and cp.visible:
			if cp.station != null:
				cp.leave_station()
			var c_local := CREW_SPECS[i]["local_pos"] as Vector3
			if cp.dead:
				cp.revive(player_ship.global_transform * c_local)
			else:
				cp.heal(cp.max_health)
			cp.board(player_ship, c_local)


func _spawn_enemy_pawn(archetype: StringName, world_pos: Vector3) -> Pawn:
	var p := EnemyBrain.spawn_enemy(archetype, world_pos, _entities_root)
	# Ensure CharacterVisual loads the exact archetype GLB rig (drowned/tidecaller/pirate).
	var cv := _character_visual_of(p)
	if cv != null:
		cv.set_archetype(archetype)
	var brain := p.get_node_or_null(^"EnemyBrain") as EnemyBrain
	if brain != null:
		brain.enemy_defeated.connect(_on_enemy_pawn_defeated)
	active_enemies.append(p)
	return p


func _on_enemy_pawn_defeated(arch: StringName, _pos: Vector3) -> void:
	if Net.is_host() and voyage_manager != null and voyage_manager.has_active_voyage():
		voyage_manager.notify_enemy_defeated(arch)


func _spawn_enemy_vessel(archetype: StringName, world_pos: Vector3) -> Ship:
	if not Net.is_host():
		return null
	var spawn_arch := archetype
	if spawn_arch == &"drowned_sloop_raider":
		spawn_arch = &"drowned_sloop"
	var enemy := AIShipBrain.spawn_enemy_sloop(spawn_arch, world_pos, _entities_root, player_ship)
	if archetype == &"drowned_sloop_raider":
		enemy.speed_modifier = 1.04
	var sunk_kind := &"ghost_ship" if spawn_arch == &"ghost_ship" else &"drowned_sloop"
	enemy.sunk.connect(func() -> void:
		if Net.is_host() and voyage_manager != null and voyage_manager.has_active_voyage():
			voyage_manager.notify_enemy_defeated(sunk_kind)
	)
	enemy_ships.append(enemy)
	return enemy


# ==============================================================================
# Fishing, Cooking & Player Revive Helpers
# ==============================================================================

func _on_fishing_interacted(pawn: Node) -> void:
	if not Net.is_host() or fishing_line == null or not (pawn is Pawn):
		return
	var p := pawn as Pawn
	if fishing_line.state == FishingLine.State.IDLE:
		var stern_dir := player_ship.global_basis.z if player_ship != null else p.facing()
		if fishing_line.cast_line(fishing_line.global_position, stern_dir, 11.0):
			_fishing_pawn = p
			if fishing_interactable != null:
				fishing_interactable.prompt = "Stow fishing line (hold LMB to reel)"
			Game.post_notice("Line cast off the stern — hold LMB to reel when it bites!")
	else:
		fishing_line.cancel_cast()
		_fishing_pawn = null
		if fishing_interactable != null:
			fishing_interactable.prompt = "Cast fishing line"


func _tick_fishing(delta: float) -> void:
	if fishing_line == null or fishing_line.state == FishingLine.State.IDLE:
		return
	if _fishing_pawn == null or not is_instance_valid(_fishing_pawn) or _fishing_pawn.dead:
		fishing_line.cancel_cast()
		_fishing_pawn = null
		if fishing_interactable != null:
			fishing_interactable.prompt = "Cast fishing line"
		return
	if _fishing_pawn.global_position.distance_to(fishing_line.global_position) > 4.2:
		fishing_line.cancel_cast()
		_fishing_pawn = null
		if fishing_interactable != null:
			fishing_interactable.prompt = "Cast fishing line"
		return
	var reeling := Input.is_action_pressed(&"primary") if (_fishing_pawn == player_pawn and active_shot_mode == "") else false
	fishing_line.step(delta, fishing_line.global_position, reeling)


func _on_fish_caught(species: Dictionary) -> void:
	_fishing_pawn = null
	if fishing_interactable != null:
		fishing_interactable.prompt = "Cast fishing line"
	# Auto-place onto empty hold stove if convenient, or store for cooking.
	if cooking_stove != null and cooking_stove.cooking_item.is_empty():
		cooking_stove.place_food(species)


func _on_fishing_line_snapped(species: Dictionary) -> void:
	_fishing_pawn = null
	if fishing_interactable != null:
		fishing_interactable.prompt = "Cast fishing line"
	Game.post_notice("Line snapped! The %s got away." % String(species.get("name", "fish")))


func _on_player_died() -> void:
	if not Net.is_host():
		return
	Game.post_notice("Downed! Crew hauling you back aboard...")
	_revive_timer = 3.0


func _revive_player_aboard_ship() -> void:
	if player_pawn == null or not is_instance_valid(player_pawn):
		return
	var has_ship := player_ship != null and is_instance_valid(player_ship)
	var respawn_pos := player_ship.global_transform * Vector3(0.0, 2.02, 4.15) if has_ship else player_pawn.global_position
	player_pawn.revive(respawn_pos)
	if has_ship:
		player_pawn.board(player_ship, Vector3(0.0, 2.02, 4.15))
	Game.post_notice("Back on your feet, Captain!")


# ==============================================================================
# UI Coordination
# ==============================================================================

func _on_outpost_voyage_board_used(outpost_id: StringName) -> void:
	if shipwright_menu == null:
		return
	shipwright_menu.origin_outpost_id = outpost_id
	if hud != null and hud.pause_open:
		hud.set_pause_open(false)
	shipwright_menu.open_menu(ShipwrightMenu.TAB_VOYAGES)


func _on_shipwright_opened(_tab: StringName) -> void:
	if hud != null:
		hud.input_enabled = false


func _on_shipwright_closed() -> void:
	if hud != null and active_shot_mode == "":
		hud.input_enabled = true


func _on_ship_class_selected(cls: StringName) -> void:
	_cli_ship_class = cls
	if cls == &"brigantine" and not ResourceLoader.exists(BRIGANTINE_SCENE_PATH):
		Game.post_notice("Brigantine hull commissioned at the drydock (sailing Sloop in harbour).")
		return
	if Net.is_host() and player_ship != null and is_instance_valid(player_ship) and player_ship.ship_class != cls:
		var near_outpost := false
		for op in archipelago.get_outposts():
			if player_ship.global_position.distance_to(op.global_position) < 130.0:
				near_outpost = true
				break
		if near_outpost:
			_swap_player_ship_class(cls)
			Game.post_notice("Launched your %s from the drydock!" % String(cls).capitalize())
			return
	Game.post_notice("Ship class set to %s (launches at your next Outpost)." % String(cls).capitalize())


func _swap_player_ship_class(cls: StringName) -> void:
	var old_ship := player_ship
	var xf := old_ship.global_transform
	xf.origin.y = Sea.height(xf.origin.x, xf.origin.z)
	if old_ship.sunk.is_connected(_on_player_ship_sunk):
		old_ship.sunk.disconnect(_on_player_ship_sunk)
	Net.unregister_replicated_ship(&"player_sloop")

	var ship_scene := _resolve_ship_scene(cls)
	var new_ship := ship_scene.instantiate() as Ship
	new_ship.name = "PlayerShip"
	new_ship.faction = &"player"
	new_ship.start_anchored = old_ship.anchor_down
	add_child(new_ship)
	new_ship.global_transform = xf
	player_ship = new_ship

	map_table = MapTableView.new()
	map_table.name = "MapTableView"
	map_table.mount_to_ship(player_ship)
	map_table.set_archipelago_data(_build_chart_map_data())
	map_table.voyage_manager = voyage_manager
	map_table.world_director = world_director
	map_table.refresh_now()

	_mount_cooking_stove(player_ship)
	_mount_fishing_station(player_ship)
	Net.register_replicated_ship(&"player_sloop", player_ship)
	player_ship.sunk.connect(_on_player_ship_sunk)
	player_ship.hull_impacted.connect(_on_player_ship_hull_impacted)

	if player_pawn != null and is_instance_valid(player_pawn):
		if player_pawn.station != null:
			player_pawn.leave_station()
		if player_pawn.platform == old_ship:
			player_pawn.board(player_ship, _captain_deck_pos(player_ship))
	var specs := _crew_specs_for(player_ship)
	for i in crew_pawns.size():
		var cp := crew_pawns[i]
		if cp != null and is_instance_valid(cp):
			if cp.station != null:
				cp.leave_station()
			cp.board(player_ship, specs[i % specs.size()]["local_pos"] as Vector3)
		if i < crew_brains.size() and crew_brains[i] != null:
			crew_brains[i].ship = player_ship
	for pid: int in _peer_pawns.keys():
		var pp: Pawn = _peer_pawns[pid]
		if pp != null and is_instance_valid(pp) and pp.platform == old_ship:
			if pp.station != null:
				pp.leave_station()
			pp.board(player_ship, _captain_deck_pos(player_ship) + Vector3(0.8, 0.0, 0.0))

	if world_director != null:
		world_director.player_ship = player_ship
	if hud != null:
		hud.ship = player_ship
	if shipwright_menu != null:
		shipwright_menu.ship = player_ship
		shipwright_menu.map_table = map_table
	ShipwrightMenu.apply_economy_to_ship(player_ship, Game.profile, crew_brains, world_director)
	old_ship.queue_free()


func _on_settings_changed() -> void:
	if hud != null and user_settings != null:
		var subs := bool(user_settings.data.get("subtitles_enabled", true))
		if not subs:
			hud.clear_banners()


# ==============================================================================
# Co-op Peer Management & AI Slot Yielding
# ==============================================================================

func _on_net_peer_joined(peer_id: int) -> void:
	if not Net.is_host() or _peer_pawns.has(peer_id):
		return
	var pp := PAWN_SCENE.instantiate() as Pawn
	pp.name = "Peer_%d" % peer_id
	add_child(pp)
	var offset_idx := _peer_pawns.size()
	var local_spawn := Vector3(0.9 * float(offset_idx + 1) - 1.2, 1.12, 0.4)
	if player_ship != null and is_instance_valid(player_ship):
		pp.board(player_ship, local_spawn)

	var cv := _character_visual_of(pp)
	if cv != null:
		cv.set_archetype(&"captain")
		var tint_pair: Array = PEER_TINTS[offset_idx % PEER_TINTS.size()]
		cv.set_tint(tint_pair[0] as Color, tint_pair[1] as Color)

	var cc := CombatComponent.new()
	cc.name = "CombatComponent"
	cc.faction = &"player"
	cc.equipped_weapon = &"cutlass"
	pp.add_child(cc)

	_peer_pawns[peer_id] = pp
	Net.register_replicated_pawn(peer_id, pp)
	_yield_one_ai_crewmate(peer_id)
	Game.post_notice("Co-op crewmate joined aboard! (Peer %d)" % peer_id)


func _on_net_peer_left(peer_id: int) -> void:
	if _peer_pawns.has(peer_id):
		var pp: Pawn = _peer_pawns[peer_id]
		_peer_pawns.erase(peer_id)
		Net.unregister_replicated_pawn(peer_id)
		if is_instance_valid(pp):
			if pp.station != null:
				pp.leave_station()
			pp.queue_free()
	_restore_ai_crewmate(peer_id)
	Game.post_notice("Co-op crewmate departed — AI crew resumed station.")


func _yield_one_ai_crewmate(peer_id: int) -> void:
	# Yield the last active AI crewmate slot (carpenter -> lookout -> helmsman).
	for idx in range(crew_brains.size() - 1, -1, -1):
		if _peer_yielded_crew.values().has(idx):
			continue
		var brain := crew_brains[idx]
		var cp := crew_pawns[idx]
		if brain != null and is_instance_valid(brain):
			brain.yield_to_human_player()
		if cp != null and is_instance_valid(cp):
			cp.visible = false
			cp.set_physics_process(false)
			cp.collision_layer = 0
		_peer_yielded_crew[peer_id] = idx
		return


func _restore_ai_crewmate(peer_id: int) -> void:
	if not _peer_yielded_crew.has(peer_id):
		return
	var idx: int = int(_peer_yielded_crew[peer_id])
	_peer_yielded_crew.erase(peer_id)
	if idx < 0 or idx >= crew_brains.size():
		return
	var brain := crew_brains[idx]
	var cp := crew_pawns[idx]
	if cp != null and is_instance_valid(cp):
		cp.visible = true
		cp.collision_layer = Pawn.LAYER_PAWN
		cp.set_physics_process(true)
		if player_ship != null and is_instance_valid(player_ship):
			cp.board(player_ship, CREW_SPECS[idx]["local_pos"] as Vector3)
	if brain != null and is_instance_valid(brain):
		brain.set_physics_process(true)


func _on_net_client_intent(peer_id: int, intent: Dictionary) -> void:
	if not Net.is_host() or not _peer_pawns.has(peer_id):
		return
	var pp: Pawn = _peer_pawns[peer_id]
	if not is_instance_valid(pp) or pp.dead:
		return
	if intent.has("wish_dir") and intent["wish_dir"] is Vector3:
		pp.wish_dir = intent["wish_dir"] as Vector3
	if intent.has("wish_sprint"):
		pp.wish_sprint = bool(intent["wish_sprint"])
	if intent.has("wish_jump"):
		pp.wish_jump = bool(intent["wish_jump"])
	if intent.has("look_yaw"):
		pp.look_yaw = float(intent["look_yaw"])
	if intent.has("look_pitch"):
		pp.look_pitch = float(intent["look_pitch"])
	if bool(intent.get("leave_station", false)) and pp.station != null:
		pp.leave_station()
	elif pp.station != null and intent.has("station_axis"):
		var ax: Vector2 = intent["station_axis"] as Vector2 if intent["station_axis"] is Vector2 else Vector2.ZERO
		pp.drive_station(ax, bool(intent.get("primary", false)), bool(intent.get("secondary", false)), 1.0 / 60.0)
	if bool(intent.get("interact", false)):
		pp.interact()
	if bool(intent.get("attack", false)):
		var cc := pp.get_node_or_null(^"CombatComponent") as CombatComponent
		if cc != null:
			cc.primary_attack()


func _send_local_client_intent() -> void:
	if player_pawn == null or not is_instance_valid(player_pawn):
		return
	var ax := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back")
	)
	Net.send_client_intent({
		"wish_dir": player_pawn.wish_dir,
		"wish_sprint": player_pawn.wish_sprint,
		"wish_jump": player_pawn.wish_jump,
		"look_yaw": player_pawn.look_yaw,
		"look_pitch": player_pawn.look_pitch,
		"station_axis": ax,
		"primary": Input.is_action_pressed(&"primary"),
		"secondary": Input.is_action_pressed(&"secondary"),
		"interact": Input.is_action_just_pressed(&"interact"),
		"leave_station": Input.is_action_just_pressed(&"leave_station"),
		"attack": Input.is_action_just_pressed(&"primary"),
	})


# ==============================================================================
# Live Audio Ambience, Thunder & Adaptive Music
# ==============================================================================

func _update_live_audio(snap: bool) -> void:
	if Audio == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var listener_pos := cam.global_position if cam != null else (player_pawn.global_position if player_pawn != null else Vector3.ZERO)

	Audio.set_sea_state(Sea.sea_state())
	Audio.set_wind(clampf(Weather.wind_vector().length() / 22.0, 0.0, 1.0))
	Audio.set_rain(Weather.rain_intensity())
	if archipelago != null:
		Audio.set_shore(archipelago.nearest_shore_factor(listener_pos))
	if player_ship != null and is_instance_valid(player_ship):
		Audio.set_ship_speed(clampf(player_ship.speed_knots() / 14.0, 0.0, 1.0))
	var sheltered := bool(sky_rig.get(&"camera_sheltered")) if sky_rig != null else false
	Audio.set_below_deck(1.0 if sheltered else 0.0)
	var submerged := Ocean.current != null and Ocean.current.camera_submerged
	Audio.set_underwater(submerged)
	if snap:
		Audio.snap_ambience()


func _on_player_ship_hull_impacted(world_pos: Vector3, intensity: float) -> void:
	if player_controller == null or not is_instance_valid(player_controller):
		return
	if player_pawn == null or not is_instance_valid(player_pawn):
		return
	var d := player_pawn.global_position.distance_to(world_pos)
	if player_pawn.platform == player_ship or d < 22.0:
		var atten := 1.0 if player_pawn.platform == player_ship else clampf(1.0 - d / 22.0, 0.25, 1.0)
		player_controller.add_camera_trauma(clampf(intensity * 0.68 * atten, 0.22, 0.85))


func _on_thunder_heard(_direction: Vector3, distance: float, intensity: float) -> void:
	var sfx_id := &"thunder_near" if distance < 900.0 else &"thunder_far"
	var db := lerpf(-8.0, 0.0, clampf(intensity, 0.0, 1.0))
	Audio.play_sfx(sfx_id, Vector3.INF, db, 0.04)
	if distance < 420.0 and player_controller != null and is_instance_valid(player_controller):
		var shake := clampf((1.0 - distance / 420.0) * intensity * 0.42, 0.0, 0.42)
		player_controller.add_camera_trauma(shake)


func _update_adaptive_music(force: bool) -> void:
	if Audio == null or Audio.is_shanty_playing():
		return
	var desired := _compute_music_mood()
	if not force and desired == current_music_mood:
		return
	current_music_mood = desired
	var track := _resolve_music_track(desired)
	if track != &"":
		Audio.play_music(track, 2.2)


func _compute_music_mood() -> StringName:
	if _is_in_active_combat():
		return &"combat"
	if Weather.storminess >= 0.58:
		return &"storm"
	if Weather.is_night():
		return &"sail_night"
	return &"sail_day"


func _is_in_active_combat() -> bool:
	if player_ship != null and is_instance_valid(player_ship):
		for es in enemy_ships:
			if is_instance_valid(es) and not es.is_sinking:
				if es.global_position.distance_to(player_ship.global_position) < 220.0:
					return true
		for lev in active_leviathans:
			if is_instance_valid(lev) and lev.active:
				return true
	if player_pawn != null and is_instance_valid(player_pawn):
		for ep in active_enemies:
			if is_instance_valid(ep) and not ep.dead:
				if ep.global_position.distance_to(player_pawn.global_position) < 24.0:
					return true
	return false


func _resolve_music_track(mood: StringName) -> StringName:
	var music_dict: Dictionary = Audio.catalogue.get("music", {})
	if music_dict.has(String(mood)):
		return mood
	if mood == &"combat":
		return &"combat" if music_dict.has("combat") else &"sailing"
	if mood == &"storm":
		return &"combat" if music_dict.has("combat") else &"sailing"
	return &"sailing" if music_dict.has("sailing") else &""


func _play_stinger_safe(preferred: StringName, fallback: StringName) -> void:
	var stingers: Dictionary = Audio.catalogue.get("stingers", {})
	if stingers.has(String(preferred)):
		Audio.play_stinger(preferred)
	elif stingers.has(String(fallback)):
		Audio.play_stinger(fallback)


# ==============================================================================
# Hero Showcase Capture Framing (`shot=...` CLI arg ONLY)
# ==============================================================================

func _apply_hero_shot(mode: String) -> void:
	var cutlass := archipelago.get_island_by_id("cutlass_cay")
	var port := archipelago.get_outpost(0)
	var is_brig := (player_ship != null and player_ship.ship_class == &"brigantine")
	var sc := 1.38 if is_brig else 1.0
	_shot_track_ship = false
	_shot_track_world_target = null
	_shot_track_world_blend = 0.0
	_shot_combat_timer = -1.0
	if hud != null:
		hud.input_enabled = false
		hud.clear_banners()
	# Show the Captain's full 3D character mesh on external third-person hero cameras.
	var p_cv := _character_visual_of(player_pawn)
	if p_cv != null:
		var third_person := mode in [
			"outpost_dock", "sailing", "island_approach", "combat",
			"storm", "sunset", "night", "leviathan", "fleet",
			"fort_siege", "harbour_plaza", "smugglers_grotto",
			"cinder_crag", "coral_reef", "fishing"
		]
		p_cv.set_first_person_hidden(not third_person)

	match mode:
		"outpost_dock":
			Weather.time_of_day = 10.0 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.0, 7.0, -0.37, 0.0, 0.35)
			Sea.amp_scale = Sea.AMP_CALM
			if port != null:
				var pier_xf := port.global_transform * port.dock_local_transform
				var cam_pos := pier_xf * Vector3(-6.8 * sc, 5.2 * sc, -2.5 * sc)
				var look_at_pt := player_ship.global_position + Vector3(0.0, 4.2 * sc, -0.8)
				_mount_shot_camera(cam_pos, look_at_pt, 56.0)

		"sailing":
			Weather.time_of_day = 10.8 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.08, 11.0, -0.35, 0.0, 0.38)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			var mid := Vector3(72.0, 0.0, -190.0)
			_place_sailing_ship(mid, -0.38, 1.0, 6.2)
			_enable_ship_track_shot(Vector3(16.8 * sc, 5.6 * sc, -17.2 * sc), Vector3(0.0, 4.8 * sc, -0.5), 54.0)

		"island_approach":
			Weather.time_of_day = 11.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.04, 9.5, -0.37, 0.0, 0.34)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.10)
			var isl_pos := cutlass.global_position if cutlass != null else Vector3(165.0, 0.0, -415.0)
			var ship_pos := isl_pos + Vector3(-42.0, 0.0, 96.0)
			var yaw := atan2(-(isl_pos.x - ship_pos.x), -(isl_pos.z - ship_pos.z))
			_place_sailing_ship(ship_pos, yaw, 0.85, 4.8)
			_enable_ship_track_shot(Vector3(13.5 * sc, 6.8 * sc, 17.5 * sc), Vector3(0.0, 4.5, -25.0), 56.0)
			_shot_track_world_target = cutlass
			_shot_track_world_blend = 0.85
			_shot_track_world_y_off = 12.0
			_update_tracked_shot_camera()

		"combat":
			Weather.time_of_day = 14.5 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.24, 12.5, -0.2, 0.0, 0.56)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.28)
			_place_sailing_ship(Vector3(60.0, 0.0, -210.0), -0.35, 0.9, 5.2)
			var foe_pos := player_ship.global_transform * Vector3(42.0, 0.0, -10.0)
			var foe := _spawn_enemy_vessel(&"drowned_sloop", foe_pos)
			if foe != null:
				foe.rotation.y = player_ship.rotation.y + 0.12
				player_ship.aim_cannon(&"starboard", 0.0, 0.10)
				if player_ship.get_station(&"cannon", &"starboard_aft") != null:
					player_ship.aim_cannon(&"starboard_aft", 0.0, 0.10)
				_shot_combat_timer = 0.25
			_enable_ship_track_shot(Vector3(-13.5 * sc, 7.0 * sc, 18.5 * sc), Vector3(12.0, 3.6, -4.0), 58.0)
			_shot_track_world_target = foe
			_shot_track_world_blend = 0.42
			_shot_track_world_y_off = 3.2
			_update_tracked_shot_camera()

		"storm":
			Weather.time_of_day = 15.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.92, 21.0, 0.3, 0.0, 1.0)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.92)
			_place_sailing_ship(Vector3(-120.0, 0.0, -260.0), 0.15, 0.75, 5.5)
			Weather.strike_lightning(Vector3(0.25, 0.0, -0.96).normalized(), 520.0, 0.9)
			_enable_ship_track_shot(Vector3(17.0 * sc, 5.6 * sc, -17.5 * sc), Vector3(0.0, 4.5 * sc, 0.0), 58.0)

		"sunset":
			Weather.time_of_day = 17.85 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.06, 8.5, -0.5, 0.0, 0.44)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.12)
			_place_sailing_ship(Vector3(85.0, 0.0, -210.0), -0.42, 1.0, 5.8)
			_enable_ship_track_shot(Vector3(15.5 * sc, 5.0 * sc, 16.5 * sc), Vector3(0.0, 4.8 * sc, -2.5), 56.0)

		"night":
			Weather.time_of_day = 23.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.08, 7.5, -0.37, 0.0, 0.30)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.10)
			if port != null:
				var pier_xf := port.global_transform * port.dock_local_transform
				var cam_pos := pier_xf * Vector3(-6.8 * sc, 4.8 * sc, -2.2 * sc)
				var look_pt := player_ship.global_position + Vector3(0.0, 3.6 * sc, -1.8)
				_mount_shot_camera(cam_pos, look_pt, 56.0)

		"helm":
			Weather.time_of_day = 10.6 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.06, 10.5, -0.37, 0.0, 0.36)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			_place_sailing_ship(Vector3(76.0, 0.0, -195.0), -0.37, 1.0, 6.0)
			var helm_eye := Vector3(0.0, 3.95, 7.35) if is_brig else Vector3(0.0, 3.65, 5.75)
			var helm_look := Vector3(0.0, 2.75, -24.0) if is_brig else Vector3(0.0, 2.55, -24.0)
			_enable_ship_track_shot(helm_eye, helm_look, 74.0)

		"map_table":
			Weather.time_of_day = 12.0 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.0, 6.0, 0.0, 0.0, 0.30)
			Sea.amp_scale = 0.0
			if map_table != null:
				map_table.refresh_now()
				var table_y := MapTableView.BRIGANTINE_TABLE_TOP_Y if is_brig else MapTableView.SHIP_TABLE_TOP_Y
				var table_local := player_ship.to_local(map_table.global_position)
				var target_local := table_local + Vector3(0.0, table_y, -0.02)
				# Stand aft of the map table (clear of the forward companionway stairs) looking down at the chart.
				var cam_local := table_local + Vector3(0.0, table_y + 0.88, 0.72)
				_enable_ship_track_shot(cam_local, target_local, 50.0)

		"hold":
			Weather.time_of_day = 14.0 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.15, 9.0, 0.0, 0.0, 0.45)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.15)
			player_ship.water_level = 0.18
			if map_table != null:
				map_table.refresh_now()
			var cam_local_hold := Vector3(1.35, 0.42, -0.45) if is_brig else Vector3(1.02, 0.34, -0.82)
			var look_local_hold := Vector3(-0.10, -0.25, 4.20) if is_brig else Vector3(-0.08, -0.22, 2.55)
			_enable_ship_track_shot(cam_local_hold, look_local_hold, 66.0)

		"leviathan":
			Weather.time_of_day = 17.25 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.72, 17.5, -0.25, 0.0, 0.88)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.65)
			_place_sailing_ship(Vector3(-40.0, 0.0, -240.0), -0.32, 0.85, 4.6)
			var lev := Leviathan.new()
			lev.name = "HeroLeviathan"
			lev.target_ship = player_ship
			var lev_pos := player_ship.global_transform * Vector3(2.0, 0.0, -4.0)
			lev.position = Vector3(lev_pos.x, 0.0, lev_pos.z)
			_entities_root.add_child(lev)
			lev.global_position = Vector3(lev_pos.x, 0.0, lev_pos.z)
			active_leviathans.append(lev)
			_enable_ship_track_shot(Vector3(22.0 * sc, 8.8 * sc, -24.0 * sc), Vector3(0.0, 4.5, -1.0), 58.0)

		"fleet":
			# 4-ship multi-faction fleet battle & real-GPU draw-call stress benchmark!
			Weather.time_of_day = 15.0 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.28, 13.0, -0.22, 0.0, 0.58)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.28)
			_place_sailing_ship(Vector3(45.0, 0.0, -215.0), -0.35, 0.92, 5.4)
			var f1_pos := player_ship.global_transform * Vector3(38.0, 0.0, -14.0)
			var f2_pos := player_ship.global_transform * Vector3(-42.0, 0.0, -26.0)
			var f3_pos := player_ship.global_transform * Vector3(22.0, 0.0, -64.0)
			var f1 := _spawn_enemy_vessel(&"drowned_sloop", f1_pos)
			var f2 := _spawn_enemy_vessel(&"ghost_ship", f2_pos)
			var f3 := _spawn_enemy_vessel(&"corsair_sloop", f3_pos)
			if f1 != null:
				f1.rotation.y = player_ship.rotation.y + 0.14
			if f2 != null:
				f2.rotation.y = player_ship.rotation.y - 0.18
			if f3 != null:
				f3.rotation.y = player_ship.rotation.y + 0.45
			_shot_combat_timer = 0.22
			var fsc := 1.38 if is_brig else 1.24
			_enable_ship_track_shot(Vector3(-19.5 * fsc, 10.8 * fsc, 27.5 * fsc), Vector3(0.0, 3.8, -22.0), 62.0)

		"fort_siege":
			# Ironwatch Fort Stone Bastion, blazing Signal Brazier & 4 live coastal Sea-Battery Cannons!
			Weather.time_of_day = 16.6 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.32, 13.5, -0.25, 0.0, 0.62)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.30)
			var fort := archipelago.get_island_by_id("ironwatch_fort")
			if fort != null:
				_on_director_spawn_fort_siege(fort.global_position, "N")
				var fpos := fort.global_position
				var ship_off := Vector3(-64.0, 0.0, 74.0)
				var s_pos := fpos + ship_off
				var yaw := atan2(-(fpos.x - s_pos.x), -(fpos.z - s_pos.z))
				_place_sailing_ship(s_pos, yaw, 0.78, 3.2)
				# Dramatic low-altitude coastal shot showing Bastion, Signal Brazier, sea batteries & approaching Brigantine!
				var cam_p := fpos + Vector3(-28.0, 26.5, 42.0)
				var look_p := fpos + Vector3(0.0, 21.0, 0.0)
				_mount_shot_camera(cam_p, look_p, 56.0)

		"harbour_plaza":
			# Port Scoundrel living harbour plaza: Merchant Factor, Pier Quartermaster, Tavern, Stall & gulls!
			Weather.time_of_day = 10.4 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.04, 8.0, -0.35, 0.0, 0.34)
			Sea.amp_scale = Sea.AMP_CALM
			if port != null:
				var pier_xf := port.global_transform * port.dock_local_transform
				var cam_p := pier_xf * Vector3(-2.5, 5.4, -7.5)
				var look_p := pier_xf * Vector3(2.2, 3.2, 12.0)
				_mount_shot_camera(cam_p, look_p, 58.0)

		"smugglers_grotto":
			# Smuggler's Cove walkable limestone Sea Cave Grotto with glowing lanterns & contraband stash!
			Weather.time_of_day = 16.8 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.18, 9.0, -0.20, 0.0, 0.45)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			var smug := archipelago.get_island_by_id("smugglers_cove")
			if smug != null:
				var grotto := smug.get_node_or_null(^"SmugglersGrotto") as Node3D
				if grotto != null:
					var g_xf := grotto.global_transform
					var cam_p := g_xf * Vector3(-3.2, 3.6, -13.5)
					var look_p := g_xf * Vector3(0.0, 2.4, 2.0)
					_mount_shot_camera(cam_p, look_p, 58.0)
				else:
					_mount_shot_camera(smug.global_position + Vector3(0.0, 12.0, 28.0), smug.global_position + Vector3(0.0, 4.0, 0.0), 58.0)

		"cinder_crag":
			# Cinder Crag volcanic summit: glowing cracked basalt magma caldera & towering ash/ember plume!
			Weather.time_of_day = 17.85 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.36, 13.0, -0.30, 0.0, 0.62)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.30)
			var volc := archipelago.get_island_by_id("cinder_crag")
			if volc != null:
				var vp := volc.global_position
				_place_sailing_ship(vp + Vector3(72.0, 0.0, 92.0), 0.55, 0.88, 4.8)
				var cam_p := vp + Vector3(34.0, 108.0, 62.0)
				var look_p := vp + Vector3(0.0, 64.0, 2.0)
				_mount_shot_camera(cam_p, look_p, 58.0)

		"coral_reef":
			# Crescent Atoll crystal turquoise underwater coral reef & swaying kelp garden!
			Weather.time_of_day = 12.4 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.02, 7.0, -0.25, 0.0, 0.28)
			Sea.amp_scale = Sea.AMP_CALM
			var atoll := archipelago.get_island_by_id("crescent_atoll")
			if atoll != null:
				var reef := atoll.get_node_or_null(^"CoralReef") as CoralReef
				var target_w := atoll.global_position + Vector3(0.0, -3.2, -32.0)
				if reef != null:
					var pts := reef.get_placed_transforms()
					if not pts.is_empty():
						target_w = atoll.global_transform * pts[0].origin
				var dir_out := Vector3(target_w.x - atoll.global_position.x, 0.0, target_w.z - atoll.global_position.z)
				dir_out = dir_out.normalized() if dir_out.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
				var cam_p := target_w + dir_out * 6.5 + Vector3(0.0, 1.35, 0.0)
				cam_p.y = minf(cam_p.y, -1.15)
				_mount_shot_camera(cam_p, target_w + Vector3(0.0, 0.45, 0.0), 66.0)

		"galley":
			# Tight watertight hold close-up on the Cast-Iron Galley Hearth, copper skillet, seared fish & steam!
			Weather.time_of_day = 15.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.05, 6.5, 0.0, 0.0, 0.35)
			Sea.amp_scale = 0.0
			player_ship.water_level = 0.0
			if cooking_stove != null:
				if not cooking_stove.cooking_item.is_empty():
					cooking_stove.take_food()
				cooking_stove.place_food({
					"id": &"azure_snapper",
					"name": "Azure Snapper",
					"heal": 35.0,
					"gold": 45,
				})
				cooking_stove.step(11.0)
				var stove_local := cooking_stove.position
				var cam_local_galley := stove_local + Vector3(-0.68, 1.00, -1.04)
				var look_local_galley := stove_local + Vector3(0.0, 0.66, 0.02)
				_enable_ship_track_shot(cam_local_galley, look_local_galley, 58.0)

		"fishing":
			# Unobstructed port-outboard golden-hour showcase: flexed 3-section bamboo rod, glowing amber
			# 14-segment catenary line, painted cork-and-crimson bobber + splashes, and sunset horizon!
			Weather.time_of_day = 17.15 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.06, 9.0, -0.35, 0.0, 0.42)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.16)
			_place_sailing_ship(Vector3(78.0, 0.0, -210.0), -0.40, 0.0, 0.0)
			player_ship.set_anchor(true)
			player_ship.anchor_progress = 1.0
			player_ship.linear_velocity = Vector3.ZERO
			if fishing_line != null:
				var cast_local_dir := Vector3(-0.18, 0.0, 0.984).normalized()
				var cast_world_dir := (player_ship.global_basis * cast_local_dir)
				cast_world_dir.y = 0.0
				cast_world_dir = cast_world_dir.normalized()
				if player_pawn != null:
					player_pawn.board(player_ship, fishing_line.position + Vector3(0.18, 0.0, 0.10))
					player_pawn.look_yaw = atan2(-cast_world_dir.x, -cast_world_dir.z)
					_fishing_pawn = player_pawn
				fishing_line.cancel_cast()
				fishing_line.cast_line(fishing_line.global_position, cast_world_dir, 7.6)
				fishing_line.state = FishingLine.State.HOOKED
				fishing_line.hooked_species = FishingLine.SPECIES[2]
				fishing_line.fish_fighting = true
				fishing_line.line_tension = 0.80
				fishing_line.distance_out = 7.6
				fishing_line.step(0.016, fishing_line.global_position, false)
				# Port-outboard camera 1.8 m clear of hull, shrouds, backstay & balustrade posts!
				var cam_local_fish := fishing_line.position + Vector3(-2.07, 1.65, -0.77)
				var look_local_fish := fishing_line.position + Vector3(-0.75, 0.0, 4.15)
				_enable_ship_track_shot(cam_local_fish, look_local_fish, 58.0)

		"treasure_shark":
			# Golden-afternoon beach cove showcase on Cutlass Cay: 6 signature sculpted treasures + circling/charging Sharks!
			Weather.time_of_day = 15.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.03, 7.5, -0.35, 0.0, 0.32)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.08)
			if cutlass != null:
				var m_orig := cutlass.mooring_transform.origin
				var sea_dir := Vector3(m_orig.x, 0.0, m_orig.z)
				sea_dir = sea_dir.normalized() if sea_dir.length_squared() > 0.01 else Vector3(-0.363, 0.0, 0.932)
				var side_dir := Vector3(-sea_dir.z, 0.0, sea_dir.x).normalized()

				# Walk seaward along Cutlass Cay's landing cove to locate the exact shoreline crossing.
				var shore_r := 46.0
				for step_i in range(36, 150):
					var r_test := float(step_i) * 0.5
					var probe := cutlass.global_position + sea_dir * r_test
					if cutlass.world_surface_height(probe) <= 0.15:
						shore_r = r_test
						break

				var beach_c := cutlass.global_position + sea_dir * (shore_r - 3.8)
				var cam_base := beach_c - sea_dir * 2.55
				var cam_ground_y := maxf(cutlass.world_surface_height(cam_base), 0.35)
				var cam_p := Vector3(cam_base.x, cam_ground_y + 1.10, cam_base.z)

				# Arrange all 6 Wave 9B sculpted pirate treasures neatly across the sunlit golden dry sand.
				var loot_layout: Array[Array] = [
					[&"sovereign_chest", -1.10, 0.62, 0.32],
					[&"weeping_bilge_chest", 0.08, 0.78, -0.16],
					[&"spice_crate", 1.20, 0.50, -0.34],
					[&"captains_skull", -0.58, -0.18, 0.24],
					[&"archive_chalice", 0.04, -0.26, 0.08],
					[&"drowned_skull", 0.66, -0.14, -0.26],
				]
				var base_face_yaw := atan2(sea_dir.x, sea_dir.z)
				for entry in loot_layout:
					var tid: StringName = entry[0]
					var lat: float = float(entry[1])
					var fwd_off: float = float(entry[2])
					var yaw_jit: float = float(entry[3])
					var p_xz := beach_c + side_dir * lat + sea_dir * fwd_off
					var py := maxf(cutlass.world_surface_height(p_xz), 0.18) + 0.015
					var item := TreasureCatalog.create_treasure_carryable(tid, Vector3(p_xz.x, py, p_xz.z))
					item.freeze = true
					_entities_root.add_child(item)
					item.global_position = Vector3(p_xz.x, py, p_xz.z)
					item.rotation.y = base_face_yaw + yaw_jit

				# Spawn hero Wave 9A countershaded Shark surging broadside in ~1.05 m crystal turquoise shallows!
				var hero_shark_pos := cutlass.global_position + sea_dir * (shore_r + 8.5) + side_dir * 0.40
				var hero_shark := Shark.new()
				hero_shark.name = "HeroShallowsShark"
				hero_shark.circle_radius = 3.2
				hero_shark.swim_speed = 2.4
				_entities_root.add_child(hero_shark)
				var hsy := Sea.height(hero_shark_pos.x, hero_shark_pos.z) - 0.18
				hero_shark.global_position = Vector3(hero_shark_pos.x, hsy, hero_shark_pos.z)
				# Orient broadside-3/4 across the cove so gills, countershading, dorsal fin, open toothed jaw & tail read vividly!
				var shark_fwd := (side_dir * 0.88 - sea_dir * 0.47).normalized()
				hero_shark.rotation.y = atan2(-shark_fwd.x, -shark_fwd.z)
				hero_shark.state = Shark.State.CHARGE
				hero_shark.set_meta(&"hero_shark_anchor", hero_shark_pos)
				hero_shark.set_meta(&"hero_shark_dir", shark_fwd)
				active_sharks.append(hero_shark)

				# Second shark circling gracefully further out in the sunlit turquoise cove.
				var outer_shark_pos := cutlass.global_position + sea_dir * (shore_r + 14.5) - side_dir * 3.8
				var outer_shark := Shark.new()
				outer_shark.name = "CoveCirclingShark"
				outer_shark.circle_radius = 6.2
				_entities_root.add_child(outer_shark)
				outer_shark.global_position = Vector3(outer_shark_pos.x, Sea.height(outer_shark_pos.x, outer_shark_pos.z) - 0.30, outer_shark_pos.z)
				active_sharks.append(outer_shark)

				var look_p := cutlass.global_position + sea_dir * (shore_r + 4.0) + Vector3(0.0, 0.52, 0.0)
				_mount_shot_camera(cam_p, look_p, 54.0)


func _enable_ship_track_shot(cam_local: Vector3, look_local: Vector3, fov_deg: float) -> void:
	_shot_track_ship = true
	_shot_track_cam_local = cam_local
	_shot_track_look_local = look_local
	_mount_shot_camera(player_ship.global_transform * cam_local, player_ship.global_transform * look_local, fov_deg)
	_update_tracked_shot_camera()


func _tick_hero_shot_tracking(delta: float) -> void:
	if _shot_combat_timer > 0.0:
		_shot_combat_timer -= delta
		if _shot_combat_timer <= 0.0 and player_ship != null and is_instance_valid(player_ship):
			player_ship.aim_cannon(&"starboard", 0.0, 0.10)
			player_ship.fire_cannon(&"starboard", player_pawn)
			if player_ship.get_station(&"cannon", &"starboard_aft") != null:
				player_ship.aim_cannon(&"starboard_aft", 0.0, 0.10)
				player_ship.fire_cannon(&"starboard_aft", player_pawn)
	if active_shot_mode == "fishing" and fishing_line != null and is_instance_valid(fishing_line):
		if fishing_line.state == FishingLine.State.HOOKED:
			var t_sec := float(Time.get_ticks_msec()) * 0.001
			fishing_line.fish_fighting = true
			fishing_line.line_tension = 0.80 + sin(t_sec * 4.5) * 0.05
			fishing_line.distance_out = 7.6
			fishing_line.step(0.0, fishing_line.global_position, false)
	elif active_shot_mode == "treasure_shark":
		var t_sec := float(Time.get_ticks_msec()) * 0.001
		for sh in active_sharks:
			if sh != null and is_instance_valid(sh) and sh.has_meta(&"hero_shark_anchor"):
				var anchor: Vector3 = sh.get_meta(&"hero_shark_anchor")
				var sdir: Vector3 = sh.get_meta(&"hero_shark_dir")
				sh.state = Shark.State.CHARGE
				var glide := sin(t_sec * 0.85) * 0.55
				var px := anchor.x + sdir.x * glide
				var pz := anchor.z + sdir.z * glide
				sh.global_position = Vector3(px, Sea.height(px, pz) - 0.18, pz)
				sh.rotation.y = atan2(-sdir.x, -sdir.z) + sin(t_sec * 1.4) * 0.08
	if _shot_track_ship:
		_update_tracked_shot_camera()


func _update_tracked_shot_camera() -> void:
	if _shot_camera == null or player_ship == null or not is_instance_valid(player_ship):
		return
	var yaw_basis := Basis(Vector3.UP, player_ship.global_rotation.y)
	var ship_pos := player_ship.global_position
	var cam_pos := ship_pos + yaw_basis * _shot_track_cam_local
	var look_pt := ship_pos + yaw_basis * _shot_track_look_local
	if _shot_track_world_target != null and is_instance_valid(_shot_track_world_target):
		var target_pt := _shot_track_world_target.global_position + Vector3(0.0, _shot_track_world_y_off, 0.0)
		look_pt = ship_pos.lerp(target_pt, _shot_track_world_blend) + Vector3(0.0, 1.4, 0.0)
	_shot_camera.global_position = cam_pos
	_shot_camera.look_at(look_pt, Vector3.UP)


func _place_sailing_ship(pos_xz: Vector3, yaw_rad: float, sail_val: float, fwd_speed: float) -> void:
	var sy := Sea.height(pos_xz.x, pos_xz.z)
	var b := Basis(Vector3.UP, yaw_rad)
	player_ship.global_transform = Transform3D(b, Vector3(pos_xz.x, sy, pos_xz.z))
	player_ship.set_anchor(false)
	player_ship.anchor_progress = 0.0
	player_ship.set_sail_target(sail_val)
	player_ship.sail_set = sail_val
	player_ship.set_trim_target(player_ship.ideal_sail_trim())
	player_ship.sail_trim = player_ship.ideal_sail_trim()
	player_ship.linear_velocity = -b.z * fwd_speed
	player_ship.angular_velocity = Vector3.ZERO
	# Re-board player and crew cleanly onto the moved ship.
	if player_pawn != null:
		player_pawn.board(player_ship, _captain_deck_pos(player_ship))
		player_pawn.look_yaw = yaw_rad
	var specs := _crew_specs_for(player_ship)
	for i in crew_pawns.size():
		if crew_pawns[i] != null:
			crew_pawns[i].board(player_ship, specs[i % specs.size()]["local_pos"] as Vector3)


func _mount_shot_camera(world_pos: Vector3, look_target: Vector3, fov_deg: float) -> void:
	if _shot_camera == null:
		_shot_camera = Camera3D.new()
		_shot_camera.name = "HeroShotCamera"
		_shot_camera.near = 0.08
		_shot_camera.far = 8000.0
		add_child(_shot_camera)
	_shot_camera.fov = fov_deg
	_shot_camera.global_position = world_pos
	_shot_camera.look_at(look_target, Vector3.UP)
	_shot_camera.make_current()


# ==============================================================================
# Utilities
# ==============================================================================

func _tick_bobbing_props(delta: float) -> void:
	var idx := 0
	while idx < _bobbing_props.size():
		var entry: Dictionary = _bobbing_props[idx]
		var node: Variant = entry["node"]
		if not is_instance_valid(node):
			_bobbing_props.remove_at(idx)
			continue
		var n3 := node as Node3D
		var x: float = float(entry["x"])
		var z: float = float(entry["z"])
		var y_off: float = float(entry["y_off"])
		var phase: float = float(entry["phase"]) + delta * 1.4
		entry["phase"] = phase
		n3.global_position = Vector3(x, Sea.height(x, z) + y_off, z)
		n3.rotation.x = sin(phase) * 0.09
		n3.rotation.z = cos(phase * 0.85) * 0.09
		idx += 1


func _build_chart_map_data() -> Array[Dictionary]:
	var raw := archipelago.get_map_data()
	var enriched: Array[Dictionary] = []
	for d in raw:
		var copy := d.duplicate(true)
		if copy.has("contour_points") and not copy.has("contour"):
			copy["contour"] = copy["contour_points"]
		enriched.append(copy)
	return enriched


func _outpost_positions_array() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for op in archipelago.get_outposts():
		out.append(op.global_position)
	return out


func _outpost_positions_dict() -> Dictionary:
	var out := {}
	for op in archipelago.get_outposts():
		out[StringName(op.island_id)] = op.global_position
	return out


static func _character_visual_of(p: Pawn) -> CharacterVisual:
	if p == null:
		return null
	var cv := p.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
	if cv != null:
		return cv
	var found := p.find_children("*", "CharacterVisual", true, false)
	if not found.is_empty():
		return found[0] as CharacterVisual
	return null
