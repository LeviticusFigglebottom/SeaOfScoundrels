extends Node3D
## Sea of Scoundrels -- Full Playable Vertical Slice Main Scene.
##
## Assembles SkyRig, Ocean, 14-island Archipelago, Sloop/Brigantine Ship with
## live MapTableView, CookingStove & FishingLine, first-person Captain Pawn +
## Inventory + CombatComponent + 3 AI Crewmates (or Co-op peers), GameHUD,
## ShipwrightMenu, VoyageManager (Story Chapters + Procedural Contracts),
## WorldDirector living-sea events, and live Audio ambience & adaptive music.
##
## CLI user args (passed after `--`):
##   host | join=IP | port=N
##   time=H | storm=S | cloud=C | quality=low|med|high | ship=sloop|brigantine | vista=morning|sunset|twilight|storm
##   shot=outpost_dock|sailing|island_approach|combat|storm|sunset|night|night_sail|night_lighthouse|rainbow|whale_breach|helm|map_table|hold|cabin|flotsam|deck_duel|leviathan|fleet|company_fleet|fort_vault|dolphins|sovereigns_bastion|galleons_reach|emerald_waterfall|archipelago_panorama

const SKY_RIG_SCENE: PackedScene = preload("res://src/sky/sky_rig.tscn")
const OCEAN_SCENE: PackedScene = preload("res://src/ocean/ocean.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const BARREL_PROP_SCENE: PackedScene = preload("res://assets/generated/props/barrel_prop.glb")
const CRATE_PROP_SCENE: PackedScene = preload("res://assets/generated/props/crate_supply.glb")
const FORT_VAULT_SCRIPT: GDScript = preload("res://src/world/fort_vault.gd")

const BRIGANTINE_SCENE_PATH := "res://src/ship/brigantine.tscn"
const DOLPHIN_POD_PATH := "res://src/world/dolphin_pod.gd"
const FLOTSAM_CLUSTER_PATH := "res://src/world/flotsam_cluster.gd"
const OCEAN_WHALE_PATH := "res://src/world/ocean_whale.gd"
const VICTORY_FLARE_PATH := "res://src/world/victory_flare.gd"

const CREW_SPECS: Array[Dictionary] = [
	{"persona": &"helmsman", "local_pos": Vector3(-1.55, 1.12, 1.35)},
	{"persona": &"lookout", "local_pos": Vector3(0.0, 1.12, -3.75)},
	{"persona": &"carpenter", "local_pos": Vector3(1.55, 1.12, -0.95)},
]

const BRIGANTINE_CREW_SPECS: Array[Dictionary] = [
	{"persona": &"helmsman", "local_pos": Vector3(-1.85, 1.25, 2.25)},
	{"persona": &"lookout", "local_pos": Vector3(0.0, 1.25, -6.10)},
	{"persona": &"carpenter", "local_pos": Vector3(1.85, 1.25, -1.10)},
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
var location_banner: LocationBanner = null
var shipwright_menu: ShipwrightMenu = null
var title_menu: TitleMenu = null
var _last_banner_island_id: StringName = &""
var voyage_manager: VoyageManager = null
var world_director: WorldDirector = null
var tutorial_director: TutorialDirector = null
var skirmish_director: SkirmishDirector = null
var user_settings: UserSettings = null
var active_session_config: SessionConfig = SessionConfig.new()

var active_enemies: Array[Pawn] = []
var enemy_ships: Array[Ship] = []
var active_sharks: Array[Shark] = []
var active_leviathans: Array[Leviathan] = []
var active_megalodons: Array[AncientMegalodon] = []
var active_mermaid: SeaMermaid = null
var current_music_mood: StringName = &""
var sea_soundscape: SeaSoundscape = null
var player_rowboat: Rowboat = null
var active_shot_mode: String = ""

var _entities_root: Node3D = null
var _shot_camera: Camera3D = null
var _title_camera: Camera3D = null
var _title_orbit_time: float = 0.0
var _title_mode_active: bool = false
var _current_spawn_outpost_id: StringName = &"port_scoundrel"
var _skirmish_enemies: Array[Node] = []
var _shot_track_ship: bool = false
var _shot_track_cam_local: Vector3 = Vector3.ZERO
var _shot_track_look_local: Vector3 = Vector3.ZERO
var _shot_track_world_target: Node3D = null
var _shot_track_world_blend: float = 0.0
var _shot_track_world_y_off: float = 3.2
var _shot_combat_timer: float = -1.0
var _shot_duel_spark_timer: float = -1.0
var _shot_duel_clash_local: Vector3 = Vector3.ZERO
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
var _active_dolphin_pod: Node3D = null
var _dolphin_pod_cooldown: float = 52.0
var _active_whale: Node3D = null
var _whale_ambient_timer: float = 95.0
var _hero_coral_manta: Node3D = null
var _hero_coral_manta_anchor: Vector3 = Vector3.ZERO
var _hero_coral_manta_dir: Vector3 = Vector3.RIGHT

# Parsed CLI options
var _cli_host: bool = false
var _cli_join_ip: String = ""
var _cli_port: int = Net.DEFAULT_PORT
var _cli_time: float = NAN
var _cli_storm: float = NAN
var _cli_cloud: float = NAN
var _cli_quality: String = ""
var _cli_ship_class: StringName = &"sloop"
var _cli_ship_explicit: bool = false
var _cli_skip_menu: bool = false
var _cli_vista: StringName = &""


func _ready() -> void:
	_parse_cli_args()
	_start_network_session()

	user_settings = UserSettings.new()
	user_settings.load_from()
	if not _cli_ship_explicit and active_shot_mode in ["sovereigns_bastion", "galleons_reach", "title_menu", "play_setup"]:
		_cli_ship_class = &"brigantine"
	elif _cli_ship_class == &"sloop" and not _cli_ship_explicit and Game != null and Game.profile != null:
		var saved_cls := String(Game.profile.data.get("ship_class", "sloop"))
		if saved_cls == "brigantine":
			_cli_ship_class = &"brigantine"

	_entities_root = Node3D.new()
	_entities_root.name = "Entities"
	add_child(_entities_root)

	_build_environment_and_world()
	_build_player_ship()
	_build_player_and_crew()
	IslandWildlife.populate_archipelago(self, archipelago, player_pawn)
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

	var should_open_title := (
		active_shot_mode == ""
		and not _cli_host
		and _cli_join_ip == ""
		and not _cli_skip_menu
		and DisplayServer.get_name() != "headless"
	)

	if active_shot_mode != "":
		_apply_hero_shot(active_shot_mode)
	elif should_open_title and title_menu != null:
		_enter_title_menu(TitleMenu.Page.LANDING)
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
	_skirmish_enemies.clear()
	_title_camera = null
	_active_dolphin_pod = null
	_disconnect_autoload_signals()
	if Net != null:
		Net.unregister_replicated_ship(&"player_sloop")
		Net.unregister_replicated_pawn(Net.local_id())
		for pid: int in _peer_pawns.keys():
			Net.unregister_replicated_pawn(pid)
	_drain_static_visual_caches()


static func _drain_static_visual_caches() -> void:
	# Release statically cached procedural meshes, materials & textures on main teardown
	# so live .exe exits cleanly with 0 leaked GPU resources (each class rebuilds lazily on demand).
	TreasureCatalog.clear_mesh_cache()
	ToolMeshes.clear_shared_cache()
	Cannonball.clear_shared_cache()
	ShipNameplate.clear_shared_cache()
	HullCrest.clear_shared_cache()
	CaptainCabinFurnishings.clear_shared_cache()
	WindRibbons.clear_shared_cache()
	ShipHarpoon.clear_shared_cache()
	ShipSupplyBarrels.clear_shared_cache()
	Rowboat.clear_shared_cache()
	ShipDamageVisuals.clear_shared_cache()
	ShipEmissaryFlag.clear_shared_cache()
	ShipFire.clear_shared_cache()
	Ship.clear_curse_ring_cache()
	WorldEventCloud.clear_shared_cache()
	CombatComponent.clear_shared_vfx_cache()
	EnemyBrain.clear_shared_vfx_cache()
	Leviathan.clear_shared_cache()
	AncientMegalodon.clear_shared_cache()
	Shark.clear_shared_cache()
	SeaMermaid.clear_shared_cache()
	CoralReef.clear_shared_cache()
	ReefFishSchool.clear_shared_cache()
	MantaRay.clear_shared_cache()
	DolphinPod.clear_shared_cache()
	OceanWhale.clear_shared_cache()
	FlotsamCluster.clear_shared_cache()
	SunkenShipwreck.clear_shared_cache()
	PowderKeg.clear_shared_cache()
	FortBattery.clear_shared_cache()
	IslandDetails.clear_shared_cache()
	IslandWildlife.clear_shared_cache()
	FortVault.clear_shared_cache()
	VictoryFlare.clear_shared_cache()
	IslandWaterfall.clear_shared_cache()
	VolcanicFumarole.clear_shared_cache()
	MerchantStall.clear_shared_cache()
	DigSite.clear_shared_cache()
	MessageBottle.clear_shared_cache()
	SupplyBarrel.clear_shared_cache()
	Outpost.clear_shared_cache()


# ==============================================================================
# CLI & Network Session
# ==============================================================================

func _parse_cli_args() -> void:
	for raw_arg in OS.get_cmdline_user_args():
		var a := String(raw_arg).strip_edges()
		if a == "host":
			_cli_host = true
		elif a == "skip_menu" or a == "--skip-menu":
			_cli_skip_menu = true
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
			_cli_ship_explicit = true
			var s_arg := a.trim_prefix("ship=").to_lower()
			if s_arg == "brigantine":
				_cli_ship_class = &"brigantine"
			else:
				_cli_ship_class = &"sloop"
		elif a.begins_with("shot="):
			active_shot_mode = a.trim_prefix("shot=").to_lower()
		elif a.begins_with("vista="):
			_cli_vista = StringName(a.trim_prefix("vista=").strip_edges().to_lower())


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
	_sync_cabin_renown(false)
	_sync_ship_name()

	if sea_soundscape == null or not is_instance_valid(sea_soundscape):
		sea_soundscape = SeaSoundscape.new()
		sea_soundscape.name = "SeaSoundscape"
		add_child(sea_soundscape)
	sea_soundscape.bind_ship(player_ship)

	_mount_player_rowboat(player_ship)
	ShipEmissaryFlag.mount_to_ship(player_ship)

	Net.register_replicated_ship(&"player_sloop", player_ship)


func _sync_emissary_visuals() -> void:
	var comp := &""
	var grade := 0
	var mult := 1.0
	if voyage_manager != null and voyage_manager.emissary != null:
		comp = voyage_manager.emissary.active_company
		grade = voyage_manager.emissary.grade
		mult = voyage_manager.emissary.get_multiplier(comp)
	if player_ship != null and is_instance_valid(player_ship):
		var eflag := ShipEmissaryFlag.mount_to_ship(player_ship)
		if eflag != null:
			eflag.set_emissary(comp, grade)
	if world_director != null and is_instance_valid(world_director):
		world_director.emissary_grade = grade
	if hud != null and is_instance_valid(hud):
		hud.set_emissary_status(comp, grade, mult)


static func _emissary_flare_color(company_id: StringName) -> Color:
	var fallback: Array = ShipEmissaryFlag.COMPANY_AURA_COLORS[&"gilded_compass"]
	var pal: Array = ShipEmissaryFlag.COMPANY_AURA_COLORS.get(company_id, fallback)
	if not pal.is_empty() and pal[0] is Color:
		return pal[0] as Color
	return Color(1.00, 0.84, 0.28, 1.0)


func _on_emissary_grade_changed(company_id: StringName, new_grade: int, _multiplier: float) -> void:
	_sync_emissary_visuals()
	if new_grade < EmissaryLedger.MAX_GRADE or not Net.is_host():
		return
	var company_label := EmissaryLedger.company_short_name(company_id)
	if player_ship != null and is_instance_valid(player_ship):
		var flare_col := _emissary_flare_color(company_id)
		_launch_victory_flare(player_ship.global_position + Vector3(0.0, 3.8, 0.0), flare_col)
	if Audio != null:
		Audio.play_stinger(&"victory")
	if location_banner != null and is_instance_valid(location_banner):
		location_banner.show_location(
			"EMISSARY GRADE V",
			"%s -- 2.50x Payout Mastery!" % company_label,
			&"outpost",
			3.5
		)
	for br in crew_brains:
		if br != null and is_instance_valid(br) and br.has_method(&"notify_emissary_grade_v"):
			br.notify_emissary_grade_v(company_label)


func _mount_player_rowboat(target_ship: Ship) -> void:
	if target_ship == null or not is_instance_valid(target_ship):
		return
	if player_rowboat == null or not is_instance_valid(player_rowboat):
		player_rowboat = Rowboat.new()
		player_rowboat.name = "PlayerRowboat"
		add_child(player_rowboat)
		player_rowboat.launched.connect(_on_player_rowboat_launched)
		player_rowboat.docked.connect(_on_player_rowboat_docked)
		player_rowboat.attach_to_ship(target_ship)
	elif player_rowboat.is_docked():
		player_rowboat.attach_to_ship(target_ship)
	else:
		player_rowboat.mother_ship = target_ship


func _on_player_rowboat_launched(_by_pawn: Node) -> void:
	if not Net.is_host():
		return
	for br in crew_brains:
		if br != null and is_instance_valid(br):
			if br.notify_rowboat_launched():
				return


func _on_player_rowboat_docked(_by_pawn: Node) -> void:
	if not Net.is_host():
		return
	for br in crew_brains:
		if br != null and is_instance_valid(br):
			if br.notify_rowboat_docked():
				return


func _resolve_ship_scene(cls: StringName) -> PackedScene:
	if cls == &"brigantine" and ResourceLoader.exists(BRIGANTINE_SCENE_PATH):
		var loaded := load(BRIGANTINE_SCENE_PATH) as PackedScene
		if loaded != null:
			return loaded
	return SLOOP_SCENE


static func _ship_scale_of(target_ship: Ship) -> float:
	if target_ship != null and is_instance_valid(target_ship):
		var hs: Variant = target_ship.get(&"hull_scale")
		if hs != null and float(hs) > 0.01:
			return float(hs)
	return 1.0


func _captain_deck_pos(target_ship: Ship) -> Vector3:
	var hs := _ship_scale_of(target_ship)
	if target_ship != null and target_ship.ship_class == &"brigantine":
		return Vector3(0.0, 2.25, 5.65) * hs
	return Vector3(0.0, 2.02, 4.15) * hs


func _crew_specs_for(target_ship: Ship) -> Array[Dictionary]:
	if target_ship != null and target_ship.ship_class == &"brigantine":
		return BRIGANTINE_CREW_SPECS
	return CREW_SPECS


func _crew_local_pos(target_ship: Ship, idx: int) -> Vector3:
	var specs := _crew_specs_for(target_ship)
	var base := specs[idx % specs.size()]["local_pos"] as Vector3
	return base * _ship_scale_of(target_ship)


func _mount_cooking_stove(target_ship: Ship) -> void:
	cooking_stove = CookingStove.new()
	cooking_stove.name = "CookingStove"
	cooking_stove.build_hearth = true
	var hs := _ship_scale_of(target_ship)
	if target_ship.ship_class == &"brigantine":
		cooking_stove.position = Vector3(1.65, -0.95, 1.85) * hs
	else:
		cooking_stove.position = Vector3(1.25, -0.85, 0.85) * hs
	target_ship.add_child(cooking_stove)

	# Intercept stove interaction when player holds freshly caught fish from FishingLine.
	if cooking_stove.interactable != null:
		cooking_stove.interactable.position = Vector3(-0.1, 0.65, 0.0)
		cooking_stove.interactable.reach = 2.8


func _mount_fishing_station(target_ship: Ship) -> void:
	fishing_line = FishingLine.new()
	fishing_line.name = "FishingLine"
	var hs := _ship_scale_of(target_ship)
	if target_ship.ship_class == &"brigantine":
		fishing_line.position = Vector3(-1.75, 2.25, 7.65) * hs
	else:
		fishing_line.position = Vector3(-1.48, 2.0, 5.72) * hs
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
	inventory.map_table = map_table
	player_pawn.add_child(inventory)
	inventory.bind(player_pawn, player_controller, player_combat, p_cv)

	player_pawn.died.connect(_on_player_died)
	Net.register_replicated_pawn(Net.local_id(), player_pawn)

	# 2. Three AI Crewmates: Barnaby (helmsman), Maren (lookout), Pip (carpenter).
	crew_pawns.clear()
	crew_brains.clear()
	var specs := _crew_specs_for(player_ship)
	for i in specs.size():
		var spec := specs[i]
		var persona: StringName = spec["persona"]
		var local_pos := _crew_local_pos(player_ship, i)
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

	tutorial_director = TutorialDirector.new()
	tutorial_director.name = "TutorialDirector"
	add_child(tutorial_director)
	tutorial_director.bind(player_ship, player_pawn, inventory, map_table, player_rowboat)

	skirmish_director = SkirmishDirector.new()
	skirmish_director.name = "SkirmishDirector"
	add_child(skirmish_director)

	# Wire MapTableView live references.
	if map_table != null:
		map_table.voyage_manager = voyage_manager
		map_table.world_director = world_director
		map_table.refresh_now()

	# Apply Economy sidegrades, liveries, tool modifiers & crew traits from Game.profile.
	ShipwrightMenu.apply_economy_to_ship(player_ship, Game.profile, crew_brains, world_director)
	_apply_inventory_tool_modifiers()


func _build_ui() -> void:
	hud = GameHUD.new()
	hud.name = "GameHUD"
	hud.input_enabled = (active_shot_mode == "")
	add_child(hud)
	hud.bind(player_pawn, player_controller, inventory, player_combat, player_ship, voyage_manager, sky_rig)
	for b in crew_brains:
		hud.register_crew_brain(b)
	hud.return_to_title_requested.connect(_on_hud_return_to_title)
	hud.mode_skip_requested.connect(_on_hud_mode_skip)

	location_banner = LocationBanner.new()
	location_banner.name = "LocationBanner"
	add_child(location_banner)

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
	shipwright_menu.loadout_changed.connect(func(_slot: StringName, _unlock_id: StringName) -> void:
		_apply_inventory_tool_modifiers()
	)
	shipwright_menu.ship_class_selected.connect(_on_ship_class_selected)
	shipwright_menu.settings_changed.connect(_on_settings_changed)
	if shipwright_menu.has_signal(&"emissary_changed"):
		shipwright_menu.connect(&"emissary_changed", func(_comp: StringName, _grade: int) -> void:
			_sync_emissary_visuals()
		)
	if shipwright_menu.has_signal(&"ship_name_changed"):
		shipwright_menu.connect(&"ship_name_changed", func(new_name: String) -> void:
			if player_ship != null and is_instance_valid(player_ship) and player_ship.has_method(&"set_ship_name"):
				player_ship.call(&"set_ship_name", new_name)
		)

	title_menu = TitleMenu.new()
	title_menu.name = "TitleMenu"
	add_child(title_menu)
	title_menu.bind(user_settings, Game.profile if Game != null else null, self)
	title_menu.preview_config_changed.connect(_on_title_preview_changed)
	title_menu.start_game_requested.connect(_on_title_start_game)
	title_menu.settings_changed.connect(_on_settings_changed)
	title_menu.quit_requested.connect(_on_title_quit_requested)


func _wire_world_signals() -> void:
	# Wire every Outpost's Voyage Board & Merchant Stall signals.
	for outpost in archipelago.get_outposts():
		var out_id := StringName(outpost.island_id)
		outpost.voyage_board_used.connect(func(_pawn: Node) -> void:
			_on_outpost_voyage_board_used(out_id)
		)
		outpost.treasure_sold.connect(_on_outpost_treasure_sold)

	# Wire every DigSite currently on every island + emergent beach MessageBottles & SupplyBarrels.
	for isl in archipelago.get_islands():
		for ds in isl.get_dig_sites():
			_wire_dig_site(ds)
	_wire_message_bottles()
	_wire_supply_barrels()

	# VoyageManager signals.
	voyage_manager.voyage_started.connect(_on_voyage_started)
	voyage_manager.voyage_stage_changed.connect(_on_voyage_stage_changed)
	voyage_manager.voyage_completed.connect(_on_voyage_completed)
	if voyage_manager.emissary != null:
		voyage_manager.emissary.flag_raised.connect(func(_company_id: StringName) -> void:
			_sync_emissary_visuals()
		)
		voyage_manager.emissary.grade_changed.connect(_on_emissary_grade_changed)
		voyage_manager.emissary.flag_lowered.connect(func(_c: StringName, _g: int, _gold: int, _ren: int) -> void:
			_sync_emissary_visuals()
		)
		voyage_manager.emissary.flag_broken.connect(func(_c: StringName, _g: int) -> void:
			_sync_emissary_visuals()
		)
	_sync_emissary_visuals()

	# Maiden Voyage TutorialDirector & Naval SkirmishDirector signals.
	if tutorial_director != null:
		tutorial_director.step_changed.connect(_on_tutorial_step_changed)
		tutorial_director.step_completed.connect(_on_tutorial_step_completed)
		tutorial_director.tutorial_completed.connect(_on_tutorial_completed)
		tutorial_director.tutorial_skipped.connect(_on_tutorial_skipped)
	if skirmish_director != null:
		skirmish_director.wave_started.connect(_on_skirmish_wave_started)
		skirmish_director.spawn_ship_requested.connect(_on_skirmish_spawn_ship)
		skirmish_director.spawn_leviathan_requested.connect(_on_skirmish_spawn_leviathan)
		skirmish_director.restock_requested.connect(_on_skirmish_restock)
		skirmish_director.objective_updated.connect(_on_skirmish_objective_updated)
		skirmish_director.skirmish_victory.connect(_on_skirmish_victory)

	# WorldDirector living-sea event signals.
	world_director.spawn_rival_ship.connect(_on_director_spawn_rival_ship)
	world_director.spawn_ghost_ship.connect(_on_director_spawn_ghost_ship)
	world_director.spawn_shark_pack.connect(_on_director_spawn_shark_pack)
	world_director.spawn_leviathan.connect(_on_director_spawn_leviathan)
	world_director.spawn_megalodon.connect(_on_director_spawn_megalodon)
	world_director.spawn_flotsam_barrels.connect(_on_director_spawn_flotsam)
	world_director.spawn_fort_siege.connect(_on_director_spawn_fort_siege)
	world_director.spawn_castaway.connect(_on_director_spawn_castaway)
	world_director.spawn_shipwreck.connect(_on_director_spawn_shipwreck)
	world_director.spawn_storm_cell.connect(_on_director_spawn_storm_cell)
	world_director.sighting_warning.connect(_on_director_sighting_warning)
	world_director.event_cloud_spawned.connect(_on_director_event_cloud_spawned)

	# Ship sinking -> zero-wipe salvage wreck & restore at last outpost.
	player_ship.sunk.connect(_on_player_ship_sunk)
	player_ship.hull_impacted.connect(_on_player_ship_hull_impacted)
	_wire_ship_bell(player_ship)

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
	_tick_title_camera(delta)
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
	if active_shot_mode == "deck_duel":
		hud.set_boss_encounter("", 0.0, false)
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
	_tick_dolphin_pod(delta)
	_tick_ambient_whale(delta)


func _apply_inventory_tool_modifiers() -> void:
	if inventory == null or not is_instance_valid(inventory) or Game == null or Game.profile == null:
		return
	if inventory.has_method(&"apply_tool_modifiers"):
		var mods := Economy.get_ship_modifiers(Game.profile)
		inventory.call(&"apply_tool_modifiers", mods)


func _spawn_dolphin_pod(count: int = 3, duration: float = 28.0) -> Node3D:
	if _entities_root == null or player_ship == null or not is_instance_valid(player_ship):
		return null
	if not ResourceLoader.exists(DOLPHIN_POD_PATH):
		return null
	var pod_script := load(DOLPHIN_POD_PATH) as GDScript
	if pod_script == null:
		return null
	var pod: Node3D = null
	if pod_script.has_method(&"spawn_alongside"):
		pod = pod_script.call(&"spawn_alongside", _entities_root, player_ship, count, duration) as Node3D
	else:
		pod = pod_script.new() as Node3D
		if pod != null:
			_entities_root.add_child(pod)
	_active_dolphin_pod = pod
	return pod


func _has_active_combat_or_boss() -> bool:
	if player_combat != null and is_instance_valid(player_combat) and player_combat.state != CombatComponent.State.IDLE:
		return true
	for lev in active_leviathans:
		if lev != null and is_instance_valid(lev) and not lev.is_defeated():
			return true
	if player_ship != null and is_instance_valid(player_ship):
		for foe in enemy_ships:
			if foe != null and is_instance_valid(foe) and not foe.is_sinking:
				if foe.global_position.distance_to(player_ship.global_position) < 220.0:
					return true
	return false


func _tick_dolphin_pod(delta: float) -> void:
	if active_shot_mode != "":
		return
	if _active_dolphin_pod != null:
		if is_instance_valid(_active_dolphin_pod) and _active_dolphin_pod.is_inside_tree():
			return
		_active_dolphin_pod = null
	if player_ship == null or not is_instance_valid(player_ship) or player_ship.is_sinking:
		return
	if player_ship.forward_speed() < 3.2 or Weather.storminess >= 0.42:
		return
	if _has_active_combat_or_boss():
		return
	_dolphin_pod_cooldown -= delta
	if _dolphin_pod_cooldown > 0.0:
		return
	_dolphin_pod_cooldown = randf_range(45.0, 75.0)
	var pod := _spawn_dolphin_pod(3, 28.0)
	if pod != null:
		var speaker := "Maren"
		for br in crew_brains:
			if br != null and is_instance_valid(br) and br.persona_id == &"lookout":
				speaker = br.crew_name()
				break
		Game.post_notice("%s: Dolphins off the bow, Cap'n! Fair winds ahead!" % speaker)


func _spawn_whale_breach(world_pos: Vector3, heading_yaw: float) -> Node3D:
	if _entities_root == null or not ResourceLoader.exists(OCEAN_WHALE_PATH):
		return null
	var whale_script := load(OCEAN_WHALE_PATH) as GDScript
	if whale_script == null:
		return null
	var whale: Node3D = null
	if whale_script.has_method(&"spawn_breach"):
		whale = whale_script.call(&"spawn_breach", _entities_root, world_pos, heading_yaw) as Node3D
	else:
		whale = whale_script.new() as Node3D
		if whale != null:
			_entities_root.add_child(whale)
			whale.global_position = world_pos
			whale.rotation.y = heading_yaw
	_active_whale = whale
	return whale


func _tick_ambient_whale(delta: float) -> void:
	if active_shot_mode != "" or archipelago == null:
		return
	if _active_whale != null:
		if is_instance_valid(_active_whale) and _active_whale.is_inside_tree():
			return
		_active_whale = null
	if player_ship == null or not is_instance_valid(player_ship) or player_ship.is_sinking:
		return
	if player_ship.forward_speed() < 2.8 or Weather.storminess >= 0.40:
		return
	if _has_active_combat_or_boss():
		return
	var near_isl := archipelago.nearest_island(player_ship.global_position)
	if near_isl != null and player_ship.global_position.distance_to(near_isl.global_position) <= 160.0:
		return
	_whale_ambient_timer -= delta
	if _whale_ambient_timer > 0.0:
		return
	_whale_ambient_timer = randf_range(95.0, 155.0)
	var side := 1.0 if randf() >= 0.5 else -1.0
	var ahead_dist := randf_range(70.0, 110.0)
	var lat_dist := side * randf_range(24.0, 42.0)
	var wpos := player_ship.global_transform * Vector3(lat_dist, 0.0, -ahead_dist)
	wpos.y = Sea.height(wpos.x, wpos.z)
	var whale := _spawn_whale_breach(wpos, player_ship.rotation.y + side * 0.65)
	if whale != null:
		var speaker := "Maren"
		for br in crew_brains:
			if br != null and is_instance_valid(br) and br.persona_id == &"lookout":
				speaker = br.crew_name()
				break
		Game.post_notice("%s: Great Humpback breaching off the bow, Cap'n! What a sight!" % speaker)


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
	_tick_sea_mermaid()


func _tick_sea_mermaid() -> void:
	if not Net.is_host() or _title_mode_active or active_shot_mode != "":
		return
	if active_mermaid != null and (not is_instance_valid(active_mermaid) or active_mermaid.is_queued_for_deletion()):
		active_mermaid = null
	if active_mermaid != null:
		return
	if SeaMermaid.should_spawn_for_pawn(player_pawn, player_ship):
		active_mermaid = SeaMermaid.spawn_near_swimmer(_entities_root, player_pawn, player_ship)
		if active_mermaid != null:
			Game.post_notice("A Sea Mermaid rises ahead with emerald smoke -- press [F] to return to your ship!")


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
		if d <= near_isl.island_radius + 95.0:
			var isl_key := StringName(near_isl.island_id)
			if not _title_mode_active and active_shot_mode == "" and location_banner != null \
					and isl_key != _last_banner_island_id:
				_last_banner_island_id = isl_key
				location_banner.show_location(
					near_isl.island_name,
					LocationBanner.format_island_subtitle(near_isl),
					LocationBanner.style_for_island(near_isl)
				)
		elif d > near_isl.island_radius + 165.0 and _last_banner_island_id == StringName(near_isl.island_id):
			_last_banner_island_id = &""
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


func _on_voyage_stage_changed(_stage_index: int, _objective_text: String) -> void:
	if voyage_manager == null or not voyage_manager.has_active_voyage():
		return
	_sync_voyage_to_hud_and_maps(voyage_manager.active_voyage)


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

		# Sync held treasure map / riddle scroll / wanted poster & MapTableView.
		_sync_voyage_to_hud_and_maps(voyage, target_isl, dig_local)

	if not already_built:
		if shape == &"cargo_run":
			_spawn_cargo_run_crates(voyage)
		elif shape == &"open_sea_hunt":
			var hunt_pos: Vector3 = voyage.get("target_position", Vector3(300.0, 0.0, -300.0))
			var threat := StringName(String(voyage.get("complication", {}).get("threat_archetype", &"drowned_sloop")))
			_spawn_enemy_vessel(threat, hunt_pos)


func _sync_voyage_to_hud_and_maps(
	voyage: Dictionary,
	target_isl: Island = null,
	dig_local: Vector3 = Vector3.ZERO
) -> void:
	if voyage.is_empty():
		return
	var target_id := String(voyage.get("target_island_id", ""))
	if target_isl == null and archipelago != null and target_id != "":
		target_isl = archipelago.get_island_by_id(target_id)
	var target_name := target_isl.display_name if target_isl != null else String(voyage.get("target_island_name", "Unknown Isle"))
	var shape := StringName(String(voyage.get("shape", &"buried_hoard")))
	var hook: Dictionary = voyage.get("hook", {})
	var hook_kind := StringName(String(hook.get("kind", &"")))

	if inventory != null:
		if (shape == &"riddle_trail" or hook_kind == &"riddle_clues") and inventory.has_method(&"set_riddle_scroll"):
			var stanzas: Array[String] = []
			var raw_clues: Variant = hook.get("clues", [])
			if raw_clues is Array:
				for c in (raw_clues as Array):
					stanzas.append(String(c))
			var revealed_count := 1
			if voyage_manager != null and voyage_manager.has_active_voyage():
				var st_idx := voyage_manager.current_stage_index
				if st_idx >= 2:
					revealed_count = maxi(1, stanzas.size())
				elif st_idx == 1:
					revealed_count = clampi(1 + voyage_manager.stage_progress, 1, maxi(1, stanzas.size()))
			inventory.call(&"set_riddle_scroll", target_name, stanzas, revealed_count)
		elif (shape == &"drowned_bounty" or hook_kind == &"bounty_poster") and inventory.has_method(&"set_bounty_poster"):
			var site_dict: Dictionary = voyage.get("site", {})
			var captain_name := String(site_dict.get("captain_name", ""))
			if captain_name == "":
				captain_name = String(voyage.get("title", "Drowned Captain")).trim_prefix("Bounty: ")
			var payoff_dict: Dictionary = voyage.get("payoff", {})
			var bounty_gold := int(payoff_dict.get("estimated_gold", payoff_dict.get("bonus_gold", 450)))
			inventory.call(&"set_bounty_poster", captain_name, target_name, bounty_gold)
		elif target_isl != null:
			var resolved_dig := dig_local
			if resolved_dig.is_zero_approx() and not target_isl.dig_points.is_empty():
				resolved_dig = target_isl.dig_points[0]
			inventory.set_treasure_map(
				target_isl.display_name,
				target_isl.contour_points,
				resolved_dig,
				target_isl.island_radius
			)

	if map_table != null and target_isl != null:
		map_table.set_voyage_target(target_isl.global_position)
		map_table.refresh_now()


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
	if tutorial_director != null and tutorial_director.active:
		tutorial_director.notify_treasure_unearthed()
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
	if tutorial_director != null and tutorial_director.active:
		tutorial_director.notify_treasure_sold()
	_update_cargo_value()
	_sync_cabin_renown(false)
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
	_sync_cabin_renown(false)
	if player_ship != null and is_instance_valid(player_ship):
		_launch_victory_flare(player_ship.global_position + Vector3(0.0, 3.6, 0.0), Color(1.0, 0.84, 0.28))
	Game.save()


func _launch_victory_flare(world_pos: Vector3, accent_col: Color = Color(1.0, 0.84, 0.28)) -> Node3D:
	if _entities_root == null or not ResourceLoader.exists(VICTORY_FLARE_PATH):
		return null
	var flare_gd := load(VICTORY_FLARE_PATH) as GDScript
	if flare_gd == null or not flare_gd.has_method(&"launch"):
		return null
	return flare_gd.call(&"launch", _entities_root, world_pos, accent_col) as Node3D


func _sync_cabin_renown(force_all: bool = false) -> void:
	if player_ship != null and is_instance_valid(player_ship) and player_ship.has_method(&"sync_cabin_renown"):
		player_ship.call(&"sync_cabin_renown", Game.profile if Game != null else null, force_all)


func _sync_ship_name() -> void:
	if player_ship == null or not is_instance_valid(player_ship) or not player_ship.has_method(&"set_ship_name"):
		return
	var nm := "The Gilded Scoundrel"
	if Game != null and Game.profile != null:
		var saved := String(Game.profile.data.get("ship_name", "")).strip_edges()
		if saved != "":
			nm = saved
	player_ship.call(&"set_ship_name", nm)


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
	lev.leviathan_defeated.connect(func(pos: Vector3, _salvage: Array) -> void:
		_launch_victory_flare(Vector3(pos.x, Sea.height(pos.x, pos.z) + 2.5, pos.z), Color(0.24, 0.94, 0.88))
	)
	active_leviathans.append(lev)
	if not _title_mode_active and active_shot_mode == "" and location_banner != null:
		location_banner.show_location("ABYSSAL LEVIATHAN", "World Boss -- Ink-Black Maelstrom", &"threat")


func _on_director_spawn_megalodon(center: Vector3, target: Node) -> void:
	if not Net.is_host():
		return
	var target_s: Ship = target as Ship if target is Ship else player_ship
	var mega := AncientMegalodon.spawn_near_ship(_entities_root, target_s, center)
	if mega != null:
		mega.megalodon_defeated.connect(func(_m: AncientMegalodon, pos: Vector3, _salvage: Array) -> void:
			_launch_victory_flare(Vector3(pos.x, Sea.height(pos.x, pos.z) + 2.8, pos.z), Color(0.18, 0.96, 0.88))
			Game.post_notice("Ancient Megalodon slain! Four treasures rise to the surface!")
		)
		active_megalodons.append(mega)
		if not _title_mode_active and active_shot_mode == "" and location_banner != null:
			location_banner.show_location("ANCIENT MEGALODON", "Open-Sea Apex Predator", &"threat")


func _on_director_spawn_flotsam(pos: Vector3, count: int) -> void:
	if not Net.is_host():
		return
	var cluster_script: GDScript = load(FLOTSAM_CLUSTER_PATH) as GDScript if ResourceLoader.exists(FLOTSAM_CLUSTER_PATH) else null
	var use_cluster := cluster_script != null and cluster_script.has_method(&"spawn_at")

	# Spawn sculpted bobbing FlotsamClusters (or legacy barrel/crate fallback) plus one floating treasure chest!
	for idx in maxi(1, count):
		var ang := float(idx) / float(maxi(1, count)) * TAU + 0.3
		var rad := 3.2 + float(idx % 2) * 2.6 if use_cluster else 2.4 + float(idx % 2) * 2.2
		var bx := pos.x + cos(ang) * rad
		var bz := pos.z + sin(ang) * rad
		var bpos := Vector3(bx, Sea.height(bx, bz), bz)
		if use_cluster:
			var cluster := cluster_script.call(&"spawn_at", _entities_root, bpos, idx + 1) as Node3D
			if cluster != null and cluster.has_signal(&"flotsam_salvaged"):
				cluster.connect(&"flotsam_salvaged", _on_flotsam_cluster_salvaged)
		else:
			var prop_scene := BARREL_PROP_SCENE if (idx % 2 == 0) else CRATE_PROP_SCENE
			var barrel := prop_scene.instantiate() as Node3D
			barrel.name = "FlotsamBarrel_%d" % idx
			_entities_root.add_child(barrel)
			barrel.global_position = Vector3(bx, bpos.y - 0.15, bz)
			var it := Interactable.create("Salvage flotsam supplies", 1.2)
			it.position = Vector3(0.0, 0.55, 0.0)
			it.interacted.connect(func(_p: Node) -> void:
				_on_flotsam_cluster_salvaged(barrel, _p, {"cannonballs": 4, "planks": 2, "gold": 35})
				barrel.queue_free()
			)
			barrel.add_child(it)
			_bobbing_props.append({"node": barrel, "x": bx, "z": bz, "y_off": -0.18, "phase": float(idx) * 1.3})

	var chest_pos := Vector3(pos.x, Sea.height(pos.x, pos.z) + 0.25, pos.z)
	var chest := TreasureCatalog.create_treasure_carryable(&"driftwood_chest", chest_pos)
	_entities_root.add_child(chest)
	chest.global_position = chest_pos

	# Circling gulls mark floating flotsam from the horizon ("gulls that mark loot").
	var flotsam_gulls := SeabirdFlock.spawn_over(_entities_root, Vector3(pos.x, 0.0, pos.z), 11.0, 14.0, 5)
	flotsam_gulls.is_loot_marker = true


func _on_flotsam_cluster_salvaged(cluster: Node, _pawn: Node, loot: Dictionary) -> void:
	if not Net.is_host():
		return
	var balls := int(loot.get("cannonballs", 4))
	var planks := int(loot.get("planks", 2))
	var gold := int(loot.get("gold", 35))
	if player_ship != null and is_instance_valid(player_ship):
		player_ship.cannonballs_remaining = mini(Ship.MAX_CANNONBALLS, player_ship.cannonballs_remaining + balls)
		player_ship.planks_remaining = mini(Ship.MAX_PLANKS, player_ship.planks_remaining + planks)
	if Game != null and Game.profile != null and gold > 0:
		Game.profile.add_gold(gold)
	var sfx_pos := (cluster as Node3D).global_position if (cluster is Node3D and is_instance_valid(cluster)) else Vector3.INF
	Audio.play_sfx(&"coin_jingle", sfx_pos)
	Game.post_notice("Salvaged supplies & %d gold from shipwreck flotsam!" % gold)


func _on_director_event_cloud_spawned(kind: StringName, world_pos: Vector3, _cloud_node: Node3D) -> void:
	if not Net.is_host():
		return
	var cloud_label := WorldEventCloud.label_for_kind(kind)
	var from_pos := player_ship.global_position if (player_ship != null and is_instance_valid(player_ship)) else Vector3.ZERO
	var bearing := WorldDirector.compass_bearing(from_pos, world_pos)
	for br in crew_brains:
		if br != null and is_instance_valid(br):
			if br.notify_event_cloud_sighted(cloud_label, bearing):
				return


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

	# Stash two interactive Gunpowder Kegs beside the fort ramp for tactical raiding or salvage!
	for k_idx in 2:
		var k_local := Vector3(-4.2 if k_idx == 0 else 4.2, 0.0, 11.5)
		k_local.y = fort.surface_height(k_local.x, k_local.z) + 0.08
		PowderKeg.spawn_at(_entities_root, fort.global_transform * k_local)


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
		if bool(vault.call(&"open_vault")):
			_launch_victory_flare(bastion.global_position + Vector3(0.0, 8.5, 0.0), Color(0.28, 0.96, 0.68))
			if location_banner != null and is_instance_valid(location_banner):
				location_banner.show_location(
					"FORT VAULT UNLOCKED",
					"Ironwatch Treasury Open -- Claim the Hoard!",
					&"outpost",
					3.4
				)
			for br in crew_brains:
				if br != null and is_instance_valid(br) and br.has_method(&"notify_fort_vault_opened"):
					br.notify_fort_vault_opened()


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


func _wire_supply_barrels() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for barrel in tree.get_nodes_in_group(&"supply_barrels"):
		if barrel == null or not is_instance_valid(barrel):
			continue
		if barrel.has_meta(&"supply_barrel_wired") or not barrel.has_signal(&"supplies_taken"):
			continue
		barrel.set_meta(&"supply_barrel_wired", true)
		barrel.connect(&"supplies_taken", _on_supply_barrel_taken)


func _on_supply_barrel_taken(_barrel: Node, _pawn: Node, loot: Dictionary) -> void:
	if not Net.is_host():
		return
	var balls := int(loot.get("cannonballs", 6))
	var planks := int(loot.get("planks", 3))
	if player_ship != null and is_instance_valid(player_ship):
		player_ship.cannonballs_remaining = mini(Ship.MAX_CANNONBALLS, player_ship.cannonballs_remaining + balls)
		player_ship.planks_remaining = mini(Ship.MAX_PLANKS, player_ship.planks_remaining + planks)
	Game.post_notice("Bonus barrel looted: +%d cannonballs & +%d planks!" % [balls, planks])


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


func _on_director_spawn_shipwreck(pos: Vector3, seed_val: int) -> void:
	if not Net.is_host():
		return
	var safe_pos := pos
	if archipelago != null:
		var near_isl := archipelago.nearest_island(safe_pos)
		if near_isl != null:
			var flat := Vector3(safe_pos.x - near_isl.global_position.x, 0.0, safe_pos.z - near_isl.global_position.z)
			var min_clear := near_isl.seabed_radius + 45.0
			if flat.length() < min_clear:
				var push_dir := flat.normalized() if flat.length_squared() > 0.01 else Vector3.FORWARD
				safe_pos = near_isl.global_position + push_dir * min_clear
	var wreck := SunkenShipwreck.spawn_at(_entities_root, safe_pos, seed_val)
	if wreck != null:
		wreck.shipwreck_cleared.connect(func(_w: SunkenShipwreck) -> void:
			if Net.is_host():
				Audio.play_stinger(&"discovery")
				Game.post_notice("Shipwreck plundered clean! All sunken treasures recovered.")
		)
		# Tuck a buoyant Gunpowder Keg near the wreck's broken port flank for daring divers!
		var keg_pos := Vector3(safe_pos.x + 5.2, Sea.height(safe_pos.x + 5.2, safe_pos.z - 2.4) + 0.15, safe_pos.z - 2.4)
		PowderKeg.spawn_at(_entities_root, keg_pos)


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

	# If flying a Trading Company Emissary Flag, it snaps on sinking and floats as salvage!
	if voyage_manager != null and voyage_manager.emissary != null and voyage_manager.emissary.is_active():
		var broken_flag := voyage_manager.emissary.break_flag_on_sink()
		if not broken_flag.is_empty():
			var wreck_items: Array = wreck.get("items", [])
			wreck_items.append({
				"treasure_id": &"captain_chest",
				"gold_value": int(broken_flag.get("gold_value", 250)),
				"display_name": String(broken_flag.get("name", "Broken Emissary Flag")),
			})
			wreck["items"] = wreck_items
			Game.post_notice("%s broke in the wreck - salvage its pennant at the buoy!" % String(broken_flag.get("name", "Emissary Flag")))
		_sync_emissary_visuals()

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
		var cap_local := _captain_deck_pos(player_ship)
		var cap_spawn := player_ship.global_transform * cap_local
		if player_pawn.dead:
			player_pawn.revive(cap_spawn)
		else:
			player_pawn.heal(player_pawn.max_health)
		player_pawn.board(player_ship, cap_local)

	for i in crew_pawns.size():
		var cp := crew_pawns[i]
		if cp != null and is_instance_valid(cp) and cp.visible:
			if cp.station != null:
				cp.leave_station()
			var c_local := _crew_local_pos(player_ship, i)
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
			Game.post_notice("Line cast off the stern -- hold LMB to reel when it bites!")
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
	var cap_local := _captain_deck_pos(player_ship) if has_ship else Vector3.ZERO
	var respawn_pos := player_ship.global_transform * cap_local if has_ship else player_pawn.global_position
	player_pawn.revive(respawn_pos)
	if has_ship:
		player_pawn.board(player_ship, cap_local)
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
	_apply_inventory_tool_modifiers()
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
			_sync_cabin_renown(false)
			Game.post_notice("Launched your %s from the drydock!" % String(cls).capitalize())
			return
	_sync_cabin_renown(false)
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
	_sync_cabin_renown(false)
	_sync_ship_name()
	Net.register_replicated_ship(&"player_sloop", player_ship)
	player_ship.sunk.connect(_on_player_ship_sunk)
	player_ship.hull_impacted.connect(_on_player_ship_hull_impacted)
	_wire_ship_bell(player_ship)

	if player_pawn != null and is_instance_valid(player_pawn):
		if player_pawn.station != null:
			player_pawn.leave_station()
		if player_pawn.platform == old_ship:
			player_pawn.board(player_ship, _captain_deck_pos(player_ship))
	for i in crew_pawns.size():
		var cp := crew_pawns[i]
		if cp != null and is_instance_valid(cp):
			if cp.station != null:
				cp.leave_station()
			cp.board(player_ship, _crew_local_pos(player_ship, i))
		if i < crew_brains.size() and crew_brains[i] != null:
			crew_brains[i].bind_ship(player_ship)
	var swap_hs := _ship_scale_of(player_ship)
	for pid: int in _peer_pawns.keys():
		var pp: Pawn = _peer_pawns[pid]
		if pp != null and is_instance_valid(pp) and pp.platform == old_ship:
			if pp.station != null:
				pp.leave_station()
			pp.board(player_ship, _captain_deck_pos(player_ship) + Vector3(0.8 * swap_hs, 0.0, 0.0))

	if world_director != null:
		world_director.player_ship = player_ship
	if hud != null:
		hud.ship = player_ship
	if sea_soundscape != null and is_instance_valid(sea_soundscape):
		sea_soundscape.bind_ship(player_ship)
	_mount_player_rowboat(player_ship)
	_sync_emissary_visuals()
	if tutorial_director != null and is_instance_valid(tutorial_director):
		tutorial_director.bind(player_ship, player_pawn, inventory, map_table, player_rowboat)
	if inventory != null and is_instance_valid(inventory):
		inventory.map_table = map_table
	if shipwright_menu != null:
		shipwright_menu.ship = player_ship
		shipwright_menu.map_table = map_table
	ShipwrightMenu.apply_economy_to_ship(player_ship, Game.profile, crew_brains, world_director)
	_apply_inventory_tool_modifiers()
	old_ship.queue_free()


func _wire_ship_bell(target_ship: Ship) -> void:
	if target_ship == null or not is_instance_valid(target_ship):
		return
	if not target_ship.ship_bell_rung.is_connected(_on_player_ship_bell_rung):
		target_ship.ship_bell_rung.connect(_on_player_ship_bell_rung)


func _on_player_ship_bell_rung(_by_pawn: Node) -> void:
	if not Net.is_host():
		return
	for br in crew_brains:
		if br != null and is_instance_valid(br) and br.current_task == &"idle":
			br._speak(&"banter", {}, "bell_cheer", 10.0)
			return


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
	var local_spawn := Vector3(0.9 * float(offset_idx + 1) - 1.2, 1.12, 0.4) * _ship_scale_of(player_ship)
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
	Game.post_notice("Co-op crewmate departed -- AI crew resumed station.")


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
			cp.board(player_ship, _crew_local_pos(player_ship, idx))
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
	if (bool(intent.get("leave_station", false)) or bool(intent.get("interact", false))) and pp.station != null:
		pp.leave_station()
	elif pp.station != null and intent.has("station_axis"):
		var ax: Vector2 = intent["station_axis"] as Vector2 if intent["station_axis"] is Vector2 else Vector2.ZERO
		pp.drive_station(ax, bool(intent.get("primary", false)), bool(intent.get("secondary", false)), 1.0 / 60.0)
	elif bool(intent.get("interact", false)):
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
	var hs := _ship_scale_of(player_ship)
	var sc := (1.38 if is_brig else 1.0) * hs
	_shot_track_ship = false
	_shot_track_world_target = null
	_shot_track_world_blend = 0.0
	_shot_combat_timer = -1.0
	_shot_duel_spark_timer = -1.0
	_hero_coral_manta = null
	if hud != null:
		hud.input_enabled = false
		hud.clear_banners()
		var ch_hero := hud.find_child("Crosshair", true, false) as CanvasItem
		if ch_hero != null:
			ch_hero.visible = false
	if player_pawn != null:
		player_pawn.focus = null
	if player_controller != null:
		player_controller.focus_prompt = ""
	# Show the Captain's full 3D character mesh on external third-person hero cameras.
	var p_cv := _character_visual_of(player_pawn)
	if p_cv != null:
		var third_person := mode in [
			"outpost_dock", "sailing", "island_approach", "combat",
			"storm", "sunset", "night", "night_sail", "night_lighthouse", "rainbow", "whale_breach", "leviathan", "fleet",
			"company_fleet", "fort_siege", "fort_vault", "dolphins", "flotsam", "deck_duel",
			"harbour_plaza", "smugglers_grotto", "cinder_crag", "coral_reef", "fishing",
			"sovereigns_bastion", "galleons_reach", "emerald_waterfall", "archipelago_panorama",
			"skull_bluff", "cutlass_meadow", "gulls_arch", "wreckers_tooth"
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

		"dolphins":
			# Tight sunlit midday starboard-bow hero shot: gilded bowsprit, billowing sails & leaping DolphinPod!
			Weather.time_of_day = 12.6 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.04, 11.2, -0.38, 0.0, 0.32)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			_place_sailing_ship(Vector3(68.0, 0.0, -195.0), -0.38, 0.92, 6.2)
			var pod := _spawn_dolphin_pod(3, 60.0)
			if pod != null and pod.has_method(&"force_leap_phase"):
				pod.call(&"force_leap_phase", 1.25)
			_enable_ship_track_shot(Vector3(12.4 * sc, 3.2 * sc, -17.2 * sc), Vector3(2.8 * sc, 2.0 * sc, -6.8 * sc), 52.0)

		"rainbow":
			# Late-afternoon coastal sunbreak looking cleanly anti-solar past our sunlit ship into the 42-deg rainbow arch!
			Weather.time_of_day = 16.45 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.32, 11.4, -0.36, 0.0, 0.62)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.28)
			if sky_rig != null and sky_rig.get(&"rainbow_override") != null:
				sky_rig.set(&"rainbow_override", 0.92)
			var ship_yaw_rb := -0.25
			_place_sailing_ship(Vector3(42.0, 0.0, -215.0), ship_yaw_rb, 0.92, 5.8)
			var sun_d := Weather.sun_direction()
			var anti_h := Vector3(-sun_d.x, 0.0, -sun_d.z)
			anti_h = anti_h.normalized() if anti_h.length_squared() > 0.001 else Vector3(0.934, 0.0, -0.356)
			var anti_right := anti_h.cross(Vector3.UP).normalized()
			var rb_yaw_inv := Basis(Vector3.UP, ship_yaw_rb).inverse()
			var rb_cam_off := -anti_h * (27.5 * sc) + anti_right * (7.5 * sc) + Vector3(0.0, 4.4 * sc, 0.0)
			var rb_look_off := anti_h * (24.0 * sc) + anti_right * (7.5 * sc) + Vector3(0.0, 11.5 * sc, 0.0)
			_enable_ship_track_shot(rb_yaw_inv * rb_cam_off, rb_yaw_inv * rb_look_off, 60.0)

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

		"night_sail":
			# Moonlit midnight Sunken Archive sailing showcase framing warm cabin lanterns & nocturnal bioluminescent wake!
			Weather.time_of_day = 22.8 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.08, 12.2, -0.55, 0.0, 0.28)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.16)
			_place_sailing_ship(Vector3(64.0, 0.0, -210.0), -0.48, 0.90, 6.4)
			_apply_company_livery(
				player_ship,
				Color(0.92, 0.96, 0.94),
				Color(0.14, 0.84, 0.72),
				Color(0.16, 0.88, 0.74),
				Color(0.58, 0.94, 0.84),
				5
			)
			# Pre-seed trailing stern V-wake foam ribbons so the glowing nocturnal bioluminescence spans cleanly aft.
			if Ocean.current != null:
				for wi in 7:
					var frac := float(wi) / 6.0
					var aft_z := (6.5 + float(wi) * 4.2) * sc
					var spread_x := (1.4 + float(wi) * 0.95) * sc
					var str_val := lerpf(0.88, 0.34, frac)
					var rad_val := lerpf(2.8, 4.2, frac) * sc
					var wp_c := player_ship.global_transform * Vector3(0.0, 0.0, aft_z)
					var wp_l := player_ship.global_transform * Vector3(-spread_x, 0.0, aft_z)
					var wp_r := player_ship.global_transform * Vector3(spread_x, 0.0, aft_z)
					Ocean.current.add_foam(wp_c, rad_val, str_val * 0.85)
					Ocean.current.add_foam(wp_l, rad_val * 0.85, str_val)
					Ocean.current.add_foam(wp_r, rad_val * 0.85, str_val)
			_enable_ship_track_shot(Vector3(14.5 * sc, 5.8 * sc, 16.5 * sc), Vector3(0.0, 2.8, -1.5), 56.0)

		"helm":
			Weather.time_of_day = 10.6 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.06, 10.5, -0.37, 0.0, 0.36)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			_place_sailing_ship(Vector3(76.0, 0.0, -195.0), -0.37, 1.0, 6.0)
			var helm_eye := (Vector3(0.0, 3.95, 7.35) if is_brig else Vector3(0.0, 3.65, 5.75)) * hs
			var helm_look := (Vector3(0.0, 2.75, -24.0) if is_brig else Vector3(0.0, 2.55, -24.0)) * hs
			_enable_ship_track_shot(helm_eye, helm_look, 74.0)

		"map_table":
			Weather.time_of_day = 12.0 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.0, 6.0, 0.0, 0.0, 0.30)
			Sea.amp_scale = 0.0
			if map_table != null:
				map_table.refresh_now()
				var table_y := (MapTableView.BRIGANTINE_TABLE_TOP_Y if is_brig else MapTableView.SHIP_TABLE_TOP_Y) * hs
				var table_local := player_ship.to_local(map_table.global_position)
				var target_local := table_local + Vector3(0.0, table_y, -0.02 * hs)
				# Stand aft of the map table (clear of the forward companionway stairs) looking down at the chart.
				var cam_local := table_local + Vector3(0.0, table_y + 0.88 * hs, 0.72 * hs)
				_enable_ship_track_shot(cam_local, target_local, 50.0)

		"hold":
			Weather.time_of_day = 14.0 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.15, 9.0, 0.0, 0.0, 0.45)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.15)
			player_ship.water_level = 0.18
			if map_table != null:
				map_table.refresh_now()
			var cam_local_hold := (Vector3(1.15, 0.48, 0.45) if is_brig else Vector3(1.02, 0.34, -0.82)) * hs
			var look_local_hold := (Vector3(-0.10, -0.25, 4.20) if is_brig else Vector3(-0.08, -0.22, 2.55)) * hs
			_enable_ship_track_shot(cam_local_hold, look_local_hold, 66.0)

		"cabin":
			# Candlelit dusk Captain's Cabin interior showcase: MapTable, Brass Armillary Astrolabe,
			# Open Logbook, all 3 glowing Trading Company Renown Medallions, velvet curtains & stern windows!
			Weather.time_of_day = 18.6 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.05, 6.0, -0.35, 0.0, 0.35)
			Sea.amp_scale = 0.0
			player_ship.water_level = 0.0
			_sync_cabin_renown(true)
			if map_table != null:
				map_table.refresh_now()
			var cam_local_cabin := (Vector3(0.0, 0.62, 3.35) if is_brig else Vector3(-0.35, 0.58, 1.85)) * hs
			var look_local_cabin := (Vector3(0.0, -0.18, 6.25) if is_brig else Vector3(0.32, -0.18, 4.75)) * hs
			_enable_ship_track_shot(cam_local_cabin, look_local_cabin, 66.0)

		"flotsam":
			# Sunlit midday open-sea shipwreck salvage showcase: sculpted FlotsamClusters (planks, mast spar,
			# hemp netting, cork floats, barrel), driftwood chest, circling gulls & approaching ship under sail!
			Weather.time_of_day = 11.8 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.04, 10.2, -0.38, 0.0, 0.34)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			_place_sailing_ship(Vector3(68.0, 0.0, -198.0), -0.38, 0.94, 2.6)
			var flotsam_pos := player_ship.global_transform * Vector3(7.4 * sc, 0.0, -17.8 * sc)
			flotsam_pos.y = Sea.height(flotsam_pos.x, flotsam_pos.z)
			_on_director_spawn_flotsam(flotsam_pos, 3)
			var to_ship := player_ship.global_position - flotsam_pos
			to_ship.y = 0.0
			to_ship = to_ship.normalized() if to_ship.length_squared() > 0.01 else Vector3(-0.38, 0.0, 0.92)
			var cam_right := to_ship.cross(Vector3.UP).normalized()
			# Low-angle ocean hero camera: foreground-left sculpted flotsam + chest, gulls overhead, ship right-center!
			var cam_p := flotsam_pos - to_ship * 8.4 + cam_right * 3.5 + Vector3(0.0, 2.45, 0.0)
			var look_p := flotsam_pos + to_ship * (10.2 * sc) - cam_right * 0.45 + Vector3(0.0, 3.25, 0.0)
			_mount_shot_camera(cam_p, look_p, 56.0)

		"deck_duel":
			# Concept Art 3 homage: wide-open sun-drenched main deck sword-clash with Captain, Rival Corsair Captain,
			# charging Royal-Azure Barnaby, staggered Corsair Raider with StaggerStars, fiery clash sparks & warm clash glow!
			Weather.time_of_day = 15.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.08, 10.5, -0.36, 0.0, 0.42)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.18)
			_place_sailing_ship(Vector3(72.0, 0.0, -195.0), -0.36, 0.90, 4.6)
			_apply_company_livery(
				player_ship,
				Color(0.96, 0.93, 0.84),
				Color(0.18, 0.46, 0.90),
				Color.BLACK,
				Color(0.62, 0.78, 1.0),
				4
			)
			for br in crew_brains:
				if br != null and is_instance_valid(br):
					br.hold_fire = true
					br.set_physics_process(false)
			if hud != null:
				hud.set_boss_encounter("", 0.0, false)
				var ch_node := hud.find_child("Crosshair", true, false) as CanvasItem
				if ch_node != null:
					ch_node.visible = false

			var deck_y := (1.25 if is_brig else 1.10) * hs
			# Completely open flat solid planked waist AFT of the mainmast (zero mast, zero hatch, zero bell occlusion!).
			var cap_loc := Vector3(-0.68 * hs, deck_y, 1.68 * hs) if is_brig else Vector3(-0.66 * hs, deck_y, 1.15 * hs)
			var foe1_loc := Vector3(0.68 * hs, deck_y, 1.68 * hs) if is_brig else Vector3(0.66 * hs, deck_y, 1.15 * hs)
			var foe2_loc := Vector3(-1.45 * hs, deck_y, 0.05 * hs) if is_brig else Vector3(-1.25 * hs, deck_y, -0.35 * hs)
			var crew_loc := Vector3(1.68 * hs, deck_y, 0.25 * hs) if is_brig else Vector3(1.38 * hs, deck_y, -0.25 * hs)
			var clash_loc := Vector3(0.0, deck_y + 1.18, cap_loc.z)
			_shot_duel_clash_local = clash_loc

			# Captain on open solid waist facing starboard (+X) in active mid-slash (slash_2).
			if player_pawn != null:
				player_pawn.board(player_ship, cap_loc)
				var cap_to_foe := (player_ship.global_transform * foe1_loc) - (player_ship.global_transform * cap_loc)
				player_pawn.look_yaw = atan2(-cap_to_foe.x, -cap_to_foe.z)
				if inventory != null:
					inventory.equip(&"cutlass", true)
				if player_combat != null:
					player_combat._play_anim(&"slash_2", 4.0)

			# Rival Corsair Captain facing port (-X) in dramatic crossed-blade block/parry pose.
			var foe1 := _spawn_enemy_pawn(&"rival_captain", player_ship.global_transform * foe1_loc)
			if foe1 != null:
				foe1.board(player_ship, foe1_loc)
				var f1_to_cap := (player_ship.global_transform * cap_loc) - (player_ship.global_transform * foe1_loc)
				foe1.look_yaw = atan2(-f1_to_cap.x, -f1_to_cap.z)
				var f1_brain := foe1.get_node_or_null(^"EnemyBrain")
				if f1_brain != null:
					f1_brain.set_physics_process(false)
				var f1_cc := foe1.get_node_or_null(^"CombatComponent") as CombatComponent
				if f1_cc != null:
					f1_cc.equip_weapon(&"cutlass")
					f1_cc.set_blocking(true)
					f1_cc._play_anim(&"block", 4.0)

			# Barnaby (crew_pawns[0]) in Royal-Azure coat charging cleanly from starboard-fore!
			if not crew_pawns.is_empty() and crew_pawns[0] != null and is_instance_valid(crew_pawns[0]):
				var barnaby := crew_pawns[0]
				barnaby.board(player_ship, crew_loc)
				var b_to_foe := (player_ship.global_transform * foe1_loc) - (player_ship.global_transform * crew_loc)
				barnaby.look_yaw = atan2(-b_to_foe.x, -b_to_foe.z)
				var b_cv := _character_visual_of(barnaby)
				if b_cv != null:
					b_cv.set_tint(Color(0.14, 0.36, 0.78), Color(0.92, 0.74, 0.24))
				var b_cc := barnaby.get_node_or_null(^"CombatComponent") as CombatComponent
				if b_cc != null:
					b_cc.equip_weapon(&"cutlass")
					b_cc._play_anim(&"heavy", 4.0)

			# Staggered Corsair Raider cleanly visible in open port-fore corridor with spinning golden StaggerStars!
			var foe2 := _spawn_enemy_pawn(&"corsair_raider", player_ship.global_transform * foe2_loc)
			if foe2 != null:
				foe2.board(player_ship, foe2_loc)
				var f2_to_cap := (player_ship.global_transform * cap_loc) - (player_ship.global_transform * foe2_loc)
				foe2.look_yaw = atan2(-f2_to_cap.x, -f2_to_cap.z)
				var f2_cc := foe2.get_node_or_null(^"CombatComponent") as CombatComponent
				if f2_cc != null:
					f2_cc.apply_stagger(8.0)

			# Warm golden clash OmniLight3D casting fiery light onto both duelists' faces & coats!
			var clash_glow := OmniLight3D.new()
			clash_glow.name = "DuelClashGlow"
			clash_glow.position = clash_loc
			clash_glow.light_color = Color(1.0, 0.74, 0.32)
			clash_glow.light_energy = 2.4
			clash_glow.omni_range = 5.5
			clash_glow.shadow_enabled = false
			player_ship.add_child(clash_glow)

			# Fire dual fiery steel sparks + drifting CombatEmbers + golden slash crescent right at the crossed blades!
			var clash_world := player_ship.global_transform * clash_loc
			if player_combat != null:
				player_combat._spawn_clash_vfx(clash_world, &"parried")
				player_combat._spawn_clash_vfx(clash_world + Vector3(0.0, 0.14, 0.0), &"heavy")
				if player_combat.has_method(&"spawn_showcase_slash_arc"):
					player_combat.call(&"spawn_showcase_slash_arc", clash_world, player_ship.global_basis * Basis(Vector3.UP, 0.35), &"heavy", true)
			_shot_duel_spark_timer = 0.42

			# Zero-occlusion main-deck waist camera strictly IN FRONT of quarterdeck rail balusters (cam_z < rail_z - 0.40)!
			var cam_duel := Vector3(-0.62 * hs, deck_y + 1.56, 3.38 * hs) if is_brig else Vector3(-0.55 * hs, deck_y + 1.48, 2.55 * hs)
			var look_duel := Vector3(0.05 * hs, deck_y + 1.24, 0.92 * hs)
			_enable_ship_track_shot(cam_duel, look_duel, 58.0)

		"whale_breach":
			# Golden-hour sunset open-sea showcase: sailing Brigantine/Sloop left-foreground + monumental 14 m Humpback Whale
			# soaring in full-length broadside profile out of exploding spray curtain 21.5 m off the starboard bow!
			Weather.time_of_day = 17.55 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.08, 10.8, -0.38, 0.0, 0.38)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.22)
			_place_sailing_ship(Vector3(64.0, 0.0, -205.0), -0.38, 0.94, 5.2)
			var whale_pos := player_ship.global_transform * Vector3(11.5, 0.0, -19.5)
			whale_pos.y = Sea.height(whale_pos.x, whale_pos.z)
			var whale := _spawn_whale_breach(whale_pos, player_ship.rotation.y - 1.28)
			if whale != null and whale.has_method(&"force_breach_apex"):
				whale.call(&"force_breach_apex")
			_enable_ship_track_shot(Vector3(1.5 * sc, 4.0 * sc, 13.8 * sc), Vector3(6.2 * sc, 4.6 * sc, -10.0 * sc), 52.0)

		"night_lighthouse":
			# Panoramic moonlit Port Scoundrel harbour showcase: glowing Tavern, HarbourBunting, beach campfire,
			# moored Brigantine showing glowing stern windows & ShipNameplate, and sweeping golden LighthouseBeam!
			Weather.time_of_day = 22.8 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.06, 8.2, -0.37, 0.0, 0.26)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.10)
			if port != null:
				var dock_xf := port.global_transform * port.dock_local_transform
				# Moor Brigantine/Sloop cleanly in the glowing bay angled to showcase stern cabin glow & nameplate.
				var berth_w := dock_xf * Vector3(7.6, 0.0, -10.5)
				berth_w.y = Sea.height(berth_w.x, berth_w.z)
				player_ship.global_transform = Transform3D(Basis(Vector3.UP, port.dock_yaw + 2.38), berth_w)
				player_ship.set_anchor(true)
				player_ship.anchor_progress = 1.0
				player_ship.linear_velocity = Vector3.ZERO
				player_ship.angular_velocity = Vector3.ZERO
				_sync_ship_name()

				# Seaward panoramic camera looking straight across the moonlit bay toward Tavern, Pier, Ship & Lighthouse!
				var cam_w := dock_xf * Vector3(10.5, 11.8, -46.0)
				var look_w := dock_xf * Vector3(7.2, 11.4, 15.0)
				_mount_shot_camera(cam_w, look_w, 56.0)

				# Orient Port Scoundrel's dual volumetric LighthouseBeam diagonally across the starry harbour sky!
				if port.beacon_beam != null and is_instance_valid(port.beacon_beam) and port.beacon_node != null:
					var cam_fwd := (look_w - cam_w).normalized()
					var cam_r := cam_fwd.cross(Vector3.UP).normalized()
					var sweep_world := (cam_r * 0.86 - cam_fwd * 0.50).normalized()
					var sweep_local := port.beacon_node.global_basis.inverse() * sweep_world
					port.beacon_beam.rotation.y = atan2(sweep_local.x, sweep_local.z)
					port._update_beacon_beam(0.0)

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
			var fsc := (1.38 if is_brig else 1.24) * hs
			_enable_ship_track_shot(Vector3(-19.5 * fsc, 10.8 * fsc, 27.5 * fsc), Vector3(0.0, 3.8 * hs, -22.0), 62.0)

		"company_fleet":
			# 4-ship Trading Company armada parade echoing Concept Art 2 in sunlit turquoise swells near Cutlass Cay!
			Weather.time_of_day = 14.8 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.08, 12.5, -0.75, 0.0, 0.34)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			for br in crew_brains:
				if br != null and is_instance_valid(br):
					br.hold_fire = true
			var cc_pos := cutlass.global_position if cutlass != null else Vector3(165.0, 0.0, -415.0)
			var cam_dir_h := Vector3(0.996, 0.0, 0.087).normalized()
			var cam_right := cam_dir_h.cross(Vector3.UP).normalized()
			# Position fleet ~195 m west of Cutlass Cay so its limestone spires rise behind left-center.
			var fleet_c := cc_pos - cam_dir_h * 195.0 + cam_right * 48.0
			var parade_yaw := 1.05
			var parade_spd := 4.8

			# Center-stage flagship (player's Brigantine or current ship): Sunken Archive (emblem_mode = 5).
			var center_pos := fleet_c - cam_right * 0.5 - cam_dir_h * 5.0
			_place_sailing_ship(center_pos, parade_yaw, 0.92, parade_spd)
			_apply_company_livery(
				player_ship,
				Color(0.92, 0.96, 0.94),
				Color(0.14, 0.84, 0.72),
				Color(0.16, 0.88, 0.74),
				Color(0.58, 0.94, 0.84),
				5
			)

			# Left-center: Gilded Compass (emblem_mode = 4).
			var gc_ship := _spawn_parade_ship(&"sloop", fleet_c - cam_right * 19.0 + cam_dir_h * 5.5, parade_yaw, 0.92, parade_spd)
			_apply_company_livery(
				gc_ship,
				Color(0.96, 0.93, 0.84),
				Color(0.20, 0.48, 0.92),
				Color.BLACK,
				Color(0.62, 0.78, 1.0),
				4
			)

			# Right-center: Iron Tide (emblem_mode = 6).
			var it_ship := _spawn_parade_ship(&"brigantine", fleet_c + cam_right * 18.5 + cam_dir_h * 3.5, parade_yaw, 0.92, parade_spd)
			_apply_company_livery(
				it_ship,
				Color(0.96, 0.88, 0.86),
				Color(0.84, 0.16, 0.18),
				Color.BLACK,
				Color(1.0, 0.56, 0.48),
				6
			)

			# Far-right: Sovereign Sunburst (emblem_mode = 7).
			var sv_ship := _spawn_parade_ship(&"sloop", fleet_c + cam_right * 34.0 + cam_dir_h * 12.0, parade_yaw, 0.92, parade_spd)
			_apply_company_livery(
				sv_ship,
				Color(0.96, 0.90, 0.74),
				Color(0.95, 0.72, 0.24),
				Color(0.95, 0.68, 0.22),
				Color(0.42, 0.40, 0.44),
				7
			)

			# Sweeping low-waterline 3/4 bow hero camera tracking the armada (all 4 ships & streamers inside [-0.80, +0.76]).
			var yaw_inv := Basis(Vector3.UP, parade_yaw).inverse()
			var fleet_cam_w := fleet_c - cam_dir_h * 46.5 + cam_right * 4.0 + Vector3(0.0, 5.4, 0.0)
			var fleet_look_w := fleet_c + cam_right * 4.0 + Vector3(0.0, 8.2, 0.0)
			var ship_origin := player_ship.global_position
			_enable_ship_track_shot(
				yaw_inv * (fleet_cam_w - ship_origin),
				yaw_inv * (fleet_look_w - ship_origin),
				52.0
			)

		"fort_siege":
			# Ironwatch Fort Stone Bastion, blazing Signal Brazier, 4 coastal Sea-Battery Cannons
			# AND our approaching Brigantine under full sail framed heroically in one vista!
			Weather.time_of_day = 16.6 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.32, 13.5, -0.25, 0.0, 0.62)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.30)
			_suppress_shot_hud_overlays()
			var fort := archipelago.get_island_by_id("ironwatch_fort")
			if fort != null:
				_on_director_spawn_fort_siege(fort.global_position, "N")
				var fpos := fort.global_position
				var fr := fort.island_radius
				var bastion := fort.get_node_or_null(^"FortBastion") as Node3D
				var fort_focus := bastion.global_position if bastion != null else (fpos + Vector3(0.0, fort.peak_height * 0.45, 0.0))
				var sea_sw := Vector3(-0.66, 0.0, 0.75).normalized()
				var side_se := (-sea_sw).cross(Vector3.UP).normalized()
				# Place Brigantine cruising broadside-3/4 off the SW flank well clear of the shoreline.
				var s_pos := fpos + sea_sw * (fr + 34.0) - side_se * 18.0
				var to_fort := (fpos + side_se * 36.0) - s_pos
				to_fort.y = 0.0
				var yaw := atan2(-to_fort.x, -to_fort.z)
				_place_sailing_ship(s_pos, yaw, 0.88, 4.4)
				# Seaward abeam maritime camera framing both the blazing Fort Bastion and our Brigantine!
				var cam_p := fpos + sea_sw * (fr + 84.0) - side_se * 36.0 + Vector3(0.0, 20.5, 0.0)
				var look_p := fort_focus.lerp(s_pos + Vector3(0.0, 7.5, 0.0), 0.24) + Vector3(0.0, 4.0, 0.0)
				_mount_shot_camera(cam_p, look_p, 56.0)

		"fort_vault":
			# Tight golden-afternoon closeup into Ironwatch Fort's Bay 0 gateway framing the sculpted wrought-iron FortVault gate & Sovereign hoard!
			Weather.time_of_day = 16.4 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.10, 9.5, -0.35, 0.0, 0.36)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.12)
			var fort := archipelago.get_island_by_id("ironwatch_fort")
			if fort != null:
				_on_director_spawn_fort_siege(fort.global_position, "N")
				var bastion := fort.get_node_or_null(^"FortBastion") as Node3D
				if bastion != null:
					var b_xf := bastion.global_transform
					# Showcase gleaming Sovereign Chests & Archive Chalice right behind the barred vault gate bathed in VaultTreasuryGlow!
					var vault_hoard: Array[Array] = [
						[&"sovereign_chest", Vector3(0.05, 0.08, -8.35), 0.12],
						[&"sovereign_chest", Vector3(-0.78, 0.08, -9.10), -0.38],
						[&"archive_chalice", Vector3(0.76, 0.08, -8.90), 0.32],
					]
					for item_spec in vault_hoard:
						var tid: StringName = item_spec[0]
						var loc_p: Vector3 = item_spec[1] as Vector3
						var yaw_off: float = float(item_spec[2])
						var wp := b_xf * loc_p
						var loot := TreasureCatalog.create_treasure_carryable(tid, wp)
						loot.freeze = true
						_entities_root.add_child(loot)
						loot.global_position = wp
						loot.rotation.y = bastion.global_rotation.y + yaw_off
					# Keep spawned fort defenders inside the far courtyard so none block the gateway closeup.
					for ep in active_enemies:
						if ep != null and is_instance_valid(ep):
							var ep_loc := b_xf.affine_inverse() * ep.global_position
							if ep_loc.z < -6.0:
								ep.teleport(b_xf * Vector3(clampf(ep_loc.x, -4.5, 4.5), 0.15, 3.8))
					var cam_p := b_xf * Vector3(-1.35, 1.98, -18.1)
					cam_p.y = maxf(cam_p.y, fort.world_surface_height(cam_p) + 1.15)
					var look_p := b_xf * Vector3(0.15, 1.72, -10.2)
					_mount_shot_camera(cam_p, look_p, 52.0)
				else:
					_mount_shot_camera(fort.global_position + Vector3(-18.0, 22.0, 22.0), fort.global_position + Vector3(0.0, 18.0, 0.0), 52.0)

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
				var vr := volc.island_radius
				var vpk := volc.peak_height
				_place_sailing_ship(vp + Vector3(vr * 0.85, 0.0, vr * 1.10), 0.55, 0.88, 4.8)
				var cam_p := vp + Vector3(vr * 0.72, vpk * 1.18, vr * 0.96)
				var look_p := vp + Vector3(0.0, vpk * 0.68, 0.0)
				_mount_shot_camera(cam_p, look_p, 58.0)

		"coral_reef":
			# Crescent Atoll crystal turquoise underwater coral reef & swaying kelp garden!
			Weather.time_of_day = 12.4 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.02, 7.0, -0.25, 0.0, 0.28)
			Sea.amp_scale = Sea.AMP_CALM
			var atoll := archipelago.get_island_by_id("crescent_atoll")
			if atoll != null:
				var reef := atoll.get_node_or_null(^"CoralReef") as CoralReef
				var atmo := atoll.get_node_or_null(^"ReefAtmosphere") as ReefAtmosphere
				var target_w := atoll.global_position + Vector3(0.0, -3.2, -32.0)
				if reef != null:
					var pts := reef.get_placed_transforms()
					if not pts.is_empty():
						target_w = atoll.global_transform * pts[0].origin
				if atmo != null:
					atmo.tick_atmosphere(0.35, true)
				var dir_out := Vector3(target_w.x - atoll.global_position.x, 0.0, target_w.z - atoll.global_position.z)
				dir_out = dir_out.normalized() if dir_out.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
				var cam_p := target_w + dir_out * 6.5 + Vector3(0.0, 1.35, 0.0)
				cam_p.y = minf(cam_p.y, -1.15)
				var look_p := target_w + Vector3(0.0, 0.45, 0.0)
				_mount_shot_camera(cam_p, look_p, 66.0)

				# Pose Crescent Atoll's Giant Reef Manta Ray gliding gracefully through the sunlit upper-midground!
				var manta := atoll.get_node_or_null(^"MantaRay") as Node3D
				if manta == null and get_tree() != null:
					var best_d := INF
					for mn in get_tree().get_nodes_in_group(&"manta_rays"):
						if mn is Node3D and is_instance_valid(mn):
							var d_m := (mn as Node3D).global_position.distance_squared_to(atoll.global_position)
							if d_m < best_d:
								best_d = d_m
								manta = mn as Node3D
				if manta != null:
					manta.set_physics_process(false)
					var cam_fwd_h := Vector3(look_p.x - cam_p.x, 0.0, look_p.z - cam_p.z).normalized()
					var cam_r_h := cam_fwd_h.cross(Vector3.UP).normalized()
					var manta_w := cam_p + cam_fwd_h * 7.6 + cam_r_h * 0.65
					manta_w.y = -2.20
					manta.global_position = manta_w
					manta.rotation = Vector3.ZERO
					var glide_dir := (-cam_r_h * 0.88 + cam_fwd_h * 0.46).normalized()
					var g_root := manta.get_node_or_null(^"GlideRoot") as Node3D
					if g_root != null:
						g_root.position = Vector3.ZERO
						g_root.global_basis = Basis(Vector3.UP, atan2(-glide_dir.x, -glide_dir.z)) \
							* Basis(Vector3.RIGHT, 0.08) \
							* Basis(Vector3.FORWARD, -0.26)
						var lw := g_root.get_node_or_null(^"LeftWingPivot") as Node3D
						var rw := g_root.get_node_or_null(^"RightWingPivot") as Node3D
						if lw != null:
							lw.rotation.z = 0.24
						if rw != null:
							rw.rotation.z = -0.24
					_hero_coral_manta = manta
					_hero_coral_manta_anchor = manta_w
					_hero_coral_manta_dir = glide_dir

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
				var cam_local_galley := stove_local + Vector3(-0.68 * hs, 1.00, -1.04 * hs)
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
					player_pawn.board(player_ship, fishing_line.position + Vector3(0.18 * hs, 0.0, 0.10 * hs))
					player_pawn.look_yaw = atan2(-cast_world_dir.x, -cast_world_dir.z)
					_fishing_pawn = player_pawn
				# Hide any held weapon/tool meshes on the Captain's right hand so no stray cutlass clips the rail.
				if inventory != null:
					inventory.set_process(false)
					if inventory.tp_tool_node != null and is_instance_valid(inventory.tp_tool_node):
						inventory.tp_tool_node.visible = false
						for mi in inventory.tp_tool_node.find_children("*", "MeshInstance3D", true, false):
							(mi as Node3D).visible = false
					if inventory.fp_tool_node != null and is_instance_valid(inventory.fp_tool_node):
						inventory.fp_tool_node.visible = false
				if player_pawn != null:
					var f_cv := _character_visual_of(player_pawn)
					if f_cv != null and f_cv.hand_right != null:
						for h_child in f_cv.hand_right.get_children():
							if h_child is Node3D:
								(h_child as Node3D).visible = false
							for h_mi in h_child.find_children("*", "MeshInstance3D", true, false):
								(h_mi as Node3D).visible = false
				if player_combat != null:
					player_combat.equipped_weapon = &""
				fishing_line.cancel_cast()
				fishing_line.cast_line(fishing_line.global_position, cast_world_dir, 7.6)
				fishing_line.state = FishingLine.State.HOOKED
				fishing_line.hooked_species = FishingLine.SPECIES[2]
				fishing_line.fish_fighting = true
				fishing_line.line_tension = 0.80
				fishing_line.distance_out = 7.6
				fishing_line.step(0.016, fishing_line.global_position, false)
				# Port-outboard camera 1.8 m clear of hull, shrouds, backstay & balustrade posts!
				var cam_local_fish := fishing_line.position + Vector3(-2.07 * hs, 1.65, -0.77 * hs)
				var look_local_fish := fishing_line.position + Vector3(-0.75 * hs, 0.0, 4.15 * hs)
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

		"sovereigns_bastion":
			# Crisp golden-morning hero maritime vista: Brigantine cruising off Sovereign's Bastion
			# framing the massive 364 m multi-elevation citadel, outer seawall bastions, ruin arches,
			# cascading waterfall, jungle banyans & towering ridged cliffs!
			Weather.time_of_day = 9.4 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.0, 10.5, -0.35, 0.0, 0.32)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			_suppress_shot_hud_overlays()
			var citadel := archipelago.get_island_by_id("sovereigns_bastion")
			if citadel == null:
				citadel = archipelago.get_island_by_id("ironwatch_fort")
			if citadel != null:
				var cpos := citadel.global_position
				var r := citadel.island_radius
				var pk := citadel.peak_height
				var m_orig := citadel.mooring_transform.origin
				var sea_dir := Vector3(m_orig.x, 0.0, m_orig.z)
				sea_dir = sea_dir.normalized() if sea_dir.length_squared() > 0.01 else Vector3(-0.707, 0.0, 0.707)
				var view_right := (-sea_dir).cross(Vector3.UP).normalized()
				var moor_dist := Vector2(m_orig.x, m_orig.z).length()
				var offshore_base := maxf(r + 36.0, moor_dist + 18.0)

				# Position Brigantine cruising cleanly across the sunlit landing cove approach.
				var ship_pos := cpos + sea_dir * (offshore_base + 22.0) - view_right * maxf(18.0, r * 0.16)
				var ship_fwd := (cpos + view_right * (r * 0.22)) - ship_pos
				ship_fwd.y = 0.0
				ship_fwd = ship_fwd.normalized() if ship_fwd.length_squared() > 0.01 else -sea_dir
				var ship_yaw := atan2(-ship_fwd.x, -ship_fwd.z)
				_place_sailing_ship(ship_pos, ship_yaw, 0.92, 5.2)

				var cam_p := cpos + sea_dir * (offshore_base + maxf(54.0, r * 0.42)) \
					- view_right * maxf(30.0, r * 0.24) \
					+ Vector3(0.0, clampf(pk * 0.24, 14.0, 26.0), 0.0)
				var look_p := cpos + sea_dir * (r * 0.12) + view_right * (r * 0.04) \
					+ Vector3(0.0, pk * 0.38, 0.0)
				_mount_shot_camera(cam_p, look_p, 58.0)

		"galleons_reach":
			# Warm sunlit afternoon panoramic view of Galleon's Reach grand capital trade port:
			# harbour warehouse, stone seawalls, wooden lookout watchtower, bunting, tavern plaza,
			# beacon tower, and towering sculpted amphitheatre cliffs behind our moored Brigantine!
			Weather.time_of_day = 15.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.02, 8.5, -0.35, 0.0, 0.28)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.08)
			_suppress_shot_hud_overlays()
			var capital_isl := archipelago.get_island_by_id("galleons_reach")
			if capital_isl == null:
				capital_isl = port
			if capital_isl != null:
				var capital_op := capital_isl as Outpost
				var moor_xf := capital_isl.get_world_mooring_transform()
				moor_xf.origin.y = Sea.height(moor_xf.origin.x, moor_xf.origin.z)
				player_ship.global_transform = moor_xf
				player_ship.set_anchor(true)
				player_ship.anchor_progress = 1.0
				player_ship.set_sail_target(0.0)
				player_ship.sail_set = 0.0
				player_ship.linear_velocity = Vector3.ZERO
				player_ship.angular_velocity = Vector3.ZERO
				if player_pawn != null:
					player_pawn.board(player_ship, _captain_deck_pos(player_ship))
					player_pawn.look_yaw = player_ship.rotation.y
				for i in crew_pawns.size():
					if crew_pawns[i] != null:
						crew_pawns[i].board(player_ship, _crew_local_pos(player_ship, i))

				var scale_k := clampf(capital_isl.island_radius / 62.0, 1.0, 2.6)
				if capital_op != null:
					var dock_xf := capital_op.global_transform * capital_op.dock_local_transform
					var z_cam := -lerpf(48.0, 92.0, clampf((scale_k - 1.0) / 1.5, 0.0, 1.0))
					var cam_w := dock_xf * Vector3(18.0 * scale_k, clampf(14.5 * scale_k, 14.5, 28.0), z_cam)
					var look_w := dock_xf * Vector3(-2.0 * scale_k, clampf(capital_isl.peak_height * 0.28, 12.0, 28.0), 22.0 * scale_k)
					_mount_shot_camera(cam_w, look_w, 58.0)
				else:
					var m_orig := capital_isl.mooring_transform.origin
					var sea_dir := Vector3(m_orig.x, 0.0, m_orig.z)
					sea_dir = sea_dir.normalized() if sea_dir.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
					var view_right := (-sea_dir).cross(Vector3.UP).normalized()
					var cam_w := capital_isl.global_position + sea_dir * (capital_isl.island_radius + 54.0) \
						+ view_right * (18.0 * scale_k) + Vector3(0.0, clampf(14.5 * scale_k, 14.5, 28.0), 0.0)
					var look_w := capital_isl.global_position + Vector3(0.0, capital_isl.peak_height * 0.30, 0.0)
					_mount_shot_camera(cam_w, look_w, 58.0)

		"emerald_waterfall":
			# Lush sunlit tropical vista off Emerald Spire looking straight toward its dramatic
			# cascading IslandWaterfall, turquoise plunge pool, dense jungle banyan canopy, ancient
			# stone ruins, and towering sculpted twin massifs!
			Weather.time_of_day = 10.6 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.02, 8.0, -0.35, 0.0, 0.26)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.08)
			_suppress_shot_hud_overlays()
			var emerald := archipelago.get_island_by_id("emerald_spire")
			if emerald != null:
				var epos := emerald.global_position
				var er := emerald.island_radius
				var epk := emerald.peak_height
				var m_orig := emerald.mooring_transform.origin
				var sea_dir := Vector3(m_orig.x, 0.0, m_orig.z)
				sea_dir = sea_dir.normalized() if sea_dir.length_squared() > 0.01 else Vector3(0.988, 0.0, -0.150)

				var wf_node := emerald.get_node_or_null(^"IslandWaterfall") as Node3D
				if wf_node == null:
					var found_wf := emerald.find_children("*Waterfall*", "Node3D", true, false)
					if not found_wf.is_empty():
						wf_node = found_wf[0] as Node3D

				if wf_node != null:
					var wf_pos := wf_node.global_position
					var out_dir := -wf_node.global_basis.z
					out_dir.y = 0.0
					out_dir = out_dir.normalized() if out_dir.length_squared() > 0.001 else sea_dir
					var side_dir := (-out_dir).cross(Vector3.UP).normalized()
					var rb_node := wf_node.get_node_or_null(^"WaterfallMistRainbow") as Node3D
					var focus_p := rb_node.global_position if rb_node != null else (wf_pos + out_dir * 6.0 + Vector3(0.0, -7.0, 0.0))
					var cam_p := focus_p + out_dir * 16.5 - side_dir * 4.5 + Vector3(0.0, 3.8, 0.0)
					cam_p.y = maxf(cam_p.y, emerald.world_surface_height(cam_p) + 2.6)
					var look_p := focus_p.lerp(wf_pos, 0.25) + Vector3(0.0, 1.8, 0.0)
					_mount_shot_camera(cam_p, look_p, 60.0)
				else:
					var side_dir := (-sea_dir).cross(Vector3.UP).normalized()
					var cam_p := epos + sea_dir * (er + 42.0) + side_dir * 14.0 \
						+ Vector3(0.0, clampf(epk * 0.18, 11.0, 20.0), 0.0)
					var look_p := epos + Vector3(0.0, epk * 0.36, 0.0)
					_mount_shot_camera(cam_p, look_p, 56.0)

		"archipelago_panorama":
			# Elevated scenic aerial vista (y = 72 m above Port Scoundrel's seaward headland)
			# looking NNE across Port Scoundrel harbour, Cutlass Cay, Smuggler's Cove, and the
			# vast multi-scale archipelago horizon!
			Weather.time_of_day = 10.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.0, 8.5, -0.37, 0.0, 0.30)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.08)
			_suppress_shot_hud_overlays()
			var port_pos := port.global_position if port != null else Vector3.ZERO
			var cam_p := port_pos + Vector3(-58.0, 72.0, 96.0)
			if port != null:
				cam_p.y = maxf(cam_p.y, port.world_surface_height(cam_p) + 18.0)
			var look_p := port_pos + Vector3(240.0, 10.0, -340.0)
			_mount_shot_camera(cam_p, look_p, 62.0)

		"skull_bluff":
			# Dramatic maritime headland vista framing Skull Bluff's sea-facing cliff skull carving,
			# glowing cursed cavern eyes, flanking 3D cliff buttresses, and tropical meadow.
			Weather.time_of_day = 15.8 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.06, 8.5, -0.40, 0.0, 0.34)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			_suppress_shot_hud_overlays()
			var sb_isl := archipelago.get_island_by_id("skull_bluff")
			if sb_isl != null:
				var sb_pos := sb_isl.global_position
				var sb_r := sb_isl.island_radius
				var sb_pk := sb_isl.peak_height
				var sb_m := sb_isl.mooring_transform.origin
				var sb_sea := Vector3(sb_m.x, 0.0, sb_m.z)
				sb_sea = sb_sea.normalized() if sb_sea.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
				var sb_nodes := sb_isl.find_children("*SkullCliff*", "Node3D", true, false)
				if sb_nodes.is_empty():
					sb_nodes = sb_isl.find_children("*skull*", "Node3D", true, false)
				var sb_target := sb_pos + Vector3(0.0, sb_pk * 0.42, 0.0)
				var sb_out := sb_sea
				for sn in sb_nodes:
					var n3 := sn as Node3D
					if n3 != null and n3 != sb_isl:
						sb_target = n3.global_position + Vector3(0.0, 5.5, 0.0)
						# SkullCliffCarving faces local -Z; +Z is the rear cranium embedded in the bluff.
						var fwd := -n3.global_basis.z
						fwd.y = 0.0
						if fwd.length_squared() > 0.01:
							sb_out = fwd.normalized()
						break
				var sb_side := (-sb_out).cross(Vector3.UP).normalized()
				var sb_cam := sb_target + sb_out * maxf(48.0, sb_r * 0.44) + sb_side * 16.0 + Vector3(0.0, 8.5, 0.0)
				sb_cam.y = maxf(sb_cam.y, sb_isl.world_surface_height(sb_cam) + 5.0)
				_mount_shot_camera(sb_cam, sb_target, 54.0)

		"cutlass_meadow":
			# Low-to-mid beach & hillside vista on Cutlass Cay showcasing stochastic PBR golden sand,
			# winding dirt trail (1.0 - COLOR.a), 3D meadow ground cover, hibiscus shrubs & cliff buttresses.
			Weather.time_of_day = 10.4 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.0, 7.5, -0.35, 0.0, 0.25)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.08)
			_suppress_shot_hud_overlays()
			var cm_isl := archipelago.get_island_by_id("cutlass_cay")
			if cm_isl != null:
				var cm_pos := cm_isl.global_position
				var cm_r := cm_isl.island_radius
				var cm_pk := cm_isl.peak_height
				var cm_m := cm_isl.mooring_transform.origin
				var cm_sea := Vector3(cm_m.x, 0.0, cm_m.z)
				cm_sea = cm_sea.normalized() if cm_sea.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
				var cm_side := (-cm_sea).cross(Vector3.UP).normalized()
				var cm_cam := cm_pos + cm_sea * (cm_r * 0.88) + cm_side * (cm_r * 0.34)
				cm_cam.y = maxf(cm_isl.world_surface_height(cm_cam) + 5.2, 6.2)
				var cm_look := cm_pos - cm_sea * (cm_r * 0.08) + Vector3(0.0, clampf(cm_pk * 0.34, 6.5, 18.0), 0.0)
				_mount_shot_camera(cm_cam, cm_look, 58.0)

		"gulls_arch":
			# Maritime sailing approach framing Gull's Arch coastal sea arch with turquoise pass-through
			# water and craggy 3D cliff headlands.
			Weather.time_of_day = 11.2 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.0, 8.0, -0.38, 0.0, 0.28)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.10)
			_suppress_shot_hud_overlays()
			var ga_isl := archipelago.get_island_by_id("gulls_arch")
			if ga_isl != null:
				var ga_pos := ga_isl.global_position
				var ga_r := ga_isl.island_radius
				var ga_pk := ga_isl.peak_height
				var ga_m := ga_isl.mooring_transform.origin
				var ga_sea := Vector3(ga_m.x, 0.0, ga_m.z)
				ga_sea = ga_sea.normalized() if ga_sea.length_squared() > 0.01 else Vector3(-0.6, 0.0, 0.8)
				var ga_nodes := ga_isl.find_children("CoastalSeaArch_Main*", "Node3D", true, false)
				if ga_nodes.is_empty():
					ga_nodes = ga_isl.find_children("*arch*", "Node3D", true, false)
				var ga_target := ga_pos + Vector3(0.0, clampf(ga_pk * 0.28, 7.0, 16.0), 0.0)
				var ga_out := ga_sea
				for an in ga_nodes:
					var n3 := an as Node3D
					if n3 != null and n3 != ga_isl:
						ga_target = n3.global_position + Vector3(0.0, 4.5, 0.0)
						var fwd := n3.global_basis.z
						fwd.y = 0.0
						if fwd.length_squared() > 0.01:
							fwd = fwd.normalized()
							if fwd.dot(ga_sea) < 0.0:
								fwd = -fwd
							ga_out = fwd
						break
				var ga_side := (-ga_out).cross(Vector3.UP).normalized()
				var ga_cam := ga_target + ga_out * maxf(44.0, ga_r * 0.72) + ga_side * 14.0 + Vector3(0.0, 7.5, 0.0)
				ga_cam.y = maxf(ga_cam.y, ga_isl.world_surface_height(ga_cam) + 4.5)
				_mount_shot_camera(ga_cam, ga_target, 56.0)

		"wreckers_tooth":
			# Dramatic coastal vista framing Wrecker's Shoal's impaled galleon shipwreck prow wedged
			# high on jagged rock fangs amid foaming reef surf and tidal outcrops.
			Weather.time_of_day = 16.4 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.12, 9.5, -0.45, 0.0, 0.42)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.20)
			_suppress_shot_hud_overlays()
			var wt_isl := archipelago.get_island_by_id("wreckers_shoal")
			if wt_isl == null:
				wt_isl = archipelago.get_island_by_id("sirens_tooth")
			if wt_isl != null:
				var wt_pos := wt_isl.global_position
				var wt_r := wt_isl.island_radius
				var wt_pk := wt_isl.peak_height
				var wt_m := wt_isl.mooring_transform.origin
				var wt_sea := Vector3(wt_m.x, 0.0, wt_m.z)
				wt_sea = wt_sea.normalized() if wt_sea.length_squared() > 0.01 else Vector3(0.7, 0.0, 0.7)
				var wt_nodes := wt_isl.find_children("*ImpaledShipwreck*", "Node3D", true, false)
				if wt_nodes.is_empty():
					wt_nodes = wt_isl.find_children("*shipwreck*", "Node3D", true, false)
				if wt_nodes.is_empty():
					wt_nodes = wt_isl.find_children("*wreck*", "Node3D", true, false)
				var wt_target := wt_pos + Vector3(0.0, clampf(wt_pk * 0.30, 6.0, 14.0), 0.0)
				var wt_out := wt_sea
				for wn in wt_nodes:
					var n3 := wn as Node3D
					if n3 != null and n3 != wt_isl:
						wt_target = n3.global_position + Vector3(0.0, 3.8, 0.0)
						var rel := Vector3(n3.global_position.x - wt_pos.x, 0.0, n3.global_position.z - wt_pos.z)
						if rel.length_squared() > 1.0:
							wt_out = rel.normalized()
						break
				var wt_side := (-wt_out).cross(Vector3.UP).normalized()
				var wt_cam := wt_target + wt_out * maxf(40.0, wt_r * 0.68) + wt_side * 16.0 + Vector3(0.0, 6.5, 0.0)
				wt_cam.y = maxf(wt_cam.y, wt_isl.world_surface_height(wt_cam) + 4.5)
				_mount_shot_camera(wt_cam, wt_target, 55.0)

		"cinder_arch":
			# Wave I-3 Q16 hero shot: blazing molten lava river pouring through VolcanicObsidianArch_Portal
			# at the foot of 176 m Cinder Crag caldera under golden-hour sunset skies.
			Weather.time_of_day = 17.1 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.14, 10.0, -0.45, 0.0, 0.42)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.22)
			_suppress_shot_hud_overlays()
			var ca_isl := archipelago.get_island_by_id("cinder_crag")
			if ca_isl != null:
				var ca_pos := ca_isl.global_position
				var ca_m := ca_isl.mooring_transform.origin
				var ca_sea := Vector3(ca_m.x, 0.0, ca_m.z)
				ca_sea = ca_sea.normalized() if ca_sea.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
				var ca_arch := ca_isl.find_child("VolcanicObsidianArch*", true, false) as Node3D
				var ca_target := ca_pos + Vector3(0.0, 18.0, 0.0)
				var ca_fwd := ca_sea
				if ca_arch != null:
					ca_target = ca_arch.global_position + Vector3(0.0, 6.5, 0.0)
					var af := ca_arch.global_basis.z
					af.y = 0.0
					if af.length_squared() > 0.01:
						af = af.normalized()
						if af.dot(ca_sea) < 0.0:
							af = -af
						ca_fwd = af
				var ca_side := (-ca_fwd).cross(Vector3.UP).normalized()
				var ca_cam := ca_target + ca_fwd * 54.0 + ca_side * 14.0 + Vector3(0.0, 11.0, 0.0)
				ca_cam.y = maxf(ca_cam.y, ca_isl.world_surface_height(ca_cam) + 4.5)
				_mount_shot_camera(ca_cam, ca_target, 56.0)

		"smugglers_vault":
			# Wave I-3 Q16 hero shot: cove-mouth vista into Smuggler's Cove amphitheatre showing
			# triplanar PBR SmugglersGrotto cavern, PirateGibbet_Gate, CliffCatwalkPier_Cove & campfire.
			Weather.time_of_day = 16.0 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.06, 8.0, -0.38, 0.0, 0.30)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.14)
			_suppress_shot_hud_overlays()
			var sv_isl := archipelago.get_island_by_id("smugglers_cove")
			if sv_isl != null:
				var sv_pos := sv_isl.global_position
				var sv_r := sv_isl.island_radius
				var sv_m := sv_isl.mooring_transform.origin
				var sv_sea := Vector3(sv_m.x, 0.0, sv_m.z)
				sv_sea = sv_sea.normalized() if sv_sea.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
				var sv_grotto := sv_isl.find_child("SmugglersGrotto*", true, false) as Node3D
				var sv_target := sv_grotto.global_position + Vector3(0.0, 4.5, 0.0) if sv_grotto != null else (sv_pos + Vector3(0.0, 7.0, 0.0))
				var sv_side := (-sv_sea).cross(Vector3.UP).normalized()
				var sv_cam := sv_pos + sv_sea * (sv_r * 0.96) + sv_side * 10.0 + Vector3(0.0, 10.5, 0.0)
				sv_cam.y = maxf(sv_cam.y, sv_isl.world_surface_height(sv_cam) + 4.5)
				_mount_shot_camera(sv_cam, sv_target, 58.0)

		"skull_cloud":
			# Wave 30B horizon sky beacon hero shot: Brigantine sailing toward Sovereign's Bastion
			# crowned by a colossal blazing emerald-eyed Fort Skull Cloud hovering at y=175 m!
			Weather.time_of_day = 17.55 if is_nan(_cli_time) else _cli_time
			Weather.set_weather(0.24, 11.5, -0.42, 0.0, 0.48)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.24)
			_suppress_shot_hud_overlays()
			var sc_fort := archipelago.get_island_by_id("sovereigns_bastion")
			if sc_fort == null:
				sc_fort = archipelago.get_island_by_id("ironwatch_fort")
			if sc_fort != null and world_director != null:
				var sc_fpos := sc_fort.global_position
				var sc_cloud: Node = world_director.spawn_event_cloud(&"fort_siege", sc_fpos, true)
				if sc_cloud != null and sc_cloud.has_method(&"trigger_lightning_flash"):
					sc_cloud.call(&"trigger_lightning_flash", 1.0)
				var sc_dir := Vector3(-0.62, 0.0, 0.78).normalized()
				var sc_side := (-sc_dir).cross(Vector3.UP).normalized()
				var sc_ship_pos := sc_fpos + sc_dir * 420.0 + sc_side * 34.0
				var sc_to := sc_fpos - sc_ship_pos
				sc_to.y = 0.0
				_place_sailing_ship(sc_ship_pos, atan2(-sc_to.x, -sc_to.z), 1.0, 6.2)
				var sc_cam := sc_ship_pos + sc_dir * 42.0 - sc_side * 24.0 + Vector3(0.0, 14.5, 0.0)
				sc_cam.y = maxf(sc_cam.y, Sea.height(sc_cam.x, sc_cam.z) + 12.0)
				var sc_look := sc_fpos + Vector3(0.0, 128.0, 0.0)
				_mount_shot_camera(sc_cam, sc_look, 58.0)

		"title_menu":
			# Wave 32 / Q11B first-launch live-3D Title Menu hero shot: left-anchored parchment Title Menu
			# with unobstructed moored Brigantine, Port Scoundrel lighthouse & shimmering ocean on the right!
			Weather.time_of_day = 10.2
			Weather.set_weather(0.06, 9.0, -0.35, 0.0, 0.36)
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.06)
			_suppress_shot_hud_overlays()
			if title_menu != null:
				title_menu.config.mode = SessionConfig.MODE_ADVENTURE
				title_menu.config.ship_class = player_ship.ship_class if player_ship != null else &"brigantine"
				title_menu.config.spawn_outpost_id = &"port_scoundrel"
				title_menu.config.time_preset = &"morning"
				title_menu.config.weather_preset = &"fair"
				_enter_title_menu(TitleMenu.Page.LANDING)
				var shot_vista := _cli_vista
				if shot_vista == &"night":
					shot_vista = &"twilight"
				if shot_vista != &"":
					title_menu.select_harbour_vista(shot_vista)
				if not is_nan(_cli_time):
					Weather.time_of_day = _cli_time
				if not is_nan(_cli_storm) or not is_nan(_cli_cloud):
					var st_ov := Weather.storminess if is_nan(_cli_storm) else _cli_storm
					var cl_ov := Weather.cloudiness if is_nan(_cli_cloud) else _cli_cloud
					Weather.set_weather(st_ov, lerpf(9.0, 18.5, st_ov), -0.35, 0.0, cl_ov)
					Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, st_ov)
				_title_orbit_time = 0.0
				_update_title_camera()
			elif not is_nan(_cli_time):
				Weather.time_of_day = _cli_time

		"play_setup":
			# Wave 32 Pre-Sail Configurator hero shot: sunset harbour + Brigantine with raised Emissary Flag
			# visible live beside the Setup configurator panel!
			_suppress_shot_hud_overlays()
			if title_menu != null:
				title_menu.select_mode(SessionConfig.MODE_ADVENTURE)
				title_menu.select_ship_class(&"brigantine")
				title_menu.select_spawn_outpost(&"port_scoundrel")
				title_menu.select_time_preset(&"sunset")
				title_menu.select_weather_preset(&"fair")
				title_menu.select_starting_emissary(&"gilded_compass")
				_enter_title_menu(TitleMenu.Page.SETUP)
				_title_orbit_time = 1.6
				_update_title_camera()


func _suppress_shot_hud_overlays() -> void:
	if hud != null:
		hud.set_boss_encounter("", 0.0, false)
		var ch_node := hud.find_child("Crosshair", true, false) as CanvasItem
		if ch_node != null:
			ch_node.visible = false
		var prompt_node := hud.find_child("PromptHolder", true, false) as CanvasItem
		if prompt_node != null:
			prompt_node.visible = false
	if player_pawn != null:
		player_pawn.focus = null
	if player_controller != null:
		player_controller.focus_prompt = ""


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
	if active_shot_mode != "" and _shot_camera != null:
		if player_pawn != null:
			player_pawn.focus = null
		if player_controller != null:
			player_controller.focus_prompt = ""
	if active_shot_mode == "deck_duel" and player_ship != null and is_instance_valid(player_ship):
		_shot_duel_spark_timer -= delta
		if _shot_duel_spark_timer <= 0.0:
			_shot_duel_spark_timer = 0.42
			if player_combat != null:
				var cw := player_ship.global_transform * _shot_duel_clash_local
				player_combat._spawn_clash_vfx(cw, &"parried")
				player_combat._spawn_clash_vfx(cw + Vector3(0.0, 0.14, 0.0), &"heavy")
				if player_combat.has_method(&"spawn_showcase_slash_arc"):
					player_combat.call(&"spawn_showcase_slash_arc", cw, player_ship.global_basis * Basis(Vector3.UP, 0.35), &"heavy", true)
	elif active_shot_mode == "coral_reef" and _hero_coral_manta != null and is_instance_valid(_hero_coral_manta):
		var t_m := float(Time.get_ticks_msec()) * 0.001
		var flap := sin(t_m * 2.15) * 0.30
		var heave := -cos(t_m * 2.15) * 0.14
		var surge := sin(t_m * 0.55) * 0.85
		_hero_coral_manta.global_position = _hero_coral_manta_anchor + _hero_coral_manta_dir * surge + Vector3(0.0, heave, 0.0)
		var g_root := _hero_coral_manta.get_node_or_null(^"GlideRoot") as Node3D
		if g_root != null:
			var lw := g_root.get_node_or_null(^"LeftWingPivot") as Node3D
			var rw := g_root.get_node_or_null(^"RightWingPivot") as Node3D
			if lw != null:
				lw.rotation.z = flap
			if rw != null:
				rw.rotation.z = -flap
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
	for i in crew_pawns.size():
		if crew_pawns[i] != null:
			crew_pawns[i].board(player_ship, _crew_local_pos(player_ship, i))


func _spawn_parade_ship(cls: StringName, pos_xz: Vector3, yaw_rad: float, sail_val: float, fwd_speed: float) -> Ship:
	var ship_scene := _resolve_ship_scene(cls)
	var vessel := ship_scene.instantiate() as Ship
	vessel.name = "ParadeShip_%s" % String(cls).capitalize()
	vessel.faction = &"player"
	vessel.enable_effects = true
	vessel.start_anchored = false
	_entities_root.add_child(vessel)
	var sy := Sea.height(pos_xz.x, pos_xz.z)
	var b := Basis(Vector3.UP, yaw_rad)
	vessel.global_transform = Transform3D(b, Vector3(pos_xz.x, sy, pos_xz.z))
	vessel.set_anchor(false)
	vessel.anchor_progress = 0.0
	vessel.set_sail_target(sail_val)
	vessel.sail_set = sail_val
	var ideal_trim := vessel.ideal_sail_trim()
	vessel.set_trim_target(ideal_trim)
	vessel.sail_trim = ideal_trim
	vessel.linear_velocity = -b.z * fwd_speed
	vessel.angular_velocity = Vector3.ZERO
	return vessel


static func _apply_company_livery(
	vessel: Ship,
	sail_tint: Color,
	flag_tint: Color,
	glow_accent: Color,
	hull_tint: Color,
	emblem_mode: int
) -> void:
	if vessel == null or not is_instance_valid(vessel):
		return
	var supports_emblem := false
	for m: Dictionary in vessel.get_method_list():
		if String(m.get("name", "")) == "apply_livery":
			var args: Array = m.get("args", [])
			supports_emblem = args.size() >= 5
			break
	if supports_emblem:
		vessel.call(&"apply_livery", sail_tint, flag_tint, glow_accent, hull_tint, emblem_mode)
	else:
		vessel.apply_livery(sail_tint, flag_tint, glow_accent, hull_tint)


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


# ==============================================================================
# Wave 32 -- First-Launch Title Menu, Live Preview, Maiden Voyage & Naval Skirmish
# ==============================================================================

func _enter_title_menu(page: TitleMenu.Page = TitleMenu.Page.LANDING) -> void:
	_title_mode_active = true
	if shipwright_menu != null and shipwright_menu.is_open:
		shipwright_menu.close_menu()
	if hud != null:
		hud.set_pause_open(false)
		hud.clear_mode_objective()
		hud.set_hud_visible(false)
	if player_controller != null:
		player_controller.input_enabled = false
		player_controller.capture_mouse = false
		player_controller.set_look_paused(true)
	if inventory != null:
		inventory.input_enabled = false
	if world_director != null:
		world_director.enabled = false
	if _title_camera == null or not is_instance_valid(_title_camera):
		_title_camera = Camera3D.new()
		_title_camera.name = "TitleMenuCamera"
		_title_camera.fov = 56.0
		_title_camera.near = 0.1
		_title_camera.far = 6000.0
		add_child(_title_camera)
	_title_camera.make_current()
	_update_title_camera()
	if title_menu != null:
		title_menu.refresh_profile_summary()
		title_menu.open_menu(page)


func _exit_title_menu() -> void:
	_title_mode_active = false
	if title_menu != null and title_menu.is_open:
		title_menu.close_menu()
	if _title_camera != null and is_instance_valid(_title_camera):
		_title_camera.current = false
	if player_controller != null:
		if player_controller.camera != null:
			player_controller.camera.make_current()
		player_controller.input_enabled = (active_shot_mode == "")
		player_controller.capture_mouse = (active_shot_mode == "")
		player_controller.set_look_paused(false)
		if active_shot_mode == "" and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if inventory != null:
		inventory.input_enabled = (active_shot_mode == "")
	if hud != null:
		hud.set_hud_visible(true)
		hud.input_enabled = (active_shot_mode == "")


func _tick_title_camera(delta: float) -> void:
	if not _title_mode_active or _title_camera == null or not is_instance_valid(_title_camera):
		return
	_title_orbit_time += delta
	_update_title_camera()


func _update_title_camera() -> void:
	if _title_camera == null or not is_instance_valid(_title_camera):
		return
	if player_ship == null or not is_instance_valid(player_ship):
		return
	var hs := _ship_scale_of(player_ship)
	var is_brig := (player_ship.ship_class == &"brigantine")
	var sc := (1.24 if is_brig else 1.0) * hs
	var ship_pos := player_ship.global_position
	var ship_yaw := Basis(Vector3.UP, player_ship.global_rotation.y)
	# Gentle seaward quarter-bow orbit framing the full moored vessel (hull, masts, stern Emissary flag,
	# golden dusk lanterns) and Port Scoundrel harbourfront cleanly on the right 60% of the screen!
	var ang := 0.76 + sin(_title_orbit_time * 0.14) * 0.18
	var eye := ship_pos + ship_yaw * Vector3(sin(ang) * 27.5 * sc, 6.4 * sc, -cos(ang) * 27.5 * sc)
	eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 3.4)
	var to_ship := ship_pos - eye
	to_ship.y = 0.0
	var cam_fwd := to_ship.normalized() if to_ship.length_squared() > 0.001 else Vector3.FORWARD
	var cam_right := cam_fwd.cross(Vector3.UP).normalized()
	# Shift look point left of the ship so vessel & harbour skyline frame cleanly beside the menu!
	var look := ship_pos + Vector3(0.0, 3.6 * sc, 0.0) - cam_right * (6.8 * sc)
	_title_camera.look_at_from_position(eye, look, Vector3.UP)


func _apply_crew_roster_count(desired_count: int) -> void:
	var target := clampi(desired_count, 0, crew_pawns.size())
	for idx in crew_pawns.size():
		var cp := crew_pawns[idx]
		var br := crew_brains[idx] if idx < crew_brains.size() else null
		var yielded_to_peer := _peer_yielded_crew.values().has(idx)
		var should_active := (idx < target) and not yielded_to_peer
		if should_active:
			if cp != null and is_instance_valid(cp):
				cp.visible = true
				cp.collision_layer = Pawn.LAYER_PAWN
				cp.set_physics_process(true)
				if player_ship != null and is_instance_valid(player_ship) and cp.platform != player_ship:
					cp.board(player_ship, _crew_local_pos(player_ship, idx))
			if br != null and is_instance_valid(br):
				br.set_physics_process(true)
		else:
			if br != null and is_instance_valid(br):
				br.yield_to_human_player()
			if cp != null and is_instance_valid(cp):
				cp.visible = false
				cp.set_physics_process(false)
				cp.collision_layer = 0


func _apply_session_preview(cfg: SessionConfig, apply_emissary_preview: bool = true) -> void:
	if cfg == null:
		return
	cfg.validate()
	# 1. Ship class swap live in the harbour.
	if Net.is_host() and player_ship != null and is_instance_valid(player_ship) and player_ship.ship_class != cfg.ship_class:
		_swap_player_ship_class(cfg.ship_class)
	# 2. Spawn outpost mooring relocation.
	if Net.is_host() and cfg.spawn_outpost_id != _current_spawn_outpost_id:
		_current_spawn_outpost_id = cfg.spawn_outpost_id
		_restore_player_ship_at_outpost(cfg.spawn_outpost_id)
		var op := archipelago.get_island_by_id(String(cfg.spawn_outpost_id))
		if op != null and world_director != null:
			world_director.set_last_outpost(cfg.spawn_outpost_id, op.global_position)
		if Game != null and Game.profile != null:
			Game.profile.discover(String(cfg.spawn_outpost_id))
	# 3. Custom ship name live on stern nameplate.
	if player_ship != null and is_instance_valid(player_ship) and player_ship.has_method(&"set_ship_name"):
		player_ship.call(&"set_ship_name", cfg.ship_name)
	# 4. Crew roster count (0..3) live on deck.
	_apply_crew_roster_count(cfg.crew_count)
	# 5. Live sky time of day & weather.
	if Net.is_host():
		Weather.time_of_day = cfg.get_time_of_day()
		var wp := cfg.get_weather_params()
		var st := float(wp.get("storm", 0.06))
		Weather.set_weather(st, float(wp.get("wind", 9.0)), -0.35, 0.0, float(wp.get("cloud", 0.36)))
		Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, st)
	# 6. Stern Emissary flag preview.
	if apply_emissary_preview and player_ship != null and is_instance_valid(player_ship):
		var eflag := ShipEmissaryFlag.mount_to_ship(player_ship)
		if eflag != null:
			var prev_grade := 1 if cfg.starting_emissary != &"" else 0
			eflag.set_emissary(cfg.starting_emissary, prev_grade)
	_update_title_camera()


func _on_title_preview_changed(cfg: SessionConfig) -> void:
	_apply_session_preview(cfg, true)


func _on_title_start_game(cfg: SessionConfig) -> void:
	if cfg == null:
		return
	var launch := cfg.duplicate_config()
	launch.validate()
	active_session_config = launch

	# Persist ship class & vessel name in Captain Profile.
	if Game != null and Game.profile != null:
		Game.profile.set_ship_name(launch.ship_name)
		Game.profile.data["ship_class"] = String(launch.ship_class)
		Game.save()

	# Handle Co-op Host / Join networking before dropping onto deck.
	if launch.mode == SessionConfig.MODE_COOP:
		if launch.coop_role == &"host":
			var herr := Net.host(launch.coop_port)
			if herr != OK:
				if title_menu != null:
					title_menu.set_status_message("Failed to host on port %d (%s)." % [launch.coop_port, error_string(herr)])
				return
		else:
			var jerr := Net.join(launch.coop_address, launch.coop_port)
			if jerr != OK:
				if title_menu != null:
					title_menu.set_status_message("Could not join %s:%d (%s)." % [launch.coop_address, launch.coop_port, error_string(jerr)])
				return
	elif not Net.is_host():
		Net.disconnect_session()

	# Stop any prior special modes & clear prior skirmish vessels cleanly.
	_stop_active_special_modes()
	_apply_session_preview(launch, false)
	_exit_title_menu()

	if not Net.is_host():
		if hud != null:
			hud.show_voyage_title("CO-OP CREW", "Joining %s:%d..." % [launch.coop_address, launch.coop_port], 3.8)
		return

	# Sync real Trading Company Emissary Flag state cleanly.
	if voyage_manager != null and voyage_manager.emissary != null:
		if launch.starting_emissary != &"" and launch.mode != SessionConfig.MODE_TUTORIAL:
			voyage_manager.emissary.raise_flag(launch.starting_emissary)
		elif voyage_manager.emissary.is_active():
			voyage_manager.emissary.active_company = &""
			voyage_manager.emissary.grade = 0
			voyage_manager.emissary.xp = 0.0
	_sync_emissary_visuals()

	match launch.mode:
		SessionConfig.MODE_TUTORIAL:
			_start_maiden_voyage_mode()
		SessionConfig.MODE_SKIRMISH:
			_start_naval_skirmish_mode(launch)
		_:
			_start_adventure_mode(launch)


func _start_adventure_mode(cfg: SessionConfig) -> void:
	if world_director != null:
		world_director.enabled = true
	if hud != null:
		hud.clear_mode_objective()
	var map_data := archipelago.get_map_data()
	if voyage_manager != null:
		voyage_manager.refresh_offers(map_data, 3, cfg.spawn_outpost_id)
		if not voyage_manager.has_active_voyage():
			voyage_manager.start_starter_voyage(map_data)
		if voyage_manager.has_active_voyage():
			_prepare_active_voyage_world(voyage_manager.active_voyage)
	if map_table != null:
		map_table.refresh_now()
	var op_name := String(cfg.get_outpost_spec().get("name", "Port Scoundrel"))
	var subtitle := "%s - Open-Seas Adventure" % op_name
	if cfg.mode == SessionConfig.MODE_COOP:
		subtitle = "%s - Hosting Co-op on Port %d" % [op_name, cfg.coop_port]
	if hud != null:
		hud.show_voyage_title("SEA OF SCOUNDRELS", subtitle, 4.4)


func _start_maiden_voyage_mode() -> void:
	if world_director != null:
		world_director.enabled = false
	_current_spawn_outpost_id = &"port_scoundrel"
	_restore_player_ship_at_outpost(&"port_scoundrel")
	var map_data := archipelago.get_map_data()
	if voyage_manager != null:
		voyage_manager.refresh_offers(map_data, 3, &"port_scoundrel")
		if not voyage_manager.has_active_voyage():
			voyage_manager.start_starter_voyage(map_data)
		if voyage_manager.has_active_voyage():
			_prepare_active_voyage_world(voyage_manager.active_voyage)
	var cutlass := archipelago.get_island_by_id("cutlass_cay")
	var cutlass_pos := cutlass.global_position if cutlass != null else Vector3(0.0, 0.0, -520.0)
	if tutorial_director != null:
		tutorial_director.bind(player_ship, player_pawn, inventory, map_table, player_rowboat)
		tutorial_director.start_tutorial(cutlass_pos, "Cutlass Cay")
	if hud != null:
		hud.show_voyage_title("MAIDEN VOYAGE", "Guided Pirate Tutorial - Port Scoundrel", 4.2)


func _start_naval_skirmish_mode(cfg: SessionConfig) -> void:
	if world_director != null:
		world_director.enabled = false
	# Launch directly into wide open combat waters far from any reef or island!
	var arena_xz := Vector3(-240.0, 0.0, -280.0)
	_place_sailing_ship(arena_xz, 0.35, 0.65, 5.2)
	if player_ship != null and is_instance_valid(player_ship):
		player_ship.cannonballs_remaining = Ship.MAX_CANNONBALLS
		player_ship.planks_remaining = Ship.MAX_PLANKS
		player_ship.water_level = 0.0
	var scales := cfg.get_difficulty_scales()
	if skirmish_director != null:
		skirmish_director.start_skirmish(
			float(scales.get("enemy_scale", 1.0)),
			float(scales.get("payout_scale", 1.0)),
			1.5
		)
	if hud != null:
		hud.show_voyage_title("NAVAL SKIRMISH", "All Hands to Battle Stations!", 3.8)


func _stop_active_special_modes() -> void:
	if tutorial_director != null and tutorial_director.active:
		tutorial_director.stop_tutorial()
	if skirmish_director != null and skirmish_director.state != SkirmishDirector.State.IDLE:
		skirmish_director.stop_skirmish()
	for foe_node in _skirmish_enemies:
		if foe_node != null and is_instance_valid(foe_node):
			foe_node.queue_free()
	_skirmish_enemies.clear()
	if hud != null:
		hud.clear_mode_objective()


func _on_hud_return_to_title() -> void:
	_stop_active_special_modes()
	if Net.is_host():
		_restore_player_ship_at_outpost(_current_spawn_outpost_id)
	_enter_title_menu(TitleMenu.Page.LANDING)


func _on_hud_mode_skip() -> void:
	if tutorial_director != null and tutorial_director.active:
		tutorial_director.skip_current_step()


func _on_title_quit_requested() -> void:
	if Game != null:
		Game.save()
	if DisplayServer.get_name() != "headless":
		get_tree().quit()


func _speak_crew_mode_line(event_key: StringName) -> void:
	for idx in crew_brains.size():
		var br := crew_brains[idx]
		var cp := crew_pawns[idx] if idx < crew_pawns.size() else null
		if br != null and is_instance_valid(br) and cp != null and is_instance_valid(cp) and cp.visible:
			var line := CrewDialogue.format_line(br.persona_id, event_key)
			if line != "":
				var pname := String(CrewDialogue.get_persona(br.persona_id).get("name", "Barnaby"))
				Game.post_notice("%s: %s" % [pname, line])
				return


func _on_tutorial_step_changed(_idx: int, _step_id: StringName, title: String, hint: String, progress_text: String) -> void:
	if hud != null:
		hud.set_mode_objective(title, hint, progress_text, true)


func _on_tutorial_step_completed(_idx: int, _step_id: StringName) -> void:
	_speak_crew_mode_line(&"tutorial_step")


func _on_tutorial_completed(bonus_gold: int, bonus_renown: int) -> void:
	if world_director != null:
		world_director.enabled = true
	if hud != null:
		hud.clear_mode_objective()
		hud.show_voyage_title("MAIDEN VOYAGE COMPLETE!", "+%d Gold & +%d Renown - The Archipelago Awaits!" % [bonus_gold, bonus_renown], 5.0)
	if player_ship != null and is_instance_valid(player_ship):
		_launch_victory_flare(player_ship.global_position + Vector3(0.0, 3.8, 0.0), Color(1.0, 0.86, 0.28))
	Game.save()


func _on_tutorial_skipped() -> void:
	if world_director != null:
		world_director.enabled = true
	if hud != null:
		hud.clear_mode_objective()
	Game.post_notice("Tutorial skipped - sailing freely in Open-Seas Adventure!")


func _on_skirmish_wave_started(wave_num: int, wave_title: String, banner_text: String, _enemy_count: int) -> void:
	if hud != null:
		hud.show_voyage_title("WAVE %d - %s" % [wave_num, wave_title.to_upper()], banner_text, 4.0)
	_speak_crew_mode_line(&"skirmish_wave")


func _on_skirmish_spawn_ship(archetype: StringName, relative_offset: Vector3) -> void:
	if not Net.is_host() or player_ship == null or not is_instance_valid(player_ship):
		return
	var spawn_pos := player_ship.global_position + relative_offset
	spawn_pos.y = Sea.height(spawn_pos.x, spawn_pos.z)
	var foe := _spawn_enemy_vessel(archetype, spawn_pos)
	if foe != null:
		_skirmish_enemies.append(foe)
		foe.sunk.connect(func() -> void:
			if skirmish_director != null and skirmish_director.state == SkirmishDirector.State.COMBAT:
				skirmish_director.notify_enemy_defeated(&"ship")
		, CONNECT_ONE_SHOT)


func _on_skirmish_spawn_leviathan(relative_offset: Vector3) -> void:
	if not Net.is_host() or player_ship == null or not is_instance_valid(player_ship):
		return
	var spawn_pos := player_ship.global_position + relative_offset
	var lev := Leviathan.new()
	lev.target_ship = player_ship
	lev.position = Vector3(spawn_pos.x, 0.0, spawn_pos.z)
	_entities_root.add_child(lev)
	lev.global_position = Vector3(spawn_pos.x, 0.0, spawn_pos.z)
	lev.leviathan_defeated.connect(func(pos: Vector3, _salvage: Array) -> void:
		_launch_victory_flare(Vector3(pos.x, Sea.height(pos.x, pos.z) + 2.5, pos.z), Color(0.24, 0.94, 0.88))
		if skirmish_director != null and skirmish_director.state == SkirmishDirector.State.COMBAT:
			skirmish_director.notify_enemy_defeated(&"leviathan")
	, CONNECT_ONE_SHOT)
	active_leviathans.append(lev)
	_skirmish_enemies.append(lev)


func _on_skirmish_restock(cannonballs: int, planks: int) -> void:
	if player_ship != null and is_instance_valid(player_ship):
		SkirmishDirector.apply_ship_restock(player_ship, cannonballs, planks)


func _on_skirmish_objective_updated(title: String, detail: String, progress: String) -> void:
	if hud != null:
		hud.set_mode_objective(title, detail, progress, false)


func _on_skirmish_victory(total_gold: int, total_kills: int, total_score: int) -> void:
	if hud != null:
		hud.show_voyage_title(
			"SKIRMISH VICTORY!",
			"%d Hostiles Sunk  |  +%d Gold  |  Score %d" % [total_kills, total_gold, total_score],
			5.5
		)
	_speak_crew_mode_line(&"skirmish_victory")
	if player_ship != null and is_instance_valid(player_ship):
		_launch_victory_flare(player_ship.global_position + Vector3(0.0, 4.0, 0.0), Color(1.0, 0.84, 0.28))
	Game.save()
