shader_type sky;
render_mode use_quarter_res_pass;
// Sky with low-quality clouds. All the code is in sky_body.gdshaderinc.
#define CLOUD_QUALITY 0
#include "res://src/sky/sky_body.gdshaderinc"
