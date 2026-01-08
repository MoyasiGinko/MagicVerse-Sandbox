extends Node
class_name GlobalPlayMenuBackend

signal rooms_fetched(rooms: Array)
signal room_created(room_id: String, room_data: Dictionary)

@export var base_api_url: String = "http://localhost:30820/api"
var _http_rooms: HTTPRequest
var _http_create: HTTPRequest

func _ready() -> void:
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
	var url := base_api_url + "/rooms"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	var body := JSON.stringify(config)
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
		return
	var json_text: String = body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return
	var data := json.data as Dictionary
	if not data.get("success", false):
		return
	var room: Dictionary = data.get("room", {}) as Dictionary
	var room_id: String = str(room.get("id", ""))
	room_created.emit(room_id, room)
