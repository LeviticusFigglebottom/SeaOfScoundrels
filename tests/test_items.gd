extends TestCase
## Headless tests for src/items/ and src/ui/: ToolMeshes, MapPainter, Inventory,
## MapTableView, RadialWheel, HudIcons, and GameHUD.

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")


class MockArchipelago:
	extends Node
	var islands_data: Array[Dictionary] = []

	func get_map_data() -> Array[Dictionary]:
		return islands_data


class MockSkyRig:
	extends Node
	var cloud_quality: int = 1
	var sky_material: ShaderMaterial = ShaderMaterial.new()


var _root: Node3D = null
var _saved_weather: Dictionary = {}
var _saved_amp: float = 1.0


func _begin() -> void:
	_saved_weather = Weather.get_state()
	_saved_amp = Sea.amp_scale
	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.set_weather(0.0, 8.0, 0.0)
	Weather.clear_storm_cell(0.0)
	Sea.amp_scale = 0.0
	_root = Node3D.new()
	add_child(_root)


func _end() -> void:
	Audio.stop_shanty(0.01)
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
		_root = null
	await physics_frames(2)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp


static func _ship_scale(s: Ship) -> float:
	if s != null and is_instance_valid(s):
		var hs: Variant = s.get(&"hull_scale")
		if hs != null and float(hs) > 0.01:
			return float(hs)
	return 1.0


func _make_player_pawn(pos: Vector3 = Vector3.ZERO) -> Dictionary:
	var p := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(p)
	p.global_position = pos
	var pc := PlayerController.new()
	pc.input_enabled = false
	pc.capture_mouse = false
	pc.make_current = false
	p.add_child(pc)
	var cc := CombatComponent.new()
	p.add_child(cc)
	var inv := Inventory.new()
	inv.input_enabled = false
	p.add_child(inv)
	return {"pawn": p, "pc": pc, "combat": cc, "inv": inv}


# ---------------------------------------------------------------------------
# 1. All 11 ToolMeshes build cleanly with non-empty surfaces & named subnodes
# ---------------------------------------------------------------------------

func test_all_eleven_tool_meshes_build_cleanly() -> void:
	var ids := ToolMeshes.get_tool_ids()
	check_eq(ids.size(), 11, "expected 11 canonical held tools")

	for tid in ids:
		var node := ToolMeshes.build_tool(tid)
		check(node != null, "ToolMeshes.build_tool(%s) returned node" % tid)
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 1, "tool %s must have at least 1 MeshInstance3D" % tid)
		var total_faces := 0
		for m_node in meshes:
			var mi := m_node as MeshInstance3D
			check(mi.mesh != null, "tool %s mesh '%s' non-null" % [tid, mi.name])
			if mi.mesh != null:
				check(mi.mesh.get_surface_count() > 0, "tool %s mesh '%s' has surfaces" % [tid, mi.name])
				total_faces += mi.mesh.get_faces().size()
		check(total_faces >= 18, "tool %s should have rich non-empty geometry (got %d verts)" % [tid, total_faces])

		match tid:
			&"compass":
				check(node.get_node_or_null(^"Needle") != null, "compass has live Needle child")
			&"spyglass":
				check(node.get_node_or_null(^"DrawTubes") != null, "spyglass has DrawTubes child")
				ToolMeshes.set_spyglass_extension(node, 1.0)
				check((node.get_node(^"DrawTubes") as Node3D).position.z < -0.1, "spyglass draw tubes extend")
			&"lantern":
				var light := node.get_node_or_null(^"LanternLight") as OmniLight3D
				check(light != null, "lantern has real OmniLight3D")
				check(light.visible and light.light_energy > 0.5, "lantern starts lit")
				ToolMeshes.set_lantern_lit(node, false)
				check(not light.visible and light.light_energy == 0.0, "lantern snuffs cleanly")
				ToolMeshes.set_lantern_lit(node, true)
				check(light.visible and light.light_energy > 0.5, "lantern relights cleanly")
			&"map":
				var surf := node.get_node_or_null(^"MapSurface") as MeshInstance3D
				check(surf != null, "map has MapSurface child")
				var mat := surf.material_override as StandardMaterial3D if surf != null else null
				check(mat != null and mat.albedo_texture != null, "map has initial ImageTexture")
			&"bucket":
				var wf := node.get_node_or_null(^"WaterFill") as Node3D
				check(wf != null and not wf.visible, "bucket WaterFill starts hidden")
				ToolMeshes.set_bucket_full(node, true)
				check(wf != null and wf.visible, "bucket WaterFill visible when full")
			&"tankard":
				check(node.get_node_or_null(^"FoamTop") != null, "tankard has FoamTop")
			&"instrument":
				var bellows := node.get_node_or_null(^"Bellows") as Node3D
				check(bellows != null, "concertina has Bellows")
				ToolMeshes.set_concertina_stretch(node, 1.0)
				check(bellows.scale.x > 1.2, "concertina bellows expand cleanly")
		node.free()


# ---------------------------------------------------------------------------
# 2. Inventory cycling, compass needle, spyglass FOV, lantern, treasure map
# ---------------------------------------------------------------------------

func test_inventory_equip_compass_spyglass_lantern_and_map() -> void:
	_begin()
	var rig := _make_player_pawn(Vector3(0.0, 2.0, 0.0))
	var pawn: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	await physics_frames(2)

	# Equip & cycle through all 11 slots cleanly.
	var seen: Array[StringName] = []
	for _i in 11:
		seen.append(inv.active_item)
		inv.next_item()
	check_eq(seen.size(), 11, "cycled through all 11 tools")
	check_eq(inv.active_item, seen[0], "next_item wraps cleanly back to start")

	# Equipping cutlass & pistol updates CombatComponent.
	inv.equip(&"pistol", true)
	check_eq(cc.equipped_weapon, &"pistol", "equipping pistol syncs CombatComponent")
	inv.equip(&"cutlass", true)
	check_eq(cc.equipped_weapon, &"cutlass", "equipping cutlass syncs CombatComponent")

	# Compass needle rotates with pawn yaw to point true North (-Z).
	inv.equip(&"compass", true)
	pawn.look_yaw = 0.0
	for _i in 30:
		await get_tree().process_frame
	var compass_node := inv.get_active_tool_node()
	var needle := compass_node.get_node_or_null(^"Needle") as Node3D
	check(needle != null, "equipped compass has Needle node")
	var yaw_north := needle.rotation.y

	# Turn 90 degrees right (facing East -> look_yaw = -PI/2); true North is now left (+PI/2).
	pawn.look_yaw = -PI * 0.5
	for _i in 45:
		await get_tree().process_frame
	var yaw_east := needle.rotation.y
	var diff_rad := absf(wrapf(yaw_east - yaw_north, -PI, PI))
	check(diff_rad > 1.0, "compass needle rotates cleanly when pawn turns (delta=%.2f rad)" % diff_rad)

	# Spyglass smoothly zooms camera FOV and detects a distant ship under crosshair.
	var distant_ship := SLOOP_SCENE.instantiate() as Ship
	distant_ship.enable_effects = false
	distant_ship.faction = &"drowned"
	_root.add_child(distant_ship)
	distant_ship.global_position = Vector3(120.0, 0.0, 0.0)
	pawn.look_yaw = -PI * 0.5  # look straight East (+X) at the ship
	pawn.look_pitch = 0.0

	var zoom_signals: Array[int] = [0]
	inv.spyglass_zoom_changed.connect(func(_z: float) -> void: zoom_signals[0] += 1)
	inv.equip(&"spyglass", true)
	var fov_before := pc.camera.fov
	inv.set_secondary_held(true)
	for _i in 35:
		await get_tree().process_frame
	check(zoom_signals[0] > 0, "spyglass emits spyglass_zoom_changed")
	check(inv.spyglass_zoom > 0.75, "spyglass zoom reaches high level (got %.2f)" % inv.spyglass_zoom)
	check(pc.camera.fov < fov_before - 35.0, "spyglass narrows camera FOV (%.1f -> %.1f)" % [fov_before, pc.camera.fov])
	check(inv.spyglass_sighting != "", "spyglass detects distant ship under crosshair (got '%s')" % inv.spyglass_sighting)

	inv.set_secondary_held(false)
	for _i in 45:
		await get_tree().process_frame
	check(pc.camera.fov > 72.0, "releasing spyglass restores wide FOV (got %.1f)" % pc.camera.fov)

	# Lantern toggles flame & OmniLight3D cleanly.
	inv.equip(&"lantern", true)
	var toggled_vals: Array[bool] = []
	inv.lantern_toggled.connect(func(on: bool) -> void: toggled_vals.append(on))
	check(inv.lantern_lit, "lantern starts lit")
	inv.use_primary()
	check(not inv.lantern_lit, "lantern turns off on primary")
	var lan_light := inv.get_active_tool_node().get_node_or_null(^"LanternLight") as OmniLight3D
	check(lan_light != null and not lan_light.visible, "lantern OmniLight3D hides when snuffed")
	inv._use_cooldown = 0.0
	inv.use_primary()
	check(inv.lantern_lit and lan_light.visible, "lantern relights cleanly")
	check_eq(toggled_vals.size(), 2, "lantern_toggled emitted twice")

	# Held Treasure Map renders a rich non-blank parchment texture with island & red X.
	inv.equip(&"map", true)
	var contour := PackedVector2Array([
		Vector2(-60, -50), Vector2(55, -60), Vector2(75, 10),
		Vector2(40, 70), Vector2(-50, 60), Vector2(-75, 5),
	])
	var map_tex := inv.set_treasure_map("Skull Cove", contour, Vector2(22.0, -14.0), 100.0)
	check(map_tex != null, "set_treasure_map returns ImageTexture")
	var img := map_tex.get_image()
	check(img != null and img.get_width() >= 128 and img.get_height() >= 128, "map texture has valid dimensions")
	var has_crimson := false
	var has_land := false
	var has_parchment := false
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.r > 0.62 and c.g < 0.25 and c.b < 0.25:
				has_crimson = true
			if c.g > c.b + 0.12 and c.r > 0.50 and c.r < 0.80:
				has_land = true
			if c.r > 0.82 and c.g > 0.72 and c.b > 0.54:
				has_parchment = true
	check(has_parchment, "treasure map contains warm parchment background")
	check(has_land, "treasure map contains island contour fill")
	check(has_crimson, "treasure map contains bold crimson X marker")
	await _end()


# ---------------------------------------------------------------------------
# 3. Shovel dig, Bucket bail, Planks patch, Tankard grog, Concertina shanty
# ---------------------------------------------------------------------------

func test_tools_shovel_bucket_planks_tankard_and_instrument() -> void:
	_begin()
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(8)

	var rig := _make_player_pawn(Vector3.ZERO)
	var pawn: Pawn = rig["pawn"]
	var inv: Inventory = rig["inv"]

	# Shovel digs a real DigSite in 3 strikes and unearths a Carryable chest.
	var site := DigSite.new()
	site.treasure_id = &"wayfarer_chest"
	_root.add_child(site)
	site.global_position = Vector3(20.0, 0.0, 20.0)
	pawn.teleport(Vector3(18.6, 0.0, 20.0))
	pawn.look_yaw = -PI * 0.5
	inv.equip(&"shovel", true)

	for step in 3:
		inv._use_cooldown = 0.0
		var res: Dictionary = inv.use_primary()
		check(bool(res.get("hit", false)), "shovel dig #%d hits nearby DigSite" % (step + 1))
	check(site.is_unearthed and site.spawned_chest != null, "3 shovel digs unearth a Carryable treasure chest")

	# Board the real Ship and test Bucket bailing & splashing.
	var hs := _ship_scale(ship)
	pawn.board(ship, Vector3(0.0, -0.82, 0.2) * hs)
	await physics_frames(3)
	ship.water_level = 0.45
	inv.equip(&"bucket", true)
	inv._use_cooldown = 0.0
	var bail_res: Dictionary = inv.use_primary()
	check_eq(bail_res.get("action"), &"bail", "bucket bails flooded ship hold")
	check(ship.water_level < 0.35, "ship water_level dropped after bucket bail (got %.2f)" % ship.water_level)
	check(inv.bucket_full, "bucket becomes full after bailing")
	var wf := inv.get_active_tool_node().get_node_or_null(^"WaterFill") as Node3D
	check(wf != null and wf.visible, "bucket WaterFill visible when carrying bailed water")

	# Second primary splashes water out and empties bucket.
	inv._use_cooldown = 0.0
	var splash_res: Dictionary = inv.use_primary()
	check_eq(splash_res.get("action"), &"splash", "second primary splashes carried water out")
	check(not inv.bucket_full and not wf.visible, "bucket empties cleanly after splash")

	# Planks patch the nearest open hull breach on the real Ship within PLANK_REACH (3.8 m).
	var breach_slot := ship.apply_hull_damage(ship.global_transform * (Vector3(1.8, -0.45, 0.4) * hs), 0.5)
	check(breach_slot >= 0 and ship.open_hole_count() == 1, "ship has 1 open hull breach")
	var hole_local: Vector3 = ship.holes[breach_slot]["local_pos"]
	pawn.board(ship, Vector3(hole_local.x * 0.4, -0.82 * hs, hole_local.z))
	await physics_frames(2)
	inv.equip(&"planks", true)
	inv._use_cooldown = 0.0
	var patched: bool = inv.use_primary()
	check(patched, "planks use_primary returns true when patching breach")
	check_eq(ship.open_hole_count(), 0, "open hull breach is patched cleanly")

	# Tankard heals +15 HP and builds tipsy sway.
	pawn.apply_damage(40.0)
	var hp_before := pawn.health
	var tipsy_events: Array[int] = [0]
	inv.tipsy_changed.connect(func(_t: float) -> void: tipsy_events[0] += 1)
	inv.equip(&"tankard", true)
	inv._use_cooldown = 0.0
	inv.use_primary()
	check_near(pawn.health, hp_before + 15.0, 0.01, "tankard heals +15 HP")
	check(inv.tipsy > 0.3 and tipsy_events[0] > 0, "tankard increases tipsy sway and emits signal")

	# Concertina starts & stops Audio shanty playback cleanly.
	inv.equip(&"instrument", true)
	inv._use_cooldown = 0.0
	inv.use_primary()
	check(inv.playing_shanty and Audio.is_shanty_playing(), "concertina starts shanty stems")
	inv._use_cooldown = 0.0
	inv.use_primary()
	check(not inv.playing_shanty, "concertina toggles shanty off cleanly")
	await _end()


# ---------------------------------------------------------------------------
# 4. MapTableView renders archipelago data, tracks ship heading & markers
# ---------------------------------------------------------------------------

func test_map_table_view_archipelago_and_tracking() -> void:
	_begin()
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)

	var arch := MockArchipelago.new()
	arch.islands_data = [
		{"id": &"port_scoundrel", "name": "Port Scoundrel", "kind": &"outpost", "position": Vector3(0, 0, 0), "radius": 110.0, "discovered": true},
		{"id": &"cutlass_cay", "name": "Cutlass Cay", "kind": &"treasure_island", "position": Vector3(420, 0, -680), "radius": 95.0, "discovered": true},
		{"id": &"mysterious_reef", "name": "Mysterious Reef", "kind": &"landmark", "position": Vector3(-540, 0, -900), "radius": 80.0, "discovered": false},
	]
	_root.add_child(arch)

	var mtv := MapTableView.new()
	check(mtv.mount_to_ship(ship), "MapTableView mounts cleanly onto Ship MapTable")
	mtv.set_archipelago_data(arch)
	mtv.set_voyage_target(Vector3(420.0, 0.0, -680.0))
	mtv.salvage_wrecks.append(Vector3(-180.0, 0.0, -320.0))
	Weather.set_storm_cell(Vector3(-300.0, 0.0, -700.0), 280.0, 0.8, 0.0)
	mtv.refresh_now()
	await get_tree().process_frame

	check_eq(mtv.get_island_count(), 3, "MapTableView reads all archipelago islands")
	check(mtv.get_chart_texture() != null, "MapTableView provides live SubViewport texture")

	# Coordinate round-trip accuracy.
	var probe_w := Vector3(310.0, 0.0, -540.0)
	var px := mtv.world_to_chart(probe_w)
	var back := mtv.chart_to_world(px)
	check_near(back.x, probe_w.x, 0.5, "world_to_chart/chart_to_world X round-trip")
	check_near(back.z, probe_w.z, 0.5, "world_to_chart/chart_to_world Z round-trip")

	# Pan, zoom, and marker placement.
	var old_center := mtv.view_center
	var old_span := mtv.view_span
	mtv.pan(Vector2(150.0, -120.0))
	check_near(mtv.view_center.x, old_center.x + 150.0, 0.01, "pan updates view_center.x")
	mtv.zoom_by(0.75)
	check(mtv.view_span < old_span, "zoom_by(0.75) zooms chart in")
	mtv.place_marker(Vector3(120.0, 0.0, -260.0))
	check_eq(mtv.markers.size(), 1, "place_marker appends marker")

	# Ship movement updates chart coordinate.
	var ship_px_before := mtv.get_ship_chart_pos()
	ship.global_position += Vector3(240.0, 0.0, -180.0)
	mtv.refresh_now()
	var ship_px_after := mtv.get_ship_chart_pos()
	check(ship_px_before.distance_to(ship_px_after) > 25.0, "chart tracks moving ship position")
	mtv.clear_markers()
	check_eq(mtv.markers.size(), 0, "clear_markers clears markers")
	await _end()


# ---------------------------------------------------------------------------
# 5. GameHUD radials, CrewBrain order delivery, notices, quality presets
# ---------------------------------------------------------------------------

func test_hud_radials_crew_orders_banners_and_quality_presets() -> void:
	_begin()
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)

	var rig := _make_player_pawn(Vector3.ZERO)
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	var hs := _ship_scale(ship)
	captain.board(ship, Vector3(0.0, 2.02, 4.9) * hs)

	var mate := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(mate)
	mate.board(ship, Vector3(0.8, 1.12, 0.5) * hs)
	var brain := CrewBrain.new()
	brain.setup(ship, captain, &"helmsman")
	mate.add_child(brain)

	var mock_sky := MockSkyRig.new()
	_root.add_child(mock_sky)

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, inv, cc, ship, null, mock_sky)
	hud.register_crew_brain(brain)
	await get_tree().process_frame

	# Verify original BMFont loads cleanly.
	check(HudIcons.get_ui_font() != null, "UI font loads cleanly")

	# Item Radial opens, pauses mouse look, selects Spyglass, equips it, resumes look.
	hud.open_item_radial()
	check(hud.item_radial.is_open, "Item Radial opens cleanly")
	check(pc.look_paused, "opening Item Radial pauses PlayerController look")
	check(hud.item_radial.select_by_id(&"spyglass"), "Item Radial selects spyglass")
	check(not hud.item_radial.is_open, "Item Radial closes after selection")
	check_eq(inv.active_item, &"spyglass", "Item Radial equips selected tool on Inventory")
	check(not pc.look_paused, "closing Item Radial restores look")

	# Crew Command Wheel opens and routes order cleanly to CrewBrain!
	var ordered: Array[StringName] = []
	hud.crew_order_issued.connect(func(o: StringName) -> void: ordered.append(o))
	hud.open_command_wheel()
	check(hud.command_wheel.is_open, "Crew Command Wheel opens cleanly")
	check_eq(hud.command_wheel.entries.size(), 9, "Crew Command Wheel has 9 wedges")
	check(hud.command_wheel.select_by_id(&"anchor_drop"), "Crew Command Wheel selects anchor_drop")
	check_eq(brain.current_order, &"anchor_drop", "CrewBrain receives captain's anchor_drop order")
	check(ordered.has(&"anchor_drop"), "GameHUD emits crew_order_issued")

	# Hold fire order toggles CrewBrain.hold_fire!
	check(not brain.hold_fire, "CrewBrain starts weapons free")
	var count := hud.issue_crew_order(&"hold_fire")
	check(count >= 1 and brain.hold_fire, "issue_crew_order(&'hold_fire') reaches CrewBrain")

	# CrewBrain's spoken order acknowledgement automatically surfaces on GameHUD's banner!
	check(hud.get_active_banner_text().contains("Barnaby"), "crew order ack appears on HUD banner")

	# Game.notice banner queue works cleanly without overlap.
	hud.clear_banners()
	Game.post_notice("First notice: Land ho!")
	Game.post_notice("Second notice: Wind shifting east!")
	check_eq(hud.get_active_banner_text(), "First notice: Land ho!", "first notice displays immediately")
	check_eq(hud.get_queued_banner_count(), 1, "second notice queues cleanly behind active banner")

	# Pause overlay, quality presets & audio volume sliders work without error.
	hud.set_pause_open(true)
	check(hud.pause_open and pc.look_paused, "Pause overlay opens and pauses camera look")
	hud.set_cloud_quality(2)
	check_eq(mock_sky.cloud_quality, 2, "set_cloud_quality updates SkyRig.cloud_quality")
	hud.set_ocean_quality(0)
	hud.set_bus_volume(Audio.BUS_SFX, 0.55)
	hud.set_pause_open(false)
	check(not hud.pause_open and not pc.look_paused, "closing Pause overlay resumes look")
	await _end()


# ---------------------------------------------------------------------------
# 6. Armory Weapon Meshes (Boarding Axe & Blunderbuss) & Loadout Switching
# ---------------------------------------------------------------------------

func test_armory_weapon_loadouts_and_meshes() -> void:
	_begin()
	for wid: StringName in [&"boarding_axe", &"blunderbuss"]:
		var node := ToolMeshes.build_tool(wid)
		check(node != null, "ToolMeshes.build_tool(%s) returns valid node" % wid)
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 1, "armory weapon %s has MeshInstance3D children" % wid)
		var verts := 0
		for m_node in meshes:
			var mi := m_node as MeshInstance3D
			if mi.mesh != null:
				verts += mi.mesh.get_faces().size()
		check(verts >= 36, "armory weapon %s has sculpted geometry (got %d verts)" % [wid, verts])
		node.free()

	var rig := _make_player_pawn(Vector3(0.0, 2.0, 0.0))
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	await physics_frames(2)

	inv.set_weapon_loadout(&"boarding_axe", &"blunderbuss")
	check_eq(inv.melee_weapon, &"boarding_axe", "Inventory switches melee loadout to boarding_axe")
	check_eq(inv.ranged_weapon, &"blunderbuss", "Inventory switches ranged loadout to blunderbuss")

	inv.equip(&"cutlass", true)
	check_eq(cc.equipped_weapon, &"boarding_axe", "equipping melee slot activates boarding_axe on CombatComponent")
	inv.equip(&"pistol", true)
	check_eq(cc.equipped_weapon, &"blunderbuss", "equipping ranged slot activates blunderbuss on CombatComponent")

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(rig["pawn"], rig["pc"], inv, cc, null, null, null)
	hud.open_item_radial()
	check_eq(String(hud.item_radial.entries[0]["label"]), "Boarding Axe", "Item Radial reflects Boarding Axe label")
	check_eq(hud.item_radial.entries[0]["icon"], &"boarding_axe", "Item Radial reflects boarding_axe icon")
	check_eq(String(hud.item_radial.entries[1]["label"]), "Blunderbuss", "Item Radial reflects Blunderbuss label")
	check_eq(hud.item_radial.entries[1]["icon"], &"blunderbuss", "Item Radial reflects blunderbuss icon")
	hud.close_item_radial(false)

	var menu := ShipwrightMenu.new()
	_root.add_child(menu)
	menu.inventory = inv
	menu.select_armory_loadout(&"cutlass", &"pistol")
	check_eq(inv.melee_weapon, &"cutlass", "ShipwrightMenu restores cutlass loadout")
	check_eq(inv.ranged_weapon, &"pistol", "ShipwrightMenu restores pistol loadout")
	check_eq(cc.equipped_weapon, &"pistol", "CombatComponent updates live from ShipwrightMenu Armory")
	await _end()


# ---------------------------------------------------------------------------
# 7. Wave 10D: Combat Hit-Confirm, Parry Arcs, Damage Vignette & Hull Alerts
# ---------------------------------------------------------------------------

func test_hud_combat_feedback_vignette_and_hull_alert() -> void:
	_begin()
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)

	var hs := _ship_scale(ship)
	var rig := _make_player_pawn(Vector3.ZERO)
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	captain.board(ship, Vector3(0.0, 1.12, 0.2) * hs)

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	# Calling bind() twice verifies signal connections stay idempotent.
	hud.bind(captain, pc, inv, cc, ship, null, null)
	hud.bind(captain, pc, inv, cc, ship, null, null)
	await get_tree().process_frame
	hud.set_process(false)

	# 1. Crosshair hit-confirm & parry guard-arc signals and smooth decay.
	check_near(hud.get_hit_confirm_remaining(), 0.0, 0.001, "hit-confirm starts idle")
	check_near(hud.get_parry_flash_remaining(), 0.0, 0.001, "parry flash starts idle")

	cc.hit_landed.emit(captain, 20.0, false)
	check(hud.get_hit_confirm_remaining() > 0.20, "hit_landed triggers crosshair hit-confirm")
	hud._process(0.12)
	check(hud.get_hit_confirm_remaining() > 0.08 and hud.get_hit_confirm_remaining() < 0.16,
		"hit-confirm decays smoothly")
	hud._process(0.16)
	check_near(hud.get_hit_confirm_remaining(), 0.0, 0.001, "hit-confirm decays cleanly to 0")

	cc.target_hit.emit(ship, 44.0, true)
	check(hud.get_hit_confirm_remaining() > 0.20, "target_hit triggers heavy hit-confirm")
	hud._process(0.30)
	check_near(hud.get_hit_confirm_remaining(), 0.0, 0.001, "heavy hit-confirm decays to 0")

	cc.parried.emit(captain)
	check(hud.get_parry_flash_remaining() > 0.30, "parried triggers brass guard-arc flash")
	hud._process(0.17)
	check(hud.get_parry_flash_remaining() > 0.12 and hud.get_parry_flash_remaining() < 0.22,
		"parry flash decays smoothly")
	hud._process(0.22)
	check_near(hud.get_parry_flash_remaining(), 0.0, 0.001, "parry flash decays cleanly to 0")

	# Direct helper API works cleanly too.
	hud.flash_hit_confirm(true)
	hud.flash_parry()
	check(hud.get_hit_confirm_remaining() > 0.20 and hud.get_parry_flash_remaining() > 0.30,
		"public flash_hit_confirm and flash_parry helpers trigger timers")
	hud._process(0.40)

	# 2. Peripheral damage ink-wash vignette & low-HP heartbeat pulse.
	check_near(hud.get_damage_vignette_alpha(), 0.0, 0.001, "damage vignette starts at 0 at full HP")
	check(not hud.is_damage_vignette_visible(), "damage vignette is hidden at full HP")

	captain.apply_damage(25.0)
	check(hud.is_damage_vignette_visible() and hud.get_damage_vignette_alpha() > 0.25,
		"taking damage spikes peripheral vignette (alpha=%.2f)" % hud.get_damage_vignette_alpha())
	hud._process(0.60)
	check_near(hud.get_damage_vignette_alpha(), 0.0, 0.005,
		"damage flash decays back to 0 when HP stays above 30%")
	check(not hud.is_damage_vignette_visible(), "vignette hides again once flash fades above 30% HP")

	# Low HP (< 30%, alive) sustains gentle breathing pulse (0.12..0.28).
	captain.apply_damage(55.0)  # now 20 / 100 HP
	hud._process(0.60)  # let initial flash decay completely
	hud._process(0.10)
	var low_a := hud.get_damage_vignette_alpha()
	check(hud.is_damage_vignette_visible() and low_a >= 0.11 and low_a <= 0.30,
		"low HP maintains gentle peripheral heartbeat pulse (alpha=%.2f)" % low_a)

	# Colorblind accessibility shifts tint cleanly without error.
	var settings := UserSettings.new()
	settings.data["colorblind_mode"] = "deuteranopia"
	hud.user_settings = settings
	hud._process(0.12)
	check(hud.is_damage_vignette_visible(), "colorblind vignette mode updates cleanly")

	# Healing to full HP hides the vignette cleanly again.
	captain.heal(100.0)
	hud._process(0.05)
	check_near(hud.get_damage_vignette_alpha(), 0.0, 0.005, "full HP clears low-HP vignette pulse")
	check(not hud.is_damage_vignette_visible(), "vignette hides cleanly after healing to full")

	# 3. Hull leak & flooding urgency in bottom-right supplies chip.
	hud._process(0.05)
	check(not hud.is_hull_alert_active(), "intact dry ship shows no hull alert")
	check(not hud.get_tool_meta_text().contains("LEAKS") and not hud.get_tool_meta_text().contains("FLOODING"),
		"dry ship supplies chip stays clean")

	var slot := ship.apply_hull_damage(ship.global_transform * (Vector3(1.8, -0.45, 0.4) * hs), 0.5)
	check(slot >= 0, "breached hull slot for HUD alert test")
	hud._process(0.05)
	check(hud.is_hull_alert_active() and hud.get_tool_meta_text().contains("LEAKS: 1"),
		"open breach appends LEAKS warning (got '%s')" % hud.get_tool_meta_text())

	ship.water_level = 0.48
	hud._process(0.05)
	check(hud.is_hull_alert_active() and hud.get_tool_meta_text().contains("FLOODING!"),
		"high water level escalates chip to FLOODING! (got '%s')" % hud.get_tool_meta_text())

	ship.patch_hole(slot)
	ship.water_level = 0.0
	hud._process(0.05)
	check(not hud.is_hull_alert_active(), "patching & bailing clears hull alert cleanly")

	# 4. Clean teardown disconnects combat/pawn signals with zero leaks.
	hud.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(hud), "GameHUD frees cleanly on teardown")
	await _end()


# ---------------------------------------------------------------------------
# 8. Wave 12A: MapTableView Course Bearing, Wind Feather, Pin Toggle & Threats
# ---------------------------------------------------------------------------

class MockThreatNode:
	extends Node3D
	var dead: bool = false


func test_map_table_course_bearing_wind_pins_and_threats() -> void:
	_begin()
	# 1. Exact 16-point compass bearing & distance formatting (-Z North, +X East).
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(0.0, 0.0, -480.0)), "N  480 m", "due North bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(184.0, 0.0, -443.0)), "NNE  480 m", "NNE intercardinal bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(300.0, 0.0, -300.0)), "NE  424 m", "NE bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(250.0, 0.0, 0.0)), "E  250 m", "due East bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(200.0, 0.0, 200.0)), "SE  283 m", "SE bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(0.0, 0.0, 500.0)), "S  500 m", "due South bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(-200.0, 0.0, 200.0)), "SW  283 m", "SW bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(-350.0, 0.0, 0.0)), "W  350 m", "due West bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(-200.0, 0.0, -200.0)), "NW  283 m", "NW bearing")
	check_eq(MapTableView.format_course_bearing(Vector3.ZERO, Vector3(-184.0, 0.0, -443.0)), "NNW  480 m", "NNW intercardinal bearing")

	# 2. Live wind feather & sepia course-bearing snapshot fields.
	Weather.set_weather(0.15, 14.0, 0.75)
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)
	ship.global_position = Vector3.ZERO

	var mtv := MapTableView.new()
	check(mtv.mount_to_ship(ship), "MapTableView mounts cleanly to sloop")
	mtv.set_voyage_target(Vector3(400.0, 0.0, -400.0))
	mtv.refresh_now()
	var snap := mtv.get_last_snapshot()
	check_near(float(snap.get("wind_heading", -99.0)), 0.75, 0.01, "snapshot records live Weather.wind_heading")
	check(float(snap.get("wind_speed", 0.0)) >= 13.0, "snapshot records live Weather wind speed")
	check(String(snap.get("course_bearing_text", "")).begins_with("NE"),
		"course bearing plots to active voyage target (got '%s')" % String(snap.get("course_bearing_text", "")))
	check(not bool(snap.get("course_from_pin", true)), "voyage course is marked non-pin")

	# 3. Interactive pin toggle (newest pin overrides voyage target for course bearing).
	var added := mtv.toggle_marker_at(Vector3(-300.0, 0.0, 0.0))
	check(added and mtv.markers.size() == 1, "toggle_marker_at drops new pin when empty")
	mtv.refresh_now()
	snap = mtv.get_last_snapshot()
	check(bool(snap.get("course_from_pin", false)), "player pin takes priority for course bearing line")
	check(String(snap.get("course_bearing_text", "")).begins_with("W"),
		"course bearing updates to newest pin (got '%s')" % String(snap.get("course_bearing_text", "")))

	var removed := not mtv.toggle_marker_at(Vector3(-260.0, 0.0, 25.0))
	check(removed and mtv.markers.is_empty(), "toggle_marker_at clears nearest existing pin within 90 m")

	# Verify station occupation activates plotting reticle and edge-triggered Spacebar pin toggle.
	var rig := _make_player_pawn(Vector3.ZERO)
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	pc.input_enabled = true
	captain.board(ship, Vector3(0.0, -0.82, 2.5) * _ship_scale(ship))
	var map_st := ship.get_station(&"map_table")
	check(map_st != null and captain.enter_station(map_st), "captain occupies Station_MapTable")
	mtv.view_center = Vector2(180.0, -320.0)
	Input.action_press(&"jump")
	mtv._poll_table_station_controls(1.0 / 60.0)
	mtv._poll_table_station_controls(1.0 / 60.0)  # holding Space must NOT double-toggle
	Input.action_release(&"jump")
	check_eq(mtv.markers.size(), 1, "edge-triggered Spacebar drops exactly 1 pin at view_center")
	check_near(mtv.markers[0].x, 180.0, 0.1, "Spacebar pin placed at view_center.x")
	mtv.refresh_now()
	check(bool(mtv.get_last_snapshot().get("station_occupied", false)),
		"snapshot flags station_occupied for brass plotting reticle")

	# Re-pressing Spacebar clears the pin right at view_center.
	mtv._poll_table_station_controls(1.0 / 60.0)
	Input.action_press(&"jump")
	mtv._poll_table_station_controls(1.0 / 60.0)
	Input.action_release(&"jump")
	check_eq(mtv.markers.size(), 0, "second Spacebar press clears pin at view_center")
	captain.leave_station()

	# 4. World-threat ink stamps: active Leviathan sigil & clustered active Fort Siege centroid.
	var lev_active := MockThreatNode.new()
	lev_active.add_to_group(&"leviathan")
	_root.add_child(lev_active)
	lev_active.global_position = Vector3(260.0, 0.0, -520.0)

	var lev_dead := MockThreatNode.new()
	lev_dead.dead = true
	lev_dead.add_to_group(&"leviathan")
	_root.add_child(lev_dead)
	lev_dead.global_position = Vector3(-500.0, 0.0, -600.0)

	var bat_a := FortBattery.new()
	bat_a.enable_effects = false
	bat_a.siege_active = true
	_root.add_child(bat_a)
	bat_a.global_position = Vector3(-380.0, 12.0, -490.0)

	var bat_b := FortBattery.new()
	bat_b.enable_effects = false
	bat_b.siege_active = true
	_root.add_child(bat_b)
	bat_b.global_position = Vector3(-420.0, 12.0, -510.0)

	var bat_destroyed := FortBattery.new()
	bat_destroyed.enable_effects = false
	bat_destroyed.siege_active = true
	bat_destroyed.destroyed = true
	_root.add_child(bat_destroyed)
	bat_destroyed.global_position = Vector3(500.0, 12.0, -700.0)

	var bat_idle := FortBattery.new()
	bat_idle.enable_effects = false
	bat_idle.siege_active = false
	_root.add_child(bat_idle)
	bat_idle.global_position = Vector3(600.0, 12.0, -800.0)

	mtv.refresh_now()
	await get_tree().process_frame
	snap = mtv.get_last_snapshot()
	var levs: Array = snap.get("leviathans", [])
	var forts: Array = snap.get("fort_sieges", [])
	check_eq(levs.size(), 1, "chart plots exactly 1 active Leviathan sigil (ignoring defeated)")
	check_eq(forts.size(), 1, "chart clusters 2 active FortBatteries into 1 Fort Siege emblem")
	if forts.size() == 1:
		var fc: Vector3 = forts[0]
		check_near(fc.x, -400.0, 0.5, "Fort Siege centroid X matches clustered active batteries")
		check_near(fc.z, -500.0, 0.5, "Fort Siege centroid Z matches clustered active batteries")

	await _end()


# ---------------------------------------------------------------------------
# 7. Diegetic Riddle Scroll & WANTED Bounty Poster parchment modes
# ---------------------------------------------------------------------------

func test_riddle_scroll_and_bounty_poster_parchment_modes() -> void:
	_begin()
	var stanzas := [
		"Where twin palms lean above the cove,",
		"Walk seven paces toward the stony alcove,",
		"Strike spade where shadows guard the trove.",
	]

	# 1. MapPainter.paint_riddle_scroll produces a rich 512x512 parchment with ink, wax seal & progressive reveal.
	var riddle_1 := MapPainter.paint_riddle_scroll("Cutlass Cay", stanzas, 1, 17)
	var riddle_3 := MapPainter.paint_riddle_scroll("Cutlass Cay", stanzas, 3, 17)
	check(riddle_1 != null and riddle_3 != null, "paint_riddle_scroll returns ImageTexture")
	var r1_img := riddle_1.get_image()
	var r3_img := riddle_3.get_image()
	check_eq(r1_img.get_width(), 512, "riddle scroll width is 512")
	check_eq(r1_img.get_height(), 512, "riddle scroll height is 512")

	var r1_ink := 0
	var r3_ink := 0
	var r1_wax := 0
	for y in range(0, 512, 2):
		for x in range(0, 512, 2):
			var c1 := r1_img.get_pixel(x, y)
			var c3 := r3_img.get_pixel(x, y)
			if c1.r < 0.34 and c1.g < 0.24 and c1.b < 0.16:
				r1_ink += 1
			if c3.r < 0.34 and c3.g < 0.24 and c3.b < 0.16:
				r3_ink += 1
			if x > 360 and y > 380 and c1.r > 0.58 and c1.g < 0.24 and c1.b < 0.20:
				r1_wax += 1
	check(r1_ink > 500, "riddle scroll contains crisp hand-inked typography & border (%d ink samples)" % r1_ink)
	check(r3_ink > r1_ink + 200, "revealing all 3 stanzas inks visibly more text (%d > %d)" % [r3_ink, r1_ink])
	check(r1_wax > 120, "riddle scroll stamps crimson wax seal at bottom-right (%d wax samples)" % r1_wax)

	# 2. MapPainter.paint_bounty_poster produces a rich 512x512 WANTED bill with skull portrait, glowing eyes & wax seal.
	var bounty_tex := MapPainter.paint_bounty_poster("Captain Vane", "Skull Bluff", 1250, 29)
	check(bounty_tex != null, "paint_bounty_poster returns ImageTexture")
	var b_img := bounty_tex.get_image()
	check_eq(b_img.get_width(), 512, "bounty poster width is 512")
	check_eq(b_img.get_height(), 512, "bounty poster height is 512")

	var b_ink := 0
	var b_wax := 0
	var b_glow_eyes := 0
	var b_diff_from_riddle := 0
	for y in range(0, 512, 2):
		for x in range(0, 512, 2):
			var cb := b_img.get_pixel(x, y)
			var cr := r3_img.get_pixel(x, y)
			if cb.r < 0.32 and cb.g < 0.24 and cb.b < 0.18:
				b_ink += 1
			if x > 370 and y > 385 and cb.r > 0.58 and cb.g < 0.24 and cb.b < 0.20:
				b_wax += 1
			if x > 210 and x < 302 and y > 230 and y < 270 and cb.r > 0.88 and cb.g > 0.30 and cb.b < 0.55:
				b_glow_eyes += 1
			if absf(cb.r - cr.r) + absf(cb.g - cr.g) + absf(cb.b - cr.b) > 0.25:
				b_diff_from_riddle += 1
	check(b_ink > 1800, "bounty poster renders bold WANTED header, tricorn hat & portrait ink (%d samples)" % b_ink)
	check(b_wax > 120, "bounty poster stamps crimson wax seal (%d wax samples)" % b_wax)
	check(b_glow_eyes > 20, "bounty poster renders glowing skull eyes (%d glow samples)" % b_glow_eyes)
	check(b_diff_from_riddle > 4000, "bounty poster is visually distinct from riddle scroll (%d differing pixels)" % b_diff_from_riddle)

	# 3. Inventory swaps held 3D MapSurface texture across treasure -> riddle -> bounty -> treasure seamlessly.
	var rig := _make_player_pawn(Vector3(0.0, 2.0, 0.0))
	var inv: Inventory = rig["inv"]
	await physics_frames(2)
	inv.equip(&"map", true)
	check_eq(inv.map_mode, &"treasure", "Inventory starts in treasure map_mode")

	var surf := inv.get_active_tool_node().get_node_or_null(^"MapSurface") as MeshInstance3D
	check(surf != null, "equipped map tool has MapSurface")
	var mat := surf.material_override as StandardMaterial3D

	var r_tex := inv.set_riddle_scroll("Cutlass Cay", stanzas, 2)
	check_eq(inv.map_mode, &"riddle", "set_riddle_scroll switches map_mode to riddle")
	check(r_tex != null and mat.albedo_texture == r_tex, "held MapSurface displays Riddle Scroll texture")

	var b_tex := inv.set_bounty_poster("Captain Vane", "Skull Bluff", 1250)
	check_eq(inv.map_mode, &"bounty", "set_bounty_poster switches map_mode to bounty")
	check(b_tex != null and mat.albedo_texture == b_tex, "held MapSurface displays WANTED Bounty Poster texture")

	var t_tex := inv.set_treasure_map("Cutlass Cay", PackedVector2Array(), Vector2(18.0, -12.0), 100.0)
	check_eq(inv.map_mode, &"treasure", "set_treasure_map resets map_mode to treasure")
	check(t_tex != null and mat.albedo_texture == t_tex, "held MapSurface restores Treasure Map texture")

	await _end()


# ---------------------------------------------------------------------------
# 10. Wave 16B: Full-Spectrum Living-Sea Spyglass Identifier & 16-Point Bearings
# ---------------------------------------------------------------------------

func test_spyglass_living_sea_horizon_identifier_and_bearings() -> void:
	_begin()

	# 1. Verify exact 16-point maritime compass heading convention (-Z = N, +X = E).
	check_eq(Inventory.format_compass_bearing(Vector3.ZERO, Vector3(0.0, 0.0, -200.0)), "N")
	check_eq(Inventory.format_compass_bearing(Vector3.ZERO, Vector3(200.0, 0.0, 0.0)), "E")
	check_eq(Inventory.format_compass_bearing(Vector3.ZERO, Vector3(0.0, 0.0, 200.0)), "S")
	check_eq(Inventory.format_compass_bearing(Vector3.ZERO, Vector3(-200.0, 0.0, 0.0)), "W")
	check_eq(Inventory.format_compass_bearing(Vector3.ZERO, Vector3(-180.0, 0.0, 180.0)), "SW")
	check_eq(Inventory.format_compass_bearing(Vector3.ZERO, Vector3(-240.0, 0.0, -100.0)), "WNW")
	check_eq(Inventory.format_compass_bearing(Vector3.ZERO, Vector3(165.0, 0.0, -415.0)), "NNE")

	var rig := _make_player_pawn(Vector3(0.0, 4.0, 0.0))
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, inv, cc, null, null, null)
	await physics_frames(2)

	# Build a ring of living-sea horizon targets around the observer (one per bearing).
	var corsair := SLOOP_SCENE.instantiate() as Ship
	corsair.enable_effects = false
	corsair.start_anchored = true
	corsair.faction = &"corsair"
	corsair.ship_class = &"sloop"
	corsair.position = Vector3(0.0, 0.0, -220.0)  # N
	_root.add_child(corsair)

	var ghost := SLOOP_SCENE.instantiate() as Ship
	ghost.enable_effects = false
	ghost.start_anchored = true
	ghost.faction = &"ghost"
	ghost.ship_class = &"sloop"
	ghost.position = Vector3(240.0, 0.0, 0.0)  # E
	_root.add_child(ghost)

	var brig := SLOOP_SCENE.instantiate() as Ship
	brig.enable_effects = false
	brig.start_anchored = true
	brig.faction = &"player"
	brig.ship_class = &"brigantine"
	brig.position = Vector3(-180.0, 0.0, 180.0)  # SW
	_root.add_child(brig)

	var dolphins := Node3D.new()
	dolphins.position = Vector3(-110.0, 0.0, -110.0)  # NW
	dolphins.add_to_group(&"dolphins")
	_root.add_child(dolphins)

	var shark := Node3D.new()
	shark.position = Vector3(70.0, 0.0, 70.0)  # SE
	shark.add_to_group(&"sharks")
	_root.add_child(shark)

	var raft := CastawayRaft.new()
	raft.auto_buoyancy = false
	raft.position = Vector3(-160.0, 0.0, 0.0)  # W
	_root.add_child(raft)

	var battery := FortBattery.new()
	battery.siege_active = true
	battery.destroyed = false
	battery.position = Vector3(0.0, 0.0, 180.0)  # S
	_root.add_child(battery)

	var lev := Node3D.new()
	lev.position = Vector3(240.0, 0.0, -100.0)  # ENE
	lev.add_to_group(&"leviathan")
	_root.add_child(lev)

	var island := Node3D.new()
	island.position = Vector3(165.0, 0.0, -415.0)  # NNE
	island.set_meta("display_name", "Cutlass Cay")
	island.add_to_group(&"islands")
	_root.add_child(island)

	await physics_frames(1)
	inv.equip(&"spyglass", true)
	inv.set_secondary_held(true)

	var aim_and_scan := func(target_pos: Vector3) -> void:
		var delta := target_pos - captain.eye_position()
		var horiz := maxf(Vector2(delta.x, delta.z).length(), 0.001)
		captain.look_yaw = atan2(-delta.x, -delta.z)
		captain.look_pitch = atan2(delta.y, horiz)
		inv.call(&"_scan_spyglass_sighting")

	var cases: Array[Array] = [
		[corsair.global_position + Vector3.UP * 3.5, "Corsair Raider", "N"],
		[ghost.global_position + Vector3.UP * 3.5, "Spectral Ghost Ship", "E"],
		[brig.global_position + Vector3.UP * 3.5, "Brigantine", "SW"],
		[dolphins.global_position + Vector3.UP * 1.0, "Dolphin Pod", "NW"],
		[shark.global_position + Vector3.UP * 0.5, "Ocean Shark", "SE"],
		[raft.global_position + Vector3.UP * 2.0, "Castaway Raft", "W"],
		[battery.global_position + Vector3.UP * 2.0, "Ironwatch Fort Battery", "S"],
		[lev.global_position + Vector3.UP * 6.0, "Abyssal Leviathan", "ENE"],
		[island.global_position + Vector3.UP * 14.0, "Cutlass Cay", "NNE"],
	]
	for c: Array in cases:
		aim_and_scan.call(c[0] as Vector3)
		check_eq(inv.spyglass_sighting, String(c[1]),
			"spyglass identifies '%s' (got '%s')" % [String(c[1]), inv.spyglass_sighting])
		check_eq(inv.spyglass_sighting_bearing, String(c[2]),
			"spyglass computes bearing '%s' for %s (got '%s')" % [String(c[2]), String(c[1]), inv.spyglass_sighting_bearing])

	# Verify HUD spyglass overlay formats crisp uppercase ASCII 'LABEL  -  DIST m  BEARING' pill!
	aim_and_scan.call(ghost.global_position + Vector3.UP * 3.5)
	var hud_txt: String = hud._spyglass_view.get_sighting_text()
	check(hud_txt.begins_with("SPECTRAL GHOST SHIP  -  ") and hud_txt.ends_with(" m  E"),
		"HUD spyglass pill formats uppercase ASCII with bearing (got '%s')" % hud_txt)
	for ci in hud_txt.length():
		check(hud_txt.unicode_at(ci) < 128, "HUD spyglass text is strictly ASCII")

	# Verify rescued CastawayRaft is ignored cleanly.
	raft.is_rescued = true
	aim_and_scan.call(raft.global_position + Vector3.UP * 2.0)
	check_eq(inv.spyglass_sighting, "", "rescued CastawayRaft is ignored by spyglass")

	inv.set_secondary_held(false)
	await _end()


# ---------------------------------------------------------------------------
# 9. Wave 17B: Captain Multi-Instrument Shanty Solo Cycling & Golden Motes
# ---------------------------------------------------------------------------

func test_captain_multi_instrument_shanty_cycling_and_motes() -> void:
	_begin()
	var rig := _make_player_pawn(Vector3(0.0, 2.0, 0.0))
	var captain: Pawn = rig["pawn"]
	var inv: Inventory = rig["inv"]

	# Verify FP_POSES exist for all 3 instruments without near-plane camera clipping.
	for pid: StringName in [&"instrument", &"hurdy_gurdy", &"whistle"]:
		check(Inventory.FP_POSES.has(pid), "FP_POSES defines pose for %s" % pid)
		var pose: Array = Inventory.FP_POSES[pid]
		check((pose[0] as Vector3).z <= -0.25 and (pose[2] as Vector3).z <= -0.22,
			"FP pose for %s stays cleanly clear of camera near plane" % pid)

	check_eq(inv.shanty_instrument, &"concertina", "default shanty_instrument is concertina")
	check_eq(inv.get_resolved_tool_id(&"instrument"), &"instrument", "concertina resolves to &'instrument'")

	var changed_events: Array[StringName] = []
	inv.shanty_instrument_changed.connect(func(inst: StringName) -> void: changed_events.append(inst))
	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	inv.equip(&"instrument", true)
	await get_tree().process_frame
	check(inv.fp_tool_node != null and inv.fp_tool_node.get_node_or_null(^"Bellows") != null,
		"equipping instrument defaults to sculpted Concertina mesh")

	# Start shanty on concertina -> starts Audio shanty & spawns CaptainShantyMotes.
	inv.set_playing_shanty(true)
	check(inv.playing_shanty and Audio.is_shanty_playing(), "playing shanty starts Audio stems")
	check_near(float(Audio._stems[&"concertina"]["goal"]), 1.0, 0.01, "concertina stem active")
	var motes := inv.get_shanty_motes()
	check(motes != null and motes.name == "CaptainShantyMotes" and motes.emitting and motes.amount == 8,
		"starting shanty spawns 8-mote CaptainShantyMotes GPUParticles3D")

	# Holding RMB edge-triggers cycling ONCE: concertina -> hurdy_gurdy (without restarting shanty!).
	inv.set_secondary_held(true)
	inv.set_secondary_held(true)  # holding must NOT cycle twice
	await get_tree().process_frame
	check_eq(inv.shanty_instrument, &"hurdy_gurdy", "RMB press cycles concertina -> hurdy_gurdy once")
	check_eq(inv.get_resolved_tool_id(&"instrument"), &"hurdy_gurdy", "hurdy_gurdy resolves cleanly")
	check_eq(changed_events.size(), 1, "holding RMB does not double-cycle")
	check(notices.has("Instrument: Hurdy-Gurdy"), "cycling posts Hurdy-Gurdy toast notice")
	check(Audio.is_shanty_playing(), "cycling mid-song keeps shanty playing without restart")
	check_near(float(Audio._stems[&"concertina"]["goal"]), 0.0, 0.01, "old concertina stem crossfades off")
	check_near(float(Audio._stems[&"hurdy_gurdy"]["goal"]), 1.0, 0.01, "new hurdy_gurdy stem crossfades on")
	var crank := inv.fp_tool_node.get_node_or_null(^"CrankHandle") as Node3D if inv.fp_tool_node != null else null
	check(crank != null, "held FP mesh swaps to sculpted Hurdy-Gurdy with CrankHandle")
	var crank_before := crank.rotation.x if crank != null else 0.0
	for _i in 6:
		inv._tick_concertina(0.05)
	check(crank != null and absf(crank.rotation.x - crank_before) > 0.1,
		"Hurdy-Gurdy crank animates rhythmically while playing")

	# Release & press RMB again -> cycles hurdy_gurdy -> whistle and animates sway/nod.
	inv.set_secondary_held(false)
	inv.set_secondary_held(true)
	await get_tree().process_frame
	check_eq(inv.shanty_instrument, &"whistle", "second RMB press cycles hurdy_gurdy -> whistle")
	check_eq(inv.get_resolved_tool_id(&"instrument"), &"whistle", "whistle resolves cleanly")
	check(notices.has("Instrument: Bosun's Whistle"), "cycling posts Bosun's Whistle toast notice")
	check_near(float(Audio._stems[&"hurdy_gurdy"]["goal"]), 0.0, 0.01, "hurdy_gurdy stem crossfades off")
	check_near(float(Audio._stems[&"whistle"]["goal"]), 1.0, 0.01, "whistle stem crossfades on")
	check(inv.fp_tool_node != null and inv.fp_tool_node.get_node_or_null(^"BraidedLanyard") != null,
		"held FP mesh swaps to sculpted Bosun's Whistle")
	for _i in 6:
		inv._tick_concertina(0.05)
	check(inv._whistle_rot_deg.length() > 0.2, "Bosun's Whistle animates rhythmic sway/nod while playing")

	# Third cycle wraps whistle -> concertina cleanly.
	inv.set_secondary_held(false)
	inv.cycle_shanty_instrument(false)
	check_eq(inv.shanty_instrument, &"concertina", "third cycle wraps cleanly back to concertina")

	# Stopping shanty detaches & frees CaptainShantyMotes cleanly with zero leaks.
	inv.set_playing_shanty(false)
	await get_tree().process_frame
	check(inv.get_shanty_motes() == null, "stopping shanty clears CaptainShantyMotes ref")
	check(not is_instance_valid(motes), "CaptainShantyMotes freed cleanly on stop")
	check(captain.get_node_or_null(^"CaptainShantyMotes") == null, "no dangling motes child on captain pawn")

	Game.notice.disconnect(notice_cb)
	await _end()


# ---------------------------------------------------------------------------
# 10. Wave 19D: Spyglass LMB Horizon Callout & Crew Acknowledgement
# ---------------------------------------------------------------------------

func test_spyglass_callout_signals_and_crew_acknowledgement() -> void:
	_begin()
	var rig := _make_player_pawn(Vector3(0.0, 4.0, 0.0))
	var captain: Pawn = rig["pawn"]
	var inv: Inventory = rig["inv"]

	# Place a Spectral Ghost Ship cleanly to the East (240 m away).
	var ghost := SLOOP_SCENE.instantiate() as Ship
	ghost.enable_effects = false
	ghost.start_anchored = true
	ghost.faction = &"ghost"
	ghost.ship_class = &"sloop"
	ghost.position = Vector3(240.0, 0.0, 0.0)
	_root.add_child(ghost)

	# Place Maren (closest crewmate) and Barnaby + Pip (to test all 3 persona ack templates).
	var maren_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(maren_pawn)
	maren_pawn.global_position = Vector3(0.0, 4.0, -2.0)
	var maren := CrewBrain.new()
	maren.setup(null, captain, &"lookout")
	maren_pawn.add_child(maren)

	var barnaby_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(barnaby_pawn)
	barnaby_pawn.global_position = Vector3(0.0, 4.0, 8.0)
	var barnaby := CrewBrain.new()
	barnaby.setup(null, captain, &"helmsman")
	barnaby_pawn.add_child(barnaby)

	var pip_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pip_pawn)
	pip_pawn.global_position = Vector3(0.0, 4.0, 12.0)
	var pip := CrewBrain.new()
	pip.setup(null, captain, &"carpenter")
	pip_pawn.add_child(pip)
	await physics_frames(2)

	var callout_events: Array[Dictionary] = []
	inv.spyglass_callout_made.connect(func(lbl: String, dist_m: float, brg: String, tpos: Vector3) -> void:
		callout_events.append({"label": lbl, "dist": dist_m, "bearing": brg, "pos": tpos})
	)
	var crew_acks: Array[Dictionary] = []
	for br: CrewBrain in [maren, barnaby, pip]:
		br.callout_spoken.connect(func(sp: String, txt: String, cat: StringName) -> void:
			if cat == &"sighting_ack":
				crew_acks.append({"speaker": sp, "text": txt})
		)
	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	# Aim zoomed spyglass straight East at the Ghost Ship & verify LMB primary callout!
	inv.equip(&"spyglass", true)
	inv.set_secondary_held(true)
	check(inv.spyglass_zoomed, "spyglass_zoomed is true while peering through spyglass")
	var delta_g := (ghost.global_position + Vector3.UP * 3.5) - captain.eye_position()
	var horiz := maxf(Vector2(delta_g.x, delta_g.z).length(), 0.001)
	captain.look_yaw = atan2(-delta_g.x, -delta_g.z)
	captain.look_pitch = atan2(delta_g.y, horiz)
	inv.call(&"_scan_spyglass_sighting")
	check_eq(inv.spyglass_sighting, "Spectral Ghost Ship", "spyglass locks onto Spectral Ghost Ship")
	check_eq(inv.spyglass_sighting_bearing, "E", "spyglass bearing is E")

	var ok_call: Variant = inv.use_primary()
	check_eq(bool(ok_call), true, "LMB primary-use calls out sighted target while zoomed")
	check_eq(callout_events.size(), 1, "spyglass_callout_made emits once")
	if callout_events.size() == 1:
		check_eq(callout_events[0]["label"], "Spectral Ghost Ship", "callout label matches")
		check_eq(callout_events[0]["bearing"], "E", "callout bearing matches")
		check(float(callout_events[0]["dist"]) > 200.0, "callout distance matches target")
	var found_cap_notice := false
	for n_txt in notices:
		if n_txt.begins_with("Captain: Spectral Ghost Ship off the E - "):
			found_cap_notice = true
	check(found_cap_notice, "Captain ASCII callout posted to Game notices")

	# Nearest crewmate (Maren) acknowledges sighting and turns toward East!
	check_eq(crew_acks.size(), 1, "nearest active CrewBrain acknowledges captain sighting once")
	if crew_acks.size() == 1:
		check_eq(crew_acks[0]["speaker"], "Maren", "nearest crewmate Maren responds")
		check(String(crew_acks[0]["text"]).contains("Spotted Spectral Ghost Ship off the E"),
			"Maren uses authentic lookout sighting ack template (got '%s')" % String(crew_acks[0]["text"]))
	var maren_fwd := Vector3(-sin(maren_pawn.look_yaw), 0.0, -cos(maren_pawn.look_yaw))
	check(maren_fwd.dot(Vector3(1.0, 0.0, 0.0)) > 0.9, "Maren turns toward the sighted East target")

	# Immediate second LMB press obeys 2.5 s anti-spam cooldown cleanly.
	var spam_call: Variant = inv.use_primary()
	check_eq(bool(spam_call), false, "repeat LMB press within 2.5 s cooldown is ignored cleanly")
	check_eq(callout_events.size(), 1, "cooldown prevents duplicate spyglass_callout_made signals")

	# Verify Barnaby & Pip persona templates and 4.0 s sighting_ack cooldown.
	check(barnaby.acknowledge_captain_sighting("Abyssal Leviathan", "NW", Vector3(-180.0, 0.0, -180.0)),
		"Barnaby acknowledges sighting cleanly")
	check(not barnaby.acknowledge_captain_sighting("Abyssal Leviathan", "NW", Vector3(-180.0, 0.0, -180.0)),
		"Barnaby obeys 4.0 s sighting_ack cooldown")
	check(pip.acknowledge_captain_sighting("Corsair Raider", "S", Vector3(0.0, 0.0, 220.0)),
		"Pip acknowledges sighting cleanly")
	check_eq(crew_acks.size(), 3, "all three persona templates emitted sighting_ack")
	if crew_acks.size() == 3:
		check(String(crew_acks[1]["text"]).contains("Aye, Captain! Abyssal Leviathan to the NW"),
			"Barnaby uses authentic helmsman ack template")
		check(String(crew_acks[2]["text"]).contains("Corsair Raider to the S? Guns and planks"),
			"Pip uses authentic carpenter ack template")

	Game.notice.disconnect(notice_cb)
	inv.set_secondary_held(false)
	await _end()


# ---------------------------------------------------------------------------
# 11. Wave 20C: Spyglass Whale/Manta Sightings, Helm Telemetry & Ship Title
# ---------------------------------------------------------------------------

func test_spyglass_whale_manta_and_helm_sailing_telemetry_pill() -> void:
	_begin()
	Weather.set_weather(0.0, 10.0, 0.0)
	Sea.amp_scale = 0.0

	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	ship.start_anchored = true
	_root.add_child(ship)
	ship.global_position = Vector3.ZERO

	var rig := _make_player_pawn(Vector3(0.0, 2.0, 4.0))
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	captain.board(ship, Vector3(0.0, 2.02, 4.1) * _ship_scale(ship))

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, inv, cc, ship, null, null)
	await physics_frames(4)

	# 1. Verify Spyglass identifies Humpback Whale (&"whales") & Giant Manta Ray (&"manta_rays").
	var whale := Node3D.new()
	whale.add_to_group(&"whales")
	_root.add_child(whale)
	whale.global_position = Vector3(-115.0, 0.0, -280.0)  # NNW, ~303 m

	var manta := Node3D.new()
	manta.add_to_group(&"manta_rays")
	_root.add_child(manta)
	manta.global_position = Vector3(68.0, 0.0, 28.0)  # ESE, ~73 m

	inv.equip(&"spyglass", true)
	inv.set_secondary_held(true)

	var aim_at := func(world_pt: Vector3) -> void:
		var d := world_pt - captain.eye_position()
		var h := maxf(Vector2(d.x, d.z).length(), 0.001)
		captain.look_yaw = atan2(-d.x, -d.z)
		captain.look_pitch = atan2(d.y, h)
		inv.call(&"_scan_spyglass_sighting")

	aim_at.call(whale.global_position + Vector3.UP * 2.5)
	check_eq(inv.spyglass_sighting, "Humpback Whale", "spyglass identifies Humpback Whale in group &'whales'")
	check_eq(inv.spyglass_sighting_bearing, "NNW", "Humpback Whale bearing is NNW")

	aim_at.call(manta.global_position + Vector3.UP * 0.4)
	check_eq(inv.spyglass_sighting, "Giant Manta Ray", "spyglass identifies Giant Manta Ray in group &'manta_rays'")
	check_eq(inv.spyglass_sighting_bearing, "ESE", "Giant Manta Ray bearing is ESE")
	inv.set_secondary_held(false)

	# 2. Verify helm-only SailingTrimPill stays strictly hidden while free-roaming & at non-sailing stations!
	hud._process(0.05)
	check(not hud.is_sailing_telemetry_visible(), "SailingTrimPill is strictly hidden while walking free on deck")

	var map_st := ship.get_station(&"map_table")
	if map_st != null:
		captain.enter_station(map_st)
		hud._process(0.05)
		check(not hud.is_sailing_telemetry_visible(), "SailingTrimPill stays hidden at non-sailing MapTable station")
		captain.leave_station()

	# Occupy Station_Helm -> pill becomes visible and tracks ANCHORED, SAILS FURLED, FULL WIND, TRIM SAILS!
	var helm_st := ship.get_station(&"helm")
	check(helm_st != null and captain.enter_station(helm_st), "captain takes Station_Helm")

	ship.anchor_down = true
	hud._process(0.05)
	check(hud.is_sailing_telemetry_visible(), "SailingTrimPill shows while occupying Station_Helm")
	check(hud.get_sailing_telemetry_text().ends_with("kt  |  ANCHORED"),
		"anchored ship displays ANCHORED telemetry (got '%s')" % hud.get_sailing_telemetry_text())

	ship.anchor_down = false
	ship.sail_set = 0.0
	hud._process(0.05)
	check(hud.get_sailing_telemetry_text().ends_with("kt  |  SAILS FURLED"),
		"furled sails display SAILS FURLED telemetry (got '%s')" % hud.get_sailing_telemetry_text())

	ship.sail_set = 0.90
	ship.sail_trim = ship.ideal_sail_trim()
	hud._process(0.05)
	var full_txt := hud.get_sailing_telemetry_text()
	check(full_txt.ends_with("kt  |  FULL WIND"),
		"aligned sail trim displays FULL WIND telemetry (got '%s')" % full_txt)
	for ci in full_txt.length():
		check(full_txt.unicode_at(ci) < 128, "SailingTrimPill text is strictly ASCII")

	ship.sail_trim = wrapf(ship.ideal_sail_trim() + 1.15, -PI, PI)
	hud._process(0.05)
	check(hud.get_sailing_telemetry_text().ends_with("kt  |  TRIM SAILS"),
		"misaligned sail trim displays TRIM SAILS telemetry (got '%s')" % hud.get_sailing_telemetry_text())

	# Leaving helm hides pill immediately.
	captain.leave_station()
	hud._process(0.05)
	check(not hud.is_sailing_telemetry_visible(), "SailingTrimPill hides immediately upon leaving Station_Helm")

	# 3. Verify show_voyage_title() appends custom ship name cleanly in strict ASCII.
	var prev_ship_name := Game.profile.get_ship_name()
	Game.profile.set_ship_name("Gilded Gull")
	hud.show_voyage_title("CUTLASS CAY", "Buried Hoard", 4.0)
	var sub_txt := hud.get_voyage_title_subtitle_text()
	check(sub_txt.contains("Aboard Gilded Gull"),
		"Voyage Title Card subtitle includes custom ship name (got '%s')" % sub_txt)
	for ci in sub_txt.length():
		check(sub_txt.unicode_at(ci) < 128, "Voyage Title Card subtitle is strictly ASCII")
	Game.profile.set_ship_name(prev_ship_name)

	hud.queue_free()
	await physics_frames(2)
	await _end()


# ---------------------------------------------------------------------------
# 12. Wave 22D: 3D Tool Variants, Lantern Beacon Flare/Signal & Sculpted Dirt VFX
# ---------------------------------------------------------------------------

func test_tool_variant_3d_visuals_lantern_signal_and_zero_primitive_shovel() -> void:
	_begin()
	var rig := _make_player_pawn(Vector3(0.0, 2.0, 0.0))
	var inv: Inventory = rig["inv"]

	# 1. Zero-primitive sculpted earth-clod shovel VFX (zero SphereMesh in Inventory!).
	var inv_src := FileAccess.get_file_as_string("res://src/items/inventory.gd")
	check(not inv_src.contains("SphereMesh.new"), "src/items/inventory.gd contains zero raw SphereMesh.new() placeholders")
	var dirt_vfx := inv.spawn_shovel_dirt_vfx(Vector3(0.0, 1.0, -1.0))
	check(dirt_vfx != null and dirt_vfx.mesh is ArrayMesh and not (dirt_vfx.mesh is PrimitiveMesh),
		"shovel dirt VFX uses sculpted flat-faceted ArrayMesh (zero SphereMesh)")
	if dirt_vfx != null and dirt_vfx.mesh is ArrayMesh:
		var cmat := (dirt_vfx.mesh as ArrayMesh).surface_get_material(0) as StandardMaterial3D
		check(cmat != null and cmat.vertex_color_use_as_albedo and cmat.vertex_color_is_srgb,
			"shovel clod material enables vertex_color_use_as_albedo and vertex_color_is_srgb")
	if dirt_vfx != null:
		dirt_vfx.queue_free()

	# 2. Interactive Lantern RMB Beacon Flare & LMB Mariner's Signal Flash!
	inv.equip(&"lantern", true)
	inv.lantern_lit = true
	await get_tree().process_frame
	var light := inv.fp_tool_node.get_node_or_null(^"LanternLight") as OmniLight3D
	check(light != null, "equipped Lantern exposes LanternLight OmniLight3D")
	inv._tick_lantern_flicker(0.1)
	var rest_energy := light.light_energy if light != null else 0.0
	var rest_range := light.omni_range if light != null else 0.0
	check(not inv.is_lantern_beacon_flared(), "lantern starts un-flared while lowered")

	# Raise lantern with RMB -> flares energy (~2.4 -> ~4.3) and range (12 -> 22 m)!
	inv.set_secondary_held(true)
	check(inv.is_lantern_beacon_flared(), "holding RMB activates is_lantern_beacon_flared()")
	for _i in 20:
		inv._tick_lantern_flicker(0.05)
	check(light != null and light.light_energy > rest_energy + 1.1 and light.omni_range > rest_range + 7.5,
		"RMB beacon flare boosts lantern light energy (%.2f -> %.2f) and range (%.1f -> %.1f)" % [
			rest_energy, light.light_energy, rest_range, light.omni_range])

	# LMB while raising triggers Mariner's Signal Flash (energy ~6.5, emits lantern_signaled, respects 2.5 s cooldown)!
	var signal_positions: Array[Vector3] = []
	inv.lantern_signaled.connect(func(wp: Vector3) -> void: signal_positions.append(wp))
	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	var ok_sig: Variant = inv.use_primary()
	check_eq(bool(ok_sig), true, "LMB while raising lit Lantern triggers Mariner's Signal Flash")
	check_eq(signal_positions.size(), 1, "lantern_signaled emits once")
	check(notices.has("Lantern signal flashed across the water!"), "signal flash posts water signal notice")
	check(light != null and light.light_energy >= 6.0,
		"momentary signal flash boosts lantern energy to ~6.5 (got %.2f)" % (light.light_energy if light != null else 0.0))
	check(inv.lantern_lit, "LMB signal flash keeps raised lantern lit instead of turning it off")
	check_eq(bool(inv.trigger_lantern_signal()), false, "signal flash obeys 2.5 s anti-spam cooldown")
	inv.set_secondary_held(false)
	Game.notice.disconnect(notice_cb)

	# 3. Visible 3D first-person tool_variant visuals & clean reset on &"".
	# 3a. Far-Spyglass: elongated DrawTubes + sculpted azure-sapphire VariantAccentRing.
	inv.equip(&"spyglass", true)
	inv.apply_tool_modifiers({"tool_variant_id": &"tool_far_spyglass", "spyglass_zoom_scale": 0.72})
	var tubes := inv.fp_tool_node.get_node_or_null(^"DrawTubes") as Node3D
	var ring := tubes.get_node_or_null(^"VariantAccentRing") as MeshInstance3D if tubes != null else null
	check(tubes != null and is_equal_approx(tubes.scale.z, 1.22), "tool_far_spyglass elongates DrawTubes.scale.z to 1.22")
	check(ring != null and ring.visible and ring.mesh is ArrayMesh and not (ring.mesh is PrimitiveMesh),
		"tool_far_spyglass attaches visible sculpted ArrayMesh VariantAccentRing")
	inv.apply_tool_modifiers({"tool_variant_id": &""})
	check(tubes != null and tubes.scale.is_equal_approx(Vector3.ONE) and ring != null and not ring.visible,
		"clearing tool_variant resets Spyglass draw-tubes & hides VariantAccentRing")

	# 3b. Relic Shovel: antique gold-bronze SpadeBlade + luminous jade-turquoise VariantRunicBand.
	inv.equip(&"shovel", true)
	inv.apply_tool_modifiers({"tool_variant_id": &"tool_relic_shovel", "dig_power": 2.0})
	var blade := inv.fp_tool_node.get_node_or_null(^"SpadeBlade") as MeshInstance3D
	var band := inv.fp_tool_node.get_node_or_null(^"VariantRunicBand") as MeshInstance3D
	check(blade != null and (blade.material_override as StandardMaterial3D).albedo_color.r > 0.75,
		"tool_relic_shovel accents SpadeBlade to burnished antique gold-bronze")
	check(band != null and band.visible and band.mesh is ArrayMesh and not (band.mesh is PrimitiveMesh),
		"tool_relic_shovel attaches luminous sculpted jade-turquoise VariantRunicBand")
	inv.apply_tool_modifiers({"tool_variant_id": &""})
	check(band != null and not band.visible and (blade.material_override as StandardMaterial3D).albedo_color.r < 0.35,
		"clearing tool_variant restores standard iron SpadeBlade & hides VariantRunicBand")

	# 3c. Heavy Bailer: widened OakStaves & reinforced gleaming IronBands.
	inv.equip(&"bucket", true)
	inv.apply_tool_modifiers({"tool_variant_id": &"tool_heavy_bailer", "bail_power_scale": 1.40})
	var staves := inv.fp_tool_node.get_node_or_null(^"OakStaves") as Node3D
	var bands := inv.fp_tool_node.get_node_or_null(^"IronBands") as MeshInstance3D
	check(staves != null and staves.scale.is_equal_approx(Vector3(1.16, 1.06, 1.16)),
		"tool_heavy_bailer widens bucket geometry to (1.16, 1.06, 1.16)")
	check(bands != null and (bands.material_override as StandardMaterial3D).metallic >= 0.90,
		"tool_heavy_bailer enhances IronBands forged-iron gleam")
	inv.apply_tool_modifiers({"tool_variant_id": &""})
	check(staves != null and staves.scale.is_equal_approx(Vector3.ONE),
		"clearing tool_variant restores standard bucket scale")

	# 4. Zero-leak teardown releases static sculpted clod/splash caches cleanly.
	await _end()
	check(Inventory._clod_mesh == null and Inventory._splash_drop_mesh == null,
		"Inventory releases static sculpted particle mesh caches cleanly when last inventory exits tree")


# ---------------------------------------------------------------------------
# 13. Wave 23D: MapTableView Ship Cartouche, Wind-Knot Medallion & Outpost Stars
# ---------------------------------------------------------------------------

func test_map_table_ship_cartouche_wind_knots_and_outpost_markers() -> void:
	_begin()
	var prev_profile_ship := Game.profile.get_ship_name()

	# 1. Pure formatting & strict-ASCII sanitization checks.
	check_eq(MapTableView.format_ship_cartouche(""), "SV SCOUNDREL", "empty ship name falls back to SV SCOUNDREL")
	check_eq(MapTableView.format_ship_cartouche("Abyssal Dawn"), "SV ABYSSAL DAWN", "prefixes ship name with SV")
	check_eq(MapTableView.format_ship_cartouche("SV Crimson Kraken"), "SV CRIMSON KRAKEN", "avoids double SV prefix")
	check_eq(MapTableView.format_wind_medallion(10.0, 0.0), "WIND 19 kt N", "10 m/s due North formats as WIND 19 kt N")
	check_eq(MapTableView.format_wind_medallion(16.0, PI * 0.5), "WIND 31 kt E", "16 m/s due East formats as WIND 31 kt E")
	check_eq(MapTableView.format_wind_medallion(8.0, PI * 0.25), "WIND 16 kt NE", "8 m/s NE formats as WIND 16 kt NE")

	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)

	var arch := MockArchipelago.new()
	arch.islands_data = [
		{"id": &"port_scoundrel", "name": "Port Scoundrel", "kind": &"outpost", "is_outpost": true, "position": Vector3(0, 0, 0), "radius": 110.0, "discovered": true},
		{"id": &"haven_harbor", "name": "Haven Harbor", "kind": &"treasure_island", "is_outpost": true, "position": Vector3(-320, 0, -280), "radius": 90.0, "discovered": false},
		{"id": &"cutlass_cay", "name": "Cutlass Cay", "kind": &"treasure_island", "is_outpost": false, "position": Vector3(420, 0, -680), "radius": 95.0, "discovered": true},
		{"id": &"shrouded_atoll", "name": "Shrouded Atoll", "kind": &"landmark", "is_outpost": false, "position": Vector3(-540, 0, -900), "radius": 80.0, "discovered": false},
	]
	_root.add_child(arch)

	var mtv := MapTableView.new()
	check(mtv.mount_to_ship(ship), "MapTableView mounts cleanly onto sloop")
	mtv.set_archipelago_data(arch)

	# 2. Custom ship name reflects live in get_ship_cartouche_text() and chart snapshot in strict ASCII!
	ship.set_ship_name("Crimson Kraken")
	var cartouche_txt := mtv.get_ship_cartouche_text()
	check_eq(cartouche_txt, "SV CRIMSON KRAKEN",
		"ship.set_ship_name('Crimson Kraken') renders as 'SV CRIMSON KRAKEN' (got '%s')" % cartouche_txt)
	for ci in cartouche_txt.length():
		check(cartouche_txt.unicode_at(ci) < 128, "ship cartouche text is strictly ASCII")

	# 3. Live Weather wind knots & 16-point compass readout in strict ASCII!
	Weather.set_weather(0.15, 14.0, 0.7854)  # 14 m/s ~= 27 kt, NE
	mtv.refresh_now()
	await get_tree().process_frame
	var wind_txt := mtv.get_wind_medallion_text()
	check_eq(wind_txt, "WIND 27 kt NE", "wind medallion formats 14 m/s NE as WIND 27 kt NE (got '%s')" % wind_txt)
	for ci in wind_txt.length():
		check(wind_txt.unicode_at(ci) < 128, "wind medallion text is strictly ASCII")

	var snap := mtv.get_last_snapshot()
	check_eq(String(snap.get("ship_cartouche_text", "")), "SV CRIMSON KRAKEN",
		"snapshot carries live ship_cartouche_text")
	check_eq(String(snap.get("wind_medallion_text", "")), "WIND 27 kt NE",
		"snapshot carries live wind_medallion_text")

	# 4. Outpost Lighthouse Star flags & discovered vs undiscovered island states!
	var plotted := mtv.get_plotted_islands()
	check_eq(plotted.size(), 4, "all 4 test islands normalized cleanly")
	var by_id: Dictionary = {}
	for isl in plotted:
		by_id[isl["id"]] = isl
	check(bool((by_id[&"port_scoundrel"] as Dictionary).get("is_outpost", false))
		and bool((by_id[&"port_scoundrel"] as Dictionary).get("discovered", false)),
		"Port Scoundrel carries is_outpost=true and discovered=true")
	check(bool((by_id[&"haven_harbor"] as Dictionary).get("is_outpost", false))
		and bool((by_id[&"haven_harbor"] as Dictionary).get("discovered", false)),
		"explicit is_outpost=true island is preserved and marked discovered for Outpost Lighthouse Star")
	check(not bool((by_id[&"cutlass_cay"] as Dictionary).get("is_outpost", true))
		and bool((by_id[&"cutlass_cay"] as Dictionary).get("discovered", false)),
		"Cutlass Cay renders as discovered charted non-outpost island")
	check(not bool((by_id[&"shrouded_atoll"] as Dictionary).get("is_outpost", true))
		and not bool((by_id[&"shrouded_atoll"] as Dictionary).get("discovered", true)),
		"Shrouded Atoll renders as undiscovered dashed sepia silhouette")

	# 5. Off-screen far camera throttling switches SubViewport to UPDATE_DISABLED cleanly.
	var far_cam := Camera3D.new()
	_root.add_child(far_cam)
	far_cam.global_position = mtv.global_position + Vector3(0.0, 2.0, 35.0)
	far_cam.current = true
	mtv._dirty = false
	mtv._process(0.25)
	check_eq(mtv._viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"MapTableView throttles SubViewport to UPDATE_DISABLED when camera is far away")

	Game.profile.set_ship_name(prev_profile_ship)
	await _end()
	check(not is_instance_valid(mtv), "MapTableView tears down cleanly with 0 leaks")


# ---------------------------------------------------------------------------
# 14. Wave 26B: Station & Held-Tool ASCII Control Hints + [F] Prompt Ribbon
# ---------------------------------------------------------------------------

func test_hud_station_and_tool_chip_ascii_control_hints() -> void:
	_begin()
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	ship.start_anchored = true
	_root.add_child(ship)
	await physics_frames(4)

	var rig := _make_player_pawn(Vector3.ZERO)
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	captain.board(ship, Vector3(0.0, 2.02, 4.15) * _ship_scale(ship))

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, inv, cc, ship, null, null)
	await get_tree().process_frame
	hud.set_process(false)

	var check_ascii := func(label: String, text: String) -> void:
		check(text != "", "%s is non-empty" % label)
		for ci in text.length():
			check(text.unicode_at(ci) < 128, "%s is strictly ASCII ('%s')" % [label, text])

	# 1. Verify station ToolChip ASCII control hints across all sailing & deck stations.
	ship.anchor_progress = 0.5
	ship.sail_set = 0.75
	var station_checks: Array[Array] = [
		[&"helm", "Ship's Wheel", "[A/D] Steer"],
		[&"anchor", "Anchor Capstan", "[Hold W] Heave (50%)"],
		[&"sail_length", "Sail Hoist", "[S] Lower / [W] Raise (75%)"],
		[&"sail_angle", "Sail Braces", "[A/D] Angle"],
		[&"cannon", "Ship Cannon", "[WASD/Mouse] Aim"],
		[&"map_table", "Map Table", "[Space] Pin"],
		[&"bilge", "Ship's Bilge", "[Hold LMB] Bail Water"],
	]
	for spec: Array in station_checks:
		var kind: StringName = spec[0]
		var want_title: String = spec[1]
		var want_sub: String = spec[2]
		var st := ship.get_station(kind)
		check(st != null and captain.enter_station(st), "captain occupies station %s" % kind)
		hud._process(0.05)
		var t_txt := hud.get_tool_title_text()
		var m_txt := hud.get_tool_meta_text()
		check_eq(t_txt, want_title, "ToolChip title for %s" % kind)
		check(m_txt.contains(want_sub), "ToolChip meta for %s contains '%s' (got '%s')" % [kind, want_sub, m_txt])
		check_ascii.call("ToolChip title (%s)" % kind, t_txt)
		check_ascii.call("ToolChip meta (%s)" % kind, m_txt)
		captain.leave_station()

	# Verify context prompt uses [F] for station Step away fallback and preserves leading '[' prompts!
	var helm_st := ship.get_station(&"helm")
	captain.enter_station(helm_st)
	pc.focus_prompt = "Step away"
	hud._process(0.2)
	check_eq(hud.get_context_prompt_text(), "[F] Step away", "station fallback prompt renders with [F]")
	pc.focus_prompt = "[A/D] Steer | [S/RMB] Center | [F] Step Off"
	hud._process(0.2)
	check_eq(hud.get_context_prompt_text(), "[A/D] Steer | [S/RMB] Center | [F] Step Off",
		"bracketed dynamic station prompt renders verbatim")
	captain.leave_station()

	# 2. Verify held-tool ASCII control hints for bucket, planks, shovel, compass, and all other slots.
	inv.bucket_full = false
	var tool_checks: Array[Array] = [
		[&"bucket", "[LMB] Scoop Bilge / Sea"],
		[&"planks", "[LMB] Patch Breach"],
		[&"shovel", "[LMB] Dig Treasure"],
		[&"compass", "[Hold RMB] Raise & Count Paces"],
		[&"spyglass", "[RMB] Zoom | [LMB] Call Out Sighting"],
		[&"lantern", "[RMB] Raise"],
		[&"tankard", "[LMB] Drink Grog | [RMB] Cheers Toast"],
		[&"cutlass", "[RMB] Block"],
		[&"pistol", "[LMB] Fire | [RMB] Aim"],
		[&"map", "[RMB] Inspect"],
		[&"instrument", "[RMB] Swap Instrument"],
	]
	for tspec: Array in tool_checks:
		var tid: StringName = tspec[0]
		var want_hint: String = tspec[1]
		inv.equip(tid, true)
		hud._process(0.05)
		var meta_txt := hud.get_tool_meta_text()
		check(meta_txt.contains(want_hint), "ToolChip meta for %s contains '%s' (got '%s')" % [tid, want_hint, meta_txt])
		check_ascii.call("ToolChip meta (%s)" % tid, meta_txt)

	inv.equip(&"bucket", true)
	inv.bucket_full = true
	hud._process(0.05)
	check(hud.get_tool_meta_text().contains("[LMB] Throw / Bail | [RMB] Splash"),
		"full bucket shows Throw / Bail | [RMB] Splash hint (got '%s')" % hud.get_tool_meta_text())

	# 3. Verify SailingTrimPill stays 100% green alongside updated ToolChip!
	captain.enter_station(helm_st)
	ship.anchor_down = true
	hud._process(0.05)
	check(hud.get_sailing_telemetry_text().ends_with("kt  |  ANCHORED"), "SailingTrimPill ANCHORED intact")
	ship.anchor_down = false
	ship.sail_set = 0.0
	hud._process(0.05)
	check(hud.get_sailing_telemetry_text().ends_with("kt  |  SAILS FURLED"), "SailingTrimPill SAILS FURLED intact")
	ship.sail_set = 0.9
	ship.sail_trim = ship.ideal_sail_trim()
	hud._process(0.05)
	check(hud.get_sailing_telemetry_text().ends_with("kt  |  FULL WIND"), "SailingTrimPill FULL WIND intact")
	captain.leave_station()

	hud.queue_free()
	await physics_frames(2)
	await _end()


# ---------------------------------------------------------------------------
# 15. Wave 27B: Tool Object-Space Triplanar PBR, Compass Paces, Toast & Splash
# ---------------------------------------------------------------------------

func test_wave27_tool_pbr_compass_paces_toast_and_bucket_splash() -> void:
	_begin()
	ToolMeshes.clear_shared_cache()

	# 1. Verify object-space triplanar PBR normal & roughness bindings across iconic held tools
	#    while keeping printed dials, maps, and foam razor-crisp!
	var check_pbr := func(tool_node: Node3D, mesh_path: NodePath, label: String,
			expect_pbr: bool, expect_rough: bool = true) -> StandardMaterial3D:
		var mi := tool_node.get_node_or_null(mesh_path) as MeshInstance3D
		check(mi != null, "%s exists" % label)
		var mat := mi.material_override as StandardMaterial3D if mi != null else null
		check(mat != null, "%s has StandardMaterial3D" % label)
		if mat == null:
			return null
		if expect_pbr:
			check(mat.uv1_triplanar and not mat.uv1_world_triplanar,
				"%s uses object-space triplanar (uv1_triplanar=true, world=false)" % label)
			check(mat.normal_enabled and mat.normal_texture != null,
				"%s binds PBR normal_texture" % label)
			if expect_rough:
				check(mat.roughness_texture != null, "%s binds PBR roughness_texture" % label)
		else:
			check(not mat.normal_enabled and mat.normal_texture == null,
				"%s stays razor-crisp without normal override" % label)
			check(not mat.uv1_triplanar, "%s disables triplanar override" % label)
		return mat

	var cutlass := ToolMeshes.build_tool(&"cutlass")
	var cutlass_blade_mat: StandardMaterial3D = check_pbr.call(cutlass, ^"Blade", "Cutlass.Blade", true)
	check_pbr.call(cutlass, ^"Grip", "Cutlass.Grip", true)
	var cutlass_hilt_mat: StandardMaterial3D = check_pbr.call(cutlass, ^"BrassHilt", "Cutlass.BrassHilt", true)

	var pistol := ToolMeshes.build_tool(&"pistol")
	check_pbr.call(pistol, ^"Stock", "Pistol.Stock", true)
	check_pbr.call(pistol, ^"BarrelAndLock", "Pistol.BarrelAndLock", true)
	check_pbr.call(pistol, ^"BrassTrim", "Pistol.BrassTrim", true)

	var compass := ToolMeshes.build_tool(&"compass")
	check_pbr.call(compass, ^"BrassCase", "Compass.BrassCase", true)
	check_pbr.call(compass, ^"DialFace", "Compass.DialFace", false)
	check_pbr.call(compass, ^"DialTicks", "Compass.DialTicks", false)
	check_pbr.call(compass, ^"NorthMarker", "Compass.NorthMarker", false)

	var lantern := ToolMeshes.build_tool(&"lantern")
	var lantern_brass_mat: StandardMaterial3D = check_pbr.call(lantern, ^"BrassCage", "Lantern.BrassCage", true)
	check_pbr.call(lantern, ^"GlassCore", "Lantern.GlassCore", false)

	var shovel := ToolMeshes.build_tool(&"shovel")
	check_pbr.call(shovel, ^"TimberHandle", "Shovel.TimberHandle", true)
	var shovel_blade_mat: StandardMaterial3D = check_pbr.call(shovel, ^"SpadeBlade", "Shovel.SpadeBlade", true)

	var bucket := ToolMeshes.build_tool(&"bucket")
	check_pbr.call(bucket, ^"OakStaves", "Bucket.OakStaves", true)
	check_pbr.call(bucket, ^"IronBands", "Bucket.IronBands", true)

	var tankard := ToolMeshes.build_tool(&"tankard")
	check_pbr.call(tankard, ^"OakMug", "Tankard.OakMug", true)
	check_pbr.call(tankard, ^"PewterBands", "Tankard.PewterBands", true)
	check_pbr.call(tankard, ^"FoamTop", "Tankard.FoamTop", false)

	var map_tool := ToolMeshes.build_tool(&"map")
	check_pbr.call(map_tool, ^"ScrollRollers", "Map.ScrollRollers", true)
	check_pbr.call(map_tool, ^"MapSurface", "Map.MapSurface", false)

	var planks := ToolMeshes.build_tool(&"planks")
	check_pbr.call(planks, ^"RopeLashing", "Planks.RopeLashing", true)

	var concertina := ToolMeshes.build_tool(&"instrument")
	check_pbr.call(concertina, ^"Bellows", "Concertina.Bellows", true, false)

	# Verify shared VRAM texture identity across tools using the same PBR family.
	check(cutlass_hilt_mat != null and lantern_brass_mat != null \
		and cutlass_hilt_mat.normal_texture == lantern_brass_mat.normal_texture,
		"Cutlass and Lantern share identical cached ship_brass_normal Texture2D")
	check(cutlass_blade_mat != null and shovel_blade_mat != null \
		and cutlass_blade_mat.normal_texture == shovel_blade_mat.normal_texture,
		"Cutlass and Shovel share identical cached ship_iron_normal Texture2D")

	for tn: Node3D in [cutlass, pistol, compass, lantern, shovel, bucket, tankard, map_tool, planks, concertina]:
		tn.free()

	# 2. Compass [RMB] step-counting pace mode: counts 0 -> 3+ paces over ~3.2 m and resets cleanly on release!
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60.0, 1.0, 60.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.collision_layer = 1
	_root.add_child(floor_body)

	var rig := _make_player_pawn(Vector3(0.0, 0.2, 0.0))
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, inv, cc, null, null, null)
	await physics_frames(8)

	check(captain.is_grounded(), "captain stands grounded on test deck floor")
	captain.look_yaw = -PI * 0.5  # facing due East (+X)
	inv.equip(&"compass", true)
	hud._process(0.05)
	check(hud.get_tool_meta_text().contains("[Hold RMB] Raise & Count Paces"),
		"lowered compass shows pace-count RMB hint (got '%s')" % hud.get_tool_meta_text())

	var pace_events: Array[Dictionary] = []
	inv.compass_pace_counted.connect(func(paces: int, heading_str: String) -> void:
		pace_events.append({"paces": paces, "heading": heading_str})
	)

	inv.set_secondary_held(true)
	check_eq(inv.get_compass_paces(), 0, "raising compass resets compass_paces to 0")
	check_eq(inv.get_compass_heading_label(), "E", "compass heading reads E when facing +X")

	var start_xz := Vector2(captain.global_position.x, captain.global_position.z)
	captain.wish_dir = Vector3(1.0, 0.0, 0.0)
	var walked := 0.0
	for _step in 120:
		await physics_frames(1)
		inv._tick_compass(1.0 / 60.0)
		walked = Vector2(captain.global_position.x, captain.global_position.z).distance_to(start_xz)
		if walked >= 3.25:
			break
	captain.wish_dir = Vector3.ZERO

	check(walked >= 3.1, "captain walked ~3.2 m (got %.2f m)" % walked)
	check(inv.get_compass_paces() >= 3,
		"compass pace counter incremented 0 -> 3+ over ~3.2 m (got %d)" % inv.get_compass_paces())
	check(pace_events.size() >= 3, "compass_pace_counted emitted >= 3 times (got %d)" % pace_events.size())
	if not pace_events.is_empty():
		check_eq(String(pace_events[0]["heading"]), "E", "compass_pace_counted reports E heading")

	hud._process(0.05)
	var pace_hud := hud.get_tool_meta_text()
	check(pace_hud.contains("Compass | %d paces (E)" % inv.get_compass_paces()),
		"HUD displays live dynamic pace readout (got '%s')" % pace_hud)
	for ci in pace_hud.length():
		check(pace_hud.unicode_at(ci) < 128, "HUD compass pace text is strictly ASCII")

	inv.set_secondary_held(false)
	check_eq(inv.get_compass_paces(), 0, "releasing RMB resets compass_paces cleanly to 0")

	# 3. Tankard [RMB] pirate toast emits grog_toast_raised and prompts nearby CrewBrain.acknowledge_captain_toast()!
	var barnaby_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(barnaby_pawn)
	barnaby_pawn.global_position = captain.global_position + Vector3(2.8, 0.0, 0.0)
	var barnaby := CrewBrain.new()
	barnaby.setup(null, captain, &"helmsman")
	barnaby_pawn.add_child(barnaby)

	var maren_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(maren_pawn)
	maren_pawn.global_position = captain.global_position + Vector3(-9.0, 0.0, 0.0)
	var maren := CrewBrain.new()
	maren.setup(null, captain, &"lookout")
	maren_pawn.add_child(maren)

	var pip_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pip_pawn)
	pip_pawn.global_position = captain.global_position + Vector3(0.0, 0.0, 11.0)
	var pip := CrewBrain.new()
	pip.setup(null, captain, &"carpenter")
	pip_pawn.add_child(pip)
	await physics_frames(2)

	var toast_count := [0]
	inv.grog_toast_raised.connect(func() -> void: toast_count[0] += 1)
	var crew_toasts: Array[Dictionary] = []
	var crew_splashes: Array[Dictionary] = []
	for br: CrewBrain in [barnaby, maren, pip]:
		br.callout_spoken.connect(func(sp: String, txt: String, cat: StringName) -> void:
			if cat == &"toast_ack":
				crew_toasts.append({"speaker": sp, "text": txt})
			elif cat == &"splashed":
				crew_splashes.append({"speaker": sp, "text": txt})
		)
	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	inv.equip(&"tankard", true)
	inv.set_secondary_held(true)
	check_eq(toast_count[0], 1, "Tankard [RMB] emits grog_toast_raised once")
	check(notices.has("Captain raises a tankard: To fair winds and fat coffers!"),
		"Tankard toast posts cheerful Captain notice")
	check_eq(crew_toasts.size(), 1, "closest living CrewBrain within 14 m acknowledges captain toast")
	if crew_toasts.size() == 1:
		check_eq(String(crew_toasts[0]["speaker"]), "Barnaby", "closest crewmate Barnaby cheers back")
		var ack_txt := String(crew_toasts[0]["text"])
		for ci in ack_txt.length():
			check(ack_txt.unicode_at(ci) < 128, "Barnaby toast_ack line is strictly ASCII")

	# Verify 4.0 s anti-spam cooldown on Tankard toast and all 3 persona toast_ack lines.
	inv.set_secondary_held(false)
	check(not inv.raise_grog_toast(), "Tankard toast obeys 4.0 s cooldown")
	check(maren.acknowledge_captain_toast(), "Maren responds to captain toast")
	check(pip.acknowledge_captain_toast(), "Pip responds to captain toast")
	check_eq(crew_toasts.size(), 3, "all three personas emit strict-ASCII toast_ack lines")
	for entry_t: Dictionary in crew_toasts:
		var line_t := String(entry_t["text"])
		for ci in line_t.length():
			check(line_t.unicode_at(ci) < 128, "toast_ack line is strictly ASCII ('%s')" % line_t)

	# 4. Bucket [RMB] forward water splash empties bucket_full and splashes crewmate ahead!
	captain.look_yaw = -PI * 0.5  # facing +X straight toward Barnaby (2.8 m ahead!)
	inv.equip(&"bucket", true)
	inv.bucket_full = true
	ToolMeshes.set_bucket_full(inv.fp_tool_node, true)
	var bucket_events: Array[bool] = []
	inv.bucket_changed.connect(func(full: bool) -> void: bucket_events.append(full))

	inv.set_secondary_held(true)
	check(not inv.bucket_full, "Bucket [RMB] forward splash empties bucket_full")
	check(bucket_events.has(false), "Bucket [RMB] forward splash emits bucket_changed(false)")
	var wf := inv.fp_tool_node.get_node_or_null(^"WaterFill") as Node3D if inv.fp_tool_node != null else null
	check(wf != null and not wf.visible, "Bucket WaterFill mesh hides cleanly after RMB forward splash")
	check_eq(crew_splashes.size(), 1, "crewmate within 4.5 m in front reacts to water splash")
	if crew_splashes.size() == 1:
		check_eq(String(crew_splashes[0]["speaker"]), "Barnaby", "Barnaby reacts to forward bucket splash")
	inv.set_secondary_held(false)

	# Also verify Maren & Pip splash reactions & strict ASCII dialogue lines.
	check(maren.react_to_water_splash(), "Maren reacts to water splash")
	check(pip.react_to_water_splash(), "Pip reacts to water splash")
	check_eq(crew_splashes.size(), 3, "all three personas emit splashed barks")
	for entry_s: Dictionary in crew_splashes:
		var line_s := String(entry_s["text"])
		for ci in line_s.length():
			check(line_s.unicode_at(ci) < 128, "splashed bark is strictly ASCII ('%s')" % line_s)

	Game.notice.disconnect(notice_cb)
	hud.queue_free()
	await physics_frames(2)
	await _end()

	# 5. Clean ToolMeshes.clear_shared_cache() teardown!
	ToolMeshes.clear_shared_cache()
	check(ToolMeshes._pbr_tex_cache.is_empty(), "ToolMeshes.clear_shared_cache() clears PBR texture cache cleanly")


# ---------------------------------------------------------------------------
# 16. Wave 29A: Tactical Map-Pin Compass Bearing, Toggle & Rowboat Oars HUD Hint
# ---------------------------------------------------------------------------

class MockRowboatOarsStation:
	extends Node3D
	var kind: StringName = &"rowboat_oars"


func test_wave29_compass_map_pin_bearing_toggle_and_hud_hint() -> void:
	_begin()
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)
	ship.global_position = Vector3.ZERO

	var mtv := MapTableView.new()
	check(mtv.mount_to_ship(ship), "MapTableView mounts cleanly onto sloop")
	await get_tree().process_frame

	var rig := _make_player_pawn(Vector3.ZERO)
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	captain.board(ship, ship.ship_point(Vector3(0.0, 1.12, 0.2)))
	captain.look_yaw = 0.0  # Facing due North (-Z)
	await physics_frames(4)

	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, inv, cc, ship, null, null)
	await get_tree().process_frame
	hud.set_process(false)

	var mode_events: Array[bool] = []
	inv.compass_mode_changed.connect(func(pin_mode: bool) -> void: mode_events.append(pin_mode))
	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	# 1. No active pin: has_active_pin() == false, get_active_pin() == ZERO, toggle returns false.
	check(not mtv.has_active_pin(), "MapTableView starts without active chart pin")
	check(mtv.get_active_pin().is_equal_approx(Vector3.ZERO), "get_active_pin() returns Vector3.ZERO when empty")
	inv.equip(&"compass", true)
	check_eq(inv.get_compass_pin_summary(), "", "get_compass_pin_summary() is empty when no pin exists")
	check(not bool(inv.use_primary()), "compass LMB without active pin returns false")
	check(not inv.compass_pin_mode, "compass_pin_mode stays false without pin")
	hud._process(0.05)
	check(hud.get_tool_meta_text().contains("[Hold RMB] Raise & Count Paces"),
		"compass HUD without pin preserves classic pace hint (got '%s')" % hud.get_tool_meta_text())

	# 2. Place NNE chart pin (~310 m from captain) -> automatic MapTableView resolution + strict-ASCII summary!
	var pin_nne := captain.global_position + Vector3(119.0, 0.0, -286.0)
	mtv.place_marker(pin_nne)
	check(mtv.has_active_pin(), "has_active_pin() returns true after place_marker")
	check(mtv.get_active_pin().is_equal_approx(pin_nne), "get_active_pin() returns active marker world pos")
	var pin_sum := inv.get_compass_pin_summary()
	check_eq(pin_sum, "Pin: NNE 310 m", "get_compass_pin_summary() normalizes spacing cleanly (got '%s')" % pin_sum)

	hud._process(0.05)
	var meta_north := hud.get_tool_meta_text()
	check_eq(meta_north, "Compass | Pin: NNE 310 m | [LMB] Track Pin | [RMB] Pace",
		"HUD shows True North compass hint with live NNE pin bearing (got '%s')" % meta_north)

	# 3. Place newer due-East pin -> newest pin wins, and LMB locks compass needle toward East!
	var pin_east := captain.global_position + Vector3(280.0, 0.0, 0.0)
	mtv.place_marker(pin_east)
	check(mtv.get_active_pin().is_equal_approx(pin_east), "get_active_pin() returns newest placed pin")
	check_eq(inv.get_compass_pin_summary(), "Pin: E 280 m", "pin summary updates to newest East pin")

	# Settle compass needle on True North first while facing North (-Z).
	for _i in 60:
		inv._tick_compass(1.0 / 60.0)
	var compass_node := inv.get_active_tool_node()
	var needle := compass_node.get_node_or_null(^"Needle") as Node3D if compass_node != null else null
	check(needle != null, "equipped compass has live Needle node")
	var needle_north := needle.rotation.y

	# Press primary (LMB) on compass -> locks onto East chart pin!
	check(bool(inv.use_primary()), "compass use_primary() toggles pin lock on when pin exists")
	check(inv.compass_pin_mode, "compass_pin_mode becomes true")
	check_eq(mode_events.size(), 1, "compass_mode_changed emitted once")
	check_eq(mode_events[0], true, "compass_mode_changed emitted true")
	check(notices.has("Compass locked onto chart pin!"), "locking pin posts strict-ASCII notice")

	# Verify HUD updates immediately via compass_mode_changed signal!
	var meta_pin := hud.get_tool_meta_text()
	check_eq(meta_pin, "Compass [Pin] | Pin: E 280 m | [LMB] True North | [RMB] Pace",
		"HUD immediately updates to Compass [Pin] tracking mode (got '%s')" % meta_pin)

	# Advance damped magnetic needle physics -> swings smoothly ~90 deg right toward East!
	for _i in 90:
		inv._tick_compass(1.0 / 60.0)
	var needle_east := needle.rotation.y
	var swing_rad := absf(wrapf(needle_east - needle_north, -PI, PI))
	check(swing_rad > 1.15 and swing_rad < 1.95,
		"magnetic needle swings ~90 deg toward East pin (delta=%.2f rad)" % swing_rad)

	# Verify pacing HUD format while pin is active ("Pace %d %s").
	inv.set_secondary_held(true)
	hud._process(0.05)
	var meta_pace := hud.get_tool_meta_text()
	check(meta_pace.contains("Compass [Pin]") and meta_pace.contains("Pin: E 280 m") \
		and meta_pace.contains("Pace 0 ") and meta_pace.contains("[LMB] True North"),
		"pacing with active pin includes Pace readout and Pin mode (got '%s')" % meta_pace)
	inv.set_secondary_held(false)

	# 4. Second LMB toggles back to True North and swings needle back!
	check(not bool(inv.use_primary()), "second compass LMB returns false (True North mode)")
	check(not inv.compass_pin_mode, "compass_pin_mode returns to false")
	check_eq(mode_events.size(), 2, "compass_mode_changed emitted second time")
	check_eq(mode_events[1], false, "compass_mode_changed emitted false")
	check(notices.has("Compass returned to True North."), "returning to True North posts notice")
	for _i in 90:
		inv._tick_compass(1.0 / 60.0)
	var back_err := absf(wrapf(needle.rotation.y - needle_north, -PI, PI))
	check(back_err < 0.25, "needle settles back to True North (err=%.2f rad)" % back_err)

	# 5. Clearing chart markers while in Pin Lock auto-resets compass_pin_mode cleanly!
	check(inv.toggle_compass_pin_mode(), "re-engage pin lock before clear_markers")
	check(inv.compass_pin_mode, "compass_pin_mode is true before clearing markers")
	mtv.clear_markers()
	inv._tick_compass(1.0 / 60.0)
	check(not inv.compass_pin_mode, "clearing markers auto-resets compass_pin_mode to false")
	check_eq(mode_events[mode_events.size() - 1], false, "auto-reset emits compass_mode_changed(false)")
	check_eq(inv.get_compass_pin_summary(), "", "pin summary clears to empty after clear_markers")
	hud._process(0.05)
	check(hud.get_tool_meta_text().contains("[Hold RMB] Raise & Count Paces"),
		"HUD reverts cleanly to no-pin pace hint after markers cleared")

	# 6. Verify Rowboat Oars station hint (`&"rowboat_oars"`) in GameHUD!
	var mock_oars := MockRowboatOarsStation.new()
	_root.add_child(mock_oars)
	captain.station = mock_oars
	hud._process(0.05)
	var oars_title := hud.get_tool_title_text()
	var oars_meta := hud.get_tool_meta_text()
	check_eq(oars_title, "Rowboat Oars", "rowboat_oars station title matches")
	check_eq(oars_meta, "[A/D] Stroke Port/Stbd | [W] Surge | [S] Brake | [F] Stand",
		"rowboat_oars station meta hint matches")
	captain.station = null

	for txt_chk: String in [pin_sum, meta_north, meta_pin, meta_pace, oars_title, oars_meta]:
		for ci in txt_chk.length():
			check(txt_chk.unicode_at(ci) < 128, "HUD/compass text is strictly ASCII ('%s')" % txt_chk)

	Game.notice.disconnect(notice_cb)
	hud.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(hud), "GameHUD frees cleanly on teardown")
	check_eq(inv.compass_mode_changed.get_connections().size(), 1,
		"GameHUD disconnects compass_mode_changed cleanly on teardown (only test listener remains)")
	await _end()


# ---------------------------------------------------------------------------
# 17. Wave 36B: Cinematic LocationBanner & Sculpted Brass SpeakingTrumpet Hail
# ---------------------------------------------------------------------------

class MockLocationIsland:
	extends Node
	var archetype: StringName = &"treasure_peak"
	var is_outpost: bool = false
	var radius: float = 80.0


func test_wave36_location_banner_and_speaking_trumpet_hail() -> void:
	_begin()
	ToolMeshes.clear_shared_cache()

	var check_ascii := func(label: String, text: String) -> void:
		check(text != "", "%s is non-empty" % label)
		for ci in text.length():
			check(text.unicode_at(ci) < 128, "%s is strictly ASCII ('%s')" % [label, text])

	# 1. LocationBanner: non-blocking layer 14, all 3 styles, smooth fade-in/hold/fade-out,
	#    queue + consecutive title deduplication, island subtitles/styles, strict ASCII.
	var banner := LocationBanner.new()
	_root.add_child(banner)
	banner.set_process(false)
	await get_tree().process_frame

	check_eq(banner.layer, 14, "LocationBanner renders on CanvasLayer 14")
	var banner_controls := banner.find_children("*", "Control", true, false)
	check(banner_controls.size() >= 2, "LocationBanner builds root and _BannerArt controls")
	for c_node in banner_controls:
		var ctrl := c_node as Control
		check_eq(ctrl.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"LocationBanner control '%s' uses MOUSE_FILTER_IGNORE" % ctrl.name)

	var shown_events: Array[Dictionary] = []
	banner.banner_shown.connect(func(t: String, sub: String, st: StringName) -> void:
		shown_events.append({"title": t, "subtitle": sub, "style": st})
	)

	# Show threat banner and step through fade-in -> hold -> fade-out!
	check(banner.show_location("Sovereign's Bastion", "Grand Citadel -- Tier IV Sea Fortress", &"threat", 3.2),
		"show_location displays initial threat banner")
	check(banner.is_banner_active(), "banner is active immediately after show_location")
	check_eq(banner.get_current_title(), "SOVEREIGN'S BASTION", "banner title renders uppercase")
	check_eq(banner.get_current_subtitle(), "Grand Citadel -- Tier IV Sea Fortress", "banner subtitle matches")
	check_eq(banner.get_current_style(), &"threat", "banner style matches &'threat'")
	check_eq(shown_events.size(), 1, "banner_shown emitted once for initial banner")

	# Fade-in midpoint (0.225 s of 0.45 s).
	banner.step_banner(0.225)
	check_eq(banner.get_banner_phase(), &"fade_in", "banner enters fade_in phase")
	check(banner.get_current_alpha() > 0.25 and banner.get_current_alpha() < 0.80,
		"fade_in alpha rises smoothly (got %.2f)" % banner.get_current_alpha())
	await get_tree().process_frame  # exercise _BannerArt._draw() in &"threat" style

	# Hold phase (total 0.70 s, inside 0.45..3.65 s).
	banner.step_banner(0.475)
	check_eq(banner.get_banner_phase(), &"hold", "banner enters crisp hold phase")
	check_near(banner.get_current_alpha(), 1.0, 0.001, "hold alpha equals 1.0")

	# Deduplication & 2-slot queue cap while active.
	check(not banner.show_location("sovereign's bastion", "Duplicate", &"threat", 1.0),
		"consecutive identical title is deduplicated case-insensitively")
	check(banner.show_location("Port Scoundrel", "Outpost Harbour -- Safe Anchorage", &"outpost", 1.0),
		"queues first pending banner (&'outpost')")
	check_eq(banner.get_queued_count(), 1, "queued count is 1")
	check(not banner.show_location("PORT SCOUNDREL", "Duplicate Tail", &"outpost", 1.0),
		"deduplicates consecutive identical title against queue tail")
	check(banner.show_location("Cutlass Cay", "Uncharted Treasure Cay", &"island", 1.0),
		"queues second pending banner (&'island')")
	check_eq(banner.get_queued_count(), 2, "queued count is 2")
	check(not banner.show_location("Cinder Crag", "Active Volcanic Caldera", &"threat", 1.0),
		"rejects 3rd pending banner when 2-slot queue is full")

	# Fade-out phase (total 3.975 s, midpoint of 3.65..4.30 s).
	banner.step_banner(3.275)
	check_eq(banner.get_banner_phase(), &"fade_out", "banner enters graceful fade_out phase")
	check(banner.get_current_alpha() > 0.15 and banner.get_current_alpha() < 0.85,
		"fade_out alpha decays smoothly (got %.2f)" % banner.get_current_alpha())

	# Complete first banner -> seamlessly advances to queued &'outpost' banner!
	banner.step_banner(0.50)
	check(banner.is_banner_active(), "banner stays active advancing to queued outpost")
	check_eq(banner.get_current_title(), "PORT SCOUNDREL", "advances to queued Port Scoundrel")
	check_eq(banner.get_current_style(), &"outpost", "outpost style active")
	check_eq(banner.get_queued_count(), 1, "queue decrements to 1")
	banner.step_banner(0.55)
	await get_tree().process_frame  # exercise _BannerArt._draw() in &"outpost" style

	# Finish outpost banner -> advances to queued &'island' banner!
	banner.step_banner(1.75)
	check(banner.is_banner_active(), "banner stays active advancing to queued island")
	check_eq(banner.get_current_title(), "CUTLASS CAY", "advances to queued Cutlass Cay")
	check_eq(banner.get_current_style(), &"island", "island style active")
	check_eq(banner.get_queued_count(), 0, "queue is now empty")
	banner.step_banner(0.55)
	await get_tree().process_frame  # exercise _BannerArt._draw() in &"island" style

	# Finish final banner -> cleanly returns to idle!
	banner.step_banner(1.75)
	check(not banner.is_banner_active(), "banner becomes inactive after final fade-out")
	check_eq(banner.get_current_title(), "", "idle banner title is empty")
	check_eq(shown_events.size(), 3, "banner_shown emitted once for each of the 3 banners")

	# Verify strict-ASCII sanitization (< 128) on non-ASCII typography & glyphs.
	var dirty_title := "Skull" + char(0x2014) + "Bluff " + char(0x2019) + "Tis" + char(0x2605)
	var dirty_sub := "Cursed" + char(0x2013) + "Isle " + char(0x2026) + char(0x00E9)
	check(banner.show_location(dirty_title, dirty_sub, &"island", 1.0), "sanitized banner shows cleanly")
	check_ascii.call("sanitized banner title", banner.get_current_title())
	check_ascii.call("sanitized banner subtitle", banner.get_current_subtitle())
	banner.clear_banner()
	check(not banner.is_banner_active() and banner.get_queued_count() == 0, "clear_banner resets cleanly")

	# Verify format_island_subtitle & style_for_island across all 14 archetypes!
	var arch_checks: Array[Array] = [
		[&"outpost", true, 82.0, &"outpost", "Outpost"],
		[&"grand_outpost", true, 166.0, &"outpost", "Outpost"],
		[&"volcano_crag", false, 176.0, &"threat", "Volcanic"],
		[&"fort_rock", false, 92.0, &"threat", "Bastion"],
		[&"grand_citadel", false, 182.0, &"threat", "Citadel"],
		[&"smuggler_cove", false, 96.0, &"island", "Smuggler"],
		[&"twin_spires", false, 138.0, &"island", "Twin-Spire"],
		[&"crescent_lagoon", false, 134.0, &"island", "Lagoon"],
		[&"palm_atoll", false, 70.0, &"island", "Atoll"],
		[&"wreck_shoal", false, 46.0, &"island", "Shipwreck"],
		[&"skull_bluff", false, 124.0, &"island", "Skull"],
		[&"sea_arch", false, 82.0, &"island", "Sea Arch"],
		[&"sea_stack", false, 38.0, &"island", "Sea-Stack"],
		[&"treasure_peak", false, 54.0, &"island", "Treasure"],
	]
	for spec: Array in arch_checks:
		var mock_isl := MockLocationIsland.new()
		mock_isl.archetype = spec[0]
		mock_isl.is_outpost = bool(spec[1])
		mock_isl.radius = float(spec[2])
		var want_style: StringName = spec[3]
		var want_word: String = spec[4]
		var sub := LocationBanner.format_island_subtitle(mock_isl)
		var st := LocationBanner.style_for_island(mock_isl)
		check_eq(st, want_style, "style_for_island(%s) == %s" % [mock_isl.archetype, want_style])
		check(sub.contains(want_word), "subtitle for %s contains '%s' (got '%s')" % [mock_isl.archetype, want_word, sub])
		check_ascii.call("subtitle(%s)" % mock_isl.archetype, sub)
		mock_isl.free()

	# 2. Sculpted Brass SpeakingTrumpet mesh verification (>= 380 tris, 0 PrimitiveMeshes,
	#    0 extra VRAM, uv1_world_triplanar == false, vertex_color_is_srgb == true).
	check_eq(ToolMeshes.get_tool_ids().size(), 11, "canonical ALL_TOOLS count stays 11")
	check_eq(ToolMeshes.get_display_name(&"speaking_trumpet"), "Speaking Trumpet",
		"speaking_trumpet has proper display name")

	var lantern_ref := ToolMeshes.build_tool(&"lantern")
	var cutlass_ref := ToolMeshes.build_tool(&"cutlass")
	var cache_keys_before := ToolMeshes._pbr_tex_cache.size()
	var trumpet := ToolMeshes.build_tool(&"speaking_trumpet")
	check(trumpet != null, "ToolMeshes.build_tool(&'speaking_trumpet') builds cleanly")

	var trumpet_meshes := trumpet.find_children("*", "MeshInstance3D", true, false)
	check(trumpet_meshes.size() >= 4, "SpeakingTrumpet has sculpted multi-part MeshInstance3D hierarchy")
	var trumpet_tris := 0
	var primitive_count := 0
	var trumpet_brass_norm: Texture2D = null
	var trumpet_leather_norm: Texture2D = null
	for m_node in trumpet_meshes:
		var mi := m_node as MeshInstance3D
		check(mi.mesh != null, "SpeakingTrumpet mesh '%s' non-null" % mi.name)
		if mi.mesh is PrimitiveMesh:
			primitive_count += 1
		check(mi.mesh is ArrayMesh, "SpeakingTrumpet mesh '%s' is sculpted ArrayMesh" % mi.name)
		if mi.mesh != null:
			trumpet_tris += int(roundf(float(mi.mesh.get_faces().size()) / 3.0))
		var mat := mi.material_override as StandardMaterial3D
		check(mat != null, "SpeakingTrumpet mesh '%s' has StandardMaterial3D" % mi.name)
		if mat != null:
			check(not mat.uv1_world_triplanar,
				"SpeakingTrumpet '%s' has uv1_world_triplanar == false" % mi.name)
			check(mat.vertex_color_is_srgb,
				"SpeakingTrumpet '%s' has vertex_color_is_srgb == true" % mi.name)
			if mi.name == "BrassHorn":
				trumpet_brass_norm = mat.normal_texture
			elif mi.name == "LeatherHandle":
				trumpet_leather_norm = mat.normal_texture

	check(trumpet_tris >= 380, "SpeakingTrumpet has >= 380 sculpted tris (got %d)" % trumpet_tris)
	check_eq(primitive_count, 0, "SpeakingTrumpet uses 0 PrimitiveMeshes")
	var lantern_brass_mi := lantern_ref.get_node_or_null(^"BrassCage") as MeshInstance3D
	var cutlass_grip_mi := cutlass_ref.get_node_or_null(^"Grip") as MeshInstance3D
	var lantern_brass_norm := (lantern_brass_mi.material_override as StandardMaterial3D).normal_texture if lantern_brass_mi != null else null
	var cutlass_grip_norm := (cutlass_grip_mi.material_override as StandardMaterial3D).normal_texture if cutlass_grip_mi != null else null
	check(trumpet_brass_norm != null and trumpet_brass_norm == lantern_brass_norm,
		"SpeakingTrumpet brass shares zero-extra-VRAM cached ship_brass_normal Texture2D")
	check(trumpet_leather_norm != null and trumpet_leather_norm == cutlass_grip_norm,
		"SpeakingTrumpet leather shares zero-extra-VRAM cached ship_oak_normal Texture2D")
	check(ToolMeshes._pbr_tex_cache.size() <= cache_keys_before + 3,
		"SpeakingTrumpet reuses existing resident ship PBR textures with zero custom VRAM")
	print("Wave 36B SpeakingTrumpet sculpted triangles: %d" % trumpet_tris)
	trumpet.free()
	lantern_ref.free()
	cutlass_ref.free()

	# 3. Inventory.hail_with_speaking_trumpet() + CrewBrain.receive_trumpet_hail() + CrewDialogue!
	var ship := SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)
	ship.global_position = Vector3.ZERO

	var rig := _make_player_pawn(Vector3(0.0, 1.0, 0.0))
	var captain: Pawn = rig["pawn"]
	var inv: Inventory = rig["inv"]

	# Ashore crewmate #1 (Barnaby) at 85 m (<= 110 m hail radius), currently on &"follow".
	var barnaby_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(barnaby_pawn)
	barnaby_pawn.global_position = Vector3(85.0, 0.0, 0.0)
	var barnaby := CrewBrain.new()
	barnaby.setup(ship, captain, &"helmsman")
	barnaby_pawn.add_child(barnaby)

	# Far crewmate #2 (Maren) at 145 m (> 135 m & > 110 m), currently on &"follow".
	var maren_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(maren_pawn)
	maren_pawn.global_position = Vector3(145.0, 0.0, 0.0)
	var maren := CrewBrain.new()
	maren.setup(ship, captain, &"lookout")
	maren_pawn.add_child(maren)

	# Third persona crewmate (Pip) placed far initially (160 m), then tested in range for persona coverage.
	var pip_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pip_pawn)
	pip_pawn.global_position = Vector3(-160.0, 0.0, 0.0)
	var pip := CrewBrain.new()
	pip.setup(ship, captain, &"carpenter")
	pip_pawn.add_child(pip)
	await physics_frames(2)

	barnaby.current_order = &"follow"
	maren.current_order = &"follow"
	pip.current_order = &"follow"

	var hail_events: Array[Dictionary] = []
	inv.speaking_trumpet_hailed.connect(func(origin: Vector3, radius: float, acked: int) -> void:
		hail_events.append({"origin": origin, "radius": radius, "acked": acked})
	)
	var ack_lines: Array[Dictionary] = []
	for br: CrewBrain in [barnaby, maren, pip]:
		br.callout_spoken.connect(func(sp: String, txt: String, cat: StringName) -> void:
			if cat == &"trumpet_hail_ack":
				ack_lines.append({"speaker": sp, "text": txt})
		)

	var warned_before := Audio._warned.size()
	var hail_res := inv.hail_with_speaking_trumpet()
	check(bool(hail_res.get("ok", false)), "hail_with_speaking_trumpet returns ok=true")
	check_near(float(hail_res.get("radius", 0.0)), 110.0, 0.01, "hail radius is 110 m")
	check_eq(int(hail_res.get("crew_acked", -1)), 1, "exactly 1 crewmate within 110 m acknowledged hail")
	check_eq(hail_events.size(), 1, "speaking_trumpet_hailed signal emitted once")
	if hail_events.size() == 1:
		check_near(float(hail_events[0]["radius"]), 110.0, 0.01, "signal reports 110 m hail radius")
		check_eq(int(hail_events[0]["acked"]), 1, "signal reports 1 crewmate acknowledged")

	check_eq(barnaby.current_order, &"return_ship", "ashore Barnaby at 85 m recalled to &'return_ship'")
	check_eq(maren.current_order, &"follow", "distant Maren at 145 m ignored by 110 m hail")
	check_eq(pip.current_order, &"follow", "distant Pip at 160 m ignored by 110 m hail")
	check_eq(ack_lines.size(), 1, "only Barnaby spoke trumpet_hail_ack")
	if ack_lines.size() == 1:
		check_eq(String(ack_lines[0]["speaker"]), "Barnaby", "Barnaby acknowledged trumpet hail")
		check_ascii.call("Barnaby trumpet_hail_ack", String(ack_lines[0]["text"]))

	# Verify Audio generated zero unknown-sound warnings!
	check_eq(Audio._warned.size(), warned_before, "SpeakingTrumpet hail causes 0 Audio unknown-sound warnings")

	# Verify 3.5 s cooldown rejects immediate repeat hail!
	var repeat_res := inv.hail_with_speaking_trumpet()
	check(not bool(repeat_res.get("ok", true)), "immediate repeat hail blocked by 3.5 s cooldown")

	# Verify out-of-range receive_trumpet_hail returns false (> 115 m), and in-range recalls Maren & Pip!
	check(not maren.receive_trumpet_hail(captain.global_position, ship),
		"CrewBrain.receive_trumpet_hail returns false beyond 115 m (145 m)")
	maren_pawn.global_position = Vector3(60.0, 0.0, 0.0)
	pip_pawn.global_position = Vector3(-45.0, 0.0, 0.0)
	check(maren.receive_trumpet_hail(captain.global_position, ship),
		"Maren at 60 m responds true to receive_trumpet_hail")
	check_eq(maren.current_order, &"return_ship", "Maren switches order to &'return_ship'")
	check(pip.receive_trumpet_hail(captain.global_position, ship),
		"Pip at 45 m responds true to receive_trumpet_hail")
	check_eq(pip.current_order, &"return_ship", "Pip switches order to &'return_ship'")
	check_eq(ack_lines.size(), 3, "all 3 personas emit trumpet_hail_ack barks")
	for entry: Dictionary in ack_lines:
		check_ascii.call("trumpet_hail_ack (%s)" % String(entry["speaker"]), String(entry["text"]))
	for pid: StringName in [&"helmsman", &"lookout", &"carpenter"]:
		var line := CrewDialogue.format_line(pid, &"trumpet_hail_ack")
		check_ascii.call("CrewDialogue.format_line(%s, trumpet_hail_ack)" % pid, line)

	# Step cooldown & temporary trumpet VFX smoothly to completion, then confirm next hail succeeds!
	for _step in 36:
		inv._process(0.1)
	check(inv._fp_trumpet_node == null, "brief first-person SpeakingTrumpet mesh frees cleanly after display")
	check(inv._trumpet_pulses.is_empty(), "acoustic brass ring pulses free cleanly after fade")
	var second_res := inv.hail_with_speaking_trumpet()
	check(bool(second_res.get("ok", false)), "hail succeeds again after 3.5 s cooldown expires")
	check_eq(int(second_res.get("crew_acked", 0)), 3, "all 3 in-range crewmates ack second hail")

	# Clean teardown with zero leaks!
	banner.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(banner), "LocationBanner frees cleanly on teardown")
	await _end()
	ToolMeshes.clear_shared_cache()
	check(ToolMeshes._pbr_tex_cache.is_empty(), "ToolMeshes shared PBR cache clears cleanly")













