// Cloud shadows for any spatial shader. Include it and multiply sunlight by it:
//
//   #include "res://src/sky/cloud_shadow.gdshaderinc"
//   void light() {  // or wherever you use the `sun_color` global
//       float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(world_pos.xz) : 1.0;
//       DIFFUSE_LIGHT += ... * sun;
//   }
//
// The sky rig bakes the clouds' ground shadow around the camera every frame.
// It also dims the sun (the DirectionalLight3D and the `sun_color` global) by
// the shadow at the camera, so standard materials darken when a cloud passes
// over. Because of that there are two functions:
//   cloud_shadow(world_xz)  absolute: 1 in open sun, about 0.2 under thick cloud.
//                           Use it for things that do not go through the light
//                           (foam sparkle, glints you gate by hand).
//   cloud_light(world_xz)   relative to the dimming already in the light:
//                           multiply DirectionalLight terms or `sun_color` by it.
global uniform sampler2D cloud_shadow_tex : repeat_disable, filter_linear;
// xy = centre of the baked square (world xz), z = 1 / its size in metres,
// w = shadow at the camera (already applied to the sun light and sun_color).
global uniform vec4 cloud_shadow_params;

float cloud_shadow(vec2 world_xz) {
	vec2 uv = (world_xz - cloud_shadow_params.xy) * cloud_shadow_params.z + 0.5;
	// Past the baked square, fall back to the value at the camera.
	vec2 e = smoothstep(vec2(0.5), vec2(0.44), abs(uv - 0.5));
	return mix(cloud_shadow_params.w, texture(cloud_shadow_tex, uv).r, e.x * e.y);
}

float cloud_light(vec2 world_xz) {
	return cloud_shadow(world_xz) / max(cloud_shadow_params.w, 0.05);
}
