shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// The wall of rain under a storm cell: an open cylinder from the cloud base to
// the sea, so the storm reads as a place from far away, hides the islands
// behind it and closes around you when you sail in. sky_rig.gd sizes it to
// the cell. UV.x runs around the cylinder, UV.y from top (0) to sea (1).

uniform sampler2D streak_tex : repeat_enable, filter_linear_mipmap; // cloud_map.png, A = streaks
uniform vec3 tint = vec3(0.2, 0.25, 0.25);
uniform float opacity = 0.8;
uniform float around = 24.0;  // streak repeats around the wall
uniform float slant = 0.0;    // lean of the streaks with the wind
uniform float fall = 0.0;     // scroll, advanced by the rig
uniform float flash = 0.0;

void fragment() {
	vec2 uv = vec2(UV.x * around + UV.y * slant, UV.y * 0.55 - fall);
	float a = texture(streak_tex, uv).a;
	float b = texture(streak_tex, uv * vec2(0.37, 0.6) + vec2(0.31, fall * 0.4)).a;
	float streaks = clamp(0.5 + 1.5 * (a - 0.5) + 1.1 * (b - 0.5), 0.0, 1.0);
	// Seen edge-on the wall is thin; face-on you look through its full depth.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Dissolves into the cloud base above and into spray at the sea.
	float top = smoothstep(0.0, 0.16, UV.y);
	float foot = mix(0.75, 1.0, smoothstep(1.0, 0.8, UV.y));
	ALBEDO = tint + vec3(0.7, 0.8, 1.0) * flash * 0.25;
	ALPHA = opacity * top * foot * (0.5 + 0.5 * streaks) * smoothstep(0.0, 0.45, facing);
}
