extends Node
## Two-process netcode probe, driven by tools/test_net.sh.
##   -- role=host|client port=N
## Host runs a session and prints its clock; client joins and prints the error.

var role := "host"
var port := Net.DEFAULT_PORT
var t := 0.0
var samples: Array[float] = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("role="): role = a.trim_prefix("role=")
		if a.begins_with("port="): port = int(a.trim_prefix("port="))
	if role == "host":
		Sea.time = 1234.5
		Weather.storminess = 0.7
		var err := Net.host(port)
		print("HOST listen err=", err)
	else:
		print("CLIENT join err=", Net.join("127.0.0.1", port))

func _physics_process(delta: float) -> void:
	t += delta
	if role == "host":
		# Print wall-clock-tagged sea time so the client log can be compared.
		if Engine.get_physics_frames() % 30 == 0:
			print("HOSTCLK %d %f" % [Time.get_ticks_usec(), Sea.time])
		if t > 9.0:
			get_tree().quit(0)
	else:
		if Engine.get_physics_frames() % 30 == 0:
			print("CLIENTCLK %f storm=%f host=%s" % [Sea.time, Weather.storminess, Net.is_host()])
		if t > 6.0:
			var ok := Sea.time > 1234.5 and absf(Weather.storminess - 0.7) < 0.01 and not Net.is_host()
			print("CLIENT RESULT ", "PASS" if ok else "FAIL", " sea_time=", Sea.time)
			get_tree().quit(0 if ok else 1)
