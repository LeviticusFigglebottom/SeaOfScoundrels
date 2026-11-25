shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// One rain streak: a thin quad stretched along its fall direction by the
// particle system. Tinted by the sky so rain sits in the scene's light, and
// hidden inside shelter volumes (below deck, under a roof).
#include "res://src/sky/rain_shelter.gdshaderinc"

global uniform vec3 ambient_color;
uniform vec3 tint = vec3(0.4, 0.5, 0.5);
uniform float opacity = 0.4;
uniform float flash = 0.0;

varying float near_fade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Test the head and the foot of the streak: neither may poke into cover.
	vec3 along = normalize(MODEL_MATRIX[1].xyz) * 0.6;
	if (sheltered(origin) || sheltered(origin - along) || sheltered(origin - along * 3.0)) {
		VERTEX = vec3(0.0);
	}
	// Streaks right at the lens are distracting: let them fade.
	near_fade = smoothstep(0.6, 2.5, length(origin - CAMERA_POSITION_WORLD));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y);
	ALBEDO = mix(tint, ambient_color, 0.3) * 1.5 + vec3(0.05) + vec3(0.7, 0.8, 1.0) * flash;
	ALPHA = across * along * opacity * COLOR.a * near_fade;
}
