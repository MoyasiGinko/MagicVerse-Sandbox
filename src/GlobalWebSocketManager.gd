# Global WebSocket Manager
# Maintains persistent WebSocket connection for real-time updates
# Connects on authentication, stays connected throughout session
extends Node
class_name GlobalWebSocketManager

signal rooms_list_changed
signal user_status_changed(user_id: int, is_online: bool)
signal connection_established
signal connection_lost
signal auth_handshake_accepted(user_id: int)

var ws: WebSocketPeer = null
var server_url: String = BackendConfig.get_node_ws_url()
var is_connected: bool = false
var is_socket_authenticated: bool = false
var should_reconnect: bool = false
var reconnect_timer: Timer
var heartbeat_timer: Timer

func _ready() -> void:
	# Setup reconnection timer
	reconnect_timer = Timer.new()
	add_child(reconnect_timer)
	reconnect_timer.timeout.connect(_attempt_reconnect)
	reconnect_timer.wait_time = 5.0
	reconnect_timer.one_shot = false

	# Setup heartbeat/ping timer
	heartbeat_timer = Timer.new()
	add_child(heartbeat_timer)
	heartbeat_timer.timeout.connect(_send_heartbeat)
	heartbeat_timer.wait_time = 30.0
	heartbeat_timer.one_shot = false

	print("[WSManager] Initialized")

func connect_to_server() -> void:
	"""Connect to WebSocket server with authentication"""
	server_url = BackendConfig.get_node_ws_url()
	if not Global.is_authenticated or Global.auth_token == "":
		print("[WSManager] ❌ Cannot connect - not authenticated")
		return

	if is_connected:
		print("[WSManager] ℹ️ Already connected")
		return

	print("[WSManager] 🔄 Connecting to ", server_url)
	ws = WebSocketPeer.new()
	var err: Error = ws.connect_to_url(server_url)

	if err != OK:
		push_error("[WSManager] ❌ Connection failed: " + str(err))
		_schedule_reconnect()
		return

	should_reconnect = true
	print("[WSManager] 📡 Connection initiated...")

func disconnect_from_server() -> void:
	"""Disconnect from WebSocket server"""
	print("[WSManager] 🔌 Disconnecting...")
	should_reconnect = false
	is_connected = false
	is_socket_authenticated = false

	if heartbeat_timer:
		heartbeat_timer.stop()
	if reconnect_timer:
		reconnect_timer.stop()

	if ws:
		ws.close()
		ws = null

func _process(_delta: float) -> void:
	if ws == null:
		return

	ws.poll()
	var state: WebSocketPeer.State = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			_on_connection_established()

		# Process all incoming messages
		while ws.get_available_packet_count() > 0:
			_on_message_received()

	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			_on_connection_lost()

func _on_connection_established() -> void:
	"""Handle successful connection"""
	print("[WSManager] ✅ Connected!")
	is_connected = true

	# Send authentication handshake
	_send_auth_handshake()

	# Start heartbeat
	heartbeat_timer.start()

	# Stop reconnection attempts
	reconnect_timer.stop()

	connection_established.emit()

func _on_connection_lost() -> void:
	"""Handle connection loss"""
	print("[WSManager] ❌ Connection lost")
	is_connected = false
	is_socket_authenticated = false
	heartbeat_timer.stop()

	connection_lost.emit()

	if should_reconnect:
		_schedule_reconnect()

func _schedule_reconnect() -> void:
	"""Schedule reconnection attempt"""
	if not should_reconnect:
		return
	print("[WSManager] 🔄 Will retry connection in 5 seconds...")
	reconnect_timer.start()

func _attempt_reconnect() -> void:
	"""Attempt to reconnect"""
	if is_connected:
		reconnect_timer.stop()
		return
	print("[WSManager] 🔄 Attempting reconnection...")
	connect_to_server()

func _send_auth_handshake() -> void:
	"""Send authentication handshake after connection"""
	if not is_connected or not ws:
		return

	var handshake_data: Dictionary = {
		"version": "13020",
		"name": Global.display_name,
		"token": Global.auth_token
	}

	_send_message("handshake", handshake_data)
	print("[WSManager] 🤝 Sent authentication handshake")

func _send_heartbeat() -> void:
	"""Send periodic heartbeat to keep connection alive"""
	if is_connected:
		_send_message("ping", {})

func _send_message(msg_type: String, data: Dictionary) -> void:
	"""Send message to server"""
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var message: Dictionary = {"type": msg_type, "data": data}
	var json_str: String = JSON.stringify(message)
	ws.send_text(json_str)

func _on_message_received() -> void:
	"""Handle incoming WebSocket message"""
	var packet: PackedByteArray = ws.get_packet()
	var json_str: String = packet.get_string_from_utf8()
	var json: JSON = JSON.new()

	if json.parse(json_str) != OK:
		push_error("[WSManager] Failed to parse message: " + json_str)
		return

	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return

	var msg_type: String = data.get("type", "")
	var msg_data: Dictionary = data.get("data", {})

	# Route messages to appropriate handlers
	match msg_type:
		"handshake_accepted":
			var handshake_user_id: int = int(msg_data.get("user_id", 0) as float)
			is_socket_authenticated = true
			print("[WSManager] ✅ Handshake accepted - User ID: ", handshake_user_id)
			auth_handshake_accepted.emit(handshake_user_id)

		"rooms_changed":
			print("[WSManager] 🔔 Rooms list changed")
			rooms_list_changed.emit()

		"user_online":
			var user_id: int = msg_data.get("user_id", 0)
			print("[WSManager] 👤 User ", user_id, " is now online")
			user_status_changed.emit(user_id, true)

		"user_offline":
			var user_id: int = msg_data.get("user_id", 0)
			print("[WSManager] 👤 User ", user_id, " is now offline")
			user_status_changed.emit(user_id, false)

		"pong":
			pass # Heartbeat response

		"error":
			var reason: String = msg_data.get("reason", "unknown")
			push_error("[WSManager] ❌ Server error: " + reason)

		_:
			# Unknown message type - might be handled by other systems
			pass
