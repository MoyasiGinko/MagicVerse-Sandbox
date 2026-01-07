extends Node
class_name AuthenticationEntry

# This scene acts as the entry point to handle authentication flow
# It checks if user is authenticated and routes to the appropriate scene

func _ready() -> void:
	# Check if user has a valid token saved
	var auth_manager: AuthenticationManager = AuthenticationManager.new()
	var saved_token: String = auth_manager.load_saved_token()

	print("AuthenticationEntry: Checking for saved token...")
	if saved_token:
		# Token exists, go to splash verification
		print("AuthenticationEntry: Token found, going to splash screen...")
		get_tree().change_scene_to_file("res://data/scene/SplashVerification.tscn")
	else:
		# No token, show authentication screen
		print("AuthenticationEntry: No token, showing authentication screen...")
		get_tree().change_scene_to_file("res://data/scene/AuthenticationScreen.tscn")
