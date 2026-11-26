shader_type spatial;
// Stylized wind-billow and luffing shader for sloop sails and masthead flag.
// Uses UV2 wind weights baked into sloop.glb:
//   UV2.x = vertex freedom (0 at yard/hoist/bolt ropes .. 1 in belly/fly)
//   UV2.y = distance down the sail or hoist (0..1)
// Preserves embedded glTF albedo texture, vertex colour tint, and back-face
// translucent canvas glow.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec3 sun_dir;
global uniform vec3 sun_color;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float use_albedo_tex = 1.0;
uniform vec3 albedo_tint : source_color = vec3(1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.92;
uniform vec3 emission_tint : source_color = vec3(1.0, 0.86, 0.6);
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.28;

// 0.0 = sail (single-sided layer with backface discard), 1.0 = two-sided flag.
uniform float is_flag = 0.0;
// 0.0 = forward face, 1.0 = aft face of sail.
uniform float is_back_face = 0.0;

// Dynamic sailing parameters driven by Ship every frame.
uniform float wind_catch : hint_range(0.0, 1.0) = 0.7;
uniform float luff_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wind_strength : hint_range(0.0, 3.0) = 0.8;
uniform float sail_time = 0.0;

varying vec3 v_world_normal;
varying float v_ripple;

void vertex() {
	float w = clamp(UV2.x, 0.0, 1.0);
	float v_down = clamp(UV2.y, 0.0, 1.0);
	float ws = clamp(wind_strength, 0.0, 2.5);

	if (is_flag > 0.5) {
		// Flag extends along local -Z from the hoist (w = 0) to the fly (w = 1).
		float freq = 6.5 + ws * 5.2;
		float wave1 = sin(w * 8.2 - sail_time * freq);
		float wave2 = sin(w * 15.4 - sail_time * (freq * 1.65) + v_down * 2.8);
		float amp = (0.09 + 0.14 * clamp(ws, 0.0, 1.5)) * pow(w, 1.15);
		float disp_x = (wave1 * 0.75 + wave2 * 0.25) * amp;
		float droop = -0.14 * (1.0 - clamp(ws, 0.0, 1.0)) * w * w;
		float snap_y = cos(w * 9.5 - sail_time * (freq * 1.1)) * 0.028 * w * ws;
		VERTEX.x += disp_x;
		VERTEX.y += droop + snap_y;
		// Tilt normal gently with the travelling wave for painterly shading.
		float slope = cos(w * 8.2 - sail_time * freq) * amp * 2.4;
		NORMAL = normalize(NORMAL + vec3(0.0, 0.0, slope));
		v_ripple = wave1 * w;
	} else {
		// Sail belly bulges along local -Z in sloop.glb.
		// Relax the baked belly when wind catch is low, and puff it full in strong wind.
		float relax = 0.42 * (1.0 - wind_catch);
		float puff = -0.52 * wind_catch * clamp(0.35 + ws * 0.65, 0.0, 1.65);
		float breathe = -0.075 * sin(sail_time * 1.65 + v_down * 1.9) * wind_catch * ws;

		// Luffing ripples travel across the canvas when poorly trimmed or head-to-wind.
		float luff_freq = 7.5 + ws * 4.5;
		float r1 = sin(VERTEX.x * 3.1 + sail_time * luff_freq + v_down * 2.6);
		float r2 = sin(VERTEX.x * 5.8 - sail_time * (luff_freq * 1.35) - v_down * 4.2);
		float luff_wave = (r1 * 0.65 + r2 * 0.35) * (0.24 * luff_amount * clamp(0.3 + ws * 0.7, 0.2, 1.6));

		// Fine taut shimmer even when drawing full wind.
		float taut_shimmer = sin(VERTEX.x * 2.2 - sail_time * (4.0 + ws * 2.0) + v_down * 3.4)
			* 0.032 * wind_catch * ws;

		float dz = (relax + puff + breathe + luff_wave + taut_shimmer) * w;
		VERTEX.z += dz;
		// Subtle vertical lift at the foot when billowing hard.
		VERTEX.y += 0.06 * wind_catch * clamp(ws, 0.0, 1.5) * w * v_down;

		// Perturb normal slightly so ripples catch sunlit highlights cleanly.
		float dnx = (cos(VERTEX.x * 3.1 + sail_time * luff_freq + v_down * 2.6) * luff_amount * 0.45
			+ cos(VERTEX.x * 2.2 - sail_time * (4.0 + ws * 2.0) + v_down * 3.4) * 0.08) * w;
		NORMAL = normalize(NORMAL + vec3(dnx, 0.0, 0.0));
		v_ripple = (r1 * luff_amount + taut_shimmer * 4.0) * w;
	}

	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Sail front/back are separate offset sheets (1.4 cm); cull each sheet's back face
	// while keeping the single-sheet flag two-sided.
	if (is_flag < 0.5 && !FRONT_FACING) {
		discard;
	}

	vec3 tex_col = use_albedo_tex > 0.5 ? texture(albedo_tex, UV).rgb : vec3(1.0);
	vec3 base_col = tex_col * COLOR.rgb * albedo_tint;
	// Subtle shading accent inside luff creases.
	base_col *= 1.0 + clamp(v_ripple * 0.06, -0.08, 0.08);

	ALBEDO = base_col;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	SPECULAR = 0.12;

	// Warm sunlit translucency when light strikes the far side of the canvas.
	vec3 n_world = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	float back_lit = clamp(-dot(n_world, normalize(sun_dir)), 0.0, 1.0);
	float sss = pow(back_lit, 1.4) * sss_strength * (is_back_face > 0.5 ? 1.25 : 0.75);
	vec3 trans_glow = base_col * sun_color * sss;
	EMISSION = emission_tint * emission_strength + trans_glow;
}
