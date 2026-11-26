extends Node3D
## Self-contained island & archipelago showcase using the real Ocean, SkyRig,
## 11-island Archipelago (Port Scoundrel, Cutlass Cay & horizon landmarks),
## and a moored Sloop at Port Scoundrel's pier.
##
##   tools/capture.sh res://scenes/showcase/island_showcase.tscn outpost 2 5 -- shot=outpost
##
## User args (after `--`), all optional:
##   shot=outpost|treasure|horizon|beach|sunset|aerial   (default outpost)
##   time=<hour>       hour of day (default 10.4, sunset shot defaults to 17.95)
##   storm=<0..1>      storminess (default 0.0)
##   cloud=<0..1>      cloudiness (default 0.36)
##   quality=low|medium|high   Ocean & cloud quality (default medium sky / high ocean)
##   scale=<0.25..1>   3D render scale
##   clock=<seconds>   starting pan clock
##   ship=0|1          moor a sloop beside Port Scoundrel pier (default 1)

const SLOOP_SCENE: PackedScene = preload("res://src/ship/sloop.tscn")

var _args: Dictionary = {}
var _shot: String = "outpost"
var _clock: float = 0.0
var _cam: Camera3D = null
var _archipelago: Archipelago = null
var _outpost: Outpost = null
var _cutlass: Island = null
var _sloop: Ship = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_shot = String(_args.get("shot", "outpost"))
	_clock = float(_args.get("clock", "0.0"))

	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.clear_storm_cell()

	var default_time := 17.95 if _shot == "sunset" else 10.4
	var default_cloud := 0.44 if _shot == "sunset" else 0.36
	Weather.time_of_day = float(_args.get("time", str(default_time)))
	var storm := float(_args.get("storm", "0.0"))
	var cloud := float(_args.get("cloud", str(default_cloud)))
	Weather.set_weather(storm, 8.5, deg_to_rad(32.0), 0.0, cloud)
	Weather.cloud_offset = Vector2(260.0, 140.0)

	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	if _shot == "beach":
		Sea.amp_scale = 0.45
	Sea.time = float(_args.get("t", "36.0"))

	# Configure real SkyRig and real Ocean.
	var sky_rig := get_node_or_null(^"SkyRig")
	if sky_rig != null:
		var q_str := String(_args.get("quality", "medium"))
		sky_rig.set(&"cloud_quality", {"low": 0, "medium": 1, "high": 2}.get(q_str, 1))
		sky_rig.set(&"shadow_distance", 280.0)

	var ocean := get_node_or_null(^"Ocean") as Ocean
	if ocean != null:
		var oq_str := String(_args.get("quality", "high"))
		ocean.quality = {"low": Ocean.Quality.LOW, "medium": Ocean.Quality.MEDIUM}.get(oq_str, Ocean.Quality.HIGH)

	# Build the full deterministic 11-island archipelago so horizon silhouettes are live.
	_archipelago = Archipelago.new()
	_archipelago.name = "Archipelago"
	add_child(_archipelago)
	_outpost = _archipelago.get_outpost(0)
	_cutlass = _archipelago.get_starter_treasure_island()

	# Moor a real Sloop cleanly beside Port Scoundrel's dock pier for scale & harbour charm.
	if String(_args.get("ship", "1")) != "0" and _outpost != null:
		_sloop = SLOOP_SCENE.instantiate() as Ship
		_sloop.name = "MooredSloop"
		_sloop.start_anchored = true
		add_child(_sloop)
		_sloop.global_transform = _outpost.get_world_mooring_transform()
		_sloop.freeze = true

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.12
	_cam.far = 4500.0
	add_child(_cam)
	_cam.make_current()

	if _args.has("scale"):
		get_viewport().scaling_3d_scale = float(_args["scale"])

	_update_camera()
	Weather.set_focus(_cam.global_position)


func _process(delta: float) -> void:
	_clock += delta
	_update_camera()


func _update_camera() -> void:
	if _cam == null or _outpost == null or _cutlass == null:
		return

	var op_pos := _outpost.global_position
	var op_basis := Basis(Vector3.UP, _outpost.dock_yaw)
	var cc_pos := _cutlass.global_position
	var cc_basis := Basis(Vector3.UP, 2.77)

	match _shot:
		"outpost":
			# Dramatic 3/4 maritime approach to Port Scoundrel: dock, sloop, stall, tavern, beacon & peaks.
			var pan := sin(_clock * 0.35) * 6.0
			var eye := op_pos + op_basis * Vector3(-24.0 + pan, 14.5, -72.0)
			var aim := op_pos + op_basis * Vector3(5.0, 9.0, -10.0)
			_cam.look_at_from_position(eye, aim)

		"treasure":
			# Hero beauty shot of Cutlass Cay: turquoise shallows, golden cove, palms, dig site & twin spires.
			var pan := sin(_clock * 0.35) * 7.0
			var eye := cc_pos + cc_basis * Vector3(-22.0 + pan, 17.0, -88.0)
			var aim := cc_pos + cc_basis * Vector3(2.0, 18.0, 4.0)
			_cam.look_at_from_position(eye, aim)

		"horizon":
			# Deck-height vista off Port Scoundrel pier looking NNE across open swell to horizon silhouettes.
			var sway := sin(_clock * 0.6) * 0.55
			var eye := op_pos + op_basis * Vector3(1.5, 4.4 + sway * 0.25, -48.0)
			var aim := cc_pos + Vector3(0.0, 14.0, 0.0)
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"beach":
			# Low beach walk along Cutlass Cay's golden shore past wet sand, swaying palms & DigSite.
			var site_pos := cc_pos + (_cutlass.dig_points[0] if not _cutlass.dig_points.is_empty() else Vector3(0.0, 2.0, 26.0))
			var eye := site_pos + cc_basis * Vector3(-12.0 + _clock * 1.4, 2.3, -10.5)
			eye.y = maxf(2.2, _cutlass.world_surface_height(eye) + 1.85)
			var aim := site_pos + Vector3(0.0, 3.2, 0.0)
			_cam.look_at_from_position(eye, aim)

		"sunset":
			# Golden-hour dusk across Port Scoundrel harbour with glowing tavern, lanterns & beacon tower.
			var pan := sin(_clock * 0.3) * 5.0
			var eye := op_pos + op_basis * Vector3(-18.0 + pan, 10.5, -62.0)
			var aim := op_pos + op_basis * Vector3(6.5, 11.5, -10.0)
			_cam.look_at_from_position(eye, aim)

		"aerial":
			# High sweeping aerial overview of Port Scoundrel, turquoise shallows & sailing channel to Cutlass Cay.
			var drift := _clock * 6.0
			var eye := op_pos + op_basis * Vector3(-55.0 + drift, 108.0, 82.0)
			var aim := op_pos + op_basis * Vector3(12.0, 4.0, -52.0)
			_cam.fov = 58.0
			_cam.look_at_from_position(eye, aim)

		_:
			var eye := op_pos + op_basis * Vector3(-24.0, 14.5, -72.0)
			var aim := op_pos + op_basis * Vector3(5.0, 9.0, -10.0)
			_cam.look_at_from_position(eye, aim)
