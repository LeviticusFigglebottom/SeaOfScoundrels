shader_type spatial;
// Stylized wind-sway foliage shader for tropical palm fronds and coastal ferns.
// Reads UV2 bend weight (x: 0 at crown/stem .. 1 at tip) and per-frond random
// phase (y: 0..1) baked by tools/blender/gen_props.py, with height fallback.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 sun_dir;
global uniform vec3 sun_color;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float use_albedo_tex = 1.0;
uniform vec3 albedo_tint : source_color = vec3(1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.62;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.34;

uniform vec2 wind_dir = vec2(0.7, -0.7);
uniform float wind_speed = 6.5;
uniform float sway_strength : hint_range(0.0, 2.5) = 1.0;
uniform float use_uv2_weight = 1.0;
uniform float fallback_height = 8.0;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_tip_weight;

void vertex() {
	float w = use_uv2_weight > 0.5
		? clamp(UV2.x, 0.0, 1.0)
		: clamp(VERTEX.y / max(fallback_height, 0.25), 0.0, 1.0);
	float frond_phase = UV2.y * 6.2831853;

	vec3 node_pos = NODE_POSITION_WORLD;
	float tree_phase = dot(node_pos.xz, vec2(0.17, 0.23));
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
}

void fragment() {
	vec3 tex_col = use_albedo_tex > 0.5 ? texture(albedo_tex, UV).rgb : vec3(1.0);
	vec3 base_col = tex_col * COLOR.rgb * albedo_tint;
	ALBEDO = base_col;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	SPECULAR = 0.18;

	// Subtle warm lime-gold subsurface glow when sunlight shines through palm fronds.
	vec3 n_w = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	float back_lit = clamp(-dot(n_w, normalize(sun_dir)) * 0.65 + 0.35, 0.0, 1.0);
	float sun_sh = cloud_shadow(v_world.xz);
	EMISSION = base_col * vec3(1.05, 1.15, 0.55) * sun_color * (back_lit * sss_strength * (0.4 + 0.6 * v_tip_weight) * sun_sh * 0.25);
}

void light() {
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(v_world.xz) : 1.0;
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + 0.28) / 1.28, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR * sun / PI;
	vec3 h_vec = normalize(VIEW + LIGHT);
	float spec = pow(clamp(dot(NORMAL, h_vec), 0.0, 1.0), 22.0) * 0.12;
	SPECULAR_LIGHT += spec * clamp(ndl, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR * sun;
}
