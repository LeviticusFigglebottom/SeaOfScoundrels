class_name VoyageComposer
extends RefCounted
## Modular voyage composer and authored Story Voyage library.
##
## Procedural voyages are assembled from four interlocking parts — Hook, Site,
## Complication, and Payoff — across 7 distinct voyage shapes, with strict
## anti-repetition history (never repeating the same shape or target island
## back-to-back) and deterministic seeding support.

const STORY_CHAPTER_COUNT := 3

const SHAPES: Array[StringName] = [
	&"buried_hoard",
	&"riddle_trail",
	&"drowned_bounty",
	&"wreck_salvage",
	&"cargo_run",
	&"fort_siege",
	&"open_sea_hunt",
]

const CAPTAIN_NAMES: Array[String] = [
	"Captain Barnacle-Tooth Voss",
	"Marrow-Eye Calder",
	"Dread Bosun Orlov",
	"Salt-Beard Maren",
	"Quartermaster Grin",
	"Iron-Hook Fenwick",
	"Bilge-Queen Harker",
]

const DIRECTIONS: Array[String] = [
	"north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest",
]

const TITLE_ADJECTIVES: Array[String] = [
	"Gilded", "Sunken", "Salt-Bitten", "Crimson", "Forgotten", "Weeping",
	"Tide-Worn", "Iron", "Cursed", "Smuggler's", "Storm-Swept", "Ashen",
]

var _rng := RandomNumberGenerator.new()
var _serial: int = 0
var recent_shapes: Array[StringName] = []
var recent_islands: Array[StringName] = []
var _shape_counts: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		set_seed(seed_value)
	else:
		_rng.randomize()
	_reset_shape_counts()


func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value
	_serial = 0
	recent_shapes.clear()
	recent_islands.clear()
	_reset_shape_counts()


func clear_history() -> void:
	recent_shapes.clear()
	recent_islands.clear()
	_reset_shape_counts()


func _reset_shape_counts() -> void:
	_shape_counts.clear()
	for s in SHAPES:
		_shape_counts[s] = 0


## Default 14-island canonical archipelago descriptor used as fallback when no
## live Archipelago map array is supplied.
static func default_archipelago_roster() -> Array[Dictionary]:
	return [
		{
			"id": &"port_scoundrel",
			"name": "Port Scoundrel",
			"kind": &"outpost",
			"position": Vector3(0.0, 0.0, 0.0),
			"landmarks": ["Harbour Crane", "Gilded Pier", "Tavern Bell"],
		},
		{
			"id": &"cutlass_cay",
			"name": "Cutlass Cay",
			"kind": &"treasure_island",
			"position": Vector3(420.0, 0.0, -680.0),
			"landmarks": ["Split Palm", "Cutlass Rock", "Smuggler's Cove"],
		},
		{
			"id": &"gull_roost",
			"name": "Gull Roost",
			"kind": &"treasure_island",
			"position": Vector3(-560.0, 0.0, -520.0),
			"landmarks": ["White Arch", "Driftwood Cairn", "Tern Cliff"],
		},
		{
			"id": &"rumrunners_haven",
			"name": "Rumrunner's Haven",
			"kind": &"outpost",
			"position": Vector3(1180.0, 0.0, -340.0),
			"landmarks": ["Barrel Wharf", "Copper Still", "Signal Brazier"],
		},
		{
			"id": &"ironwatch_fort",
			"name": "Ironwatch Fort",
			"kind": &"fort",
			"position": Vector3(-920.0, 0.0, -1240.0),
			"landmarks": ["North Bastion", "Powder Gate", "Bell Tower"],
		},
		{
			"id": &"wreck_shoal",
			"name": "Shipwreck Shoal",
			"kind": &"shipwreck",
			"position": Vector3(260.0, 0.0, -1480.0),
			"landmarks": ["Broken Bow", "Barnacle Mast", "Sunken Stern"],
		},
		{
			"id": &"coral_spire",
			"name": "Coral Spire",
			"kind": &"landmark",
			"position": Vector3(1060.0, 0.0, -1320.0),
			"landmarks": ["Tidecaller Arch", "Pink Monolith", "Echoing Pool"],
		},
		{
			"id": &"blackfin_atoll",
			"name": "Blackfin Atoll",
			"kind": &"treasure_island",
			"position": Vector3(-1260.0, 0.0, -280.0),
			"landmarks": ["Shark-Jaw Reef", "Twin Palms", "Sunken Anchor"],
		},
		{
			"id": &"cinder_crag",
			"name": "Cinder Crag",
			"kind": &"landmark",
			"position": Vector3(-340.0, 0.0, -1960.0),
			"landmarks": ["Basalt Fang", "Ash Hollow", "Charred Wreck"],
		},
		{
			"id": &"lantern_point",
			"name": "Lantern Point",
			"kind": &"outpost",
			"position": Vector3(-1140.0, 0.0, 580.0),
			"landmarks": ["Beacon Tower", "Salt Jetty", "Shipwright Shed"],
		},
		{
			"id": &"salt_reach",
			"name": "Salt Reach",
			"kind": &"treasure_island",
			"position": Vector3(880.0, 0.0, 620.0),
			"landmarks": ["Salt Pillars", "Dry Cistern", "Weathered Gallows"],
		},
		{
			"id": &"sirens_tooth",
			"name": "Siren's Tooth",
			"archetype": &"sea_stack",
			"kind": &"landmark",
			"position": Vector3(1480.0, 0.0, -960.0),
			"landmarks": ["Twin Basalt Fangs", "Siren Tidepool", "Reef Shelf"],
		},
		{
			"id": &"sovereigns_bastion",
			"name": "Sovereign's Bastion",
			"archetype": &"grand_citadel",
			"kind": &"fort",
			"position": Vector3(-1640.0, 0.0, -1580.0),
			"landmarks": ["Outer Seawall", "Ruined Temple Arch", "Waterfall Terrace", "Citadel Vault"],
		},
		{
			"id": &"galleons_reach",
			"name": "Galleon's Reach",
			"archetype": &"grand_outpost",
			"kind": &"outpost",
			"position": Vector3(1560.0, 0.0, 980.0),
			"landmarks": ["Grand Trade Pier", "Harbour Warehouse", "Seawall Promenade", "Cliffside Watchtower"],
		},
	]


## Normalize an Array of Dictionaries, an Array of island Nodes, or a duck-typed
## Archipelago Node into plain island dictionaries.
static func extract_archipelago_data(source: Variant) -> Array[Dictionary]:
	var raw_list: Array = []
	if source is Array:
		raw_list = source
	elif source is Object:
		if source.has_method("get_map_data"):
			var data: Variant = source.call("get_map_data")
			if data is Array:
				raw_list = data
		elif source.get("islands") is Array:
			raw_list = source.get("islands")
	if raw_list.is_empty():
		return default_archipelago_roster()

	var out: Array[Dictionary] = []
	for item in raw_list:
		if item is Dictionary:
			var d: Dictionary = item
			var id := StringName(String(d.get("id", d.get("island_id", "island_%d" % out.size()))))
			var pos_raw: Variant = d.get("position", Vector3.ZERO)
			var pos: Vector3 = pos_raw if pos_raw is Vector3 else Vector3.ZERO
			var lm_raw: Variant = d.get("landmarks", [])
			var landmarks: Array = lm_raw if lm_raw is Array else []
			out.append({
				"id": id,
				"name": String(d.get("name", String(id).capitalize())),
				"archetype": StringName(String(d.get("archetype", &""))),
				"kind": StringName(String(d.get("kind", &"treasure_island"))),
				"position": pos,
				"landmarks": landmarks.duplicate(),
			})
		elif item is Node:
			var n: Node = item
			var id_val: Variant = n.get("island_id")
			if id_val == null:
				id_val = n.get("id")
			var id := StringName(String(id_val if id_val != null else n.name))
			var name_val: Variant = n.get("island_name")
			var arch_val: Variant = n.get("archetype")
			var kind_val: Variant = n.get("kind")
			var pos := Vector3.ZERO
			if n is Node3D:
				pos = (n as Node3D).global_position if n.is_inside_tree() else (n as Node3D).position
			var lm_val: Variant = n.get("landmarks")
			var landmarks: Array = lm_val if lm_val is Array else []
			out.append({
				"id": id,
				"name": String(name_val if name_val != null else n.name),
				"archetype": StringName(String(arch_val if arch_val != null else &"")),
				"kind": StringName(String(kind_val if kind_val != null else &"treasure_island")),
				"position": pos,
				"landmarks": landmarks.duplicate(),
			})
	return out if not out.is_empty() else default_archipelago_roster()


## Compose a modular procedural voyage. Pass `forced_shape` to request a specific
## shape, or leave empty to let the anti-repetition selector pick freely.
func compose_voyage(archipelago_source: Variant = [], difficulty: int = 1,
		company_filter: StringName = &"", forced_shape: StringName = &"",
		origin_outpost_id: StringName = &"port_scoundrel") -> Dictionary:
	var islands := extract_archipelago_data(archipelago_source)
	var diff := clampi(difficulty, 1, 5)
	var shape := _pick_shape(forced_shape, company_filter)
	var origin := _find_island(islands, origin_outpost_id)
	if origin.is_empty():
		origin = _find_first_of_kind(islands, &"outpost", islands[0])
	var resolved_origin: StringName = origin["id"]

	var target := _pick_target_island(islands, shape, resolved_origin)

	_record_history(shape, target["id"])
	_serial += 1

	var voyage: Dictionary
	match shape:
		&"buried_hoard":
			voyage = _build_buried_hoard(diff, resolved_origin, target)
		&"riddle_trail":
			voyage = _build_riddle_trail(diff, resolved_origin, target)
		&"drowned_bounty":
			voyage = _build_drowned_bounty(diff, resolved_origin, target)
		&"wreck_salvage":
			voyage = _build_wreck_salvage(diff, resolved_origin, target)
		&"cargo_run":
			voyage = _build_cargo_run(diff, origin, target)
		&"fort_siege":
			voyage = _build_fort_siege(diff, resolved_origin, target)
		&"open_sea_hunt":
			voyage = _build_open_sea_hunt(diff, resolved_origin, target)
		_:
			voyage = _build_buried_hoard(diff, resolved_origin, target)

	if company_filter != &"" and Economy.COMPANIES.has(company_filter):
		voyage["company_id"] = company_filter
	return voyage


## Generate a varied board of voyage contracts offered at an outpost.
func generate_board_offers(archipelago_source: Variant = [], count: int = 3,
		company_ranks: Dictionary = {}, origin_outpost_id: StringName = &"port_scoundrel") -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var companies: Array[StringName] = [&"gilded_compass", &"iron_tide", &"sunken_archive"]
	for i in maxi(1, count):
		var comp: StringName = companies[i % companies.size()]
		var rank: int = int(company_ranks.get(String(comp), company_ranks.get(comp, 1)))
		var diff := clampi(1 + int(floor(float(rank - 1) / 3.0)), 1, 5)
		offers.append(compose_voyage(archipelago_source, diff, comp, &"", origin_outpost_id))
	return offers


## Return an authored multi-beat Story Voyage (Chapters 1..3).
func get_story_voyage(chapter: int, archipelago_source: Variant = []) -> Dictionary:
	var islands := extract_archipelago_data(archipelago_source)
	var port := _find_island(islands, &"port_scoundrel")
	if port.is_empty():
		port = _find_first_of_kind(islands, &"outpost", islands[0])
	var port_id: StringName = port["id"]
	var port_name: String = String(port["name"])

	match chapter:
		1:
			var cay := _find_island(islands, &"cutlass_cay")
			if cay.is_empty():
				cay = _find_first_of_kind(islands, &"treasure_island", islands[mini(1, islands.size() - 1)])
			var cay_id: StringName = cay["id"]
			var cay_name: String = String(cay["name"])
			var cay_pos: Vector3 = cay["position"]
			var landmark := _first_landmark(cay, "Split Palm")
			var treasures: Array[StringName] = [&"ledger_coffer"]
			var payoff := _make_payoff(treasures, 250, 60)
			return {
				"id": "story_ch1_salt_kings_ledger",
				"title": "The Salt-King's Ledger",
				"shape": &"buried_hoard",
				"company_id": &"sunken_archive",
				"difficulty": 1,
				"is_story": true,
				"story_chapter": 1,
				"origin_outpost_id": port_id,
				"return_outpost_id": port_id,
				"target_island_id": cay_id,
				"target_island_name": cay_name,
				"target_position": cay_pos,
				"hook": {
					"kind": &"treasure_map",
					"title": "The Salt-King's Torn Chart",
					"briefing": "Archivist Morwenna hands you a water-stained chart to %s. The Salt-King's ciphered Ledger Coffer lies buried near %s — guarded by Drowned deckhands." % [cay_name, landmark],
					"clues": [
						"Set sail from %s on the chart's bearing to %s." % [port_name, cay_name],
						"Look for the red cross beside %s, watch for Drowned guards, and dig." % landmark,
						"Watch the horizon on the sail back — a Drowned sloop patrols these waters.",
					],
					"landmark": landmark,
				},
				"site": {
					"kind": &"landmark_island",
					"island_id": cay_id,
					"island_name": cay_name,
					"position": cay_pos,
					"destination_outpost_id": port_id,
					"enemy_faction": &"drowned",
					"enemy_count": 3,
					"has_captain": false,
					"dig_count": 1,
					"wave_count": 0,
				},
				"complication": {
					"kind": &"rival_intercept",
					"description": "A Drowned Sloop intercepts the crossing back to %s once the Ledger Coffer is aboard." % port_name,
					"trigger": &"on_return",
					"time_limit_sec": 0.0,
					"threat_archetype": &"drowned_sloop",
				},
				"payoff": payoff,
				"stages": [
					{
						"kind": &"sail_to",
						"objective": "Sail from %s to %s with the Salt-King's chart." % [port_name, cay_name],
						"target_id": cay_id,
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"dig_treasure",
						"objective": "Defeat or outwit the Drowned guards and unearth the Salt-King's Ledger Coffer near %s." % landmark,
						"target_id": &"ledger_coffer",
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"board_treasure",
						"objective": "Carry the Ledger Coffer aboard your sloop.",
						"target_id": &"ledger_coffer",
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"sell_treasure",
						"objective": "Survive the Drowned sloop interception and sell the Ledger Coffer at %s." % port_name,
						"target_id": port_id,
						"required_count": 1,
						"optional": false,
					},
				],
			}

		2:
			var spire := _find_island(islands, &"coral_spire")
			if spire.is_empty():
				spire = _find_island(islands, &"smugglers_cove")
			if spire.is_empty():
				spire = _find_first_of_kind(islands, &"landmark", islands[mini(2, islands.size() - 1)])
			var spire_id: StringName = spire["id"]
			var spire_name: String = String(spire["name"])
			var spire_pos: Vector3 = spire["position"]
			var lm_a := _landmark_at(spire, 0, "Tidecaller Arch")
			var lm_b := _landmark_at(spire, 1, "Pink Monolith")
			var lm_c := _landmark_at(spire, 2, "Echoing Pool")
			var treasures: Array[StringName] = [&"archive_chalice", &"weeping_bilge_chest"]
			var payoff := _make_payoff(treasures, 400, 95)
			return {
				"id": "story_ch2_lanterns_of_the_tidecallers",
				"title": "Lanterns of the Tidecallers",
				"shape": &"riddle_trail",
				"company_id": &"sunken_archive",
				"difficulty": 3,
				"is_story": true,
				"story_chapter": 2,
				"origin_outpost_id": port_id,
				"return_outpost_id": port_id,
				"target_island_id": spire_id,
				"target_island_name": spire_name,
				"target_position": spire_pos,
				"hook": {
					"kind": &"riddle_clues",
					"title": "The Ciphered Tide-Hymnal",
					"briefing": "The Salt-King's ledger names a hidden Tidecaller beacon on %s. Raise your lantern at each shrine landmark to uncover the weeping vault." % spire_name,
					"clues": [
						"Where coral crowns the foaming sea, seek %s under %s's lee." % [lm_a, spire_name],
						"Hold lantern high by %s stone, where salt-wind hums in hollow tone." % lm_b,
						"Seven paces north of %s's rim, dig deep before the sky grows grim." % lm_c,
					],
					"landmark": lm_c,
				},
				"site": {
					"kind": &"landmark_island",
					"island_id": spire_id,
					"island_name": spire_name,
					"position": spire_pos,
					"destination_outpost_id": port_id,
					"enemy_faction": &"tidecallers",
					"enemy_count": 5,
					"has_captain": false,
					"dig_count": 2,
					"wave_count": 0,
				},
				"complication": {
					"kind": &"storm_squall",
					"description": "Breaking the Tidecaller seal summons a rolling squall while the Bilge-Weep Chest floods your hold.",
					"trigger": &"on_return",
					"time_limit_sec": 0.0,
					"threat_archetype": &"storm_cell",
				},
				"payoff": payoff,
				"stages": [
					{
						"kind": &"sail_to",
						"objective": "Sail to %s to read the first Tidecaller lantern clue." % spire_name,
						"target_id": spire_id,
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"solve_riddle",
						"objective": "Follow the 3 lantern clues across %s (%s -> %s -> %s)." % [spire_name, lm_a, lm_b, lm_c],
						"target_id": spire_id,
						"required_count": 3,
						"optional": false,
					},
					{
						"kind": &"dig_treasure",
						"objective": "Unearth the Gilded Tide-Chalice and Cursed Bilge-Weep Chest.",
						"target_id": &"weeping_bilge_chest",
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"board_treasure",
						"objective": "Haul the relics aboard and keep bailing against the Bilge-Weep curse.",
						"target_id": &"weeping_bilge_chest",
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"sell_treasure",
						"objective": "Weather the squall and deliver the relics to %s." % port_name,
						"target_id": port_id,
						"required_count": 1,
						"optional": false,
					},
				],
			}

		3:
			var fort := _find_island(islands, &"ironwatch_fort")
			if fort.is_empty():
				fort = _find_first_of_kind(islands, &"fort", islands[mini(4, islands.size() - 1)])
			var fort_id: StringName = fort["id"]
			var fort_name: String = String(fort["name"])
			var fort_pos: Vector3 = fort["position"]
			var landmark := _first_landmark(fort, "North Bastion")
			var treasures: Array[StringName] = [&"sovereign_chest", &"captains_skull", &"ledger_coffer"]
			var payoff := _make_payoff(treasures, 750, 160)
			return {
				"id": "story_ch3_the_sunken_crown",
				"title": "The Sunken Crown",
				"shape": &"fort_siege",
				"company_id": &"sunken_archive",
				"difficulty": 5,
				"is_story": true,
				"story_chapter": 3,
				"origin_outpost_id": port_id,
				"return_outpost_id": port_id,
				"target_island_id": fort_id,
				"target_island_name": fort_name,
				"target_position": fort_pos,
				"hook": {
					"kind": &"war_letter",
					"title": "Warrant of the Sunken Crown",
					"briefing": "The Salt-King's flagship garrison has fortified %s. Silence the batteries at %s, break three Drowned waves, claim the Vault Key, and outrun the Ghost Ship on the dash home." % [fort_name, landmark],
					"clues": [
						"Approach %s cautiously — shore batteries guard the anchorage." % fort_name,
						"Break three garrison waves and slay the Fort Commander for the Vault Key.",
						"Expect a spectral Ghost Ship on the voyage back to %s." % port_name,
					],
					"landmark": landmark,
				},
				"site": {
					"kind": &"sea_fort",
					"island_id": fort_id,
					"island_name": fort_name,
					"position": fort_pos,
					"destination_outpost_id": port_id,
					"enemy_faction": &"drowned",
					"enemy_count": 12,
					"has_captain": true,
					"dig_count": 0,
					"wave_count": 3,
				},
				"complication": {
					"kind": &"ghost_ambush",
					"description": "Fort cannon batteries fire during approach, and a Ghost Ship hunts you on the return leg.",
					"trigger": &"on_return",
					"time_limit_sec": 0.0,
					"threat_archetype": &"ghost_ship",
				},
				"payoff": payoff,
				"stages": [
					{
						"kind": &"sail_to",
						"objective": "Sail to %s and clear the harbour cannon batteries." % fort_name,
						"target_id": fort_id,
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"defeat_enemies",
						"objective": "Break the 3 Drowned garrison waves and claim the Vault Key.",
						"target_id": &"drowned_captain",
						"required_count": 3,
						"optional": false,
					},
					{
						"kind": &"board_treasure",
						"objective": "Open the fort vault and haul the Salt-King's royal hoard aboard.",
						"target_id": &"sovereign_chest",
						"required_count": 1,
						"optional": false,
					},
					{
						"kind": &"sell_treasure",
						"objective": "Survive the Ghost Ship ambush and sell the royal hoard at %s." % port_name,
						"target_id": port_id,
						"required_count": 1,
						"optional": false,
					},
				],
			}

		_:
			push_warning("VoyageComposer: unknown story chapter %d, returning Chapter 1" % chapter)
			return get_story_voyage(1, islands)


# --- Procedural Shape Builders ------------------------------------------

func _build_buried_hoard(diff: int, origin_id: StringName, target: Dictionary) -> Dictionary:
	var tid: StringName = target["id"]
	var tname: String = String(target["name"])
	var landmark := _random_landmark(target, "Split Palm")
	var treasures: Array[StringName] = []
	if diff >= 4:
		treasures = [&"sovereign_chest", &"corsair_chest"]
	elif diff >= 2:
		treasures = [&"corsair_chest", &"wayfarer_chest"]
	else:
		treasures = [&"wayfarer_chest", &"driftwood_chest"]
	var adj := _pick_str(TITLE_ADJECTIVES)
	var payoff := _make_payoff(treasures, 60 * diff, 15 * diff)
	return {
		"id": "voy_hoard_%d" % _serial,
		"title": "The %s Hoard of %s" % [adj, tname],
		"shape": &"buried_hoard",
		"company_id": &"gilded_compass",
		"difficulty": diff,
		"is_story": false,
		"story_chapter": 0,
		"origin_outpost_id": origin_id,
		"return_outpost_id": origin_id,
		"target_island_id": tid,
		"target_island_name": tname,
		"target_position": target["position"],
		"hook": {
			"kind": &"treasure_map",
			"title": "Chart of %s" % tname,
			"briefing": "A Gilded Compass survey marks buried strongboxes near %s on %s." % [landmark, tname],
			"clues": ["Red X marked beside %s on %s." % [landmark, tname]],
			"landmark": landmark,
		},
		"site": {
			"kind": &"landmark_island",
			"island_id": tid,
			"island_name": tname,
			"position": target["position"],
			"destination_outpost_id": origin_id,
			"enemy_faction": &"drowned",
			"enemy_count": 2 + diff,
			"has_captain": false,
			"dig_count": treasures.size(),
			"wave_count": 0,
		},
		"complication": {
			"kind": &"rival_intercept",
			"description": "A rival Drowned sloop catches wind of the haul and intercepts your return lane.",
			"trigger": &"on_return",
			"time_limit_sec": 0.0,
			"threat_archetype": &"drowned_sloop",
		},
		"payoff": payoff,
		"stages": [
			{"kind": &"sail_to", "objective": "Sail to %s using your held chart." % tname, "target_id": tid, "required_count": 1, "optional": false},
			{"kind": &"dig_treasure", "objective": "Dig up the buried hoard near %s." % landmark, "target_id": treasures[0], "required_count": 1, "optional": false},
			{"kind": &"board_treasure", "objective": "Stow the chest aboard your sloop.", "target_id": treasures[0], "required_count": 1, "optional": false},
			{"kind": &"sell_treasure", "objective": "Outrun or sink the intercepting sloop and sell the haul at port.", "target_id": origin_id, "required_count": 1, "optional": false},
		],
	}


func _build_riddle_trail(diff: int, origin_id: StringName, target: Dictionary) -> Dictionary:
	var tid: StringName = target["id"]
	var tname: String = String(target["name"])
	var lm1 := _landmark_at(target, 0, "the Lone Palm")
	var lm2 := _landmark_at(target, 1, "the Sea Arch")
	var lm3 := _landmark_at(target, 2, "the Broken Anchor")
	var dir := _pick_str(DIRECTIONS)
	var paces := 5 + (_rng.randi() % 6)
	var clues: Array[String] = [
		"To %s turn your weathered prow; seek %s where seabirds bow." % [tname, lm1],
		"From %s raise lantern bright, till %s gleams in amber light." % [lm1, lm2],
		"At %s step %d paces %s, and strike the sand for buried worth." % [lm3, paces, dir],
	]
	var treasures: Array[StringName] = [&"archive_chalice", &"sovereign_chest" if diff >= 3 else &"corsair_chest"]
	var payoff := _make_payoff(treasures, 80 * diff, 25 * diff)
	return {
		"id": "voy_riddle_%d" % _serial,
		"title": "Riddle of %s" % tname,
		"shape": &"riddle_trail",
		"company_id": &"sunken_archive",
		"difficulty": diff,
		"is_story": false,
		"story_chapter": 0,
		"origin_outpost_id": origin_id,
		"return_outpost_id": origin_id,
		"target_island_id": tid,
		"target_island_name": tname,
		"target_position": target["position"],
		"hook": {
			"kind": &"riddle_clues",
			"title": "Rhyming Scroll of %s" % tname,
			"briefing": "Three inked couplets guide you across %s's landmarks to a hidden Archive cache." % tname,
			"clues": clues,
			"landmark": lm3,
		},
		"site": {
			"kind": &"landmark_island",
			"island_id": tid,
			"island_name": tname,
			"position": target["position"],
			"destination_outpost_id": origin_id,
			"enemy_faction": &"tidecallers",
			"enemy_count": 2 + diff,
			"has_captain": false,
			"dig_count": 1,
			"wave_count": 0,
		},
		"complication": {
			"kind": &"cursed_haul",
			"description": "Disturbing the Archive cache wakes Tidecaller guardians along the ridge.",
			"trigger": &"on_arrival",
			"time_limit_sec": 0.0,
			"threat_archetype": &"tidecaller_ambush",
		},
		"payoff": payoff,
		"stages": [
			{"kind": &"sail_to", "objective": "Sail to %s and read the first riddle stanza." % tname, "target_id": tid, "required_count": 1, "optional": false},
			{"kind": &"solve_riddle", "objective": "Follow all 3 rhyming clues across %s." % tname, "target_id": tid, "required_count": 3, "optional": false},
			{"kind": &"dig_treasure", "objective": "Unearth the Archive relic %d paces %s of %s." % [paces, dir, lm3], "target_id": treasures[0], "required_count": 1, "optional": false},
			{"kind": &"board_treasure", "objective": "Carry the Archive cache back to your ship.", "target_id": treasures[0], "required_count": 1, "optional": false},
			{"kind": &"sell_treasure", "objective": "Return to port and turn in the relic to the Sunken Archive.", "target_id": origin_id, "required_count": 1, "optional": false},
		],
	}


func _build_drowned_bounty(diff: int, origin_id: StringName, target: Dictionary) -> Dictionary:
	var tid: StringName = target["id"]
	var tname: String = String(target["name"])
	var landmark := _random_landmark(target, "Skull Camp")
	var captain := _pick_str(CAPTAIN_NAMES)
	var treasures: Array[StringName] = [&"captains_skull" if diff >= 2 else &"drowned_skull"]
	if diff >= 4:
		treasures.append(&"drowned_skull")
	var payoff := _make_payoff(treasures, 75 * diff, 25 * diff)
	return {
		"id": "voy_bounty_%d" % _serial,
		"title": "Bounty: %s" % captain,
		"shape": &"drowned_bounty",
		"company_id": &"iron_tide",
		"difficulty": diff,
		"is_story": false,
		"story_chapter": 0,
		"origin_outpost_id": origin_id,
		"return_outpost_id": origin_id,
		"target_island_id": tid,
		"target_island_name": tname,
		"target_position": target["position"],
		"hook": {
			"kind": &"bounty_poster",
			"title": "Iron Tide Warrant — %s" % captain,
			"briefing": "%s and a Drowned crew were sighted encamped near %s on %s. Claim the Captain's Skull." % [captain, landmark, tname],
			"clues": ["Target camp spotted near %s on %s." % [landmark, tname]],
			"landmark": landmark,
		},
		"site": {
			"kind": &"island_camp",
			"island_id": tid,
			"island_name": tname,
			"position": target["position"],
			"destination_outpost_id": origin_id,
			"enemy_faction": &"drowned",
			"enemy_count": 3 + diff * 2,
			"has_captain": true,
			"captain_name": captain,
			"dig_count": 0,
			"wave_count": 0,
		},
		"complication": {
			"kind": &"storm_squall",
			"description": "A heavy rain squall sweeps over %s during the skirmish and return sail." % tname,
			"trigger": &"on_arrival",
			"time_limit_sec": 0.0,
			"threat_archetype": &"storm_cell",
		},
		"payoff": payoff,
		"stages": [
			{"kind": &"sail_to", "objective": "Sail to %s to hunt %s." % [tname, captain], "target_id": tid, "required_count": 1, "optional": false},
			{"kind": &"defeat_captain", "objective": "Defeat %s and their Drowned crew near %s." % [captain, landmark], "target_id": &"drowned_captain", "required_count": 1, "optional": false},
			{"kind": &"board_treasure", "objective": "Bring the Drowned Skull aboard your sloop.", "target_id": treasures[0], "required_count": 1, "optional": false},
			{"kind": &"sell_treasure", "objective": "Deliver the skull to the Iron Tide Warden at port.", "target_id": origin_id, "required_count": 1, "optional": false},
		],
	}


func _build_wreck_salvage(diff: int, origin_id: StringName, target: Dictionary) -> Dictionary:
	var tid: StringName = target["id"]
	var tname: String = String(target["name"])
	var landmark := _random_landmark(target, "Sunken Stern")
	var treasures: Array[StringName] = [&"weeping_bilge_chest", &"archive_chalice"]
	var payoff := _make_payoff(treasures, 90 * diff, 30 * diff)
	return {
		"id": "voy_wreck_%d" % _serial,
		"title": "Salvage of %s" % tname,
		"shape": &"wreck_salvage",
		"company_id": &"sunken_archive",
		"difficulty": diff,
		"is_story": false,
		"story_chapter": 0,
		"origin_outpost_id": origin_id,
		"return_outpost_id": origin_id,
		"target_island_id": tid,
		"target_island_name": tname,
		"target_position": target["position"],
		"hook": {
			"kind": &"rumour_chart",
			"title": "Diver's Rumour of %s" % tname,
			"briefing": "Gulls wheel above a shattered galleon near %s off %s. Dive the cabin for a Cursed Bilge-Weep Chest and Tide-Chalice." % [landmark, tname],
			"clues": ["Watch for circling gulls above %s near %s." % [landmark, tname]],
			"landmark": landmark,
		},
		"site": {
			"kind": &"shipwreck_shoal",
			"island_id": tid,
			"island_name": tname,
			"position": target["position"],
			"destination_outpost_id": origin_id,
			"enemy_faction": &"sharks",
			"enemy_count": 2 + mini(diff, 3),
			"has_captain": false,
			"dig_count": 1,
			"wave_count": 0,
		},
		"complication": {
			"kind": &"shark_pack",
			"description": "A pack of reef sharks circles the wreck while the recovered Bilge-Weep Chest floods your hold.",
			"trigger": &"during_dive",
			"time_limit_sec": 0.0,
			"threat_archetype": &"shark_pack",
		},
		"payoff": payoff,
		"stages": [
			{"kind": &"sail_to", "objective": "Sail to the wreck off %s." % tname, "target_id": tid, "required_count": 1, "optional": false},
			{"kind": &"dig_treasure", "objective": "Dive past the circling sharks and recover the Bilge-Weep Chest and Tide-Chalice.", "target_id": &"weeping_bilge_chest", "required_count": 1, "optional": false},
			{"kind": &"board_treasure", "objective": "Haul the weeping chest aboard and stay ahead of the bilge water.", "target_id": &"weeping_bilge_chest", "required_count": 1, "optional": false},
			{"kind": &"sell_treasure", "objective": "Race back to port and sell the cursed haul before you founder.", "target_id": origin_id, "required_count": 1, "optional": false},
		],
	}


func _build_cargo_run(diff: int, origin: Dictionary, dest: Dictionary) -> Dictionary:
	var origin_id: StringName = origin["id"]
	var origin_name: String = String(origin["name"])
	var dest_id: StringName = dest["id"]
	var dest_name: String = String(dest["name"])
	var dist := (origin["position"] as Vector3).distance_to(dest["position"] as Vector3)
	var time_limit := maxf(240.0, dist * 0.35 + 180.0 - float(diff) * 15.0)
	var crate_count := 1 + mini(diff, 2)
	var treasures: Array[StringName] = []
	for _i in crate_count:
		treasures.append(&"spice_crate")
	var payoff := _make_payoff(treasures, 120 * diff, 35 * diff)
	return {
		"id": "voy_cargo_%d" % _serial,
		"title": "Express Spice Charter to %s" % dest_name,
		"shape": &"cargo_run",
		"company_id": &"gilded_compass",
		"difficulty": diff,
		"is_story": false,
		"story_chapter": 0,
		"origin_outpost_id": origin_id,
		"return_outpost_id": dest_id,
		"target_island_id": dest_id,
		"target_island_name": dest_name,
		"target_position": dest["position"],
		"hook": {
			"kind": &"merchant_contract",
			"title": "Sealed Bill of Lading: %s -> %s" % [origin_name, dest_name],
			"briefing": "Deliver %d fragile Spice Crate(s) dry and unbroken from %s to %s within %d seconds for full bonus." % [crate_count, origin_name, dest_name, roundi(time_limit)],
			"clues": ["Keep crates out of bilge water and avoid hard drops.", "Deliver to the Factor at %s." % dest_name],
			"landmark": _first_landmark(dest, "Wharf"),
		},
		"site": {
			"kind": &"outpost_route",
			"island_id": dest_id,
			"island_name": dest_name,
			"position": dest["position"],
			"destination_outpost_id": dest_id,
			"enemy_faction": &"none",
			"enemy_count": 0,
			"has_captain": false,
			"dig_count": 0,
			"wave_count": 0,
		},
		"complication": {
			"kind": &"fragile_timed",
			"description": "A drifting storm cell crosses the trade lane; rough seas and hard drops crack the fragile spice jars.",
			"trigger": &"on_departure",
			"time_limit_sec": time_limit,
			"threat_archetype": &"storm_cell",
		},
		"payoff": payoff,
		"stages": [
			{"kind": &"board_treasure", "objective": "Load the fragile Spice Crates aboard at %s." % origin_name, "target_id": &"spice_crate", "required_count": 1, "optional": false},
			{"kind": &"sail_to", "objective": "Sail cleanly to %s before the charter clock runs down." % dest_name, "target_id": dest_id, "required_count": 1, "optional": false},
			{"kind": &"sell_treasure", "objective": "Hand the Spice Crates to the Factor at %s." % dest_name, "target_id": dest_id, "required_count": 1, "optional": false},
		],
	}


func _build_fort_siege(diff: int, origin_id: StringName, target: Dictionary) -> Dictionary:
	var tid: StringName = target["id"]
	var tname: String = String(target["name"])
	var landmark := _random_landmark(target, "North Bastion")
	var waves := clampi(2 + int(diff / 2.0), 2, 4)
	var treasures: Array[StringName] = [&"sovereign_chest", &"corsair_chest", &"captains_skull"]
	var payoff := _make_payoff(treasures, 180 * diff, 45 * diff)
	return {
		"id": "voy_fort_%d" % _serial,
		"title": "Siege of %s" % tname,
		"shape": &"fort_siege",
		"company_id": &"iron_tide",
		"difficulty": diff,
		"is_story": false,
		"story_chapter": 0,
		"origin_outpost_id": origin_id,
		"return_outpost_id": origin_id,
		"target_island_id": tid,
		"target_island_name": tname,
		"target_position": target["position"],
		"hook": {
			"kind": &"war_letter",
			"title": "Iron Tide Siege Orders — %s" % tname,
			"briefing": "Drowned signal flares burn over %s. Silence the fort batteries at %s, break %d waves, seize the Vault Key, and raid the armoury." % [tname, landmark, waves],
			"clues": ["Watch the battery firing arcs around %s." % landmark, "The Fort Warden carries the Vault Key on the final wave."],
			"landmark": landmark,
		},
		"site": {
			"kind": &"sea_fort",
			"island_id": tid,
			"island_name": tname,
			"position": target["position"],
			"destination_outpost_id": origin_id,
			"enemy_faction": &"drowned",
			"enemy_count": waves * 4,
			"has_captain": true,
			"dig_count": 0,
			"wave_count": waves,
		},
		"complication": {
			"kind": &"fort_batteries",
			"description": "Shore cannon towers bombard approaching ships until silenced.",
			"trigger": &"during_assault",
			"time_limit_sec": 0.0,
			"threat_archetype": &"fort_cannons",
		},
		"payoff": payoff,
		"stages": [
			{"kind": &"sail_to", "objective": "Sail into range of %s and weather the battery fire." % tname, "target_id": tid, "required_count": 1, "optional": false},
			{"kind": &"defeat_enemies", "objective": "Clear %d fort garrison waves to claim the Vault Key." % waves, "target_id": &"drowned_captain", "required_count": waves, "optional": false},
			{"kind": &"board_treasure", "objective": "Plunder the vault and haul the multi-chest hoard aboard.", "target_id": &"sovereign_chest", "required_count": 1, "optional": false},
			{"kind": &"sell_treasure", "objective": "Deliver the fort haul back to port.", "target_id": origin_id, "required_count": 1, "optional": false},
		],
	}


func _build_open_sea_hunt(diff: int, origin_id: StringName, anchor: Dictionary) -> Dictionary:
	var aid: StringName = anchor["id"]
	var aname: String = String(anchor["name"])
	var angle := _rng.randf() * TAU
	var sea_pos: Vector3 = (anchor["position"] as Vector3) + Vector3(cos(angle), 0.0, sin(angle)) * 240.0
	var is_ghost := diff >= 3
	var prey_name := "Spectral Ghost Ship" if is_ghost else "Drowned Raider Sloop"
	var prey_kind := &"ghost_ship" if is_ghost else &"drowned_sloop"
	var treasures: Array[StringName] = [
		&"captains_skull" if is_ghost else &"drowned_skull",
		&"sovereign_chest" if is_ghost else &"corsair_chest",
	]
	var payoff := _make_payoff(treasures, 110 * diff, 35 * diff)
	return {
		"id": "voy_hunt_%d" % _serial,
		"title": "Open-Sea Hunt off %s" % aname,
		"shape": &"open_sea_hunt",
		"company_id": &"iron_tide",
		"difficulty": diff,
		"is_story": false,
		"story_chapter": 0,
		"origin_outpost_id": origin_id,
		"return_outpost_id": origin_id,
		"target_island_id": aid,
		"target_island_name": "Waters off %s" % aname,
		"target_position": sea_pos,
		"hook": {
			"kind": &"sea_sighting",
			"title": "Lookout Report — %s" % prey_name,
			"briefing": "Merchants spotted a %s prowling the deep channel off %s. Sink it and fish its floating salvage from the waves." % [prey_name, aname],
			"clues": ["Last seen patrolling 240 m off %s." % aname],
			"landmark": "Open Channel off %s" % aname,
		},
		"site": {
			"kind": &"open_sea",
			"island_id": aid,
			"island_name": "Waters off %s" % aname,
			"position": sea_pos,
			"destination_outpost_id": origin_id,
			"enemy_faction": &"drowned",
			"enemy_count": 1,
			"has_captain": true,
			"dig_count": 0,
			"wave_count": 0,
		},
		"complication": {
			"kind": &"ghost_ambush" if is_ghost else &"rival_intercept",
			"description": "The %s trades broadsides in open swell — watch your waterline and bail fast." % prey_name,
			"trigger": &"on_arrival",
			"time_limit_sec": 0.0,
			"threat_archetype": prey_kind,
		},
		"payoff": payoff,
		"stages": [
			{"kind": &"sail_to", "objective": "Intercept the %s prowling off %s." % [prey_name, aname], "target_id": aid, "required_count": 1, "optional": false},
			{"kind": &"defeat_captain", "objective": "Sink the %s in open water." % prey_name, "target_id": prey_kind, "required_count": 1, "optional": false},
			{"kind": &"board_treasure", "objective": "Recover the floating salvage from the waves.", "target_id": treasures[0], "required_count": 1, "optional": false},
			{"kind": &"sell_treasure", "objective": "Sell the recovered spoils at port.", "target_id": origin_id, "required_count": 1, "optional": false},
		],
	}


# --- Selection & Anti-Repetition Helpers --------------------------------

func _pick_shape(forced_shape: StringName, company_filter: StringName) -> StringName:
	if forced_shape != &"" and SHAPES.has(forced_shape):
		return forced_shape

	var pool: Array[StringName] = []
	if company_filter == &"gilded_compass":
		pool = [&"buried_hoard", &"cargo_run", &"riddle_trail"]
	elif company_filter == &"iron_tide":
		pool = [&"drowned_bounty", &"fort_siege", &"open_sea_hunt"]
	elif company_filter == &"sunken_archive":
		pool = [&"riddle_trail", &"wreck_salvage", &"buried_hoard"]
	else:
		pool = SHAPES.duplicate()

	var last_shape: StringName = recent_shapes[recent_shapes.size() - 1] if not recent_shapes.is_empty() else &""
	var filtered: Array[StringName] = []
	for s in pool:
		if s != last_shape:
			filtered.append(s)
	if filtered.is_empty():
		filtered = pool

	# Bias gently toward less-used shapes so all 7 shapes get healthy airtime
	# without ever becoming a predictable fixed cycle.
	var min_used := 1_000_000
	for s in filtered:
		min_used = mini(min_used, int(_shape_counts.get(s, 0)))

	var weighted: Array[StringName] = []
	for s in filtered:
		var count := int(_shape_counts.get(s, 0))
		var weight := 1
		if count == min_used:
			weight = 4
		elif count == min_used + 1:
			weight = 2
		for _w in weight:
			weighted.append(s)

	return weighted[_rng.randi() % weighted.size()]


func _pick_target_island(islands: Array[Dictionary], shape: StringName,
		origin_id: StringName) -> Dictionary:
	var last_island: StringName = recent_islands[recent_islands.size() - 1] if not recent_islands.is_empty() else &""
	var prev_island: StringName = recent_islands[recent_islands.size() - 2] if recent_islands.size() >= 2 else &""

	var preferred: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for isl in islands:
		var id: StringName = isl["id"]
		var kind: StringName = isl["kind"]
		if id == origin_id and islands.size() > 1:
			continue
		var is_outpost := _is_outpost_entry(isl)
		var is_citadel := _is_citadel_entry(isl)
		var is_fort := _is_fort_entry(isl)
		var matches_shape := false
		match shape:
			&"cargo_run":
				matches_shape = is_outpost
			&"fort_siege":
				matches_shape = is_fort
			&"wreck_salvage":
				matches_shape = (kind == &"shipwreck" or kind == &"reef" or kind == &"landmark")
			&"open_sea_hunt":
				matches_shape = not is_outpost
			_:
				matches_shape = (kind == &"treasure_island" or kind == &"landmark" or is_citadel)
		if matches_shape:
			preferred.append(isl)
		if not is_outpost or shape == &"cargo_run":
			fallback.append(isl)

	if fallback.is_empty():
		fallback = islands.duplicate()

	# Strictly forbid repeating the exact previous target island whenever another exists.
	var pick := _pick_excluding(preferred, last_island, prev_island)
	if not pick.is_empty():
		return pick
	pick = _pick_excluding(fallback, last_island, prev_island)
	if not pick.is_empty():
		return pick
	pick = _pick_excluding(islands, last_island, &"")
	if not pick.is_empty():
		return pick
	return islands[0]


func _pick_excluding(pool: Array[Dictionary], forbid_id: StringName,
		soft_avoid_id: StringName) -> Dictionary:
	if pool.is_empty():
		return {}
	var strict_soft: Array[Dictionary] = []
	var strict_only: Array[Dictionary] = []
	for isl in pool:
		var id: StringName = isl["id"]
		if id == forbid_id:
			continue
		strict_only.append(isl)
		if id != soft_avoid_id:
			strict_soft.append(isl)
	if not strict_soft.is_empty():
		return strict_soft[_rng.randi() % strict_soft.size()]
	if not strict_only.is_empty():
		return strict_only[_rng.randi() % strict_only.size()]
	return {}


func _record_history(shape: StringName, island_id: StringName) -> void:
	recent_shapes.append(shape)
	if recent_shapes.size() > 8:
		recent_shapes.pop_front()
	recent_islands.append(island_id)
	if recent_islands.size() > 8:
		recent_islands.pop_front()
	_shape_counts[shape] = int(_shape_counts.get(shape, 0)) + 1


func _make_payoff(treasures: Array[StringName], bonus_gold: int, bonus_renown: int) -> Dictionary:
	var est_gold := bonus_gold
	var est_renown := bonus_renown
	for tid in treasures:
		var entry := TreasureCatalog.get_entry(tid)
		est_gold += int(entry.get("gold_value", 0))
		est_renown += int(entry.get("renown_value", 0))
	return {
		"treasures": treasures,
		"bonus_gold": bonus_gold,
		"bonus_renown": bonus_renown,
		"estimated_gold": est_gold,
		"estimated_renown": est_renown,
	}


func _find_island(islands: Array[Dictionary], target_id: StringName) -> Dictionary:
	for isl in islands:
		if isl["id"] == target_id:
			return isl
	return {}


static func _is_outpost_entry(isl: Dictionary) -> bool:
	var kind: StringName = isl.get("kind", &"")
	var arch: StringName = isl.get("archetype", &"")
	return kind == &"outpost" or kind == &"grand_outpost" or arch == &"outpost" or arch == &"grand_outpost"


static func _is_citadel_entry(isl: Dictionary) -> bool:
	var kind: StringName = isl.get("kind", &"")
	var arch: StringName = isl.get("archetype", &"")
	return kind == &"grand_citadel" or arch == &"grand_citadel"


static func _is_fort_entry(isl: Dictionary) -> bool:
	var kind: StringName = isl.get("kind", &"")
	var arch: StringName = isl.get("archetype", &"")
	return kind == &"fort" or arch == &"fort_rock" or _is_citadel_entry(isl)


func _find_first_of_kind(islands: Array[Dictionary], kind: StringName,
		default_isl: Dictionary) -> Dictionary:
	for isl in islands:
		if isl["kind"] == kind:
			return isl
		if kind == &"outpost" and _is_outpost_entry(isl):
			return isl
		if kind == &"fort" and _is_fort_entry(isl):
			return isl
	return default_isl


func _first_landmark(island: Dictionary, fallback: String) -> String:
	var lms: Array = island.get("landmarks", [])
	return String(lms[0]) if not lms.is_empty() else fallback


func _landmark_at(island: Dictionary, idx: int, fallback: String) -> String:
	var lms: Array = island.get("landmarks", [])
	if lms.is_empty():
		return fallback
	return String(lms[idx % lms.size()])


func _random_landmark(island: Dictionary, fallback: String) -> String:
	var lms: Array = island.get("landmarks", [])
	if lms.is_empty():
		return fallback
	return String(lms[_rng.randi() % lms.size()])


func _pick_str(list: Array[String]) -> String:
	return list[_rng.randi() % list.size()]
