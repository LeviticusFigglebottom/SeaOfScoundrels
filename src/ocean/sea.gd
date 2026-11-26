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
	# primary ocean swell (>= 100 m): chunky rolling swells that beat into sets
	# of big waves and lulls even in fair weather
	[221.0, 0.22, 1.80, 0.28, 1.00],
	[163.0, 0.30, 1.54, 0.45, 1.02],
	[127.0, 0.34, 1.24, 0.14, 1.08],
	[103.0, 0.34, 0.95, 0.56, 1.15],
	# crossing swell (>= 100 m): builds chunky 3D peaks and hollows
	[149.0, 0.17, 0.88, -0.78, 1.02],
	[107.0, 0.20, 0.76, -0.52, 1.10],
	# secondary waves and lively wind chop riding on top of the big swells
	[73.0, 0.205, 0.58, 1.05, 1.22],
	[57.0, 0.165, 0.46, 0.60, 1.24],
	[45.0, 0.088, 0.39, 1.45, 1.22],
	[35.0, 0.130, 0.295, -0.95, 1.24],
	[27.5, 0.110, 0.230, 1.72, 1.22],
	[21.3, 0.092, 0.175, 0.38, 1.20],
	[16.3, 0.075, 0.135, -1.25, 1.18],
	[12.7, 0.060, 0.102, 0.08, 1.14],
	[9.7, 0.048, 0.076, 1.58, 1.10],
	[7.3, 0.036, 0.056, -0.68, 1.06],
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
var _dx: PackedFloat64Array = PackedFloat64Array()     # dir.x * k
var _dz: PackedFloat64Array = PackedFloat64Array()     # dir.z * k
var _hx: PackedFloat64Array = PackedFloat64Array()     # dir.x * horizontal amplitude
var _hz: PackedFloat64Array = PackedFloat64Array()     # dir.z * horizontal amplitude
var _amp: PackedFloat64Array = PackedFloat64Array()    # vertical amplitude now
var _ph: PackedFloat64Array = PackedFloat64Array()     # phase - omega * time
var _jxx: PackedFloat64Array = PackedFloat64Array()    # dir.x * dir.x * k * amp * steepness
var _jzz: PackedFloat64Array = PackedFloat64Array()    # dir.z * dir.z * k * amp * steepness
var _jxz: PackedFloat64Array = PackedFloat64Array()    # dir.x * dir.z * k * amp * steepness
var _vx: PackedFloat64Array = PackedFloat64Array()     # dir.x * omega * amp * steepness
var _vz: PackedFloat64Array = PackedFloat64Array()     # dir.z * omega * amp * steepness
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
	for arr: PackedFloat64Array in [_dx, _dz, _hx, _hz, _amp, _ph, _jxx, _jzz, _jxz, _vx, _vz]:
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
			var h_amp := amp * a.w
			var ka_st := a.z * h_amp
			_amp[i] = amp
			_dx[i] = a.x * a.z
			_dz[i] = a.y * a.z
			_hx[i] = a.x * h_amp
			_hz[i] = a.y * h_amp
			_jxx[i] = a.x * a.x * ka_st
			_jzz[i] = a.y * a.y * ka_st
			_jxz[i] = a.x * a.y * ka_st
			_vx[i] = a.x * b.y * h_amp
			_vz[i] = a.y * b.y * h_amp
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

## Fast combined Gerstner displacement (xyz) and surface Jacobian determinant (w)
## for a rest-plane point (x, z). Used by crest spray and foam queries.
func displacement_and_jacobian(x: float, z: float) -> Vector4:
	_refresh()
	var ox := 0.0
	var oy := 0.0
	var oz := 0.0
	var dxx := 1.0
	var dzz := 1.0
	var dxz := 0.0
	for i in _count:
		var th := _dx[i] * x + _dz[i] * z + _ph[i]
		var sn := sin(th)
		var cs := cos(th)
		ox -= _hx[i] * sn
		oz -= _hz[i] * sn
		oy += _amp[i] * cs
		dxx -= _jxx[i] * cs
		dzz -= _jzz[i] * cs
		dxz -= _jxz[i] * cs
	return Vector4(ox, oy, oz, dxx * dzz - dxz * dxz)

## Horizontal Gerstner orbital velocity d/dt(displacement.xz) (m/s) of rest point (x, z).
## Mirrors `flow_vel` in waves.gdshaderinc.
func orbital_velocity(x: float, z: float) -> Vector2:
	_refresh()
	var vx := 0.0
	var vz := 0.0
	for i in _count:
		var cs := cos(_dx[i] * x + _dz[i] * z + _ph[i])
		vx += _vx[i] * cs
		vz += _vz[i] * cs
	return Vector2(vx, vz)

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
