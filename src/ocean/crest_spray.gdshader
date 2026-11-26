shader_type spatial;
// Breaking wave crest spray & backlit mist puffs for `Ocean` (CrestSpray).
// Billboarded quads using the ocean's procedural Voronoi foam texture for
// organic wispy droplet bursts, warm backlit sun glow, per-pixel cloud
// shadows, and soft depth fade against ships & rocks.
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

	// Rotate each spray puff uniquely in screen space so no two puffs repeat.
	float ang = v_seed * TAU + v_age * (v_seed - 0.5) * 1.1;
	float ca = cos(ang);
	float sa = sin(ang);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_fwd = INV_VIEW_MATRIX[2].xyz;
	vec3 rx = (cam_right * ca + cam_up * sa) * sz;
	vec3 ry = (-cam_right * sa + cam_up * ca) * sz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(rx, 0.0),
		vec4(ry, 0.0),
		vec4(cam_fwd * sz, 0.0),
		vec4(origin, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r2 = dot(q, q);
	if (r2 > 1.0) {
		discard;
	}

	// Soft radial envelope, slightly fuller near the crest base and feathered at the top.
	float radial = smoothstep(1.0, 0.04, r2);
	float life_in = smoothstep(0.0, 0.14, v_age);
	float life_out = pow(1.0 - v_age, 1.35);
	float life_env = life_in * life_out;

	// Break up the silhouette into wispy spray droplets + airy mist using foam_tex.
	vec2 fuv = UV * mix(1.15, 0.72, v_age) + vec2(v_seed * 3.7, v_seed * 7.1 + v_age * 0.25);
	vec3 ft = texture(foam_tex, fuv).rgb;
	float droplets = 1.0 - smoothstep(0.05, 0.52, ft.b);
	float wisp = (1.0 - smoothstep(0.08, 0.78, ft.r)) * 0.65 + ft.g * 0.35;
	// Early life leans crisp sparkling droplets; late life softens into misty spindrift.
	float shape = mix(droplets * 0.75 + wisp * 0.45, wisp * 0.85 + 0.22, clamp(v_mist_mix + v_age * 0.55, 0.0, 1.0));
	float alpha = radial * radial * shape * life_env * v_strength;

	// Soft depth fade against ships, rocks and water; fade close to the camera lens.
	float raw_d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_d, 1.0);
	float scene_z = -upos.z / max(upos.w, 1e-5);
	float soft = clamp((scene_z + VERTEX.z) / 1.8, 0.0, 1.0);
	float near_fade = smoothstep(2.4, 7.5, -VERTEX.z);
	float far_fade = smoothstep(105.0, 55.0, -VERTEX.z);
	alpha *= soft * near_fade * far_fade;
	if (alpha < 0.004) {
		discard;
	}

	// Lighting: backlit warm golden-white against the sun/sky, cool sea-mist in shadow/night.
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_origin);
	vec3 L = normalize(sun_dir);
	float cl = spray_cloud_light(v_world_origin.xz);
	vec3 sun_l = sun_color * smoothstep(-0.06, 0.25, L.y) * cl;
	float backlit = pow(max(dot(V, -L), 0.0), 3.0);
	float sun_side = 0.45 + 0.55 * max(dot(normalize(vec3(q.x, q.y, 0.6)), L), 0.0);

	vec3 base_tint = mix(vec3(0.92, 0.98, 0.97), vec3(0.82, 0.88, 0.86), storm_level * 0.6);
	vec3 col = base_tint * (ambient_color * 0.92 + sun_l * (0.45 + 0.45 * sun_side));
	// Warm luminous rim / forward-scatter when spray is backlit against the sun.
	vec3 warm_rim = sun_l * vec3(1.18, 1.06, 0.90) * (0.55 + 1.35 * backlit);
	col += warm_rim * (0.28 + 0.55 * (1.0 - radial * 0.5)) * smoothstep(0.02, 0.25, L.y);
	// Slight horizon lift so distant spray blends into atmospheric haze cleanly.
	float dist = length(CAMERA_POSITION_WORLD - v_world_origin);
	col = mix(col, sky_horizon_color * 1.05, smoothstep(40.0, 110.0, dist) * 0.35);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.85);
}
