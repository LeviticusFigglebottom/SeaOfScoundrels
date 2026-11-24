shader_type sky;
// Painterly sky: three-stop gradient, sun and moon discs, stars, and two cloud
// layers (chunky cumulus, thin cirrus) drawn as flat layers of tiled noise.
// No raymarching: the main pass costs seven texture reads per pixel, the
// radiance cubemap pass three. Every colour arrives from sky_rig.gd already
// in linear space; see sky_palette.gd for the colour script.

uniform vec3 zenith_color = vec3(0.01, 0.09, 0.6);
uniform vec3 mid_color = vec3(0.04, 0.22, 0.8);
uniform vec3 horizon_color = vec3(0.35, 0.65, 0.95);
uniform vec3 glow_color = vec3(0.05);
uniform float glow_strength = 0.0;
uniform vec3 sun_halo_color = vec3(1.0, 0.9, 0.7);

uniform vec3 sun_dir = vec3(0.3, 0.8, 0.3);
uniform vec3 sun_disc_color = vec3(1.0, 0.95, 0.85);
uniform float sun_radius = 0.036; // radians; the real sun is 0.0047
uniform float sun_visibility = 1.0;

uniform vec3 moon_dir = vec3(-0.3, 0.5, -0.3);
uniform vec3 moon_color = vec3(0.8, 0.88, 1.0);
uniform float moon_radius = 0.055;
uniform float moon_phase = 0.5; // 0 new, 0.5 full, 1 new
uniform float moon_visibility = 0.0;

uniform float star_intensity = 0.0;
uniform mat3 star_basis = mat3(1.0);

// Tiled noise from tools/textures/gen_sky_noise.py: R shapes, G billows, B wisps, A soft.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover = 0.4;
uniform vec2 scroll_shape = vec2(0.0);
uniform vec2 scroll_big = vec2(0.0);
uniform vec2 scroll_detail = vec2(0.0);
uniform vec2 scroll_cirrus = vec2(0.0);
uniform vec3 cloud_lit_color = vec3(1.0);
uniform vec3 cloud_shade_color = vec3(0.3, 0.4, 0.6);
uniform vec3 cloud_rim_color = vec3(1.0);
// Towards whichever body lights the clouds (sun by day, moon by night).
uniform vec3 light_dir = vec3(0.3, 0.8, 0.3);
// 0 while sun and moon swap as key light, so the cloud shading never flips.
uniform float light_amount = 1.0;
uniform float storm = 0.0;

uniform float flash = 0.0;
uniform vec3 flash_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 flash_color = vec3(0.6, 0.7, 1.0);

const float SHAPE_SCALE = 0.42;
const float BIG_SCALE = 0.11;
const float DETAIL_SCALE = 1.25;
// Flattens the cloud layer towards the horizon without letting it run to infinity.
const float HORIZON_BEND = 0.11;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Cloud "amount" at a point on the cloud layer, roughly 0.15..0.85.
float cloud_field(vec2 p) {
	float shape = texture(noise_tex, p * SHAPE_SCALE - scroll_shape).r;
	float big = texture(noise_tex, p.yx * BIG_SCALE - scroll_big).r;
	float detail = texture(noise_tex, p * DETAIL_SCALE - scroll_detail).g;
	return shape * 0.56 + big * 0.32 + detail * 0.12;
}

float cloud_field_coarse(vec2 p) {
	float shape = texture(noise_tex, p * SHAPE_SCALE - scroll_shape).r;
	float big = texture(noise_tex, p.yx * BIG_SCALE - scroll_big).r;
	return shape * 0.56 + big * 0.32 + 0.06;
}

vec3 star_field(vec3 d, float time) {
	vec3 p = star_basis * d * 85.0;
	vec3 cell = floor(p);
	float pick = hash13(cell);
	if (pick < 0.80) {
		return vec3(0.0);
	}
	vec3 pos = cell + 0.2 + 0.6 * vec3(hash13(cell + 1.7), hash13(cell + 5.3), hash13(cell + 9.1));
	float big = pow(hash13(cell + 3.3), 5.0);
	float radius = mix(0.07, 0.2, big);
	float s = smoothstep(radius, radius * 0.25, length(p - pos));
	float twinkle = 0.78 + 0.22 * sin(time * (1.3 + 2.5 * pick) + pick * 90.0);
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.72), hash13(cell + 7.7));
	return tint * s * twinkle * mix(0.55, 2.2, big);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = max(d.y, 0.0);

	// --- Gradient -------------------------------------------------------
	vec3 col = mix(horizon_color, mid_color, 1.0 - exp(-up * 5.5));
	col = mix(col, zenith_color, smoothstep(0.08, 0.85, up));
	// Below the horizon: hold the horizon colour so the sea's edge melts into it.
	col = mix(col, horizon_color * 0.8, smoothstep(0.0, -0.6, d.y));

	// Sunset or sunrise colour poured along the horizon, strongest towards the sun.
	float sun_dot = dot(d, sun_dir);
	vec2 sun_flat = normalize(sun_dir.xz + vec2(0.0001));
	float toward = dot(normalize(d.xz + vec2(0.00001)), sun_flat) * 0.5 + 0.5;
	float band = exp(-abs(d.y) * 5.0);
	float pour = (0.18 + 0.82 * toward * toward * toward) * band;
	col = mix(col, glow_color, clamp(pour * 0.85 * glow_strength, 0.0, 1.0));
	col += glow_color * pow(max(sun_dot, 0.0), 6.0) * 0.2 * glow_strength * sun_visibility;

	float above = smoothstep(-0.015, 0.01, d.y);

	// --- Stars and moon (behind the clouds) -------------------------------
	float moon_dot = dot(d, moon_dir);
	if (!AT_CUBEMAP_PASS) {
		if (star_intensity > 0.003 && d.y > -0.02) {
			float horizon_fade = smoothstep(0.0, 0.25, d.y);
			col += star_field(d, TIME) * star_intensity * horizon_fade;
		}
		if (moon_visibility > 0.003 && moon_dot > 0.9) {
			vec3 mx = normalize(cross(vec3(0.0, 1.0, 0.0), moon_dir));
			vec3 my = cross(moon_dir, mx);
			vec2 q = vec2(dot(d, mx), dot(d, my)) / moon_radius;
			float r = length(q);
			if (r < 1.0) {
				vec3 n = vec3(q, sqrt(1.0 - r * r));
				float th = moon_phase * TAU;
				vec3 l = normalize(vec3(sin(th), 0.18, -cos(th)));
				float lit = smoothstep(-0.04, 0.12, dot(n, l));
				float blotch = texture(noise_tex, q * 0.16 + 0.37).a;
				float seas = smoothstep(0.45, 0.6, blotch) * 0.38;
				vec3 face = moon_color * (1.0 - seas) * (0.82 + 0.18 * n.z);
				vec3 body = mix(col + moon_color * 0.035, face * 1.35, lit);
				col = mix(col, body, smoothstep(1.0, 0.94, r) * moon_visibility * above);
			}
		}
	}
	// Soft glow around the moon, scaled by how much of it is lit.
	float moon_lit = 0.5 - 0.5 * cos(moon_phase * TAU);
	float moon_ang = acos(clamp(moon_dot, -1.0, 1.0));
	col += moon_color * moon_visibility * moon_lit * above
			* (0.22 * exp(-moon_ang * 14.0) + 0.05 * exp(-moon_ang * 3.5));

	// --- Sun --------------------------------------------------------------
	float sun_ang = acos(clamp(sun_dot, -1.0, 1.0));
	// The disc swells a little as it nears the horizon.
	float disc_r = sun_radius * (1.0 + 0.45 * (1.0 - smoothstep(0.0, 0.35, sun_dir.y)));
	float disc = smoothstep(disc_r, disc_r * 0.92, sun_ang) * above;
	vec3 sun_add = sun_halo_color * (0.5 * exp(-sun_ang * 18.0) + 0.09 * exp(-sun_ang * 5.0)) * above;
	if (!AT_CUBEMAP_PASS) {
		sun_add += sun_disc_color * disc * 4.5;
	}

	// --- Clouds -----------------------------------------------------------
	float cloud_alpha = 0.0;
	vec3 cloud_col = vec3(0.0);
	float cirrus = 0.0;
	if (d.y > 0.0) {
		vec2 p = d.xz / (d.y + HORIZON_BEND);
		float far = dot(p, p);
		float haze = 1.0 - exp(-far * 0.022);
		// The last quarter of cover closes every remaining gap.
		float thr = mix(0.84, 0.3, cloud_cover) - smoothstep(0.72, 1.0, cloud_cover) * 0.32;
		float n = AT_CUBEMAP_PASS ? cloud_field_coarse(p) : cloud_field(p);
		float alpha = smoothstep(thr, thr + 0.055, n);
		float thick = clamp((n - thr) / 0.26, 0.0, 1.0);

		// Directional light: compare with the field a step towards the light.
		vec2 l_flat = light_dir.xz / max(length(light_dir.xz), 0.001);
		float low_light = 1.0 - smoothstep(0.1, 0.8, light_dir.y);
		float n2 = AT_CUBEMAP_PASS ? n : cloud_field_coarse(p + l_flat * 0.16);
		float facing = (n - n2) * 3.2 * light_amount;
		// Seen from below, thin edges glow and thick middles are in shade.
		float b = 1.0 - thick * mix(0.75, 0.5, low_light) + facing * mix(0.35, 1.0, low_light);
		// Three flat tones with soft steps between them: the painterly part.
		float tone = 0.55 * smoothstep(0.32, 0.46, b) + 0.45 * smoothstep(0.62, 0.74, b);
		// A storm deck is mostly shade, with only thin pale seams.
		tone *= mix(1.0, 0.6, storm);
		vec3 c = mix(cloud_shade_color, cloud_lit_color, tone);
		// Heavy storm bases: the thick parts sink towards near-black.
		c *= mix(1.0, mix(1.0, 0.62, smoothstep(0.35, 1.0, thick)), storm);
		// Rim light on thin cloud around the sun or moon.
		float light_dot = max(dot(d, light_dir), 0.0);
		float rim = pow(light_dot, 10.0) * (1.0 - thick * 0.8) * light_amount;
		c += cloud_rim_color * rim * 0.9;
		// Lightning lights the cloud deck from inside, brightest towards the bolt.
		float to_flash = max(dot(normalize(d.xz + vec2(0.00001)), flash_dir.xz), 0.0);
		c += flash_color * flash * (0.16 + 1.2 * pow(to_flash, 3.0)) * (0.35 + 0.65 * n);

		cloud_alpha = alpha * (1.0 - haze * 0.92);
		cloud_col = c;

		// Cirrus: long thin streaks high above, only in fair weather.
		if (!AT_CUBEMAP_PASS) {
			vec2 cp = vec2(p.x * 0.8 + p.y * 0.6, p.y * 0.8 - p.x * 0.6);
			float wisp = texture(noise_tex, cp * vec2(0.1, 0.24) - scroll_cirrus).b;
			cirrus = smoothstep(0.6, 1.0, wisp) * (1.0 - haze) * 0.3
					* (1.0 - smoothstep(0.5, 0.95, cloud_cover));
		}
	}

	col = mix(col, mix(cloud_lit_color, col, 0.25) + cloud_rim_color * 0.1, cirrus);
	col += sun_add * sun_visibility * (1.0 - cloud_alpha * 0.93);
	col = mix(col, cloud_col, cloud_alpha);
	// A flash also lifts the whole sky a little.
	col += flash_color * flash * 0.06;

	if (!AT_CUBEMAP_PASS) {
		// Break up 8-bit banding in the smooth gradient.
		col += (hash12(FRAGCOORD.xy) - 0.5) * (1.5 / 255.0) * (col + 0.02);
	}
	COLOR = col;
}
