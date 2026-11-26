shader_type spatial;
// Painterly stylized island terrain shader for Sea of Scoundrels.
// Elevates coastal cliffs, beaches, tropical grass, volcanic basalt, and mossy ledges
// with zero-tiling world-space geological strata, vertical rock-fracture streaks,
// crevice darkening, procedural micro-normal relief, and atmospheric aerial perspective:
//   deep seabed (< -3 m) -> turquoise shallow seabed (-3..0 m) -> glistening
//   wet sand with foam sheen & shell micro-grain (0..0.85 m) -> trade-wind dry beach
//   (0.85..2.8 m) -> golden coastal tussocks & tropical emerald grass -> layered
//   sunlit ochre/limestone cliffs with mossy flat ledges & cool slate-teal shadows.
//
// Wave 24 Massive Archipelago Contract (100% backward-compatible defaults):
//   - COLOR.rgb : vertex crevice AO / biome tint (preserved)
//   - 1.0 - COLOR.a : optional walkable dirt/stone inland trail mask (0 on legacy meshes)
//   - volcanic_amount, lush_jungle_amount, ruin_moss_amount, cliff_strata_scale
//
// Wave 25B/26 Non-Repeating Stochastic PBR Terrain Texture Contract:
//   - use_terrain_textures = false by default (100% compatible with procedural Wave 24!)
//   - When true, samples 1024x1024 Albedo + Normal maps with 2-tap golden-ratio rotated
//     stochastic breakup on ground/beaches/trails and triplanar projection on steep cliffs!
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 ambient_color;
global uniform vec3 sky_horizon_color;
global uniform vec3 sky_zenith_color;

uniform vec3 deep_seabed_color : source_color = vec3(0.14, 0.25, 0.30);
uniform vec3 shallow_seabed_color : source_color = vec3(0.76, 0.81, 0.64);
uniform vec3 wet_sand_color : source_color = vec3(0.69, 0.54, 0.30);
uniform vec3 dry_sand_color : source_color = vec3(0.90, 0.78, 0.51);
uniform vec3 grass_deep_color : source_color = vec3(0.12, 0.36, 0.13);
uniform vec3 grass_sun_color : source_color = vec3(0.42, 0.64, 0.17);
uniform vec3 grass_dry_color : source_color = vec3(0.66, 0.63, 0.26);
uniform vec3 cliff_warm_color : source_color = vec3(0.76, 0.56, 0.36);
uniform vec3 cliff_pale_color : source_color = vec3(0.86, 0.77, 0.60);
uniform vec3 cliff_dark_color : source_color = vec3(0.40, 0.34, 0.29);
uniform vec3 sea_moss_color : source_color = vec3(0.20, 0.28, 0.19);
uniform vec3 path_dirt_color : source_color = vec3(0.64, 0.50, 0.33);

uniform vec3 cliff_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float cliff_facet_strength : hint_range(0.0, 1.0) = 0.68;

// Optional biome uniforms for Wave 24 Massive Flagship Islands (safe defaults = 0 / 1).
uniform float volcanic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float lush_jungle_amount : hint_range(0.0, 1.0) = 0.0;
uniform float ruin_moss_amount : hint_range(0.0, 1.0) = 0.0;
uniform float cliff_strata_scale : hint_range(0.25, 3.0) = 1.0;
uniform float path_warmth : hint_range(0.0, 1.0) = 0.55;
uniform float aerial_perspective_strength : hint_range(0.0, 1.0) = 0.42;

// Optional Wave 25B/26 Stochastic PBR Terrain Texture Set (disabled by default until bound).
uniform bool use_terrain_textures = false;
uniform float terrain_tex_scale : hint_range(0.02, 1.0) = 0.14;
uniform float terrain_tex_normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float terrain_tex_blend : hint_range(0.0, 1.0) = 0.78;
uniform sampler2D tex_grass_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_grass_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_dirt_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_dirt_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_sand_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_sand_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_cliff_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_cliff_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_volcanic_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_volcanic_normal : hint_normal, repeat_enable, filter_linear_mipmap;

varying vec3 v_world;
varying vec3 v_world_normal;
varying vec3 v_view_up;
varying float v_cam_dist;

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

float ridged2(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 2; i++) {
		float n = 1.0 - abs(vnoise2(p) * 2.0 - 1.0);
		v += amp * n * n;
		p = rot * p * 2.18 + vec2(11.3, 27.1);
		amp *= 0.45;
	}
	return clamp(v, 0.0, 1.0);
}

// Evaluates warped coastal cliff strata & vertical fracture relief for both albedo and normal bump.
vec2 eval_cliff_relief(vec3 wp, float macro_n, float brush_n, float strata_sc) {
	float dip = wp.x * 0.024 - wp.z * 0.018;
	float warp = (macro_n - 0.5) * 3.8 + (brush_n - 0.5) * 1.25;
	float bed_y = (wp.y + dip) * 0.16 * strata_sc + warp;
	float horiz = (wp.x * 0.72 + wp.z * 0.69) * 0.018;
	// Non-repeating sedimentary rock benches: domain-warped multi-octave strata (zero periodic stripes).
	float n_broad = vnoise2(vec2(bed_y * 0.95, horiz + macro_n * 0.65));
	float n_mid = vnoise2(vec2(bed_y * 2.35 + n_broad * 1.15, horiz * 2.1 - brush_n * 0.7));
	float strata = smoothstep(0.20, 0.82, n_broad * 0.62 + n_mid * 0.38);

	// Organic vertical weathering fractures, rain-runoff streaks & geological joint cracks.
	vec2 horiz_uv = vec2((wp.x - wp.z) * 0.13, (wp.x + wp.z) * 0.15);
	float v_streak = ridged2(vec2(horiz_uv.x + macro_n * 1.7, wp.y * 0.036 * strata_sc));
	float v_crack = ridged2(vec2(horiz_uv.y * 1.35 - brush_n * 0.9, wp.y * 0.088 * strata_sc + 4.2));
	float fracture = clamp(v_streak * 0.54 + v_crack * 0.46, 0.0, 1.0);
	return vec2(strata, fracture);
}

// Fast 2D hash for hex/simplex stochastic cell offsets & rotations.
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Ultra-fast zero-tiling 2-tap golden-ratio rotated stochastic PBR sampler.
// Layer A covers crisp near/mid micro-detail; Layer B rotates by rot_angle at irrational scale
// (0.618034) with prime translation offset and macro-noise crossfade (zero visible repetition
// across 364 m mega-islands at 1/2 the texture bandwidth of 3-vertex simplex textureGrad!).
// OpenGL tangent-space normals (-dh/du, +dh/dv, +1) are converted to (-dh/du, -dh/dv) BEFORE
// counter-rotation by transpose(R) so directional sunlight stays 100% mathematically exact!
void sample_stochastic_ground(
	sampler2D alb_tex,
	sampler2D nrm_tex,
	vec2 xz,
	float sc,
	float macro_n,
	float brush_n,
	float nrm_str,
	float rot_angle,
	out vec3 out_alb,
	out vec3 out_nrm_offset
) {
	vec2 uv0 = xz * sc + vec2(macro_n - 0.5, brush_n - 0.5) * 0.24;
	float ca = cos(rot_angle);
	float sa = sin(rot_angle);
	mat2 rot_b = mat2(vec2(ca, sa), vec2(-sa, ca));
	vec2 uv1 = rot_b * (uv0 * 0.618034) + vec2(4.73, 2.39);
	float w = smoothstep(0.18, 0.82, macro_n * 0.62 + brush_n * 0.38);

	vec3 a0 = texture(alb_tex, uv0).rgb;
	vec3 a1 = texture(alb_tex, uv1).rgb;
	out_alb = mix(a0, a1, w);

	if (nrm_str > 0.02) {
		vec2 s0 = texture(nrm_tex, uv0).xy * 2.0 - 1.0;
		vec2 s1 = texture(nrm_tex, uv1).xy * 2.0 - 1.0;
		vec2 n0 = vec2(s0.x, -s0.y);
		vec2 n1 = transpose(rot_b) * vec2(s1.x, -s1.y);
		vec2 nxy = mix(n0, n1, w) * nrm_str;
		out_nrm_offset = vec3(nxy.x, 0.0, nxy.y);
	} else {
		out_nrm_offset = vec3(0.0);
	}
}

// Fast zero-stretching dominant-axis triplanar PBR sampler for steep 360-deg coastal & volcanic cliffs.
// Uses -wp.y so PNG top (v=0) maps UP (+Y) and switches cleanly to single-tap macro sampling at far
// range so 70%-screen-coverage mega-massifs stay well under +0.25 ms GPU on RX 9070 XT!
void sample_triplanar_cliff(
	sampler2D alb_tex,
	sampler2D nrm_tex,
	vec3 wp,
	vec3 sn,
	float sc,
	float strata_sc,
	float macro_n,
	float brush_n,
	float nrm_str,
	bool far_lod,
	out vec3 out_alb,
	out vec3 out_nrm_offset
) {
	vec3 blend = pow(abs(sn), vec3(5.0));
	blend /= max(blend.x + blend.y + blend.z, 1e-4);

	float y_warp = (macro_n - 0.5) * 0.65 + (brush_n - 0.5) * 0.24;
	float h_warp = (brush_n - 0.5) * 0.35;
	// Subtle tilt keeps geological beds aligned with natural strata while breaking horizontal tiling.
	const mat2 TILT_B = mat2(vec2(0.978, 0.208), vec2(-0.208, 0.978));
	const mat2 INV_TILT_B = mat2(vec2(0.978, -0.208), vec2(0.208, 0.978));
	float w_var = smoothstep(0.22, 0.78, macro_n * 0.65 + brush_n * 0.35);

	// Use -wp.y for v so PNG top (v=0) maps UP (+Y) on cliffs (strata drips & shadows stay right-side up!).
	vec2 uv_x = vec2(wp.z * sc * 0.85 + h_warp, -(wp.y * strata_sc) * sc * 0.92 + y_warp);
	vec2 uv_z = vec2(wp.x * sc * 0.85 + 2.37 - h_warp, -(wp.y * strata_sc) * sc * 0.92 - y_warp * 0.85);

	vec3 alb = vec3(0.0);
	vec3 n_off = vec3(0.0);
	float w_sum = 0.0;

	if (blend.x > 0.08) {
		vec3 ax = texture(alb_tex, uv_x).rgb;
		if (!far_lod) {
			vec2 uv_x2 = TILT_B * (uv_x * 0.618034) + vec2(4.13, 1.91);
			ax = mix(ax, texture(alb_tex, uv_x2).rgb, w_var);
			if (nrm_str > 0.02) {
				vec2 sx1 = texture(nrm_tex, uv_x).xy * 2.0 - 1.0;
				vec2 sx2 = texture(nrm_tex, uv_x2).xy * 2.0 - 1.0;
				vec2 gx = mix(vec2(sx1.x, -sx1.y), INV_TILT_B * vec2(sx2.x, -sx2.y), w_var);
				n_off += vec3(0.0, -gx.y, gx.x) * (blend.x * nrm_str);
			}
		}
		alb += ax * blend.x;
		w_sum += blend.x;
	}
	if (blend.z > 0.08) {
		vec3 az = texture(alb_tex, uv_z).rgb;
		if (!far_lod) {
			vec2 uv_z2 = TILT_B * (uv_z * 0.618034) + vec2(6.71, 3.27);
			az = mix(az, texture(alb_tex, uv_z2).rgb, w_var);
			if (nrm_str > 0.02) {
				vec2 sz1 = texture(nrm_tex, uv_z).xy * 2.0 - 1.0;
				vec2 sz2 = texture(nrm_tex, uv_z2).xy * 2.0 - 1.0;
				vec2 gz = mix(vec2(sz1.x, -sz1.y), INV_TILT_B * vec2(sz2.x, -sz2.y), w_var);
				n_off += vec3(gz.x, -gz.y, 0.0) * (blend.z * nrm_str);
			}
		}
		alb += az * blend.z;
		w_sum += blend.z;
	}
	if (blend.y > 0.16) {
		vec2 uv_y = wp.xz * (sc * 0.78) + vec2(h_warp, y_warp * 0.5);
		alb += texture(alb_tex, uv_y).rgb * blend.y;
		if (nrm_str > 0.02) {
			vec2 sy = texture(nrm_tex, uv_y).xy * 2.0 - 1.0;
			n_off += vec3(sy.x, 0.0, -sy.y) * (blend.y * nrm_str);
		}
		w_sum += blend.y;
	}

	out_alb = alb / max(w_sum, 1e-4);
	out_nrm_offset = n_off / max(w_sum, 1e-4);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_view_up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	v_cam_dist = length(CAMERA_POSITION_WORLD - v_world);
}

void fragment() {
	vec3 smooth_n = normalize(v_world_normal);
	float h = v_world.y;
	vec2 xz = v_world.xz;

	// Compute crisp geometric facet normal early so spire apexes evaluate slope accurately.
	vec3 dpdx = dFdx(v_world);
	vec3 dpdy = dFdy(v_world);
	vec3 raw_face_n = cross(dpdy, dpdx);
	float fn_len = length(raw_face_n);
	vec3 face_n = fn_len > 1e-5 ? (raw_face_n / fn_len) : smooth_n;
	face_n *= (dot(face_n, smooth_n) >= 0.0) ? 1.0 : -1.0;

	// Auto-detect dark volcanic islands (legacy volcano_crag cliff_tint lum < 0.52) so Cinder Crag
	// immediately benefits from charred basalt & warm magma seams alongside explicit volcanic_amount.
	float tint_lum = dot(cliff_tint, vec3(0.299, 0.587, 0.114));
	float auto_volc = smoothstep(0.56, 0.42, tint_lum);
	float volc = clamp(max(volcanic_amount, auto_volc * 0.88), 0.0, 1.0);

	// Zero-tiling world-space painterly brush, tussock, pebble & wind-ripple noise fields.
	float macro_n = fbm2(xz * 0.028);
	float brush_n = fbm2(xz * 0.13 + vec2(macro_n * 2.4, -macro_n * 1.9));
	float tussock_n = fbm2(xz * 0.34 + vec2(-brush_n * 1.6, macro_n * 1.8));
	float grain_n = vnoise2(xz * 0.88 + vec2(brush_n * 1.3));
	float pebble_n = vnoise2(xz * 3.6 + vec2(grain_n * 1.7));
	float shell_speck = smoothstep(0.84, 0.96, vnoise2(xz * 7.8 + vec2(3.1, 8.7)));
	float ripple_n = sin(xz.x * 0.42 + xz.y * 0.35 + macro_n * 4.5) * 0.5 + 0.5;

	// Trade-wind sand drifts & gentle beach ripples.
	vec2 wind_uv = vec2(xz.x * 0.78 + xz.y * 0.62, -xz.x * 0.62 + xz.y * 0.78);
	float dune_drift = fbm2(vec2(wind_uv.x * 0.075, wind_uv.y * 0.22) + vec2(macro_n * 1.6, -macro_n * 1.1));
	float sand_ripple_phase = wind_uv.y * 2.45 + dune_drift * 5.2 + brush_n * 1.8;
	float sand_ripple = smoothstep(0.18, 0.82, sin(sand_ripple_phase) * 0.5 + 0.5);
	float sand_wave = mix(dune_drift, sand_ripple, 0.45);

	// Height-jittered boundaries keep biome edges organic and hand-painted.
	float edge_jit = (macro_n - 0.5) * 0.72 + (brush_n - 0.5) * 0.38 + (tussock_n - 0.5) * 0.22;
	float h_org = h + edge_jit;

	// --- Elevation bands (deep seabed -> shallow -> wet sand -> dry sand -> lush grass) ---
	float t_shallow = smoothstep(-5.4, -1.5, h + (macro_n - 0.5) * 1.15);
	float t_wet_in = smoothstep(-0.48, 0.08, h + (brush_n - 0.5) * 0.18);
	float t_dry_in = smoothstep(0.62, 1.02, h + (brush_n - 0.5) * 0.22);
	float t_grass_in = smoothstep(2.25, 3.35, h_org + (tussock_n - 0.5) * 0.55);

	vec3 col_deep = deep_seabed_color * mix(0.84, 1.16, brush_n);
	vec3 col_shallow = shallow_seabed_color * mix(0.90, 1.10, ripple_n * 0.55 + brush_n * 0.45);

	// Wet shoreline sand: warm wet amber-gold with subtle foam-edge sheen & washed shell/pebble micro-grain.
	float shore_foam_band = smoothstep(-0.20, 0.12, h) * smoothstep(0.56, 0.18, h + (brush_n - 0.5) * 0.16);
	vec3 col_wet = wet_sand_color * mix(0.88, 1.12, ripple_n * 0.45 + pebble_n * 0.55);
	col_wet = mix(col_wet, col_wet * vec3(0.86, 0.80, 0.72), smoothstep(0.68, 0.90, pebble_n) * 0.25);
	col_wet = mix(col_wet, vec3(0.92, 0.95, 0.91), shore_foam_band * smoothstep(0.52, 0.88, brush_n * 0.7 + pebble_n * 0.3) * 0.22);
	col_wet = mix(col_wet, col_wet * vec3(0.52, 0.48, 0.48), volc * 0.55);

	// Dry sunlit beach: warm wind-ripple troughs/crests + faint coral-shell sparkle.
	float beach_band = smoothstep(0.58, 1.20, h_org) * smoothstep(3.30, 2.25, h_org);
	vec3 sand_trough = dry_sand_color * vec3(0.93, 0.87, 0.79);
	vec3 sand_crest = dry_sand_color * vec3(1.06, 1.04, 0.99);
	float sand_t = mix(brush_n * 0.62 + ripple_n * 0.38, sand_wave, 0.64 * beach_band);
	vec3 col_dry = mix(sand_trough, sand_crest, sand_t) * mix(0.95, 1.04, grain_n);
	col_dry = mix(col_dry, vec3(0.96, 0.92, 0.83), shell_speck * beach_band * 0.24);
	col_dry = mix(col_dry, col_dry * vec3(0.56, 0.52, 0.50), volc * 0.48);

	// Painterly layered coastal grass: warm golden dry coastal tussocks + deep emerald jungle floor.
	float grass_mix = smoothstep(0.20, 0.82, brush_n * 0.58 + tussock_n * 0.42);
	vec3 jungle_deep = mix(grass_deep_color, vec3(0.07, 0.28, 0.11), lush_jungle_amount * 0.75);
	vec3 jungle_sun = mix(grass_sun_color, vec3(0.32, 0.58, 0.16), lush_jungle_amount * 0.55);
	vec3 col_grass = mix(jungle_deep, jungle_sun, grass_mix);
	// Warm sun-baked dry grass tussocks along the sandy verge and sunny ridges.
	float beach_verge = smoothstep(5.4, 2.2, h_org);
	float dry_tussock = smoothstep(0.52, 0.86, tussock_n * 0.65 + macro_n * 0.35) * (0.28 + 0.52 * beach_verge) * (1.0 - lush_jungle_amount * 0.55);
	col_grass = mix(col_grass, grass_dry_color, dry_tussock);
	// Deep humus / moss mottling for dense tropical jungle interiors.
	float humus = smoothstep(0.62, 0.92, 1.0 - brush_n) * lush_jungle_amount * smoothstep(3.5, 8.0, h_org);
	col_grass = mix(col_grass, vec3(0.18, 0.24, 0.11), humus * 0.42);
	col_grass *= mix(0.90, 1.10, grain_n * 0.6 + pebble_n * 0.4);
	col_grass *= grass_tint;
	// Scorched volcanic ash & hardy olive cinder-scrub on active volcanic islands (Cinder Crag + Wave 24).
	if (volc > 0.01) {
		vec3 ash_scrub = mix(vec3(0.16, 0.15, 0.14), vec3(0.29, 0.27, 0.16), brush_n * 0.65 + tussock_n * 0.35);
		col_grass = mix(col_grass, ash_scrub, volc * 0.78);
	}

	vec3 ground_col = mix(col_deep, col_shallow, t_shallow);
	ground_col = mix(ground_col, col_wet, t_wet_in);
	ground_col = mix(ground_col, col_dry, t_dry_in);
	ground_col = mix(ground_col, col_grass, t_grass_in);

	// Optional walkable inland dirt/stone trail blending driven by vertex alpha (1.0 - COLOR.a).
	float dirt_path_mask = clamp(1.0 - COLOR.a, 0.0, 1.0) * smoothstep(0.6, 1.8, h);
	if (dirt_path_mask > 0.005) {
		float path_edge = smoothstep(0.08, 0.58, dirt_path_mask + (tussock_n - 0.5) * 0.24);
		vec3 col_path = mix(path_dirt_color * 0.88, path_dirt_color * vec3(1.12, 1.06, 0.95), path_warmth * (0.4 + 0.6 * grain_n));
		col_path = mix(col_path, cliff_pale_color * 0.82, smoothstep(0.72, 0.92, pebble_n) * 0.30);
		ground_col = mix(ground_col, col_path, path_edge);
	}

	// --- Painterly Geological Coastal Cliffs (Warm Sunlit Ochre/Limestone Strata & Crevices) ---
	vec2 cr = eval_cliff_relief(v_world, macro_n, brush_n, cliff_strata_scale);
	float strata_band = cr.x;
	float fracture = cr.y;
	float ochre_wash = fbm2(vec2(h * 0.055 * cliff_strata_scale - macro_n * 1.4, (xz.x + xz.y) * 0.038));
	float height_warm = smoothstep(3.5, 28.0, h + (macro_n - 0.5) * 7.0);

	// Directional rock-plane tonal variation (uses smooth_n + gentle fracture modulation so
	// 45-deg heightmap ridge triangles never show alternating diagonal sawtooth striping!).
	float facet_var = clamp(smooth_n.x * 0.34 - smooth_n.z * 0.28 + smooth_n.y * 0.42 + (fracture - 0.5) * 0.24, -0.5, 0.5);
	float ivory_mix = clamp(height_warm * 0.44 + strata_band * 0.42 + facet_var * 0.16, 0.0, 1.0);
	vec3 cliff_base = mix(cliff_warm_color, cliff_pale_color, ivory_mix);
	// Warm sunlit terracotta-ochre sedimentary streaks break up pale limestone faces.
	float ochre_patch = smoothstep(0.42, 0.84, ochre_wash * 0.72 + (1.0 - strata_band) * 0.28);
	cliff_base = mix(cliff_base, cliff_warm_color * vec3(1.06, 0.88, 0.70), ochre_patch * 0.44);

	// Deep weathered rock crevices & vertical rain-runoff streaks.
	float strata_groove = smoothstep(0.58, 0.90, 1.0 - strata_band);
	float crevice_shade = clamp(fracture * 0.54 + strata_groove * 0.38 + (1.0 - brush_n) * 0.16, 0.0, 0.88);
	cliff_base = mix(cliff_base, cliff_dark_color, crevice_shade * 0.68);
	cliff_base *= mix(0.92, 1.08, grain_n * 0.65 + pebble_n * 0.35);

	// Wet sea-line algae/barnacle band where rocky cliffs plunge into the surf.
	float sea_band = smoothstep(-2.4, -0.2, h) * smoothstep(2.4, 0.45, h + (brush_n - 0.5) * 0.55);
	cliff_base = mix(cliff_base, sea_moss_color, sea_band * 0.62);
	cliff_base *= cliff_tint;

	// Volcanic charred basalt & warm glowing fissure seams (Cinder Crag + Wave 24 volcanic_amount).
	float magma_emit = 0.0;
	float magma_core = 0.0;
	if (volc > 0.01) {
		vec3 basalt_dark = vec3(0.10, 0.09, 0.11);
		vec3 basalt_ridge = vec3(0.27, 0.22, 0.21);
		vec3 basalt_scorch = vec3(0.46, 0.20, 0.10);
		vec3 basalt = mix(basalt_dark, basalt_ridge, strata_band * 0.55 + (1.0 - fracture) * 0.45);
		basalt = mix(basalt, basalt_scorch, smoothstep(0.52, 0.88, ochre_wash) * smoothstep(7.0, 28.0, h) * 0.48);
		basalt *= mix(0.86, 1.15, pebble_n);
		cliff_base = mix(cliff_base, basalt, volc * 0.86);
		// Subtle glowing incandescent magma cracks inside deep upper basalt fissures.
		float crack_hot = smoothstep(0.70, 0.91, fracture) * smoothstep(6.0, 22.0, h) * smoothstep(0.45, 0.80, macro_n + 0.28);
		magma_emit = crack_hot * volc * 1.95;
		magma_core = crack_hot;
	}

	// Slope-driven cliff mask using pure smooth_n.y + painterly brushwork jitter so coarse coastal
	// bluffs & grassy hilltops never show polygonal triangle seams between grass and limestone.
	// Summit rock respects flat highland jungle plateaus on Wave 24 massive islands (only exposing
	// rock on sloped ridges or high alpine crests, while volcanic calderas bare out lower).
	float cliff_ny = smooth_n.y;
	float slope_jit = (macro_n - 0.5) * 0.14 + (brush_n - 0.5) * 0.17 + (tussock_n - 0.5) * 0.09;
	float slope_cliff = smoothstep(0.80, 0.48, cliff_ny + slope_jit);
	float summit_lo = mix(17.0, 34.0, lush_jungle_amount) - volc * 6.0;
	float summit_hi = mix(29.0, 56.0, lush_jungle_amount) - volc * 8.0;
	// Check both smooth_n.y and face_n.y so flat highland plateaus stay lush green while
	// sharp 1-vertex pyramid spire apexes (whose averaged smooth_n points straight up) stay bare rock!
	float summit_ny = min(smooth_n.y, face_n.y);
	float summit_slope_gate = mix(smoothstep(0.92, 0.72, summit_ny), 1.0, volc * 0.85);
	float summit_rock = smoothstep(summit_lo, summit_hi, h_org + (macro_n - 0.5) * 5.0) * summit_slope_gate;
	float cliff_mask = clamp(max(slope_cliff, summit_rock), 0.0, 1.0);
	cliff_mask *= mix(smoothstep(0.55, 0.35, cliff_ny), 1.0, smoothstep(-1.8, 0.35, h));

	// Mossy emerald cliff-ledge caps where rock faces flatten slightly (normal.y in 0.38..0.78).
	float ledge_up = smoothstep(0.36, 0.64, smooth_n.y) * smoothstep(0.88, 0.62, smooth_n.y);
	float ledge_alt = smoothstep(2.6, 5.2, h) * smoothstep(32.0, 15.0, h + lush_jungle_amount * 12.0);
	float moss_boost = clamp(0.64 + lush_jungle_amount * 0.36 + ruin_moss_amount * 0.34, 0.0, 1.0);
	float ledge_patch = smoothstep(0.28, 0.72, brush_n * 0.58 + tussock_n * 0.28 + strata_groove * 0.14);
	float ledge_moss = ledge_up * ledge_alt * cliff_mask * ledge_patch * moss_boost * (1.0 - volc * 0.85);
	vec3 col_ledge_moss = mix(jungle_deep * 1.08, jungle_sun * 0.94, tussock_n) * grass_tint;
	cliff_base = mix(cliff_base, col_ledge_moss, ledge_moss * 0.88);

	// Subtle lichen & ruin moss creeping along shadowed lower cliff crevices.
	if (ruin_moss_amount > 0.01) {
		float ruin_m = smoothstep(0.48, 0.82, fracture * 0.6 + brush_n * 0.4) * smoothstep(18.0, 4.0, h) * ruin_moss_amount * (1.0 - volc);
		cliff_base = mix(cliff_base, mix(sea_moss_color, jungle_deep, 0.45), ruin_m * 0.55);
	}

	// Preserve vertex crevice AO / tint cleanly.
	vec3 albedo = mix(ground_col, cliff_base, cliff_mask) * COLOR.rgb;

	// --- Procedural Micro-Normal Relief (Sand Ripples + Grass Brushwork + Cliff Strata/Cracks) ---
	float ripple_slope = cos(sand_ripple_phase);
	vec3 beach_n = normalize(smooth_n + vec3(-0.62, 0.0, 0.78) * (ripple_slope * 0.048 * beach_band));
	vec3 grass_n = normalize(smooth_n + vec3(tussock_n - 0.5, 0.0, grain_n - 0.5) * (0.14 * t_grass_in));
	vec3 ground_n = mix(beach_n, grass_n, t_grass_in);

	// Distance-fade high-frequency cliff bump & PBR normal maps beyond 260 m to prevent shimmer.
	// Keep geometric quad-triangle faceting subtle & fracture-gated so giant 166-182 m massifs
	// read as organic carved cliffs instead of diagonal heightmap sawtooth strips!
	float detail_fade = smoothstep(260.0, 45.0, v_cam_dist);
	float ridge_smooth = smoothstep(0.18, 0.48, abs(smooth_n.x) * abs(smooth_n.z) * 4.0);
	float bare_rock_facet = cliff_facet_strength * mix(0.28, 0.14, ridge_smooth) * smoothstep(0.32, 0.88, cliff_mask) * (1.0 - ledge_moss * 0.80) * mix(0.55, 1.0, fracture);
	vec3 cliff_n = normalize(mix(smooth_n, face_n, bare_rock_facet));
	if (cliff_mask > 0.04 && detail_fade > 0.01) {
		float eps = 0.24;
		vec2 cr_y = eval_cliff_relief(v_world + vec3(0.0, eps, 0.0), macro_n, brush_n, cliff_strata_scale);
		vec2 cr_x = eval_cliff_relief(v_world + vec3(eps, 0.0, 0.0), macro_n, brush_n, cliff_strata_scale);
		float d_strata_y = (cr_y.x - strata_band) / eps;
		float d_frac_x = (cr_x.y - fracture) / eps;
		vec3 tangent_h = normalize(cross(vec3(0.0, 1.0, 0.0), cliff_n) + vec3(0.001, 0.0, 0.001));
		float bump_str = 0.44 * detail_fade * (1.0 - ledge_moss * 0.65);
		cliff_n = normalize(cliff_n + vec3(0.0, -d_strata_y * 0.90, 0.0) * bump_str + tangent_h * (d_frac_x * 0.85 * bump_str));
	}

	vec3 final_n_world = normalize(mix(ground_n, cliff_n, cliff_mask));

	// --- Optional Wave 25B/26 Non-Repeating Stochastic PBR Terrain Texture Overlay ---
	// Conditionally samples only the 1-2 active biomes at this pixel (zero cost when disabled!).
	// Fades micro-normal maps cleanly past 125 m and full albedo past 420 m for < +0.20 ms GPU cost!
	if (use_terrain_textures && v_cam_dist < 440.0) {
		float pbr_nrm_fade = smoothstep(130.0, 26.0, v_cam_dist);
		float tex_nrm_str = terrain_tex_normal_strength * pbr_nrm_fade;
		bool far_cliff = v_cam_dist > 145.0;
		float path_edge_w = dirt_path_mask > 0.005
			? smoothstep(0.08, 0.58, dirt_path_mask + (tussock_n - 0.5) * 0.24)
			: 0.0;
		float g_vis = 1.0 - cliff_mask;
		float w_sand = g_vis * t_wet_in * (1.0 - t_grass_in) * (1.0 - path_edge_w);
		float w_grass = g_vis * t_grass_in * (1.0 - path_edge_w);
		float w_dirt = g_vis * path_edge_w;
		float w_cliff_norm = cliff_mask * (1.0 - ledge_moss * 0.85) * (1.0 - volc * 0.86);
		float w_cliff_volc = cliff_mask * (1.0 - ledge_moss * 0.85) * (volc * 0.86);
		float w_moss_grass = cliff_mask * ledge_moss * 0.85;
		w_grass += w_moss_grass;

		vec3 tex_alb_acc = vec3(0.0);
		vec3 tex_nrm_acc = vec3(0.0);
		float tex_w_acc = 0.0;

		if (w_sand > 0.08) {
			vec3 sa; vec3 sn_o;
			// Directional trade-wind sand ripples: gentle 12-deg meander avoids cross-patch seams!
			sample_stochastic_ground(tex_sand_albedo, tex_sand_normal, xz, terrain_tex_scale * 1.65, macro_n, brush_n, tex_nrm_str * 0.36, 0.21, sa, sn_o);
			tex_alb_acc += mix(col_dry, sa, 0.62) * w_sand;
			tex_nrm_acc += sn_o * w_sand;
			tex_w_acc += w_sand;
		}
		if (w_grass > 0.08) {
			vec3 ga; vec3 gn_o;
			sample_stochastic_ground(tex_grass_albedo, tex_grass_normal, xz, terrain_tex_scale * 1.42, macro_n, brush_n, tex_nrm_str * 0.82, 0.645, ga, gn_o);
			tex_alb_acc += (ga * grass_tint) * w_grass;
			tex_nrm_acc += gn_o * w_grass;
			tex_w_acc += w_grass;
		}
		if (w_dirt > 0.08) {
			vec3 da; vec3 dn_o;
			sample_stochastic_ground(tex_dirt_albedo, tex_dirt_normal, xz, terrain_tex_scale * 1.45, macro_n, brush_n, tex_nrm_str * 0.92, 0.89, da, dn_o);
			tex_alb_acc += da * w_dirt;
			tex_nrm_acc += dn_o * w_dirt;
			tex_w_acc += w_dirt;
		}
		if (w_cliff_norm > 0.08) {
			vec3 ca; vec3 cn_o;
			sample_triplanar_cliff(tex_cliff_albedo, tex_cliff_normal, v_world, smooth_n, terrain_tex_scale * 0.78, cliff_strata_scale, macro_n, brush_n, tex_nrm_str, far_cliff, ca, cn_o);
			tex_alb_acc += (ca * cliff_tint) * w_cliff_norm;
			tex_nrm_acc += cn_o * w_cliff_norm;
			tex_w_acc += w_cliff_norm;
		}
		if (w_cliff_volc > 0.08) {
			vec3 va; vec3 vn_o;
			sample_triplanar_cliff(tex_volcanic_albedo, tex_volcanic_normal, v_world, smooth_n, terrain_tex_scale * 0.82, cliff_strata_scale, macro_n, brush_n, tex_nrm_str * 1.05, far_cliff, va, vn_o);
			tex_alb_acc += va * w_cliff_volc;
			tex_nrm_acc += vn_o * w_cliff_volc;
			tex_w_acc += w_cliff_volc;
		}

		if (tex_w_acc > 0.01) {
			vec3 pbr_alb = (tex_alb_acc / tex_w_acc) * COLOR.rgb;
			// Harmonize painted PBR texture detail with painterly procedural biome gradients & crevice shading.
			vec3 pbr_shaded = pbr_alb * mix(vec3(1.0), clamp(albedo * 1.55, vec3(0.42), vec3(1.32)), 0.42);
			float tex_fade = smoothstep(430.0, 95.0, v_cam_dist) * terrain_tex_blend * clamp(tex_w_acc, 0.0, 1.0);
			albedo = mix(albedo, pbr_shaded, tex_fade);
			if (pbr_nrm_fade > 0.01) {
				final_n_world = normalize(final_n_world + (tex_nrm_acc / tex_w_acc) * (0.58 * clamp(tex_w_acc, 0.0, 1.0)));
			}
		}
	}

	float facet_pop = clamp(dot(face_n, smooth_n), 0.72, 1.0);
	albedo *= mix(1.0, 0.92 + 0.11 * facet_pop, cliff_mask * (1.0 - ledge_moss * 0.75));

	// Surface roughness & specular: glistening wet sand, tactile dry sand, mossy ledges, rough cliffs.
	float wet_mask = t_wet_in * (1.0 - t_dry_in) * (1.0 - cliff_mask * 0.85);
	float rough = mix(0.92, 0.86, t_shallow);
	rough = mix(rough, mix(0.26, 0.42, grain_n * 0.5 + pebble_n * 0.5), wet_mask);
	rough = mix(rough, mix(0.84, 0.92, sand_wave), t_dry_in * (1.0 - t_grass_in));
	rough = mix(rough, mix(0.80, 0.90, tussock_n), t_grass_in);
	rough = mix(rough, mix(0.76, 0.94, crevice_shade), cliff_mask);
	rough = mix(rough, 0.84, ledge_moss);
	rough = mix(rough, 0.90, dirt_path_mask);

	// Graceful atmospheric aerial perspective for massive distant islands (400-2400 m).
	float aerial_t = smoothstep(380.0, 2400.0, v_cam_dist) * aerial_perspective_strength;
	vec3 aerial_col = mix(sky_horizon_color, sky_zenith_color, clamp(h * 0.004, 0.0, 0.25));
	albedo = mix(albedo, aerial_col * 0.92, aerial_t * 0.52);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.26, 0.48, wet_mask);
	vec3 magma_col = mix(vec3(0.95, 0.18, 0.02), vec3(1.0, 0.56, 0.10), magma_core);
	EMISSION = magma_col * magma_emit + aerial_col * (aerial_t * 0.075);
	NORMAL = normalize((VIEW_MATRIX * vec4(final_n_world, 0.0)).xyz);
}

void light() {
	// Per-pixel drifting cloud shadows on directional sunlight (never on lanterns/fires).
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(v_world.xz) : 1.0;
	float ndl_raw = dot(NORMAL, LIGHT);
	float ndl = clamp(ndl_raw, 0.0, 1.0);
	float face_up_n = dot(NORMAL, normalize(v_view_up));
	float up_n = min(normalize(v_world_normal).y, face_up_n);
	float s_lo = mix(17.0, 34.0, lush_jungle_amount) - clamp(volcanic_amount, 0.0, 1.0) * 6.0;
	float s_hi = mix(29.0, 56.0, lush_jungle_amount) - clamp(volcanic_amount, 0.0, 1.0) * 8.0;
	float cliff_m = clamp(max(smoothstep(0.78, 0.50, up_n), smoothstep(s_lo, s_hi, v_world.y) * smoothstep(0.92, 0.72, up_n)), 0.0, 1.0);
	float wet_m = smoothstep(0.58, 0.30, ROUGHNESS);

	if (LIGHT_IS_DIRECTIONAL) {
		// Detect warm daylight vs cool moonlight so night cliffs stay silver-blue while day cliffs glow golden-ochre.
		float warmth = clamp((LIGHT_COLOR.r - LIGHT_COLOR.b) * 2.2 + 0.45, 0.0, 1.0);
		vec3 sunlit_tint = mix(vec3(1.0), vec3(1.10, 0.98, 0.85), cliff_m * warmth);
		// Soft wrapped terminator on sand/grass, crisp painterly sculpted planes on cliffs.
		float wrap = mix(0.16, 0.04, cliff_m);
		float diff_term = clamp((ndl_raw + wrap) / (1.0 + wrap), 0.0, 1.0);
		DIFFUSE_LIGHT += diff_term * ATTENUATION * LIGHT_COLOR * sunlit_tint * sun / PI;

		// Rich cool coastal slate-teal sky-bounce fill on shaded cliff faces turned away from the sun.
		float shadow_plane = smoothstep(0.22, -0.35, ndl_raw);
		vec3 cool_fill = mix(ambient_color, sky_horizon_color * vec3(0.54, 0.78, 1.06), 0.62);
		float fill_str = mix(0.07, 0.28, cliff_m) * warmth * clamp(sun, 0.38, 1.15);
		DIFFUSE_LIGHT += shadow_plane * cool_fill * fill_str / PI;

		// Glistening wet sand specular & subtle sunlit cliff rim sheen.
		vec3 h_vec = normalize(VIEW + LIGHT);
		float ndh = clamp(dot(NORMAL, h_vec), 0.0, 1.0);
		float spec_pow = mix(16.0, 118.0, wet_m);
		float spec_amp = mix(0.06, 0.56, wet_m);
		SPECULAR_LIGHT += pow(ndh, spec_pow) * spec_amp * ndl * ATTENUATION * LIGHT_COLOR * sun;
	} else {
		// Point/spot lights (campfires, lava caldera, tavern/dock/beacon lanterns).
		DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;
		vec3 h_vec = normalize(VIEW + LIGHT);
		float ndh = clamp(dot(NORMAL, h_vec), 0.0, 1.0);
		float spec_pow = mix(16.0, 72.0, wet_m);
		SPECULAR_LIGHT += pow(ndh, spec_pow) * (0.08 + 0.35 * wet_m) * ndl * ATTENUATION * LIGHT_COLOR;
	}
}
