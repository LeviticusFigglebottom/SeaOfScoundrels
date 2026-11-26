class_name UserSettings
extends RefCounted
## Persistent graphics quality, audio bus, accessibility, and keybinding settings.
## Stored as plain JSON at `user://settings.json` (same atomic-write pattern as Profile).

const DEFAULT_PATH := "user://settings.json"

var data: Dictionary = _defaults()


static func _defaults() -> Dictionary:
	return {
		"ocean_quality": 2,          # Ocean.Quality.HIGH (0=LOW, 1=MEDIUM, 2=HIGH)
		"cloud_quality": 1,          # SkyRig.CloudQuality.MEDIUM (0=LOW, 1=MEDIUM, 2=HIGH)
		"master_volume": 1.0,
		"music_volume": 0.85,
		"ambience_volume": 0.9,
		"sfx_volume": 1.0,
		"voice_volume": 1.0,
		"mouse_sensitivity": 0.0023,
		"fov": 80.0,
		"head_bob_enabled": true,
		"high_contrast_prompts": false,
		"subtitles_enabled": true,
		"keybinds": {},              # action_name -> physical_keycode int
	}


func save(path: String = DEFAULT_PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return DirAccess.get_open_error()
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file())


func load_from(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return false
	var merged := _defaults()
	for k in (json.data as Dictionary):
		merged[k] = (json.data as Dictionary)[k]
	data = merged
	return true


## Rebind a keyboard action dynamically at runtime and record it in `data["keybinds"]`.
func rebind_key(action: StringName, physical_keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	var to_remove: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			to_remove.append(ev)
	for ev in to_remove:
		InputMap.action_erase_event(action, ev)
	var kev := InputEventKey.new()
	kev.physical_keycode = physical_keycode
	InputMap.action_add_event(action, kev)
	var kb: Dictionary = data["keybinds"]
	kb[String(action)] = int(physical_keycode)
	return true


## Apply all loaded settings to Audio, Ocean, SkyRig, PlayerController, and InputMap.
func apply_all(scene_root: Node = null) -> void:
	Audio.set_bus_volume(Audio.BUS_MASTER, float(data["master_volume"]))
	Audio.set_bus_volume(Audio.BUS_MUSIC, float(data["music_volume"]))
	Audio.set_bus_volume(Audio.BUS_AMBIENCE, float(data["ambience_volume"]))
	Audio.set_bus_volume(Audio.BUS_SFX, float(data["sfx_volume"]))
	Audio.set_bus_volume(Audio.BUS_VOICE, float(data["voice_volume"]))

	var kb: Dictionary = data.get("keybinds", {})
	for action_str: String in kb:
		rebind_key(StringName(action_str), int(kb[action_str]) as Key)

	if Ocean.current != null:
		Ocean.current.quality = clampi(int(data["ocean_quality"]), 0, 2) as Ocean.Quality

	if scene_root == null:
		return
	for n in scene_root.find_children("*", "", true, false):
		if n.get(&"cloud_quality") != null and n.has_method(&"cloud_light_at"):
			n.set(&"cloud_quality", clampi(int(data["cloud_quality"]), 0, 2))
		elif n is PlayerController:
			var pc := n as PlayerController
			pc.mouse_sensitivity = float(data["mouse_sensitivity"])
			pc.fov = float(data["fov"])
			pc.bob_amount = 0.028 if bool(data["head_bob_enabled"]) else 0.0
			if pc.camera != null:
				pc.camera.fov = pc.fov
