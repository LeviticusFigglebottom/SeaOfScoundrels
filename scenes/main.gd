extends Node3D
## Main scene. Interim: the real ocean under the real sky with a free camera
## position, until ship, crew and world are integrated.

func _ready() -> void:
	Net.start_single_player()
	add_child(load("res://src/sky/sky_rig.tscn").instantiate())
	add_child(load("res://src/ocean/ocean.tscn").instantiate())
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 0)
	cam.rotation_degrees = Vector3(-4, 30, 0)
	cam.far = 8000.0
	add_child(cam)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("time="):
			Weather.time_of_day = float(a.trim_prefix("time="))
		if a.begins_with("storm="):
			Weather.storminess = float(a.trim_prefix("storm="))
			Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, Weather.storminess)
