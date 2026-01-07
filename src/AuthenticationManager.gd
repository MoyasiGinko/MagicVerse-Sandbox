extends Node
class_name AuthenticationManager

# Signals
signal authentication_complete(token: String, username: String)
signal authentication_failed(reason: String)
signal verification_complete(is_valid: bool)

# Backend URL
var backend_url := "http://localhost:30820"
var http_client: HTTPClient = null

# Token storage
const TOKEN_SAVE_PATH := "user://tinybox_token.json"

func _ready() -> void:
	http_client = HTTPClient.new()

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
				return data["token"]
	return ""

## Save token to disk
func save_token(token: String, username: String) -> void:
	var data: Dictionary = {
		"token": token,
		"username": username,
		"timestamp": Time.get_ticks_msec()
	}

	var file: FileAccess = FileAccess.open(TOKEN_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

	# Also save to Global singleton
	Global.auth_token = token
	Global.player_username = username

## Clear saved token
func clear_saved_token() -> void:
	if ResourceLoader.exists(TOKEN_SAVE_PATH):
		DirAccess.remove_absolute(TOKEN_SAVE_PATH)
	Global.auth_token = ""
	Global.player_username = ""

## Private helper to make HTTP requests
func _make_request(method: String, endpoint: String, body: Dictionary = {}, headers: Array = []) -> void:
	var url: String = backend_url + endpoint
	var error: int = http_client.connect_to_host("localhost", 30820)

	if error != OK:
		authentication_failed.emit("Connection failed")
		return

	# Wait for connection
	await get_tree().process_frame

	var request_headers: Array = [
		"Content-Type: application/json",
		"User-Agent: Godot/4.0 (Tinybox)"
	]
	request_headers.append_array(headers)

	var request_body: String = JSON.stringify(body) if body else ""

	error = http_client.request(HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, endpoint, PackedStringArray(request_headers), request_body)

	if error != OK:
		authentication_failed.emit("Request failed")
		return

	# Wait for response
	while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
		await get_tree().process_frame

	if http_client.get_status() != HTTPClient.STATUS_BODY:
		authentication_failed.emit("Invalid response")
		return

	var response_text: String = ""
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		response_text += http_client.read_response_body_chunk().get_string_from_utf8()

	http_client.close()

	var json: JSON = JSON.new()
	var response_data: Variant = json.parse_string(response_text)

	if not response_data:
		authentication_failed.emit("Invalid response format")
		return

	# Handle response based on endpoint
	if endpoint == "/api/auth/register" or endpoint == "/api/auth/login":
		if response_data.has("error"):
			authentication_failed.emit(response_data["error"])
		elif response_data.has("token") and response_data.has("user"):
			var token: String = response_data["token"]
			var username: String = response_data["user"]["username"]
			save_token(token, username)
			authentication_complete.emit(token, username)
		else:
			authentication_failed.emit("No token in response")

	elif endpoint == "/api/auth/verify":
		if response_data.has("valid"):
			verification_complete.emit(response_data["valid"])
		else:
			verification_complete.emit(false)

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
