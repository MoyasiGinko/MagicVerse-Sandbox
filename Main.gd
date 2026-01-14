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

extends Node
class_name Main

signal upnp_completed(error : Object)

const PLAYER : PackedScene = preload("res://data/scene/character/RigidPlayer.tscn")
const CAMERA : PackedScene = preload("res://data/scene/camera/Camera.tscn")
const PORT = 30815
const SERVER_INFO_PORT = 30816
const NETWORK_COMPRESSION_MODE := ENetConnection.CompressionMode.COMPRESS_FASTLZ

# Backend selection: "enet" (default) or "node"
# Set via UserPreferences or config file
var backend := "enet"
var node_server_url := "ws://localhost:30820"
var play_mode := "classic" # "classic" (ENet) or "global" (Node)

# thread for UPNP connection
var thread : Thread = null
var upnp : UPNP = null
var host_public := true
var upnp_err : int = -1
var enet_peer := ENetMultiplayerPeer.new()
var node_peer : MultiplayerNodeAdapter = null
var multiplayer_peer : MultiplayerPeer = null
# For LAN servers
var lan_advertiser : ServerAdvertiser = null
var lan_listener : ServerListener = ServerListener.new()
var lan_entries := []

# Server version between client and server must match
# in order for client to join.
#
# Same as display version, but with leading zero for minor release
# to make room for double digit minor releases
# Last digit is 0 for pre-release and 1 for release
# ex. 9101 for 9.10; 10060 for 10.6pre; 12111 for 12.11
#     9 10 1         10 06 0            12 11 1
var server_version : int = 13020

# Displays on the title screen and game canvas
#
# major.minor
# add 'pre' at end for pre-release
var display_version := "beta 13.2pre"

# Classic (ENet) UI references
@onready var host_button : Button = $MultiplayerMenu/ClassicPlayMenu/HostHbox/Host
@onready var host_public_button : Button = $MultiplayerMenu/HostSettingsMenu/HostPublic
@onready var join_button : Button = $MultiplayerMenu/ClassicPlayMenu/JoinHbox/Join
@onready var display_name_field : LineEdit = $MultiplayerMenu/DisplayName
@onready var join_address : LineEdit = $MultiplayerMenu/ClassicPlayMenu/JoinHbox/Address
@onready var editor_button : Button = $MultiplayerMenu/MainMenu/Editor
@onready var tutorial_button : Button = $MultiplayerMenu/MainMenu/Tutorial
@onready var play_button : Button = $MultiplayerMenu/MainMenu/Play if has_node("MultiplayerMenu/MainMenu/Play") else null

# Menu panels
@onready var multiplayer_menu : CanvasLayer = $MultiplayerMenu
@onready var main_menu : Control = $MultiplayerMenu/MainMenu if has_node("MultiplayerMenu/MainMenu") else null
@onready var mode_selector_panel : Control = $MultiplayerMenu/GameModeMenu
@onready var classic_play_menu : Control = $MultiplayerMenu/ClassicPlayMenu
@onready var global_play_menu : Control = $MultiplayerMenu/GlobalPlayMenu

# Global (Node) UI references
@onready var global_host_button : Button = $MultiplayerMenu/GlobalPlayMenu/HostHbox/Host
@onready var global_join_button : Button = $MultiplayerMenu/GlobalPlayMenu/JoinHbox/Join
@onready var global_room_code_field : LineEdit = $MultiplayerMenu/GlobalPlayMenu/JoinHbox/Address

# Mode selector buttons
@onready var classic_mode_button : Button = $MultiplayerMenu/GameModeMenu/Classic
@onready var global_mode_button : Button = $MultiplayerMenu/GameModeMenu/Global

@onready var udp_server : InfoServer = $UDPServer

# Authentication manager for API calls
var auth_manager: AuthenticationManager

func _ready() -> void:
	# reset paused state
	Global.is_paused = false
	# Clear the graphics cache when entering the main menu.
	Global.graphics_cache = []
	# Update the spawnable scenes in case the player left a server.
	# (re-adds all spawnable objs to the multiplayerspawner)
	SpawnableObjects.update_spawnable_scenes()

	# Initialize authentication manager
	auth_manager = AuthenticationManager.new()
	add_child(auth_manager)

	# Load saved authentication token and user data
	auth_manager.load_saved_token()
	print("[Main] ✅ Initialization complete")

	# ask user before quitting (command and Q are buttons that may both
	# be used at the same time)
	get_tree().set_auto_accept_quit(false)

	# Connect UI buttons to handlers
	if play_button:
		if not play_button.is_connected("pressed", Callable(self, "_on_play_pressed")):
			play_button.pressed.connect(_on_play_pressed)
	else:
		print_debug("Play button not found; mode selector won't show")

	# Mode selector buttons
	if classic_mode_button and not classic_mode_button.is_connected("pressed", Callable(self, "_on_choose_classic")):
		classic_mode_button.pressed.connect(_on_choose_classic)
	if global_mode_button and not global_mode_button.is_connected("pressed", Callable(self, "_on_choose_global")):
		global_mode_button.pressed.connect(_on_choose_global)

	# Classic (ENet) buttons
	if not host_button.is_connected("pressed", Callable(self, "_on_host_pressed")):
		host_button.connect("pressed", _on_host_pressed)
	if not host_public_button.is_connected("toggled", Callable(self, "_on_host_public_toggled")):
		host_public_button.connect("toggled", _on_host_public_toggled)
	host_public = host_public_button.button_pressed
	if not join_button.is_connected("pressed", Callable(self, "_on_join_pressed")):
		join_button.connect("pressed", _on_join_pressed)

	# Global (Node) buttons
	if global_host_button and not global_host_button.is_connected("pressed", Callable(self, "_on_global_host_pressed")):
		global_host_button.connect("pressed", _on_global_host_pressed)
	if global_join_button and not global_join_button.is_connected("pressed", Callable(self, "_on_global_join_pressed")):
		global_join_button.connect("pressed", _on_global_join_pressed)

	# Other menu buttons
	if not editor_button.is_connected("pressed", Callable(self, "_on_editor_pressed")):
		editor_button.connect("pressed", _on_editor_pressed)
	if not tutorial_button.is_connected("pressed", Callable(self, "_on_tutorial_pressed")):
		tutorial_button.connect("pressed", _on_tutorial_pressed)

	# Initialize menu visibility
	_reset_menu_visibility()

	# Scan for LAN servers.
	get_tree().current_scene.add_child(lan_listener)
	lan_listener.connect("new_server", _on_new_lan_server)
	lan_listener.connect("remove_server", _on_remove_lan_server)

	# Load display name from authenticated user (API-based)
	var current_display: String = Global.player_display_name if Global.player_display_name != "" else Global.display_name
	if current_display != "":
		display_name_field.text = current_display
		Global.display_name = current_display

	# Load join address from prefs.
	var address : Variant = UserPreferences.load_pref("join_address")
	if address != null:
		join_address.text = str(address)

	# check if running in server mode
	if Global.server_mode():
		_on_host_pressed()

	if display_version.contains("pre"):
		UIHandler.show_alert("You are using a pre-release build, you may encounter unexpected issues when joining incompatible servers", 8, false, UIHandler.alert_colour_error)

	# debug tools
	if OS.get_cmdline_args().has("--debug_host"):
		_on_host_pressed()
	if OS.get_cmdline_args().has("--debug_join_local"):
		await get_tree().create_timer(2).timeout
		_on_join_pressed("localhost", true)

# quit request
func _notification(what : int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if !Global.server_mode():
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			var question : String = "Are you sure you want to quit?"
			if Global.get_world().get_current_map() is Editor:
				question = "Are you sure you want to quit? All unsaved\nchanges will be lost!"
			var actions := UIHandler.show_alert_with_actions(question, ["Quit game", "Cancel"], true)
			actions[0].connect("pressed", get_tree().quit)
		# server quit
		else:
			print("\nSaving world...")
			var ok : Variant = await Global.get_world().save_tbw("server_world", true)
			if ok == false:
				print("\nFailed to save world!")
			get_tree().quit()

func _on_new_lan_server(serverInfo : Dictionary) -> void:
	var multiplayer_menu : CanvasLayer = get_node_or_null("MultiplayerMenu")
	var lan_entry : PackedScene = load("res://data/scene/ui/LANEntry.tscn")
	if multiplayer_menu:
		var new_lan_entry : Control = lan_entry.instantiate()
		var lan_label : Label = get_node_or_null("MultiplayerMenu/ClassicPlayMenu/LANPanelContainer/Label")
		if lan_label:
			lan_label.text = "Join a server via LAN"
		var lan_container : Control = multiplayer_menu.get_node_or_null("ClassicPlayMenu/LANPanelContainer")
		if lan_container:
			lan_container.add_child(new_lan_entry)
			new_lan_entry.get_node("Name").text = str(serverInfo.name)
			new_lan_entry.get_node("Join").connect("pressed", _on_join_pressed.bind(serverInfo.ip, true))
			new_lan_entry.entry_server_ip = serverInfo.ip
			lan_entries.append(new_lan_entry)

func _on_remove_lan_server(serverIp : String) -> void:
	for entry : Control in lan_entries:
		if entry is LANEntry:
			if entry.entry_server_ip == serverIp:
				lan_entries.erase(entry)
				entry.queue_free()
				if lan_entries.size() < 1:
					var lan_label : Label = get_node_or_null("MultiplayerMenu/ClassicPlayMenu/LANPanelContainer/Label")
					if lan_label:
						lan_label.text = "Searching for LAN servers..."

func verify_display_name(check_string : String) -> Variant:
	var regex := RegEx.new()
	regex.compile("^\\s+$")
	if regex.search(str(check_string)):
		return "has only whitespaces"
	return null

func get_display_name_from_field() -> Variant:
	var t_display_name : String = display_name_field.text
	# User must have a display name.
	if t_display_name == "" || t_display_name == null:
		UIHandler.show_alert("Please enter a display name on the left.", 4, false, UIHandler.alert_colour_error)
		display_name_field.text = ""
		return null
	# Users can't have a display name that's only whitespace.
	var check_result : Variant = verify_display_name(t_display_name)
	if check_result != null:
		UIHandler.show_alert(str("Display name invalid (", check_result, ")"), 4)
		display_name_field.text = ""
		return null
	# Update Global values and sync to backend via API
	Global.display_name = t_display_name
	Global.player_display_name = t_display_name

	# Send update to backend if authenticated
	if auth_manager and Global.auth_token != "":
		auth_manager.update_display_name(t_display_name)

	return t_display_name

# --- Menu visibility and state management ---
func _reset_menu_visibility() -> void:
	"""Reset all menus to initial state (main menu visible, others hidden)"""
	if main_menu:
		main_menu.visible = true
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if classic_play_menu:
		classic_play_menu.visible = false
	if global_play_menu:
		global_play_menu.visible = false
	# Reset button states
	if host_button:
		host_button.disabled = false
	if join_button:
		join_button.disabled = false
	if global_host_button:
		global_host_button.disabled = false
	if global_join_button:
		global_join_button.disabled = false
	if global_room_code_field:
		global_room_code_field.text = ""

func _on_play_pressed() -> void:
	"""Show mode selector (GameModeMenu) when Play button clicked"""
	if main_menu:
		main_menu.visible = false
	if classic_play_menu:
		classic_play_menu.visible = false
	if global_play_menu:
		global_play_menu.visible = false
	if mode_selector_panel:
		mode_selector_panel.visible = true

# --- Mode handlers ---
func _on_choose_classic() -> void:
	"""User chose Classic (ENet) mode"""
	play_mode = "classic"
	backend = "enet"
	_show_classic_menu()

func _on_choose_global() -> void:
	"""User chose Global (Node) mode"""
	play_mode = "global"
	backend = "node"
	_show_global_menu()

func _show_classic_menu() -> void:
	"""Show classic ENet PlayMenu with Host/Join buttons"""
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if global_play_menu:
		global_play_menu.visible = false
	if main_menu:
		main_menu.visible = false
	if classic_play_menu:
		classic_play_menu.visible = true
	# reset button states
	if host_button:
		host_button.disabled = false
	if join_button:
		join_button.disabled = false

func _show_global_menu() -> void:
	"""Show Global (Node backend) menu with dedicated Host/Join controls"""
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if classic_play_menu:
		classic_play_menu.visible = false
	if main_menu:
		main_menu.visible = false
	if global_room_code_field:
		global_room_code_field.text = ""
	# Reset button states
	if global_host_button:
		global_host_button.disabled = false
	if global_join_button:
		global_join_button.disabled = false
	if global_play_menu:
		global_play_menu.visible = true

func _on_global_back() -> void:
	"""Return to mode selector from global menu (Back button handler)"""
	if global_play_menu:
		global_play_menu.visible = false
	# Reset input fields and button states
	if global_room_code_field:
		global_room_code_field.text = ""
	if global_host_button:
		global_host_button.disabled = false
	if global_join_button:
		global_join_button.disabled = false
	if mode_selector_panel:
		mode_selector_panel.visible = true

func _on_choose_global_connect() -> void:
	"""Legacy handler - no longer used since we have dedicated global UI"""
	play_mode = "global"
	backend = "node"
	_show_classic_menu()

func _on_global_host_pressed() -> void:
	"""Handle Host button click from Global menu"""
	play_mode = "global"
	backend = "node"
	var name: String = str(get_display_name_from_field())
	if name == "" or name == "null":
		return
	Global.display_name = name
	if global_host_button:
		global_host_button.text = "Starting server..."
		global_host_button.disabled = true
	host_button.text = "Starting server..."
	host_button.disabled = true
	if main_menu:
		main_menu.visible = false
	if classic_play_menu:
		classic_play_menu.visible = false
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if global_play_menu:
		global_play_menu.visible = false
	_setup_websocket_host()

func _on_global_join_pressed() -> void:
	"""Handle Join button click from Global menu"""
	play_mode = "global"
	backend = "node"
	var room_code := ""
	if global_room_code_field:
		room_code = global_room_code_field.text
	if room_code == "":
		UIHandler.show_alert("Enter a room code.", 5, false, UIHandler.alert_colour_error)
		return
	# editor debug names
	if OS.has_feature("editor"):
		Global.display_name = str("Editor Client ", randi_range(0, 99))
	else:
		var name: String = str(get_display_name_from_field())
		if name == "" or name == "null":
			return
		Global.display_name = name
	if global_join_button:
		global_join_button.text = "Connecting..."
		global_join_button.disabled = true
	join_button.text = JsonHandler.find_entry_in_file("ui/join_clicked")
	if main_menu:
		main_menu.visible = false
	if classic_play_menu:
		classic_play_menu.visible = false
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if global_play_menu:
		global_play_menu.visible = false
	_setup_websocket_client(room_code)

# UPnP setup thread
func _upnp_setup(server_port : int) -> void:
	upnp = UPNP.new()
	host_button.call_deferred("set", "text", "Finding gateway...")
	# timeout 2500ms
	var err := upnp.discover(2500)

	if err != OK:
		push_error(str(err))
		upnp_err = err
		UIHandler.call_deferred("show_alert", str("Failed to start server because: ", str(err)), 15, false, true)
		call_deferred("emit_signal", "upnp_completed", err)
		return

	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		host_button.call_deferred("set", "text", "Configuring...")
		upnp.add_port_mapping(server_port, server_port, str(ProjectSettings.get_setting("application/config/name")), "UDP")
		upnp.add_port_mapping(server_port, server_port, str(ProjectSettings.get_setting("application/config/name")), "TCP")
		call_deferred("emit_signal", "upnp_completed", OK)
	elif upnp.get_device_count() < 1:
		UIHandler.call_deferred("show_alert", "Failed to start server because: No devices", 15, false, true)
		call_deferred("emit_signal", "upnp_completed", 27)
	else:
		# unknown error
		UIHandler.call_deferred("show_alert", "Failed to start server because: Unknown\n(UPnP is probably disabled on your router)", 15, false, true)
		call_deferred("emit_signal", "upnp_completed", 28)

func _exit_tree() -> void:
	# Wait for thread finish here to handle game exit while the thread is running.
	if thread != null:
		thread.wait_to_finish()
	# Delete the port opened by upnp.
	if upnp != null:
		upnp.delete_port_mapping(PORT, "UDP")
		upnp.delete_port_mapping(PORT, "TCP")

func _on_host_public_toggled(mode : bool) -> void:
	host_public = mode
	if mode:
		host_public_button.set_text_to_json("ui/host_public_settings/on")
	else:
		host_public_button.set_text_to_json("ui/host_public_settings/off")

func _on_host_pressed() -> void:
	var no_display_name : bool = false
	if get_display_name_from_field() == null:
		if !Global.server_mode():
			return
		else:
			# Just use "Server" as default if display name is invalid
			Global.display_name = "Server"
			no_display_name = true
	else:
		Global.display_name = get_display_name_from_field()
	# Change button text to notify user server is starting.
	host_button.text = "Starting server..."
	host_button.disabled = true

	# Global (Node) path
	if play_mode == "global":
		_setup_websocket_host()
		return
	# only port forward public servers
	if host_public:
		thread = Thread.new()
		thread.start(_upnp_setup.bind(PORT))
		await Signal(self, "upnp_completed")
		if upnp_err != -1:
			host_button.text = "Host server"
			host_button.disabled = false
			return
	# Get the host's selected map from the dropdown.
	# Create the server.
	enet_peer.create_server(PORT)
	if enet_peer.host == null:
		host_button.text = "Host server"
		host_button.disabled = false
		UIHandler.show_alert("Failed to start server, is one already running?", 6, false, UIHandler.alert_colour_error)
		return
	enet_peer.host.compress(NETWORK_COMPRESSION_MODE)
	# Set the current multiplayer peer to the server.
	multiplayer.multiplayer_peer = enet_peer
	# When a new player connects, add them with their id.
	multiplayer.peer_connected.connect(add_peer)
	multiplayer.peer_disconnected.connect(remove_player)
	# Server info ping listener
	udp_server.start_udp_listener()
	# Load the world using the multiplayerspawner spawn method.
	var world : World = $World

	if Global.server_mode():
		# load server preferences
		Global.server_banned_ips = UserPreferences.load_server_pref("banned_ips")
		Global.server_can_clients_load_worlds = UserPreferences.load_server_pref("can_clients_load_worlds")
		# Set 'low processor mode', so that the screen does not redraw if
		# nothing changes
		OS.low_processor_usage_mode = true
		# Disable audio and no camera for dedicated servers
		AudioServer.set_bus_mute(0, true)
		UIHandler.show_alert(str("Started with arguments: ", OS.get_cmdline_args()))
		CommandHandler.submit_command.rpc("Info", "Your dedicated server has started! Type '?' in the command box for a list of commands. Alerts will show in this chat list. Player's chats will also appear here.")
		CommandHandler.submit_command.rpc("Info", "To stop the server and quit the app type '$quit'.")
		if no_display_name:
			CommandHandler.submit_command.rpc("Alert", "You have no saved display name so the default name 'Server' was used.")
		# load server world, first check if world exists
		var lines : Array = Global.get_tbw_lines("server_world", true)
		if lines.size() > 0:
			world.load_tbw.call_deferred("server_world", false, true, true)
		else:
			# load default world
			world.load_tbw.call_deferred("Grasslands", false, true, false)
	else:
		get_tree().current_scene.get_node("GameCanvas").visible = true
		# remove ".tbw"
		world.load_tbw.call_deferred("Frozen Field")
	# add camera
	var camera_inst : Node3D = CAMERA.instantiate()
	world.add_child(camera_inst, true)
	if !Global.server_mode():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	await Signal(world, "map_loaded")
	add_peer(multiplayer.get_unique_id())
	# Create the LAN advertiser.
	lan_advertiser = ServerAdvertiser.new()
	get_tree().current_scene.add_child(lan_advertiser)
	# Don't stop advertising to LAN listeners when the server pauses.
	lan_advertiser.process_mode = Node.PROCESS_MODE_ALWAYS
	lan_advertiser.serverInfo["name"] = str(display_name_field.text, "'s Server")
	lan_advertiser.broadcast_interval = 3
	get_tree().current_scene.get_node("MultiplayerMenu").visible = false

# Only runs for client
func _on_join_pressed(address : Variant = null, is_from_list := false) -> void:
	if address == null:
		address = join_address.text
		if join_address.text == "" && !is_from_list:
			UIHandler.show_alert("Enter an IP or domain to join in the '+' section\nto the right of the Join button.", 8, false, UIHandler.alert_colour_error)
			return
	# Save address for join (only if not LAN or server browser.)
	if !is_from_list:
		UserPreferences.save_pref("join_address", str(address))

	# editor debug names
	if OS.has_feature("editor"):
		Global.display_name = str("Editor Client ", randi_range(0, 99))
	else:
		if get_display_name_from_field() == null:
			return
		Global.display_name = get_display_name_from_field()

	# Change button text to notify user we are joining.
	join_button.text = JsonHandler.find_entry_in_file("ui/join_clicked")

	# Global (Node) path
	if play_mode == "global":
		var room_code := str(address)
		if room_code == "":
			room_code = join_address.text
		_setup_websocket_client(room_code)
		return

	# Create the client.
	enet_peer.create_client(str(address), PORT)
	enet_peer.host.compress(NETWORK_COMPRESSION_MODE)
	# Set the current multiplayer peer to the client.
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.connection_failed.connect(kick_client.bind("Server timeout or couldn't find server."))
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.server_disconnected.connect(_on_host_disconnect_as_client)
	$World.delete_old_map()
	await Signal($World, "map_loaded")

	# add camera
	var camera_inst : Node3D = CAMERA.instantiate()
	$World.add_child(camera_inst, true)
	camera_inst.global_position = Vector3(70, 190, 0)

	get_tree().current_scene.get_node("MultiplayerMenu").visible = false
	get_tree().current_scene.get_node("GameCanvas").visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Show loading screen for world load
	# This is hidden once the client's player object is ready
	Global.get_world().set_loading_canvas_visiblity(true)
	Global.get_world().set_loading_canvas_text("Connecting to server...")

# Entering the world editor.
func _on_editor_pressed() -> void:
	if get_display_name_from_field() == null:
		return
	Global.display_name = get_display_name_from_field()

	# Change button text to notify user server is starting.
	editor_button.text = "Loading editor..."
	editor_button.disabled = true

	get_tree().current_scene.get_node("MultiplayerMenu").visible = false
	get_tree().current_scene.get_node("EditorCanvas").visible = true

	# Editor is single player.
	var world : World = $World
	world.load_map.call_deferred(load(str("res://data/scene/EditorWorld/EditorWorld.tscn")))
	await Signal(world, "map_loaded")
	# add camera
	var camera_inst : Node3D = CAMERA.instantiate()
	world.add_child(camera_inst, true)

	add_peer(multiplayer.get_unique_id())
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Entering the tutorial.
func _on_tutorial_pressed() -> void:
	if get_display_name_from_field() == null:
		return
	Global.display_name = get_display_name_from_field()

	# Change button text to notify user server is starting.
	tutorial_button.text = "Loading tutorial..."
	tutorial_button.disabled = true

	get_tree().current_scene.get_node("MultiplayerMenu").visible = false
	get_tree().current_scene.get_node("GameCanvas").visible = true

	# Editor is single player.
	var world : World = $World
	world.load_tbw.call_deferred("tutorial")
	await Signal(world, "map_loaded")
	# add camera
	var camera_inst : Node3D = CAMERA.instantiate()
	world.add_child(camera_inst, true)

	add_peer(multiplayer.get_unique_id())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Notify clients if the host disconnects.
func _on_host_disconnect_as_client() -> void:
	# in case host disconnects while mouse is captured
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UIHandler.show_alert("Connection lost :(", 12, false, UIHandler.alert_colour_error)
	leave_server()

func leave_server() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	enet_peer.close()
	if udp_server != null:
		udp_server.udp_server.stop()
	Global.connected_to_server = false
	get_tree().change_scene_to_file("res://data/scene/MainScene.tscn")

# Kick or disconnect from the server with a reason.
func kick_client(reason : String) -> void:
	UIHandler.show_alert(str("Connection failure: ", reason), 8, false, UIHandler.alert_colour_error)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	leave_server()

@rpc("any_peer", "call_remote", "reliable")
func announce_player_joined(p_display_name : String) -> void:
	UIHandler.show_alert(str(p_display_name, " joined."), 4, false, UIHandler.alert_colour_player)
	if multiplayer.is_server():
		print("Server info: IP of player ", p_display_name, ": ", enet_peer.get_peer(multiplayer.get_remote_sender_id()).get_remote_address())

# Adds a player to the server with id & name.
func add_peer(peer_id : int) -> void:
	if multiplayer.is_server():
		# unpause, if was paused from empty server
		if get_tree().paused == true:
			get_tree().paused = false
			CommandHandler._send_response("Info", str("Server unpaused."))
		# for connecting clients, do prejoin before adding player
		if peer_id != 1:
			rpc_id(peer_id, "client_info_request_from_server")
		# for the server just add them
		else:
			# if joining as a player
			if !Global.server_mode():
				var player : RigidPlayer = PLAYER.instantiate()
				player.name = str(peer_id)
				$World.add_child(player, true)
			Global.connected_to_server = true

# first request sent out to the joining client from the server
@rpc("call_local", "reliable")
func client_info_request_from_server() -> void:
	info_response_from_client.rpc_id(1, multiplayer.get_unique_id(), server_version, Global.display_name)

# first response from the joining client; check validity here
@rpc("any_peer", "call_remote", "reliable")
func info_response_from_client(id : int, client_server_version : int, client_name : String) -> void:
	# check if ip banned
	var remote_ip := enet_peer.get_peer(multiplayer.get_remote_sender_id()).get_remote_address()
	if Global.server_banned_ips.has(remote_ip):
		# kick new client with code 3 (banned)
		response_from_server_joined.rpc_id(multiplayer.get_remote_sender_id(), 3)
		await get_tree().create_timer(0.35).timeout
		enet_peer.disconnect_peer(multiplayer.get_remote_sender_id())
		return

	if client_server_version != server_version:
		# kick new client with code 1 (mismatch version)
		response_from_server_joined.rpc_id(multiplayer.get_remote_sender_id(), 1)
		# wait for a bit before kicking to get message to client sent
		await get_tree().create_timer(0.35).timeout
		enet_peer.disconnect_peer(multiplayer.get_remote_sender_id())
		return
	for i in Global.get_world().get_children():
		if i is RigidPlayer:
			# case insensitive
			if i.display_name.to_lower() == client_name.to_lower():
				# kick new client with code 2 (name taken)
				response_from_server_joined.rpc_id(multiplayer.get_remote_sender_id(), 2)
				# wait for a bit before kicking to get message to client sent
				await get_tree().create_timer(0.35).timeout
				enet_peer.disconnect_peer(multiplayer.get_remote_sender_id())
				return
	# nothing wrong
	response_from_server_joined.rpc_id(multiplayer.get_remote_sender_id(), 0)
	var player : RigidPlayer = PLAYER.instantiate()
	player.name = str(multiplayer.get_remote_sender_id())
	$World.add_child(player)

# second response from server to client
@rpc("call_local", "reliable")
func response_from_server_joined(response_code : int) -> void:
	if response_code == 1:
		kick_client("Version mismatch (your version does not match host version)")
	elif response_code == 2:
		kick_client("Display name already in use")
	elif response_code == 3:
		kick_client("You are banned from this server")
	elif response_code == 0:
		# announce to other clients, from the joined client
		announce_player_joined.rpc(Global.display_name)
		Global.connected_to_server = true

# Removes a player from the server given an id.
func remove_player(peer_id : int) -> void:
	var player : RigidPlayer = $World.get_node_or_null(str(peer_id))
	if player:
		# don't tell clients that the host disconnected
		if peer_id != 1:
			# Tell others that someone left
			UIHandler.show_alert(str(player.display_name, " left."), 4, false, UIHandler.alert_colour_player)
		# Remove player from World player list.
		Global.get_world().remove_player_from_list(player)
		# if server, demote player
		if multiplayer.is_server():
			if CommandHandler.admins.has(peer_id):
				CommandHandler.admins.erase(peer_id)
				CommandHandler._send_response("Info", str("Demoted ", player.display_name, " because they left."))

		player.queue_free()

	# if no one is online, pause physics
	if multiplayer.is_server():
		if Global.get_world().rigidplayer_list.size() == 0:
			CommandHandler._send_response("Info", str("Pausing the server because no one is online. It will automatically resume when someone joins."))
			get_tree().paused = true

# ============ WebSocket Multiplayer Setup ============

## Signal handlers for old adapter (deprecated, keeping for reference)
# These are no longer used with WebSocketMultiplayerPeer

func _on_room_created(room_id: String) -> void:
	print("Room created: ", room_id)
	UIHandler.show_alert("Room created: " + room_id, 6, false, UIHandler.alert_colour_player)

func _on_room_joined(peer_id: int, room_id: String) -> void:
	print("Joined room ", room_id, " as peer ", peer_id)
	UIHandler.show_alert("Connected as peer " + str(peer_id), 4, false, UIHandler.alert_colour_player)

func _on_peer_joined_with_name(peer_id: int, peer_name: String) -> void:
	"""Called when a new peer joins the room after we're already in"""
	print("[Main] 👤 New peer joined: ", peer_id, " name=", peer_name)

	var player_list: Control = get_tree().current_scene.get_node_or_null("GameCanvas/PlayerList")
	if player_list and player_list.has_method("add_player_from_server"):
		player_list.add_player_from_server(peer_id, peer_name, 0)
		print("[Main] ✅ Added new peer to player list")
	else:
		print("[Main] ⚠️ PlayerList not found")

func _on_connection_failed(reason: String) -> void:
	push_error("Node backend connection failed: " + reason)
	UIHandler.show_alert("Connection failed: " + reason, 8, false, UIHandler.alert_colour_error)
	host_button.disabled = false
	host_button.text = "Host server"
	if join_button:
		join_button.text = JsonHandler.find_entry_in_file("ui/join") if JsonHandler.has_method("find_entry_in_file") else "Join"
		join_button.disabled = false
	if global_host_button:
		global_host_button.text = "Host (Global)"
		global_host_button.disabled = false
	if global_join_button:
		global_join_button.text = "Join (Global)"
		global_join_button.disabled = false

## NEW WEBSOCKET MULTIPLAYER PEER IMPLEMENTATION

func _setup_websocket_host(room_id: String = "", map_name: String = "Frozen Field", gamemode: String = "Deathmatch") -> void:
	"""Setup WebSocket multiplayer as host - uses MultiplayerNodeAdapter"""
	print("[Main] 🌐 === WEBSOCKET HOST SETUP ===")
	if room_id != "":
		print("[Main] 🔑 Room ID (from HTTP API): ", room_id)
	print("[Main] 🗺️ Map: ", map_name)
	print("[Main] 🎮 Gamemode: ", gamemode)

	# Store room info for pause menu to read and update
	Global.set_meta("current_room_id", room_id)
	Global.set_meta("current_room_map", map_name)
	Global.set_meta("current_room_gamemode", gamemode)
	print("[Main] ✅ Room info stored in Global metadata")

	# Create Node adapter (this replaces the old setup we removed)
	print("[Main] 🔨 Creating MultiplayerNodeAdapter...")
	node_peer = MultiplayerNodeAdapter.new()
	add_child(node_peer)
	set_meta("node_adapter", node_peer)
	print("[Main] ✅ MultiplayerNodeAdapter created and added")

	# Connect adapter signals
	print("[Main] 🔗 Connecting adapter signals...")
	node_peer.connection_failed.connect(_on_connection_failed)
	node_peer.room_joined.connect(_on_room_joined)
	node_peer.peer_joined_with_name.connect(_on_peer_joined_with_name)
	print("[Main] ✅ Signals connected")

	# Connect to Node backend
	print("[Main] 🔄 Connecting to Node backend...")
	if not node_peer.connect_to_server(node_server_url):
		push_error("[Main] ❌ Failed to connect")
		_reset_host_buttons()
		return

	# Wait for WebSocket connection
	print("[Main] ⏳ Waiting for connection...")
	await get_tree().create_timer(0.5).timeout

	# Send handshake
	print("[Main] 🤝 Sending handshake...")
	node_peer.send_handshake(str(server_version), Global.display_name, Global.auth_token)
	await get_tree().create_timer(0.3).timeout

# Join or create room
	if room_id != "":
		print("[Main] 📥 Joining existing room (created via HTTP API): ", room_id)
		node_peer.join_room(room_id, str(server_version), Global.display_name)
		# Wait for backend to confirm room join
		print("[Main] ⏳ Waiting for room_joined confirmation...")
		await node_peer.room_joined
	else:
		print("[Main] 📤 Creating new room via WebSocket...")
		node_peer.create_room(str(server_version), Global.display_name)
		print("[Main] ⏳ Waiting for room_created confirmation...")
		await node_peer.room_created

	print("[Main] ✅ Room ready, peer_id=", node_peer.get_unique_peer_id())

	print("[Main] ✅ Host setup complete")

	# Store adapter wrapper for RigidPlayer to use for is_server() checks
	set_meta("adapter_wrapper", AdapterMultiplayerPeer.new(node_peer))
	print("[Main] ✅ Adapter wrapper stored")

	# Load world and start game with selected map
	await _load_world_and_start(map_name)

func _setup_websocket_client(room_code: String) -> void:
	"""Setup WebSocket multiplayer as client - uses MultiplayerNodeAdapter"""
	print("[Main] 🌐 === WEBSOCKET CLIENT SETUP ===")

	# Create Node adapter
	print("[Main] 🔨 Creating MultiplayerNodeAdapter...")
	node_peer = MultiplayerNodeAdapter.new()
	add_child(node_peer)
	set_meta("node_adapter", node_peer)
	print("[Main] ✅ MultiplayerNodeAdapter created and added")

	# Connect adapter signals
	print("[Main] 🔗 Connecting adapter signals...")
	node_peer.connection_failed.connect(_on_connection_failed)
	node_peer.room_joined.connect(_on_room_joined)
	node_peer.peer_joined_with_name.connect(_on_peer_joined_with_name)
	print("[Main] ✅ Signals connected")

	# Connect to Node backend
	print("[Main] 🔄 Connecting to Node backend...")
	if not node_peer.connect_to_server(node_server_url):
		push_error("[Main] ❌ Failed to connect")
		_reset_join_buttons()
		return

	# Wait for WebSocket connection
	print("[Main] ⏳ Waiting for connection...")
	await get_tree().create_timer(0.5).timeout

	# Send handshake
	print("[Main] 🤝 Sending handshake...")
	node_peer.send_handshake(str(server_version), Global.display_name, Global.auth_token)
	await get_tree().create_timer(0.3).timeout

	# Join room
	print("[Main] 📤 Joining room: ", room_code)
	node_peer.join_room(room_code, str(server_version), Global.display_name)

	# Wait for backend to confirm room join (get peer_id and member list)
	print("[Main] ⏳ Waiting for room_joined confirmation...")
	await node_peer.room_joined
	print("[Main] ✅ Room joined, peer_id=", node_peer.get_unique_peer_id())

	print("[Main] ✅ Client setup complete")

	# Store adapter wrapper for RigidPlayer to use for is_server() checks
	set_meta("adapter_wrapper", AdapterMultiplayerPeer.new(node_peer))
	print("[Main] ✅ Adapter wrapper stored")

	# Load world and start game - get map from Global metadata (set by backend in room_joined)
	var room_map: String = Global.get_meta("current_room_map") if Global.has_meta("current_room_map") else "Frozen Field"
	print("[Main] 🗺️ Loading room map: ", room_map)
	await _load_world_and_start(room_map)

func _load_world_and_start(map_name: String) -> void:
	"""Load world/map for WebSocket multiplayer"""
	print("[Main] 🌍 Loading world...")
	$World.delete_old_map()

	var lines: Array = Global.get_tbw_lines(map_name, false)
	if lines.size() > 0:
		$World.open_tbw(lines)
		await Signal($World, "map_loaded")
		print("[Main] ✅ Map loaded")
	else:
		push_error("[Main] ❌ Failed to load map")
		return

	# Add camera
	var camera_inst : Node3D = CAMERA.instantiate()
	$World.add_child(camera_inst, true)

	# Spawn local player character
	if node_peer:
		var local_peer_id: int = node_peer.get_unique_peer_id()
		print("[Main] 👤 Spawning local player (peer_id=", local_peer_id, ")...")
		var player: RigidPlayer = PLAYER.instantiate()
		player.name = str(local_peer_id)
		player.set_multiplayer_authority(local_peer_id)
		$World.add_child(player, true)
		print("[Main] ✅ Local player spawned")
		Global.connected_to_server = true

	# Spawn any existing room members as RigidPlayers
	if node_peer and node_peer.room_members.size() > 0:
		print("[Main] 👥 Spawning existing room members...")
		for member: Dictionary in node_peer.room_members:
			var member_peer_id: int = member.get("peerId", -1)
			var member_name: String = member.get("name", "Unknown")

			# Skip local player
			if member_peer_id == node_peer.get_unique_peer_id():
				continue

			print("[Main] 👤 Spawning RigidPlayer for peer: ", member_peer_id, " name: ", member_name)
			var remote_player: RigidPlayer = PLAYER.instantiate()
			remote_player.name = str(member_peer_id)
			remote_player.assigned_player_name = member_name  # Set the remote player's actual name
			remote_player.set_multiplayer_authority(member_peer_id)
			$World.add_child(remote_player, true)
		print("[Main] ✅ Existing members spawned")

	# Spawn any peers that joined before world was ready
	if node_peer:
		print("[Main] 🎭 Spawning pending members...")
		node_peer.spawn_pending_members()

	# Show game UI
	get_tree().current_scene.get_node("MultiplayerMenu").visible = false
	get_tree().current_scene.get_node("GameCanvas").visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Populate player list from server room data (after UI is visible)
	if node_peer:
		var all_peers: Array = node_peer.get_all_peers_with_names()
		var player_list: Control = get_tree().current_scene.get_node_or_null("GameCanvas/PlayerList")

		if player_list and player_list.has_method("add_player_from_server"):
			print("[Main] 👥 Populating player list with ", all_peers.size(), " players")
			for peer_data: Variant in all_peers:
				if typeof(peer_data) == TYPE_DICTIONARY:
					var peer_dict: Dictionary = peer_data as Dictionary
					var peer_id_val: int = peer_dict.get("peerId", 0) as int
					var peer_name: String = peer_dict.get("name", "Unknown") as String
					player_list.add_player_from_server(peer_id_val, peer_name, 0)
			print("[Main] ✅ Player list populated")
		else:
			print("[Main] ⚠️ PlayerList not found or missing method")

func _reset_host_buttons() -> void:
	host_button.text = "Host server"
	host_button.disabled = false
	if global_host_button:
		global_host_button.text = "Host (Global)"
		global_host_button.disabled = false

func _reset_join_buttons() -> void:
	join_button.text = JsonHandler.find_entry_in_file("ui/join") if JsonHandler.has_method("find_entry_in_file") else "Join"
	join_button.disabled = false
	if global_join_button:
		global_join_button.text = "Join (Global)"
		global_join_button.disabled = false
