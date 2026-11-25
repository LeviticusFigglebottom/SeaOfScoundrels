// Shelter from the rain. sky_rig.gd passes the nearest boxes flagged by an
// Area3D in group `shelter`; particle shaders hide anything inside one.
uniform int shelter_count = 0;
uniform mat4 shelter_inv[4];  // world -> box space
uniform vec3 shelter_half[4]; // half extents

bool sheltered(vec3 world_pos) {
	for (int i = 0; i < shelter_count; i++) {
		vec3 l = abs((shelter_inv[i] * vec4(world_pos, 1.0)).xyz);
		if (l.x < shelter_half[i].x && l.y < shelter_half[i].y && l.z < shelter_half[i].z) {
			return true;
		}
	}
	return false;
}
