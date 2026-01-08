# Tinybox Node.js Backend Adapter
# Bridges WebSocket communication with Godot's multiplayer system
extends Node
class_name MultiplayerNodeAdapter

signal room_created(room_id: String)
signal room_joined(peer_id: int, room_id: String)
signal connection_failed(reason: String)

var ws: WebSocketPeer = null
var server_url: String = "ws://localhost:30820"
var _peer_id: int = 0
var _room_id: String = ""
var _connected_peers: PackedInt32Array = []
var _is_connected: bool = false

func _init() -> void:
	ws = WebSocketPeer.new()

func connect_to_server(url: String) -> bool:
	server_url = url
	var err: Error = ws.connect_to_url(server_url)
	if err != OK:
		push_error("Failed to connect to Node backend: " + str(err))
		return false
	_is_connected = false
	return true

func _process(_delta: float) -> void:
	if ws == null:
		return

	ws.poll()
	var state: WebSocketPeer.State = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _is_connected:
			_is_connected = true

		while ws.get_available_packet_count() > 0:
			_on_ws_message()

	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_is_connected = false
			connection_failed.emit("Connection closed")

func _on_ws_message() -> void:
	var packet: PackedByteArray = ws.get_packet()
	var json_str: String = packet.get_string_from_utf8()
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_str)

	if parse_result != OK:
		push_error("Failed to parse JSON: " + json_str)
		return

	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Invalid message format")
		return

	var msg_type: String = data.get("type", "")
	var msg_data: Dictionary = data.get("data", {})

	match msg_type:
		"handshake_accepted":
			_handle_handshake_accepted(msg_data)
		"state":
			_handle_state(msg_data)
		"rpc":
			_handle_rpc(msg_data)
		"sync":
			_handle_sync(msg_data)
		"error":
			_handle_error(msg_data)
		"room_created":
			_handle_room_created(msg_data)
		"room_joined":
			_handle_room_joined(msg_data)
		_:
			push_warning("Unknown message type: " + str(msg_type))

func _handle_handshake_accepted(data: Dictionary) -> void:
	print("[NodeAdapter] ✅ Handshake accepted")
	print("[NodeAdapter] User ID: ", data.get("user_id", "N/A"))
	print("[NodeAdapter] Username: ", data.get("username", "N/A"))

func _handle_room_created(data: Dictionary) -> void:
	_room_id = data.get("roomId", "")
	_peer_id = data.get("peerId", 1)
	print("[NodeAdapter] ✅ Room created: ", _room_id, " (peer ", _peer_id, ")")
	room_created.emit(_room_id)
	UIHandler.show_alert("Room created: " + _room_id, 6, false, UIHandler.alert_colour_player)

func _handle_room_joined(data: Dictionary) -> void:
	_room_id = data.get("roomId", "")
	_peer_id = data.get("peerId", 0)
	var peers: Array = data.get("peers", [])
	_connected_peers.clear()
	for p: Variant in peers:
		if typeof(p) == TYPE_INT:
			_connected_peers.append(p as int)
		elif typeof(p) == TYPE_FLOAT:
			_connected_peers.append(int(p as float))
	print("[NodeAdapter] ✅ Room joined: ", _room_id, " (peer ", _peer_id, ")")
	room_joined.emit(_peer_id, _room_id)

func _handle_state(data: Dictionary) -> void:
	var state_type: String = data.get("type", "")
	match state_type:
		"room_created":
			_room_id = data.get("roomId", "")
			_peer_id = 1  # Host is always peer 1
			room_created.emit(_room_id)
			UIHandler.show_alert("Room created: " + _room_id, 6, false, UIHandler.alert_colour_player)
		"room_joined":
			_room_id = data.get("roomId", "")
			_peer_id = data.get("peerId", 0)
			var peers: Array = data.get("peers", [])
			_connected_peers.clear()
			for p: Variant in peers:
				if typeof(p) == TYPE_INT:
					_connected_peers.append(p as int)
				elif typeof(p) == TYPE_FLOAT:
					_connected_peers.append(int(p as float))
			room_joined.emit(_peer_id, _room_id)
		"peer_joined":
			var peer_id: int = data.get("peerId", 0)
			if peer_id > 0 and not _connected_peers.has(peer_id):
				_connected_peers.append(peer_id)
		"peer_left":
			var peer_id: int = data.get("peerId", 0)
			if _connected_peers.has(peer_id):
				_connected_peers.erase(peer_id)

func _handle_rpc(data: Dictionary) -> void:
	var method_name: String = data.get("method", "")
	var args: Array = data.get("args", [])
	var from_peer: int = data.get("from", 0)

	# Route to existing Godot RPC methods
	var main: Node = get_tree().current_scene
	if main and main.has_method(method_name):
		match args.size():
			0:
				main.call(method_name)
			1:
				main.call(method_name, args[0])
			2:
				main.call(method_name, args[0], args[1])
			3:
				main.call(method_name, args[0], args[1], args[2])
			_:
				main.callv(method_name, args)

func _handle_sync(data: Dictionary) -> void:
	# Handle player state snapshots
	var peer_id: int = data.get("peerId", 0)
	var state: Dictionary = data.get("state", {})
	# Forward to world/player sync system
	pass

func _handle_error(data: Dictionary) -> void:
	var code: String = data.get("code", "")
	var message: String = data.get("message", "Unknown error")
	push_error("Backend error: " + message)
	UIHandler.show_alert(message, 8, false, UIHandler.alert_colour_error)
	connection_failed.emit(message)

# Send message to backend
func _send_message(msg_type: String, msg_data: Dictionary) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_error("Cannot send message: WebSocket not open")
		return

	var message: Dictionary = {"type": msg_type, "data": msg_data}
	var json_str: String = JSON.stringify(message)
	ws.send_text(json_str)

# Protocol methods
func send_handshake(version: String, player_name: String, token: String = "") -> void:
	"""Send handshake with authentication token"""
	var handshake_data: Dictionary = {
		"version": version,
		"name": player_name
	}
	if token != "":
		handshake_data["token"] = token
	_send_message("handshake", handshake_data)
	print("[NodeAdapter] 🤝 Sent handshake: version=", version, " name=", player_name, " auth=", token != "")

func create_room(version: String, player_name: String, gamemode: String = "deathmatch", map_name: String = "", max_players: int = 8, is_public: bool = true) -> void:
	_send_message("create_room", {
		"version": version,
		"playerName": player_name,
		"gamemode": gamemode,
		"map_name": map_name,
		"max_players": max_players,
		"is_public": is_public
	})
	print("[NodeAdapter] 📤 Sent create_room request")

func join_room(room_id: String, version: String, player_name: String) -> void:
	_send_message("join_room", {
		"roomId": room_id,
		"version": version,
		"playerName": player_name
	})

func send_chat(text: String) -> void:
	_send_message("chat", {"text": text})

func load_tbw(lines: PackedStringArray) -> void:
	var lines_array: Array = []
	for line in lines:
		lines_array.append(line)
	_send_message("load_tbw", {"lines": lines_array})

func send_player_snapshot(state: Dictionary) -> void:
	_send_message("player_snapshot", state)

func kick_peer(peer_id: int) -> void:
	_send_message("kick_peer", {"peerId": peer_id})

func ban_peer(peer_id: int) -> void:
	_send_message("ban_peer", {"peerId": peer_id})

func ping() -> void:
	_send_message("ping", {})

# Cleanup
func close() -> void:
	if ws:
		ws.close()
	_is_connected = false

func get_peer_id() -> int:
	return _peer_id

func get_room_id() -> String:
	return _room_id

func is_backend_connected() -> bool:
	return _is_connected and ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN
