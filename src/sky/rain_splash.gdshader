shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;
// Where a raindrop hits the sea: a ring that opens and fades, lying on the
// water. With `follow_sea` it rides the same Gerstner surface as the ocean
// (register the material with Sea.bind_material()).
#include "res://src/ocean/waves.gdshaderinc"
#include "res://src/sky/rain_shelter.gdshaderinc"

uniform vec3 tint = vec3(0.4, 0.5, 0.5);
uniform float opacity = 0.5;
uniform float flash = 0.0;
uniform float follow_sea = 1.0;

varying float phase;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	phase = INSTANCE_CUSTOM.y;
	vec2 local = (UV - 0.5) * size * 0.34 * (0.3 + 0.7 * phase);
	float y = follow_sea > 0.5 ? sea_height(origin.xz) : 0.0;
	VERTEX = vec3(origin.x + local.x, y + 0.04, origin.z + local.y);
	if (sheltered(vec3(origin.x, y + 0.2, origin.z))) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.5, 0.8, r) * smoothstep(1.0, 0.86, r) * 0.6;
	float dot_ = smoothstep(0.35, 0.0, r) * (1.0 - phase) * (1.0 - phase);
	ALBEDO = tint * 1.5 + vec3(0.22) + vec3(0.6, 0.7, 0.9) * flash;
	ALPHA = (ring * (1.0 - phase) + dot_) * opacity;
}
