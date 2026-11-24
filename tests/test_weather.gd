extends TestCase
## Weather logic: wind, sun and moon, transitions, lightning, host authority.

const Palette := preload("res://src/sky/sky_palette.gd")

var _saved: Dictionary

func _save() -> void:
	_saved = Weather.get_state()
	Weather.lightning_enabled = false
	Weather.day_length_seconds = 0.0

func _restore() -> void:
	Weather.set_weather(_saved["storm"], _saved["wind_speed"], _saved["wind_heading"], 0.0, _saved["cloudiness"])
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
		# There is always a light above the horizon, or about to be.
		check(maxf(Weather.sun_height(), Weather.moon_direction().y) > -0.02, "no light at %f h" % (h * 0.5))
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
	check_near(moved.x, 20.0, 0.01, "clouds move with the wind along +X")
	check_near(moved.y, 0.0, 0.01)
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
