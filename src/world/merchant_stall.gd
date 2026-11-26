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

@export var merchant_name: String = "Port Factor"

var interactable: Interactable = null
var _coin_burst: CPUParticles3D = null


func _ready() -> void:
	_build_interactable()
	_build_coin_burst()


func _build_coin_burst() -> void:
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
	var coin := CylinderMesh.new()
	coin.top_radius = 0.65
	coin.bottom_radius = 0.65
	coin.height = 0.16
	coin.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.80, 0.22)
	mat.metallic = 0.85
	mat.roughness = 0.22
	mat.emission_enabled = true
	mat.emission = Color(0.98, 0.78, 0.18)
	mat.emission_energy_multiplier = 0.45
	coin.material = mat
	p.mesh = coin
	add_child(p)
	_coin_burst = p


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
