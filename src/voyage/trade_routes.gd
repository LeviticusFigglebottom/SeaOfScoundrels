class_name TradeRoutes
extends RefCounted
## 3-Outpost Merchant Commodity Trade Routes & Arbitrage Pricing for Sea of Scoundrels.
##
## Connects Port Scoundrel, Barnacle Haven, and Galleon's Reach in a circular
## 1.8x-2.4x merchant arbitrage trade triangle with 4 physical Carryable trade
## crates (`Spiced Silk`, `Cinder Rum`, `Gilded Tea`, and rotating `Sea-Salt`).

## Canonical outpost identifiers participating in the archipelago trade triangle.
const OUTPOST_IDS: Array[StringName] = [
	&"port_scoundrel",
	&"barnacle_haven",
	&"galleons_reach",
]

## Strict-ASCII display names for all three merchant outposts.
const OUTPOST_NAMES := {
	&"port_scoundrel": "Port Scoundrel",
	&"barnacle_haven": "Barnacle Haven",
	&"galleons_reach": "Galleon's Reach",
}

const MULT_SURPLUS := 0.85
const MULT_FAIR := 1.25
const MULT_SEA_SALT_HIGH := 1.90

## Canonical merchant trade commodities (IDs mirror TreasureCatalog.CATALOG).
const COMMODITIES := {
	&"commodity_spiced_silk": {
		"id": &"commodity_spiced_silk",
		"name": "Spiced Silk Crate",
		"buy_price": 120,
		"surplus_outpost": &"port_scoundrel",
		"high_demand_outpost": &"galleons_reach",
		"high_demand_mult": 2.25,
		"neutral_outpost": &"barnacle_haven",
		"rotating_demand": false,
		"available_everywhere": false,
		"description": "Bolts of saffron-dyed silk packed in cedar. Surplus at Port Scoundrel; top coin at Galleon's Reach.",
	},
	&"commodity_cinder_rum": {
		"id": &"commodity_cinder_rum",
		"name": "Cinder Rum Cask",
		"buy_price": 140,
		"surplus_outpost": &"barnacle_haven",
		"high_demand_outpost": &"port_scoundrel",
		"high_demand_mult": 2.20,
		"neutral_outpost": &"galleons_reach",
		"rotating_demand": false,
		"available_everywhere": false,
		"description": "Charred-oak casks of volcanic rum. Surplus at Barnacle Haven; prized at Port Scoundrel.",
	},
	&"commodity_gilded_tea": {
		"id": &"commodity_gilded_tea",
		"name": "Gilded Tea Chest",
		"buy_price": 160,
		"surplus_outpost": &"galleons_reach",
		"high_demand_outpost": &"barnacle_haven",
		"high_demand_mult": 2.30,
		"neutral_outpost": &"port_scoundrel",
		"rotating_demand": false,
		"available_everywhere": false,
		"description": "Tin-lined merchant chest of gilded highland tea. Surplus at Galleon's Reach; high demand at Barnacle Haven.",
	},
	&"commodity_sea_salt": {
		"id": &"commodity_sea_salt",
		"name": "Refined Sea-Salt Keg",
		"buy_price": 100,
		"surplus_outpost": &"",
		"high_demand_outpost": &"",
		"high_demand_mult": MULT_SEA_SALT_HIGH,
		"neutral_outpost": &"",
		"rotating_demand": true,
		"available_everywhere": true,
		"description": "Brine-dried sea salt stocked at every port. High demand rotates across outposts each day.",
	},
}


## Return true if `treasure_id` is a Merchant Commodity Trade Route crate.
static func is_commodity(treasure_id: StringName) -> bool:
	return COMMODITIES.has(treasure_id)


## Return defensive copies of all 4 trade commodity definitions.
static func get_all_commodities() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: StringName in COMMODITIES.keys():
		var entry: Dictionary = (COMMODITIES[key] as Dictionary).duplicate(true)
		entry["best_dest_id"] = get_best_destination_outpost(key)
		entry["best_dest_name"] = get_outpost_name(entry["best_dest_id"] as StringName)
		out.append(entry)
	return out


## Return the strict-ASCII display name for an outpost ID.
static func get_outpost_name(outpost_id: StringName) -> String:
	if OUTPOST_NAMES.has(outpost_id):
		return String(OUTPOST_NAMES[outpost_id])
	return String(outpost_id).replace("_", " ").capitalize()


## Return the current day index used to rotate Sea-Salt high demand across outposts.
static func _current_day_index() -> int:
	if Weather != null:
		return posmod(int(Weather.day), OUTPOST_IDS.size())
	return 0


## Return the highest-paying destination outpost for `commodity_id`.
static func get_best_destination_outpost(commodity_id: StringName) -> StringName:
	if not COMMODITIES.has(commodity_id):
		return &"port_scoundrel"
	var spec: Dictionary = COMMODITIES[commodity_id]
	if bool(spec.get("rotating_demand", false)):
		var day_idx := _current_day_index()
		return OUTPOST_IDS[posmod(day_idx + 1, OUTPOST_IDS.size())]
	return spec["high_demand_outpost"] as StringName


## Return the sell price multiplier for `commodity_id` at `outpost_id`.
static func get_demand_multiplier(commodity_id: StringName, outpost_id: StringName) -> float:
	if not COMMODITIES.has(commodity_id):
		return 1.0
	var spec: Dictionary = COMMODITIES[commodity_id]
	var high_mult := float(spec.get("high_demand_mult", 2.0))
	if bool(spec.get("rotating_demand", false)):
		var day_idx := _current_day_index()
		var surplus_id: StringName = OUTPOST_IDS[day_idx]
		var high_id: StringName = OUTPOST_IDS[posmod(day_idx + 1, OUTPOST_IDS.size())]
		if outpost_id == high_id:
			return high_mult
		if outpost_id == surplus_id:
			return MULT_SURPLUS
		return MULT_FAIR
	if outpost_id == (spec["high_demand_outpost"] as StringName):
		return high_mult
	if outpost_id == (spec["surplus_outpost"] as StringName):
		return MULT_SURPLUS
	return MULT_FAIR


## Return the purchase price (gold) for buying `commodity_id` at `outpost_id`.
static func get_buy_price(commodity_id: StringName, outpost_id: StringName) -> int:
	if not COMMODITIES.has(commodity_id):
		return 0
	var spec: Dictionary = COMMODITIES[commodity_id]
	var base_buy := int(spec.get("buy_price", 100))
	if bool(spec.get("available_everywhere", false)):
		return base_buy
	if outpost_id == (spec["surplus_outpost"] as StringName):
		return base_buy
	if outpost_id == (spec["high_demand_outpost"] as StringName):
		return roundi(float(base_buy) * float(spec.get("high_demand_mult", 2.0)))
	return roundi(float(base_buy) * MULT_FAIR)


## Return the merchant sell payout (gold) for delivering `commodity_id` to `outpost_id`.
static func get_sell_price(commodity_id: StringName, outpost_id: StringName) -> int:
	if not COMMODITIES.has(commodity_id):
		return 0
	var spec: Dictionary = COMMODITIES[commodity_id]
	var base_buy := int(spec.get("buy_price", 100))
	var mult := get_demand_multiplier(commodity_id, outpost_id)
	return maxi(1, roundi(float(base_buy) * mult))


## Return a strict-ASCII market demand label: "SURPLUS", "FAIR", or "HIGH DEMAND (2.25x!)".
static func get_demand_label(commodity_id: StringName, outpost_id: StringName) -> String:
	if not COMMODITIES.has(commodity_id):
		return "FAIR"
	var mult := get_demand_multiplier(commodity_id, outpost_id)
	if mult >= 1.80:
		return "HIGH DEMAND (%.2fx!)" % mult
	if mult <= 0.95:
		return "SURPLUS"
	return "FAIR"


## Return the local surplus commodities offered for purchase at `outpost_id`,
## complete with buy price, best destination port, and projected arbitrage profit.
static func get_outpost_manifest(outpost_id: StringName) -> Array[Dictionary]:
	var resolved_outpost := outpost_id if OUTPOST_NAMES.has(outpost_id) else &"port_scoundrel"
	var out: Array[Dictionary] = []
	for key: StringName in COMMODITIES.keys():
		var spec: Dictionary = COMMODITIES[key]
		var best_dest := get_best_destination_outpost(key)
		var include := false
		if bool(spec.get("available_everywhere", false)):
			# Offer Sea-Salt at ports where another outpost currently pays high demand.
			include = (best_dest != resolved_outpost)
		else:
			include = ((spec["surplus_outpost"] as StringName) == resolved_outpost)
		if not include:
			continue
		var buy_price := get_buy_price(key, resolved_outpost)
		var best_sell := get_sell_price(key, best_dest)
		var best_mult := get_demand_multiplier(key, best_dest)
		out.append({
			"id": key,
			"name": String(spec["name"]),
			"buy_price": buy_price,
			"best_dest_id": best_dest,
			"best_dest_name": get_outpost_name(best_dest),
			"best_sell_price": best_sell,
			"best_multiplier": best_mult,
			"projected_profit": best_sell - buy_price,
			"demand_label": get_demand_label(key, best_dest),
			"description": String(spec["description"]),
		})
	return out


## Host-only. Deduct gold from `profile` and spawn a physical Carryable trade crate
## tagged with `origin_outpost_id` and `purchase_price`.
static func purchase_commodity(
	profile: Profile,
	commodity_id: StringName,
	outpost_id: StringName,
	spawn_pos: Vector3,
	parent: Node
) -> Dictionary:
	var best_dest := get_best_destination_outpost(commodity_id)
	if not Net.is_host():
		return {
			"ok": false,
			"item": null,
			"cost": 0,
			"best_dest": best_dest,
			"best_dest_name": get_outpost_name(best_dest),
			"reason": "Host only.",
		}
	if profile == null:
		return {
			"ok": false,
			"item": null,
			"cost": 0,
			"best_dest": best_dest,
			"best_dest_name": get_outpost_name(best_dest),
			"reason": "No captain profile loaded.",
		}
	if not is_commodity(commodity_id):
		return {
			"ok": false,
			"item": null,
			"cost": 0,
			"best_dest": &"",
			"best_dest_name": "",
			"reason": "Unknown trade commodity.",
		}

	var resolved_outpost := outpost_id if OUTPOST_NAMES.has(outpost_id) else &"port_scoundrel"
	var cost := get_buy_price(commodity_id, resolved_outpost)
	if cost <= 0 or not profile.spend_gold(cost):
		return {
			"ok": false,
			"item": null,
			"cost": cost,
			"best_dest": best_dest,
			"best_dest_name": get_outpost_name(best_dest),
			"reason": "Requires %d gold (have %d)." % [cost, int(profile.data.get("gold", 0))],
		}

	var item := TreasureCatalog.create_treasure_carryable(commodity_id, spawn_pos)
	item.set_meta(&"origin_outpost_id", resolved_outpost)
	item.set_meta(&"purchase_price", cost)
	if parent != null and is_instance_valid(parent):
		parent.add_child(item)
		if item.is_inside_tree():
			item.global_position = spawn_pos

	return {
		"ok": true,
		"item": item,
		"cost": cost,
		"best_dest": best_dest,
		"best_dest_name": get_outpost_name(best_dest),
		"projected_payout": get_sell_price(commodity_id, best_dest),
		"reason": "",
	}
