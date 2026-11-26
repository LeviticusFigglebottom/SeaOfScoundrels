extends Node
## Session/authority facade. The simulation is host-authoritative from day one:
## single-player is simply a host with no remote peers and AI filling crew slots.
## Gameplay code asks `Net.is_host()` before mutating world state, and routes
## player intent through RPCs that the host validates.

signal session_started
signal peer_joined(id: int)
signal peer_left(id: int)
signal client_intent_received(peer_id: int, intent: Dictionary)

const DEFAULT_PORT := 24642
const MAX_PLAYERS := 4
## World clock/weather snapshots per second sent to clients.
const WORLD_SYNC_HZ := 4.0
## Ship & pawn state snapshots per second sent to clients.
const ENTITY_SYNC_HZ := 15.0

var _sync_accum := 0.0
var _entity_sync_accum := 0.0
var _host_time_offset := 0.0  # client: smoothed (host Sea.time - local Sea.time) error
var _ships: Dictionary = {}   # StringName -> Node3D (Ship)
var _pawns: Dictionary = {}   # int peer_id -> Node3D (Pawn)
var _signals_bound := false


func is_host() -> bool:
	return multiplayer.multiplayer_peer == null \
		or multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


func start_single_player() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session_started.emit()


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_bind_multiplayer_signals()
	session_started.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_bind_multiplayer_signals()
	return OK


func disconnect_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	start_single_player()


func _bind_multiplayer_signals() -> void:
	if _signals_bound:
		return
	_signals_bound = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		# Immediate late-join sync so joining friends immediately see the exact sea, weather, and ship.
		_world_snapshot_reliable.rpc_id(id, Sea.time, Sea.amp_scale, Weather.get_state())
		var ship_snap := _collect_ship_states()
		if not ship_snap.is_empty():
			_ships_snapshot_reliable.rpc_id(id, ship_snap)
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	_pawns.erase(id)
	peer_left.emit(id)


## Register a ship for host -> client state replication under a stable id (e.g. &"player_sloop").
func register_replicated_ship(net_id: StringName, ship_node: Node3D) -> void:
	_ships[net_id] = ship_node


func unregister_replicated_ship(net_id: StringName) -> void:
	_ships.erase(net_id)


## Register a pawn for host -> client state replication under its controlling peer id (1 = host).
func register_replicated_pawn(peer_id: int, pawn_node: Node3D) -> void:
	_pawns[peer_id] = pawn_node


func unregister_replicated_pawn(peer_id: int) -> void:
	_pawns.erase(peer_id)


## Client -> Host: send compact player intent for the host to apply to this peer's Pawn.
func send_client_intent(intent: Dictionary) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer or multiplayer.is_server():
		return
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_client_intent.rpc_id(1, intent)


func _physics_process(delta: float) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.is_server():
		_sync_accum += delta
		if _sync_accum >= 1.0 / WORLD_SYNC_HZ:
			_sync_accum = 0.0
			_world_snapshot.rpc(Sea.time, Sea.amp_scale, Weather.get_state())
		_entity_sync_accum += delta
		if _entity_sync_accum >= 1.0 / ENTITY_SYNC_HZ:
			_entity_sync_accum = 0.0
			var ship_snap := _collect_ship_states()
			if not ship_snap.is_empty():
				_ships_snapshot.rpc(ship_snap)
			var pawn_snap := _collect_pawn_states()
			if not pawn_snap.is_empty():
				_pawns_snapshot.rpc(pawn_snap)
	else:
		# Clients run the wave clock locally and bleed off error against the host,
		# so the sea stays smooth between snapshots and identical across peers.
		var step := delta + clampf(_host_time_offset, -0.5, 0.5) * minf(delta * 4.0, 1.0)
		_host_time_offset -= step - delta
		Sea.time += step


func _collect_ship_states() -> Dictionary:
	var out := {}
	var dead_keys: Array[StringName] = []
	for k: StringName in _ships:
		var s: Node3D = _ships[k]
		if not is_instance_valid(s) or not s.is_inside_tree():
			dead_keys.append(k)
			continue
		if s.has_method(&"get_net_state"):
			out[String(k)] = s.call(&"get_net_state")
	for k in dead_keys:
		_ships.erase(k)
	return out


func _collect_pawn_states() -> Dictionary:
	var out := {}
	var dead_keys: Array[int] = []
	for pid: int in _pawns:
		var p: Node3D = _pawns[pid]
		if not is_instance_valid(p) or not p.is_inside_tree():
			dead_keys.append(pid)
			continue
		out[pid] = {
			"pos": p.global_position,
			"yaw": float(p.get(&"look_yaw")),
			"pitch": float(p.get(&"look_pitch")),
			"health": float(p.get(&"health")),
			"dead": bool(p.get(&"dead")),
		}
	for pid in dead_keys:
		_pawns.erase(pid)
	return out


@rpc("authority", "call_remote", "unreliable_ordered")
func _world_snapshot(sea_time: float, amp_scale: float, weather: Dictionary) -> void:
	_apply_world_snapshot(sea_time, amp_scale, weather)


@rpc("authority", "call_remote", "reliable")
func _world_snapshot_reliable(sea_time: float, amp_scale: float, weather: Dictionary) -> void:
	_apply_world_snapshot(sea_time, amp_scale, weather)


func _apply_world_snapshot(sea_time: float, amp_scale: float, weather: Dictionary) -> void:
	var err := sea_time - Sea.time
	if absf(err) > 2.0:
		Sea.time = sea_time
		_host_time_offset = 0.0
	else:
		_host_time_offset = err
	Sea.amp_scale = amp_scale
	Weather.apply_state(weather)


@rpc("authority", "call_remote", "unreliable_ordered")
func _ships_snapshot(states: Dictionary) -> void:
	_apply_ships_snapshot(states)


@rpc("authority", "call_remote", "reliable")
func _ships_snapshot_reliable(states: Dictionary) -> void:
	_apply_ships_snapshot(states)


func _apply_ships_snapshot(states: Dictionary) -> void:
	for k_str: String in states:
		var k := StringName(k_str)
		if not _ships.has(k):
			continue
		var s: Node3D = _ships[k]
		if is_instance_valid(s) and s.has_method(&"apply_net_state"):
			s.call(&"apply_net_state", states[k_str])


@rpc("authority", "call_remote", "unreliable_ordered")
func _pawns_snapshot(states: Dictionary) -> void:
	for pid_var in states:
		var pid := int(pid_var)
		if not _pawns.has(pid):
			continue
		var p: Node3D = _pawns[pid]
		if not is_instance_valid(p):
			continue
		var st: Dictionary = states[pid_var]
		p.global_position = p.global_position.lerp(st["pos"] as Vector3, 0.45)
		if pid != local_id():
			p.set(&"look_yaw", float(st["yaw"]))
			p.set(&"look_pitch", float(st["pitch"]))
		p.set(&"health", float(st["health"]))
		p.set(&"dead", bool(st["dead"]))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _client_intent(intent: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	client_intent_received.emit(sender, intent)
