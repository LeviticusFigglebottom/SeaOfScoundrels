extends Node
## Global weather + time-of-day state (host-authoritative, replicated later).
## Everything that cares about wind, storms or the sun reads from here.

## Hours, 0..24. 6 = sunrise, 12 = noon, 18 = sunset.
var time_of_day: float = 10.0
## Real seconds per in-game day. 0 freezes time.
var day_length_seconds: float = 1440.0
## Direction the wind blows TOWARDS, radians around +Y; 0 = towards -Z (north).
var wind_heading: float = 0.6
## Wind speed in m/s. ~4 light breeze, ~9 fresh, ~18 gale.
var wind_speed: float = 8.0
## 0 = clear and calm, 1 = full storm. Drives waves, clouds, rain, lighting.
var storminess: float = 0.0

func wind_vector() -> Vector3:
	## World-space wind velocity (m/s), horizontal.
	return Vector3(sin(wind_heading), 0.0, -cos(wind_heading)) * wind_speed

func sun_direction() -> Vector3:
	## Unit vector pointing FROM the scene TOWARDS the sun.
	var a := (time_of_day - 6.0) / 24.0 * TAU
	return Vector3(cos(a), sin(a), 0.35).normalized()

func _physics_process(delta: float) -> void:
	if day_length_seconds > 0.0 and Net.is_host():
		time_of_day = fposmod(time_of_day + delta * 24.0 / day_length_seconds, 24.0)
