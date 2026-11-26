shader_type spatial;
// Stylized wind-sway foliage shader for tropical palm fronds and coastal ferns.
// Reads UV2 bend weight (x: 0 at crown/stem .. 1 at tip) and per-frond random
// phase (y: 0..1) baked by tools/blender/gen_props.py, with height fallback.
// Enriched with warm-gold-to-deep-jade painterly tip gradients, view-dependent
// translucent palm-frond subsurface backlight, and cool coastal sky bounce fill.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 sun_dir;
global uniform vec3 sun_color;
global uniform vec3 ambient_color;
global uniform vec3 sky_horizon_color;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float use_albedo_tex = 1.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform float use_normal_tex = 0.0;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.85;
uniform sampler2D roughness_tex : hint_roughness_g, filter_linear_mipmap_anisotropic;
uniform float use_roughness_tex = 0.0;
uniform vec3 albedo_tint : source_color = vec3(1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.56;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.46;

uniform vec2 wind_dir = vec2(0.7, -0.7);
uniform float wind_speed = 6.5;
uniform float sway_strength : hint_range(0.0, 2.5) = 1.0;
uniform float use_uv2_weight = 1.0;
uniform float fallback_height = 8.0;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_tip_weight;
varying float v_frond_var;
varying float v_cam_dist;

float foliage_hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float foliage_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = foliage_hash31(i);
	float n100 = foliage_hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = foliage_hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = foliage_hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = foliage_hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = foliage_hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = foliage_hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = foliage_hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

void vertex() {
	float w = use_uv2_weight > 0.5
		? clamp(UV2.x, 0.0, 1.0)
		: clamp(VERTEX.y / max(fallback_height, 0.25), 0.0, 1.0);
	float frond_phase = UV2.y * 6.2831853;

	// Use MODEL_MATRIX[3].xyz instead of NODE_POSITION_WORLD so batched Wave 24
	// MultiMeshInstance3D jungle canopies sway in organic rolling waves per tree!
	vec3 inst_pos = MODEL_MATRIX[3].xyz;
	float tree_phase = dot(inst_pos.xz, vec2(0.17, 0.23));
	float ws = clamp(wind_speed / 10.0, 0.15, 2.4);

	// Slow rolling trade-wind gust + faster organic tip flutter.
	float gust_t = TIME * (1.15 + ws * 0.65) + tree_phase;
	float gust = sin(gust_t) * 0.65 + sin(gust_t * 2.13 + 1.4) * 0.35;
	float flutter_t = TIME * (3.1 + ws * 1.9) + frond_phase + tree_phase * 0.5;
	float flutter = sin(flutter_t + VERTEX.x * 1.2 + VERTEX.z * 1.2);

	vec2 wd = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(0.707, -0.707);
	vec3 world_wind = vec3(wd.x, 0.0, wd.y);
	// Convert world wind direction into mesh-local horizontal space.
	vec3 local_wind = normalize((transpose(mat3(MODEL_MATRIX)) * world_wind) + vec3(1e-5, 0.0, 0.0));

	float bend = (0.14 + 0.24 * ws) * sway_strength * w * w;
	vec3 disp = local_wind * (0.35 + 0.65 * gust) * bend;
	disp.y += (-0.18 * abs(gust) + 0.22 * flutter) * bend;
	disp += cross(vec3(0.0, 1.0, 0.0), local_wind) * flutter * (0.07 * ws * sway_strength * w);

	VERTEX += disp;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_tip_weight = w;
	v_frond_var = fract(UV2.y + sin(tree_phase) * 0.37);
	v_cam_dist = length(CAMERA_POSITION_WORLD - v_world);
}

void fragment() {
	vec3 tex_col = use_albedo_tex > 0.5 ? texture(albedo_tex, UV).rgb : vec3(1.0);
	vec3 base_col = tex_col * COLOR.rgb * albedo_tint;

	// Detect green foliage vs vivid hibiscus/floral petals so blossoms stay pure saturated coral/gold!
	float is_leaf = smoothstep(-0.02, 0.08, base_col.g - max(base_col.r, base_col.b) * 0.78);
	float near_foliage = smoothstep(85.0, 10.0, v_cam_dist);

	// Procedural pinnate frond midrib, angled leaflet veins & world-space overlapping leaf-cluster breakup.
	float u_ctr = abs(UV.x * 2.0 - 1.0);
	float midrib = exp(-u_ctr * 14.0);
	float vein_phase = (UV.y * 26.0 - u_ctr * 10.5) * PI;
	float vein_wave = sin(vein_phase);
	float vein_ridge = smoothstep(-0.2, 0.85, vein_wave);
	float fine_fiber = sin(UV.x * 22.0 * PI) * 0.5 + 0.5;
	float cluster_n = foliage_noise3(v_world * 2.55) * 0.64 + foliage_noise3(v_world * 6.20) * 0.36;
	float cluster_dapple = smoothstep(0.22, 0.82, cluster_n);

	// Deep cool emerald-teal canopy interior self-AO + ground-root contact darkening -> warm sunlit tips.
	// On untextured MultiMesh ground flora (grass/ferns), blend world normal gently skyward (BOTW/SoT
	// painterly turf smoothing) and anchor roots cleanly into earth shadow so clumps never read as flat polygons!
	float is_ground_flora = (1.0 - step(0.5, use_albedo_tex)) * is_leaf;
	vec3 n_w_raw = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 n_w = normalize(mix(n_w_raw, normalize(n_w_raw + vec3(0.0, 0.72, 0.0)), is_ground_flora * 0.42));
	float up_ao = mix(0.64, 1.08, smoothstep(-0.40, 0.72, n_w.y));
	float crown_ao = mix(mix(0.60, 0.54, is_ground_flora), 1.08, smoothstep(0.03, 0.82, v_tip_weight));
	// Soft macro meadow-patch harmony so ground flora blends organically into Pass Q3A turf underneath.
	float meadow_patch = foliage_noise3(vec3(v_world.xz * 0.24, 1.7));
	float canopy_ao = mix(1.0, clamp(up_ao * crown_ao * mix(0.78, 1.18, cluster_dapple) * mix(1.0, mix(0.86, 1.12, meadow_patch), is_ground_flora), 0.36, 1.22), is_leaf);

	// Painterly tropical frond gradient: rich deep jade shadow core -> sunlit golden-lime outer leaflets.
	vec3 jade_base = mix(vec3(0.56, 0.82, 0.72), vec3(0.48, 0.74, 0.56), is_ground_flora);
	vec3 gold_tip = vec3(1.24, 1.18, 0.70);
	vec3 grad_tint = mix(vec3(1.0), mix(jade_base, gold_tip, smoothstep(0.06, 0.90, v_tip_weight)), is_leaf);
	// Per-frond hue shift + sunlit leaf-cluster & subtle pinnate-vein contrast breakup (zero corduroy striping!).
	vec3 frond_shift = mix(vec3(0.88, 0.98, 0.96), vec3(1.12, 1.05, 0.84), v_frond_var);
	vec3 leaf_col = base_col * grad_tint * mix(vec3(1.0), frond_shift, is_leaf) * canopy_ao;

	// Highlight central frond spine & natural pinnate ribs (gentle on close blades, bolder on palm/banyan canopies).
	float vein_shade = mix(0.91, 1.09, vein_ridge * 0.72 + fine_fiber * 0.28);
	leaf_col *= mix(1.0, mix(1.0, vein_shade, mix(0.44, 0.56, is_ground_flora) * near_foliage), is_leaf);
	leaf_col = mix(leaf_col, leaf_col * vec3(1.16, 1.20, 0.78), midrib * mix(0.28, 0.34, is_ground_flora) * is_leaf * near_foliage);

	ALBEDO = leaf_col;
	float base_rough = use_roughness_tex > 0.5 ? texture(roughness_tex, UV).g : roughness_val;
	float waxy_tip = mix(base_rough + 0.14, max(base_rough - 0.14, 0.30), v_tip_weight);
	float vein_rough = mix(0.08, -0.08, vein_ridge * 0.65 + cluster_dapple * 0.35) * is_leaf * near_foliage;
	ROUGHNESS = clamp(waxy_tip + vein_rough + is_ground_flora * 0.08, 0.24, 0.96);

	if (use_normal_tex > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale * 1.22;
	} else if (near_foliage > 0.02) {
		// Analytical cylindrical blade curvature, central keel & pinnate leaflet micro-normal relief
		// for untextured MultiMesh foliage (eliminates harsh flat-triangle facets on 2.2 m closeups!).
		vec3 f_t = normalize(cross(abs(n_w.y) < 0.92 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0), n_w));
		vec3 f_b = cross(n_w, f_t);
		float u_signed = UV.x * 2.0 - 1.0;
		float blade_curve = u_signed * (0.28 * is_ground_flora);
		float d_vein = cos(vein_phase) * 0.20 + (cluster_n - 0.5) * 0.30;
		float d_rib = u_signed * midrib * 0.34;
		vec3 n_pert = normalize(n_w + (f_t * (d_vein + d_rib + blade_curve) + f_b * (d_vein * 0.68)) * (near_foliage * is_leaf));
		NORMAL = normalize((VIEW_MATRIX * vec4(n_pert, 0.0)).xyz);
	} else if (is_ground_flora > 0.05) {
		NORMAL = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);
	}
	METALLIC = 0.0;
	SPECULAR = mix(0.28, 0.36, v_tip_weight * is_leaf);

	// Translucent sunlit palm-frond subsurface backlight (veined forward scatter + thin golden-lime rim!).
	vec3 s_dir = normalize(sun_dir);
	vec3 view_w = normalize(CAMERA_POSITION_WORLD - v_world);
	float forward_scatter = pow(clamp(dot(-view_w, s_dir), 0.0, 1.0), 2.6);
	float rim_back = pow(1.0 - abs(dot(n_w, view_w)), 2.2) * clamp(dot(view_w, -s_dir) * 0.5 + 0.5, 0.0, 1.0);
	float back_lit = clamp(-dot(n_w, s_dir) * 0.55 + 0.45, 0.0, 1.0);
	float sun_sh = cloud_light(v_world.xz);
	float thinness = (0.30 + 0.70 * smoothstep(0.08, 0.92, v_tip_weight)) * mix(0.82, 1.24, vein_ridge * 0.55 + cluster_dapple * 0.45);
	float day_gate = smoothstep(0.02, 0.18, s_dir.y);
	float sss_factor = (back_lit * 0.46 + forward_scatter * 1.15 + rim_back * 0.55) * sss_strength * thinness * sun_sh * day_gate;
	vec3 sss_tint = mix(vec3(1.22, 0.92, 0.72), vec3(1.24, 1.32, 0.46), is_leaf);
	EMISSION = leaf_col * sss_tint * sun_color * (sss_factor * 0.44);
}

void light() {
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(v_world.xz) : 1.0;
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + 0.32) / 1.32, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR * sun / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		// Rich cool turquoise-sky bounce fill on shaded underside of tropical palm & banyan canopies.
		float under = smoothstep(0.16, -0.48, ndl);
		vec3 sky_fill = mix(ambient_color, sky_horizon_color * vec3(0.54, 0.86, 1.08), 0.58);
		DIFFUSE_LIGHT += under * sky_fill * (0.20 * clamp(sun, 0.35, 1.1)) / PI;
	}
	vec3 h_vec = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h_vec), 0.0, 1.0);
	float spec_pow = mix(18.0, 48.0, 1.0 - ROUGHNESS);
	float spec_amp = mix(0.10, 0.28, 1.0 - ROUGHNESS);
	SPECULAR_LIGHT += pow(ndh, spec_pow) * spec_amp * clamp(ndl, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR * sun;
}
