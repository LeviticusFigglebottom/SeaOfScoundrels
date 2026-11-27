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

const SALE_HALO_POS := Vector3(0.0, 1.48, 0.0)
const SALE_HALO_VISIBILITY_RANGE := 110.0
const SALE_FLASH_DURATION := 0.90
const SALE_FLASH_PEAK_ENERGY := 1.45
const SALE_FLASH_START_SCALE := 0.75
const SALE_FLASH_END_SCALE := 1.85
const COL_SALE_HALO_CORE := Color(1.00, 0.96, 0.60, 1.0)
const COL_SALE_HALO_MID := Color(0.98, 0.62, 0.14, 1.0)
const COL_SALE_HALO_RIM := Color(0.00, 0.00, 0.00, 1.0)

static var _active_stalls: int = 0
static var _doubloon_mesh: ArrayMesh = null
static var _doubloon_mat: StandardMaterial3D = null
static var _sale_halo_mesh: ArrayMesh = null

@export var merchant_name: String = "Port Factor"
@export var outpost_id: StringName = &""

var interactable: Interactable = null
var _coin_burst: CPUParticles3D = null
var _sale_halo_mi: MeshInstance3D = null
var _sale_halo_mat: StandardMaterial3D = null
var _sale_halo_energy: float = 0.0
var _sale_flash_elapsed: float = -1.0


## Resolve the owning Outpost ID (explicit export, ancestor Outpost/Island, or merchant_name fallback).
func get_outpost_id() -> StringName:
	if outpost_id != &"":
		return outpost_id
	var cur: Node = get_parent()
	while cur != null:
		if cur is Outpost or cur is Island:
			var iid: Variant = cur.get(&"island_id")
			if iid != null and String(iid) != "":
				return StringName(String(iid))
		if cur.has_meta(&"island_id"):
			var mid := String(cur.get_meta(&"island_id"))
			if mid != "":
				return StringName(mid)
		cur = cur.get_parent()
	var lower_nm := merchant_name.to_lower()
	if lower_nm.contains("galleon"):
		return &"galleons_reach"
	if lower_nm.contains("barnacle"):
		return &"barnacle_haven"
	return &"port_scoundrel"


## Release statically cached sculpted doubloon & sale-halo assets cleanly.
static func clear_shared_cache() -> void:
	_doubloon_mesh = null
	_doubloon_mat = null
	_sale_halo_mesh = null


func _enter_tree() -> void:
	_active_stalls += 1


func _exit_tree() -> void:
	_release_local_refs()
	_active_stalls = maxi(0, _active_stalls - 1)
	if _active_stalls == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_local_refs()


func _release_local_refs() -> void:
	if _coin_burst != null and is_instance_valid(_coin_burst):
		_coin_burst.emitting = false
		_coin_burst.visible = false
		_coin_burst.material_override = null
	if _sale_halo_mi != null and is_instance_valid(_sale_halo_mi):
		_sale_halo_mi.visible = false
		_sale_halo_mi.material_override = null
		_sale_halo_mi.set_mesh(null)
	_coin_burst = null
	_sale_halo_mi = null
	_sale_halo_mat = null
	_sale_halo_energy = 0.0
	_sale_flash_elapsed = -1.0


func _ready() -> void:
	_build_interactable()
	_build_coin_burst()
	_build_sale_halo()


func _process(delta: float) -> void:
	if _sale_flash_elapsed < 0.0:
		return
	step_vfx(delta)


## Return the celebratory additive SaleGoldHalo MeshInstance3D mounted above the stall counter.
func get_sale_halo_node() -> MeshInstance3D:
	return _sale_halo_mi


## Return current SaleGoldHalo additive energy (0.0 when idle or after sale flash decays).
func get_sale_halo_energy() -> float:
	return _sale_halo_energy


## Trigger the celebratory doubloon-gold SaleGoldHalo flash above the merchant counter.
func trigger_sale_flash() -> void:
	if _sale_halo_mi == null:
		_build_sale_halo()
	_sale_flash_elapsed = 0.0
	step_vfx(0.0)


## Deterministically advance the celebratory SaleGoldHalo flash & scale bloom.
func step_vfx(delta: float) -> void:
	if _sale_halo_mi == null or not is_instance_valid(_sale_halo_mi):
		_sale_halo_energy = 0.0
		_sale_flash_elapsed = -1.0
		return
	if _sale_flash_elapsed < 0.0:
		_sale_halo_energy = 0.0
		_sale_halo_mi.visible = false
		if _sale_halo_mat != null:
			_sale_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		return

	_sale_flash_elapsed += maxf(delta, 0.0)
	var u := clampf(_sale_flash_elapsed / SALE_FLASH_DURATION, 0.0, 1.0)
	if u >= 1.0:
		_sale_flash_elapsed = -1.0
		_sale_halo_energy = 0.0
		_sale_halo_mi.visible = false
		if _sale_halo_mat != null:
			_sale_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		return

	var decay := pow(1.0 - u, 1.75)
	_sale_halo_energy = SALE_FLASH_PEAK_ENERGY * decay
	var expand_t := 1.0 - pow(1.0 - u, 2.0)
	var halo_scale := lerpf(SALE_FLASH_START_SCALE, SALE_FLASH_END_SCALE, expand_t)
	_sale_halo_mi.visible = true
	_sale_halo_mi.scale = Vector3.ONE * halo_scale
	if _sale_halo_mat != null:
		_sale_halo_mat.albedo_color = Color(
			_sale_halo_energy,
			0.94 * _sale_halo_energy,
			0.74 * _sale_halo_energy,
			1.0
		)


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


func _build_sale_halo() -> void:
	if _sale_halo_mi != null:
		return
	_ensure_doubloon_assets()

	_sale_halo_mat = StandardMaterial3D.new()
	_sale_halo_mat.vertex_color_use_as_albedo = true
	_sale_halo_mat.vertex_color_is_srgb = true
	_sale_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sale_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sale_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_sale_halo_mat.billboard_keep_scale = true
	_sale_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_sale_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sale_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)

	_sale_halo_mi = MeshInstance3D.new()
	_sale_halo_mi.name = "SaleGoldHalo"
	_sale_halo_mi.position = SALE_HALO_POS
	_sale_halo_mi.scale = Vector3.ONE * SALE_FLASH_START_SCALE
	_sale_halo_mi.mesh = _sale_halo_mesh
	_sale_halo_mi.material_override = _sale_halo_mat
	_sale_halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sale_halo_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_sale_halo_mi.visibility_range_end = SALE_HALO_VISIBILITY_RANGE
	_sale_halo_mi.extra_cull_margin = 1.5
	_sale_halo_mi.visible = false
	_sale_halo_energy = 0.0
	add_child(_sale_halo_mi)


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
	if _sale_halo_mesh == null:
		_sale_halo_mesh = _build_sale_halo_mesh()


static func _build_sale_halo_mesh() -> ArrayMesh:
	# Exact 48-tri 16-wedge radial-gradient doubloon-gold billboard disc (diameter 1.0 m)
	# grading incandescent doubloon-gold core -> warm amber mid -> pure Color(0, 0, 0, 1) rim,
	# with finite unit (0, 0, 1) normals for zero hard edge under additive blending.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const INNER_R := 0.22
	const OUTER_R := 0.50
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	var ctr := Vector3.ZERO
	for i in WEDGES:
		var a0 := TAU * float(i) / float(WEDGES)
		var a1 := TAU * float(i + 1) / float(WEDGES)
		var m0 := Vector3(cos(a0) * INNER_R, sin(a0) * INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * INNER_R, sin(a1) * INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)
		# Inner doubloon-gold core wedge (16 tris).
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_CORE)
		st.add_vertex(ctr)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_MID)
		st.add_vertex(m0)
		# Outer warm-amber skirt fading cleanly to pure black (32 tris).
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_SALE_HALO_RIM)
		st.add_vertex(o0)
	return st.commit()


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
## Applies 3-Outpost `TradeRoutes` arbitrage pricing for merchant commodity crates
## (stacking cleanly with active Emissary Grade multipliers via VoyageManager).
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

	var tid := StringName(String(info.get("treasure_id", &"")))
	var is_trade_commodity := TradeRoutes.is_commodity(tid)
	var stall_outpost := get_outpost_id()
	var demand_label := ""
	var trade_profit := 0
	if is_trade_commodity:
		var sell_price := TradeRoutes.get_sell_price(tid, stall_outpost)
		var demand_mult := TradeRoutes.get_demand_multiplier(tid, stall_outpost)
		demand_label = TradeRoutes.get_demand_label(tid, stall_outpost)
		info["gold_value"] = sell_price
		info["base_gold_value"] = sell_price
		if demand_mult >= 1.80:
			var base_ren := int(info.get("renown_value", 20))
			info["renown_value"] = maxi(base_ren, roundi(float(base_ren) * 1.5))
		var origin_id := StringName(String(item.get_meta(&"origin_outpost_id", stall_outpost)))
		var paid := int(item.get_meta(&"purchase_price", TradeRoutes.get_buy_price(tid, origin_id)))
		trade_profit = sell_price - paid

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
		_coin_burst.visible = true
		_coin_burst.restart()
		_coin_burst.emitting = true
	trigger_sale_flash()
	if is_trade_commodity:
		var port_name := TradeRoutes.get_outpost_name(stall_outpost)
		if trade_profit > 0:
			Game.post_notice("Trade Sale! %s at %s (%s) for %d gold (+%dg profit, +%d renown)!" % [
				sold_name, port_name, demand_label, gold, trade_profit, renown])
		else:
			Game.post_notice("Trade Sale: %s at %s (%s) for %d gold (+%d renown)." % [
				sold_name, port_name, demand_label, gold, renown])
	else:
		Game.post_notice("Sold %s for %d gold (+%d renown)" % [sold_name, gold, renown])
	if bool(receipt.get("ranked_up", false)):
		var promo := String(receipt.get("rank_up_notice", ""))
		if promo != "":
			Game.post_notice(promo)

	treasure_sold.emit(item, gold, renown)
	item.queue_free()
	return true
