shader_type spatial;
// Stylized painterly animated cliffside waterfall curtain shader.
// Zero external texture taps; dynamically lit by SkyRig globals (sun_dir, sun_color,
// ambient_color, sky_horizon_color) so cascades glow warm at sunset and stay readable
// blue-silver under moonlight.
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

global uniform vec3 sun_dir;
global uniform vec3 sun_color;
global uniform vec3 ambient_color;
global uniform vec3 sky_horizon_color;

uniform float flow_speed = 1.45;
uniform vec3 water_color : source_color = vec3(0.06, 0.56, 0.66);
uniform vec3 deep_water_color : source_color = vec3(0.03, 0.30, 0.48);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 0.98);
uniform float opacity : hint_range(0.0, 1.0) = 0.88;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_wave_crest;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	// Pin top cliff lip (UV.y = 0) and plunge base (UV.y = 1); undulate mid-fall curtain smoothly.
	float fall_free = smoothstep(0.0, 0.14, UV.y) * smoothstep(1.0, 0.86, UV.y);
	float w1 = sin(UV.y * 14.0 - TIME * 7.5 + UV.x * 4.5);
	float w2 = cos(UV.y * 23.0 - TIME * 11.2 - UV.x * 7.0);
	float disp = (w1 * 0.085 + w2 * 0.040) * fall_free;
	VERTEX += NORMAL * disp;
	v_wave_crest = w1 * 0.5 + 0.5;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float t = TIME * flow_speed;

	// Multi-band scrolling downward aerated foam streaks (UV.y increases top -> bottom).
	float n_broad = vnoise2(vec2(UV.x * 7.5, UV.y * 3.8 - t * 1.12));
	float n_mid = vnoise2(vec2(UV.x * 16.0 + 3.1, UV.y * 6.4 - t * 1.55 + n_broad * 0.45));
	float n_fine = vnoise2(vec2(UV.x * 31.0 - 1.7, UV.y * 11.0 - t * 2.05));
	float streak = clamp(n_broad * 0.45 + n_mid * 0.35 + n_fine * 0.20, 0.0, 1.0);

	// Foaming turbulent whitewater at upper cliff lip (UV.y < 0.14) and plunge base (UV.y > 0.78).
	float lip_foam = smoothstep(0.16, 0.02, UV.y) * (0.65 + 0.35 * n_mid);
	float plunge_foam = smoothstep(0.74, 0.96, UV.y) * (0.70 + 0.30 * n_broad);
	float mid_streaks = smoothstep(0.48, 0.78, streak) * (0.62 + 0.38 * v_wave_crest);
	float foam_mask = clamp(max(max(lip_foam, plunge_foam), mid_streaks), 0.0, 1.0);

	// Translucent tropical turquoise-aqua water core grading deeper in the curtain center.
	float center_depth = 1.0 - abs(UV.x * 2.0 - 1.0);
	vec3 water_core = mix(water_color, deep_water_color, clamp(center_depth * 0.55 * (1.0 - n_broad * 0.4), 0.0, 1.0));

	// Dynamic lighting from SkyRig globals (golden sunset, bright noon, moody night).
	vec3 n_w = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 L = normalize(sun_dir);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float ndotl = clamp(dot(n_w, L) * 0.5 + 0.5, 0.0, 1.0);
	float ndotv = clamp(abs(dot(n_w, V)), 0.0, 1.0);
	float rim = pow(clamp(1.0 - ndotv, 0.0, 1.0), 2.4);

	vec3 light_term = max(ambient_color * 0.88 + sun_color * (0.28 + 0.72 * ndotl), vec3(0.08, 0.11, 0.18));
	vec3 lit_water = water_core * light_term * (1.0 + rim * 0.32);
	vec3 lit_foam = foam_color * (light_term * 1.06 + sun_color * (rim * 0.38));
	vec3 col = mix(lit_water, lit_foam, foam_mask);

	// Gentle aerial horizon blend so distant cliff cascades sit harmoniously in coastal haze.
	float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
	float haze = smoothstep(140.0, 560.0, dist) * 0.42;
	col = mix(col, sky_horizon_color, haze);

	// Feathered left/right edges broken organically by falling foam noise, plus soft bottom blend.
	float edge_noise = (n_mid - 0.5) * 0.10;
	float side_fade = smoothstep(0.02, 0.18, UV.x + edge_noise) * smoothstep(0.98, 0.82, UV.x - edge_noise);
	float bottom_fade = smoothstep(1.0, 0.92, UV.y);
	float alpha = clamp(side_fade * bottom_fade * mix(opacity * 0.76, min(opacity + 0.10, 0.97), foam_mask), 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
