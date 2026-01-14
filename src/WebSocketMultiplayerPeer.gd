# WebSocketMultiplayerPeer - Handles WebSocket connection setup for Node.js backend
# This is used alongside Godot's built-in multiplayer to manage server connections

class_name WebSocketMultiplayerPeer

var _ws: WebSocketPeer
var _server_url: String
var _unique_id: int = 0
var _connection_status: ConnectionStatus = CONNECTION_DISCONNECTED
var _target_peer: int = 0
var _is_server_flag: bool = false
var _room_id: String = ""

# Packet management
var _incoming_packets: Array = []
var _current_packet_peer: int = 0

# Peer tracking
var _connected_peers: Dictionary = {}  # peer_id -> peer_name

func _init() -> void:
	_ws = WebSocketPeer.new()
	print("[WSPeer] Initialized")

func ws_connect(url: String) -> Error:
	_server_url = url
	var err = _ws.connect_to_url(url)
	if err != OK:
		push_error("[WSPeer] Failed to connect: " + str(err))
		return err

	_connection_status = CONNECTION_CONNECTING
	print("[WSPeer] Connecting to ", url)
	return OK

func send_handshake(version: String, player_name: String, token: String) -> void:
	var msg = {
		"type": "handshake",
		"data": {
			"version": version,
			"name": player_name,
			"token": token
		}
	}
	_send_message(msg)
	print("[WSPeer] Sent handshake")

func create_room(version: String, player_name: String) -> void:
	var msg = {
		"type": "create_room",
		"data": {
			"version": version,
			"name": player_name
		}
	}
	_send_message(msg)
	print("[WSPeer] Sent create_room")

func join_room(room_id: String, version: String, player_name: String) -> void:
	var msg = {
		"type": "join_room",
		"data": {
			"roomId": room_id,
			"version": version,
			"name": player_name
		}
	}
	_send_message(msg)
	print("[WSPeer] Sent join_room: ", room_id)

func _send_message(msg: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify(msg))

## Override MultiplayerPeerExtension methods

## Connection status tracking

func get_connection_status() -> int:
	return _connection_status

func get_unique_id() -> int:
	return _unique_id

func is_server() -> bool:
	return _is_server_flag

func poll() -> void:
	if _ws == null:
		return

	_ws.poll()
	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if _connection_status == CONNECTION_CONNECTING:
			_connection_status = CONNECTION_CONNECTED
			print("[WSPeer] Connection established")

		while _ws.get_available_packet_count() > 0:
			_process_incoming_message()

	elif state == WebSocketPeer.STATE_CLOSED:
		if _connection_status != CONNECTION_DISCONNECTED:
			_connection_status = CONNECTION_DISCONNECTED
			print("[WSPeer] Connection closed")


func _process_incoming_message() -> void:
	var packet = _ws.get_packet()
	var text = packet.get_string_from_utf8()

	var json = JSON.new()
	if json.parse(text) != OK:
		return

	var msg = json.data
	if typeof(msg) != TYPE_DICTIONARY:
		return

	var msg_type = msg.get("type", "")
	var msg_data = msg.get("data", {})

	match msg_type:
		"handshake_accepted":
			_unique_id = int(msg_data.get("userId", 0))
			print("[WSPeer] ✅ Handshake accepted, peer_id: ", _unique_id)

		"room_created":
			_room_id = msg_data.get("roomId", "")
			_unique_id = int(msg_data.get("peerId", 1))
			_is_server_flag = true
			print("[WSPeer] ✅ Room created: ", _room_id, " as peer ", _unique_id)

		"room_joined":
			_room_id = msg_data.get("roomId", "")
			_unique_id = int(msg_data.get("peerId", 0))
			_is_server_flag = (_unique_id == 1)

			# Process existing members
			var members = msg_data.get("members", [])
			for member in members:
				var peer_id = int(member.get("peerId", 0))
				var peer_name = member.get("name", "Unknown")
				if peer_id != _unique_id:
					_connected_peers[peer_id] = peer_name
					peer_connected.emit(peer_id)

			print("[WSPeer] ✅ Room joined: ", _room_id, " as peer ", _unique_id, " (", members.size(), " members)")

		"peer_joined":
			var peer_id = int(msg_data.get("peerId", 0))
			var peer_name = msg_data.get("name", "Unknown")
			if peer_id != _unique_id:
				_connected_peers[peer_id] = peer_name
				peer_connected.emit(peer_id)
				print("[WSPeer] 👤 Peer joined: ", peer_id, " (", peer_name, ")")

		"peer_left":
			var peer_id = int(msg_data.get("peerId", 0))
			if _connected_peers.has(peer_id):
				_connected_peers.erase(peer_id)
				peer_disconnected.emit(peer_id)
				print("[WSPeer] 👋 Peer left: ", peer_id)

		"rpc_call":
			# RPC call from another peer
			var from_peer = int(msg_data.get("fromPeer", 0))
			var method_name = msg_data.get("method", "")
			var args = msg_data.get("args", [])

			# Store as incoming packet for Godot to process
			var packet_data = {
				"from": from_peer,
				"method": method_name,
				"args": args
			}
			_current_packet_peer = from_peer
			_incoming_packets.append(var_to_bytes(packet_data))

func close() -> void:
	if _ws:
		_ws.close()
	_connection_status = CONNECTION_DISCONNECTED
	_connected_peers.clear()
	_incoming_packets.clear()
	print("[WSPeer] Closed connection")

## Helper methods
func get_peer_name(peer_id: int) -> String:
	return _connected_peers.get(peer_id, "Unknown")

func get_connected_peers() -> Array:
	return _connected_peers.keys()

func get_room_id() -> String:
	return _room_id

func is_backend_connected() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN
