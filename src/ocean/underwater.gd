extends Node3D
## Underwater view for `Ocean`: a full-screen pass that fogs, tints and lights
## the scene while the camera lens is (partly) below the water surface. The
## surface seen from below (Snell's window) is drawn by ocean.gdshader itself;
## this pass is drawn first so the surface composites over it.

const SHADER := preload("res://src/ocean/underwater.gdshader")
const DETAIL_TEX := preload("res://assets/generated/ocean/water_detail.png")

## Show the pass while the camera is within this many metres above the surface.
const NEAR_SURFACE := 0.6

var material: ShaderMaterial
var _quad: MeshInstance3D

func setup(_ocean: Node3D) -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = -10  # before the ocean surface
	material.set_shader_parameter(&"detail_tex", DETAIL_TEX)
	Sea.bind_material(material)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_quad = MeshInstance3D.new()
	_quad.name = "ScreenPass"
	_quad.mesh = quad
	_quad.material_override = material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	_quad.visible = false
	add_child(_quad)

func set_shaft_steps(steps: int) -> void:
	material.set_shader_parameter(&"uw_shaft_steps", steps)

## Called by Ocean every frame. depth > 0 means the camera is under water.
func update(cam: Camera3D, depth: float) -> void:
	var on := depth > -NEAR_SURFACE
	_quad.visible = on
	if not on:
		return
	_quad.global_position = cam.global_position
	material.set_shader_parameter(&"uw_cam_depth", depth)
	material.set_shader_parameter(&"waterline_active", 1.0 if absf(depth) < NEAR_SURFACE else 0.0)
