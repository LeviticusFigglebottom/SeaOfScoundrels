shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Lightning bolt ribbons: a white-hot core with a coloured fringe, plus wide
// soft ribbons behind them for the glow. Additive and unfogged so it reads
// through storm murk; sky_rig.gd flickers it with `intensity`.
// Vertex colour: r = brightness (forks are dimmer and die sooner),
// g = 1 on glow ribbons, b = fade where the bolt leaves the cloud.

uniform vec3 tint = vec3(0.62, 0.74, 1.0);
uniform float intensity = 0.0;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float core = smoothstep(0.45, 0.9, across);
	vec3 hot = vec3(1.0) * core * 7.0 + tint * across * across * 2.0;
	vec3 glow = tint * across * across * across * 0.55;
	// Forks fade before the trunk does.
	float life = pow(intensity, mix(2.4, 1.0, COLOR.r));
	ALBEDO = mix(hot, glow, COLOR.g) * life * COLOR.r * COLOR.b;
}
