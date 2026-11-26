// The cloud field: where clouds are, how tall, and how stormy, as a function of
// world position. Shared by the sky shaders (which raymarch it) and the cloud
// shadow bake (which projects it onto the ground), so shadows on the sea line
// up with the clouds overhead. `src/sky/cloud_field.gd` is the CPU copy of
// cloud_column(); keep the two in step.
//
// Model: a 2D weather map says where cloud footprints are. Over each footprint
// the cloud is a dome with a flat base: the higher you go, the deeper inside
// the footprint you must be. A 3D noise volume of round puffs is subtracted
// from that "inside-ness", so tops and sides both break into cauliflower lumps.
// The result is a rough signed distance, which lets the sky march stride
// through empty air and land on surfaces. A storm cell lowers the base, raises
// a tower and spreads an anvil on top.

// cloud_map.png: R footprints, G large-scale variation, B tower height, A rain streaks.
uniform sampler2D cloud_map : repeat_enable, filter_linear_mipmap;
// cloud_volume.png: R billows, G fine puffs, B wisps, A big lumps.
uniform sampler3D cloud_volume : repeat_enable, filter_linear_mipmap;
// Wind drift of the whole field in metres (wrapped by Weather.CLOUD_WRAP).
uniform vec2 cloud_drift = vec2(0.0);
// Offset of the noise volume in tiles: billows boil and rise.
uniform vec3 cloud_churn = vec3(0.0);
// Fair-weather cloud amount and background storminess (behind the front).
uniform float cloudiness = 0.4;
uniform float storm_base = 0.0;
// Storm cell: centre xz, radius, intensity.
uniform vec4 storm_cell = vec4(0.0, 0.0, 1.0, 0.0);
// Weather front: direction xy (downwind), line position along it, 1 if active.
uniform vec4 front_line = vec4(0.0, -1.0, 0.0, 0.0);
uniform vec2 front_origin = vec2(0.0);
// Cloudiness and storminess ahead of the front.
uniform vec2 front_ahead = vec2(0.4, 0.0);

const float MAP_TILE = 12000.0;
const float BIG_TILE = 48000.0;
const float VOL_TILE = 2600.0;
const float CELL_CORE = 0.45;        // Weather.CELL_CORE
const float FRONT_WIDTH = 4500.0;    // Weather.FRONT_WIDTH
const float BASE_FAIR = 950.0;       // cloud base altitude in fair weather, metres
const float BASE_STORM = 380.0;      // and under a full storm
// Highest any fair-weather or overcast cloud top can reach; storm cells go higher.
const float TOP_LIMIT = 4200.0;

struct CloudColumn {
	float m;      // > 0 inside a cloud footprint; grows towards its middle
	float base;   // altitude of the flat base
	float height; // how tall the cloud is in the middle of a footprint
	float k;      // dome tightness: at relative height hn you need m > k * hn^2
	float storm;  // local storminess 0..1
	float cell;   // storm cell strength here 0..1 (shape times intensity)
	float relief; // metres of rolling relief on the base
};

// Metres of horizontal distance per unit of `m` (the map's typical slope).
const float M_SCALE = 1500.0;
// How much of `m` the puffs can eat: about 250 m of billow.
const float PUFF = 0.22;

// Altitude of the top of the storm cell's tower for a cell of this radius.
float cell_top(float radius) {
	return BASE_STORM + clamp(radius * 1.5, 1800.0, 5200.0);
}

// Local weather at a world position: x = cloudiness, y = storminess, z = cell strength.
vec3 weather_at(vec2 xz) {
	float cl = cloudiness;
	float st = storm_base;
	if (front_line.w > 0.5) {
		float along = dot(front_line.xy, xz - front_origin);
		float behind = 1.0 - smoothstep(front_line.z - FRONT_WIDTH, front_line.z + FRONT_WIDTH, along);
		cl = mix(front_ahead.x, cl, behind);
		st = mix(front_ahead.y, st, behind);
	}
	float cell = 0.0;
	if (storm_cell.w > 0.0) {
		float r = length(xz - storm_cell.xy) / storm_cell.z;
		cell = storm_cell.w * (1.0 - smoothstep(CELL_CORE, 1.0, r));
	}
	return vec3(cl, max(st, cell), cell);
}

CloudColumn cloud_column(vec2 xz) {
	vec2 q = xz - cloud_drift;
	// Explicit LOD 0 prevents divergent raymarch-loop quad derivative explosions on real GPUs.
	vec4 a = textureLod(cloud_map, q / MAP_TILE, 0.0);
	// A second, rotated, much larger read breaks up the tiling of the first.
	float big = textureLod(cloud_map, vec2(q.x * 0.8 + q.y * 0.6, q.y * 0.8 - q.x * 0.6) / BIG_TILE + 0.37, 0.0).g;
	vec3 w = weather_at(xz);
	float st = w.y;
	float cover = clamp(mix(w.x, 1.0, smoothstep(0.1, 0.7, st)), 0.0, 1.0);
	float f = a.r * 0.7 + big * 0.3;
	// The last stretch of cover closes every remaining gap.
	float thr = mix(0.95, 0.3, cover) - smoothstep(0.72, 1.0, cover) * 0.31;
	CloudColumn c;
	c.m = f - thr;
	c.storm = st;
	c.cell = w.z;
	float heavy = smoothstep(0.2, 0.9, st);
	c.base = mix(BASE_FAIR, BASE_STORM, heavy);
	// Fair weather: domes, taller where the map says so. More cloud and a
	// little storminess make them tower.
	float tower = clamp(0.2 + 0.9 * smoothstep(0.25, 0.75, w.x) + 2.0 * st, 0.0, 1.0);
	float h = 450.0 + 2500.0 * a.b * tower;
	// Overcast flattens into a deck with a lumpy top.
	float deck = smoothstep(0.7, 1.0, cover);
	h = mix(h, 700.0 + 900.0 * a.b, deck * (1.0 - 0.5 * heavy));
	// Storms pile it deep.
	h = mix(h, 900.0 + 900.0 * big, heavy);
	c.height = h;
	c.k = mix(0.22, 0.07, deck);
	c.relief = mix(25.0, 150.0, max(heavy, deck * 0.75));
	return c;
}

// The storm cell's cumulonimbus, in true metres: a tapering tower over the
// core, and an anvil lens spreading from its top, wider than the cell.
// Returns x = tower, y = anvil (they erode differently).
vec2 cell_sd(vec3 p) {
	float radius = storm_cell.z;
	float top = cell_top(radius);
	float r = length(p.xz - storm_cell.xy);
	float hn = clamp((p.y - BASE_STORM) / (top - BASE_STORM), 0.0, 1.0);
	// Wide at the base, a waist two thirds up, then flaring into the anvil.
	float waist = radius * mix(0.7, 0.4, smoothstep(0.0, 0.65, hn)) * storm_cell.w;
	float tower = min(min(waist - r, top - p.y), p.y - BASE_STORM);
	float rn = r / (radius * 1.35);
	float thick = (top - BASE_STORM) * 0.24 * (1.0 - rn * rn) * storm_cell.w;
	float anvil = min(p.y - (top - thick), top + thick * 0.35 - p.y);
	return vec2(tower, anvil);
}

// Rough signed distance in metres to the cloud surface at `p` (positive
// inside), given its column. `fine` adds a second octave of puffs.
float cloud_sd(vec3 p, CloudColumn c, bool fine) {
	vec2 parts = storm_cell.w > 0.0 ? cell_sd(p) : vec2(-1.0e5);
	float cell = max(parts.x, parts.y);
	float hn = max(p.y - c.base, 0.0) / c.height;
	// Inside-ness before the puffs are carved out: an upper bound, so anything
	// already outside needs no noise read at all.
	float e = c.m - c.k * hn * hn;
	float below = p.y - c.base;
	float d = min(e * M_SCALE, below);
	if (d < -c.relief * 2.5 && cell < 0.0) {
		return max(d, cell);
	}
	vec3 uvw = vec3(p.x - cloud_drift.x, p.y, p.z - cloud_drift.y) / VOL_TILE + cloud_churn;
	// Explicit LOD 0 avoids hardware 2x2 quad derivative spikes across divergent march steps.
	vec4 n = textureLod(cloud_volume, uvw, 0.0);
	float eat = 1.0 - n.r;
	if (fine) {
		float n2 = textureLod(cloud_volume, uvw * 3.3 + 0.31, 0.0).g;
		eat = eat * 0.78 + (1.0 - n2) * 0.22;
	}
	// Puffs bite hardest up the sides and top; the base stays flat in fair
	// weather and rolls under a storm.
	float bite = PUFF * (0.42 + 0.58 * smoothstep(0.0, 0.25, hn));
	// Under a storm the base rolls: slow swells from the big lumps, scud from the wisps.
	float roll = (n.b - 0.35) * 2.0 + (n.a - 0.5) * 3.0;
	float side_sd = (e - eat * bite) * M_SCALE;
	float base_sd = below - roll * c.relief;
	// Gently tuck hanging cloud bellies below `c.base` and smooth-blend the base crease
	// so distant cumulus flanks never terminate in a razor-sharp vertical clip edge.
	float hn_sub = max(-below, 0.0) / max(c.relief * 2.5, 90.0);
	side_sd -= (c.k * 0.45 * hn_sub * hn_sub) * M_SCALE;
	float h_blend = clamp(0.5 + 0.5 * (base_sd - side_sd) / 55.0, 0.0, 1.0);
	d = mix(base_sd, side_sd, h_blend) - 55.0 * h_blend * (1.0 - h_blend);
	if (cell > -900.0) {
		// The tower is built of turrets: one more read at a much larger scale.
		float turret = textureLod(cloud_volume, uvw * 0.31 + 0.17, 0.0).r;
		float lump = min(storm_cell.z * 0.24, 520.0);
		cell = max(parts.x - (1.0 - turret) * lump - eat * 60.0,
				parts.y - (1.0 - turret) * 130.0 - eat * 90.0);
	}
	return max(d, cell);
}

float cloud_density(float sd) {
	return clamp(sd / 70.0, 0.0, 1.0);
}

// Fraction of sunlight reaching the ground through the column above `xz`
// (1 = open sky). `floor_light` is what the thickest cloud lets through.
float column_light(CloudColumn c, float floor_light) {
	float thick = c.height * sqrt(clamp(c.m / c.k, 0.0, 1.0)) * 0.8;
	return mix(floor_light, 1.0, exp(-thick / 220.0));
}
