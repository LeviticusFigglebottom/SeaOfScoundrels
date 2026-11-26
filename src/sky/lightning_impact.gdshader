shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Storm lightning-strike ocean impact surge: three wave-conformal sub-layers
// packed into one reusable ArrayMesh (selected by COLOR.r):
//   COLOR.r < 0.25  -> Expanding electric water shockwave disc (~3 m -> ~26 m)
//                      draping over live Gerstner swells via waves.gdshaderinc.
//   0.25..0.75      -> Fluted rising ionized spray crown (0 -> ~18 m surge).
//   COLOR.r >= 0.75 -> Crossed feathered inner plasma & billowing geyser plumes.
#include "res://src/ocean/waves.gdshaderinc"

global uniform vec3 sky_horizon_color;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 impact_origin = vec3(0.0);
uniform float progress = 1.0;
uniform float intensity = 1.0;
uniform float flash = 0.0;
uniform float ring_radius = 26.0;
uniform float plume_height = 18.0;
uniform float follow_sea = 1.0;
uniform vec3 electric_tint = vec3(0.42, 0.88, 1.0);
uniform vec3 spray_tint = vec3(0.72, 0.82, 0.88);
uniform float seed = 0.0;

varying float v_part;
varying vec3 v_local;
varying float v_dist;

void vertex() {
	v_part = COLOR.r;
	float p = clamp(progress, 0.0, 1.0);
	float p_safe = max(p, 0.0001);
	float inv_p = max(1.0 - p, 0.0001);

	if (v_part < 0.25) {
		// Part 0: Expanding wave-conformal shockwave disc (unit disc in XZ, UV.y = radius 0..1).
		vec2 dir_xz = VERTEX.xz;
		float expand = mix(0.115, 1.0, 1.0 - pow(inv_p, 2.35));
		vec2 local_xz = dir_xz * (ring_radius * expand);
		float wave_dy = follow_sea > 0.5 ? (sea_height(impact_origin.xz + local_xz) - impact_origin.y) : 0.0;
		float front_r = mix(0.26, 0.84, pow(p_safe, 0.65));
		float d_f = (UV.y - front_r) * 7.5;
		float crest = exp(-(d_f * d_f)) * (1.0 - p) * 0.65;
		VERTEX = vec3(local_xz.x, wave_dy + 0.16 + crest, local_xz.y);
		v_local = vec3(dir_xz.x, UV.y, dir_xz.y);
	} else if (v_part < 0.75) {
		// Part 1: Fluted rising ionized spray crown (unit cylinder in XZ, UV.y = height 0..1).
		vec2 radial = VERTEX.xz;
		float h = UV.y;
		float h_safe = max(h, 0.0001);
		float rise = sin(pow(p_safe, 0.52) * PI);
		float cur_h = plume_height * (0.14 + 0.86 * rise);
		float ang = UV.x * TAU;
		float flute = 1.0 + 0.16 * sin(ang * 8.0 + seed * TAU) * h
				+ 0.09 * cos(ang * 13.0 - seed * 11.3) * h;
		float r_base = ring_radius * mix(0.08, 0.18, p);
		float r_tip = ring_radius * mix(0.16, 0.44, pow(p_safe, 0.68));
		float rad = mix(r_base, r_tip, pow(h_safe, 0.78)) * flute;
		vec2 local_xz = radial * rad;
		float wave_dy = follow_sea > 0.5 ? (sea_height(impact_origin.xz + local_xz) - impact_origin.y) : 0.0;
		float y = wave_dy - 0.15 + h * cur_h - pow(h_safe, 2.3) * cur_h * 0.24 * p;
		VERTEX = vec3(local_xz.x, y, local_xz.y);
		v_local = vec3(radial.x, h, radial.y);
	} else {
		// Part 2: Crossed feathered inner plasma & billowing geyser plume sheets.
		vec2 sheet_xz = VERTEX.xz;
		float h = UV.y;
		float rise = sin(pow(p_safe, 0.50) * PI);
		float cur_h = plume_height * 1.12 * (0.18 + 0.82 * rise);
		float half_w = ring_radius * mix(0.14, 0.34, pow(p_safe, 0.65)) * (0.68 + 0.54 * h);
		vec2 local_xz = sheet_xz * half_w;
		float wave_dy = follow_sea > 0.5 ? (sea_height(impact_origin.xz + local_xz) - impact_origin.y) : 0.0;
		VERTEX = vec3(local_xz.x, wave_dy - 0.10 + h * cur_h, local_xz.y);
		v_local = vec3(sheet_xz.x, h, sheet_xz.y);
	}

	vec3 world_pos = impact_origin + VERTEX;
	v_dist = length(CAMERA_POSITION_WORLD - world_pos);
}

void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	float p_safe = max(p, 0.0001);
	float inv_p = max(1.0 - p, 0.0001);
	// Electric plasma heat fades rapidly while restrikes re-energize the glow.
	float electric = clamp(pow(inv_p, 1.85) + flash * 0.45 * (1.0 - p * 0.5), 0.0, 1.0);
	float life_fade = smoothstep(1.0, 0.68, p) * clamp(intensity, 0.25, 1.0);
	vec3 spray_col = mix(spray_tint, vec3(0.86, 0.94, 0.98), 0.55) * (0.95 + flash * 0.65);
	// Gentle distance haze on cool spray only; electric plasma punches through storm murk.
	float haze = clamp(1.0 - exp(-v_dist * 0.00055), 0.0, 0.65);

	vec3 col = spray_col;
	float alpha = 0.0;

	if (v_part < 0.25) {
		// --- Expanding Electric Water Shockwave Disc ---
		float r = v_local.y;
		vec2 p_uv = v_local.xz * 0.62 + vec2(seed * 1.37, -seed * 0.83);
		vec4 n_coarse = texture(noise_tex, p_uv * 1.15 - v_local.xz * p * 0.45);
		vec4 n_fine = texture(noise_tex, p_uv * 2.75 + vec2(p * 0.32, -p * 0.26));
		float warp = (n_coarse.a - 0.5) * 0.11 + (n_fine.g - 0.5) * 0.05;
		float rw = r + warp;

		float front_r = mix(0.26, 0.84, pow(p_safe, 0.65));
		float ring_w = mix(0.11, 0.24, p);
		float d_r = (rw - front_r) / ring_w;
		float d_t = (rw - front_r * 0.56) / (ring_w * 1.25);
		float primary_ring = exp(-(d_r * d_r));
		float trail_ring = exp(-(d_t * d_t)) * 0.48 * n_fine.g;
		float frothy = mix(0.55, 1.15, n_coarse.r * 0.6 + n_fine.g * 0.4);
		float shock = (primary_ring * frothy + trail_ring) * smoothstep(1.0, 0.82, r);

		// Blinding plasma touchdown hotspot + crackling surface lightning tendrils.
		float core = exp(-r * r * 15.0) * pow(inv_p, 2.2) * (1.0 + flash * 0.65);
		float arc_ridge = smoothstep(0.60, 0.88, n_fine.b) * smoothstep(front_r + 0.08, 0.12, r)
				* smoothstep(0.05, 0.22, r) * pow(inv_p, 2.6);

		vec3 hot_col = vec3(5.6, 6.4, 7.2) * (core + arc_ridge * 0.85)
				+ electric_tint * (3.2 * electric * primary_ring + 2.8 * arc_ridge);
		vec3 cool_spray = mix(spray_col, sky_horizon_color * 1.15, haze * 0.6);
		col = mix(cool_spray, hot_col, clamp(electric * 0.85 + core + arc_ridge, 0.0, 1.0));
		alpha = clamp((shock * 0.88 + core * 1.1 + arc_ridge * 0.75) * life_fade, 0.0, 0.96);
	} else if (v_part < 0.75) {
		// --- Fluted Rising Ionized Spray Crown ---
		float h = v_local.y;
		// Seamless cylindrical coordinates around the crown (zero UV.x seam).
		vec2 cyl_a = v_local.xz * 0.48 + vec2(seed * 0.73, seed * 1.19);
		vec4 n1 = texture(noise_tex, vec2(cyl_a.x + cyl_a.y * 0.5, h * 0.95 - p * 1.35));
		vec4 n2 = texture(noise_tex, vec2(cyl_a.y - cyl_a.x * 0.5, h * 1.85 - p * 2.10) + 0.37);
		float plume_noise = n1.r * 0.55 + n2.g * 0.45;
		float spire_cut = smoothstep(0.18 + h * mix(0.28, 0.72, p), 0.78 + h * 0.18, plume_noise + (1.0 - h) * 0.38);
		float v_env = smoothstep(0.0, 0.14, h) * smoothstep(1.0, 0.68, h);
		float mask = spire_cut * v_env;

		float base_glow = exp(-h * 3.1) * electric;
		float wisp_arc = smoothstep(0.64, 0.90, n2.b) * (1.0 - h * 0.5) * pow(inv_p, 2.2);
		vec3 hot_col = vec3(4.2, 5.2, 6.2) * (base_glow * 0.75 + wisp_arc * 0.6)
				+ electric_tint * (2.6 * base_glow + 2.2 * wisp_arc);
		vec3 cool_spray = mix(spray_col * mix(0.82, 1.15, h), sky_horizon_color * 1.15, haze * 0.65);
		col = mix(cool_spray, hot_col, clamp(base_glow * 0.85 + wisp_arc, 0.0, 1.0));
		alpha = clamp(mask * mix(0.86, 0.48, p) * life_fade + wisp_arc * 0.45 * v_env, 0.0, 0.92);
	} else {
		// --- Crossed Feathered Inner Plasma & Billowing Geyser Plumes ---
		float h = v_local.y;
		float across = abs(UV.x * 2.0 - 1.0);
		float side_fade = smoothstep(1.0, 0.16, across);
		float v_env = smoothstep(0.0, 0.12, h) * smoothstep(1.0, 0.56, h);

		vec2 g_uv = vec2(UV.x * 1.4 + seed * 1.9, h * 1.25 - p * 1.85);
		vec4 n_billow = texture(noise_tex, g_uv);
		vec4 n_detail = texture(noise_tex, g_uv * 2.15 + vec2(0.41, -p * 0.9));
		float mist = smoothstep(0.24 + h * 0.25, 0.78, n_billow.r * 0.6 + n_detail.g * 0.4 + (1.0 - across) * 0.28);

		// Intense vertical ionized plasma core right along the bolt channel at touchdown.
		float plasma_axis = exp(-across * across * 16.0) * (1.0 - h * 0.55) * pow(inv_p, 2.1) * (1.0 + flash * 0.55);
		vec3 hot_col = vec3(5.8, 6.6, 7.5) * plasma_axis + electric_tint * (3.0 * electric * (1.0 - h * 0.5));
		vec3 cool_spray = mix(spray_col * mix(0.88, 1.18, h), sky_horizon_color * 1.15, haze * 0.65);
		col = mix(cool_spray, hot_col, clamp(plasma_axis + electric * (1.0 - h * 0.6) * 0.65, 0.0, 1.0));
		alpha = clamp((mist * side_fade * v_env * 0.74 + plasma_axis * 0.95 * v_env) * life_fade, 0.0, 0.95);
	}

	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = col;
	ALPHA = alpha;
}
