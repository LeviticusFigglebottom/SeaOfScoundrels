// Shader mirror of src/ocean/sea.gd. Keep the maths IDENTICAL to the CPU side.
// Materials including this must be registered with Sea.bind_material().
#define SEA_MAX_WAVES 12

global uniform float sea_time;
global uniform float sea_amp_scale;
uniform vec4 sea_wave_a[SEA_MAX_WAVES]; // dir.x, dir.z, k, amplitude
uniform vec4 sea_wave_b[SEA_MAX_WAVES]; // horizontal amplitude, omega, phase, -
uniform int sea_wave_count = 0;

// Gerstner displacement of rest-plane point p (world xz).
vec3 sea_displacement(vec2 p) {
	vec3 d = vec3(0.0);
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float th = a.z * dot(a.xy, p) - b.y * sea_time + b.z;
		float sn = sin(th);
		d.x -= a.x * b.x * sn;
		d.z -= a.y * b.x * sn;
		d.y += a.w * cos(th);
	}
	return d * sea_amp_scale;
}

// Analytic surface normal and Jacobian determinant (foam where j is small).
void sea_normal_jacobian(vec2 p, out vec3 n, out float j) {
	float dxx = 1.0, dzz = 1.0, dxz = 0.0;
	float dyx = 0.0, dyz = 0.0;
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float th = a.z * dot(a.xy, p) - b.y * sea_time + b.z;
		float c = cos(th) * a.z * sea_amp_scale;
		float s = sin(th) * a.z * sea_amp_scale;
		dxx -= a.x * a.x * b.x * c;
		dzz -= a.y * a.y * b.x * c;
		dxz -= a.x * a.y * b.x * c;
		dyx -= a.x * a.w * s;
		dyz -= a.y * a.w * s;
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
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float w = sea_lod_weight(a.z, cut);
		float th = a.z * dot(a.xy, p) - b.y * sea_time + b.z;
		float sn = sin(th) * w;
		d.x -= a.x * b.x * sn;
		d.z -= a.y * b.x * sn;
		d.y += a.w * cos(th) * w;
	}
	return d * sea_amp_scale;
}

// Normal and Jacobian at wave time t, dropping waves shorter than `cut`.
// lost_var is the slope variance of what was dropped (to widen highlights).
void sea_surface_lod(vec2 p, float t, float cut, out vec3 n, out float j, out float lost_var) {
	float dxx = 1.0, dzz = 1.0, dxz = 0.0;
	float dyx = 0.0, dyz = 0.0;
	lost_var = 0.0;
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float w = sea_lod_weight(a.z, cut);
		float ka = a.z * a.w * sea_amp_scale;
		lost_var += (1.0 - w * w) * ka * ka * 0.5;
		float th = a.z * dot(a.xy, p) - b.y * t + b.z;
		float c = cos(th) * a.z * sea_amp_scale * w;
		float s = sin(th) * a.z * sea_amp_scale * w;
		dxx -= a.x * a.x * b.x * c;
		dzz -= a.y * a.y * b.x * c;
		dxz -= a.x * a.y * b.x * c;
		dyx -= a.x * a.w * s;
		dyz -= a.y * a.w * s;
	}
	vec3 tx = vec3(dxx, dyx, dxz);
	vec3 tz = vec3(dxz, dyz, dzz);
	n = normalize(cross(tz, tx));
	j = dxx * dzz - dxz * dxz;
}

// Jacobian only (cheaper; used for lagged foam).
float sea_jacobian_lod(vec2 p, float t, float cut) {
	float dxx = 1.0, dzz = 1.0, dxz = 0.0;
	for (int i = 0; i < sea_wave_count; i++) {
		vec4 a = sea_wave_a[i];
		vec4 b = sea_wave_b[i];
		float th = a.z * dot(a.xy, p) - b.y * t + b.z;
		float c = cos(th) * a.z * sea_amp_scale * b.x * sea_lod_weight(a.z, cut);
		dxx -= a.x * a.x * c;
		dzz -= a.y * a.y * c;
		dxz -= a.x * a.y * c;
	}
	return dxx * dzz - dxz * dxz;
}
