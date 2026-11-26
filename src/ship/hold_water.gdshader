shader_type spatial;
// Rising translucent bilge water inside the sloop's hold.
// Sloshes subtly with ship roll/pitch and stays clipped to the curved hull interior.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.025, 0.14, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.30, 0.29);
uniform vec3 foam_color : source_color = vec3(0.76, 0.88, 0.86);

uniform float water_level : hint_range(0.0, 1.0) = 0.0;
uniform float slosh_time = 0.0;
// Local slosh surface tilt: x = tilt along ship X (roll), y = tilt along ship Z (pitch).
uniform vec2 slosh_tilt = vec2(0.0, 0.0);
uniform float disturbance : hint_range(0.0, 1.0) = 0.2;

varying vec3 v_local;
varying float v_edge;
varying float v_wave;

// Approximate inner half-breadth of the sloop hull at (z, y) so rising/sloshing
// water always stays cleanly inside the curved planking.
float inner_half_breadth(float z, float y) {
	float h = clamp((y + 1.0) / 1.9, 0.02, 1.0);
	float bmid = 2.2 * pow(1.0 - pow(1.0 - h, 3.0), 1.0 / 3.6);
	float half_w;
	if (z >= 0.0) {
		float zs = 6.5 + 0.2 * max(y + 0.15, 0.0);
		float t = clamp(z / max(zs, 1.0), 0.0, 1.0);
		float wt = 1.55 * pow(clamp((y + 0.25) / 1.25, 0.05, 1.0), 0.45);
		half_w = bmid - (bmid - wt) * t * t * t;
	} else {
		float t = clamp(-z / 5.4, 0.0, 1.0);
		half_w = bmid * pow(max(0.0, 1.0 - pow(t, 2.3)), 0.72);
	}
	// Inset by plank thickness + frame ribs so water never pokes out.
	return max(half_w - 0.22, 0.15);
}

void vertex() {
	float z = VERTEX.z;
	float base_y = mix(-0.83, 0.86, water_level);
	float est_x = (UV.x * 2.0 - 1.0) * inner_half_breadth(z, base_y);
	float tilt_y = clamp(est_x * slosh_tilt.x + z * slosh_tilt.y, -0.22, 0.22);

	float w1 = sin(est_x * 3.8 + slosh_time * 3.2 + z * 1.4);
	float w2 = cos(z * 4.5 - slosh_time * 2.7 - est_x * 2.1);
	float w3 = sin((est_x - z) * 6.2 + slosh_time * 4.8);
	float ripple = (w1 * 0.45 + w2 * 0.35 + w3 * 0.20) * (0.018 + 0.032 * disturbance);

	float y_here = base_y + tilt_y + ripple;
	float max_x = inner_half_breadth(z, y_here);
	VERTEX.x = (UV.x * 2.0 - 1.0) * max_x;
	VERTEX.y = y_here;

	// Approximate wave normal for crisp interior lantern glints.
	float dx = cos(VERTEX.x * 3.8 + slosh_time * 3.2 + z * 1.4) * 0.11
		+ slosh_tilt.x;
	float dz = -sin(z * 4.5 - slosh_time * 2.7 - VERTEX.x * 2.1) * 0.11
		+ slosh_tilt.y;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));

	v_local = VERTEX;
	v_edge = abs(UV.x * 2.0 - 1.0);
	v_wave = ripple;
}

void fragment() {
	// Clip cleanly past the forward hold bulkhead and stern transom interior.
	if (v_local.z < -4.22 || v_local.z > 5.72) {
		discard;
	}
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float depth_mix = clamp(water_level * 1.25 + 0.18, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, depth_mix);

	// Subtle oily/milky ripples and foam rim where water laps the inner hull planks.
	float rim_noise = 0.5 + 0.5 * sin(v_local.z * 7.0 + slosh_time * 2.8)
		* cos(v_local.x * 9.0 - slosh_time * 2.1);
	float rim = smoothstep(0.84, 0.99, v_edge + rim_noise * 0.06)
		* (0.35 + 0.55 * disturbance);
	float chop_foam = smoothstep(0.015, 0.042, v_wave) * 0.22 * disturbance;
	col = mix(col, foam_color, clamp(rim + chop_foam, 0.0, 0.72));

	ALBEDO = col;
	ROUGHNESS = mix(0.14, 0.45, clamp(rim + chop_foam, 0.0, 1.0));
	METALLIC = 0.04;
	SPECULAR = 0.65;
	ALPHA = clamp(mix(0.68, 0.90, depth_mix) + fresnel * 0.15 + rim * 0.15, 0.62, 0.95);
}
