shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Bakes the clouds' shadow on the ground into a small texture each frame
// (sky_rig.gd draws this into a SubViewport). Other shaders read it through
// cloud_shadow.gdshaderinc; the sky reads it for light shafts.
//   R  fraction of the key light reaching the ground here (1 = open sky)
//   G  1 where there is cloud straight overhead
//   B  local storminess
#include "res://src/sky/cloud_field.gdshaderinc"

uniform vec4 rect = vec4(0.0, 0.0, 16000.0, 0.0); // centre xz, size in metres
uniform vec2 shift = vec2(0.0);                    // ground metres per metre of height, towards the light
uniform float cast_height = 1100.0;                // altitude the shadow is cast from
uniform float floor_light = 0.22;                  // light left under the thickest cloud

void fragment() {
	vec2 xz = rect.xy + (UV - 0.5) * rect.z;
	CloudColumn lit = cloud_column(xz + shift * cast_height);
	CloudColumn above = cloud_column(xz);
	COLOR = vec4(column_light(lit, floor_light), step(0.0, above.m), above.storm, 1.0);
}
