extends Node
## THE shared wave function. Autoloaded as `Sea`.
##
## One set of Gerstner waves drives both the ocean shader (see
## waves.gdshaderinc, which implements the identical maths) and all CPU-side
## queries (buoyancy, swimmers, AI, spawning). What you see is what floats.
##
## Rules:
##  * Anything that displaces geometry in the shader MUST exist here too.
##    The shader may add normal-only micro detail, nothing with real height.
##  * Wave directions are fixed world constants. Rotating a Gerstner wave's
##    direction makes the whole pattern sweep sideways far from the origin, so
##    weather only ever changes amplitudes (through `amp_scale`), never direction.
##  * `time` is the only clock. It is advanced by the host and will be
##    replicated to clients; never use engine time for waves.

const GRAVITY := 9.81
const MAX_WAVES := 32

## Wave table: wavelength (m), calm amplitude (m), storm amplitude (m), heading
## (rad, direction of travel, 0 = towards -Z), steepness (horizontal pinch
## relative to the amplitude; 1 = classic Gerstner, more = choppier crests).
##
## Each wave has its own calm and storm amplitude, so the sea changes character
## with the weather instead of just scaling: calm is a long, low ocean swell
## that is almost glassy between crests; a storm keeps that swell (grown to
## several metres), adds a crossing swell, and piles a steep, short-crested wind
## sea on top from a third direction, which is what makes it look chaotic.
##
## Constraint: sum(k * storm amplitude * steepness) must stay < 1 or crests
## loop over themselves (tests/test_sea.gd checks this).
## Waves shorter than about 7 m carry centimetres of height; they live in the
## ocean shader as normal-only detail and are deliberately not listed here.
const WAVE_TABLE: Array[Array] = [
	# primary ocean swell: four wavelengths within ~25 degrees, so they beat
	# into sets of big waves and lulls
	[263.0, 0.36, 1.85, 0.30, 1.00],
	[191.0, 0.28, 1.55, 0.47, 1.00],
	[139.0, 0.18, 1.20, 0.16, 1.05],
	[101.0, 0.11, 0.90, 0.58, 1.10],
	# crossing swell from an old, distant blow
	[173.0, 0.12, 0.90, -0.80, 1.00],
	[113.0, 0.08, 0.75, -0.55, 1.00],
	# wind sea: steep, wide directional spread
	[79.0, 0.110, 0.62, 1.05, 1.20],
	[61.0, 0.088, 0.50, 0.62, 1.20],
	[47.0, 0.070, 0.40, 1.45, 1.20],
	[37.0, 0.056, 0.32, 0.85, 1.20],
	[29.0, 0.045, 0.25, 1.75, 1.15],
	[22.5, 0.036, 0.195, 0.40, 1.15],
	[17.3, 0.028, 0.150, 1.25, 1.15],
	[13.3, 0.022, 0.115, 0.05, 1.10],
	[10.1, 0.017, 0.088, 1.60, 1.05],
	[7.7, 0.013, 0.066, 0.75, 1.00],
]

## `amp_scale` runs from AMP_CALM (the calm column of the table) to AMP_STORM
## (the storm column), blended by Weather.storminess. Values outside the range
## scale the nearest column (so amp_scale = 0 is a flat sea).
const AMP_CALM := 0.65
const AMP_STORM := 2.6

## Seconds of wave time. Host-owned.
var time: float = 0.0
## Current sea state (smoothed), AMP_CALM..AMP_STORM. See above.
var amp_scale: float = 1.0

# Packed per-wave data, mirrored to shaders:
#   _wa[i] = (dir.x, dir.z, k, steepness)
#   _wb[i] = (calm amplitude, omega, phase, storm amplitude)
var _wa: PackedVector4Array = PackedVector4Array()
var _wb: PackedVector4Array = PackedVector4Array()
var _count: int = 0
var _materials: Array[WeakRef] = []

# Flat per-wave arrays for the CPU hot path (see _refresh()).
var _dx: PackedFloat64Array = PackedFloat64Array()   # dir.x * k
var _dz: PackedFloat64Array = PackedFloat64Array()   # dir.z * k
var _hx: PackedFloat64Array = PackedFloat64Array()   # dir.x * horizontal amplitude
var _hz: PackedFloat64Array = PackedFloat64Array()   # dir.z * horizontal amplitude
var _amp: PackedFloat64Array = PackedFloat64Array()  # vertical amplitude now
var _ph: PackedFloat64Array = PackedFloat64Array()   # phase - omega * time
var _cache_amp: float = -1.0
var _cache_time: float = -INF

func _enter_tree() -> void:
	_build()

func _build() -> void:
	_wa.clear()
	_wb.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EA5C0
	for w in WAVE_TABLE:
		var k: float = TAU / float(w[0])
		var heading: float = w[3]
		var dir := Vector2(sin(heading), -cos(heading))
		_wa.append(Vector4(dir.x, dir.y, k, float(w[4])))
		_wb.append(Vector4(float(w[1]), sqrt(GRAVITY * k), rng.randf() * TAU, float(w[2])))
	_count = _wa.size()
	while _wa.size() < MAX_WAVES:
		_wa.append(Vector4.ZERO)
		_wb.append(Vector4.ZERO)
	for arr: PackedFloat64Array in [_dx, _dz, _hx, _hz, _amp, _ph]:
		arr.resize(_count)
	_cache_amp = -1.0
	_cache_time = -INF

func _physics_process(delta: float) -> void:
	if Net.is_host():
		time += delta
	var target := lerpf(AMP_CALM, AMP_STORM, clampf(Weather.storminess, 0.0, 1.0))
	amp_scale = move_toward(amp_scale, target, delta * 0.08)

func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set(&"sea_time", time)
	RenderingServer.global_shader_parameter_set(&"sea_amp_scale", amp_scale)

## Give a ShaderMaterial that includes waves.gdshaderinc the wave table.
func bind_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"sea_wave_a", _wa)
	mat.set_shader_parameter(&"sea_wave_b", _wb)
	mat.set_shader_parameter(&"sea_wave_count", _count)
	mat.set_shader_parameter(&"sea_amp_range", Vector2(AMP_CALM, AMP_STORM))
	_materials.append(weakref(mat))

## 0 in a calm, 1 in a full storm (where `amp_scale` sits in its range).
func sea_state() -> float:
	return clampf(inverse_lerp(AMP_CALM, AMP_STORM, amp_scale), 0.0, 1.0)

## Vertical amplitude (m) of wave `i` in the current sea state.
func wave_amplitude(i: int) -> float:
	_refresh()
	return _amp[i]

## Significant wave height (m, roughly the height of the larger waves) now.
func significant_height() -> float:
	_refresh()
	var s := 0.0
	for a in _amp:
		s += a * a
	return 4.0 * sqrt(s * 0.5)

# Recompute the per-wave working arrays when the sea state or time changed.
func _refresh() -> void:
	if amp_scale != _cache_amp:
		_cache_amp = amp_scale
		var c := clampf(amp_scale, AMP_CALM, AMP_STORM)
		var blend := (c - AMP_CALM) / (AMP_STORM - AMP_CALM)
		var ext := amp_scale / c
		for i in _count:
			var a := _wa[i]
			var b := _wb[i]
			var amp := lerpf(b.x, b.w, blend) * ext
			_amp[i] = amp
			_dx[i] = a.x * a.z
			_dz[i] = a.y * a.z
			_hx[i] = a.x * amp * a.w
			_hz[i] = a.y * amp * a.w
	if time != _cache_time:
		_cache_time = time
		for i in _count:
			var b := _wb[i]
			_ph[i] = b.z - b.y * time

## Gerstner displacement of the rest-plane point (x, z) at the current time.
func displacement(x: float, z: float) -> Vector3:
	_refresh()
	var ox := 0.0
	var oy := 0.0
	var oz := 0.0
	for i in _count:
		var th := _dx[i] * x + _dz[i] * z + _ph[i]
		var sn := sin(th)
		ox -= _hx[i] * sn
		oz -= _hz[i] * sn
		oy += _amp[i] * cos(th)
	return Vector3(ox, oy, oz)

## Water surface height (world Y) above the world-space point (x, z).
## Inverts the horizontal Gerstner displacement with a few fixed-point steps
## (4 steps: worst-case error about 0.1 m on the steepest storm crests,
## millimetres otherwise). waves.gdshaderinc uses the same step count.
func height(x: float, z: float) -> float:
	_refresh()
	var px := x
	var pz := z
	var n := _count
	for _i in 4:
		var ox := 0.0
		var oz := 0.0
		for i in n:
			var sn := sin(_dx[i] * px + _dz[i] * pz + _ph[i])
			ox -= _hx[i] * sn
			oz -= _hz[i] * sn
		px = x - ox
		pz = z - oz
	var h := 0.0
	for i in n:
		h += _amp[i] * cos(_dx[i] * px + _dz[i] * pz + _ph[i])
	return h

func height_at(p: Vector3) -> float:
	return height(p.x, p.z)

## Rest-plane point whose displaced position lies above world (x, z): the
## water "particle" currently under that spot. Foam and wakes are stored in
## these coordinates so they ride the waves.
func rest_point(x: float, z: float) -> Vector2:
	_refresh()
	var px := x
	var pz := z
	for _i in 4:
		var ox := 0.0
		var oz := 0.0
		for i in _count:
			var sn := sin(_dx[i] * px + _dz[i] * pz + _ph[i])
			ox -= _hx[i] * sn
			oz -= _hz[i] * sn
		px = x - ox
		pz = z - oz
	return Vector2(px, pz)

## Surface normal at world (x, z) by central differences.
func normal(x: float, z: float, eps: float = 0.4) -> Vector3:
	var hx := height(x + eps, z) - height(x - eps, z)
	var hz := height(x, z + eps) - height(x, z - eps)
	return Vector3(-hx, 2.0 * eps, -hz).normalized()

## Depth of a world point below the surface (positive = submerged).
func depth(p: Vector3) -> float:
	return height(p.x, p.z) - p.y
