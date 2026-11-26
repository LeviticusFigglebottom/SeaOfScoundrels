shader_type spatial;
// Stylized wind-fluttering nautical bunting pennant & festoon rope shader.
// UV.y encodes flutter weight (0.0 pinned on timber posts & rope anchors .. 1.0 at pennant tip).
// UV.x encodes per-pennant phase offset (0..1) for lively traveling harbour breeze waves.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 sun_dir;
global uniform vec3 sun_color;

uniform vec2 wind_dir = vec2(0.707, -0.707);
uniform float wind_speed = 6.5;
uniform float wind_time = 0.0;
uniform float flutter_strength : hint_range(0.0, 2.5) = 1.0;
uniform float roughness_val : hint_range(0.1, 1.0) = 0.78;
uniform float fabric_sss : hint_range(0.0, 1.0) = 0.30;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_flutter_w;

vec3 srgb_to_linear(vec3 c) {
	vec3 cl = max(c, vec3(0.0));
	vec3 lo = cl / 12.92;
	vec3 hi = pow((cl + 0.055) / 1.055, vec3(2.4));
	return mix(lo, hi, step(vec3(0.04045), cl));
}

void vertex() {
	float w = clamp(UV.y, 0.0, 1.0);
	float bend_w = w * w;
	float phase = UV.x * 6.2831853;
	float t = wind_time > 0.0001 ? wind_time : TIME;

	float ws = clamp(wind_speed / 9.0, 0.18, 2.4);
	vec2 wd = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(0.707, -0.707);
	vec3 world_wind = vec3(wd.x, 0.0, wd.y);

	// Convert world wind into mesh-local horizontal space.
	vec3 col0 = normalize(MODEL_MATRIX[0].xyz + vec3(1e-5, 0.0, 0.0));
	vec3 col1 = normalize(MODEL_MATRIX[1].xyz + vec3(0.0, 1e-5, 0.0));
	vec3 col2 = normalize(MODEL_MATRIX[2].xyz + vec3(0.0, 0.0, 1e-5));
	mat3 world_to_local = transpose(mat3(col0, col1, col2));
	vec3 local_wind = normalize(world_to_local * world_wind + vec3(1e-5, 0.0, 0.0));
	vec3 cross_wind = normalize(cross(vec3(0.0, 1.0, 0.0), local_wind) + vec3(0.0, 0.0, 1e-5));

	vec3 wp0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float spatial_p = dot(wp0.xz, vec2(0.55, 0.42)) + phase;

	// Rolling trade-wind billow + crisp double-harmonic cloth snap along pennant tips.
	float billow = 0.55 + 0.45 * sin(t * (1.8 + ws * 0.9) + spatial_p * 0.45);
	float ripple = sin(t * (4.6 + ws * 2.4) + spatial_p - w * 2.8) * 0.65
		+ sin(t * (8.2 + ws * 3.1) + spatial_p * 1.7 - w * 4.2) * 0.35;

	float amp = (0.08 + 0.14 * ws) * flutter_strength;
	vec3 disp = local_wind * (billow * amp * 1.15 * bend_w);
	disp += cross_wind * (ripple * amp * 0.95 * bend_w);
	disp.y += (0.045 * ws * billow + 0.025 * ripple) * flutter_strength * bend_w;

	VERTEX += disp;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_flutter_w = w;
}

void fragment() {
	vec3 base_col = srgb_to_linear(COLOR.rgb);
	ALBEDO = base_col;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	SPECULAR = 0.14;

	// Warm sunlit canvas glow on thin fluttering pennant cloth (suppressed on rigid timber posts).
	vec3 n_w = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	float back_lit = clamp(-dot(n_w, normalize(sun_dir)) * 0.60 + 0.40, 0.0, 1.0);
	float sun_sh = cloud_shadow(v_world.xz);
	float cloth_mask = smoothstep(0.04, 0.25, v_flutter_w);
	EMISSION = base_col * sun_color * (back_lit * fabric_sss * cloth_mask * sun_sh * 0.28);
}

void light() {
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(v_world.xz) : 1.0;
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + 0.24) / 1.24, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR * sun / PI;
}
