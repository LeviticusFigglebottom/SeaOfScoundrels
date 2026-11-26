shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// Zero-texture analytic volumetric lighthouse light-cone shader.
// UV.y spans 0.0 at the Fresnel lantern aperture to 1.0 at the 74 m far cone tip.

uniform vec3 beam_color : source_color = vec3(1.0, 0.80, 0.38);
uniform float beam_intensity : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.55);
	float near_fade = smoothstep(0.0, 0.055, t);
	float far_fade = pow(clamp(1.0 - t, 0.0, 1.0), 1.85);
	float lens_core = smoothstep(0.14, 0.0, t) * near_fade;
	float axial = near_fade * far_fade + lens_core * 0.45;

	ALBEDO = beam_color * (1.25 - t * 0.35 + lens_core * 0.30);
	ALPHA = clamp(edge * axial * beam_intensity * 0.42, 0.0, 0.65);
}
