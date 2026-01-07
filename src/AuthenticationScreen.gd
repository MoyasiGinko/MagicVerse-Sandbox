extends CanvasLayer
class_name AuthenticationScreen

var register_username_input: LineEdit
var register_email_input: LineEdit
var register_password_input: LineEdit
var register_confirm_input: LineEdit
var register_status_label: Label
var register_button: Button

var login_username_input: LineEdit
var login_password_input: LineEdit
var login_remember_checkbox: CheckBox
var login_status_label: Label
var login_button: Button

var auth_manager: AuthenticationManager = null

func _ready() -> void:
	# Get node references
	register_username_input = $VBoxContainer/TabContainer/Register/RegisterForm/UsernameInput
	register_email_input = $VBoxContainer/TabContainer/Register/RegisterForm/EmailInput
	register_password_input = $VBoxContainer/TabContainer/Register/RegisterForm/PasswordInput
	register_confirm_input = $VBoxContainer/TabContainer/Register/RegisterForm/ConfirmPasswordInput
	register_status_label = $VBoxContainer/TabContainer/Register/RegisterForm/StatusLabel
	register_button = $VBoxContainer/TabContainer/Register/RegisterForm/RegisterButton

	login_username_input = $VBoxContainer/TabContainer/Login/LoginForm/UsernameInput
	login_password_input = $VBoxContainer/TabContainer/Login/LoginForm/PasswordInput
	login_remember_checkbox = $VBoxContainer/TabContainer/Login/LoginForm/RememberCheckbox
	login_status_label = $VBoxContainer/TabContainer/Login/LoginForm/StatusLabel
	login_button = $VBoxContainer/TabContainer/Login/LoginForm/LoginButton

	# Create the authentication manager
	auth_manager = AuthenticationManager.new()
	add_child(auth_manager)

	# Connect signals
	auth_manager.authentication_complete.connect(_on_authentication_complete)
	auth_manager.authentication_failed.connect(_on_authentication_failed)

	# Connect button signals
	register_button.pressed.connect(_on_register_pressed)
	login_button.pressed.connect(_on_login_pressed)

	print("AuthenticationScreen loaded successfully")

## Handle register button press
func _on_register_pressed() -> void:
	register_status_label.text = ""

	var username: String = register_username_input.text.strip_edges()
	var email: String = register_email_input.text.strip_edges()
	var password: String = register_password_input.text
	var confirm_password: String = register_confirm_input.text

	# Validate inputs
	if not username:
		_show_register_error("Username required")
		return

	if not email:
		_show_register_error("Email required")
		return

	if not password:
		_show_register_error("Password required")
		return

	if password != confirm_password:
		_show_register_error("Passwords do not match")
		return

	if password.length() < 8:
		_show_register_error("Password must be at least 8 characters")
		return

	# Show loading state
	register_button.disabled = true
	register_status_label.text = "Creating account..."

	# Attempt registration
	auth_manager.register_user(username, email, password)

## Handle login button press
func _on_login_pressed() -> void:
	login_status_label.text = ""

	var username: String = login_username_input.text.strip_edges()
	var password: String = login_password_input.text

	if not username:
		_show_login_error("Username or email required")
		return

	if not password:
		_show_login_error("Password required")
		return

	# Show loading state
	login_button.disabled = true
	login_status_label.text = "Logging in..."

	# Attempt login
	auth_manager.login_user(username, password)

## Called when authentication is successful
func _on_authentication_complete(token: String, username: String) -> void:
	# Clear sensitive data
	register_password_input.text = ""
	register_confirm_input.text = ""
	login_password_input.text = ""

	# Re-enable buttons
	register_button.disabled = false
	login_button.disabled = false

	# Show success message
	register_status_label.text = "Account created! Loading..."
	login_status_label.text = "Login successful! Loading..."

	# Proceed to splash screen
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://data/scene/SplashVerification.tscn")

## Called when authentication fails
func _on_authentication_failed(reason: String) -> void:
	register_button.disabled = false
	login_button.disabled = false

	_show_register_error(reason)
	_show_login_error(reason)

func _show_register_error(message: String) -> void:
	register_status_label.add_theme_color_override("font_color", Color.RED)
	register_status_label.text = message
	register_button.disabled = false

func _show_login_error(message: String) -> void:
	login_status_label.add_theme_color_override("font_color", Color.RED)
	login_status_label.text = message
	login_button.disabled = false
