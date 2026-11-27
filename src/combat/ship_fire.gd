class_name ShipFire
extends Node3D
## Sculpted multi-tongue spreading deck fire system for ships.
##
## Features 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` flame clusters
## (zero `PrimitiveMesh`es, zero extra VRAM, ref-counted leak-free static cache),
## 6 deck/hold fire zones per hull (`SLOOP_ZONES` / `BRIG_ZONES`), host-authoritative
## fire spreading, pawn scorching, unchecked hull charring, storm rain extinguishing,
## water-bucket dousing, and a single shared flickering unshadowed `OmniLight3D`
## dynamically positioned at the active flame centroid (hidden when no fires burn).

signal fire_ignited(zone_idx: int)
signal fire_doused(doused_count: int)
signal all_fires_out()

const ZONE_COUNT := 6

## 6 ship-local unscaled deck/hold fire zones for Sloop (foredeck, port/stbd mid, helm qdeck, fwd hold, aft cabin).
const SLOOP_ZONES: Array[Vector3] = [
	Vector3(0.0, 1.12, -3.2),
	Vector3(-1.1, 1.12, -0.4),
	Vector3(1.1, 1.12, -0.4),
	Vector3(0.0, 2.02, 4.4),
	Vector3(0.0, -0.82, -0.5),
	Vector3(0.0, -0.82, 2.4),
]

## 6 ship-local unscaled deck/hold fire zones for Brigantine.
const BRIG_ZONES: Array[Vector3] = [
	Vector3(0.0, 1.27, -5.2),
	Vector3(-1.4, 1.27, -1.6),
	Vector3(1.4, 1.27, -1.6),
	Vector3(0.0, 2.27, 5.4),
	Vector3(0.0, -0.92, -1.0),
	Vector3(0.0, -0.92, 3.0),
]

## Adjacency graph between the 6 zones for organic fire spreading across decks.
const ZONE_ADJACENCY: Array[Array] = [
	[1, 2, 4],
	[0, 2, 3, 4],
	[0, 1, 3, 4],
	[1, 2, 5],
	[0, 1, 2, 5],
	[3, 4, 1, 2],
]

const STORM_EXTINGUISH_THRESHOLD := 0.55
const STORM_DECAY_RATE := 0.26
const SPREAD_INTERVAL := 11.0
const SPREAD_MIN_INTENSITY := 0.75
const SCORCH_INTERVAL := 0.5
const SCORCH_RADIUS := 1.85
const SCORCH_DAMAGE := 3.0
const KEG_IGNITE_RADIUS := 2.4
const KEG_IGNITE_MIN_INTENSITY := 0.25
const HULL_CHAR_INTERVAL := 18.0
const HULL_CHAR_RADIUS := 0.35
const NEIGHBOR_COOL_AMOUNT := 0.35
const FIRE_LIGHT_RANGE := 10.5
const EMBER_COUNT := 30
const SMOKE_COUNT := 20
const EMBER_Y_MIN := 0.30
const EMBER_Y_MAX := 4.20
const SMOKE_Y_MIN := 0.80
const SMOKE_Y_MAX := 6.20
const EMBER_VISIBILITY_RANGE := 180.0
const SMOKE_VISIBILITY_RANGE := 260.0
const HALO_VISIBILITY_RANGE := 260.0

# sRGB-calibrated fiery painterly palette (charcoal embers -> crimson -> fiery orange -> incandescent white-gold).
const COL_COAL_DARK := Color(0.11, 0.08, 0.07)
const COL_COAL_GLOW := Color(0.86, 0.20, 0.04)
const COL_HEARTH_ASH := Color(0.18, 0.13, 0.11)
const COL_FLAME_CRIMSON := Color(0.88, 0.18, 0.04)
const COL_FLAME_ORANGE := Color(1.0, 0.48, 0.07)
const COL_FLAME_AMBER := Color(1.0, 0.72, 0.16)
const COL_FLAME_GOLD := Color(1.0, 0.88, 0.38)
const COL_FLAME_CORE := Color(1.0, 0.98, 0.82)
const COL_SMOKE_BASE := Color(0.24, 0.14, 0.10)
const COL_SMOKE_SOOT := Color(0.11, 0.10, 0.12)
const COL_SMOKE_ASH := Color(0.20, 0.20, 0.22)
const COL_HALO_CENTER := Color(1.0, 0.72, 0.24, 1.0)
const COL_HALO_MID := Color(0.60, 0.26, 0.05, 1.0)
const COL_HALO_RIM := Color(0.0, 0.0, 0.0, 1.0)

## Visual scale matched to the owning ship's hull_scale.
@export var visual_scale: float = 1.0

## Owning ship (`Ship` / `RigidBody3D`).
var ship: Node3D = null

var _zone_local_positions: Array[Vector3] = []
var _zone_intensity: Array[float] = []
var _zone_nodes: Array[MeshInstance3D] = []
var _fire_light: OmniLight3D = null
var _ember_mmi: MultiMeshInstance3D = null
var _smoke_mmi: MultiMeshInstance3D = null
var _fire_halo: MeshInstance3D = null
var _halo_mat: StandardMaterial3D = null
var _fire_halo_energy: float = 0.0
var _vfx_active_last_sync: bool = false

# Pre-allocated fixed-size per-particle arrays (zero steady-state allocations in _process/tick_fire_vfx).
var _active_zone_buf: PackedInt32Array = PackedInt32Array()
var _ember_age: PackedFloat32Array = PackedFloat32Array()
var _ember_speed: PackedFloat32Array = PackedFloat32Array()
var _ember_phase: PackedFloat32Array = PackedFloat32Array()
var _ember_swirl_r: PackedFloat32Array = PackedFloat32Array()
var _ember_swirl_freq: PackedFloat32Array = PackedFloat32Array()
var _ember_scale: PackedFloat32Array = PackedFloat32Array()
var _ember_pos: PackedVector3Array = PackedVector3Array()

var _smoke_age: PackedFloat32Array = PackedFloat32Array()
var _smoke_speed: PackedFloat32Array = PackedFloat32Array()
var _smoke_phase: PackedFloat32Array = PackedFloat32Array()
var _smoke_swirl_r: PackedFloat32Array = PackedFloat32Array()
var _smoke_scale: PackedFloat32Array = PackedFloat32Array()
var _smoke_pos: PackedVector3Array = PackedVector3Array()
var _smoke_live_scale: PackedFloat32Array = PackedFloat32Array()

var _spread_accum: float = 0.0
var _scorch_accum: float = 0.0
var _char_timer: float = 0.0
var _anim_clock: float = 0.0

# Ref-counted static sculpted flame, ember, smoke & halo caches (0 extra VRAM, 0 leaks).
static var _active_instances: int = 0
static var _flame_mesh: ArrayMesh = null
static var _flame_mat: StandardMaterial3D = null
static var _ember_mesh: ArrayMesh = null
static var _ember_mat: StandardMaterial3D = null
static var _smoke_mesh: ArrayMesh = null
static var _smoke_mat: StandardMaterial3D = null
static var _halo_mesh: ArrayMesh = null


## Release all statically cached sculpted fire geometry & materials cleanly.
static func clear_shared_cache() -> void:
	_flame_mesh = null
	_flame_mat = null
	_ember_mesh = null
	_ember_mat = null
	_smoke_mesh = null
	_smoke_mat = null
	_halo_mesh = null


func _enter_tree() -> void:
	_active_instances += 1


func _ready() -> void:
	if ship == null and get_parent() is Node3D:
		ship = get_parent() as Node3D
	if ship != null:
		var hs: Variant = ship.get(&"hull_scale")
		if hs != null and float(hs) > 0.01 and is_equal_approx(visual_scale, 1.0):
			visual_scale = float(hs)
	_ensure_shared_assets()
	_build_zones()
	_sync_visuals(0.0)


func _exit_tree() -> void:
	for mi: MeshInstance3D in _zone_nodes:
		if mi != null and is_instance_valid(mi):
			mi.material_override = null
			mi.mesh = null
	_zone_nodes.clear()
	_zone_local_positions.clear()
	_zone_intensity.clear()
	if _ember_mmi != null and is_instance_valid(_ember_mmi):
		_ember_mmi.visible = false
		_ember_mmi.material_override = null
		_ember_mmi.multimesh = null
	_ember_mmi = null
	if _smoke_mmi != null and is_instance_valid(_smoke_mmi):
		_smoke_mmi.visible = false
		_smoke_mmi.material_override = null
		_smoke_mmi.multimesh = null
	_smoke_mmi = null
	if _fire_halo != null and is_instance_valid(_fire_halo):
		_fire_halo.material_override = null
		_fire_halo.mesh = null
		_fire_halo.visible = false
	_fire_halo = null
	_halo_mat = null
	_fire_halo_energy = 0.0
	_vfx_active_last_sync = false
	if _fire_light != null and is_instance_valid(_fire_light):
		_fire_light.light_energy = 0.0
		_fire_light.visible = false
	_fire_light = null
	ship = null
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


func _physics_process(delta: float) -> void:
	step_fire(delta)


func _process(delta: float) -> void:
	if has_active_fire():
		tick_fire_vfx(delta)


# ==============================================================================
# Public Host-Authoritative Fire Lifecycle API
# ==============================================================================

## Host only. Ignite the fire zone nearest to `world_pos`. Returns zone index (0..5) or -1.
func ignite_at_world(world_pos: Vector3, intensity: float = 1.0) -> int:
	if not Net.is_host() or _zone_local_positions.is_empty():
		return -1
	var best_idx := 0
	var best_d2 := INF
	for i in _zone_local_positions.size():
		var d2 := world_pos.distance_squared_to(get_zone_world_pos(i))
		if d2 < best_d2:
			best_d2 = d2
			best_idx = i
	if ignite_zone(best_idx, intensity):
		return best_idx
	return -1


## Host only. Ignite a specific zone index (0..5). Returns true on success.
func ignite_zone(zone_idx: int, intensity: float = 1.0) -> bool:
	if not Net.is_host():
		return false
	if zone_idx < 0 or zone_idx >= _zone_intensity.size():
		return false
	var eff := clampf(intensity, 0.1, 1.0)
	_zone_intensity[zone_idx] = maxf(_zone_intensity[zone_idx], eff)
	_sync_visuals()
	Audio.play_sfx(&"hull_impact", get_zone_world_pos(zone_idx), -3.0)
	fire_ignited.emit(zone_idx)
	return true


## Host only. Ignite one adjacent unlit zone neighboring `zone_idx` (used by direct firebomb blasts).
func ignite_adjacent_to(zone_idx: int, intensity: float = 0.85) -> int:
	if not Net.is_host() or zone_idx < 0 or zone_idx >= ZONE_ADJACENCY.size():
		return -1
	var neighbors: Array = ZONE_ADJACENCY[zone_idx]
	for nb_v: Variant in neighbors:
		var nb := int(nb_v)
		if nb >= 0 and nb < _zone_intensity.size() and _zone_intensity[nb] <= 0.01:
			if ignite_zone(nb, intensity):
				return nb
	return -1


## Host only. Snuff all active zones within `radius` of `world_pos` and cool neighboring zones by -0.35.
## Returns the number of zones extinguished.
func douse_at_world(world_pos: Vector3, radius: float = 4.5) -> int:
	if not Net.is_host() or _zone_intensity.is_empty():
		return 0
	var had_fire := has_active_fire()
	var snuffed_zones: Array[int] = []
	var doused := 0
	var cooled_any := false

	for i in _zone_intensity.size():
		if _zone_intensity[i] <= 0.01:
			continue
		var d := world_pos.distance_to(get_zone_world_pos(i))
		if d <= radius:
			_zone_intensity[i] = 0.0
			snuffed_zones.append(i)
			doused += 1

	# Cool neighboring zones adjacent to snuffed flames (or near splash fringe) by -0.35.
	var cool_candidates: Dictionary = {}
	for s_idx in snuffed_zones:
		if s_idx >= 0 and s_idx < ZONE_ADJACENCY.size():
			for nb_v: Variant in ZONE_ADJACENCY[s_idx]:
				cool_candidates[int(nb_v)] = true
	for i in _zone_intensity.size():
		if _zone_intensity[i] <= 0.01:
			continue
		var in_fringe := world_pos.distance_to(get_zone_world_pos(i)) <= radius * 1.6
		if cool_candidates.has(i) or in_fringe:
			_zone_intensity[i] = maxf(0.0, _zone_intensity[i] - NEIGHBOR_COOL_AMOUNT)
			cooled_any = true
			if _zone_intensity[i] <= 0.01:
				_zone_intensity[i] = 0.0
				doused += 1

	if doused > 0 or cooled_any:
		_sync_visuals()
		Audio.play_sfx(&"splash_small", world_pos, -1.5)
	if doused > 0:
		fire_doused.emit(doused)
	if had_fire and not has_active_fire():
		_on_all_fires_extinguished()
	return doused


## Host only. Immediately extinguish every active deck fire zone. Returns count extinguished.
func douse_all() -> int:
	if not Net.is_host() or _zone_intensity.is_empty():
		return 0
	var doused := 0
	for i in _zone_intensity.size():
		if _zone_intensity[i] > 0.01:
			_zone_intensity[i] = 0.0
			doused += 1
	_spread_accum = 0.0
	_char_timer = 0.0
	_scorch_accum = 0.0
	_sync_visuals()
	if doused > 0:
		Audio.play_sfx(&"splash_small", global_position, -1.5)
		fire_doused.emit(doused)
		_on_all_fires_extinguished()
	return doused


## Host-authoritative fire simulation tick (called from `_physics_process` and directly testable).
func step_fire(delta: float) -> void:
	if not Net.is_host() or delta <= 0.0 or _zone_intensity.is_empty():
		return
	if not has_active_fire():
		_spread_accum = 0.0
		_char_timer = 0.0
		_scorch_accum = 0.0
		return

	# A sinking hull plunging beneath the waves immediately snuffs all deck flames.
	if ship != null and is_instance_valid(ship) and bool(ship.get(&"is_sinking")):
		douse_all()
		return

	var storm := Weather.storminess if Weather != null else 0.0

	# 1. Storm Rain Extinguishing: heavy rain (> 0.55) decays active flames naturally at -0.26/s.
	if storm > STORM_EXTINGUISH_THRESHOLD:
		_spread_accum = 0.0
		var storm_snuffed := 0
		for i in _zone_intensity.size():
			if _zone_intensity[i] <= 0.01:
				continue
			_zone_intensity[i] = maxf(0.0, _zone_intensity[i] - STORM_DECAY_RATE * delta)
			if _zone_intensity[i] <= 0.01:
				_zone_intensity[i] = 0.0
				storm_snuffed += 1
		_sync_visuals()
		if storm_snuffed > 0:
			fire_doused.emit(storm_snuffed)
		if not has_active_fire():
			_on_all_fires_extinguished()
			return
	else:
		# 2. Dry-weather flame growth & spreading across adjacent zones every 11.0 s.
		var has_hot_zone := false
		for i in _zone_intensity.size():
			if _zone_intensity[i] > 0.01:
				if _zone_intensity[i] < 1.0:
					_zone_intensity[i] = minf(1.0, _zone_intensity[i] + 0.05 * delta)
				if _zone_intensity[i] >= SPREAD_MIN_INTENSITY:
					has_hot_zone = true
		if has_hot_zone:
			_spread_accum += delta
			while _spread_accum >= SPREAD_INTERVAL:
				_spread_accum -= SPREAD_INTERVAL
				if not _try_spread_fire():
					break

	# 3. Pawn Scorching & Powder Keg Ignition: every 0.5 s scorch living pawns within 1.85 m
	#    and detonate any unexploded PowderKegs within 2.4 m of an active burning zone (>= 0.25).
	_scorch_accum += delta
	while _scorch_accum >= SCORCH_INTERVAL:
		_scorch_accum -= SCORCH_INTERVAL
		_scorch_nearby_pawns()
		_check_nearby_powder_kegs()

	# 4. Hull Charring: unchecked deck fire pops 1 hull hole every 18.0 s.
	if storm <= STORM_EXTINGUISH_THRESHOLD and has_active_fire():
		_char_timer += delta
		while _char_timer >= HULL_CHAR_INTERVAL:
			_char_timer -= HULL_CHAR_INTERVAL
			_apply_hull_char_damage()


# ==============================================================================
# Introspection & Net Sync API
# ==============================================================================

## Number of currently burning deck fire zones (0..6).
func get_active_fire_count() -> int:
	var n := 0
	for v: float in _zone_intensity:
		if v > 0.01:
			n += 1
	return n


## True when at least one deck fire zone is actively burning.
func has_active_fire() -> bool:
	for v: float in _zone_intensity:
		if v > 0.01:
			return true
	return false


## Return the current intensity (0.0..1.0) of fire zone `zone_idx`.
func get_zone_intensity(zone_idx: int) -> float:
	if zone_idx < 0 or zone_idx >= _zone_intensity.size():
		return 0.0
	return _zone_intensity[zone_idx]


## Return the ship-local position of fire zone `zone_idx`.
func get_zone_local_pos(zone_idx: int) -> Vector3:
	if zone_idx < 0 or zone_idx >= _zone_local_positions.size():
		return Vector3.ZERO
	return _zone_local_positions[zone_idx]


## Return the world-space position of fire zone `zone_idx`.
func get_zone_world_pos(zone_idx: int) -> Vector3:
	var lp := get_zone_local_pos(zone_idx)
	if is_inside_tree():
		return global_transform * lp
	if ship != null and is_instance_valid(ship):
		return ship.global_transform * lp
	return lp


## Return the world-space position of the active fire zone nearest to `from_pos`, or `Vector3.INF`.
func get_nearest_fire_world_pos(from_pos: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d2 := INF
	for i in _zone_intensity.size():
		if _zone_intensity[i] <= 0.01:
			continue
		var wp := get_zone_world_pos(i)
		var d2 := from_pos.distance_squared_to(wp)
		if d2 < best_d2:
			best_d2 = d2
			best = wp
	return best


## Encode the 6 active fire zones into a compact 6-bit integer bitmask for network replication.
func get_fire_bitmask() -> int:
	var mask := 0
	for i in _zone_intensity.size():
		if _zone_intensity[i] > 0.01:
			mask |= (1 << i)
	return mask


## Restore active deck fire zones from a host-replicated 6-bit integer bitmask.
func apply_fire_bitmask(mask: int) -> void:
	for i in _zone_intensity.size():
		var lit := (mask & (1 << i)) != 0
		if lit:
			_zone_intensity[i] = maxf(_zone_intensity[i], 1.0)
		else:
			_zone_intensity[i] = 0.0
	if not has_active_fire():
		_spread_accum = 0.0
		_char_timer = 0.0
	_sync_visuals()


## Return the sculpted triangle count of a single multi-tongue flame cluster ArrayMesh.
func get_triangle_count() -> int:
	_ensure_shared_assets()
	if _flame_mesh == null:
		return 0
	var tris := 0
	for si in _flame_mesh.get_surface_count():
		var ilen := _flame_mesh.surface_get_array_index_len(si)
		if ilen > 0:
			tris += floori(float(ilen) / 3.0)
		else:
			tris += floori(float(_flame_mesh.surface_get_array_len(si)) / 3.0)
	return tris


## Return the shared unshadowed flickering OmniLight3D illuminating active deck fires.
func get_fire_light() -> OmniLight3D:
	if _fire_light != null and is_instance_valid(_fire_light):
		return _fire_light
	return null


## Return the batched 30-instance sculpted ember spark MultiMeshInstance3D (`FireEmberSwarm`).
func get_ember_swarm_node() -> MultiMeshInstance3D:
	if _ember_mmi != null and is_instance_valid(_ember_mmi):
		return _ember_mmi
	return null


## Return the batched 20-instance sculpted soot smoke plume MultiMeshInstance3D (`FireSmokePlumes`).
func get_smoke_plumes_node() -> MultiMeshInstance3D:
	if _smoke_mmi != null and is_instance_valid(_smoke_mmi):
		return _smoke_mmi
	return null


## Return the sculpted additive radial-gradient fire bloom billboard (`FireGlowHalo`).
func get_fire_halo_node() -> MeshInstance3D:
	if _fire_halo != null and is_instance_valid(_fire_halo):
		return _fire_halo
	return null


## Return the current atmospheric bloom energy of `FireGlowHalo` (0.0 when no fire burns).
func get_fire_halo_energy() -> float:
	return _fire_halo_energy


## Return the latest ship-local positions of all 30 ember instances (headless-safe mirror of MultiMesh).
func get_ember_positions() -> PackedVector3Array:
	return _ember_pos


## Return the latest ship-local positions of all 20 smoke puff instances (headless-safe mirror of MultiMesh).
func get_smoke_positions() -> PackedVector3Array:
	return _smoke_pos


## Return the latest uniform growth scales of all 20 smoke puff instances (headless-safe mirror of MultiMesh).
func get_smoke_scales() -> PackedFloat32Array:
	return _smoke_live_scale


## Advance flame flicker, swirling wind-driven embers, billowing soot smoke plumes, and fire halo glow.
func tick_fire_vfx(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	_anim_clock += dt
	_sync_visuals(dt)


# ==============================================================================
# Internal Fire Mechanics
# ==============================================================================

func _on_all_fires_extinguished() -> void:
	_spread_accum = 0.0
	_char_timer = 0.0
	_scorch_accum = 0.0
	all_fires_out.emit()
	if ship != null and is_instance_valid(ship) and ship.get(&"faction") == &"player" and Game != null:
		Game.post_notice("Deck fires extinguished!")


func _try_spread_fire() -> bool:
	for i in _zone_intensity.size():
		if _zone_intensity[i] < SPREAD_MIN_INTENSITY:
			continue
		var neighbors: Array = ZONE_ADJACENCY[i]
		for nb_v: Variant in neighbors:
			var nb := int(nb_v)
			if nb >= 0 and nb < _zone_intensity.size() and _zone_intensity[nb] <= 0.01:
				return ignite_zone(nb, 0.90)
	return false


func _apply_hull_char_damage() -> void:
	if ship == null or not is_instance_valid(ship) or not ship.has_method(&"apply_hull_damage"):
		return
	var hottest_idx := -1
	var hottest_val := 0.0
	for i in _zone_intensity.size():
		if _zone_intensity[i] > hottest_val:
			hottest_val = _zone_intensity[i]
			hottest_idx = i
	if hottest_idx >= 0:
		var wp := get_zone_world_pos(hottest_idx)
		ship.call(&"apply_hull_damage", wp, HULL_CHAR_RADIUS)


func _scorch_nearby_pawns() -> void:
	if not is_inside_tree():
		return
	var active_positions: Array[Vector3] = []
	for i in _zone_intensity.size():
		if _zone_intensity[i] > 0.01:
			active_positions.append(get_zone_world_pos(i))
	if active_positions.is_empty():
		return

	var r_sq := SCORCH_RADIUS * SCORCH_RADIUS
	var candidates := _collect_candidate_pawns()
	for p: Node3D in candidates:
		if p == null or not is_instance_valid(p):
			continue
		var is_dead: Variant = p.get(&"dead")
		if is_dead is bool and bool(is_dead):
			continue
		var p_pos := p.global_position
		var hit := false
		for f_pos: Vector3 in active_positions:
			if p_pos.distance_squared_to(f_pos) <= r_sq:
				hit = true
				break
		if hit:
			if p.has_method(&"take_damage"):
				p.call(&"take_damage", SCORCH_DAMAGE)
			elif p.has_method(&"apply_damage"):
				p.call(&"apply_damage", SCORCH_DAMAGE, self)


func _check_nearby_powder_kegs() -> void:
	if not Net.is_host() or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var kegs := tree.get_nodes_in_group(&"powder_kegs")
	if kegs.is_empty():
		return
	var hot_positions: Array[Vector3] = []
	for i in _zone_intensity.size():
		if _zone_intensity[i] >= KEG_IGNITE_MIN_INTENSITY:
			hot_positions.append(get_zone_world_pos(i))
	if hot_positions.is_empty():
		return

	var r_sq := KEG_IGNITE_RADIUS * KEG_IGNITE_RADIUS
	for node in kegs:
		if not is_instance_valid(node) or not (node is PowderKeg):
			continue
		var keg := node as PowderKeg
		if keg.exploded:
			continue
		var kpos := keg.global_position + Vector3(0.0, PowderKeg.KEG_CENTER_Y, 0.0)
		var ignited := false
		for f_pos: Vector3 in hot_positions:
			if kpos.distance_squared_to(f_pos) <= r_sq:
				ignited = true
				break
		if ignited:
			keg.detonate(ship)


func _collect_candidate_pawns() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var seen: Dictionary = {}
	var tree := get_tree()
	if tree != null:
		for grp: StringName in [&"pawn", &"pawns"]:
			for n in tree.get_nodes_in_group(grp):
				if n is Node3D and is_instance_valid(n):
					var iid := n.get_instance_id()
					if not seen.has(iid):
						seen[iid] = true
						out.append(n as Node3D)
		for cb in tree.get_nodes_in_group(&"crew_brains"):
			var p := cb.get_parent() as Node3D
			if p != null and is_instance_valid(p):
				var iid := p.get_instance_id()
				if not seen.has(iid):
					seen[iid] = true
					out.append(p)
		for cc in tree.get_nodes_in_group(&"combatants"):
			var p2 := cc.get_parent() as Node3D
			if p2 != null and is_instance_valid(p2):
				var iid := p2.get_instance_id()
				if not seen.has(iid):
					seen[iid] = true
					out.append(p2)
	if ship != null and is_instance_valid(ship):
		var parent_node := ship.get_parent()
		if parent_node != null:
			for ch in parent_node.get_children():
				if ch is Pawn and is_instance_valid(ch):
					var iid := ch.get_instance_id()
					if not seen.has(iid):
						seen[iid] = true
						out.append(ch as Node3D)
	return out


# ==============================================================================
# Zone Construction & Live Visual Flicker
# ==============================================================================

func _build_zones() -> void:
	_zone_local_positions.clear()
	_zone_intensity.clear()
	_zone_nodes.clear()

	var is_brig := ship != null and ship.has_method(&"is_brigantine") and bool(ship.call(&"is_brigantine"))
	var base_zones: Array[Vector3] = BRIG_ZONES if is_brig else SLOOP_ZONES
	var sc := maxf(visual_scale, 0.5)

	for i in base_zones.size():
		var unscaled := base_zones[i]
		var scaled_pos: Vector3
		if ship != null and ship.has_method(&"ship_point"):
			scaled_pos = ship.call(&"ship_point", unscaled) as Vector3
		else:
			scaled_pos = unscaled * sc
		_zone_local_positions.append(scaled_pos)
		_zone_intensity.append(0.0)

		var mi := MeshInstance3D.new()
		mi.name = "FireZone_%02d" % i
		mi.mesh = _flame_mesh
		mi.material_override = _flame_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = scaled_pos
		mi.scale = Vector3.ONE * sc
		mi.visible = false
		add_child(mi)
		_zone_nodes.append(mi)

	_fire_light = OmniLight3D.new()
	_fire_light.name = "DeckFireLight"
	_fire_light.light_color = Color(1.0, 0.54, 0.16)
	_fire_light.light_energy = 0.0
	_fire_light.omni_range = FIRE_LIGHT_RANGE
	_fire_light.omni_attenuation = 1.35
	_fire_light.shadow_enabled = false
	_fire_light.visible = false
	add_child(_fire_light)

	_build_fire_vfx()


func _build_fire_vfx() -> void:
	_active_zone_buf.resize(ZONE_COUNT)

	_ember_age.resize(EMBER_COUNT)
	_ember_speed.resize(EMBER_COUNT)
	_ember_phase.resize(EMBER_COUNT)
	_ember_swirl_r.resize(EMBER_COUNT)
	_ember_swirl_freq.resize(EMBER_COUNT)
	_ember_scale.resize(EMBER_COUNT)
	_ember_pos.resize(EMBER_COUNT)
	for i in EMBER_COUNT:
		var fi := float(i)
		_ember_speed[i] = lerpf(0.36, 0.56, fposmod(fi * 0.381966, 1.0))
		_ember_phase[i] = fi / float(EMBER_COUNT) * TAU
		_ember_swirl_r[i] = lerpf(0.18, 0.44, fposmod(fi * 0.618034, 1.0))
		_ember_swirl_freq[i] = lerpf(2.8, 5.2, fposmod(fi * 0.271828, 1.0)) * (1.0 if (i % 2 == 0) else -1.0)
		_ember_scale[i] = lerpf(0.72, 1.38, fposmod(fi * 0.754877, 1.0))
		_ember_pos[i] = Vector3.ZERO

	_smoke_age.resize(SMOKE_COUNT)
	_smoke_speed.resize(SMOKE_COUNT)
	_smoke_phase.resize(SMOKE_COUNT)
	_smoke_swirl_r.resize(SMOKE_COUNT)
	_smoke_scale.resize(SMOKE_COUNT)
	_smoke_pos.resize(SMOKE_COUNT)
	_smoke_live_scale.resize(SMOKE_COUNT)
	for i in SMOKE_COUNT:
		var fi := float(i)
		_smoke_speed[i] = lerpf(0.20, 0.30, fposmod(fi * 0.381966, 1.0))
		_smoke_phase[i] = fi / float(SMOKE_COUNT) * TAU
		_smoke_swirl_r[i] = lerpf(0.10, 0.28, fposmod(fi * 0.618034, 1.0))
		_smoke_scale[i] = lerpf(0.84, 1.24, fposmod(fi * 0.754877, 1.0))
		_smoke_pos[i] = Vector3.ZERO
		_smoke_live_scale[i] = 0.0

	_reset_vfx_ages()

	var ember_mm := MultiMesh.new()
	ember_mm.transform_format = MultiMesh.TRANSFORM_3D
	ember_mm.use_colors = true
	ember_mm.use_custom_data = false
	ember_mm.mesh = _ember_mesh
	ember_mm.instance_count = EMBER_COUNT
	for i in EMBER_COUNT:
		ember_mm.set_instance_transform(i, Transform3D.IDENTITY)
		ember_mm.set_instance_color(i, COL_FLAME_GOLD)

	_ember_mmi = MultiMeshInstance3D.new()
	_ember_mmi.name = "FireEmberSwarm"
	_ember_mmi.multimesh = ember_mm
	_ember_mmi.material_override = _ember_mat
	_ember_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ember_mmi.visibility_range_end = EMBER_VISIBILITY_RANGE
	_ember_mmi.extra_cull_margin = 8.0
	_ember_mmi.visible = false
	add_child(_ember_mmi)

	var smoke_mm := MultiMesh.new()
	smoke_mm.transform_format = MultiMesh.TRANSFORM_3D
	smoke_mm.use_colors = true
	smoke_mm.use_custom_data = false
	smoke_mm.mesh = _smoke_mesh
	smoke_mm.instance_count = SMOKE_COUNT
	for i in SMOKE_COUNT:
		smoke_mm.set_instance_transform(i, Transform3D.IDENTITY)
		smoke_mm.set_instance_color(i, Color(COL_SMOKE_SOOT.r, COL_SMOKE_SOOT.g, COL_SMOKE_SOOT.b, 0.0))

	_smoke_mmi = MultiMeshInstance3D.new()
	_smoke_mmi.name = "FireSmokePlumes"
	_smoke_mmi.multimesh = smoke_mm
	_smoke_mmi.material_override = _smoke_mat
	_smoke_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke_mmi.visibility_range_end = SMOKE_VISIBILITY_RANGE
	_smoke_mmi.extra_cull_margin = 12.0
	_smoke_mmi.visible = false
	add_child(_smoke_mmi)

	_halo_mat = StandardMaterial3D.new()
	_halo_mat.vertex_color_use_as_albedo = true
	_halo_mat.vertex_color_is_srgb = true
	_halo_mat.emission_enabled = true
	_halo_mat.emission = Color(1.0, 0.50, 0.14)
	_halo_mat.emission_energy_multiplier = 0.0
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.billboard_keep_scale = true
	_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)

	_fire_halo = MeshInstance3D.new()
	_fire_halo.name = "FireGlowHalo"
	_fire_halo.mesh = _halo_mesh
	_fire_halo.material_override = _halo_mat
	_fire_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fire_halo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_fire_halo.visibility_range_end = HALO_VISIBILITY_RANGE
	_fire_halo.extra_cull_margin = 2.0
	_fire_halo.visible = false
	add_child(_fire_halo)
	_fire_halo_energy = 0.0
	_vfx_active_last_sync = false


func _reset_vfx_ages() -> void:
	for i in EMBER_COUNT:
		_ember_age[i] = lerpf(0.02, 0.46, float(i) / float(EMBER_COUNT))
	for i in SMOKE_COUNT:
		_smoke_age[i] = lerpf(0.02, 0.44, float(i) / float(SMOKE_COUNT))


func _get_local_up_and_wind() -> Basis:
	# Pack local_up in .y, local_wind in .x (unnormalized), and unused .z so zero heap allocations occur.
	var world_wind := Weather.wind_vector() if Weather != null else Vector3(3.0, 0.0, -2.0)
	var local_up := Vector3.UP
	var local_wind := world_wind
	if is_inside_tree():
		var gb := global_basis
		if absf(gb.determinant()) > 1e-6:
			var inv_b := gb.inverse()
			local_up = (inv_b * Vector3.UP).normalized()
			local_wind = inv_b * world_wind
	elif ship != null and is_instance_valid(ship) and ship.is_inside_tree():
		var sb := ship.global_basis
		if absf(sb.determinant()) > 1e-6:
			var inv_sb := sb.inverse()
			local_up = (inv_sb * Vector3.UP).normalized()
			local_wind = inv_sb * world_wind
	var wind_h := local_wind - local_up * local_wind.dot(local_up)
	return Basis(wind_h, local_up, Vector3.ZERO)


func _sync_visuals(vfx_delta: float = 0.0) -> void:
	var sc := maxf(visual_scale, 0.5)
	var active_count := 0
	var centroid := Vector3.ZERO
	var total_intensity := 0.0

	for i in _zone_nodes.size():
		var mi := _zone_nodes[i]
		if mi == null or not is_instance_valid(mi):
			continue
		var inten := _zone_intensity[i] if i < _zone_intensity.size() else 0.0
		var is_lit := inten > 0.01
		mi.visible = is_lit
		if is_lit:
			if active_count < _active_zone_buf.size():
				_active_zone_buf[active_count] = i
			active_count += 1
			total_intensity += inten
			centroid += _zone_local_positions[i]
			var fi := float(i)
			var base_s := sc * lerpf(0.45, 1.08, inten)
			var lick_y := 1.0 + 0.17 * sin(_anim_clock * 11.8 + fi * 2.1) + 0.09 * cos(_anim_clock * 18.4 + fi * 3.3)
			var sway_xz := 1.0 + 0.08 * sin(_anim_clock * 9.1 + fi * 1.7)
			mi.scale = Vector3(base_s * sway_xz, base_s * lick_y, base_s * sway_xz)
			mi.rotation.y = fi * 1.05 + sin(_anim_clock * 3.6 + fi * 1.4) * 0.16

	if active_count > 0:
		centroid /= float(active_count)

	if _fire_light != null and is_instance_valid(_fire_light):
		if active_count > 0:
			_fire_light.position = centroid + Vector3(0.0, 0.90 * sc, 0.0)
			var flick := 0.88 + 0.12 * sin(_anim_clock * 14.2) * cos(_anim_clock * 8.9)
			var base_energy := lerpf(2.1, 4.0, clampf(total_intensity / 3.0, 0.0, 1.0))
			_fire_light.light_energy = base_energy * flick
			_fire_light.visible = true
		else:
			_fire_light.light_energy = 0.0
			_fire_light.visible = false

	if active_count <= 0:
		_fire_halo_energy = 0.0
		_vfx_active_last_sync = false
		if _fire_halo != null and is_instance_valid(_fire_halo):
			_fire_halo.visible = false
		if _halo_mat != null:
			_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		if _ember_mmi != null and is_instance_valid(_ember_mmi):
			_ember_mmi.visible = false
		if _smoke_mmi != null and is_instance_valid(_smoke_mmi):
			_smoke_mmi.visible = false
		return

	var fresh_ignite := not _vfx_active_last_sync
	if fresh_ignite:
		_reset_vfx_ages()
		_vfx_active_last_sync = true

	# Update sculpted radial-gradient FireGlowHalo centered smoothly above burning deck zones.
	var intensity_t := clampf(total_intensity / 3.0, 0.0, 1.0)
	var night := clampf(1.0 - (Weather.daylight() if Weather != null else 1.0), 0.0, 1.0)
	var halo_flick := 0.94 + 0.06 * sin(_anim_clock * 13.5) * cos(_anim_clock * 8.1)
	_fire_halo_energy = lerpf(0.32, 0.68, intensity_t) * lerpf(1.0, 2.25, night) * halo_flick
	if _fire_halo != null and is_instance_valid(_fire_halo):
		var target_halo_pos := centroid + Vector3(0.0, 0.75 * sc, 0.0)
		if fresh_ignite or vfx_delta <= 0.0:
			_fire_halo.position = target_halo_pos
		else:
			_fire_halo.position = _fire_halo.position.lerp(target_halo_pos, clampf(vfx_delta * 8.0, 0.0, 1.0))
		var halo_r := lerpf(1.75, 3.45, intensity_t) * lerpf(1.0, 1.24, night) * sc * (0.96 + 0.04 * halo_flick)
		_fire_halo.scale = Vector3(halo_r, halo_r, halo_r)
		_fire_halo.visible = true
	if _halo_mat != null:
		_halo_mat.albedo_color = Color(_fire_halo_energy, _fire_halo_energy, _fire_halo_energy, 1.0)

	_update_embers_and_smoke(active_count, sc, vfx_delta)


func _update_embers_and_smoke(active_count: int, sc: float, vfx_delta: float) -> void:
	var frame_info := _get_local_up_and_wind()
	var wind_h := frame_info.x
	var local_up := frame_info.y
	var wind_spd := wind_h.length()
	var wind_dir := wind_h / wind_spd if wind_spd > 0.001 else Vector3.ZERO
	var ref_ax := Vector3.RIGHT if absf(local_up.dot(Vector3.RIGHT)) < 0.85 else Vector3.FORWARD
	var tan_u := local_up.cross(ref_ax).normalized()
	var tan_v := local_up.cross(tan_u).normalized()

	var ember_drift_max := clampf(wind_spd * 0.24, 0.35, 3.80) * sc if wind_spd > 0.001 else 0.0
	var smoke_drift_max := clampf(wind_spd * 0.38, 0.60, 6.20) * sc if wind_spd > 0.001 else 0.0

	if _ember_mmi != null and is_instance_valid(_ember_mmi):
		_ember_mmi.visible = true
		var ember_mm := _ember_mmi.multimesh
		if ember_mm != null:
			for i in EMBER_COUNT:
				var age := _ember_age[i]
				if vfx_delta > 0.0:
					age = fposmod(age + _ember_speed[i] * vfx_delta, 1.0)
					_ember_age[i] = age
				var z_idx := _active_zone_buf[i % active_count]
				var base_pos := _zone_local_positions[z_idx]
				var z_inten := _zone_intensity[z_idx]
				var rise := lerpf(EMBER_Y_MIN, EMBER_Y_MAX, age) * sc
				var ang := _ember_phase[i] + _anim_clock * _ember_swirl_freq[i] + age * TAU * 1.15
				var swirl_rad := _ember_swirl_r[i] * sc * (0.45 + 0.75 * age)
				var drift := ember_drift_max * pow(age, 1.2)
				var pos := base_pos + local_up * rise + wind_dir * drift \
					+ (tan_u * cos(ang) + tan_v * sin(ang)) * swirl_rad
				_ember_pos[i] = pos
				var env := smoothstep(0.0, 0.08, age) * (1.0 - 0.65 * smoothstep(0.76, 1.0, age))
				var s := maxf(0.18, _ember_scale[i] * env * lerpf(0.70, 1.18, z_inten) * sc)
				var spin_b := Basis(Vector3.UP, ang * 0.9) * Basis(Vector3.RIGHT, _anim_clock * 3.4 + float(i) * 0.7)
				ember_mm.set_instance_transform(i, Transform3D(spin_b.scaled(Vector3(s, s, s)), pos))
				var col: Color
				if age < 0.45:
					col = COL_FLAME_GOLD.lerp(COL_FLAME_ORANGE, age / 0.45)
				else:
					col = COL_FLAME_ORANGE.lerp(COL_FLAME_CRIMSON, (age - 0.45) / 0.55)
				ember_mm.set_instance_color(i, col)

	if _smoke_mmi != null and is_instance_valid(_smoke_mmi):
		_smoke_mmi.visible = true
		var smoke_mm := _smoke_mmi.multimesh
		if smoke_mm != null:
			for i in SMOKE_COUNT:
				var age := _smoke_age[i]
				if vfx_delta > 0.0:
					age = fposmod(age + _smoke_speed[i] * vfx_delta, 1.0)
					_smoke_age[i] = age
				var z_idx := _active_zone_buf[i % active_count]
				var base_pos := _zone_local_positions[z_idx]
				var z_inten := _zone_intensity[z_idx]
				var rise := lerpf(SMOKE_Y_MIN, SMOKE_Y_MAX, age) * sc
				var ang := _smoke_phase[i] + _anim_clock * 0.75 + age * 2.2
				var sway_rad := _smoke_swirl_r[i] * sc * (0.40 + 0.85 * age)
				var drift := smoke_drift_max * pow(age, 1.25)
				var pos := base_pos + local_up * rise + wind_dir * drift \
					+ (tan_u * cos(ang) + tan_v * sin(ang)) * sway_rad
				var grow := lerpf(0.55, 1.85, age) * _smoke_scale[i] * lerpf(0.75, 1.15, z_inten) * sc
				_smoke_pos[i] = pos
				_smoke_live_scale[i] = grow
				var puff_b := Basis(Vector3.UP, _smoke_phase[i] + _anim_clock * 0.35) * Basis(Vector3.RIGHT, sin(ang) * 0.22)
				smoke_mm.set_instance_transform(i, Transform3D(puff_b.scaled(Vector3(grow * 1.12, grow * 0.88, grow * 1.12)), pos))
				var alpha := smoothstep(0.0, 0.14, age) * (1.0 - smoothstep(0.68, 1.0, age)) * lerpf(0.52, 0.78, z_inten)
				var base_col: Color
				if age < 0.22:
					base_col = COL_SMOKE_BASE.lerp(COL_SMOKE_SOOT, age / 0.22)
				else:
					base_col = COL_SMOKE_SOOT.lerp(COL_SMOKE_ASH, (age - 0.22) / 0.78)
				smoke_mm.set_instance_color(i, Color(base_col.r, base_col.g, base_col.b, alpha))


# ==============================================================================
# 100% Sculpted Zero-Primitive Multi-Tongue Flame Cluster & VFX Builders
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _flame_mat == null:
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.vertex_color_use_as_albedo = true
		_flame_mat.vertex_color_is_srgb = true
		_flame_mat.emission_enabled = true
		_flame_mat.emission = Color(1.0, 0.44, 0.08)
		_flame_mat.emission_energy_multiplier = 1.45
		_flame_mat.roughness = 0.48
		_flame_mat.metallic = 0.0
	if _flame_mesh == null:
		_flame_mesh = _build_flame_cluster_mesh()
	if _ember_mat == null:
		_ember_mat = StandardMaterial3D.new()
		_ember_mat.vertex_color_use_as_albedo = true
		_ember_mat.vertex_color_is_srgb = true
		_ember_mat.emission_enabled = true
		_ember_mat.emission = Color(1.0, 0.52, 0.12)
		_ember_mat.emission_energy_multiplier = 2.10
		_ember_mat.roughness = 0.30
		_ember_mat.metallic = 0.0
	if _ember_mesh == null:
		_ember_mesh = _build_ember_mesh()
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.vertex_color_is_srgb = true
		_smoke_mat.roughness = 0.95
		_smoke_mat.metallic = 0.0
	if _smoke_mesh == null:
		_smoke_mesh = _build_smoke_puff_mesh()
	if _halo_mesh == null:
		_halo_mesh = _build_fire_halo_mesh()


static func _build_ember_mesh() -> ArrayMesh:
	# Sculpted 8-tri faceted diamond bipyramid ember spark (finite unit normals).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, 0.088, 0.0)
	var bot := Vector3(0.0, -0.072, 0.0)
	const R := 0.044
	var ring: Array[Vector3] = [
		Vector3(R, 0.0, 0.0),
		Vector3(0.0, 0.0, R),
		Vector3(-R, 0.0, 0.0),
		Vector3(0.0, 0.0, -R),
	]
	var c_top := Color(1.0, 0.99, 0.94)
	var c_mid := Color(1.0, 0.95, 0.86)
	var c_bot := Color(0.92, 0.84, 0.74)
	for k in 4:
		var k1 := (k + 1) % 4
		_emit_outward_tri(st, top, ring[k], ring[k1], Vector3.ZERO, c_top, c_mid, c_mid)
		_emit_outward_tri(st, bot, ring[k1], ring[k], Vector3.ZERO, c_bot, c_mid, c_mid)
	st.generate_normals()
	return st.commit()


static func _build_smoke_puff_mesh() -> ArrayMesh:
	# Sculpted 24-tri organic multi-faceted billowing low-poly soot smoke puff (finite unit normals).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 6
	var north := Vector3(0.02, 0.48, -0.02)
	var south := Vector3(-0.02, -0.44, 0.02)
	var upper: Array[Vector3] = []
	var lower: Array[Vector3] = []
	for k in SEGS:
		var a_u := TAU * float(k) / float(SEGS)
		var r_u := 0.44 * (1.0 + 0.14 * sin(float(k) * 2.1 + 0.4))
		var y_u := 0.20 + 0.05 * cos(float(k) * 1.7)
		upper.append(Vector3(cos(a_u) * r_u, y_u, sin(a_u) * r_u))

		var a_l := a_u + PI / float(SEGS)
		var r_l := 0.47 * (1.0 + 0.15 * cos(float(k) * 2.5 - 0.3))
		var y_l := -0.18 + 0.04 * sin(float(k) * 2.3)
		lower.append(Vector3(cos(a_l) * r_l, y_l, sin(a_l) * r_l))

	var c_top := Color(1.0, 0.98, 0.96)
	var c_mid := Color(0.84, 0.82, 0.84)
	var c_bot := Color(0.62, 0.60, 0.64)
	for k in SEGS:
		var k1 := (k + 1) % SEGS
		_emit_outward_tri(st, north, upper[k], upper[k1], Vector3.ZERO, c_top, c_mid, c_mid)
		_emit_outward_quad(st, upper[k], lower[k], lower[k1], upper[k1], Vector3.ZERO, c_mid, c_bot, c_bot, c_mid)
		_emit_outward_tri(st, south, lower[k1], lower[k], Vector3.ZERO, c_bot, c_bot, c_bot)
	st.generate_normals()
	return st.commit()


static func _build_fire_halo_mesh() -> ArrayMesh:
	# Sculpted 16-wedge radial-gradient halo disc (center amber-gold -> rim black for seamless additive feathering).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const INNER_R := 0.42
	const OUTER_R := 1.0
	var n := Vector3(0.0, 0.0, 1.0)
	var ctr := Vector3.ZERO
	for i in WEDGES:
		var a0 := TAU * float(i) / float(WEDGES)
		var a1 := TAU * float(i + 1) / float(WEDGES)
		var m0 := Vector3(cos(a0) * INNER_R, sin(a0) * INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * INNER_R, sin(a1) * INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)
		# Inner core wedge facing +Z
		st.set_normal(n)
		st.set_color(COL_HALO_CENTER)
		st.add_vertex(ctr)
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		# Outer feathered skirt quad facing +Z
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(n)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(n)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(n)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o0)
	return st.commit()


static func _build_flame_cluster_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Charred ash & molten-fissure ember hearth bed disc (y = 0.01..0.06, 72 tris).
	_add_ember_hearth(st, 0.52, 0.28, 0.055, 12)

	# 2. 10 sculpted faceted charcoal & glowing-coal lumps ringing the hearth (120 tris).
	for ci in 10:
		var ang := float(ci) / 10.0 * TAU + 0.18 * sin(float(ci) * 2.7)
		var rad := 0.16 + 0.24 * (0.5 + 0.5 * sin(float(ci) * 3.1 + 0.6))
		var pos := Vector3(cos(ang) * rad, 0.045 + 0.02 * float(ci % 3), sin(ang) * rad)
		var size := Vector3(
			0.095 + 0.030 * float(ci % 3),
			0.068 + 0.022 * float((ci + 1) % 3),
			0.085 + 0.025 * float((ci + 2) % 2)
		)
		var col_top := COL_COAL_GLOW if (ci % 2 == 0) else COL_FLAME_CRIMSON
		_add_faceted_coal(st, pos, size, ang, col_top, COL_COAL_DARK)

	# 3. 5 inner incandescent gold-white core flame tongues licking upward (160 tris).
	var inner_specs: Array[Array] = [
		[Vector3(0.0, 0.04, 0.0), 1.18, 0.19, 0.14, 0.05, 0.0],
		[Vector3(0.11, 0.04, 0.06), 0.96, 0.15, 0.12, 0.08, 1.15],
		[Vector3(-0.10, 0.04, 0.08), 1.02, 0.15, 0.11, 0.09, 2.45],
		[Vector3(-0.08, 0.04, -0.11), 0.92, 0.14, 0.11, 0.07, 3.80],
		[Vector3(0.09, 0.04, -0.09), 0.88, 0.14, 0.11, 0.08, 5.05],
	]
	for sp: Array in inner_specs:
		_add_flame_tongue(
			st,
			sp[0] as Vector3,
			float(sp[1]),
			float(sp[2]),
			float(sp[3]),
			float(sp[4]),
			float(sp[5]),
			COL_FLAME_AMBER,
			COL_FLAME_GOLD,
			COL_FLAME_CORE
		)

	# 4. 7 mid/outer fiery-orange & crimson leaping flame blades sweeping around the cluster (224 tris).
	for oi in 7:
		var ang := float(oi) / 7.0 * TAU + 0.22
		var r_base := 0.21 + 0.08 * float(oi % 2)
		var base_pos := Vector3(cos(ang) * r_base, 0.03, sin(ang) * r_base)
		var h := 0.78 + 0.18 * float(oi % 3) + 0.16 * float((oi + 1) % 2)
		var w := 0.16 + 0.035 * float(oi % 2)
		var depth := 0.11 + 0.025 * float((oi + 1) % 2)
		var lean := 0.15 + 0.06 * float(oi % 3)
		_add_flame_tongue(
			st,
			base_pos,
			h,
			w,
			depth,
			lean,
			ang,
			COL_FLAME_CRIMSON,
			COL_FLAME_ORANGE,
			COL_FLAME_GOLD
		)

	# 5. 8 rising faceted diamond ember sparks hovering above the leaping flame tips (96 tris).
	for ei in 8:
		var ang := float(ei) / 8.0 * TAU + 0.45
		var rad := 0.12 + 0.26 * (float((ei * 3) % 5) / 4.0)
		var y_pos := 0.96 + 0.12 * float(ei)
		var pos := Vector3(cos(ang) * rad, y_pos, sin(ang) * rad)
		var spark_r := 0.032 + 0.012 * float(ei % 3)
		var spark_h := 0.068 + 0.022 * float((ei + 1) % 3)
		var c_top := COL_FLAME_CORE if (ei % 2 == 0) else COL_FLAME_GOLD
		var c_bot := COL_FLAME_ORANGE if (ei % 2 == 0) else COL_FLAME_CRIMSON
		_add_faceted_spark(st, pos, spark_r, spark_h, ang, c_top, c_bot)

	st.generate_normals()
	return st.commit()


static func _add_ember_hearth(st: SurfaceTool, r_outer: float, r_inner: float, height: float, segs: int) -> void:
	var center_bot := Vector3(0.0, 0.006, 0.0)
	var center_top := Vector3(0.0, height, 0.0)
	var ref_c := Vector3(0.0, height * 0.45, 0.0)
	var y_rim := height * 0.42
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var j0 := 1.0 + 0.10 * sin(float(i) * 2.5)
		var j1 := 1.0 + 0.10 * sin(float((i + 1) % segs) * 2.5)
		var out_b0 := Vector3(cos(a0) * r_outer * j0, 0.008, sin(a0) * r_outer * j0)
		var out_b1 := Vector3(cos(a1) * r_outer * j1, 0.008, sin(a1) * r_outer * j1)
		var out_t0 := Vector3(cos(a0) * r_outer * 0.88 * j0, y_rim, sin(a0) * r_outer * 0.88 * j0)
		var out_t1 := Vector3(cos(a1) * r_outer * 0.88 * j1, y_rim, sin(a1) * r_outer * 0.88 * j1)
		var in_t0 := Vector3(cos(a0) * r_inner * j0, height * 0.85, sin(a0) * r_inner * j0)
		var in_t1 := Vector3(cos(a1) * r_inner * j1, height * 0.85, sin(a1) * r_inner * j1)

		var c_glow := COL_COAL_GLOW if (i % 2 == 0) else COL_FLAME_ORANGE
		# Bottom cap
		_emit_outward_tri(st, center_bot, out_b1, out_b0, ref_c, COL_COAL_DARK, COL_COAL_DARK, COL_COAL_DARK)
		# Outer charred bevel skirt
		_emit_outward_quad(st, out_b0, out_b1, out_t1, out_t0, ref_c, COL_COAL_DARK, COL_COAL_DARK, COL_HEARTH_ASH, COL_HEARTH_ASH)
		# Mid transition to glowing ember pit
		_emit_outward_quad(st, out_t0, out_t1, in_t1, in_t0, ref_c, COL_HEARTH_ASH, COL_HEARTH_ASH, c_glow, c_glow)
		# Hot glowing inner pit core
		_emit_outward_tri(st, in_t0, in_t1, center_top, ref_c, c_glow, c_glow, COL_FLAME_AMBER)


static func _add_faceted_coal(st: SurfaceTool, center: Vector3, size: Vector3, yaw: float,
		col_hot: Color, col_dark: Color) -> void:
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.16 * sin(yaw * 2.0))
	var top := center + rot * Vector3(0.0, size.y * 0.65, 0.0)
	var bot := center + rot * Vector3(0.0, -size.y * 0.50, 0.0)
	var ring: Array[Vector3] = []
	const SEGS := 6
	for k in SEGS:
		var a := TAU * float(k) / float(SEGS)
		var w := 1.0 + 0.18 * sin(float(k) * 2.3 + yaw)
		ring.append(center + rot * Vector3(cos(a) * size.x * 0.55 * w, sin(a * 2.0) * size.y * 0.14, sin(a) * size.z * 0.55 * w))
	for k in SEGS:
		var k1 := (k + 1) % SEGS
		var c_up := col_hot if (k % 3 == 0) else col_dark.lerp(col_hot, 0.25)
		var c_dn := col_dark
		_emit_outward_tri(st, top, ring[k], ring[k1], center, c_up, c_up, col_dark)
		_emit_outward_tri(st, bot, ring[k1], ring[k], center, c_dn, c_dn, c_dn)


static func _add_flame_tongue(
	st: SurfaceTool,
	base_pos: Vector3,
	height: float,
	width: float,
	depth: float,
	lean_rad: float,
	azimuth: float,
	col_base: Color,
	col_mid: Color,
	col_tip: Color
) -> void:
	# 4-sided diamond cross-section tapering across 4 vertical tiers with an organic S-curve lick.
	var radial := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var tangent := Vector3(-sin(azimuth), 0.0, cos(azimuth))
	var tier_t: Array[float] = [0.0, 0.24, 0.54, 0.80]
	var tier_s: Array[float] = [0.68, 1.0, 0.72, 0.34]
	var rings: Array[Array] = []
	var centers: Array[Vector3] = []

	for ti in tier_t.size():
		var t := tier_t[ti]
		var sc := tier_s[ti]
		var curve_out := sin(t * PI) * lean_rad
		var curve_swirl := sin(t * TAU * 0.85 + azimuth) * lean_rad * 0.42
		var ctr := base_pos + Vector3(0.0, t * height, 0.0) + radial * curve_out + tangent * curve_swirl
		centers.append(ctr)
		var twist := t * 0.55 + azimuth
		var rx := Vector3(cos(twist), 0.0, sin(twist)) * (width * sc)
		var rz := Vector3(-sin(twist), 0.0, cos(twist)) * (depth * sc)
		rings.append([ctr + rx, ctr + rz, ctr - rx, ctr - rz])

	var tip := base_pos + Vector3(0.0, height, 0.0) + radial * (lean_rad * 0.38) + tangent * (cos(azimuth) * lean_rad * 0.22)
	var base_cap := base_pos + Vector3(0.0, -0.02, 0.0)

	var tier_cols: Array[Color] = [
		col_base,
		col_base.lerp(col_mid, 0.65),
		col_mid.lerp(col_tip, 0.55),
		col_tip,
	]

	# Base cap pyramid (4 tris)
	var r_bot: Array = rings[0]
	var ref_bot := (base_cap + centers[0]) * 0.5 + Vector3(0.0, 0.04, 0.0)
	for k in 4:
		var k1 := (k + 1) % 4
		_emit_outward_tri(st, base_cap, r_bot[k1] as Vector3, r_bot[k] as Vector3, ref_bot, col_base, col_base, col_base)

	# 3 quad body tiers (3 * 4 * 2 = 24 tris)
	for ti in range(rings.size() - 1):
		var r0: Array = rings[ti]
		var r1: Array = rings[ti + 1]
		var ref_mid := (centers[ti] + centers[ti + 1]) * 0.5
		var c0 := tier_cols[ti]
		var c1 := tier_cols[ti + 1]
		for k in 4:
			var k1 := (k + 1) % 4
			_emit_outward_quad(st, r0[k] as Vector3, r0[k1] as Vector3, r1[k1] as Vector3, r1[k] as Vector3,
				ref_mid, c0, c0, c1, c1)

	# Tapered sharp flame tip pyramid (4 tris)
	var r_top: Array = rings[rings.size() - 1]
	var ref_top := (centers[centers.size() - 1] + tip) * 0.5
	for k in 4:
		var k1 := (k + 1) % 4
		_emit_outward_tri(st, r_top[k] as Vector3, r_top[k1] as Vector3, tip, ref_top, tier_cols[3], tier_cols[3], col_tip)


static func _add_faceted_spark(st: SurfaceTool, center: Vector3, radius: float, half_h: float,
		yaw: float, col_top: Color, col_bot: Color) -> void:
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.24)
	var top := center + rot * Vector3(0.0, half_h, 0.0)
	var bot := center + rot * Vector3(0.0, -half_h * 0.82, 0.0)
	const SEGS := 6
	var ring: Array[Vector3] = []
	for k in SEGS:
		var a := TAU * float(k) / float(SEGS)
		ring.append(center + rot * Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	var col_mid := col_bot.lerp(col_top, 0.5)
	for k in SEGS:
		var k1 := (k + 1) % SEGS
		_emit_outward_tri(st, top, ring[k], ring[k1], center, col_top, col_mid, col_mid)
		_emit_outward_tri(st, bot, ring[k1], ring[k], center, col_bot, col_mid, col_mid)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)
