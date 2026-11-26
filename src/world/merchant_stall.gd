class_name MerchantStall
extends Node3D
## Outpost merchant buyer stall.
##
## Implements the container contract (`accept_carryable(item) -> bool`) so any
## `Pawn` carrying treasure can hand it straight over by interacting with the
## stall's `Interactable` (via `Carryable.hand_to()`). Sales flow through
## `Economy.sell_treasure(Game.profile, info)` with a 250g / 40 renown fallback
## for plain untagged `Carryable` objects.

signal treasure_sold(item: Node, gold: int, renown: int)

const FALLBACK_GOLD := 250
const FALLBACK_RENOWN := 40
const FALLBACK_COMPANY := &"gilded_compass"

static var _active_stalls: int = 0
static var _doubloon_mesh: ArrayMesh = null
static var _doubloon_mat: StandardMaterial3D = null

@export var merchant_name: String = "Port Factor"

var interactable: Interactable = null
var _coin_burst: CPUParticles3D = null


## Release statically cached sculpted doubloon mesh & material cleanly.
static func clear_shared_cache() -> void:
	_doubloon_mesh = null
	_doubloon_mat = null


func _enter_tree() -> void:
	_active_stalls += 1


func _exit_tree() -> void:
	if _coin_burst != null and is_instance_valid(_coin_burst):
		_coin_burst.emitting = false
		_coin_burst.mesh = null
		_coin_burst.material_override = null
	_coin_burst = null
	_active_stalls = maxi(0, _active_stalls - 1)
	if _active_stalls == 0:
		clear_shared_cache()


func _ready() -> void:
	_build_interactable()
	_build_coin_burst()


func _build_coin_burst() -> void:
	_ensure_doubloon_assets()
	var p := CPUParticles3D.new()
	p.name = "GoldCoinBurst"
	p.emitting = false
	p.one_shot = true
	p.amount = 20
	p.lifetime = 0.85
	p.explosiveness = 0.88
	p.position = Vector3(0.0, 1.35, -0.85)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 48.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0.0, -9.2, 0.0)
	p.scale_amount_min = 0.055
	p.scale_amount_max = 0.095
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = _doubloon_mesh
	p.material_override = _doubloon_mat
	add_child(p)
	_coin_burst = p


static func _ensure_doubloon_assets() -> void:
	if _doubloon_mat == null:
		_doubloon_mat = StandardMaterial3D.new()
		_doubloon_mat.albedo_color = Color.WHITE
		_doubloon_mat.vertex_color_use_as_albedo = true
		_doubloon_mat.vertex_color_is_srgb = true
		_doubloon_mat.metallic = 0.88
		_doubloon_mat.roughness = 0.20
		_doubloon_mat.emission_enabled = true
		_doubloon_mat.emission = Color(0.98, 0.78, 0.18)
		_doubloon_mat.emission_energy_multiplier = 0.45

	if _doubloon_mesh == null:
		_doubloon_mesh = _build_octagonal_doubloon_mesh()


static func _build_octagonal_doubloon_mesh() -> ArrayMesh:
	## Sculpted flat-faceted Octagonal Embossed Spanish Doubloon: chamfered 8-sided
	## rim, recessed coin field, and raised stamped center crown boss on both faces.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_boss := Color(1.00, 0.90, 0.36)
	var col_rim := Color(0.98, 0.80, 0.22)
	var col_edge := Color(0.84, 0.64, 0.16)
	var col_field := Color(0.76, 0.56, 0.12)

	# Profile stations (y, radius, color) from bottom crown boss -> edge -> top crown boss.
	var stations: Array[Array] = [
		[-0.112, 0.000, col_boss],
		[-0.112, 0.250, col_boss],
		[-0.080, 0.310, col_field],
		[-0.072, 0.460, col_field],
		[-0.084, 0.540, col_rim],
		[-0.056, 0.620, col_edge],
		[0.056, 0.620, col_edge],
		[0.084, 0.540, col_rim],
		[0.072, 0.460, col_field],
		[0.080, 0.310, col_field],
		[0.112, 0.250, col_boss],
		[0.112, 0.000, col_boss],
	]
	var segs := 8
	for j in range(stations.size() - 1):
		var y0: float = float(stations[j][0])
		var r0: float = float(stations[j][1])
		var c0: Color = stations[j][2] as Color
		var y1: float = float(stations[j + 1][0])
		var r1: float = float(stations[j + 1][1])
		var c1: Color = stations[j + 1][2] as Color
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 > 1e-5 and r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)
			elif r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
			elif r0 > 1e-5:
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)

	st.generate_normals()
	return st.commit()


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


func _build_interactable() -> void:
	if interactable != null:
		return
	interactable = Interactable.create("Sell treasure", 1.45)
	interactable.name = "MerchantInteractable"
	interactable.position = Vector3(0.0, 1.15, -1.15)
	interactable.reach = 3.2
	interactable.target = self
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)


func _on_interacted(pawn: Node) -> void:
	if not Net.is_host():
		return
	# If the pawn somehow triggered interact directly while carrying, complete the handoff.
	var carried: Variant = pawn.get(&"carried") if pawn != null else null
	if carried is Node and (carried as Node).has_method("hand_to"):
		if (carried as Node).call("hand_to", self):
			return
	Audio.play_sfx(&"ui_tick", global_position)
	Game.post_notice("%s: Bring me treasure chests or cargo to sell for gold!" % merchant_name)


## Accept and sell a carried treasure item (host-authoritative).
## Queues the sold item for removal so `Carryable.hand_to()` finishes cleanly.
func accept_carryable(item: Node) -> bool:
	if not Net.is_host() or item == null or not is_instance_valid(item):
		return false
	if item.has_meta(&"_merchant_sold"):
		return false
	item.set_meta(&"_merchant_sold", true)

	var info := TreasureCatalog.inspect_carryable(item)
	if info.is_empty():
		var fallback_name: Variant = item.get(&"item_name")
		var label := String(fallback_name) if fallback_name != null and String(fallback_name) != "" else "Cargo"
		info = {
			"treasure_id": &"plain_cargo",
			"name": label,
			"base_gold_value": FALLBACK_GOLD,
			"gold_value": FALLBACK_GOLD,
			"renown_value": FALLBACK_RENOWN,
			"company_id": FALLBACK_COMPANY,
			"fragile": false,
		}

	var receipt := Economy.sell_treasure(Game.profile, info)
	if not bool(receipt.get("ok", false)):
		item.remove_meta(&"_merchant_sold")
		return false

	var gold: int = int(receipt.get("gold_awarded", 0))
	var renown: int = int(receipt.get("renown_awarded", 0))
	var sold_name := String(receipt.get("name", "Treasure"))

	Game.save()
	Audio.play_sfx(&"coin_jingle", global_position)
	if _coin_burst != null:
		_coin_burst.restart()
		_coin_burst.emitting = true
	Game.post_notice("Sold %s for %d gold (+%d renown)" % [sold_name, gold, renown])
	if bool(receipt.get("ranked_up", false)):
		var promo := String(receipt.get("rank_up_notice", ""))
		if promo != "":
			Game.post_notice(promo)

	treasure_sold.emit(item, gold, renown)
	item.queue_free()
	return true
