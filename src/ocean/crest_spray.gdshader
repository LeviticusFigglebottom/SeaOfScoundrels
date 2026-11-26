shader_type spatial;
// Breaking wave crest spray & wind-sheared backlit mist wisps for `Ocean` (CrestSpray).
// Horizontally stretched billboard quads broken up at high frequency by the ocean's
// frothy foam texture so puffs read as windswept spray fans & fine sparkling droplets,
// never round bokeh circles.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://src/sky/cloud_shadow.gdshaderinc"

global uniform vec3 sun_dir;
global uniform vec3 sun_color;
global uniform vec3 sky_horizon_color;
global uniform vec3 ambient_color;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D foam_tex : repeat_enable, filter_linear_mipmap;
uniform float storm_level = 0.0;

varying vec3 v_world_origin;
varying float v_age;
varying float v_seed;
varying float v_strength;
varying float v_mist_mix;

float spray_cloud_light(vec2 world_xz) {
	float cl = cloud_light(world_xz);
	if (cloud_shadow_params.w >= 0.999 && cl < 0.05) {
		return 1.0;
	}
	return clamp(cl, 0.0, 6.0);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sz = length(MODEL_MATRIX[0].xyz);
	v_world_origin = origin;
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = COLOR.r;
	v_strength = COLOR.g;
	v_mist_mix = COLOR.b;

	// Stretch horizontally (~2.1 x 0.85) with subtle wind tilt so spray reads as
	// wind-sheared horizontal fans rather than round puffs.
	float ang = (v_seed - 0.5) * 0.52 + v_age * (v_seed - 0.5) * 0.28;
	float ca = cos(ang);
	float sa = sin(ang);
	float sx = sz * 2.10;
	float sy = sz * 0.86;
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = INV_VIEW_MATRIX[2].xyz;
	vec3 rx = (cam_right * ca + cam_up * sa) * sx;
	vec3 ry = (-cam_right * sa + cam_up * ca) * sy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(rx, 0.0),
		vec4(ry, 0.0),
		vec4(cam_fwd * sz, 0.0),
		vec4(origin, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// Elliptical feathered mask wider along the horizon, slightly denser near crest base.
	vec2 q = (UV - 0.5) * 2.0;
	vec2 qe = vec2(q.x * 0.96, q.y * 1.10 + 0.08);
	float r2 = dot(qe, qe);
	if (r2 > 1.0) {
		discard;
	}

	float radial = smoothstep(1.0, 0.08, r2);
	float life_in = smoothstep(0.0, 0.12, v_age);
	float life_out = pow(1.0 - v_age, 1.55);
	float life_env = life_in * life_out;

	// High-frequency frothy droplet breakup + airy spindrift mist tail (never solid blobs).
	vec2 uv_hi = UV * vec2(4.4, 3.8) + vec2(v_seed * 5.3 + v_age * 0.32, v_seed * 8.7);
	vec2 uv_sp = UV * vec2(5.6, 4.8) - vec2(v_seed * 3.1, v_seed * 4.9 + v_age * 0.18);
	vec3 ft1 = texture(foam_tex, uv_hi).rgb;
	vec3 ft2 = texture(foam_tex, uv_sp).rgb;
	// Crisp tiny sparkling droplets (concentrated early in puff life)
	float speck1 = 1.0 - smoothstep(0.08, 0.42, ft1.b);
	float speck2 = 1.0 - smoothstep(0.10, 0.46, ft2.r);
	float droplets = speck1 * speck2 * 1.35 + speck1 * 0.42;
	// Airy low-opacity wind-torn mist tail (grows softer as puff disperses)
	float wisp = (1.0 - smoothstep(0.12, 0.72, ft1.r)) * ft1.g;
	float mist_tail = wisp * 0.65 + ft2.g * 0.18;
	float mist_w = clamp(v_mist_mix + v_age * 0.58, 0.0, 1.0);
	float shape = mix(droplets * 0.85 + mist_tail * 0.35, mist_tail * 0.78 + droplets * 0.25, mist_w);
	// Soft wind-fade along the upper/outer edges for irregular torn silhouettes
	float edge_break = smoothstep(0.14, 0.76, radial * (0.65 + 0.70 * ft1.g));
	float alpha = edge_break * radial * shape * life_env * v_strength;

	// Soft depth fade against ships, rocks and water; fade close to the camera lens.
	float raw_d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_d, 1.0);
	float scene_z = -upos.z / max(upos.w, 1e-5);
	float soft = clamp((scene_z + VERTEX.z) / 1.6, 0.0, 1.0);
	float near_fade = smoothstep(2.6, 8.0, -VERTEX.z);
	float far_fade = smoothstep(95.0, 48.0, -VERTEX.z);
	alpha *= soft * near_fade * far_fade;
	if (alpha < 0.005) {
		discard;
	}

	// Lighting: backlit warm golden-white spray droplets against sky, cool mist in shadow/night.
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_origin);
	vec3 L = normalize(sun_dir);
	float cl = spray_cloud_light(v_world_origin.xz);
	vec3 sun_l = sun_color * smoothstep(-0.06, 0.25, L.y) * cl;
	float backlit = pow(max(dot(V, -L), 0.0), 3.0);
	float sun_side = 0.45 + 0.55 * max(dot(normalize(vec3(q.x, q.y, 0.6)), L), 0.0);

	vec3 base_tint = mix(vec3(0.94, 0.99, 0.98), vec3(0.82, 0.88, 0.87), storm_level * 0.6);
	vec3 col = base_tint * (ambient_color * 0.90 + sun_l * (0.48 + 0.45 * sun_side));
	vec3 warm_rim = sun_l * vec3(1.20, 1.08, 0.90) * (0.55 + 1.45 * backlit);
	col += warm_rim * (0.25 + 0.65 * clamp(droplets, 0.0, 1.0)) * smoothstep(0.02, 0.25, L.y);
	float dist = length(CAMERA_POSITION_WORLD - v_world_origin);
	col = mix(col, sky_horizon_color * 1.04, smoothstep(38.0, 95.0, dist) * 0.35);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.62);
}
