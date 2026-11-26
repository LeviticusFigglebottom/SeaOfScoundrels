class_name SessionConfig
extends RefCounted
## Structured launch configuration for a Sea of Scoundrels play session.
##
## Carries game mode (Adventure, Maiden Voyage Tutorial, High-Seas Naval Skirmish,
## or Co-op Crew), ship class & vessel name, starting outpost, AI crew roster,
## time of day, weather, difficulty scaling, starting Trading Company Emissary
## flag, and Co-op Host/Join networking parameters.

const MODE_ADVENTURE := &"adventure"
const MODE_TUTORIAL := &"tutorial"
const MODE_SKIRMISH := &"skirmish"
const MODE_COOP := &"coop"

const VALID_MODES: Array[StringName] = [
	MODE_ADVENTURE,
	MODE_TUTORIAL,
	MODE_SKIRMISH,
	MODE_COOP,
]

const MODE_SPECS: Array[Dictionary] = [
	{
		"id": MODE_ADVENTURE,
		"label": "Open-Seas Adventure",
		"short": "Adventure",
		"desc": "Full 14-island archipelago, Trading Company voyages, Salt-King's Ledger story campaign, world events & Emissary Grades.",
	},
	{
		"id": MODE_TUTORIAL,
		"label": "Maiden Voyage (Tutorial)",
		"short": "Tutorial",
		"desc": "Guided 8-step interactive pirate tutorial from Port Scoundrel to Cutlass Cay.",
	},
	{
		"id": MODE_SKIRMISH,
		"label": "High-Seas Naval Skirmish",
		"short": "Naval Skirmish",
		"desc": "Instant open-sea naval combat waves escalating to the Abyssal Leviathan.",
	},
	{
		"id": MODE_COOP,
		"label": "Co-op Crew",
		"short": "Co-op Crew",
		"desc": "Host a LAN/Direct-IP crew server or join a friend's ship across the archipelago.",
	},
]

const OUTPOST_SPECS: Array[Dictionary] = [
	{
		"id": &"port_scoundrel",
		"name": "Port Scoundrel",
		"region": "Central Harbour",
		"desc": "Balanced starter harbour near Cutlass Cay and Gull's Arch.",
	},
	{
		"id": &"barnacle_haven",
		"name": "Barnacle Haven",
		"region": "Eastern Shoals",
		"desc": "Cliff-catwalk smuggling haven near Skull Bluff and Cinder Crag.",
	},
	{
		"id": &"galleons_reach",
		"name": "Galleon's Reach",
		"region": "Northern Fjord Capital",
		"desc": "Grand timber capital facing Sovereign's Bastion and Emerald Spire.",
	},
]

const SHIP_SPECS: Array[Dictionary] = [
	{
		"id": &"sloop",
		"name": "Sloop",
		"crew_rec": "1-2 Crew",
		"cannons": 2,
		"desc": "Nimble single-masted cutter. +30% headwind king, effortless solo handling.",
	},
	{
		"id": &"brigantine",
		"name": "Brigantine",
		"crew_rec": "2-4 Crew",
		"cannons": 4,
		"desc": "Twin-masted war cruiser. Fastest downwind speed, 4 cannons, grand stern cabin.",
	},
]

const CREW_PRESETS: Array[Dictionary] = [
	{
		"count": 0,
		"name": "Solo Captain",
		"short": "Solo (0)",
		"desc": "Sail alone - pure captain challenge",
		"personas": [],
	},
	{
		"count": 1,
		"name": "Duo (Barnaby)",
		"short": "Duo (1)",
		"desc": "Veteran helmsman Barnaby keeps sails trimmed",
		"personas": [&"helmsman"],
	},
	{
		"count": 2,
		"name": "Trio (Barnaby & Maren)",
		"short": "Trio (2)",
		"desc": "Helmsman + keen-eyed lookout/gunner Maren",
		"personas": [&"helmsman", &"lookout"],
	},
	{
		"count": 3,
		"name": "Full Crew (All 3)",
		"short": "Full Crew (3)",
		"desc": "Barnaby, Maren & carpenter Pip patch, bail & fight",
		"personas": [&"helmsman", &"lookout", &"carpenter"],
	},
]

const TIME_PRESETS: Array[Dictionary] = [
	{"id": &"dawn", "name": "Golden Dawn", "short": "Dawn", "time": 6.35},
	{"id": &"morning", "name": "Fair Morning", "short": "Morning", "time": 10.2},
	{"id": &"sunset", "name": "Crimson Sunset", "short": "Sunset", "time": 17.65},
	{"id": &"night", "name": "Starlit Night", "short": "Night", "time": 22.4},
]

const WEATHER_PRESETS: Array[Dictionary] = [
	{"id": &"fair", "name": "Fair Trade Winds", "short": "Fair", "storm": 0.06, "wind": 9.0, "cloud": 0.36},
	{"id": &"choppy", "name": "Choppy Swells", "short": "Choppy", "storm": 0.36, "wind": 13.5, "cloud": 0.62},
	{"id": &"storm", "name": "Looming Squall", "short": "Squall", "storm": 0.78, "wind": 18.5, "cloud": 0.90},
]

const DIFFICULTY_PRESETS: Array[Dictionary] = [
	{"id": &"relaxed", "name": "Relaxed Seas", "short": "Relaxed", "enemy_scale": 0.72, "payout_scale": 0.90},
	{"id": &"standard", "name": "Scoundrel Standard", "short": "Standard", "enemy_scale": 1.0, "payout_scale": 1.0},
	{"id": &"cursed", "name": "Cursed Waters", "short": "Cursed", "enemy_scale": 1.35, "payout_scale": 1.25},
]

const EMISSARY_PRESETS: Array[Dictionary] = [
	{"id": &"", "name": "No Emissary Flag", "short": "None"},
	{"id": &"gilded_compass", "name": "Gilded Compass", "short": "Compass"},
	{"id": &"sunken_archive", "name": "Sunken Archive", "short": "Archive"},
	{"id": &"iron_tide", "name": "Iron Tide", "short": "Iron Tide"},
]

const MIN_COOP_PORT := 1024
const MAX_COOP_PORT := 65535

var mode: StringName = MODE_ADVENTURE
var ship_class: StringName = &"sloop"
var ship_name: String = Profile.DEFAULT_SHIP_NAME
var spawn_outpost_id: StringName = &"port_scoundrel"
var crew_count: int = 3
var time_preset: StringName = &"morning"
var weather_preset: StringName = &"fair"
var difficulty: StringName = &"standard"
var starting_emissary: StringName = &""
var coop_role: StringName = &"host"
var coop_address: String = "127.0.0.1"
var coop_port: int = Net.DEFAULT_PORT


## Return the ordered AI crewmate personas for the selected `crew_count` (0..3).
func get_crew_personas() -> Array[StringName]:
	var idx := clampi(crew_count, 0, CREW_PRESETS.size() - 1)
	var raw: Variant = CREW_PRESETS[idx].get("personas", [])
	var out: Array[StringName] = []
	if raw is Array:
		for item in (raw as Array):
			out.append(StringName(item))
	return out


## Return a copy of the active crew preset metadata dictionary.
func get_crew_preset() -> Dictionary:
	var idx := clampi(crew_count, 0, CREW_PRESETS.size() - 1)
	return CREW_PRESETS[idx].duplicate(true)


## Return the starting time of day (in 24h hours) for `time_preset`.
func get_time_of_day() -> float:
	for entry in TIME_PRESETS:
		if entry["id"] == time_preset:
			return float(entry["time"])
	return 10.2


## Return `{"storm": float, "wind": float, "cloud": float}` for `weather_preset`.
func get_weather_params() -> Dictionary:
	for entry in WEATHER_PRESETS:
		if entry["id"] == weather_preset:
			return {
				"storm": float(entry["storm"]),
				"wind": float(entry["wind"]),
				"cloud": float(entry["cloud"]),
			}
	return {"storm": 0.06, "wind": 9.0, "cloud": 0.36}


## Return `{"enemy_scale": float, "payout_scale": float}` for `difficulty`.
func get_difficulty_scales() -> Dictionary:
	for entry in DIFFICULTY_PRESETS:
		if entry["id"] == difficulty:
			return {
				"enemy_scale": float(entry["enemy_scale"]),
				"payout_scale": float(entry["payout_scale"]),
			}
	return {"enemy_scale": 1.0, "payout_scale": 1.0}


## Return a copy of the selected spawn outpost spec from `OUTPOST_SPECS`.
func get_outpost_spec() -> Dictionary:
	for entry in OUTPOST_SPECS:
		if entry["id"] == spawn_outpost_id:
			return entry.duplicate(true)
	return OUTPOST_SPECS[0].duplicate(true)


## Return a copy of the selected ship spec from `SHIP_SPECS`.
func get_ship_spec() -> Dictionary:
	for entry in SHIP_SPECS:
		if entry["id"] == ship_class:
			return entry.duplicate(true)
	return SHIP_SPECS[0].duplicate(true)


## Return a copy of the selected game mode spec from `MODE_SPECS`.
func get_mode_spec() -> Dictionary:
	for entry in MODE_SPECS:
		if entry["id"] == mode:
			return entry.duplicate(true)
	return MODE_SPECS[0].duplicate(true)


## Return the strict-ASCII display label for the active game mode.
func get_mode_label() -> String:
	return String(get_mode_spec().get("label", "Open-Seas Adventure"))


## Return the strict-ASCII display name for the active starting emissary flag.
func get_emissary_label() -> String:
	for entry in EMISSARY_PRESETS:
		if entry["id"] == starting_emissary:
			return String(entry["name"])
	return "No Emissary Flag"


## Populate vessel name and preferred ship class from a persistent `Profile`.
func apply_profile_defaults(profile: Profile) -> void:
	if profile == null:
		validate()
		return
	ship_name = profile.get_ship_name()
	var saved_cls := String(profile.data.get("ship_class", "sloop")).strip_edges().to_lower()
	if _has_id(SHIP_SPECS, StringName(saved_cls)):
		ship_class = StringName(saved_cls)
	validate()


## Return an independent validated copy of this `SessionConfig`.
func duplicate_config() -> SessionConfig:
	var copy := SessionConfig.new()
	copy.mode = mode
	copy.ship_class = ship_class
	copy.ship_name = ship_name
	copy.spawn_outpost_id = spawn_outpost_id
	copy.crew_count = crew_count
	copy.time_preset = time_preset
	copy.weather_preset = weather_preset
	copy.difficulty = difficulty
	copy.starting_emissary = starting_emissary
	copy.coop_role = coop_role
	copy.coop_address = coop_address
	copy.coop_port = coop_port
	copy.validate()
	return copy


## Serialize all session fields into a plain JSON-safe Dictionary.
func to_dict() -> Dictionary:
	validate()
	return {
		"mode": String(mode),
		"ship_class": String(ship_class),
		"ship_name": ship_name,
		"spawn_outpost_id": String(spawn_outpost_id),
		"crew_count": crew_count,
		"time_preset": String(time_preset),
		"weather_preset": String(weather_preset),
		"difficulty": String(difficulty),
		"starting_emissary": String(starting_emissary),
		"coop_role": String(coop_role),
		"coop_address": coop_address,
		"coop_port": coop_port,
	}


## Deserialize a `SessionConfig` from a Dictionary and clamp/validate all values.
static func from_dict(d: Dictionary) -> SessionConfig:
	var cfg := SessionConfig.new()
	if d.has("mode"):
		cfg.mode = StringName(String(d["mode"]).strip_edges().to_lower())
	if d.has("ship_class"):
		cfg.ship_class = StringName(String(d["ship_class"]).strip_edges().to_lower())
	if d.has("ship_name"):
		cfg.ship_name = String(d["ship_name"])
	if d.has("spawn_outpost_id"):
		cfg.spawn_outpost_id = StringName(String(d["spawn_outpost_id"]).strip_edges().to_lower())
	if d.has("crew_count"):
		cfg.crew_count = int(d["crew_count"])
	if d.has("time_preset"):
		cfg.time_preset = StringName(String(d["time_preset"]).strip_edges().to_lower())
	if d.has("weather_preset"):
		cfg.weather_preset = StringName(String(d["weather_preset"]).strip_edges().to_lower())
	if d.has("difficulty"):
		cfg.difficulty = StringName(String(d["difficulty"]).strip_edges().to_lower())
	if d.has("starting_emissary"):
		cfg.starting_emissary = StringName(String(d["starting_emissary"]).strip_edges().to_lower())
	if d.has("coop_role"):
		cfg.coop_role = StringName(String(d["coop_role"]).strip_edges().to_lower())
	if d.has("coop_address"):
		cfg.coop_address = String(d["coop_address"])
	if d.has("coop_port"):
		cfg.coop_port = int(d["coop_port"])
	cfg.validate()
	return cfg


## Sanitize and clamp all fields; enforce safe tutorial defaults in `MODE_TUTORIAL`.
func validate() -> void:
	if not VALID_MODES.has(mode):
		mode = MODE_ADVENTURE
	if not _has_id(SHIP_SPECS, ship_class):
		ship_class = &"sloop"
	ship_name = Profile.sanitize_ship_name(ship_name)
	if not _has_id(OUTPOST_SPECS, spawn_outpost_id):
		spawn_outpost_id = &"port_scoundrel"
	crew_count = clampi(crew_count, 0, CREW_PRESETS.size() - 1)
	if not _has_id(TIME_PRESETS, time_preset):
		time_preset = &"morning"
	if not _has_id(WEATHER_PRESETS, weather_preset):
		weather_preset = &"fair"
	if not _has_id(DIFFICULTY_PRESETS, difficulty):
		difficulty = &"standard"
	if not _has_id(EMISSARY_PRESETS, starting_emissary):
		starting_emissary = &""
	if coop_role != &"host" and coop_role != &"join":
		coop_role = &"host"
	coop_address = _sanitize_address(coop_address)
	if coop_port <= 0:
		coop_port = Net.DEFAULT_PORT
	else:
		coop_port = clampi(coop_port, MIN_COOP_PORT, MAX_COOP_PORT)

	if mode == MODE_TUTORIAL:
		spawn_outpost_id = &"port_scoundrel"
		weather_preset = &"fair"
		starting_emissary = &""
		crew_count = maxi(crew_count, 1)


static func _has_id(specs: Array[Dictionary], id_val: StringName) -> bool:
	for entry in specs:
		if entry.get("id", &"") == id_val:
			return true
	return false


static func _sanitize_address(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code > 32 and code <= 126:
			out += char(code)
	out = out.strip_edges()
	if out.is_empty():
		return "127.0.0.1"
	if out.length() > 64:
		out = out.substr(0, 64)
	return out
