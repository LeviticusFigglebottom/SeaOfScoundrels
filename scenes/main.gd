extends Node3D
## Placeholder main scene: proves the wave include compiles and renders.
## Replaced by the real world scene as systems land.

func _ready() -> void:
	Net.start_single_player()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(400, 400)
	mesh.subdivide_width = 200
	mesh.subdivide_depth = 200
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/placeholder_ocean.gdshader")
	Sea.bind_material(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.extra_cull_margin = 10.0
	add_child(mi)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5, 20)
	cam.rotation_degrees = Vector3(-10, 0, 0)
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 40, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(env)
