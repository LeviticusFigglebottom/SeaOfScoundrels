class_name WindRibbons
extends Node3D
## 3D airborne Sea-of-Thieves wind stream ribbons mounted above the player ship.
##
## Renders 14 translucent wispy cream-white sculpted ribbons in a single draw call
## (`MultiMeshInstance3D` + custom `SurfaceTool` `ArrayMesh`, zero raw PrimitiveMeshes)
## gliding smoothly along `Weather.wind_vector()` through a 38 m dome around and
## above the sails (`y = 4.5 .. 17.0 m`), fading cleanly at start/end of travel and
## scaling speed & visibility with `Weather.wind_speed`.

const RIBBON_COUNT := 14
const DOME_DIAMETER := 38.0
const DOME_HALF_SPAN := DOME_DIAMETER * 0.5
const LATERAL_HALF_SPAN := 16.5
const MIN_ALT_Y := 4.5
const MAX_ALT_Y := 17.0
const RIBBON_SEGS := 14
const RIBBON_LENGTH := 7.4
const RIBBON_HALF_WIDTH := 0.145

static var _active_instances: int = 0
static var _ribbon_mesh: ArrayMesh = null
static var _ribbon_shader: Shader = null

var _mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _mat: ShaderMaterial = null
var _clock: float = 0.0
var _wind_dir: Vector3 = Vector3.FORWARD

# Per-ribbon deterministic lanes: {u, lat, alt, phase, length_scale, speed_scale, roll}.
var _lanes: Array[Dictionary] = []
var _ribbon_world_xforms: Array[Transform3D] = []


## Release all statically cached ribbon mesh and shader resources cleanly.
static func clear_shared_cache() -> void:
	_ribbon_mesh = null
	_ribbon_shader = null


func _enter_tree() -> void:
	_active_instances += 1


func _ready() -> void:
	_ensure_shared_assets()
	_init_lanes()

	_mat = ShaderMaterial.new()
	_mat.shader = _ribbon_shader
	_mat.set_shader_parameter(&"wind_time", 0.0)
	_mat.set_shader_parameter(&"ribbon_color", Color(0.97, 0.96, 0.91))

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.instance_count = RIBBON_COUNT
	_mm.mesh = _ribbon_mesh

	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "WindRibbonsMultiMesh"
	_mmi.multimesh = _mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mmi.custom_aabb = AABB(Vector3(-46.0, -4.0, -46.0), Vector3(92.0, 32.0, 92.0))
	add_child(_mmi)

	_step_ribbons(0.0)


func _exit_tree() -> void:
	if _mmi != null and is_instance_valid(_mmi):
		_mmi.material_override = null
		_mmi.multimesh = null
	if _mm != null:
		_mm.instance_count = 0
		_mm.mesh = null
	_mmi = null
	_mm = null
	_mat = null
	_lanes.clear()
	_ribbon_world_xforms.clear()
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


func _process(delta: float) -> void:
	_step_ribbons(delta)


## Return the single-draw-call MultiMeshInstance3D rendering all wind ribbons.
func get_multimesh_instance() -> MultiMeshInstance3D:
	return _mmi


## Return the number of active airborne wind ribbons.
func get_ribbon_count() -> int:
	return _mm.instance_count if _mm != null else 0


## Return the latest horizontal world-space unit wind direction tracked by the ribbons.
func get_wind_direction() -> Vector3:
	return _wind_dir


## Return the world-space forward (-Z) direction of ribbon instance `idx`.
func get_ribbon_forward_world(idx: int = 0) -> Vector3:
	if idx >= 0 and idx < _ribbon_world_xforms.size():
		var fwd := -_ribbon_world_xforms[idx].basis.z
		if fwd.length_squared() > 1e-6:
			return fwd.normalized()
	return _wind_dir


func _init_lanes() -> void:
	_lanes.clear()
	_ribbon_world_xforms.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x571D26A
	for i in RIBBON_COUNT:
		var frac := (float(i) + 0.5) / float(RIBBON_COUNT)
		# Stratified height & lateral spread across the 38 m dome so wind reads from every angle.
		var alt := lerpf(MIN_ALT_Y, MAX_ALT_Y, fmod(frac * 1.6180339 + rng.randf_range(-0.08, 0.08), 1.0))
		alt = clampf(alt, MIN_ALT_Y, MAX_ALT_Y)
		var lat := lerpf(-LATERAL_HALF_SPAN, LATERAL_HALF_SPAN, frac) + rng.randf_range(-2.0, 2.0)
		lat = clampf(lat, -LATERAL_HALF_SPAN, LATERAL_HALF_SPAN)
		_lanes.append({
			"u": fmod(float(i) / float(RIBBON_COUNT) + rng.randf_range(0.0, 0.14), 1.0),
			"lat": lat,
			"alt": alt,
			"phase": rng.randf_range(0.0, TAU),
			"length_scale": rng.randf_range(0.78, 1.32),
			"speed_scale": rng.randf_range(0.84, 1.22),
			"roll": rng.randf_range(-0.28, 0.28),
		})
		_ribbon_world_xforms.append(Transform3D.IDENTITY)


func _step_ribbons(delta: float) -> void:
	if _mmi == null or _mm == null or _mat == null:
		return
	var wind_vec := Weather.wind_vector()
	var horiz := Vector3(wind_vec.x, 0.0, wind_vec.z)
	var wind_spd := horiz.length()
	if wind_spd < 0.15:
		var mean_w := Weather.mean_wind_vector()
		var mean_h := Vector3(mean_w.x, 0.0, mean_w.z)
		if mean_h.length_squared() > 0.01:
			_wind_dir = mean_h.normalized()
	else:
		_wind_dir = horiz / wind_spd

	var eff_spd := maxf(wind_spd, Weather.wind_speed)
	var speed_norm := clampf((eff_spd - 2.0) / 18.0, 0.0, 1.0)
	# Travel rate across the 38 m dome scales smoothly with wind speed.
	var travel_mps := lerpf(5.8, 18.5, speed_norm)
	var vis_alpha := clampf(lerpf(0.18, 0.56, speed_norm), 0.0, 0.60)
	if wind_spd < 0.25 and Weather.wind_speed < 0.25:
		vis_alpha = 0.0

	_clock += delta * lerpf(0.85, 2.35, speed_norm)
	_mat.set_shader_parameter(&"wind_time", _clock)

	# World-space upright wind frame: -Z points strictly along live wind direction, +Y up, +X right.
	var wind_right := _wind_dir.cross(Vector3.UP)
	if wind_right.length_squared() < 1e-6:
		wind_right = Vector3.RIGHT
	else:
		wind_right = wind_right.normalized()
	var wind_basis := Basis(wind_right, Vector3.UP, -_wind_dir)

	var ship_origin := global_position if is_inside_tree() else Vector3.ZERO
	var inv_self := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY

	for i in RIBBON_COUNT:
		var lane: Dictionary = _lanes[i]
		var u: float = float(lane["u"])
		if delta > 0.0:
			var du := (travel_mps * float(lane["speed_scale"]) / DOME_DIAMETER) * delta
			u = fposmod(u + du, 1.0)
			lane["u"] = u

		# Smooth fade-in at start (0.0..0.22) and fade-out at end (0.76..1.0) of travel lifecycle.
		var fade_in := smoothstep(0.0, 0.22, u)
		var fade_out := smoothstep(1.0, 0.76, u)
		var life_fade := fade_in * fade_out

		var along := lerpf(-DOME_HALF_SPAN, DOME_HALF_SPAN, u)
		var lat := float(lane["lat"]) + sin(_clock * 0.65 + float(lane["phase"])) * 0.85
		var alt := float(lane["alt"]) + cos(_clock * 0.55 + float(lane["phase"])) * 0.45
		var world_pos := ship_origin + _wind_dir * along + wind_right * lat + Vector3.UP * alt

		var len_sc := float(lane["length_scale"]) * lerpf(0.86, 1.38, speed_norm)
		var roll_b := Basis(Vector3.FORWARD, float(lane["roll"]))
		var sc_b := Basis.from_scale(Vector3(1.0, 1.0, len_sc))
		var world_xf := Transform3D(wind_basis * roll_b * sc_b, world_pos)
		_ribbon_world_xforms[i] = world_xf
		_mm.set_instance_transform(i, inv_self * world_xf)
		_mm.set_instance_custom_data(i, Color(life_fade, float(lane["phase"]), speed_norm, vis_alpha))


# ==============================================================================
# Shared Sculpted 14-Segment Sinusoidal Ribbon ArrayMesh & Alpha Shader
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _ribbon_mesh == null:
		_ribbon_mesh = _build_ribbon_mesh()
	if _ribbon_shader == null:
		_ribbon_shader = _build_ribbon_shader()


static func _build_ribbon_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sculpt twin crossed 14-segment sinusoidal tapered ribbon vanes (+32 deg & -58 deg)
	# so every airborne wind streak reads cleanly both looking up from the deck and side-on!
	var vane_angles: Array[float] = [deg_to_rad(18.0), deg_to_rad(-72.0)]
	var vane_widths: Array[float] = [RIBBON_HALF_WIDTH, RIBBON_HALF_WIDTH * 0.78]
	for vi in vane_angles.size():
		_append_sinusoidal_ribbon_vane(st, vane_angles[vi], vane_widths[vi])

	st.generate_normals()
	return st.commit()


static func _append_sinusoidal_ribbon_vane(st: SurfaceTool, roll_angle: float, max_half_w: float) -> void:
	var half_len := RIBBON_LENGTH * 0.5
	var side_dir := Vector3(cos(roll_angle), sin(roll_angle), 0.0)
	var col_tail := Color(0.88, 0.93, 0.96, 1.0)
	var col_core := Color(1.00, 0.99, 0.96, 1.0)

	var left_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	var cols: Array[Color] = []
	var ts: Array[float] = []

	for i in RIBBON_SEGS + 1:
		var t := float(i) / float(RIBBON_SEGS)
		# Local -Z runs forward along wind travel direction (t=0 tail at +half_len -> t=1 tip at -half_len).
		var z := lerpf(half_len, -half_len, t)
		var taper := pow(sin(PI * t), 0.72)
		var hw := maxf(max_half_w * taper, 0.004)
		# Graceful subtle S-curve wave sculpted into the rest geometry.
		var cx := sin(t * TAU * 1.1) * 0.16 * taper
		var cy := sin(t * TAU * 0.8 + 0.65) * 0.11 * taper
		var center := Vector3(cx, cy, z)
		left_pts.append(center - side_dir * hw)
		right_pts.append(center + side_dir * hw)
		cols.append(col_tail.lerp(col_core, smoothstep(0.0, 0.55, t)))
		ts.append(t)

	for i in RIBBON_SEGS:
		var l0 := left_pts[i]
		var r0 := right_pts[i]
		var l1 := left_pts[i + 1]
		var r1 := right_pts[i + 1]
		var t0 := ts[i]
		var t1 := ts[i + 1]
		var c0 := cols[i]
		var c1 := cols[i + 1]

		_emit_ribbon_tri(st, l0, r0, r1, c0, c0, c1, Vector2(t0, 0.0), Vector2(t0, 1.0), Vector2(t1, 1.0))
		_emit_ribbon_tri(st, l0, r1, l1, c0, c1, c1, Vector2(t0, 0.0), Vector2(t1, 1.0), Vector2(t1, 0.0))


static func _emit_ribbon_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-12:
		return
	st.set_smooth_group(1)
	st.set_color(ca)
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_smooth_group(1)
	st.set_color(cb)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_smooth_group(1)
	st.set_color(cc)
	st.set_uv(uvc)
	st.add_vertex(c)


static func _build_ribbon_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float wind_time = 0.0;
uniform vec3 ribbon_color : source_color = vec3(0.97, 0.96, 0.91);

varying float v_life;
varying float v_phase;
varying float v_alpha_mult;
varying vec3 v_vcol;

void vertex() {
	v_life = INSTANCE_CUSTOM.x;
	v_phase = INSTANCE_CUSTOM.y;
	float spd_norm = INSTANCE_CUSTOM.z;
	v_alpha_mult = INSTANCE_CUSTOM.w;
	v_vcol = COLOR.rgb;

	// Flowing airborne sinusoidal shimmer along ribbon length UV.x.
	float env = sin(UV.x * 3.14159265);
	float wave_arg = UV.x * 8.0 - wind_time * (2.6 + spd_norm * 2.8) + v_phase;
	VERTEX.x += sin(wave_arg) * (0.12 + 0.10 * spd_norm) * env;
	VERTEX.y += cos(wave_arg * 0.85 + 0.7) * (0.08 + 0.07 * spd_norm) * env;
}

void fragment() {
	// Feathered brushstroke alpha along length and across ribbon width.
	float long_fade = smoothstep(0.0, 0.24, UV.x) * smoothstep(1.0, 0.72, UV.x);
	float across = abs(UV.y * 2.0 - 1.0);
	float cross_fade = smoothstep(1.0, 0.14, across);
	float wisp = 0.78 + 0.22 * sin(UV.x * 15.0 - wind_time * 3.8 + v_phase);
	float alpha = clamp(long_fade * cross_fade * v_life * v_alpha_mult * wisp, 0.0, 0.62);
	if (alpha < 0.008) {
		discard;
	}
	ALBEDO = ribbon_color * v_vcol;
	ALPHA = alpha;
}
"""
	return sh
