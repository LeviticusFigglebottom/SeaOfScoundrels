extends Node
## Two-process netcode probe, driven by tools/test_net.sh.
##   -- role=host|client port=N
## Verifies host -> client replication of Sea clock, Weather, AND a live Ship sloop
## (position, sail_set, helm, and hull breach state).

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")

var role := "host"
var port := Net.DEFAULT_PORT
var t := 0.0
var ship: Ship


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("role="): role = a.trim_prefix("role=")
		if a.begins_with("port="): port = int(a.trim_prefix("port="))

	ship = SLOOP_SCENE.instantiate() as Ship
	ship.enable_effects = false
	add_child(ship)
	Net.register_replicated_ship(&"player_sloop", ship)

	if role == "host":
		Sea.time = 1234.5
		Weather.storminess = 0.7
		ship.global_position = Vector3(18.0, 0.2, -24.0)
		ship.set_sail_target(0.85)
		ship.sail_set = 0.85
		ship.set_helm_target(0.35)
		ship.helm = 0.35
		ship.apply_hull_damage(ship.global_transform * Vector3(2.0, -0.4, 0.4), 0.5)
		var err := Net.host(port)
		print("HOST listen err=", err)
	else:
		ship.global_position = Vector3.ZERO
		print("CLIENT join err=", Net.join("127.0.0.1", port))


func _physics_process(delta: float) -> void:
	t += delta
	if role == "host":
		if Engine.get_physics_frames() % 30 == 0:
			print("HOSTCLK %d %f ship=%s sail=%.2f holes=%d" % [
				Time.get_ticks_usec(), Sea.time, str(ship.global_position.snapped(Vector3.ONE * 0.1)),
				ship.sail_set, ship.open_hole_count()])
		if t > 9.0:
			get_tree().quit(0)
	else:
		if Engine.get_physics_frames() % 30 == 0:
			print("CLIENTCLK %f storm=%f host=%s ship=%s sail=%.2f holes=%d" % [
				Sea.time, Weather.storminess, Net.is_host(),
				str(ship.global_position.snapped(Vector3.ONE * 0.1)), ship.sail_set, ship.open_hole_count()])
		if t > 6.0:
			var ship_synced := ship.global_position.x > 8.0 and ship.sail_set > 0.7 \
				and ship.open_hole_count() >= 1
			var ok := Sea.time > 1234.5 and absf(Weather.storminess - 0.7) < 0.01 \
				and not Net.is_host() and ship_synced
			print("CLIENT RESULT ", "PASS" if ok else "FAIL", " sea_time=", Sea.time,
				" ship_pos=", ship.global_position, " sail=", ship.sail_set, " holes=", ship.open_hole_count())
			get_tree().quit(0 if ok else 1)
