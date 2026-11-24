shader_type sky;
// Minimal stand-in sky for the ocean showcase (the real sky lives in src/sky/).
global uniform vec3 sun_dir;
global uniform vec3 sun_color;
global uniform vec3 sky_horizon_color;
global uniform vec3 sky_zenith_color;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 c = mix(sky_horizon_color, sky_zenith_color, pow(clamp(d.y, 0.0, 1.0), 0.5));
	c = mix(c, sky_horizon_color * 0.9, smoothstep(0.0, -0.3, d.y));
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	vec3 sun = sun_color * (smoothstep(0.9994, 0.9997, sd) * 12.0 + pow(sd, 180.0) * 1.2 + pow(sd, 12.0) * 0.25);
	COLOR = c + sun * step(-0.02, d.y);
}
