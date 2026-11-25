shader_type spatial;
// Showcase stand-in for the ocean and island shaders: a plain lit surface that
// takes cloud shadows the way real ones should (see cloud_shadow.gdshaderinc).
#include "res://src/sky/cloud_shadow.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.3, 0.4, 0.3);
uniform float roughness = 0.8;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}

void light() {
	// Only the sun (or moon) is shadowed by clouds; lanterns are not.
	float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(world_pos.xz) : 1.0;
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR * sun / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float spec = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(180.0, 8.0, roughness)) * (1.0 - roughness);
	SPECULAR_LIGHT += spec * ndl * ATTENUATION * LIGHT_COLOR * sun;
}
