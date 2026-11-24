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
