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
// Simulated foam (Ocean's foam field): R = amount, stored in rest-plane
// coordinates, one tile of foam_field_size metres that wraps around the camera.
uniform sampler2D foam_field : repeat_enable, filter_linear;
uniform float foam_field_size = 256.0;
uniform float foam_field_on = 0.0;

// 0 low, 1 medium, 2 high. See Ocean.quality for what each level buys.
uniform int quality = 2;

group_uniforms water;
uniform vec3 deep_color : source_color = vec3(0.004, 0.055, 0.18);
uniform vec3 scatter_color : source_color = vec3(0.008, 0.42, 0.48);
uniform vec3 sss_color : source_color = vec3(0.10, 0.90, 0.80);
uniform vec3 shallow_color : source_color = vec3(0.04, 0.72, 0.70);
uniform vec3 foam_under_color : source_color = vec3(0.18, 0.74, 0.68);
uniform vec3 absorption = vec3(0.42, 0.082, 0.068); // per metre
uniform float turbidity = 0.12;       // how fast the body colour builds with depth
uniform float refraction_strength = 0.36;
uniform float sss_strength = 1.10;
uniform float reflectivity = 0.60;
group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 0.97);
uniform float foam_crest_start = 0.91; // Jacobian below this starts to foam
uniform float foam_crest_full = 0.66;
uniform float foam_scale = 0.20;
uniform float shore_foam_depth = 1.45;
group_uniforms sun;
uniform float glint_sharpness = 320.0;
uniform float glint_strength = 6.5;
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

float linear_depth(vec2 uv, mat4 inv_proj, out vec3 view_pos) {
	float raw = texture(depth_tex, uv).r;
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
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
		vec2 suv = vec2(dot(rest_p, along) * 0.16, dot(rest_p, across) * 0.62) * foam_scale;
		float s1 = texture(foam_tex, suv + w * 0.35).r;
		float s2 = texture(foam_tex, suv * vec2(0.65, 1.70) + 0.37).b;
		pattern = mix(pattern, s1 * 0.56 + s2 * 0.44, streak);
		fil_wall = mix(fil_wall, s1 * 0.50 + s2 * 0.50, streak * 0.75);
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
	float body = smoothstep(thr, thr + 0.42, 1.0 - pattern);
	// Organic frothy webbing draped strictly where wave action / wakes / surf exist
	float web_edge = mix(0.18, 0.56, clamp(web_amt, 0.0, 1.0));
	float web_fil = 1.0 - smoothstep(0.06, web_edge, s.y);
	float web_cover = web_fil * smoothstep(0.02, 0.14, web_amt) * clamp(web_amt * 1.10, 0.0, 0.68);
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

	// --- multi-octave variance-normalized wave-advected micro ripples (normal-only detail)
	const mat2 ROT_B = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	float fine = smoothstep(0.45, 0.025, fp);
	float med_fade = smoothstep(1.6, 0.08, fp);
	vec2 rip_fine;
	vec2 rip_med;
	vec2 rip_micro = vec2(0.0);
	vec2 ripple;
	float gust = 0.55;
	if (quality > 0) {
		rip_fine = ripple_flow(draped * 0.135, flow_off0 * 0.135, flow_off1 * 0.135, flow_w) * fine;
		vec2 uv_m = (ROT_B * draped) * 0.054;
		vec2 fm0 = (ROT_B * flow_off0) * 0.054;
		vec2 fm1 = (ROT_B * flow_off1) * 0.054;
		rip_med = ripple_flow(uv_m, fm0, fm1, flow_w) * med_fade;
		// Third broad chop octave for sculpted mid-distance facets
		vec2 r3 = texture(detail_tex, draped * 0.0165 + flow_off0 * 0.0165).rg - 0.5;
		// Fourth high-frequency wind-chop layer for crisp near sparkles & glossy texture
		vec2 uv_micro = (draped.yx * 0.295) + wind_dir * 0.055 * sea_time;
		rip_micro = ripple_flow(uv_micro, flow_off0.yx * 0.295, flow_off1.yx * 0.295, flow_w) * smoothstep(0.26, 0.015, fp);
		ripple = rip_fine * 1.05 + rip_med * 1.30 + r3 * 0.65 * smoothstep(5.5, 0.45, fp) + rip_micro * (0.62 + 0.42 * storm);
		gust = smoothstep(0.18, 0.82, texture(foam_tex, v_rest * 0.0037 + wind_dir * 0.004 * sea_time).g);
	} else {
		rip_fine = (texture(detail_tex, draped * 0.125 + flow_off0 * 0.125).rg - 0.5) * fine;
		rip_med = (texture(detail_tex, (ROT_B * draped) * 0.048 + (ROT_B * flow_off0) * 0.048).rg - 0.5) * med_fade;
		ripple = rip_fine * 0.95 + rip_med * 1.25;
	}

	float crest_pre = clamp((1.0 - jac) * 1.9, 0.0, 1.0) * 0.55 + smoothstep(0.10, 1.05, h_rel) * 0.65;
	crest_pre = clamp(crest_pre, 0.0, 1.0);
	// Sheltered lagoons keep calmer gentle ripples; open fair/storm seas are richly sculpted & glossy.
	float open_sea = smoothstep(0.28, 0.65, sea_amp_scale);
	float ripple_amt = mix(0.28, mix(0.52, 0.78, storm), open_sea) * mix(0.72, 1.38, gust) * (1.0 + 0.24 * crest_pre);
	float exag = mix(1.90, 1.0, smoothstep(0.0, 0.65, storm));
	vec3 n_shade = normalize(n_geo - vec3(long_slope.x, 0.0, long_slope.y) * (exag - 1.0));
	vec3 n_detail = vec3(ripple.x, 0.0, ripple.y) * ripple_amt;
	float splash = 0.0;
	if (rain_intensity > 0.01 && quality > 0 && fp < 0.09) {
		vec3 rr = rain_rings(v_rest, rain_intensity, quality > 1 ? 3 : 2) * smoothstep(0.09, 0.02, fp);
		n_detail += vec3(rr.x, 0.0, rr.y) * 0.22;
		splash = rr.z;
	}
	vec3 N = normalize(n_shade + n_detail);
	float rough_var = lost_var + 0.0005 + 0.0024 * storm + 0.004 * rain_intensity;

	// --- lighting with per-pixel cloud shadows
	vec3 L = normalize(sun_dir);
	float cloud_l = sample_cloud_light(v_world.xz);
	vec3 sun_light = ocean_sun_light() * cloud_l;
	vec3 light = ambient_color * 0.68 + sun_light * (0.24 + 0.76 * clamp(L.y, 0.0, 1.0));

	// --- what lies behind the surface
	vec3 scene_view;
	float scene_z = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX, scene_view);
	float thick0 = max(scene_z - surf_z, 0.0) * dist / max(surf_z, 1e-4);

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
		if (quality > 0) {
			vec3 n_view = (VIEW_MATRIX * vec4(N, 0.0)).xyz;
			vec2 offs = n_view.xy * refraction_strength * clamp(thick0 * 0.6, 0.0, 1.0) / max(surf_z, 1.0);
			uv_r = clamp(SCREEN_UV - offs, vec2(0.001), vec2(0.999));
			rz = linear_depth(uv_r, INV_PROJECTION_MATRIX, rv);
			if (rz < surf_z + 0.02) {
				uv_r = SCREEN_UV;
				rv = scene_view;
				rz = scene_z;
			}
		}
		float thick = max(rz - surf_z, 0.0) * dist / max(surf_z, 1e-4);
		vec3 scene_world = (INV_VIEW_MATRIX * vec4(rv, 1.0)).xyz;
		float vdepth = max(v_world.y - scene_world.y, 0.0);
		vec3 behind = texture(screen_tex, uv_r).rgb;

		// Caustic light dancing on shallow seabeds (modulated by cloud shadow).
		if (quality > 0 && vdepth < 14.0 && dist < 120.0) {
			float sun_up = max(L.y, 0.15);
			vec2 cq = scene_world.xz + L.xz * (vdepth / sun_up);
			float caus = ocean_caustic(cq) * exp(-vdepth * 0.21) * smoothstep(0.0, 0.45, vdepth);
			caus *= smoothstep(120.0, 30.0, dist);
			vec3 floor_n = normalize(cross(dFdy(scene_world), dFdx(scene_world)));
			caus = min(caus, 2.5) * smoothstep(0.25, 0.7, floor_n.y);
			behind *= 1.0 + caus * 1.75 * smoothstep(0.0, 0.3, L.y) * (sun_light.g + 0.08);
		}
		behind *= 0.70 + 0.30 * exp(-thick * 4.0);
		behind *= mix(vec3(1.0), vec3(0.38, 0.94, 0.96), 1.0 - exp(-thick * 1.3));

		// --- deep jewel-teal colour separation: deep sapphire troughs & backs,
		// rich emerald-teal wave bodies, luminous aquamarine-cyan thinned crests (SSS)
		float crest = crest_pre;
		float facing = 1.0 - max(dot(N, V), 0.0);
		float back_lit = pow(max(dot(V, -normalize(L + N * 0.32)), 0.0), 2.5);
		float side_lit = pow(max(dot(V, -normalize(vec3(L.x, L.y * 0.5, L.z) + N * 0.45)), 0.0), 1.9);
		float slope_light = dot(N, normalize(L + vec3(0.0, 0.50, 0.0)));
		float macro_light = dot(n_shade, normalize(L + vec3(0.0, 0.55, 0.0)));
		float tilt = dot(-long_slope, normalize(L.xz + vec2(1e-4)));
		float swell_shade = clamp(1.0 + tilt * mix(8.5, 1.8, storm), 0.46, 1.38);

		// Deep sapphire-indigo in distant backs & troughs; luminous jewel sapphire-emerald
		// translucent body floor in near-camera troughs (~60 m), tapering gently with distance.
		float near_emerald = smoothstep(115.0, 18.0, dist);
		float body_floor = mix(0.03, 0.16, near_emerald);
		float dist_sapphire = smoothstep(50.0, 480.0, dist);
		float body_k = body_floor + 0.34 * smoothstep(-0.55, 1.05, h_rel) + 0.40 * crest + 0.14 * facing * facing;
		body_k *= mix(1.0, 0.14, dist_sapphire);
		body_k *= mix(0.56, 1.22, smoothstep(0.58, 0.98, macro_light));
		body_k = max(body_k, body_floor * 0.78);
		float face_contrast = mix(0.46, 1.36, smoothstep(0.60, 0.98, mix(macro_light, slope_light, 0.45)));
		vec3 body = mix(deep_color, scatter_color, clamp(body_k, 0.0, 1.0)) * light * face_contrast * swell_shade;

		// Luminous emerald-aquamarine translucent glow reserved for thinned upper crests,
		// moderated at low sun/moon elevation so night horizon stays moody indigo-teal.
		float sss_elev = smoothstep(-0.02, 0.16, L.y);
		float sss_key = smoothstep(0.08, 0.55, max(sun_light.r, max(sun_light.g, sun_light.b)));
		float sss_mod = mix(0.22, 1.0, sss_elev * sss_key);
		// Break smooth crest SSS with organic wavelet facets so aerial views never show uniform ovals.
		float sss_break = clamp(0.65 + (N.x * 0.9 + N.z * 0.7) * 0.55 + (1.0 - N.y) * 0.75, 0.35, 1.30);
		float ridge_thin = smoothstep(0.34, 0.96, crest) * smoothstep(0.10, 0.92, h_rel) * sss_break;
		float thin = clamp(ridge_thin * 1.02 + 0.52 * smoothstep(0.14, 0.90, h_rel) * max(back_lit, side_lit * 0.50) * sss_break, 0.0, 1.0);
		body += sss_color * sss_strength * sss_mod * (
				ridge_thin * light * 0.44
				+ thin * sun_light * (2.05 * back_lit + 0.52 * side_lit)
		) * (0.35 + 0.65 * facing) * mix(1.0, 0.25, dist_sapphire);

		// Depth-based absorption: vibrant turquoise shallows over sandy beaches.
		float path = vdepth * 1.45 + min(thick, 10.0) * 0.12;
		vec3 trans = exp(-(absorption + turbidity) * path);
		float fill = 1.0 - exp(-turbidity * (path + min(thick, 4.0) * 0.85));
		vec3 shallow_tint = mix(shallow_color, scatter_color, 0.25) * light * 0.68;
		col = behind * trans + mix(shallow_tint, body, smoothstep(0.0, 8.5, path)) * fill;

		// --- compute foam sources early so milky aqua aeration glows ONLY beneath real foam
		float lod_fade = smoothstep(0.95, 0.22, fp * 0.18);
		// Keep calm sheltered lagoons (depth < ~3 m or low-swell flat water) clean and foam-free.
		float has_floor = step(scene_z, surf_z + 60.0);
		float deep_water = mix(1.0, smoothstep(2.4, 4.0, vdepth), has_floor);
		float open_foam = smoothstep(0.46, 0.64, sea_amp_scale) * deep_water;
		float f_now = smoothstep(foam_crest_start, foam_crest_full, jac) * deep_water;
		// Chunky fair-weather breaking ridges: steep pinched high crests form creamy lacy caps
		float fair_cap = smoothstep(0.32, 0.92, h_rel) * smoothstep(0.97, 0.84, jac) * mix(0.84, 0.30, storm) * open_foam;
		float field = field_foam(v_rest, dist);
		float crest_foam = max(max(f_now, fair_cap), field);
		float linger = clamp(field - max(f_now, fair_cap), 0.0, 1.0);
		if (foam_field_on < 0.5 || dist > foam_field_size * 0.31) {
			float j1 = sea_jacobian_lod(v_rest, sea_time - 1.1, max(fp * 2.5, 5.0));
			float f_trail = smoothstep(foam_crest_start, foam_crest_full, j1 + 0.02) * 0.60 * deep_water;
			if (quality > 0) {
				float j2 = sea_jacobian_lod(v_rest, sea_time - 2.6, max(fp * 2.5, 5.0));
				f_trail = max(f_trail, smoothstep(foam_crest_start, foam_crest_full, j2 + 0.04) * 0.36 * deep_water);
			}
			crest_foam = max(crest_foam, f_trail);
			linger = max(linger, clamp(f_trail - f_now, 0.0, 1.0));
		}
		// Wind streaks: standing foam in rough weather, drawn out downwind.
		vec2 wuv = vec2(dot(v_rest, wind_dir) * 0.004, dot(v_rest, vec2(-wind_dir.y, wind_dir.x)) * 0.021);
		float blot = texture(foam_tex, wuv + vec2(0.002, 0.0) * sea_time).g;
		float standing = storm * storm * smoothstep(0.38, 0.90, blot) * 0.62 * smoothstep(-0.5, 0.5, h_rel) * deep_water;
		crest_foam = max(crest_foam, standing);

		// Shoreline / ship-hull intersection foam from the depth buffer.
		vec3 sw0 = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
		float vd0 = max(v_world.y - sw0.y, 0.0);
		float in_water = 1.0;
		if (quality > 0 && thick0 < 8.0 && vd0 < shore_foam_depth) {
			vec2 rest_there = sw0.xz - (v_world.xz - v_rest);
			float sd = sea_displacement_lod(rest_there, fp * 2.5).y - sw0.y;
			vd0 = max(sd, 0.0);
			in_water = smoothstep(-0.30, -0.05, sd);
		}
		// Gentle beaches get animated multi-band surf wash; steep rocks & hulls get a crisp white collar.
		vec3 scene_n = normalize(cross(dFdy(sw0), dFdx(sw0)));
		float flatness = smoothstep(0.50, 0.92, abs(scene_n.y));
		float foam_depth = shore_foam_depth * mix(0.18, 1.0, flatness);
		float shore = 1.0 - smoothstep(0.0, foam_depth, vd0);
		float band1 = 0.5 + 0.5 * sin(vd0 * 10.5 / foam_depth + sea_time * 1.65 + blot * 5.5);
		float band2 = 0.5 + 0.5 * sin(vd0 * 18.0 / foam_depth + sea_time * 2.35 - blot * 3.8);
		float surf_bands = max(band1 * band1, band2 * band2 * 0.70);
		float beach_wash = shore * (0.24 + 0.76 * surf_bands) * 0.92 + smoothstep(0.12, 0.0, vd0) * 0.78;
		// Crisp white collar right around steep rocks and ship hulls.
		float collar_wave = 0.85 + 0.15 * sin(sea_time * 2.2 + dot(v_rest, vec2(0.7, 0.5)));
		float hull_collar = (smoothstep(0.26, 0.0, vd0) * 0.88 + smoothstep(0.55, 0.08, vd0) * 0.35 * band1) * collar_wave;
		float shore_foam = mix(hull_collar, beach_wash, flatness);
		shore_foam *= step(scene_z, surf_z + 60.0) * in_water;

		// Wave-action-driven gossamer frothy webbing: ZERO unconditional open-water floor!
		// Calm troughs and sheltered lagoons stay rich glassy jewel-teal; breaking ridges,
		// steep faces, lingering trails/wakes, and surf drape organic frothy webbing.
		float wave_energy = smoothstep(0.46, 0.78, sea_amp_scale) * deep_water;
		float slope_len = length(n_geo.xz);
		float near_web_fade = smoothstep(115.0, 10.0, dist);
		float web_patch = smoothstep(0.22, 0.84, texture(foam_tex, (draped + flow_off0 * 0.7) * 0.026).g);
		float ridge_act = smoothstep(0.22, 0.82, crest) * 0.64 + smoothstep(0.08, 0.30, slope_len) * 0.56;
		float web_src = max(ridge_act * wave_energy, max(field * 0.95, shore_foam * 0.82));
		web_src = max(web_src, crest_foam * 0.88 + storm * 0.24 * smoothstep(0.06, 0.26, slope_len) * deep_water);
		float web_amt = near_web_fade * clamp(web_src, 0.0, 1.0) * mix(0.30, 1.28, web_patch);

		float soft = clamp(0.045 + fp * 0.55, 0.045, 0.45);
		float amount = clamp(max(min(crest_foam, 0.78), shore_foam), 0.0, 1.0);
		float streak = storm * clamp(max(linger, standing) * 2.0 - shore_foam, 0.0, 1.0) * 0.85;
		vec3 fm = foam_mask_flow(amount, web_amt, draped, flow_off0, flow_off1, flow_w, flow_dir, flow_stretch, soft, quality > 0 ? streak : 0.0);
		float heavy_foam = mix(amount * amount * 0.6, fm.x, lod_fade);
		float foam_body = mix(0.5, fm.y, lod_fade);
		float web_foam = fm.z * lod_fade;

		// Milky turquoise-green aerated water visibly glowing right beneath actual foam patches.
		float aerate_src = clamp(max(amount * 1.15, web_foam * 0.95) + field * 0.80 + shore_foam * 0.75, 0.0, 1.0);
		float aerate = smoothstep(0.15, 0.72, aerate_src) * mix(0.45, 1.0, lod_fade);
		vec3 milky_light = ambient_color * 0.70 + sun_light * (0.36 + 0.64 * clamp(dot(N, L), 0.0, 1.0));
		vec3 milky_col = foam_under_color * milky_light * mix(0.80, 1.12, smoothstep(0.75, 1.0, macro_light));
		col = mix(col, milky_col, clamp(aerate * 0.60 + heavy_foam * 0.28, 0.0, 0.72));

		// --- sky reflection (lower flat reflectivity keeps deep jewel troughs bold)
		float ndv = max(dot(N, V), 0.0);
		float ndv_eff = clamp(ndv + sqrt(rough_var) * 0.85, 0.0, 1.0);
		float fres = 0.02 + 0.98 * pow(1.0 - ndv_eff, 5.0);
		vec3 R = reflect(-V, N);
		R.y = abs(R.y) + sqrt(rough_var) * 0.72;
		R = normalize(R);
		vec3 refl = ocean_sky(R);
		// Sun reflection accent (cloud-shadowed); keep broad lobe minimal so sunlit
		// foreground troughs remain jewel sapphire-emerald rather than muddy olive.
		float rs = max(dot(R, L), 0.0);
		refl += sun_light * (pow(rs, 10.0) * 0.04 + pow(rs, 70.0) * 0.56);
		float film = mix(0.28, 1.0, smoothstep(0.0, 2.5, thick));
		float foam_damp = 1.0 - clamp(heavy_foam * 0.68 + aerate * 0.26, 0.0, 0.84);
		col = mix(col, refl, clamp(fres * reflectivity * film * foam_damp, 0.0, 1.0));

		// --- crisp dense twinkling sun / moon glints across sunlit wave facets
		vec3 H = normalize(L + V);
		float sharp = 1.0 / (1.0 / glint_sharpness + rough_var * 1.8);
		float glint_norm = glint_sharpness / (sharp + glint_sharpness);
		float glint = 0.0;
		if (quality > 0) {
			vec3 n_sp1 = normalize(N + vec3(rip_fine.x, 0.0, rip_fine.y) * 2.1 + vec3(rip_med.x, 0.0, rip_med.y) * 0.55);
			vec3 n_sp2 = normalize(N + vec3(rip_micro.x, 0.0, rip_micro.y) * 2.5 - vec3(rip_fine.y, 0.0, -rip_fine.x) * 0.70);
			float c1 = pow(max(dot(n_sp1, H), 0.0), sharp);
			float c2 = pow(max(dot(n_sp2, H), 0.0), sharp * 1.15);
			float tw1 = smoothstep(0.34, 0.66, c1) * glint_norm * 2.05;
			float tw2 = smoothstep(0.32, 0.64, c2) * glint_norm * 1.85 * smoothstep(380.0, 10.0, dist);
			glint = max(tw1, tw2) + min(tw1, tw2) * 0.50;
		} else {
			float c1 = pow(max(dot(N, H), 0.0), sharp);
			glint = smoothstep(0.34, 0.66, c1) * glint_norm * 1.8;
		}
		// Crisp sunlit shimmer path across mid/far sea without warm foreground wash
		glint += pow(max(dot(N, H), 0.0), sharp * 0.22) * 0.035;
		float key = max(sun_light.r, max(sun_light.g, sun_light.b));
		vec3 glint_col = sun_light * (1.0 + 1.5 * smoothstep(0.5, 0.05, key));
		float glint_mask = (1.0 - clamp(heavy_foam * 0.85, 0.0, 0.85)) * smoothstep(-0.02, 0.05, L.y);
		col += glint_col * glint * glint_strength * (0.34 + 0.66 * fres) * glint_mask;
		col += (ambient_color + sun_light * 0.5) * splash * 0.35;

		// --- composite organic wave-action webbing and creamy breaking caps on top
		vec3 foam_light = ambient_color * 0.86 + sun_light * (0.36 + 0.58 * clamp(dot(N, L), 0.0, 1.0));
		float foam_shade = mix(0.80, 1.08, smoothstep(0.75, 1.0, macro_light));
		vec3 web_tone = mix(foam_under_color, foam_color, 0.76) * foam_light * foam_shade;
		col = mix(col, web_tone, clamp(web_foam * 0.72, 0.0, 0.72));
		vec3 thin_tone = mix(foam_under_color, foam_color, 0.68);
		vec3 foam_lit = mix(thin_tone, foam_color, smoothstep(0.05, 0.72, foam_body)) * foam_light * foam_shade;
		col = mix(col, foam_lit, heavy_foam * mix(0.80, 0.97, foam_body));

		alpha_edge = smoothstep(0.0, 0.06, thick0);
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
			vec3 sky = ocean_sky(T);
			float sd = max(dot(T, L), 0.0);
			sky += sun_light * (pow(sd, 350.0) * 14.0 + pow(sd, 24.0) * 0.9 + pow(sd, 4.0) * 0.25);
			vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(T, 0.0));
			vec2 suv = clip.xy / max(clip.w, 1e-4) * 0.5 + 0.5;
			vec2 edge = min(suv, 1.0 - suv);
			float on_screen = step(1e-4, clip.w) * smoothstep(0.0, 0.08, min(edge.x, edge.y));
			vec3 sv;
			float sz = linear_depth(clamp(suv, vec2(0.001), vec2(0.999)), INV_PROJECTION_MATRIX, sv);
			vec3 sw = (INV_VIEW_MATRIX * vec4(sv, 1.0)).xyz;
			on_screen *= step(-0.2, sw.y);
			sky = mix(sky, texture(screen_tex, clamp(suv, vec2(0.001), vec2(0.999))).rgb, on_screen * 0.85);
			float fr = 0.02 + 0.98 * pow(1.0 - max(dot(T, N), 0.0), 5.0);
			col = mix(sky, mirror, clamp(fr, 0.0, 1.0));
			col *= 1.0 + 0.25 * smoothstep(0.6, 1.0, cos_i);
		}
		float f_under = max(smoothstep(foam_crest_start, foam_crest_full, jac), field_foam(v_rest, dist));
		col *= 1.0 - 0.45 * f_under;
		col = uw_apply(col, dist, I) + uw_shafts(cam, I, dist, FRAGCOORD.xy);
	}
	ALBEDO = col;
}
