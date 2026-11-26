extends TestCase
## End-to-end headless vertical slice tests for Sea of Scoundrels.
##
## Verifies full zero-placeholder boot of `scenes/main.tscn`, the complete
## "there and back" Story Chapter 1 voyage loop (moored -> sail -> Cutlass Cay ->
## Drowned combat -> Shovel dig -> haul chest -> Drowned Sloop intercept ->
## breach/patch/bail -> sell at Port Scoundrel -> gold/renown saved), and
## ShipwrightMenu sidegrade refits + WorldDirector ~60% salvage wreck restore.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SPEEDUP := 6

var _main: Node3D = null
var _saved_profile_data: Dictionary = {}
var _saved_weather: Dictionary = {}
var _saved_amp: float = 1.0
var _had_profile_file: bool = false
var _saved_profile_raw: String = ""


func _fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEEDUP if on else 1)
	Engine.time_scale = float(SPEEDUP) if on else 1.0
	Engine.max_physics_steps_per_frame = 8 * (SPEEDUP if on else 1)


func _begin(use_fast: bool = false) -> void:
	_saved_weather = Weather.get_state()
	_saved_amp = Sea.amp_scale
	_saved_profile_data = Game.profile.data.duplicate(true)
	_had_profile_file = FileAccess.file_exists(Profile.DEFAULT_PATH)
	if _had_profile_file:
		_saved_profile_raw = FileAccess.get_file_as_string(Profile.DEFAULT_PATH)
	# Start each test with a clean captain profile so assertions are deterministic.
	Game.profile.data = Profile._defaults()
	Net.start_single_player()
	if use_fast:
		_fast(true)


func _spawn_main() -> Node3D:
	_main = MAIN_SCENE.instantiate() as Node3D
	add_child(_main)
	# Suppress storm lightning & time drift during deterministic headless runs.
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	return _main


func _end() -> void:
	Audio.stop_shanty(0.01)
	Audio.stop_music(0.01)
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		_main = null
	await physics_frames(3)
	_fast(false)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_amp
	Game.profile.data = _saved_profile_data.duplicate(true)
	if _had_profile_file:
		var f := FileAccess.open(Profile.DEFAULT_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_saved_profile_raw)
			f.close()
	elif FileAccess.file_exists(Profile.DEFAULT_PATH):
		var dir := DirAccess.open(Profile.DEFAULT_PATH.get_base_dir())
		if dir != null:
			dir.remove(Profile.DEFAULT_PATH.get_file())


# ==============================================================================
# Test 1: Zero-Placeholder Main Scene Boot
# ==============================================================================

func test_main_scene_boots_zero_placeholders() -> void:
	_begin(false)
	var m := _spawn_main()
	await physics_frames(8)

	# Core world systems
	var sky_rig: Node = m.get(&"sky_rig")
	var ocean: Ocean = m.get(&"ocean") as Ocean
	var arch: Archipelago = m.get(&"archipelago") as Archipelago
	check(sky_rig != null and sky_rig.get(&"sky_material") != null, "real SkyRig booted")
	check(ocean != null and Ocean.current == ocean, "real Ocean booted")
	check(arch != null and arch.get_islands().size() == 11, "Archipelago has all 11 islands")
	check(arch.get_island_by_id("port_scoundrel") is Outpost, "Port Scoundrel outpost present")
	check(arch.get_island_by_id("cutlass_cay") != null, "Cutlass Cay starter island present")

	# Moored Ship + diegetic stations + downtime props
	var ship: Ship = m.get(&"player_ship") as Ship
	var map_table: MapTableView = m.get(&"map_table") as MapTableView
	var stove: CookingStove = m.get(&"cooking_stove") as CookingStove
	var fish: FishingLine = m.get(&"fishing_line") as FishingLine
	check(ship != null and ship.anchor_down, "player Ship starts moored and anchored")
	var port := arch.get_outpost(0)
	var moor_pos := port.get_world_mooring_transform().origin
	var moor_dist := Vector2(ship.global_position.x - moor_pos.x, ship.global_position.z - moor_pos.z).length()
	check(moor_dist < 4.0, "player Ship moored at Port Scoundrel pier (dist=%.2f m)" % moor_dist)
	check(map_table != null and map_table.get_island_count() == 11, "MapTableView mounted with 11 islands")
	check(stove != null and stove.get_parent() == ship, "CookingStove mounted in ship hold")
	check(fish != null and fish.get_parent() == ship, "FishingLine mounted on aft rail")

	# Player Pawn, Controller, Combat, Inventory, HUD & ShipwrightMenu
	var player: Pawn = m.get(&"player_pawn") as Pawn
	var inv: Inventory = m.get(&"inventory") as Inventory
	var hud: GameHUD = m.get(&"hud") as GameHUD
	var menu: ShipwrightMenu = m.get(&"shipwright_menu") as ShipwrightMenu
	check(player != null and player.platform == ship, "Player Pawn boarded onto player Ship")
	check(inv != null and inv.map_island_name == "Cutlass Cay", "Held treasure map synced to Cutlass Cay")
	var p_cv := player.get_node_or_null(^"Visual/CharacterVisual") as CharacterVisual
	check(p_cv != null and p_cv.first_person_hidden, "Player visual hidden in first-person")
	check(hud != null and hud.pawn == player and hud.ship == ship, "GameHUD bound to live player & ship")
	check(menu != null and not menu.is_open, "ShipwrightMenu mounted and initially closed")

	# Three AI Crewmates
	var brains: Array = m.get(&"crew_brains")
	check_eq(brains.size(), 3, "3 AI CrewBrains spawned")
	var names: Array[String] = []
	for b in brains:
		var cb := b as CrewBrain
		check(cb != null and cb.ship == ship, "CrewBrain wired to player ship")
		if cb != null:
			names.append(cb.crew_name())
	check(names.has("Barnaby") and names.has("Maren") and names.has("Pip"), "Barnaby, Maren & Pip present")

	# Active Story Chapter 1 Voyage + Cutlass Cay DigSite & Drowned Guardians
	var vm: VoyageManager = m.get(&"voyage_manager") as VoyageManager
	check(vm != null and vm.has_active_voyage(), "Story Chapter 1 active on launch")
	check_eq(String(vm.active_voyage.get("id", "")), "story_ch1_salt_kings_ledger", "Story Chapter 1 loaded")
	var cay := arch.get_island_by_id("cutlass_cay")
	var sites := cay.get_dig_sites()
	check(not sites.is_empty() and sites[0].treasure_id == &"ledger_coffer", "Cutlass Cay has Ledger Coffer DigSite")
	var enemies: Array = m.get(&"active_enemies")
	check(enemies.size() >= 4, "Cutlass Cay Drowned guardians spawned (got %d)" % enemies.size())

	await _end()


# ==============================================================================
# Test 2: Complete "There and Back" Vertical Slice Voyage Loop
# ==============================================================================

func test_there_and_back_full_voyage_loop() -> void:
	_begin(true)
	var m := _spawn_main()
	# Disable ambient WorldDirector random events during deterministic scripted leg checks.
	var wd: WorldDirector = m.get(&"world_director") as WorldDirector
	var vm: VoyageManager = m.get(&"voyage_manager") as VoyageManager
	var arch: Archipelago = m.get(&"archipelago") as Archipelago
	var ship: Ship = m.get(&"player_ship") as Ship
	var player: Pawn = m.get(&"player_pawn") as Pawn
	var inv: Inventory = m.get(&"inventory") as Inventory
	var brains: Array = m.get(&"crew_brains")

	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 11.0, -0.37, 0.0, 0.35)
	await physics_frames(15)

	var gold_start := int(Game.profile.data.get("gold", 0))
	var renown_start := Economy.get_company_renown(Game.profile, &"sunken_archive")

	# 1. Weigh anchor & sail out of Port Scoundrel with AI crew!
	check(ship.anchor_down, "starts anchored at Port Scoundrel")
	ship.set_anchor(false)
	ship.set_sail_target(1.0)
	ship.set_trim_target(ship.ideal_sail_trim())
	for b in brains:
		(b as CrewBrain).give_order(&"trim")
	var start_pos := ship.global_position
	await physics_frames(320)
	var sailed_dist := Vector2(ship.global_position.x - start_pos.x, ship.global_position.z - start_pos.z).length()
	print("    departed Port Scoundrel: sailed %.1f m, speed %.1f kt" % [sailed_dist, ship.speed_knots()])
	check(not ship.anchor_down and sailed_dist > 15.0 and ship.speed_knots() > 5.0, "sloop weighs anchor and sails under wind")

	# 2. Arrive at Cutlass Cay -> discovery + stage advances from sail_to -> dig_treasure!
	var cay := arch.get_island_by_id("cutlass_cay")
	var cay_moor := cay.get_world_mooring_transform()
	cay_moor.origin.y = Sea.height(cay_moor.origin.x, cay_moor.origin.z)
	ship.global_transform = cay_moor
	ship.linear_velocity = Vector3.ZERO
	ship.set_sail_target(0.0)
	ship.set_anchor(true)
	player.board(ship, Vector3(0.0, 2.02, 4.15))
	for i in brains.size():
		var cp: Pawn = (m.get(&"crew_pawns") as Array)[i]
		cp.board(ship, Vector3(-0.8 + float(i) * 0.8, 1.12, 0.2))
	await physics_frames(50)

	check(Game.profile.data["discoveries"].has("cutlass_cay"), "Cutlass Cay discovered in profile")
	check_eq(vm.get_current_stage().get("kind", &""), &"dig_treasure", "stage advanced to dig_treasure on landfall")

	# 3. Defeat all guarding Drowned on Cutlass Cay!
	var enemies: Array = m.get(&"active_enemies")
	var alive_before := 0
	for ep_var in enemies:
		var ep := ep_var as Pawn
		if ep != null and is_instance_valid(ep) and not ep.dead:
			alive_before += 1
			ep.apply_damage(999.0, player)
	check(alive_before >= 4, "defeated all %d guarding Drowned on Cutlass Cay" % alive_before)
	await physics_frames(5)

	# 4. Walk to Cutlass Cay DigSite, equip Shovel, and dig 3 times to unearth Ledger Coffer!
	var dig_sites := cay.get_dig_sites()
	check(not dig_sites.is_empty(), "Cutlass Cay has active DigSite")
	var site := dig_sites[0]
	player.teleport(site.global_position + Vector3(0.0, 0.15, 0.9))
	player.look_yaw = 0.0
	inv.equip(&"shovel", true)
	await physics_frames(4)

	var chest: Carryable = null
	for strike in 3:
		var res := inv.use_shovel()
		check(bool(res.get("hit", false)), "shovel dig strike %d hit DigSite" % (strike + 1))
		if bool(res.get("unearthed", false)):
			chest = res.get("chest") as Carryable
		await physics_frames(4)
	check(site.is_unearthed and chest != null, "3 shovel digs unearthed physical Ledger Coffer Carryable")
	check_eq(vm.get_current_stage().get("kind", &""), &"board_treasure", "stage advanced to board_treasure after dig")

	# 5. Carry physical Ledger Coffer aboard the sloop and set it on deck!
	check(player.pick_up(chest), "captain picked up physical Ledger Coffer")
	player.board(ship, Vector3(0.0, 1.15, 0.2))
	await physics_frames(4)
	player.drop_carried(0.05)
	chest.global_position = ship.global_transform * Vector3(0.35, 1.32, 0.2)
	chest.linear_velocity = Vector3.ZERO
	await physics_frames(45)

	check_eq(vm.get_current_stage().get("kind", &""), &"sell_treasure", "stage advanced to sell_treasure once chest aboard")
	check(wd.cargo_value_aboard >= 950, "WorldDirector tracks live Ledger Coffer value aboard (%d g)" % wd.cargo_value_aboard)

	# 6. Return leg: Drowned Sloop interception + hull breach -> AI crew patches & bails!
	var mid_xf := Transform3D(Basis.IDENTITY, Vector3(80.0, 0.0, -210.0))
	ship.global_transform = mid_xf
	ship.set_anchor(false)
	ship.anchor_progress = 0.0
	chest.global_position = ship.global_transform * Vector3(0.35, 1.32, 0.2)
	chest.linear_velocity = Vector3.ZERO
	player.board(ship, Vector3(0.0, 2.02, 4.15))
	for i in brains.size():
		var cp: Pawn = (m.get(&"crew_pawns") as Array)[i]
		cp.board(ship, Vector3(-0.7 + float(i) * 0.7, 1.12, 0.4))
		(brains[i] as CrewBrain).give_order(&"auto")

	wd.trigger_event(&"drowned_sloop", {
		"ship_pos": ship.global_position,
		"ship_forward": Vector3(0.0, 0.0, 1.0),
		"ship_node": ship,
	})
	await physics_frames(6)
	var enemy_ships: Array = m.get(&"enemy_ships")
	check(enemy_ships.size() >= 1, "Drowned Sloop interceptor spawned on return crossing")

	# Take a real hull breach & flood water; verify AI crew patches and bails!
	ship.apply_hull_damage(ship.global_transform * Vector3(2.0, -0.45, 0.4), 0.5)
	ship.water_level = 0.28
	check_eq(ship.open_hole_count(), 1, "hull breach opened by engagement")

	var patched := false
	for _i in 650:
		await physics_frames(1)
		if ship.open_hole_count() == 0:
			patched = true
			break
	check(patched, "AI crew navigated below deck and patched open hull breach")

	var water_after_patch := ship.water_level
	for _i in 500:
		await physics_frames(1)
		if ship.water_level < 0.05:
			break
	print("    crew patched breach & bailed bilge: %.3f -> %.3f" % [water_after_patch, ship.water_level])
	check(ship.water_level < water_after_patch - 0.12, "AI crew bailed bilge water after patching")

	# 7. Return to Port Scoundrel and sell the Ledger Coffer at MerchantStall!
	var port := arch.get_outpost(0)
	check(port != null and port.merchant_stall != null, "Port Scoundrel MerchantStall present")
	player.teleport(port.merchant_stall.global_position + Vector3(0.0, 0.1, -1.2))
	chest.global_position = player.global_position + Vector3(0.0, 0.5, 0.0)
	check(player.pick_up(chest), "captain picked up Ledger Coffer for turn-in")
	check(chest.hand_to(port.merchant_stall), "sold Ledger Coffer to Port Scoundrel MerchantStall")
	await physics_frames(6)

	var gold_end := int(Game.profile.data.get("gold", 0))
	var renown_end := Economy.get_company_renown(Game.profile, &"sunken_archive")
	print("    voyage complete! gold: %d -> %d, archive renown: %d -> %d" % [
		gold_start, gold_end, renown_start, renown_end])
	check_eq(vm.completed_count, 1, "Story Chapter 1 completed on VoyageManager")
	check(not vm.has_active_voyage(), "no active voyage remains after completion")
	check_eq(gold_end - gold_start, 1200, "gold increased by 950 (Ledger Coffer) + 250 (story bonus)")
	check_eq(renown_end - renown_start, 200, "Sunken Archive renown increased by 140 + 60 bonus")
	check(FileAccess.file_exists(Profile.DEFAULT_PATH), "profile saved to disk after turn-in")

	await _end()


# ==============================================================================
# Test 3: ShipwrightMenu Refits, Co-op Slot Yield, & WorldDirector Wreck Salvage
# ==============================================================================

func test_shipwright_menu_and_world_director_wreck_salvage() -> void:
	_begin(false)
	var m := _spawn_main()
	await physics_frames(8)

	var ship: Ship = m.get(&"player_ship") as Ship
	var player: Pawn = m.get(&"player_pawn") as Pawn
	var pc: PlayerController = m.get(&"player_controller") as PlayerController
	var hud: GameHUD = m.get(&"hud") as GameHUD
	var menu: ShipwrightMenu = m.get(&"shipwright_menu") as ShipwrightMenu
	var wd: WorldDirector = m.get(&"world_director") as WorldDirector
	var arch: Archipelago = m.get(&"archipelago") as Archipelago
	var brains: Array = m.get(&"crew_brains")

	# 1. Open ShipwrightMenu, verify mouse/look pause & HUD coordination.
	menu.open_menu(ShipwrightMenu.TAB_SHIPWRIGHT)
	check(menu.is_open, "ShipwrightMenu opened")
	check(pc.look_paused, "PlayerController look paused while ShipwrightMenu open")
	check(not hud.input_enabled, "HUD input paused while ShipwrightMenu open")

	# Grant funds & rank 2 Gilded Compass renown to purchase & equip Swift Red Cedar Hull + Crimson Gull Flag.
	Game.profile.add_gold(1500)
	Game.profile.add_renown("gilded_compass", 150)
	var speed_before := ship.speed_modifier
	var resist_before := ship.breach_resist_modifier

	var buy_hull := menu.buy_or_equip_unlock(&"hull_swift_cedar")
	check(bool(buy_hull.get("ok", false)), "purchased & equipped Swift Red Cedar Hull")
	check_near(ship.speed_modifier, 1.12, 0.005, "Ship speed_modifier updated to 1.12")
	check_near(ship.breach_resist_modifier, 0.80, 0.005, "Ship breach_resist_modifier updated to 0.80")
	check(ship.speed_modifier > speed_before and ship.breach_resist_modifier < resist_before, "sidegrade trade-off active on Ship")

	var buy_flag := menu.buy_or_equip_unlock(&"flag_crimson_gull")
	check(bool(buy_flag.get("ok", false)), "purchased & equipped Crimson Gull Pennant livery")

	# Verify Ship Class toggle signal & Settings tab actions.
	var picked_classes: Array[StringName] = []
	menu.ship_class_selected.connect(func(cls: StringName) -> void: picked_classes.append(cls))
	menu.select_ship_class(&"brigantine")
	check_eq(picked_classes.size(), 1, "ship_class_selected emitted")
	check_eq(picked_classes[0], &"brigantine", "ship class toggled to brigantine")

	menu.apply_quality_preset(0)
	check_eq(int(Ocean.current.quality), int(Ocean.Quality.LOW), "quality preset propagated to Ocean")
	menu.reset_keybindings()
	check(InputMap.has_action(&"interact"), "keybinding reset preserved actions")

	menu.close_menu()
	check(not menu.is_open and not pc.look_paused, "ShipwrightMenu closed cleanly and restored look")
	check(hud.input_enabled, "HUD input restored after closing ShipwrightMenu")

	# 2. Verify Co-op peer join yields 1 AI crewmate slot & peer leave restores it!
	Net.peer_joined.emit(42)
	await physics_frames(2)
	var last_brain := brains[brains.size() - 1] as CrewBrain
	check(not last_brain.is_physics_processing(), "AI crewmate yielded slot when co-op peer joined")
	Net.peer_left.emit(42)
	await physics_frames(2)
	check(last_brain.is_physics_processing(), "AI crewmate restored when co-op peer left")

	# 3. Sail into open water with 3 treasure chests aboard, sink ship, verify ~60% salvage wreck & clean restore!
	var wreck_spot := Vector3(140.0, 0.0, -240.0)
	ship.global_transform = Transform3D(Basis.IDENTITY, wreck_spot)
	ship.set_anchor(false)
	player.board(ship, Vector3(0.0, 2.02, 4.15))

	var cargo_ids: Array[StringName] = [&"corsair_chest", &"wayfarer_chest", &"drowned_skull"]
	for i in cargo_ids.size():
		var item := TreasureCatalog.create_treasure_carryable(
			cargo_ids[i], ship.global_transform * Vector3(-0.6 + float(i) * 0.6, 1.3, 0.0))
		m.add_child(item)
		item.global_position = ship.global_transform * Vector3(-0.6 + float(i) * 0.6, 1.3, 0.0)
	await physics_frames(4)

	# Flood ship to trigger `sunk` signal -> WorldDirector records wreck + Main restores ship at Port Scoundrel!
	ship.add_water(1.0)
	await physics_frames(6)

	check_eq(wd.salvage_wrecks.size(), 1, "WorldDirector recorded 1 salvage wreck on sink")
	var wreck: Dictionary = wd.salvage_wrecks[0]
	var total_lost := int(wreck.get("total_lost_value", 0))
	var salvage_val := int(wreck.get("salvage_value", 0))
	var ratio := float(wreck.get("salvage_ratio", 0.0))
	print("    ship sunk -> wreck salvage: %d / %d gold (%.1f%%)" % [salvage_val, total_lost, ratio * 100.0])
	check(total_lost == 1020, "all 3 aboard chests accounted for (420 + 240 + 360 = 1020g)")
	check(ratio >= 0.45 and ratio <= 0.72, "wreck preserved ~60%% salvage value (got %.2f)" % ratio)

	# Verify ship cleanly restored at Port Scoundrel mooring!
	var port := arch.get_outpost(0)
	var moor_origin := port.get_world_mooring_transform().origin
	var restore_dist := Vector2(ship.global_position.x - moor_origin.x, ship.global_position.z - moor_origin.z).length()
	check(not ship.is_sinking, "restored ship is no longer sinking")
	check_near(ship.water_level, 0.0, 0.01, "restored ship hold is dry")
	check_eq(ship.open_hole_count(), 0, "restored ship has zero open hull breaches")
	check(ship.anchor_down, "restored ship moored with anchor down")
	check(restore_dist < 4.0, "restored ship returned to Port Scoundrel mooring (dist=%.2f m)" % restore_dist)
	check(not player.dead and player.platform == ship, "captain alive and boarded on restored ship")

	await _end()


# ==============================================================================
# Test 4: Voyage Board Contracts, Living-Sea Spawners & Ship Downtime
# ==============================================================================

func test_voyage_board_and_living_sea_events() -> void:
	_begin(false)
	var m := _spawn_main()
	await physics_frames(8)

	var vm: VoyageManager = m.get(&"voyage_manager") as VoyageManager
	var wd: WorldDirector = m.get(&"world_director") as WorldDirector
	var ship: Ship = m.get(&"player_ship") as Ship
	var menu: ShipwrightMenu = m.get(&"shipwright_menu") as ShipwrightMenu
	var map_table: MapTableView = m.get(&"map_table") as MapTableView
	var stove: CookingStove = m.get(&"cooking_stove") as CookingStove
	var fish: FishingLine = m.get(&"fishing_line") as FishingLine

	# 1. Accept a procedural Voyage Board offer via ShipwrightMenu -> syncs VoyageManager & MapTableView.
	check(vm.available_voyages.size() == 3, "3 procedural contracts posted on Voyage Board")
	var chosen_offer: Dictionary = vm.available_voyages[0]
	menu.open_menu(ShipwrightMenu.TAB_VOYAGES)
	check(menu.accept_voyage(chosen_offer), "accepted procedural contract from Voyage Board")
	check_eq(String(vm.active_voyage.get("id", "")), String(chosen_offer.get("id", "")), "active voyage switched cleanly")
	check(map_table.active_voyage_target.is_finite(), "MapTableView updated active voyage target")
	menu.close_menu()

	# 2. Fire every WorldDirector living-sea event signal -> verify real zero-placeholder spawns!
	var ctx := {
		"ship_pos": Vector3(0.0, 0.0, -320.0),
		"ship_forward": Vector3(0.0, 0.0, -1.0),
		"ship_node": ship,
		"swimmer_pos": Vector3(40.0, 0.0, -320.0),
	}
	wd.trigger_event(&"ghost_ship", ctx)
	wd.trigger_event(&"shark_pack", ctx)
	wd.trigger_event(&"leviathan", ctx)
	wd.trigger_event(&"flotsam_barrels", ctx)
	wd.trigger_event(&"fort_siege", ctx)
	wd.trigger_event(&"castaway", ctx)
	await physics_frames(4)

	var enemy_ships: Array = m.get(&"enemy_ships")
	var sharks: Array = m.get(&"active_sharks")
	var levs: Array = m.get(&"active_leviathans")
	var entities := m.get_node_or_null(^"Entities")
	check(enemy_ships.size() >= 1, "Ghost Ship spawned cleanly")
	check(sharks.size() >= 2, "Shark pack spawned cleanly (got %d)" % sharks.size())
	check(levs.size() >= 1, "Leviathan spawned cleanly")
	check(entities != null and entities.find_child("CastawayRaft", true, false) != null, "Castaway raft spawned cleanly")
	check(entities != null and entities.find_child("FlotsamBarrel_0", true, false) != null, "Flotsam salvage barrels spawned cleanly")

	# 3. Verify FishingLine & CookingStove live aboard the sloop.
	check(fish.cast_line(fish.global_position, ship.global_basis.z, 10.0), "FishingLine casts off stern rail")
	check_eq(fish.state, FishingLine.State.WAITING, "FishingLine entered WAITING state")
	fish.cancel_cast()
	check(stove.place_food(FishingLine.SPECIES[0]), "placed fish on hold CookingStove")
	stove.step(CookingStove.COOK_TIME + 0.5)
	check_eq(stove.cook_state, &"cooked", "CookingStove cooked fish to golden state")

	await _end()

