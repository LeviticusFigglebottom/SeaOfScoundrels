// The whole sky. Included by sky_low / sky_medium / sky_high.gdshader, which
// only differ in CLOUD_QUALITY and in which reduced-resolution pass they ask for:
//   0 low     clouds marched in the quarter-res pass, 16 steps, 2 light samples
//   1 medium  clouds marched in the half-res pass,    32 steps, 3 light samples, light shafts
//   2 high    clouds marched at full resolution,      56 steps, 5 light samples, fine noise
// The reduced pass renders the "weather layer" (clouds, rain curtains, light
// shafts) premultiplied; the full-res pass draws gradient, stars, Milky Way,
// moon, sun and cirrus, then lays the weather layer over them.
// Every colour arrives from sky_rig.gd in linear space; sky_palette.gd is the
// colour script. Cost per pixel is written up in docs/ARCHITECTURE.md (Sky).

#include "cloud_field.gdshaderinc"

uniform vec3 zenith_color = vec3(0.01, 0.09, 0.6);
uniform vec3 mid_color = vec3(0.04, 0.22, 0.8);
uniform vec3 horizon_color = vec3(0.35, 0.65, 0.95);
uniform vec3 glow_color = vec3(0.05);
uniform float glow_strength = 0.0;
uniform vec3 sun_halo_color = vec3(1.0, 0.9, 0.7);

uniform vec3 sun_dir = vec3(0.3, 0.8, 0.3);
uniform vec3 sun_disc_color = vec3(1.0, 0.95, 0.85);
uniform float sun_radius = 0.034; // radians; the real sun is 0.0047
uniform float sun_visibility = 1.0;

uniform vec3 moon_dir = vec3(-0.3, 0.5, -0.3);
uniform vec3 moon_color = vec3(0.8, 0.88, 1.0);
uniform float moon_radius = 0.052;
uniform float moon_visibility = 0.0;

uniform float star_intensity = 0.0;
uniform mat3 star_basis = mat3(1.0);
// xyz = unit vector to the head of a shooting star, w = brightness (0 = none).
uniform vec4 meteor_head = vec4(0.0);
uniform vec3 meteor_tail = vec3(0.0, 1.0, 0.0);

// Tiled 2D noise from tools/textures/gen_sky_noise.py: B wisps (cirrus), A soft (moon, Milky Way).
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 cirrus_scroll = vec2(0.0);
uniform float cirrus_amount = 0.3;

uniform vec3 cloud_lit_color = vec3(1.0);
uniform vec3 cloud_shade_color = vec3(0.3, 0.4, 0.6);
uniform vec3 cloud_rim_color = vec3(1.0);
uniform vec3 storm_lit_color = vec3(0.2, 0.25, 0.24);
uniform vec3 storm_shade_color = vec3(0.03, 0.04, 0.04);
// Towards whichever body lights the clouds (sun by day, moon by night).
uniform vec3 light_dir = vec3(0.3, 0.8, 0.3);
// 0 while sun and moon swap as key light, so the cloud shading never flips.
uniform float light_amount = 1.0;
// Altitudes the march has to cover this frame.
uniform float slab_base = 760.0;
uniform float slab_top = 3600.0;
// Extinction per metre for cloud aerial perspective (a fraction of the fog density).
uniform float cloud_fog = 0.00005;

// Rain at the camera 0..1, and how far the streaks lean (wind).
uniform float storm = 0.0;
uniform float rain = 0.0;
uniform float rain_slant = 0.0;

uniform float flash = 0.0;
uniform vec3 flash_pos = vec3(0.0, 900.0, -1000.0);
uniform vec3 flash_color = vec3(0.6, 0.7, 1.0);

// Baked ground shadow of the clouds (see cloud_shadow.gdshaderinc), for light shafts.
uniform sampler2D shadow_map : repeat_disable, filter_linear;
uniform vec4 shadow_rect = vec4(0.0, 0.0, 0.0001, 0.0); // centre xz, 1 / size, unused
uniform vec2 shadow_shift = vec2(0.0); // ground metres per metre of height, towards the light
uniform float ray_strength = 0.0;

const float CURVE = 2.0e-6;     // 1 / (2 * 250 km): a small planet, so clouds sink behind the horizon
const float FAR = 27000.0;
const float SIGMA = 1.0 / 80.0;  // extinction per metre at full density: clouds are near solid

#if CLOUD_QUALITY == 0
const int STEPS = 16;
const int LIGHT_STEPS = 2;
const int RAY_STEPS = 0;
const bool FINE = false;
#elif CLOUD_QUALITY == 1
const int STEPS = 32;
const int LIGHT_STEPS = 3;
const int RAY_STEPS = 6;
const bool FINE = false;
#else
const int STEPS = 56;
const int LIGHT_STEPS = 5;
const int RAY_STEPS = 12;
const bool FINE = true;
#endif

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

// --- Background -------------------------------------------------------------

vec3 sky_gradient(vec3 d) {
	float up = max(d.y, 0.0);
	vec3 col = mix(horizon_color, mid_color, 1.0 - exp(-up * 6.0));
	col = mix(col, zenith_color, smoothstep(0.06, 0.8, up));
	// Below the horizon: hold the horizon colour so the sea's edge melts into it.
	col = mix(col, horizon_color * 0.8, smoothstep(0.0, -0.6, d.y));
	// Sunset or sunrise colour poured along the horizon, strongest towards the sun.
	vec2 sun_flat = normalize(sun_dir.xz + vec2(0.0001));
	float toward = dot(normalize(d.xz + vec2(0.00001)), sun_flat) * 0.5 + 0.5;
	float band = exp(-abs(d.y) * 6.5);
	float pour = (0.12 + 0.88 * toward * toward * toward) * band;
	col = mix(col, glow_color, clamp(pour * 0.9 * glow_strength, 0.0, 1.0));
	col += glow_color * pow(max(dot(d, sun_dir), 0.0), 6.0) * 0.2 * glow_strength * sun_visibility;
	return col;
}

vec3 star_field(vec3 sd, float time, float density) {
	vec3 p = sd * 85.0;
	vec3 cell = floor(p);
	float pick = hash13(cell);
	if (pick < 1.0 - density) {
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

// The Milky Way: a soft band around one great circle of the star sphere, with
// a dust lane down the middle. Returns x = glow, y = extra star density.
vec2 milky_way(vec3 sd) {
	const vec3 pole = vec3(0.42, 0.33, 0.845);
	float lat = dot(sd, pole);
	vec3 along = normalize(sd - pole * lat);
	vec3 ax = normalize(cross(pole, vec3(0.0, 1.0, 0.0)));
	vec3 ay = cross(pole, ax);
	float lon = atan(dot(along, ay), dot(along, ax));
	vec2 uv = vec2(lon / TAU * 3.0, lat * 0.5);
	float clumps = texture(noise_tex, uv).a;
	float dust = texture(noise_tex, uv * 1.7 + 0.43).a;
	float band = exp(-lat * lat * 26.0);
	float core = exp(-lat * lat * 110.0);
	float lane = smoothstep(0.45, 0.7, dust) * core;
	float glow = band * (0.35 + 0.9 * clumps * clumps) * (1.0 - 0.75 * lane);
	// Brightest towards one end, like the galactic centre.
	glow *= 0.55 + 0.45 * cos(lon - 0.6);
	return vec2(glow, band);
}

// Cirrus: thin streaks high above. They are laid out on an equal-angle map of
// the sky dome (distance from the zenith = angle), not on a flat plane: on a
// plane, parallel streaks race to a vanishing point and fan out like rays at a
// wide field of view; on this map they stay evenly spaced arcs to the horizon.
float cirrus_layer(vec3 d) {
	float zen = acos(clamp(d.y, -1.0, 1.0));
	vec2 p = d.xz / max(length(d.xz), 0.0001) * zen * 4.2;
	// A slow warp bends them into hooks.
	vec2 warp = texture(noise_tex, p * 0.05 + cirrus_scroll * 0.3).ag - 0.5;
	vec2 cp = vec2(p.x * 0.8 + p.y * 0.6, p.y * 0.8 - p.x * 0.6) + warp * 1.1;
	float wisp = texture(noise_tex, cp * vec2(0.085, 0.3) - cirrus_scroll).b;
	float patches = texture(noise_tex, cp * 0.055 + 0.21 - cirrus_scroll * 0.5).a;
	float c = smoothstep(0.6, 0.98, wisp) * smoothstep(0.45, 0.72, patches);
	return c * smoothstep(0.05, 0.3, d.y);
}

// --- Weather layer ----------------------------------------------------------

// Distance along the ray to altitude `h` on the curved world (h above the eye).
float to_altitude(float y0, float dy, float a, float h) {
	float rise = max(h - y0, 1.0);
	return 2.0 * rise / (dy + sqrt(dy * dy + 4.0 * a * rise));
}

float sample_sd(vec3 ro, vec3 rd, float t, float a, bool fine, out CloudColumn c, out vec3 p) {
	p = ro + rd * t;
	p.y += a * t * t;
	c = cloud_column(p.xz);
	return cloud_sd(p, c, fine);
}

// Sunlight reaching `p` through the cloud between it and the light, 0..1.
float light_march(vec3 p, int samples) {
	float tau = 0.0;
	float at = 0.0;
	float seg = 90.0;
	for (int k = 0; k < samples; k++) {
		at += seg;
		vec3 lp = p + light_dir * (at - seg * 0.4);
		CloudColumn lc = cloud_column(lp.xz);
		tau += cloud_density(cloud_sd(lp, lc, false)) * seg;
		seg *= 2.1;
	}
	return exp(-tau / 260.0);
}

// Clouds along a ray: premultiplied colour and alpha.
vec4 march_clouds(vec3 ro, vec3 rd, int steps, int light_steps, bool fine, vec3 haze) {
	float a = CURVE * (1.0 - rd.y * rd.y);
	float top = slab_top;
	if (storm_cell.w > 0.0) {
		// Only rays that pass over the storm cell need to climb its tower.
		vec2 oc = ro.xz - storm_cell.xy;
		float qa = max(dot(rd.xz, rd.xz), 0.00001);
		float qb = dot(oc, rd.xz);
		float r = storm_cell.z * 1.35;
		float disc = qb * qb - qa * (dot(oc, oc) - r * r);
		if (disc > 0.0 && sqrt(disc) - qb > 0.0) {
			top = max(top, cell_top(storm_cell.z) * 1.06);
		}
	}
	float t0 = to_altitude(ro.y, rd.y, a, slab_base);
	float t1 = min(to_altitude(ro.y, rd.y, a, top), FAR);
	if (rd.y < -0.05 || t0 >= t1) {
		return vec4(0.0);
	}
	float t = t0;
	float last_t = t0;
	float last_reach = 1.0e9;
	bool inside = false;
	int lit_left = 2;
	float trans = 1.0;
	float direct = 1.0;
	// Weighted sums over the visible cloud: light, height in cloud, storminess, flash, distance.
	float s_direct = 0.0;
	float s_height = 0.0;
	float s_storm = 0.0;
	float s_flash = 0.0;
	float s_dist = 0.0;
	float s_thick = 0.0;
	float s_belly = 0.0;
	float s_deck = 0.0;
	CloudColumn c;
	vec3 p;
	for (int i = 0; i < steps; i++) {
		if (t >= t1) {
			break;
		}
		float sd = sample_sd(ro, rd, t, a, fine, c, p);
		if (sd <= 0.0) {
			// Empty air: stride as far as the nearest surface allows, and at
			// least an even share of what is left so the ray always arrives.
			inside = false;
			last_t = t;
			last_reach = -sd * 0.7 + t * 0.003;
			// Close to a surface the forced share is cut, so grazing rays do
			// not hop over the thin top of a cloud.
			float share = (t1 - t) / float(steps - i);
			t += max(last_reach, share * (-sd < share ? 0.4 : 1.0));
			continue;
		}
		if (!inside) {
			inside = true;
			if (t - last_t > last_reach * 1.5) {
				// A forced long stride landed inside a cloud: bisect back to
				// its surface so silhouettes stay crisp and steady.
				float lo = last_t;
				float hi = t;
				for (int j = 0; j < 4; j++) {
					float mid = 0.5 * (lo + hi);
					CloudColumn mc;
					vec3 mp;
					if (sample_sd(ro, rd, mid, a, false, mc, mp) > 0.0) {
						hi = mid;
					} else {
						lo = mid;
					}
				}
				t = hi + 8.0;
				sd = sample_sd(ro, rd, t, a, fine, c, p);
			}
		}
		float dens = cloud_density(max(sd, 4.0));
		// Anything that belongs to the storm cell wears storm colours, tower and anvil included.
		float in_cell = 0.0;
		if (storm_cell.w > 0.0) {
			float rc = length(p.xz - storm_cell.xy) / (storm_cell.z * 1.4);
			in_cell = storm_cell.w * (1.0 - smoothstep(0.75, 1.0, rc));
		}
		float dt = clamp(t * 0.03, 80.0, 520.0);
		if (lit_left > 0) {
			lit_left -= 1;
			direct = light_steps > 0 ? light_march(p, light_steps) : 1.0;
		}
		float alpha = 1.0 - exp(-dens * dt * SIGMA);
		float w = trans * alpha;
		s_direct += w * direct;
		float hn = clamp((p.y - c.base) / c.height, 0.0, 1.0);
		if (in_cell > 0.0) {
			hn = mix(hn, clamp((p.y - BASE_STORM) / (cell_top(storm_cell.z) - BASE_STORM), 0.0, 1.0), in_cell);
		}
		s_height += w * hn;
		// How low this bit of the base hangs: bellies of the rolling deck are darker.
		s_belly += w * clamp((c.base + c.relief * 1.2 - p.y) / max(c.relief * 2.6, 1.0), 0.0, 1.0);
		s_storm += w * max(smoothstep(0.25, 0.85, c.storm), in_cell);
		vec3 to_flash = p - flash_pos;
		s_flash += w * exp(-dot(to_flash, to_flash) / 5.0e5) * (0.35 + 0.65 * dens);
		s_dist += w * t;
		s_deck += w * clamp((0.22 - c.k) / 0.15, 0.0, 1.0);
		s_thick += w * clamp(c.height * sqrt(clamp(c.m / c.k, 0.0, 1.0)) / 1500.0, 0.0, 1.0);
		trans *= 1.0 - alpha;
		t += dt;
		if (trans < 0.03) {
			break;
		}
	}
	float cover = 1.0 - trans;
	if (cover < 0.004) {
		return vec4(0.0);
	}
	float inv = 1.0 / cover;
	direct = s_direct * inv;
	float height = s_height * inv;
	float st = s_storm * inv;
	float dist = s_dist * inv;

	// Toon shading: three flat tones with soft steps between them.
	float tone = 0.5 * smoothstep(0.2, 0.34, direct) + 0.5 * smoothstep(0.58, 0.72, direct);
	// Flat bases sit in their own shade, one clean tone; the sun models the sides and tops.
	tone *= smoothstep(0.03, 0.3, height);
	tone *= light_amount;
	// A thunderhead is darkest at its base and catches more light up in the anvil.
	vec3 lit = mix(cloud_lit_color, storm_lit_color * (0.36 + 0.6 * smoothstep(0.45, 1.0, height) * (1.0 - storm) + 0.64 * storm), st);
	vec3 shade = mix(cloud_shade_color, storm_shade_color, st);
	vec3 col = mix(shade, lit, tone);
	col *= mix(0.86, 1.04, smoothstep(0.0, 0.9, height));
	// Seen from below, the deep middle of a base is a shade darker than its rim.
	float core = smoothstep(0.35, 0.6, s_thick * inv);
	col *= 1.0 - 0.14 * core * (1.0 - tone);
	// A storm deck is modelled by how it hangs: three tones from the high, pale
	// recesses down to the near-black bellies of the rolls.
	float belly = s_belly * inv;
	float hang = 0.5 * smoothstep(0.3, 0.4, belly) + 0.5 * smoothstep(0.55, 0.66, belly);
	col *= mix(1.0, mix(1.4, 0.64, hang), max(st, s_deck * inv * 0.8) * (1.0 - tone));
	// Silver lining: thin edges between the eye and the light glow.
	float vl = max(dot(rd, light_dir), 0.0);
	float thin = trans + (1.0 - trans) * direct * 0.35;
	col += cloud_rim_color * pow(vl, 7.0) * thin * 1.4 * light_amount * (1.0 - 0.8 * st);
	// Lightning lights the cloud from inside, around the bolt only.
	col += flash_color * flash * s_flash * inv * 1.8;

	// Aerial perspective: far clouds take the horizon's colour, then dissolve.
	// A storm seen from fair weather keeps its darkness: it is the subject.
	float fog = (1.0 - exp(-dist * cloud_fog)) * (1.0 - 0.6 * st * (1.0 - storm));
	col *= 1.0 - 0.3 * st * (1.0 - storm);
	col = mix(col, haze, fog);
	cover *= 1.0 - smoothstep(FAR * 0.72, FAR * 0.98, dist);
	return vec4(col * cover, cover);
}

// Rain all around the camera: opacity of a streaky veil that closes off the
// horizon. (A storm cell's own curtain is geometry: see rain_curtain.gdshader.)
float rain_veil(vec3 rd, float time) {
	float az = atan(rd.z, rd.x);
	float fall = time * 0.22;
	float streak = texture(cloud_map, vec2(az * 2.6 + rd.y * rain_slant, rd.y * 0.9 + fall)).a;
	float streak2 = texture(cloud_map, vec2(az * 0.9 - rd.y * rain_slant * 0.6, rd.y * 0.5 + fall * 0.6 + 0.4)).a;
	float streaks = 0.55 + 0.9 * (streak - 0.5) + 0.7 * (streak2 - 0.5);
	float veil = 0.0;
	// Around the camera: a streaky veil that closes off the horizon.
	if (rain > 0.0) {
		veil = rain * exp(-max(rd.y, 0.0) * 5.0) * 0.6 * streaks;
	}
	return clamp(veil, 0.0, 0.96);
}

// Light shafts: how much of the air along the ray (below the clouds) is sunlit.
float sun_shafts(vec3 ro, vec3 rd, vec2 frag) {
#if CLOUD_QUALITY == 0
	return 1.0;
#else
	float a = CURVE * (1.0 - rd.y * rd.y);
	float t_end = min(to_altitude(ro.y, rd.y, a, slab_base), 9000.0);
	float jitter = hash12(frag);
	float lit = 0.0;
	float total = 0.0;
	for (int i = 0; i < RAY_STEPS; i++) {
		float f = (float(i) + jitter) / float(RAY_STEPS);
		float t = t_end * f * f;
		vec3 p = ro + rd * t;
		vec2 uv = (p.xz - shadow_shift * p.y - shadow_rect.xy) * shadow_rect.z + 0.5;
		float w = f + 0.15;
		lit += texture(shadow_map, uv).r * w;
		total += w;
	}
	return lit / total;
#endif
}

vec4 weather_layer(vec3 ro, vec3 rd, vec2 frag, float time, bool cube) {
	vec3 flat_dir = normalize(vec3(rd.x, 0.015, rd.z));
	vec3 haze = sky_gradient(flat_dir);
	vec4 layer;
	if (cube) {
		layer = march_clouds(ro, rd, 10, 1, false, haze);
	} else {
		layer = march_clouds(ro, rd, STEPS, LIGHT_STEPS, FINE, haze);
	}
	if (rd.y < -0.05) {
		return layer;
	}
	// Rain between the eye and the clouds.
	float veil = rain_veil(rd, time);
	if (veil > 0.0) {
		vec3 rain_col = mix(haze, storm_shade_color, 0.4) + flash_color * flash * 0.04;
		layer = vec4(rain_col * veil, veil) + layer * (1.0 - veil);
	}
	// Shafts of light through gaps, brightest looking towards the sun.
	if (ray_strength > 0.0 && !cube) {
		float vl = max(dot(rd, light_dir), 0.0);
		float phase = 0.1 + 0.9 * pow(vl, 5.0);
		float lit = sun_shafts(ro, rd, frag);
		float low = exp(-max(rd.y, 0.0) * 3.0);
		layer.rgb += sun_halo_color * ray_strength * phase * low * (lit * lit - 0.35);
		layer.rgb = max(layer.rgb, vec3(0.0));
	}
	return layer;
}

// --- Main ---------------------------------------------------------------------

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 eye = POSITION;
	bool sub_pass = false;
#if CLOUD_QUALITY == 0
	sub_pass = AT_QUARTER_RES_PASS;
#elif CLOUD_QUALITY == 1
	sub_pass = AT_HALF_RES_PASS;
#endif
	if (sub_pass) {
		vec4 layer = weather_layer(eye, d, FRAGCOORD.xy, TIME, AT_CUBEMAP_PASS);
		COLOR = layer.rgb;
		ALPHA = layer.a;
	} else {
		vec3 col = sky_gradient(d);
		float above = smoothstep(-0.015, 0.01, d.y);

		// Stars, Milky Way, shooting star and moon (behind the clouds).
		float moon_dot = dot(d, moon_dir);
		float sun_moon = dot(sun_dir, moon_dir);
		float moon_lit = 0.5 - 0.5 * sun_moon;
		if (!AT_CUBEMAP_PASS) {
			if (star_intensity > 0.003 && d.y > -0.02) {
				float horizon_fade = smoothstep(0.0, 0.25, d.y);
				vec3 sd = star_basis * d;
				vec2 mw = milky_way(sd);
				vec3 stars = star_field(sd, TIME, 0.2 + 0.25 * mw.y);
				stars += star_field(sd * 1.9 + 4.0, TIME, 0.1 + 0.5 * mw.y) * (0.25 + 0.5 * mw.y);
				col += stars * star_intensity * horizon_fade;
				col += mix(vec3(0.16, 0.22, 0.42), vec3(0.42, 0.36, 0.38), mw.x) * mw.x * 0.16
						* star_intensity * horizon_fade;
				if (meteor_head.w > 0.0) {
					// Distance to the streak's segment on the unit sphere.
					vec3 seg = meteor_tail - meteor_head.xyz;
					float along = clamp(dot(d - meteor_head.xyz, seg) / dot(seg, seg), 0.0, 1.0);
					float off = length(d - (meteor_head.xyz + seg * along));
					float core = smoothstep(0.0028, 0.0004, off) * (1.0 - along) * (1.0 - along);
					col += vec3(0.85, 0.95, 1.0) * core * meteor_head.w * 3.0 * horizon_fade;
				}
			}
			if (moon_visibility > 0.003 && moon_dot > 0.9) {
				vec3 mx = normalize(cross(vec3(0.0, 1.0, 0.0), moon_dir));
				vec3 my = cross(moon_dir, mx);
				vec2 q = vec2(dot(d, mx), dot(d, my)) / moon_radius;
				float r = length(q);
				if (r < 1.0) {
					// The disc is a sphere lit by the real sun, so the terminator
					// always points at the sun and the phase follows the geometry.
					vec3 n = mx * q.x + my * q.y - moon_dir * sqrt(1.0 - r * r);
					float lit = smoothstep(-0.03, 0.1, dot(n, sun_dir));
					float blotch = texture(noise_tex, q * 0.16 + 0.37).a;
					float seas = smoothstep(0.45, 0.6, blotch) * 0.36;
					float limb = sqrt(1.0 - r * r);
					vec3 face = moon_color * (1.0 - seas) * (0.8 + 0.2 * limb);
					vec3 body = mix(col + moon_color * 0.03 * moon_visibility, face * 1.6, lit);
					col = mix(col, body, smoothstep(1.0, 0.95, r) * moon_visibility * above);
				}
			}
		}
		// Soft glow around the moon, scaled by how much of it is lit.
		float moon_ang = acos(clamp(moon_dot, -1.0, 1.0));
		vec3 moon_add = moon_color * moon_visibility * moon_lit * above
				* (0.2 * exp(-moon_ang * 14.0) + 0.045 * exp(-moon_ang * 3.5));

		// Sun: a crisp bright disc (it blooms and glitters on the sea) in a tight halo.
		float sun_dot = dot(d, sun_dir);
		float sun_ang = acos(clamp(sun_dot, -1.0, 1.0));
		// The disc swells a little as it nears the horizon.
		float disc_r = sun_radius * (1.0 + 0.4 * (1.0 - smoothstep(0.0, 0.35, sun_dir.y)));
		float disc = smoothstep(disc_r, disc_r * 0.9, sun_ang) * above;
		vec3 sun_add = sun_halo_color * (0.55 * exp(-sun_ang * 20.0) + 0.1 * exp(-sun_ang * 5.5)) * above;
		if (!AT_CUBEMAP_PASS) {
			float limb = 1.0 - 0.35 * smoothstep(0.3, 1.0, sun_ang / disc_r);
			sun_add += sun_disc_color * disc * limb * 6.0;
		}

		// Cirrus, high above everything else.
		float cirrus = 0.0;
		if (d.y > 0.0 && cirrus_amount > 0.0 && !AT_CUBEMAP_PASS) {
			cirrus = cirrus_layer(d) * cirrus_amount;
			float c_light = pow(max(sun_dot, 0.0), 4.0);
			vec3 c_col = mix(cloud_shade_color, cloud_lit_color, 0.8 * light_amount) + cloud_rim_color * c_light * 0.5;
			col = mix(col, c_col, cirrus);
		}
		col += moon_add * (1.0 - cirrus * 0.5);
		col += sun_add * sun_visibility * (1.0 - cirrus * 0.4);

		// The weather layer over everything.
		vec4 layer;
#if CLOUD_QUALITY == 0
		layer = QUARTER_RES_COLOR;
#elif CLOUD_QUALITY == 1
		layer = HALF_RES_COLOR;
#else
		layer = weather_layer(eye, d, FRAGCOORD.xy, TIME, AT_CUBEMAP_PASS);
#endif
		col = col * (1.0 - layer.a) + layer.rgb;

		if (!AT_CUBEMAP_PASS) {
			// Break up 8-bit banding in the smooth gradient.
			col += (hash12(FRAGCOORD.xy) - 0.5) * (1.5 / 255.0) * (col + 0.02);
		}
		COLOR = col;
	}
}
