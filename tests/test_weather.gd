extends TestCase
## Weather logic: wind, sun and moon, transitions, lightning, host authority.

const Palette := preload("res://src/sky/sky_palette.gd")
const CloudField := preload("res://src/sky/cloud_field.gd")

var _saved: Dictionary

func _save() -> void:
	_saved = Weather.get_state()
	Weather.lightning_enabled = false
	Weather.day_length_seconds = 0.0

func _restore() -> void:
	Weather.set_weather(_saved["storm"], _saved["wind_speed"], _saved["wind_heading"], 0.0, _saved["cloudiness"])
	Weather.clear_storm_cell()
	Weather.set_focus(Vector3.ZERO)
	Weather.apply_state(_saved)
	Weather.lightning_enabled = true

func test_wind_vector_follows_heading() -> void:
	_save()
	Weather.set_weather(0.0, 10.0, 0.0)
	var north := Weather.mean_wind_vector()
	check_near(north.x, 0.0, 0.001)
	check_near(north.z, -10.0, 0.001, "heading 0 blows towards -Z")
	Weather.set_weather(0.0, 10.0, PI * 0.5)
	check_near(Weather.mean_wind_vector().x, 10.0, 0.001, "heading 90 degrees blows towards +X")
	check_near(Weather.wind_vector().y, 0.0, 0.0001, "wind is horizontal")
	_restore()

func test_gusts_stay_near_the_mean() -> void:
	_save()
	for storm: float in [0.0, 1.0]:
		Weather.set_weather(storm, 12.0, 1.0)
		var lo := 1e9
		var hi := -1e9
		for i in 400:
			Weather.clock = i * 0.37
			var v := Weather.wind_vector()
			lo = minf(lo, v.length())
			hi = maxf(hi, v.length())
			check(v.normalized().dot(Weather.mean_wind_vector().normalized()) > 0.9, "gusts veer only slightly")
		var g := Weather.gustiness()
		check(lo > 12.0 * (1.0 - g * 1.4) and lo > 0.0, "gust lull %f too deep at storm %f" % [lo, storm])
		check(hi < 12.0 * (1.0 + g * 1.4), "gust peak %f too high at storm %f" % [hi, storm])
		check(hi - lo > 12.0 * g * 0.5, "gusts should actually vary")
	_restore()

func test_sun_and_moon_directions() -> void:
	_save()
	for h in 49:
		Weather.time_of_day = h * 0.5
		check_near(Weather.sun_direction().length(), 1.0, 0.0001)
		check_near(Weather.moon_direction().length(), 1.0, 0.0001)
		check_near(Weather.dominant_light_direction().length(), 1.0, 0.0001)
	Weather.time_of_day = 12.0
	check(Weather.sun_height() > 0.9, "noon sun is high")
	check(not Weather.is_night())
	check_near(Weather.daylight(), 1.0, 0.001)
	Weather.time_of_day = 6.0
	check_near(Weather.sun_height(), 0.0, 0.001, "sunrise at 6")
	check(Weather.sun_direction().x > 0.9, "sun rises in +X")
	Weather.time_of_day = 18.0
	check_near(Weather.sun_height(), 0.0, 0.001, "sunset at 18")
	Weather.time_of_day = 0.0
	check(Weather.sun_height() < -0.9, "midnight sun is far below")
	check(Weather.is_night())
	check(Weather.dominant_light_direction().y > 0.5, "the moon lights midnight")
	check_near(Weather.daylight(), 0.0, 0.001)
	var phase := Weather.moon_phase()
	check(phase > 0.2 and phase < 0.8, "moon is never new")
	_restore()

func test_time_advances_and_days_roll() -> void:
	_save()
	Weather.day_length_seconds = 240.0
	Weather.time_of_day = 23.5
	var day0 := Weather.day
	Weather.advance(10.0)  # one hour
	check_near(Weather.time_of_day, 0.5, 0.001)
	check_eq(Weather.day, day0 + 1)
	Weather.day_length_seconds = 0.0
	Weather.advance(10.0)
	check_near(Weather.time_of_day, 0.5, 0.001, "day length 0 freezes time")
	_restore()

func test_transition_is_smooth_and_lands() -> void:
	_save()
	Weather.set_weather(0.0, 6.0, 0.2, 0.0, 0.3)
	check(not Weather.is_transitioning())
	Weather.set_weather(1.0, 20.0, 1.2, 10.0, 1.0)
	check(Weather.is_transitioning())
	check_near(Weather.storminess, 0.0, 0.0001, "nothing jumps when a transition starts")
	check_near(Weather.target_storminess(), 1.0, 0.0001)
	var last := 0.0
	var biggest_step := 0.0
	for i in 100:
		Weather.advance(0.1)
		check(Weather.storminess >= last - 0.00001, "storminess rises monotonically")
		biggest_step = maxf(biggest_step, Weather.storminess - last)
		last = Weather.storminess
	check(biggest_step < 0.03, "no step larger than 3%% (got %f)" % biggest_step)
	Weather.advance(0.1)
	check(not Weather.is_transitioning())
	check_near(Weather.storminess, 1.0, 0.0001)
	check_near(Weather.wind_speed, 20.0, 0.0001)
	check_near(Weather.wind_heading, 1.2, 0.0001)
	check_near(Weather.cloudiness, 1.0, 0.0001)
	check_near(Weather.cloud_cover(), 1.0, 0.0001)
	check_near(Weather.rain_intensity(), 1.0, 0.0001)
	_restore()

func test_heading_turns_the_short_way() -> void:
	_save()
	Weather.set_weather(0.0, 8.0, deg_to_rad(350.0))
	Weather.set_weather(0.0, 8.0, deg_to_rad(20.0), 4.0)
	Weather.advance(2.0)
	# Halfway from 350 to 20 the short way is 5 degrees, not 185.
	check_near(angle_difference(Weather.wind_heading, deg_to_rad(5.0)), 0.0, 0.01)
	Weather.advance(2.5)
	check_near(Weather.wind_heading, deg_to_rad(20.0), 0.001)
	_restore()

func test_presets() -> void:
	_save()
	Weather.set_preset(&"storm")
	check_near(Weather.storminess, 1.0, 0.0001)
	check(Weather.wind_speed > 18.0)
	Weather.set_preset(&"clear")
	check_near(Weather.storminess, 0.0, 0.0001)
	check(Weather.cloud_cover() < 0.2)
	check_near(Weather.rain_intensity(), 0.0, 0.0001)
	_restore()

func test_clouds_drift_downwind() -> void:
	_save()
	Weather.set_weather(0.0, 10.0, PI * 0.5)
	var before := Weather.cloud_offset
	Weather.advance(2.0)
	var moved := Weather.cloud_offset - before
	# The offset wraps; take the short way round.
	var wrap: float = Weather.CLOUD_WRAP
	moved = Vector2(fposmod(moved.x + wrap * 0.5, wrap) - wrap * 0.5, fposmod(moved.y + wrap * 0.5, wrap) - wrap * 0.5)
	# Clouds ride the gusty wind, so allow for the gust of the moment.
	check_near(moved.x, 20.0, 20.0 * Weather.gustiness() * 1.5, "clouds move with the wind along +X")
	check(absf(moved.y) < 2.0, "and barely across it")
	_restore()

func test_lightning_signal_and_flash() -> void:
	_save()
	var hits: Array = []
	var on_hit := func(dir: Vector3, dist: float, intensity: float) -> void:
		hits.append([dir, dist, intensity])
	Weather.lightning_struck.connect(on_hit)
	Weather.strike_lightning(Vector3(0, 0, -2), 800.0)
	check_eq(hits.size(), 1)
	check_near((hits[0][0] as Vector3).length(), 1.0, 0.0001, "direction is normalised")
	check_near(hits[0][1], 800.0, 0.001)
	check(Weather.lightning_flash > 0.9, "flash starts bright")
	Weather.advance(1.5)
	check_near(Weather.lightning_flash, 0.0, 0.0001, "flash is over within 1.5 s")
	# Storms strike on their own; calm weather never does.
	hits.clear()
	Weather.lightning_enabled = true
	Weather.set_weather(1.0, 20.0, 0.0)
	for i in 600:
		Weather.advance(0.1)
	check(hits.size() >= 3, "a minute of full storm should strike several times (got %d)" % hits.size())
	hits.clear()
	Weather.set_weather(0.2, 8.0, 0.0)
	for i in 600:
		Weather.advance(0.1)
	check_eq(hits.size(), 0, "no lightning in fair weather")
	Weather.lightning_struck.disconnect(on_hit)
	_restore()

func test_only_the_host_changes_weather() -> void:
	_save()
	Weather.set_weather(0.1, 7.0, 0.3)
	# A client is a peer that is connected (or connecting) to someone else's server.
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", 24699) == OK:
		var old_peer := multiplayer.multiplayer_peer
		multiplayer.multiplayer_peer = peer
		check(not Net.is_host(), "a client is not the host")
		var t := Weather.time_of_day
		Weather.day_length_seconds = 100.0
		Weather.set_weather(1.0, 25.0, 2.0)
		Weather.strike_lightning()
		Weather.advance(5.0)
		check_near(Weather.storminess, 0.1, 0.0001, "client cannot set weather")
		check_near(Weather.time_of_day, t, 0.0001, "client does not advance time")
		check_near(Weather.lightning_flash, 0.0, 0.0001, "client cannot strike lightning")
		peer.close()
		multiplayer.multiplayer_peer = old_peer
		check(Net.is_host())
	_restore()

func test_palette_is_sane_everywhere() -> void:
	# Night is never black, colours stay in range, and nothing jumps between
	# neighbouring times of day.
	var prev: Dictionary = {}
	for storm: float in [0.0, 1.0]:
		prev = {}
		for i in 481:
			var hour := i * 0.05
			var a := (hour - 6.0) / 24.0 * TAU
			var sun_h := sin(a) / sqrt(1.1225)
			var p := Palette.compute(sun_h, -sun_h, smoothstep(11.0, 13.0, hour), 1.0, 0.4 if storm < 0.5 else 1.0, storm)
			for key: String in ["zenith", "horizon", "ambient", "cloud_lit"]:
				var c: Color = p[key]
				check(c.r >= 0.0 and c.g >= 0.0 and c.b >= 0.0 and maxf(c.r, maxf(c.g, c.b)) <= 1.0001, "%s out of range at %f h" % [key, hour])
				if not prev.is_empty() and i > 0:
					var q: Color = prev[key]
					var step := absf(c.r - q.r) + absf(c.g - q.g) + absf(c.b - q.b)
					check(step < 0.2, "%s jumps by %f at %f h (storm %f)" % [key, step, hour, storm])
			var horizon: Color = p["horizon"]
			var ambient: Color = p["ambient"]
			check(horizon.get_luminance() > 0.06, "horizon too dark at %f h storm %f" % [hour, storm])
			check(ambient.get_luminance() > 0.1, "ambient too dark at %f h storm %f" % [hour, storm])
			check(float(p["sun_energy"]) + float(p["moon_energy"]) >= 0.0)
			if sun_h < -0.4:
				check(horizon.b > horizon.r, "night is blue at %f h" % hour)
				check(float(p["sun_energy"]) == 0.0, "no sunlight at night")
				check(float(p["moon_energy"]) > 0.05, "moonlight at night")
			prev = p

func test_storm_cell_is_a_place() -> void:
	_save()
	Weather.set_weather(0.1, 8.0, 0.0, 0.0, 0.3)
	Weather.set_focus(Vector3.ZERO)
	Weather.set_storm_cell(Vector3(4000.0, 50.0, 0.0), 2000.0, 1.0)
	check_near(Weather.storm_center.y, 0.0, 0.0001, "the cell lives at sea level")
	check_near(Weather.local_storminess(Vector3(4000.0, 0.0, 0.0)), 1.0, 0.0001, "full storm in the core")
	check_near(Weather.local_storminess(Vector3(4000.0, 300.0, 600.0)), 1.0, 0.0001, "the core is wide, height is ignored")
	check_near(Weather.local_storminess(Vector3(0.0, 0.0, 0.0)), 0.1, 0.0001, "background weather outside")
	check_near(Weather.local_storminess(Vector3(4000.0, 0.0, 2001.0)), 0.1, 0.0001, "nothing past the radius")
	var last := 1.0
	for i in 41:
		var s := Weather.local_storminess(Vector3(4000.0 + i * 50.0, 0.0, 0.0))
		check(s <= last + 0.00001, "storminess falls off monotonically from the centre")
		check(last - s < 0.12, "and without a step")
		last = s
	# The global value is the value at the focus.
	check_near(Weather.storminess, 0.1, 0.0001, "calm at the focus, outside the cell")
	check_near(Weather.rain_intensity(), 0.0, 0.0001)
	check_near(Weather.mean_wind_vector().length(), 8.0, 0.001)
	Weather.set_focus(Vector3(4000.0, 3.0, 100.0))
	check_near(Weather.storminess, 1.0, 0.0001, "sailing in brings the full storm")
	check_near(Weather.rain_intensity(), 1.0, 0.0001)
	check_near(Weather.cloud_cover(), 1.0, 0.0001)
	check_near(Weather.mean_wind_vector().length(), Weather.storm_wind_speed, 0.001, "and its wind")
	check_near(Weather.wind_speed_at(Vector3.ZERO), 8.0, 0.001)
	check_near(Weather.local_rain_intensity(Vector3.ZERO), 0.0, 0.0001)
	# The cell drifts, grows and dies.
	Weather.clear_storm_cell()
	Weather.set_storm_cell(Vector3.ZERO, 1000.0, 0.8, 10.0, Vector3(5.0, 0.0, 0.0))
	check_near(Weather.storm_intensity, 0.0, 0.0001, "a new cell eases in")
	Weather.advance(5.0)
	check_near(Weather.storm_intensity, 0.4, 0.0001)
	check_near(Weather.storm_center.x, 25.0, 0.001, "the cell drifts")
	Weather.advance(6.0)
	check_near(Weather.storm_intensity, 0.8, 0.0001)
	Weather.clear_storm_cell(4.0)
	Weather.advance(5.0)
	check_near(Weather.storm_intensity, 0.0, 0.0001)
	Weather.set_focus(Weather.storm_center)
	check_near(Weather.storminess, 0.1, 0.0001, "a dead cell leaves the background weather")
	_restore()

func test_moon_geometry() -> void:
	_save()
	var widest := 0.0
	for d in 16:
		Weather.day = d
		var up_at_night := 0
		var night_samples := 0
		for h in 96:
			Weather.time_of_day = h * 0.25
			var sun := Weather.sun_direction()
			var moon := Weather.moon_direction()
			check_near(moon.length(), 1.0, 0.0001)
			# The lit fraction is the real geometry: full when opposite the sun.
			check_near(Weather.moon_illumination(), 0.5 - 0.5 * sun.dot(moon), 0.0001)
			check(Weather.moon_illumination() > 0.5, "the moon is always gibbous")
			check(sun.dot(moon) < 0.0, "so it is never on the sun's side of the sky")
			if Weather.sun_height() < -0.2:
				night_samples += 1
				if moon.y > 0.0:
					up_at_night += 1
		check(up_at_night * 10 >= night_samples * 6, "moonlit for most of the night on day %d" % d)
		Weather.time_of_day = 12.0
		widest = maxf(widest, absf(Weather.moon_elongation() - PI))
		check(Weather.moon_phase() > 0.3 and Weather.moon_phase() < 0.7)
	check(widest > 0.6, "the phase really changes over the cycle")
	# Decoupled from the sun: at sunset the moon is not always just rising.
	var heights: Array[float] = []
	for d in 8:
		Weather.day = d
		Weather.time_of_day = 18.0
		heights.append(Weather.moon_direction().y)
	check(heights.max() - heights.min() > 0.4, "moonrise time moves through the cycle")
	_restore()

func test_fronts_roll_in_from_upwind() -> void:
	_save()
	Weather.set_weather(0.0, 10.0, PI * 0.5, 0.0, 0.2)  # blowing towards +X
	Weather.set_focus(Vector3.ZERO)
	check_near(Weather.front_weight(Vector3(-9000.0, 0.0, 0.0)), 1.0, 0.0001, "no front when nothing is changing")
	Weather.set_weather(1.0, 20.0, PI * 0.5, 100.0, 1.0)
	check_near(Weather.front_weight(Vector3.ZERO), 0.0, 0.0001, "the new weather starts far upwind")
	var arrived_upwind := -1.0
	var arrived_here := -1.0
	var arrived_downwind := -1.0
	var last_here := 0.0
	for i in 100:
		Weather.advance(1.0)
		var here := Weather.front_weight(Vector3.ZERO)
		check(here >= last_here - 0.0001, "the front only advances")
		last_here = here
		if arrived_upwind < 0.0 and Weather.front_weight(Vector3(-8000.0, 0.0, 0.0)) > 0.5:
			arrived_upwind = i
		if arrived_here < 0.0 and here > 0.5:
			arrived_here = i
		if arrived_downwind < 0.0 and Weather.front_weight(Vector3(8000.0, 0.0, 0.0)) > 0.5:
			arrived_downwind = i
		check_near(Weather.front_weight(Vector3(0.0, 0.0, 7000.0)), here, 0.0001, "the front is a line across the wind")
	check(arrived_upwind >= 0.0 and arrived_upwind < arrived_here, "cloud reaches upwind first")
	check(arrived_here < arrived_downwind, "then passes overhead and on downwind")
	check(Weather.rain_intensity() > 0.99)
	check_near(Weather.front_weight(Vector3(15000.0, 0.0, 0.0)), 1.0, 0.0001, "the whole sky has changed at the end")
	_restore()

func test_lightning_place_and_thunder() -> void:
	_save()
	Weather.set_focus(Vector3(100.0, 4.0, 0.0))
	var heard: Array = []
	var on_thunder := func(_dir: Vector3, dist: float, _intensity: float) -> void:
		heard.append(dist)
	Weather.thunder_heard.connect(on_thunder)
	Weather.strike_lightning_at(Vector3(100.0, 0.0, -686.0), 1.0)
	check_near(Weather.lightning_distance, 686.0, 0.01)
	check_near(Weather.lightning_direction.z, -1.0, 0.0001)
	check_near(Weather.thunder_delay(686.0), 2.0, 0.0001, "sound takes two seconds over 686 m")
	Weather.advance(1.9)
	check_eq(heard.size(), 0, "thunder has not arrived yet")
	Weather.advance(0.2)
	check_eq(heard.size(), 1, "thunder arrives distance / 343 after the flash")
	# The flash falls off with distance from the bolt.
	Weather.strike_lightning_at(Vector3(100.0, 0.0, -686.0), 1.0)
	var near := Weather.lightning_illumination(Vector3(100.0, 0.0, -600.0))
	var far := Weather.lightning_illumination(Vector3(100.0, 0.0, 6000.0))
	check(near > 0.9, "bright next to the bolt")
	check(far < 0.06 and far > 0.0, "faint kilometres away (got %f)" % far)
	# Automatic strikes land inside a storm cell when there is one.
	Weather.set_weather(0.0, 8.0, 0.0)
	Weather.set_storm_cell(Vector3(9000.0, 0.0, 0.0), 1500.0, 1.0)
	Weather.lightning_enabled = true
	var struck := 0
	var serial := Weather.lightning_serial
	for i in 600:
		Weather.advance(0.1)
		if Weather.lightning_serial != serial:
			serial = Weather.lightning_serial
			struck += 1
			check(Weather.lightning_position.distance_to(Weather.storm_center) < 1500.0, "bolts land in the cell")
			check(Weather.lightning_distance > 7000.0, "far from the listener outside it")
	check(struck >= 3, "a distant cell flickers on its own (got %d)" % struck)
	Weather.thunder_heard.disconnect(on_thunder)
	_restore()

func test_state_round_trip() -> void:
	_save()
	Weather.set_weather(0.2, 9.0, 1.0, 0.0, 0.5)
	Weather.set_focus(Vector3(10.0, 0.0, 20.0))
	Weather.set_weather(0.9, 19.0, 2.0, 50.0, 1.0)
	Weather.set_storm_cell(Vector3(3000.0, 0.0, -2000.0), 1700.0, 0.9, 0.0, Vector3(3.0, 0.0, 1.0))
	Weather.advance(20.0)
	Weather.strike_lightning_at(Vector3(2500.0, 0.0, -1800.0), 0.8, true)
	Weather.advance(0.05)
	var snap := Weather.get_state()
	var probe := Vector3(-5000.0, 0.0, 1000.0)
	var want := [Weather.base_storminess, Weather.storm_center, Weather.storm_radius, Weather.storm_intensity,
			Weather.storm_velocity, Weather.front_progress, Weather.front_weight(probe), Weather.cloud_offset,
			Weather.cloud_evolution, Weather.local_storminess(Vector3(3000.0, 0.0, -2000.0)), Weather.lightning_serial]
	# Scramble everything, then restore from the snapshot as a client would.
	Weather.set_weather(0.0, 3.0, 0.0, 0.0, 0.1)
	Weather.clear_storm_cell()
	Weather.advance(3.0)
	var flashes: Array = []
	var on_hit := func(_dir: Vector3, dist: float, _intensity: float) -> void:
		flashes.append(dist)
	Weather.lightning_struck.connect(on_hit)
	Weather.lightning_serial = 0
	Weather.apply_state(snap)
	var got := [Weather.base_storminess, Weather.storm_center, Weather.storm_radius, Weather.storm_intensity,
			Weather.storm_velocity, Weather.front_progress, Weather.front_weight(probe), Weather.cloud_offset,
			Weather.cloud_evolution, Weather.local_storminess(Vector3(3000.0, 0.0, -2000.0)), Weather.lightning_serial]
	for i in want.size():
		check(is_equal_approx_any(want[i], got[i]), "state field %d survives the round trip (%s vs %s)" % [i, want[i], got[i]])
	check_eq(flashes.size(), 1, "a snapshot carrying a new bolt starts the flash on the client")
	check(Weather.lightning_is_sheet, "and says it was sheet lightning")
	check(Weather.lightning_flash > 0.3, "with the flash already under way")
	Weather.apply_state(snap)
	check_eq(flashes.size(), 1, "the same snapshot twice does not strike twice")
	check_eq(JSON.stringify(Weather.get_state()).length() > 0, true)
	Weather.lightning_struck.disconnect(on_hit)
	_restore()

func is_equal_approx_any(a: Variant, b: Variant) -> bool:
	if a is float or a is int:
		return absf(float(a) - float(b)) < 0.0001
	return a.is_equal_approx(b)

func test_cloud_field_and_shadow() -> void:
	_save()
	var field: RefCounted = CloudField.new()
	var up := Vector3(0.0, 1.0, 0.0)
	Weather.set_weather(0.0, 8.0, 0.0, 0.0, 0.0)
	var lit := 0
	for i in 200:
		var l: float = field.light_at(Vector3(i * 137.0, 0.0, i * 71.0), up)
		check(l >= CloudField.FLOOR_LIGHT - 0.0001 and l <= 1.0001)
		if l > 0.95:
			lit += 1
	check(lit > 190, "an empty sky casts almost no shadow (%d of 200 lit)" % lit)
	Weather.set_weather(1.0, 20.0, 0.0, 0.0, 1.0)
	var dark := 0
	for i in 200:
		if field.light_at(Vector3(i * 137.0, 0.0, i * 71.0), up) < 0.4:
			dark += 1
	check(dark > 185, "a storm deck shades nearly everything (%d of 200 dark)" % dark)
	# A storm cell shades its own patch of sea and nothing far away.
	Weather.set_weather(0.0, 8.0, 0.0, 0.0, 0.0)
	Weather.set_storm_cell(Vector3(5000.0, 0.0, 5000.0), 2000.0, 1.0)
	check(field.light_at(Vector3(5000.0, 0.0, 5000.0), up) < 0.4, "dark under the cell")
	var col: Dictionary = field.column(Vector2(5000.0, 5000.0))
	check_near(col["base"], CloudField.BASE_STORM, 0.5, "the cell's base hangs low")
	check_near(col["storm"], 1.0, 0.0001)
	# Shadows fall away from the light.
	var shift: Vector2 = CloudField.shadow_shift(Vector3(0.6, 0.5, 0.0).normalized())
	check(shift.x > 0.5 and absf(shift.y) < 0.0001, "the cloud that shades a point lies towards the sun")
	_restore()

func test_dusk_handover_never_pops() -> void:
	# Through sunset and moonrise, on every day of the moon's cycle, the total
	# key light and the sky colours change smoothly: no pop when the moon takes over.
	const Rig := preload("res://src/sky/sky_rig.gd")
	_save()
	for d in 8:
		Weather.day = d
		var prev: Dictionary = {}
		for i in 241:
			Weather.time_of_day = 16.5 + i * 0.02
			var p := Palette.compute(Weather.sun_height(), Weather.moon_direction().y,
					Rig.evening(Weather.time_of_day), Weather.moon_illumination(), 0.4, 0.0)
			if not prev.is_empty():
				check(absf(float(p["sun_energy"]) - float(prev["sun_energy"])) < 0.05, "sun energy steps at %f h" % Weather.time_of_day)
				check(absf(float(p["moon_energy"]) - float(prev["moon_energy"])) < 0.05, "moon energy steps at %f h" % Weather.time_of_day)
				for key: String in ["zenith", "mid", "horizon", "cloud_lit", "cloud_shade", "ambient"]:
					var a: Color = p[key]
					var b: Color = prev[key]
					check(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.08, "%s jumps at %f h" % [key, Weather.time_of_day])
			prev = p
	_restore()
