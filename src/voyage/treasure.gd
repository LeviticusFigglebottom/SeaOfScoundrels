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
		"tint": Color(0.92, 0.74, 0.24),
		"accent_tint": Color(0.18, 0.68, 0.74),
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
		"tint": Color(0.78, 0.56, 0.30),
		"accent_tint": Color(0.76, 0.22, 0.16),
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
	return {
		"damaged": next_integrity < prev_integrity,
		"integrity": next_integrity,
		"gold_value": new_gold,
	}


## Apply impact damage when a fragile cargo item is dropped hard.
static func notify_drop_impact(item: Node, impact_speed: float) -> Dictionary:
	if impact_speed <= FRAGILE_IMPACT_THRESHOLD:
		return {"damaged": false, "integrity": float(item.get_meta(&"integrity", 1.0)) if item != null else 1.0}
	var excess := (impact_speed - FRAGILE_IMPACT_THRESHOLD) / 8.0
	return damage_fragile_carryable(item, clampf(excess * 0.35, 0.08, 0.45))


## Tick cursed & fragile treasures aboard a ship (host-only, duck-typed ship API).
## Returns {flood_added: float, damaged_count: int, total_cargo_value: int}.
static func step_aboard_hazards(items: Array, ship: Node, delta: float) -> Dictionary:
	var result := {"flood_added": 0.0, "damaged_count": 0, "total_cargo_value": 0}
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


static func _build_visual(entry: Dictionary) -> Node3D:
	var shape_kind: StringName = entry["shape"]
	if (shape_kind == &"chest" or shape_kind == &"coffer") and ResourceLoader.exists(CHEST_GLB_PATH):
		var packed: Variant = ResourceLoader.load(CHEST_GLB_PATH)
		if packed is PackedScene:
			var inst: Node = (packed as PackedScene).instantiate()
			if inst is Node3D:
				return inst as Node3D
	var root := Node3D.new()
	var body_mat := _make_mat(entry["tint"], 0.72, 0.08, false)
	var accent_mat := _make_mat(entry["accent_tint"], 0.35, 0.65, bool(entry["cursed"]) or shape_kind == &"skull")

	match shape_kind:
		&"skull":
			var cranium := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.16
			sph.height = 0.30
			sph.radial_segments = 10
			sph.rings = 6
			cranium.mesh = sph
			cranium.material_override = body_mat
			cranium.position = Vector3(0.0, 0.22, 0.0)
			root.add_child(cranium)

			var jaw := MeshInstance3D.new()
			var jaw_box := BoxMesh.new()
			jaw_box.size = Vector3(0.18, 0.10, 0.16)
			jaw.mesh = jaw_box
			jaw.material_override = body_mat
			jaw.position = Vector3(0.0, 0.09, -0.04)
			root.add_child(jaw)

			for side in [-1.0, 1.0]:
				var eye := MeshInstance3D.new()
				var eye_sph := SphereMesh.new()
				eye_sph.radius = 0.036
				eye_sph.height = 0.072
				eye_sph.radial_segments = 8
				eye_sph.rings = 4
				eye.mesh = eye_sph
				eye.material_override = accent_mat
				eye.position = Vector3(side * 0.055, 0.22, -0.13)
				root.add_child(eye)

		&"chalice":
			var foot := MeshInstance3D.new()
			var foot_cyl := CylinderMesh.new()
			foot_cyl.top_radius = 0.04
			foot_cyl.bottom_radius = 0.11
			foot_cyl.height = 0.08
			foot_cyl.radial_segments = 10
			foot.mesh = foot_cyl
			foot.material_override = body_mat
			foot.position = Vector3(0.0, 0.04, 0.0)
			root.add_child(foot)

			var stem := MeshInstance3D.new()
			var stem_cyl := CylinderMesh.new()
			stem_cyl.top_radius = 0.035
			stem_cyl.bottom_radius = 0.035
			stem_cyl.height = 0.14
			stem_cyl.radial_segments = 8
			stem.mesh = stem_cyl
			stem.material_override = accent_mat
			stem.position = Vector3(0.0, 0.14, 0.0)
			root.add_child(stem)

			var cup := MeshInstance3D.new()
			var cup_cyl := CylinderMesh.new()
			cup_cyl.top_radius = 0.13
			cup_cyl.bottom_radius = 0.05
			cup_cyl.height = 0.16
			cup_cyl.radial_segments = 10
			cup.mesh = cup_cyl
			cup.material_override = body_mat
			cup.position = Vector3(0.0, 0.28, 0.0)
			root.add_child(cup)

		&"crate":
			var crate_body := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.54, 0.54, 0.54)
			crate_body.mesh = box
			crate_body.material_override = body_mat
			crate_body.position = Vector3(0.0, 0.27, 0.0)
			root.add_child(crate_body)

			var seal := MeshInstance3D.new()
			var seal_box := BoxMesh.new()
			seal_box.size = Vector3(0.57, 0.10, 0.57)
			seal.mesh = seal_box
			seal.material_override = accent_mat
			seal.position = Vector3(0.0, 0.27, 0.0)
			root.add_child(seal)

		_:
			# Stylized chunky pirate chest / coffer with domed lid, bands, and clasp.
			var base_mesh := MeshInstance3D.new()
			var base_box := BoxMesh.new()
			base_box.size = Vector3(0.66, 0.30, 0.44)
			base_mesh.mesh = base_box
			base_mesh.material_override = body_mat
			base_mesh.position = Vector3(0.0, 0.15, 0.0)
			root.add_child(base_mesh)

			var lid_mesh := MeshInstance3D.new()
			var lid_cyl := CylinderMesh.new()
			lid_cyl.top_radius = 0.22
			lid_cyl.bottom_radius = 0.22
			lid_cyl.height = 0.66
			lid_cyl.radial_segments = 10
			lid_mesh.mesh = lid_cyl
			lid_mesh.material_override = body_mat
			lid_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
			lid_mesh.position = Vector3(0.0, 0.30, 0.0)
			root.add_child(lid_mesh)

			for x_off in [-0.22, 0.22]:
				var band := MeshInstance3D.new()
				var band_box := BoxMesh.new()
				band_box.size = Vector3(0.07, 0.34, 0.47)
				band.mesh = band_box
				band.material_override = accent_mat
				band.position = Vector3(x_off, 0.18, 0.0)
				root.add_child(band)

			var clasp := MeshInstance3D.new()
			var clasp_box := BoxMesh.new()
			clasp_box.size = Vector3(0.10, 0.12, 0.06)
			clasp.mesh = clasp_box
			clasp.material_override = accent_mat
			clasp.position = Vector3(0.0, 0.28, -0.23)
			root.add_child(clasp)

	return root


static func _make_mat(col: Color, roughness: float, metallic: float,
		emissive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	mat.metallic = metallic
	if emissive:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.4
	return mat
