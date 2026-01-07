extends CanvasLayer
class_name SplashVerification

var banner_image: TextureRect
var progress_bar: ProgressBar
var status_label: Label
var loading_label: Label

# Configuration
const MINIMUM_SPLASH_TIME: float = 15.0  # Minimum time to show splash
const BANNER_IMAGE_PATH: String = "res://title.png"  # Path to your banner image
const VERIFICATION_TIMEOUT: float = 10.0  # Maximum time to wait for verification

var auth_manager: AuthenticationManager = null
var splash_timer: float = 0.0
var verification_complete: bool = false
var verification_successful: bool = false

func _ready() -> void:
	# Get node references
	banner_image = $BannerImage
	progress_bar = $VerificationOverlay/ProgressBar
	status_label = $VerificationOverlay/StatusLabel
	loading_label = $VerificationOverlay/VBoxContainer/LoadingSpinner

	# Load banner image
	if ResourceLoader.exists(BANNER_IMAGE_PATH):
		banner_image.texture = load(BANNER_IMAGE_PATH)

	# Create and configure authentication manager
	auth_manager = AuthenticationManager.new()
	add_child(auth_manager)
	auth_manager.verification_complete.connect(_on_verification_complete)

	# Start splash timer
	splash_timer = 0.0
	status_label.text = "Initializing..."
	progress_bar.value = 0

	# Check if we have a saved token or need to verify
	_start_verification()

func _process(delta: float) -> void:
	splash_timer += delta

	# Update progress bar based on splash timer
	var progress = min(splash_timer / MINIMUM_SPLASH_TIME, 1.0)
	progress_bar.value = progress * 100

	# Check if we can proceed
	if splash_timer >= MINIMUM_SPLASH_TIME and verification_complete:
		if verification_successful:
			# Token is valid, proceed to main game
			_proceed_to_game()
		else:
			# Token invalid, go back to authentication
			_go_back_to_authentication()

func _start_verification() -> void:
	# Load saved token
	var saved_token = auth_manager.load_saved_token()

	if saved_token:
		status_label.text = "Verifying session..."
		loading_label.text = "⏳ Verifying token..."
		# Verify the saved token
		auth_manager.verify_token(saved_token)

		# Set timeout for verification
		await get_tree().create_timer(VERIFICATION_TIMEOUT).timeout
		if not verification_complete:
			status_label.text = "Verification timeout"
			verification_complete = true
			verification_successful = false
	else:
		# No saved token, go back to authentication
		status_label.text = "Please login or register"
		loading_label.text = "No saved session found"
		await get_tree().create_timer(3.0).timeout
		verification_complete = true
		verification_successful = false

func _on_verification_complete(is_valid: bool) -> void:
	verification_complete = true
	verification_successful = is_valid

	if is_valid:
		status_label.text = "Session verified! ✓"
		loading_label.text = "✓ Ready to play"
	else:
		status_label.text = "Session expired, please login again"
		loading_label.text = "✗ Session invalid"

func _proceed_to_game() -> void:
	status_label.text = "Entering game..."
	loading_label.text = "✓ Session valid - Entering game"
	progress_bar.value = 100

	# Fade out and proceed to main menu
	await _fade_out()
	get_tree().change_scene_to_file("res://Main.tscn")

func _go_back_to_authentication() -> void:
	status_label.text = "Please login again"
	loading_label.text = "Session invalid - returning to login"

	# Clear invalid token
	auth_manager.clear_saved_token()

	# Fade out and return to authentication
	await _fade_out()
	get_tree().change_scene_to_file("res://data/scene/AuthenticationScreen.tscn")

func _fade_out() -> void:
	var overlay = $VerificationOverlay
	var tween = create_tween()
	tween.tween_property(overlay, "color", Color(0, 0, 0, 1), 0.5)
	await tween.finished

## Called if user skips verification (optional - for testing)
func skip_verification() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_go_back_to_authentication()
