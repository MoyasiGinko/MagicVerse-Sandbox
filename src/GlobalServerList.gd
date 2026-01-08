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
var room_list_http: HTTPRequest
var refresh_timer: Timer
var current_rooms: Array = []

func _ready() -> void:
	# Setup HTTP request
	room_list_http = HTTPRequest.new()
	add_child(room_list_http)
	room_list_http.request_completed.connect(_on_room_list_received)

	# Setup auto-refresh timer (5 seconds)
	refresh_timer = Timer.new()
	add_child(refresh_timer)
	refresh_timer.timeout.connect(refresh_server_list)
	refresh_timer.wait_time = 5.0
	refresh_timer.autostart = false

	# Initial load
	if Global.is_authenticated:
		refresh_server_list()

func start_refresh() -> void:
	"""Start auto-refreshing the server list"""
	print("[ServerList] Starting auto-refresh")
	refresh_server_list()
	refresh_timer.start()

func stop_refresh() -> void:
	"""Stop auto-refreshing the server list"""
	print("[ServerList] Stopping auto-refresh")
	refresh_timer.stop()

func refresh_server_list() -> void:
	"""Fetch the room list from the backend API"""
	if not Global.is_authenticated or Global.auth_token == "":
		print("[ServerList] Not authenticated, skipping refresh")
		return

	var url: String = "http://localhost:30820/api/rooms"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]

	print("[ServerList] Fetching server list from: ", url)
	var error := room_list_http.request(url, headers)
	if error != OK:
		print("[ServerList] HTTP Request failed with error: ", error)

func _on_room_list_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle server list response from API"""
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[ServerList] Request failed with result: ", result)
		_show_error_state("Connection Failed")
		return

	if response_code < 200 or response_code >= 300:
		print("[ServerList] Bad response code: ", response_code)
		_show_error_state("Server Error: %d" % response_code)
		return

	var json_string := body.get_string_from_utf8()
	var json := JSON.new()
	var parse_error := json.parse(json_string)

	if parse_error != OK:
		print("[ServerList] JSON parse error at line ", json.get_error_line(), ": ", json.get_error_message())
		_show_error_state("Invalid Response")
		return

	var data: Dictionary = json.data
	if not data.has("rooms"):
		print("[ServerList] Response missing 'rooms' field")
		_show_error_state("Invalid Response")
		return

	var rooms: Array = data.get("rooms", []) as Array
	current_rooms = rooms
	_populate_server_list(rooms)

func _populate_server_list(rooms: Array) -> void:
	"""Populate the UI with rooms from the server"""
	# Clear existing list
	for child in list_container.get_children():
		child.queue_free()

	print("[ServerList] Populating with ", rooms.size(), " rooms")

	if rooms.is_empty():
		_show_empty_state()
		return

	# Create a panel for each room
	for room_data: Variant in rooms:
		var room: Dictionary = room_data as Dictionary
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
	var gamemode: String = room.get("gamemode", "Unknown")
	var map_name: String = room.get("map_name", "Unknown Map")
	title_label.text = "%s - %s" % [gamemode, map_name]
	title_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(title_label)

	# Host info
	var host_label := Label.new()
	var host_username: String = room.get("host_username", "Unknown")
	host_label.text = "Host: %s" % host_username
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
	join_button.pressed.connect(_on_room_join_clicked.bind(room_id, room))

	hbox.add_child(join_button)

	# Add to list
	list_container.add_child(container)

func _show_empty_state() -> void:
	"""Show empty state when no rooms available"""
	var label := Label.new()
	label.text = "No active rooms"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 1, 1, 0.5)
	label.custom_minimum_size = Vector2(0, 100)
	list_container.add_child(label)

func _show_error_state(error_message: String) -> void:
	"""Show error state"""
	for child in list_container.get_children():
		child.queue_free()

	var label := Label.new()
	label.text = "[ERROR] %s" % error_message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 0.5, 0.5, 0.8)
	label.custom_minimum_size = Vector2(0, 100)
	list_container.add_child(label)
	print("[ServerList] Error: ", error_message)

func _on_room_join_clicked(room_id: String, room: Dictionary) -> void:
	"""Handle room join button click"""
	print("[ServerList] Joining room: ", room_id)
	room_selected.emit(room_id)
	# TODO: Implement WebSocket connection and room joining

func get_room_by_id(room_id: String) -> Dictionary:
	"""Get room data by ID"""
	for room: Variant in current_rooms:
		var room_dict: Dictionary = room as Dictionary
		if str(room_dict.get("id", "")) == room_id:
			return room_dict
	return {}
