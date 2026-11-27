shader_type spatial;
// Stylized painterly animated cliffside waterfall curtain shader (RX 9070 XT look-dev).
// Zero external texture taps; dynamically lit by SkyRig globals (sun_dir, sun_color,
// ambient_color, sky_horizon_color) with dual-velocity domain-warped silk cascades,
// translucent sunlit turquoise subsurface scatter, crest specular sparkle, and crisp
// readability across noon, golden sunset, storm, and moonlit night.
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

#include "res://src/sky/cloud_shadow.gdshaderinc"

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

	// Domain-warped dual-velocity silk water ribbons + crisp filamentous whitewater chutes.
	float flow_accel = 1.0 + UV.y * 0.45;
	float warp_x = (vnoise2(vec2(UV.x * 5.2, UV.y * 2.4 - t * 0.65)) - 0.5) * 0.34;
	float n_broad = vnoise2(vec2((UV.x + warp_x) * 8.4, UV.y * 3.8 - t * 1.05 * flow_accel));
	float n_mid = vnoise2(vec2((UV.x - warp_x * 0.7) * 18.0 + 3.1, UV.y * 7.2 - t * 1.62 * flow_accel + n_broad * 0.52));
	float n_fine = vnoise2(vec2(UV.x * 38.0 - 1.7 + n_mid * 0.5, UV.y * 13.5 - t * 2.35 * flow_accel));
	float ribbon = smoothstep(0.46, 0.84, n_broad * 0.54 + n_mid * 0.46);
	float filament = smoothstep(0.62, 0.90, n_mid * 0.42 + n_fine * 0.58);

	// Turbulent foaming whitewater at upper cliff crest (UV.y < 0.16) and billowing plunge base (UV.y > 0.72),
	// preserving deep jewel-like turquoise-emerald water windows between racing foam chutes!
	float lip_foam = smoothstep(0.16, 0.025, UV.y) * (0.64 + 0.36 * n_mid);
	float plunge_foam = smoothstep(0.72, 0.96, UV.y) * (0.70 + 0.30 * n_broad);
	float mid_streaks = clamp(ribbon * 0.40 + filament * 0.82, 0.0, 1.0) * (0.50 + 0.50 * v_wave_crest);
	float foam_mask = clamp(max(max(lip_foam, plunge_foam), mid_streaks), 0.0, 1.0);

	// Deep tropical emerald-turquoise water core grading richer in thick center chutes.
	float center_depth = 1.0 - abs(UV.x * 2.0 - 1.0);
	vec3 water_core = mix(water_color * vec3(0.86, 0.96, 1.00), deep_water_color * vec3(0.78, 0.90, 0.96), clamp(center_depth * 0.74 * (1.0 - n_broad * 0.38), 0.0, 1.0));

	// Dynamic lighting from SkyRig globals (sunlit turquoise translucency + crest sparkle + moonlight readability).
	vec3 n_w = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	// Perturb normal slightly along ribbon crests for lively specular glitter!
	vec3 side_t = normalize(cross(vec3(0.0, 1.0, 0.0), n_w) + vec3(0.001, 0.0, 0.001));
	vec3 n_lit = normalize(n_w + side_t * ((n_mid - 0.5) * 0.36) + vec3(0.0, (n_fine - 0.5) * 0.22, 0.0));
	vec3 L = normalize(sun_dir);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	// SkyRig flips sun_dir upward to the moon at night, so detect true night via sky_horizon_color lum too!
	float hor_lum = dot(sky_horizon_color, vec3(0.2126, 0.7152, 0.0722));
	float night_gate = clamp(max(smoothstep(0.02, -0.10, L.y), smoothstep(0.068, 0.024, hor_lum)), 0.0, 1.0);
	float day_gate = (1.0 - night_gate) * smoothstep(-0.02, 0.12, L.y);
	float golden_hour = (1.0 - night_gate) * smoothstep(-0.02, 0.05, L.y) * smoothstep(0.26, 0.07, L.y);
	// Sample live CloudShadowBake so overcast rainstorms naturally mood-darken cascades while
	// sunlit cloud-breaks flash with dazzling turquoise-and-gold foam!
	float sun_sh = cloud_light(v_world_pos.xz);
	float sun_vis = smoothstep(0.26, 0.84, sun_sh);
	float ndotl = clamp(dot(n_lit, L) * 0.5 + 0.5, 0.0, 1.0);
	float ndotv = clamp(abs(dot(n_lit, V)), 0.0, 1.0);
	float rim = pow(clamp(1.0 - ndotv, 0.0, 1.0), 2.3);
	float back_scatter = pow(clamp(dot(-V, L) * 0.5 + 0.5, 0.0, 1.0), 2.8) * (1.0 - foam_mask * 0.55) * day_gate * sun_vis;
	vec3 H = normalize(L + V);
	float sparkle = pow(clamp(dot(n_lit, H), 0.0, 1.0), 48.0) * (0.45 + 0.55 * n_fine) * day_gate * sun_vis;

	vec3 direct_sun = sun_color * (0.22 + 0.86 * ndotl) * mix(0.32, 1.0, sun_sh);
	vec3 light_term = max(ambient_color * mix(0.76, 0.90, sun_vis) + direct_sun, vec3(0.05, 0.08, 0.13));
	// Preserve jewel deep emerald-teal water core even under warm amber-rose sunset skies (never muddy beige!),
	// deepen overcast stormy cascades to brooding slate-teal, and keep moonlit night silvery-indigo.
	float storm_dim = (1.0 - night_gate) * (1.0 - sun_vis);
	vec3 storm_water = vec3(0.04, 0.18, 0.24);
	vec3 night_water = vec3(0.09, 0.14, 0.21);
	vec3 core_tod = mix(water_core, storm_water, storm_dim * 0.72);
	core_tod = mix(core_tod, night_water, night_gate * 0.86);
	float sunset_warm = golden_hour * clamp(0.45 + (sun_color.r - sun_color.b) * 1.4, 0.0, 1.0) * mix(0.45, 1.0, sun_vis);
	// At golden sunset, neutralize magenta-brown mud in the shadowed water core with cool zenith-teal depth
	// so bright golden-apricot foam chutes pop with painterly warm-vs-cool contrast!
	vec3 water_light = mix(light_term, vec3(light_term.r * 0.56, max(light_term.g, light_term.r * 0.82), max(light_term.b, light_term.r * 0.96)), sunset_warm * 0.82);
	vec3 sss_tint = mix(vec3(0.14, 0.86, 0.84), vec3(0.28, 0.76, 0.68), sunset_warm * 0.65);
	vec3 sss_glow = sss_tint * sun_color * (back_scatter * 0.52 + 0.14 * day_gate * sun_vis);
	vec3 lit_water = core_tod * water_light * mix(0.78, 1.08, ndotl) * (1.0 + rim * 0.36) + sss_glow;
	vec3 foam_tod_tint = mix(mix(foam_color, vec3(1.00, 0.88, 0.68), sunset_warm * 0.86), vec3(0.58, 0.66, 0.78), night_gate * 0.82);
	foam_tod_tint = mix(foam_tod_tint, vec3(0.56, 0.64, 0.70), storm_dim * 0.52);
	vec3 lit_foam = foam_tod_tint * (light_term * mix(1.14, 0.58, night_gate) + sun_color * ((rim * 0.48 + sunset_warm * 0.65) * sun_vis));
	// Delicate sunlit mist-prism iridescence near aerated plunge curtain (UV.y 0.56..0.94, pairs w/ Pass Q15 rainbow!).
	float plunge_zone = smoothstep(0.54, 0.76, UV.y) * smoothstep(0.98, 0.78, UV.y) * day_gate * sun_vis * (1.0 - storm_dim);
	float prism_t = clamp((UV.x + (n_broad - 0.5) * 0.16) * 1.45 - 0.22, 0.0, 1.0);
	vec3 prism_col = 0.5 + 0.5 * cos(6.28318 * (prism_t * 0.78 + vec3(0.02, 0.34, 0.66)));
	vec3 col = mix(lit_water, lit_foam, foam_mask) + sun_color * (sparkle * 0.78) + prism_col * (plunge_zone * foam_mask * 0.11);

	// Gentle aerial horizon blend so distant cliff cascades sit harmoniously in coastal haze.
	float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
	float haze = smoothstep(140.0, 560.0, dist) * 0.42;
	col = mix(col, sky_horizon_color, haze);

	// Organic foam-feathered left/right edges + clean lip/plunge transitions.
	float edge_noise = (n_mid - 0.5) * 0.12 + warp_x * 0.18;
	float side_fade = smoothstep(0.02, 0.18, UV.x + edge_noise) * smoothstep(0.98, 0.82, UV.x - edge_noise);
	float top_fade = smoothstep(0.0, 0.035, UV.y);
	float bottom_fade = smoothstep(1.0, 0.90, UV.y);
	float alpha = clamp(side_fade * top_fade * bottom_fade * mix(opacity * 0.74, min(opacity + 0.11, 0.97), foam_mask), 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
