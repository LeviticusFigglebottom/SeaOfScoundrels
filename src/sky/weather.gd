extends Node
## Global weather + time-of-day state (host-authoritative, replicated later).
## Everything that cares about wind, storms or the sun reads from here.
##
## State changes only where Net.is_host(). Clients will receive `get_state()`
## snapshots through `apply_state()` once replication lands; everything derived
## (gusts, sun and moon directions, cloud cover, rain) is a pure function of
## that state, so every peer sees the same sky.

## A bolt struck. `direction` is the unit vector from the listener towards the
## bolt (horizontal), `distance` is in metres (use it to delay thunder),
## `intensity` is 0..1. Emitted on every peer.
signal lightning_struck(direction: Vector3, distance: float, intensity: float)
## Thunder from an earlier strike reaches the listener now: `lightning_struck`
## re-sent after distance / SPEED_OF_SOUND seconds. Emitted on every peer.
signal thunder_heard(direction: Vector3, distance: float, intensity: float)
## A transition towards new weather started (host only).
signal weather_changing(storminess: float, wind_speed: float, wind_heading: float, seconds: float)

## Named weather states for `set_preset()`: storminess, wind speed, cloudiness.
const PRESETS := {
	&"clear": [0.0, 5.0, 0.12],
	&"fair": [0.0, 8.0, 0.4],
	&"breezy": [0.15, 12.0, 0.55],
	&"overcast": [0.45, 11.0, 0.9],
	&"squall": [0.75, 17.0, 1.0],
	&"storm": [1.0, 22.0, 1.0],
}
## Storminess above which lightning starts.
const LIGHTNING_THRESHOLD := 0.55
## Sun height (sine of elevation) below which the moon becomes the dominant light.
const DOMINANT_SWITCH_HEIGHT := -0.095
## Days per full cycle of the moon's phase.
const MOON_CYCLE_DAYS := 8.0
## How far (radians) the moon swings either side of opposition over that cycle.
## Under PI/2 so the moon is always gibbous and most of every night is moonlit.
const MOON_SWING := 0.9
## Metres per second; thunder arrives distance / SPEED_OF_SOUND after the flash.
const SPEED_OF_SOUND := 343.0
## Flash brightness halves (roughly) this far from a bolt.
const FLASH_REACH := 1400.0
## A storm cell is at full strength inside this fraction of its radius, then
## falls off smoothly to nothing at the radius. sky_clouds.gdshaderinc matches.
const CELL_CORE := 0.45
## Weather fronts: new weather set with `set_weather(..., seconds)` arrives from
## upwind as a band FRONT_WIDTH metres deep that starts FRONT_REACH upwind.
const FRONT_REACH := 16000.0
const FRONT_WIDTH := 4500.0
## Cloud drift wraps at this distance (a multiple of every cloud texture's tile).
const CLOUD_WRAP := 192000.0

## Hours, 0..24. 6 = sunrise, 12 = noon, 18 = sunset.
var time_of_day: float = 10.0
## Real seconds per in-game day. 0 freezes time.
var day_length_seconds: float = 1440.0
## Direction the wind blows TOWARDS, radians around +Y; 0 = towards -Z (north).
var wind_heading: float = 0.6
## Mean wind speed in m/s. ~4 light breeze, ~9 fresh, ~18 gale.
var wind_speed: float = 8.0
## 0 = clear and calm, 1 = full storm, AT `focus_position` (this peer's camera or
## ship): the background weather or a local storm cell, whichever is stronger.
## Drives waves, rain and lighting. Setting it sets the background weather.
var storminess: float:
	get:
		return _storm_here
	set(v):
		base_storminess = clampf(v, 0.0, 1.0)
		_refresh_focus()
## Background storminess everywhere, outside any storm cell. Replicated.
var base_storminess: float = 0.0

## A local storm: a place in the world you can see from afar and sail into.
## Centre (y ignored), radius in metres and peak storminess; 0 intensity = none.
var storm_center: Vector3 = Vector3.ZERO
var storm_radius: float = 2600.0
var storm_intensity: float = 0.0
## The cell drifts at this velocity (m/s, horizontal).
var storm_velocity: Vector3 = Vector3.ZERO
## Mean wind speed in the core of a full-strength cell (the wind outside is `wind_speed`).
var storm_wind_speed: float = 22.0
## Where this peer experiences the weather from (the sky rig sets it to the camera
## each frame). Not replicated: `storminess`, wind and rain are evaluated here.
var focus_position: Vector3 = Vector3.ZERO

## Whole days elapsed (advances when time_of_day wraps). Drives the moon phase.
var day: int = 0
## Fair-weather cloud amount, 0 (empty sky) to 1 (overcast). Storms add to it.
var cloudiness: float = 0.4
## Seconds of weather simulation. Gusts are a function of this.
var clock: float = 0.0
## Accumulated cloud drift in metres (wind integrated over time); x = +X, y = +Z.
var cloud_offset: Vector2 = Vector2.ZERO
## Set false to stop automatic strikes (cutscenes, tests). Manual strikes still work.
var lightning_enabled: bool = true
## 0..1 brightness of the current lightning flash (flickers, then decays).
var lightning_flash: float = 0.0
## Unit vector towards the latest bolt and its distance in metres (from the focus).
var lightning_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var lightning_distance: float = 1000.0
## World position of the latest bolt's foot (sea level), its strength, and whether
## it was sheet lightning (a flash inside the clouds with no bolt to the sea).
var lightning_position: Vector3 = Vector3(0.0, 0.0, -1000.0)
var lightning_intensity: float = 0.0
var lightning_is_sheet: bool = false
## Counts strikes; a peer that sees it change in a snapshot starts the flash.
var lightning_serial: int = 0
## Accumulated cloud churn (billows boiling), faster in gusts and storms.
var cloud_evolution: float = 0.0

## Weather front of the current (or last) transition; see `front_weight()`.
var front_progress: float = 1.0
var front_heading: float = 0.6
var front_origin: Vector3 = Vector3.ZERO
## x = cloudiness, y = background storminess, before and after the front.
var front_from: Vector2 = Vector2(0.4, 0.0)
var front_to: Vector2 = Vector2(0.4, 0.0)

var _tr_time: float = 0.0
var _tr_duration: float = 0.0
var _tr_from: Array[float] = [0.0, 8.0, 0.6, 0.4]
var _tr_to: Array[float] = [0.0, 8.0, 0.6, 0.4]
var _storm_here: float = 0.0
var _cell_here: float = 0.0
var _cell_tr: Array[float] = [0.0, 0.0, 0.0, 0.0]  # time, duration, from, to
var _thunder: Array = []  # pending [seconds_left, direction, distance, intensity]
var _flash_age: float = 99.0
var _flash_strength: float = 0.0
var _next_strike: float = 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x5EA5C0DE
	_tr_from = [base_storminess, wind_speed, wind_heading, cloudiness]
	_tr_to = _tr_from.duplicate()
	front_heading = wind_heading
	front_from = Vector2(cloudiness, base_storminess)
	front_to = front_from


# --- Wind ---------------------------------------------------------------

func wind_vector() -> Vector3:
	## World-space wind velocity (m/s), horizontal, including gusts.
	var h := wind_heading + gust_heading_offset()
	return Vector3(sin(h), 0.0, -cos(h)) * local_wind_speed() * gust_factor()

func mean_wind_vector() -> Vector3:
	## Wind velocity without gusts: steady heading and speed (at the focus).
	return Vector3(sin(wind_heading), 0.0, -cos(wind_heading)) * local_wind_speed()

func local_wind_speed() -> float:
	## Mean wind speed at the focus: `wind_speed`, raised inside a storm cell.
	return lerpf(wind_speed, maxf(wind_speed, storm_wind_speed), _cell_here)

func wind_speed_at(world_pos: Vector3) -> float:
	## Mean wind speed at any world position.
	return lerpf(wind_speed, maxf(wind_speed, storm_wind_speed), storm_cell_strength(world_pos))

func gustiness() -> float:
	## How far gusts swing the wind speed, as a fraction of the mean.
	return lerpf(0.08, 0.32, clampf(storminess, 0.0, 1.0))

func gust_factor() -> float:
	## Multiplier on wind speed right now, around 1. Slow swells plus sharper puffs.
	var c := clock
	var slow := 0.55 * sin(c * 0.21) + 0.3 * sin(c * 0.53 + 1.3)
	var puff := sin(c * 1.37 + 4.1) * sin(c * 0.31 + 0.7)
	return maxf(0.2, 1.0 + gustiness() * (slow + 0.45 * puff))

func gust_heading_offset() -> float:
	## Radians the wind veers from its mean heading right now.
	return gustiness() * 0.35 * (sin(clock * 0.17 + 2.0) + 0.5 * sin(clock * 0.61))


# --- Sun and moon -------------------------------------------------------

func sun_direction() -> Vector3:
	## Unit vector pointing FROM the scene TOWARDS the sun.
	var a := (time_of_day - 6.0) / 24.0 * TAU
	return Vector3(cos(a), sin(a), 0.35).normalized()

func moon_elongation() -> float:
	## Radians the moon trails the sun around the sky. PI is opposition (a full
	## moon that rises at sunset); it swings MOON_SWING either side over the cycle,
	## so the moon rises up to about 3.4 hours before or after sunset.
	var t := (float(day) + time_of_day / 24.0) / MOON_CYCLE_DAYS
	return PI + MOON_SWING * sin(t * TAU)

func moon_direction() -> Vector3:
	## Unit vector towards the moon. It has its own path: the sun's daily circle,
	## trailed by `moon_elongation()` and tilted the other way.
	var a := (time_of_day - 6.0) / 24.0 * TAU - moon_elongation()
	return Vector3(cos(a), sin(a), -0.28).normalized()

func moon_illumination() -> float:
	## Lit fraction of the moon's disc, 0..1, from the real sun-moon geometry
	## (the sky shader lights the disc from `sun_direction()`, so they agree).
	return 0.5 - 0.5 * sun_direction().dot(moon_direction())

func sun_height() -> float:
	## Sine of the sun's elevation: 0 at the horizon, about 0.94 at noon.
	return sun_direction().y

func moon_phase() -> float:
	## 0 = new, 0.5 = full, 1 = new again; below 0.5 the moon is waxing. Stylized:
	## it swings between waxing and waning gibbous and is never new.
	return moon_elongation() / TAU

func daylight() -> float:
	## 0 at night, 1 in full day, smooth through twilight.
	return smoothstep(-0.12, 0.25, sun_height())

func is_night() -> bool:
	return sun_height() < DOMINANT_SWITCH_HEIGHT

func dominant_light_direction() -> Vector3:
	## Towards whichever body lights the scene: the sun by day, the moon by night.
	return moon_direction() if is_night() else sun_direction()


# --- Derived weather ----------------------------------------------------

func cloud_cover() -> float:
	## 0 = empty sky, 1 = solid overcast, at the focus. Cloudiness plus the storm.
	return cover_for(cloudiness, storminess)

static func cover_for(cloud_amount: float, storm: float) -> float:
	## Cloud cover for a cloudiness and storminess (the cloud shader uses the same curve).
	return clampf(lerpf(cloud_amount, 1.0, smoothstep(0.1, 0.7, storm)), 0.0, 1.0)

func storm_cell_strength(world_pos: Vector3) -> float:
	## 0..1 shape of the storm cell at a position: 1 in the core, 0 outside the
	## radius (and everywhere when there is no cell). Not scaled by intensity.
	if storm_intensity <= 0.0 or storm_radius <= 0.0:
		return 0.0
	var d := Vector2(world_pos.x - storm_center.x, world_pos.z - storm_center.z).length() / storm_radius
	return 1.0 - smoothstep(CELL_CORE, 1.0, d)

func local_storminess(world_pos: Vector3) -> float:
	## Storminess at any world position: the background or the storm cell,
	## whichever is stronger. Ocean, ships and audio should query this.
	return maxf(base_storminess, storm_intensity * storm_cell_strength(world_pos))

func local_rain_intensity(world_pos: Vector3) -> float:
	return smoothstep(0.4, 0.9, local_storminess(world_pos))

func front_weight(world_pos: Vector3) -> float:
	## How much of the weather being transitioned to has arrived at a position:
	## 0 ahead of the front, 1 behind it. The front is a line across the wind
	## that starts FRONT_REACH upwind of where the transition began and sweeps
	## downwind, so new cloud rolls in from the wind's direction. Only the sky's
	## look uses this; `storminess` itself eases smoothly.
	if front_progress >= 1.0:
		return 1.0
	var dir := Vector2(sin(front_heading), -cos(front_heading))
	var along := dir.dot(Vector2(world_pos.x - front_origin.x, world_pos.z - front_origin.z))
	var line := front_line()
	return 1.0 - smoothstep(line - FRONT_WIDTH, line + FRONT_WIDTH, along)

func front_line() -> float:
	## Metres downwind of `front_origin` the middle of the front has reached.
	return (FRONT_REACH + FRONT_WIDTH) * (2.5 * front_progress - 1.0)

func rain_intensity() -> float:
	## 0 = dry, 1 = downpour.
	return smoothstep(0.4, 0.9, storminess)


# --- Changing the weather (host only) -----------------------------------

func set_weather(new_storminess: float, new_wind_speed: float, new_wind_heading: float,
		seconds: float = 0.0, new_cloudiness: float = -1.0) -> void:
	## Move smoothly to new weather over `seconds` (0 = at once). The heading
	## turns the short way round. Pass `new_cloudiness` < 0 to keep the current one.
	if not Net.is_host():
		return
	var target_heading := wind_heading + angle_difference(wind_heading, new_wind_heading)
	# A front already crossing is dropped where it stands: start from what the
	# focus has now.
	_tr_from = [base_storminess, wind_speed, wind_heading, cloudiness]
	_tr_to = [
		clampf(new_storminess, 0.0, 1.0),
		maxf(new_wind_speed, 0.0),
		target_heading,
		cloudiness if new_cloudiness < 0.0 else clampf(new_cloudiness, 0.0, 1.0),
	]
	_tr_time = 0.0
	_tr_duration = maxf(seconds, 0.0)
	front_from = Vector2(_tr_from[3], _tr_from[0])
	front_to = Vector2(_tr_to[3], _tr_to[0])
	front_heading = fposmod(target_heading, TAU)
	front_origin = focus_position
	front_progress = 0.0 if _tr_duration > 0.0 else 1.0
	weather_changing.emit(_tr_to[0], _tr_to[1], fposmod(_tr_to[2], TAU), _tr_duration)
	if _tr_duration <= 0.0:
		_apply_transition(1.0)

func set_preset(preset: StringName, seconds: float = 0.0, new_wind_heading: float = NAN) -> void:
	## Move to a named weather state from PRESETS, keeping the heading unless given.
	if not PRESETS.has(preset):
		push_warning("Weather: unknown preset '%s'" % preset)
		return
	var p: Array = PRESETS[preset]
	var heading := wind_heading if is_nan(new_wind_heading) else new_wind_heading
	set_weather(p[0], p[1], heading, seconds, p[2])

func is_transitioning() -> bool:
	return _tr_time < _tr_duration

func target_storminess() -> float:
	return _tr_to[0] if is_transitioning() else base_storminess

func set_storm_cell(center: Vector3, radius: float, intensity: float = 1.0,
		seconds: float = 0.0, velocity: Vector3 = Vector3.ZERO) -> void:
	## Place a local storm (host only): full weather inside `radius` of `center`,
	## visible from far off. `intensity` is the storminess in its core and eases
	## in over `seconds`; the cell then drifts at `velocity`.
	if not Net.is_host():
		return
	var growing_in_place := storm_intensity > 0.0 and seconds > 0.0
	storm_center = Vector3(center.x, 0.0, center.z)
	storm_radius = maxf(radius, 1.0)
	storm_velocity = Vector3(velocity.x, 0.0, velocity.z)
	var from := storm_intensity if growing_in_place else 0.0
	_cell_tr = [0.0, maxf(seconds, 0.0), from, clampf(intensity, 0.0, 1.0)]
	if seconds <= 0.0:
		storm_intensity = _cell_tr[3]
	else:
		storm_intensity = from
	_refresh_focus()

func clear_storm_cell(seconds: float = 0.0) -> void:
	## Let the storm cell die away over `seconds` (host only).
	if not Net.is_host():
		return
	_cell_tr = [0.0, maxf(seconds, 0.0), storm_intensity, 0.0]
	if seconds <= 0.0:
		storm_intensity = 0.0
	_refresh_focus()

func strike_lightning(direction: Vector3 = Vector3.ZERO, distance: float = -1.0,
		intensity: float = 1.0) -> void:
	## Start a lightning flash now (host only), given relative to the focus. With
	## no arguments the bolt lands somewhere random around it.
	if not Net.is_host():
		return
	if direction.length_squared() < 0.0001:
		var az := _rng.randf() * TAU
		direction = Vector3(sin(az), 0.0, -cos(az))
	if distance <= 0.0:
		distance = _rng.randf_range(500.0, 2600.0)
	direction.y = 0.0
	var at := focus_position + direction.normalized() * distance
	strike_lightning_at(Vector3(at.x, 0.0, at.z), intensity)

func strike_lightning_at(world_pos: Vector3, intensity: float = 1.0, sheet: bool = false) -> void:
	## Lightning at a world position (host only). `sheet` lightning flickers
	## inside the clouds without a bolt reaching the sea.
	if not Net.is_host():
		return
	lightning_serial += 1
	_begin_flash(world_pos, intensity, sheet, 0.0)

func thunder_delay(distance: float) -> float:
	## Seconds between seeing a flash `distance` metres away and hearing it.
	return maxf(distance, 0.0) / SPEED_OF_SOUND

func lightning_illumination(world_pos: Vector3 = focus_position) -> float:
	## How brightly the current flash lights a position, 0..1: the flash envelope
	## with inverse-square style falloff from the bolt. Sheet lightning is weaker.
	if lightning_flash <= 0.0:
		return 0.0
	var d := Vector2(world_pos.x - lightning_position.x, world_pos.z - lightning_position.z).length()
	var reach := FLASH_REACH * (0.6 if lightning_is_sheet else 1.0)
	return lightning_flash / (1.0 + (d / reach) * (d / reach))

func _begin_flash(world_pos: Vector3, intensity: float, sheet: bool, age: float) -> void:
	# Runs on every peer: the host from strike_lightning_at(), clients when a
	# snapshot carries a new lightning_serial.
	lightning_position = Vector3(world_pos.x, 0.0, world_pos.z)
	lightning_is_sheet = sheet
	var to := lightning_position - Vector3(focus_position.x, 0.0, focus_position.z)
	lightning_distance = to.length()
	lightning_direction = to / lightning_distance if lightning_distance > 0.01 else Vector3(0.0, 0.0, -1.0)
	_flash_strength = clampf(intensity, 0.0, 1.0)
	lightning_intensity = _flash_strength
	_flash_age = age
	lightning_flash = _flash_envelope(age) * _flash_strength
	lightning_struck.emit(lightning_direction, lightning_distance, _flash_strength)
	_thunder.append([thunder_delay(lightning_distance) - age, lightning_direction,
			lightning_distance, _flash_strength])


# --- Replication hooks --------------------------------------------------

func get_state() -> Dictionary:
	return {
		"time": time_of_day, "day": day, "day_length": day_length_seconds,
		"storm": base_storminess, "wind_speed": wind_speed, "wind_heading": wind_heading,
		"cloudiness": cloudiness, "clock": clock, "cloud_offset": cloud_offset,
		"cloud_evolution": cloud_evolution,
		"cell_center": storm_center, "cell_radius": storm_radius,
		"cell_intensity": storm_intensity, "cell_velocity": storm_velocity,
		"cell_wind": storm_wind_speed,
		"front_progress": front_progress, "front_heading": front_heading,
		"front_origin": front_origin, "front_from": front_from, "front_to": front_to,
		"bolt_serial": lightning_serial, "bolt_pos": lightning_position,
		"bolt_intensity": lightning_intensity, "bolt_sheet": lightning_is_sheet,
		"bolt_age": _flash_age,
	}

func apply_state(s: Dictionary) -> void:
	## Overwrite local state with a host snapshot (clients).
	time_of_day = s.get("time", time_of_day)
	day = s.get("day", day)
	day_length_seconds = s.get("day_length", day_length_seconds)
	base_storminess = s.get("storm", base_storminess)
	wind_speed = s.get("wind_speed", wind_speed)
	wind_heading = s.get("wind_heading", wind_heading)
	cloudiness = s.get("cloudiness", cloudiness)
	clock = s.get("clock", clock)
	cloud_offset = s.get("cloud_offset", cloud_offset)
	cloud_evolution = s.get("cloud_evolution", cloud_evolution)
	storm_center = s.get("cell_center", storm_center)
	storm_radius = s.get("cell_radius", storm_radius)
	storm_intensity = s.get("cell_intensity", storm_intensity)
	storm_velocity = s.get("cell_velocity", storm_velocity)
	storm_wind_speed = s.get("cell_wind", storm_wind_speed)
	front_progress = s.get("front_progress", 1.0)
	front_heading = s.get("front_heading", wind_heading)
	front_origin = s.get("front_origin", front_origin)
	front_from = s.get("front_from", Vector2(cloudiness, base_storminess))
	front_to = s.get("front_to", Vector2(cloudiness, base_storminess))
	_tr_duration = 0.0
	_tr_time = 0.0
	_cell_tr = [0.0, 0.0, storm_intensity, storm_intensity]
	_refresh_focus()
	var serial: int = s.get("bolt_serial", lightning_serial)
	if serial != lightning_serial:
		lightning_serial = serial
		var age: float = s.get("bolt_age", 0.0)
		if age < 1.0:
			_begin_flash(s.get("bolt_pos", lightning_position), s.get("bolt_intensity", 1.0),
					s.get("bolt_sheet", false), age)


# --- Simulation ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	## Step the weather by `delta` seconds. Called every physics tick; tests call it directly.
	_flash_age += delta
	lightning_flash = _flash_envelope(_flash_age) * _flash_strength
	_advance_thunder(delta)
	if not Net.is_host():
		_refresh_focus()
		return
	if day_length_seconds > 0.0:
		var t := time_of_day + delta * 24.0 / day_length_seconds
		if t >= 24.0:
			day += int(t / 24.0)
		time_of_day = fposmod(t, 24.0)
	if is_transitioning():
		_tr_time = minf(_tr_time + delta, _tr_duration)
		_apply_transition(_tr_time / _tr_duration)
	if _cell_tr[0] < _cell_tr[1]:
		_cell_tr[0] = minf(_cell_tr[0] + delta, _cell_tr[1])
		storm_intensity = lerpf(_cell_tr[2], _cell_tr[3], smoothstep(0.0, 1.0, _cell_tr[0] / _cell_tr[1]))
	storm_center += storm_velocity * delta
	_refresh_focus()
	clock += delta
	# Clouds ride the gusty wind: they surge and veer with it.
	var w := wind_vector()
	cloud_offset += Vector2(w.x, w.z) * delta
	cloud_offset = Vector2(fposmod(cloud_offset.x, CLOUD_WRAP), fposmod(cloud_offset.y, CLOUD_WRAP))
	cloud_evolution += delta * gust_factor() * lerpf(0.6, 2.2, clampf(maxf(_storm_here, storm_intensity), 0.0, 1.0))
	var fury_at := maxf(base_storminess, storm_intensity)
	if lightning_enabled and fury_at > LIGHTNING_THRESHOLD:
		_next_strike -= delta
		if _next_strike <= 0.0:
			var fury := inverse_lerp(LIGHTNING_THRESHOLD, 1.0, fury_at)
			_next_strike = lerpf(16.0, 5.0, fury) * _rng.randf_range(0.4, 1.6)
			_strike_somewhere(_rng.randf_range(0.6, 1.0))

func _strike_somewhere(intensity: float) -> void:
	## Automatic strikes land inside the storm cell when it is the stronger
	## weather, so a distant storm flickers on the horizon; otherwise around the focus.
	var sheet := _rng.randf() < 0.35
	if storm_intensity > base_storminess and storm_intensity > LIGHTNING_THRESHOLD:
		var az := _rng.randf() * TAU
		var r := storm_radius * 0.8 * sqrt(_rng.randf())
		strike_lightning_at(storm_center + Vector3(sin(az), 0.0, -cos(az)) * r, intensity, sheet)
	else:
		var az := _rng.randf() * TAU
		var at := focus_position + Vector3(sin(az), 0.0, -cos(az)) * _rng.randf_range(500.0, 2600.0)
		strike_lightning_at(at, intensity, sheet)

func _advance_thunder(delta: float) -> void:
	var i := 0
	while i < _thunder.size():
		var t: Array = _thunder[i]
		t[0] -= delta
		if t[0] <= 0.0:
			_thunder.remove_at(i)
			thunder_heard.emit(t[1], t[2], t[3])
		else:
			i += 1

func set_focus(world_pos: Vector3) -> void:
	## Tell the weather where this peer is (the sky rig does this with the camera).
	focus_position = world_pos
	_refresh_focus()

func _refresh_focus() -> void:
	_cell_here = storm_intensity * storm_cell_strength(focus_position)
	_storm_here = maxf(base_storminess, _cell_here)

func _apply_transition(t: float) -> void:
	var k := smoothstep(0.0, 1.0, t)
	base_storminess = lerpf(_tr_from[0], _tr_to[0], k)
	wind_speed = lerpf(_tr_from[1], _tr_to[1], k)
	wind_heading = fposmod(lerpf(_tr_from[2], _tr_to[2], k), TAU)
	cloudiness = lerpf(_tr_from[3], _tr_to[3], k)
	front_progress = t
	_refresh_focus()

func _flash_envelope(age: float) -> float:
	## A bright stroke, then two weaker restrikes, gone in about 0.7 s.
	if age < 0.0 or age > 0.9:
		return 0.0
	var f := exp(-age * 11.0)
	if age > 0.13:
		f += 0.65 * exp(-(age - 0.13) * 15.0)
	if age > 0.3:
		f += 0.4 * exp(-(age - 0.3) * 9.0)
	return clampf(f, 0.0, 1.0)
