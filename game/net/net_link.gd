class_name NetLink
extends Node
## One ENet endpoint (server or client) polled every frame; messages go out as JSON packets and
## come in through `received`. Reliable by default; `send_fast` is unordered and may be dropped
## (ball positions during a roll).

signal received(peer: int, msg: Dictionary)
signal peer_joined(peer: int)
signal peer_left(peer: int)
signal link_failed(reason: String)

var peer: ENetMultiplayerPeer
var is_server: bool = false
var connected: bool = false


func host(port: int, max_clients: int = 7) -> String:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, max_clients)
	if err != OK:
		peer = null
		return "cannot listen on port %d (%s)" % [port, error_string(err)]
	is_server = true
	connected = true
	peer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	peer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	return ""


func join(address: String, port: int) -> String:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		peer = null
		return "cannot connect to %s:%d (%s)" % [address, port, error_string(err)]
	is_server = false
	return ""


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	connected = false


func send(to: int, msg: Dictionary) -> void:
	_put(to, msg, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)


func send_fast(to: int, msg: Dictionary) -> void:
	_put(to, msg, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)


## Server: to every connected client.
func broadcast(msg: Dictionary) -> void:
	send(MultiplayerPeer.TARGET_PEER_BROADCAST, msg)


func broadcast_fast(msg: Dictionary) -> void:
	send_fast(MultiplayerPeer.TARGET_PEER_BROADCAST, msg)


func _put(to: int, msg: Dictionary, mode: MultiplayerPeer.TransferMode, channel: int) -> void:
	if peer == null or not connected:
		return
	peer.set_target_peer(to)
	peer.transfer_mode = mode
	peer.transfer_channel = channel
	peer.put_packet(NetProtocol.encode(msg))


func _process(_delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	if not is_server:
		var status: MultiplayerPeer.ConnectionStatus = peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED and not connected:
			connected = true
			peer_joined.emit(1)
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			var was: bool = connected
			close()
			if was:
				peer_left.emit(1)
			else:
				link_failed.emit("the host did not answer")
			return
	while peer != null and peer.get_available_packet_count() > 0:
		var from: int = peer.get_packet_peer()
		var msg: Dictionary = NetProtocol.decode(peer.get_packet())
		if not msg.is_empty():
			received.emit(from, msg)
