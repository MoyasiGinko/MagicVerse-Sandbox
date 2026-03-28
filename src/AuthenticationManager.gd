extends Node
class_name AuthenticationManager

# Signals
signal authentication_complete(token: String, username: String)
signal authentication_failed(reason: String)
signal verification_complete(is_valid: bool)

enum RequestType {
	NONE,
	REGISTER,
	LOGIN,
	VERIFY,
	UPDATE_DISPLAY_NAME
}

# Backend URL
var backend_url := BackendConfig.get_django_base_url()
var http_request: HTTPRequest = null
var config_request: HTTPRequest = null
var ws_manager: GlobalWebSocketManager  # Reference to WebSocket manager
var current_request_type: RequestType = RequestType.NONE

# Token storage
const TOKEN_SAVE_PATH := "user://tinybox_token.json"

func _ready() -> void:
	backend_url = BackendConfig.get_django_base_url()
	_ensure_runtime_dependencies()
	_fetch_dynamic_client_config()

func _ensure_runtime_dependencies() -> void:
	# Create HTTPRequest node for making requests
	if http_request == null:
		http_request = HTTPRequest.new()
		add_child(http_request)
	if not http_request.request_completed.is_connected(_on_http_request_completed):
		http_request.request_completed.connect(_on_http_request_completed)

	if config_request == null:
		config_request = HTTPRequest.new()
		add_child(config_request)
	if not config_request.request_completed.is_connected(_on_client_config_request_completed):
		config_request.request_completed.connect(_on_client_config_request_completed)

	# Get reference to WebSocket Manager
	if ws_manager == null:
		ws_manager = get_node_or_null("/root/WSManager") as GlobalWebSocketManager

func _fetch_dynamic_client_config() -> void:
	if config_request == null:
		return
	var url: String = BackendConfig.get_client_config_url()
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"User-Agent: Godot/4.0 (Tinybox)"
	])
	var err: int = config_request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		print("[AuthMgr] Failed to request dynamic client config: ", err)

func _on_client_config_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if response_code < 200 or response_code >= 300:
		return

	var response_text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if not (parsed is Dictionary):
		return

	var payload: Dictionary = parsed as Dictionary
	if not payload.get("success", false):
		return

	if payload.has("config") and payload.get("config") is Dictionary:
		BackendConfig.apply_client_config(payload.get("config") as Dictionary)
		backend_url = BackendConfig.get_django_base_url()
		print("[AuthMgr] Applied dynamic client config from server")

## Register a new user
func register_user(username: String, email: String, password: String) -> void:
	if not _validate_inputs(username, email, password):
		authentication_failed.emit("Invalid input")
		return

	var body: Dictionary = {
		"username": username,
		"email": email,
		"password": password
	}

	current_request_type = RequestType.REGISTER
	_make_request("POST", "/api/auth/register", body)

## Login existing user
func login_user(username: String, password: String) -> void:
	if not username or not password:
		authentication_failed.emit("Username and password required")
		return

	var body: Dictionary = {
		"username": username,
		"password": password
	}

	current_request_type = RequestType.LOGIN
	_make_request("POST", "/api/auth/login", body)

## Verify saved token
func verify_token(token: String) -> void:
	var headers: Array = [
		"Authorization: Bearer " + token
	]

	current_request_type = RequestType.VERIFY
	_make_request("GET", "/api/auth/verify", {}, headers)

## Load token from disk
func load_saved_token() -> String:
	_ensure_runtime_dependencies()
	if ResourceLoader.exists(TOKEN_SAVE_PATH):
		var file: FileAccess = FileAccess.open(TOKEN_SAVE_PATH, FileAccess.READ)
		if file:
			var json: JSON = JSON.new()
			var data: Variant = json.parse_string(file.get_as_text())
			if data and data.has("token"):
				var token: String = data["token"]
				# Load all saved data into Global
				Global.auth_token = token
				if data.has("username"):
					Global.player_username = data["username"]
				if data.has("display_name"):
					Global.player_display_name = data["display_name"]
					Global.display_name = data["display_name"]
				else:
					var username: String = data.get("username", "")
					Global.player_display_name = username
					Global.display_name = username
				Global.is_authenticated = true
				# Connect to WebSocket for real-time updates
				if ws_manager:
					ws_manager.connect_to_server()
				return token
	return ""
## Save token to disk
func save_token(token: String, username: String, display_name: String = "") -> void:
	_ensure_runtime_dependencies()
	var data: Dictionary = {
		"token": token,
		"username": username,
		"display_name": display_name if display_name else username,
		"timestamp": Time.get_ticks_msec()
	}

	var file: FileAccess = FileAccess.open(TOKEN_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

	# Also save to Global singleton
	Global.auth_token = token
	Global.player_username = username
	Global.player_display_name = display_name if display_name else username
	Global.display_name = Global.player_display_name
	# Connect to WebSocket for real-time updates
	if ws_manager:
		ws_manager.connect_to_server()

## Clear saved token
func clear_saved_token() -> void:
	_ensure_runtime_dependencies()
	if ResourceLoader.exists(TOKEN_SAVE_PATH):
		DirAccess.remove_absolute(TOKEN_SAVE_PATH)
	Global.auth_token = ""
	Global.player_username = ""
	Global.player_display_name = ""
	Global.display_name = ""
	# Disconnect WebSocket
	if ws_manager:
		ws_manager.disconnect_from_server()

## Private helper to make HTTP requests
func _make_request(method: String, endpoint: String, body: Dictionary = {}, headers: Array = []) -> void:
	_ensure_runtime_dependencies()
	var url: String = backend_url + endpoint
	var request_headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"User-Agent: Godot/4.0 (Tinybox)"
	])

	# Add custom headers
	for header: String in headers:
		request_headers.append(header)

	var request_body: String = JSON.stringify(body) if body else ""

	# Convert method string to HTTPClient enum
	var http_method: HTTPClient.Method = HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET

	print("Making request to: ", url)
	print("Method: ", method)
	print("Body: ", request_body)

	var error: int = http_request.request(url, request_headers, http_method, request_body)

	if error != OK:
		print("HTTP Request error: ", error)
		if current_request_type == RequestType.VERIFY:
			verification_complete.emit(false)
		else:
			authentication_failed.emit("Request failed: " + str(error))
		current_request_type = RequestType.NONE
		return

## Handle HTTP response
func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("HTTP Response - Code: ", response_code, " Result: ", result)

	if result != HTTPRequest.RESULT_SUCCESS:
		print("Request failed with result: ", result)
		if current_request_type == RequestType.VERIFY:
			verification_complete.emit(false)
		else:
			authentication_failed.emit("Network error")
		current_request_type = RequestType.NONE
		return

	# Accept 2xx status codes (200-299) as success
	if response_code < 200 or response_code >= 300:
		print("Server returned error code: ", response_code)
		var error_text: String = body.get_string_from_utf8()
		print("Error response: ", error_text)

		# Try to parse error from response
		var json: JSON = JSON.new()
		var response_data: Variant = json.parse_string(error_text)
		if current_request_type == RequestType.VERIFY:
			verification_complete.emit(false)
		elif response_data and response_data.has("error"):
			authentication_failed.emit(response_data["error"])
		else:
			if current_request_type == RequestType.VERIFY:
				verification_complete.emit(false)
			else:
				authentication_failed.emit("Server error: " + str(response_code))
		current_request_type = RequestType.NONE
		return

	var response_text: String = body.get_string_from_utf8()
	print("Response body: ", response_text)

	var json: JSON = JSON.new()
	var response_data: Variant = json.parse_string(response_text)

	if not response_data:
		print("Failed to parse response")
		if current_request_type == RequestType.VERIFY:
			verification_complete.emit(false)
		else:
			authentication_failed.emit("Invalid response format")
		current_request_type = RequestType.NONE
		return

	print("Parsed response: ", response_data)

	# Determine which endpoint this was for based on the response structure
	if response_data.has("token") and response_data.has("user"):
		# Register or Login response
		var token: String = response_data["token"]
		var username: String = response_data["user"]["username"]
		var display_name: String = response_data["user"].get("display_name", username)
		save_token(token, username, display_name)
		authentication_complete.emit(token, username)
	elif response_data.has("valid"):
		# Verify token response
		if response_data["valid"] and response_data.has("user"):
			var v_user: Dictionary = response_data["user"]
			Global.player_username = v_user.get("username", Global.player_username)
			Global.player_display_name = v_user.get("display_name", Global.player_username)
			Global.display_name = Global.player_display_name
		verification_complete.emit(response_data["valid"])
	elif response_data.has("success") and response_data.has("user") and response_data["user"].has("display_name"):
		# Display name update response
		print("[AuthMgr] Received display name update response")
		var new_display_name: String = response_data["user"]["display_name"]
		Global.player_display_name = new_display_name
		Global.display_name = new_display_name
		# Update saved token with new display name
		save_token(Global.auth_token, Global.player_username, new_display_name)
		print("[AuthMgr] Display name updated to: ", new_display_name)
	else:
		print("Unexpected response structure")
		if current_request_type == RequestType.VERIFY:
			verification_complete.emit(false)
		else:
			authentication_failed.emit("Unexpected server response")

	current_request_type = RequestType.NONE

## Validate registration inputs
func _validate_inputs(username: String, email: String, password: String) -> bool:
	# Username: 3-20 chars, alphanumeric + underscore
	if username.length() < 3 or username.length() > 20:
		return false

	if not username.is_valid_identifier():
		return false

	# Email validation
	if "@" not in email or "." not in email:
		return false

	# Password minimum 8 chars
	if password.length() < 8:
		return false

	return true

## Update display name
func update_display_name(new_display_name: String) -> void:
	print("[AuthMgr] update_display_name called with: ", new_display_name)
	print("[AuthMgr] Auth token exists: ", Global.auth_token != "")

	if not Global.auth_token:
		print("[AuthMgr] ERROR: Not authenticated")
		authentication_failed.emit("Not authenticated")
		return

	if new_display_name.length() < 1 or new_display_name.length() > 30:
		print("[AuthMgr] ERROR: Display name length invalid")
		authentication_failed.emit("Display name must be 1-30 characters")
		return

	var body: Dictionary = {
		"display_name": new_display_name
	}

	var headers: Array = [
		"Authorization: Bearer " + Global.auth_token
	]

	print("[AuthMgr] Sending PUT request to update display name")
	current_request_type = RequestType.UPDATE_DISPLAY_NAME
	_make_request_with_method("PUT", "/api/users/display-name", body, headers)

func _make_request_with_method(method: String, endpoint: String, body: Dictionary = {}, headers: Array = []) -> void:
	_ensure_runtime_dependencies()
	var url: String = backend_url + endpoint
	var request_headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"User-Agent: Godot/4.0 (Tinybox)"
	])

	# Add custom headers
	for header: String in headers:
		request_headers.append(header)

	var request_body: String = JSON.stringify(body) if body else ""

	# Convert method string to HTTPClient enum
	var http_method: HTTPClient.Method
	match method:
		"GET":
			http_method = HTTPClient.METHOD_GET
		"POST":
			http_method = HTTPClient.METHOD_POST
		"PUT":
			http_method = HTTPClient.METHOD_PUT
		_:
			http_method = HTTPClient.METHOD_GET

	print("Making ", method, " request to: ", url)
	print("Body: ", request_body)

	var error: int = http_request.request(url, request_headers, http_method, request_body)

	if error != OK:
		print("HTTP Request error: ", error)
		if current_request_type == RequestType.VERIFY:
			verification_complete.emit(false)
		else:
			authentication_failed.emit("Request failed: " + str(error))
		current_request_type = RequestType.NONE
		return
