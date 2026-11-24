extends Node
## Session/authority facade. The simulation is host-authoritative from day one:
## single-player is simply a host with no remote peers and AI filling crew slots.
## Gameplay code asks `Net.is_host()` before mutating world state, and routes
## player intent through RPCs that the host validates.

signal session_started
signal peer_joined(id: int)
signal peer_left(id: int)

const DEFAULT_PORT := 24642
const MAX_PLAYERS := 4
## World clock/weather snapshots per second sent to clients.
const WORLD_SYNC_HZ := 4.0

var _sync_accum := 0.0
var _host_time_offset := 0.0  # client: smoothed (host Sea.time - local Sea.time) error

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
	multiplayer.peer_connected.connect(func(id): peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id): peer_left.emit(id))
	session_started.emit()
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

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
	else:
		# Clients run the wave clock locally and bleed off error against the host,
		# so the sea stays smooth between snapshots and identical across peers.
		var step := delta + clampf(_host_time_offset, -0.5, 0.5) * minf(delta * 4.0, 1.0)
		_host_time_offset -= step - delta
		Sea.time += step

@rpc("authority", "call_remote", "unreliable_ordered")
func _world_snapshot(sea_time: float, amp_scale: float, weather: Dictionary) -> void:
	var err := sea_time - Sea.time
	if absf(err) > 2.0:
		Sea.time = sea_time
		_host_time_offset = 0.0
	else:
		_host_time_offset = err
	Sea.amp_scale = amp_scale
	Weather.apply_state(weather)
