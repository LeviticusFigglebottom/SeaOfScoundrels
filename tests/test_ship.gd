extends TestCase
## Headless physics, mechanics, damage, cannon, pawn-riding, and replication tests for Ship.

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")
const PAWN_SCENE: PackedScene = preload("res://src/characters/pawn.tscn")
const SPEEDUP := 6

var _root: Node3D
var _saved_weather: Dictionary
var _saved_sea_amp: float = 1.0
var _saved_sea_time: float = 0.0


func _fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEEDUP if on else 1)
	Engine.time_scale = float(SPEEDUP) if on else 1.0
	Engine.max_physics_steps_per_frame = 8 * (SPEEDUP if on else 1)


func _begin() -> void:
	_saved_weather = Weather.get_state()
	_saved_sea_amp = Sea.amp_scale
	_saved_sea_time = Sea.time
	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	_fast(true)
	_root = Node3D.new()
	add_child(_root)


func _end() -> void:
	for ch in get_tree().root.get_children():
		if ch is Cannonball:
			ch.queue_free()
	_root.queue_free()
	_root = null
	await physics_frames(2)
	_fast(false)
	Weather.apply_state(_saved_weather)
	Sea.amp_scale = _saved_sea_amp
	Sea.time = _saved_sea_time


func _spawn_sloop(at: Vector3 = Vector3.ZERO) -> Ship:
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = false
	_root.add_child(s)
	s.global_position = at
	return s


func test_sloop_loads_stations_and_collision() -> void:
	_begin()
	var s := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	await physics_frames(2)

	check(s.is_in_group(&"ship"), "ship must be in group `ship`")
	check_eq(s.collision_layer, Ship.LAYER_SHIP, "ship must live on collision layer 2")
	check((s.collision_mask & Pawn.LAYER_PAWN) == 0, "ship collision_mask must NOT include layer 3 (pawns)")

	for kind: StringName in [&"helm", &"sail_length", &"sail_angle", &"anchor", &"cannon", &"map_table", &"bilge"]:
		check(s.get_station(kind) != null, "missing station kind " + String(kind))
	check_eq(s.get_stations(&"cannon").size(), 2, "sloop must have port and starboard cannons")
	check(s.get_station(&"cannon", &"port") != null, "port cannon station")
	check(s.get_station(&"cannon", &"starboard") != null, "starboard cannon station")

	var ladders := 0
	var cols := 0
	var shelters := 0
	for child in s.get_children():
		if child is Ladder:
			ladders += 1
		elif child is CollisionShape3D:
			cols += 1
		elif child.is_in_group(&"shelter"):
			shelters += 1
	check_eq(ladders, 2, "sloop must create port & starboard Ladder nodes")
	check(cols > 40, "expected convex collision pieces from col_*, got %d" % cols)
	check(shelters >= 1, "sloop hold must have a shelter volume")
	check_eq(s.holes.size(), 10, "sloop must map all 10 damage slots")
	await _end()


func test_floats_in_calm_and_storm_and_rides_swell() -> void:
	_begin()
	# 1. Calm sea equilibrium.
	Weather.set_weather(0.0, 6.0, 0.0)
	Sea.amp_scale = Sea.AMP_CALM
	Sea.time = 10.0
	var s := _spawn_sloop(Vector3(0.0, Sea.height(0.0, 0.0) + 0.2, 0.0))
	await physics_frames(180)
	var surf := Sea.height(s.global_position.x, s.global_position.z)
	var err := absf(s.global_position.y - surf)
	print("    calm float: ship y=%.2f sea y=%.2f |dy|=%.2f up.y=%.3f" % [s.global_position.y, surf, err, s.global_basis.y.y])
	check(err < 0.75, "calm waterline error %.2f m too large" % err)
	check(s.global_basis.y.y > 0.90, "ship should stay upright in calm sea, up.y=%.3f" % s.global_basis.y.y)

	# 2. Full 16-wave storm: ship must stay afloat, never capsize, and pitch with visible swells.
	Weather.set_weather(1.0, 22.0, 0.5)
	Sea.amp_scale = Sea.AMP_STORM
	var min_up := 1.0
	var max_bow_diff := 0.0
	var bow_pitch_matches := 0
	var samples := 0
	for _i in 30:
		await physics_frames(12)
		min_up = minf(min_up, s.global_basis.y.y)
		var bow_w := s.global_transform * Vector3(0.0, 0.0, -5.5)
		var stern_w := s.global_transform * Vector3(0.0, 0.0, 5.5)
		var wave_slope := Sea.height(bow_w.x, bow_w.z) - Sea.height(stern_w.x, stern_w.z)
		var hull_slope := bow_w.y - stern_w.y
		max_bow_diff = maxf(max_bow_diff, absf(hull_slope))
		if absf(wave_slope) > 0.45:
			samples += 1
			if wave_slope * hull_slope > 0.0:
				bow_pitch_matches += 1
	var surf_storm := Sea.height(s.global_position.x, s.global_position.z)
	print("    storm float: min up.y=%.3f max pitch diff=%.2f m slope match=%d/%d |dy|=%.2f" % [
		min_up, max_bow_diff, bow_pitch_matches, samples, absf(s.global_position.y - surf_storm)])
	check(min_up > 0.65, "ship must never capsize in full storm (min up.y=%.3f)" % min_up)
	check(max_bow_diff > 0.45, "bow must visibly pitch on storm swells (max diff=%.2f)" % max_bow_diff)
	check(absf(s.global_position.y - surf_storm) < 2.5, "ship must ride storm surface")
	if samples >= 4:
		check(float(bow_pitch_matches) / float(samples) >= 0.55, "bow should rise on oncoming crests")
	await _end()


func test_sailing_wind_trim_and_turn() -> void:
	_begin()
	# Steady downwind breeze towards -Z (heading 0).
	Weather.set_weather(0.0, 11.0, 0.0)
	Sea.amp_scale = 0.0  # flat sea to isolate sailing & turning cleanly
	Sea.time = 0.0
	var s := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	await physics_frames(40)

	# Full sail with optimal trim (0 rad for downwind).
	s.set_sail_target(1.0)
	s.set_trim_target(0.0)
	await physics_frames(320)
	var v_good := s.forward_speed()
	print("    downwind good trim speed: %.2f m/s (%.1f kn)" % [v_good, s.speed_knots()])
	check(v_good > 5.0, "full sail with good trim must accelerate well (got %.2f m/s)" % v_good)

	# Poor trim (yard turned sideways 1.2 rad) should noticeably lose speed.
	s.set_trim_target(1.2)
	await physics_frames(300)
	var v_bad := s.forward_speed()
	print("    poor trim speed: %.2f m/s" % v_bad)
	check(v_bad < v_good * 0.85, "poor trim (%.2f) must be slower than good trim (%.2f)" % [v_bad, v_good])

	# Turn to starboard with wheel inertia.
	s.set_trim_target(0.0)
	var yaw_before := s.rotation.y
	s.set_helm_target(1.0)
	await physics_frames(15)
	check(s.helm > 0.05 and s.helm < 0.95, "wheel must have inertia (helm=%.2f after 0.25s)" % s.helm)
	await physics_frames(160)
	var dyaw := angle_difference(yaw_before, s.rotation.y)
	print("    starboard turn dyaw: %.2f rad" % dyaw)
	# Positive helm turns starboard -> negative Y rotation in Godot (-Z forward, +X right).
	check(dyaw < -0.25, "positive helm must turn bow to starboard (dyaw=%.2f)" % dyaw)

	# Drop anchor while moving -> stops ship cleanly.
	s.set_helm_target(0.0)
	s.set_anchor(true)
	await physics_frames(240)
	var v_anchored := Vector2(s.linear_velocity.x, s.linear_velocity.z).length()
	print("    anchored speed: %.2f m/s" % v_anchored)
	check(v_anchored < 0.8, "anchor must arrest ship motion (got %.2f m/s)" % v_anchored)
	await _end()


func test_hull_damage_flood_bail_patch_and_sink() -> void:
	_begin()
	Weather.set_weather(0.0, 5.0, 0.0)
	Sea.amp_scale = 0.0
	var s := _spawn_sloop(Vector3.ZERO)
	await physics_frames(30)

	# Breach one below-waterline panel on starboard side.
	var breach_idx := s.apply_hull_damage(s.global_transform * Vector3(2.0, -0.45, 0.2), 0.5)
	check(breach_idx >= 0, "apply_hull_damage must breach a slot")
	check_eq(s.open_hole_count(), 1, "one open hole")
	var slot: Dictionary = s.holes[breach_idx]
	check(not (slot["panel"] as Node3D).visible, "HullPanel must hide on breach")
	check((slot["hole"] as Node3D).visible, "Hole must show on breach")
	check(not (slot["patch"] as Node3D).visible, "HolePatch stays hidden before repair")

	# Wait for water to flood in.
	await physics_frames(240)
	var flooded := s.water_level
	print("    after 4 s with 1 hole: water_level=%.3f" % flooded)
	check(flooded > 0.03, "unpatched submerged hole must flood the hold (got %.4f)" % flooded)

	# Bail reduces water level.
	var removed := s.bail(0.025)
	check(removed > 0.01, "bail must remove water")
	check(s.water_level < flooded - 0.01, "water_level must drop after bailing")

	# Patch stops flooding and displays HolePatch.
	var ok := s.patch_hole(breach_idx)
	check(ok, "patch_hole must succeed")
	check_eq(s.open_hole_count(), 0, "open hole count should be 0 after patch")
	check((slot["patch"] as Node3D).visible, "HolePatch must appear after repair")
	var level_after_patch := s.water_level
	await physics_frames(120)
	check_near(s.water_level, level_after_patch, 0.002, "patched hull must stop taking on water")

	# Breach multiple holes and verify sinking triggers and lowers the ship.
	var sunk_emitted := [false]
	s.sunk.connect(func() -> void: sunk_emitted[0] = true)
	for z_pos: float in [-3.2, -1.6, 0.2, 1.8, 3.2]:
		s.apply_hull_damage(s.global_transform * Vector3(2.0, -0.5, z_pos), 0.65)
		s.apply_hull_damage(s.global_transform * Vector3(-2.0, -0.5, z_pos), 0.65)
	s.water_level = 0.85
	await physics_frames(320)
	print("    after heavy flooding: is_sinking=%s y=%.2f" % [str(s.is_sinking), s.global_position.y])
	check(s.is_sinking and sunk_emitted[0], "unchecked flooding must founder the ship")
	check(s.global_position.y < -0.7, "sinking ship must settle below waterline (y=%.2f)" % s.global_position.y)
	await _end()


func test_cannon_fires_and_breaches_target_ship() -> void:
	_begin()
	Weather.set_weather(0.0, 0.0, 0.0)
	Sea.amp_scale = 0.0
	var shooter := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var target := _spawn_sloop(Vector3(26.0, 0.0, -1.5))
	await physics_frames(40)

	var ammo_before := shooter.cannonballs_remaining
	shooter.aim_cannon(&"starboard", 0.0, -0.02)
	await physics_frames(2)
	var ball := shooter.fire_cannon(&"starboard")
	check(ball != null, "fire_cannon must spawn a Cannonball")
	check_eq(shooter.cannonballs_remaining, ammo_before - 1, "firing consumes 1 cannonball")

	var hit := [false]
	target.hull_breached.connect(func(_idx: int, _p: Vector3) -> void: hit[0] = true)
	for _i in 120:
		await physics_frames(1)
		if hit[0]:
			break
	print("    cannon hit target: %s open_holes=%d" % [str(hit[0]), target.open_hole_count()])
	check(hit[0] and target.open_hole_count() >= 1, "cannonball must strike and breach target sloop")
	await _end()


func test_pawn_walks_sailing_sloop_in_waves() -> void:
	_begin()
	Weather.set_weather(0.35, 11.0, 0.2)
	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, 0.35)
	Sea.time = 15.0
	var s := _spawn_sloop(Vector3(0.0, Sea.height(0.0, 0.0), 0.0))
	s.set_sail_target(0.85)
	s.set_trim_target(0.0)
	await physics_frames(80)

	var pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pawn)
	pawn.board(s, Vector3(0.0, 2.05, 5.4))
	await physics_frames(30)

	# 1. Idle riding check on sailing sloop in real waves.
	var ref_local := pawn.ride_local_position()
	var max_drift := 0.0
	for _i in 90:
		await physics_frames(1)
		max_drift = maxf(max_drift, pawn.ride_local_position().distance_to(ref_local))
	print("    pawn idle on sailing sloop in waves: max drift %.2f mm, ship speed %.2f m/s" % [
		max_drift * 1000.0, s.forward_speed()])
	check(pawn.platform == s, "pawn must stay anchored to sloop")
	check(max_drift < 0.05, "idle pawn drifted %.3f m on sailing sloop" % max_drift)

	# 2. Walk quarterdeck -> starboard stairs -> main deck -> hold -> main deck.
	var route: Array[Vector3] = [
		Vector3(1.4, 2.0, 4.3),
		Vector3(1.4, 1.1, 2.2),
		Vector3(0.0, 1.1, 2.62),
		Vector3(0.0, -0.85, -0.3),
		Vector3(0.8, -0.85, 2.2),
	]
	for idx in route.size():
		var local_goal: Vector3 = route[idx]
		var ticks := 0
		while ticks < 480:
			var cur_local := pawn.platform_local_position()
			var d_local := local_goal - cur_local
			d_local.y = 0.0
			if d_local.length() < 0.38:
				break
			var d_world := s.global_basis * d_local
			d_world.y = 0.0
			pawn.wish_dir = d_world.normalized() if d_world.length_squared() > 0.0001 else Vector3.ZERO
			await physics_frames(1)
			ticks += 1
		pawn.wish_dir = Vector3.ZERO
		check(ticks < 480, "pawn stuck reaching sloop waypoint %d %s (at %s)" % [idx, local_goal, pawn.platform_local_position()])
		check(pawn.platform == s, "pawn fell off sloop at waypoint %d" % idx)
	await _end()


func test_net_state_roundtrip() -> void:
	_begin()
	Sea.amp_scale = 0.0
	var a := _spawn_sloop(Vector3(12.0, 0.1, -18.0))
	var b := _spawn_sloop(Vector3.ZERO)
	await physics_frames(10)

	a.helm = 0.45
	a.helm_target = 0.6
	a.sail_set = 0.75
	a.sail_target = 0.8
	a.sail_trim = -0.55
	a.trim_target = -0.55
	a.anchor_down = true
	a.anchor_progress = 0.9
	a.water_level = 0.42
	var h0 := a.apply_hull_damage(a.global_transform * Vector3(2.0, -0.4, 0.5), 0.5)
	var h1 := a.apply_hull_damage(a.global_transform * Vector3(-2.0, -0.4, -1.5), 0.5)
	a.patch_hole(h1)

	var snap := a.get_net_state()
	b.apply_net_state(snap)

	check_near(b.global_position.distance_to(a.global_position), 0.0, 0.01, "origin synced")
	check_near(b.helm, 0.45, 0.001, "helm synced")
	check_near(b.sail_set, 0.75, 0.001, "sail_set synced")
	check_near(b.sail_trim, -0.55, 0.001, "sail_trim synced")
	check_eq(b.anchor_down, true, "anchor_down synced")
	check_near(b.water_level, 0.42, 0.001, "water_level synced")
	check(bool(b.holes[h0]["breached"]) and not bool(b.holes[h0]["patched"]), "open breach synced")
	check(bool(b.holes[h1]["breached"]) and bool(b.holes[h1]["patched"]), "patched breach synced")
	await _end()


func test_brigantine_dual_masts_four_cannons_and_sailing() -> void:
	_begin()
	Weather.set_weather(0.0, 12.0, 0.0)
	Sea.amp_scale = Sea.AMP_CALM
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	check(brig_scene != null, "brigantine.tscn loads cleanly")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(0.0, Sea.height(0.0, 0.0), 0.0)
	await physics_frames(45)

	check_eq(brig.ship_class, &"brigantine", "ship_class is brigantine")
	check(brig.get_station(&"helm") != null, "brigantine has helm station")
	check(brig.get_station(&"cannon", &"port") != null, "brigantine has fore port cannon")
	check(brig.get_station(&"cannon", &"starboard") != null, "brigantine has fore starboard cannon")
	check(brig.get_station(&"cannon", &"port_aft") != null, "brigantine has aft port cannon")
	check(brig.get_station(&"cannon", &"starboard_aft") != null, "brigantine has aft starboard cannon")
	check_eq(brig.holes.size(), 10, "brigantine has 10 breach slots")

	# Both broadside starboard cannons fire cleanly.
	var b1 := brig.fire_cannon(&"starboard")
	var b2 := brig.fire_cannon(&"starboard_aft")
	check(b1 != null and b2 != null, "brigantine fires twin broadside cannons")

	# Full sails catch wind and achieve higher Brigantine top speed while staying upright.
	brig.set_sail_target(1.0)
	brig.set_trim_target(brig.ideal_sail_trim())
	brig.apply_livery(Color(0.9, 0.85, 0.72), Color(0.18, 0.56, 0.64))
	await physics_frames(220)
	var spd := brig.forward_speed()
	print("    brigantine downwind speed: %.2f m/s (%.1f kn) up.y=%.3f" % [spd, brig.speed_knots(), brig.global_basis.y.y])
	check(spd > 6.0, "brigantine sails briskly downwind (got %.2f m/s)" % spd)
	check(brig.global_basis.y.y > 0.90, "brigantine stays upright in waves")
	await _end()

