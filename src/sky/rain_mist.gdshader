shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Spindrift: big soft sheets of mist the wind tears off a rain-beaten sea.
// Billboarded, faded where they meet anything solid and near the lens.
#include "res://src/sky/rain_shelter.gdshaderinc"

global uniform vec3 ambient_color;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 tint = vec3(0.4, 0.5, 0.5);
uniform float opacity = 0.08;
uniform float flash = 0.0;

varying float life;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	life = sin(INSTANCE_CUSTOM.y * PI);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size,
			INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	if (sheltered(origin)) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float blob = smoothstep(1.0, 0.0, dot(q, q));
	// Thicker along the bottom, wispy on top.
	blob *= mix(0.55, 1.0, UV.y);
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene = -upos.z / upos.w;
	float soft = clamp((scene + VERTEX.z) / 4.0, 0.0, 1.0);
	float near_fade = smoothstep(5.0, 18.0, -VERTEX.z);
	ALBEDO = mix(tint, ambient_color, 0.35) * 1.5 + vec3(0.04) + vec3(0.6, 0.7, 0.9) * flash;
	ALPHA = blob * blob * life * opacity * soft * near_fade;
}
