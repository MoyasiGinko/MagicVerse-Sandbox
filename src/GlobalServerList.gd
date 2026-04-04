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

signal room_selected(room_id: String, room_data: Dictionary)

var scroll_container: ScrollContainer
var list_container: VBoxContainer
var refresh_button: Button
@export var backend_path: NodePath = NodePath("../Backend")
var backend: GlobalPlayMenuBackend
var refresh_timer: Timer
var current_rooms: Array = []
var _http_refresh: HTTPRequest  # Dedicated HTTPRequest for continuous refreshes
var _http_all_registry: HTTPRequest
var ws_manager: GlobalWebSocketManager  # Reference to WebSocket manager
var _last_join_click_time_ms: int = 0
var _last_join_room_id: String = ""
var _join_in_progress: bool = false
var _scope_mode: String = "all"
var _selected_server: Dictionary = {}
var _rooms_request_in_flight: bool = false
var _registry_request_in_flight: bool = false
var _pending_rooms_refresh: bool = false
var _pending_registry_refresh: bool = false
var _active_specific_server_id: String = ""
var _requested_specific_server_id: String = ""
var _active_registry_scope: String = ""
const JOIN_CLICK_DEBOUNCE_MS: int = 2000
const REALTIME_REFRESH_INTERVAL_SEC: float = 2.0

func _normalize_server_api_url(raw_url: String) -> String:
	var value := raw_url.strip_edges()
	while value.ends_with("/"):
		value = value.left(value.length() - 1)
	if value == "":
		return ""
	if value.ends_with("/api"):
		return value

	# Some registry entries may provide only the host URL; rooms endpoint expects API base.
	var scheme_pos := value.find("://")
	if scheme_pos == -1:
		return value
	var host_start := scheme_pos + 3
	var path_start := value.find("/", host_start)
	if path_start == -1:
		return value + "/api"

	var path := value.substr(path_start, value.length() - path_start)
	if path == "":
		return value + "/api"
	if path.begins_with("/api"):
		return value
	return value

func _variant_to_int(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return value as int
	if value is bool:
		return 1 if (value as bool) else 0
	if value is float:
		return int(value as float)
	return fallback

func _extract_room_server_id(room: Dictionary) -> String:
	var direct_keys: Array[String] = ["server_id", "serverId", "game_server_id", "gameServerId", "node_server_id", "nodeServerId"]
	for key: String in direct_keys:
		if room.has(key):
			var value := str(room.get(key, "")).strip_edges()
			if value != "":
				return value
	var server_meta: Variant = room.get("server", null)
	if server_meta is Dictionary:
		var server_dict := server_meta as Dictionary
		var nested := str(server_dict.get("id", "")).strip_edges()
		if nested != "":
			return nested
	return ""

func _ready() -> void:
	print("[ServerList] Initializing...")

	# Find scroll container and list - handle both old standalone and new embedded layout
	if has_node("MainVBox/ScrollContainer"):
		# New embedded layout (MultiplayerMenu)
		scroll_container = get_node("MainVBox/ScrollContainer") as ScrollContainer
		list_container = get_node("MainVBox/ScrollContainer/List") as VBoxContainer
		refresh_button = get_node("MainVBox/RefreshButton") as Button
	elif has_node("VBoxContainer/ScrollContainer"):
		# Standalone scene layout
		scroll_container = get_node("VBoxContainer/ScrollContainer") as ScrollContainer
		list_container = get_node("VBoxContainer/ScrollContainer/List") as VBoxContainer
		refresh_button = get_node("VBoxContainer/RefreshButton") as Button
	else:
		# Legacy layout (fallback)
		scroll_container = get_node_or_null("ScrollContainer") as ScrollContainer
		list_container = get_node_or_null("ScrollContainer/List") as VBoxContainer
		if not list_container:
			push_error("[ServerList] ❌ Could not find List container!")
			return

	# Resolve backend reference via exported path
	backend = get_node_or_null(backend_path) as GlobalPlayMenuBackend
	# Connect to backend rooms fetched
	if backend and backend.has_signal("rooms_fetched"):
		backend.rooms_fetched.connect(_on_backend_rooms_fetched)
		print("[ServerList] Backend rooms_fetched signal connected")

	# Live capacity banner for selected scope/server.
	_ensure_capacity_banner()

	# Create dedicated HTTPRequest for fetching rooms on demand
	_http_refresh = HTTPRequest.new()
	add_child(_http_refresh)
	_http_refresh.request_completed.connect(_on_refresh_response)

	_http_all_registry = HTTPRequest.new()
	add_child(_http_all_registry)
	_http_all_registry.request_completed.connect(_on_all_registry_response)

	# Periodic fallback refresh keeps list state fresh even if a WS event is missed.
	refresh_timer = Timer.new()
	add_child(refresh_timer)
	refresh_timer.wait_time = REALTIME_REFRESH_INTERVAL_SEC
	refresh_timer.one_shot = false
	refresh_timer.timeout.connect(_on_realtime_refresh_tick)
	refresh_timer.start()

	# Connect refresh button if it exists
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_button_pressed)
		print("[ServerList] 🔘 Refresh button connected")

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
		set_all_servers_mode()
		refresh_server_list()
	else:
		print("[ServerList] User not authenticated yet, skipping initial load")

	print("[ServerList] Initialization complete!")

func refresh_server_list() -> void:
	"""Fetch the room list from the backend API"""
	if not Global.is_authenticated or Global.auth_token == "":
		return
	var selected_id := str(_selected_server.get("id", ""))
	var selected_api := _normalize_server_api_url(str(_selected_server.get("api_url", "")))
	print("[ServerList] 🔄 refresh_server_list mode=", _scope_mode, " selected_id=", selected_id, " selected_api=", selected_api)
	if _scope_mode == "all":
		_set_capacity_text("Loading...", Color(1, 1, 1, 0.7))
		_fetch_all_servers_rooms()
		return

	var server_api := _normalize_server_api_url(str(_selected_server.get("api_url", "")))
	if server_api == "":
		server_api = _normalize_server_api_url(BackendConfig.get_node_api_base_url())
	_requested_specific_server_id = str(_selected_server.get("id", ""))

	var url := server_api + "/rooms"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	if _rooms_request_in_flight:
		_pending_rooms_refresh = true
		return
	var err := _http_refresh.request(url, headers)
	if err == OK:
		_rooms_request_in_flight = true
		_pending_rooms_refresh = false
		_active_specific_server_id = _requested_specific_server_id
		_set_capacity_text("Loading...", Color(1, 1, 1, 0.7))
		return
	if err == ERR_BUSY:
		_pending_rooms_refresh = true
		return
	print("[ServerList] ❌ Specific refresh request failed: ", err, " url=", url)

func set_all_servers_mode() -> void:
	_scope_mode = "all"
	_selected_server = {}
	_active_specific_server_id = ""
	_set_capacity_text("All servers", Color(1, 1, 1, 0.7))

func set_specific_server_mode(server_data: Dictionary) -> void:
	_scope_mode = "specific"
	_selected_server = server_data.duplicate(true)
	_pending_registry_refresh = false
	_active_registry_scope = ""
	# Clear stale entries immediately so previous scope/server rooms are not shown.
	current_rooms.clear()
	_populate_server_list([])
	_set_capacity_text("Loading...", Color(1, 1, 1, 0.7))

func is_all_servers_mode() -> bool:
	return _scope_mode == "all"

func _fetch_all_servers_rooms() -> void:
	var url := BackendConfig.get_django_api_base_url() + "/game-servers"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	if _registry_request_in_flight:
		_pending_registry_refresh = true
		return
	var err := _http_all_registry.request(url, headers)
	if err == OK:
		_registry_request_in_flight = true
		_pending_registry_refresh = false
		_active_registry_scope = _scope_mode
		return
	if err == ERR_BUSY:
		# Another refresh request is still running; do not show a false error state.
		_pending_registry_refresh = true
		return
	if err != OK:
		_show_error_state("Could not fetch server registry")

func _fetch_rooms_for_server(server_data: Dictionary) -> Dictionary:
	var api_url := _normalize_server_api_url(str(server_data.get("api_url", "")))
	if api_url == "":
		return {
			"rooms": [],
			"server_capacity": {},
		}

	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(api_url + "/rooms", headers)
	if err != OK:
		req.queue_free()
		return {
			"rooms": [],
			"server_capacity": {},
		}

	var result_data: Array = await req.request_completed
	req.queue_free()
	if result_data.size() < 4:
		return {
			"rooms": [],
			"server_capacity": {},
		}

	var result: int = _variant_to_int(result_data[0], HTTPRequest.RESULT_CANT_CONNECT)
	var response_code: int = _variant_to_int(result_data[1], 0)
	var body := result_data[3] as PackedByteArray
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return {
			"rooms": [],
			"server_capacity": {},
		}

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return {
			"rooms": [],
			"server_capacity": {},
		}

	var payload := json.data as Dictionary
	var rooms := payload.get("rooms", []) as Array
	var capacity: Variant = payload.get("server_capacity", {})
	var capacity_dict: Dictionary = {}
	if capacity is Dictionary:
		capacity_dict = (capacity as Dictionary).duplicate(true)
	var merged: Array = []
	var expected_server_id := str(server_data.get("id", "")).strip_edges()
	for room_value: Variant in rooms:
		if not (room_value is Dictionary):
			continue
		var room := (room_value as Dictionary).duplicate(true)
		var room_server_id := _extract_room_server_id(room)
		if expected_server_id != "" and room_server_id != "" and room_server_id != expected_server_id:
			continue
		room["server"] = server_data
		if expected_server_id != "" and not room.has("server_id"):
			room["server_id"] = expected_server_id
		merged.append(room)
	return {
		"rooms": merged,
		"server_capacity": capacity_dict,
	}

func _on_all_registry_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _active_registry_scope != "all" or _scope_mode != "all":
		_registry_request_in_flight = false
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_registry_request_in_flight = false
		_show_error_state("Could not load server registry")
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		_registry_request_in_flight = false
		_show_error_state("Invalid server registry response")
		return

	var payload := json.data as Dictionary
	var servers := payload.get("servers", []) as Array
	await _load_all_rooms_from_servers(servers)
	_registry_request_in_flight = false
	if _pending_registry_refresh and _scope_mode == "all":
		_pending_registry_refresh = false
		call_deferred("_fetch_all_servers_rooms")

func _load_all_rooms_from_servers(servers: Array) -> void:
	if _scope_mode != "all":
		return

	var all_rooms: Array = []
	var aggregated_current_rooms: int = 0
	var aggregated_max_rooms: int = 0
	var has_known_max: bool = false
	var seen_server_ids: Dictionary = {}
	for server_value: Variant in servers:
		if _scope_mode != "all":
			return
		if not (server_value is Dictionary):
			continue
		var server_data := server_value as Dictionary
		var server_id := str(server_data.get("id", "")).strip_edges()
		if server_id != "":
			if seen_server_ids.has(server_id):
				continue
			seen_server_ids[server_id] = true
		var fetch_result: Dictionary = await _fetch_rooms_for_server(server_data)
		var rooms_for_server: Array = fetch_result.get("rooms", []) as Array
		var capacity: Variant = fetch_result.get("server_capacity", {})
		if capacity is Dictionary:
			var capacity_dict := capacity as Dictionary
			aggregated_current_rooms += _variant_to_int(capacity_dict.get("current_rooms", 0), 0)
			var max_for_server := _variant_to_int(capacity_dict.get("max_rooms", -1), -1)
			if max_for_server >= 0:
				has_known_max = true
				aggregated_max_rooms += max_for_server
		for room_value: Variant in rooms_for_server:
			all_rooms.append(room_value)

	if has_known_max:
		_set_capacity_text(
			"%d/%d (all servers)" % [aggregated_current_rooms, aggregated_max_rooms],
			Color(1, 1, 1, 0.8),
		)
	else:
		_set_capacity_text(
			"%d (all servers)" % [aggregated_current_rooms],
			Color(1, 1, 1, 0.8),
		)

	if _scope_mode == "all":
		_on_rooms_fetched(all_rooms)

func _on_refresh_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle rooms response from direct HTTP request"""
	_rooms_request_in_flight = false
	if _scope_mode != "specific":
		if _pending_rooms_refresh:
			_pending_rooms_refresh = false
			call_deferred("refresh_server_list")
		return

	var selected_server_id_now := str(_selected_server.get("id", ""))

	var stale_response := false
	if _active_specific_server_id != "" and selected_server_id_now != "" and selected_server_id_now != _active_specific_server_id:
		stale_response = true

	if stale_response:
		# Ignore stale response from previous specific-server selection.
		if _pending_rooms_refresh:
			_pending_rooms_refresh = false
		call_deferred("refresh_server_list")
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		print("[ServerList] ⚠️ Specific refresh response failed: result=", result, " code=", response_code, " active_server_id=", _active_specific_server_id)
		if _pending_rooms_refresh:
			_pending_rooms_refresh = false
			call_deferred("refresh_server_list")
		return
	var json_text: String = body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		print("[ServerList] ⚠️ Failed to parse rooms response as JSON. active_server_id=", _active_specific_server_id)
		if _pending_rooms_refresh:
			_pending_rooms_refresh = false
			call_deferred("refresh_server_list")
		return
	var data := json.data as Dictionary
	var rooms: Array = data.get("rooms", []) as Array
	var filtered_rooms: Array = []
	var selected_server_id := str(_selected_server.get("id", "")).strip_edges()
	for room_value: Variant in rooms:
		if not (room_value is Dictionary):
			continue
		var room := (room_value as Dictionary).duplicate(true)
		var room_server_id := _extract_room_server_id(room)
		if selected_server_id != "" and room_server_id != "" and room_server_id != selected_server_id:
			continue
		if _selected_server.size() > 0:
			room["server"] = _selected_server.duplicate(true)
		if selected_server_id != "" and not room.has("server_id"):
			room["server_id"] = selected_server_id
		filtered_rooms.append(room)
	var server_capacity: Variant = data.get("server_capacity", {})
	if server_capacity is Dictionary:
		var cap := server_capacity as Dictionary
		var current_rooms := _variant_to_int(cap.get("current_rooms", filtered_rooms.size()), filtered_rooms.size())
		var max_rooms := _variant_to_int(cap.get("max_rooms", -1), -1)
		if max_rooms >= 0:
			_set_capacity_text("%d/%d" % [current_rooms, max_rooms], Color(1, 1, 1, 0.8))
		else:
			_set_capacity_text("%d" % [current_rooms], Color(1, 1, 1, 0.8))
	else:
		_set_capacity_text("%d" % [filtered_rooms.size()], Color(1, 1, 1, 0.8))
	_on_rooms_fetched(filtered_rooms)
	if _pending_rooms_refresh:
		_pending_rooms_refresh = false
		call_deferred("refresh_server_list")

func _on_rooms_fetched(rooms: Array) -> void:
	"""Handle rooms fetched from backend script"""
	var sorted_rooms: Array = rooms.duplicate(true) as Array
	sorted_rooms.sort_custom(_sort_room_by_fill_desc)
	print("[ServerList] 📥 Received ", sorted_rooms.size(), " rooms")
	current_rooms = sorted_rooms
	_populate_server_list(sorted_rooms)

func _on_backend_rooms_fetched(rooms: Array) -> void:
	# Room list updates are scope-aware via dedicated HTTP requests in this class.
	# Ignore legacy backend push updates to avoid cross-server room bleed.
	return

func _sort_room_by_fill_desc(a: Variant, b: Variant) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false

	var room_a := a as Dictionary
	var room_b := b as Dictionary
	var current_a: int = _variant_to_int(room_a.get("current_players", 0), 0)
	var current_b: int = _variant_to_int(room_b.get("current_players", 0), 0)
	if current_a != current_b:
		return current_a > current_b

	var max_a: int = max(_variant_to_int(room_a.get("max_players", 1), 1), 1)
	var max_b: int = max(_variant_to_int(room_b.get("max_players", 1), 1), 1)
	var ratio_a: float = float(current_a) / float(max_a)
	var ratio_b: float = float(current_b) / float(max_b)
	if ratio_a != ratio_b:
		return ratio_a > ratio_b

	return str(room_a.get("id", "")) < str(room_b.get("id", ""))

func _on_rooms_changed_websocket() -> void:
	"""Handle real-time room list changes from WebSocket"""
	print("[ServerList] 🔔 Received rooms_changed event from WebSocket")
	refresh_server_list()

func _on_websocket_connected() -> void:
	"""Handle WebSocket connection established"""
	print("[ServerList] 🔌 WebSocket connected, refreshing server list")
	refresh_server_list()

func _on_refresh_button_pressed() -> void:
	"""Handle manual refresh button press"""
	print("[ServerList] 🔘 Manual refresh button pressed")
	refresh_server_list()

func _on_realtime_refresh_tick() -> void:
	"""Fallback real-time refresh while menu list is visible."""
	if not is_visible_in_tree():
		return
	if not Global.is_authenticated or Global.auth_token == "":
		return
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

	var current_players: int = _variant_to_int(room.get("current_players", 0), 0)
	var max_players: int = max(_variant_to_int(room.get("max_players", 8), 8), 1)
	var is_full_value: Variant = room.get("is_full", false)
	var is_full: bool = false
	if is_full_value is bool:
		is_full = is_full_value as bool
	elif is_full_value is int:
		is_full = (is_full_value as int) != 0
	elif is_full_value is float:
		is_full = (is_full_value as float) != 0.0
	else:
		is_full = current_players >= max_players

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
	join_button.set_meta("room_is_full", is_full)
	join_button.disabled = is_full or _join_in_progress

	var room_id: String = str(room.get("id", ""))
	print("[ServerList] 🔗 Connecting join button for room: ", room_id)
	join_button.pressed.connect(_on_room_join_clicked.bind(room_id, room))

	hbox.add_child(join_button)

	# Add to list
	print("[ServerList] ✅ Adding room entry to container")
	list_container.add_child(container)

func set_join_in_progress(in_progress: bool) -> void:
	"""Enable/disable room join actions while a join attempt is active."""
	_join_in_progress = in_progress
	_refresh_join_buttons_state()

func _refresh_join_buttons_state() -> void:
	"""Apply current join lock state to all visible join buttons."""
	if not list_container:
		return

	for entry: Node in list_container.get_children():
		if not (entry is PanelContainer):
			continue
		var hbox: HBoxContainer = entry.get_child(0) as HBoxContainer
		if not hbox:
			continue
		var join_button: Button = hbox.get_child(hbox.get_child_count() - 1) as Button
		if not join_button:
			continue
		var is_full_meta: Variant = join_button.get_meta("room_is_full", false)
		var is_full: bool = false
		if is_full_meta is bool:
			is_full = is_full_meta as bool
		elif is_full_meta is int:
			is_full = (is_full_meta as int) != 0
		elif is_full_meta is float:
			is_full = (is_full_meta as float) != 0.0
		join_button.disabled = _join_in_progress or is_full

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
	_set_capacity_text("Unavailable", Color(1, 0.6, 0.6, 0.9))

func _ensure_capacity_banner() -> void:
	# Capacity banner intentionally disabled: no text should be shown in this area.
	return

func _set_capacity_text(text: String, tint: Color = Color(1, 1, 1, 0.7)) -> void:
	# Capacity banner intentionally disabled: ignore all text updates.
	return

func _on_room_join_clicked(room_id: String, room: Dictionary) -> void:
	"""Handle room join button click"""
	if _join_in_progress:
		print("[ServerList] ⏳ Join is currently in progress; ignoring click for room: ", room_id)
		return

	var now_ms: int = Time.get_ticks_msec()
	if _last_join_room_id == room_id and (now_ms - _last_join_click_time_ms) < JOIN_CLICK_DEBOUNCE_MS:
		print("[ServerList] ⏳ Ignoring duplicate join click for room: ", room_id)
		return

	_last_join_room_id = room_id
	_last_join_click_time_ms = now_ms

	if room.has("server") and room.get("server") is Dictionary:
		var server_data: Dictionary = room.get("server") as Dictionary
		BackendConfig.set_selected_game_server(server_data)
	var gamemode: String = room.get("gamemode", "Unknown") as String
	var map: String = room.get("map_name", "Unknown") as String
	var host: String = room.get("host_username", "Unknown") as String
	var current_players: int = room.get("current_players", 0) as int
	var max_players: int = room.get("max_players", 8) as int
	print("[ServerList] 🎯 JOIN BUTTON CLICKED for room: ", room_id)
	print("[ServerList] 📥 Room details: Gamemode=", gamemode, " Map=", map, " Host=", host)
	print("[ServerList] 👥 Players: ", current_players, "/", max_players)
	print("[ServerList] 📤 Emitting room_selected signal with ID: ", room_id)
	room_selected.emit(room_id, room)
	print("[ServerList] ✅ room_selected signal emitted successfully")

func get_room_by_id(room_id: String) -> Dictionary:
	"""Get room data by ID"""
	for room: Variant in current_rooms:
		var room_dict: Dictionary = room as Dictionary
		if str(room_dict.get("id", "")) == room_id:
			return room_dict
	return {}
