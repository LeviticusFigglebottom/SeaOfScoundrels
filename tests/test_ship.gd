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
	check_eq(ladders, 3, "sloop must create port, starboard, and crow's nest Ladder nodes")
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
		var bow_w := s.global_transform * s.ship_point(Vector3(0.0, 0.0, -5.5))
		var stern_w := s.global_transform * s.ship_point(Vector3(0.0, 0.0, 5.5))
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
	await physics_frames(380)
	var v_good := s.forward_speed()
	print("    downwind good trim speed: %.2f m/s (%.1f kn)" % [v_good, s.speed_knots()])
	check(v_good > 4.8, "full sail with good trim must accelerate well (got %.2f m/s)" % v_good)

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
	var breach_idx := s.apply_hull_damage(s.global_transform * s.ship_point(Vector3(2.0, -0.45, 0.2)), 0.5)
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
		s.apply_hull_damage(s.global_transform * s.ship_point(Vector3(2.0, -0.5, z_pos)), 0.65)
		s.apply_hull_damage(s.global_transform * s.ship_point(Vector3(-2.0, -0.5, z_pos)), 0.65)
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
	pawn.board(s, s.ship_point(Vector3(0.0, 2.05, 5.4)))
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
		s.ship_point(Vector3(1.4, 2.0, 4.3)),
		s.ship_point(Vector3(1.4, 1.1, 2.2)),
		s.ship_point(Vector3(0.0, 1.1, 2.62)),
		s.ship_point(Vector3(0.0, -0.85, -0.3)),
		s.ship_point(Vector3(0.8, -0.85, 2.2)),
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
	var h0 := a.apply_hull_damage(a.global_transform * a.ship_point(Vector3(2.0, -0.4, 0.5)), 0.5)
	var h1 := a.apply_hull_damage(a.global_transform * a.ship_point(Vector3(-2.0, -0.4, -1.5)), 0.5)
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

	# Full sails catch wind and achieve authentic weighty Brigantine top speed while staying upright.
	brig.set_sail_target(1.0)
	brig.set_trim_target(brig.ideal_sail_trim())
	brig.apply_livery(Color(0.9, 0.85, 0.72), Color(0.18, 0.56, 0.64))
	await physics_frames(360)
	var spd := brig.forward_speed()
	print("    brigantine downwind speed: %.2f m/s (%.1f kn) up.y=%.3f" % [spd, brig.speed_knots(), brig.global_basis.y.y])
	check(spd >= 6.1 and spd <= 8.2, "brigantine sails in weighty downwind speed band (got %.2f m/s)" % spd)
	check(brig.global_basis.y.y > 0.90, "brigantine stays upright in waves")
	await _end()


func test_patch_bail_vfx_and_wind_caught_signal() -> void:
	_begin()
	Weather.set_weather(0.0, 12.0, 0.0)
	Sea.amp_scale = 0.0
	var s := SLOOP_SCENE.instantiate() as Ship
	s.enable_effects = true
	_root.add_child(s)
	s.global_position = Vector3.ZERO
	await physics_frames(8)

	# 1. patch_hole() spawns oak sawdust + hammer-spark burst VFX tracked for leak-free cleanup.
	var h_idx := s.apply_hull_damage(s.global_transform * s.ship_point(Vector3(1.9, -0.35, 0.4)), 0.5)
	check(h_idx >= 0, "hull breach created before patch")
	check(s.patch_hole(h_idx), "patch_hole succeeds")
	var patch_fx := s.get_node_or_null(^"PatchBurstVFX") as Node3D
	check(patch_fx != null and is_instance_valid(patch_fx), "PatchBurstVFX spawned on patch_hole")
	var sawdust := patch_fx.get_node_or_null(^"PatchSawdust") as GPUParticles3D if patch_fx != null else null
	var sparks := patch_fx.get_node_or_null(^"HammerSparks") as GPUParticles3D if patch_fx != null else null
	check(sawdust != null and sawdust.one_shot and sawdust.emitting, "PatchSawdust GPUParticles3D emits one-shot burst")
	check(sparks != null and sparks.one_shot and sparks.amount >= 6 and sparks.amount <= 8, "HammerSparks emits 6-8 bright hammer-nail spark motes")

	# 2. bail() removes flood water and spawns BilgeBailSplashVFX; bailing dry spawns nothing.
	s.water_level = 0.35
	var removed := s.bail(0.14)
	check_near(removed, 0.14, 0.005, "bail removes expected flood water")
	var bail_fx := s.get_node_or_null(^"BilgeBailSplashVFX") as Node3D
	check(bail_fx != null and is_instance_valid(bail_fx), "BilgeBailSplashVFX spawned on bail")
	var splash := bail_fx.get_node_or_null(^"BailSplashPuff") as GPUParticles3D if bail_fx != null else null
	check(splash != null and splash.one_shot and splash.emitting, "BailSplashPuff GPUParticles3D emits splash puff")

	# Wait for transient timers to auto-free both bursts cleanly (at 6x test speedup, 0.55 s ~= 60 ticks).
	await physics_frames(240)
	check(not is_instance_valid(patch_fx) and not is_instance_valid(bail_fx), "patch & bail VFX auto-clean after burst lifetime")

	# 3. wind_caught(efficiency) fires once on reaching peak wind trim, respects hysteresis (no spam), and re-arms after furling.
	var caught_events: Array[float] = []
	s.wind_caught.connect(func(eff: float) -> void: caught_events.append(eff))
	s.set_sail_target(1.0)
	s.set_trim_target(s.ideal_sail_trim())
	await physics_frames(150)
	check_eq(caught_events.size(), 1, "wind_caught fires exactly once upon reaching peak wind (no spam)")
	if not caught_events.is_empty():
		check(caught_events[0] >= 0.88, "wind_caught reports peak efficiency >= 0.88 (got %.2f)" % caught_events[0])

	# Furl sails to drop below hysteresis threshold, then re-raise to verify clean re-arming.
	s.set_sail_target(0.0)
	await physics_frames(160)
	check_eq(caught_events.size(), 1, "furling sails does not spuriously emit wind_caught")
	s.set_sail_target(1.0)
	s.set_trim_target(s.ideal_sail_trim())
	await physics_frames(150)
	check_eq(caught_events.size(), 2, "wind_caught re-arms cleanly after furling and re-catching peak wind")

	# 4. Early ship teardown mid-burst frees active patch & bail VFX cleanly with zero leaks!
	var h2 := s.apply_hull_damage(s.global_transform * s.ship_point(Vector3(-1.9, -0.35, -0.8)), 0.5)
	check(s.patch_hole(h2), "second patch_hole succeeds before teardown")
	s.water_level = 0.25
	check(s.bail(0.14) > 0.01, "second bail succeeds before teardown")
	var live_patch := s.get_node_or_null(^"PatchBurstVFX") as Node3D
	var live_bail := s.get_node_or_null(^"BilgeBailSplashVFX") as Node3D
	check(live_patch != null and live_bail != null, "fresh patch & bail bursts active right before ship exit")
	await _end()
	check(not is_instance_valid(live_patch) and not is_instance_valid(live_bail), "mid-burst patch & bail VFX freed cleanly on Ship _exit_tree()")


func test_emissary_streamer_and_trading_company_sail_emblems() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 12.0, PI * 0.5)

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(24.0, 0.0, 0.0)
	await physics_frames(4)

	# 1. Verify EmissaryStreamer mounts cleanly above mainmast Flag on both Sloop & Brigantine!
	var sloop_tris := 0
	var brig_tris := 0
	for spec: Array in [[sloop, "sloop", 4.2, 4.6], [brig, "brigantine", 5.2, 5.6]]:
		var sh: Ship = spec[0] as Ship
		var lbl: String = String(spec[1])
		var min_len: float = float(spec[2])
		var max_len: float = float(spec[3])
		var streamer := sh.find_child("EmissaryStreamer", true, false) as MeshInstance3D
		check(streamer != null and streamer == sh._emissary_streamer,
			"%s mounts EmissaryStreamer MeshInstance3D" % lbl)
		if streamer != null:
			check(streamer.mesh is ArrayMesh and not (streamer.mesh is PrimitiveMesh),
				"%s EmissaryStreamer uses sculpted ArrayMesh (zero primitives)" % lbl)
			check_eq(streamer.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s EmissaryStreamer disables shadows" % lbl)
			var smat := streamer.material_override as ShaderMaterial
			check(smat != null and smat.shader == Ship.SAIL_WIND_SHADER,
				"%s EmissaryStreamer binds sail_wind.gdshader" % lbl)
			if smat != null:
				check_near(float(smat.get_shader_parameter(&"is_flag")), 1.0, 0.01,
					"%s EmissaryStreamer runs in flag ripple mode (is_flag=1.0)" % lbl)
			if streamer.mesh is ArrayMesh:
				var am := streamer.mesh as ArrayMesh
				var aabb := am.get_aabb()
				check(aabb.size.z >= min_len and aabb.size.z <= max_len,
					"%s EmissaryStreamer length %.2f m within expected %.1f..%.1f m" % [lbl, aabb.size.z, min_len, max_len])
				var arr := am.surface_get_arrays(0)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var tris := floori(float(verts.size()) / 3.0)
				var bad_n := 0
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_n += 1
				check_eq(bad_n, 0, "%s EmissaryStreamer normals are all finite unit vectors" % lbl)
				if lbl == "sloop":
					sloop_tris = tris
				else:
					brig_tris = tris
			if not sh._flags.is_empty():
				check_near(streamer.position.y, sh._flags[0].position.y + 0.55, 0.02,
					"%s EmissaryStreamer sits cleanly 0.55 m above mainmast Flag" % lbl)
	print("    EmissaryStreamer sculpted tris: sloop=%d, brigantine=%d" % [sloop_tris, brig_tris])

	# 2. Verify EmissaryStreamer weathervanes smoothly into crosswind alongside mainmast Flag!
	var yaw0 := sloop._emissary_streamer.rotation.y
	Weather.set_weather(0.0, 14.0, -PI * 0.5)
	await physics_frames(60)
	var yaw1 := sloop._emissary_streamer.rotation.y
	check(absf(angle_difference(yaw0, yaw1)) > 0.6,
		"EmissaryStreamer weathervanes into shifting crosswind (%.2f -> %.2f rad)" % [yaw0, yaw1])

	# 3. Verify apply_livery 5th parameter cleanly applies Trading Company emblem modes 4, 5, 6, 7 & default -1!
	for mode_i: int in [4, 5, 6, 7]:
		sloop.apply_livery(Color.WHITE, Color(0.92, 0.74, 0.24), Color.BLACK, Color.WHITE, mode_i)
		check_eq(sloop.get_emblem_mode(), mode_i, "get_emblem_mode() reports %d" % mode_i)
		check(not sloop._sail_mats.is_empty(), "sloop has active _sail_mats")
		for sm in sloop._sail_mats:
			check_eq(int(sm.get_shader_parameter(&"emblem_mode")), mode_i,
				"sail ShaderMaterial receives emblem_mode=%d" % mode_i)
		for fm in sloop._flag_mats:
			check_eq(int(fm.get_shader_parameter(&"emblem_mode")), mode_i,
				"flag/streamer ShaderMaterial receives emblem_mode=%d" % mode_i)

	sloop.apply_livery(Color.WHITE, Color.WHITE, Color.BLACK, Color.WHITE, -1)
	check_eq(sloop.get_emblem_mode(), 0, "sail_emblem_mode=-1 restores faction default (0 for player)")

	await _end()
	check(Ship._streamer_mesh_sloop == null and Ship._streamer_mesh_brig == null,
		"Ship releases static EmissaryStreamer mesh caches cleanly when last ship exits tree")


func test_anchor_turn_swinging_stop_rotates_hull() -> void:
	_begin()
	Weather.set_weather(0.0, 11.0, 0.0)
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	var s_straight := _spawn_sloop(Vector3(-25.0, 0.0, 0.0))
	var s_turn := _spawn_sloop(Vector3(25.0, 0.0, 0.0))
	await physics_frames(20)

	# Accelerate both sloops smoothly downwind past 4.5 m/s.
	for sh: Ship in [s_straight, s_turn]:
		sh.set_sail_target(1.0)
		sh.set_trim_target(0.0)
		sh.set_helm_target(0.0)
	await physics_frames(300)
	check(s_turn.forward_speed() >= 4.5, "sloop reaches speed >= 4.5 m/s before anchor drop (got %.2f)" % s_turn.forward_speed())

	var straight_events: Array[Array] = []
	var turn_events: Array[Array] = []
	s_straight.anchor_turn_triggered.connect(func(spd: float, ydir: float) -> void: straight_events.append([spd, ydir]))
	s_turn.anchor_turn_triggered.connect(func(spd: float, ydir: float) -> void: turn_events.append([spd, ydir]))

	var yaw_straight0 := s_straight.rotation.y
	var yaw_turn0 := s_turn.rotation.y

	# Straight-ahead anchor drop vs hard-starboard anchor-turn drop!
	s_straight.set_helm_target(0.0)
	s_straight.set_anchor(true)
	s_turn.set_helm_target(1.0)
	s_turn.set_anchor(true)

	await physics_frames(240)

	var dyaw_straight := absf(angle_difference(yaw_straight0, s_straight.rotation.y))
	var dyaw_turn_signed := angle_difference(yaw_turn0, s_turn.rotation.y)
	var dyaw_turn := absf(dyaw_turn_signed)
	var stop_spd_turn := Vector2(s_turn.linear_velocity.x, s_turn.linear_velocity.z).length()
	var stop_spd_straight := Vector2(s_straight.linear_velocity.x, s_straight.linear_velocity.z).length()
	print("    anchor-turn: straight_dyaw=%.2f rad, turn_dyaw=%.2f rad (signed=%.2f), stop_spd=%.2f m/s" % [
		dyaw_straight, dyaw_turn, dyaw_turn_signed, stop_spd_turn])

	check_eq(straight_events.size(), 0, "straight-ahead anchor drop does not emit anchor_turn_triggered")
	check_eq(turn_events.size(), 1, "hard-rudder high-speed anchor drop emits anchor_turn_triggered once")
	if not turn_events.is_empty():
		check(float(turn_events[0][0]) >= 3.0, "anchor_turn_triggered reports entry speed >= 3.0 m/s")
		check(float(turn_events[0][1]) < 0.0, "starboard anchor-turn reports negative Y yaw_dir")
	check(dyaw_turn > dyaw_straight + 0.55 and dyaw_turn_signed < -0.55,
		"anchor-turn swings bow sharply to starboard vs straight drop (%.2f vs %.2f rad)" % [dyaw_turn, dyaw_straight])
	check(stop_spd_turn < 0.9 and stop_spd_straight < 0.9,
		"both ships settle cleanly to a stop after anchor bite (turn=%.2f, straight=%.2f m/s)" % [stop_spd_turn, stop_spd_straight])

	# Verify Sunken Archive (emblem_mode 5) does not flood non-archive flag/sail mats with bright blanket glow.
	s_turn.apply_livery(Color.WHITE, Color(0.16, 0.88, 0.74), Color(0.16, 0.88, 0.74), Color(0.58, 0.94, 0.84), 5)
	check_eq(s_turn.get_emblem_mode(), 5, "Sunken Archive sets emblem_mode 5")
	for fm in s_turn._flag_mats:
		check_near(float(fm.get_shader_parameter(&"emission_strength")), 0.0, 0.01,
			"Trading Company mode 5 suppresses blanket flat emission on flags/streamer")

	await _end()


func test_cabin_furnishings_and_rival_lookout_glint() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Weather.time_of_day = 12.0  # High noon daylight

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(26.0, 0.0, 0.0)

	var corsair := SLOOP_SCENE.instantiate() as Ship
	corsair.faction = &"corsair"
	corsair.enable_effects = true
	_root.add_child(corsair)
	corsair.global_position = Vector3(0.0, 0.0, -160.0)
	await physics_frames(2)

	# 1. Verify CaptainCabinFurnishings mounts on BOTH player Sloop & Brigantine, NOT on rival Corsair.
	check(sloop.cabin_furnishings != null, "player Sloop auto-mounts CaptainCabinFurnishings")
	check(brig.cabin_furnishings != null, "player Brigantine auto-mounts CaptainCabinFurnishings")
	check(corsair.cabin_furnishings == null, "rival Corsair ship does not mount player cabin furnishings")

	var furn := brig.cabin_furnishings
	check(furn.astrolabe_stand != null and furn.astrolabe_rings != null and furn.orrery_globe != null,
		"CaptainCabinFurnishings builds AstrolabeStand, AstrolabeRings, and OrreryGlobe")
	check(furn.trophy_lectern != null and furn.candle_light != null,
		"CaptainCabinFurnishings builds TrophyLectern and CabinCandleLight")
	for comp_name: String in ["Medallion_gilded_compass", "Medallion_sunken_archive", "Medallion_iron_tide"]:
		check(furn.find_child(comp_name, true, false) is MeshInstance3D,
			"CaptainCabinFurnishings builds sculpted %s" % comp_name)

	# 2. Verify zero raw PrimitiveMeshes, finite unit normals, and vertex_color_is_srgb = true across ALL materials!
	var raw_prims := 0
	var bad_normals := 0
	var total_tris := 0
	var srgb_missing := 0
	for n in furn.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
		var am := mi.mesh as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				total_tris += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
				var mat := mi.get_surface_override_material(si) as StandardMaterial3D
				if mat == null:
					mat = mi.material_override as StandardMaterial3D
				if mat != null and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb:
					srgb_missing += 1
	print("    CaptainCabinFurnishings total sculpted tris: %d" % total_tris)
	check_eq(raw_prims, 0, "CaptainCabinFurnishings contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "CaptainCabinFurnishings normals are all finite unit vectors")
	check_eq(srgb_missing, 0, "all CaptainCabinFurnishings vertex-colored materials enable vertex_color_is_srgb")
	check(total_tris >= 900, "CaptainCabinFurnishings has rich sculpted geometry (%d tris)" % total_tris)

	# 3. Verify AstrolabeRings & OrreryGlobe spin smoothly over process frames!
	var ry0 := furn.astrolabe_rings.rotation.y
	var gy0 := furn.orrery_globe.rotation.y
	await get_tree().process_frame
	await get_tree().process_frame
	check(furn.astrolabe_rings.rotation.y != ry0, "AstrolabeRings spins smoothly in _process")
	check(furn.orrery_globe.rotation.y != gy0, "OrreryGlobe counter-rotates smoothly in _process")

	# 4. Verify sync_renown toggles medallions per Trading Company renown & force_all showcases all 3!
	var prof := Profile.new()
	prof.add_renown("gilded_compass", 300)  # >= 250 -> shown + gleaming
	prof.add_renown("sunken_archive", 80)   # >= 50 -> shown
	# iron_tide stays 0 -> hidden!
	brig.sync_cabin_renown(prof, false)
	check((furn.medallions[&"gilded_compass"] as MeshInstance3D).visible, "gilded_compass medallion visible at 300 renown")
	check((furn.medallions[&"sunken_archive"] as MeshInstance3D).visible, "sunken_archive medallion visible at 80 renown")
	check(not (furn.medallions[&"iron_tide"] as MeshInstance3D).visible, "iron_tide medallion hidden at 0 renown")

	brig.sync_cabin_renown(prof, true)
	check((furn.medallions[&"iron_tide"] as MeshInstance3D).visible, "force_all = true reveals all 3 company medallions")

	# 5. Verify AstrolabeInteractable boosts spin cleanly on interaction!
	check(furn.astrolabe_interactable != null, "AstrolabeInteractable exists")
	furn.astrolabe_interactable.interact(null)
	check(furn._spin_boost >= 2.5, "interacting with AstrolabeInteractable boosts spin velocity (%.2f)" % furn._spin_boost)

	# 6. Verify Distant Rival Lookout Spyglass Glint (LookoutGlint)!
	check(sloop.get_node_or_null(^"LookoutGlint") == null, "player ship does NOT mount rival LookoutGlint")
	var glint := corsair.get_node_or_null(^"LookoutGlint") as MeshInstance3D
	check(glint != null and glint.mesh is ArrayMesh, "rival Corsair ship mounts sculpted ArrayMesh LookoutGlint")

	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.global_position = Vector3(0.0, 4.0, 0.0)
	cam.current = true
	await get_tree().process_frame

	# At 160 m in bright noon daylight & peak flash phase -> glint becomes visible!
	Weather.time_of_day = 12.0
	corsair._lookout_glint_phase = (PI * 0.5) / 1.38
	corsair._update_visuals(0.0)
	check(glint.visible, "LookoutGlint flashes visible at 160 m in daylight")

	# At midnight -> glint hides completely!
	Weather.time_of_day = 0.0
	corsair._lookout_glint_phase = (PI * 0.5) / 1.38
	corsair._update_visuals(0.0)
	check(not glint.visible, "LookoutGlint hides at midnight")

	# During daylight when sinking -> glint hides completely!
	Weather.time_of_day = 12.0
	corsair.is_sinking = true
	corsair._lookout_glint_phase = (PI * 0.5) / 1.38
	corsair._update_visuals(0.0)
	check(not glint.visible, "LookoutGlint hides when rival ship is sinking")

	await _end()
	check(CaptainCabinFurnishings._astrolabe_base_mesh == null and CaptainCabinFurnishings._lectern_mesh == null,
		"CaptainCabinFurnishings releases static mesh caches cleanly on teardown")
	check(Ship._lookout_glint_mesh == null and Ship._lookout_glint_shader == null,
		"Ship releases static LookoutGlint caches cleanly when last ship exits tree")



func test_livery_net_state_replication_roundtrip() -> void:
	_begin()
	Sea.amp_scale = 0.0
	var host_ship := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var client_ship := _spawn_sloop(Vector3(24.0, 0.0, 0.0))
	await physics_frames(8)

	check_eq(client_ship.get_emblem_mode(), 0, "client ship starts at default player emblem_mode 0")

	# Host commissions Sunken Archive livery (emblem_mode = 5) with custom tints & glow accent.
	var s_col := Color(0.92, 0.96, 0.94)
	var f_col := Color(0.14, 0.84, 0.72)
	var g_col := Color(0.16, 0.88, 0.74)
	var h_col := Color(0.58, 0.94, 0.84)
	host_ship.apply_livery(s_col, f_col, g_col, h_col, 5)

	var snap := host_ship.get_net_state()
	check_eq(int(snap.get("emblem_mode", -1)), 5, "get_net_state exports emblem_mode = 5")
	check((snap.get("sail_tint", Color.BLACK) as Color).is_equal_approx(s_col), "get_net_state exports sail_tint")
	check((snap.get("flag_tint", Color.BLACK) as Color).is_equal_approx(f_col), "get_net_state exports flag_tint")
	check((snap.get("hull_tint", Color.BLACK) as Color).is_equal_approx(h_col), "get_net_state exports hull_tint")
	check((snap.get("glow_accent", Color.WHITE) as Color).is_equal_approx(g_col), "get_net_state exports glow_accent")

	# Apply snapshot to client sloop and verify full visual/shader sync.
	client_ship.apply_net_state(snap)
	check_eq(client_ship.get_emblem_mode(), 5, "client ship syncs emblem_mode = 5")
	check(client_ship._livery_sail_tint.is_equal_approx(s_col), "client ship syncs _livery_sail_tint")
	check(client_ship._livery_flag_tint.is_equal_approx(f_col), "client ship syncs _livery_flag_tint")
	check(client_ship._livery_hull_tint.is_equal_approx(h_col), "client ship syncs _livery_hull_tint")
	check(client_ship._livery_glow_accent.is_equal_approx(g_col), "client ship syncs _livery_glow_accent")
	for sm in client_ship._sail_mats:
		check_eq(int(sm.get_shader_parameter(&"emblem_mode")), 5, "client sail ShaderMaterial synced to emblem_mode = 5")
	for fm in client_ship._flag_mats:
		check_eq(int(fm.get_shader_parameter(&"emblem_mode")), 5, "client flag ShaderMaterial synced to emblem_mode = 5")

	# Steady-state repeat snapshot is a clean no-op, and subsequent livery swap replicates immediately.
	client_ship.apply_net_state(snap)
	check_eq(client_ship.get_emblem_mode(), 5, "repeat snapshot preserves emblem_mode = 5")

	var iron_hull := Color(1.0, 0.56, 0.48)
	var iron_flag := Color(0.84, 0.16, 0.18)
	host_ship.apply_livery(Color(0.96, 0.88, 0.86), iron_flag, Color.BLACK, iron_hull, 6)
	client_ship.apply_net_state(host_ship.get_net_state())
	check_eq(client_ship.get_emblem_mode(), 6, "subsequent livery change replicates emblem_mode = 6")
	check(client_ship._livery_hull_tint.is_equal_approx(iron_hull), "subsequent hull_tint replicates cleanly")
	check(client_ship._livery_flag_tint.is_equal_approx(iron_flag), "subsequent flag_tint replicates cleanly")

	await _end()


func test_interactive_ship_bell_swing_signal_and_zero_primitives() -> void:
	_begin()
	Sea.amp_scale = 0.0
	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(28.0, 0.0, 0.0)

	var corsair := SLOOP_SCENE.instantiate() as Ship
	corsair.faction = &"corsair"
	corsair.enable_effects = false
	_root.add_child(corsair)
	corsair.global_position = Vector3(-28.0, 0.0, 0.0)
	await physics_frames(4)

	# 1. Verify ShipBell mounts on player Sloop & Brigantine rail positions, NOT on rival ships.
	check(sloop.ship_bell_node != null and sloop.ship_bell_interactable != null,
		"player Sloop mounts sculpted ShipBell and ShipBellInteractable")
	check(brig.ship_bell_node != null and brig.ship_bell_interactable != null,
		"player Brigantine mounts sculpted ShipBell and ShipBellInteractable")
	check(corsair.ship_bell_node == null, "rival Corsair ship does not mount player ShipBell")
	check(sloop.ship_bell_node.position.is_equal_approx(sloop.ship_point(Vector3(0.0, 2.86, 2.98))),
		"Sloop ShipBell mounts atop quarterdeck front balustrade rail")
	check(brig.ship_bell_node.position.is_equal_approx(brig.ship_point(Vector3(0.0, 3.08, 3.98))),
		"Brigantine ShipBell mounts atop quarterdeck front balustrade rail")
	check(sloop.ship_bell_node.scale.is_equal_approx(Vector3.ONE * sloop.hull_scale),
		"Sloop ShipBell scales cleanly with hull_scale")
	check_eq(sloop.ship_bell_interactable.prompt, "Ring ship's bell", "ShipBell interactable prompt matches")
	check_near(sloop.ship_bell_interactable.reach, 1.65, 0.01, "ShipBell interactable reach is 1.65 m")
	check(Audio.has_sound(&"ship_bell"), "Audio catalogue registers synthesized maritime ship_bell SFX")

	# 2. Verify zero raw PrimitiveMeshes, finite unit normals, and vertex_color_is_srgb = true!
	var raw_prims := 0
	var bad_normals := 0
	var srgb_missing := 0
	var total_tris := 0
	for n in brig.ship_bell_node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
		var am := mi.mesh as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				total_tris += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_normals += 1
				var mat := mi.material_override as StandardMaterial3D
				if mat != null and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb:
					srgb_missing += 1
	print("    ShipBell sculpted tris: %d" % total_tris)
	check_eq(raw_prims, 0, "ShipBell contains zero raw PrimitiveMeshes")
	check_eq(bad_normals, 0, "ShipBell normals are finite unit vectors")
	check_eq(srgb_missing, 0, "ShipBell materials enable vertex_color_is_srgb = true")
	check(total_tris >= 350, "ShipBell has sculpted flat-faceted belfry & bronze cup detail (%d >= 350 tris)" % total_tris)

	# 3. Verify Brigantine cabin hammock & bilge-wall flush clearance + softened candlelight polish.
	var furn := brig.cabin_furnishings
	check(furn != null and furn.trophy_lectern.position.is_equal_approx(Vector3(-0.56, -0.95, 5.45)),
		"Brigantine TrophyLectern seated flush inboard clear of crew hammocks & hull wall")
	check(furn != null and furn.astrolabe_stand.position.is_equal_approx(Vector3(0.58, -0.95, 5.45)),
		"Brigantine AstrolabeStand seated flush inboard clear of crew hammocks & hull wall")
	check(furn != null and furn.candle_light != null and furn.candle_light.light_energy <= 0.70 and furn.candle_light.omni_range <= 3.3,
		"CabinCandleLight softened to prevent hammock highlight blowout")

	# 4. Verify ring_bell() emits ship_bell_rung & drives damped pendulum oscillation on ShipBellPivot.
	var rung_pawns: Array[Node] = []
	brig.ship_bell_rung.connect(func(by_p: Node) -> void: rung_pawns.append(by_p))
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.global_position = brig.ship_bell_node.global_position + Vector3(0.0, -0.5, 0.9)
	brig.ship_bell_interactable.interact(captain)
	check_eq(rung_pawns.size(), 1, "ShipBell interact emits ship_bell_rung once")
	if not rung_pawns.is_empty():
		check_eq(rung_pawns[0], captain, "ship_bell_rung passes ringing pawn")

	var pivot := brig.ship_bell_node.get_node_or_null(^"ShipBellPivot") as Node3D
	check(pivot != null, "ShipBell exposes ShipBellPivot for pendulum swing")
	var peak_pos := 0.0
	var peak_neg := 0.0
	for _i in 45:
		brig._update_visuals(1.0 / 30.0)
		if pivot != null:
			peak_pos = maxf(peak_pos, pivot.rotation.x)
			peak_neg = minf(peak_neg, pivot.rotation.x)
	check(peak_pos > 0.25 and peak_neg < -0.10,
		"ShipBell swings back and forth with damped harmonic pendulum (pos=%.2f, neg=%.2f)" % [peak_pos, peak_neg])
	for _i in 75:
		brig._update_visuals(1.0 / 30.0)
	check(pivot != null and absf(pivot.rotation.x) < 0.12,
		"ShipBell pendulum damps cleanly toward rest (rot=%.3f)" % (pivot.rotation.x if pivot != null else 99.0))

	# 5. Clean teardown releases all static ShipBell meshes & materials with zero leaks.
	await _end()
	check(Ship._bell_frame_mesh == null and Ship._bell_cup_mesh == null \
		and Ship._bell_iron_mat == null and Ship._bell_bronze_mat == null,
		"Ship releases static ShipBell mesh & material caches cleanly when last ship exits tree")


func test_sculpted_bow_hull_crest_medallions_liveries_and_teardown() -> void:
	_begin()
	Sea.amp_scale = 0.0

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(26.0, 0.0, 0.0)

	var ghost := SLOOP_SCENE.instantiate() as Ship
	ghost.faction = &"ghost"
	ghost.enable_effects = false
	_root.add_child(ghost)
	ghost.global_position = Vector3(-26.0, 0.0, 0.0)

	var drowned := SLOOP_SCENE.instantiate() as Ship
	drowned.faction = &"drowned"
	drowned.enable_effects = false
	_root.add_child(drowned)
	drowned.global_position = Vector3(0.0, 0.0, -32.0)
	await physics_frames(4)

	# 1. Mounted on ALL ships (player Sloop, player Brigantine, Ghost & Drowned enemies),
	# strictly 1 MeshInstance3D draw call (2 surfaces), zero raw PrimitiveMeshes, >= 240 tris!
	var sloop_tris := 0
	var brig_tris := 0
	for spec: Array in [[sloop, "sloop", -4.25, 1.62], [brig, "brigantine", -6.30, 1.92], [drowned, "drowned", -4.25, 1.62]]:
		var sh := spec[0] as Ship
		var lbl := String(spec[1])
		var exp_z := float(spec[2])
		var exp_y := float(spec[3])
		var crest := sh.hull_crest
		check(crest != null and is_instance_valid(crest), "%s mounts HullCrest node" % lbl)
		if crest == null:
			continue
		var mis := crest.find_children("*", "MeshInstance3D", true, false)
		check_eq(mis.size(), 1, "%s HullCrest uses strictly 1 MeshInstance3D draw-call node" % lbl)
		var tris := int(crest.call(&"get_triangle_count"))
		check(tris >= 240, "%s HullCrest has rich sculpted geometry (%d >= 240 tris)" % [lbl, tris])
		if lbl == "sloop":
			sloop_tris = tris
		elif lbl == "brigantine":
			brig_tris = tris

		var mi := mis[0] as MeshInstance3D
		check(mi.mesh is ArrayMesh and not (mi.mesh is PrimitiveMesh),
			"%s HullCrest uses sculpted ArrayMesh (zero PrimitiveMeshes)" % lbl)
		var am := mi.mesh as ArrayMesh
		check_eq(am.get_surface_count(), 2, "%s HullCrest has 2 surfaces (frame + runic core)" % lbl)

		# Verify finite unit normals, sRGB vertex colors, and symmetrical Port/Starboard placement on bow cheeks!
		var bad_normals := 0
		var srgb_missing := 0
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bad_normals += 1
			var mat := mi.get_surface_override_material(si) as StandardMaterial3D
			if mat != null and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb:
				srgb_missing += 1
		check_eq(bad_normals, 0, "%s HullCrest normals are all finite unit vectors" % lbl)
		check_eq(srgb_missing, 0, "%s HullCrest materials enable vertex_color_is_srgb = true" % lbl)

		var aabb := am.get_aabb()
		check(aabb.position.x < -1.0 and aabb.end.x > 1.0,
			"%s HullCrest spans Port (-X) and Starboard (+X) bow cheeks symmetrically (%s)" % [lbl, aabb])
		check_near(aabb.get_center().x, 0.0, 0.02, "%s HullCrest is symmetrically centered in X" % lbl)
		check(absf(aabb.get_center().z - exp_z) < 0.35 and absf(aabb.get_center().y - exp_y) < 0.25,
			"%s HullCrest hugs forward bow cheek near z=%.2f, y=%.2f (center=%s)" % [lbl, exp_z, exp_y, aabb.get_center()])
	print("    HullCrest sculpted tris: sloop=%d, brigantine=%d" % [sloop_tris, brig_tris])

	# 2. Verify dynamic apply_livery across ALL emblem_modes 0..7 updates runic core emission cleanly!
	var core_mat := sloop.hull_crest.call(&"get_core_material") as StandardMaterial3D
	check(core_mat != null and core_mat.emission_enabled, "HullCrest exposes emissive runic core material")
	var expected_energies := {
		0: 0.15,
		1: 0.85,
		2: 1.45,
		3: 1.65,
		4: 0.45,
		5: 1.50,
		6: 0.70,
		7: 0.75,
	}
	for mode_i: int in range(8):
		sloop.apply_livery(Color.WHITE, Color.WHITE, Color.BLACK, Color.WHITE, mode_i)
		check_near(core_mat.emission_energy_multiplier, float(expected_energies[mode_i]), 0.02,
			"HullCrest emblem_mode=%d sets expected core emission energy %.2f (got %.2f)" % [
				mode_i, float(expected_energies[mode_i]), core_mat.emission_energy_multiplier])
		if mode_i == 2:
			check(core_mat.emission.g > 0.85 and core_mat.emission.b > 0.45 and core_mat.emission_energy_multiplier >= 1.4,
				"emblem_mode 2 (Drowned) produces vivid Concept Art 2 emerald-turquoise runic glow")
		elif mode_i == 5:
			check(core_mat.emission.g > 0.85 and core_mat.emission.b > 0.70 and core_mat.emission_energy_multiplier >= 1.45,
				"emblem_mode 5 (Sunken Archive) produces vivid Concept Art 2 turquoise-emerald arcane seal glow")

	# Auto-faction styling check on Drowned & Ghost ships right out of _ready().
	var drowned_core := drowned.hull_crest.call(&"get_core_material") as StandardMaterial3D
	check(drowned_core != null and drowned_core.emission_energy_multiplier >= 1.4 and drowned_core.emission.g > 0.85,
		"Drowned faction ship auto-styles HullCrest with luminous emerald-turquoise glow on spawn")

	# 3. Verify Ghost Ship spectral phase shift hides & fades HullCrest, then restores cleanly!
	var ghost_core := ghost.hull_crest.call(&"get_core_material") as StandardMaterial3D
	check(ghost.hull_crest.visible and ghost_core.emission_energy_multiplier >= 1.6,
		"Ghost ship HullCrest starts visible with ethereal cyan-jade glow")
	ghost.set_spectral_phase(0.0)
	check(not ghost.hull_crest.visible, "set_spectral_phase(0.0) hides Ghost HullCrest")
	check_near(ghost_core.emission_energy_multiplier, 0.0, 0.01,
		"set_spectral_phase(0.0) fades Ghost HullCrest core emission to 0.0")
	ghost.set_spectral_phase(0.5)
	check(ghost.hull_crest.visible, "set_spectral_phase(0.5) keeps HullCrest visible at half phase")
	check_near(ghost_core.emission_energy_multiplier, 1.65 * 0.5, 0.03,
		"set_spectral_phase(0.5) scales Ghost HullCrest emission linearly")
	ghost.set_spectral_phase(1.0)
	check(ghost.hull_crest.visible, "set_spectral_phase(1.0) restores Ghost HullCrest visibility")
	check_near(ghost_core.emission_energy_multiplier, 1.65, 0.02,
		"set_spectral_phase(1.0) restores full Ghost HullCrest emission")

	# 4. Clean teardown releases all static HullCrest mesh & frame material caches (zero leaks!).
	await _end()
	var crest_gd := load(Ship.HULL_CREST_PATH) as GDScript
	check(crest_gd != null, "HullCrest script loads cleanly for cache audit")
	if crest_gd != null:
		check_eq(int(crest_gd.get(&"_active_crests")), 0, "HullCrest _active_crests drops to 0 on teardown")
		check(crest_gd.get(&"_sloop_mesh") == null and crest_gd.get(&"_brig_mesh") == null \
			and crest_gd.get(&"_frame_mat") == null,
			"HullCrest releases static _sloop_mesh, _brig_mesh, and _frame_mat caches on teardown")


func test_sculpted_cannonball_ordnance_variants_and_fort_battery_zero_primitives() -> void:
	_begin()
	Sea.amp_scale = 0.0

	# 1. Verify all 3 Cannonball ordnance variants (both explicit & auto-detected from hull_damage_radius)!
	var b_iron := Cannonball.new()
	b_iron.enable_effects = false
	b_iron.hull_damage_radius = 0.45
	_root.add_child(b_iron)
	b_iron.global_position = Vector3(0.0, 20.0, 0.0)

	var b_heavy := Cannonball.new()
	b_heavy.enable_effects = false
	b_heavy.hull_damage_radius = 0.45 * 1.25  # Auto-detects &"heavy" from cannon_heavy_shot sidegrade!
	_root.add_child(b_heavy)
	b_heavy.global_position = Vector3(2.0, 20.0, 0.0)

	var b_swivel := Cannonball.new()
	b_swivel.enable_effects = false
	b_swivel.hull_damage_radius = 0.45 * 0.85  # Auto-detects &"swivel" from cannon_quick_swivel sidegrade!
	_root.add_child(b_swivel)
	b_swivel.global_position = Vector3(4.0, 20.0, 0.0)

	var b_explicit_heavy := Cannonball.new()
	b_explicit_heavy.enable_effects = false
	b_explicit_heavy.ordnance_style = &"heavy"
	b_explicit_heavy.hull_damage_radius = 0.45
	_root.add_child(b_explicit_heavy)
	b_explicit_heavy.global_position = Vector3(6.0, 20.0, 0.0)
	await physics_frames(2)

	check_eq(b_iron.get_resolved_ordnance_style(), &"iron", "default radius 0.45 resolves to &'iron'")
	check_eq(b_heavy.get_resolved_ordnance_style(), &"heavy", "heavy sidegrade radius >= 0.52 auto-detects &'heavy'")
	check_eq(b_swivel.get_resolved_ordnance_style(), &"swivel", "swivel sidegrade radius <= 0.40 auto-detects &'swivel'")
	check_eq(b_explicit_heavy.get_resolved_ordnance_style(), &"heavy", "explicit ordnance_style=&'heavy' honored")

	var tri_counts := {}
	var widths := {}
	for spec: Array in [[b_iron, "iron", 1], [b_heavy, "heavy", 2], [b_swivel, "swivel", 1]]:
		var cb := spec[0] as Cannonball
		var lbl := String(spec[1])
		var exp_surfs := int(spec[2])
		var mi := cb.get_node_or_null(^"IronBall") as MeshInstance3D
		check(mi != null and mi.mesh is ArrayMesh and not (mi.mesh is PrimitiveMesh),
			"Cannonball %s uses sculpted ArrayMesh (zero SphereMesh/PrimitiveMesh)" % lbl)
		if mi != null and mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			check_eq(am.get_surface_count(), exp_surfs, "Cannonball %s surface count == %d" % [lbl, exp_surfs])
			var tris := 0
			var bad_norms := 0
			var srgb_missing := 0
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				tris += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_norms += 1
				var mat := mi.get_surface_override_material(si) as StandardMaterial3D
				if mat != null and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb:
					srgb_missing += 1
			tri_counts[lbl] = tris
			widths[lbl] = am.get_aabb().size.x
			check(tris >= 120, "Cannonball %s has sculpted multi-facet detail (%d >= 120 tris)" % [lbl, tris])
			check_eq(bad_norms, 0, "Cannonball %s normals are all finite unit vectors" % lbl)
			check_eq(srgb_missing, 0, "Cannonball %s materials enable vertex_color_is_srgb" % lbl)

	check(float(widths["swivel"]) < float(widths["iron"]) and float(widths["iron"]) < float(widths["heavy"]),
		"Ordnance silhouette sizes scale distinctly: swivel (%.3f) < iron (%.3f) < heavy (%.3f)" % [
			float(widths["swivel"]), float(widths["iron"]), float(widths["heavy"])])
	if b_swivel.trail != null and b_iron.trail != null and b_heavy.trail != null:
		check(float(b_swivel.trail.get(&"width")) < float(b_iron.trail.get(&"width"))
				and float(b_iron.trail.get(&"width")) < float(b_heavy.trail.get(&"width")),
			"Trail3D widths scale distinctly: swivel < iron < heavy")
	var heavy_mi := b_heavy.get_node(^"IronBall") as MeshInstance3D
	var heavy_glow_mat := heavy_mi.get_surface_override_material(1) as StandardMaterial3D
	check(heavy_glow_mat != null and heavy_glow_mat.emission_enabled and heavy_glow_mat.emission_energy_multiplier >= 2.0,
		"Heavy culverin shot features glowing orange-gold core seams (surface 1)")

	# 2. Verify sculpted jagged oak plank splinter ArrayMesh (ZERO BoxMesh!).
	var spl_mesh: Mesh = Cannonball.get_splinter_mesh()
	check(spl_mesh != null and spl_mesh is ArrayMesh and not (spl_mesh is PrimitiveMesh),
		"Cannonball hull splinter uses sculpted ArrayMesh (zero BoxMesh)")
	var spl_tris := 0
	var spl_bad_n := 0
	if spl_mesh is ArrayMesh:
		var spl_am := spl_mesh as ArrayMesh
		var arr := spl_am.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		spl_tris = floori(float(verts.size()) / 3.0)
		for nv in norms:
			if not nv.is_finite() or nv.length_squared() < 0.5:
				spl_bad_n += 1
		var spl_mat := spl_am.surface_get_material(0) as StandardMaterial3D
		check(spl_mat != null and spl_mat.vertex_color_use_as_albedo and spl_mat.vertex_color_is_srgb,
			"Oak plank splinter material enables sRGB vertex colors (honey oak vs dark bark)")
	check(spl_tris >= 40, "Oak plank splinter has sculpted tapered jagged geometry (%d >= 40 tris)" % spl_tris)
	check_eq(spl_bad_n, 0, "Oak plank splinter normals are all finite unit vectors")

	# 3. Verify FortBattery uses ZERO SphereMesh/PrimitiveMesh on PrimingFuseSpark & IronShot_0..3!
	var bat := FortBattery.new()
	bat.enable_effects = false
	_root.add_child(bat)
	bat.global_position = Vector3(12.0, 2.0, 0.0)
	await physics_frames(2)

	var bat_prims := 0
	var bat_bad_n := 0
	var fuse_tris := 0
	var shot_tris := 0
	var shot_count := 0
	for n in bat.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			bat_prims += 1
		var am := mi.mesh as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var t := floori(float(verts.size()) / 3.0)
				if mi.name == &"PrimingFuseSpark":
					fuse_tris += t
				elif String(mi.name).begins_with("IronShot_"):
					shot_count += 1
					if shot_tris == 0:
						shot_tris = t
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bat_bad_n += 1
	check_eq(bat_prims, 0, "FortBattery contains ZERO SphereMesh/BoxMesh/PrimitiveMesh instances")
	check_eq(bat_bad_n, 0, "FortBattery sculpted meshes have all finite unit normals")
	check_eq(shot_count, 4, "FortBattery stacks 4 sculpted coastal iron shot balls")
	check(fuse_tris >= 24, "FortBattery PrimingFuseSpark uses sculpted diamond crystal (%d >= 24 tris)" % fuse_tris)
	check(shot_tris >= 120, "FortBattery coastal IronShot uses sculpted hammered iron mesh (%d >= 120 tris)" % shot_tris)
	print("    Ordnance & Fort sculpted tris: iron=%d, heavy=%d, swivel=%d, splinter=%d, fort_fuse=%d, fort_shot=%d" % [
		int(tri_counts["iron"]), int(tri_counts["heavy"]), int(tri_counts["swivel"]), spl_tris, fuse_tris, shot_tris])

	# 4. Clean 0-leak teardown releases ALL static caches on both Cannonball and FortBattery!
	spl_mesh = null
	await _end()
	check_eq(Cannonball._active_cannonballs, 0, "Cannonball _active_cannonballs returns to 0 on teardown")
	check(Cannonball._ball_meshes.is_empty() and Cannonball._splinter_mesh == null and Cannonball._splinter_mat == null,
		"Cannonball releases all static ordnance & splinter caches on teardown")
	check_eq(FortBattery._active_batteries, 0, "FortBattery _active_batteries returns to 0 on teardown")
	check(FortBattery._fuse_spark_mesh == null and FortBattery._coastal_shot_mesh == null \
		and FortBattery._coastal_shot_mat == null,
		"FortBattery releases all static fuse spark & coastal shot caches on teardown")


func test_crows_nest_ladder_rungs_and_ship_name_net_replication() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 0.0, 0.0)

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(28.0, 0.0, 0.0)
	await physics_frames(12)

	# 1. Verify Ladder_CrowsNest & sculpted 1-draw-call CrowsNestRungs on BOTH Sloop & Brigantine!
	var sloop_rung_tris := 0
	var brig_rung_tris := 0
	for spec: Array in [[sloop, "sloop", 10.0 * sloop.hull_scale], [brig, "brigantine", 11.5 * brig.hull_scale]]:
		var sh := spec[0] as Ship
		var lbl := String(spec[1])
		var min_h := float(spec[2])
		var sh_lad := sh.crows_nest_ladder
		check(sh_lad != null and sh_lad == sh.get_node_or_null(^"Ladder_CrowsNest"),
			"%s mounts Ladder_CrowsNest and exposes crows_nest_ladder" % lbl)
		if sh_lad != null:
			check(sh_lad.height >= 7.5 and sh_lad.height >= min_h,
				"%s Ladder_CrowsNest height %.2f m reaches Crow's Nest (>= %.1f m)" % [lbl, sh_lad.height, min_h])
			check(sh_lad.get_platform() == sh, "%s Ladder_CrowsNest binds to Ship platform" % lbl)

		var rungs := sh.get_node_or_null(^"CrowsNestRungs") as MeshInstance3D
		check(rungs != null and rungs.mesh is ArrayMesh and not (rungs.mesh is PrimitiveMesh),
			"%s CrowsNestRungs uses sculpted ArrayMesh (zero PrimitiveMeshes)" % lbl)
		if rungs != null and rungs.mesh is ArrayMesh:
			var am := rungs.mesh as ArrayMesh
			check_eq(am.get_surface_count(), 1, "%s CrowsNestRungs is strictly 1 draw call (1 surface)" % lbl)
			var arr := am.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var tris := floori(float(verts.size()) / 3.0)
			var bad_n := 0
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					bad_n += 1
			check_eq(bad_n, 0, "%s CrowsNestRungs normals are all finite unit vectors" % lbl)
			check(tris >= 400, "%s CrowsNestRungs has rich sculpted side-ropes & oak rungs (%d >= 400 tris)" % [lbl, tris])
			var rmat := rungs.material_override as StandardMaterial3D
			check(rmat != null and rmat.vertex_color_use_as_albedo and rmat.vertex_color_is_srgb,
				"%s CrowsNestRungs material enables vertex_color_is_srgb" % lbl)
			if lbl == "sloop":
				sloop_rung_tris = tris
			else:
				brig_rung_tris = tris
	print("    CrowsNestRungs sculpted tris: sloop=%d, brigantine=%d" % [sloop_rung_tris, brig_rung_tris])

	# 2. Verify a real Pawn climbs Ladder_CrowsNest from the main deck all the way onto the Crow's Nest!
	var pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pawn)
	var lad := sloop.crows_nest_ladder
	var lad_xf := lad.transform
	var start_local := lad_xf * Vector3(0.0, 0.04, lad.standoff + 0.25)
	pawn.board(sloop, start_local)
	await physics_frames(8)

	var entered_ladder := false
	var reached_top := false
	for _tick in 560:
		var into := lad.into_dir()
		pawn.wish_dir = into
		await physics_frames(1)
		if pawn.mode == Pawn.Mode.LADDER and pawn.ladder == lad:
			entered_ladder = true
		elif entered_ladder and pawn.mode == Pawn.Mode.WALK:
			reached_top = true
			break
	pawn.wish_dir = Vector3.ZERO
	check(entered_ladder, "Pawn mounts Sloop Ladder_CrowsNest cleanly from main deck")
	check(reached_top, "Pawn climbs Sloop Ladder_CrowsNest all the way to the Crow's Nest top")

	# Hold steady on the Crow's Nest platform for 30 physics ticks to prove solid perch with zero ejection!
	await physics_frames(30)
	var nest_local := pawn.platform_local_position()
	print("    Pawn atop Sloop Crow's Nest: local=%s platform=%s" % [nest_local, pawn.platform])
	check(pawn.platform == sloop, "Pawn remains anchored to Sloop while perched in Crow's Nest")
	check(nest_local.y >= 11.2 * sloop.hull_scale and nest_local.y <= 12.2 * sloop.hull_scale,
		"Pawn lands safely on Sloop Crow's Nest deck (local y=%.2f)" % nest_local.y)

	# 3. Verify co-op custom ship_name replication via get_net_state() -> apply_net_state() with dirty-check!
	sloop.set_ship_name("Emerald Horizon")
	check_eq(sloop.ship_name, "Emerald Horizon", "host sloop updates ship_name to Emerald Horizon")
	var snap := sloop.get_net_state()
	check_eq(String(snap.get("ship_name", "")), "Emerald Horizon",
		"get_net_state() exports custom ship_name")

	var client_sloop := _spawn_sloop(Vector3(-28.0, 0.0, 0.0))
	await physics_frames(4)
	check(client_sloop.ship_name != "Emerald Horizon", "client sloop starts with default ship_name")
	var tex_before: Variant = client_sloop.ship_nameplate.call(&"get_plaque_texture") \
		if client_sloop.ship_nameplate != null else null

	client_sloop.apply_net_state(snap)
	check_eq(client_sloop.ship_name, "Emerald Horizon",
		"apply_net_state() replicates custom ship_name to client ship")
	var tex_after: Variant = client_sloop.ship_nameplate.call(&"get_plaque_texture") \
		if client_sloop.ship_nameplate != null else null
	check(tex_after != null and tex_after != tex_before,
		"ShipNameplate repaints plaque texture once when replicated ship_name changes")

	# Repeat unchanged snapshot -> must NOT trigger needless ShipNameplate texture repaint!
	client_sloop.apply_net_state(snap)
	var tex_repeat: Variant = client_sloop.ship_nameplate.call(&"get_plaque_texture") \
		if client_sloop.ship_nameplate != null else null
	check(tex_repeat == tex_after,
		"Repeated apply_net_state() with unchanged ship_name skips redundant ShipNameplate repaint")

	# 4. Clean 0-leak teardown releases all static CrowsNestRungs caches!
	tex_before = null
	tex_after = null
	tex_repeat = null
	await _end()
	check(Ship._crows_nest_rungs_sloop == null and Ship._crows_nest_rungs_brig == null \
		and Ship._crows_nest_rungs_mat == null,
		"Ship releases static CrowsNestRungs mesh & material caches cleanly on teardown")


func test_wave26_spacious_hull_sea_of_thieves_sailing_capstan_and_wind_ribbons() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.set_weather(0.0, 10.0, 0.0)  # Steady wind blowing toward -Z (downwind for heading 0)

	var sloop := SLOOP_SCENE.instantiate() as Ship
	sloop.enable_effects = true
	_root.add_child(sloop)
	sloop.global_position = Vector3(-28.0, 0.0, 0.0)

	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(28.0, 0.0, 0.0)

	var corsair := SLOOP_SCENE.instantiate() as Ship
	corsair.faction = &"corsair"
	corsair.enable_effects = true
	_root.add_child(corsair)
	corsair.global_position = Vector3(0.0, 0.0, -90.0)
	await physics_frames(60)

	# 1. Spacious 1.24x hull scale, unit-basis collision & stations, waterline equilibrium, & scaled attachments.
	check_near(sloop.hull_scale, 1.24, 0.001, "Sloop defaults to 1.24x spacious hull_scale")
	check_near(brig.hull_scale, 1.24, 0.001, "Brigantine defaults to 1.24x spacious hull_scale")
	check_near(sloop.global_position.y, 0.0, 0.35, "1.24x Sloop floats near waterline y ~= 0.0 m (y=%.2f)" % sloop.global_position.y)
	check_near(brig.global_position.y, 0.0, 0.35, "1.24x Brigantine floats near waterline y ~= 0.0 m (y=%.2f)" % brig.global_position.y)
	check(sloop.ship_nameplate != null and sloop.ship_nameplate.scale.is_equal_approx(Vector3.ONE * 1.24),
		"ShipNameplate scales cleanly by hull_scale")
	check(sloop.hull_crest != null and sloop.hull_crest.scale.is_equal_approx(Vector3.ONE * 1.24),
		"HullCrest scales cleanly by hull_scale")
	check(sloop.cabin_furnishings != null and sloop.cabin_furnishings.scale.is_equal_approx(Vector3.ONE * 1.24),
		"CaptainCabinFurnishings scales cleanly by hull_scale")

	var non_unit_cols := 0
	var col_count := 0
	for ch in sloop.get_children():
		if ch is CollisionShape3D:
			col_count += 1
			var sc := (ch as CollisionShape3D).transform.basis.get_scale()
			if not sc.is_equal_approx(Vector3.ONE):
				non_unit_cols += 1
	check(col_count > 40 and non_unit_cols == 0,
		"all %d CollisionShape3D pieces have orthonormal unit basis (bad=%d)" % [col_count, non_unit_cols])

	var non_unit_sts := 0
	for kind: StringName in [&"helm", &"sail_length", &"sail_angle", &"anchor", &"cannon", &"map_table", &"bilge"]:
		for st: Station in sloop.get_stations(kind):
			var sc := st.transform.basis.get_scale()
			if not sc.is_equal_approx(Vector3.ONE):
				non_unit_sts += 1
			var fp := st.get_focus_prompt()
			var ap := st.get_active_prompt()
			check(fp.length() > 0, "station %s returns non-empty focus prompt" % String(kind))
			check(ap.begins_with("["), "station %s active prompt starts with '[' (got '%s')" % [String(kind), ap])
			for ci in fp.length():
				check(fp.unicode_at(ci) < 128, "focus prompt is strict ASCII: '%s'" % fp)
			for ci in ap.length():
				check(ap.unicode_at(ci) < 128, "active prompt is strict ASCII: '%s'" % ap)
	check_eq(non_unit_sts, 0, "all Station nodes keep orthonormal unit basis so Pawns stay 1.0x human size")

	# 1b. Captain-scale Helm Wheel (< 1.56 m above quarterdeck @ 1.24x), 12-o'clock King Spoke,
	#     fixed brass binnacle/lubber-line geometry, and stepped-back Station_Helm stand_point!
	for hspec: Array in [[sloop, "sloop", 2.0, 5.2], [brig, "brigantine", 2.25, 6.8]]:
		var hsh: Ship = hspec[0] as Ship
		var hlbl: String = String(hspec[1])
		var qdeck_y: float = float(hspec[2])
		var helm_z: float = float(hspec[3])
		var wmi := hsh._wheel as MeshInstance3D
		check(wmi != null and wmi.mesh != null, "%s exposes MeshInstance3D Wheel" % hlbl)
		if wmi != null and wmi.mesh != null:
			var wbb := wmi.mesh.get_aabb()
			var king_top_y := wbb.position.y + wbb.size.y
			var reg_bot_y := absf(wbb.position.y)
			var scaled_top := (wmi.position.y - qdeck_y + king_top_y) * hsh.hull_scale
			check_near(wmi.position.y - qdeck_y, 0.68, 0.015,
				"%s Wheel hub sits at waist height QDECK_Y + 0.68 (got %.3f)" % [hlbl, wmi.position.y - qdeck_y])
			check(king_top_y > reg_bot_y + 0.05,
				"%s 12-o'clock King Spoke (+Y=%.3f) stands taller than regular spokes (%.3f)" % [hlbl, king_top_y, reg_bot_y])
			check(scaled_top < 1.56,
				"%s Wheel top spoke sits below Captain 1.60 m eye height at 1.24x (%.3f m < 1.56 m)" % [hlbl, scaled_top])
			# Verify Hull mesh includes fixed brass binnacle/lubber-line geometry directly behind the wheel!
			var hull_mi := hsh._model.get_node_or_null(^"Hull") as MeshInstance3D
			var brass_lubber_verts := 0
			if hull_mi != null and hull_mi.mesh != null:
				for si in hull_mi.mesh.get_surface_count():
					var smat := hull_mi.mesh.surface_get_material(si)
					if smat == null or smat.resource_name != "mat_brass":
						continue
					var sarr := hull_mi.mesh.surface_get_arrays(si)
					var sverts: PackedVector3Array = sarr[Mesh.ARRAY_VERTEX]
					for sv in sverts:
						if absf(sv.x) <= 0.42 and sv.y >= qdeck_y + 0.78 and sv.y <= qdeck_y + 1.12 \
								and sv.z >= helm_z - 0.36 and sv.z <= helm_z - 0.04:
							brass_lubber_verts += 1
			check(brass_lubber_verts >= 60,
				"%s sculpts fixed brass binnacle & lubber-line indicator arch behind wheel (%d verts)" % [hlbl, brass_lubber_verts])
		var helm_st := hsh.get_station(&"helm")
		check(helm_st != null and helm_st.stand_point.origin.z >= 0.90,
			"%s Station_Helm stand_point stepped cleanly aft (z=%.2f)" % [hlbl, helm_st.stand_point.origin.z if helm_st else 0.0])

	# 2. Weighty Tall-Ship Wind Speed Roles: Brigantine wins downwind, Sloop wins headwind (dummy sails)!
	for sh: Ship in [sloop, brig]:
		sh.set_sail_target(1.0)
		sh.sail_set = 1.0
		sh.set_trim_target(0.0)
		sh.sail_trim = 0.0
	await physics_frames(480)
	var sloop_down := sloop.forward_speed()
	var brig_down := brig.forward_speed()
	print("    Wave 26 downwind (10 m/s): Sloop=%.2f m/s (%.1f kt), Brigantine=%.2f m/s (%.1f kt)" % [
		sloop_down, sloop.speed_knots(), brig_down, brig.speed_knots()])
	check(sloop_down >= 4.8 and sloop_down <= 6.4,
		"Sloop downwind speed sits in weighty tall-ship band 4.8..6.4 m/s (got %.2f m/s)" % sloop_down)
	check(brig_down >= 6.1 and brig_down <= 7.8 and brig_down > sloop_down + 0.7,
		"Brigantine downwind speed (%.2f m/s) sits in 6.1..7.8 m/s and beats Sloop (%.2f m/s)" % [brig_down, sloop_down])

	# 2b. Graceful gliding coast momentum when furling sails into harbour (does not stop dead).
	sloop.set_sail_target(0.0)
	sloop.sail_set = 0.0
	await physics_frames(180)
	var sloop_coast := sloop.forward_speed()
	print("    Wave 26 furled coast (3 s from %.2f m/s): %.2f m/s" % [sloop_down, sloop_coast])
	check(sloop_coast > 2.0 and sloop_coast < sloop_down * 0.85,
		"Sloop glides smoothly forward when sails furl instead of stopping dead (%.2f m/s)" % sloop_coast)

	# Reverse wind to pure headwind (blowing toward +Z, heading = PI), keep sails squared flat forward (0 rad)!
	Weather.set_weather(0.0, 10.0, PI)
	sloop.linear_velocity = Vector3.ZERO
	brig.linear_velocity = Vector3.ZERO
	sloop.set_sail_target(1.0)
	sloop.sail_set = 1.0
	sloop.set_trim_target(0.0)
	sloop.sail_trim = 0.0
	brig.set_sail_target(1.0)
	brig.sail_set = 1.0
	brig.set_trim_target(0.0)
	brig.sail_trim = 0.0
	await physics_frames(480)
	var sloop_head := sloop.forward_speed()
	var brig_head := brig.forward_speed()
	print("    Wave 26 headwind dummy-sails (10 m/s): Sloop=%.2f m/s (%.1f kt), Brigantine=%.2f m/s (%.1f kt)" % [
		sloop_head, sloop.speed_knots(), brig_head, brig.speed_knots()])
	check(sloop_head >= 2.8 and sloop_head <= 4.0,
		"Sloop headwind dummy-sails makes steady headway 2.8..4.0 m/s (got %.2f m/s)" % sloop_head)
	check(brig_head >= 2.0 and brig_head <= 3.1,
		"Brigantine headwind avoids dead-zone 2.0..3.1 m/s (got %.2f m/s)" % brig_head)
	check(sloop_head > brig_head + 0.35,
		"Sloop is Headwind King: %.2f m/s > Brigantine %.2f m/s" % [sloop_head, brig_head])

	# 3. Deliberate weighty in-place zero-sail pivot turning (sails raised, anchor up, hard helm -> gentle maritime pivot!).
	sloop.set_sail_target(0.0)
	sloop.sail_set = 0.0
	sloop.linear_velocity = Vector3.ZERO
	sloop.angular_velocity = Vector3.ZERO
	sloop.anchor_down = false
	sloop.anchor_progress = 0.0
	var pivot_yaw0 := sloop.rotation.y
	sloop.set_helm_target(1.0)
	sloop.helm = 1.0
	await physics_frames(120)
	var pivot_dyaw := angle_difference(pivot_yaw0, sloop.rotation.y)
	print("    Wave 26 zero-sail in-place pivot dyaw: %.2f rad (fwd=%.2f m/s)" % [pivot_dyaw, sloop.forward_speed()])
	check(pivot_dyaw < -0.18 and pivot_dyaw > -0.40,
		"zero-sail hard starboard helm pivots bow deliberately in place (dyaw=%.2f rad)" % pivot_dyaw)
	sloop.set_helm_target(0.0)
	sloop.helm = 0.0

	# 4. Sail Length polarity ([S] lowers sail, [W] raises sail) & aim_cannon_delta helper!
	var sail_st := sloop.get_station(&"sail_length")
	var pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pawn)
	pawn.board(sloop, sloop.ship_point(Vector3(-1.2, 1.12, 0.5)))
	sloop.sail_set = 0.0
	sloop.sail_target = 0.0
	check(pawn.enter_station(sail_st), "Pawn enters Station_SailLength")
	for _i in 30:
		sail_st.drive(Vector2(0.0, -1.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
	var after_s := sloop.sail_set
	check(after_s > 0.20, "holding [S] (axis.y=-1) LOWERS sail (sail_set=%.2f)" % after_s)
	for _i in 30:
		sail_st.drive(Vector2(0.0, 1.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
	var after_w := sloop.sail_set
	check(after_w < after_s - 0.15, "holding [W] (axis.y=+1) RAISES sail (%.2f -> %.2f)" % [after_s, after_w])
	pawn.leave_station()

	sloop.aim_cannon(&"port", 0.0, 0.05)
	sloop.aim_cannon_delta(&"port", 0.15, 0.10)
	var port_c: Dictionary = sloop._cannons[&"port"]
	check_near(float(port_c["yaw"]), 0.15, 0.005, "aim_cannon_delta adjusts yaw cleanly")
	check_near(float(port_c["pitch"]), 0.15, 0.005, "aim_cannon_delta adjusts pitch cleanly")

	# 5. Capstan one-tap quick-drop + physical [Hold W] heaving + gravity slip-back + lock & auto-release!
	var cap_st := sloop.get_station(&"anchor")
	sloop.anchor_down = false
	sloop.anchor_progress = 0.0
	check_eq(cap_st.get_focus_prompt(), "Drop anchor", "raised capstan focus prompt says 'Drop anchor'")
	var quick_ok := cap_st.try_quick_use(pawn)
	check(quick_ok, "try_quick_use() consumes one-tap anchor drop when stowed")
	check(sloop.anchor_down, "quick-drop commands anchor_down = true")
	check(not cap_st.is_occupied() and pawn.station == null, "quick-drop does NOT lock pawn into capstan station")
	await physics_frames(100)
	check(sloop.anchor_progress >= 0.98, "quick-dropped anchor free-falls briskly to seabed (progress=%.2f)" % sloop.anchor_progress)

	# Second interact when anchor is down -> try_quick_use returns false, pawn enters capstan to heave!
	check(not cap_st.try_quick_use(pawn), "try_quick_use() returns false when anchor is already down")
	check(cap_st.get_focus_prompt().begins_with("Heave anchor"), "dropped capstan prompt invites heaving")
	check(pawn.enter_station(cap_st), "Pawn occupies capstan to heave anchor up")

	# Heave halfway up with [Hold W].
	var raised_count := [0]
	sloop.anchor_raised.connect(func() -> void: raised_count[0] += 1)
	for _i in 105:
		cap_st.drive(Vector2(0.0, 1.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
	var mid_prog := sloop.anchor_progress
	check(mid_prog < 0.72 and mid_prog > 0.25, "holding [W] physically heaves anchor partway (progress=%.2f)" % mid_prog)

	# Release [W] early -> gravity slip-back drops anchor back toward 1.0!
	for _i in 45:
		cap_st.drive(Vector2.ZERO, false, false, 1.0 / 60.0)
		await physics_frames(1)
	var slipped_prog := sloop.anchor_progress
	check(slipped_prog > mid_prog + 0.18, "releasing [W] early lets anchor slip back under gravity (%.2f -> %.2f)" % [mid_prog, slipped_prog])

	# Now hold [W] all the way to top -> locks anchor_down = false, emits anchor_raised, auto-releases occupant!
	for _i in 320:
		if not cap_st.is_occupied():
			break
		cap_st.drive(Vector2(0.0, 1.0), false, false, 1.0 / 60.0)
		await physics_frames(1)
	check_near(sloop.anchor_progress, 0.0, 0.01, "full [Hold W] heave locks anchor_progress to 0.0")
	check(not sloop.anchor_down, "full heave clears anchor_down = false")
	check_eq(raised_count[0], 1, "full heave emits anchor_raised exactly once")
	check(not cap_st.is_occupied(), "full heave auto-releases capstan occupant on lock clang")

	# 6. 3D Airborne WindRibbons: 1 draw call, 0 primitives, tracks wind direction, 0-leak teardown!
	check(sloop.wind_ribbons != null and sloop.get_node_or_null(^"WindRibbons") == sloop.wind_ribbons,
		"player Ship mounts WindRibbons when enable_effects=true")
	check(corsair.wind_ribbons == null, "rival Corsair ship does NOT mount player WindRibbons")
	var wr := sloop.wind_ribbons
	var mmi := wr.get_multimesh_instance()
	check(mmi != null and mmi.multimesh != null, "WindRibbons builds MultiMeshInstance3D")
	check_eq(wr.find_children("*", "MeshInstance3D", true, false).size(), 0,
		"WindRibbons uses single MultiMeshInstance3D draw call (no extra MeshInstance3D nodes)")
	check_eq(wr.find_children("*", "MultiMeshInstance3D", true, false).size(), 1,
		"WindRibbons renders strictly 1 MultiMeshInstance3D draw call")
	check_eq(wr.get_ribbon_count(), 14, "WindRibbons renders 14 airborne ribbons")
	check_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "WindRibbons disables shadows")
	var wr_mesh := mmi.multimesh.mesh
	check(wr_mesh is ArrayMesh and not (wr_mesh is PrimitiveMesh), "WindRibbons uses sculpted ArrayMesh (zero primitives)")
	if wr_mesh is ArrayMesh:
		var arr := (wr_mesh as ArrayMesh).surface_get_arrays(0)
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var bad_n := 0
		for nv in norms:
			if not nv.is_finite() or nv.length_squared() < 0.5:
				bad_n += 1
		check_eq(bad_n, 0, "WindRibbons ArrayMesh has all finite unit normals")

	# Rotate wind to +X (east, heading = PI * 0.5) and step process frames -> ribbons align with live wind!
	Weather.set_weather(0.0, 14.0, PI * 0.5)
	wr._step_ribbons(0.1)
	var exp_wdir := Weather.wind_vector()
	exp_wdir.y = 0.0
	exp_wdir = exp_wdir.normalized()
	var rib_fwd := wr.get_ribbon_forward_world(0)
	check(rib_fwd.dot(exp_wdir) > 0.92,
		"WindRibbons align strictly along live Weather.wind_vector() (dot=%.3f)" % rib_fwd.dot(exp_wdir))

	# Clean 0-leak teardown releases all static WindRibbons caches!
	wr_mesh = null
	await _end()
	check_eq(WindRibbons._active_instances, 0, "WindRibbons _active_instances drops to 0 on teardown")
	check(WindRibbons._ribbon_mesh == null and WindRibbons._ribbon_shader == null,
		"WindRibbons releases static mesh & shader caches cleanly on teardown (0 leaks)")


func test_wave28_ship_harpoon_deck_lanterns_and_cannon_ordnance() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.set_weather(0.0, 11.0, 0.0)
	Weather.time_of_day = 0.5  # Deep night so deck lantern blackout & illumination shine clearly

	var sloop := SLOOP_SCENE.instantiate() as Ship
	sloop.enable_effects = true
	_root.add_child(sloop)
	sloop.global_position = Vector3(0.0, 0.0, 0.0)

	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(32.0, 0.0, 0.0)
	await physics_frames(12)

	# ------------------------------------------------------------------
	# 1. Bow-mounted Sculpted ShipHarpoon on Sloop & Brigantine (0 primitives, triplanar PBR)
	# ------------------------------------------------------------------
	var harpoon_tris := 0
	for spec: Array in [[sloop, "sloop"], [brig, "brigantine"]]:
		var sh := spec[0] as Ship
		var lbl := String(spec[1])
		for side: StringName in [&"port", &"starboard"]:
			var hp := sh.get_harpoon(side)
			check(hp != null and is_instance_valid(hp), "%s mounts ShipHarpoon on %s bow" % [lbl, side])
			var st := sh.get_station(&"harpoon", side)
			check(st != null, "%s registers Station for %s harpoon" % [lbl, side])
			if st != null:
				check_eq(st.meta_key, side, "%s %s harpoon station meta_key matches" % [lbl, side])
				check(st.transform.basis.get_scale().is_equal_approx(Vector3.ONE),
					"%s %s harpoon station keeps orthonormal unit basis" % [lbl, side])
				var ap := st.get_active_prompt()
				check(ap.begins_with("[Mouse/WASD] Aim") and ap.contains("[Hold RMB] Reel") and ap.contains("[R] Release"),
					"%s %s harpoon active prompt lists full ASCII controls (got '%s')" % [lbl, side, ap])
				for ci in ap.length():
					check(ap.unicode_at(ci) < 128, "harpoon active prompt is strict ASCII")
			if hp == null:
				continue
			var raw_prims := 0
			var bad_norms := 0
			var bad_mats := 0
			for n in hp.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if mi == null or mi.mesh == null:
					continue
				if mi.mesh is PrimitiveMesh:
					raw_prims += 1
				var am := mi.mesh as ArrayMesh
				if am != null:
					for si in am.get_surface_count():
						var arr := am.surface_get_arrays(si)
						var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
						for nv in norms:
							if not nv.is_finite() or nv.length_squared() < 0.5:
								bad_norms += 1
				var mat := mi.material_override as StandardMaterial3D
				if mat != null:
					if not mat.vertex_color_use_as_albedo or not mat.vertex_color_is_srgb \
							or not mat.uv1_triplanar or mat.uv1_world_triplanar:
						bad_mats += 1
			check_eq(raw_prims, 0, "%s %s ShipHarpoon contains ZERO PrimitiveMeshes" % [lbl, side])
			check_eq(bad_norms, 0, "%s %s ShipHarpoon normals are all finite unit vectors" % [lbl, side])
			check_eq(bad_mats, 0, "%s %s ShipHarpoon uses sRGB vertex colors + object-space triplanar PBR" % [lbl, side])
			var tris := hp.get_triangle_count()
			check(tris >= 800, "%s %s ShipHarpoon has rich sculpted geometry (%d >= 800 tris)" % [lbl, side, tris])
			if harpoon_tris == 0:
				harpoon_tris = tris

	# 1b. Harpoon magnetic grab cone snags floating Carryable treasure onto foredeck & emits signal!
	var hp_port := sloop.get_harpoon(&"port")
	sloop.set_anchor(true)
	sloop.anchor_progress = 1.0
	await physics_frames(8)

	var loot_item := Carryable.new()
	loot_item.name = "FloatingChest"
	loot_item.item_name = "Sovereign Strongbox"
	loot_item.add_to_group(&"carryables")
	var lcol := CollisionShape3D.new()
	var lbox := BoxShape3D.new()
	lbox.size = Vector3(0.6, 0.45, 0.45)
	lcol.shape = lbox
	loot_item.add_child(lcol)
	_root.add_child(loot_item)

	var muzzle_p := hp_port.get_muzzle_world_pos()
	var aim_p := hp_port.get_aim_direction_world()
	# Place floating chest 14 m ahead along aim ray with slight 1.1 m lateral offset inside 2.6 m grab cone!
	var lateral := aim_p.cross(Vector3.UP).normalized()
	loot_item.global_position = muzzle_p + aim_p * 14.0 + lateral * 1.1
	await physics_frames(2)

	var snagged_events: Array[Array] = []
	sloop.harpoon_loot_snagged.connect(func(label: String, side_sn: StringName) -> void:
		snagged_events.append([label, side_sn])
	)
	var fire_loot := sloop.fire_harpoon(&"port", null)
	check(bool(fire_loot.get("hit", false)) and fire_loot.get("kind") == &"loot",
		"port harpoon snags floating Carryable inside 2.6 m magnetic cone")
	check_eq(hp_port.state, ShipHarpoon.State.REELING_LOOT, "harpoon enters REELING_LOOT animation state")
	check_eq(snagged_events.size(), 1, "ship emits harpoon_loot_snagged once")
	if not snagged_events.is_empty():
		check_eq(String(snagged_events[0][0]), "Sovereign Strongbox", "harpoon_loot_snagged carries item label")
		check_eq(snagged_events[0][1], &"port", "harpoon_loot_snagged carries side &'port'")

	# Advance past 0.42 s reel-in animation -> treasure lands squarely on Sloop foredeck!
	await physics_frames(45)
	check_eq(hp_port.state, ShipHarpoon.State.IDLE, "harpoon returns cleanly to IDLE after loot reel")
	var expected_deck := sloop.global_transform * sloop.ship_point(Vector3(-0.95, 1.25, -3.55))
	var deck_dist := loot_item.global_position.distance_to(expected_deck)
	check(deck_dist < 1.35, "snagged treasure reels cleanly onto foredeck (dist=%.2f m)" % deck_dist)
	check(not loot_item.freeze, "delivered treasure is unfrozen and pickable on foredeck")

	# 1c. Harpoon tether pier -> reel pulls ship bow toward pier -> release snaps cleanly!
	sloop.set_anchor(false)
	sloop.anchor_progress = 0.0
	sloop.linear_velocity = Vector3.ZERO
	sloop.angular_velocity = Vector3.ZERO
	await physics_frames(4)

	var hp_stbd := sloop.get_harpoon(&"starboard")
	hp_stbd.cooldown = 0.0
	var muzzle_s := hp_stbd.get_muzzle_world_pos()
	var aim_s := hp_stbd.get_aim_direction_world()
	var pier := StaticBody3D.new()
	pier.name = "HarpoonTestPier"
	pier.collision_layer = 1
	pier.collision_mask = 0
	var pcol := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(5.0, 8.0, 5.0)
	pcol.shape = pbox
	pier.add_child(pcol)
	_root.add_child(pier)
	pier.global_position = muzzle_s + aim_s * 16.0
	await physics_frames(4)

	var fire_tether := sloop.fire_harpoon(&"starboard", null)
	check(bool(fire_tether.get("hit", false)) and fire_tether.get("kind") == &"tether",
		"starboard harpoon tethers solid pier collider on layer 1")
	check_eq(hp_stbd.state, ShipHarpoon.State.TETHERED, "harpoon enters TETHERED state")
	var dist_before_reel := sloop.global_position.distance_to(hp_stbd.tether_world_pos)
	var len_before_reel := hp_stbd.tether_length
	for _i in 60:
		sloop.reel_harpoon(&"starboard", true, 1.0 / 60.0)
		await physics_frames(1)
	var dist_after_reel := sloop.global_position.distance_to(hp_stbd.tether_world_pos)
	check(hp_stbd.tether_length < len_before_reel - 1.5,
		"reeling shortens tether length smoothly (%.2f -> %.2f m)" % [len_before_reel, hp_stbd.tether_length])
	check(dist_after_reel < dist_before_reel - 0.5,
		"reeling pulls ship bow cleanly toward tethered pier (%.2f -> %.2f m)" % [dist_before_reel, dist_after_reel])
	check(sloop.global_basis.y.y > 0.90, "harpoon reel traction never flips or violently rolls ship")

	sloop.release_harpoon(&"starboard")
	check_eq(hp_stbd.state, ShipHarpoon.State.IDLE, "release_harpoon() returns harpoon cleanly to IDLE")
	check(not hp_stbd._rope_mi.visible, "release_harpoon() hides taut rope mesh")

	# ------------------------------------------------------------------
	# 2. Interactive Deck Lanterns ([F] quick-use blackout + co-op net roundtrip)
	# ------------------------------------------------------------------
	var lantern_st := sloop.get_station(&"lantern")
	check(lantern_st != null and lantern_st.name == &"Station_Lantern_Node",
		"sloop registers Station_Lantern_Node (kind=&'lantern')")
	check(brig.get_station(&"lantern") != null, "brigantine registers Station_Lantern_Node")
	check(sloop.lanterns_lit, "ship lanterns start lit by default")
	check_eq(lantern_st.get_focus_prompt(), "Douse ship lanterns", "lit lantern station prompt says 'Douse ship lanterns'")
	check(not sloop._lantern_lights.is_empty(), "ship spawns OmniLight3D lantern glows when enable_effects=true")
	check(not sloop._lantern_glass_mats.is_empty(), "ship duplicates per-ship mat_lantern_glass materials")

	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(sloop, sloop.ship_point(Vector3(-0.6, 2.05, 5.1)))
	await physics_frames(4)

	var lantern_events: Array[bool] = []
	sloop.lanterns_toggled.connect(func(lit: bool) -> void: lantern_events.append(lit))
	check(lantern_st.try_quick_use(captain), "lantern try_quick_use consumes one-tap [F] toggle")
	check(not sloop.lanterns_lit, "first [F] tap douses ship lanterns (lanterns_lit == false)")
	check(not lantern_st.is_occupied() and captain.station == null,
		"dousing ship lanterns does NOT lock pawn into lantern station")
	check(not lantern_st.can_occupy(captain), "lantern station cannot lock a pawn")
	check_eq(lantern_st.get_focus_prompt(), "Light ship lanterns", "dark lantern station prompt says 'Light ship lanterns'")
	check_eq(lantern_events.size(), 1, "lanterns_toggled signal emitted once on douse")

	sloop._update_visuals(0.05)
	for l in sloop._lantern_lights:
		check_near(l.light_energy, 0.0, 0.001, "doused lantern OmniLight3D has 0.0 energy")
		check(not l.visible, "doused lantern OmniLight3D is hidden")
	for lg in sloop._lantern_glass_mats:
		check_near(lg.emission_energy_multiplier, 0.0, 0.001, "doused mat_lantern_glass emission is zeroed")

	# Co-op net state roundtrip of lanterns_lit!
	var snap_dark := sloop.get_net_state()
	check_eq(bool(snap_dark.get("lanterns_lit", true)), false, "get_net_state exports lanterns_lit = false")
	var client_sloop := SLOOP_SCENE.instantiate() as Ship
	client_sloop.enable_effects = true
	_root.add_child(client_sloop)
	client_sloop.global_position = Vector3(-34.0, 0.0, 0.0)
	await physics_frames(4)
	check(client_sloop.lanterns_lit, "client sloop starts with lanterns lit")
	client_sloop.apply_net_state(snap_dark)
	check(not client_sloop.lanterns_lit, "apply_net_state replicates lanterns_lit = false to client ship")
	for cl in client_sloop._lantern_lights:
		check_near(cl.light_energy, 0.0, 0.001, "replicated dark client ship zeroes lantern energy")

	# Second [F] tap relights ship lanterns cleanly!
	check(lantern_st.try_quick_use(captain), "second try_quick_use relights ship lanterns")
	check(sloop.lanterns_lit, "second [F] tap restores lanterns_lit = true")
	sloop._update_visuals(0.05)
	for l in sloop._lantern_lights:
		check(l.visible and l.light_energy > 0.25, "relit lantern OmniLight3D restores night glow")
	for lg in sloop._lantern_glass_mats:
		check(lg.emission_enabled and lg.emission_energy_multiplier > 0.5,
			"relit mat_lantern_glass restores night emission")

	# ------------------------------------------------------------------
	# 3. Tactile Cannon Ordnance Cycling ([R]: Iron -> Chainshot -> Firebomb -> Anchorball -> Ballastball -> Flare -> Iron)
	# ------------------------------------------------------------------
	var ord_events: Array[StringName] = []
	sloop.cannon_ordnance_changed.connect(func(k: StringName) -> void: ord_events.append(k))
	check_eq(sloop.cannon_ordnance, &"iron", "ship cannon starts on &'iron' ordnance")
	check_eq(sloop.get_cannon_ordnance_label(), "Iron", "Iron label matches")
	check_eq(sloop.cycle_cannon_ordnance(), &"chainshot", "1st cycle -> &'chainshot'")
	check_eq(sloop.get_cannon_ordnance_label(), "Chainshot", "Chainshot label matches")
	check_eq(sloop.cycle_cannon_ordnance(), &"firebomb", "2nd cycle -> &'firebomb'")
	check_eq(sloop.get_cannon_ordnance_label(), "Firebomb", "Firebomb label matches")
	check_eq(sloop.cycle_cannon_ordnance(), &"anchorball", "3rd cycle -> &'anchorball'")
	check_eq(sloop.get_cannon_ordnance_label(), "Anchorball", "Anchorball label matches")
	check_eq(sloop.cycle_cannon_ordnance(), &"ballastball", "4th cycle -> &'ballastball'")
	check_eq(sloop.get_cannon_ordnance_label(), "Ballastball", "Ballastball label matches")
	check_eq(sloop.cycle_cannon_ordnance(), &"flare", "5th cycle -> &'flare'")
	check_eq(sloop.get_cannon_ordnance_label(), "Flare", "Flare label matches")
	check_eq(sloop.cycle_cannon_ordnance(), &"iron", "6th cycle wraps cleanly -> &'iron'")
	check_eq(ord_events.size(), 6, "cannon_ordnance_changed emitted on each swap")

	# Verify PlayerController mouse-aim on harpoon + [R] station special action + HUD hints!
	var pc := PlayerController.new()
	pc.capture_mouse = false
	pc.input_enabled = false
	pc.make_current = false
	captain.add_child(pc)
	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, null, null, sloop, null, null)
	await get_tree().process_frame
	hud.set_process(false)

	var cannon_st := sloop.get_station(&"cannon", &"port")
	check(captain.enter_station(cannon_st), "captain enters port cannon station")
	pc._handle_station_special_action()
	check_eq(sloop.cannon_ordnance, &"chainshot", "PlayerController [R] on cannon cycles to &'chainshot'")
	hud._process(0.05)
	check(hud.get_tool_meta_text().contains("Chainshot") and hud.get_tool_meta_text().contains("[R] Swap Shot"),
		"HUD cannon chip displays live Chainshot ordnance and [R] Swap Shot")
	check(cannon_st.get_active_prompt().contains("Fire (Chainshot)") and cannon_st.get_active_prompt().contains("[R] Swap Shot"),
		"cannon active prompt shows live ordnance and [R] Swap Shot")
	captain.leave_station()

	var hp_st := sloop.get_station(&"harpoon", &"port")
	check(captain.enter_station(hp_st), "captain enters port harpoon station")
	var yaw_before_mouse := hp_port.aim_yaw
	pc.add_look(Vector2(60.0, -25.0))
	check(absf(hp_port.aim_yaw - yaw_before_mouse) > 0.05, "PlayerController mouse look aims harpoon")
	hud._process(0.05)
	check_eq(hud.get_tool_title_text(), "Bow Harpoon", "HUD tool chip title shows Bow Harpoon")
	check(hud.get_tool_meta_text().contains("[Hold RMB] Reel") and hud.get_tool_meta_text().contains("[R] Release"),
		"HUD harpoon chip displays strict-ASCII reel/release controls")
	captain.leave_station()

	# 3b. Sculpted zero-primitive meshes for chainshot & flare!
	var chain_tris := 0
	var flare_tris := 0
	for o_spec: Array in [[&"chainshot", 1], [&"flare", 2]]:
		var o_kind: StringName = o_spec[0]
		var exp_surfs: int = int(o_spec[1])
		var test_b := Cannonball.new()
		test_b.enable_effects = false
		test_b.ordnance_style = o_kind
		_root.add_child(test_b)
		test_b.global_position = Vector3(0.0, 40.0, 0.0)
		await physics_frames(1)
		check_eq(test_b.get_resolved_ordnance_style(), o_kind, "Cannonball resolves %s" % o_kind)
		var mi := test_b.get_node_or_null(^"IronBall") as MeshInstance3D
		check(mi != null and mi.mesh is ArrayMesh and not (mi.mesh is PrimitiveMesh),
			"Cannonball %s uses sculpted ArrayMesh (zero PrimitiveMesh)" % o_kind)
		if mi != null and mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			check_eq(am.get_surface_count(), exp_surfs, "Cannonball %s surface count == %d" % [o_kind, exp_surfs])
			var t_cnt := 0
			var bad_n := 0
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				t_cnt += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_n += 1
			check_eq(bad_n, 0, "Cannonball %s normals are all finite unit vectors" % o_kind)
			check(t_cnt >= 160, "Cannonball %s has sculpted multi-facet detail (%d >= 160 tris)" % [o_kind, t_cnt])
			if o_kind == &"chainshot":
				chain_tris = t_cnt
			else:
				flare_tris = t_cnt
				check(test_b.flare_light != null and test_b.flare_light.omni_range >= 64.0 and test_b.flare_light.light_energy >= 5.0,
					"Flare shell equips 65 m OmniLight3D illumination (energy=%.1f, range=%.1f)" % [
						test_b.flare_light.light_energy if test_b.flare_light != null else 0.0,
						test_b.flare_light.omni_range if test_b.flare_light != null else 0.0])
		test_b.queue_free()
	await physics_frames(2)

	# 3c. Live Chainshot impact applies sail_damage_timer > 0 and slows target ship dramatically vs healthy ship!
	var shooter := _spawn_sloop(Vector3(0.0, 0.0, -70.0))
	var victim := _spawn_sloop(Vector3(24.0, 0.0, -71.5))
	var healthy := _spawn_sloop(Vector3(56.0, 0.0, -71.5))
	await physics_frames(20)

	# First verify Flare hits target hull with ZERO hull breach & ZERO sail damage!
	shooter.set_cannon_ordnance(&"flare")
	shooter.aim_cannon(&"starboard", 0.0, -0.02)
	var flare_shot := shooter.fire_cannon(&"starboard")
	check(flare_shot != null and flare_shot.get_resolved_ordnance_style() == &"flare", "shooter fires Signal Flare")
	check(flare_shot.flare_light != null and flare_shot.flare_light.omni_range >= 64.0,
		"fired Signal Flare illuminates with 65 m OmniLight3D")
	for _i in 90:
		await physics_frames(1)
		if not is_instance_valid(flare_shot) or flare_shot._impacted:
			break
	check_eq(victim.open_hole_count(), 0, "Signal Flare impact causes ZERO hull breaches")
	check_near(victim.sail_damage_timer, 0.0, 0.01, "Signal Flare impact causes ZERO sail damage")

	# Reset cannon reload & fire Chainshot into victim hull!
	shooter._cannons[&"starboard"]["reload"] = 0.0
	shooter.set_cannon_ordnance(&"chainshot")
	shooter.aim_cannon(&"starboard", 0.0, -0.02)
	var sail_hit_events: Array[float] = []
	victim.sail_damaged.connect(func(dur: float) -> void: sail_hit_events.append(dur))
	var chain_shot := shooter.fire_cannon(&"starboard")
	check(chain_shot != null and chain_shot.get_resolved_ordnance_style() == &"chainshot", "shooter fires Chainshot")
	for _i in 90:
		await physics_frames(1)
		if victim.sail_damage_timer > 0.0:
			break
	check(victim.sail_damage_timer > 10.0 and sail_hit_events.size() == 1,
		"Chainshot impact applies 14 s sail_damage_timer (got %.1f s)" % victim.sail_damage_timer)

	# Race damaged victim vs undamaged healthy sloop downwind -> chainshot slashes forward speed!
	for sh_r: Ship in [victim, healthy]:
		for hi in sh_r.holes.size():
			sh_r.patch_hole(hi)
		sh_r.water_level = 0.0
		sh_r.linear_velocity = Vector3.ZERO
		sh_r.set_sail_target(1.0)
		sh_r.sail_set = 1.0
		sh_r.set_trim_target(0.0)
		sh_r.sail_trim = 0.0
	await physics_frames(220)
	var v_damaged := victim.forward_speed()
	var v_healthy := healthy.forward_speed()
	print("    Wave 28A tris: harpoon=%d, chainshot=%d, flare=%d | sail_dmg_speed=%.2f vs healthy=%.2f m/s" % [
		harpoon_tris, chain_tris, flare_tris, v_damaged, v_healthy])
	check(v_damaged < v_healthy * 0.72,
		"Chainshot sail damage significantly reduces target forward speed (%.2f vs %.2f m/s)" % [v_damaged, v_healthy])

	# 4. Clean 0-leak teardown releases all static ShipHarpoon & Cannonball caches!
	await _end()
	check_eq(ShipHarpoon._active_instances, 0, "ShipHarpoon _active_instances returns to 0 on teardown")
	check(ShipHarpoon._pedestal_oak_mesh == null and ShipHarpoon._spear_mesh == null \
		and ShipHarpoon._oak_mat == null and ShipHarpoon._pbr_tex_cache.is_empty(),
		"ShipHarpoon releases all static sculpted meshes, PBR materials, and WeakRef cache cleanly (0 leaks)")
	check_eq(Cannonball._active_cannonballs, 0, "Cannonball _active_cannonballs returns to 0 on teardown")
	check(Cannonball._ball_meshes.is_empty(), "Cannonball releases all ordnance mesh caches including chainshot & flare")


func test_wave29_ship_supply_barrels_geometry_fill_tiers_and_one_press_restock() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 6.0, 0.0)

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(32.0, 0.0, 0.0)
	await physics_frames(4)

	# 1. Mount verification & backward-compatible deck SupplyBarrelsInteractable preserved.
	var sb_sloop := sloop.get_supply_barrels()
	var sb_brig := brig.get_supply_barrels()
	check(sb_sloop != null, "Sloop mounts ShipSupplyBarrels via get_supply_barrels()")
	check(sb_brig != null, "Brigantine mounts ShipSupplyBarrels via get_supply_barrels()")
	check(sloop.get_node_or_null(^"SupplyBarrelsInteractable") != null,
		"Sloop keeps existing deck SupplyBarrelsInteractable intact")
	check(brig.get_node_or_null(^"SupplyBarrelsInteractable") != null,
		"Brigantine keeps existing deck SupplyBarrelsInteractable intact")

	# Exact flush-grounded port hold placement scaled by ship_point + hull_scale!
	var sloop_expect := {
		"CannonballBarrel": Vector3(-0.86, -0.85, -0.15),
		"PlankBarrel": Vector3(-0.88, -0.85, 0.72),
		"RationsBarrel": Vector3(-0.85, -0.85, 1.58),
	}
	for bname: String in sloop_expect:
		var bn := sb_sloop.get_node_or_null(bname) as Node3D
		check(bn != null, "Sloop ShipSupplyBarrels builds %s" % bname)
		if bn != null:
			check(bn.position.is_equal_approx(sloop.ship_point(sloop_expect[bname] as Vector3)),
				"Sloop %s positioned at exact flush port hold coord" % bname)
			check(bn.scale.is_equal_approx(Vector3.ONE * sloop.hull_scale),
				"Sloop %s scales cleanly with hull_scale" % bname)

	var brig_expect := {
		"CannonballBarrel": Vector3(-1.02, -0.95, 0.72),
		"PlankBarrel": Vector3(-1.02, -0.95, 1.62),
		"RationsBarrel": Vector3(-0.98, -0.95, 2.52),
	}
	for bname: String in brig_expect:
		var bn := sb_brig.get_node_or_null(bname) as Node3D
		check(bn != null, "Brigantine ShipSupplyBarrels builds %s" % bname)
		if bn != null:
			check(bn.position.is_equal_approx(brig.ship_point(brig_expect[bname] as Vector3)),
				"Brigantine %s positioned at exact port hold bulkhead coord" % bname)
			check(bn.scale.is_equal_approx(Vector3.ONE * brig.hull_scale),
				"Brigantine %s scales cleanly with hull_scale" % bname)

	# 2. Zero PrimitiveMesh, finite unit normals, sRGB vertex-color + object-space triplanar PBR, >= 1,100 tris!
	var raw_prims := 0
	var bad_norms := 0
	var bad_mats := 0
	for n in sb_sloop.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
		var am := mi.mesh as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_norms += 1
		var mat := mi.material_override as StandardMaterial3D
		if mat == null or not mat.vertex_color_use_as_albedo or not mat.vertex_color_is_srgb \
				or not mat.uv1_triplanar or mat.uv1_world_triplanar \
				or not mat.normal_enabled or mat.normal_texture == null or mat.roughness_texture == null:
			bad_mats += 1
	var barrel_tris := sb_sloop.get_triangle_count()
	print("    Wave 29A ShipSupplyBarrels sculpted tris: %d" % barrel_tris)
	check_eq(raw_prims, 0, "ShipSupplyBarrels contains ZERO PrimitiveMeshes")
	check_eq(bad_norms, 0, "ShipSupplyBarrels normals are all finite unit vectors")
	check_eq(bad_mats, 0, "ShipSupplyBarrels binds sRGB vertex colors + object-space triplanar BC7 PBR maps")
	check(barrel_tris >= 1100, "ShipSupplyBarrels has rich sculpted geometry (%d >= 1100 tris)" % barrel_tris)

	# 3. Tiered fill visuals (full -> mid -> low -> empty) & dynamic strict-ASCII prompts!
	var ammo_it := sb_sloop.get_barrel_interactable(&"cannonball")
	var plank_it := sb_sloop.get_barrel_interactable(&"planks")
	var rations_it := sb_sloop.get_barrel_interactable(&"rations")
	check(ammo_it != null and plank_it != null and rations_it != null,
		"all three barrel Interactables are exposed via get_barrel_interactable()")
	check_eq(rations_it.prompt, "Grab rations & grog (+25 HP)", "rations barrel prompt matches")

	check_near(sb_sloop.get_fill_ratio(&"cannonball"), 1.0, 0.001, "full cannonball fill ratio == 1.0")
	check_near(sb_sloop.get_fill_ratio(&"planks"), 1.0, 0.001, "full planks fill ratio == 1.0")
	check(sb_sloop._ammo_fill_mi.visible and sb_sloop._plank_fill_mi.visible, "both fill meshes visible when full")
	var ammo_y_full := sb_sloop._ammo_fill_mi.position.y
	var plank_y_full := sb_sloop._plank_fill_mi.position.y
	check_eq(ammo_it.prompt, "Take cannonballs (%d/%d)" % [Ship.MAX_CANNONBALLS, Ship.MAX_CANNONBALLS],
		"full cannonball prompt reflects full stock")

	# Mid tier (~50%)
	sloop.cannonballs_remaining = floori(float(Ship.MAX_CANNONBALLS) * 0.5)
	sloop.planks_remaining = floori(float(Ship.MAX_PLANKS) * 0.5)
	sb_sloop.sync_fill_visuals()
	var ammo_y_mid := sb_sloop._ammo_fill_mi.position.y
	var plank_y_mid := sb_sloop._plank_fill_mi.position.y
	check(sb_sloop._ammo_fill_mi.visible and ammo_y_mid < ammo_y_full, "mid ammo tier drops roundshot stack height")
	check(sb_sloop._plank_fill_mi.visible and plank_y_mid < plank_y_full, "mid plank tier drops plank bundle height")
	check_eq(ammo_it.prompt, "Restock cannonballs (%d/%d)" % [sloop.cannonballs_remaining, Ship.MAX_CANNONBALLS],
		"partial cannonball prompt switches to Restock")

	# Low tier (~12%)
	sloop.cannonballs_remaining = 5
	sloop.planks_remaining = 3
	sb_sloop.sync_fill_visuals()
	check(sb_sloop._ammo_fill_mi.visible and sb_sloop._ammo_fill_mi.position.y < ammo_y_mid,
		"low ammo tier lowers roundshot stack further")
	check(sb_sloop._plank_fill_mi.visible and sb_sloop._plank_fill_mi.position.y < plank_y_mid,
		"low plank tier lowers plank bundle further")

	# Empty tier (0)
	sloop.cannonballs_remaining = 0
	sloop.planks_remaining = 0
	sb_sloop.sync_fill_visuals()
	check(not sb_sloop._ammo_fill_mi.visible, "ammo fill mesh hides at 0 cannonballs")
	check(not sb_sloop._plank_fill_mi.visible, "plank fill mesh hides at 0 planks")
	check_near(sb_sloop.get_fill_ratio(&"cannonball"), 0.0, 0.001, "empty cannonball fill ratio == 0.0")
	check_near(sb_sloop.get_fill_ratio(&"planks"), 0.0, 0.001, "empty planks fill ratio == 0.0")

	# 4. One-press restock & rations heal (+25 HP clamped to max_health) + signals & ASCII notices!
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(sloop, sloop.ship_point(Vector3(-0.35, -0.85, 0.72)))
	await physics_frames(4)

	var used_events: Array[StringName] = []
	var ship_taken_count := [0]
	var notices: Array[String] = []
	sb_sloop.barrel_used.connect(func(k: StringName, _p: Node) -> void: used_events.append(k))
	sloop.supplies_taken.connect(func(_p: Node) -> void: ship_taken_count[0] += 1)
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	# One-press cannonball restock via Interactable.interact(captain)
	ammo_it.interact(captain)
	check_eq(sloop.cannonballs_remaining, Ship.MAX_CANNONBALLS, "CannonballBarrel refills cannonballs to MAX")
	check(sb_sloop._ammo_fill_mi.visible and is_equal_approx(sb_sloop._ammo_fill_mi.position.y, ammo_y_full),
		"CannonballBarrel restores full roundshot stack visual")
	check_eq(used_events.size(), 1, "barrel_used emitted once for cannonball")
	check_eq(used_events[0], &"cannonball", "barrel_used emits &'cannonball'")
	check_eq(ship_taken_count[0], 1, "ship.supplies_taken emitted on cannonball restock")

	# One-press oak plank restock via Interactable.interact(captain)
	plank_it.interact(captain)
	check_eq(sloop.planks_remaining, Ship.MAX_PLANKS, "PlankBarrel refills planks to MAX")
	check(sb_sloop._plank_fill_mi.visible and is_equal_approx(sb_sloop._plank_fill_mi.position.y, plank_y_full),
		"PlankBarrel restores full plank bundle visual")
	check_eq(used_events.size(), 2, "barrel_used emitted for planks")
	check_eq(used_events[1], &"planks", "barrel_used emits &'planks'")
	check_eq(ship_taken_count[0], 2, "ship.supplies_taken emitted on plank restock")

	# One-press rations & grog barrel heals +25 HP and clamps cleanly to max_health!
	captain.apply_damage(40.0)  # 60 / 100 HP
	rations_it.interact(captain)
	check_near(captain.health, 85.0, 0.01, "RationsBarrel heals damaged pawn by +25 HP (60 -> 85)")
	check_eq(used_events.size(), 3, "barrel_used emitted for rations")
	check_eq(used_events[2], &"rations", "barrel_used emits &'rations'")
	rations_it.interact(captain)
	check_near(captain.health, captain.max_health, 0.01, "RationsBarrel clamps heal cleanly to max_health (85 -> 100)")

	for n_txt: String in notices:
		for ci in n_txt.length():
			check(n_txt.unicode_at(ci) < 128, "ShipSupplyBarrels notice is strictly ASCII ('%s')" % n_txt)
	for it_chk: Interactable in [ammo_it, plank_it, rations_it]:
		for ci in it_chk.prompt.length():
			check(it_chk.prompt.unicode_at(ci) < 128, "barrel prompt is strictly ASCII ('%s')" % it_chk.prompt)

	# 5. Live Ship events (fire_cannon, patch_hole, apply_net_state) auto-sync barrel prompts & fill visuals!
	var ball := sloop.fire_cannon(&"port")
	check(ball != null, "sloop fires port cannon")
	check(ammo_it.prompt.contains("(%d/%d)" % [Ship.MAX_CANNONBALLS - 1, Ship.MAX_CANNONBALLS]),
		"fire_cannon automatically updates CannonballBarrel prompt (got '%s')" % ammo_it.prompt)

	var h_idx := sloop.apply_hull_damage(sloop.global_transform * sloop.ship_point(Vector3(1.9, -0.35, 0.4)), 0.5)
	check(h_idx >= 0 and sloop.patch_hole(h_idx), "sloop patches hull breach consuming 1 plank")
	check(plank_it.prompt.contains("(%d/%d)" % [Ship.MAX_PLANKS - 1, Ship.MAX_PLANKS]),
		"patch_hole automatically updates PlankBarrel prompt (got '%s')" % plank_it.prompt)

	# apply_net_state syncs client ship barrel fill visuals cleanly!
	sloop.cannonballs_remaining = 0
	sloop.planks_remaining = 0
	var snap_empty := sloop.get_net_state()
	brig.apply_net_state(snap_empty)
	check(not sb_brig._ammo_fill_mi.visible and not sb_brig._plank_fill_mi.visible,
		"apply_net_state automatically syncs ShipSupplyBarrels fill visuals to empty")

	Game.notice.disconnect(notice_cb)

	# 6. Clean 0-leak ref-counted teardown releases all ShipSupplyBarrels static caches!
	await _end()
	check_eq(ShipSupplyBarrels._active_instances, 0, "ShipSupplyBarrels._active_instances returns to 0 on teardown")
	check(ShipSupplyBarrels._cannon_oak_mesh == null and ShipSupplyBarrels._ammo_fill_mesh == null \
		and ShipSupplyBarrels._plank_fill_mesh == null and ShipSupplyBarrels._rations_brass_mesh == null \
		and ShipSupplyBarrels._oak_mat == null and ShipSupplyBarrels._iron_mat == null \
		and ShipSupplyBarrels._brass_mat == null and ShipSupplyBarrels._pbr_tex_cache.is_empty(),
		"ShipSupplyBarrels releases all static meshes, PBR materials, and WeakRef cache cleanly (0 leaks)")


func test_wave30_physical_mast_tilt_active_repair_bilge_pump_and_cannon_recoil() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 6.0, 0.0)

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	_root.add_child(brig)
	brig.global_position = Vector3(36.0, 0.0, 0.0)
	await physics_frames(4)

	# 1. ShipDamageVisuals mounted on Sloop & Brigantine, >= 480 sculpted tris, 0 PrimitiveMesh, uv1_world_triplanar == false.
	var dv_sloop := sloop.get_damage_visuals()
	var dv_brig := brig.get_damage_visuals()
	check(dv_sloop != null, "Sloop mounts ShipDamageVisuals via get_damage_visuals()")
	check(dv_brig != null, "Brigantine mounts ShipDamageVisuals via get_damage_visuals()")

	var pump_sloop := dv_sloop.get_node_or_null(^"BilgePumpRoot") as Node3D
	var pump_brig := dv_brig.get_node_or_null(^"BilgePumpRoot") as Node3D
	check(pump_sloop != null and pump_sloop.position.is_equal_approx(sloop.ship_point(Vector3(0.0, -0.85, -2.1))),
		"Sloop bilge pump mounts at Station_Bilge coordinate")
	check(pump_brig != null and pump_brig.position.is_equal_approx(brig.ship_point(Vector3(0.0, -0.95, 2.0))),
		"Brigantine bilge pump mounts at Station_Bilge coordinate")
	if pump_sloop != null:
		check(pump_sloop.scale.is_equal_approx(Vector3.ONE * sloop.hull_scale),
			"Sloop bilge pump scales cleanly with hull_scale")
	if pump_brig != null:
		check(pump_brig.scale.is_equal_approx(Vector3.ONE * brig.hull_scale),
			"Brigantine bilge pump scales cleanly with hull_scale")

	var raw_prims := 0
	var bad_norms := 0
	var bad_mats := 0
	var world_triplanar_hits := 0
	for n in dv_sloop.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			raw_prims += 1
		var am := mi.mesh as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_norms += 1
		var mat := mi.material_override as StandardMaterial3D
		if mat == null or not mat.vertex_color_use_as_albedo or not mat.vertex_color_is_srgb \
				or not mat.uv1_triplanar:
			bad_mats += 1
		elif mat.uv1_world_triplanar:
			world_triplanar_hits += 1
	var dmg_tris := dv_sloop.get_triangle_count()
	print("    Wave 30A ShipDamageVisuals sculpted tris: %d" % dmg_tris)
	check_eq(raw_prims, 0, "ShipDamageVisuals contains ZERO PrimitiveMeshes")
	check_eq(bad_norms, 0, "ShipDamageVisuals normals are all finite unit vectors")
	check_eq(bad_mats, 0, "ShipDamageVisuals uses sRGB vertex colors + triplanar StandardMaterial3D")
	check_eq(world_triplanar_hits, 0, "ShipDamageVisuals sets uv1_world_triplanar == false on all materials")
	check(dmg_tris >= 480, "ShipDamageVisuals sculpted triangle count >= 480 (got %d)" % dmg_tris)

	# 2. Chainshot apply_sail_damage(12.0) -> physical yardarm roll tilt > 0.10, splinter burst active,
	#    focus prompt "Mend damaged rigging", HUD hint, and active [W] hauling repairs >= 2.8x faster!
	sloop.set_sail_target(0.85)
	sloop.sail_set = 0.85
	brig.set_sail_target(0.85)
	brig.sail_set = 0.85

	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(sloop, sloop.ship_point(Vector3(0.0, 1.15, 0.5)))
	var pc := PlayerController.new()
	pc.capture_mouse = false
	pc.input_enabled = false
	pc.make_current = false
	captain.add_child(pc)
	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, null, null, sloop, null, null)
	await get_tree().process_frame
	hud.set_process(false)

	var repaired_count := [0]
	var notices: Array[String] = []
	sloop.sail_repaired.connect(func() -> void: repaired_count[0] += 1)
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	sloop.apply_sail_damage(12.0)
	brig.apply_sail_damage(12.0)
	check(dv_sloop.is_splinter_burst_active(), "apply_sail_damage triggers sculpted spar splinter burst")
	check_near(sloop.get_sail_damage_remaining(), 12.0, 0.05, "get_sail_damage_remaining reports ~12.0 s")

	# Step visuals so smooth yardarm cant settles cleanly past 0.10 rad.
	for _i in 24:
		sloop._update_visuals(1.0 / 60.0)
		brig._update_visuals(1.0 / 60.0)
	check(not sloop._yards.is_empty(), "Sloop has main Yard pivot")
	check(not brig._yards.is_empty(), "Brigantine has Yard pivots")
	if not sloop._yards.is_empty():
		var sloop_yard := sloop._yards[0]
		check(absf(sloop_yard.rotation.z) > 0.10,
			"Chainshot cants Sloop yardarm roll > 0.10 rad (got %.3f)" % sloop_yard.rotation.z)
	if not brig._yards.is_empty():
		var brig_yard := brig._yards[0]
		check(absf(brig_yard.rotation.z) > 0.10,
			"Chainshot cants Brigantine yardarm roll > 0.10 rad (got %.3f)" % brig_yard.rotation.z)

	var sail_st := sloop.get_station(&"sail_length")
	check(sail_st != null, "Sloop has Station_SailLength")
	check_eq(sail_st.get_focus_prompt(), "Mend damaged rigging",
		"Station_SailLength focus prompt reads 'Mend damaged rigging' while damaged")

	check(captain.enter_station(sail_st), "captain enters Station_SailLength to mend rigging")
	hud._process(0.05)
	var dmg_meta := hud.get_tool_meta_text()
	check(dmg_meta.contains("Rigging Damaged (") and dmg_meta.contains("[Hold W] Mend Rigging | [F] Leave"),
		"HUD Sail Hoist chip shows damaged rigging mend hint (got '%s')" % dmg_meta)
	for ci in dmg_meta.length():
		check(dmg_meta.unicode_at(ci) < 128, "HUD rigging mend hint is strictly ASCII")

	# Compare 1.0 s of active hauling ([W], axis.y = +1.0) on Sloop vs passive decay on Brigantine.
	var sloop_before := sloop.sail_damage_timer
	var brig_before := brig.sail_damage_timer
	const DT := 1.0 / 60.0
	for _i in 60:
		sail_st.drive(Vector2(0.0, 1.0), false, false, DT)
		sloop._tick_controls(DT)
		brig._tick_controls(DT)
	var active_drop := sloop_before - sloop.sail_damage_timer
	var passive_drop := brig_before - brig.sail_damage_timer
	check(passive_drop > 0.5 and active_drop >= passive_drop * 2.8,
		"Active [W] rigging repair reduces sail_damage_timer >= 2.8x faster (active=%.2f s vs passive=%.2f s)" % [
			active_drop, passive_drop])

	# Continue active hauling until fully mended -> emits sail_repaired and restores yardarm roll near 0.0!
	var mend_ticks := 0
	while sloop.sail_damage_timer > 0.0 and mend_ticks < 240:
		sail_st.drive(Vector2(0.0, 1.0), false, false, DT)
		sloop._tick_controls(DT)
		mend_ticks += 1
	check_near(sloop.get_sail_damage_remaining(), 0.0, 0.001, "Active hauling mends sail_damage_timer completely to 0.0")
	check_eq(repaired_count[0], 1, "sail_repaired signal emitted once when reaching 0.0")
	check(notices.has("Rigging mended! Full sail restored."),
		"Player ship posts strict-ASCII 'Rigging mended! Full sail restored.' notice")
	for n_txt: String in notices:
		for ci in n_txt.length():
			check(n_txt.unicode_at(ci) < 128, "Ship sail repair notice is strictly ASCII ('%s')" % n_txt)

	# Yardarm roll smoothly returns near 0.0 after repair & splinter burst finishes cleanly!
	for _i in 100:
		sloop._update_visuals(DT)
		dv_sloop.step(DT)
	if not sloop._yards.is_empty():
		check(absf(sloop._yards[0].rotation.z) < 0.02,
			"Repaired Sloop yardarm roll returns near 0.0 (got %.4f)" % sloop._yards[0].rotation.z)
	check(not dv_sloop.is_splinter_burst_active(), "Splinter burst finishes and hides cleanly after ~1.45 s")
	check(sail_st.get_focus_prompt() != "Mend damaged rigging",
		"Station_SailLength focus prompt returns to sail hoist after repair")
	captain.leave_station()

	# 3. Animated Bilge Pump lever rocking & overboard water plume while driving Station_Bilge!
	var bilge_st := sloop.get_station(&"bilge")
	check(bilge_st != null, "Sloop has Station_Bilge")
	check_near(dv_sloop.get_pump_handle_angle(), 0.0, 0.001, "Bilge pump handle rests at 0.0 when idle")
	check(not dv_sloop.is_pump_streaming(), "Bilge pump water plume is hidden when idle")

	sloop.water_level = 0.45
	check(captain.enter_station(bilge_st), "captain enters Station_Bilge")
	var peak_handle_angle := 0.0
	var saw_streaming := false
	for _i in 30:
		bilge_st.drive(Vector2(0.0, 1.0), true, false, DT)
		dv_sloop.step(DT)
		peak_handle_angle = maxf(peak_handle_angle, absf(dv_sloop.get_pump_handle_angle()))
		if dv_sloop.is_pump_streaming():
			saw_streaming = true
	check(peak_handle_angle > 0.18,
		"Driving Station_Bilge rocks sculpted pump handle lever (peak=%.3f rad)" % peak_handle_angle)
	check(saw_streaming, "Driving Station_Bilge streams sculpted overboard water plume")
	captain.leave_station()

	# Idle settle turns off water plume and returns pump lever back to rest.
	for _i in 80:
		dv_sloop.step(DT)
	check(not dv_sloop.is_pump_streaming(), "Bilge pump water plume fades & hides cleanly when idle")
	check(absf(dv_sloop.get_pump_handle_angle()) < 0.02,
		"Bilge pump handle returns to rest when idle (got %.4f)" % dv_sloop.get_pump_handle_angle())

	# 4. Cannon barrel recoil kick (0.34 m) + sculpted priming fuse spark + damped spring return < 0.02 within 0.6 s!
	var stbd_cannon: Dictionary = sloop._cannons[&"starboard"]
	var stbd_barrel: Node3D = stbd_cannon["barrel"] as Node3D
	var barrel_rest: Vector3 = stbd_cannon["barrel_rest_pos"] as Vector3
	check(stbd_barrel != null, "Sloop starboard cannon barrel Node3D exists")
	check_near(sloop.get_cannon_recoil(&"starboard"), 0.0, 0.001, "Starboard cannon starts with 0.0 recoil")

	var shot := sloop.fire_cannon(&"starboard", captain)
	check(shot != null, "Sloop fires starboard cannon")
	var recoil_after_fire := sloop.get_cannon_recoil(&"starboard")
	check(recoil_after_fire >= 0.20,
		"Starboard cannon recoil >= 0.20 m right after firing (got %.3f m)" % recoil_after_fire)
	if stbd_barrel != null:
		var barrel_disp := stbd_barrel.position.distance_to(barrel_rest)
		check(barrel_disp >= 0.20,
			"Starboard cannon barrel shifts along local +Z from barrel_rest_pos (disp=%.3f m)" % barrel_disp)
	check(dv_sloop.is_fuse_flash_active(), "Firing cannon flares sculpted priming fuse spark star")

	# Advance 0.6 s (36 ticks at 60 Hz) -> recoil decays cleanly to < 0.02 and fuse spark hides!
	for _i in 36:
		sloop._tick_cannons(DT)
		sloop._update_visuals(DT)
		dv_sloop.step(DT)
	var recoil_after_decay := sloop.get_cannon_recoil(&"starboard")
	check(recoil_after_decay < 0.02,
		"Starboard cannon recoil decays cleanly to < 0.02 m within 0.6 s (got %.4f m)" % recoil_after_decay)
	if stbd_barrel != null:
		check(stbd_barrel.position.distance_to(barrel_rest) < 0.02,
			"Starboard cannon barrel returns cleanly to barrel_rest_pos")
	check(not dv_sloop.is_fuse_flash_active(), "Cannon priming fuse spark fades out cleanly")

	Game.notice.disconnect(notice_cb)

	# 5. Clean 0-leak ref-counted teardown & ShipDamageVisuals.clear_shared_cache()!
	await _end()
	ShipDamageVisuals.clear_shared_cache()
	check_eq(ShipDamageVisuals._active_instances, 0, "ShipDamageVisuals._active_instances returns to 0 on teardown")
	check(ShipDamageVisuals._pump_oak_mesh == null and ShipDamageVisuals._pump_iron_mesh == null \
		and ShipDamageVisuals._pump_brass_mesh == null and ShipDamageVisuals._pump_water_mesh == null \
		and ShipDamageVisuals._splinter_mesh == null and ShipDamageVisuals._canvas_shred_mesh == null \
		and ShipDamageVisuals._fuse_spark_mesh == null and ShipDamageVisuals._oak_mat == null \
		and ShipDamageVisuals._iron_mat == null and ShipDamageVisuals._brass_mat == null \
		and ShipDamageVisuals._canvas_mat == null and ShipDamageVisuals._water_mat == null \
		and ShipDamageVisuals._fuse_mat == null and ShipDamageVisuals._pbr_tex_cache.is_empty(),
		"ShipDamageVisuals.clear_shared_cache() leaves 0 cached meshes/materials/WeakRefs (0 leaks)")


func test_wave31_firebomb_ordnance_spreading_ship_fire_bucket_douse_and_crew_firefighting() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 6.0, 0.0)

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	sloop.set_anchor(true)
	sloop.anchor_progress = 1.0
	var target_sloop := _spawn_sloop(Vector3(24.0, 0.0, -1.5))
	target_sloop.faction = &"drowned"
	target_sloop.set_anchor(true)
	target_sloop.anchor_progress = 1.0
	var brig_scene: PackedScene = load("res://src/ship/brigantine.tscn")
	var brig := brig_scene.instantiate() as Ship
	brig.enable_effects = false
	brig.start_anchored = true
	_root.add_child(brig)
	brig.global_position = Vector3(-42.0, 0.0, 0.0)
	await physics_frames(8)

	# 1. Sculpted zero-primitive &"firebomb" Cannonball (>= 320 tris) & ShipFire (>= 420 tris)!
	var fb_probe := Cannonball.new()
	fb_probe.enable_effects = false
	fb_probe.ordnance_style = &"firebomb"
	_root.add_child(fb_probe)
	fb_probe.global_position = Vector3(0.0, 45.0, 0.0)
	await physics_frames(1)
	check_eq(fb_probe.get_resolved_ordnance_style(), &"firebomb", "Cannonball resolves &'firebomb'")
	var fb_mi := fb_probe.get_node_or_null(^"IronBall") as MeshInstance3D
	check(fb_mi != null and fb_mi.mesh is ArrayMesh and not (fb_mi.mesh is PrimitiveMesh),
		"Firebomb uses sculpted ArrayMesh (zero PrimitiveMesh)")
	var fb_tris := 0
	var fb_bad_norms := 0
	if fb_mi != null and fb_mi.mesh is ArrayMesh:
		var fb_am := fb_mi.mesh as ArrayMesh
		check_eq(fb_am.get_surface_count(), 2, "Firebomb sculpted mesh has 2 surfaces (flask + glowing core)")
		for si in fb_am.get_surface_count():
			var arr := fb_am.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			fb_tris += floori(float(verts.size()) / 3.0)
			for nv in norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					fb_bad_norms += 1
			var ov_mat := fb_mi.get_surface_override_material(si) as StandardMaterial3D
			check(ov_mat != null and ov_mat.vertex_color_use_as_albedo and ov_mat.vertex_color_is_srgb,
				"Firebomb surface %d enables sRGB vertex color albedo" % si)
	check_eq(fb_bad_norms, 0, "Firebomb normals are all finite unit vectors")
	check(fb_tris >= 320, "Firebomb sculpted triangle count >= 320 (got %d)" % fb_tris)
	check(fb_probe.firebomb_light != null and not fb_probe.firebomb_light.shadow_enabled
		and fb_probe.firebomb_light.omni_range >= 10.0,
		"Firebomb equips unshadowed warm flickering travel OmniLight3D")
	fb_probe.queue_free()
	await physics_frames(2)

	var sf_sloop := sloop.get_ship_fire()
	var sf_brig := brig.get_ship_fire()
	check(sf_sloop != null, "Sloop mounts ShipFire via get_ship_fire()")
	check(sf_brig != null, "Brigantine mounts ShipFire via get_ship_fire()")
	var sf_tris := sf_sloop.get_triangle_count()
	check(sf_tris >= 420, "ShipFire sculpted flame cluster triangle count >= 420 (got %d)" % sf_tris)
	var sf_prims := 0
	var sf_bad_norms := 0
	var sf_bad_mats := 0
	for n in sf_sloop.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is PrimitiveMesh:
			sf_prims += 1
		var am := mi.mesh as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						sf_bad_norms += 1
		var smat := mi.material_override as StandardMaterial3D
		if smat == null or not smat.vertex_color_use_as_albedo or not smat.vertex_color_is_srgb or not smat.emission_enabled:
			sf_bad_mats += 1
		check_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"ShipFire flame clusters disable shadow casting")
	check_eq(sf_prims, 0, "ShipFire contains ZERO PrimitiveMeshes")
	check_eq(sf_bad_norms, 0, "ShipFire normals are all finite unit vectors")
	check_eq(sf_bad_mats, 0, "ShipFire uses sRGB vertex-color emissive StandardMaterial3D")
	var sf_light := sf_sloop.get_fire_light()
	check(sf_light != null and not sf_light.shadow_enabled and not sf_light.visible,
		"ShipFire OmniLight3D is unshadowed and hidden when active_count == 0")
	print("    Wave 31B sculpted tris: firebomb=%d, ship_fire_cluster=%d" % [fb_tris, sf_tris])

	# 2. 6-item Ordnance Cycle: iron -> chainshot -> firebomb -> anchorball -> ballastball -> flare -> iron!
	check_eq(sloop.cannon_ordnance, &"iron", "starts on &'iron'")
	check_eq(sloop.cycle_cannon_ordnance(), &"chainshot", "cycle 1 -> &'chainshot'")
	check_eq(sloop.cycle_cannon_ordnance(), &"firebomb", "cycle 2 -> &'firebomb'")
	check_eq(sloop.get_cannon_ordnance_label(), "Firebomb", "Firebomb label matches strict ASCII")
	check_eq(sloop.cycle_cannon_ordnance(), &"anchorball", "cycle 3 -> &'anchorball'")
	check_eq(sloop.cycle_cannon_ordnance(), &"ballastball", "cycle 4 -> &'ballastball'")
	check_eq(sloop.cycle_cannon_ordnance(), &"flare", "cycle 5 -> &'flare'")
	check_eq(sloop.cycle_cannon_ordnance(), &"iron", "cycle 6 wraps -> &'iron'")

	# 3. Firing a &"firebomb" cannonball into target_sloop ignites deck fires (without punching a deep iron hull breach)
	#    and fire_mask round-trips cleanly via get_net_state() / apply_net_state()!
	sloop.set_cannon_ordnance(&"firebomb")
	sloop.aim_cannon(&"starboard", 0.0, -0.02)
	var fb_shot := sloop.fire_cannon(&"starboard")
	check(fb_shot != null and fb_shot.get_resolved_ordnance_style() == &"firebomb",
		"Sloop fires sculpted &'firebomb' cannonball")
	for _i in 90:
		await physics_frames(1)
		if target_sloop.has_deck_fire():
			break
	check(target_sloop.has_deck_fire() and target_sloop.get_active_fire_count() >= 1,
		"Firebomb impact ignites target ship deck fire (active=%d)" % target_sloop.get_active_fire_count())
	check_eq(target_sloop.open_hole_count(), 0,
		"Firebomb impact ignites fire instead of punching an immediate deep iron cannon hole")

	var target_sf := target_sloop.get_ship_fire()
	var mask_before := target_sf.get_fire_bitmask()
	check(mask_before > 0, "Ignited target ship produces non-zero fire_mask (%d)" % mask_before)
	var net_snap := target_sloop.get_net_state()
	check_eq(int(net_snap.get("fire_mask", 0)), mask_before, "Ship.get_net_state() includes fire_mask")
	brig.apply_net_state(net_snap)
	check_eq(sf_brig.get_fire_bitmask(), mask_before,
		"Ship.apply_net_state() restores fire_mask cleanly onto client ship")
	check(brig.has_deck_fire() and sf_brig.get_fire_light().visible,
		"Replicated fire_mask activates sculpted flames and shared OmniLight3D")
	sf_brig.douse_all()
	check(not brig.has_deck_fire() and not sf_brig.get_fire_light().visible,
		"douse_all() clears fires and hides shared OmniLight3D")

	# 4. Full Water Bucket (use_bucket() AND splash_bucket_forward()) extinguishes deck flames cleanly!
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(sloop, sloop.ship_point(Vector3(0.0, 1.12, -2.2)))
	var inv := Inventory.new()
	inv.name = "Inventory"
	inv.input_enabled = false
	captain.add_child(inv)
	await physics_frames(4)
	inv.equip(&"bucket", true)

	var notices: Array[String] = []
	var all_out_count := [0]
	sf_sloop.all_fires_out.connect(func() -> void: all_out_count[0] += 1)
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	# 4a. Test Inventory.use_bucket() on deck fire at zone 0 (foredeck).
	sloop.ignite_deck_fire(sf_sloop.get_zone_world_pos(0), false)
	check(sloop.has_deck_fire() and sf_sloop.get_fire_light().visible, "Sloop foredeck fire lit")
	inv.bucket_full = true
	var use_res := inv.use_bucket()
	check(int(use_res.get("fires_doused", 0)) >= 1,
		"Inventory.use_bucket() extinguishes deck fire and reports fires_doused >= 1 (got %s)" % str(use_res))
	check(not sloop.has_deck_fire(), "Sloop deck fire is fully extinguished after use_bucket()")
	check_eq(all_out_count[0], 1, "all_fires_out emitted once when last zone is doused")
	check(notices.has("Deck fires extinguished!"), "Player ship posts strict-ASCII 'Deck fires extinguished!'")

	# 4b. Test Inventory.splash_bucket_forward() on deck fire at zone 0.
	sloop.ignite_deck_fire(sf_sloop.get_zone_world_pos(0), false)
	check(sloop.has_deck_fire(), "Sloop foredeck fire re-lit for splash_bucket_forward()")
	inv.bucket_full = true
	var fwd_res := inv.splash_bucket_forward()
	check(int(fwd_res.get("fires_doused", 0)) >= 1,
		"Inventory.splash_bucket_forward() extinguishes deck fire (got %s)" % str(fwd_res))
	check(not sloop.has_deck_fire(), "Sloop deck fire is fully extinguished after splash_bucket_forward()")

	# 5. AI CrewBrain fire-fighting: Carpenter Pip detects deck fire, calls out strict-ASCII &"fire_aboard",
	#    sprints to flame, extinguishes it, and calls out strict-ASCII &"fire_doused"!
	for persona: StringName in [&"helmsman", &"lookout", &"carpenter"]:
		for cat: StringName in [&"fire_aboard", &"fire_doused"]:
			var line := CrewDialogue.format_line(persona, cat)
			check(line.length() > 8, "CrewDialogue has %s line for %s" % [String(cat), String(persona)])
			for ci in line.length():
				check(line.unicode_at(ci) < 128, "CrewDialogue %s/%s is strictly ASCII ('%s')" % [
					String(persona), String(cat), line])

	var pip := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(pip)
	var brain := CrewBrain.new()
	brain.name = "CrewBrain"
	pip.add_child(brain)
	brain.setup(sloop, captain, &"carpenter")
	pip.board(sloop, sloop.ship_point(Vector3(1.1, 1.12, 1.0)))
	await physics_frames(4)

	var crew_events: Array[Dictionary] = []
	brain.callout_spoken.connect(func(sp: String, txt: String, cat: StringName) -> void:
		crew_events.append({"speaker": sp, "text": txt, "cat": cat})
	)

	sloop.ignite_deck_fire(sf_sloop.get_zone_world_pos(0), false)
	check(sloop.has_deck_fire(), "Deck fire ignited for Carpenter Pip AI test")
	var saw_douse_task := false
	for _i in 320:
		await physics_frames(1)
		if brain.current_task == &"douse_fire":
			saw_douse_task = true
		if not sloop.has_deck_fire():
			break

	var saw_fire_aboard := false
	var saw_fire_doused := false
	for ev: Dictionary in crew_events:
		var ev_txt := String(ev["text"])
		for ci in ev_txt.length():
			check(ev_txt.unicode_at(ci) < 128, "Crew fire callout is strictly ASCII ('%s')" % ev_txt)
		if ev["cat"] == &"fire_aboard":
			saw_fire_aboard = true
		elif ev["cat"] == &"fire_doused":
			saw_fire_doused = true

	check(saw_douse_task, "CrewBrain Carpenter Pip switches to &'douse_fire' task")
	check(saw_fire_aboard, "CrewBrain calls out &'fire_aboard' upon detecting deck fire")
	check(not sloop.has_deck_fire(), "CrewBrain sprints to flame and extinguishes deck fire cleanly")
	check(saw_fire_doused, "CrewBrain calls out &'fire_doused' after extinguishing deck fire")

	Game.notice.disconnect(notice_cb)
	for n_txt: String in notices:
		for ci in n_txt.length():
			check(n_txt.unicode_at(ci) < 128, "Deck fire notice is strictly ASCII ('%s')" % n_txt)

	# 6. Clean 0-leak ref-counted teardown & clear_shared_cache()!
	await _end()
	ShipFire.clear_shared_cache()
	Cannonball.clear_shared_cache()
	check_eq(ShipFire._active_instances, 0, "ShipFire._active_instances returns to 0 on teardown")
	check(ShipFire._flame_mesh == null and ShipFire._flame_mat == null,
		"ShipFire.clear_shared_cache() leaves 0 cached meshes/materials (0 leaks)")
	check(Cannonball._firebomb_mesh == null and Cannonball._ball_meshes.is_empty(),
		"Cannonball.clear_shared_cache() clears _firebomb_mesh and _ball_meshes cleanly (0 leaks)")


func test_wave33_cannon_self_launch_and_interactive_boarding_ladders() -> void:
	_begin()
	Weather.set_weather(0.0, 0.0, 0.0)
	Sea.amp_scale = 0.0
	Sea.time = 0.0

	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	await physics_frames(8)

	# 1. Verify strict-ASCII CrewDialogue &"cannon_self_launch" callouts for all 3 personas.
	for persona: StringName in [&"helmsman", &"lookout", &"carpenter"]:
		var line := CrewDialogue.format_line(persona, &"cannon_self_launch")
		check(line.length() > 8, "CrewDialogue has cannon_self_launch line for %s" % String(persona))
		for ci in line.length():
			check(line.unicode_at(ci) < 128, "CrewDialogue %s/cannon_self_launch is strictly ASCII ('%s')" % [
				String(persona), line])

	# 2. Spawn Captain Pawn with PlayerController + AI CrewBrain mate (Barnaby) bound to sloop.
	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(sloop, sloop.ship_point(Vector3(1.1, 1.12, -1.5)))
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	pc.capture_mouse = false
	pc.input_enabled = false
	pc.make_current = false
	captain.add_child(pc)

	var crew_pawn := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(crew_pawn)
	var brain := CrewBrain.new()
	brain.name = "CrewBrain"
	crew_pawn.add_child(brain)
	brain.setup(sloop, captain, &"helmsman")
	crew_pawn.board(sloop, sloop.ship_point(Vector3(-0.8, 1.12, 1.8)))
	await physics_frames(4)

	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	var launched_events: Array[Array] = []
	sloop.pawn_cannon_launched.connect(func(side: StringName, lp: Node) -> void:
		launched_events.append([side, lp])
	)

	var crew_events: Array[Dictionary] = []
	brain.callout_spoken.connect(func(sp: String, txt: String, cat: StringName) -> void:
		crew_events.append({"speaker": sp, "text": txt, "cat": cat})
	)

	# 3. Verify normal & loaded cannon prompts + [RMB] climb-in / climb-out edge latch + station release cleanup.
	var stbd_st := sloop.get_station(&"cannon", &"starboard")
	check(stbd_st != null, "Sloop has starboard cannon station")
	var normal_prompt := stbd_st.get_active_prompt()
	check(normal_prompt.contains("[RMB] Climb In") and normal_prompt.contains("Fire (Iron)")
		and normal_prompt.contains("[R] Swap Shot"),
		"Normal cannon active prompt includes [RMB] Climb In alongside Fire and [R] Swap Shot (got '%s')" % normal_prompt)
	for ci in normal_prompt.length():
		check(normal_prompt.unicode_at(ci) < 128, "Normal cannon prompt is strictly ASCII")

	check(captain.enter_station(stbd_st), "Captain enters starboard cannon station")
	# Rising edge of [RMB] loads captain into cannon; holding [RMB] keeps loaded; next rising edge unloads!
	captain.drive_station(Vector2.ZERO, false, true, 0.016)
	check(sloop.is_pawn_loaded_in_cannon(&"starboard"), "[RMB] rising edge loads occupant into cannon barrel")
	captain.drive_station(Vector2.ZERO, false, true, 0.016)
	check(sloop.is_pawn_loaded_in_cannon(&"starboard"), "Holding [RMB] does not immediately unload occupant")
	captain.drive_station(Vector2.ZERO, false, false, 0.016)
	captain.drive_station(Vector2.ZERO, false, true, 0.016)
	check(not sloop.is_pawn_loaded_in_cannon(&"starboard"), "Second [RMB] press cleanly climbs back out")
	captain.drive_station(Vector2.ZERO, false, false, 0.016)
	captain.leave_station()

	# Verify leaving station via [F] while loaded also clears loaded_pawn cleanly.
	check(sloop.load_pawn_into_cannon(&"starboard", captain), "load_pawn_into_cannon succeeds directly")
	check(sloop.is_pawn_loaded_in_cannon(&"starboard"), "is_pawn_loaded_in_cannon reports true")
	captain.leave_station()
	check(not sloop.is_pawn_loaded_in_cannon(&"starboard"), "leave_station automatically unloads pawn from cannon")

	# 4. Load Captain into starboard cannon, verify loaded prompt & camera shift, then LAUNCH!
	sloop.aim_cannon(&"starboard", 0.0, 0.22)
	check(sloop.load_pawn_into_cannon(&"starboard", captain), "Captain climbs into starboard cannon barrel")
	check(sloop.is_pawn_loaded_in_cannon(&"starboard"), "is_pawn_loaded_in_cannon true after load")
	var loaded_prompt := stbd_st.get_active_prompt()
	check_eq(loaded_prompt, "[WASD] Aim  [LMB] LAUNCH YOURSELF!  [RMB] Climb Out  [F] Leave",
		"Loaded cannon active prompt matches strict-ASCII spec")
	for ci in loaded_prompt.length():
		check(loaded_prompt.unicode_at(ci) < 128, "Loaded cannon prompt is strictly ASCII")
	check(notices.has("Loaded into cannon! [WASD] Aim  [LMB] LAUNCH!  [F/X] Climb out"),
		"Loading into cannon posts strict-ASCII HUD notice")

	pc._update_camera(0.0)
	check(pc._cannon_cam_blend > 0.9, "PlayerController blends camera cleanly toward cannon muzzle while loaded")

	var hp_before := captain.health
	var launch_origin := sloop.global_position
	check(sloop.launch_pawn_from_cannon(&"starboard"), "launch_pawn_from_cannon succeeds")
	check(not sloop.is_pawn_loaded_in_cannon(&"starboard"), "cannon barrel cleared after self-launch")
	check_eq(launched_events.size(), 1, "pawn_cannon_launched emitted once")
	if not launched_events.is_empty():
		check_eq(launched_events[0][0], &"starboard", "pawn_cannon_launched reports &'starboard'")
		check(launched_events[0][1] == captain, "pawn_cannon_launched reports launched Captain pawn")
	check(captain.cannon_launched, "Captain pawn.cannon_launched is true right after launch")
	check(captain.station == null and captain.platform == null, "Captain detached from station and ship on launch")
	check(pc.get_camera_trauma() >= 0.45, "Captain PlayerController receives >= 0.45 camera trauma on launch")
	check(sloop.get_cannon_recoil(&"starboard") >= 0.30, "Starboard cannon kicks back with recoil on launch")

	# Verify CrewBrain received pawn_cannon_launched and spoke strict-ASCII &"cannon_self_launch" callout!
	var saw_crew_cheer := false
	for ev: Dictionary in crew_events:
		if ev["cat"] == &"cannon_self_launch":
			saw_crew_cheer = true
			var txt := String(ev["text"])
			for ci in txt.length():
				check(txt.unicode_at(ci) < 128, "Crew cannon_self_launch callout is strictly ASCII ('%s')" % txt)
	check(saw_crew_cheer, "CrewBrain hears pawn_cannon_launched and cheers strict-ASCII &'cannon_self_launch'")

	# Step physics frames until Captain splashes down cleanly into the ocean!
	var splashed := false
	for _i in 320:
		await physics_frames(1)
		if captain.mode == Pawn.Mode.SWIM:
			splashed = true
			break
	var horiz_dist := Vector2(captain.global_position.x - launch_origin.x, captain.global_position.z - launch_origin.z).length()
	print("    Wave 33A cannon self-launch: horiz_dist=%.1f m, mode=%d, hp=%.1f" % [horiz_dist, captain.mode, captain.health])
	check(horiz_dist > 25.0, "Cannon self-launch soars > 25 m horizontally (got %.1f m)" % horiz_dist)
	check(splashed and captain.mode == Pawn.Mode.SWIM, "Launched Captain splashes down cleanly into Mode.SWIM")
	check(not captain.cannon_launched, "Water splashdown clears pawn.cannon_launched = false")
	check_near(captain.health, hp_before, 0.01, "Ocean splashdown deals 0 fall damage (HP preserved)")

	# 5. Interactive [F] Hull Boarding Ladders on BOTH Friendly & Hostile Enemy Ships!
	for lad_name: String in ["Ladder_Port", "Ladder_Starboard"]:
		var player_lad := sloop.get_node_or_null(NodePath(lad_name)) as Ladder
		check(player_lad != null, "Player sloop has %s" % lad_name)
		var player_it := player_lad.get_node_or_null(^"BoardingLadderInteractable") as Interactable if player_lad != null else null
		check(player_it != null, "Player %s carries BoardingLadderInteractable" % lad_name)
		if player_it != null:
			check_eq(player_it.prompt, "Climb boarding ladder", "Friendly %s prompt matches strict ASCII" % lad_name)
			check_near(player_it.reach, 3.8 * sloop.hull_scale, 0.02, "Friendly %s reach matches 3.8 * hull_scale" % lad_name)

	var enemy_ship := SLOOP_SCENE.instantiate() as Ship
	enemy_ship.faction = &"drowned"
	enemy_ship.enable_effects = false
	_root.add_child(enemy_ship)
	enemy_ship.global_position = Vector3(85.0, 0.0, 0.0)
	await physics_frames(6)

	var enemy_port_lad: Ladder = null
	var enemy_port_it: Interactable = null
	for lad_name: String in ["Ladder_Port", "Ladder_Starboard"]:
		var e_lad := enemy_ship.get_node_or_null(NodePath(lad_name)) as Ladder
		check(e_lad != null, "Enemy drowned ship has %s" % lad_name)
		var e_it := e_lad.get_node_or_null(^"BoardingLadderInteractable") as Interactable if e_lad != null else null
		check(e_it != null, "Enemy %s carries BoardingLadderInteractable" % lad_name)
		if e_it != null:
			check_eq(e_it.prompt, "Board enemy ship", "Hostile %s prompt reads 'Board enemy ship'" % lad_name)
			for ci in e_it.prompt.length():
				check(e_it.prompt.unicode_at(ci) < 128, "Hostile boarding ladder prompt is strictly ASCII")
			if lad_name == "Ladder_Port":
				enemy_port_lad = e_lad
				enemy_port_it = e_it

	# Swim Captain alongside enemy ship's port boarding ladder and interact with [F]!
	check(enemy_port_lad != null and enemy_port_it != null, "Enemy port boarding ladder ready")
	if enemy_port_lad != null and enemy_port_it != null:
		var swim_pos := enemy_port_it.global_position + enemy_port_lad.global_basis.z * 1.4
		swim_pos.y = Sea.height(swim_pos.x, swim_pos.z) - captain.swim_float_depth
		captain.teleport(swim_pos)
		await physics_frames(3)
		check_eq(captain.mode, Pawn.Mode.SWIM, "Captain is swimming alongside hostile ship")
		check(enemy_port_it.can_interact(captain), "Swimmer can interact with enemy BoardingLadderInteractable")
		captain.host_interact(enemy_port_it)
		check_eq(captain.mode, Pawn.Mode.LADDER, "Interacting with enemy boarding ladder latches Captain into Mode.LADDER")
		check(captain.platform == enemy_ship, "Captain boards hostile enemy_ship platform upon grabbing ladder")
		check(captain.ladder == enemy_port_lad, "Captain is latched onto enemy ship's Ladder_Port")

	Game.notice.disconnect(notice_cb)
	for n_txt: String in notices:
		for ci in n_txt.length():
			check(n_txt.unicode_at(ci) < 128, "Wave 33A notice is strictly ASCII ('%s')" % n_txt)

	await _end()


func test_wave36_cursed_cannonballs_anchorball_ballastball_curse_physics_vfx_and_hud() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Sea.time = 0.0
	Weather.set_weather(0.0, 9.0, 0.0)

	# 1. Sculpted zero-primitive Anchorball (>= 480 tris) & Ballastball (>= 480 tris) meshes + unshadowed OmniLight3D!
	var anchor_tris := 0
	var ballast_tris := 0
	for c_kind: StringName in [&"anchorball", &"ballastball"]:
		var probe := Cannonball.new()
		probe.enable_effects = false
		probe.ordnance_style = c_kind
		_root.add_child(probe)
		probe.global_position = Vector3(0.0, 42.0, 0.0)
		await physics_frames(1)
		check_eq(probe.get_resolved_ordnance_style(), c_kind, "Cannonball resolves %s" % String(c_kind))
		var mi := probe.get_node_or_null(^"IronBall") as MeshInstance3D
		check(mi != null and mi.mesh is ArrayMesh and not (mi.mesh is PrimitiveMesh),
			"%s uses sculpted ArrayMesh (zero PrimitiveMesh)" % String(c_kind))
		var tri_cnt := 0
		var bad_norms := 0
		if mi != null and mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			check_eq(am.get_surface_count(), 2, "%s has 2 sculpted surfaces (iron + spectral relief)" % String(c_kind))
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				tri_cnt += floori(float(verts.size()) / 3.0)
				for nv in norms:
					if not nv.is_finite() or nv.length_squared() < 0.5:
						bad_norms += 1
				var ov_mat := mi.get_surface_override_material(si) as StandardMaterial3D
				check(ov_mat != null and ov_mat.vertex_color_use_as_albedo and ov_mat.vertex_color_is_srgb,
					"%s surface %d enables sRGB vertex color albedo" % [String(c_kind), si])
				check(ov_mat != null and ov_mat.albedo_texture == null,
					"%s surface %d allocates zero extra texture VRAM" % [String(c_kind), si])
		check_eq(bad_norms, 0, "%s normals are all finite unit vectors" % String(c_kind))
		check(tri_cnt >= 480, "%s sculpted triangle count >= 480 (got %d)" % [String(c_kind), tri_cnt])
		check(probe.curse_light != null and not probe.curse_light.shadow_enabled and probe.curse_light.omni_range >= 12.0,
			"%s equips unshadowed spectral OmniLight3D (range=%.1f)" % [
				String(c_kind), probe.curse_light.omni_range if probe.curse_light != null else 0.0])
		if c_kind == &"anchorball":
			anchor_tris = tri_cnt
			check(probe.curse_light != null and probe.curse_light.light_color.g > probe.curse_light.light_color.r
				and probe.curse_light.light_color.g > probe.curse_light.light_color.b,
				"Anchorball travel OmniLight3D glows spectral emerald")
		else:
			ballast_tris = tri_cnt
			check(probe.curse_light != null and probe.curse_light.light_color.b > probe.curse_light.light_color.g
				and probe.curse_light.light_color.r > probe.curse_light.light_color.g,
				"Ballastball travel OmniLight3D glows spectral amethyst-violet")
		probe.queue_free()
	await physics_frames(2)

	# 2. Ship sculpted spectral CurseRing (>= 192 tris, 0 primitives, 0 extra VRAM) & full 6-item [R] HUD cycle!
	var sloop := _spawn_sloop(Vector3(0.0, 0.0, 0.0))
	sloop.set_anchor(true)
	sloop.anchor_progress = 1.0
	await physics_frames(4)

	var ring_mi := sloop.get_curse_ring_mesh_instance()
	check(ring_mi != null and not ring_mi.visible, "Ship spectral CurseRing mounts cleanly and starts hidden")
	check(ring_mi != null and ring_mi.mesh is ArrayMesh and not (ring_mi.mesh is PrimitiveMesh),
		"Ship CurseRing uses sculpted ArrayMesh (zero PrimitiveMesh)")
	var ring_tris := 0
	var ring_bad_norms := 0
	if ring_mi != null and ring_mi.mesh is ArrayMesh:
		var r_am := ring_mi.mesh as ArrayMesh
		for si in r_am.get_surface_count():
			var r_arr := r_am.surface_get_arrays(si)
			var r_verts: PackedVector3Array = r_arr[Mesh.ARRAY_VERTEX]
			var r_norms: PackedVector3Array = r_arr[Mesh.ARRAY_NORMAL]
			ring_tris += floori(float(r_verts.size()) / 3.0)
			for nv in r_norms:
				if not nv.is_finite() or nv.length_squared() < 0.5:
					ring_bad_norms += 1
		var r_mat := ring_mi.material_override as StandardMaterial3D
		check(r_mat != null and r_mat.vertex_color_use_as_albedo and r_mat.vertex_color_is_srgb
			and r_mat.albedo_texture == null,
			"Ship CurseRing material uses sRGB vertex colors with zero extra texture VRAM")
	check_eq(ring_bad_norms, 0, "Ship CurseRing normals are all finite unit vectors")
	check(ring_tris >= 192, "Ship CurseRing sculpted triangle count >= 192 (got %d)" % ring_tris)

	var captain := PAWN_SCENE.instantiate() as Pawn
	_root.add_child(captain)
	captain.board(sloop, sloop.ship_point(Vector3(-1.0, 1.12, -1.0)))
	var pc := PlayerController.new()
	pc.capture_mouse = false
	pc.input_enabled = false
	pc.make_current = false
	captain.add_child(pc)
	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(captain, pc, null, null, sloop, null, null)
	await get_tree().process_frame
	hud.set_process(false)

	var cannon_st := sloop.get_station(&"cannon", &"port")
	check(captain.enter_station(cannon_st), "Captain enters port cannon station for 6-ordnance HUD test")
	var expected_cycle: Array[Array] = [
		[&"iron", "Iron"],
		[&"chainshot", "Chainshot"],
		[&"firebomb", "Firebomb"],
		[&"anchorball", "Anchorball"],
		[&"ballastball", "Ballastball"],
		[&"flare", "Flare"],
	]
	var seen_colors: Array[Color] = []
	for step_i in expected_cycle.size():
		var exp_kind: StringName = expected_cycle[step_i][0]
		var exp_label: String = expected_cycle[step_i][1]
		check_eq(sloop.cannon_ordnance, exp_kind, "Ordnance cycle step %d == %s" % [step_i, String(exp_kind)])
		check_eq(sloop.get_cannon_ordnance_label(), exp_label, "Ordnance label step %d == %s" % [step_i, exp_label])
		hud._process(0.05)
		check_eq(hud.get_tool_title_text(), "Ship Cannon", "HUD tool title stays Ship Cannon on %s" % exp_label)
		check(hud.is_ordnance_chip_visible(), "HUD cannon ordnance badge visible for %s" % exp_label)
		check_eq(hud.get_ordnance_chip_text(), exp_label, "HUD ordnance badge displays %s" % exp_label)
		check(hud.get_tool_meta_text().contains("Shot: %s" % exp_label)
			and hud.get_tool_meta_text().contains("[R] Swap Shot"),
			"HUD cannon meta shows Shot: %s and [R] Swap Shot (got '%s')" % [exp_label, hud.get_tool_meta_text()])
		var active_prompt := cannon_st.get_active_prompt()
		check(active_prompt.contains("Fire (%s)" % exp_label),
			"Cannon active prompt shows Fire (%s)" % exp_label)
		for txt_check: String in [exp_label, hud.get_ordnance_chip_text(), hud.get_tool_meta_text(), active_prompt]:
			for ci in txt_check.length():
				check(txt_check.unicode_at(ci) < 128, "HUD/Prompt ordnance string is strictly ASCII ('%s')" % txt_check)
		var acc_col := GameHUD.get_ordnance_accent_color(exp_kind)
		check(acc_col.is_equal_approx(hud.get_active_ordnance_accent_color()),
			"HUD live cannon accent color matches GameHUD.get_ordnance_accent_color(%s)" % String(exp_kind))
		for prev_col: Color in seen_colors:
			check(not acc_col.is_equal_approx(prev_col),
				"Ordnance accent color for %s is distinct from prior ordnance colors" % String(exp_kind))
		seen_colors.append(acc_col)
		pc._handle_station_special_action()
	check_eq(sloop.cannon_ordnance, &"iron", "6th [R] press wraps cleanly back to &'iron'")
	# Verify emerald & violet color signatures specifically.
	var col_anc := GameHUD.get_ordnance_accent_color(&"anchorball")
	var col_bal := GameHUD.get_ordnance_accent_color(&"ballastball")
	check(col_anc.g > col_anc.r and col_anc.g > col_anc.b, "HUD Anchorball accent color is spectral emerald")
	check(col_bal.b > col_bal.g and col_bal.r > col_bal.g, "HUD Ballastball accent color is spectral violet")
	captain.leave_station()
	hud._process(0.05)
	check(not hud.is_ordnance_chip_visible(), "HUD cannon ordnance badge hides after leaving cannon station")

	# 3. Live Anchorball shot into a sailing ship drops anchor immediately, pulses emerald capstan ring, and halts forward speed!
	var notices: Array[String] = []
	var notice_cb := func(txt: String) -> void: notices.append(txt)
	Game.notice.connect(notice_cb)

	var sailing_victim := _spawn_sloop(Vector3(60.0, 0.0, 0.0))
	sailing_victim.faction = &"player"
	sailing_victim.set_anchor(false)
	sailing_victim.anchor_progress = 0.0
	sailing_victim.set_sail_target(1.0)
	sailing_victim.sail_set = 1.0
	sailing_victim.set_trim_target(0.0)
	sailing_victim.sail_trim = 0.0
	await physics_frames(150)
	var pre_hit_speed := sailing_victim.forward_speed()
	check(pre_hit_speed > 3.0, "Sailing victim reaches cruising speed before Anchorball hit (got %.2f m/s)" % pre_hit_speed)
	check(not sailing_victim.anchor_down, "Sailing victim anchor starts raised")

	var anchor_events: Array[Array] = []
	sailing_victim.cursed_hit.connect(func(k: StringName, dur: float) -> void: anchor_events.append([k, dur]))

	var shooter := _spawn_sloop(sailing_victim.global_position + Vector3(-20.0, 0.0, -1.8))
	shooter.set_anchor(true)
	shooter.anchor_progress = 1.0
	await physics_frames(3)
	shooter.set_cannon_ordnance(&"anchorball")
	shooter.aim_cannon(&"starboard", 0.0, -0.02)
	var anchor_shot := shooter.fire_cannon(&"starboard")
	check(anchor_shot != null and anchor_shot.get_resolved_ordnance_style() == &"anchorball",
		"Shooter fires sculpted &'anchorball' cannonball")
	for _i in 90:
		await physics_frames(1)
		if sailing_victim.anchor_down:
			break
	check(sailing_victim.anchor_down and sailing_victim.anchor_progress >= 0.99,
		"Anchorball impact immediately slams target ship anchor down (down=%s, prog=%.2f)" % [
			str(sailing_victim.anchor_down), sailing_victim.anchor_progress])
	check_eq(anchor_events.size(), 1, "Anchorball emits cursed_hit once")
	if not anchor_events.is_empty():
		check_eq(anchor_events[0][0], &"anchorball", "cursed_hit reports &'anchorball'")
		check(float(anchor_events[0][1]) >= 4.0, "cursed_hit reports 4.5 s emerald capstan FX duration")
	check(sailing_victim.anchor_curse_fx_timer > 3.0, "Anchorball activates emerald capstan FX timer")
	var anc_ring := sailing_victim.get_curse_ring_mesh_instance()
	sailing_victim._update_visuals(0.05)
	check(anc_ring != null and anc_ring.visible, "Anchorball activates visible spectral emerald capstan ring")
	var anc_mat := anc_ring.material_override as StandardMaterial3D if anc_ring != null else null
	check(anc_mat != null and anc_mat.emission.g > anc_mat.emission.r and anc_mat.emission.g > anc_mat.emission.b,
		"Anchorball capstan ring glows spectral emerald")
	check(notices.has("Cursed Anchorball strike! Anchor slammed to the seabed!"),
		"Player ship posts strict-ASCII Anchorball strike notice")
	check_eq(sailing_victim.open_hole_count(), 1, "Anchorball punches a modest tactical breach on impact")

	# Step physics frames -> slammed anchor rapidly brakes forward speed!
	await physics_frames(150)
	var post_anchor_speed := sailing_victim.forward_speed()
	check(post_anchor_speed < 0.75 and post_anchor_speed < pre_hit_speed * 0.25,
		"Anchorball halts sailing ship forward speed (%.2f -> %.2f m/s)" % [pre_hit_speed, post_anchor_speed])

	# 4. Live Ballastball shot: deeper draft, >= 1.8x flooding acceleration, violet waterline ring, net replication & 12 s decay!
	var ballast_victim := _spawn_sloop(Vector3(-55.0, 0.0, 0.0))
	ballast_victim.faction = &"player"
	ballast_victim.set_anchor(true)
	ballast_victim.anchor_progress = 1.0
	var control_ship := _spawn_sloop(Vector3(-85.0, 0.0, 0.0))
	control_ship.faction = &"drowned"
	control_ship.set_anchor(true)
	control_ship.anchor_progress = 1.0
	var ballast_shooter := _spawn_sloop(Vector3(-75.0, 0.0, -1.0))
	ballast_shooter.set_anchor(true)
	ballast_shooter.anchor_progress = 1.0
	await physics_frames(90)

	var y_normal := ballast_victim.global_position.y
	var ballast_events: Array[Array] = []
	ballast_victim.cursed_hit.connect(func(k: StringName, dur: float) -> void: ballast_events.append([k, dur]))

	ballast_shooter.set_cannon_ordnance(&"ballastball")
	ballast_shooter.aim_cannon(&"starboard", 0.0, -0.02)
	var ballast_shot := ballast_shooter.fire_cannon(&"starboard")
	check(ballast_shot != null and ballast_shot.get_resolved_ordnance_style() == &"ballastball",
		"Shooter fires sculpted &'ballastball' cannonball")
	for _i in 90:
		await physics_frames(1)
		if ballast_victim.is_ballast_cursed():
			break
	check(ballast_victim.is_ballast_cursed(), "Ballastball impact activates is_ballast_cursed() == true")
	check_eq(ballast_events.size(), 1, "Ballastball emits cursed_hit once")
	if not ballast_events.is_empty():
		check_eq(ballast_events[0][0], &"ballastball", "cursed_hit reports &'ballastball'")
		check_near(float(ballast_events[0][1]), Ship.BALLAST_CURSE_DURATION, 0.1,
			"cursed_hit reports 12.0 s Ballastball duration")
	check(notices.has("Cursed Ballastball strike! Hull dragging deep -- bail fast!"),
		"Player ship posts strict-ASCII Ballastball strike notice")

	var bal_ring := ballast_victim.get_curse_ring_mesh_instance()
	ballast_victim._update_visuals(0.05)
	check(bal_ring != null and bal_ring.visible, "Ballastball activates visible violet hull waterline ring")
	var bal_mat := bal_ring.material_override as StandardMaterial3D if bal_ring != null else null
	check(bal_mat != null and bal_mat.emission.b > bal_mat.emission.g and bal_mat.emission.r > bal_mat.emission.g,
		"Ballastball hull ring glows pulsing violet-amethyst")

	# 4a. Isolate pure buoyancy draft effect (patch impact breach + dry bilge) -> ship rides visibly deeper!
	for hi in ballast_victim.holes.size():
		ballast_victim.patch_hole(hi)
	ballast_victim.water_level = 0.0
	await physics_frames(110)
	var y_cursed := ballast_victim.global_position.y
	check(y_cursed < y_normal - 0.25,
		"Ballastball drags cursed hull visibly deeper (y_cursed=%.2f vs y_normal=%.2f)" % [y_cursed, y_normal])
	check(ballast_victim.global_basis.y.y > 0.90,
		"Ballastball cursed hull stays upright without capsizing (up.y=%.3f)" % ballast_victim.global_basis.y.y)

	# 4b. Open identical deepest hull breach on cursed vs uncursed ship -> cursed floods >= 1.8x faster!
	var deepest_idx := 0
	var deepest_y := INF
	for h: Dictionary in ballast_victim.holes:
		var ly := (h["local_pos"] as Vector3).y
		if ly < deepest_y:
			deepest_y = ly
			deepest_idx = int(h["index"])
	ballast_victim.ballast_curse_timer = Ship.BALLAST_CURSE_DURATION
	ballast_victim.water_level = 0.0
	control_ship.water_level = 0.0
	ballast_victim.apply_hull_damage(
		ballast_victim.global_transform * (ballast_victim.holes[deepest_idx]["local_pos"] as Vector3), 0.45)
	control_ship.apply_hull_damage(
		control_ship.global_transform * (control_ship.holes[deepest_idx]["local_pos"] as Vector3), 0.45)
	await physics_frames(180)
	var flood_cursed := ballast_victim.water_level
	var flood_normal := control_ship.water_level
	check(flood_normal > 0.02 and flood_cursed >= flood_normal * 1.8,
		"Ballastball accelerates open-breach flooding >= 1.8x (cursed=%.3f vs normal=%.3f, ratio=%.2fx)" % [
			flood_cursed, flood_normal, flood_cursed / maxf(flood_normal, 0.0001)])

	# 4c. Co-op net replication round-trip & backward compatibility with old state dicts!
	var snap := ballast_victim.get_net_state()
	check(float(snap.get("ballast_curse_timer", 0.0)) > 5.0,
		"Ship.get_net_state() includes ballast_curse_timer (got %.2f)" % float(snap.get("ballast_curse_timer", 0.0)))
	control_ship.apply_net_state(snap)
	check(control_ship.is_ballast_cursed()
		and is_equal_approx(control_ship.ballast_curse_timer, float(snap["ballast_curse_timer"])),
		"Ship.apply_net_state() replicates ballast_curse_timer cleanly")
	control_ship.apply_net_state({})
	check_near(control_ship.ballast_curse_timer, 0.0, 0.001,
		"Ship.apply_net_state() preserves backward compatibility with dicts omitting ballast_curse_timer")

	# 4d. Curse decays cleanly back to normal after 12 s!
	for hi in ballast_victim.holes.size():
		ballast_victim.patch_hole(hi)
	ballast_victim.water_level = 0.0
	ballast_victim.ballast_curse_timer = Ship.BALLAST_CURSE_DURATION
	await physics_frames(810)
	ballast_victim._update_visuals(0.05)
	var y_recovered := ballast_victim.global_position.y
	check(not ballast_victim.is_ballast_cursed() and is_zero_approx(ballast_victim.ballast_curse_timer),
		"Ballastball curse decays to 0.0 after 12 s (remaining=%.2f)" % ballast_victim.ballast_curse_timer)
	check(bal_ring != null and not bal_ring.visible,
		"Ballastball spectral waterline ring hides once curse expires")
	check(y_recovered > y_cursed + 0.35,
		"Hull recovers buoyantly after Ballastball curse expires (y_recovered=%.2f vs y_cursed=%.2f)" % [
			y_recovered, y_cursed])

	print("    Wave 36A tris: anchorball=%d, ballastball=%d, curse_ring=%d | speed %.2f->%.2f | y %.2f->%.2f->%.2f | flood %.2fx" % [
		anchor_tris, ballast_tris, ring_tris, pre_hit_speed, post_anchor_speed,
		y_normal, y_cursed, y_recovered, flood_cursed / maxf(flood_normal, 0.0001)])

	Game.notice.disconnect(notice_cb)
	for n_txt: String in notices:
		for ci in n_txt.length():
			check(n_txt.unicode_at(ci) < 128, "Wave 36A notice is strictly ASCII ('%s')" % n_txt)

	# 5. Clean zero-leak teardown!
	await _end()
	Cannonball.clear_shared_cache()
	Ship.clear_curse_ring_cache()
	check_eq(Cannonball._active_cannonballs, 0, "Cannonball._active_cannonballs returns to 0 on teardown")
	check(Cannonball._anchorball_mesh == null and Cannonball._ballastball_mesh == null
		and Cannonball._ball_meshes.is_empty(),
		"Cannonball.clear_shared_cache() releases _anchorball_mesh, _ballastball_mesh, and _ball_meshes (0 leaks)")
	check_eq(Ship._active_ship_count, 0, "Ship._active_ship_count returns to 0 on teardown")
	check(Ship._curse_ring_mesh == null, "Ship releases static _curse_ring_mesh cache cleanly (0 leaks)")


func test_q5b_helm_spoke_clicks_rigging_creaks_and_shore_soundscape() -> void:
	_begin()
	Sea.amp_scale = 0.0
	Weather.set_weather(0.0, 8.0, 0.0)
	Weather.time_of_day = 11.5

	var sloop := _spawn_sloop(Vector3.ZERO)
	sloop.start_anchored = true
	await physics_frames(4)
	sloop.freeze = true
	sloop.rotation = Vector3.ZERO
	sloop.linear_velocity = Vector3.ZERO
	sloop.angular_velocity = Vector3.ZERO

	# 1. Wooden helm spoke detent clicks: turning a Sloop helm 0.0 -> 1.0 (1.0 wheel turn x 8 spokes)
	#    cleanly increments ship.helm_spoke_clicks (>= 6).
	check_eq(sloop.helm_spoke_clicks, 0, "Sloop starts with 0 helm_spoke_clicks")
	sloop.set_helm_target(1.0)
	await physics_frames(130)
	check(sloop.helm >= 0.99, "Sloop helm reaches hard-over 1.0 (got %.2f)" % sloop.helm)
	check(sloop.helm_spoke_clicks >= 6,
		"Turning Sloop helm 0.0 -> 1.0 increments helm_spoke_clicks >= 6 (got %d)" % sloop.helm_spoke_clicks)
	var clicks_at_lock := sloop.helm_spoke_clicks
	await physics_frames(20)
	check_eq(sloop.helm_spoke_clicks, clicks_at_lock,
		"Steady helm at hard-over does not spuriously increment helm_spoke_clicks")

	# 2. Sail-hoist & yardarm-brace pulley creaks: actively hoisting/trimming increments rigging_creak_count
	#    (>= 1) while strict 0.55 s rate-limiting prevents per-tick audio spam!
	check_eq(sloop.rigging_creak_count, 0, "Sloop starts with 0 rigging_creak_count")
	sloop.set_sail_target(1.0)
	await physics_frames(120)
	var hoist_creaks := sloop.rigging_creak_count
	check(hoist_creaks >= 1 and hoist_creaks <= 5,
		"Full Sloop sail hoist triggers rate-limited pulley creaks in 1..5 (got %d)" % hoist_creaks)
	sloop.set_trim_target(1.1)
	await physics_frames(80)
	check(sloop.rigging_creak_count > hoist_creaks and sloop.rigging_creak_count <= hoist_creaks + 4,
		"Bracing yardarm triggers additional rate-limited pulley creaks (total=%d)" % sloop.rigging_creak_count)
	var settled_creaks := sloop.rigging_creak_count
	await physics_frames(45)
	check_eq(sloop.rigging_creak_count, settled_creaks,
		"Settled sails emit zero extra rigging pulley creaks")

	# 3. Living tropical island shore ambiance on SeaSoundscape!
	var soundscape := SeaSoundscape.new()
	soundscape.set_physics_process(false)
	_root.add_child(soundscape)
	soundscape.bind_ship(sloop)

	var isl := Island.new()
	isl.island_id = "q5b_test_cay"
	isl.display_name = "Test Cay"
	isl.island_radius = 65.0
	_root.add_child(isl)
	isl.global_position = Vector3(200.0, 0.0, 0.0)
	check(isl.is_in_group(&"islands"), "Island joins &'islands' group cleanly")

	# Place ship well within island_radius + 35.0 m (= 100.0 m) -> near_island_factor rises to 1.0
	# and triggers rate-limited daytime coastal bird ambiance!
	sloop.global_position = Vector3(120.0, 0.0, 0.0)  # 80 m from island center <= 100 m
	sloop.sail_set = 0.0
	sloop.sail_target = 0.0
	Weather.time_of_day = 12.0
	Weather.set_weather(0.0, 6.0, 0.0)
	soundscape.step(0.1)
	check_near(soundscape.near_island_factor, 1.0, 0.01,
		"SeaSoundscape.near_island_factor rises to 1.0 within island_radius + 35 m (got %.2f)" % soundscape.near_island_factor)
	check_eq(int(soundscape.get_event_counts().get(SeaSoundscape.SFX_SHORE_BIRD, 0)), 1,
		"Daytime calm shore proximity triggers coastal bird call once")
	# Rate limit (7..14 s) prevents rapid spam over 5 s.
	for _i in 5:
		soundscape.step(1.0)
	check_eq(int(soundscape.get_event_counts().get(SeaSoundscape.SFX_SHORE_BIRD, 0)), 1,
		"Coastal bird call 7..14 s cooldown prevents spam")
	# Nighttime (23:00) & stormy weather (0.75) suppress daytime coastal birds cleanly!
	Weather.time_of_day = 23.0
	soundscape.step(15.0)
	check_eq(int(soundscape.get_event_counts().get(SeaSoundscape.SFX_SHORE_BIRD, 0)), 1,
		"Nighttime suppresses daytime coastal bird ambiance")
	Weather.time_of_day = 12.0
	Weather.set_weather(0.75, 18.0, 0.0)
	soundscape.step(15.0)
	check_eq(int(soundscape.get_event_counts().get(SeaSoundscape.SFX_SHORE_BIRD, 0)), 1,
		"Stormy weather suppresses calm coastal bird ambiance")
	# Returning to calm daytime after cooldown re-triggers cleanly!
	Weather.set_weather(0.0, 6.0, 0.0)
	soundscape.step(0.1)
	check_eq(int(soundscape.get_event_counts().get(SeaSoundscape.SFX_SHORE_BIRD, 0)), 2,
		"Calm daytime re-triggers coastal bird call after cooldown")

	# Move ship out into open ocean (far past island_radius + 150 m) -> near_island_factor drops to 0.0!
	sloop.global_position = Vector3(-900.0, 0.0, 0.0)
	soundscape.step(0.1)
	check_near(soundscape.near_island_factor, 0.0, 0.001,
		"SeaSoundscape.near_island_factor drops cleanly to 0.0 in open ocean (got %.3f)" % soundscape.near_island_factor)

	# 4. Zero-leak teardown!
	soundscape.queue_free()
	await _end()
	check(not is_instance_valid(soundscape), "SeaSoundscape frees cleanly with zero leaks")
	check_eq(Ship._active_ship_count, 0, "Ship._active_ship_count returns to 0 after Q5B teardown")

