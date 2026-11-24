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

## Hours, 0..24. 6 = sunrise, 12 = noon, 18 = sunset.
var time_of_day: float = 10.0
## Real seconds per in-game day. 0 freezes time.
var day_length_seconds: float = 1440.0
## Direction the wind blows TOWARDS, radians around +Y; 0 = towards -Z (north).
var wind_heading: float = 0.6
## Mean wind speed in m/s. ~4 light breeze, ~9 fresh, ~18 gale.
var wind_speed: float = 8.0
## 0 = clear and calm, 1 = full storm. Drives waves, clouds, rain, lighting.
var storminess: float = 0.0

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
## Unit vector towards the latest bolt and its distance in metres.
var lightning_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var lightning_distance: float = 1000.0

var _tr_time: float = 0.0
var _tr_duration: float = 0.0
var _tr_from: Array[float] = [0.0, 8.0, 0.6, 0.4]
var _tr_to: Array[float] = [0.0, 8.0, 0.6, 0.4]
var _flash_age: float = 99.0
var _flash_strength: float = 0.0
var _next_strike: float = 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x5EA5C0DE
	_tr_from = [storminess, wind_speed, wind_heading, cloudiness]
	_tr_to = _tr_from.duplicate()


# --- Wind ---------------------------------------------------------------

func wind_vector() -> Vector3:
	## World-space wind velocity (m/s), horizontal, including gusts.
	var h := wind_heading + gust_heading_offset()
	return Vector3(sin(h), 0.0, -cos(h)) * wind_speed * gust_factor()

func mean_wind_vector() -> Vector3:
	## Wind velocity without gusts: steady heading and speed.
	return Vector3(sin(wind_heading), 0.0, -cos(wind_heading)) * wind_speed

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

func moon_direction() -> Vector3:
	## Unit vector towards the moon. It rides opposite the sun, so it rises at dusk.
	var a := (time_of_day - 6.0) / 24.0 * TAU + PI
	return Vector3(cos(a), sin(a), -0.28).normalized()

func sun_height() -> float:
	## Sine of the sun's elevation: 0 at the horizon, about 0.94 at noon.
	return sun_direction().y

func moon_phase() -> float:
	## 0 = new, 0.5 = full, 1 = new again. Stylized: swings between the two half
	## moons through full, so nights always have some moonlight.
	var t := (float(day) + time_of_day / 24.0) / MOON_CYCLE_DAYS
	return 0.5 + 0.24 * sin(t * TAU)

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
	## 0 = empty sky, 1 = solid overcast. Fair-weather cloudiness plus the storm.
	return clampf(lerpf(cloudiness, 1.0, smoothstep(0.1, 0.7, storminess)), 0.0, 1.0)

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
	_tr_from = [storminess, wind_speed, wind_heading, cloudiness]
	_tr_to = [
		clampf(new_storminess, 0.0, 1.0),
		maxf(new_wind_speed, 0.0),
		target_heading,
		cloudiness if new_cloudiness < 0.0 else clampf(new_cloudiness, 0.0, 1.0),
	]
	_tr_time = 0.0
	_tr_duration = maxf(seconds, 0.0)
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
	return _tr_to[0] if is_transitioning() else storminess

func strike_lightning(direction: Vector3 = Vector3.ZERO, distance: float = -1.0,
		intensity: float = 1.0) -> void:
	## Start a lightning flash now (host only). With no arguments the bolt lands
	## somewhere random around the listener.
	if not Net.is_host():
		return
	if direction.length_squared() < 0.0001:
		var az := _rng.randf() * TAU
		direction = Vector3(sin(az), 0.0, -cos(az))
	if distance <= 0.0:
		distance = _rng.randf_range(500.0, 2600.0)
	_begin_flash(direction, distance, intensity)

func _begin_flash(direction: Vector3, distance: float, intensity: float) -> void:
	# Split from strike_lightning so clients can run it from an RPC later.
	direction.y = 0.0
	lightning_direction = direction.normalized()
	lightning_distance = distance
	_flash_strength = clampf(intensity, 0.0, 1.0)
	_flash_age = 0.0
	lightning_flash = _flash_envelope(0.0) * _flash_strength
	lightning_struck.emit(lightning_direction, lightning_distance, _flash_strength)


# --- Replication hooks --------------------------------------------------

func get_state() -> Dictionary:
	return {
		"time": time_of_day, "day": day, "day_length": day_length_seconds,
		"storm": storminess, "wind_speed": wind_speed, "wind_heading": wind_heading,
		"cloudiness": cloudiness, "clock": clock, "cloud_offset": cloud_offset,
	}

func apply_state(s: Dictionary) -> void:
	## Overwrite local state with a host snapshot (clients).
	time_of_day = s.get("time", time_of_day)
	day = s.get("day", day)
	day_length_seconds = s.get("day_length", day_length_seconds)
	storminess = s.get("storm", storminess)
	wind_speed = s.get("wind_speed", wind_speed)
	wind_heading = s.get("wind_heading", wind_heading)
	cloudiness = s.get("cloudiness", cloudiness)
	clock = s.get("clock", clock)
	cloud_offset = s.get("cloud_offset", cloud_offset)
	_tr_duration = 0.0
	_tr_time = 0.0


# --- Simulation ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	## Step the weather by `delta` seconds. Called every physics tick; tests call it directly.
	_flash_age += delta
	lightning_flash = _flash_envelope(_flash_age) * _flash_strength
	if not Net.is_host():
		return
	if day_length_seconds > 0.0:
		var t := time_of_day + delta * 24.0 / day_length_seconds
		if t >= 24.0:
			day += int(t / 24.0)
		time_of_day = fposmod(t, 24.0)
	if is_transitioning():
		_tr_time = minf(_tr_time + delta, _tr_duration)
		_apply_transition(_tr_time / _tr_duration)
	clock += delta
	var w := mean_wind_vector()
	cloud_offset += Vector2(w.x, w.z) * delta
	if lightning_enabled and storminess > LIGHTNING_THRESHOLD:
		_next_strike -= delta
		if _next_strike <= 0.0:
			var fury := inverse_lerp(LIGHTNING_THRESHOLD, 1.0, storminess)
			_next_strike = lerpf(16.0, 5.0, fury) * _rng.randf_range(0.4, 1.6)
			strike_lightning(Vector3.ZERO, -1.0, _rng.randf_range(0.6, 1.0))

func _apply_transition(t: float) -> void:
	var k := smoothstep(0.0, 1.0, t)
	storminess = lerpf(_tr_from[0], _tr_to[0], k)
	wind_speed = lerpf(_tr_from[1], _tr_to[1], k)
	wind_heading = fposmod(lerpf(_tr_from[2], _tr_to[2], k), TAU)
	cloudiness = lerpf(_tr_from[3], _tr_to[3], k)

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
