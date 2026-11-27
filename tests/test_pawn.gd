extends TestCase
## Pawn tests. The moving-deck tests run the simulation faster than real time
## (more physics ticks per second with the same 1/60 s step).

const PAWN := preload("res://src/characters/pawn.tscn")
const SPEEDUP := 8

var _root: Node3D

func _fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEEDUP if on else 1)
	Engine.time_scale = float(SPEEDUP) if on else 1.0
	Engine.max_physics_steps_per_frame = 8 * (SPEEDUP if on else 1)

func _begin() -> void:
	_fast(true)
	_root = Node3D.new()
	add_child(_root)

func _end() -> void:
	_tracks.clear()
	_root.queue_free()
	_root = null
	await physics_frames(2)
	_fast(false)

func _storm_deck(at: Vector3 = Vector3.ZERO) -> MockDeck:
	var d := MockDeck.new()
	d.build_visuals = false
	d.speed = 10.0
	d.yaw_rate = 0.2
	d.roll_deg = 20.0
	d.roll_period = 6.0
	d.pitch_deg = 6.0
	d.pitch_period = 4.3
	d.heave = 0.8
	d.heave_period = 5.0
	d.position = at
	_root.add_child(d)
	return d

func _calm_deck(at: Vector3 = Vector3.ZERO) -> MockDeck:
	var d := MockDeck.new()
	d.build_visuals = false
	d.position = at
	_root.add_child(d)
	return d

func _pawn_on(deck: MockDeck, local: Vector3) -> Pawn:
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.board(deck, local + Vector3(0, 0.02, 0))
	return p

func _bot(p: Pawn) -> BotController:
	var b := BotController.new()
	p.add_child(b)
	return b

func _ground(at: Vector3, size: Vector3 = Vector3(20, 1, 20)) -> StaticBody3D:
	var g := StaticBody3D.new()
	g.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	g.add_child(cs)
	_root.add_child(g)
	g.global_position = at - Vector3(0, size.y * 0.5, 0)
	return g

## Deck-local position of the pawn's standing point (bottom sphere centre),
## expressed at foot level so y reads as deck height.
## Only valid at the END of a physics tick (inside a TickProbe): between
## ticks the deck has already moved on and the pawn has not been carried yet.
func _local_now(deck: MockDeck, p: Pawn) -> Vector3:
	return deck.global_transform.affine_inverse() * (p.global_position + Vector3.UP * p.radius) - Vector3(0, p.radius, 0)

var _tracks := {}

## Latest end-of-tick deck-local position of a pawn, sampled by a probe.
func _local(deck: MockDeck, p: Pawn) -> Vector3:
	if not _tracks.has(p):
		var box := {"l": _local_now(deck, p)}
		_tracks[p] = box
		_root.add_child(TickProbe.new(func(_d):
			if is_instance_valid(p) and is_instance_valid(deck):
				box.l = _local_now(deck, p)))
	return _tracks[p].l

# ------------------------------------------------------------------ riding

func test_engine_step_is_fixed() -> void:
	_begin()
	var deltas := []
	var probe := TickProbe.new(func(d): deltas.append(d))
	_root.add_child(probe)
	await physics_frames(10)
	check(deltas.size() >= 9, "probe ticks")
	for d in deltas:
		check_near(d, 1.0 / 60.0, 0.0001, "physics step must stay 1/60 when sped up")
	await _end()

func test_idle_pawn_rides_storm_deck() -> void:
	_begin()
	var deck := _storm_deck()
	var spots := [Vector3(1.4, 1.1, -4.5), Vector3(-1.2, 2.0, 5.2), Vector3(1.5, -0.6, -1.5)]
	var pawns: Array[Pawn] = []
	for s in spots:
		pawns.append(_pawn_on(deck, s))
	# A fourth pawn with the idle anchor lock off shows what the raw solver does.
	var raw := _pawn_on(deck, Vector3(-1.4, 1.1, -5.0))
	raw.idle_anchor_lock = false
	var raw_stats := {"ref": Vector3.INF, "drift": 0.0}
	_root.add_child(TickProbe.new(func(_d):
		var l := _local_now(deck, raw)
		if raw_stats.ref == Vector3.INF:
			raw_stats.ref = l
		raw_stats.drift = maxf(raw_stats.drift, l.distance_to(raw_stats.ref))))
	await physics_frames(40)
	var ref: Array[Vector3] = []
	var last: Array[Vector3] = []
	for p in pawns:
		check(p.platform == deck, "pawn should ride the deck")
	var stats := {"drift": 0.0, "jitter": 0.0, "off_floor": 0, "ticks": 0, "yaw0": pawns[0].look_yaw, "speed": 0.0}
	var probe := TickProbe.new(func(_d):
		stats.ticks += 1
		stats.speed = maxf(stats.speed, deck.linear_velocity.length())
		for i in pawns.size():
			var l := _local_now(deck, pawns[i])
			if ref.size() <= i:
				ref.append(l)
				last.append(l)
			stats.drift = maxf(stats.drift, l.distance_to(ref[i]))
			stats.jitter = maxf(stats.jitter, l.distance_to(last[i]))
			last[i] = l
			if not pawns[i].is_on_floor() or pawns[i].platform != deck:
				stats.off_floor += 1
	)
	_root.add_child(probe)
	var heading0 := deck.heading
	await physics_frames(1200)
	probe.queue_free()
	print("    idle on storm deck, 20 s: max drift %.2f mm, max tick-to-tick jitter %.3f mm, off-floor ticks %d, deck speed up to %.1f m/s (%d ticks)" % [stats.drift * 1000.0, stats.jitter * 1000.0, stats.off_floor, stats.speed, stats.ticks])
	print("    same, with the idle anchor lock off (raw solver): max drift %.2f mm" % (raw_stats.drift * 1000.0))
	check(raw_stats.drift < 0.05, "raw solver drift %.4f m" % raw_stats.drift)
	check(stats.ticks >= 1150, "ran 20 s")
	check(stats.drift < 0.05, "idle drift %.4f m must stay under 5 cm" % stats.drift)
	check(stats.jitter < 0.01, "tick-to-tick jitter %.4f m" % stats.jitter)
	check_eq(stats.off_floor, 0, "pawns must stay on the deck floor")
	check(stats.speed > 9.0, "deck really moves")
	for i in pawns.size():
		check_near(last[i].y, spots[i].y, 0.03, "pawn %d did not sink through or float" % i)
	# The view yaws with the ship.
	var turned := wrapf(pawns[0].look_yaw - stats.yaw0, -PI, PI)
	check_near(turned, wrapf(deck.heading - heading0, -PI, PI), 0.08, "look_yaw follows ship yaw")
	await _end()

func test_walk_across_storm_deck() -> void:
	_begin()
	var deck := _storm_deck()
	var p := _pawn_on(deck, Vector3(1.4, 1.1, 0.8))
	var bot := _bot(p)
	_local(deck, p)
	await physics_frames(30)
	var start := _local(deck, p)
	bot.run([{move = Vector3(0, 0, -1), time = 1.5, frame = deck}, {wait = 0.5}])
	while not bot.done:
		await get_tree().physics_frame
	var l := _local(deck, p)
	var expected_z := start.z - (p.walk_speed * 1.5 - p.walk_speed * p.walk_speed / (2.0 * p.ground_accel))
	print("    walk 1.5 s forward on storm deck: local z %.2f (expected %.2f), x %.2f (expected %.2f)" % [l.z, expected_z, l.x, start.x])
	check_near(l.z, expected_z, 0.4, "forward distance along the deck")
	check_near(l.x, start.x, 0.3, "no sideways slide")
	check_near(l.y, 1.1, 0.03, "still on deck")
	check(p.platform == deck)
	await _end()

func test_jump_lands_on_same_spot() -> void:
	_begin()
	var deck := _storm_deck()
	var p := _pawn_on(deck, Vector3(-1.4, 1.1, -4.0))
	var bot := _bot(p)
	_local(deck, p)
	await physics_frames(60)
	var worst := 0.0
	var peak := {"y": 0.0}
	var probe := TickProbe.new(func(_d): peak.y = maxf(peak.y, _local_now(deck, p).y))
	_root.add_child(probe)
	for i in 4:
		var start := _local(deck, p)
		bot.run([{jump = true}, {wait = 1.3}])
		while not bot.done:
			await get_tree().physics_frame
		var l := _local(deck, p)
		worst = maxf(worst, Vector2(l.x - start.x, l.z - start.z).length())
		check(p.is_on_floor() and p.platform == deck, "landed on the deck")
		check_near(l.y, 1.1, 0.03)
	print("    4 jumps on storm deck: worst landing offset %.1f mm, peak height %.2f m above deck" % [worst * 1000.0, peak.y - 1.1])
	check(worst < 0.1, "jump landing offset %.3f m" % worst)
	check(peak.y - 1.1 > 0.8, "jump height")
	await _end()

func test_stairs_ramp_and_hold() -> void:
	_begin()
	var deck := _storm_deck()
	deck.roll_deg = 12.0
	var p := _pawn_on(deck, Vector3(-1.6, 1.1, 0.6))
	var bot := _bot(p)
	_local(deck, p)
	await physics_frames(20)
	# Up the stairs (4 steps of 0.225 m) to the quarterdeck.
	bot.run([{goto = Vector3(-1.6, 0, 4.6), frame = deck, timeout = 5.0}, {wait = 0.3}])
	while not bot.done:
		await get_tree().physics_frame
	var l := _local(deck, p)
	check_near(l.y, 2.0, 0.05, "climbed the stairs to the quarterdeck (z %.2f)" % l.z)
	check(l.z > 4.0, "reached the quarterdeck")
	# Across and down the ramp, back to the main deck.
	bot.run([{goto = Vector3(1.6, 0, 4.6), frame = deck}, {goto = Vector3(1.6, 0, 0.6), frame = deck}, {wait = 0.3}])
	while not bot.done:
		await get_tree().physics_frame
	l = _local(deck, p)
	check_near(l.y, 1.1, 0.05, "came down the ramp")
	check(p.platform == deck)
	# Down the companion ramp into the hold and forward under the low deck.
	bot.run([{goto = Vector3(0, 0, 0.2), frame = deck}, {goto = Vector3(0, 0, -3.1), frame = deck},
		{goto = Vector3(1.4, 0, -4.8), frame = deck, timeout = 5.0}, {wait = 0.3}])
	while not bot.done:
		await get_tree().physics_frame
	l = _local(deck, p)
	print("    hold: local %s crouched %s mode %d" % [l, p.crouched, p.mode])
	check_near(l.y, -0.6, 0.06, "standing on the hold floor")
	check(l.distance_to(Vector3(1.4, -0.6, -4.8)) < 0.5, "walked under the deck")
	check(p.crouched, "ducks under the 1.6 m hold ceiling")
	check(p.mode == Pawn.Mode.WALK, "dry in the hold although below the waterline")
	check(p.platform == deck)
	# And back up into daylight.
	bot.run([{goto = Vector3(0, 0, -3.0), frame = deck}, {goto = Vector3(0, 0, 0.6), frame = deck, timeout = 6.0}, {wait = 0.5}])
	while not bot.done:
		await get_tree().physics_frame
	l = _local(deck, p)
	check_near(l.y, 1.1, 0.05, "back on deck")
	check(not p.crouched, "stands up again")
	await _end()

# ---------------------------------------------------------------- water

func test_floats_in_open_water() -> void:
	_begin()
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.global_position = Vector3(300, Sea.height(300, 300) + 1.0, 300)
	var bot := _bot(p)
	await physics_frames(180)
	check(p.mode == Pawn.Mode.SWIM, "swimming after falling in")
	var stats := {"worst": 0.0, "not_swim": 0}
	var probe := TickProbe.new(func(_d):
		stats.worst = maxf(stats.worst, absf(Sea.depth(p.global_position) - p.swim_float_depth))
		if p.mode != Pawn.Mode.SWIM:
			stats.not_swim += 1
	)
	_root.add_child(probe)
	await physics_frames(480)
	print("    floating 8 s: worst deviation from float depth %.1f cm" % (stats.worst * 100.0))
	check(stats.worst < 0.2, "stays at the surface (%.3f)" % stats.worst)
	check_eq(stats.not_swim, 0)
	# Swim, then dive a little, then come back up.
	var x0 := p.global_position
	bot.run([{move = Vector3(1, 0, 0), time = 2.0}])
	while not bot.done:
		await get_tree().physics_frame
	check(p.global_position.x - x0.x > 3.0, "swims forward")
	bot.run([{look = -PI * 0.5, pitch = -1.0, move = Vector3(1, 0, 0), time = 1.5}])
	while not bot.done:
		await get_tree().physics_frame
	var dive := Sea.depth(p.global_position)
	check(dive > p.swim_float_depth + 0.8, "dives when swimming forward looking down (depth %.2f)" % dive)
	bot.run([{look = -PI * 0.5, pitch = 0.0}, {wait = 3.0}])
	while not bot.done:
		await get_tree().physics_frame
	check_near(Sea.depth(p.global_position), p.swim_float_depth, 0.25, "resurfaces")
	await _end()

func test_overboard_swim_and_ladder() -> void:
	_begin()
	var deck := _calm_deck(Vector3(-300, 0, 200))
	deck.roll_deg = 8.0
	deck.heave = 0.3
	var p := _pawn_on(deck, Vector3(0.9, 1.1, -5.0))
	var bot := _bot(p)
	_local(deck, p)
	await physics_frames(20)
	# Run at the starboard rail and vault it.
	bot.run([{move = Vector3(1, 0, 0), time = 0.12, frame = deck, sprint = true},
		{move = Vector3(1, 0, 0), time = 0.9, frame = deck, sprint = true, jump = true}, {wait = 2.0}])
	while not bot.done:
		await get_tree().physics_frame
	check(p.mode == Pawn.Mode.SWIM, "overboard and swimming (mode %d, local %s)" % [p.mode, _local(deck, p)])
	check(p.platform == null, "left the ship's frame")
	check(_local(deck, p).x > 2.4, "is outside the hull")
	# Swim to the ladder and climb it.
	bot.run([{goto = Vector3(3.4, 0, 0.0), frame = deck, timeout = 12.0},
		{goto = Vector3(1.0, 0, 0.0), frame = deck, timeout = 6.0}, {wait = 0.5}])
	var was_on_ladder := false
	while not bot.done:
		await get_tree().physics_frame
		if p.mode == Pawn.Mode.LADDER:
			was_on_ladder = true
	var l := _local(deck, p)
	print("    after ladder: local %s mode %d" % [l, p.mode])
	check(was_on_ladder, "used the ladder")
	check(p.mode == Pawn.Mode.WALK and p.platform == deck, "back aboard")
	check_near(l.y, 1.1, 0.05, "on the main deck")
	check(absf(l.x) < 2.1, "inside the rails")
	await _end()

# --------------------------------------------------------------- gameplay

func test_damage_and_death() -> void:
	_begin()
	_ground(Vector3(0, 60, 0))
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.global_position = Vector3(0, 60.05, 0)
	var deaths := [0]
	var hits := [0.0]
	p.died.connect(func(): deaths[0] += 1)
	p.damaged.connect(func(a, _f): hits[0] += a)
	await physics_frames(10)
	check_near(p.health, 100.0)
	p.apply_damage(30.0, null)
	check_near(p.health, 70.0)
	check_eq(deaths[0], 0)
	check(not p.dead)
	p.apply_damage(500.0, self)
	check_near(p.health, 0.0)
	check(p.dead)
	check_eq(deaths[0], 1)
	p.apply_damage(10.0, null)
	check_eq(deaths[0], 1, "dies once")
	check_near(hits[0], 530.0)
	# A dead pawn ignores intent.
	var before := p.global_position
	p.wish_dir = Vector3(1, 0, 0)
	await physics_frames(30)
	check(p.global_position.distance_to(before) < 0.05, "dead pawns do not walk")
	p.revive(Vector3(1, 60.05, 0))
	check(not p.dead)
	check_near(p.health, 100.0)
	await _end()

func test_station_occupy_drive_release() -> void:
	_begin()
	var deck := _storm_deck(Vector3(400, 0, -400))
	var st := MockStation.new()
	deck.add_child(st)
	st.position = Vector3(1.2, 1.1, -3.0)
	var p := _pawn_on(deck, Vector3(1.2, 1.1, -1.8))
	await physics_frames(20)
	p.focus = st.interactable
	p.interact()
	check(st.occupant == p, "station occupied")
	check(p.station == st, "pawn knows its station")
	check(p.mode == Pawn.Mode.STATION)
	var worst := {"d": 0.0, "n": 0}
	var probe := TickProbe.new(func(d):
		p.drive_station(Vector2(1, 0), true, false, d)
		worst.n += 1
		if worst.n > 30:
			worst.d = maxf(worst.d, p.global_position.distance_to(Pawn.station_stand_transform(st).origin))
	)
	_root.add_child(probe)
	p.wish_dir = Vector3(1, 0, 0)
	await physics_frames(120)
	probe.queue_free()
	print("    at station on storm deck: worst offset from stand point %.2f mm" % (worst.d * 1000.0))
	check(st.drive_calls >= 100, "drive called each tick")
	check(st.value > 0.9, "axis reached the station")
	check(st.primary_ticks >= 100)
	check_eq(st.secondary_ticks, 0)
	check(worst.d < 0.02, "held at the stand point (%.4f)" % worst.d)
	# A second pawn cannot take an occupied station.
	var q := _pawn_on(deck, Vector3(0.9, 1.1, -4.5))
	q.focus = st.interactable
	q.interact()
	check(q.station == null and st.occupant == p, "occupied station refuses others")
	p.leave_station()
	check(st.occupant == null, "released")
	check(p.station == null)
	check(p.mode == Pawn.Mode.WALK)
	p.wish_dir = Vector3.ZERO
	await physics_frames(20)
	check(p.is_on_floor() and p.platform == deck, "standing on deck after leaving")
	await _end()

class Barrel extends Node3D:
	var items: Array = []
	var handle: Interactable
	func _ready() -> void:
		handle = Interactable.create("Store", 0.5)
		add_child(handle)
	func accept_carryable(item: Node) -> bool:
		items.append(item)
		return true

func _crate(at: Vector3) -> Carryable:
	var c := Carryable.new()
	c.mass = 12.0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.5, 0.5, 0.5)
	cs.shape = bx
	c.add_child(cs)
	_root.add_child(c)
	c.global_position = at
	return c

func test_carry_pick_up_and_drop() -> void:
	_begin()
	_ground(Vector3(0, 80, 0))
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.global_position = Vector3(0, 80.05, 0)
	var crate := _crate(Vector3(0, 80.3, -1.2))
	await physics_frames(40)
	check(not crate.freeze)
	p.focus = crate.interactable
	p.interact()
	check(p.carried == crate, "picked up")
	check(crate.holder == p and crate.freeze, "crate is held")
	p.wish_dir = Vector3(1, 0, 0)
	p.wish_sprint = true
	p.look_yaw = -PI * 0.5
	await physics_frames(60)
	var hold: Vector3 = p.global_position + Basis(Vector3.UP, p.look_yaw) * crate.hold_offset
	check(crate.global_position.distance_to(hold) < 0.02, "carried in front of the body")
	check(p.velocity.length() < p.sprint_speed * 0.8, "hauling slows the sprint (%.2f)" % p.velocity.length())
	check(p.velocity.length() > p.walk_speed, "but sprint still beats walking")
	p.wish_dir = Vector3.ZERO
	p.wish_sprint = false
	await physics_frames(20)
	p.interact()
	check(p.carried == null, "dropped with interact")
	check(crate.holder == null and not crate.freeze)
	await physics_frames(120)
	check_near(crate.global_position.y, 80.25, 0.05, "crate rests on the ground")
	check(crate.global_position.distance_to(p.global_position) < 2.5)
	# Hand over to a container.
	var barrel := Barrel.new()
	_root.add_child(barrel)
	barrel.global_position = p.global_position + Vector3(1.2, 1.0, 0)
	p.pick_up(crate)
	check(p.carried == crate)
	p.focus = barrel.handle
	p.interact()
	check(p.carried == null, "handed over")
	check(barrel.items.has(crate) and crate.stored_in == barrel, "container received the crate")
	await _end()

func test_carryable_floats() -> void:
	_begin()
	var crate := _crate(Vector3(-200, Sea.height(-200, 100) + 1.5, 100))
	await physics_frames(600)
	var d := Sea.depth(crate.global_position)
	print("    crate after 10 s in the sea: depth of centre %.2f m" % d)
	check(absf(d) < 0.4, "floats at the surface")
	await _end()

# ------------------------------------------------------- player controller

func test_player_controller_focus_station_and_carry() -> void:
	_begin()
	_ground(Vector3(0, 90, 0))
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.global_position = Vector3(0, 90.05, 0)
	var pc := PlayerController.new()
	pc.capture_mouse = false
	pc.make_current = false
	p.add_child(pc)
	var st := MockStation.new()
	_root.add_child(st)
	st.global_position = Vector3(0, 90, -1.6)
	p.look_pitch = -0.3
	await physics_frames(10)
	check(pc.camera != null and pc.camera.get_parent() == pc, "camera exists")
	check_near(pc.camera.global_position.y - p.global_position.y, p.eye_height, 0.05, "camera at eye height")
	check(p.focus == st.interactable, "looks at the station handle")
	check_eq(pc.focus_prompt, st.prompt)
	# Mouse look.
	pc.add_look(Vector2(-100, 0))
	check(p.look_yaw > 0.1, "mouse left turns left")
	pc.add_look(Vector2(100, 0))
	# Walk input reaches the pawn.
	Input.action_press(&"move_right")
	await physics_frames(20)
	Input.action_release(&"move_right")
	check(p.global_position.x > 0.3, "move_right walks right (x %.2f)" % p.global_position.x)
	Input.action_press(&"move_left")
	await physics_frames(20)
	Input.action_release(&"move_left")
	await physics_frames(10)
	check(p.focus == st.interactable, "station in view again")
	# Occupy, drive, leave.
	Input.action_press(&"interact")
	await physics_frames(3)
	Input.action_release(&"interact")
	check(p.station == st and st.occupant == p, "interact occupies the station")
	Input.action_press(&"move_right")
	Input.action_press(&"primary")
	var x_before := p.global_position.x
	await physics_frames(30)
	Input.action_release(&"move_right")
	Input.action_release(&"primary")
	check(st.last_axis.x > 0.9 or st.value > 0.3, "movement input drives the station")
	check(st.primary_ticks > 20, "primary forwarded")
	check_near(p.global_position.x, Pawn.station_stand_transform(st).origin.x, 0.05, "does not walk while crewing")
	check(absf(p.global_position.x - x_before) < 0.3)
	var yaw := p.look_yaw
	pc.add_look(Vector2(-200, 50))
	check(absf(p.look_yaw - yaw) > 0.2, "can still look around at the station")
	pc.add_look(Vector2(200, -50))
	Input.action_press(&"leave_station")
	await physics_frames(3)
	Input.action_release(&"leave_station")
	check(p.station == null and st.occupant == null, "leave_station releases")
	# Carry: pick up with interact, drop with secondary.
	st.queue_free()
	var crate := _crate(p.global_position + Vector3(0, 0.3, -1.3))
	p.look_yaw = 0.0
	p.look_pitch = -0.5
	await physics_frames(40)
	check(p.focus == crate.interactable, "crate focused")
	Input.action_press(&"interact")
	await physics_frames(3)
	Input.action_release(&"interact")
	check(p.carried == crate, "picked up through the controller")
	check_eq(pc.focus_prompt, "Drop")
	Input.action_press(&"secondary")
	await physics_frames(3)
	Input.action_release(&"secondary")
	check(p.carried == null, "secondary drops")
	await _end()

func test_player_controller_camera_trauma_and_accessibility_gate() -> void:
	_begin()
	_fast(false)
	_ground(Vector3(0, 100, 0))
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.global_position = Vector3(0, 100.05, 0)
	var pc := PlayerController.new()
	pc.capture_mouse = false
	pc.make_current = false
	pc.input_enabled = false
	p.add_child(pc)
	await physics_frames(10)
	pc._update_camera(0.0)

	var rest_xf := pc.camera.transform
	check_near(pc.get_camera_trauma(), 0.0, 0.0001, "camera trauma starts at 0.0")

	# Adding trauma applies a crisp bounded micro-impulse and decays smoothly to 0 over ~0.6 s.
	pc.add_camera_trauma(0.75)
	check(pc.get_camera_trauma() > 0.7, "add_camera_trauma(0.75) sets trauma > 0.7 (got %.3f)" % pc.get_camera_trauma())
	pc._update_camera(1.0 / 60.0)
	var shaken_xf := pc.camera.transform
	var pos_delta := shaken_xf.origin.distance_to(rest_xf.origin)
	var rot_delta := (shaken_xf.basis.z - rest_xf.basis.z).length() + (shaken_xf.basis.x - rest_xf.basis.x).length()
	check(pos_delta > 0.0005 and pos_delta < 0.08, "camera trauma applies bounded position shake (%.4f m)" % pos_delta)
	check(rot_delta > 0.0005 and rot_delta < 0.12, "camera trauma applies bounded pitch/roll shake (%.4f)" % rot_delta)

	var prev_trauma := pc.get_camera_trauma()
	for _i in 36:
		pc._update_camera(1.0 / 60.0)
		var cur_trauma := pc.get_camera_trauma()
		check(cur_trauma <= prev_trauma + 0.0001, "camera trauma decays monotonically")
		prev_trauma = cur_trauma
	check_near(pc.get_camera_trauma(), 0.0, 0.0001, "camera trauma decays cleanly to 0.0 over ~0.6 s")
	check(pc.camera.transform.origin.distance_to(rest_xf.origin) < 0.0001, "camera position returns cleanly to rest")
	check(pc.camera.transform.basis.is_equal_approx(rest_xf.basis), "camera basis returns cleanly to rest")

	# Accessibility gate: disabling head-bob (bob_amount = 0.0) makes add_camera_trauma a complete no-op.
	pc.bob_amount = 0.0
	pc.add_camera_trauma(0.9)
	check_near(pc.get_camera_trauma(), 0.0, 0.0001, "bob_amount = 0.0 suppresses add_camera_trauma completely")
	pc._update_camera(1.0 / 60.0)
	check(pc.camera.transform.origin.distance_to(rest_xf.origin) < 0.0001, "camera stays still when accessibility motion is off")
	check(pc.camera.transform.basis.is_equal_approx(rest_xf.basis), "camera orientation stays still when accessibility motion is off")

	# Diegetic Voyage Title Card: shows, eases in/holds/fades out cleanly, and auto-hides on overlays.
	var hud := GameHUD.new()
	hud.input_enabled = false
	_root.add_child(hud)
	hud.bind(p, pc)
	await get_tree().process_frame
	hud.set_process(false)

	check(not hud.is_voyage_title_visible(), "voyage title card starts hidden")
	hud.show_voyage_title("SEA OF SCOUNDRELS", "Chapter I -- The Salt-King's Ledger", 0.4)
	check(hud.is_voyage_title_visible(), "show_voyage_title shows card immediately")
	var card := hud.find_child("VoyageTitleCard", true, false) as PanelContainer
	check(card != null and card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "voyage title card is non-blocking")

	# Ease-in (0.45 s), hold (0.40 s), ease-out (0.90 s).
	hud._process(0.225)
	check(hud.is_voyage_title_visible() and card.modulate.a > 0.35 and card.modulate.a < 0.75,
		"voyage title eases in smoothly (alpha=%.2f)" % card.modulate.a)
	hud._process(0.30)
	check(hud.is_voyage_title_visible() and card.modulate.a >= 0.99,
		"voyage title holds at full alpha (alpha=%.2f)" % card.modulate.a)
	hud._process(0.775)
	check(hud.is_voyage_title_visible() and card.modulate.a > 0.1 and card.modulate.a < 0.85,
		"voyage title eases out smoothly (alpha=%.2f)" % card.modulate.a)
	hud._process(0.55)
	check(not hud.is_voyage_title_visible() and not card.visible, "voyage title hides cleanly after fade-out")

	# Opening pause, item radial, or crew command wheel immediately hides active voyage title card.
	hud.show_voyage_title("PORT SCOUNDREL", "Morning Watch", 4.0)
	check(hud.is_voyage_title_visible(), "voyage title shows again cleanly")
	hud.set_pause_open(true)
	check(not hud.is_voyage_title_visible(), "opening pause overlay dismisses voyage title card")
	var log_panel := hud.find_child("CaptainLogPanel", true, false) as PanelContainer
	var ctrl_strip := hud.find_child("CaptainControlsStrip", true, false) as VBoxContainer
	check(log_panel != null and ctrl_strip != null and ctrl_strip.get_child_count() == 2,
		"pause overlay includes 2-line Captain's Controls strip")
	if log_panel != null:
		var min_sz := log_panel.get_combined_minimum_size()
		check(min_sz.x <= 1200.0 and min_sz.y <= 680.0,
			"pause overlay fits comfortably inside 1280x720 (min_size=%s)" % str(min_sz))
	hud.set_pause_open(false)

	hud.show_voyage_title("CUTLASS CAY", "Buried Hoard", 4.0)
	hud.open_item_radial()
	check(not hud.is_voyage_title_visible(), "opening item radial dismisses voyage title card")
	hud.close_item_radial(false)

	hud.show_voyage_title("IRONWATCH FORT", "Sea Bastion", 4.0)
	hud.open_command_wheel()
	check(not hud.is_voyage_title_visible(), "opening crew command wheel dismisses voyage title card")
	hud.close_command_wheel(false)
	await _end()

func test_ship_cannon_recoil_trauma_and_hull_impact_signal() -> void:
	_begin()
	_fast(false)
	Net.start_single_player()
	var sloop_scene: PackedScene = load("res://src/ship/sloop.tscn")
	var ship := sloop_scene.instantiate() as Ship
	ship.enable_effects = false
	_root.add_child(ship)
	await physics_frames(4)

	var hs_v: Variant = ship.get(&"hull_scale")
	var hs := float(hs_v) if (hs_v != null and float(hs_v) > 0.01) else 1.0
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.board(ship, Vector3(-1.5, 1.12, -1.5) * hs)
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	pc.capture_mouse = false
	pc.make_current = false
	pc.input_enabled = false
	p.add_child(pc)
	await physics_frames(2)

	# Firing a ship cannon triggers subtle recoil trauma on the firing player's PlayerController.
	var ball := ship.fire_cannon(&"port", p)
	check(ball != null, "cannon fires cleanly with shooter pawn")
	check(pc.get_camera_trauma() >= 0.30 and pc.get_camera_trauma() <= 0.42,
		"cannon fire adds subtle 0.36 recoil trauma (got %.3f)" % pc.get_camera_trauma())
	if ball != null and is_instance_valid(ball):
		ball.queue_free()

	# Hull damage emits hull_impacted(world_pos, intensity) cleanly.
	var impacts: Array[Dictionary] = []
	ship.hull_impacted.connect(func(wpos: Vector3, intensity: float) -> void:
		impacts.append({"pos": wpos, "intensity": intensity})
	)
	var hit_pos := ship.global_transform * (Vector3(2.0, -0.35, 0.2) * hs)
	var slot := ship.apply_hull_damage(hit_pos, 0.5)
	check(slot >= 0, "apply_hull_damage opens breach slot")
	check_eq(impacts.size(), 1, "hull_impacted emitted once on hull breach")
	if not impacts.is_empty():
		check((impacts[0]["pos"] as Vector3).distance_to(hit_pos) < 0.01, "hull_impacted reports world impact pos")
		check_near(float(impacts[0]["intensity"]), 1.0, 0.01, "hull_impacted intensity scales cleanly with radius")
	await _end()


class _Wave26DynamicStation extends MockStation:
	var focus_msg: String = "[F] Drop Anchor"
	var active_msg: String = "[Hold W] Heave | [F] Step Off"
	var quick_use_enabled: bool = false
	var quick_uses: int = 0
	var meta_id: StringName = &"starboard"
	var ship: Node3D = null

	func get_focus_prompt() -> String:
		return focus_msg

	func get_active_prompt() -> String:
		return active_msg

	func try_quick_use(_pawn: Node) -> bool:
		if quick_use_enabled:
			quick_uses += 1
			return true
		return false


class _Wave26MockCannonShip extends Node3D:
	var last_side: StringName = &""
	var total_dyaw: float = 0.0
	var total_dpitch: float = 0.0
	var calls: int = 0

	func aim_cannon_delta(side: StringName, dyaw: float, dpitch: float) -> void:
		last_side = side
		total_dyaw += dyaw
		total_dpitch += dpitch
		calls += 1


func test_f_key_station_toggle_quick_use_dynamic_prompts_and_cannon_mouse_aim() -> void:
	_begin()
	_fast(false)
	Net.start_single_player()
	_ground(Vector3(0, 110, 0))
	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.global_position = Vector3(0, 110.05, 0)
	var pc := PlayerController.new()
	pc.capture_mouse = false
	pc.make_current = false
	p.add_child(pc)

	var st := _Wave26DynamicStation.new()
	_root.add_child(st)
	st.global_position = Vector3(0, 110.0, -1.6)
	p.look_pitch = -0.3
	await physics_frames(8)

	# 1. Dynamic focus prompt comes from Station.get_focus_prompt().
	check(p.focus == st.interactable, "player focuses dynamic station handle")
	check_eq(pc.focus_prompt, "[F] Drop Anchor", "focus_prompt reads Station.get_focus_prompt()")

	# 2. One-tap quick_use runs WITHOUT locking pawn into the station!
	st.quick_use_enabled = true
	Input.action_press(&"interact")
	await physics_frames(2)
	Input.action_release(&"interact")
	await physics_frames(2)
	check_eq(st.quick_uses, 1, "try_quick_use invoked on [F] interact")
	check(p.station == null and st.occupant == null, "quick-use does NOT lock pawn into station")

	# 3. When quick_use returns false, [F] enters station, shows get_active_prompt(), and pressing [F] again exits!
	st.quick_use_enabled = false
	Input.action_press(&"interact")
	await physics_frames(2)
	Input.action_release(&"interact")
	await physics_frames(2)
	check(p.station == st and st.occupant == p, "[F] enters station when try_quick_use returns false")
	check_eq(pc.focus_prompt, "[Hold W] Heave | [F] Step Off", "active focus_prompt reads Station.get_active_prompt()")

	# Pressing [F] (interact) a second time exits the station cleanly!
	Input.action_press(&"interact")
	await physics_frames(2)
	Input.action_release(&"interact")
	await physics_frames(2)
	check(p.station == null and st.occupant == null, "pressing [F] (interact) exits station cleanly")

	# 4. Cannon mouse aim forwards relative look deltas to ship.aim_cannon_delta(side, dyaw, dpitch).
	var mock_ship := _Wave26MockCannonShip.new()
	_root.add_child(mock_ship)
	st.kind = &"cannon"
	st.meta_id = &"port"
	st.ship = mock_ship
	check(p.enter_station(st), "pawn occupies mock cannon station")
	pc.add_look(Vector2(100.0, -50.0))
	check_eq(mock_ship.calls, 1, "add_look forwards cannon mouse aim delta to ship")
	check_eq(mock_ship.last_side, &"port", "aim_cannon_delta receives station meta_id")
	check_near(mock_ship.total_dyaw, -100.0 * 0.0018, 0.0001, "aim_cannon_delta yaw delta matches -relative.x * 0.0018")
	check_near(mock_ship.total_dpitch, 50.0 * 0.0016, 0.0001, "aim_cannon_delta pitch delta matches -relative.y * 0.0016")
	p.leave_station()
	await _end()


func test_q1b_physics_priority_interpolation_and_station_zero_jitter() -> void:
	_begin()
	Net.start_single_player()

	# 1. Native 3D physics interpolation must be enabled in project.godot and active in SceneTree.
	check(bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
		"project.godot must enable physics/common/physics_interpolation=true")
	check(get_tree().physics_interpolation, "SceneTree physics_interpolation must be active")

	# 2. Pawn must tick strictly AFTER Ship / MockDeck (priority 0) and BEFORE TickProbe (1000).
	var deck := _storm_deck(Vector3(600, 0, -600))
	deck.roll_deg = 22.0
	deck.pitch_deg = 10.0
	deck.yaw_rate = 0.35
	deck.speed = 11.0
	deck.heave = 0.9

	var st := MockStation.new()
	deck.add_child(st)
	st.position = Vector3(0.0, 2.0, 5.0)

	var p := _pawn_on(deck, Vector3(-1.0, 2.0, 4.2))
	var pc := PlayerController.new()
	pc.capture_mouse = false
	pc.make_current = false
	pc.input_enabled = false
	p.add_child(pc)

	check(p.process_physics_priority > deck.process_physics_priority,
		"Pawn process_physics_priority (%d) must run after Ship/MockDeck (%d)" % [
			p.process_physics_priority, deck.process_physics_priority
		])
	check(p.process_physics_priority > 0 and p.process_physics_priority < 1000,
		"Pawn process_physics_priority (%d) must sit cleanly between Ship (0) and TickProbe (1000)" % p.process_physics_priority)
	check(pc.process_physics_priority < deck.process_physics_priority,
		"PlayerController (%d) writes intent before Ship (0) and Pawn (%d)" % [
			pc.process_physics_priority, p.process_physics_priority
		])
	check_eq(pc.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"PlayerController uses PHYSICS_INTERPOLATION_MODE_OFF for instant mouse look on interpolated Pawn")

	# 3. Station-locked pawn on a wildly pitching/rolling/turning storm deck must have < 1 mm jitter from tick 1.
	await physics_frames(6)
	check(p.enter_station(st), "pawn occupies storm-deck station cleanly")
	var metrics := {"max_stand_err": 0.0, "max_tick_jitter": 0.0, "prev_local": Vector3.INF, "ticks": 0}
	var probe := TickProbe.new(func(d: float) -> void:
		p.drive_station(Vector2(0.5, 0.0), true, false, d)
		metrics.ticks += 1
		var stand_pos := Pawn.station_stand_transform(st).origin
		metrics.max_stand_err = maxf(metrics.max_stand_err, p.global_position.distance_to(stand_pos))
		var loc := deck.global_transform.affine_inverse() * p.global_position
		if metrics.prev_local != Vector3.INF:
			metrics.max_tick_jitter = maxf(metrics.max_tick_jitter, loc.distance_to(metrics.prev_local))
		metrics.prev_local = loc
	)
	_root.add_child(probe)
	await physics_frames(180)
	probe.queue_free()

	print("    Q1B storm station lock (%d ticks): max stand err %.4f mm, max tick-to-tick local jitter %.4f mm" % [
		metrics.ticks, metrics.max_stand_err * 1000.0, metrics.max_tick_jitter * 1000.0
	])
	check(metrics.ticks >= 170, "sampled full 3 s storm station window")
	check(metrics.max_stand_err < 0.001,
		"station-locked pawn stand error must be < 1 mm (got %.4f mm)" % (metrics.max_stand_err * 1000.0))
	check(metrics.max_tick_jitter < 0.001,
		"station-locked pawn tick-to-tick local jitter must be < 1 mm (got %.4f mm)" % (metrics.max_tick_jitter * 1000.0))

	# 4. Leaving station & snapping via teleport/board cleanly resets interpolation offsets without errors.
	p.leave_station()
	p.visual_offset_y = -0.25
	p.teleport(Vector3(10.0, 50.0, 10.0))
	check_near(p.visual_offset_y, 0.0, 0.0001, "teleport clears visual_offset_y cleanly")
	p.board(deck, Vector3(0.0, 1.12, -2.0))
	check_near(p.visual_offset_y, 0.0, 0.0001, "board clears visual_offset_y cleanly")
	await _end()


func test_q9a_surface_aware_footsteps_wading_landing_ladder_and_swim_audio() -> void:
	_begin()
	var saved_sea_amp := Sea.amp_scale
	Net.start_single_player()

	# 1. Standing completely idle on a rolling storm deck triggers 0 phantom footsteps.
	var deck := _storm_deck(Vector3(750.0, 0.0, -750.0))
	var idle_pawn := _pawn_on(deck, Vector3(1.2, 1.1, -3.5))
	await physics_frames(15)
	idle_pawn.reset_locomotion_sfx_counts()
	await physics_frames(180)
	var idle_counts := idle_pawn.get_locomotion_sfx_counts()
	var idle_total := 0
	for k in idle_counts:
		idle_total += int(idle_counts[k])
	check_eq(idle_total, 0, "idle pawn on rolling storm deck triggers 0 phantom footsteps (got %s)" % str(idle_counts))
	check_eq(idle_pawn.get_last_locomotion_sfx(), &"", "idle pawn has no last locomotion SFX")
	check_eq(idle_pawn.resolve_footstep_surface(), &"wood", "storm deck resolves wood surface")
	# Returned counts dictionary must be a defensive copy.
	idle_counts[&"footstep_wood"] = 99
	check(idle_pawn.get_locomotion_sfx_counts().is_empty(), "get_locomotion_sfx_counts returns a duplicate")
	idle_pawn.queue_free()
	deck.queue_free()
	await physics_frames(2)

	# 2. Walking across a real Sloop's oak deck resolves &"wood" and triggers >= 2 &"footstep_wood".
	Sea.amp_scale = 0.0
	var sloop_scene: PackedScene = load("res://src/ship/sloop.tscn")
	var sloop := sloop_scene.instantiate() as Ship
	sloop.enable_effects = false
	sloop.start_anchored = true
	_root.add_child(sloop)
	sloop.global_position = Vector3(-650.0, 0.0, -650.0)
	await physics_frames(8)

	var p: Pawn = PAWN.instantiate()
	_root.add_child(p)
	p.board(sloop, sloop.ship_point(Vector3(1.25, 1.14, 2.0)))
	await physics_frames(10)
	p.reset_locomotion_sfx_counts()
	check_eq(p.resolve_footstep_surface(), &"wood", "Sloop oak deck resolves wood")
	var fwd_deck := sloop.global_basis * Vector3(0.0, 0.0, -1.0)
	fwd_deck.y = 0.0
	p.wish_dir = fwd_deck.normalized()
	await physics_frames(85)
	p.wish_dir = Vector3.ZERO
	await physics_frames(6)
	var deck_counts := p.get_locomotion_sfx_counts()
	var deck_wood := int(deck_counts.get(&"footstep_wood", 0))
	check(deck_wood >= 2, "walking across Sloop oak deck triggers >= 2 footstep_wood (got %d, %s)" % [deck_wood, str(deck_counts)])
	check_eq(p.get_last_locomotion_sfx(), &"footstep_wood", "last locomotion SFX on oak deck is footstep_wood")

	# 3. Walking in a flooded Sloop hold (water_level = 0.35, below main deck) resolves &"water" & triggers &"footstep_water".
	sloop.water_level = 0.35
	p.board(sloop, sloop.ship_point(Vector3(0.95, -0.82, 2.5)))
	await physics_frames(10)
	p.reset_locomotion_sfx_counts()
	check_eq(p.resolve_footstep_surface(), &"water", "flooded Sloop bilge hold resolves water")
	var fwd_hold := sloop.global_basis * Vector3(0.0, 0.0, -1.0)
	fwd_hold.y = 0.0
	p.wish_dir = fwd_hold.normalized()
	await physics_frames(85)
	p.wish_dir = Vector3.ZERO
	await physics_frames(6)
	var hold_counts := p.get_locomotion_sfx_counts()
	var hold_water := int(hold_counts.get(&"footstep_water", 0))
	check(hold_water >= 2, "walking in flooded Sloop hold triggers >= 2 footstep_water (got %d, %s)" % [hold_water, str(hold_counts)])
	check_eq(p.get_last_locomotion_sfx(), &"footstep_water", "last locomotion SFX in flooded hold is footstep_water")

	# 4. Walking ashore on dry island ground (y > Sea.height + 2.0) resolves &"sand" & triggers &"footstep_sand".
	var island_y := Sea.height(220.0, 220.0) + 12.0
	var island_ground := _ground(Vector3(220.0, island_y, 220.0), Vector3(36.0, 1.0, 36.0))
	island_ground.name = "TerrainBody"
	p.teleport(Vector3(212.0, island_y + 0.06, 220.0))
	await physics_frames(12)
	p.reset_locomotion_sfx_counts()
	check_eq(p.resolve_footstep_surface(), &"sand", "dry island ground resolves sand")
	p.wish_dir = Vector3(1.0, 0.0, 0.0)
	await physics_frames(85)
	p.wish_dir = Vector3.ZERO
	await physics_frames(6)
	var sand_counts := p.get_locomotion_sfx_counts()
	var sand_steps := int(sand_counts.get(&"footstep_sand", 0))
	check(sand_steps >= 2, "walking ashore on dry island triggers >= 2 footstep_sand (got %d, %s)" % [sand_steps, str(sand_counts)])
	check_eq(p.get_last_locomotion_sfx(), &"footstep_sand", "last locomotion SFX on island sand is footstep_sand")

	# 4b. Static wooden pier ashore (no moving platform) resolves &"wood" by collider name.
	var pier_body := _ground(Vector3(160.0, island_y, 220.0), Vector3(20.0, 1.0, 20.0))
	pier_body.name = "OutpostPierDeck"
	p.teleport(Vector3(155.0, island_y + 0.06, 220.0))
	await physics_frames(12)
	p.reset_locomotion_sfx_counts()
	check_eq(p.resolve_footstep_surface(), &"wood", "static wooden pier collider resolves wood")
	p.wish_dir = Vector3(1.0, 0.0, 0.0)
	await physics_frames(65)
	p.wish_dir = Vector3.ZERO
	await physics_frames(6)
	var pier_counts := p.get_locomotion_sfx_counts()
	check(int(pier_counts.get(&"footstep_wood", 0)) >= 1,
		"walking on static wooden pier triggers footstep_wood (got %s)" % str(pier_counts))

	# 4c. Coastal shallow water wading ashore resolves &"water" & triggers &"footstep_water".
	# Use calm still lagoon water (amp_scale = 0.0) so arbitrary Sea.time wave phase never dries out the shallows slab.
	Sea.amp_scale = 0.0
	var shallow_y := Sea.height(260.0, 220.0) - 0.40
	var seabed := _ground(Vector3(260.0, shallow_y, 220.0), Vector3(24.0, 1.0, 24.0))
	seabed.name = "CoastalSeabed"
	p.teleport(Vector3(254.0, shallow_y + 0.06, 220.0))
	await physics_frames(12)
	p.reset_locomotion_sfx_counts()
	check_eq(p.resolve_footstep_surface(), &"water", "coastal ocean shallows resolve water")
	p.wish_dir = Vector3(1.0, 0.0, 0.0)
	await physics_frames(85)
	p.wish_dir = Vector3.ZERO
	await physics_frames(6)
	var wade_counts := p.get_locomotion_sfx_counts()
	check(int(wade_counts.get(&"footstep_water", 0)) >= 1,
		"wading in coastal shallows triggers footstep_water (got %s)" % str(wade_counts))

	# 5. Jumping and landing triggers &"landing" (>= 1) and surface SFX.
	p.teleport(Vector3(220.0, island_y + 0.06, 220.0))
	await physics_frames(12)
	p.reset_locomotion_sfx_counts()
	p.wish_jump = true
	await physics_frames(3)
	p.wish_jump = false
	await physics_frames(75)
	var land_counts := p.get_locomotion_sfx_counts()
	var land_n := int(land_counts.get(&"landing", 0))
	check(land_n >= 1, "jump and land triggers landing SFX count >= 1 (got %d, %s)" % [land_n, str(land_counts)])
	check(int(land_counts.get(&"footstep_sand", 0)) >= 1, "landing on sand increments footstep_sand")

	# 6. Climbing a Ladder triggers rhythmic ladder rung footsteps (footstep_wood and rope_creak).
	var lad := Ladder.new()
	lad.height = 4.5
	lad.width = 0.9
	lad.standoff = 0.4
	_root.add_child(lad)
	lad.global_position = Vector3(220.0, island_y, 214.0)
	p.teleport(Vector3(220.0, island_y + 0.1, 214.5))
	await physics_frames(4)
	p.reset_locomotion_sfx_counts()
	check(p.grab_ladder(lad), "pawn grabs ladder cleanly")
	p.wish_dir = lad.into_dir()
	await physics_frames(95)
	p.wish_dir = Vector3.ZERO
	await physics_frames(4)
	var lad_counts := p.get_locomotion_sfx_counts()
	var lad_wood := int(lad_counts.get(&"footstep_wood", 0))
	var lad_creak := int(lad_counts.get(&"rope_creak", 0))
	check(lad_wood >= 2, "climbing ladder triggers rhythmic footstep_wood rungs (got %d, %s)" % [lad_wood, str(lad_counts)])
	check(lad_creak >= 1, "climbing ladder triggers alternating rope_creak every 3rd rung (got %d, %s)" % [lad_creak, str(lad_counts)])

	# 7. Swimming forward in open water triggers &"splash_small" arm strokes.
	var swim_y := Sea.height(420.0, 420.0) - 1.35
	p.teleport(Vector3(420.0, swim_y, 420.0))
	await physics_frames(15)
	check_eq(p.mode, Pawn.Mode.SWIM, "pawn enters SWIM mode in deep open water")
	p.reset_locomotion_sfx_counts()
	p.wish_dir = Vector3(1.0, 0.0, 0.0)
	await physics_frames(120)
	p.wish_dir = Vector3.ZERO
	await physics_frames(4)
	var swim_counts := p.get_locomotion_sfx_counts()
	var swim_splashes := int(swim_counts.get(&"splash_small", 0))
	check(swim_splashes >= 2, "swimming forward in open water triggers >= 2 splash_small arm strokes (got %d, %s)" % [swim_splashes, str(swim_counts)])
	check_eq(p.get_last_locomotion_sfx(), &"splash_small", "last locomotion SFX while swimming is splash_small")

	print("    Q9A locomotion audio: idle=%d, deck_wood=%d, hold_water=%d, sand=%d, land=%d, ladder=%d/%d, swim=%d" % [
		idle_total, deck_wood, hold_water, sand_steps, land_n, lad_wood, lad_creak, swim_splashes
	])
	Sea.amp_scale = saved_sea_amp
	await _end()

