shader_type spatial;
// Stylized ocean surface. Geometry comes from the shared Gerstner set in
// waves.gdshaderinc (identical to the CPU `Sea` autoload); everything else here
// is shading only and never adds height.
render_mode unshaded, cull_disabled, depth_draw_always, world_vertex_coords, shadows_disabled;

#include "res://src/ocean/waves.gdshaderinc"
#include "res://src/ocean/ocean_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
// R = foam lace erosion map, G = blotch noise, B = second lace map.
uniform sampler2D foam_tex : repeat_enable, filter_linear_mipmap_anisotropic;

group_uniforms water;
uniform vec3 deep_color : source_color = vec3(0.012, 0.16, 0.25);
uniform vec3 scatter_color : source_color = vec3(0.03, 0.50, 0.52);
uniform vec3 sss_color : source_color = vec3(0.10, 0.95, 0.70);
uniform vec3 absorption = vec3(0.42, 0.085, 0.07); // per metre
uniform float turbidity = 0.16;       // how fast the body colour builds with depth
uniform float refraction_strength = 0.35;
uniform float sss_strength = 1.0;
uniform float reflectivity = 1.0;
group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 0.96);
uniform float foam_crest_start = 0.80; // Jacobian below this starts to foam
uniform float foam_crest_full = 0.42;
uniform float foam_scale = 0.085;
uniform float shore_foam_depth = 0.9;
group_uniforms sun;
uniform float glint_sharpness = 900.0;
uniform float glint_strength = 6.0;
group_uniforms lod;
uniform float mesh_base_cell = 0.5;
uniform float mesh_cell_per_metre = 0.0278;
uniform float horizon_fade_start = 2500.0;
uniform float horizon_fade_end = 3900.0;
uniform float skirt_distance = 60000.0;

varying vec2 v_rest;
varying vec3 v_world;
varying float v_height;

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
	vec3 d = sea_displacement_lod(rest, cell * 2.5);
	VERTEX = vec3(rest.x, 0.0, rest.y) + d;
	v_rest = rest;
	v_world = VERTEX;
	v_height = d.y;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(VERTEX, 1.0));
	// Depth clamp: geometry past the far plane stays just inside it (reversed Z).
	POSITION.z = max(POSITION.z, POSITION.w * 2e-7);
}

float linear_depth(vec2 uv, mat4 inv_proj, out vec3 view_pos) {
	float raw = texture(depth_tex, uv).r;
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	view_pos = p.xyz / p.w;
	return -view_pos.z;
}

// Painterly foam: `amount` (0..1) erodes a lace pattern; edges stay crisp.
float foam_mask(float amount, vec2 uv, float soft) {
	float warp = texture(foam_tex, uv * 0.23 + vec2(0.11, 0.07)).g;
	vec2 w = (vec2(warp, texture(foam_tex, uv.yx * 0.19).g) - 0.5) * 0.35;
	float lace = texture(foam_tex, uv + w + vec2(0.006, -0.004) * sea_time).r;
	float lace2 = texture(foam_tex, uv * 2.7 - w + vec2(-0.011, 0.007) * sea_time).b;
	float pattern = mix(lace, lace2, 0.3);
	// amount = 1 covers everything, small amounts leave only the thinnest lace.
	float thr = 1.0 - amount * 1.15;
	return smoothstep(thr - soft, thr + soft, 1.0 - pattern) * smoothstep(0.0, 0.08, amount);
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 to_cam = cam - v_world;
	float dist = length(to_cam);
	vec3 V = to_cam / dist;
	float surf_z = -VERTEX.z;
	float storm = clamp((sea_amp_scale - 0.5) / 2.0, 0.0, 1.0);

	// --- surface normal and pinch, per pixel, filtered to the pixel footprint
	float fp_a = length(dFdx(v_rest));
	float fp_b = length(dFdy(v_rest));
	float fp = mix(min(fp_a, fp_b), max(fp_a, fp_b), 0.35);
	vec3 n_geo;
	float jac;
	float lost_var;
	sea_surface_lod(v_rest, sea_time, fp * 2.5, n_geo, jac, lost_var);

	// normal-only micro detail (three scrolling octaves of generated ripples)
	vec2 r1 = texture(detail_tex, v_rest * 0.110 + vec2(0.031, 0.017) * sea_time).rg;
	vec2 r2 = texture(detail_tex, v_rest.yx * 0.041 + vec2(-0.012, 0.019) * sea_time).rg;
	vec2 r3 = texture(detail_tex, v_rest * 0.0113 + vec2(0.004, -0.003) * sea_time).rg;
	vec2 ripple = (r1 - 0.5) * 0.9 + (r2 - 0.5) * 1.2 + (r3 - 0.5) * 1.0;
	float ripple_amt = mix(0.16, 0.42, storm);
	vec3 N = normalize(n_geo + vec3(ripple.x, 0.0, ripple.y) * ripple_amt);
	float rough_var = lost_var + 0.0006 + 0.0025 * storm;

	vec3 L = normalize(sun_dir);
	vec3 sun_light = ocean_sun_light();
	vec3 light = ambient_color * 0.65 + sun_light * (0.25 + 0.75 * clamp(L.y, 0.0, 1.0));

	// --- what lies behind the surface
	vec3 scene_view;
	float scene_z = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX, scene_view);
	float thick0 = max(scene_z - surf_z, 0.0) * dist / max(surf_z, 1e-4);

	vec3 col;
	float alpha_edge = 1.0;
	float foam = 0.0;

	if (FRONT_FACING) {
		// ---------------- seen from above ----------------
		// Refraction: nudge the lookup along the normal, reject samples in front.
		vec3 n_view = (VIEW_MATRIX * vec4(N, 0.0)).xyz;
		vec2 offs = n_view.xy * refraction_strength * clamp(thick0 * 0.6, 0.0, 1.0) / max(surf_z, 1.0);
		vec2 uv_r = clamp(SCREEN_UV - offs, vec2(0.001), vec2(0.999));
		vec3 rv;
		float rz = linear_depth(uv_r, INV_PROJECTION_MATRIX, rv);
		if (rz < surf_z + 0.02) {
			uv_r = SCREEN_UV;
			rv = scene_view;
			rz = scene_z;
		}
		float thick = max(rz - surf_z, 0.0) * dist / max(surf_z, 1e-4);
		vec3 scene_world = (INV_VIEW_MATRIX * vec4(rv, 1.0)).xyz;
		float vdepth = max(v_world.y - scene_world.y, 0.0);
		vec3 behind = texture(screen_tex, uv_r).rgb;

		// caustic light dancing on whatever is under shallow water
		float sun_up = max(L.y, 0.15);
		vec2 cq = scene_world.xz + L.xz * (vdepth / sun_up);
		float caus = ocean_caustic(cq) * exp(-vdepth * 0.22) * smoothstep(0.0, 0.5, vdepth);
		caus *= smoothstep(120.0, 30.0, dist);
		behind *= 1.0 + caus * 1.6 * smoothstep(0.0, 0.3, L.y) * (sun_light.g + 0.1);

		// crest mask: pinched and high water is thin, so light gets through
		float amp_ref = max(sea_amp_scale * 1.6, 0.3);
		float crest = clamp((1.0 - jac) * 1.6, 0.0, 1.0) * 0.6 + smoothstep(0.1, 1.0, v_height / amp_ref) * 0.6;
		crest = clamp(crest, 0.0, 1.0);
		float facing = 1.0 - max(dot(N, V), 0.0);
		float back_lit = pow(max(dot(V, -normalize(L + N * 0.35)), 0.0), 3.0);
		vec3 body = mix(deep_color, scatter_color, clamp(0.10 + 0.55 * crest + 0.30 * facing * facing, 0.0, 1.0)) * light;
		body += sss_color * sun_light * sss_strength * crest * (0.10 + 1.1 * back_lit) * (0.35 + 0.65 * facing);

		// depth-based absorption: shallows stay see-through and turquoise
		float path = thick + vdepth * 0.6;
		vec3 trans = exp(-absorption * path);
		float fill = 1.0 - exp(-turbidity * path);
		vec3 shallow_tint = scatter_color * light * 0.9;
		col = behind * trans + mix(shallow_tint, body, smoothstep(0.0, 9.0, path)) * fill;

		// --- reflection
		float ndv = max(dot(N, V), 0.0);
		// distant unresolved waves tilt towards the viewer: less mirror, more sky above
		float ndv_eff = clamp(ndv + sqrt(rough_var) * 0.9, 0.0, 1.0);
		float fres = 0.02 + 0.98 * pow(1.0 - ndv_eff, 5.0);
		vec3 R = reflect(-V, N);
		R.y = abs(R.y) + sqrt(rough_var) * 0.8;
		vec3 refl = ocean_sky(normalize(R));
		col = mix(col, refl, clamp(fres * reflectivity, 0.0, 1.0));

		// --- stylized sun glint: a crisp core plus a soft sheen, widened by roughness
		vec3 H = normalize(L + V);
		float ndh = max(dot(N, H), 0.0);
		float sharp = 1.0 / (1.0 / glint_sharpness + rough_var * 2.2);
		float core = pow(ndh, sharp);
		float glint = smoothstep(0.35, 0.75, core) * (glint_sharpness / (sharp + glint_sharpness)) * 2.0;
		glint += pow(ndh, sharp * 0.12) * 0.18;
		col += sun_light * glint * glint_strength * (0.2 + 0.8 * fres) * smoothstep(-0.02, 0.05, L.y);

		// --- foam: breaking crests (Jacobian) with a lagged copy for trails
		float lod_fade = smoothstep(0.9, 0.25, fp * 0.18);
		float f_now = smoothstep(foam_crest_start, foam_crest_full, jac);
		float j1 = sea_jacobian_lod(v_rest, sea_time - 1.1, max(fp * 2.5, 5.0));
		float j2 = sea_jacobian_lod(v_rest, sea_time - 2.6, max(fp * 2.5, 5.0));
		float f_trail = max(smoothstep(foam_crest_start, foam_crest_full, j1 + 0.03) * 0.62,
				smoothstep(foam_crest_start, foam_crest_full, j2 + 0.05) * 0.36);
		float crest_foam = max(f_now, f_trail);
		// wind streaks: a little standing foam in rough weather
		float blot = texture(foam_tex, v_rest * 0.013 + vec2(0.002, 0.001) * sea_time).g;
		crest_foam = max(crest_foam, storm * smoothstep(0.55, 0.95, blot) * 0.34 * smoothstep(-0.3, 0.6, v_height / amp_ref));

		// shoreline / intersection foam from the depth buffer
		vec3 sw0 = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
		float vd0 = max(v_world.y - sw0.y, 0.0);
		float shore = 1.0 - smoothstep(0.0, shore_foam_depth, vd0);
		float band = 0.5 + 0.5 * sin(vd0 * 9.0 / shore_foam_depth + sea_time * 1.6 + blot * 5.0);
		float shore_foam = shore * shore * (0.55 + 0.45 * band) + smoothstep(0.22, 0.0, vd0) * 0.6;
		shore_foam *= step(scene_z, surf_z + 60.0);

		vec2 fuv = v_rest * foam_scale;
		float soft = clamp(0.05 + fp * 0.6, 0.05, 0.5);
		foam = foam_mask(clamp(max(crest_foam, shore_foam), 0.0, 1.0), fuv, soft);
		// beyond pattern resolution, fall back to plain coverage
		foam = mix(clamp(max(crest_foam, shore_foam), 0.0, 1.0) * 0.55, foam, lod_fade);
		vec3 foam_lit = foam_color * (ambient_color * 0.85 + sun_light * (0.35 + 0.55 * clamp(dot(N, L), 0.0, 1.0)));
		// thin foam lets the water colour through: reads as paint, not as noise
		col = mix(col, foam_lit, foam * 0.92);

		alpha_edge = smoothstep(0.0, 0.10, thick0);
		col = mix(texture(screen_tex, SCREEN_UV).rgb, col, alpha_edge);

		// --- fade into the sky at the horizon
		float hf = smoothstep(horizon_fade_start, horizon_fade_end, dist);
		col = mix(col, sky_horizon_color, hf);
	} else {
		// ---------------- seen from below ----------------
		vec3 Nd = -N;
		vec3 I = -V;
		vec3 T = refract(I, Nd, 1.333);
		float cos_i = max(dot(V, Nd), 0.0);
		vec3 Rd = reflect(I, Nd);
		vec3 mirror = uw_ambient(normalize(vec3(Rd.x, -abs(Rd.y), Rd.z))) * 0.9;
		if (dot(T, T) < 1e-5) {
			col = mirror; // total internal reflection outside Snell's window
		} else {
			T = normalize(T);
			vec3 sky = ocean_sky(T);
			float sd = max(dot(T, L), 0.0);
			sky += ocean_sun_light() * (pow(sd, 350.0) * 14.0 + pow(sd, 24.0) * 0.9 + pow(sd, 4.0) * 0.25);
			// look the refracted ray up on screen so real sky and objects show
			vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(T, 0.0));
			vec2 suv = clip.xy / max(clip.w, 1e-4) * 0.5 + 0.5;
			vec2 edge = min(suv, 1.0 - suv);
			float on_screen = step(1e-4, clip.w) * smoothstep(0.0, 0.08, min(edge.x, edge.y));
			vec3 sv;
			float sz = linear_depth(clamp(suv, vec2(0.001), vec2(0.999)), INV_PROJECTION_MATRIX, sv);
			vec3 sw = (INV_VIEW_MATRIX * vec4(sv, 1.0)).xyz;
			on_screen *= step(-0.2, sw.y); // ignore things that are under water
			sky = mix(sky, texture(screen_tex, clamp(suv, vec2(0.001), vec2(0.999))).rgb, on_screen * 0.85);
			// Fresnel towards the rim of the window
			float fr = 0.02 + 0.98 * pow(1.0 - max(dot(T, N), 0.0), 5.0);
			col = mix(sky, mirror, clamp(fr, 0.0, 1.0));
			col *= 1.0 + 0.25 * smoothstep(0.6, 1.0, cos_i);
		}
		// foam seen from below reads as a darker, soft patch
		float f_now = smoothstep(foam_crest_start, foam_crest_full, jac);
		col *= 1.0 - 0.45 * f_now;
		col = uw_apply(col, dist, I);
	}
	ALBEDO = col;
}
