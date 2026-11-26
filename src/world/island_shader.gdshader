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
uniform vec3 wet_sand_color : source_color = vec3(0.71, 0.56, 0.31);
uniform vec3 dry_sand_color : source_color = vec3(0.89, 0.77, 0.50);
uniform vec3 grass_deep_color : source_color = vec3(0.14, 0.37, 0.12);
uniform vec3 grass_sun_color : source_color = vec3(0.40, 0.63, 0.17);
uniform vec3 cliff_warm_color : source_color = vec3(0.79, 0.66, 0.47);
uniform vec3 cliff_pale_color : source_color = vec3(0.90, 0.85, 0.74);
uniform vec3 cliff_dark_color : source_color = vec3(0.56, 0.50, 0.43);
uniform vec3 sea_moss_color : source_color = vec3(0.22, 0.27, 0.20);

uniform vec3 cliff_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float cliff_facet_strength : hint_range(0.0, 1.0) = 0.72;

varying vec3 v_world;
varying vec3 v_world_normal;
varying vec3 v_view_up;

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
	v_view_up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec3 smooth_n = normalize(v_world_normal);
	float h = v_world.y;
	vec2 xz = v_world.xz;

	// Compute crisp geometric facet normal early so spire apexes (where smooth_n.y -> 1.0)
	// evaluate cliff slope accurately and never receive green grass triangle caps.
	vec3 dpdx = dFdx(v_world);
	vec3 dpdy = dFdy(v_world);
	vec3 raw_face_n = cross(dpdy, dpdx);
	float fn_len = length(raw_face_n);
	vec3 face_n = fn_len > 1e-5 ? (raw_face_n / fn_len) : smooth_n;
	face_n *= (dot(face_n, smooth_n) >= 0.0) ? 1.0 : -1.0;

	// Zero-tiling world-space painterly brush & wind-ripple noise fields.
	float macro_n = fbm2(xz * 0.032);
	float brush_n = fbm2(xz * 0.14 + vec2(macro_n * 2.6, -macro_n * 2.1));
	float grain_n = vnoise2(xz * 0.72 + vec2(brush_n * 1.4));
	float ripple_n = sin(xz.x * 0.42 + xz.y * 0.35 + macro_n * 4.5) * 0.5 + 0.5;

	// Subtle trade-wind sand drifts and ripples for painterly broad beaches.
	vec2 wind_uv = vec2(xz.x * 0.78 + xz.y * 0.62, -xz.x * 0.62 + xz.y * 0.78);
	float dune_drift = fbm2(vec2(wind_uv.x * 0.075, wind_uv.y * 0.22) + vec2(macro_n * 1.6, -macro_n * 1.1));
	float sand_ripple_phase = wind_uv.y * 2.35 + dune_drift * 5.2 + brush_n * 1.8;
	float sand_ripple = smoothstep(0.18, 0.82, sin(sand_ripple_phase) * 0.5 + 0.5);
	float sand_wave = mix(dune_drift, sand_ripple, 0.42);

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

	// Low-contrast warm wind-ripple variation across the dry sand beach band.
	float beach_band = smoothstep(0.55, 1.15, h_org) * smoothstep(3.15, 2.35, h_org);
	vec3 sand_trough = dry_sand_color * vec3(0.95, 0.90, 0.83);
	vec3 sand_crest = dry_sand_color * vec3(1.05, 1.04, 1.00);
	float sand_t = mix(brush_n * 0.65 + ripple_n * 0.35, sand_wave, 0.62 * beach_band);
	vec3 col_dry = mix(sand_trough, sand_crest, sand_t) * mix(0.97, 1.03, grain_n);

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

	// --- Bold chunky faceted sunlit limestone / warm ochre coastal cliffs ---
	// Organic warped sedimentary drift & ochre washes (no harsh periodic sine stripes).
	float drift_n = fbm2(vec2(h * 0.075 + macro_n * 1.85, (xz.x - xz.y) * 0.028 + brush_n * 1.15));
	float ochre_wash = fbm2(vec2(h * 0.048 - macro_n * 1.4, (xz.x + xz.y) * 0.036));
	float strata_soft = smoothstep(0.28, 0.78, drift_n);
	float height_pale = smoothstep(4.0, 22.0, h + (macro_n - 0.5) * 6.0);

	// Subtle per-facet tonal variation emphasizes sculpted monolithic cliff planes.
	float facet_var = clamp(face_n.x * 0.35 - face_n.z * 0.30 + face_n.y * 0.45, -0.5, 0.5);
	float ivory_mix = clamp(height_pale * 0.72 + strata_soft * 0.24 + facet_var * 0.16, 0.0, 1.0);
	vec3 cliff_base = mix(cliff_warm_color, cliff_pale_color, ivory_mix);
	cliff_base = mix(cliff_base, cliff_warm_color * vec3(1.04, 0.98, 0.90),
			smoothstep(0.52, 0.85, ochre_wash) * 0.28 * (1.0 - height_pale * 0.45));
	float weather_shade = (1.0 - brush_n) * 0.11 + smoothstep(0.76, 0.95, 1.0 - drift_n) * 0.08;
	cliff_base = mix(cliff_base, cliff_dark_color, weather_shade);
	// Wet sea-line algae/barnacle band where rocky cliffs plunge into the surf.
	float sea_band = smoothstep(-2.4, -0.2, h) * smoothstep(2.2, 0.45, h + (brush_n - 0.5) * 0.5);
	cliff_base = mix(cliff_base, sea_moss_color, sea_band * 0.58);
	cliff_base *= cliff_tint;

	// Slope-driven cliff mask using min(smooth_n.y, face_n.y) + rocky summits above 14-24 m.
	float cliff_ny = min(smooth_n.y, face_n.y);
	float slope_cliff = smoothstep(0.76, 0.56, cliff_ny + (brush_n - 0.5) * 0.09);
	float summit_rock = smoothstep(14.0, 24.0, h_org);
	float cliff_mask = clamp(max(slope_cliff, summit_rock), 0.0, 1.0);
	cliff_mask *= mix(smoothstep(0.55, 0.35, cliff_ny), 1.0, smoothstep(-1.8, 0.35, h));

	// Subtle per-vertex tint (crevice AO / volcanic rim / coastal paths).
	vec3 albedo = mix(ground_col, cliff_base, cliff_mask) * COLOR.rgb;

	// Gentle wind-ripple normal modeling on dry beaches + crisp geometric facets on cliffs.
	float ripple_slope = cos(sand_ripple_phase);
	vec3 beach_n = normalize(smooth_n + vec3(-0.62, 0.0, 0.78) * (ripple_slope * 0.042 * beach_band));
	vec3 final_n_world = normalize(mix(beach_n, face_n, cliff_mask * cliff_facet_strength));
	float facet_pop = clamp(dot(face_n, smooth_n), 0.75, 1.0);
	albedo *= mix(1.0, 0.92 + 0.12 * facet_pop, cliff_mask);

	// Surface roughness & specular: glistening wet sand, dry matte sand, textured cliffs.
	float wet_mask = t_wet_in * (1.0 - t_dry_in) * (1.0 - cliff_mask * 0.85);
	float rough = mix(0.92, 0.86, t_shallow);
	rough = mix(rough, mix(0.28, 0.40, grain_n), wet_mask);
	rough = mix(rough, mix(0.86, 0.91, sand_wave), t_dry_in * (1.0 - t_grass_in));
	rough = mix(rough, 0.84, t_grass_in);
	rough = mix(rough, mix(0.78, 0.92, 1.0 - strata_soft), cliff_mask);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.28, 0.44, wet_mask);
	NORMAL = normalize((VIEW_MATRIX * vec4(final_n_world, 0.0)).xyz);
}

void light() {
	// Per-pixel drifting cloud shadows on directional sunlight (never on lanterns/fires).
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(v_world.xz) : 1.0;
	float ndl_raw = dot(NORMAL, LIGHT);
	float ndl = clamp(ndl_raw, 0.0, 1.0);
	float face_up_n = dot(NORMAL, normalize(v_view_up));
	float up_n = min(normalize(v_world_normal).y, face_up_n);
	float cliff_m = clamp(max(smoothstep(0.76, 0.56, up_n), smoothstep(14.0, 24.0, v_world.y)), 0.0, 1.0);
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
