extends Node3D
## Ship showcase: real Sloop sailing on the real Ocean under the real SkyRig.
##
##   tools/capture.sh res://scenes/showcase/ship_showcase.tscn ship_sail 3 8 -- shot=sailing
##
## User args (after `--`):
##   shot=sailing|storm|sunset|damage|broadside|helm|hold   (default sailing)
##   ship=sloop|brigantine   (default sloop)
##   time=<0..24>   override time of day
##   storm=<0..1>   override weather storminess
##   livery=player|drowned|ghost|corsair   optional ship livery

const SKY_RIG: PackedScene = preload("res://src/sky/sky_rig.tscn")
const OCEAN_SCENE: PackedScene = preload("res://src/ocean/ocean.tscn")
const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const BRIGANTINE_SCENE: PackedScene = preload("res://src/ship/brigantine.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")

var _args: Dictionary = {}
var _shot: String = "sailing"
var _is_brig: bool = false
var _ship: Ship
var _rowboat: Rowboat = null
var _target_ship: Ship = null
var _pawn: Pawn = null
var _cam: Camera3D
var _clock: float = 0.0
var _fired: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_shot = String(_args.get("shot", "sailing"))
	_is_brig = String(_args.get("ship", "sloop")).to_lower() == "brigantine"

	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false

	var time_h := 11.2
	var storm := 0.12
	var wind_spd := 10.5
	var wind_hdg := 0.25
	match _shot:
		"storm":
			time_h = 15.0
			storm = 0.95
			wind_spd = 21.0
			wind_hdg = 0.75
		"sunset":
			time_h = 17.85
			storm = 0.22
			wind_spd = 9.5
			wind_hdg = 0.4
		"damage", "hold", "barrels":
			time_h = 13.0
			storm = 0.28
			wind_spd = 9.0
		"broadside":
			time_h = 14.5
			storm = 0.18
			wind_spd = 9.5
		"fire", "rage_chest":
			time_h = 18.25
			storm = 0.24
			wind_spd = 11.0
		"emissary":
			time_h = 16.9
			storm = 0.14
			wind_spd = 11.5
			wind_hdg = 0.55

	if _args.has("time"):
		time_h = float(_args["time"])
	if _args.has("storm"):
		storm = float(_args["storm"])

	Weather.time_of_day = time_h
	Weather.set_weather(storm, wind_spd, wind_hdg, 0.0, lerpf(0.38, 1.0, storm))
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	Sea.time = 24.0

	add_child(SKY_RIG.instantiate())
	add_child(OCEAN_SCENE.instantiate())

	_ship = (BRIGANTINE_SCENE if _is_brig else SLOOP_SCENE).instantiate() as Ship
	var liv := String(_args.get("livery", "player")).to_lower()
	if liv == "drowned":
		_ship.faction = &"drowned"
	elif liv == "ghost":
		_ship.faction = &"ghost"
	elif liv == "corsair":
		_ship.faction = &"corsair"
	add_child(_ship)
	_ship.global_position = Vector3(0.0, Sea.height(0.0, 0.0), 0.0)
	_ship.set_sail_target(1.0)
	_ship.sail_set = 1.0
	_ship.set_trim_target(_ship.ideal_sail_trim())
	_ship.sail_trim = _ship.trim_target
	_ship.linear_velocity = Vector3(0.0, 0.0, -5.8)

	if liv == "drowned":
		_ship.apply_livery(Color(0.32, 0.38, 0.34), Color(0.18, 0.55, 0.42), Color(0.16, 0.95, 0.62))
	elif liv == "ghost":
		_ship.apply_livery(Color(0.45, 0.92, 0.88), Color(0.35, 0.95, 0.9), Color(0.25, 0.98, 0.85))
	elif liv == "corsair":
		_ship.apply_livery(Color(0.22, 0.16, 0.16), Color(0.84, 0.18, 0.14), Color(0.0, 0.0, 0.0))

	if _shot == "rowboat" or liv == "player":
		_rowboat = Rowboat.new()
		_rowboat.name = "ShipRowboat"
		add_child(_rowboat)
		_rowboat.attach_to_ship(_ship)
		if String(_args.get("rowboat", "docked")).to_lower() == "launched":
			_rowboat.launch()

	if _shot == "emissary":
		var eflag := ShipEmissaryFlag.mount_to_ship(_ship)
		if eflag != null:
			var comp := StringName(String(_args.get("company", "gilded_compass")))
			var grade := clampi(int(_args.get("grade", "5")), 1, 5)
			eflag.set_emissary(comp, grade)

	if _shot == "fire":
		var sfire: ShipFire = _ship.get_node_or_null(^"ShipFire") as ShipFire
		if sfire != null:
			sfire.ignite_zone(0, 1.0)
			sfire.ignite_zone(1, 0.95)
			sfire.ignite_zone(2, 0.92)

	if _shot == "rage_chest":
		var deck_y := 1.24 if _is_brig else 1.08
		var z_shift := -0.75 if _is_brig else 0.0
		var loot_specs: Array[Array] = [
			[&"blazing_rage_chest", Vector3(-0.06, deck_y, -2.42 + z_shift), 0.22],
			[&"commodity_spiced_silk", Vector3(-0.92, deck_y, -2.62 + z_shift), 0.44],
			[&"commodity_cinder_rum", Vector3(0.78, deck_y, -2.38 + z_shift), -0.34],
		]
		for spec in loot_specs:
			var tid: StringName = spec[0]
			if not TreasureCatalog.has_treasure(tid):
				continue
			var lpos := _ship.ship_point(spec[1] as Vector3)
			var item := TreasureCatalog.create_treasure_carryable(tid, Vector3.ZERO)
			item.freeze = true
			_ship.add_child(item)
			item.position = lpos
			item.rotation.y = float(spec[2])
			if tid == &"blazing_rage_chest":
				item.set_meta(&"rage_heat", 0.88)
				TreasureCatalog.sync_rage_visual(item)

	if _shot == "damage" or _shot == "hold":
		var bx := 2.4 if _is_brig else 2.0
		_ship.apply_hull_damage(_ship.global_transform * _ship.ship_point(Vector3(bx, -0.35, 0.4)), 0.55)
		_ship.apply_hull_damage(_ship.global_transform * _ship.ship_point(Vector3(-bx, -0.35, -1.2)), 0.55)
		_ship.apply_hull_damage(_ship.global_transform * _ship.ship_point(Vector3(bx - 0.1, -0.3, -2.5)), 0.5)
		_ship.patch_hole(0)
		_ship.water_level = 0.26

	if _shot == "broadside":
		_target_ship = SLOOP_SCENE.instantiate() as Ship
		_target_ship.faction = &"drowned"
		add_child(_target_ship)
		_target_ship.global_position = Vector3(38.0, Sea.height(38.0, -6.0), -6.0)
		_target_ship.apply_livery(Color(0.3, 0.36, 0.33), Color(0.2, 0.6, 0.46), Color(0.18, 0.95, 0.6))
		_target_ship.set_sail_target(0.6)
		_target_ship.sail_set = 0.6
		_ship.aim_cannon(&"starboard", 0.0, 0.09)
		if _is_brig:
			_ship.aim_cannon(&"starboard_aft", 0.0, 0.09)

	_pawn = PAWN_SCENE.instantiate() as Pawn
	add_child(_pawn)
	var helm_st := _ship.get_station(&"helm")
	if helm_st != null:
		var helm_pos := _ship.ship_point(Vector3(0.0, 2.25, 7.2) if _is_brig else Vector3(0.0, 2.02, 5.9))
		_pawn.board(_ship, helm_pos)
		_pawn.enter_station(helm_st)

	_cam = Camera3D.new()
	_cam.fov = 78.0 if (_shot == "harpoon" and _is_brig) else 66.0
	_cam.near = 0.08
	_cam.far = 6000.0
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _process(delta: float) -> void:
	_clock += delta
	if _shot == "broadside" and not _fired and _clock > 0.45:
		_fired = true
		_ship.fire_cannon(&"starboard", _pawn)
		if _is_brig:
			_ship.fire_cannon(&"starboard_aft", _pawn)
	_update_camera()


func _update_camera() -> void:
	var xf := _ship.global_transform
	var pos := xf.origin
	var hs := _ship.hull_scale
	var sc := (1.32 if _is_brig else 1.0) * hs
	# Ship bow faces local -Z (xf.basis.z points aft), so atan2(z.x, z.z) aligns with ship yaw.
	var yaw := Basis(Vector3.UP, atan2(xf.basis.z.x, xf.basis.z.z))
	match _shot:
		"helm":
			# Over-the-shoulder helm framing showing Captain gripping wheel, deck, sail, and horizon.
			var eye := xf * _ship.ship_point(Vector3(1.05, 3.95, 8.7) if _is_brig else Vector3(0.85, 3.65, 7.1))
			var look := xf * _ship.ship_point(Vector3(-0.15, 2.95, -12.0))
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"hold":
			var eye := xf * _ship.ship_point(Vector3(-0.45, 0.58, 6.1) if _is_brig else Vector3(-0.35, 0.68, 4.3))
			var look := xf * _ship.ship_point(Vector3(0.2, -0.3, -1.8))
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"damage":
			var eye := pos + yaw * Vector3(11.0 * sc, 3.2 * sc, 2.0 * hs)
			_cam.look_at_from_position(eye, pos + Vector3(0.0, 0.8 * hs, 0.0), Vector3.UP)
		"broadside":
			var eye := pos + yaw * Vector3(-11.0 * sc, 6.5 * sc, 16.0 * sc)
			_cam.look_at_from_position(eye, pos + Vector3(18.0, 1.5, -4.0), Vector3.UP)
		"storm":
			var ang := 0.58 + _clock * 0.12
			var eye := pos + yaw * Vector3(sin(ang) * 23.5 * sc, 5.8 * sc, -cos(ang) * 23.5 * sc)
			eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 2.4)
			_cam.look_at_from_position(eye, pos + Vector3(0.0, 4.2 * sc, -1.0), Vector3.UP)
		"harpoon":
			# Foredeck 3/4 view cleanly ahead of the foremast (MAST_FORE_Z = -4.60 on Brig) framing BOTH bow ShipHarpoons unobstructed.
			var eye := xf * _ship.ship_point(Vector3(0.32, 3.22, -4.95) if _is_brig else Vector3(1.18, 2.95, -2.15))
			var look := xf * _ship.ship_point(Vector3(-0.08, 2.48, -7.85) if _is_brig else Vector3(-0.40, 2.35, -4.85))
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"emissary":
			# Dramatic 3/4 starboard-stern view framing the sculpted ShipEmissaryFlag & all 5 Grade V pennants above the taffrail.
			var eye := xf * _ship.ship_point(Vector3(6.2, 5.45, 11.4) if _is_brig else Vector3(5.2, 4.95, 9.2))
			var look := xf * _ship.ship_point(Vector3(1.75, 4.95, 7.15) if _is_brig else Vector3(1.45, 4.45, 5.65))
			eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 2.0)
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"fire":
			# Dramatic dusk quarter-bow view framing blazing multi-tongue sculpted ShipFire deck flames.
			var eye := xf * _ship.ship_point(Vector3(7.4, 5.2, -9.8) if _is_brig else Vector3(6.2, 4.6, -7.8))
			var look := xf * _ship.ship_point(Vector3(0.0, 2.0, -2.2) if _is_brig else Vector3(0.0, 1.8, -1.2))
			eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 2.0)
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"rage_chest":
			# Intimate foredeck dusk close-up cleanly ahead of the mainmast framing glowing BlazingRageChest & Trade Crates.
			var eye := xf * _ship.ship_point(Vector3(0.32, 2.48, -2.05) if _is_brig else Vector3(0.28, 2.34, -1.32))
			var look := xf * _ship.ship_point(Vector3(-0.06, 1.46, -3.22) if _is_brig else Vector3(-0.06, 1.32, -2.55))
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"rowboat":
			# Dramatic 3/4 stern view framing the sculpted clinker Rowboat on stern davits cleanly below ShipNameplate.
			var eye := xf * _ship.ship_point(Vector3(5.6, 2.65, 14.4) if _is_brig else Vector3(4.8, 2.35, 11.8))
			var look := xf * _ship.ship_point(Vector3(0.0, 1.35, 9.1) if _is_brig else Vector3(0.0, 1.25, 7.2))
			eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 1.4)
			_cam.look_at_from_position(eye, look, Vector3.UP)
		"barrels":
			# Lower-deck hold framing all 3 sculpted coopered-oak ShipSupplyBarrels clear of companionway stringers.
			var eye := xf * _ship.ship_point(Vector3(0.85, 0.25, 3.35) if _is_brig else Vector3(0.28, 0.16, 1.95))
			var look := xf * _ship.ship_point(Vector3(-1.45, -0.45, 1.55) if _is_brig else Vector3(-1.22, -0.42, 0.55))
			_cam.look_at_from_position(eye, look, Vector3.UP)
		_:
			# Quarter-bow hero view showing figurehead, bow wave, billowing sail, and pennant.
			var ang := 0.66 + _clock * 0.10
			var eye := pos + yaw * Vector3(sin(ang) * 22.5 * sc, 4.8 * sc, -cos(ang) * 22.5 * sc)
			eye.y = maxf(eye.y, Sea.height(eye.x, eye.z) + 2.2)
			_cam.look_at_from_position(eye, pos + Vector3(0.0, 4.8 * sc, -1.0), Vector3.UP)


func _exit_tree() -> void:
	if Audio != null and Audio.has_method(&"shutdown"):
		Audio.shutdown()
	TreasureCatalog.clear_mesh_cache()
	ShipFire.clear_shared_cache()
	ShipEmissaryFlag.clear_shared_cache()
	ShipDamageVisuals.clear_shared_cache()
	Rowboat.clear_shared_cache()
	ShipSupplyBarrels.clear_shared_cache()
	ShipHarpoon.clear_shared_cache()
	WindRibbons.clear_shared_cache()
	ShipNameplate.clear_shared_cache()
	HullCrest.clear_shared_cache()
	CaptainCabinFurnishings.clear_shared_cache()
	Cannonball.clear_shared_cache()
	ToolMeshes.clear_shared_cache()
	CombatComponent.clear_shared_vfx_cache()

