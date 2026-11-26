class_name Profile
extends RefCounted
## Persistent captain profile: gold, renown, unlocks, ship loadout, discoveries.
## Plain data + JSON so saves are diffable and forward-compatible. Unknown keys
## in a file are preserved; missing keys take defaults.

signal changed

const VERSION := 1
const DEFAULT_PATH := "user://profile.json"
const DEFAULT_SHIP_NAME := "The Gilded Scoundrel"
const MAX_SHIP_NAME_LEN := 26
const PRESET_SHIP_NAMES: Array[String] = [
	"The Gilded Scoundrel",
	"Sovereign's Reckoning",
	"Emerald Cutlass",
	"Tidebreaker",
	"Salt-King's Folly",
	"Starlight Brigand",
	"Crimson Compass",
	"Abyssal Dawn",
]

var data: Dictionary = _defaults()

static func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		"captain_name": "Captain",
		"ship_name": DEFAULT_SHIP_NAME,
		"gold": 0,
		"renown": {},        # company id -> points
		"unlocks": [],       # ids of fittings, cosmetics, tools
		"loadout": {},       # slot -> unlock id
		"crew": [],          # crew member records
		"discoveries": [],   # island / landmark ids
		"stats": {
			"voyages_completed": 0,
			"chests_sold": 0,
			"times_sunk": 0,
			"gold_earned": 0,
			"bosses_defeated": 0,
		},
	}

static func sanitize_ship_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code <= 126:
			out += char(code)
	out = out.strip_edges()
	if out.length() > MAX_SHIP_NAME_LEN:
		out = out.substr(0, MAX_SHIP_NAME_LEN).strip_edges()
	if out.is_empty():
		return DEFAULT_SHIP_NAME
	return out

func get_ship_name() -> String:
	return sanitize_ship_name(String(data.get("ship_name", DEFAULT_SHIP_NAME)))

func set_ship_name(new_name: String) -> String:
	var clean := sanitize_ship_name(new_name)
	data["ship_name"] = clean
	changed.emit()
	return clean

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
	var stats := _ensure_stats_dict()
	stats[key] = int(stats.get(key, 0)) + by


func record_voyage_completed() -> void:
	bump_stat("voyages_completed", 1)
	changed.emit()


func record_chest_sold(gold_delta: int = 0) -> void:
	bump_stat("chests_sold", 1)
	if gold_delta > 0:
		bump_stat("gold_earned", gold_delta)
	changed.emit()


func record_boss_defeated() -> void:
	bump_stat("bosses_defeated", 1)
	changed.emit()


func get_stats() -> Dictionary:
	var stats := _ensure_stats_dict()
	var out := stats.duplicate()
	for k: String in ["voyages_completed", "chests_sold", "times_sunk", "gold_earned", "bosses_defeated"]:
		out[k] = int(stats.get(k, 0))
	return out


func get_discovery_count() -> int:
	var disc: Variant = data.get("discoveries", [])
	return (disc as Array).size() if disc is Array else 0


func _ensure_stats_dict() -> Dictionary:
	var raw: Variant = data.get("stats", null)
	if not (raw is Dictionary):
		raw = {}
		data["stats"] = raw
	var stats := raw as Dictionary
	for k: String in ["voyages_completed", "chests_sold", "times_sunk", "gold_earned", "bosses_defeated"]:
		if not stats.has(k):
			stats[k] = 0
	return stats

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

func save_to(path: String = DEFAULT_PATH) -> Error:
	return save(path)

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
