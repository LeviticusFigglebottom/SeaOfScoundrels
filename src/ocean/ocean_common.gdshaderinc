// Shared by the ocean surface and the underwater pass: sky globals, sky colour,
// caustics and underwater fog. Original code, no third-party sources.

global uniform vec3 sun_dir;            // unit vector towards the sun
global uniform vec3 sun_color;
global uniform vec3 sky_horizon_color;
global uniform vec3 sky_zenith_color;
global uniform vec3 ambient_color;

// R,G = ripple normal xy, B = caustic pattern (tools/textures/gen_ocean.py).
uniform sampler2D detail_tex : repeat_enable, filter_linear_mipmap_anisotropic;

uniform vec3 uw_fog_color : source_color = vec3(0.03, 0.42, 0.50);
uniform vec3 uw_extinction = vec3(0.150, 0.050, 0.040); // per metre, red dies first
uniform float uw_cam_depth = 0.0; // metres the camera is below the surface (>0 under)
uniform float uw_shaft_strength = 4.5;
uniform int uw_shaft_steps = 10;

// Analytic sky used for reflections and the Snell window.
vec3 ocean_sky(vec3 dir) {
	float h = clamp(dir.y, 0.0, 1.0);
	return mix(sky_horizon_color, sky_zenith_color, pow(h, 0.5));
}

// Sunlight that actually reaches the water (fades as the sun sets).
vec3 ocean_sun_light() {
	return sun_color * smoothstep(-0.06, 0.25, sun_dir.y);
}

// Animated caustic network on the horizontal plane q (metres).
float ocean_caustic(vec2 q) {
	float t = sea_time;
	float a = texture(detail_tex, q * 0.115 + vec2(0.021, 0.013) * t).b;
	float b = texture(detail_tex, q.yx * 0.087 + vec2(-0.017, 0.024) * t + 0.37).b;
	return min(a, b) * 2.2 + a * b * 1.5;
}

// Colour of the water volume seen from inside, looking along dir.
vec3 uw_ambient(vec3 dir) {
	vec3 light = ambient_color * 0.55 + ocean_sun_light() * 0.75;
	float up = smoothstep(-1.0, 1.0, dir.y);
	float deep = exp(-max(uw_cam_depth, 0.0) * 0.035);
	// A soft bloom of light around the refracted sun direction.
	float toward_sun = pow(max(dot(dir, normalize(sun_dir + vec3(0.0, 1.2, 0.0))), 0.0), 6.0);
	return uw_fog_color * light * deep * (mix(0.34, 1.45, up * up) + 0.9 * toward_sun);
}

// Fog a colour seen through d metres of water along dir.
vec3 uw_apply(vec3 col, float d, vec3 dir) {
	vec3 tr = exp(-uw_extinction * d);
	return col * tr + uw_ambient(dir) * (1.0 - tr);
}

// Sun shafts seen from under water: march the view ray and look each sample up
// in a soft, slowly drifting light field projected along the sun direction.
// Both the underwater pass and the surface underside add this, so they match.
vec3 uw_shafts(vec3 cam, vec3 dir, float dist, vec2 frag) {
	vec3 L = normalize(sun_dir);
	float sun_up = max(L.y, 0.2);
	float tmax = min(dist, 40.0);
	float jitter = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	float soft_jitter = mix(0.5, jitter, 0.38);
	float shaft = 0.0;
	for (int i = 0; i < uw_shaft_steps; i++) {
		float t = (float(i) + soft_jitter) / float(uw_shaft_steps) * tmax;
		vec3 p = cam + dir * t;
		float d = -p.y;
		if (d > 0.0) {
			vec2 q = p.xz + L.xz * (d / sun_up);
			float a = textureLod(detail_tex, q * 0.061 + vec2(0.006, 0.004) * sea_time, 2.2).b;
			float b = textureLod(detail_tex, q.yx * 0.043 - vec2(0.005, 0.007) * sea_time + 0.5, 2.2).b;
			float beam = smoothstep(0.24, 0.78, a + b);
			shaft += beam * exp(-d * 0.10) * exp(-t * 0.06);
		}
	}
	shaft *= tmax / float(uw_shaft_steps) * 0.11;
	float toward = 0.30 + 0.70 * pow(max(dot(dir, L), 0.0), 2.0);
	return uw_fog_color * ocean_sun_light() * shaft * uw_shaft_strength * toward * smoothstep(0.0, 0.25, L.y);
}
