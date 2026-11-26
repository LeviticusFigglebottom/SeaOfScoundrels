shader_type spatial;
// Stylized swaying underwater kelp & seagrass ribbon shader for Sea of Scoundrels.
// Compatible with MultiMeshInstance3D per-instance COLOR tinting & Godot 4.8 Forward+.
// Keeps holdfast roots planted firmly on the seabed while undulating multi-blade fronds
// in coherent world-space underwater surge with backlit emerald-gold translucency.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 sun_dir;
global uniform vec3 sun_color;
global uniform vec3 ambient_color;

uniform vec3 root_tint : source_color = vec3(0.09, 0.24, 0.20);
uniform vec3 tip_sun_shift : source_color = vec3(1.18, 1.16, 0.72);
uniform vec3 sss_tint : source_color = vec3(0.46, 0.98, 0.54);
uniform float sway_speed : hint_range(0.2, 4.0) = 1.35;
uniform float sway_amplitude : hint_range(0.0, 0.8) = 0.24;
uniform float ripple_amplitude : hint_range(0.0, 0.5) = 0.09;
uniform float reference_height : hint_range(0.5, 5.0) = 2.2;
uniform float roughness_val : hint_range(0.1, 1.0) = 0.54;
uniform float sss_strength : hint_range(0.0, 1.5) = 0.62;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_tip;
varying float v_blade_u;

vec3 srgb_to_linear(vec3 c) {
	vec3 cl = max(c, vec3(0.0));
	vec3 lo = cl / 12.92;
	vec3 hi = pow((cl + 0.055) / 1.055, vec3(2.4));
	return mix(lo, hi, step(vec3(0.04045), cl));
}

void vertex() {
	// Per-instance world XZ root drives coherent rolling ocean surge across the reef.
	vec2 inst_xz = MODEL_MATRIX[3].xz;
	float world_phase = dot(inst_xz, vec2(0.19, 0.23)) + sin(inst_xz.x * 0.055 - inst_xz.y * 0.048) * 2.2;
	float blade_phase = UV2.x * 6.2831853;

	// UV.y = 1.0 at seabed root -> 0.0 at frond tip; fallback guards against zero-height holdfasts.
	float uv_h = clamp(1.0 - UV.y, 0.0, 1.0);
	float vert_h = clamp(VERTEX.y / max(reference_height, 0.25), 0.0, 1.35);
	float root_lock = smoothstep(0.02, 0.14, VERTEX.y);
	float tip_w = pow(uv_h, 1.5) * root_lock;
	float height_gain = mix(0.45, 1.20, clamp(vert_h, 0.0, 1.0));

	// Primary slow ocean surge traveling across the shallow seabed shelf.
	float t_surge = TIME * sway_speed + world_phase;
	float surge_x = sin(t_surge - uv_h * 2.35) * 0.68 + sin(t_surge * 1.61 + 1.15 - uv_h * 3.05) * 0.32;
	float surge_z = cos(t_surge * 0.87 + 0.72 - uv_h * 2.05) * 0.66 + sin(t_surge * 1.39 + 2.35 - uv_h * 2.75) * 0.34;

	// Convert world surge into instance-local space (scale-invariant orthonormal basis)
	// so randomly rotated tufts still bow together with the passing underwater swell.
	vec3 col0 = normalize(MODEL_MATRIX[0].xyz + vec3(1e-5, 0.0, 0.0));
	vec3 col1 = normalize(MODEL_MATRIX[1].xyz + vec3(0.0, 1e-5, 0.0));
	vec3 col2 = normalize(MODEL_MATRIX[2].xyz + vec3(0.0, 0.0, 1e-5));
	mat3 world_to_local = transpose(mat3(col0, col1, col2));
	vec3 local_surge = world_to_local * vec3(surge_x * sway_amplitude, 0.0, surge_z * sway_amplitude);

	// Secondary delicate per-blade S-wave ripple dancing along each kelp ribbon.
	float t_rip = TIME * (sway_speed * 2.10) + blade_phase + world_phase * 0.5;
	vec3 local_ripple = vec3(
		sin(t_rip - uv_h * 4.6) * ripple_amplitude,
		0.0,
		cos(t_rip * 1.13 + 0.85 - uv_h * 4.1) * ripple_amplitude
	);

	vec3 disp = (local_surge + local_ripple) * tip_w * height_gain;
	// Subtle arc-length vertical dip so tall blades bow naturally instead of stretching.
	disp.y -= dot(disp.xz, disp.xz) * 0.22 * root_lock;

	VERTEX += disp;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_tip = uv_h;
	v_blade_u = UV.x;
}

void fragment() {
	// MultiMesh per-instance color * mesh vertex shading gradient, converted sRGB -> linear.
	vec3 inst_lin = srgb_to_linear(COLOR.rgb);

	// Subtle painterly depth: grounded emerald-teal root -> sunlit golden-jade blade tips,
	// with a slightly richer central midrib vein and luminous ruffled blade margins.
	float midrib = exp(-pow((v_blade_u - 0.5) * 4.8, 2.0));
	vec3 base_col = mix(root_tint, inst_lin, smoothstep(0.0, 0.24, v_tip));
	base_col *= mix(vec3(0.92, 0.96, 0.98), tip_sun_shift, smoothstep(0.28, 0.96, v_tip));
	base_col *= mix(1.05, 0.86, midrib * (1.0 - v_tip * 0.45));

	ALBEDO = base_col;
	ROUGHNESS = mix(roughness_val + 0.14, roughness_val, smoothstep(0.05, 0.65, v_tip));
	METALLIC = 0.0;
	SPECULAR = 0.22;

	// Translucent backlit emerald-gold subsurface glow driven by sun_dir & cloud shadows.
	vec3 n_w = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 l_dir = normalize(sun_dir);
	vec3 v_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float sun_sh = cloud_shadow(v_world.xz);
	float depth_atten = exp(-max(-v_world.y, 0.0) * 0.12);
	float sun_up = smoothstep(-0.04, 0.24, l_dir.y);

	float view_back = pow(clamp(dot(v_dir, -l_dir), 0.0, 1.0), 2.8);
	float thin_lit = clamp(-dot(n_w, l_dir) * 0.55 + 0.45, 0.0, 1.0);
	float margin_glow = mix(0.68, 1.24, abs(v_blade_u - 0.5) * 2.0);
	float sss_factor = (0.36 * thin_lit + 0.72 * view_back) * (0.25 + 0.75 * v_tip) * margin_glow;
	EMISSION = base_col * sss_tint * sun_color * (sss_factor * sss_strength * sun_sh * depth_atten * sun_up * 0.44);
}

void light() {
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(v_world.xz) : 1.0;
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + 0.36) / 1.36, 0.0, 1.0);
	// Soft double-sided light transmission through thin submerged kelp fronds.
	float back_wrap = clamp(-ndl, 0.0, 1.0) * 0.28 * (0.30 + 0.70 * v_tip);
	DIFFUSE_LIGHT += (wrapped + back_wrap) * ATTENUATION * LIGHT_COLOR * sun / PI;

	if (LIGHT_IS_DIRECTIONAL) {
		// Gentle cool underwater sky bounce so night & shadow sides stay readable teal-blue.
		float shadow_side = smoothstep(0.25, -0.45, ndl);
		DIFFUSE_LIGHT += shadow_side * ambient_color * vec3(0.45, 0.78, 0.85) * 0.14 / PI;
	}

	vec3 h_vec = normalize(VIEW + LIGHT);
	float spec = pow(clamp(dot(NORMAL, h_vec), 0.0, 1.0), 20.0) * 0.14;
	SPECULAR_LIGHT += spec * clamp(ndl, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR * sun;
}
