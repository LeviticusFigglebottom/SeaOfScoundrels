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
##    weather only ever changes amplitude (`amp_scale`), never direction.
##  * `time` is the only clock. It is advanced by the host and will be
##    replicated to clients; never use engine time for waves.

const GRAVITY := 9.81
const MAX_WAVES := 12

## Wave table: wavelength (m), amplitude (m, at amp_scale 1), heading (rad,
## direction of travel, 0 = towards -Z), steepness (horizontal pinch relative
## to the amplitude; 1 = classic Gerstner, more = choppier crests).
## Constraint: sum(k * amplitude * steepness) * max amp_scale must stay < 1 or
## crests loop over themselves (tests/test_sea.gd checks this).
##
## Shape: a long primary swell train (three wavelengths within ~30 degrees, so
## they beat into sets of big waves and lulls), a crossing secondary swell, and
## wind sea filling in below. Amplitude is roughly proportional to wavelength,
## so the energy sits in the long waves: the sea reads as large, not as ripples.
const WAVE_TABLE: Array[Array] = [
	[211.0, 1.10, 0.30, 1.15],
	[149.0, 0.74, 0.58, 1.15],
	[103.0, 0.50, 0.08, 1.20],
	[71.0, 0.34, 0.80, 1.20],
	[47.0, 0.22, -0.28, 1.20],
	[31.0, 0.145, 1.05, 1.15],
	[21.0, 0.095, -0.62, 1.10],
	[14.0, 0.062, 0.42, 1.05],
	[9.1, 0.039, 1.45, 0.95],
	[6.1, 0.025, -1.02, 0.90],
	[4.3, 0.016, 0.92, 0.80],
	[3.1, 0.010, -0.20, 0.70],
]

## Calm-to-storm amplitude multipliers, blended by Weather.storminess.
## Calm: a gentle long swell about 1 m high. Storm: 6 to 12 m seas.
const AMP_CALM := 0.5
const AMP_STORM := 2.6

## Seconds of wave time. Host-owned.
var time: float = 0.0
## Current global amplitude multiplier (smoothed).
var amp_scale: float = 1.0

# Packed per-wave data, mirrored to shaders:
#   _wa[i] = (dir.x, dir.z, k, amplitude)
#   _wb[i] = (horizontal_amplitude, omega, phase, 0)
var _wa: PackedVector4Array = PackedVector4Array()
var _wb: PackedVector4Array = PackedVector4Array()
var _count: int = 0
var _materials: Array[WeakRef] = []

func _enter_tree() -> void:
	_build()

func _build() -> void:
	_wa.clear()
	_wb.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EA5C0
	for w in WAVE_TABLE:
		var k: float = TAU / float(w[0])
		var amp: float = w[1]
		var heading: float = w[2]
		var dir := Vector2(sin(heading), -cos(heading))
		_wa.append(Vector4(dir.x, dir.y, k, amp))
		_wb.append(Vector4(amp * float(w[3]), sqrt(GRAVITY * k), rng.randf() * TAU, 0.0))
	_count = _wa.size()
	while _wa.size() < MAX_WAVES:
		_wa.append(Vector4.ZERO)
		_wb.append(Vector4.ZERO)

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
	_materials.append(weakref(mat))

## Gerstner displacement of the rest-plane point (x, z) at the current time.
func displacement(x: float, z: float) -> Vector3:
	var d := Vector3.ZERO
	var t := time
	var s := amp_scale
	for i in _count:
		var a := _wa[i]
		var b := _wb[i]
		var th := a.z * (a.x * x + a.y * z) - b.y * t + b.z
		var sn := sin(th)
		d.x -= a.x * b.x * sn
		d.z -= a.y * b.x * sn
		d.y += a.w * cos(th)
	return d * s

## Water surface height (world Y) above the world-space point (x, z).
## Inverts the horizontal Gerstner displacement with a few fixed-point steps.
func height(x: float, z: float) -> float:
	var px := x
	var pz := z
	var d := Vector3.ZERO
	for _i in 3:
		d = displacement(px, pz)
		px = x - d.x
		pz = z - d.z
	return displacement(px, pz).y

func height_at(p: Vector3) -> float:
	return height(p.x, p.z)

## Surface normal at world (x, z) by central differences.
func normal(x: float, z: float, eps: float = 0.4) -> Vector3:
	var hx := height(x + eps, z) - height(x - eps, z)
	var hz := height(x, z + eps) - height(x, z - eps)
	return Vector3(-hx, 2.0 * eps, -hz).normalized()

## Depth of a world point below the surface (positive = submerged).
func depth(p: Vector3) -> float:
	return height(p.x, p.z) - p.y
