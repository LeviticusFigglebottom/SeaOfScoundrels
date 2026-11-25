shader_type spatial;
// Full-screen underwater pass, drawn before the ocean surface in the
// transparent pass. Fogs and tints everything seen through water, adds caustic
// light and sun shafts, and cuts a clean waterline when the lens straddles
// the surface (per-pixel test of the near plane against the shared wave set).
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://src/ocean/waves.gdshaderinc"
#include "res://src/ocean/ocean_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float waterline_active = 0.0; // 1 while the camera is close to the surface
uniform float caustic_strength = 0.9;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// world position of this pixel on the near plane
	vec4 nv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec3 near_world = (INV_VIEW_MATRIX * vec4(nv.xyz / nv.w, 1.0)).xyz;
	vec3 cam = CAMERA_POSITION_WORLD;

	float cover = 1.0;
	float meniscus = 0.0;
	if (waterline_active > 0.5) {
		float s = sea_height(near_world.xz) - near_world.y; // > 0: lens under water
		float w = max(fwidth(s), 1e-6);
		cover = clamp(s / w + 0.5, 0.0, 1.0);
		meniscus = smoothstep(7.0, 0.0, abs(s / w - 1.0));
	}
	if (cover <= 0.0 && meniscus <= 0.0) {
		discard;
	}

	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec3 scene_view = sp.xyz / sp.w;
	float dist = min(length(scene_view), 4000.0);
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	vec3 dir = normalize(scene_world - cam);
	vec3 L = normalize(sun_dir);
	float sun_up = max(L.y, 0.2);
	vec3 sun_light = ocean_sun_light();

	vec3 col = base;
	// caustics on submerged geometry
	float sdepth = max(-scene_world.y, 0.0);
	if (raw > 0.0) {
		float c = ocean_caustic(scene_world.xz + L.xz * (sdepth / sun_up));
		c *= exp(-sdepth * 0.10) * smoothstep(0.0, 0.4, sdepth) * smoothstep(60.0, 15.0, dist);
		col *= 1.0 + c * caustic_strength * (sun_light.g + 0.1) * smoothstep(0.0, 0.3, L.y);
	}
	col = uw_apply(col, dist, dir);

	col += uw_shafts(cam, dir, dist, FRAGCOORD.xy);

	// waterline: a thin dark-then-bright lip where the surface meets the lens
	col = mix(base, col, cover);
	col = mix(col, uw_ambient(vec3(0.0, 1.0, 0.0)) * 0.6, meniscus * 0.55);
	ALBEDO = col;
}
