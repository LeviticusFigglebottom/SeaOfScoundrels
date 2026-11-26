extends Node3D
## Items, Map Table & Parchment HUD showcase.
##
##   tools/capture.sh res://scenes/showcase/items_showcase.tscn items_tools 3 8 -- shot=tools
##   tools/capture.sh res://scenes/showcase/items_showcase.tscn items_map 3 8 -- shot=map_table
##   tools/capture.sh res://scenes/showcase/items_showcase.tscn items_hud 3 8 -- shot=hud
##
## User args (after `--`):
##   shot=tools|map_table|hud       (default tools)
##   wheel=item|crew|none           (for shot=hud, default item)
##   item=compass|map|lantern|...   (held FP tool for shot=hud, default compass)

const SKY_RIG: PackedScene = preload("res://src/sky/sky_rig.tscn")
const OCEAN_SCENE: PackedScene = preload("res://src/ocean/ocean.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

var _shot: String = "tools"
var _wheel_mode: String = "item"
var _fp_item: StringName = &"compass"

var _cam: Camera3D = null
var _ship: Ship = null
var _map_view: MapTableView = null
var _hud: GameHUD = null
var _inventory: Inventory = null
var _display_compass: Node3D = null
var _display_instrument: Node3D = null
var _clock: float = 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			_shot = a.trim_prefix("shot=")
		elif a.begins_with("wheel="):
			_wheel_mode = a.trim_prefix("wheel=")
		elif a.begins_with("item="):
			_fp_item = StringName(a.trim_prefix("item="))

	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.time_of_day = 15.8 if _shot == "tools" else 11.2
	Weather.set_weather(0.10, 9.5, 0.45, 0.0, 0.36)
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.08)
	Sea.time = 14.0

	var sky := SKY_RIG.instantiate()
	add_child(sky)
	add_child(OCEAN_SCENE.instantiate())

	match _shot:
		"map_table":
			_setup_map_table_shot()
		"hud":
			_setup_hud_shot(sky)
		_:
			_setup_tools_table_shot()


func _setup_tools_table_shot() -> void:
	# Elevated oak pirate workbench overlooking the sparkling sunlit sea.
	var bench := Node3D.new()
	bench.name = "ToolBench"
	bench.position = Vector3(0.0, 2.2, 0.0)
	add_child(bench)

	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Solid tabletop (top flush at y = 0.0) & four heavy oak legs.
	ToolMeshes._append_beveled_box(st_wood, Vector3(3.15, 0.12, 1.25), 0.02, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, 0.0)))
	for sx in [-1.35, 1.35]:
		for sz in [-0.46, 0.46]:
			ToolMeshes._append_beveled_box(st_wood, Vector3(0.14, 1.10, 0.14), 0.015, Transform3D(Basis.IDENTITY, Vector3(sx, -0.62, sz)))
	# Rear oak display rack (uprights, leaning crossbar, front cleat & cutlass cradle pegs) resting flush on y = 0.0.
	ToolMeshes._append_beveled_box(st_wood, Vector3(0.07, 0.40, 0.07), 0.008, Transform3D(Basis.IDENTITY, Vector3(-1.38, 0.20, -0.46)))
	ToolMeshes._append_beveled_box(st_wood, Vector3(0.07, 0.40, 0.07), 0.008, Transform3D(Basis.IDENTITY, Vector3(0.94, 0.20, -0.46)))
	ToolMeshes._append_beveled_box(st_wood, Vector3(2.40, 0.055, 0.055), 0.008, Transform3D(Basis.IDENTITY, Vector3(-0.22, 0.32, -0.46)))
	ToolMeshes._append_beveled_box(st_wood, Vector3(2.36, 0.022, 0.032), 0.005, Transform3D(Basis.IDENTITY, Vector3(-0.22, 0.011, -0.18)))
	# Two notched timber pegs cradling the cutlass cleanly above the tabletop.
	ToolMeshes._append_beveled_box(st_wood, Vector3(0.045, 0.095, 0.065), 0.006, Transform3D(Basis.IDENTITY, Vector3(-1.24, 0.0475, -0.26)))
	ToolMeshes._append_beveled_box(st_wood, Vector3(0.045, 0.140, 0.065), 0.006, Transform3D(Basis.IDENTITY, Vector3(-0.86, 0.070, -0.26)))
	st_wood.generate_normals()
	var table_mi := MeshInstance3D.new()
	table_mi.mesh = st_wood.commit()
	table_mi.material_override = ToolMeshes._make_mat(ToolMeshes.COL_OAK_DARK, 0.78, 0.04)
	bench.add_child(table_mi)

	# Warm fill lamp illuminating the brass & steel facets nicely.
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.6, 1.25, 1.1)
	fill.light_color = Color(1.0, 0.88, 0.70)
	fill.light_energy = 1.6
	fill.omni_range = 8.0
	bench.add_child(fill)

	# Place all 11 procedural 3D tools grounded on the oak bench & rear display rack!
	var layout: Array[Array] = [
		# Back row (resting flush on y = 0.0 & leaning against the oak display rail; cutlass on twin pegs)
		[&"cutlass", Vector3(-1.26, 0.112, -0.26), Vector3(-14.0, 8.0, -82.0), 0.98],
		[&"shovel", Vector3(-0.38, 0.528, -0.484), Vector3(158.0, 10.0, 0.0), 0.78],
		[&"map", Vector3(0.14, 0.177, -0.359), Vector3(-18.0, 0.0, 0.0), 1.06],
		[&"planks", Vector3(0.68, 0.156, -0.338), Vector3(-18.0, -8.0, 3.0), 0.94],
		[&"lantern", Vector3(1.20, 0.352, -0.24), Vector3(0.0, -24.0, 0.0), 1.02],
		# Front row (grounded flush on tabletop; spyglass & bucket separated by ~14 cm clear air gap)
		[&"pistol", Vector3(-1.18, 0.029, 0.26), Vector3(0.0, -55.0, 88.0), 1.12],
		[&"compass", Vector3(-0.76, 0.032, 0.28), Vector3(0.0, 18.0, 0.0), 1.32],
		[&"spyglass", Vector3(-0.34, 0.043, 0.34), Vector3(0.0, -76.0, 0.0), 1.02],
		[&"bucket", Vector3(0.46, 0.348, 0.24), Vector3(0.0, 15.0, 0.0), 0.98],
		[&"tankard", Vector3(0.85, 0.121, 0.28), Vector3(0.0, -35.0, 0.0), 1.12],
		[&"instrument", Vector3(1.24, 0.112, 0.26), Vector3(0.0, -22.0, 0.0), 1.08],
	]

	for spec in layout:
		var tid: StringName = spec[0]
		var node := ToolMeshes.build_tool(tid)
		node.position = spec[1]
		node.rotation_degrees = spec[2]
		node.scale = Vector3.ONE * float(spec[3])
		bench.add_child(node)
		if tid == &"bucket":
			ToolMeshes.set_bucket_full(node, true)
		elif tid == &"lantern":
			ToolMeshes.set_lantern_lit(node, true)
		elif tid == &"spyglass":
			ToolMeshes.set_spyglass_extension(node, 0.55)
		elif tid == &"map":
			var tex := MapPainter.render_treasure_map("Cutlass Cay", PackedVector2Array(), Vector2(28.0, -16.0), 120.0)
			ToolMeshes.apply_map_texture(node, tex)
		elif tid == &"compass":
			_display_compass = node
		elif tid == &"instrument":
			_display_instrument = node

	_cam = Camera3D.new()
	_cam.fov = 52.0
	_cam.near = 0.05
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _setup_map_table_shot() -> void:
	_ship = SLOOP_SCENE.instantiate() as Ship
	_ship.start_anchored = true
	add_child(_ship)
	_ship.global_position = Vector3(0.0, Sea.height(0.0, 0.0), 0.0)
	_ship.rotation_degrees.y = -24.0

	# Discover several islands so both named and undiscovered silhouettes show on the chart!
	if Game != null and Game.profile != null:
		Game.profile.discover("cutlass_cay")
		Game.profile.discover("gull_roost")
		Game.profile.discover("ironwatch_fort")
		Game.profile.discover("coral_spire")

	# Place a live storm cell out to the northwest for the cyclone swirl on the chart.
	Weather.set_storm_cell(Vector3(-420.0, 0.0, -980.0), 340.0, 0.85, 0.0)

	_map_view = MapTableView.new()
	_map_view.name = "MapTableView"
	_map_view.mount_to_ship(_ship)
	_map_view.view_center = Vector2(40.0, -680.0)
	_map_view.view_span = 2600.0
	_map_view.set_voyage_target(Vector3(420.0, 0.0, -680.0))
	_map_view.salvage_wrecks.append(Vector3(-210.0, 0.0, -390.0))
	_map_view.place_marker(Vector3(140.0, 0.0, -480.0))
	_map_view.refresh_now()

	_cam = Camera3D.new()
	_cam.fov = 48.0
	_cam.near = 0.05
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _setup_hud_shot(sky: Node) -> void:
	_ship = SLOOP_SCENE.instantiate() as Ship
	add_child(_ship)
	_ship.global_position = Vector3(0.0, Sea.height(0.0, 0.0), 0.0)
	_ship.set_sail_target(1.0)
	_ship.sail_set = 1.0
	_ship.set_trim_target(-0.35)
	_ship.sail_trim = -0.35

	var captain := PAWN_SCENE.instantiate() as Pawn
	add_child(captain)
	captain.board(_ship, Vector3(-0.35, 2.02, 4.9))
	captain.look_yaw = 0.12
	captain.look_pitch = -0.06
	captain.health = 78.0

	var pc := PlayerController.new()
	pc.input_enabled = false
	pc.capture_mouse = false
	pc.make_current = true
	captain.add_child(pc)
	pc.focus_prompt = "Take the helm"

	var cc := CombatComponent.new()
	cc.stamina = 64.0
	captain.add_child(cc)

	var vis := captain.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
	if vis != null:
		vis.set_first_person_hidden(true)

	_inventory = Inventory.new()
	_inventory.input_enabled = false
	captain.add_child(_inventory)
	_inventory.bind(captain, pc, cc, vis)
	_inventory.set_treasure_map("Cutlass Cay", PackedVector2Array(), Vector2(28.0, -18.0), 120.0)
	_inventory.equip(_fp_item, true)
	if _fp_item == &"compass" or _fp_item == &"map":
		_inventory.set_secondary_held(true)

	if Game != null and Game.profile != null:
		Game.profile.data["gold"] = 420

	_hud = GameHUD.new()
	_hud.input_enabled = false
	_hud.force_show_vitals = true
	_hud.force_show_whisper = true
	add_child(_hud)
	_hud.bind(captain, pc, _inventory, cc, _ship, null, sky)
	_hud.set_voyage_whisper("The Salt-King's Ledger", "Sail NE to Cutlass Cay and unearth the hoard", 12.0)
	Game.post_notice("Maren: Land ho! Cutlass Cay off the starboard bow!")

	if _wheel_mode == "item":
		_hud.open_item_radial()
		_hud.item_radial.set_hover_index(2, false)
	elif _wheel_mode == "crew":
		_hud.open_command_wheel()
		_hud.command_wheel.set_hover_index(1, false)


func _process(delta: float) -> void:
	_clock += delta
	if _display_compass != null:
		var needle := _display_compass.get_node_or_null(^"Needle") as Node3D
		if needle != null:
			needle.rotation.y = sin(_clock * 1.6) * 0.35
	if _display_instrument != null:
		ToolMeshes.set_concertina_stretch(_display_instrument, 0.5 + 0.38 * sin(_clock * 3.2))
	if _cam != null:
		_update_camera()


func _update_camera() -> void:
	if _shot == "map_table" and _ship != null:
		var xf := _ship.global_transform
		var table_top := xf * Vector3(0.0, 0.025, 2.5)
		var sway_x := sin(_clock * 0.7) * 0.16
		var eye := xf * Vector3(sway_x, 0.92, 3.22)
		_cam.look_at_from_position(eye, table_top, Vector3.UP)
	elif _shot == "tools":
		var pan_x := sin(_clock * 0.55) * 0.65
		var eye := Vector3(pan_x, 3.35, 2.15)
		var target := Vector3(pan_x * 0.55, 2.38, -0.02)
		_cam.look_at_from_position(eye, target, Vector3.UP)
