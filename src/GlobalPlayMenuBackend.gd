extends Node
class_name GlobalPlayMenuBackend

signal rooms_fetched(rooms: Array)
signal room_created(room_id: String, room_data: Dictionary)
signal room_create_failed(message: String)

@export var base_api_url: String = ""
var _http_rooms: HTTPRequest
var _http_create: HTTPRequest
var _selected_server: Dictionary = {}

func _normalize_server_api_url(raw_url: String) -> String:
	var value := raw_url.strip_edges()
	while value.ends_with("/"):
		value = value.left(value.length() - 1)
	if value == "":
		return ""
	if value.ends_with("/api"):
		return value

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

func set_selected_server(server_data: Dictionary) -> void:
	_selected_server = server_data.duplicate(true)
	var selected_api := _normalize_server_api_url(str(_selected_server.get("api_url", "")))
	if selected_api != "":
		base_api_url = selected_api

func _ready() -> void:
	if base_api_url.strip_edges() == "":
		base_api_url = BackendConfig.get_node_api_base_url()
	_http_rooms = HTTPRequest.new()
	add_child(_http_rooms)
	_http_rooms.request_completed.connect(_on_rooms_response)

	_http_create = HTTPRequest.new()
	add_child(_http_create)
	_http_create.request_completed.connect(_on_create_response)

	print("[GlobalPMBackend] ✅ Ready. Base API:", base_api_url)

func fetch_rooms() -> void:
	if not Global.is_authenticated or Global.auth_token == "":
		print("[GlobalPMBackend] ❌ Not authenticated; cannot fetch rooms")
		rooms_fetched.emit([])
		return
	base_api_url = BackendConfig.get_node_api_base_url()
	var url := base_api_url + "/rooms"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	print("[GlobalPMBackend] 📤 GET rooms:", url)
	var err := _http_rooms.request(url, headers)
	if err != OK:
		print("[GlobalPMBackend] ❌ HTTP error:", err)
		rooms_fetched.emit([])

func create_room(config: Dictionary) -> void:
	if not Global.is_authenticated or Global.auth_token == "":
		print("[GlobalPMBackend] ❌ Not authenticated; cannot create room")
		return
	var selected_server_id := str(_selected_server.get("id", "")).strip_edges()
	if selected_server_id == "":
		selected_server_id = BackendConfig.get_selected_server_id().strip_edges()
	if selected_server_id == "":
		print("[GlobalPMBackend] ❌ No selected server_id; cannot create room")
		room_create_failed.emit("Select a specific server before creating a room")
		return
	var selected_api := _normalize_server_api_url(str(_selected_server.get("api_url", "")))
	if selected_api != "":
		base_api_url = selected_api
	else:
		base_api_url = BackendConfig.get_node_api_base_url()
	var url := base_api_url + "/rooms"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	var payload := config.duplicate(true)
	payload["server_id"] = selected_server_id
	var body := JSON.stringify(payload)
	print("[GlobalPMBackend] 📤 POST room:", url, " body:", body)
	var err := _http_create.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[GlobalPMBackend] ❌ HTTP error:", err)

func _on_rooms_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[GlobalPMBackend] 📥 Rooms response:", response_code, " result:", result)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		rooms_fetched.emit([])
		return
	var json_text: String = body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		rooms_fetched.emit([])
		return
	var data := json.data as Dictionary
	var rooms: Array = data.get("rooms", []) as Array
	rooms_fetched.emit(rooms)

func _on_create_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[GlobalPMBackend] 📥 Create response:", response_code, " result:", result)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var message := "Failed to create room"
		var error_text: String = body.get_string_from_utf8()
		var parsed := JSON.new()
		if parsed.parse(error_text) == OK and parsed.data is Dictionary:
			var data_dict: Dictionary = parsed.data as Dictionary
			if data_dict.has("error"):
				message = str(data_dict.get("error", message))
		print("[GlobalPMBackend] ❌ HTTP error: response_code=", response_code, " result=", result, " message=", message)
		room_create_failed.emit(message)
		return
	var json_text: String = body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		print("[GlobalPMBackend] ❌ Failed to parse JSON response")
		room_create_failed.emit("Failed to parse server response")
		return
	var data := json.data as Dictionary
	if not data.get("success", false):
		print("[GlobalPMBackend] ❌ Server responded with success=false")
		room_create_failed.emit(str(data.get("error", "Room creation failed")))
		return
	var room: Dictionary = data.get("room", {}) as Dictionary
	var room_id: String = str(room.get("id", ""))
	print("[GlobalPMBackend] ✅ Room created successfully! ID: ", room_id)
	room_created.emit(room_id, room)
