# Tinybox
# Copyright (C) 2023-present Caelan Douglas
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

extends PanelContainer
class_name GlobalServerList

signal room_selected(room_id: String)

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var list_container: VBoxContainer = $ScrollContainer/List
@export var backend_path: NodePath = NodePath("../Backend")
var backend: GlobalPlayMenuBackend
var refresh_timer: Timer
var current_rooms: Array = []
var _http_refresh: HTTPRequest  # Dedicated HTTPRequest for continuous refreshes
var ws_manager: GlobalWebSocketManager  # Reference to WebSocket manager

func _ready() -> void:
	print("[ServerList] Initializing...")
	# Resolve backend reference via exported path
	backend = get_node_or_null(backend_path) as GlobalPlayMenuBackend
	# Connect to backend rooms fetched
	if backend and backend.has_signal("rooms_fetched"):
		backend.rooms_fetched.connect(_on_rooms_fetched)
		print("[ServerList] Backend rooms_fetched signal connected")

	# Create dedicated HTTPRequest for fetching rooms on demand
	_http_refresh = HTTPRequest.new()
	add_child(_http_refresh)
	_http_refresh.request_completed.connect(_on_refresh_response)

	# Get reference to WebSocket Manager
	ws_manager = get_tree().root.get_child(0).get_node_or_null("WSManager") as GlobalWebSocketManager
	if not ws_manager:
		# Try to get it as an autoload directly
		ws_manager = get_node("/root/WSManager") as GlobalWebSocketManager

	# Connect to WebSocket Manager for real-time room updates
	if ws_manager:
		ws_manager.rooms_list_changed.connect(_on_rooms_changed_websocket)
		ws_manager.connection_established.connect(_on_websocket_connected)
		print("[ServerList] ✅ WebSocket signals connected")
	else:
		push_error("[ServerList] ❌ WSManager not found!")

	# Initial load
	if Global.is_authenticated:
		print("[ServerList] User authenticated, loading initial server list")
		refresh_server_list()
	else:
		print("[ServerList] User not authenticated yet, skipping initial load")

	print("[ServerList] Initialization complete!")

func refresh_server_list() -> void:
	"""Fetch the room list from the backend API"""
	if not Global.is_authenticated or Global.auth_token == "":
		return
	var url := "http://localhost:30820/api/rooms"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	_http_refresh.request(url, headers)

func _on_refresh_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle rooms response from direct HTTP request"""
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return
	var json_text: String = body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return
	var data := json.data as Dictionary
	var rooms: Array = data.get("rooms", []) as Array
	_on_rooms_fetched(rooms)

func _on_rooms_fetched(rooms: Array) -> void:
	"""Handle rooms fetched from backend script"""
	print("[ServerList] 📥 Received ", rooms.size(), " rooms")
	current_rooms = rooms
	_populate_server_list(rooms)

func _on_rooms_changed_websocket() -> void:
	"""Handle real-time room list changes from WebSocket"""
	print("[ServerList] 🔔 Received rooms_changed event from WebSocket")
	refresh_server_list()

func _on_websocket_connected() -> void:
	"""Handle WebSocket connection established"""
	print("[ServerList] 🔌 WebSocket connected, refreshing server list")
	refresh_server_list()

func _populate_server_list(rooms: Array) -> void:
	"""Populate the UI with rooms from the server"""
	# Clear existing list
	print("[ServerList] 🔄 Clearing old list container...")
	for child in list_container.get_children():
		child.queue_free()

	print("[ServerList] ✅ Populating with ", rooms.size(), " rooms")

	if rooms.is_empty():
		print("[ServerList] ⚠️ No rooms available, showing empty state")
		_show_empty_state()
		return

	# Create a panel for each room
	for room_data: Variant in rooms:
		var room: Dictionary = room_data as Dictionary
		var room_id: String = str(room.get("id", "?"))
		print("[ServerList] 📋 Creating entry for room: ", room_id)
		_create_room_entry(room)

func _create_room_entry(room: Dictionary) -> void:
	"""Create a UI entry for a single room"""
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(0, 60)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	container.add_child(hbox)

	# Room info (left side)
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	# Gamemode and Map
	var title_label := Label.new()
	var gamemode: String = str(room.get("gamemode", "Unknown"))
	var map_name: String = str(room.get("map_name", "Unknown Map"))
	title_label.text = "%s - %s" % [gamemode, map_name]
	print("[ServerList] 🎮 Room gamemode: ", gamemode, ", map: ", map_name)
	title_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(title_label)

	# Host info
	var host_label := Label.new()
	var host_username: String = room.get("host_username", "Unknown")
	host_label.text = "Host: %s" % host_username
	print("[ServerList] 👤 Room host: ", host_username)
	host_label.modulate = Color(1, 1, 1, 0.6)
	host_label.add_theme_font_size_override("font_size", 10)
	info_vbox.add_child(host_label)

	# Player count and status (right side)
	var status_vbox := VBoxContainer.new()
	status_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(status_vbox)

	var current_players: int = room.get("current_players", 0)
	var max_players: int = room.get("max_players", 8)
	var is_full: bool = room.get("is_full", false)

	var player_count_label := Label.new()
	player_count_label.text = "%d / %d" % [current_players, max_players]
	print("[ServerList] 👥 Room players: ", current_players, "/", max_players, " [Full: ", is_full, "]")
	player_count_label.add_theme_font_size_override("font_size", 12)

	if is_full:
		player_count_label.modulate = Color(1, 0.5, 0.5, 1)
	else:
		player_count_label.modulate = Color(0.5, 1, 0.5, 1)

	status_vbox.add_child(player_count_label)

	# Join button
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.custom_minimum_size = Vector2(60, 0)
	join_button.disabled = is_full

	var room_id: String = str(room.get("id", ""))
	print("[ServerList] 🔗 Connecting join button for room: ", room_id)
	join_button.pressed.connect(_on_room_join_clicked.bind(room_id, room))

	hbox.add_child(join_button)

	# Add to list
	print("[ServerList] ✅ Adding room entry to container")
	list_container.add_child(container)

func _show_empty_state() -> void:
	"""Show empty state when no rooms available"""
	print("[ServerList] 📭 Displaying empty state - no active rooms")
	var label := Label.new()
	label.text = "No active rooms"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 1, 1, 0.5)
	label.custom_minimum_size = Vector2(0, 100)
	list_container.add_child(label)

func _show_error_state(error_message: String) -> void:
	"""Show error state"""
	print("[ServerList] ❌ Displaying error state: ", error_message)
	for child in list_container.get_children():
		child.queue_free()

	var label := Label.new()
	label.text = "[ERROR] %s" % error_message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 0.5, 0.5, 0.8)
	label.custom_minimum_size = Vector2(0, 100)
	list_container.add_child(label)
	print("[ServerList] ❌ Error message displayed to user: ", error_message)

func _on_room_join_clicked(room_id: String, room: Dictionary) -> void:
	"""Handle room join button click"""
	var gamemode: String = room.get("gamemode", "Unknown") as String
	var map: String = room.get("map_name", "Unknown") as String
	var host: String = room.get("host_username", "Unknown") as String
	var current_players: int = room.get("current_players", 0) as int
	var max_players: int = room.get("max_players", 8) as int
	print("[ServerList] 🎯 JOIN BUTTON CLICKED for room: ", room_id)
	print("[ServerList] 📥 Room details: Gamemode=", gamemode, " Map=", map, " Host=", host)
	print("[ServerList] 👥 Players: ", current_players, "/", max_players)
	print("[ServerList] 📤 Emitting room_selected signal with ID: ", room_id)
	room_selected.emit(room_id)
	print("[ServerList] ✅ room_selected signal emitted successfully")

func get_room_by_id(room_id: String) -> Dictionary:
	"""Get room data by ID"""
	for room: Variant in current_rooms:
		var room_dict: Dictionary = room as Dictionary
		if str(room_dict.get("id", "")) == room_id:
			return room_dict
	return {}
