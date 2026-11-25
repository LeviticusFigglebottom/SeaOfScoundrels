extends RefCounted
## The sky's colour script: every colour the sky rig uses, as a pure function of
## sun height, morning/evening, cloud cover and storminess. No nodes, so it can
## be tested and tuned in one place.
##
## Colours are authored in sRGB (what you would pick in a paint program) and
## keyed on the sun's height `h` (sine of elevation, -1..1).

# Key heights: deep night, twilight, sun on the horizon, golden hour, morning, full day.
const KEYS: Array[float] = [-0.32, -0.12, 0.0, 0.22, 0.46, 0.66]

# Rows: one colour per key height. Dusk is gold and ember under deep blue;
# dawn is its own thing: rose and peach under a paler, greener blue, and mistier.
const ZENITH_DUSK: Array[Color] = [
	Color(0.030, 0.055, 0.165), Color(0.055, 0.095, 0.30), Color(0.085, 0.19, 0.50),
	Color(0.09, 0.28, 0.70), Color(0.09, 0.33, 0.82), Color(0.07, 0.30, 0.80)]
const ZENITH_DAWN: Array[Color] = [
	Color(0.030, 0.055, 0.165), Color(0.065, 0.11, 0.31), Color(0.13, 0.25, 0.52),
	Color(0.12, 0.36, 0.72), Color(0.09, 0.34, 0.82), Color(0.07, 0.30, 0.80)]
const MID_DUSK: Array[Color] = [
	Color(0.045, 0.10, 0.27), Color(0.13, 0.19, 0.45), Color(0.34, 0.43, 0.68),
	Color(0.48, 0.68, 0.88), Color(0.27, 0.55, 0.93), Color(0.21, 0.50, 0.92)]
const MID_DAWN: Array[Color] = [
	Color(0.045, 0.10, 0.27), Color(0.20, 0.24, 0.50), Color(0.50, 0.56, 0.76),
	Color(0.56, 0.80, 0.90), Color(0.30, 0.60, 0.93), Color(0.21, 0.50, 0.92)]
const HORIZON_DUSK: Array[Color] = [
	Color(0.085, 0.17, 0.36), Color(0.60, 0.33, 0.28), Color(1.0, 0.60, 0.30),
	Color(1.0, 0.80, 0.48), Color(0.74, 0.88, 0.97), Color(0.62, 0.83, 0.98)]
const HORIZON_DAWN: Array[Color] = [
	Color(0.085, 0.17, 0.36), Color(0.52, 0.38, 0.54), Color(1.0, 0.70, 0.64),
	Color(1.0, 0.88, 0.70), Color(0.78, 0.90, 0.96), Color(0.62, 0.83, 0.98)]
# Extra colour poured along the horizon on the sun's side.
const GLOW_DUSK: Array[Color] = [
	Color(0.45, 0.14, 0.14), Color(0.95, 0.30, 0.10), Color(1.0, 0.46, 0.07),
	Color(1.0, 0.66, 0.18), Color(1.0, 0.85, 0.55), Color(1.0, 0.9, 0.7)]
const GLOW_DAWN: Array[Color] = [
	Color(0.45, 0.14, 0.14), Color(0.84, 0.30, 0.44), Color(1.0, 0.56, 0.42),
	Color(1.0, 0.80, 0.46), Color(1.0, 0.88, 0.62), Color(1.0, 0.9, 0.7)]
const GLOW_STRENGTH: Array[float] = [0.0, 0.85, 1.0, 0.8, 0.22, 0.0]
# Sunlight colour and energy.
const SUN: Array[Color] = [
	Color(1.0, 0.35, 0.15), Color(1.0, 0.38, 0.16), Color(1.0, 0.50, 0.22),
	Color(1.0, 0.72, 0.40), Color(1.0, 0.92, 0.76), Color(1.0, 0.96, 0.86)]
const SUN_DAWN: Array[Color] = [
	Color(1.0, 0.40, 0.30), Color(1.0, 0.46, 0.36), Color(1.0, 0.60, 0.44),
	Color(1.0, 0.82, 0.60), Color(1.0, 0.94, 0.80), Color(1.0, 0.96, 0.86)]
const SUN_ENERGY: Array[float] = [0.0, 0.0, 0.45, 1.1, 1.2, 1.25]
const AMBIENT: Array[Color] = [
	Color(0.15, 0.23, 0.46), Color(0.20, 0.24, 0.46), Color(0.36, 0.35, 0.52),
	Color(0.43, 0.45, 0.58), Color(0.36, 0.48, 0.66), Color(0.34, 0.48, 0.68)]
# Clouds: sunlit side, shaded body, and the rim that faces the sun.
const CLOUD_LIT_DUSK: Array[Color] = [
	Color(0.30, 0.40, 0.62), Color(0.66, 0.40, 0.42), Color(1.0, 0.60, 0.34),
	Color(1.0, 0.84, 0.56), Color(1.0, 0.98, 0.94), Color(1.0, 1.0, 0.98)]
const CLOUD_LIT_DAWN: Array[Color] = [
	Color(0.30, 0.40, 0.62), Color(0.68, 0.46, 0.58), Color(1.0, 0.72, 0.64),
	Color(1.0, 0.91, 0.76), Color(1.0, 0.98, 0.94), Color(1.0, 1.0, 0.98)]
const CLOUD_SHADE: Array[Color] = [
	Color(0.07, 0.11, 0.25), Color(0.13, 0.15, 0.35), Color(0.25, 0.27, 0.50),
	Color(0.36, 0.42, 0.64), Color(0.50, 0.62, 0.84), Color(0.52, 0.64, 0.86)]
const CLOUD_RIM: Array[Color] = [
	Color(0.0, 0.0, 0.0), Color(1.0, 0.35, 0.22), Color(1.0, 0.56, 0.16),
	Color(1.0, 0.86, 0.50), Color(1.0, 0.97, 0.85), Color(1.0, 1.0, 0.95)]

const MOON_LIGHT := Color(0.50, 0.66, 1.0)
const MOON_ENERGY := 0.6
const STORM_ZENITH := Color(0.17, 0.22, 0.23)
const STORM_HORIZON := Color(0.31, 0.38, 0.36)
const STORM_AMBIENT := Color(0.34, 0.42, 0.39)
const STORM_CLOUD_LIT := Color(0.46, 0.53, 0.50)
const STORM_CLOUD_SHADE := Color(0.15, 0.20, 0.19)
const STORM_SUN := Color(0.72, 0.84, 0.78)
const FLASH := Color(0.80, 0.86, 1.0)


static func _sample(row: Array[Color], h: float) -> Color:
	if h <= KEYS[0]:
		return row[0]
	for i in range(1, KEYS.size()):
		if h < KEYS[i]:
			var t := smoothstep(0.0, 1.0, (h - KEYS[i - 1]) / (KEYS[i] - KEYS[i - 1]))
			return row[i - 1].lerp(row[i], t)
	return row[KEYS.size() - 1]

static func _sample_f(row: Array[float], h: float) -> float:
	if h <= KEYS[0]:
		return row[0]
	for i in range(1, KEYS.size()):
		if h < KEYS[i]:
			var t := smoothstep(0.0, 1.0, (h - KEYS[i - 1]) / (KEYS[i] - KEYS[i - 1]))
			return lerpf(row[i - 1], row[i], t)
	return row[KEYS.size() - 1]


## Returns every colour for the frame. `sun_h` and `moon_h` are sines of
## elevation, `evening` is 0 in the morning and 1 in the evening, `moon_lit` is
## the lit fraction of the moon's disc (0..1), `cover` is cloud cover and
## `storm` is storminess. All Colors are sRGB; energies are plain multipliers.
static func compute(sun_h: float, moon_h: float, evening: float, moon_lit: float,
		cover: float, storm: float) -> Dictionary:
	var p := {}
	var zenith := _sample(ZENITH_DAWN, sun_h).lerp(_sample(ZENITH_DUSK, sun_h), evening)
	var mid := _sample(MID_DAWN, sun_h).lerp(_sample(MID_DUSK, sun_h), evening)
	var horizon := _sample(HORIZON_DAWN, sun_h).lerp(_sample(HORIZON_DUSK, sun_h), evening)
	var glow := _sample(GLOW_DAWN, sun_h).lerp(_sample(GLOW_DUSK, sun_h), evening)
	var ambient := _sample(AMBIENT, sun_h)
	var sun_col := _sample(SUN_DAWN, sun_h).lerp(_sample(SUN, sun_h), evening)
	var sun_energy := _sample_f(SUN_ENERGY, sun_h)
	var cloud_lit := _sample(CLOUD_LIT_DAWN, sun_h).lerp(_sample(CLOUD_LIT_DUSK, sun_h), evening)
	var cloud_shade := _sample(CLOUD_SHADE, sun_h)
	var cloud_rim := _sample(CLOUD_RIM, sun_h)

	# How bright the world is: storms are darker by day, and nights stay readable.
	var day := smoothstep(-0.15, 0.22, sun_h)
	var night := 1.0 - smoothstep(-0.3, -0.04, sun_h)
	# Overcast swallows the blue; storms add the green-grey cast and dim everything.
	var grey := smoothstep(0.55, 1.0, cover) * 0.85
	var gloom := smoothstep(0.0, 1.0, storm)
	var storm_level := lerpf(0.42, 1.0, day) * lerpf(1.0, 0.78, gloom)
	# Storm greys lean blue at night so a stormy night is still a blue night.
	var storm_tint := Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.85, 1.35), 1.0 - day)
	zenith = zenith.lerp(STORM_ZENITH * storm_tint * storm_level, grey)
	mid = mid.lerp(STORM_ZENITH.lerp(STORM_HORIZON, 0.45) * storm_tint * storm_level, grey)
	horizon = horizon.lerp(STORM_HORIZON * storm_tint * storm_level, grey * 0.92)
	var glow_strength := _sample_f(GLOW_STRENGTH, sun_h) * (1.0 - grey * 0.85)
	ambient = ambient.lerp(STORM_AMBIENT * storm_tint * storm_level, grey * 0.9)
	cloud_lit = cloud_lit.lerp(STORM_CLOUD_LIT * storm_tint * storm_level, grey * lerpf(0.55, 1.0, gloom))
	cloud_shade = cloud_shade.lerp(STORM_CLOUD_SHADE * storm_tint * lerpf(0.6, 1.0, day), gloom * 0.9 + grey * 0.1)
	cloud_rim = cloud_rim * (1.0 - grey)
	# Direct light: the cloud shadow at the camera does the dimming under cloud
	# (see sky_rig.gd); here only the storm's own murk, and its greenish cast.
	var direct := lerpf(1.0, 0.6, gloom)
	sun_col = sun_col.lerp(STORM_SUN, grey * 0.8)

	var moon_up := smoothstep(-0.06, 0.12, moon_h)
	var moon_energy := MOON_ENERGY * night * moon_up * lerpf(0.55, 1.0, moon_lit) * direct
	# Moonlit cloud edges at night.
	cloud_rim = cloud_rim + Color(0.45, 0.58, 0.85) * (night * moon_up * (1.0 - grey) * 0.8)

	p["zenith"] = zenith
	p["mid"] = mid
	p["horizon"] = horizon
	p["glow"] = glow
	p["glow_strength"] = glow_strength
	p["sun_halo"] = sun_col
	p["ambient"] = ambient
	p["ambient_energy"] = lerpf(1.0, 0.9, gloom)
	p["sun_color"] = sun_col
	p["sun_energy"] = sun_energy * direct
	p["sun_disc"] = _sample(SUN_DAWN, sun_h).lerp(_sample(SUN, sun_h), evening).lerp(
			Color(1.0, 0.97, 0.9), smoothstep(0.0, 0.4, sun_h))
	p["moon_color"] = MOON_LIGHT
	p["moon_energy"] = moon_energy
	p["cloud_lit"] = cloud_lit
	p["cloud_shade"] = cloud_shade
	p["cloud_rim"] = cloud_rim
	# Storm cloud colours on their own, for a storm cell seen from fair weather.
	p["storm_cloud_lit"] = STORM_CLOUD_LIT * storm_tint * storm_level
	p["storm_cloud_shade"] = STORM_CLOUD_SHADE * storm_tint * lerpf(0.6, 1.0, day)
	# Light shafts under broken cloud: strongest with a low sun, gone under overcast.
	p["ray_strength"] = day * (1.0 - grey) * lerpf(0.5, 0.22, smoothstep(0.1, 0.6, sun_h))
	p["star_intensity"] = night * (1.0 - grey)
	p["night"] = night
	p["day"] = day
	p["flash_color"] = FLASH
	# Visibility: kilometres on a clear day, a few hundred metres in a storm.
	# Mornings are mistier than evenings.
	var morning_mist := (1.0 - evening) * smoothstep(-0.2, 0.0, sun_h) * (1.0 - smoothstep(0.1, 0.4, sun_h))
	p["fog_density"] = lerpf(0.00016, 0.0024, pow(gloom, 1.6)) + grey * 0.0003 + morning_mist * 0.00016
	# Clouds are bigger and brighter than islands: they fade over a longer distance,
	# and a storm deck must stay dark overhead instead of dissolving into murk.
	p["cloud_fog"] = float(p["fog_density"]) * lerpf(0.4, 0.1, gloom)
	return p
