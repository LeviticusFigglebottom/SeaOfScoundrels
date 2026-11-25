// Shader mirror of src/ocean/sea.gd. Keep the maths IDENTICAL to the CPU side.
// Materials including this must be registered with Sea.bind_material().
#define SEA_MAX_WAVES 32

global uniform float sea_time;
global uniform float sea_amp_scale;
uniform vec4 sea_wave_a[SEA_MAX_WAVES]; // dir.x, dir.z, k, steepness
uniform vec4 sea_wave_b[SEA_MAX_WAVES]; // calm amplitude, omega, phase, storm amplitude
uniform int sea_wave_count = 0;
uniform vec2 sea_amp_range = vec2(0.65, 2.6); // Sea.AMP_CALM, Sea.AMP_STORM

// x: 0 calm .. 1 storm; y: extra scale when sea_amp_scale is outside the range.
vec2 sea_state() {
	float c = clamp(sea_amp_scale, sea_amp_range.x, sea_amp_range.y);
	return vec2((c - sea_amp_range.x) / (sea_amp_range.y - sea_amp_range.x), sea_amp_scale / c);
}

// Vertical amplitude of a wave in the current sea state (b = sea_wave_b[i]).
float sea_wave_amp(vec4 b, vec2 st) {
	return mix(b.x, b.w, st.x) * st.y;
}

// Gerstner displacement of rest-plane point p (world xz).
vec3 sea_displacement(vec2 p) {
	vec3 d = vec3(0.0);
	vec2 st = sea_state();
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float amp = sea_wave_amp(b, st);
		float th = a.z * dot(a.xy, p) - b.y * sea_time + b.z;
		float sn = sin(th) * amp * a.w;
		d.x -= a.x * sn;
		d.z -= a.y * sn;
		d.y += amp * cos(th);
	}
	return d;
}

// Analytic surface normal and Jacobian determinant (foam where j is small).
void sea_normal_jacobian(vec2 p, out vec3 n, out float j) {
	float dxx = 1.0, dzz = 1.0, dxz = 0.0;
	float dyx = 0.0, dyz = 0.0;
	vec2 st = sea_state();
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float ka = sea_wave_amp(b, st) * a.z;
		float th = a.z * dot(a.xy, p) - b.y * sea_time + b.z;
		float c = cos(th) * ka * a.w;
		float s = sin(th) * ka;
		dxx -= a.x * a.x * c;
		dzz -= a.y * a.y * c;
		dxz -= a.x * a.y * c;
		dyx -= a.x * s;
		dyz -= a.y * s;
	}
	vec3 tx = vec3(dxx, dyx, dxz);
	vec3 tz = vec3(dxz, dyz, dzz);
	n = normalize(cross(tz, tx));
	j = dxx * dzz - dxz * dxz;
}

// Height of the surface above world xz (inverse of the horizontal shift).
float sea_height(vec2 world_xz) {
	vec2 p = world_xz;
	for (int i = 0; i < 4; i++) {
		p = world_xz - sea_displacement(p).xz;
	}
	return sea_displacement(p).y;
}

// ---------------------------------------------------------------------------
// Level-of-detail variants. These only ever REMOVE waves that the mesh or the
// pixel grid cannot resolve; with cut = 0 they equal the functions above.

// 1 for waves at least twice as long as `cut` metres, 0 for waves shorter than it.
float sea_lod_weight(float k, float cut) {
	return smoothstep(1.0, 2.0, TAU / (k * max(cut, 1e-5)));
}

vec3 sea_displacement_lod(vec2 p, float cut) {
	vec3 d = vec3(0.0);
	vec2 st = sea_state();
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float amp = sea_wave_amp(b, st) * sea_lod_weight(a.z, cut);
		float th = a.z * dot(a.xy, p) - b.y * sea_time + b.z;
		float sn = sin(th) * amp * a.w;
		d.x -= a.x * sn;
		d.z -= a.y * sn;
		d.y += amp * cos(th);
	}
	return d;
}

// Normal and Jacobian at wave time t, dropping waves shorter than `cut`.
// lost_var: slope variance of what was dropped (to widen highlights);
// h: full vertical displacement of rest point p; h_var: variance of the wave
// heights in this sea state (h / sqrt(h_var) is a unitless crest mask);
// long_slope: surface slope (dy/dx, dy/dz) of the swell alone (waves over 35 m).
void sea_surface_lod(vec2 p, float t, float cut, out vec3 n, out float j, out float lost_var, out float h, out float h_var, out vec2 long_slope) {
	float dxx = 1.0, dzz = 1.0, dxz = 0.0;
	float dyx = 0.0, dyz = 0.0;
	lost_var = 0.0;
	h = 0.0;
	h_var = 0.0;
	long_slope = vec2(0.0);
	vec2 st = sea_state();
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float amp = sea_wave_amp(b, st);
		float w = sea_lod_weight(a.z, cut);
		float ka = a.z * amp;
		lost_var += (1.0 - w * w) * ka * ka * 0.5;
		h_var += amp * amp * 0.5;
		float th = a.z * dot(a.xy, p) - b.y * t + b.z;
		float cs = cos(th);
		h += cs * amp;
		float c = cs * ka * a.w * w;
		float s = sin(th) * ka * w;
		dxx -= a.x * a.x * c;
		dzz -= a.y * a.y * c;
		dxz -= a.x * a.y * c;
		dyx -= a.x * s;
		dyz -= a.y * s;
		if (a.z < 0.18) {
			long_slope -= a.xy * s;
		}
	}
	vec3 tx = vec3(dxx, dyx, dxz);
	vec3 tz = vec3(dxz, dyz, dzz);
	n = normalize(cross(tz, tx));
	j = dxx * dzz - dxz * dxz;
}

// Jacobian only (cheaper; used for foam).
float sea_jacobian_lod(vec2 p, float t, float cut) {
	float dxx = 1.0, dzz = 1.0, dxz = 0.0;
	vec2 st = sea_state();
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float th = a.z * dot(a.xy, p) - b.y * t + b.z;
		float c = cos(th) * a.z * sea_wave_amp(b, st) * a.w * sea_lod_weight(a.z, cut);
		dxx -= a.x * a.x * c;
		dzz -= a.y * a.y * c;
		dxz -= a.x * a.y * c;
	}
	return dxx * dzz - dxz * dxz;
}
