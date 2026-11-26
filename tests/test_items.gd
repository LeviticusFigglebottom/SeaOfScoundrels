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
	pawn.board(ship, Vector3(0.0, -0.82, 0.2))
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

	# Planks patch the nearest open hull breach on the real Ship within 3.2 m.
	var breach_slot := ship.apply_hull_damage(ship.global_transform * Vector3(1.8, -0.45, 0.4), 0.5)
	check(breach_slot >= 0 and ship.open_hole_count() == 1, "ship has 1 open hull breach")
	var hole_local: Vector3 = ship.holes[breach_slot]["local_pos"]
	pawn.board(ship, Vector3(hole_local.x * 0.4, -0.82, hole_local.z))
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
	captain.board(ship, Vector3(0.0, 2.02, 4.9))

	var mate := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(mate)
	mate.board(ship, Vector3(0.8, 1.12, 0.5))
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

	var rig := _make_player_pawn(Vector3.ZERO)
	var captain: Pawn = rig["pawn"]
	var pc: PlayerController = rig["pc"]
	var cc: CombatComponent = rig["combat"]
	var inv: Inventory = rig["inv"]
	captain.board(ship, Vector3(0.0, 1.12, 0.2))

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

	var slot := ship.apply_hull_damage(ship.global_transform * Vector3(1.8, -0.45, 0.4), 0.5)
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
	captain.board(ship, Vector3(0.0, -0.82, 2.5))
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




