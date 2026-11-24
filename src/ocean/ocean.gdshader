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
uniform vec3 deep_color : source_color = vec3(0.0, 0.20, 0.34);
uniform vec3 scatter_color : source_color = vec3(0.0, 0.58, 0.60);
uniform vec3 sss_color : source_color = vec3(0.16, 0.95, 0.72);
uniform vec3 absorption = vec3(0.42, 0.085, 0.07); // per metre
uniform float turbidity = 0.12;       // how fast the body colour builds with depth
uniform float refraction_strength = 0.35;
uniform float sss_strength = 1.0;
uniform float reflectivity = 0.75;
group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 0.96);
uniform float foam_crest_start = 0.87; // Jacobian below this starts to foam
uniform float foam_crest_full = 0.46;
uniform float foam_scale = 0.085;
uniform float shore_foam_depth = 1.3;
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
	vec3 d = sea_displacement_lod(rest, cell * 3.0);
	VERTEX = vec3(rest.x, 0.0, rest.y) + d;
	v_rest = rest;
	v_world = VERTEX;
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
	float lace_big = texture(foam_tex, uv.yx * 0.29 + w * 0.5 + vec2(-0.003, 0.002) * sea_time).r;
	float lace2 = texture(foam_tex, uv * 2.7 - w + vec2(-0.011, 0.007) * sea_time).b;
	// big torn patches, medium bubbles inside them, a little fine break-up
	float pattern = lace * 0.45 + lace_big * 0.40 + lace2 * 0.15;
	pattern = smoothstep(0.12, 0.88, pattern);
	// amount = 1 covers everything, small amounts leave only the thinnest lace.
	float thr = 1.0 - amount;
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
	// Footprint of a pixel on the water, metres. Analytic (distance and grazing
	// angle) rather than from derivatives, which are constant per triangle and
	// would print the mesh into the shading.
	float px_angle = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float fp_across = dist * px_angle;
	float fp = fp_across * mix(1.0, 1.0 / max(abs(V.y), 0.04), 0.35);
	vec3 n_geo;
	float jac;
	float lost_var;
	float wave_h; // analytic, so colour masks do not show the mesh
	sea_surface_lod(v_rest, sea_time, fp * 2.5, n_geo, jac, lost_var, wave_h);

	// normal-only micro detail (three scrolling octaves of generated ripples)
	vec2 r1 = texture(detail_tex, v_rest * 0.110 + vec2(0.031, 0.017) * sea_time).rg;
	vec2 r2 = texture(detail_tex, v_rest.yx * 0.041 + vec2(-0.012, 0.019) * sea_time).rg;
	vec2 r3 = texture(detail_tex, v_rest * 0.0113 + vec2(0.004, -0.003) * sea_time).rg;
	float fine = smoothstep(0.35, 0.03, fp);
	vec2 rip_fine = (r1 - 0.5) * fine;
	vec2 ripple = rip_fine * 0.8 + (r2 - 0.5) * 1.2 * smoothstep(1.2, 0.1, fp) + (r3 - 0.5) * 0.7 * smoothstep(5.0, 0.5, fp);
	// wind patches: gusts roughen the water in slow-moving blotches
	float gust = texture(foam_tex, v_rest * 0.0037 + vec2(0.0011, 0.0007) * sea_time).g;
	gust = smoothstep(0.2, 0.8, gust);
	float ripple_amt = mix(0.14, 0.27, storm) * mix(0.45, 1.5, gust);
	// calm seas get their swell slopes exaggerated for shading only, so long
	// low waves still read as forms (no height is added)
	float exag = mix(1.8, 1.0, smoothstep(0.0, 0.6, storm));
	vec3 n_shade = normalize(vec3(n_geo.x * exag, n_geo.y, n_geo.z * exag));
	vec3 N = normalize(n_shade + vec3(ripple.x, 0.0, ripple.y) * ripple_amt);
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

	// The sea is a height field: its underside is only ever visible to a camera
	// that is under water. Facing only decides while the lens straddles the
	// surface (edge-on slivers at the horizon must not flip).
	bool underside = uw_cam_depth > 0.15 || (uw_cam_depth > -0.15 && !FRONT_FACING);
	if (!underside) {
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
		// anything seen through water reads a little darker and richer straight away
		behind *= 0.68 + 0.32 * exp(-thick * 4.0);

		// crest mask: pinched and high water is thin, so light gets through
		float amp_ref = max(sea_amp_scale * 2.3, 0.3);
		float h_rel = wave_h / amp_ref;
		float crest = clamp((1.0 - jac) * 1.8, 0.0, 1.0) * 0.55 + smoothstep(0.15, 1.1, h_rel) * 0.65;
		crest = clamp(crest, 0.0, 1.0);
		float facing = 1.0 - max(dot(N, V), 0.0);
		float back_lit = pow(max(dot(V, -normalize(L + N * 0.35)), 0.0), 3.0);
		// slopes turned to the light are brighter, troughs sink into the deep colour
		float slope_light = dot(n_shade, normalize(L + vec3(0.0, 0.6, 0.0)));
		float k = 0.08 + 0.34 * smoothstep(-0.9, 1.1, h_rel) + 0.30 * crest + 0.25 * facing * facing;
		k *= mix(1.0, 0.15, smoothstep(100.0, 1200.0, dist));
		vec3 body = mix(deep_color, scatter_color, clamp(k, 0.0, 1.0)) * light * mix(0.55, 1.25, smoothstep(0.78, 1.0, slope_light));
		// translucent crests: a steady glow, much stronger when the sun is behind the wave
		float thin = clamp(crest + 0.6 * smoothstep(-0.3, 0.7, h_rel) * back_lit, 0.0, 1.0);
		body += sss_color * sss_strength * (crest * light * 0.40 + thin * sun_light * 1.9 * back_lit) * (0.35 + 0.65 * facing);

		// depth-based absorption: shallows stay see-through and turquoise
		// mostly vertical depth, so shallows stay clear even at grazing view angles
		float path = vdepth * 1.5 + min(thick, 10.0) * 0.12;
		vec3 trans = exp(-(absorption + turbidity) * path);
		float fill = 1.0 - exp(-turbidity * path);
		vec3 shallow_tint = scatter_color * light * 0.55;
		col = behind * trans + mix(shallow_tint, body, smoothstep(0.0, 9.0, path)) * fill;

		// --- reflection
		float ndv = max(dot(N, V), 0.0);
		// distant unresolved waves tilt towards the viewer: less mirror, more sky above
		float ndv_eff = clamp(ndv + sqrt(rough_var) * 0.9, 0.0, 1.0);
		float fres = 0.02 + 0.98 * pow(1.0 - ndv_eff, 5.0);
		vec3 R = reflect(-V, N);
		R.y = abs(R.y) + sqrt(rough_var) * 0.8;
		R = normalize(R);
		vec3 refl = ocean_sky(R);
		// the glow around the sun also reflects: a warm path at low sun
		float rs = max(dot(R, L), 0.0);
		refl += sun_light * (pow(rs, 10.0) * 0.30 + pow(rs, 80.0) * 0.6);
		col = mix(col, refl, clamp(fres * reflectivity, 0.0, 1.0));

		// --- stylized sun glint: a crisp core plus a soft sheen, widened by roughness
		vec3 H = normalize(L + V);
		// sparkle normal: extra fine ripples so the glint breaks into glitter
		vec3 n_spark = normalize(N + vec3(rip_fine.x, 0.0, rip_fine.y) * 1.1 + vec3(r2.x - 0.5, 0.0, r2.y - 0.5) * 0.5);
		float ndh = max(dot(n_spark, H), 0.0);
		float sharp = 1.0 / (1.0 / glint_sharpness + rough_var * 2.2);
		float core = pow(ndh, sharp);
		float glint = smoothstep(0.30, 0.60, core) * (glint_sharpness / (sharp + glint_sharpness)) * 2.0;
		glint += pow(max(dot(N, H), 0.0), sharp * 0.2) * 0.05;
		col += sun_light * glint * glint_strength * (0.2 + 0.8 * fres) * smoothstep(-0.02, 0.05, L.y);

		// --- foam: breaking crests (Jacobian) with a lagged copy for trails
		float lod_fade = smoothstep(0.9, 0.25, fp * 0.18);
		float f_now = smoothstep(foam_crest_start, foam_crest_full, jac);
		float j1 = sea_jacobian_lod(v_rest, sea_time - 1.1, max(fp * 2.5, 5.0));
		float j2 = sea_jacobian_lod(v_rest, sea_time - 2.6, max(fp * 2.5, 5.0));
		float f_trail = max(smoothstep(foam_crest_start, foam_crest_full, j1 + 0.02) * 0.60,
				smoothstep(foam_crest_start, foam_crest_full, j2 + 0.04) * 0.36);
		float crest_foam = max(f_now, f_trail);
		// wind streaks: a little standing foam in rough weather
		float blot = texture(foam_tex, v_rest * 0.013 + vec2(0.002, 0.001) * sea_time).g;
		crest_foam = max(crest_foam, storm * smoothstep(0.45, 0.95, blot) * 0.42 * smoothstep(-0.5, 0.5, wave_h / amp_ref));

		// shoreline / intersection foam from the depth buffer
		vec3 sw0 = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
		float vd0 = max(v_world.y - sw0.y, 0.0);
		// Beaches get a wide wash; steep things (rocks, hulls, crates) only a
		// thin lip. Steepness comes from the depth buffer's own slope.
		vec3 scene_n = normalize(cross(dFdy(sw0), dFdx(sw0)));
		float flatness = smoothstep(0.55, 0.95, abs(scene_n.y));
		float foam_depth = shore_foam_depth * mix(0.12, 1.0, flatness);
		float shore = 1.0 - smoothstep(0.0, foam_depth, vd0);
		// wash lines sweeping in towards the beach, plus a solid lip at contact
		float band = 0.5 + 0.5 * sin(vd0 * 11.0 / foam_depth + sea_time * 1.3 + blot * 6.0);
		float shore_foam = shore * (0.25 + 0.75 * band * band) * 0.9 + smoothstep(0.10, 0.0, vd0) * 0.7;
		shore_foam *= step(scene_z, surf_z + 60.0);

		vec2 fuv = v_rest * foam_scale;
		float soft = clamp(0.05 + fp * 0.6, 0.05, 0.5);
		foam = foam_mask(clamp(max(crest_foam, shore_foam), 0.0, 1.0), fuv, soft);
		// beyond pattern resolution, fall back to plain coverage
		float plain = clamp(max(crest_foam, shore_foam), 0.0, 1.0);
		foam = mix(plain * plain * 0.6, foam, lod_fade);
		vec3 foam_lit = foam_color * (ambient_color * 0.85 + sun_light * (0.35 + 0.55 * clamp(dot(N, L), 0.0, 1.0)));
		// thin foam lets the water colour through: reads as paint, not as noise
		col = mix(col, foam_lit, foam * 0.92);

		alpha_edge = smoothstep(0.0, 0.06, thick0);
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
		// the mirror outside Snell's window: reflects the deep, shaded by the waves
		vec3 mirror = uw_ambient(normalize(vec3(Rd.x, -abs(Rd.y), Rd.z))) * (0.55 + 1.6 * pow(1.0 - abs(Rd.y), 3.0));
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
		col = uw_apply(col, dist, I) + uw_shafts(cam, I, dist, FRAGCOORD.xy);
	}
	ALBEDO = col;
}
