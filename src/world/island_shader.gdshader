shader_type spatial;
// Painterly stylized island terrain shader for Sea of Scoundrels.
// Blends seamlessly by elevation and slope with zero-tiling world-space brush
// variation and geological strata:
//   deep seabed (< -3 m) -> turquoise shallow seabed (-3..0 m) -> glistening
//   wet sand (0..0.75 m) -> warm sunlit golden beach (0.75..2.8 m) -> vibrant
//   tropical grass (> 2.8 m, gentle slopes) -> bold chunky faceted limestone /
//   sandstone cliffs (normal.y < 0.70, warm sunlit vs cool blue-slate shadows).
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 ambient_color;
global uniform vec3 sky_horizon_color;

uniform vec3 deep_seabed_color : source_color = vec3(0.16, 0.26, 0.30);
uniform vec3 shallow_seabed_color : source_color = vec3(0.76, 0.80, 0.64);
uniform vec3 wet_sand_color : source_color = vec3(0.54, 0.43, 0.26);
uniform vec3 dry_sand_color : source_color = vec3(0.88, 0.76, 0.49);
uniform vec3 grass_deep_color : source_color = vec3(0.14, 0.37, 0.12);
uniform vec3 grass_sun_color : source_color = vec3(0.40, 0.63, 0.17);
uniform vec3 cliff_warm_color : source_color = vec3(0.73, 0.61, 0.44);
uniform vec3 cliff_pale_color : source_color = vec3(0.88, 0.83, 0.73);
uniform vec3 cliff_dark_color : source_color = vec3(0.44, 0.41, 0.38);
uniform vec3 sea_moss_color : source_color = vec3(0.20, 0.25, 0.20);

uniform vec3 cliff_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float cliff_facet_strength : hint_range(0.0, 1.0) = 0.72;

varying vec3 v_world;
varying vec3 v_world_normal;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

float fbm2(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise2(p);
		p = rot * p * 2.07 + vec2(19.7, 7.3);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 smooth_n = normalize(v_world_normal);
	float h = v_world.y;
	vec2 xz = v_world.xz;

	// Zero-tiling world-space painterly brush & strata noise fields.
	float macro_n = fbm2(xz * 0.032);
	float brush_n = fbm2(xz * 0.14 + vec2(macro_n * 2.6, -macro_n * 2.1));
	float grain_n = vnoise2(xz * 0.72 + vec2(brush_n * 1.4));
	float ripple_n = sin(xz.x * 0.42 + xz.y * 0.35 + macro_n * 4.5) * 0.5 + 0.5;

	// Height-jittered boundaries keep biome edges organic and hand-painted.
	float edge_jit = (macro_n - 0.5) * 0.65 + (brush_n - 0.5) * 0.30;
	float h_org = h + edge_jit;

	// --- Elevation bands (deep seabed -> shallow -> wet sand -> dry sand -> grass) ---
	float t_shallow = smoothstep(-5.2, -1.6, h + (macro_n - 0.5) * 1.1);
	float t_wet_in = smoothstep(-0.45, 0.08, h + (brush_n - 0.5) * 0.16);
	float t_dry_in = smoothstep(0.58, 0.92, h + (brush_n - 0.5) * 0.18);
	float t_grass_in = smoothstep(2.45, 3.35, h_org);

	vec3 col_deep = deep_seabed_color * mix(0.86, 1.14, brush_n);
	vec3 col_shallow = shallow_seabed_color * mix(0.92, 1.08, ripple_n * 0.6 + brush_n * 0.4);
	vec3 col_wet = wet_sand_color * mix(0.90, 1.10, ripple_n * 0.5 + grain_n * 0.5);
	vec3 col_dry = dry_sand_color * mix(0.92, 1.08, brush_n * 0.65 + ripple_n * 0.35);

	// Painterly layered tropical grass with golden coastal verge and deep emerald patches.
	vec3 col_grass = mix(grass_deep_color, grass_sun_color, smoothstep(0.24, 0.78, brush_n * 0.72 + macro_n * 0.28));
	col_grass *= mix(0.92, 1.08, grain_n);
	col_grass *= grass_tint;
	float beach_verge = smoothstep(4.6, 2.5, h_org);
	col_grass = mix(col_grass, mix(col_dry, grass_sun_color * grass_tint, 0.55), beach_verge * 0.35);

	vec3 ground_col = mix(col_deep, col_shallow, t_shallow);
	ground_col = mix(ground_col, col_wet, t_wet_in);
	ground_col = mix(ground_col, col_dry, t_dry_in);
	ground_col = mix(ground_col, col_grass, t_grass_in);

	// --- Bold chunky faceted limestone / warm sandstone coastal cliffs ---
	float strata_coord = h * 0.42 + macro_n * 2.8 + brush_n * 0.9;
	float strata_band = smoothstep(0.25, 0.75, sin(strata_coord * 3.14159) * 0.5 + 0.5);
	float height_pale = smoothstep(5.0, 26.0, h + (macro_n - 0.5) * 5.0);

	vec3 cliff_base = mix(cliff_warm_color, cliff_pale_color, clamp(height_pale * 0.78 + strata_band * 0.26, 0.0, 1.0));
	float ledge_crevice = smoothstep(0.78, 0.96, sin(strata_coord * 6.28318) * 0.5 + 0.5);
	cliff_base = mix(cliff_base, cliff_dark_color, ledge_crevice * 0.26 + (1.0 - brush_n) * 0.14);
	// Wet sea-line algae/barnacle band where rocky cliffs plunge into the surf.
	float sea_band = smoothstep(-2.4, -0.2, h) * smoothstep(2.2, 0.45, h + (brush_n - 0.5) * 0.5);
	cliff_base = mix(cliff_base, sea_moss_color, sea_band * 0.62);
	cliff_base *= cliff_tint;

	// Slope-driven cliff mask (normal.y < 0.70 -> bold cliffs) + high rocky summits.
	float slope_cliff = smoothstep(0.76, 0.56, smooth_n.y + (brush_n - 0.5) * 0.09);
	float summit_rock = smoothstep(28.0, 44.0, h_org) * smoothstep(0.95, 0.74, smooth_n.y);
	float cliff_mask = clamp(max(slope_cliff, summit_rock), 0.0, 1.0);
	cliff_mask *= mix(smoothstep(0.55, 0.35, smooth_n.y), 1.0, smoothstep(-1.8, 0.35, h));

	// Subtle per-vertex tint (crevice AO / volcanic rim / coastal paths).
	vec3 albedo = mix(ground_col, cliff_base, cliff_mask) * COLOR.rgb;

	// Crisp geometric facet normals on cliffs for that sculpted monolithic spire look.
	vec3 dpdx = dFdx(v_world);
	vec3 dpdy = dFdy(v_world);
	vec3 raw_face_n = cross(dpdy, dpdx);
	float fn_len = length(raw_face_n);
	vec3 face_n = fn_len > 1e-5 ? (raw_face_n / fn_len) : smooth_n;
	face_n *= (dot(face_n, smooth_n) >= 0.0) ? 1.0 : -1.0;

	vec3 final_n_world = normalize(mix(smooth_n, face_n, cliff_mask * cliff_facet_strength));
	float facet_pop = clamp(dot(face_n, smooth_n), 0.75, 1.0);
	albedo *= mix(1.0, 0.90 + 0.14 * facet_pop, cliff_mask);

	// Surface roughness & specular: glistening wet sand, dry matte sand, textured cliffs.
	float wet_mask = t_wet_in * (1.0 - t_dry_in) * (1.0 - cliff_mask * 0.85);
	float rough = mix(0.92, 0.86, t_shallow);
	rough = mix(rough, mix(0.20, 0.32, grain_n), wet_mask);
	rough = mix(rough, 0.88, t_dry_in * (1.0 - t_grass_in));
	rough = mix(rough, 0.84, t_grass_in);
	rough = mix(rough, mix(0.78, 0.92, 1.0 - strata_band), cliff_mask);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.28, 0.65, wet_mask);
	NORMAL = normalize((VIEW_MATRIX * vec4(final_n_world, 0.0)).xyz);
}

void light() {
	// Per-pixel drifting cloud shadows on directional sunlight (never on lanterns/fires).
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(v_world.xz) : 1.0;
	float ndl_raw = dot(NORMAL, LIGHT);
	float ndl = clamp(ndl_raw, 0.0, 1.0);
	float up_n = normalize(v_world_normal).y;
	float cliff_m = clamp(max(smoothstep(0.76, 0.56, up_n), smoothstep(28.0, 44.0, v_world.y) * smoothstep(0.95, 0.74, up_n)), 0.0, 1.0);
	float wet_m = smoothstep(0.60, 0.32, ROUGHNESS);

	if (LIGHT_IS_DIRECTIONAL) {
		// Detect warm daylight vs cool moonlight so night cliffs stay silver-blue.
		float warmth = clamp((LIGHT_COLOR.r - LIGHT_COLOR.b) * 2.2 + 0.45, 0.0, 1.0);
		vec3 sunlit_tint = mix(vec3(1.0), vec3(1.06, 0.99, 0.90), cliff_m * warmth);
		// Soft wrapped terminator on sand/grass, crisp sculptural planes on cliffs.
		float wrap = mix(0.14, 0.03, cliff_m);
		float diff_term = clamp((ndl_raw + wrap) / (1.0 + wrap), 0.0, 1.0);
		DIFFUSE_LIGHT += diff_term * ATTENUATION * LIGHT_COLOR * sunlit_tint * sun / PI;

		// Cool blue-slate sky-bounce fill on cliff planes turned away from the sun.
		float shadow_plane = smoothstep(0.18, -0.35, ndl_raw);
		vec3 cool_fill = mix(ambient_color, sky_horizon_color * vec3(0.68, 0.84, 1.12), 0.55);
		float fill_str = mix(0.05, 0.22, cliff_m) * warmth * clamp(sun, 0.35, 1.15);
		DIFFUSE_LIGHT += shadow_plane * cool_fill * fill_str / PI;

		// Glistening wet sand specular & subtle sunlit cliff rim sheen.
		vec3 h_vec = normalize(VIEW + LIGHT);
		float ndh = clamp(dot(NORMAL, h_vec), 0.0, 1.0);
		float spec_pow = mix(14.0, 120.0, wet_m);
		float spec_amp = mix(0.06, 0.55, wet_m);
		SPECULAR_LIGHT += pow(ndh, spec_pow) * spec_amp * ndl * ATTENUATION * LIGHT_COLOR * sun;
	} else {
		// Point/spot lights (campfires, tavern/dock/beacon lanterns).
		DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;
		vec3 h_vec = normalize(VIEW + LIGHT);
		float ndh = clamp(dot(NORMAL, h_vec), 0.0, 1.0);
		float spec_pow = mix(16.0, 72.0, wet_m);
		SPECULAR_LIGHT += pow(ndh, spec_pow) * (0.08 + 0.35 * wet_m) * ndl * ATTENUATION * LIGHT_COLOR;
	}
}
