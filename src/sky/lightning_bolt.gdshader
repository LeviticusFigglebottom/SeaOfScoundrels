shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Lightning bolt ribbon: white-hot core with a soft coloured fringe. Additive
// and unfogged so it reads through storm murk; sky_rig fades it with `intensity`.

uniform vec3 tint = vec3(0.7, 0.8, 1.0);
uniform float intensity = 0.0;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float core = smoothstep(0.55, 0.9, across);
	float fringe = across * across;
	ALBEDO = (vec3(1.0) * core * 6.0 + tint * fringe * 1.6) * intensity * COLOR.r;
}
