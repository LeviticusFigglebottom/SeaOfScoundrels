class_name Profile
extends RefCounted
## Persistent captain profile: gold, renown, unlocks, ship loadout, discoveries.
## Plain data + JSON so saves are diffable and forward-compatible. Unknown keys
## in a file are preserved; missing keys take defaults.

const VERSION := 1
const DEFAULT_PATH := "user://profile.json"

var data: Dictionary = _defaults()

static func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		"captain_name": "Captain",
		"ship_name": "The Unsinkable Rumour",
		"gold": 0,
		"renown": {},        # company id -> points
		"unlocks": [],       # ids of fittings, cosmetics, tools
		"loadout": {},       # slot -> unlock id
		"crew": [],          # crew member records
		"discoveries": [],   # island / landmark ids
		"stats": {"voyages_completed": 0, "chests_sold": 0, "times_sunk": 0},
	}

func add_gold(amount: int) -> void:
	data["gold"] = maxi(0, int(data["gold"]) + amount)

func spend_gold(amount: int) -> bool:
	if int(data["gold"]) < amount:
		return false
	data["gold"] = int(data["gold"]) - amount
	return true

func add_renown(company: String, points: int) -> void:
	var r: Dictionary = data["renown"]
	r[company] = int(r.get(company, 0)) + points

func unlock(id: String) -> void:
	if not data["unlocks"].has(id):
		data["unlocks"].append(id)

func has_unlock(id: String) -> bool:
	return data["unlocks"].has(id)

func discover(id: String) -> bool:
	if data["discoveries"].has(id):
		return false
	data["discoveries"].append(id)
	return true

func bump_stat(key: String, by: int = 1) -> void:
	data["stats"][key] = int(data["stats"].get(key, 0)) + by

func save(path: String = DEFAULT_PATH) -> Error:
	# Write to a temp file then rename, so a crash never leaves a half-written save.
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
	var parsed: Variant = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		parsed = json.data
	if not parsed is Dictionary:
		push_warning("Profile at %s is corrupt; keeping defaults" % path)
		return false
	var merged := _defaults()
	_merge(merged, parsed)
	merged["version"] = VERSION
	data = merged
	return true

static func _merge(into: Dictionary, from: Dictionary) -> void:
	for k in from:
		if into.has(k) and into[k] is Dictionary and from[k] is Dictionary:
			_merge(into[k], from[k])
		else:
			into[k] = from[k]
