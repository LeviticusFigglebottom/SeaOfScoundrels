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
uniform float sss_strength : hint_range(0.0, 1.0) = 0.48;

// 0.0 = sail (single-sided layer with backface discard), 1.0 = two-sided flag.
uniform float is_flag = 0.0;
// 0.0 = forward face, 1.0 = aft face of sail.
uniform float is_back_face = 0.0;

// Dynamic sailing parameters driven by Ship every frame.
uniform float wind_catch : hint_range(0.0, 1.0) = 0.7;
uniform float luff_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wind_strength : hint_range(0.0, 3.0) = 0.8;
uniform float sail_time = 0.0;

// Faction emblem & spectral phase parameters (defaults keep player sails 100% unchanged).
// 0 = standard, 1 = corsair, 2 = drowned, 3 = ghost.
uniform int emblem_mode = 0;
uniform float phase_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float phase_flare : hint_range(0.0, 2.0) = 0.0;

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec2 v_uv2;
varying float v_ripple;
varying float v_belly;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float gyroid3(vec3 p) {
	return dot(sin(p), cos(p.yzx));
}

float spectral_fbm(vec3 p) {
	float n = gyroid3(p) * 0.55;
	n += gyroid3(p * 2.13 + vec3(1.7, 3.1, 2.3)) * 0.30;
	n += gyroid3(p * 4.37 - vec3(2.4, 1.3, 3.7)) * 0.15;
	return clamp(n * 0.34 + 0.5, 0.0, 1.0);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

// Corsair Raider skull-and-crossbones SDF in aspect-corrected coords centered at (0.5, 0.46).
// Returns vec3(crossbones_mask, skull_mask, dark_feature_mask).
vec3 corsair_skull_emblem(vec2 q) {
	// Twin crossed femurs with chunky twin knuckle condyles at all 4 diagonal ends.
	vec2 a1 = vec2(-0.165, -0.105);
	vec2 b1 = vec2(0.165, 0.145);
	vec2 a2 = vec2(0.165, -0.105);
	vec2 b2 = vec2(-0.165, 0.145);

	float d_b1 = sd_segment(q, a1, b1) - 0.020;
	float d_b2 = sd_segment(q, a2, b2) - 0.020;

	vec2 n1 = normalize(vec2(-(b1.y - a1.y), b1.x - a1.x));
	vec2 n2 = normalize(vec2(-(b2.y - a2.y), b2.x - a2.x));
	float k_rad = 0.024;
	float k_off = 0.017;
	float d_kn = length(q - (a1 + n1 * k_off)) - k_rad;
	d_kn = min(d_kn, length(q - (a1 - n1 * k_off)) - k_rad);
	d_kn = min(d_kn, length(q - (b1 + n1 * k_off)) - k_rad);
	d_kn = min(d_kn, length(q - (b1 - n1 * k_off)) - k_rad);
	d_kn = min(d_kn, length(q - (a2 + n2 * k_off)) - k_rad);
	d_kn = min(d_kn, length(q - (a2 - n2 * k_off)) - k_rad);
	d_kn = min(d_kn, length(q - (b2 + n2 * k_off)) - k_rad);
	d_kn = min(d_kn, length(q - (b2 - n2 * k_off)) - k_rad);
	float d_bones = min(min(d_b1, d_b2), d_kn);

	// Chunky stylized pirate skull (-y is up toward the yard, +y is down toward the foot).
	vec2 sq = vec2(abs(q.x), q.y);
	float d_cranium = length((q - vec2(0.0, -0.048)) / vec2(0.106, 0.094)) - 1.0;
	d_cranium *= 0.098;
	float d_cheek = length(sq - vec2(0.068, 0.012)) - 0.041;
	float d_jaw = sd_box(q - vec2(0.0, 0.068), vec2(0.056, 0.044)) - 0.014;
	float d_skull = min(min(d_cranium, d_cheek), d_jaw);

	// Bold dark outline ring separating the skull cleanly in front of the crossed bones.
	float skull_outline = smoothstep(0.014, 0.002, d_skull);

	// Angry tilted eye sockets, triangular nasal cavity, and crisp vertical tooth notches.
	vec2 eye_p = sq - vec2(0.042, -0.014);
	// Tilt inner brow downward for a fierce scoundrel scowl.
	vec2 eye_rot = vec2(eye_p.x * 0.94 + eye_p.y * 0.34, -eye_p.x * 0.34 + eye_p.y * 0.94);
	float d_eye = length(eye_rot / vec2(0.029, 0.024)) - 1.0;
	d_eye *= 0.026;

	// Inverted triangle / heart nasal cavity.
	vec2 nose_p = q - vec2(0.0, 0.024);
	float d_nose = max(abs(nose_p.x) - clamp((0.022 + nose_p.y) * 0.58, 0.0, 0.020), abs(nose_p.y) - 0.019);

	// Grin bar + 3 crisp vertical tooth slits.
	float d_grin = sd_box(q - vec2(0.0, 0.072), vec2(0.044, 0.005));
	float tooth_x = min(abs(q.x), abs(abs(q.x) - 0.025));
	float d_teeth = max(tooth_x - 0.0045, abs(q.y - 0.082) - 0.026);
	float d_features = min(min(d_eye, d_nose), min(d_grin, d_teeth));

	float bones_m = smoothstep(0.006, -0.004, d_bones) * (1.0 - skull_outline);
	float skull_m = smoothstep(0.004, -0.004, d_skull);
	float feat_m = smoothstep(0.004, -0.003, d_features) * skull_m;
	return vec3(bones_m, skull_m * (1.0 - feat_m), max(feat_m, skull_outline * (1.0 - skull_m)));
}

// Drowned cursed anchor/trident rune sigil SDF in aspect-corrected coords centered at (0.5, 0.46).
float drowned_trident_anchor_rune(vec2 q) {
	vec2 sq = vec2(abs(q.x), q.y);
	// Central shaft + sharp spearhead at top (-y).
	float d = sd_segment(q, vec2(0.0, -0.235), vec2(0.0, 0.195)) - 0.014;
	float d_tip = sd_segment(sq, vec2(0.0, -0.245), vec2(0.032, -0.185)) - 0.009;
	d = min(d, d_tip);

	// Top arcane anchor ring / diamond.
	float ring_r = abs(length(q - vec2(0.0, -0.155)) - 0.038) - 0.010;
	d = min(d, ring_r);

	// Cross-stock bar with diamond end caps.
	float d_stock = sd_segment(q, vec2(-0.115, -0.055), vec2(0.115, -0.055)) - 0.011;
	float d_cap = (abs(sq.x - 0.122) + abs(sq.y + 0.055)) - 0.024;
	d = min(d, min(d_stock, d_cap));

	// Upper sweeping trident outer prongs rising toward -y.
	float d_p1 = sd_segment(sq, vec2(0.0, -0.055), vec2(0.095, -0.085)) - 0.011;
	float d_p2 = sd_segment(sq, vec2(0.095, -0.085), vec2(0.118, -0.195)) - 0.011;
	float d_pbarb = sd_segment(sq, vec2(0.118, -0.195), vec2(0.085, -0.165)) - 0.008;
	d = min(d, min(d_p1, min(d_p2, d_pbarb)));

	// Lower sweeping anchor crown & barbed flukes (+y bottom curving out and up).
	float d_f1 = sd_segment(sq, vec2(0.0, 0.195), vec2(0.095, 0.165)) - 0.013;
	float d_f2 = sd_segment(sq, vec2(0.095, 0.165), vec2(0.152, 0.072)) - 0.012;
	float d_fluke = sd_segment(sq, vec2(0.152, 0.072), vec2(0.105, 0.096)) - 0.010;
	d = min(d, min(d_f1, min(d_f2, d_fluke)));

	// Flanking eldritch chevron runes.
	float d_r1 = sd_segment(sq, vec2(0.195, -0.045), vec2(0.225, 0.0)) - 0.008;
	float d_r2 = sd_segment(sq, vec2(0.225, 0.0), vec2(0.195, 0.045)) - 0.008;
	d = min(d, min(d_r1, d_r2));

	return smoothstep(0.006, -0.004, d);
}

void vertex() {
	float w = clamp(UV2.x, 0.0, 1.0);
	float v_down = clamp(UV2.y, 0.0, 1.0);
	float ws = clamp(wind_strength, 0.0, 2.5);
	v_belly = 0.0;
	v_uv2 = UV2;

	if (is_flag > 0.5) {
		// Flag extends along local -Z from the hoist (w = 0) to the fly (w = 1).
		float freq = 6.5 + ws * 5.2;
		float wave1 = sin(w * 8.2 - sail_time * freq);
		float wave2 = sin(w * 15.4 - sail_time * (freq * 1.65) + v_down * 2.8);
		float amp = (0.11 + 0.16 * clamp(ws, 0.0, 1.5)) * pow(w, 1.15);
		float disp_x = (wave1 * 0.75 + wave2 * 0.25) * amp;
		float droop = -0.10 * (1.0 - clamp(ws, 0.0, 1.0)) * w * w;
		float snap_y = cos(w * 9.5 - sail_time * (freq * 1.1)) * 0.032 * w * ws;
		VERTEX.x += disp_x;
		VERTEX.y += droop + snap_y;
		// Tilt normal gently with the travelling wave for painterly shading.
		float slope = cos(w * 8.2 - sail_time * freq) * amp * 2.4;
		NORMAL = normalize(NORMAL + vec3(0.0, 0.0, slope));
		v_ripple = wave1 * w;
	} else {
		// Sail belly bulges boldly along local -Z in sloop.glb (deep billowing canvas like image_2.png).
		float pillow = sin(clamp(v_down, 0.0, 1.0) * 3.14159265);
		float relax = 0.36 * (1.0 - wind_catch);
		float puff = -1.28 * wind_catch * clamp(0.55 + ws * 0.55, 0.0, 1.65) * (0.65 + 0.55 * pillow);
		float breathe = -0.11 * sin(sail_time * 1.65 + v_down * 1.9) * wind_catch * ws;

		// Luffing ripples travel across the canvas when poorly trimmed or head-to-wind.
		float luff_freq = 7.5 + ws * 4.5;
		float r1 = sin(VERTEX.x * 3.1 + sail_time * luff_freq + v_down * 2.6);
		float r2 = sin(VERTEX.x * 5.8 - sail_time * (luff_freq * 1.35) - v_down * 4.2);
		float luff_wave = (r1 * 0.65 + r2 * 0.35) * (0.28 * luff_amount * clamp(0.3 + ws * 0.7, 0.2, 1.6));

		// Fine taut shimmer even when drawing full wind.
		float taut_shimmer = sin(VERTEX.x * 2.2 - sail_time * (4.0 + ws * 2.0) + v_down * 3.4)
			* 0.04 * wind_catch * ws;

		float dz = (relax + puff + breathe + luff_wave + taut_shimmer) * w;
		VERTEX.z += dz;
		// Subtle vertical lift & curved normal tilt so the billow catches bold light/shadow bands.
		VERTEX.y += 0.14 * wind_catch * clamp(ws, 0.0, 1.5) * w * v_down;

		float dnx = (cos(VERTEX.x * 3.1 + sail_time * luff_freq + v_down * 2.6) * luff_amount * 0.48
			+ cos(VERTEX.x * 2.2 - sail_time * (4.0 + ws * 2.0) + v_down * 3.4) * 0.09
			- VERTEX.x * 0.14 * wind_catch) * w;
		float dny = (0.5 - v_down) * 0.48 * wind_catch * w;
		NORMAL = normalize(NORMAL + vec3(dnx, dny, 0.0));
		v_ripple = (r1 * luff_amount + taut_shimmer * 4.0) * w;
		v_belly = clamp(-puff * w * 0.55, 0.0, 1.0);
	}

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Sail front/back are separate offset sheets (1.4 cm); cull each sheet's back face
	// while keeping the single-sheet flag two-sided.
	if (is_flag < 0.5 && !FRONT_FACING) {
		discard;
	}

	if (phase_alpha <= 0.005) {
		discard;
	}

	// Spectral phase dissolve applies to both sails and flags when phase_alpha < 1.0.
	vec3 wp = v_world_pos;
	float dissolve_edge = 0.0;
	if (phase_alpha < 0.999) {
		float d_field = spectral_fbm(vec3(wp.x * 0.85, wp.y * 0.72 - sail_time * 1.05, wp.z * 0.85));
		float height_bias = clamp((wp.y + 1.8) * 0.025, 0.0, 0.14);
		float dissolve_field = clamp(d_field * 0.90 + height_bias, 0.0, 1.0);
		float thresh = mix(1.08, -0.08, phase_alpha);
		float margin = dissolve_field - thresh;
		if (margin < 0.0) {
			discard;
		}
		dissolve_edge = (1.0 - smoothstep(0.0, 0.14, margin)) * smoothstep(0.999, 0.92, phase_alpha);
	}

	vec3 tex_col = use_albedo_tex > 0.5 ? texture(albedo_tex, UV).rgb : vec3(1.0);
	vec3 base_col = tex_col * COLOR.rgb * albedo_tint;
	// Painterly billow crease shading & subtle stitched seam depth.
	float seam = smoothstep(0.92, 1.0, abs(sin(UV.x * 18.84955))) * 0.045;
	float billow_mod = 1.0 + clamp(v_ripple * 0.07, -0.09, 0.09) + v_belly * 0.06 - seam;

	vec3 extra_emission = vec3(0.0);
	bool is_sail_canvas = is_flag < 0.5 && use_albedo_tex > 0.5;

	if (emblem_mode == 0) {
		base_col *= billow_mod;
	} else {
		// Neutral woven linen canvas grain for faction sails so the player's red winking sun
		// baked into sloop_sail does not ghost behind enemy emblems.
		float weave = 0.94 + 0.03 * sin(UV.x * 180.0) * sin(UV.y * 180.0)
			+ 0.08 * (vnoise2(UV * 10.5) - 0.5);
		float panel_seam = smoothstep(0.94, 1.0, abs(sin(UV.x * 18.84955))) * 0.14;
		float reef_band = smoothstep(0.012, 0.0, abs(UV.y - 0.26)) * 0.09
			+ smoothstep(0.012, 0.0, abs(UV.y - 0.70)) * 0.09;
		float linen = clamp(weave - panel_seam - reef_band, 0.65, 1.08);
		vec3 faction_canvas = vec3(linen) * COLOR.rgb * albedo_tint;

		if (emblem_mode == 1) {
			// CORSAIR RAIDER: deep blood-crimson canvas + charcoal horizontal/diagonal war-band
			// + bold warm-ivory skull-and-crossbones medallion centered at (0.5, 0.46).
			if (is_sail_canvas) {
				vec2 p = UV - vec2(0.5, 0.46);
				vec2 q = vec2(p.x * 1.14, p.y);
				float brush = (vnoise2(UV * 24.0) - 0.5) * 0.012;

				// Bold charcoal horizontal-chevron war-band + angled slash stripe across the belly.
				float chev_d = abs(p.y - (0.045 - abs(p.x) * 0.16)) + brush;
				float diag_d = abs(p.y - p.x * 0.48) + brush;
				float band_m = max(smoothstep(0.118, 0.106, chev_d), smoothstep(0.062, 0.052, diag_d));
				float trim_m = max(
					smoothstep(0.012, 0.004, abs(chev_d - 0.122)),
					smoothstep(0.010, 0.003, abs(diag_d - 0.066))
				) * (1.0 - band_m);

				// Medallion backing disc + ivory-gold ring frame.
				float med_r = length(q) + brush * 0.55;
				float med_bg = smoothstep(0.232, 0.222, med_r);
				float med_ring = smoothstep(0.011, 0.004, abs(med_r - 0.214));

				vec3 skull_parts = corsair_skull_emblem(q);
				float ivory_m = clamp(skull_parts.x + skull_parts.y, 0.0, 1.0);
				float dark_ink_m = skull_parts.z;

				vec3 charcoal = vec3(0.065, 0.060, 0.068) * linen;
				vec3 ivory = vec3(0.95, 0.89, 0.75) * linen;
				vec3 gold_trim = vec3(0.86, 0.66, 0.24) * linen;

				vec3 painted = faction_canvas;
				painted = mix(painted, charcoal, clamp(band_m + med_bg, 0.0, 1.0));
				painted = mix(painted, gold_trim, clamp(trim_m * 0.85 + med_ring * 0.95, 0.0, 1.0));
				painted = mix(painted, ivory, ivory_m);
				painted = mix(painted, charcoal * 0.72, dark_ink_m);

				// Soften slightly on aft side so ink looks naturally soaked through backlit canvas.
				base_col = mix(faction_canvas, painted, is_back_face > 0.5 ? 0.72 : 1.0) * billow_mod;
			} else {
				base_col *= billow_mod;
			}
		} else if (emblem_mode == 2) {
			// DROWNED CURSED: barnacle-tattered jagged bottom hem (v > 0.80) + eerie glowing
			// sea-green anchor/trident rune sigil near the center.
			if (is_flag < 0.5) {
				if (use_albedo_tex > 0.5) {
					// Multi-frequency organic irregular tear silhouette (non-repeating shredded ribbons).
					float n_broad = vnoise2(vec2(UV.x * 5.3 + 0.7, 1.9));
					float n_mid = vnoise2(vec2(UV.x * 13.7 + 2.3, 4.1));
					float n_fine = vnoise2(vec2(UV.x * 29.0 + 6.1, 8.3));
					float notch = sin(UV.x * 17.5 + n_broad * 3.8) * 0.048
						+ cos(UV.x * 31.0 - n_mid * 4.5) * 0.026;
					float tear_line = 0.80 + 0.115 * n_broad + 0.055 * n_mid + 0.028 * n_fine + notch;
					float hem_edge = tear_line - UV.y;
					if (UV.y > 0.77 && hem_edge < 0.0) {
						discard;
					}
					float rot_n = vnoise2(UV * vec2(11.5, 9.2) + vec2(3.1, 1.7));
					if (UV.y > 0.72 && UV.y < 0.91 && rot_n > 0.83) {
						discard;
					}

					// Salt-stained brine weathering & frayed dark edge along the jagged tears.
					float brine = vnoise2(UV * 7.5 + vec2(1.4, 5.2));
					float foot_rot = smoothstep(0.62, 0.94, UV.y) * (0.45 + 0.55 * brine);
					float fray = smoothstep(0.055, 0.0, max(hem_edge, 0.0)) * smoothstep(0.70, 0.82, UV.y);
					vec3 cursed_cloth = faction_canvas * mix(1.0, 0.58, clamp(foot_rot * 0.55 + fray * 0.75, 0.0, 0.85));

					// Glowing sunken anchor/trident rune sigil centered at (0.5, 0.46).
					vec2 q = vec2((UV.x - 0.5) * 1.14, UV.y - 0.46);
					float rune_m = drowned_trident_anchor_rune(q);
					float rune_halo = smoothstep(0.28, 0.04, length(q)) * 0.16;
					float pulse = 0.78 + 0.22 * sin(sail_time * 2.1 + UV.y * 4.5);

					vec3 rune_paint = vec3(0.36, 0.88, 0.64) * linen;
					vec3 rune_glow_col = vec3(0.14, 0.96, 0.56);
					float face_str = is_back_face > 0.5 ? 0.76 : 1.0;
					base_col = mix(cursed_cloth, rune_paint, rune_m * 0.85 * face_str) * billow_mod;
					extra_emission += rune_glow_col * (rune_m * 0.82 * face_str + rune_halo * 0.35) * pulse;
				} else {
					// Discard the bottom bolt rope where the hem is shredded (UV2.y == 0 at foot).
					if ((1.0 - v_uv2.y) > 0.90 && v_uv2.x > 0.12) {
						discard;
					}
					base_col *= billow_mod;
				}
			} else {
				base_col *= billow_mod;
			}
		} else if (emblem_mode == 3) {
			// GHOST SHIP: deep abyssal-cyan inner canvas + blazing Fresnel aqua-emerald rim +
			// upward drifting ectoplasmic bands + organic ragged trailing spectral tears (v > 0.74).
			float frayed_glow = 0.0;
			if (is_flag < 0.5) {
				if (use_albedo_tex > 0.5) {
					float sway = sin(UV.x * 13.0 - sail_time * 2.2) * 0.020;
					float gn1 = vnoise2(vec2(UV.x * 4.8 + 1.1, sail_time * 0.14 + 2.3));
					float gn2 = vnoise2(vec2(UV.x * 12.5 + 3.7, sail_time * 0.28 + 5.7));
					float gn3 = vnoise2(vec2(UV.x * 26.0 + 7.2, 9.1));
					float streamer = sin(UV.x * 16.0 + gn1 * 4.2) * 0.062
						+ cos(UV.x * 29.0 - gn2 * 3.8) * 0.032;
					float ghost_tear = 0.74 + 0.135 * gn1 + 0.068 * gn2 + 0.025 * gn3 + streamer + sway;
					float g_edge = ghost_tear - UV.y;
					if (UV.y > 0.70 && g_edge < 0.0) {
						discard;
					}
					float g_hole = vnoise2(UV * vec2(7.8, 6.2) + vec2(0.0, -sail_time * 0.16));
					if (UV.y > 0.60 && g_hole > 0.80) {
						discard;
					}
					frayed_glow = smoothstep(0.085, 0.0, max(g_edge, 0.0)) * smoothstep(0.60, 0.75, UV.y);
				} else {
					if ((1.0 - v_uv2.y) > 0.88 && v_uv2.x > 0.12) {
						discard;
					}
				}
			}

			// World-space upward-drifting spectral wisp bands matching ghost_hull.gdshader.
			float swirl_x = sin(wp.z * 0.46 + wp.y * 0.65 - sail_time * 1.15) * 0.56;
			float swirl_z = cos(wp.x * 0.50 - wp.y * 0.58 - sail_time * 0.92) * 0.56;
			float w_fbm = spectral_fbm(vec3(wp.x * 0.68 + swirl_x, wp.y * 0.95 - sail_time * 1.65, wp.z * 0.68 + swirl_z));
			float band_wave = 0.5 + 0.5 * sin(wp.y * 2.7 - sail_time * 2.7 + (w_fbm - 0.5) * 4.6 + (wp.x - wp.z) * 0.35);
			float wisp = smoothstep(0.48, 0.88, w_fbm * 0.62 + band_wave * 0.42);

			// Upward-licking painterly ectoplasmic veins rising from the tattered lower hem.
			float vein = 0.0;
			if (is_sail_canvas) {
				float warp_u = UV.x * 9.0 + sin(UV.y * 11.0 + sail_time * 1.8) * 0.65;
				float v_str = vnoise2(vec2(warp_u, UV.y * 3.8 + sail_time * 0.55));
				vein = smoothstep(0.58, 0.88, v_str) * smoothstep(0.08, 0.85, UV.y) * 0.55;
			}

			// Blazing Fresnel aqua-emerald rim contrasting against a deep haunted abyssal belly.
			float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
			float fresnel = pow(1.0 - ndotv, 2.2);
			float sharp_rim = pow(1.0 - ndotv, 4.4);
			float leech_rim = is_sail_canvas ? smoothstep(0.32, 0.50, abs(UV.x - 0.5)) * 0.42 : 0.0;

			vec3 abyssal_core = vec3(0.016, 0.085, 0.125) * linen;
			vec3 rim_col = vec3(0.24, 1.0, 0.90);
			vec3 hot_edge = vec3(0.86, 1.0, 0.99);

			base_col = mix(abyssal_core, rim_col * 0.38, clamp(fresnel * 0.45 + leech_rim * 0.35, 0.0, 0.8)) * billow_mod;
			extra_emission += abyssal_core * (0.28 + 0.55 * wisp);
			extra_emission += rim_col * (fresnel * 1.25 + sharp_rim * 1.45 + leech_rim * 0.55 + wisp * 0.62 + vein * 0.72 + frayed_glow * 1.65);
			extra_emission += mix(rim_col, hot_edge, 0.48) * phase_flare * (0.45 + fresnel * 0.85);
		} else {
			base_col *= billow_mod;
		}
	}

	if (dissolve_edge > 0.001) {
		extra_emission += vec3(0.88, 1.0, 0.99) * dissolve_edge * 3.8;
	}

	ALBEDO = base_col;
	ROUGHNESS = emblem_mode == 3 ? 0.56 : roughness_val;
	METALLIC = 0.0;
	SPECULAR = emblem_mode == 3 ? 0.28 : 0.12;

	// Warm sunlit translucency when light strikes the far side of the canvas.
	vec3 n_world = normalize(v_world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	float back_lit = clamp(-dot(n_world, normalize(sun_dir)), 0.0, 1.0);
	float sss = pow(back_lit, 1.3) * sss_strength * (is_back_face > 0.5 ? 1.3 : 0.8);
	vec3 trans_glow = emblem_mode == 3
		? vec3(0.10, 0.55, 0.54) * sss * 0.28
		: base_col * sun_color * sss;
	EMISSION = emission_tint * emission_strength + trans_glow + extra_emission;
}

