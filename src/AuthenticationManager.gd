extends Node
class_name AuthenticationManager

# Signals
signal authentication_complete(token: String, username: String)
signal authentication_failed(reason: String)
signal verification_complete(is_valid: bool)

# Backend URL
var backend_url := "http://localhost:30820"
var http_request: HTTPRequest = null

# Token storage
const TOKEN_SAVE_PATH := "user://tinybox_token.json"

func _ready() -> void:
	# Create HTTPRequest node for making requests
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)

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

	_make_request("POST", "/api/auth/login", body)

## Verify saved token
func verify_token(token: String) -> void:
	var headers: Array = [
		"Authorization: Bearer " + token
	]

	_make_request("GET", "/api/auth/verify", {}, headers)

## Load token from disk
func load_saved_token() -> String:
	if ResourceLoader.exists(TOKEN_SAVE_PATH):
		var file: FileAccess = FileAccess.open(TOKEN_SAVE_PATH, FileAccess.READ)
		if file:
			var json: JSON = JSON.new()
			var data: Variant = json.parse_string(file.get_as_text())
			if data and data.has("token"):
				if data.has("username"):
					Global.player_username = data["username"]
				if data.has("display_name"):
					Global.player_display_name = data["display_name"]
				else:
					Global.player_display_name = data.get("username", "")
				return data["token"]
	return ""

## Save token to disk
func save_token(token: String, username: String, display_name: String = "") -> void:
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

## Clear saved token
func clear_saved_token() -> void:
	if ResourceLoader.exists(TOKEN_SAVE_PATH):
		DirAccess.remove_absolute(TOKEN_SAVE_PATH)
	Global.auth_token = ""
	Global.player_username = ""
	Global.player_display_name = ""
	Global.display_name = ""

## Private helper to make HTTP requests
func _make_request(method: String, endpoint: String, body: Dictionary = {}, headers: Array = []) -> void:
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
		authentication_failed.emit("Request failed: " + str(error))
		return

## Handle HTTP response
func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("HTTP Response - Code: ", response_code, " Result: ", result)

	if result != HTTPRequest.RESULT_SUCCESS:
		print("Request failed with result: ", result)
		authentication_failed.emit("Network error")
		return

	# Accept 2xx status codes (200-299) as success
	if response_code < 200 or response_code >= 300:
		print("Server returned error code: ", response_code)
		var error_text: String = body.get_string_from_utf8()
		print("Error response: ", error_text)

		# Try to parse error from response
		var json: JSON = JSON.new()
		var response_data: Variant = json.parse_string(error_text)
		if response_data and response_data.has("error"):
			authentication_failed.emit(response_data["error"])
		else:
			authentication_failed.emit("Server error: " + str(response_code))
		return

	var response_text: String = body.get_string_from_utf8()
	print("Response body: ", response_text)

	var json: JSON = JSON.new()
	var response_data: Variant = json.parse_string(response_text)

	if not response_data:
		print("Failed to parse response")
		authentication_failed.emit("Invalid response format")
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
		var new_display_name: String = response_data["user"]["display_name"]
		Global.player_display_name = new_display_name
		Global.display_name = new_display_name
		# Update saved token with new display name
		save_token(Global.auth_token, Global.player_username, new_display_name)
		print("Display name updated to: ", new_display_name)
	else:
		print("Unexpected response structure")
		authentication_failed.emit("Unexpected server response")

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
	if not Global.auth_token:
		authentication_failed.emit("Not authenticated")
		return

	if new_display_name.length() < 1 or new_display_name.length() > 30:
		authentication_failed.emit("Display name must be 1-30 characters")
		return

	var body: Dictionary = {
		"display_name": new_display_name
	}

	var headers: Array = [
		"Authorization: Bearer " + Global.auth_token
	]

	_make_request_with_method("PUT", "/api/users/display-name", body, headers)

func _make_request_with_method(method: String, endpoint: String, body: Dictionary = {}, headers: Array = []) -> void:
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
		authentication_failed.emit("Request failed: " + str(error))
		return
