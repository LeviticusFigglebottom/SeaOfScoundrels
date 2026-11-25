shader_type sky;
render_mode use_half_res_pass;
// Sky with medium-quality clouds. All the code is in sky_body.gdshaderinc.
#define CLOUD_QUALITY 1
#include "res://src/sky/sky_body.gdshaderinc"
