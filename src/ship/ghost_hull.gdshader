shader_type spatial;
// Ethereal spectral ghost hull shader for phantom ships (faction == &"ghost").
// Preserves subtle timber plank grain inside a dark abyssal-teal core while rimming
// silhouettes in luminous Fresnel cyan-emerald, drifting world-space spectral wisps,
// and an animated ectoplasmic noise dissolve driven by `phase_alpha`.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float use_albedo_tex = 1.0;
uniform vec3 base_color : source_color = vec3(0.06, 0.22, 0.26);
uniform vec3 rim_color : source_color = vec3(0.24, 1.0, 0.90);
uniform float phase_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float wisp_time = 0.0;
uniform float phase_flare : hint_range(0.0, 2.0) = 0.0;

varying vec3 v_world_pos;

float gyroid3(vec3 p) {
	return dot(sin(p), cos(p.yzx));
}

float spectral_fbm(vec3 p) {
	float n = gyroid3(p) * 0.55;
	n += gyroid3(p * 2.13 + vec3(1.7, 3.1, 2.3)) * 0.30;
	n += gyroid3(p * 4.37 - vec3(2.4, 1.3, 3.7)) * 0.15;
	return clamp(n * 0.34 + 0.5, 0.0, 1.0);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (phase_alpha <= 0.005) {
		discard;
	}

	vec3 wp = v_world_pos;
	float t = wisp_time;

	// Animated ectoplasmic dissolve field driven by phase_alpha.
	float edge_band = 0.0;
	if (phase_alpha < 0.999) {
		float d_field = spectral_fbm(vec3(wp.x * 0.85, wp.y * 0.72 - t * 1.05, wp.z * 0.85));
		float height_bias = clamp((wp.y + 1.8) * 0.025, 0.0, 0.14);
		float dissolve_field = clamp(d_field * 0.90 + height_bias, 0.0, 1.0);
		float thresh = mix(1.08, -0.08, phase_alpha);
		float margin = dissolve_field - thresh;
		if (margin < 0.0) {
			discard;
		}
		edge_band = (1.0 - smoothstep(0.0, 0.14, margin)) * smoothstep(0.999, 0.92, phase_alpha);
	}

	// Preserve underlying plank grain and baked vertex bevel shading inside dark abyssal-teal wood.
	vec3 tex_col = use_albedo_tex > 0.5 ? texture(albedo_tex, UV).rgb : vec3(1.0);
	float grain = clamp(dot(tex_col, vec3(0.30, 0.59, 0.11)), 0.30, 1.25);
	float v_luma = clamp(dot(COLOR.rgb, vec3(0.30, 0.59, 0.11)), 0.16, 1.15);
	float plank_mod = mix(0.28, 1.08, v_luma) * mix(0.62, 1.22, grain);
	vec3 core_col = base_color * plank_mod;

	// Strong grazing-angle Fresnel rim glow in luminous ectoplasmic cyan-emerald.
	float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 2.2);
	float sharp_rim = pow(1.0 - ndotv, 4.5);

	// Upward-drifting procedural spectral wisp bands in world space Y + XZ.
	float swirl_x = sin(wp.z * 0.48 + wp.y * 0.68 - t * 1.15) * 0.58;
	float swirl_z = cos(wp.x * 0.52 - wp.y * 0.58 - t * 0.92) * 0.58;
	float w_fbm = spectral_fbm(vec3(wp.x * 0.68 + swirl_x, wp.y * 0.95 - t * 1.65, wp.z * 0.68 + swirl_z));
	float band_wave = 0.5 + 0.5 * sin(wp.y * 2.8 - t * 2.7 + (w_fbm - 0.5) * 4.6 + (wp.x - wp.z) * 0.36);
	float wisp = smoothstep(0.50, 0.88, w_fbm * 0.62 + band_wave * 0.42);

	ALBEDO = mix(core_col, rim_color * 0.36, fresnel * 0.35);
	ROUGHNESS = mix(0.64, 0.22, fresnel);
	METALLIC = 0.06;
	SPECULAR = 0.32;

	vec3 hot_edge = vec3(0.86, 1.0, 0.99);
	vec3 core_shimmer = core_col * (0.35 + 0.65 * wisp);
	vec3 rim_glow = rim_color * (fresnel * 1.12 + sharp_rim * 1.45);
	vec3 wisp_glow = rim_color * wisp * (0.42 + fresnel * 0.62);
	vec3 flare_glow = mix(rim_color, hot_edge, 0.48) * phase_flare * (0.45 + fresnel * 0.88);
	vec3 dissolve_glow = hot_edge * edge_band * 3.6;
	EMISSION = core_shimmer + rim_glow + wisp_glow + flare_glow + dissolve_glow;

	// Translucent abyssal-teal phantom core (~0.64..0.74 * phase_alpha) with brighter, denser Fresnel edges.
	float edge_density = clamp(fresnel * 0.82 + wisp * 0.16 + edge_band * 0.68 + phase_flare * 0.10, 0.0, 1.0);
	ALPHA = clamp(mix(0.60, 0.95, edge_density) * phase_alpha, 0.0, 0.97);
}
