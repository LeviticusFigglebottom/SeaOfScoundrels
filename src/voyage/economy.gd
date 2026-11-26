class_name Economy
extends RefCounted
## Trading companies, curved renown progression, meaningful ship/crew sidegrades,
## cosmetics, and treasure turn-in logic operating on `Profile`.
##
## Per DESIGN.md, unlocks are genuine sidegrades with mechanical trade-offs
## (speed vs. hull strength, downwind vs. close-hauled trim, heavy breach vs.
## quick reload, crew traits) alongside expressive ship cosmetics.

const MAX_RANK := 20

const DEFAULT_LOADOUT := {
	&"hull": &"hull_standard",
	&"sail": &"sail_standard",
	&"cannon": &"cannon_iron",
	&"trait": &"",
	&"flag": &"",
	&"sail_cosmetic": &"",
	&"hull_livery": &"",
	&"crew_uniform": &"",
}

const COMPANIES := {
	&"gilded_compass": {
		"id": &"gilded_compass",
		"name": "Gilded Compass Guild",
		"short_name": "Gilded Compass",
		"representative": "Factor",
		"motto": "Every bearing is a bargain.",
		"focus": "Charts, buried hoards, and merchant contracts.",
		"color": Color(0.92, 0.72, 0.22),
	},
	&"iron_tide": {
		"id": &"iron_tide",
		"name": "Iron Tide Bounty Co.",
		"short_name": "Iron Tide",
		"representative": "Warden",
		"motto": "No dead captain keeps the sea.",
		"focus": "Drowned captains, naval hunts, and sea forts.",
		"color": Color(0.76, 0.24, 0.20),
	},
	&"sunken_archive": {
		"id": &"sunken_archive",
		"name": "The Sunken Archive",
		"short_name": "Sunken Archive",
		"representative": "Archivist",
		"motto": "What the waves swallow, we remember.",
		"focus": "Riddles, shipwrecks, cursed relics, and story voyages.",
		"color": Color(0.20, 0.68, 0.72),
	},
}

const RANK_TITLES: Array[String] = [
	"Deckhand",
	"Wayfarer",
	"Swab-Boss",
	"Boatswain",
	"Chart-Hand",
	"Quartermaster",
	"Corsair",
	"Helmsman",
	"Sea Raider",
	"First Mate",
	"Privateer",
	"Master Mariner",
	"Free Captain",
	"Dread Captain",
	"Commodore",
	"Sea Baron",
	"Storm-Breaker",
	"High Admiral",
	"Sovereign's Hand",
	"Sea Sovereign",
]

## Catalogue of sidegrade fittings, crew traits, and cosmetics.
const UNLOCKS := {
	# --- Hull sidegrades ------------------------------------------------
	&"hull_standard": {
		"id": &"hull_standard",
		"name": "Seasoned Pine Hull",
		"slot": &"hull",
		"category": &"sidegrade",
		"cost": 0,
		"company_id": &"gilded_compass",
		"req_rank": 1,
		"is_default": true,
		"summary": "Balanced pine planking; dependable in fair seas and foul.",
		"modifiers": {
			"speed": 1.0,
			"turn_rate": 1.0,
			"breach_resist": 1.0,
		},
	},
	&"hull_stout_oak": {
		"id": &"hull_stout_oak",
		"name": "Stout Ironwood & Oak Hull",
		"slot": &"hull",
		"category": &"sidegrade",
		"cost": 600,
		"company_id": &"iron_tide",
		"req_rank": 2,
		"is_default": false,
		"summary": "+30% hull breach resistance, -8% top speed.",
		"modifiers": {
			"speed": 0.92,
			"turn_rate": 0.96,
			"breach_resist": 1.30,
		},
	},
	&"hull_swift_cedar": {
		"id": &"hull_swift_cedar",
		"name": "Swift Red Cedar Hull",
		"slot": &"hull",
		"category": &"sidegrade",
		"cost": 650,
		"company_id": &"gilded_compass",
		"req_rank": 2,
		"is_default": false,
		"summary": "+12% top speed & turn rate, -20% breach resistance.",
		"modifiers": {
			"speed": 1.12,
			"turn_rate": 1.12,
			"breach_resist": 0.80,
		},
	},

	# --- Sail sidegrades ------------------------------------------------
	&"sail_standard": {
		"id": &"sail_standard",
		"name": "Square Hemp Mainsail",
		"slot": &"sail",
		"category": &"sidegrade",
		"cost": 0,
		"company_id": &"gilded_compass",
		"req_rank": 1,
		"is_default": true,
		"summary": "Reliable all-points rigging with steady pull.",
		"modifiers": {
			"downwind": 1.0,
			"close_hauled": 1.0,
		},
	},
	&"sail_broad_canvas": {
		"id": &"sail_broad_canvas",
		"name": "Broad Storm-Canvas Rig",
		"slot": &"sail",
		"category": &"sidegrade",
		"cost": 550,
		"company_id": &"gilded_compass",
		"req_rank": 2,
		"is_default": false,
		"summary": "+14% downwind speed, narrower close-hauled arc (-14%).",
		"modifiers": {
			"downwind": 1.14,
			"close_hauled": 0.86,
		},
	},
	&"sail_close_hauled": {
		"id": &"sail_close_hauled",
		"name": "Split-Gaff Close-Hauler",
		"slot": &"sail",
		"category": &"sidegrade",
		"cost": 600,
		"company_id": &"sunken_archive",
		"req_rank": 2,
		"is_default": false,
		"summary": "+22% close-hauled efficiency, -6% pure downwind speed.",
		"modifiers": {
			"downwind": 0.94,
			"close_hauled": 1.22,
		},
	},

	# --- Cannon sidegrades ----------------------------------------------
	&"cannon_iron": {
		"id": &"cannon_iron",
		"name": "Cast-Iron Nine-Pounders",
		"slot": &"cannon",
		"category": &"sidegrade",
		"cost": 0,
		"company_id": &"iron_tide",
		"req_rank": 1,
		"is_default": true,
		"summary": "Balanced iron deck guns; steady cadence and solid punch.",
		"modifiers": {
			"breach_radius": 1.0,
			"reload_scale": 1.0,
		},
	},
	&"cannon_heavy_shot": {
		"id": &"cannon_heavy_shot",
		"name": "Heavy Culverin Broadside",
		"slot": &"cannon",
		"category": &"sidegrade",
		"cost": 750,
		"company_id": &"iron_tide",
		"req_rank": 3,
		"is_default": false,
		"summary": "+25% hull breach radius, +25% reload time.",
		"modifiers": {
			"breach_radius": 1.25,
			"reload_scale": 1.25,
		},
	},
	&"cannon_quick_swivel": {
		"id": &"cannon_quick_swivel",
		"name": "Quick-Breech Swivel Guns",
		"slot": &"cannon",
		"category": &"sidegrade",
		"cost": 700,
		"company_id": &"gilded_compass",
		"req_rank": 3,
		"is_default": false,
		"summary": "-25% reload time, -15% hull breach radius.",
		"modifiers": {
			"breach_radius": 0.85,
			"reload_scale": 0.75,
		},
	},

	# --- Crew traits ----------------------------------------------------
	&"trait_iron_lungs": {
		"id": &"trait_iron_lungs",
		"name": "Iron Lungs",
		"slot": &"trait",
		"category": &"trait",
		"cost": 450,
		"company_id": &"sunken_archive",
		"req_rank": 2,
		"is_default": false,
		"summary": "+30% faster bailing and +25% stronger swimming endurance.",
		"modifiers": {
			"bail_scale": 1.30,
			"swim_scale": 1.25,
		},
	},
	&"trait_keen_lookout": {
		"id": &"trait_keen_lookout",
		"name": "Keen Lookout",
		"slot": &"trait",
		"category": &"trait",
		"cost": 450,
		"company_id": &"gilded_compass",
		"req_rank": 2,
		"is_default": false,
		"summary": "+40% horizon sighting callout range for sails, squalls, and reefs.",
		"modifiers": {
			"lookout_scale": 1.40,
		},
	},
	&"trait_steady_hands": {
		"id": &"trait_steady_hands",
		"name": "Steady Hands",
		"slot": &"trait",
		"category": &"trait",
		"cost": 500,
		"company_id": &"iron_tide",
		"req_rank": 2,
		"is_default": false,
		"summary": "+25% cannon loading and hull patching speed in rough swells.",
		"modifiers": {
			"reload_scale": 0.80,
			"patch_scale": 1.25,
		},
	},

	# --- Ship cosmetics -------------------------------------------------
	&"flag_crimson_gull": {
		"id": &"flag_crimson_gull",
		"name": "Crimson Gull Pennant",
		"slot": &"flag",
		"category": &"cosmetic",
		"cost": 300,
		"company_id": &"gilded_compass",
		"req_rank": 1,
		"is_default": false,
		"summary": "Scarlet swallowtail pennant bearing a gold diving gull.",
		"tint": Color(0.84, 0.16, 0.18),
		"modifiers": {},
	},
	&"flag_emerald_kraken": {
		"id": &"flag_emerald_kraken",
		"name": "Emerald Kraken Standard",
		"slot": &"flag",
		"category": &"cosmetic",
		"cost": 450,
		"company_id": &"sunken_archive",
		"req_rank": 3,
		"is_default": false,
		"summary": "Deep sea-green banner stitched with coiled silver tentacles.",
		"tint": Color(0.14, 0.68, 0.48),
		"modifiers": {},
	},
	&"sail_sunburst": {
		"id": &"sail_sunburst",
		"name": "Sunburst Ochre Canvas",
		"slot": &"sail_cosmetic",
		"category": &"cosmetic",
		"cost": 400,
		"company_id": &"gilded_compass",
		"req_rank": 2,
		"is_default": false,
		"summary": "Warm golden-ochre canvas painted with a sovereign compass sunburst.",
		"tint": Color(0.95, 0.72, 0.24),
		"emblem_mode": 7,
		"modifiers": {},
	},
	&"sail_midnight_wave": {
		"id": &"sail_midnight_wave",
		"name": "Midnight Wave Insignia",
		"slot": &"sail_cosmetic",
		"category": &"cosmetic",
		"cost": 500,
		"company_id": &"iron_tide",
		"req_rank": 3,
		"is_default": false,
		"summary": "Indigo-dyed mainsail emblazoned with luminous tide runes and foaming crest.",
		"tint": Color(0.14, 0.22, 0.42),
		"emblem_mode": 5,
		"modifiers": {},
	},
	&"sail_gilded_compass": {
		"id": &"sail_gilded_compass",
		"name": "Gilded Compass Heraldic Sails",
		"slot": &"sail_cosmetic",
		"category": &"cosmetic",
		"cost": 380,
		"company_id": &"gilded_compass",
		"req_rank": 1,
		"is_default": false,
		"summary": "Royal azure and burnished gold heraldic canvas crowned with the Guild's compass rose.",
		"tint": Color(0.20, 0.45, 0.86),
		"emblem_mode": 4,
		"modifiers": {},
	},
	&"sail_sunken_archive": {
		"id": &"sail_sunken_archive",
		"name": "Sunken Archive Rune Sails",
		"slot": &"sail_cosmetic",
		"category": &"cosmetic",
		"cost": 480,
		"company_id": &"sunken_archive",
		"req_rank": 2,
		"is_default": false,
		"summary": "Abyssal obsidian cloth stitched with glowing turquoise sea-archive tide sigils.",
		"tint": Color(0.14, 0.84, 0.72),
		"emblem_mode": 5,
		"modifiers": {},
	},
	&"sail_iron_tide": {
		"id": &"sail_iron_tide",
		"name": "Iron Tide War-Chevron Sails",
		"slot": &"sail_cosmetic",
		"category": &"cosmetic",
		"cost": 480,
		"company_id": &"iron_tide",
		"req_rank": 2,
		"is_default": false,
		"summary": "War-crimson and sun-bleached ivory chevrons flown by Iron Tide bounty captains.",
		"tint": Color(0.76, 0.16, 0.18),
		"emblem_mode": 6,
		"modifiers": {},
	},

	# --- Hull paint liveries --------------------------------------------
	&"hull_royal_azure": {
		"id": &"hull_royal_azure",
		"name": "Admiral's Azure Hull",
		"slot": &"hull_livery",
		"category": &"cosmetic",
		"cost": 350,
		"company_id": &"gilded_compass",
		"req_rank": 1,
		"is_default": false,
		"summary": "Royal cobalt-blue timber coat finished in warm maritime varnish.",
		"tint": Color(0.62, 0.78, 1.0),
		"glow_accent": Color.BLACK,
		"modifiers": {},
	},
	&"hull_crimson_corsair": {
		"id": &"hull_crimson_corsair",
		"name": "Privateer Crimson Hull",
		"slot": &"hull_livery",
		"category": &"cosmetic",
		"cost": 450,
		"company_id": &"iron_tide",
		"req_rank": 2,
		"is_default": false,
		"summary": "Lacquered dark crimson-mahogany planking favored by bold privateers.",
		"tint": Color(1.0, 0.56, 0.48),
		"glow_accent": Color.BLACK,
		"modifiers": {},
	},
	&"hull_emerald_archive": {
		"id": &"hull_emerald_archive",
		"name": "Archive Verdigris Hull",
		"slot": &"hull_livery",
		"category": &"cosmetic",
		"cost": 450,
		"company_id": &"sunken_archive",
		"req_rank": 2,
		"is_default": false,
		"summary": "Seaworn turquoise-jade patina with a subtle emerald lantern shimmer.",
		"tint": Color(0.58, 0.94, 0.84),
		"glow_accent": Color(0.18, 0.72, 0.58),
		"modifiers": {},
	},
	&"hull_obsidian_sovereign": {
		"id": &"hull_obsidian_sovereign",
		"name": "Sovereign Pitch & Gold",
		"slot": &"hull_livery",
		"category": &"cosmetic",
		"cost": 750,
		"company_id": &"gilded_compass",
		"req_rank": 4,
		"is_default": false,
		"summary": "Dramatic charred-pitch hull crowned with a rich amber lantern glow.",
		"tint": Color(0.42, 0.40, 0.44),
		"glow_accent": Color(0.95, 0.68, 0.22),
		"modifiers": {},
	},

	# --- Crew uniform cosmetics -----------------------------------------
	&"crew_gilded_admiral": {
		"id": &"crew_gilded_admiral",
		"name": "Gilded Admiral Coats",
		"slot": &"crew_uniform",
		"category": &"cosmetic",
		"cost": 320,
		"company_id": &"gilded_compass",
		"req_rank": 1,
		"is_default": false,
		"summary": "Crisp navy-cobalt maritime coats trimmed in burnished compass-guild gold.",
		"tint": Color(0.16, 0.30, 0.56),
		"accent_tint": Color(0.92, 0.74, 0.24),
		"modifiers": {},
	},
	&"crew_crimson_corsair": {
		"id": &"crew_crimson_corsair",
		"name": "Privateer Crimson Gear",
		"slot": &"crew_uniform",
		"category": &"cosmetic",
		"cost": 420,
		"company_id": &"iron_tide",
		"req_rank": 2,
		"is_default": false,
		"summary": "Deep privateer-crimson waistcoats paired with gilded iron-tide sashes.",
		"tint": Color(0.62, 0.14, 0.16),
		"accent_tint": Color(0.90, 0.70, 0.26),
		"modifiers": {},
	},
	&"crew_archive_mystic": {
		"id": &"crew_archive_mystic",
		"name": "Archive Sea-Jade Cloaks",
		"slot": &"crew_uniform",
		"category": &"cosmetic",
		"cost": 420,
		"company_id": &"sunken_archive",
		"req_rank": 2,
		"is_default": false,
		"summary": "Abyssal sea-teal navigator cloaks accented in luminous archive turquoise.",
		"tint": Color(0.12, 0.32, 0.36),
		"accent_tint": Color(0.20, 0.84, 0.70),
		"modifiers": {},
	},
	&"crew_sovereign_velvet": {
		"id": &"crew_sovereign_velvet",
		"name": "Sovereign Velvet & Gold",
		"slot": &"crew_uniform",
		"category": &"cosmetic",
		"cost": 680,
		"company_id": &"gilded_compass",
		"req_rank": 4,
		"is_default": false,
		"summary": "Royal plum-velvet captain's livery embroidered with bright sovereign gold.",
		"tint": Color(0.24, 0.15, 0.28),
		"accent_tint": Color(0.96, 0.76, 0.22),
		"modifiers": {},
	},
}


# --- Company & Rank Queries ---------------------------------------------

static func get_companies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in COMPANIES.keys():
		out.append((COMPANIES[key] as Dictionary).duplicate(true))
	return out


static func get_company(company_id: StringName) -> Dictionary:
	if not COMPANIES.has(company_id):
		return {}
	return (COMPANIES[company_id] as Dictionary).duplicate(true)


## Cumulative renown points required to reach `rank` (1..MAX_RANK).
## Curved polynomial: Rank 1 = 0, Rank 2 = 100, Rank 3 = 300, ..., Rank 20 = 19000.
static func rank_threshold(rank: int) -> int:
	var r := clampi(rank, 1, MAX_RANK)
	return 50 * (r - 1) * r


static func rank_for_renown(points: int) -> int:
	var p := maxi(0, points)
	var rank := 1
	for r in range(2, MAX_RANK + 1):
		if p >= rank_threshold(r):
			rank = r
		else:
			break
	return rank


static func rank_title(rank: int) -> String:
	var idx := clampi(rank, 1, RANK_TITLES.size()) - 1
	return RANK_TITLES[idx]


static func get_company_renown(profile: Profile, company_id: StringName) -> int:
	if profile == null:
		return 0
	var renown_map: Dictionary = profile.data.get("renown", {})
	var key_str := String(company_id)
	if renown_map.has(key_str):
		return maxi(0, int(renown_map[key_str]))
	if renown_map.has(company_id):
		return maxi(0, int(renown_map[company_id]))
	return 0


static func get_company_rank(profile: Profile, company_id: StringName) -> int:
	return rank_for_renown(get_company_renown(profile, company_id))


static func get_company_progress(profile: Profile, company_id: StringName) -> Dictionary:
	var points := get_company_renown(profile, company_id)
	var rank := rank_for_renown(points)
	var floor_pts := rank_threshold(rank)
	var is_max := rank >= MAX_RANK
	var next_pts := floor_pts if is_max else rank_threshold(rank + 1)
	var frac := 1.0 if is_max else clampf(
		float(points - floor_pts) / maxf(1.0, float(next_pts - floor_pts)), 0.0, 1.0)
	return {
		"company_id": company_id,
		"rank": rank,
		"title": rank_title(rank),
		"points": points,
		"current_floor": floor_pts,
		"next_threshold": next_pts,
		"progress_frac": frac,
		"is_max": is_max,
	}


# --- Unlocks, Purchasing & Loadout --------------------------------------

static func get_unlock(unlock_id: StringName) -> Dictionary:
	if not UNLOCKS.has(unlock_id):
		return {}
	return (UNLOCKS[unlock_id] as Dictionary).duplicate(true)


static func get_all_unlocks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in UNLOCKS.keys():
		out.append((UNLOCKS[key] as Dictionary).duplicate(true))
	return out


static func get_unlocks_by_slot(slot: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in UNLOCKS.keys():
		var entry: Dictionary = UNLOCKS[key]
		if entry["slot"] == slot:
			out.append(entry.duplicate(true))
	return out


static func is_unlocked(profile: Profile, unlock_id: StringName) -> bool:
	if not UNLOCKS.has(unlock_id):
		return false
	var entry: Dictionary = UNLOCKS[unlock_id]
	if bool(entry.get("is_default", false)):
		return true
	if profile == null:
		return false
	return profile.has_unlock(String(unlock_id))


static func get_purchase_blocker(profile: Profile, unlock_id: StringName) -> String:
	if profile == null:
		return "No captain profile loaded."
	if not UNLOCKS.has(unlock_id):
		return "Unknown fitting '%s'." % unlock_id
	if is_unlocked(profile, unlock_id):
		return "Already owned."
	var entry: Dictionary = UNLOCKS[unlock_id]
	var company_id: StringName = entry["company_id"]
	var req_rank: int = int(entry["req_rank"])
	var current_rank := get_company_rank(profile, company_id)
	if current_rank < req_rank:
		var comp_name := String(COMPANIES.get(company_id, {}).get("name", String(company_id)))
		return "Requires %s Rank %d (currently Rank %d)." % [comp_name, req_rank, current_rank]
	var cost: int = int(entry["cost"])
	var gold: int = int(profile.data.get("gold", 0))
	if gold < cost:
		return "Requires %d gold (have %d)." % [cost, gold]
	return ""


static func can_purchase(profile: Profile, unlock_id: StringName) -> bool:
	return get_purchase_blocker(profile, unlock_id) == ""


static func purchase_unlock(profile: Profile, unlock_id: StringName) -> Dictionary:
	var blocker := get_purchase_blocker(profile, unlock_id)
	if blocker != "":
		return {
			"ok": false,
			"unlock_id": unlock_id,
			"cost": 0,
			"remaining_gold": int(profile.data.get("gold", 0)) if profile != null else 0,
			"reason": blocker,
		}
	var entry: Dictionary = UNLOCKS[unlock_id]
	var cost: int = int(entry["cost"])
	if not profile.spend_gold(cost):
		return {
			"ok": false,
			"unlock_id": unlock_id,
			"cost": cost,
			"remaining_gold": int(profile.data.get("gold", 0)),
			"reason": "Insufficient gold.",
		}
	profile.unlock(String(unlock_id))
	return {
		"ok": true,
		"unlock_id": unlock_id,
		"name": String(entry["name"]),
		"slot": entry["slot"],
		"cost": cost,
		"remaining_gold": int(profile.data.get("gold", 0)),
		"reason": "",
	}


static func equip_loadout(profile: Profile, slot: StringName, unlock_id: StringName) -> bool:
	if profile == null or not DEFAULT_LOADOUT.has(slot):
		return false
	if not profile.data.has("loadout") or not (profile.data["loadout"] is Dictionary):
		profile.data["loadout"] = {}
	var loadout: Dictionary = profile.data["loadout"]
	if unlock_id == &"":
		# Clearing an optional slot (trait or cosmetic) restores its default.
		var fallback: StringName = DEFAULT_LOADOUT[slot]
		if fallback == &"":
			loadout.erase(String(slot))
		else:
			loadout[String(slot)] = String(fallback)
		return true
	if not UNLOCKS.has(unlock_id):
		return false
	var entry: Dictionary = UNLOCKS[unlock_id]
	if entry["slot"] != slot:
		return false
	if not is_unlocked(profile, unlock_id):
		return false
	loadout[String(slot)] = String(unlock_id)
	return true


static func get_equipped(profile: Profile, slot: StringName) -> StringName:
	var fallback: StringName = DEFAULT_LOADOUT.get(slot, &"")
	if profile == null:
		return fallback
	var loadout_raw: Variant = profile.data.get("loadout", {})
	if not (loadout_raw is Dictionary):
		return fallback
	var loadout: Dictionary = loadout_raw
	var raw: Variant = loadout.get(String(slot), loadout.get(slot, ""))
	if String(raw) == "":
		return fallback
	var id := StringName(String(raw))
	if not UNLOCKS.has(id) or UNLOCKS[id]["slot"] != slot or not is_unlocked(profile, id):
		return fallback
	return id


## Compute exact aggregated ship & crew multipliers from the captain's loadout.
static func get_ship_modifiers(profile: Profile) -> Dictionary:
	var mods := {
		"speed": 1.0,
		"turn_rate": 1.0,
		"downwind": 1.0,
		"close_hauled": 1.0,
		"breach_resist": 1.0,
		"breach_radius": 1.0,
		"reload_scale": 1.0,
		"patch_scale": 1.0,
		"bail_scale": 1.0,
		"swim_scale": 1.0,
		"lookout_scale": 1.0,
		"hull_id": get_equipped(profile, &"hull"),
		"sail_id": get_equipped(profile, &"sail"),
		"cannon_id": get_equipped(profile, &"cannon"),
		"trait_id": get_equipped(profile, &"trait"),
		"flag_id": get_equipped(profile, &"flag"),
		"sail_cosmetic_id": get_equipped(profile, &"sail_cosmetic"),
		"sail_emblem_mode": 0,
		"hull_livery_id": get_equipped(profile, &"hull_livery"),
		"crew_uniform_id": get_equipped(profile, &"crew_uniform"),
	}
	var sail_cos_id: StringName = mods["sail_cosmetic_id"]
	if sail_cos_id != &"" and UNLOCKS.has(sail_cos_id):
		mods["sail_emblem_mode"] = int((UNLOCKS[sail_cos_id] as Dictionary).get("emblem_mode", 0))
	for slot in [&"hull", &"sail", &"cannon", &"trait"]:
		var equipped_id: StringName = get_equipped(profile, slot)
		if equipped_id == &"" or not UNLOCKS.has(equipped_id):
			continue
		var entry: Dictionary = UNLOCKS[equipped_id]
		var entry_mods: Dictionary = entry.get("modifiers", {})
		for stat_key in entry_mods.keys():
			if mods.has(stat_key):
				mods[stat_key] = float(mods[stat_key]) * float(entry_mods[stat_key])
	return mods


# --- Treasure Turn-in ---------------------------------------------------

## Sell a piece of treasure to its trading company, awarding gold & renown,
## updating profile stats, and returning a rich summary (including rank-up notice).
static func sell_treasure(profile: Profile, treasure_info: Dictionary,
		company_bonus: float = 1.0) -> Dictionary:
	if profile == null:
		return {"ok": false, "reason": "No profile."}
	var raw_id: Variant = treasure_info.get("treasure_id", treasure_info.get("id", &""))
	var tid := StringName(String(raw_id))
	var base := TreasureCatalog.get_entry(tid) if tid != &"" else {}

	var item_name := String(treasure_info.get("name", base.get("name", "Treasure")))
	var company_id := StringName(String(treasure_info.get("company_id",
			base.get("company_id", &"gilded_compass"))))
	if not COMPANIES.has(company_id):
		company_id = &"gilded_compass"

	var base_gold: int = int(treasure_info.get("base_gold_value", base.get("gold_value", 0)))
	var is_fragile: bool = bool(treasure_info.get("fragile", base.get("fragile", false)))
	var gold_raw: int = int(treasure_info.get("gold_value", base_gold))
	if is_fragile and treasure_info.has("integrity"):
		var effective := TreasureCatalog.compute_effective_value(
			base_gold if base_gold > 0 else gold_raw, float(treasure_info["integrity"]), true)
		if not treasure_info.has("gold_value"):
			gold_raw = effective
		else:
			gold_raw = mini(gold_raw, effective)

	var gold_awarded := maxi(0, roundi(float(gold_raw) * maxf(0.1, company_bonus)))
	var renown_raw: int = int(treasure_info.get("renown_value", base.get("renown_value", 0)))
	var renown_awarded := maxi(0, roundi(float(renown_raw) * maxf(0.1, company_bonus)))

	var old_rank := get_company_rank(profile, company_id)
	profile.add_gold(gold_awarded)
	profile.add_renown(String(company_id), renown_awarded)
	profile.bump_stat("chests_sold", 1)
	profile.bump_stat("gold_earned", gold_awarded)
	var new_rank := get_company_rank(profile, company_id)

	var ranked_up := new_rank > old_rank
	var new_title := rank_title(new_rank)
	var company_name := String(COMPANIES[company_id]["name"])
	var rank_up_notice := ""
	if ranked_up:
		rank_up_notice = "%s: Promoted to Rank %d — %s!" % [company_name, new_rank, new_title]

	return {
		"ok": true,
		"treasure_id": tid,
		"name": item_name,
		"company_id": company_id,
		"company_name": company_name,
		"gold_awarded": gold_awarded,
		"renown_awarded": renown_awarded,
		"total_gold": int(profile.data.get("gold", 0)),
		"old_rank": old_rank,
		"new_rank": new_rank,
		"ranked_up": ranked_up,
		"rank_title": new_title,
		"rank_up_notice": rank_up_notice,
	}
