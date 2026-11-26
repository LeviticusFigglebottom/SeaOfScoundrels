class_name TreasureCatalog
extends RefCounted
## Original treasure catalogue, metadata helpers, aboard-hazard ticking, and
## physical Carryable factory for Sea of Scoundrels.
##
## Every treasure has a distinct tier, weight, gold & renown value, trading
## company affinity, visual palette, and optional special trait (cursed bilge
## weeping or fragile cargo degradation).

const CHEST_GLB_PATH := "res://assets/generated/props/chest_treasure.glb"
const TREASURE_GROUP := &"treasure"

## Minimum fraction of base value a fragile item retains even when battered.
const FRAGILE_MIN_VALUE_FRAC := 0.25
## Impact drop speed (m/s) above which fragile cargo cracks on landing.
const FRAGILE_IMPACT_THRESHOLD := 3.5
## Integrity lost per second when fragile cargo is submerged in seawater.
const FRAGILE_SUBMERGE_DECAY := 0.06

## Static WeakRef caches sharing sculpted ArrayMesh & material resources across spawns
## without retaining strong static GPU Resource references at engine shutdown.
static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}

## Canonical treasure definitions keyed by StringName id.
const CATALOG := {
	&"driftwood_chest": {
		"id": &"driftwood_chest",
		"name": "Driftwood Strongbox",
		"tier": 1,
		"tier_label": "Driftwood",
		"gold_value": 120,
		"renown_value": 20,
		"company_id": &"gilded_compass",
		"mass_kg": 18.0,
		"carry_speed_factor": 0.76,
		"buoyancy": 1.65,
		"float_radius": 0.26,
		"shape": &"chest",
		"tint": Color(0.56, 0.42, 0.28),
		"accent_tint": Color(0.42, 0.44, 0.46),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Salt-bleached pine bound in pitted iron, stuffed with bent silver and dockyard scrips.",
	},
	&"wayfarer_chest": {
		"id": &"wayfarer_chest",
		"name": "Wayfarer's Chest",
		"tier": 2,
		"tier_label": "Wayfarer",
		"gold_value": 240,
		"renown_value": 40,
		"company_id": &"gilded_compass",
		"mass_kg": 22.0,
		"carry_speed_factor": 0.73,
		"buoyancy": 1.60,
		"float_radius": 0.28,
		"shape": &"chest",
		"tint": Color(0.45, 0.28, 0.16),
		"accent_tint": Color(0.72, 0.56, 0.24),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Tarred oak chest strapped in dull brass; heavy enough to earn a grin at any wharf.",
	},
	&"corsair_chest": {
		"id": &"corsair_chest",
		"name": "Corsair's War-Chest",
		"tier": 3,
		"tier_label": "Corsair",
		"gold_value": 420,
		"renown_value": 65,
		"company_id": &"gilded_compass",
		"mass_kg": 26.0,
		"carry_speed_factor": 0.70,
		"buoyancy": 1.55,
		"float_radius": 0.30,
		"shape": &"chest",
		"tint": Color(0.38, 0.17, 0.14),
		"accent_tint": Color(0.84, 0.68, 0.26),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Iron-ribbed war chest scarred by cutlass nicks, brimming with minted crowns.",
	},
	&"sovereign_chest": {
		"id": &"sovereign_chest",
		"name": "Sovereign's Strongbox",
		"tier": 4,
		"tier_label": "Sovereign",
		"gold_value": 700,
		"renown_value": 100,
		"company_id": &"gilded_compass",
		"mass_kg": 30.0,
		"carry_speed_factor": 0.67,
		"buoyancy": 1.50,
		"float_radius": 0.31,
		"shape": &"chest",
		"tint": Color(0.48, 0.12, 0.14),
		"accent_tint": Color(0.96, 0.78, 0.24),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Velvet-lined crimson strongbox studded with gilded rosettes. Every rival on the sea wants it.",
	},
	&"weeping_bilge_chest": {
		"id": &"weeping_bilge_chest",
		"name": "Cursed Bilge-Weep Chest",
		"tier": 5,
		"tier_label": "Cursed",
		"gold_value": 1100,
		"renown_value": 150,
		"company_id": &"sunken_archive",
		"mass_kg": 34.0,
		"carry_speed_factor": 0.64,
		"buoyancy": 1.45,
		"float_radius": 0.32,
		"shape": &"chest",
		"tint": Color(0.12, 0.26, 0.34),
		"accent_tint": Color(0.24, 0.92, 0.82),
		"cursed": true,
		"curse_flood_rate": 0.018,
		"fragile": false,
		"description": "Barnacle-crusted coffer that endlessly weeps icy seawater into the hold. Keep a bucket ready.",
	},
	&"drowned_skull": {
		"id": &"drowned_skull",
		"name": "Relic Skull of the Drowned",
		"tier": 2,
		"tier_label": "Relic",
		"gold_value": 360,
		"renown_value": 60,
		"company_id": &"iron_tide",
		"mass_kg": 7.0,
		"carry_speed_factor": 0.86,
		"buoyancy": 1.75,
		"float_radius": 0.20,
		"shape": &"skull",
		"tint": Color(0.80, 0.82, 0.74),
		"accent_tint": Color(0.26, 0.95, 0.56),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Coral-flecked skull humming with pale sea-fire; Iron Tide Wardens pay well for proof of a fall.",
	},
	&"captains_skull": {
		"id": &"captains_skull",
		"name": "Drowned Captain's Skull",
		"tier": 4,
		"tier_label": "Bounty",
		"gold_value": 680,
		"renown_value": 110,
		"company_id": &"iron_tide",
		"mass_kg": 8.5,
		"carry_speed_factor": 0.84,
		"buoyancy": 1.75,
		"float_radius": 0.22,
		"shape": &"skull",
		"tint": Color(0.76, 0.74, 0.68),
		"accent_tint": Color(0.95, 0.42, 0.16),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Crowned with a rusted tricorn clasp and ember-bright sockets. The trophy of a hunted scourge.",
	},
	&"archive_chalice": {
		"id": &"archive_chalice",
		"name": "Gilded Tide-Chalice",
		"tier": 2,
		"tier_label": "Artifact",
		"gold_value": 310,
		"renown_value": 55,
		"company_id": &"sunken_archive",
		"mass_kg": 6.0,
		"carry_speed_factor": 0.88,
		"buoyancy": 1.65,
		"float_radius": 0.18,
		"shape": &"chalice",
		"tint": Color(0.98, 0.74, 0.16),
		"accent_tint": Color(0.16, 0.70, 0.76),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Fluted gold ceremonial cup etched with tide-charts of a vanished archipelago.",
	},
	&"spice_crate": {
		"id": &"spice_crate",
		"name": "Fragile Spice Crate",
		"tier": 3,
		"tier_label": "Merchant",
		"gold_value": 450,
		"renown_value": 75,
		"company_id": &"gilded_compass",
		"mass_kg": 16.0,
		"carry_speed_factor": 0.78,
		"buoyancy": 1.85,
		"float_radius": 0.26,
		"shape": &"crate",
		"tint": Color(0.76, 0.44, 0.16),
		"accent_tint": Color(0.80, 0.20, 0.14),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": true,
		"description": "Wax-sealed jars of saffron and star-clove. Handle gently and keep dry or the Guild docks your pay.",
	},
	&"ledger_coffer": {
		"id": &"ledger_coffer",
		"name": "The Salt-King's Ledger Coffer",
		"tier": 5,
		"tier_label": "Story Relic",
		"gold_value": 950,
		"renown_value": 140,
		"company_id": &"sunken_archive",
		"mass_kg": 28.0,
		"carry_speed_factor": 0.68,
		"buoyancy": 1.55,
		"float_radius": 0.30,
		"shape": &"coffer",
		"tint": Color(0.18, 0.22, 0.36),
		"accent_tint": Color(0.96, 0.80, 0.30),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"description": "Bronze-bound strongbox holding the Salt-King's ciphered shipping ledgers and tide-vault bearings.",
	},
	&"blazing_rage_chest": {
		"id": &"blazing_rage_chest",
		"name": "Chest of Blazing Rage",
		"tier": 4,
		"tier_label": "Cursed Relic",
		"gold_value": 820,
		"renown_value": 115,
		"company_id": &"iron_tide",
		"mass_kg": 30.0,
		"carry_speed_factor": 0.66,
		"buoyancy": 1.45,
		"float_radius": 0.30,
		"shape": &"rage_chest",
		"tint": Color(0.24, 0.14, 0.12),
		"accent_tint": Color(1.0, 0.42, 0.08),
		"cursed": true,
		"curse_flood_rate": 0.0,
		"curse_heat_rate": 0.055,
		"fragile": false,
		"description": "Forged from volcanic iron. Builds searing ember heat aboard ship and ignites deck fires unless cooled with water!",
	},
	&"commodity_spiced_silk": {
		"id": &"commodity_spiced_silk",
		"name": "Spiced Silk Crate",
		"tier": 2,
		"tier_label": "Trade Goods",
		"gold_value": 120,
		"renown_value": 24,
		"company_id": &"gilded_compass",
		"mass_kg": 15.0,
		"carry_speed_factor": 0.78,
		"buoyancy": 1.85,
		"float_radius": 0.26,
		"shape": &"crate",
		"tint": Color(0.62, 0.34, 0.18),
		"accent_tint": Color(0.84, 0.18, 0.36),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"commodity": true,
		"description": "Bolts of saffron-dyed merchant silk sealed in cedar. Surplus at Port Scoundrel; top coin at Galleon's Reach.",
	},
	&"commodity_cinder_rum": {
		"id": &"commodity_cinder_rum",
		"name": "Cinder Rum Cask",
		"tier": 2,
		"tier_label": "Trade Goods",
		"gold_value": 140,
		"renown_value": 28,
		"company_id": &"gilded_compass",
		"mass_kg": 17.0,
		"carry_speed_factor": 0.76,
		"buoyancy": 1.80,
		"float_radius": 0.26,
		"shape": &"crate",
		"tint": Color(0.46, 0.26, 0.14),
		"accent_tint": Color(0.92, 0.42, 0.12),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"commodity": true,
		"description": "Charred-oak casks of volcanic rum. Surplus at Barnacle Haven; prized by merchants at Port Scoundrel.",
	},
	&"commodity_gilded_tea": {
		"id": &"commodity_gilded_tea",
		"name": "Gilded Tea Chest",
		"tier": 2,
		"tier_label": "Trade Goods",
		"gold_value": 160,
		"renown_value": 32,
		"company_id": &"gilded_compass",
		"mass_kg": 16.0,
		"carry_speed_factor": 0.78,
		"buoyancy": 1.82,
		"float_radius": 0.26,
		"shape": &"crate",
		"tint": Color(0.32, 0.42, 0.24),
		"accent_tint": Color(0.94, 0.74, 0.18),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"commodity": true,
		"description": "Tin-lined merchant chest of gilded highland tea. Surplus at Galleon's Reach; high demand at Barnacle Haven.",
	},
	&"commodity_sea_salt": {
		"id": &"commodity_sea_salt",
		"name": "Refined Sea-Salt Keg",
		"tier": 1,
		"tier_label": "Trade Goods",
		"gold_value": 100,
		"renown_value": 20,
		"company_id": &"gilded_compass",
		"mass_kg": 18.0,
		"carry_speed_factor": 0.77,
		"buoyancy": 1.78,
		"float_radius": 0.26,
		"shape": &"crate",
		"tint": Color(0.56, 0.62, 0.66),
		"accent_tint": Color(0.22, 0.62, 0.78),
		"cursed": false,
		"curse_flood_rate": 0.0,
		"fragile": false,
		"commodity": true,
		"description": "Brine-dried sea salt stocked at every port. High demand rotates across outposts each day.",
	},
}


static func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in CATALOG.keys():
		ids.append(key)
	return ids


static func has_treasure(treasure_id: StringName) -> bool:
	return CATALOG.has(treasure_id)


static func get_entry(treasure_id: StringName) -> Dictionary:
	if not CATALOG.has(treasure_id):
		return {}
	return (CATALOG[treasure_id] as Dictionary).duplicate(true)


static func get_by_company(company_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in CATALOG.keys():
		var entry: Dictionary = CATALOG[key]
		if entry["company_id"] == company_id:
			out.append(entry.duplicate(true))
	return out


static func get_by_tier(min_tier: int, max_tier: int = 5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in CATALOG.keys():
		var entry: Dictionary = CATALOG[key]
		var tier: int = int(entry["tier"])
		if tier >= min_tier and tier <= max_tier:
			out.append(entry.duplicate(true))
	return out


static func pick_random_for_tier(rng: RandomNumberGenerator, min_tier: int,
		max_tier: int = 5, company_id: StringName = &"") -> StringName:
	var candidates: Array[StringName] = []
	for key in CATALOG.keys():
		var entry: Dictionary = CATALOG[key]
		if bool(entry.get("commodity", false)):
			continue
		var tier: int = int(entry["tier"])
		if tier < min_tier or tier > max_tier:
			continue
		if company_id != &"" and entry["company_id"] != company_id:
			continue
		candidates.append(key)
	if candidates.is_empty():
		return &"wayfarer_chest"
	return candidates[rng.randi() % candidates.size()]


static func compute_effective_value(base_gold: int, integrity: float, fragile: bool = true) -> int:
	if not fragile:
		return maxi(0, base_gold)
	var frac := lerpf(FRAGILE_MIN_VALUE_FRAC, 1.0, clampf(integrity, 0.0, 1.0))
	return maxi(1, roundi(float(base_gold) * frac))


## Create a physical Carryable tagged with all treasure metadata and styled visuals.
static func create_treasure_carryable(treasure_id: StringName,
		world_pos: Vector3 = Vector3.ZERO) -> Carryable:
	var resolved_id := treasure_id
	if not CATALOG.has(resolved_id):
		push_warning("TreasureCatalog: unknown treasure_id '%s', falling back to driftwood_chest" % treasure_id)
		resolved_id = &"driftwood_chest"
	var entry: Dictionary = CATALOG[resolved_id]

	var item := Carryable.new()
	item.name = String(resolved_id)
	item.item_name = String(entry["name"])
	item.mass = float(entry["mass_kg"])
	item.buoyancy = float(entry["buoyancy"])
	item.float_radius = float(entry["float_radius"])
	item.carry_speed_factor = float(entry["carry_speed_factor"])
	item.collision_layer = Carryable.LAYER
	item.collision_mask = Carryable.MASK
	item.position = world_pos
	item.add_to_group(TREASURE_GROUP)

	# Tag metadata cleanly for Outpost buyers, VoyageManager, and WorldDirector.
	item.set_meta(&"treasure_id", resolved_id)
	item.set_meta(&"treasure_name", String(entry["name"]))
	item.set_meta(&"tier", int(entry["tier"]))
	item.set_meta(&"base_gold_value", int(entry["gold_value"]))
	item.set_meta(&"gold_value", int(entry["gold_value"]))
	item.set_meta(&"renown_value", int(entry["renown_value"]))
	item.set_meta(&"company_id", entry["company_id"])
	item.set_meta(&"cursed", bool(entry["cursed"]))
	item.set_meta(&"fragile", bool(entry["fragile"]))
	item.set_meta(&"curse_flood_rate", float(entry["curse_flood_rate"]))
	var heat_rate := float(entry.get("curse_heat_rate", 0.0))
	item.set_meta(&"curse_heat_rate", heat_rate)
	if heat_rate > 0.0:
		item.set_meta(&"rage_heat", 0.0)
	item.set_meta(&"integrity", 1.0)
	item.set_meta(&"tint", entry["tint"])

	# Collision shape matched to treasure silhouette.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape"
	var shape_kind: StringName = entry["shape"]
	if shape_kind == &"skull" or shape_kind == &"chalice":
		var sph := SphereShape3D.new()
		sph.radius = float(entry["float_radius"])
		col.shape = sph
		col.position = Vector3(0.0, sph.radius, 0.0)
	else:
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.68, 0.48, 0.46) if shape_kind != &"crate" else Vector3(0.56, 0.56, 0.56)
		col.shape = bx
		col.position = Vector3(0.0, bx.size.y * 0.5, 0.0)
	item.add_child(col)

	# Visual rig: load generated GLB chest if available, else build stylized fallback.
	var visual := _build_visual(entry)
	visual.name = "Visual"
	item.add_child(visual)

	# Cursed flooding chests weep luminous turquoise-emerald sculpted droplets!
	if bool(entry.get("cursed", false)) and float(entry.get("curse_flood_rate", 0.0)) > 0.0:
		var drips := _build_weeping_drips_particles()
		visual.add_child(drips)
		item.tree_exiting.connect(_cleanup_hazard_particles.bind(drips), CONNECT_ONE_SHOT)

	# Cursed volcanic BlazingRageChests mount a lightweight ember glow + rising ember motes!
	if heat_rate > 0.0:
		var glow := _build_rage_ember_glow()
		visual.add_child(glow)
		item.tree_exiting.connect(_cleanup_rage_ember_glow.bind(glow), CONNECT_ONE_SHOT)

	# Explicit Interactable so prompts are ready even before _ready() runs.
	var handle := Interactable.create("Pick up %s" % entry["name"], 0.6)
	handle.name = "Interactable"
	handle.position = Vector3(0.0, float(entry["float_radius"]), 0.0)
	item.add_child(handle)
	item.interactable = handle

	return item


## Read a normalized treasure info dictionary from a Carryable or Node.
static func inspect_carryable(node: Node) -> Dictionary:
	if node == null or not node.has_meta(&"treasure_id"):
		return {}
	var tid: StringName = StringName(node.get_meta(&"treasure_id"))
	var base := get_entry(tid)
	var base_gold: int = int(node.get_meta(&"base_gold_value", base.get("gold_value", 0)))
	var integrity: float = float(node.get_meta(&"integrity", 1.0))
	var is_fragile: bool = bool(node.get_meta(&"fragile", base.get("fragile", false)))
	var current_gold: int = int(node.get_meta(&"gold_value",
			compute_effective_value(base_gold, integrity, is_fragile)))
	return {
		"treasure_id": tid,
		"name": String(node.get_meta(&"treasure_name", base.get("name", String(tid)))),
		"tier": int(node.get_meta(&"tier", base.get("tier", 1))),
		"base_gold_value": base_gold,
		"gold_value": current_gold,
		"renown_value": int(node.get_meta(&"renown_value", base.get("renown_value", 0))),
		"company_id": StringName(node.get_meta(&"company_id", base.get("company_id", &"gilded_compass"))),
		"cursed": bool(node.get_meta(&"cursed", base.get("cursed", false))),
		"fragile": is_fragile,
		"curse_flood_rate": float(node.get_meta(&"curse_flood_rate", base.get("curse_flood_rate", 0.0))),
		"curse_heat_rate": float(node.get_meta(&"curse_heat_rate", base.get("curse_heat_rate", 0.0))),
		"rage_heat": float(node.get_meta(&"rage_heat", 0.0)),
		"commodity": bool(base.get("commodity", false)),
		"integrity": integrity,
	}


## Degrade a fragile treasure Carryable (hard drop or submersion). Host-only.
static func damage_fragile_carryable(item: Node, damage: float) -> Dictionary:
	if item == null or not item.has_meta(&"fragile") or not bool(item.get_meta(&"fragile")):
		return {"damaged": false, "integrity": 1.0, "gold_value": int(item.get_meta(&"gold_value", 0)) if item != null else 0}
	if not Net.is_host():
		return {
			"damaged": false,
			"integrity": float(item.get_meta(&"integrity", 1.0)),
			"gold_value": int(item.get_meta(&"gold_value", 0)),
		}
	var prev_integrity: float = float(item.get_meta(&"integrity", 1.0))
	var next_integrity: float = clampf(prev_integrity - maxf(0.0, damage), 0.0, 1.0)
	var base_gold: int = int(item.get_meta(&"base_gold_value", item.get_meta(&"gold_value", 0)))
	var new_gold: int = compute_effective_value(base_gold, next_integrity, true)
	item.set_meta(&"integrity", next_integrity)
	item.set_meta(&"gold_value", new_gold)
	sync_fragile_visual(item)
	return {
		"damaged": next_integrity < prev_integrity,
		"integrity": next_integrity,
		"gold_value": new_gold,
	}


## Alias for `damage_fragile_carryable()` applying fragile cargo wear and syncing visuals.
static func apply_fragile_damage(item: Node, damage: float) -> Dictionary:
	return damage_fragile_carryable(item, damage)


## Sync visual distress indicator on fragile cargo when integrity drops below 0.85
## (attaches a WeakRef-cached sculpted amber warning mote GPUParticles3D named `FragileDistress`).
static func sync_fragile_visual(item: Node) -> void:
	if item == null or not is_instance_valid(item):
		return
	if not bool(item.get_meta(&"fragile", false)):
		return
	var visual := item.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return
	var integrity := clampf(float(item.get_meta(&"integrity", 1.0)), 0.0, 1.0)
	var existing := visual.get_node_or_null(^"FragileDistress") as GPUParticles3D
	if integrity >= 0.85:
		item.set_meta(&"distress_active", false)
		if existing != null:
			existing.emitting = false
			existing.visible = false
		return

	var severity := clampf((0.85 - integrity) / 0.85, 0.0, 1.0)
	if existing == null:
		existing = _build_fragile_distress_particles()
		visual.add_child(existing)
		item.tree_exiting.connect(_cleanup_hazard_particles.bind(existing), CONNECT_ONE_SHOT)
	existing.amount_ratio = clampf(lerpf(0.35, 1.0, severity), 0.1, 1.0)
	existing.visible = true
	existing.emitting = true
	item.set_meta(&"distress_active", true)
	item.set_meta(&"distress_severity", severity)


## Sync the RageEmberGlow visual intensity (ember particles & unshadowed glow light) with `rage_heat`.
static func sync_rage_visual(item: Node) -> void:
	if item == null or not is_instance_valid(item):
		return
	var visual := item.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return
	var glow := visual.get_node_or_null(^"RageEmberGlow") as Node3D
	if glow == null:
		return
	var heat := clampf(float(item.get_meta(&"rage_heat", 0.0)), 0.0, 1.0)
	var embers := glow.get_node_or_null(^"EmberParticles") as GPUParticles3D
	if embers != null and is_instance_valid(embers):
		embers.amount_ratio = clampf(lerpf(0.25, 1.0, heat), 0.15, 1.0)
		embers.visible = true
		embers.emitting = true
	var light := glow.get_node_or_null(^"EmberLight") as OmniLight3D
	if light != null and is_instance_valid(light):
		light.light_energy = lerpf(0.45, 2.8, heat)
		light.visible = true


## Host-only. Tick volcanic heat build-up on a `BlazingRageChest` aboard `ship`.
## Cools gently when submerged in seawater or below deck in >= 0.16 flooded bilge water;
## otherwise heats up and erupts into real ShipFire deck flames at `rage_heat >= 1.0`!
static func tick_rage_chest_aboard(item: Node, ship: Node, delta: float) -> Dictionary:
	if item == null or not is_instance_valid(item):
		return {"erupted": false, "heat": 0.0, "cooled": false}
	var heat_rate := float(item.get_meta(&"curse_heat_rate", 0.0))
	var heat := clampf(float(item.get_meta(&"rage_heat", 0.0)), 0.0, 1.0)
	if not Net.is_host() or delta <= 0.0 or heat_rate <= 0.0:
		return {"erupted": false, "heat": heat, "cooled": false}

	var hold_water := 0.0
	if ship != null:
		var wl: Variant = ship.get("water_level")
		if wl is float or wl is int:
			hold_water = float(wl)

	var in_seawater := false
	var below_deck := false
	if item is Node3D and item.is_inside_tree():
		var item_pos := (item as Node3D).global_position
		if Sea != null and Sea.depth(item_pos) > 0.04:
			in_seawater = true
		if ship is Node3D and ship.is_inside_tree():
			var hs_v: Variant = ship.get(&"hull_scale")
			var hs := float(hs_v) if (hs_v != null and float(hs_v) > 0.01) else 1.0
			var local_p := (ship as Node3D).global_transform.affine_inverse() * item_pos
			below_deck = (local_p.y / hs) < 0.35
	elif ship != null and not (ship is Node3D):
		below_deck = true

	var is_wet := in_seawater or (hold_water >= 0.16 and below_deck)
	if is_wet:
		heat = clampf(heat - 0.14 * delta, 0.0, 1.0)
		item.set_meta(&"rage_heat", heat)
		sync_rage_visual(item)
		return {"erupted": false, "heat": heat, "cooled": true}

	heat += heat_rate * delta
	if heat >= 1.0:
		heat = 0.20
		item.set_meta(&"rage_heat", heat)
		sync_rage_visual(item)
		var erupt_pos := Vector3.ZERO
		if item is Node3D and item.is_inside_tree():
			erupt_pos = (item as Node3D).global_position
		elif ship is Node3D and ship.is_inside_tree():
			erupt_pos = (ship as Node3D).global_position
		if ship != null and ship.has_method(&"ignite_deck_fire"):
			ship.call(&"ignite_deck_fire", erupt_pos, false)
		if Audio != null:
			var sfx_id: StringName = &"fire_burst" if Audio.catalogue.get("sfx", {}).has("fire_burst") else &"cannon_fire"
			Audio.play_sfx(sfx_id, erupt_pos, -2.5)
		if Game != null:
			Game.post_notice("The Chest of Blazing Rage erupted! Grab a water bucket!")
		return {"erupted": true, "heat": heat, "cooled": false}

	heat = clampf(heat, 0.0, 1.0)
	item.set_meta(&"rage_heat", heat)
	sync_rage_visual(item)
	return {"erupted": false, "heat": heat, "cooled": false}


## Host-only. Splash water onto a `BlazingRageChest` to reduce its `rage_heat` cleanly (clamped >= 0.0).
static func cool_rage_chest(item: Node, amount: float = 0.65) -> bool:
	if not Net.is_host() or item == null or not is_instance_valid(item):
		return false
	if float(item.get_meta(&"curse_heat_rate", 0.0)) <= 0.0:
		return false
	if amount <= 0.0:
		return false
	var prev_heat := float(item.get_meta(&"rage_heat", 0.0))
	var next_heat := clampf(prev_heat - amount, 0.0, 1.0)
	item.set_meta(&"rage_heat", next_heat)
	sync_rage_visual(item)
	if Audio != null:
		var cool_pos := (item as Node3D).global_position if (item is Node3D and item.is_inside_tree()) else Vector3.INF
		var hiss_sfx: StringName = &"steam_hiss" if Audio.catalogue.get("sfx", {}).has("steam_hiss") else &"splash_small"
		Audio.play_sfx(hiss_sfx, cool_pos, -1.5)
	return true


## Apply impact damage when a fragile cargo item is dropped hard.
static func notify_drop_impact(item: Node, impact_speed: float) -> Dictionary:
	if impact_speed <= FRAGILE_IMPACT_THRESHOLD:
		return {"damaged": false, "integrity": float(item.get_meta(&"integrity", 1.0)) if item != null else 1.0}
	var excess := (impact_speed - FRAGILE_IMPACT_THRESHOLD) / 8.0
	return damage_fragile_carryable(item, clampf(excess * 0.35, 0.08, 0.45))


## Tick cursed & fragile treasures aboard a ship (host-only, duck-typed ship API).
## Returns {flood_added: float, damaged_count: int, fires_ignited: int, total_cargo_value: int}.
static func step_aboard_hazards(items: Array, ship: Node, delta: float) -> Dictionary:
	var result := {"flood_added": 0.0, "damaged_count": 0, "fires_ignited": 0, "total_cargo_value": 0}
	if delta <= 0.0:
		return result
	var hold_water: float = 0.0
	if ship != null:
		var wl: Variant = ship.get("water_level")
		if wl is float or wl is int:
			hold_water = float(wl)

	var flood_total: float = 0.0
	for raw in items:
		if not (raw is Node):
			continue
		var node: Node = raw
		if not is_instance_valid(node) or not node.has_meta(&"treasure_id"):
			continue
		var is_cursed: bool = bool(node.get_meta(&"cursed", false))
		var flood_rate: float = float(node.get_meta(&"curse_flood_rate", 0.0))
		if is_cursed and flood_rate > 0.0 and Net.is_host():
			flood_total += flood_rate * delta

		var heat_rate: float = float(node.get_meta(&"curse_heat_rate", 0.0))
		if heat_rate > 0.0 and Net.is_host():
			var rage_res := tick_rage_chest_aboard(node, ship, delta)
			if bool(rage_res.get("erupted", false)):
				result["fires_ignited"] = int(result["fires_ignited"]) + 1

		var is_fragile: bool = bool(node.get_meta(&"fragile", false))
		if is_fragile and Net.is_host():
			var submerged := hold_water > 0.35
			if not submerged and node is Node3D and node.is_inside_tree():
				var pos: Vector3 = (node as Node3D).global_position
				if Sea != null and Sea.depth(pos) > 0.08:
					submerged = true
			if submerged:
				var dmg := damage_fragile_carryable(node, FRAGILE_SUBMERGE_DECAY * delta)
				if bool(dmg.get("damaged", false)):
					result["damaged_count"] = int(result["damaged_count"]) + 1
			sync_fragile_visual(node)

		result["total_cargo_value"] = int(result["total_cargo_value"]) + int(node.get_meta(&"gold_value", 0))

	if flood_total > 0.0 and ship != null and Net.is_host():
		if ship.has_method("add_water"):
			ship.call("add_water", flood_total)
		elif ship.get("water_level") != null:
			ship.set("water_level", clampf(hold_water + flood_total, 0.0, 1.0))
			var after_wl: Variant = ship.get("water_level")
			if (after_wl is float or after_wl is int) and float(after_wl) <= hold_water + 0.00001 and ship.has_method("bail"):
				ship.call("bail", -flood_total)
		elif ship.has_method("bail"):
			ship.call("bail", -flood_total)
		result["flood_added"] = flood_total

	return result


## Alias for `step_aboard_hazards()` ticking cursed bilge flooding, volcanic rage heat, and fragile cargo distress.
static func tick_aboard_hazards(items: Array, ship: Node, delta: float) -> Dictionary:
	return step_aboard_hazards(items, ship, delta)


## Release cached WeakRef entries for sculpted procedural treasure meshes & materials.
static func clear_mesh_cache() -> void:
	_mesh_cache.clear()
	_mat_cache.clear()
	_tex_cache.clear()


static func _load_pbr_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		var wr: Variant = _tex_cache[path]
		if wr is WeakRef:
			var obj: Variant = (wr as WeakRef).get_ref()
			if obj is Texture2D:
				return obj as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var loaded: Variant = ResourceLoader.load(path)
	if loaded is Texture2D:
		var tex := loaded as Texture2D
		_tex_cache[path] = weakref(tex)
		return tex
	return null


## Return the cached flat-faceted sculpted ArrayMesh for any catalogue entry
## (`&"skull"`, `&"chalice"`, `&"crate"`, `&"rage_chest"`, or sculpted banded pirate `&"chest"`/`&"coffer"`).
static func build_sculpted_mesh(entry: Dictionary) -> ArrayMesh:
	var shape_kind: StringName = StringName(entry.get("shape", &"chest"))
	var tint: Color = entry.get("tint", Color(0.56, 0.42, 0.28)) as Color
	var accent: Color = entry.get("accent_tint", Color(0.84, 0.68, 0.26)) as Color
	var tier: int = int(entry.get("tier", 1))
	var cursed: bool = bool(entry.get("cursed", false))
	var key := _cache_key("body", shape_kind, tint, accent, tier, cursed)
	var cached := _get_cached_mesh(key)
	if cached != null:
		return cached

	var mesh: ArrayMesh
	match shape_kind:
		&"skull":
			mesh = _sculpt_skull_mesh(tint, accent, tier, cursed)
		&"chalice":
			mesh = _sculpt_chalice_mesh(tint, accent, tier, cursed)
		&"crate":
			mesh = _sculpt_crate_mesh(tint, accent, tier, cursed)
		&"rage_chest":
			mesh = _sculpt_rage_chest_mesh(tint, accent, tier, cursed)
		_:
			mesh = _sculpt_chest_mesh(tint, accent, tier, cursed, shape_kind == &"coffer")

	_mesh_cache[key] = weakref(mesh)
	return mesh


static func _build_visual(entry: Dictionary) -> Node3D:
	var shape_kind: StringName = StringName(entry.get("shape", &"chest"))
	if (shape_kind == &"chest" or shape_kind == &"coffer") and ResourceLoader.exists(CHEST_GLB_PATH):
		var packed: Variant = ResourceLoader.load(CHEST_GLB_PATH)
		if packed is PackedScene:
			var inst: Node = (packed as PackedScene).instantiate()
			if inst is Node3D:
				var chest_root := inst as Node3D
				_enhance_glb_chest(chest_root, entry)
				return chest_root

	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "SculptedMesh"
	mi.mesh = build_sculpted_mesh(entry)
	root.add_child(mi)
	return root


static func _cache_key(prefix: String, shape_kind: StringName, tint: Color,
		accent: Color, tier: int, cursed: bool) -> String:
	return "%s|%s|%s|%s|%d|%d" % [
		prefix,
		String(shape_kind),
		tint.to_html(false),
		accent.to_html(false),
		tier,
		1 if cursed else 0,
	]


static func _get_cached_mesh(key: String) -> ArrayMesh:
	if not _mesh_cache.has(key):
		return null
	var wr: Variant = _mesh_cache[key]
	if wr is WeakRef:
		var obj: Variant = (wr as WeakRef).get_ref()
		if obj is ArrayMesh:
			return obj as ArrayMesh
	return null


static func _get_vcol_mat(roughness: float, metallic: float,
		emissive_col: Color = Color.BLACK, emissive_energy: float = 0.0) -> StandardMaterial3D:
	var key := "%.2f|%.2f|%s|%.2f" % [roughness, metallic, emissive_col.to_html(false), emissive_energy]
	if _mat_cache.has(key):
		var wr: Variant = _mat_cache[key]
		if wr is WeakRef:
			var obj: Variant = (wr as WeakRef).get_ref()
			if obj is StandardMaterial3D:
				return obj as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = roughness
	mat.metallic = metallic
	if emissive_energy > 0.001:
		mat.emission_enabled = true
		mat.emission = emissive_col
		mat.emission_energy_multiplier = emissive_energy
	elif metallic >= 0.55:
		var norm_tex := _load_pbr_tex("res://assets/generated/textures/ship_brass_normal.png")
		var rough_tex := _load_pbr_tex("res://assets/generated/textures/ship_brass_rough.png")
		if norm_tex != null:
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = false
			mat.uv1_scale = Vector3(2.8, 2.8, 2.8)
			mat.normal_enabled = true
			mat.normal_scale = 0.52
			mat.normal_texture = norm_tex
			if rough_tex != null:
				mat.roughness_texture = rough_tex
	elif metallic < 0.25:
		var norm_tex := _load_pbr_tex("res://assets/generated/textures/ship_oak_normal.png")
		var rough_tex := _load_pbr_tex("res://assets/generated/textures/ship_oak_rough.png")
		if norm_tex != null:
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = false
			mat.uv1_scale = Vector3(2.2, 2.2, 2.2)
			mat.normal_enabled = true
			mat.normal_scale = 0.50
			mat.normal_texture = norm_tex
			if rough_tex != null:
				mat.roughness_texture = rough_tex
	_mat_cache[key] = weakref(mat)
	return mat


static func _commit_surface(mesh: ArrayMesh, st: SurfaceTool, mat: StandardMaterial3D) -> void:
	st.generate_normals()
	var surf_idx := mesh.get_surface_count()
	st.commit(mesh)
	if mesh.get_surface_count() > surf_idx:
		mesh.surface_set_material(surf_idx, mat)


# ==============================================================================
# Live Cargo Hazard VFX (Sculpted Teardrop Beads & Amber Distress Motes)
# ==============================================================================

static func _cleanup_hazard_particles(p: GPUParticles3D) -> void:
	if p != null and is_instance_valid(p):
		p.emitting = false
		p.visible = false
		p.draw_pass_1 = null
		p.process_material = null


static func _cleanup_rage_ember_glow(glow: Node3D) -> void:
	if glow == null or not is_instance_valid(glow):
		return
	var embers := glow.get_node_or_null(^"EmberParticles") as GPUParticles3D
	if embers != null and is_instance_valid(embers):
		_cleanup_hazard_particles(embers)
	var light := glow.get_node_or_null(^"EmberLight") as OmniLight3D
	if light != null and is_instance_valid(light):
		light.light_energy = 0.0
		light.visible = false


static func _build_rage_ember_glow() -> Node3D:
	var root := Node3D.new()
	root.name = "RageEmberGlow"
	root.position = Vector3(0.0, 0.34, 0.0)

	var p := GPUParticles3D.new()
	p.name = "EmberParticles"
	p.amount = 12
	p.lifetime = 0.95
	p.emitting = true
	p.amount_ratio = 0.30
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-0.70, -0.35, -0.70), Vector3(1.40, 1.35, 1.40))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.30, 0.10, 0.20)
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 42.0
	proc.initial_velocity_min = 0.24
	proc.initial_velocity_max = 0.62
	proc.gravity = Vector3(0.0, 0.25, 0.0)
	proc.scale_min = 0.65
	proc.scale_max = 1.25
	p.process_material = proc
	p.draw_pass_1 = _get_rage_ember_mesh()
	root.add_child(p)

	var light := OmniLight3D.new()
	light.name = "EmberLight"
	light.position = Vector3(0.0, 0.06, -0.10)
	light.light_color = Color(1.0, 0.42, 0.08)
	light.light_energy = 0.55
	light.omni_range = 3.8
	light.shadow_enabled = false
	root.add_child(light)

	return root


static func _get_rage_ember_mesh() -> ArrayMesh:
	const KEY := "fx|rage_ember_spark"
	var cached := _get_cached_mesh(KEY)
	if cached != null:
		return cached

	var mat := _get_fx_additive_mat(Color(1.00, 0.46, 0.08, 0.96), Color(1.00, 0.38, 0.06), 2.10)
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sculpted 6-faceted volcanic cinder spark shard (~0.052 m tall).
	var c_core := Color(1.00, 0.94, 0.60)
	var c_mid := Color(1.00, 0.44, 0.08)
	var c_bot := Color(0.84, 0.14, 0.04)
	var top_p := Vector3(0.0, 0.030, 0.0)
	var bot_p := Vector3(0.0, -0.022, 0.0)
	var ring: Array[Vector3] = []
	for k in 6:
		var a := float(k) / 6.0 * TAU
		var r := 0.018 if k % 2 == 0 else 0.011
		ring.append(Vector3(cos(a) * r, 0.002, sin(a) * r))
	for k in 6:
		var nk := (k + 1) % 6
		_emit_outward_tri(st, top_p, c_core, ring[k], c_mid, ring[nk], c_mid, Vector3.ZERO)
		_emit_outward_tri(st, bot_p, c_bot, ring[nk], c_mid, ring[k], c_mid, Vector3.ZERO)
	_commit_surface(mesh, st, mat)
	_mesh_cache[KEY] = weakref(mesh)
	return mesh


static func _build_weeping_drips_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "WeepingDrips"
	p.amount = 10
	p.lifetime = 0.85
	p.emitting = true
	p.local_coords = true
	p.position = Vector3(0.0, 0.30, 0.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-0.75, -0.55, -0.75), Vector3(1.50, 1.15, 1.50))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.32, 0.05, 0.22)
	proc.direction = Vector3(0.0, -0.25, 0.0)
	proc.spread = 85.0
	proc.initial_velocity_min = 0.14
	proc.initial_velocity_max = 0.34
	proc.gravity = Vector3(0.0, -2.4, 0.0)
	proc.scale_min = 0.72
	proc.scale_max = 1.22
	p.process_material = proc
	p.draw_pass_1 = _get_weeping_droplet_mesh()
	return p


static func _build_fragile_distress_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FragileDistress"
	p.amount = 8
	p.lifetime = 0.90
	p.emitting = false
	p.visible = false
	p.local_coords = true
	p.position = Vector3(0.0, 0.42, 0.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-0.60, -0.20, -0.60), Vector3(1.20, 1.10, 1.20))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.24, 0.08, 0.24)
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 38.0
	proc.initial_velocity_min = 0.25
	proc.initial_velocity_max = 0.52
	proc.gravity = Vector3(0.0, 0.15, 0.0)
	proc.scale_min = 0.70
	proc.scale_max = 1.20
	p.process_material = proc
	p.draw_pass_1 = _get_distress_mote_mesh()
	return p


static func _get_weeping_droplet_mesh() -> ArrayMesh:
	const KEY := "fx|weeping_droplet"
	var cached := _get_cached_mesh(KEY)
	if cached != null:
		return cached

	var mat := _get_fx_additive_mat(Color(0.24, 0.96, 0.86, 0.92), Color(0.24, 0.96, 0.86), 1.6)
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sculpted 6-sided faceted teardrop water bead (~0.048 m tall, pointed top & plump glowing drop base).
	var c_tip := Color(0.74, 1.00, 0.96)
	var c_mid := Color(0.28, 0.96, 0.86)
	var c_bot := Color(0.10, 0.72, 0.68)
	var stations: Array[Array] = [
		[-0.020, 0.000, c_bot],
		[-0.017, 0.014, c_bot],
		[-0.006, 0.020, c_mid],
		[0.009, 0.013, c_mid],
		[0.026, 0.004, c_tip],
		[0.032, 0.000, c_tip],
	]
	_add_lathe_y(st, stations, 6)
	_commit_surface(mesh, st, mat)
	_mesh_cache[KEY] = weakref(mesh)
	return mesh


static func _get_distress_mote_mesh() -> ArrayMesh:
	const KEY := "fx|fragile_distress_mote"
	var cached := _get_cached_mesh(KEY)
	if cached != null:
		return cached

	var mat := _get_fx_additive_mat(Color(1.00, 0.64, 0.16, 0.94), Color(1.00, 0.56, 0.12), 1.55)
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sculpted 4-point faceted amber warning diamond mote (~0.056 m tall).
	var c_core := Color(1.00, 0.94, 0.62)
	var c_edge := Color(1.00, 0.54, 0.12)
	var c_bot := Color(0.88, 0.24, 0.08)
	var top_p := Vector3(0.0, 0.030, 0.0)
	var bot_p := Vector3(0.0, -0.026, 0.0)
	var ring: Array[Vector3] = []
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var r := 0.022 if k % 2 == 0 else 0.011
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for k in 8:
		var nk := (k + 1) % 8
		_emit_outward_tri(st, top_p, c_core, ring[k], c_edge, ring[nk], c_edge, Vector3.ZERO)
		_emit_outward_tri(st, bot_p, c_bot, ring[nk], c_edge, ring[k], c_edge, Vector3.ZERO)
	_commit_surface(mesh, st, mat)
	_mesh_cache[KEY] = weakref(mesh)
	return mesh


static func _get_fx_additive_mat(albedo_col: Color, emissive_col: Color,
		emissive_energy: float) -> StandardMaterial3D:
	var key := "fx_add|%s|%s|%.2f" % [albedo_col.to_html(true), emissive_col.to_html(false), emissive_energy]
	if _mat_cache.has(key):
		var wr: Variant = _mat_cache[key]
		if wr is WeakRef:
			var obj: Variant = (wr as WeakRef).get_ref()
			if obj is StandardMaterial3D:
				return obj as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = albedo_col
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.emission_enabled = true
	mat.emission = emissive_col
	mat.emission_energy_multiplier = emissive_energy
	_mat_cache[key] = weakref(mat)
	return mat


# ==============================================================================
# GLB Chest Tier & Cursed Visual Enhancement
# ==============================================================================

static func _enhance_glb_chest(chest_root: Node3D, entry: Dictionary) -> void:
	var cursed: bool = bool(entry.get("cursed", false))
	var tier: int = int(entry.get("tier", 1))
	if not cursed and tier < 3:
		return

	var shape_kind: StringName = StringName(entry.get("shape", &"chest"))
	var tint: Color = entry.get("tint", Color(0.45, 0.28, 0.16)) as Color
	var accent: Color = entry.get("accent_tint", Color(0.84, 0.68, 0.26)) as Color
	var key := _cache_key("glb_trim", shape_kind, tint, accent, tier, cursed)
	var trim_mesh := _get_cached_mesh(key)
	if trim_mesh == null:
		trim_mesh = _sculpt_glb_chest_trim(tint, accent, tier, cursed, shape_kind == &"coffer")
		_mesh_cache[key] = weakref(trim_mesh)

	if trim_mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "CursedAuraTrim" if cursed else "TierOrnateTrim"
		mi.mesh = trim_mesh
		chest_root.add_child(mi)


static func _sculpt_glb_chest_trim(tint: Color, accent: Color, tier: int,
		cursed: bool, is_coffer: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var matte_st := SurfaceTool.new()
	matte_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal_st := SurfaceTool.new()
	metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_matte := false
	var has_metal := false
	var has_glow := false

	if cursed:
		_append_cursed_chest_overlay(matte_st, glow_st, tint, accent)
		has_matte = true
		has_glow = true
	elif tier >= 4:
		_append_ornate_chest_overlay(metal_st, glow_st, tint, accent, is_coffer)
		has_metal = true
		has_glow = true
	else:
		# Tier 3 Corsair war-chest: bold gilded clasp studs & lid crown ridge bosses.
		var gold_hi := accent.lightened(0.16)
		var gold_mid := accent
		var gold_lo := accent.darkened(0.32)
		var crimson_hi := tint.lightened(0.20)
		var crimson_lo := tint.darkened(0.25)
		# Ornate war-boss atop front lockplate (chest_treasure.glb lockplate front at z = -0.240).
		_add_faceted_gem(metal_st, Vector3(0.0, 0.278, -0.244), 0.032, 0.014, 0.038, 6,
			gold_hi, gold_mid, gold_lo, Basis(Vector3.RIGHT, -PI * 0.5))
		_add_beveled_block(matte_st, Vector3(0.0, 0.454, 0.0), Vector3(0.16, 0.016, 0.10), 0.004,
			crimson_hi, tint, crimson_lo)
		for sx: float in [-0.245, 0.245]:
			for sz: float in [-0.155, 0.155]:
				var ang := acos(clampf(-sz / 0.226, -0.95, 0.95))
				var ly := 0.28 + 0.169 * sin(ang)
				_add_pyramid_stud(metal_st, Vector3(sx, ly, sz), 0.018, 0.014,
					gold_hi, gold_lo, Vector3(0.0, sin(ang), -cos(ang)).normalized())
		has_matte = true
		has_metal = true

	if has_matte:
		_commit_surface(mesh, matte_st, _get_vcol_mat(0.76, 0.08))
	if has_metal:
		_commit_surface(mesh, metal_st, _get_vcol_mat(0.24, 0.88))
	if has_glow:
		var glow_col := accent if cursed else (Color(0.16, 0.46, 0.96) if is_coffer else Color(0.92, 0.16, 0.22))
		var glow_energy := 2.4 if cursed else 0.72
		_commit_surface(mesh, glow_st, _get_vcol_mat(0.20, 0.18, glow_col, glow_energy))
	return mesh


static func _append_cursed_chest_overlay(barnacle_st: SurfaceTool, glow_st: SurfaceTool,
		tint: Color, accent: Color) -> void:
	var glow_hot := accent.lerp(Color.WHITE, 0.40)
	var glow_mid := accent
	var glow_deep := accent.darkened(0.24)
	var crust_hi := tint.lightened(0.16)
	var crust_mid := tint.darkened(0.12)
	var crust_lo := tint.darkened(0.38)

	# 1. Luminous spectral aqua-emerald rim seam hugging chest_treasure.glb lid joint (y = 0.282).
	var seam_y := 0.282
	var seam_h := 0.016
	var seam_t := 0.012
	_add_beveled_block(glow_st, Vector3(0.0, seam_y, -0.227), Vector3(0.674, seam_h, seam_t), 0.004,
		glow_hot, glow_mid, glow_deep)
	_add_beveled_block(glow_st, Vector3(0.0, seam_y, 0.227), Vector3(0.674, seam_h, seam_t), 0.004,
		glow_hot, glow_mid, glow_deep)
	_add_beveled_block(glow_st, Vector3(-0.337, seam_y, 0.0), Vector3(seam_t, seam_h, 0.456), 0.004,
		glow_hot, glow_mid, glow_deep)
	_add_beveled_block(glow_st, Vector3(0.337, seam_y, 0.0), Vector3(seam_t, seam_h, 0.456), 0.004,
		glow_hot, glow_mid, glow_deep)

	# 2. Glowing spectral rune cracks arching over the domed lid (between straps, x = ±0.11).
	for side_sgn: float in [-1.0, 1.0]:
		var lid_pts: Array[Vector3] = []
		var lid_rads: Array[float] = []
		for i in range(9):
			var frac := float(i) / 8.0
			var ang := lerpf(0.18, PI - 0.18, frac)
			var zig := sin(frac * PI * 3.0) * 0.022 * side_sgn
			var px := side_sgn * 0.115 + zig
			var py := 0.28 + 0.164 * sin(ang)
			var pz := -0.225 * cos(ang)
			lid_pts.append(Vector3(px, py, pz))
			lid_rads.append(0.0075 * (0.7 + 0.5 * sin(frac * PI)))
		_add_swept_tube(glow_st, lid_pts, lid_rads, 5, glow_hot, glow_deep, false, true)

		# Weeping spectral water-rune fissure trickling down front & back hull panels.
		for face_z: float in [-1.0, 1.0]:
			var drip_pts: Array[Vector3] = [
				Vector3(side_sgn * 0.13, 0.278, face_z * 0.222),
				Vector3(side_sgn * 0.105, 0.210, face_z * 0.214),
				Vector3(side_sgn * 0.145, 0.142, face_z * 0.207),
				Vector3(side_sgn * 0.118, 0.072, face_z * 0.200),
			]
			var drip_rads: Array[float] = [0.009, 0.0075, 0.006, 0.0045]
			_add_swept_tube(glow_st, drip_pts, drip_rads, 5, glow_hot, glow_deep, false, true)

	# 3. Spectral glowing cursed keyhole sigil over front lockplate & weeping tear droplets.
	_add_faceted_gem(glow_st, Vector3(0.0, 0.278, -0.244), 0.028, 0.012, 0.042, 6,
		glow_hot, glow_mid, glow_deep, Basis(Vector3.RIGHT, -PI * 0.5))
	for drop_x: float in [-0.21, -0.09, 0.09, 0.21]:
		_add_faceted_gem(glow_st, Vector3(drop_x, 0.258, -0.226), 0.011, 0.018, 0.010, 5,
			glow_hot, glow_mid, glow_deep)

	# 4. Sculpted sea-barnacle clusters clinging to lower corners & lid flank.
	var barnacle_spots: Array[Vector3] = [
		Vector3(-0.305, 0.082, -0.198),
		Vector3(-0.278, 0.056, -0.206),
		Vector3(0.302, 0.092, -0.198),
		Vector3(0.285, 0.060, 0.202),
		Vector3(-0.296, 0.072, 0.200),
		Vector3(-0.185, 0.398, -0.142),
		Vector3(0.192, 0.386, 0.148),
	]
	for bi in barnacle_spots.size():
		var bp := barnacle_spots[bi]
		var br := 0.022 + 0.006 * float(bi % 3)
		_add_faceted_gem(barnacle_st, bp, br, br * 0.85, br, 6, crust_hi, crust_mid, crust_lo)


static func _append_ornate_chest_overlay(metal_st: SurfaceTool, glow_st: SurfaceTool,
		tint: Color, accent: Color, is_coffer: bool) -> void:
	var gold_hi := accent.lightened(0.20)
	var gold_mid := accent
	var gold_lo := accent.darkened(0.34)
	# Sovereign ruby or Archive sapphire jewel contrast against burnished gold!
	var gem_base := Color(0.16, 0.46, 0.96) if is_coffer else Color(0.92, 0.16, 0.22)
	var gem_hi := gem_base.lerp(Color.WHITE, 0.35)
	var gem_lo := gem_base.darkened(0.38)
	if not is_coffer and tint.b > tint.r:
		gem_base = accent
		gem_hi = accent.lightened(0.28)
		gem_lo = accent.darkened(0.32)

	# 1. Front lockplate gilded bezel & faceted jewel clasp (front face z = -0.240).
	_add_beveled_block(metal_st, Vector3(0.0, 0.276, -0.242), Vector3(0.074, 0.074, 0.016), 0.005,
		gold_hi, gold_mid, gold_lo)
	_add_faceted_gem(glow_st, Vector3(0.0, 0.276, -0.252), 0.024, 0.012, 0.030, 6,
		gem_hi, gem_base, gem_lo, Basis(Vector3.RIGHT, -PI * 0.5))

	# 2. Lid crown centerpiece medallion & jewel cabochon (lid crest top y = 0.453).
	if is_coffer:
		# Archive 4-point compass-star cipher medallion atop Salt-King's Ledger Coffer.
		_add_beveled_block(metal_st, Vector3(0.0, 0.456, 0.0), Vector3(0.16, 0.014, 0.056), 0.004,
			gold_hi, gold_mid, gold_lo)
		_add_beveled_block(metal_st, Vector3(0.0, 0.456, 0.0), Vector3(0.056, 0.014, 0.13), 0.004,
			gold_hi, gold_mid, gold_lo)
		_add_beveled_block(metal_st, Vector3(0.0, 0.456, 0.0), Vector3(0.11, 0.012, 0.11), 0.004,
			gold_hi, gold_mid, gold_lo, Basis(Vector3.UP, PI * 0.25))
		_add_faceted_gem(glow_st, Vector3(0.0, 0.466, 0.0), 0.032, 0.018, 0.032, 8,
			gem_hi, gem_base, gem_lo)
	else:
		# Sovereign gilded rosette crown frame & crimson-gold centerpiece jewel.
		_add_beveled_block(metal_st, Vector3(0.0, 0.455, 0.0), Vector3(0.15, 0.014, 0.10), 0.005,
			gold_hi, gold_mid, gold_lo)
		_add_faceted_gem(glow_st, Vector3(0.0, 0.466, 0.0), 0.036, 0.018, 0.026, 6,
			gem_hi, gem_base, gem_lo)

	# 3. Four gilded lid corner rosette studs & side corner finials.
	for sx: float in [-0.245, 0.245]:
		for sz: float in [-0.148, 0.148]:
			var ang := acos(clampf(-sz / 0.226, -0.95, 0.95))
			var ly := 0.28 + 0.168 * sin(ang)
			_add_pyramid_stud(metal_st, Vector3(sx, ly, sz), 0.020, 0.016,
				gold_hi, gold_lo, Vector3(0.0, sin(ang), -cos(ang)).normalized())
	for sx: float in [-0.115, 0.115]:
		for sz: float in [-0.072, 0.072]:
			_add_pyramid_stud(metal_st, Vector3(sx, 0.448, sz), 0.016, 0.015,
				gold_hi, gold_lo, Vector3.UP)


# ==============================================================================
# Archetype 1: Hero-Grade Sculpted Bounty Skull (`&"skull"`)
# ==============================================================================

static func _sculpt_skull_mesh(tint: Color, accent: Color, tier: int, cursed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var bone_st := SurfaceTool.new()
	bone_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal_st := SurfaceTool.new()
	metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bone_hi := tint.lightened(0.15)
	var bone_mid := tint
	var bone_sh := tint.darkened(0.24)
	var bone_deep := tint.darkened(0.52)
	var socket_void := Color(0.045, 0.052, 0.062)
	var tooth_ivory := Color(0.95, 0.91, 0.79)
	var tooth_shade := Color(0.76, 0.71, 0.58)
	var gold_hi := Color(1.0, 0.84, 0.30)
	var gold_mid := Color(0.92, 0.70, 0.18)
	var gold_lo := Color(0.62, 0.42, 0.08)
	var glow_hot := accent.lerp(Color.WHITE, 0.48)
	var glow_deep := accent.darkened(0.24)

	# 1. Sculpted Faceted Cranium Dome (10 latitude bands x 14 longitude segs).
	# Slightly elongated front-to-back, tapered temples, recessed orbital depressions,
	# occipital swell, and crisp flat-faceted vertex shading.
	var cran_c := Vector3(0.0, 0.236, 0.014)
	var lat_n := 10
	var lon_n := 14
	var grid_pts: Array[Array] = []
	var grid_cols: Array[Array] = []
	for j in range(lat_n + 1):
		var v := float(j) / float(lat_n)
		var phi := lerpf(-PI * 0.48, PI * 0.49, v)
		var cphi := cos(phi)
		var sphi := sin(phi)
		var row_p: Array[Vector3] = []
		var row_c: Array[Color] = []
		for i in range(lon_n):
			var theta := float(i) / float(lon_n) * TAU
			var nx := cphi * cos(theta)
			var ny := sphi
			var nz := cphi * sin(theta)

			# Elongated anatomical skull silhouette.
			var rx := 0.116
			var ry := 0.122
			var rz := 0.144
			# Parietal fullness at upper rear sides.
			if ny > 0.10 and nz > 0.05:
				rx += 0.009 * sin(clampf((ny - 0.10) * 1.8, 0.0, PI))
			# Occipital rear swell & sharp underside taper toward skull base.
			if nz > 0.30 and ny < 0.25 and ny > -0.45:
				rz += 0.012 * clampf((nz - 0.30) * 1.5, 0.0, 1.0)
			if ny < -0.35:
				var base_t := clampf((-ny - 0.35) / 0.65, 0.0, 1.0)
				rx *= lerpf(1.0, 0.68, base_t)
				rz *= lerpf(1.0, 0.72, base_t)

			var p := Vector3(nx * rx, ny * ry, nz * rz)

			# Tapered hollow temples on front-lateral flanks.
			if absf(nx) > 0.48 and nz < 0.20 and nz > -0.68 and ny > -0.32 and ny < 0.44:
				var tw := clampf((absf(nx) - 0.48) / 0.42, 0.0, 1.0) * (1.0 - absf(ny - 0.06) / 0.42)
				p.x -= signf(nx) * 0.017 * maxf(0.0, tw)

			# Prominent brow ridge overhang across forehead front (-Z).
			var col := bone_sh.lerp(bone_hi, clampf(0.45 + 0.55 * ny, 0.0, 1.0))
			if nz < -0.42 and ny > -0.08 and ny < 0.26:
				var bw := clampf((-nz - 0.42) / 0.50, 0.0, 1.0) * sin(clampf((ny + 0.08) / 0.34, 0.0, 1.0) * PI)
				var arch := 1.0 - 0.28 * exp(-pow(nx / 0.16, 2.0))
				p.z -= 0.018 * bw * arch
				col = col.lerp(bone_hi, 0.45 * bw)

			# Depress front eye-socket hollows deeply so cranium never occludes orbits.
			var eye_d_l := Vector2(nx + 0.38, ny + 0.22).length()
			var eye_d_r := Vector2(nx - 0.38, ny + 0.22).length()
			var eye_d := minf(eye_d_l, eye_d_r)
			if nz < -0.40 and eye_d < 0.32:
				var recess := pow(1.0 - eye_d / 0.32, 1.4) * clampf((-nz - 0.40) / 0.45, 0.0, 1.0)
				p.z += 0.046 * recess
				col = col.lerp(socket_void, clampf(recess * 1.45, 0.0, 1.0))
			elif absf(nx) > 0.55 and ny < 0.20:
				col = col.lerp(bone_sh, 0.38)
			elif ny < -0.30:
				col = col.lerp(bone_deep, 0.45)

			row_p.append(cran_c + p)
			row_c.append(col)
		grid_pts.append(row_p)
		grid_cols.append(row_c)

	for j in range(lat_n):
		var r0: Array = grid_pts[j]
		var r1: Array = grid_pts[j + 1]
		var c0: Array = grid_cols[j]
		var c1: Array = grid_cols[j + 1]
		for i in range(lon_n):
			var ni := (i + 1) % lon_n
			_emit_outward_quad(bone_st,
				r0[i] as Vector3, c0[i] as Color,
				r0[ni] as Vector3, c0[ni] as Color,
				r1[ni] as Vector3, c1[ni] as Color,
				r1[i] as Vector3, c1[i] as Color,
				cran_c)
	# Close crown apex & skull base cleanly.
	var base_pole := cran_c + Vector3(0.0, -0.122 * 0.96, 0.0)
	var top_pole := cran_c + Vector3(0.0, 0.124, 0.0)
	for i in range(lon_n):
		var ni := (i + 1) % lon_n
		_emit_outward_tri(bone_st,
			base_pole, bone_deep,
			(grid_pts[0][ni] as Vector3), (grid_cols[0][ni] as Color),
			(grid_pts[0][i] as Vector3), (grid_cols[0][i] as Color),
			cran_c)
		_emit_outward_tri(bone_st,
			top_pole, bone_hi,
			(grid_pts[lat_n][i] as Vector3), (grid_cols[lat_n][i] as Color),
			(grid_pts[lat_n][ni] as Vector3), (grid_cols[lat_n][ni] as Color),
			cran_c)

	# 2. Prominent Sculpted Supraorbital Brow Ridge (M-shaped scowling ridge).
	var brow_pts: Array[Vector3] = [
		Vector3(-0.094, 0.214, -0.104),
		Vector3(-0.072, 0.232, -0.128),
		Vector3(-0.042, 0.236, -0.138),
		Vector3(0.0, 0.224, -0.134),
		Vector3(0.042, 0.236, -0.138),
		Vector3(0.072, 0.232, -0.128),
		Vector3(0.094, 0.214, -0.104),
	]
	var brow_w: Array[float] = [0.018, 0.024, 0.027, 0.023, 0.027, 0.024, 0.018]
	var brow_t: Array[float] = [0.018, 0.022, 0.024, 0.020, 0.024, 0.022, 0.018]
	_add_swept_ribbon(bone_st, brow_pts, brow_w, brow_t, bone_hi, bone_mid, bone_sh, true)

	# 3. Deep Recessed Eye Sockets + Glowing Spectral Iris Cores (Left & Right).
	for side_sgn: float in [-1.0, 1.0]:
		var orbit_c := Vector3(side_sgn * 0.049, 0.194, -0.118)
		var orbit_basis := Basis(Vector3.UP, -side_sgn * 0.24)
		var segs := 8
		var outer_ring: Array[Vector3] = []
		var lip_ring: Array[Vector3] = []
		var back_ring: Array[Vector3] = []
		for k in range(segs):
			var a := float(k) / float(segs) * TAU
			var ca := cos(a)
			var sa := sin(a)
			# Scowling inner-upper orbital corner dip for fierce pirate expression.
			var scowl := -0.007 * maxf(0.0, sa) * maxf(0.0, -side_sgn * ca)
			var rx_lip := 0.031
			var ry_lip := 0.026
			var rx_out := 0.043
			var ry_out := 0.036
			var rx_in := 0.020
			var ry_in := 0.017
			outer_ring.append(orbit_c + orbit_basis * Vector3(ca * rx_out, sa * ry_out + scowl, 0.006))
			lip_ring.append(orbit_c + orbit_basis * Vector3(ca * rx_lip, sa * ry_lip + scowl, -0.010))
			back_ring.append(orbit_c + orbit_basis * Vector3(ca * rx_in, sa * ry_in + scowl * 0.5, 0.026))
		var back_center := orbit_c + orbit_basis * Vector3(0.0, 0.0, 0.030)
		var front_ref := orbit_c + orbit_basis * Vector3(0.0, 0.0, -0.08)
		var back_ref := orbit_c + orbit_basis * Vector3(0.0, 0.0, 0.06)
		for k in range(segs):
			var nk := (k + 1) % segs
			var is_top := sin(float(k) / float(segs) * TAU) > 0.0
			var rim_col := bone_hi if is_top else bone_mid
			# Outer bony rim bevel facing outward/forward.
			_emit_outward_quad(bone_st,
				outer_ring[k], bone_sh,
				outer_ring[nk], bone_sh,
				lip_ring[nk], rim_col,
				lip_ring[k], rim_col,
				back_ref)
			# Deep dark inner socket funnel wall (normals face inward/forward toward front_ref!).
			_emit_outward_quad(bone_st,
				lip_ring[k], bone_deep,
				lip_ring[nk], bone_deep,
				back_ring[nk], socket_void,
				back_ring[k], socket_void,
				front_ref)
			# Deep socket void backing disc facing forward (-Z).
			_emit_outward_tri(bone_st,
				back_center, socket_void,
				back_ring[k], socket_void,
				back_ring[nk], socket_void,
				front_ref)

		# Glowing spectral emerald/cyan/amber iris core nestled inside dark socket!
		var iris_pos := orbit_c + orbit_basis * Vector3(0.0, -0.001, 0.008)
		var iris_basis := orbit_basis * Basis(Vector3.RIGHT, -PI * 0.5)
		_add_faceted_gem(glow_st, iris_pos, 0.017, 0.011, 0.017, 8,
			glow_hot, accent, glow_deep, iris_basis)

	# 4. Sculpted Zygomatic Cheekbones & Sweeping Temporal Arches (Left & Right).
	for side_sgn: float in [-1.0, 1.0]:
		var cheek_pts: Array[Vector3] = [
			Vector3(side_sgn * 0.052, 0.156, -0.124),
			Vector3(side_sgn * 0.088, 0.155, -0.104),
			Vector3(side_sgn * 0.112, 0.152, -0.068),
			Vector3(side_sgn * 0.108, 0.158, -0.018),
			Vector3(side_sgn * 0.092, 0.166, 0.036),
		]
		var cheek_w: Array[float] = [0.024, 0.034, 0.034, 0.020, 0.018]
		var cheek_t: Array[float] = [0.022, 0.028, 0.026, 0.016, 0.016]
		_add_swept_ribbon(bone_st, cheek_pts, cheek_w, cheek_t, bone_hi, bone_mid, bone_sh, true)

	# 5. Triangular Recessed Nasal Cavity (Piriform Aperture) + Central Septum.
	var n_front_top := Vector3(0.0, 0.178, -0.136)
	var n_front_l := Vector3(-0.021, 0.130, -0.136)
	var n_front_r := Vector3(0.021, 0.130, -0.136)
	var n_out_top := Vector3(0.0, 0.192, -0.128)
	var n_out_l := Vector3(-0.035, 0.122, -0.126)
	var n_out_r := Vector3(0.035, 0.122, -0.126)
	var n_back_top := Vector3(0.0, 0.168, -0.104)
	var n_back_l := Vector3(-0.015, 0.132, -0.104)
	var n_back_r := Vector3(0.015, 0.132, -0.104)
	var n_front_ref := Vector3(0.0, 0.150, -0.22)
	var n_back_ref := Vector3(0.0, 0.150, -0.06)
	# Outer bony nasal rim framing the triangle.
	_emit_outward_quad(bone_st, n_out_top, bone_hi, n_out_r, bone_mid, n_front_r, bone_hi, n_front_top, bone_hi, n_back_ref)
	_emit_outward_quad(bone_st, n_out_l, bone_mid, n_out_top, bone_hi, n_front_top, bone_hi, n_front_l, bone_hi, n_back_ref)
	_emit_outward_quad(bone_st, n_out_r, bone_sh, n_out_l, bone_sh, n_front_l, bone_mid, n_front_r, bone_mid, n_back_ref)
	# Recessed dark inner nasal funnel & back void.
	_emit_outward_quad(bone_st, n_front_top, bone_deep, n_front_r, bone_deep, n_back_r, socket_void, n_back_top, socket_void, n_front_ref)
	_emit_outward_quad(bone_st, n_front_l, bone_deep, n_front_top, bone_deep, n_back_top, socket_void, n_back_l, socket_void, n_front_ref)
	_emit_outward_quad(bone_st, n_front_r, bone_deep, n_front_l, bone_deep, n_back_l, socket_void, n_back_r, socket_void, n_front_ref)
	_emit_outward_tri(bone_st, n_back_top, socket_void, n_back_r, socket_void, n_back_l, socket_void, n_front_ref)
	# Thin vertical nasal septum divider.
	_add_beveled_block(bone_st, Vector3(0.0, 0.148, -0.120), Vector3(0.007, 0.040, 0.022), 0.002,
		bone_mid, bone_deep, bone_deep)

	# 6. Carved Maxilla (Upper Jaw Horseshoe) + Dark Oral Cavity Backing.
	var max_pts: Array[Vector3] = [
		Vector3(-0.070, 0.114, -0.048),
		Vector3(-0.062, 0.112, -0.092),
		Vector3(-0.036, 0.110, -0.122),
		Vector3(0.0, 0.110, -0.130),
		Vector3(0.036, 0.110, -0.122),
		Vector3(0.062, 0.112, -0.092),
		Vector3(0.070, 0.114, -0.048),
	]
	var max_w: Array[float] = [0.026, 0.032, 0.038, 0.040, 0.038, 0.032, 0.026]
	var max_t: Array[float] = [0.032, 0.038, 0.042, 0.044, 0.042, 0.038, 0.032]
	_add_swept_ribbon(bone_st, max_pts, max_w, max_t, bone_hi, bone_mid, bone_sh, true)
	# Recessed dark oral shadow block behind upper & lower teeth so grin pops cleanly.
	_add_beveled_block(bone_st, Vector3(0.0, 0.078, -0.066), Vector3(0.102, 0.078, 0.078), 0.008,
		socket_void, socket_void, socket_void)

	# 7. Distinct Carved Mandible (Lower Jaw Grounded at y = 0.0) + Ascending Rami.
	var jaw_pts: Array[Vector3] = [
		Vector3(-0.082, 0.152, 0.004),
		Vector3(-0.078, 0.088, -0.012),
		Vector3(-0.070, 0.034, -0.038),
		Vector3(-0.052, 0.027, -0.088),
		Vector3(-0.026, 0.026, -0.118),
		Vector3(0.0, 0.026, -0.125),
		Vector3(0.026, 0.026, -0.118),
		Vector3(0.052, 0.027, -0.088),
		Vector3(0.070, 0.034, -0.038),
		Vector3(0.078, 0.088, -0.012),
		Vector3(0.082, 0.152, 0.004),
	]
	var jaw_w: Array[float] = [0.022, 0.026, 0.032, 0.032, 0.032, 0.034, 0.032, 0.032, 0.032, 0.026, 0.022]
	var jaw_t: Array[float] = [0.018, 0.020, 0.022, 0.022, 0.024, 0.026, 0.024, 0.022, 0.022, 0.020, 0.018]
	_add_swept_ribbon(bone_st, jaw_pts, jaw_w, jaw_t, bone_mid, bone_sh, bone_deep, true)
	# Chunky grounded pirate chin pedestal resting flush at y = 0.000.
	_add_beveled_block(bone_st, Vector3(0.0, 0.019, -0.114), Vector3(0.068, 0.038, 0.036), 0.008,
		bone_hi, bone_mid, bone_sh)

	# 8. Sculpted Individual Teeth (8 Upper + 6 Lower) + 1 Gleaming Gold Pirate Tooth!
	for ti in range(8):
		var u := (float(ti) - 3.5) / 3.5
		var ang := u * 1.12
		var tx := sin(ang) * 0.058
		var tz := -0.072 - cos(ang) * 0.058
		var tooth_h := 0.026 if absf(u) < 0.45 else 0.022
		var tooth_w := 0.0135 if absf(u) < 0.25 else 0.0115
		var t_basis := Basis(Vector3.UP, -ang)
		var t_pos := Vector3(tx, 0.078, tz)
		if ti == 5:
			# Gleaming gold pirate canine/incisor on metallic surface!
			_add_beveled_block(metal_st, t_pos, Vector3(tooth_w, tooth_h, 0.013), 0.003,
				gold_hi, gold_mid, gold_lo, t_basis)
		else:
			_add_beveled_block(bone_st, t_pos, Vector3(tooth_w, tooth_h, 0.012), 0.003,
				tooth_ivory, tooth_ivory, tooth_shade, t_basis)

	for ti in range(6):
		var u := (float(ti) - 2.5) / 2.5
		var ang := u * 0.92
		var tx := sin(ang) * 0.050
		var tz := -0.074 - cos(ang) * 0.050
		var t_basis := Basis(Vector3.UP, -ang)
		_add_beveled_block(bone_st, Vector3(tx, 0.051, tz), Vector3(0.011, 0.021, 0.011), 0.0025,
			tooth_ivory, tooth_ivory, tooth_shade, t_basis)

	# 9. Hairline Jagged Bone Crack Winding Up Right Frontal Brow.
	var crack_dark := tint.darkened(0.66)
	var crack_pts: Array[Vector3] = [
		Vector3(0.032, 0.242, -0.126),
		Vector3(0.048, 0.270, -0.114),
		Vector3(0.038, 0.296, -0.096),
		Vector3(0.058, 0.322, -0.068),
		Vector3(0.044, 0.340, -0.036),
	]
	var crack_rads: Array[float] = [0.0032, 0.0028, 0.0024, 0.0020, 0.0014]
	_add_swept_tube(bone_st, crack_pts, crack_rads, 4, crack_dark, socket_void, false, true)

	# 10. Tier-Specific Headband / Gold Ring / Coral-Fleck Accents.
	if tier >= 3 or cursed:
		# High-tier Captain's Skull: ornate crimson-and-gold headband circlet, tricorn clasp & gold hoop ring!
		var band_hi := Color(0.72, 0.14, 0.12) if not cursed else Color(0.14, 0.32, 0.38)
		var band_lo := band_hi.darkened(0.38)
		var band_segs := 14
		var band_pts: Array[Vector3] = []
		var band_w: Array[float] = []
		var band_t: Array[float] = []
		var trim_top_pts: Array[Vector3] = []
		var trim_bot_pts: Array[Vector3] = []
		var trim_rads: Array[float] = []
		for k in range(band_segs):
			var a := float(k) / float(band_segs) * TAU
			var bx := cos(a) * 0.118
			var bz := 0.014 + sin(a) * 0.142
			var by := 0.264 + 0.012 * cos(a - 0.5)
			band_pts.append(Vector3(bx, by, bz))
			band_w.append(0.012)
			band_t.append(0.028)
			trim_top_pts.append(Vector3(bx * 1.02, by + 0.014, 0.014 + (bz - 0.014) * 1.02))
			trim_bot_pts.append(Vector3(bx * 1.02, by - 0.014, 0.014 + (bz - 0.014) * 1.02))
			trim_rads.append(0.0042)
		_add_swept_ribbon(bone_st, band_pts, band_w, band_t, band_hi, band_hi.darkened(0.14), band_lo, false, true)
		_add_swept_tube(metal_st, trim_top_pts, trim_rads, 5, gold_hi, gold_lo, true, false)
		_add_swept_tube(metal_st, trim_bot_pts, trim_rads, 5, gold_hi, gold_lo, true, false)

		# Ornate brass tricorn clasp medallion + glowing gem at front-left brow.
		var clasp_pos := Vector3(-0.044, 0.270, -0.128)
		var clasp_basis := Basis(Vector3.UP, 0.34) * Basis(Vector3.RIGHT, 0.18)
		_add_beveled_block(metal_st, clasp_pos, Vector3(0.056, 0.048, 0.016), 0.005,
			gold_hi, gold_mid, gold_lo, clasp_basis)
		_add_faceted_gem(glow_st, clasp_pos + clasp_basis * Vector3(0.0, 0.0, -0.011),
			0.015, 0.010, 0.018, 6, glow_hot, accent, glow_deep,
			clasp_basis * Basis(Vector3.RIGHT, -PI * 0.5))

		# Heavy gold pirate hoop ring hooked through left temporal/zygomatic arch.
		_add_torus(metal_st, Vector3(-0.110, 0.132, 0.002), Vector3(0.18, 0.0, 1.0).normalized(),
			0.025, 0.0055, 10, 5, gold_hi, gold_lo)
	else:
		# Lower-tier Relic Skull of the Drowned: coral-flecked sea studs & faint spectral rune etch.
		var coral_hi := Color(0.28, 0.72, 0.64)
		var coral_mid := Color(0.18, 0.52, 0.48)
		var coral_lo := Color(0.10, 0.32, 0.30)
		var coral_spots: Array[Vector3] = [
			Vector3(-0.088, 0.278, -0.058),
			Vector3(-0.102, 0.252, -0.024),
			Vector3(-0.072, 0.312, -0.022),
			Vector3(0.082, 0.286, 0.064),
		]
		for ci in coral_spots.size():
			var cr := 0.014 + 0.004 * float(ci % 2)
			_add_faceted_gem(bone_st, coral_spots[ci], cr, cr * 0.85, cr, 6,
				coral_hi, coral_mid, coral_lo)
		# Small spectral sea-fire rune diamond etched between brows.
		_add_faceted_gem(glow_st, Vector3(0.0, 0.264, -0.125), 0.012, 0.006, 0.018, 4,
			glow_hot, accent, glow_deep, Basis(Vector3.RIGHT, -PI * 0.5))

	_commit_surface(mesh, bone_st, _get_vcol_mat(0.74, 0.05))
	_commit_surface(mesh, metal_st, _get_vcol_mat(0.22, 0.90))
	_commit_surface(mesh, glow_st, _get_vcol_mat(0.18, 0.12, accent, 2.5))
	return mesh


# ==============================================================================
# Archetype 2: Hero-Grade Fluted Golden Goblet / Chalice (`&"chalice"`)
# ==============================================================================

static func _sculpt_chalice_mesh(tint: Color, accent: Color, _tier: int, cursed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var gold_st := SurfaceTool.new()
	gold_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gem_st := SurfaceTool.new()
	gem_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var gold_hi := tint.lerp(Color(1.0, 0.90, 0.44), 0.34)
	var gold_mid := tint
	var gold_sh := Color(tint.r * 0.76, tint.g * 0.54, tint.b * 0.32)
	var gold_deep := Color(tint.r * 0.54, tint.g * 0.34, tint.b * 0.16)
	var bowl_dark := Color(tint.r * 0.34, tint.g * 0.19, tint.b * 0.08)
	var bowl_floor := Color(tint.r * 0.18, tint.g * 0.10, tint.b * 0.04)
	var gem_hi := accent.lerp(Color.WHITE, 0.36)
	var gem_mid := accent
	var gem_lo := accent.darkened(0.36)

	# 1. Wide Terraced Octagonal Foot (y = 0.000..0.088, 8 crisp stepped facets).
	var foot_stations: Array[Array] = [
		[0.000, 0.000, gold_deep],
		[0.000, 0.118, gold_deep],
		[0.015, 0.118, gold_mid],
		[0.022, 0.102, gold_hi],
		[0.036, 0.096, gold_mid],
		[0.044, 0.076, gold_hi],
		[0.062, 0.054, gold_sh],
		[0.076, 0.042, gold_hi],
		[0.088, 0.026, gold_deep],
	]
	_add_lathe_y(gold_st, foot_stations, 8, PI * 0.125)
	# 8 raised gold ribs accenting the octagonal foot ridges.
	for k in range(8):
		var a := PI * 0.125 + float(k) / 8.0 * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		_add_swept_tube(gold_st, [
			dir * 0.106 + Vector3(0.0, 0.022, 0.0),
			dir * 0.076 + Vector3(0.0, 0.048, 0.0),
			dir * 0.042 + Vector3(0.0, 0.078, 0.0),
		], [0.006, 0.0055, 0.0045], 4, gold_hi, gold_sh, false, true)

	# 2. Slender Ringed & Knopped Stem (y = 0.088..0.228, 12-sided turned gold).
	var stem_stations: Array[Array] = [
		[0.088, 0.026, gold_deep],
		[0.116, 0.022, gold_mid],
		[0.125, 0.038, gold_hi],
		[0.134, 0.025, gold_deep],
		[0.148, 0.050, gold_mid],
		[0.162, 0.058, gold_hi],
		[0.176, 0.050, gold_mid],
		[0.188, 0.025, gold_deep],
		[0.198, 0.039, gold_hi],
		[0.214, 0.028, gold_sh],
		[0.228, 0.052, gold_mid],
	]
	_add_lathe_y(gold_st, stem_stations, 12, 0.0, 0.06, 6)

	# Jeweled collar band around central stem knop (6 faceted gems in raised gold bezels).
	for k in range(6):
		var a := float(k) / 6.0 * TAU
		var radial := Vector3(cos(a), 0.0, sin(a))
		var b_basis := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -PI * 0.5)
		var bezel_pos := radial * 0.056 + Vector3(0.0, 0.162, 0.0)
		_add_beveled_block(gold_st, bezel_pos, Vector3(0.022, 0.010, 0.022), 0.003,
			gold_hi, gold_mid, gold_deep, b_basis)
		_add_faceted_gem(gem_st, radial * 0.063 + Vector3(0.0, 0.162, 0.0),
			0.011, 0.008, 0.011, 6, gem_hi, gem_mid, gem_lo, b_basis)

	# 3. Fluted Tulip-Flared Scalloped Bowl with Hollow Darkened Golden Interior (y = 0.228..0.418).
	# 16 segments = 8 crisp vertical flutes + 8 gentle rim scallops!
	var bowl_stations: Array[Array] = [
		[0.228, 0.052, gold_mid, 0.20, 0.0],
		[0.246, 0.088, gold_sh, 0.90, 0.0],
		[0.276, 0.106, gold_mid, 1.00, 0.0],
		[0.314, 0.098, gold_sh, 0.85, 0.15],
		[0.356, 0.114, gold_mid, 0.65, 0.45],
		[0.394, 0.136, gold_hi, 0.40, 0.85],
		[0.412, 0.140, gold_hi, 0.25, 1.00],
		# Rolled scalloped top lip curving smoothly into hollow interior!
		[0.416, 0.128, gold_hi, 0.15, 0.90],
		[0.404, 0.118, gold_sh, 0.10, 0.60],
		[0.362, 0.099, bowl_dark, 0.05, 0.0],
		[0.304, 0.082, bowl_dark, 0.0, 0.0],
		[0.264, 0.054, bowl_floor, 0.0, 0.0],
		[0.254, 0.000, bowl_floor, 0.0, 0.0],
	]
	_add_lathe_y(gold_st, bowl_stations, 16, 0.0, 0.085, 8, 0.009)

	# Raised decorative beaded rim molding ring + 8 studded turquoise/accent rim gems!
	for k in range(8):
		var a := float(k) / 8.0 * TAU
		var radial := Vector3(cos(a), 0.0, sin(a))
		var g_basis := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -PI * 0.5)
		var r_wall := 0.124
		_add_beveled_block(gold_st, radial * r_wall + Vector3(0.0, 0.366, 0.0),
			Vector3(0.018, 0.008, 0.018), 0.0025, gold_hi, gold_mid, gold_deep, g_basis)
		_add_faceted_gem(gem_st, radial * (r_wall + 0.006) + Vector3(0.0, 0.366, 0.0),
			0.0095, 0.007, 0.0095, 6, gem_hi, gem_mid, gem_lo, g_basis)

	# 4. Twin Ornate Baroque S-Scroll Handles (±X flanks).
	for side_sgn: float in [-1.0, 1.0]:
		var scroll_pts: Array[Vector3] = [
			Vector3(side_sgn * 0.086, 0.254, 0.0),
			Vector3(side_sgn * 0.128, 0.252, 0.0),
			Vector3(side_sgn * 0.152, 0.278, 0.0),
			Vector3(side_sgn * 0.146, 0.316, 0.0),
			Vector3(side_sgn * 0.166, 0.354, 0.0),
			Vector3(side_sgn * 0.168, 0.392, 0.0),
			Vector3(side_sgn * 0.148, 0.408, 0.0),
			Vector3(side_sgn * 0.126, 0.392, 0.0),
		]
		var scroll_w: Array[float] = [0.014, 0.013, 0.015, 0.013, 0.015, 0.014, 0.012, 0.014]
		var scroll_t: Array[float] = [0.018, 0.014, 0.016, 0.014, 0.016, 0.015, 0.012, 0.016]
		_add_swept_ribbon(gold_st, scroll_pts, scroll_w, scroll_t, gold_hi, gold_mid, gold_deep, true)
		# Small decorative scroll finial curl bosses at upper & lower handle curves.
		_add_faceted_gem(gold_st, Vector3(side_sgn * 0.168, 0.396, 0.0),
			0.011, 0.011, 0.013, 6, gold_hi, gold_mid, gold_deep)
		_add_faceted_gem(gold_st, Vector3(side_sgn * 0.144, 0.264, 0.0),
			0.010, 0.010, 0.012, 6, gold_hi, gold_mid, gold_deep)

	_commit_surface(mesh, gold_st, _get_vcol_mat(0.26, 0.74))
	_commit_surface(mesh, gem_st, _get_vcol_mat(0.18, 0.22, accent, 1.8 if cursed else 0.58))
	return mesh


# ==============================================================================
# Archetype 3: Hero-Grade Slatted Oak Cargo Crate (`&"crate"`)
# ==============================================================================

static func _sculpt_crate_mesh(tint: Color, accent: Color, _tier: int, cursed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal_st := SurfaceTool.new()
	metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var warm_oak := tint.lerp(Color(0.84, 0.50, 0.17), 0.30)
	var frame_hi := warm_oak.lerp(Color(0.95, 0.68, 0.28), 0.28)
	var frame_mid := warm_oak
	var frame_lo := Color(warm_oak.r * 0.64, warm_oak.g * 0.50, warm_oak.b * 0.36)
	var plank_a := Color(minf(warm_oak.r * 0.94, 1.0), warm_oak.g * 0.84, warm_oak.b * 0.70)
	var plank_b := Color(warm_oak.r * 0.78, warm_oak.g * 0.64, warm_oak.b * 0.48)
	var seam_dark := Color(warm_oak.r * 0.28, warm_oak.g * 0.19, warm_oak.b * 0.11)
	var brace_hi := warm_oak.lerp(Color(0.93, 0.63, 0.24), 0.22)
	var brace_mid := Color(warm_oak.r * 0.88, warm_oak.g * 0.76, warm_oak.b * 0.60)
	var brace_lo := Color(warm_oak.r * 0.58, warm_oak.g * 0.44, warm_oak.b * 0.30)
	var rope_hi := Color(0.86, 0.70, 0.40)
	var rope_lo := Color(0.56, 0.40, 0.19)
	var seal_hi := accent.lerp(Color(1.0, 0.44, 0.28), 0.22)
	var seal_mid := accent
	var seal_lo := accent.darkened(0.32)
	var iron_hi := Color(0.24, 0.22, 0.21)
	var iron_mid := Color(0.14, 0.13, 0.125)
	var iron_lo := Color(0.075, 0.07, 0.07)
	var gold_hi := Color(1.0, 0.86, 0.34)
	var gold_mid := Color(0.98, 0.74, 0.16)
	var gold_lo := Color(0.62, 0.40, 0.08)

	var cy := 0.270  # Crate spans y = 0.000..0.540, x/z = -0.270..+0.270.

	# 1. Dark Recessed Inner Core (forms crisp shadow crevices between individual slats).
	_add_beveled_block(wood_st, Vector3(0.0, cy, 0.0), Vector3(0.454, 0.466, 0.454), 0.008,
		seam_dark, seam_dark, seam_dark)

	# 2. Recessed Individual Slatted Oak Planks (4 horizontal boards on each side + 4 on top).
	for pi in range(4):
		var py := 0.095 + float(pi) * 0.116
		var p_hi := (plank_a if pi % 2 == 0 else plank_b).lightened(0.07)
		var p_mid := plank_a if pi % 2 == 0 else plank_b
		var p_lo := p_mid.darkened(0.18)
		# Front (-Z) & Back (+Z) horizontal planks.
		for fz: float in [-1.0, 1.0]:
			_add_beveled_block(wood_st, Vector3(0.0, py, fz * 0.232), Vector3(0.424, 0.104, 0.020), 0.005,
				p_hi, p_mid, p_lo)
		# Left (-X) & Right (+X) horizontal planks.
		for fx: float in [-1.0, 1.0]:
			_add_beveled_block(wood_st, Vector3(fx * 0.232, py, 0.0), Vector3(0.020, 0.104, 0.424), 0.005,
				p_hi, p_mid, p_lo)
		# Top (+Y) lid planks running along X.
		var pz := -0.165 + float(pi) * 0.110
		_add_beveled_block(wood_st, Vector3(0.0, 0.506, pz), Vector3(0.424, 0.020, 0.098), 0.005,
			p_hi.lightened(0.04), p_mid, p_lo)

	# 3. Chamfered Heavy Outer Corner Frame Timbers (12 rails, grounded flush at y = 0.000).
	for sx: float in [-0.234, 0.234]:
		for sz: float in [-0.234, 0.234]:
			_add_beveled_block(wood_st, Vector3(sx, cy, sz), Vector3(0.072, 0.540, 0.072), 0.011,
				frame_hi, frame_mid, frame_lo)
	for ry: float in [0.034, 0.506]:
		for sz: float in [-0.236, 0.236]:
			_add_beveled_block(wood_st, Vector3(0.0, ry, sz), Vector3(0.410, 0.068, 0.068), 0.010,
				frame_hi, frame_mid, frame_lo)
		for sx: float in [-0.236, 0.236]:
			_add_beveled_block(wood_st, Vector3(sx, ry, 0.0), Vector3(0.068, 0.068, 0.410), 0.010,
				frame_hi, frame_mid, frame_lo)

	# 4. Diagonal Cross-Brace Battens on all 4 vertical faces & top lid.
	var diag_len := 0.525
	for fz: float in [-1.0, 1.0]:
		var b_rot := Basis(Vector3.FORWARD, fz * PI * 0.25)
		_add_beveled_block(wood_st, Vector3(0.0, cy, fz * 0.248), Vector3(diag_len, 0.062, 0.024), 0.006,
			brace_hi, brace_mid, brace_lo, b_rot)
	for fx: float in [-1.0, 1.0]:
		var b_rot := Basis(Vector3.RIGHT, fx * PI * 0.25)
		_add_beveled_block(wood_st, Vector3(fx * 0.248, cy, 0.0), Vector3(0.024, 0.062, diag_len), 0.006,
			brace_hi, brace_mid, brace_lo, b_rot)
	_add_beveled_block(wood_st, Vector3(0.0, 0.522, 0.0), Vector3(diag_len, 0.022, 0.062), 0.006,
		brace_hi.lightened(0.04), brace_mid, brace_lo, Basis(Vector3.UP, PI * 0.25))

	# 5. Forged Iron Corner L-Brackets & Rivet Bosses (all 8 outer corners on metallic surface).
	for sx: float in [-1.0, 1.0]:
		for sy_idx in range(2):
			var sy_sgn := -1.0 if sy_idx == 0 else 1.0
			var by := 0.044 if sy_idx == 0 else 0.496
			var edge_y := 0.014 if sy_idx == 0 else 0.526
			for sz: float in [-1.0, 1.0]:
				# Vertical corner iron strap wrapping X/Z edge.
				_add_beveled_block(metal_st, Vector3(sx * 0.256, by, sz * 0.256),
					Vector3(0.036, 0.088, 0.036), 0.005, iron_hi, iron_mid, iron_lo)
				# Horizontal iron arms extending along X and Z rails.
				_add_beveled_block(metal_st, Vector3(sx * 0.208, edge_y, sz * 0.264),
					Vector3(0.088, 0.028, 0.022), 0.004, iron_hi, iron_mid, iron_lo)
				_add_beveled_block(metal_st, Vector3(sx * 0.264, edge_y, sz * 0.208),
					Vector3(0.022, 0.028, 0.088), 0.004, iron_hi, iron_mid, iron_lo)
				# Raised corner iron nail head.
				_add_pyramid_stud(metal_st, Vector3(sx * 0.273, by, sz * 0.246),
					0.010, 0.007, iron_hi, iron_lo, Vector3(sx, 0.0, 0.0))
				_add_pyramid_stud(metal_st, Vector3(sx * 0.246, by, sz * 0.273),
					0.010, 0.007, iron_hi, iron_lo, Vector3(0.0, 0.0, sz))
				if sy_sgn > 0.0:
					_add_pyramid_stud(metal_st, Vector3(sx * 0.242, 0.542, sz * 0.242),
						0.011, 0.007, iron_hi, iron_lo, Vector3.UP)

	# 6. Knotted Hemp Rope Side Carry Handles (±X faces).
	for side_sgn: float in [-1.0, 1.0]:
		var rope_pts: Array[Vector3] = []
		var rope_rads: Array[float] = []
		var r_steps := 8
		for ri in range(r_steps + 1):
			var t := float(ri) / float(r_steps)
			var u := lerpf(-1.0, 1.0, t)
			var arch := sin(t * PI)
			var px := side_sgn * (0.252 + 0.056 * arch)
			var py := 0.344 - 0.096 * arch
			var pz := u * 0.104
			rope_pts.append(Vector3(px, py, pz))
			rope_rads.append(0.0155 + 0.0025 * sin(t * PI * 6.0))
		_add_swept_tube(wood_st, rope_pts, rope_rads, 6, rope_hi, rope_lo, false, true)
		# Chunky faceted hemp stopper knots + iron grommet collars where rope enters crate.
		for kz: float in [-0.104, 0.104]:
			_add_faceted_gem(wood_st, Vector3(side_sgn * 0.256, 0.344, kz),
				0.022, 0.024, 0.024, 6, rope_hi, rope_hi.darkened(0.12), rope_lo)
			_add_beveled_block(metal_st, Vector3(side_sgn * 0.246, 0.344, kz),
				Vector3(0.014, 0.044, 0.044), 0.004, iron_hi, iron_mid, iron_lo)

	# 7. Proud Painted Company Crest Plate, Gold Compass Emblem & Crimson Wax Seal!
	for fz: float in [-1.0, 1.0]:
		var f_basis := Basis.IDENTITY if fz < 0.0 else Basis(Vector3.UP, PI)
		var plaque_c := Vector3(0.0, cy, fz * 0.264)
		# Chamfered crimson merchant crest plate with gilded brass frame.
		_add_beveled_block(metal_st, plaque_c, Vector3(0.214, 0.164, 0.016), 0.005,
			gold_hi, gold_mid, gold_lo, f_basis)
		_add_beveled_block(wood_st, Vector3(0.0, cy, fz * 0.270), Vector3(0.186, 0.136, 0.012), 0.004,
			seal_hi, seal_mid, seal_lo, f_basis)
		# Raised golden compass-diamond merchant crest at plaque center.
		_add_beveled_block(metal_st, Vector3(0.0, cy, fz * 0.277), Vector3(0.072, 0.072, 0.010), 0.003,
			gold_hi, gold_mid, gold_lo, f_basis * Basis(Vector3.FORWARD, PI * 0.25))
		_add_faceted_gem(metal_st, Vector3(0.0, cy, fz * 0.283), 0.018, 0.008, 0.018, 6,
			gold_hi, gold_mid, gold_lo, f_basis * Basis(Vector3.RIGHT, -PI * 0.5))
		# Stamped crimson wax seal medallion + twin fluttering wax ribbon tails on lower corner!
		var wax_c := Vector3(-fz * 0.074, cy - 0.056, fz * 0.278)
		_add_faceted_gem(wood_st, wax_c, 0.032, 0.012, 0.032, 8,
			seal_hi, seal_mid, seal_lo, f_basis * Basis(Vector3.RIGHT, -PI * 0.5))
		_add_beveled_block(wood_st, wax_c + Vector3(-fz * 0.010, -0.038, -fz * 0.004),
			Vector3(0.016, 0.044, 0.008), 0.002, seal_hi, seal_mid, seal_lo,
			f_basis * Basis(Vector3.FORWARD, 0.22))
		_add_beveled_block(wood_st, wax_c + Vector3(fz * 0.010, -0.038, -fz * 0.004),
			Vector3(0.016, 0.044, 0.008), 0.002, seal_hi, seal_mid, seal_lo,
			f_basis * Basis(Vector3.FORWARD, -0.22))

	# Top lid merchant wax seal & gilded compass badge (readable from above in ship's hold!).
	_add_beveled_block(metal_st, Vector3(0.0, 0.535, 0.0), Vector3(0.146, 0.012, 0.146), 0.004,
		gold_hi, gold_mid, gold_lo, Basis(Vector3.UP, PI * 0.25))
	_add_faceted_gem(wood_st, Vector3(0.0, 0.544, 0.0), 0.046, 0.014, 0.046, 8,
		seal_hi, seal_mid, seal_lo)
	_add_faceted_gem(metal_st, Vector3(0.0, 0.553, 0.0), 0.018, 0.009, 0.018, 6,
		gold_hi, gold_mid, gold_lo)

	_commit_surface(mesh, wood_st, _get_vcol_mat(0.74, 0.03))
	_commit_surface(mesh, metal_st, _get_vcol_mat(0.28, 0.76, accent if cursed else Color.BLACK, 1.4 if cursed else 0.0))
	return mesh


# ==============================================================================
# Archetype 4: Hero-Grade Sculpted Banded Pirate Chest Fallback (`&"chest"`/`&"coffer"`)
# ==============================================================================

static func _sculpt_chest_mesh(tint: Color, accent: Color, tier: int,
		cursed: bool, is_coffer: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal_st := SurfaceTool.new()
	metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_glow := false

	var oak_hi := tint.lightened(0.14)
	var oak_mid := tint
	var oak_sh := tint.darkened(0.22)
	var oak_deep := tint.darkened(0.42)
	var met_hi := accent.lightened(0.18)
	var met_mid := accent
	var met_lo := accent.darkened(0.36)
	var iron_hi := Color(0.34, 0.36, 0.40)
	var iron_lo := Color(0.12, 0.13, 0.16)

	# 1. Tapered Faceted Oak Lower Hull (y = 0.024..0.280, matching chest_treasure.glb).
	var bot_ring: Array[Vector3] = [
		Vector3(-0.296, 0.024, -0.186),
		Vector3(0.296, 0.024, -0.186),
		Vector3(0.296, 0.024, 0.186),
		Vector3(-0.296, 0.024, 0.186),
	]
	var top_ring: Array[Vector3] = [
		Vector3(-0.324, 0.280, -0.214),
		Vector3(0.324, 0.280, -0.214),
		Vector3(0.324, 0.280, 0.214),
		Vector3(-0.324, 0.280, 0.214),
	]
	var hull_c := Vector3(0.0, 0.152, 0.0)
	_emit_outward_quad(wood_st, bot_ring[0], oak_deep, bot_ring[3], oak_deep, bot_ring[2], oak_deep, bot_ring[1], oak_deep, hull_c)
	_emit_outward_quad(wood_st, top_ring[0], oak_hi, top_ring[1], oak_hi, top_ring[2], oak_hi, top_ring[3], oak_hi, hull_c)
	for i in range(4):
		var ni := (i + 1) % 4
		_emit_outward_quad(wood_st,
			bot_ring[i], oak_sh,
			bot_ring[ni], oak_sh,
			top_ring[ni], oak_mid,
			top_ring[i], oak_mid,
			hull_c)

	# Horizontal beveled hull plank ribs for rich chunky silhouette.
	for course_i in range(3):
		var py := 0.072 + float(course_i) * 0.076
		var frac := (py - 0.024) / 0.256
		var hx := lerpf(0.298, 0.326, frac)
		var hz := lerpf(0.188, 0.216, frac)
		var c_p := oak_mid if course_i % 2 == 0 else oak_sh
		for fz: float in [-1.0, 1.0]:
			_add_beveled_block(wood_st, Vector3(0.0, py, fz * hz), Vector3(hx * 1.94, 0.062, 0.016), 0.004,
				c_p.lightened(0.08), c_p, oak_deep)
		for fx: float in [-1.0, 1.0]:
			_add_beveled_block(wood_st, Vector3(fx * hx, py, 0.0), Vector3(0.016, 0.062, hz * 1.92), 0.004,
				c_p.lightened(0.08), c_p, oak_deep)

	# 2. Arched Slatted Barrel Lid (8-segment curved barrel vault extruded along X ±0.328).
	var lid_n := 8
	var lid_c := Vector3(0.0, 0.310, 0.0)
	var lid_l: Array[Vector3] = []
	var lid_r: Array[Vector3] = []
	var lid_cols: Array[Color] = []
	for i in range(lid_n + 1):
		var ang := PI * float(i) / float(lid_n)
		var lz := -0.218 * cos(ang)
		var ly := 0.280 + 0.156 * sin(ang)
		lid_l.append(Vector3(-0.328, ly, lz))
		lid_r.append(Vector3(0.328, ly, lz))
		var stave_tint := oak_sh.lerp(oak_hi, sin(ang))
		if i % 2 == 1:
			stave_tint = stave_tint.darkened(0.08)
		lid_cols.append(stave_tint)
	for i in range(lid_n):
		var c_a := lid_cols[i]
		var c_b := lid_cols[i + 1]
		_emit_outward_quad(wood_st, lid_l[i], c_a, lid_r[i], c_a, lid_r[i + 1], c_b, lid_l[i + 1], c_b, lid_c)
	# Close arched lid side tympanum fans (-X and +X).
	var end_l := Vector3(-0.328, 0.280, 0.0)
	var end_r := Vector3(0.328, 0.280, 0.0)
	for i in range(lid_n):
		_emit_outward_tri(wood_st, end_l, oak_sh, lid_l[i], lid_cols[i], lid_l[i + 1], lid_cols[i + 1], lid_c)
		_emit_outward_tri(wood_st, end_r, oak_sh, lid_r[i + 1], lid_cols[i + 1], lid_r[i], lid_cols[i], lid_c)

	# Decorative painted lid crown plaque.
	var plaque_col := Color(0.68, 0.14, 0.14) if (tier >= 3 and not cursed and not is_coffer) else oak_hi
	_add_beveled_block(wood_st, Vector3(0.0, 0.436, 0.0), Vector3(0.24, 0.022, 0.15), 0.005,
		plaque_col.lightened(0.10), plaque_col, plaque_col.darkened(0.25))

	# 3. Grounded Corner Feet (y = 0.000..0.032), Mid-Seam Rim Band & Lower Corner Brackets.
	for sx: float in [-0.268, 0.268]:
		for sz: float in [-0.158, 0.158]:
			_add_beveled_block(metal_st, Vector3(sx, 0.016, sz), Vector3(0.092, 0.032, 0.092), 0.006,
				met_hi, met_mid, met_lo)
	_add_beveled_block(metal_st, Vector3(0.0, 0.282, 0.0), Vector3(0.668, 0.042, 0.444), 0.007,
		met_hi, met_mid, met_lo)
	for sx: float in [-0.312, 0.312]:
		for sz: float in [-0.200, 0.200]:
			_add_beveled_block(metal_st, Vector3(sx, 0.062, sz), Vector3(0.068, 0.078, 0.068), 0.006,
				met_hi, met_mid, met_lo)

	# 4. Proud Riveted Metal Straps Wrapping Hull & Arched Barrel Lid!
	for sx: float in [-0.238, 0.238]:
		_add_beveled_block(metal_st, Vector3(sx, 0.152, 0.0), Vector3(0.058, 0.264, 0.446), 0.006,
			met_hi, met_mid, met_lo)
		var s_in_l: Array[Vector3] = []
		var s_in_r: Array[Vector3] = []
		var s_out_l: Array[Vector3] = []
		var s_out_r: Array[Vector3] = []
		for i in range(lid_n + 1):
			var ang := PI * float(i) / float(lid_n)
			var ca := cos(ang)
			var sa := sin(ang)
			s_in_l.append(Vector3(sx - 0.029, 0.280 + 0.152 * sa, -0.214 * ca))
			s_in_r.append(Vector3(sx + 0.029, 0.280 + 0.152 * sa, -0.214 * ca))
			s_out_l.append(Vector3(sx - 0.029, 0.280 + 0.166 * sa, -0.228 * ca))
			s_out_r.append(Vector3(sx + 0.029, 0.280 + 0.166 * sa, -0.228 * ca))
		var strap_c := Vector3(sx, 0.300, 0.0)
		for i in range(lid_n):
			var top_col := met_mid.lerp(met_hi, sin(PI * (float(i) + 0.5) / float(lid_n)))
			_emit_outward_quad(metal_st, s_out_l[i], top_col, s_out_r[i], top_col, s_out_r[i + 1], top_col, s_out_l[i + 1], top_col, strap_c)
			_emit_outward_quad(metal_st, s_in_l[i], met_lo, s_out_l[i], met_mid, s_out_l[i + 1], met_mid, s_in_l[i + 1], met_lo, strap_c)
			_emit_outward_quad(metal_st, s_in_r[i + 1], met_lo, s_out_r[i + 1], met_mid, s_out_r[i], met_mid, s_in_r[i], met_lo, strap_c)
		# Faceted square-pyramid rivets studded along strap arch & vertical front/back.
		for ri in [1, 3, 5, 7]:
			var ang := PI * float(ri) / float(lid_n)
			var r_nrm := Vector3(0.0, sin(ang), -cos(ang)).normalized()
			_add_pyramid_stud(metal_st, Vector3(sx, 0.280 + 0.167 * sin(ang), -0.229 * cos(ang)),
				0.015, 0.011, met_hi, met_lo, r_nrm)
		for ry: float in [0.095, 0.215]:
			_add_pyramid_stud(metal_st, Vector3(sx, ry, -0.224), 0.014, 0.010, met_hi, met_lo, Vector3.FORWARD)
			_add_pyramid_stud(metal_st, Vector3(sx, ry, 0.224), 0.014, 0.010, met_hi, met_lo, Vector3.BACK)

	# 5. Ornate Brass Lockplate, Sculpted Padlock & Iron Shackle Loop (-Z front face).
	_add_beveled_block(metal_st, Vector3(0.0, 0.260, -0.228), Vector3(0.132, 0.142, 0.028), 0.006,
		met_hi, met_mid, met_lo)
	_add_beveled_block(metal_st, Vector3(0.0, 0.205, -0.248), Vector3(0.088, 0.096, 0.036), 0.008,
		met_hi, met_mid, met_lo)
	# Dark recessed keyhole slot on padlock face.
	_add_beveled_block(wood_st, Vector3(0.0, 0.200, -0.266), Vector3(0.016, 0.034, 0.006), 0.002,
		Color(0.04, 0.04, 0.05), Color(0.04, 0.04, 0.05), Color(0.04, 0.04, 0.05))
	# Forged iron padlock shackle arch.
	_add_torus(metal_st, Vector3(0.0, 0.262, -0.246), Vector3.BACK, 0.030, 0.009, 10, 5, iron_hi, iron_lo)

	# 6. Side Iron Carrying Ring Handles (±X faces).
	for side_sgn: float in [-1.0, 1.0]:
		_add_beveled_block(metal_st, Vector3(side_sgn * 0.332, 0.172, 0.0), Vector3(0.028, 0.084, 0.122), 0.005,
			met_hi, met_mid, met_lo)
		_add_torus(metal_st, Vector3(side_sgn * 0.350, 0.142, 0.0), Vector3(side_sgn, 0.0, 0.0),
			0.052, 0.013, 10, 5, iron_hi, iron_lo)

	# 7. Tier / Cursed Accents on Sculpted Fallback Chest too.
	if cursed:
		_append_cursed_chest_overlay(wood_st, glow_st, tint, accent)
		has_glow = true
	elif tier >= 4:
		_append_ornate_chest_overlay(metal_st, glow_st, tint, accent, is_coffer)
		has_glow = true

	_commit_surface(mesh, wood_st, _get_vcol_mat(0.76, 0.06))
	_commit_surface(mesh, metal_st, _get_vcol_mat(0.28, 0.84))
	if has_glow:
		var glow_col := accent if cursed else (Color(0.16, 0.46, 0.96) if is_coffer else Color(0.92, 0.16, 0.22))
		_commit_surface(mesh, glow_st, _get_vcol_mat(0.20, 0.18, glow_col, 2.4 if cursed else 0.72))
	return mesh


# ==============================================================================
# Archetype 5: Hero-Grade Sculpted Volcanic Chest of Blazing Rage (`&"rage_chest"`)
# ==============================================================================

static func _sculpt_rage_chest_mesh(tint: Color, accent: Color, _tier: int, _cursed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var hull_st := SurfaceTool.new()
	hull_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var magma_st := SurfaceTool.new()
	magma_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var obs_hi := tint.lightened(0.16)
	var obs_mid := tint
	var obs_sh := tint.darkened(0.26)
	var obs_deep := Color(0.06, 0.04, 0.04)

	var iron_hi := Color(0.36, 0.29, 0.27)
	var iron_mid := Color(0.21, 0.17, 0.16)
	var iron_lo := Color(0.09, 0.07, 0.07)
	var horn_tip := Color(0.48, 0.24, 0.14)

	var magma_core := Color(1.00, 0.92, 0.52)
	var magma_hot := accent.lerp(Color(1.0, 0.82, 0.28), 0.45)
	var magma_mid := accent
	var magma_deep := Color(0.76, 0.14, 0.03)

	# 1. Tapered Faceted Obsidian-Iron Lower Hull (y = 0.028..0.280) with Armored Side Slabs.
	var bot_ring: Array[Vector3] = [
		Vector3(-0.298, 0.028, -0.188),
		Vector3(0.298, 0.028, -0.188),
		Vector3(0.298, 0.028, 0.188),
		Vector3(-0.298, 0.028, 0.188),
	]
	var top_ring: Array[Vector3] = [
		Vector3(-0.326, 0.280, -0.216),
		Vector3(0.326, 0.280, -0.216),
		Vector3(0.326, 0.280, 0.216),
		Vector3(-0.326, 0.280, 0.216),
	]
	var hull_c := Vector3(0.0, 0.154, 0.0)
	_emit_outward_quad(hull_st, bot_ring[0], obs_deep, bot_ring[3], obs_deep, bot_ring[2], obs_deep, bot_ring[1], obs_deep, hull_c)
	_emit_outward_quad(hull_st, top_ring[0], obs_hi, top_ring[1], obs_hi, top_ring[2], obs_hi, top_ring[3], obs_hi, hull_c)
	for i in range(4):
		var ni := (i + 1) % 4
		_emit_outward_quad(hull_st,
			bot_ring[i], obs_sh,
			bot_ring[ni], obs_sh,
			top_ring[ni], obs_mid,
			top_ring[i], obs_mid,
			hull_c)

	# Horizontal volcanic basalt-iron armor plates framing magma crevices on front/back/sides.
	for course_i in range(3):
		var py := 0.074 + float(course_i) * 0.076
		var frac := (py - 0.028) / 0.252
		var hx := lerpf(0.300, 0.328, frac)
		var hz := lerpf(0.190, 0.218, frac)
		var c_p := obs_mid if course_i % 2 == 0 else obs_sh
		for fz: float in [-1.0, 1.0]:
			_add_beveled_block(hull_st, Vector3(0.0, py, fz * hz), Vector3(hx * 1.92, 0.056, 0.018), 0.004,
				c_p.lightened(0.08), c_p, obs_deep)
		for fx: float in [-1.0, 1.0]:
			_add_beveled_block(hull_st, Vector3(fx * hx, py, 0.0), Vector3(0.018, 0.056, hz * 1.90), 0.004,
				c_p.lightened(0.08), c_p, obs_deep)

	# 2. Armored Arched Volcanic Barrel Lid (8-segment faceted obsidian vault, y = 0.280..0.440).
	var lid_n := 8
	var lid_c := Vector3(0.0, 0.312, 0.0)
	var lid_l: Array[Vector3] = []
	var lid_r: Array[Vector3] = []
	var lid_cols: Array[Color] = []
	for i in range(lid_n + 1):
		var ang := PI * float(i) / float(lid_n)
		var lz := -0.220 * cos(ang)
		var ly := 0.280 + 0.158 * sin(ang)
		lid_l.append(Vector3(-0.330, ly, lz))
		lid_r.append(Vector3(0.330, ly, lz))
		var stave_c := obs_sh.lerp(obs_hi, sin(ang))
		if i % 2 == 1:
			stave_c = stave_c.darkened(0.10)
		lid_cols.append(stave_c)
	for i in range(lid_n):
		_emit_outward_quad(hull_st, lid_l[i], lid_cols[i], lid_r[i], lid_cols[i],
			lid_r[i + 1], lid_cols[i + 1], lid_l[i + 1], lid_cols[i + 1], lid_c)
	var end_l := Vector3(-0.330, 0.280, 0.0)
	var end_r := Vector3(0.330, 0.280, 0.0)
	for i in range(lid_n):
		_emit_outward_tri(hull_st, end_l, obs_sh, lid_l[i], lid_cols[i], lid_l[i + 1], lid_cols[i + 1], lid_c)
		_emit_outward_tri(hull_st, end_r, obs_sh, lid_r[i + 1], lid_cols[i + 1], lid_r[i], lid_cols[i], lid_c)

	# Heavy obsidian furnace crown plate atop lid crest.
	_add_beveled_block(hull_st, Vector3(0.0, 0.440, 0.0), Vector3(0.32, 0.022, 0.14), 0.005,
		obs_hi, obs_mid, obs_deep)

	# 3. Grounded Forged-Iron Claw Feet (y = 0.000..0.036), Lower Corner Shoes & Mid-Seam Collar.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_beveled_block(iron_st, Vector3(sx * 0.270, 0.018, sz * 0.160), Vector3(0.096, 0.036, 0.096), 0.006,
				iron_hi, iron_mid, iron_lo)
			_add_beveled_block(iron_st, Vector3(sx * 0.314, 0.068, sz * 0.202), Vector3(0.072, 0.084, 0.072), 0.006,
				iron_hi, iron_mid, iron_lo)
	# Heavy iron seam collar framing the glowing magma lid joint.
	_add_beveled_block(iron_st, Vector3(0.0, 0.264, 0.0), Vector3(0.674, 0.026, 0.448), 0.005,
		iron_hi, iron_mid, iron_lo)
	_add_beveled_block(iron_st, Vector3(0.0, 0.300, 0.0), Vector3(0.674, 0.024, 0.448), 0.005,
		iron_hi, iron_mid, iron_lo)

	# 4. Twin Heavy Riveted Volcanic Iron Straps Wrapping Hull & Barrel Lid + Spiked Studs!
	for sx: float in [-0.232, 0.232]:
		_add_beveled_block(iron_st, Vector3(sx, 0.154, 0.0), Vector3(0.062, 0.266, 0.452), 0.006,
			iron_hi, iron_mid, iron_lo)
		var s_in_l: Array[Vector3] = []
		var s_in_r: Array[Vector3] = []
		var s_out_l: Array[Vector3] = []
		var s_out_r: Array[Vector3] = []
		for i in range(lid_n + 1):
			var ang := PI * float(i) / float(lid_n)
			var ca := cos(ang)
			var sa := sin(ang)
			s_in_l.append(Vector3(sx - 0.031, 0.280 + 0.154 * sa, -0.216 * ca))
			s_in_r.append(Vector3(sx + 0.031, 0.280 + 0.154 * sa, -0.216 * ca))
			s_out_l.append(Vector3(sx - 0.031, 0.280 + 0.172 * sa, -0.234 * ca))
			s_out_r.append(Vector3(sx + 0.031, 0.280 + 0.172 * sa, -0.234 * ca))
		var strap_c := Vector3(sx, 0.302, 0.0)
		for i in range(lid_n):
			var top_col := iron_mid.lerp(iron_hi, sin(PI * (float(i) + 0.5) / float(lid_n)))
			_emit_outward_quad(iron_st, s_out_l[i], top_col, s_out_r[i], top_col, s_out_r[i + 1], top_col, s_out_l[i + 1], top_col, strap_c)
			_emit_outward_quad(iron_st, s_in_l[i], iron_lo, s_out_l[i], iron_mid, s_out_l[i + 1], iron_mid, s_in_l[i + 1], iron_lo, strap_c)
			_emit_outward_quad(iron_st, s_in_r[i + 1], iron_lo, s_out_r[i + 1], iron_mid, s_out_r[i], iron_mid, s_in_r[i], iron_lo, strap_c)
		# Sharp forged volcanic iron pyramid rivets along straps.
		for ri in [1, 3, 5, 7]:
			var ang := PI * float(ri) / float(lid_n)
			var r_nrm := Vector3(0.0, sin(ang), -cos(ang)).normalized()
			_add_pyramid_stud(iron_st, Vector3(sx, 0.280 + 0.173 * sin(ang), -0.235 * cos(ang)),
				0.018, 0.016, iron_hi, iron_lo, r_nrm)
		for ry: float in [0.095, 0.210]:
			_add_pyramid_stud(iron_st, Vector3(sx, ry, -0.228), 0.016, 0.013, iron_hi, iron_lo, Vector3.FORWARD)
			_add_pyramid_stud(iron_st, Vector3(sx, ry, 0.228), 0.016, 0.013, iron_hi, iron_lo, Vector3.BACK)

	# 5. Four Forged Demon-Horn Corner Clasps Curving Upward & Outward from Lid Corners!
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# Bolted corner clasp collar.
			_add_beveled_block(iron_st, Vector3(sx * 0.326, 0.286, sz * 0.216), Vector3(0.056, 0.068, 0.056), 0.006,
				iron_hi, iron_mid, iron_lo)
			# Swept curving forged iron demon horn rising cleanly above corner shoulder.
			var horn_pts: Array[Vector3] = [
				Vector3(sx * 0.332, 0.304, sz * 0.220),
				Vector3(sx * 0.362, 0.348, sz * 0.244),
				Vector3(sx * 0.374, 0.398, sz * 0.254),
				Vector3(sx * 0.354, 0.444, sz * 0.236),
				Vector3(sx * 0.318, 0.472, sz * 0.206),
			]
			var horn_rads: Array[float] = [0.022, 0.018, 0.014, 0.009, 0.003]
			_add_swept_tube(iron_st, horn_pts, horn_rads, 6, horn_tip, iron_lo, false, true)

	# 6. Front Ember Keyhole Grate & Volcanic Furnace Lockplate (-Z front face).
	# Heavy wrought-iron grate frame.
	_add_beveled_block(iron_st, Vector3(0.0, 0.215, -0.234), Vector3(0.172, 0.164, 0.026), 0.006,
		iron_hi, iron_mid, iron_lo)
	# Glowing molten firebox core behind the iron grate bars!
	_add_beveled_block(magma_st, Vector3(0.0, 0.215, -0.242), Vector3(0.128, 0.118, 0.016), 0.004,
		magma_core, magma_hot, magma_deep)
	# Three vertical wrought-iron furnace grate bars + center ember keyhole diamond.
	for gx: float in [-0.042, 0.0, 0.042]:
		_add_beveled_block(iron_st, Vector3(gx, 0.215, -0.252), Vector3(0.016, 0.132, 0.014), 0.003,
			iron_hi, iron_mid, iron_lo)
	_add_beveled_block(iron_st, Vector3(0.0, 0.215, -0.253), Vector3(0.146, 0.018, 0.014), 0.003,
		iron_hi, iron_mid, iron_lo)
	_add_faceted_gem(magma_st, Vector3(0.0, 0.215, -0.261), 0.024, 0.012, 0.032, 6,
		magma_core, magma_hot, magma_deep, Basis(Vector3.RIGHT, -PI * 0.5))

	# 7. Heavy Top Iron Ring Handles atop Domed Lid + Side Iron Carry Shackles!
	for sx: float in [-0.125, 0.125]:
		_add_beveled_block(iron_st, Vector3(sx, 0.452, 0.0), Vector3(0.046, 0.028, 0.052), 0.005,
			iron_hi, iron_mid, iron_lo)
		_add_torus(iron_st, Vector3(sx, 0.474, 0.0), Vector3.BACK, 0.038, 0.011, 10, 5, iron_hi, iron_lo)
	for side_sgn: float in [-1.0, 1.0]:
		_add_beveled_block(iron_st, Vector3(side_sgn * 0.336, 0.172, 0.0), Vector3(0.028, 0.088, 0.128), 0.005,
			iron_hi, iron_mid, iron_lo)
		_add_torus(iron_st, Vector3(side_sgn * 0.354, 0.142, 0.0), Vector3(side_sgn, 0.0, 0.0),
			0.050, 0.012, 10, 5, iron_hi, iron_lo)

	# 8. Glowing Jagged Magma Fracture Bands & Volcanic Seam Veins (`magma_st`).
	# Continuous molten lid-seam band glowing between upper & lower iron flanges (y = 0.282).
	_add_beveled_block(magma_st, Vector3(0.0, 0.282, -0.228), Vector3(0.678, 0.018, 0.014), 0.004,
		magma_core, magma_hot, magma_deep)
	_add_beveled_block(magma_st, Vector3(0.0, 0.282, 0.228), Vector3(0.678, 0.018, 0.014), 0.004,
		magma_core, magma_hot, magma_deep)
	_add_beveled_block(magma_st, Vector3(-0.339, 0.282, 0.0), Vector3(0.014, 0.018, 0.460), 0.004,
		magma_core, magma_hot, magma_deep)
	_add_beveled_block(magma_st, Vector3(0.339, 0.282, 0.0), Vector3(0.014, 0.018, 0.460), 0.004,
		magma_core, magma_hot, magma_deep)

	# Jagged magma fractures arching across domed obsidian lid & crackling down front/back hull!
	for side_sgn: float in [-1.0, 1.0]:
		var lid_pts: Array[Vector3] = []
		var lid_rads: Array[float] = []
		for i in range(9):
			var frac := float(i) / 8.0
			var ang := lerpf(0.16, PI - 0.16, frac)
			var zig := sin(frac * PI * 4.0) * 0.024 * side_sgn
			var px := side_sgn * 0.108 + zig
			var py := 0.280 + 0.166 * sin(ang)
			var pz := -0.226 * cos(ang)
			lid_pts.append(Vector3(px, py, pz))
			lid_rads.append(0.0095 * (0.65 + 0.55 * sin(frac * PI)))
		_add_swept_tube(magma_st, lid_pts, lid_rads, 5, magma_core, magma_deep, false, true)

		# Diagonal molten hull cracks on front & back obsidian panels.
		for face_z: float in [-1.0, 1.0]:
			var crack_pts: Array[Vector3] = [
				Vector3(side_sgn * 0.140, 0.274, face_z * 0.226),
				Vector3(side_sgn * 0.112, 0.214, face_z * 0.218),
				Vector3(side_sgn * 0.158, 0.148, face_z * 0.211),
				Vector3(side_sgn * 0.126, 0.072, face_z * 0.204),
			]
			var crack_rads: Array[float] = [0.010, 0.0085, 0.007, 0.005]
			_add_swept_tube(magma_st, crack_pts, crack_rads, 5, magma_core, magma_deep, false, true)

		# Molten side-panel magma fissures radiating past carry shackles.
		var side_pts: Array[Vector3] = [
			Vector3(side_sgn * 0.334, 0.276, -0.095),
			Vector3(side_sgn * 0.326, 0.200, -0.060),
			Vector3(side_sgn * 0.320, 0.125, -0.105),
			Vector3(side_sgn * 0.312, 0.062, -0.068),
		]
		_add_swept_tube(magma_st, side_pts, [0.009, 0.0075, 0.0065, 0.0045], 5, magma_hot, magma_deep, false, true)

	# Glowing central crown magma rift on lid crest.
	var crown_pts: Array[Vector3] = [
		Vector3(-0.075, 0.451, -0.025),
		Vector3(-0.022, 0.453, 0.018),
		Vector3(0.026, 0.453, -0.016),
		Vector3(0.078, 0.451, 0.024),
	]
	_add_swept_tube(magma_st, crown_pts, [0.007, 0.010, 0.010, 0.007], 5, magma_core, magma_mid, false, true)

	_commit_surface(mesh, hull_st, _get_vcol_mat(0.72, 0.16))
	_commit_surface(mesh, iron_st, _get_vcol_mat(0.30, 0.84))
	_commit_surface(mesh, magma_st, _get_vcol_mat(0.18, 0.14, accent, 2.75))
	return mesh


# ==============================================================================
# Flat-Faceted `SurfaceTool` Sculpting Primitives (`set_smooth_group(-1)`)
# ==============================================================================

static func _emit_flat_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-12:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _emit_flat_quad(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, d: Vector3, cd: Color) -> void:
	_emit_flat_tri(st, a, ca, b, cb, c, cc)
	_emit_flat_tri(st, a, ca, c, cc, d, cd)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		_emit_flat_tri(st, a, ca, c, cc, b, cb)
	else:
		_emit_flat_tri(st, a, ca, b, cb, c, cc)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, d: Vector3, cd: Color,
		ref_center: Vector3) -> void:
	_emit_outward_tri(st, a, ca, b, cb, c, cc, ref_center)
	_emit_outward_tri(st, a, ca, c, cc, d, cd, ref_center)


static func _add_beveled_block(st: SurfaceTool, center: Vector3, size: Vector3, bevel: float,
		col_top: Color, col_side: Color, col_bot: Color, basis: Basis = Basis.IDENTITY) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var bx := minf(bevel, hx * 0.44)
	var by := minf(bevel, hy * 0.44)
	var bz := minf(bevel, hz * 0.44)
	var t_in: Array[Vector3] = [
		center + basis * Vector3(-hx + bx, hy, -hz + bz),
		center + basis * Vector3(hx - bx, hy, -hz + bz),
		center + basis * Vector3(hx - bx, hy, hz - bz),
		center + basis * Vector3(-hx + bx, hy, hz - bz),
	]
	var t_out: Array[Vector3] = [
		center + basis * Vector3(-hx, hy - by, -hz),
		center + basis * Vector3(hx, hy - by, -hz),
		center + basis * Vector3(hx, hy - by, hz),
		center + basis * Vector3(-hx, hy - by, hz),
	]
	var b_out: Array[Vector3] = [
		center + basis * Vector3(-hx, -hy + by, -hz),
		center + basis * Vector3(hx, -hy + by, -hz),
		center + basis * Vector3(hx, -hy + by, hz),
		center + basis * Vector3(-hx, -hy + by, hz),
	]
	var b_in: Array[Vector3] = [
		center + basis * Vector3(-hx + bx, -hy, -hz + bz),
		center + basis * Vector3(hx - bx, -hy, -hz + bz),
		center + basis * Vector3(hx - bx, -hy, hz - bz),
		center + basis * Vector3(-hx + bx, -hy, hz - bz),
	]
	_emit_flat_quad(st, t_in[0], col_top, t_in[1], col_top, t_in[2], col_top, t_in[3], col_top)
	_emit_flat_quad(st, b_in[0], col_bot, b_in[3], col_bot, b_in[2], col_bot, b_in[1], col_bot)
	var col_bev := col_top.lerp(col_side, 0.45)
	for i in range(4):
		var j := (i + 1) % 4
		_emit_flat_quad(st, t_out[i], col_bev, t_out[j], col_bev, t_in[j], col_top, t_in[i], col_top)
		_emit_flat_quad(st, b_out[i], col_bot, b_out[j], col_bot, t_out[j], col_side, t_out[i], col_side)
		_emit_flat_quad(st, b_in[i], col_bot, b_in[j], col_bot, b_out[j], col_bot, b_out[i], col_bot)


static func _add_faceted_gem(st: SurfaceTool, center: Vector3, rx: float, ry: float, rz: float,
		sides: int, col_top: Color, col_mid: Color, col_bot: Color,
		basis: Basis = Basis.IDENTITY) -> void:
	var table_ring: Array[Vector3] = []
	var girdle_ring: Array[Vector3] = []
	var top_c := center + basis * Vector3(0.0, ry, 0.0)
	var bot_c := center + basis * Vector3(0.0, -ry * 0.85, 0.0)
	for k in range(sides):
		var a := float(k) / float(sides) * TAU
		var ca := cos(a)
		var sa := sin(a)
		table_ring.append(center + basis * Vector3(ca * rx * 0.56, ry * 0.72, sa * rz * 0.56))
		girdle_ring.append(center + basis * Vector3(ca * rx, 0.0, sa * rz))
	for k in range(sides):
		var nk := (k + 1) % sides
		_emit_outward_tri(st, top_c, col_top, table_ring[k], col_top, table_ring[nk], col_top, center)
		_emit_outward_quad(st, table_ring[k], col_top, table_ring[nk], col_top,
			girdle_ring[nk], col_mid, girdle_ring[k], col_mid, center)
		_emit_outward_tri(st, bot_c, col_bot, girdle_ring[nk], col_mid, girdle_ring[k], col_mid, center)


static func _add_pyramid_stud(st: SurfaceTool, base_center: Vector3, width: float, height: float,
		col_hi: Color, col_lo: Color, normal: Vector3) -> void:
	var n := normal.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.90 else Vector3.RIGHT
	var bx := n.cross(ref).normalized()
	var by := n.cross(bx).normalized()
	var hw := width * 0.5
	var apex := base_center + n * height
	var corners: Array[Vector3] = [
		base_center + (-bx - by) * hw,
		base_center + (bx - by) * hw,
		base_center + (bx + by) * hw,
		base_center + (-bx + by) * hw,
	]
	var inner_ref := base_center - n * (height * 0.25)
	for i in range(4):
		var ni := (i + 1) % 4
		_emit_outward_tri(st, corners[i], col_lo, corners[ni], col_lo, apex, col_hi, inner_ref)
	_emit_outward_quad(st, corners[0], col_lo, corners[3], col_lo, corners[2], col_lo, corners[1], col_lo, apex)


static func _add_lathe_y(st: SurfaceTool, stations: Array[Array], segs: int,
		angle_offset: float = 0.0, flute_amp: float = 0.0, flute_count: int = 0,
		scallop_amp: float = 0.0, offset: Vector3 = Vector3.ZERO) -> void:
	for j in range(stations.size() - 1):
		var s0: Array = stations[j]
		var s1: Array = stations[j + 1]
		var y0: float = float(s0[0])
		var r0: float = float(s0[1])
		var c0: Color = s0[2] as Color
		var fw0: float = float(s0[3]) if s0.size() > 3 else 0.0
		var sw0: float = float(s0[4]) if s0.size() > 4 else 0.0

		var y1: float = float(s1[0])
		var r1: float = float(s1[1])
		var c1: Color = s1[2] as Color
		var fw1: float = float(s1[3]) if s1.size() > 3 else 0.0
		var sw1: float = float(s1[4]) if s1.size() > 4 else 0.0

		for k in range(segs):
			var a0 := angle_offset + float(k) / float(segs) * TAU
			var a1 := angle_offset + float(k + 1) / float(segs) * TAU
			var fl0 := cos(float(flute_count) * (a0 - angle_offset)) if flute_count > 0 else 0.0
			var fl1 := cos(float(flute_count) * (a1 - angle_offset)) if flute_count > 0 else 0.0
			var sc0 := 0.5 + 0.5 * fl0
			var sc1 := 0.5 + 0.5 * fl1

			var rr00 := r0 * (1.0 + flute_amp * fw0 * fl0)
			var rr01 := r0 * (1.0 + flute_amp * fw0 * fl1)
			var rr10 := r1 * (1.0 + flute_amp * fw1 * fl0)
			var rr11 := r1 * (1.0 + flute_amp * fw1 * fl1)

			var yy00 := y0 + scallop_amp * sw0 * sc0
			var yy01 := y0 + scallop_amp * sw0 * sc1
			var yy10 := y1 + scallop_amp * sw1 * sc0
			var yy11 := y1 + scallop_amp * sw1 * sc1

			var p00 := offset + Vector3(cos(a0) * rr00, yy00, sin(a0) * rr00)
			var p01 := offset + Vector3(cos(a1) * rr01, yy01, sin(a1) * rr01)
			var p10 := offset + Vector3(cos(a0) * rr10, yy10, sin(a0) * rr10)
			var p11 := offset + Vector3(cos(a1) * rr11, yy11, sin(a1) * rr11)

			var cc00 := _shade_flute(c0, fl0 * fw0)
			var cc01 := _shade_flute(c0, fl1 * fw0)
			var cc10 := _shade_flute(c1, fl0 * fw1)
			var cc11 := _shade_flute(c1, fl1 * fw1)

			if r0 > 1e-5 and r1 > 1e-5:
				_emit_flat_tri(st, p00, cc00, p11, cc11, p10, cc10)
				_emit_flat_tri(st, p00, cc00, p01, cc01, p11, cc11)
			elif r1 > 1e-5:
				_emit_flat_tri(st, p00, cc00, p11, cc11, p10, cc10)
			elif r0 > 1e-5:
				_emit_flat_tri(st, p00, cc00, p01, cc01, p11, cc11)


static func _shade_flute(base_col: Color, flute_val: float) -> Color:
	if flute_val > 0.0:
		return base_col.lightened(0.09 * flute_val)
	return base_col.darkened(0.14 * (-flute_val))


static func _add_swept_ribbon(st: SurfaceTool, pts: Array[Vector3], widths: Array[float],
		thicknesses: Array[float], col_hi: Color, col_mid: Color, col_lo: Color,
		cap_ends: bool = true, closed_loop: bool = false) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings: Array[Array] = []
	var prev_u := Vector3.ZERO
	for i in range(n):
		var p := pts[i]
		var tang: Vector3
		if closed_loop:
			tang = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		elif i == 0:
			tang = (pts[1] - p).normalized()
		elif i == n - 1:
			tang = (p - pts[n - 2]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		if tang.length_squared() < 1e-8:
			tang = Vector3.UP
		var u: Vector3
		if prev_u.length_squared() < 1e-6:
			var ref := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.88 else Vector3.RIGHT
			u = tang.cross(ref).normalized()
		else:
			u = (prev_u - tang * prev_u.dot(tang))
			if u.length_squared() < 1e-6:
				var ref := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.88 else Vector3.RIGHT
				u = tang.cross(ref).normalized()
			else:
				u = u.normalized()
		prev_u = u
		var v := tang.cross(u).normalized()
		var hw := widths[i] * 0.5
		var ht := thicknesses[i] * 0.5
		rings.append([
			p - u * hw + v * ht,
			p + u * hw + v * ht,
			p + u * hw - v * ht,
			p - u * hw - v * ht,
		])

	var face_cols: Array[Color] = [col_hi, col_mid, col_lo, col_mid]
	var seg_count := n if closed_loop else n - 1
	for i in range(seg_count):
		var ni := (i + 1) % n
		var r0: Array = rings[i]
		var r1: Array = rings[ni]
		var mid := (pts[i] + pts[ni]) * 0.5
		for k in range(4):
			var nk := (k + 1) % 4
			var fc := face_cols[k]
			_emit_outward_quad(st,
				r0[k] as Vector3, fc,
				r1[k] as Vector3, fc,
				r1[nk] as Vector3, fc,
				r0[nk] as Vector3, fc,
				mid)

	if cap_ends and not closed_loop:
		var r_first: Array = rings[0]
		var in_first := pts[1]
		_emit_outward_quad(st, r_first[0] as Vector3, col_mid, r_first[3] as Vector3, col_lo,
			r_first[2] as Vector3, col_lo, r_first[1] as Vector3, col_hi, in_first)
		var r_last: Array = rings[n - 1]
		var in_last := pts[n - 2]
		_emit_outward_quad(st, r_last[0] as Vector3, col_hi, r_last[1] as Vector3, col_hi,
			r_last[2] as Vector3, col_lo, r_last[3] as Vector3, col_mid, in_last)


static func _add_swept_tube(st: SurfaceTool, pts: Array[Vector3], radii: Array[float],
		segs: int, col_hi: Color, col_lo: Color, closed_loop: bool = false,
		cap_ends: bool = true) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings: Array[Array] = []
	var prev_u := Vector3.ZERO
	for i in range(n):
		var p := pts[i]
		var tang: Vector3
		if closed_loop:
			tang = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		elif i == 0:
			tang = (pts[1] - p).normalized()
		elif i == n - 1:
			tang = (p - pts[n - 2]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		if tang.length_squared() < 1e-8:
			tang = Vector3.UP
		var u: Vector3
		if prev_u.length_squared() < 1e-6:
			var ref := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.88 else Vector3.RIGHT
			u = tang.cross(ref).normalized()
		else:
			u = prev_u - tang * prev_u.dot(tang)
			if u.length_squared() < 1e-6:
				var ref := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.88 else Vector3.RIGHT
				u = tang.cross(ref).normalized()
			else:
				u = u.normalized()
		prev_u = u
		var v := tang.cross(u).normalized()
		var r := radii[i]
		var ring: Array[Vector3] = []
		for k in range(segs):
			var a := float(k) / float(segs) * TAU
			ring.append(p + (u * cos(a) + v * sin(a)) * r)
		rings.append(ring)

	var seg_count := n if closed_loop else n - 1
	for i in range(seg_count):
		var ni := (i + 1) % n
		var r0: Array = rings[i]
		var r1: Array = rings[ni]
		var mid := (pts[i] + pts[ni]) * 0.5
		for k in range(segs):
			var nk := (k + 1) % segs
			var p00 := r0[k] as Vector3
			var p01 := r0[nk] as Vector3
			var p10 := r1[k] as Vector3
			var p11 := r1[nk] as Vector3
			var s0 := clampf(0.5 + 0.5 * (p00 - pts[i]).normalized().y, 0.0, 1.0)
			var s1 := clampf(0.5 + 0.5 * (p01 - pts[i]).normalized().y, 0.0, 1.0)
			var c0 := col_lo.lerp(col_hi, s0)
			var c1 := col_lo.lerp(col_hi, s1)
			_emit_outward_quad(st, p00, c0, p10, c0, p11, c1, p01, c1, mid)

	if cap_ends and not closed_loop:
		var r_first: Array = rings[0]
		var p_first := pts[0]
		var ref_first := pts[1]
		for k in range(segs):
			var nk := (k + 1) % segs
			_emit_outward_tri(st, p_first, col_lo, r_first[nk] as Vector3, col_lo, r_first[k] as Vector3, col_lo, ref_first)
		var r_last: Array = rings[n - 1]
		var p_last := pts[n - 1]
		var ref_last := pts[n - 2]
		for k in range(segs):
			var nk := (k + 1) % segs
			_emit_outward_tri(st, p_last, col_hi, r_last[k] as Vector3, col_hi, r_last[nk] as Vector3, col_hi, ref_last)


static func _add_torus(st: SurfaceTool, center: Vector3, normal_axis: Vector3,
		major_r: float, minor_r: float, major_segs: int, minor_segs: int,
		col_hi: Color, col_lo: Color) -> void:
	var n := normal_axis.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.90 else Vector3.RIGHT
	var bx := n.cross(ref).normalized()
	var by := n.cross(bx).normalized()
	for i in range(major_segs):
		var u0 := float(i) / float(major_segs) * TAU
		var u1 := float(i + 1) / float(major_segs) * TAU
		var r_u0 := bx * cos(u0) + by * sin(u0)
		var r_u1 := bx * cos(u1) + by * sin(u1)
		var tc0 := center + r_u0 * major_r
		var tc1 := center + r_u1 * major_r
		var tube_mid := (tc0 + tc1) * 0.5
		for j in range(minor_segs):
			var v0 := float(j) / float(minor_segs) * TAU
			var v1 := float(j + 1) / float(minor_segs) * TAU
			var d00 := r_u0 * cos(v0) + n * sin(v0)
			var d01 := r_u0 * cos(v1) + n * sin(v1)
			var d10 := r_u1 * cos(v0) + n * sin(v0)
			var d11 := r_u1 * cos(v1) + n * sin(v1)
			var p00 := tc0 + d00 * minor_r
			var p01 := tc0 + d01 * minor_r
			var p10 := tc1 + d10 * minor_r
			var p11 := tc1 + d11 * minor_r
			var c00 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d00.y, 0.0, 1.0))
			var c01 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d01.y, 0.0, 1.0))
			var c10 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d10.y, 0.0, 1.0))
			var c11 := col_lo.lerp(col_hi, clampf(0.5 + 0.5 * d11.y, 0.0, 1.0))
			_emit_outward_quad(st, p00, c00, p10, c10, p11, c11, p01, c01, tube_mid)

