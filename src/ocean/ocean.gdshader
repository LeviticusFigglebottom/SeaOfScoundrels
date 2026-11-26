shader_type spatial;
// Stylized ocean surface. Geometry comes from the shared Gerstner set in
// waves.gdshaderinc (identical to the CPU `Sea` autoload); everything else here
// is shading only and never adds height.
render_mode unshaded, cull_disabled, depth_draw_always, world_vertex_coords, shadows_disabled;

#include "res://src/ocean/waves.gdshaderinc"
#include "res://src/ocean/ocean_common.gdshaderinc"
#include "res://src/sky/cloud_shadow.gdshaderinc"

#define MAX_HULL_MASKS 8

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
// R = organic frothy foam lace erosion map, G = blotch noise, B = fine frothy bubble lace.
uniform sampler2D foam_tex : repeat_enable, filter_linear_mipmap_anisotropic;
// 2D-FFT directional JONSWAP/Tessendorf choppy wavelets (tools/textures/gen_ocean.py):
// R,G = choppy normal slope (0.5 = flat), B = choppy ridge elevation, A = Jacobian crest fold.
uniform sampler2D chop_tex : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float chop_tex_on = 0.0;
// Simulated foam (Ocean's foam field): R = amount, stored in rest-plane
// coordinates, one tile of foam_field_size metres that wraps around the camera.
uniform sampler2D foam_field : repeat_enable, filter_linear;
uniform float foam_field_size = 256.0;
uniform float foam_field_on = 0.0;

// 0 low, 1 medium, 2 high. See Ocean.quality for what each level buys.
uniform int quality = 2;

group_uniforms water;
uniform vec3 deep_color : source_color = vec3(0.0032, 0.034, 0.145);
uniform vec3 scatter_color : source_color = vec3(0.008, 0.34, 0.48);
uniform vec3 sss_color : source_color = vec3(0.04, 0.90, 0.74);
uniform vec3 shallow_color : source_color = vec3(0.03, 0.76, 0.72);
uniform vec3 reef_color : source_color = vec3(0.014, 0.46, 0.48);
uniform vec3 foam_under_color : source_color = vec3(0.09, 0.56, 0.56);
uniform vec3 absorption = vec3(0.48, 0.095, 0.064); // per metre
uniform float turbidity = 0.13;       // how fast the body colour builds with depth
uniform float refraction_strength = 0.38;
uniform float sss_strength = 1.32;
uniform float reflectivity = 0.52;
group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 0.97);
uniform float foam_crest_start = 0.91; // Jacobian below this starts to foam
uniform float foam_crest_full = 0.66;
uniform float foam_scale = 0.20;
uniform float shore_foam_depth = 1.45;
group_uniforms sun;
uniform float glint_sharpness = 380.0;
uniform float glint_strength = 4.6;
group_uniforms weather;
uniform vec2 wind_dir = vec2(0.56, -0.83); // unit xz, the way the wind blows
uniform float rain_intensity = 0.0;        // 0..1, rings on the surface
group_uniforms hull_mask;
uniform int hull_mask_count = 0;
uniform mat4 hull_mask_inv[MAX_HULL_MASKS];
uniform vec4 hull_mask_size[MAX_HULL_MASKS];  // x = half_beam, y = half_len, z = y_min, w = y_max
uniform float hull_mask_flood[MAX_HULL_MASKS];
group_uniforms lod;
uniform float mesh_base_cell = 0.5;
uniform float mesh_cell_per_metre = 0.0278;
uniform float horizon_fade_start = 1500.0;
uniform float horizon_fade_end = 3700.0;
uniform float skirt_distance = 60000.0;

varying vec2 v_rest;
varying vec3 v_world;

void vertex() {
	vec2 rest = VERTEX.xz;
	vec3 cam = CAMERA_POSITION_WORLD;
	if (UV.x > 0.5) {
		// Skirt: push the rim out to (effectively) infinity so the sea meets
		// the true horizon whatever the camera far plane is.
		vec2 c = NODE_POSITION_WORLD.xz;
		rest = c + normalize(rest - c) * skirt_distance;
	}
	float dist = distance(rest, cam.xz);
	float cell = max(mesh_base_cell, dist * mesh_cell_per_metre);
	// Keep every wave the ring can carry with 4+ vertices per wavelength, so the
	// big swell still shapes the horizon.
	vec3 d = sea_displacement_lod(rest, cell * 2.0);
	VERTEX = vec3(rest.x, 0.0, rest.y) + d;
	v_rest = rest;
	v_world = VERTEX;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(VERTEX, 1.0));
	// Depth clamp: geometry past the far plane stays just inside it (reversed Z).
	POSITION.z = max(POSITION.z, POSITION.w * 2e-7);
}

// Per-pixel cloud lighting relative to the dimming already baked into sun_color.
// Safe when no SkyRig is active (cloud_shadow_params.w == 1.0 and unbound tex).
float sample_cloud_light(vec2 world_xz) {
	float cl = cloud_light(world_xz);
	if (cloud_shadow_params.w >= 0.999 && cl < 0.05) {
		return 1.0;
	}
	return clamp(cl, 0.0, 6.0);
}

// Tapered boat-shaped hull interior mask matching the sloop's `mask_water`.
// Discards ocean fragments inside dry holds; relaxes smoothly as flood -> 1.0.
bool is_inside_hull_mask(vec3 wp) {
	for (int i = 0; i < MAX_HULL_MASKS; i++) {
		if (i >= hull_mask_count) {
			break;
		}
		float flood = hull_mask_flood[i];
		if (flood >= 0.99) {
			continue;
		}
		vec3 lp = (hull_mask_inv[i] * vec4(wp, 1.0)).xyz;
		vec4 sz = hull_mask_size[i];
		float relax = smoothstep(0.72, 1.0, flood);
		float y_top = mix(sz.w, sz.z, relax);
		if (lp.y < sz.z || lp.y > y_top) {
			continue;
		}
		float zn = lp.z / max(sz.y, 0.1);
		if (zn < -1.0 || zn > 1.0) {
			continue;
		}
		float w;
		if (zn < 0.0) {
			float t = -zn;
			w = sz.x * pow(max(0.0, 1.0 - pow(t, 2.35)), 0.72);
		} else {
			float t = zn;
			float st = mix(0.98, 0.44, clamp((lp.y + 0.50) / 0.65, 0.0, 1.0));
			w = sz.x * (1.0 - st * t * t * t);
		}
		float yh = clamp((lp.y - sz.z) / max(-sz.z, 0.25), 0.0, 1.0);
		w *= mix(0.62, 1.0, sqrt(yh)) * (1.0 - relax * 0.85);
		if (abs(lp.x) < w) {
			return true;
		}
	}
	return false;
}

float linear_depth(vec2 uv, mat4 inv_proj, out vec3 view_pos, out float raw_depth) {
	raw_depth = texture(depth_tex, uv).r;
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	view_pos = p.xyz / p.w;
	return -view_pos.z;
}

// Lingering foam from the simulated field, faded out where the tile would wrap.
float field_foam(vec2 rest, float dist) {
	if (foam_field_on < 0.5) {
		return 0.0;
	}
	float edge = foam_field_size * 0.5;
	return texture(foam_field, rest / foam_field_size).r * smoothstep(edge * 0.86, edge * 0.62, dist);
}

// Variance-preserving dual-phase flow-advected ripple normal sample (centred xy).
// Normalizing by sqrt(w^2 + (1-w)^2) prevents micro-facets from blurring out at mid-cycle.
vec2 ripple_flow(vec2 uv, vec2 off0, vec2 off1, float flow_w) {
	vec2 a = texture(detail_tex, uv + off0).rg - 0.5;
	vec2 b = texture(detail_tex, uv + off1).rg - 0.5;
	float inv_rms = inversesqrt(max(flow_w * flow_w + (1.0 - flow_w) * (1.0 - flow_w), 0.25));
	return mix(a, b, flow_w) * inv_rms;
}

// Unpack 2D-FFT JONSWAP/Tessendorf choppy wavelet sample:
// xy = centred choppy slope, z = ridge height (0 trough..1 peak), w = Jacobian crest fold (0..1).
vec4 chop_sample(vec2 uv) {
	vec4 raw = texture(chop_tex, uv);
	return vec4(raw.rg - 0.5, raw.b, clamp((raw.a - 0.02) / 0.98, 0.0, 1.0));
}

// Variance-preserving dual-phase flow-advected sample of ocean_fft_chop.png.
vec4 chop_flow(vec2 uv, vec2 off0, vec2 off1, float flow_w) {
	vec4 a = chop_sample(uv + off0);
	vec4 b = chop_sample(uv + off1);
	float inv_rms = inversesqrt(max(flow_w * flow_w + (1.0 - flow_w) * (1.0 - flow_w), 0.25));
	vec2 slope = mix(a.xy, b.xy, flow_w) * inv_rms;
	float h = clamp(0.5 + (mix(a.z, b.z, flow_w) - 0.5) * inv_rms, 0.0, 1.0);
	float fold = mix(a.w, b.w, flow_w);
	return vec4(slope, h, fold);
}

// Anisotropically stretch foam coordinates gently along local wave flow so lacy froth
// streams over wave crests rather than sitting like a static isotropic grid.
vec2 flow_stretched_uv(vec2 p, vec2 fdir, float stretch_k) {
	vec2 fperp = vec2(-fdir.y, fdir.x);
	float along = dot(p, fdir) * mix(1.0, 0.72, stretch_k);
	float across = dot(p, fperp) * mix(1.0, 1.18, stretch_k);
	return (fdir * along + fperp * across) * foam_scale;
}

// Evaluate organic turbulent foam lace pattern (x = combined erosion, y = frothy filaments).
vec2 sample_foam_lace(vec2 rest_p, vec2 fdir, float stretch_k, float streak) {
	vec2 uv = flow_stretched_uv(rest_p, fdir, stretch_k);
	float warp = texture(foam_tex, uv * 0.27 + vec2(0.11, 0.07)).g;
	vec2 w = (vec2(warp, texture(foam_tex, uv.yx * 0.21 + vec2(0.31, 0.17)).g) - 0.5) * 0.42;
	vec3 f1 = texture(foam_tex, uv + w).rgb;
	float lace_big = texture(foam_tex, uv.yx * 0.37 + w * 0.65).r;
	float lace_fine = texture(foam_tex, uv * 2.15 - w * 0.75).b;
	// Combined erosion map for breaking caps, surf and wakes
	float pattern = f1.r * 0.42 + lace_big * 0.34 + lace_fine * 0.24;
	// Soft wispy frothy filaments for active wave-face webbing (zero straight polygon rims)
	float fil_wall = f1.r * 0.45 + lace_fine * 0.35 + (1.0 - f1.g) * 0.20;
	if (streak > 0.01) {
		vec2 along = wind_dir;
		vec2 across = vec2(-wind_dir.y, wind_dir.x);
		vec2 suv = vec2(dot(rest_p, along) * 0.30, dot(rest_p, across) * 0.96) * foam_scale;
		float s1 = texture(foam_tex, suv + w * 0.38).r;
		float s2 = texture(foam_tex, suv * vec2(0.72, 1.95) + 0.37).b;
		pattern = mix(pattern, s1 * 0.44 + s2 * 0.56, streak);
		fil_wall = mix(fil_wall, s1 * 0.40 + s2 * 0.60, streak * 0.78);
	}
	return vec2(pattern, fil_wall);
}

// Wave-flow-advected painterly foam.
// Returns x = heavy foam coverage, y = heavy foam thickness (0 at edge..1 core),
// z = delicate wave-action gossamer frothy webbing coverage.
vec3 foam_mask_flow(float amount, float web_amt, vec2 draped, vec2 off0, vec2 off1, float flow_w, vec2 fdir, float stretch_k, float soft, float streak) {
	// Shorter advect travel and smoothstep crossfade prevent double-grid ghosting on foam.
	vec2 p0 = draped + off0 * 0.78;
	vec2 s0 = sample_foam_lace(p0, fdir, stretch_k, streak);
	vec2 s = s0;
	if (quality > 0) {
		vec2 p1 = draped + off1 * 0.78;
		vec2 s1 = sample_foam_lace(p1, fdir, stretch_k, streak);
		float fw = smoothstep(0.08, 0.92, flow_w);
		s = mix(s0, s1, fw);
	}
	float pattern = smoothstep(0.12, 0.88, s.x);
	float thr = 1.0 - amount;
	float cover = smoothstep(thr - soft, thr + soft, 1.0 - pattern) * smoothstep(0.0, 0.07, amount);
	// Preserve delicate frothy water pores inside wake, surf & gale foam so high-coverage patches
	// read as aerated sea-lace instead of solid opaque paint (only tightest crest/lip core saturates).
	float bubble_lace = 1.0 - smoothstep(0.24, 0.82, s.y);
	cover *= mix(0.36 + 0.64 * bubble_lace, 1.0, smoothstep(0.84, 0.98, amount));
	float body = smoothstep(thr + 0.04, thr + 0.48, 1.0 - pattern) * (0.48 + 0.52 * bubble_lace);
	// Organic frothy webbing draped strictly where wave action / wakes / surf exist
	float web_edge = mix(0.18, 0.56, clamp(web_amt, 0.0, 1.0));
	float web_fil = 1.0 - smoothstep(0.06, web_edge, s.y);
	float web_cover = web_fil * smoothstep(0.02, 0.14, web_amt) * clamp(web_amt * 1.12, 0.0, 0.70);
	return vec3(cover, body, web_cover);
}

vec3 hash32(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yzz) * q.zyx);
}

// Rain rings: expanding ripples from random drops, as a normal offset (xz)
// with the splash brightness in z.
vec3 rain_rings(vec2 p, float amount, int layers) {
	vec3 acc = vec3(0.0);
	for (int l = 0; l < layers; l++) {
		float fl = float(l);
		vec2 g = p * (1.35 + 0.55 * fl) + vec2(17.3, 9.1) * fl;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		vec3 rnd = hash32(id + fl * 31.7);
		if (rnd.z > amount * 0.9) {
			continue;
		}
		vec2 c = (rnd.xy - 0.5) * 0.45;
		float life = fract(sea_time * (0.85 + 0.5 * rnd.x) + rnd.y * 9.0);
		vec2 dvec = f - c;
		float r = length(dvec);
		float radius = life * 0.40;
		float fade = (1.0 - life) * (1.0 - life);
		float ring = sin((r - radius) * 46.0) * smoothstep(0.075, 0.0, abs(r - radius)) * fade;
		acc.xy += dvec / max(r, 1e-4) * ring;
		acc.z += smoothstep(0.05, 0.0, r) * smoothstep(0.18, 0.0, life);
	}
	return acc;
}

void fragment() {
	if (hull_mask_count > 0 && is_inside_hull_mask(v_world)) {
		discard;
	}

	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 to_cam = cam - v_world;
	float dist = length(to_cam);
	vec3 V = to_cam / dist;
	float surf_z = -VERTEX.z;
	float storm = sea_state().x;

	// --- surface normal, Jacobian and Gerstner orbital flow, filtered to pixel footprint
	float px_angle = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float fp_across = dist * px_angle;
	float fp = fp_across * mix(1.0, 1.0 / max(abs(V.y), 0.04), 0.3);
	vec3 n_geo;
	float jac;
	float lost_var;
	float wave_h;
	float h_var;
	vec2 long_slope;
	vec2 flow_vel;
	float vert_vel;
	sea_surface_lod_motion(v_rest, sea_time, fp * 2.5, n_geo, jac, lost_var, wave_h, h_var, long_slope, flow_vel, vert_vel);
	float amp_ref = max(2.0 * sqrt(h_var), 0.05);
	float h_rel = wave_h / amp_ref;

	// --- wave-coupled dual-phase flow advection
	// Texture climbs UP rising front faces (-n_geo.xz when vert_vel > 0), surges OVER
	// crests (+flow_vel), and streams DOWN falling backs (+n_geo.xz when vert_vel < 0).
	float rise = clamp(vert_vel * 0.80, -1.0, 1.0);
	vec2 face_flow = -rise * n_geo.xz;
	vec2 raw_flow = flow_vel * 0.56 + face_flow * 2.45 + wind_dir * (0.24 + 0.58 * storm);
	float flow_mag = length(raw_flow);
	vec2 wave_flow = raw_flow / (1.0 + flow_mag * 0.16);
	vec2 flow_dir = flow_mag > 1e-4 ? (raw_flow / flow_mag) : wind_dir;
	float flow_stretch = smoothstep(0.18, 1.85, flow_mag);

	// Spatial phase jitter breaks up any global cycle pulse across the sea.
	float ph_jit = texture(foam_tex, v_rest * 0.0085).g * 0.55;
	float flow_t = sea_time * 0.35 + ph_jit;
	float ph0 = fract(flow_t);
	float ph1 = fract(flow_t + 0.5);
	float flow_w = abs(2.0 * ph0 - 1.0);
	vec2 flow_off0 = -wave_flow * (ph0 - 0.5) * 1.40;
	vec2 flow_off1 = -wave_flow * (ph1 - 0.5) * 1.40;
	// Subtle draping along wave slopes so detail hugs steep ridges.
	vec2 draped = v_rest + n_geo.xz * 0.55;

	// --- multi-cascade irrational-scale rotated 2D-FFT JONSWAP/Tessendorf chop + capillary wind ripples
	// Three irrational spatial scales (19.3 m, 51.7 m, 137.3 m) at mutually irrational angles
	// eliminate any segmented parallel rows or visible tiling from 2 m to the 3.7 km horizon.
	const mat2 ROT_B  = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	const mat2 ROT_C1 = mat2(vec2(0.77757, 0.62879), vec2(-0.62879, 0.77757));   // +0.68 rad
	const mat2 ROT_C2 = mat2(vec2(0.37166, -0.92837), vec2(0.92837, 0.37166));   // -1.19 rad
	float fine = smoothstep(0.45, 0.025, fp);
	float med_fade = smoothstep(1.6, 0.08, fp);
	float cfade_a = smoothstep(2.6, 0.07, fp);
	float cfade_b = smoothstep(7.8, 0.24, fp);
	float cfade_c = smoothstep(30.0, 1.15, fp);

	vec2 rip_fine;
	vec2 rip_med;
	vec2 rip_micro = vec2(0.0);
	vec2 ripple;
	vec2 chop_slope = vec2(0.0);
	float chop_h = 0.5;
	float chop_fold = 0.0;
	float gust = 0.55;
	float macro_patch = 0.5;

	if (quality > 0) {
		rip_fine = ripple_flow(draped * 0.145, flow_off0 * 0.145, flow_off1 * 0.145, flow_w) * fine;
		vec2 uv_m = (ROT_B * draped) * 0.056;
		vec2 fm0 = (ROT_B * flow_off0) * 0.056;
		vec2 fm1 = (ROT_B * flow_off1) * 0.056;
		rip_med = ripple_flow(uv_m, fm0, fm1, flow_w) * med_fade;
		vec2 uv_micro = (draped.yx * 0.315) + wind_dir * 0.058 * sea_time;
		rip_micro = ripple_flow(uv_micro, flow_off0.yx * 0.315, flow_off1.yx * 0.315, flow_w) * smoothstep(0.24, 0.018, fp);
		ripple = rip_fine * 0.88 + rip_med * 1.02 + rip_micro * (0.34 + 0.20 * storm);
		// 311 m macro swell-breakup & wind-gust field so the horizon feels vast and non-repeating.
		macro_patch = smoothstep(0.14, 0.86, texture(foam_tex, (ROT_C1 * v_rest) * 0.003215 + wind_dir * 0.0025 * sea_time).g);
		gust = smoothstep(0.18, 0.82, texture(foam_tex, v_rest * 0.0041 + wind_dir * 0.004 * sea_time).g);
		if (chop_tex_on > 0.5) {
			// Cascade A (19.3 m): dual-phase flow-advected near-to-mid choppy ridges & troughs.
			vec2 ca_uv = draped * 0.051813 + wind_dir * (0.012 * sea_time);
			vec4 ca = chop_flow(ca_uv, flow_off0 * 0.051813, flow_off1 * 0.051813, flow_w);
			// Cascade B (51.7 m, +0.68 rad): oblique cross-chop sculpting mid-field faces.
			vec2 cb_uv = (ROT_C1 * draped) * 0.019342 + vec2(-0.0072, 0.0054) * sea_time + (ROT_C1 * flow_off0) * 0.011;
			vec4 cb = chop_sample(cb_uv);
			vec2 cb_slope = transpose(ROT_C1) * cb.xy;
			// Cascade C (137.3 m, -1.19 rad): vast macro chop breaking up distant swell bands.
			vec2 cc_uv = (ROT_C2 * v_rest) * 0.007283 + vec2(0.0031, 0.0042) * sea_time;
			vec4 cc = chop_sample(cc_uv);
			vec2 cc_slope = transpose(ROT_C2) * cc.xy;

			chop_slope = ca.xy * (1.28 * cfade_a) + cb_slope * (1.02 * cfade_b) + cc_slope * (0.72 * cfade_c);
			chop_h = clamp(0.5 + (ca.z - 0.5) * 0.58 * cfade_a + (cb.z - 0.5) * 0.54 * cfade_b + (cc.z - 0.5) * 0.42 * cfade_c, 0.0, 1.0);
			chop_fold = clamp(ca.w * 0.64 * cfade_a + cb.w * 0.52 * cfade_b + cc.w * 0.34 * cfade_c, 0.0, 1.0);
		}
	} else {
		rip_fine = (texture(detail_tex, draped * 0.135 + flow_off0 * 0.135).rg - 0.5) * fine;
		rip_med = (texture(detail_tex, (ROT_B * draped) * 0.052 + (ROT_B * flow_off0) * 0.052).rg - 0.5) * med_fade;
		ripple = rip_fine * 0.90 + rip_med * 1.05;
		if (chop_tex_on > 0.5) {
			vec4 ca = chop_sample(draped * 0.051813 + wind_dir * (0.012 * sea_time));
			vec4 cb = chop_sample((ROT_C1 * draped) * 0.019342 + vec2(-0.0072, 0.0054) * sea_time);
			vec2 cb_slope = transpose(ROT_C1) * cb.xy;
			chop_slope = ca.xy * (1.15 * cfade_a) + cb_slope * (0.90 * cfade_b);
			chop_h = clamp(0.5 + (ca.z - 0.5) * 0.55 * cfade_a + (cb.z - 0.5) * 0.48 * cfade_b, 0.0, 1.0);
			chop_fold = clamp(ca.w * 0.58 * cfade_a + cb.w * 0.46 * cfade_b, 0.0, 1.0);
		}
	}

	float crest_pre = clamp((1.0 - jac) * 1.9, 0.0, 1.0) * 0.55 + smoothstep(0.10, 1.05, h_rel) * 0.65;
	crest_pre = clamp(crest_pre + chop_fold * 0.24, 0.0, 1.0);
	// Sheltered lagoons keep calmer gentle ripples; open fair/storm seas are richly choppy & sculptural.
	float open_sea = smoothstep(0.24, 0.64, sea_amp_scale);
	float ripple_amt = mix(0.18, mix(0.34, 0.50, storm), open_sea) * mix(0.76, 1.26, gust) * (1.0 + 0.20 * crest_pre);
	float chop_amt = mix(0.20, mix(0.72, 1.00, storm), open_sea) * mix(0.78, 1.26, macro_patch) * (1.0 + 0.28 * crest_pre);
	float exag = mix(1.65, 1.0, smoothstep(0.0, 0.65, storm));
	vec3 n_shade = normalize(n_geo - vec3(long_slope.x, 0.0, long_slope.y) * (exag - 1.0));
	vec3 n_detail = vec3(ripple.x, 0.0, ripple.y) * ripple_amt + vec3(chop_slope.x, 0.0, chop_slope.y) * chop_amt;
	float splash = 0.0;
	if (rain_intensity > 0.01 && quality > 0 && fp < 0.09) {
		vec3 rr = rain_rings(v_rest, rain_intensity, quality > 1 ? 3 : 2) * smoothstep(0.09, 0.02, fp);
		n_detail += vec3(rr.x, 0.0, rr.y) * 0.22;
		splash = rr.z;
	}
	vec3 N = normalize(n_shade + n_detail);
	// Feed unresolved distant FFT chop variance into Toksvig roughness so the horizon shimmers smoothly.
	float chop_lost_var = ((1.0 - cfade_a * cfade_a) * 0.0042 + (1.0 - cfade_b * cfade_b) * 0.0028) * open_sea * chop_tex_on;
	float rough_var = lost_var + chop_lost_var + 0.0005 + 0.0024 * storm + 0.004 * rain_intensity;

	// --- lighting with per-pixel cloud shadows
	vec3 L = normalize(sun_dir);
	float cloud_l = sample_cloud_light(v_world.xz);
	vec3 sun_light = ocean_sun_light() * cloud_l;
	vec3 light = ambient_color * 0.68 + sun_light * (0.24 + 0.76 * clamp(L.y, 0.0, 1.0));

	// --- what lies behind the surface
	vec3 scene_view;
	float raw_d0;
	float scene_z = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX, scene_view, raw_d0);
	bool has_floor0 = (raw_d0 > 1e-5) && (scene_z < surf_z + 90.0);
	float thick0 = has_floor0 ? max(scene_z - surf_z, 0.0) * dist / max(surf_z, 1e-4) : 120.0;

	vec3 col;
	float alpha_edge = 1.0;

	// The sea is a height field: its underside is only ever visible to a camera
	// that is under water. Facing only decides while the lens straddles the
	// surface (edge-on slivers at the horizon must not flip).
	bool underside = uw_cam_depth > 0.15 || (uw_cam_depth > -0.15 && !FRONT_FACING);
	if (!underside) {
		// ---------------- seen from above ----------------
		vec2 uv_r = SCREEN_UV;
		vec3 rv = scene_view;
		float rz = scene_z;
		float raw_dr = raw_d0;
		if (quality > 0 && has_floor0) {
			vec3 n_view = (VIEW_MATRIX * vec4(N, 0.0)).xyz;
			vec2 offs = n_view.xy * refraction_strength * clamp(thick0 * 0.6, 0.0, 1.0) / max(surf_z, 1.0);
			uv_r = clamp(SCREEN_UV - offs, vec2(0.001), vec2(0.999));
			rz = linear_depth(uv_r, INV_PROJECTION_MATRIX, rv, raw_dr);
			if (raw_dr <= 1e-5 || rz < surf_z + 0.02) {
				uv_r = SCREEN_UV;
				rv = scene_view;
				rz = scene_z;
				raw_dr = raw_d0;
			}
		}
		// Guard against empty sky pixels at the horizon (reversed-Z raw_depth == 0.0):
		// open ocean past island seabed skirts has infinite depth, NEVER vdepth == 0!
		bool has_seabed = (raw_dr > 1e-5) && (rz < surf_z + 85.0);
		float thick = has_seabed ? max(rz - surf_z, 0.0) * dist / max(surf_z, 1e-4) : 120.0;
		vec3 scene_world = (INV_VIEW_MATRIX * vec4(rv, 1.0)).xyz;
		float vdepth = has_seabed ? max(v_world.y - scene_world.y, 0.0) : 120.0;
		vec3 behind = has_seabed ? texture(screen_tex, uv_r).rgb : vec3(0.0);

		// Luminous Caribbean caustic light webs dancing across shallow harbours, reefs & beaches
		// (uses abs(floor_n.y) so refracted depth-derivative sign flips never drop caustics; 0 cost on open sea!).
		if (has_seabed && quality > 0 && vdepth < 14.0 && dist < 120.0) {
			float sun_up = max(L.y, 0.15);
			vec2 cq = scene_world.xz + L.xz * (vdepth / sun_up);
			float caus_raw = ocean_caustic(cq);
			float caus_sharp = smoothstep(0.24, 1.35, caus_raw) * caus_raw;
			float caus = (caus_raw * 0.55 + caus_sharp * 0.65) * exp(-vdepth * 0.19) * smoothstep(0.0, 0.35, vdepth);
			caus *= smoothstep(120.0, 26.0, dist);
			vec3 floor_n = normalize(cross(dFdy(scene_world), dFdx(scene_world)));
			caus = min(caus, 2.4) * smoothstep(0.16, 0.56, abs(floor_n.y));
			float caus_sun = smoothstep(0.04, 0.26, L.y) * (1.0 - storm * 0.72) * (sun_light.g + 0.05);
			behind *= 1.0 + caus * 1.85 * caus_sun;
			behind += vec3(0.46, 0.96, 0.92) * (caus_sharp * exp(-vdepth * 0.24) * smoothstep(0.0, 0.35, vdepth) * smoothstep(95.0, 18.0, dist) * smoothstep(0.18, 0.58, abs(floor_n.y)) * caus_sun * 0.26);
		}
		behind *= 0.70 + 0.30 * exp(-thick * 4.0);
		behind *= mix(vec3(1.0), vec3(0.38, 0.94, 0.96), 1.0 - exp(-thick * 1.3));

		// --- deep volumetric Sea-of-Thieves colour separation: fathomless dark sapphire-indigo
		// troughs & shadowed backs, rich jewel teal-blue slopes, luminous emerald thinned crests (SSS)
		float crest = crest_pre;
		float facing = 1.0 - max(dot(N, V), 0.0);
		float back_lit = pow(max(dot(V, -normalize(L + N * 0.32)), 0.0), 2.5);
		float side_lit = pow(max(dot(V, -normalize(vec3(L.x, L.y * 0.5, L.z) + N * 0.45)), 0.0), 1.85);
		float slope_light = dot(N, normalize(L + vec3(0.0, 0.46, 0.0)));
		float macro_light = dot(n_shade, normalize(L + vec3(0.0, 0.52, 0.0)));
		float tilt = dot(-long_slope, normalize(L.xz + vec2(1e-4)));
		float swell_shade = clamp(1.0 + tilt * mix(7.2, 1.9, storm), 0.40, 1.42);

		// Combine geometric swell elevation with per-pixel FFT choppy wavelet trough/ridge height
		// so deep hollows plunge into rich jewel navy-sapphire while ridges catch bold light.
		float eff_h = h_rel + (chop_h - 0.5) * mix(0.88, 1.18, storm) * open_sea;
		float trough_depth = smoothstep(0.32, -0.95, eff_h);
		float trough_ao = mix(1.0, 0.52, trough_depth * mix(0.55, 1.0, open_sea));
		float near_emerald = smoothstep(105.0, 14.0, dist);
		float body_floor = mix(0.008, 0.055, near_emerald);
		float dist_sapphire = smoothstep(45.0, 320.0, dist);
		float macro_depth = mix(0.78, 1.22, macro_patch);

		// Compute night detection early so moonlight never triggers daytime emerald SSS at the horizon.
		float sun_dip = smoothstep(0.02, -0.14, sun_dir.y);
		float hor_lum = dot(sky_horizon_color, vec3(0.2126, 0.7152, 0.0722));
		float zen_lum = dot(sky_zenith_color, vec3(0.2126, 0.7152, 0.0722));
		float dark_sky = smoothstep(0.055, 0.028, hor_lum) * smoothstep(0.018, 0.008, zen_lum);
		float blue_night = smoothstep(1.15, 1.55, sky_horizon_color.b / max(sky_horizon_color.g, 0.001));
		float night_bio = clamp(max(sun_dip, dark_sky * blue_night), 0.0, 1.0);

		// View-angle & steepness gate ensures overhead aerial views and distant horizons stay
		// deep fathomless sapphire rather than painting bright cyan bands across broad swell tops.
		float deck_angle = smoothstep(0.58, 0.12, abs(V.y));
		float grazing_sss = smoothstep(0.14, 0.72, facing) * deck_angle;
		float sss_dist = smoothstep(175.0, 16.0, dist);
		float wave_steep = smoothstep(0.06, 0.32, length(n_geo.xz) + length(chop_slope) * 0.50);

		float body_k = body_floor
			+ 0.30 * smoothstep(-0.32, 1.05, eff_h) * (0.28 + 0.72 * deck_angle)
			+ 0.34 * crest * (0.25 + 0.75 * deck_angle)
			+ 0.22 * chop_fold * open_sea
			+ 0.14 * facing * facing;
		body_k *= mix(1.0, 0.12, dist_sapphire) * macro_depth;
		body_k *= mix(0.36, 1.30, smoothstep(0.42, 0.96, mix(macro_light, slope_light, 0.50)));
		body_k = max(body_k, body_floor * 0.65);

		float face_lit = mix(macro_light, slope_light, 0.56);
		float face_contrast = mix(0.28, 1.50, smoothstep(0.36, 0.96, face_lit)) * trough_ao;
		vec3 body = mix(deep_color, scatter_color, clamp(body_k, 0.0, 1.0)) * light * face_contrast * swell_shade;

		// Luminous emerald-aquamarine translucent glow strictly in near-to-mid steep thin crests
		// viewed through the wave wall during daylight & golden hour (zero aerial pancakes, zero midnight horizon glow).
		float golden_hour = (1.0 - night_bio) * (1.0 - storm * 0.82) * smoothstep(-0.01, 0.04, L.y) * smoothstep(0.32, 0.08, L.y);
		float sss_elev = smoothstep(0.005, 0.16, L.y);
		float sss_key = smoothstep(0.10, 0.56, sun_light.r + sun_light.g * 0.8);
		float sss_mod = sss_elev * sss_key * (1.0 - night_bio) * mix(1.0, 0.44, storm);
		vec3 sss_tint = mix(sss_color, vec3(0.34, 0.82, 0.50), golden_hour * 0.46);
		float sss_break = clamp(0.62 + (N.x * 0.9 + N.z * 0.7) * 0.52 + (1.0 - N.y) * 0.85, 0.32, 1.32);
		float chop_ridge = smoothstep(0.54, 0.90, chop_h) * (0.44 + 0.56 * chop_fold) * open_sea;
		float ridge_thin = clamp(
			smoothstep(0.32, 0.92, crest) * smoothstep(0.14, 0.90, eff_h) * sss_break * wave_steep
			+ chop_ridge * smoothstep(0.00, 0.70, h_rel) * 0.78 * wave_steep,
			0.0, 1.0
		);
		float thin = clamp(
			ridge_thin * 1.08
			+ 0.56 * smoothstep(0.20, 0.92, eff_h) * wave_steep * max(back_lit, side_lit * 0.62) * sss_break,
			0.0, 1.0
		);
		body += sss_tint * sss_strength * sss_mod * (
				ridge_thin * light * 0.82
				+ thin * sun_light * (2.52 * back_lit + 0.96 * side_lit)
		) * (0.10 + 0.90 * grazing_sss) * sss_dist;

		// 3-zone coastal depth absorption: crystal turquoise shallows (0..3.5 m) -> vivid
		// emerald-jade reef dropoff (3.5..14 m) -> fathomless dark sapphire-indigo open sea (> 14 m).
		float path = vdepth * 1.45 + min(thick, 10.0) * 0.12;
		vec3 trans = has_seabed ? exp(-(absorption + turbidity) * path) : vec3(0.0);
		float fill = has_seabed ? (1.0 - exp(-turbidity * (path + min(thick, 4.0) * 0.85))) : 1.0;
		vec3 shallow_tint = mix(shallow_color, scatter_color, 0.18) * light * 0.74;
		vec3 reef_tint = reef_color * light * mix(0.62, 1.12, smoothstep(0.38, 0.95, face_lit));
		vec3 coast_body = mix(shallow_tint, reef_tint, smoothstep(1.2, 5.2, path));
		vec3 water_vol = has_seabed ? mix(coast_body, body, smoothstep(4.2, 16.5, path)) : body;
		col = behind * trans + water_vol * fill;

		// --- compute foam sources early so milky aqua aeration glows ONLY beneath real foam
		float lod_fade = smoothstep(0.95, 0.22, fp * 0.18);
		// Keep calm sheltered lagoons (depth < ~3 m or low-swell flat water) clean and foam-free.
		float has_floor = has_floor0 ? 1.0 : 0.0;
		float deep_water = mix(1.0, smoothstep(2.4, 4.0, vdepth), has_floor);
		float open_foam = smoothstep(0.44, 0.62, sea_amp_scale) * deep_water;
		float f_now = smoothstep(foam_crest_start - 0.06, foam_crest_full - 0.06, jac) * deep_water;
		// Crisp, wind-torn whitecaps strictly along the steepest pinched FFT & Gerstner crests.
		float chop_cap = smoothstep(0.56, 0.88, chop_fold) * smoothstep(0.26, 0.92, eff_h) * mix(0.40, 0.88, storm) * mix(0.60, 1.18, macro_patch) * open_foam;
		float fair_cap = max(smoothstep(0.44, 1.00, eff_h) * smoothstep(0.93, 0.72, jac) * mix(0.50, 0.42, storm) * open_foam, chop_cap);
		float field_raw = field_foam(v_rest, dist);
		// Break up Gaussian wake stamps with organic froth modulation so hull wakes stay lacy, never solid pads!
		float field = clamp(field_raw * 0.86, 0.0, 0.76);
		float crest_foam = max(max(f_now, fair_cap), field);
		float linger = clamp(field - max(f_now, fair_cap), 0.0, 1.0);
		if (foam_field_on < 0.5 || dist > foam_field_size * 0.31) {
			float j1 = sea_jacobian_lod(v_rest, sea_time - 1.1, max(fp * 2.5, 5.0));
			float f_trail = smoothstep(foam_crest_start - 0.06, foam_crest_full - 0.06, j1 + 0.02) * 0.54 * deep_water;
			if (quality > 0) {
				float j2 = sea_jacobian_lod(v_rest, sea_time - 2.6, max(fp * 2.5, 5.0));
				f_trail = max(f_trail, smoothstep(foam_crest_start - 0.06, foam_crest_full - 0.06, j2 + 0.04) * 0.32 * deep_water);
			}
			crest_foam = max(crest_foam, f_trail);
			linger = max(linger, clamp(f_trail - f_now, 0.0, 1.0));
		}
		// Wind streaks: standing foam in rough weather, drawn out downwind into crisp wind-torn spindrift ribbons.
		// Gate the extra spindrift tap strictly on active storms (0.00 ms overhead in fair weather!).
		vec2 wuv = vec2(dot(v_rest, wind_dir) * 0.004, dot(v_rest, vec2(-wind_dir.y, wind_dir.x)) * 0.021);
		float blot = texture(foam_tex, wuv + vec2(0.002, 0.0) * sea_time).g;
		float spindrift = blot;
		float standing = 0.0;
		if (storm > 0.02) {
			spindrift = texture(foam_tex, wuv * vec2(0.75, 3.10) + vec2(0.0055, 0.13) * sea_time).r;
			float wind_ribbon = smoothstep(0.38, 0.86, blot) * smoothstep(0.34, 0.84, spindrift * 0.76 + blot * 0.24);
			standing = storm * storm * wind_ribbon * 0.46 * smoothstep(-0.20, 0.58, eff_h) * deep_water;
		}
		crest_foam = max(crest_foam, standing);

		// Shoreline / ship-hull intersection foam from the depth buffer.
		vec3 sw0 = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
		float vd0 = has_floor0 ? max(v_world.y - sw0.y, 0.0) : 120.0;
		float in_water = 1.0;
		if (has_floor0 && quality > 0 && thick0 < 8.0 && vd0 < shore_foam_depth) {
			vec2 rest_there = sw0.xz - (v_world.xz - v_rest);
			float sd = sea_displacement_lod(rest_there, fp * 2.5).y - sw0.y;
			vd0 = max(sd, 0.0);
			in_water = smoothstep(-0.30, -0.05, sd);
		}
		// Gentle beaches get crisp scalloped shore-parallel surf wavelets (zero bullseye blot swirl!);
		// steep rocks & ship hulls get a tight, lacy churning waterline collar (zero thick white pillows!).
		vec3 scene_n = normalize(cross(dFdy(sw0), dFdx(sw0)));
		float flatness = smoothstep(0.50, 0.92, abs(scene_n.y));
		float foam_depth = shore_foam_depth * mix(0.18, 1.0, flatness);
		float shore = 1.0 - smoothstep(0.0, foam_depth, vd0);
		float band1 = 0.5 + 0.5 * sin(vd0 * 7.6 / foam_depth + sea_time * 1.55 + blot * 1.50);
		float band2 = 0.5 + 0.5 * sin(vd0 * 12.6 / foam_depth + sea_time * 2.15 - blot * 1.15);
		float surf_bands = max(band1 * band1, band2 * band2 * 0.58);
		float lip_lace = 0.58 + 0.46 * smoothstep(0.22, 0.82, blot * 0.56 + band1 * 0.44);
		float beach_wash = shore * (0.24 + 0.64 * surf_bands) * 0.82 + smoothstep(0.16, 0.0, vd0) * 0.88 * lip_lace;
		// Tight lacy whitewater collar around steep rocks and ship hulls (slightly boosted when foam_field is off on LOW).
		float collar_wave = 0.84 + 0.16 * sin(sea_time * 2.2 + dot(v_rest, vec2(0.7, 0.5)));
		float low_collar_k = mix(1.28, 1.0, step(0.5, foam_field_on));
		float hull_collar = (smoothstep(0.18 * low_collar_k, 0.0, vd0) * 0.90 + smoothstep(0.52 * low_collar_k, 0.06, vd0) * 0.36 * band1 * (0.48 + 0.52 * blot)) * collar_wave;
		float shore_foam = mix(hull_collar, beach_wash, flatness);
		shore_foam *= has_floor * in_water;

		// Wave-action-driven gossamer frothy webbing: ZERO unconditional open-water floor!
		// Calm troughs and sheltered lagoons stay rich deep sapphire; breaking ridges,
		// steep choppy crests, ship wakes, and surf drape delicate frothy webbing.
		float wave_energy = smoothstep(0.46, 0.78, sea_amp_scale) * deep_water;
		float slope_len = length(n_geo.xz);
		float near_web_fade = smoothstep(115.0, 10.0, dist);
		float web_patch = smoothstep(0.24, 0.86, texture(foam_tex, (draped + flow_off0 * 0.7) * 0.026).g);
		float ridge_act = smoothstep(0.42, 0.92, crest) * 0.42 + smoothstep(0.12, 0.34, slope_len) * 0.34 + smoothstep(0.60, 0.92, chop_fold) * 0.36;
		float web_src = max(ridge_act * wave_energy, max(field * 1.0, shore_foam * 0.86));
		web_src = max(web_src, crest_foam * 0.85 + storm * 0.36 * smoothstep(0.06, 0.24, slope_len) * deep_water);
		float web_amt = near_web_fade * clamp(web_src, 0.0, 1.0) * mix(0.26, 1.20, web_patch);

		float soft = clamp(0.045 + fp * 0.55, 0.045, 0.45);
		float amount = clamp(max(min(crest_foam, 0.78), shore_foam * 0.92), 0.0, 0.96);
		float streak = storm * clamp(max(linger, standing) * 1.85 - shore_foam, 0.0, 1.0) * 0.72;
		// Keep shallow beach surf lace isotropic (un-smeared) while open-sea crests stretch along wave flow.
		float foam_stretch = flow_stretch * (1.0 - clamp(shore_foam * 0.70, 0.0, 0.70));
		vec3 fm = foam_mask_flow(amount, web_amt, draped, flow_off0, flow_off1, flow_w, flow_dir, foam_stretch, soft, quality > 0 ? streak : 0.0);
		// Break distant whitecaps into wind-torn spindrift flecks & streaks instead of solid snow-drifts.
		float far_fleck = smoothstep(0.24, 0.80, mix(blot * 0.65 + chop_fold * 0.55, spindrift * 0.70 + chop_fold * 0.45, storm * 0.82));
		float heavy_foam = mix(amount * amount * 0.40 * far_fleck, fm.x, lod_fade);
		float foam_body = mix(0.5, fm.y, lod_fade);
		float web_foam = fm.z * lod_fade;

		// Tight milky turquoise-green aeration strictly beneath active foam patches & ship wakes
		// (fades cleanly at distance so aerial views never show glowing cyan halos).
		float aerate_src = clamp(max(heavy_foam * 1.15, web_foam * 0.78) + field * 0.92 + shore_foam * 0.72, 0.0, 1.0);
		float aerate = smoothstep(0.24, 0.82, aerate_src) * lod_fade * smoothstep(340.0, 45.0, dist);
		vec3 milky_light = ambient_color * 0.68 + sun_light * (0.34 + 0.66 * clamp(dot(N, L), 0.0, 1.0));
		vec3 milky_col = foam_under_color * milky_light * mix(0.72, 1.10, smoothstep(0.55, 1.0, macro_light));
		col = mix(col, milky_col, clamp(aerate * 0.46 + heavy_foam * 0.24, 0.0, 0.56));

		// --- sky reflection (lower flat reflectivity keeps deep jewel troughs bold & pure)
		float ndv = max(dot(N, V), 0.0);
		float ndv_eff = clamp(ndv + sqrt(rough_var) * 0.85, 0.0, 1.0);
		float fres = 0.02 + 0.98 * pow(1.0 - ndv_eff, 5.0);
		vec3 R = reflect(-V, N);
		R.y = abs(R.y) + sqrt(rough_var) * 0.72;
		R = normalize(R);
		vec3 refl = ocean_sky(R);
		// Keep daytime troughs rich jewel marine blue rather than muddy warm-grey reflection.
		float day_cool = (1.0 - night_bio) * (1.0 - storm) * smoothstep(0.12, 0.42, L.y);
		refl *= mix(vec3(1.0), vec3(0.84, 0.96, 1.12), day_cool * 0.42);
		// Tight sunlit mirror accent + molten golden-hour sunset sun-path ribbon (zero broad midday wash).
		float rs = max(dot(R, L), 0.0);
		float sunset_ribbon = golden_hour * clamp(cloud_l, 0.22, 1.35) * (pow(rs, 20.0) * 0.72 + pow(rs, 110.0) * 1.95);
		refl += sun_light * (pow(rs, 90.0) * 0.60 * mix(1.0, 0.14, storm) + sunset_ribbon);
		float film = mix(0.28, 1.0, smoothstep(0.0, 2.5, thick));
		float foam_damp = 1.0 - clamp(heavy_foam * 0.68 + aerate * 0.26, 0.0, 0.84);
		float refl_boost = mix(reflectivity, min(reflectivity + 0.24, 0.82), golden_hour * smoothstep(0.25, 0.85, fres));
		col = mix(col, refl, clamp(fres * refl_boost * film * foam_damp, 0.0, 1.0));

		// --- crisp refined sun sparkles along the solar path (zero overcast storm / midnight confetti)
		vec3 H = normalize(L + V);
		float sharp = 1.0 / (1.0 / glint_sharpness + rough_var * 2.1);
		float glint_norm = glint_sharpness / (sharp + glint_sharpness);
		float glint = 0.0;
		if (quality > 0) {
			vec3 n_sp1 = normalize(N + vec3(rip_fine.x, 0.0, rip_fine.y) * 1.45 + vec3(rip_med.x, 0.0, rip_med.y) * 0.42);
			vec3 n_sp2 = normalize(N + vec3(rip_micro.x, 0.0, rip_micro.y) * 1.65 - vec3(rip_fine.y, 0.0, -rip_fine.x) * 0.50);
			float c1 = pow(max(dot(n_sp1, H), 0.0), sharp);
			float c2 = pow(max(dot(n_sp2, H), 0.0), sharp * 1.20);
			float tw1 = smoothstep(0.45, 0.78, c1) * glint_norm * 1.40;
			float tw2 = smoothstep(0.44, 0.76, c2) * glint_norm * 1.15 * smoothstep(320.0, 12.0, dist);
			glint = max(tw1, tw2) + min(tw1, tw2) * 0.40;
		} else {
			float c1 = pow(max(dot(N, H), 0.0), sharp);
			glint = smoothstep(0.45, 0.78, c1) * glint_norm * 1.35;
		}
		// Subtle sunlit silk sheen along the specular azimuth, richer liquid gold at golden hour.
		glint += pow(max(dot(N, H), 0.0), sharp * 0.28) * mix(0.024, 0.11, golden_hour);
		float key = max(sun_light.r, max(sun_light.g, sun_light.b));
		vec3 glint_col = sun_light * (1.0 + 1.25 * smoothstep(0.45, 0.06, key));
		// Keep golden-hour low sun sparkling across waves while suppressing overcast storms & midnight.
		float glint_sky = smoothstep(0.005, 0.09, L.y) * (1.0 - night_bio) * mix(1.0, 0.06, storm * storm) * clamp(cloud_l, 0.18, 1.25);
		float glint_mask = (1.0 - clamp(heavy_foam * 0.85, 0.0, 0.85)) * glint_sky;
		col += glint_col * glint * glint_strength * (0.34 + 0.66 * fres) * mix(1.0, 1.45, golden_hour) * glint_mask;
		// Soft silvery moonlit silk shimmer on open night swells (zero pinhole pixel noise).
		if (night_bio > 0.01) {
			float moon_shimmer = pow(max(dot(N, H), 0.0), 46.0) * (0.24 + 0.76 * fres) * (1.0 - clamp(heavy_foam * 0.85, 0.0, 0.85));
			col += sun_light * moon_shimmer * (0.48 * night_bio);
		}
		col += (ambient_color + sun_light * 0.5) * splash * 0.35;

		// --- composite organic wave-action webbing and creamy breaking caps on top
		vec3 foam_light = ambient_color * 0.86 + sun_light * (0.36 + 0.58 * clamp(dot(N, L), 0.0, 1.0));
		// Keep night-time ship wake foam subtle moonlit silver-blue so bioluminescent plankton stars pop cleanly!
		foam_light *= mix(1.0, 0.66, night_bio);
		float foam_shade = mix(0.80, 1.08, smoothstep(0.75, 1.0, macro_light));
		vec3 web_tone = mix(foam_under_color, foam_color, 0.76) * foam_light * foam_shade;
		col = mix(col, web_tone, clamp(web_foam * 0.72, 0.0, 0.72));
		vec3 thin_tone = mix(foam_under_color, foam_color, 0.68);
		vec3 foam_lit = mix(thin_tone, foam_color, smoothstep(0.05, 0.72, foam_body)) * foam_light * foam_shade;
		col = mix(col, foam_lit, heavy_foam * mix(0.76, 0.95, foam_body));

		// --- nocturnal bioluminescent plankton shimmer in ship wakes, breaking crests & surf (0 extra taps)
		// Carves lacy starry plankton ribbons out of swirling wake filaments & fine ripple glitter so
		// night wakes sparkle like living bioluminescence rather than glowing solid oval pads!
		if (night_bio > 0.001) {
			float rip_energy = clamp(length(rip_fine + rip_micro * 0.85) * 2.4, 0.0, 1.0);
			float micro_twinkle = 0.5 + 0.5 * sin(dot(v_rest, vec2(3.7, -2.9)) + sea_time * 2.6 + blot * 9.0);
			float fine_glitter = smoothstep(0.48, 0.94, rip_energy * 0.58 + micro_twinkle * 0.52);
			float lace_fil = clamp((heavy_foam - foam_body * 0.58) * 1.35 + web_foam * 1.48 + shore_foam * 0.72, 0.0, 1.0);
			float wake_bio = max(field, shore_foam * (1.0 - step(0.5, foam_field_on)) * 0.58) * smoothstep(0.18, 0.82, lace_fil * 0.76 + fine_glitter * 0.58) * (0.28 + 0.96 * lace_fil);
			float crest_bio = clamp(heavy_foam * 0.52 + web_foam * 0.58 + shore_foam * 0.48, 0.0, 1.0) * smoothstep(0.24, 0.84, blot * 0.52 + fine_glitter * 0.58);
			float bio_shimmer = (0.40 + 0.60 * blot) * (0.50 + 0.92 * fine_glitter);
			float bio_dist = smoothstep(135.0, 16.0, dist);
			vec3 bio_col = mix(vec3(0.03, 0.58, 0.84), vec3(0.26, 0.98, 1.00), fine_glitter * 0.74);
			float bio_intensity = (wake_bio * 0.62 + crest_bio * 0.16) * bio_shimmer * bio_dist * night_bio;
			col += bio_col * bio_intensity;
		}

		alpha_edge = smoothstep(0.0, 0.04, thick0);
		col = mix(texture(screen_tex, SCREEN_UV).rgb, col, alpha_edge);

		// --- aerial haze & bright hazy horizon melt into sky_horizon_color
		float aerial = (1.0 - exp(-max(dist - 220.0, 0.0) * 0.00042)) * mix(0.55, 0.85, pow(1.0 - max(V.y, 0.0), 3.0));
		col = mix(col, sky_horizon_color, clamp(aerial * 0.55, 0.0, 0.55));
		float hf = smoothstep(horizon_fade_start, horizon_fade_end, dist);
		col = mix(col, sky_horizon_color, hf);
	} else {
		// ---------------- seen from below ----------------
		vec3 Nd = -N;
		vec3 I = -V;
		vec3 T = refract(I, Nd, 1.333);
		float cos_i = max(dot(V, Nd), 0.0);
		vec3 Rd = reflect(I, Nd);
		vec3 mirror = uw_ambient(normalize(vec3(Rd.x, -abs(Rd.y), Rd.z))) * (0.75 + 2.2 * pow(1.0 - abs(Rd.y), 2.0));
		if (dot(T, T) < 1e-5) {
			col = mirror;
		} else {
			T = normalize(T);
			vec3 T_sky = normalize(vec3(T.x, max(T.y, 0.06), T.z));
			vec3 sky = ocean_sky(T_sky);
			float sd = max(dot(T_sky, L), 0.0);
			sky += sun_light * (pow(sd, 350.0) * 14.0 + pow(sd, 24.0) * 0.9 + pow(sd, 4.0) * 0.25);
			vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(T, 0.0));
			vec2 suv = clip.xy / max(clip.w, 1e-4) * 0.5 + 0.5;
			vec2 edge = min(suv, 1.0 - suv);
			float tn = max(dot(T, N), 0.0);
			float snell_soft = smoothstep(0.14, 0.46, tn);
			float on_screen = step(1e-4, clip.w) * smoothstep(0.0, 0.12, min(edge.x, edge.y)) * snell_soft;
			vec3 sv;
			float raw_u;
			float sz = linear_depth(clamp(suv, vec2(0.001), vec2(0.999)), INV_PROJECTION_MATRIX, sv, raw_u);
			vec3 sw = (INV_VIEW_MATRIX * vec4(sv, 1.0)).xyz;
			on_screen *= step(1e-5, raw_u) * step(-0.2, sw.y);
			sky = mix(sky, texture(screen_tex, clamp(suv, vec2(0.001), vec2(0.999))).rgb, on_screen * 0.80);
			float fr = clamp(0.04 + 0.96 * pow(1.0 - tn, 2.35), 0.0, 1.0);
			col = mix(sky, mirror, fr);
			col *= 1.0 + 0.22 * smoothstep(0.55, 1.0, cos_i);
		}
		float f_under = max(smoothstep(foam_crest_start, foam_crest_full, jac), field_foam(v_rest, dist));
		col *= 1.0 - 0.45 * f_under;
		col = uw_apply(col, dist, I) + uw_shafts(cam, I, dist, FRAGCOORD.xy);
	}
	ALBEDO = col;
}
