shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// One rain streak: a thin quad stretched along its fall direction by the
// particle system. Tinted by the sky so rain sits in the scene's light.

global uniform vec3 sky_horizon_color;
global uniform vec3 ambient_color;
uniform float opacity = 0.4;
uniform float flash = 0.0;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y);
	ALBEDO = mix(sky_horizon_color, ambient_color, 0.3) * 1.5 + vec3(0.05) + vec3(0.7, 0.8, 1.0) * flash;
	ALPHA = across * along * opacity * COLOR.a;
}
