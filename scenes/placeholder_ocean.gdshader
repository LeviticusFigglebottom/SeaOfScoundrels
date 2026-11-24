shader_type spatial;
#include "res://src/ocean/waves.gdshaderinc"
varying float jac;
void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	VERTEX += sea_displacement(p);
	vec3 n;
	float j;
	sea_normal_jacobian(p, n, j);
	jac = j;
	NORMAL = n;
}
void fragment() {
	ALBEDO = mix(vec3(0.02, 0.25, 0.35), vec3(1.0), smoothstep(0.55, 0.3, jac));
	ROUGHNESS = 0.15;
}
