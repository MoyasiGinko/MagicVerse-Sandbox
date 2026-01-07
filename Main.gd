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

@onready var host_button : Button = $MultiplayerMenu/PlayMenu/HostHbox/Host
@onready var host_public_button : Button = $MultiplayerMenu/HostSettingsMenu/HostPublic
@onready var join_button : Button = $MultiplayerMenu/PlayMenu/JoinHbox/Join
@onready var display_name_field : LineEdit = $MultiplayerMenu/DisplayName
@onready var join_address : LineEdit = $MultiplayerMenu/PlayMenu/JoinHbox/Address
@onready var editor_button : Button = $MultiplayerMenu/MainMenu/Editor
@onready var tutorial_button : Button = $MultiplayerMenu/MainMenu/Tutorial
@onready var play_button : Button = $MultiplayerMenu/MainMenu/Play if has_node("MultiplayerMenu/MainMenu/Play") else null

@onready var multiplayer_menu : CanvasLayer = $MultiplayerMenu
@onready var main_menu : Control = $MultiplayerMenu/MainMenu if has_node("MultiplayerMenu/MainMenu") else null
@onready var play_menu : Control = $MultiplayerMenu/PlayMenu
var mode_selector_panel : Panel = null
var global_menu_panel : Panel = null
var global_server_url_field : LineEdit = null
var global_room_code_field : LineEdit = null
var global_host_button : Button = null
var global_join_button : Button = null

@onready var udp_server : InfoServer = $UDPServer

func _ready() -> void:
	# reset paused state
	Global.is_paused = false
	# Clear the graphics cache when entering the main menu.
	Global.graphics_cache = []
	# Update the spawnable scenes in case the player left a server.
	# (re-adds all spawnable objs to the multiplayerspawner)
	SpawnableObjects.update_spawnable_scenes()

	# ask user before quitting (command and Q are buttons that may both
	# be used at the same time)
	get_tree().set_auto_accept_quit(false)

	# Hook Play button to mode selector
	if play_button:
		if not play_button.is_connected("pressed", Callable(self, "_on_play_pressed")):
			play_button.pressed.connect(_on_play_pressed)
	else:
		print_debug("Play button not found; mode selector won't show")
	# Prepare panels but keep them hidden until Play is clicked
	_build_mode_selector()
	_build_global_menu()
	_reset_menu_visibility()

	if not host_button.is_connected("pressed", Callable(self, "_on_host_pressed")):
		host_button.connect("pressed", _on_host_pressed)
	if not host_public_button.is_connected("toggled", Callable(self, "_on_host_public_toggled")):
		host_public_button.connect("toggled", _on_host_public_toggled)
	host_public = host_public_button.button_pressed
	if not join_button.is_connected("pressed", Callable(self, "_on_join_pressed")):
		join_button.connect("pressed", _on_join_pressed)
	if not editor_button.is_connected("pressed", Callable(self, "_on_editor_pressed")):
		editor_button.connect("pressed", _on_editor_pressed)
	if not tutorial_button.is_connected("pressed", Callable(self, "_on_tutorial_pressed")):
		tutorial_button.connect("pressed", _on_tutorial_pressed)

	# Scan for LAN servers.
	get_tree().current_scene.add_child(lan_listener)
	lan_listener.connect("new_server", _on_new_lan_server)
	lan_listener.connect("remove_server", _on_remove_lan_server)

	# Load display name from prefs.
	var display_pref : Variant = UserPreferences.load_pref("display_name")
	if display_pref != null:
		display_name_field.text = str(display_pref)

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
		get_node("MultiplayerMenu/PlayMenu/LANPanelContainer/Label").text = "Join a server via LAN"
		multiplayer_menu.get_node("PlayMenu/LANPanelContainer").add_child(new_lan_entry)
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
					get_node("MultiplayerMenu/PlayMenu/LANPanelContainer/Label").text = "Searching for LAN servers..."

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
	# Save the successful name.
	UserPreferences.save_pref("display_name", t_display_name)
	return t_display_name

# --- Menu visibility and state management ---
func _reset_menu_visibility() -> void:
	"""Reset all menus to initial state (main menu visible, others hidden)"""
	if main_menu:
		main_menu.visible = true
	if play_menu:
		play_menu.visible = false
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if global_menu_panel:
		global_menu_panel.visible = false
	# Reset button states to enabled and default text
	if host_button:
		host_button.disabled = false
		host_button.text = JsonHandler.find_entry_in_file("ui/host") if JsonHandler.has_method("find_entry_in_file") else "Host"
	if join_button:
		join_button.disabled = false
		join_button.text = JsonHandler.find_entry_in_file("ui/join") if JsonHandler.has_method("find_entry_in_file") else "Join"
	if global_host_button:
		global_host_button.disabled = false
		global_host_button.text = "Host (Global)"
	if global_join_button:
		global_join_button.disabled = false
		global_join_button.text = "Join (Global)"
	if global_room_code_field:
		global_room_code_field.text = ""

func _on_play_pressed() -> void:
	"""Show mode selector when Play button clicked"""
	if main_menu:
		main_menu.visible = false
	if play_menu:
		play_menu.visible = false
	if global_menu_panel:
		global_menu_panel.visible = false
	if mode_selector_panel:
		mode_selector_panel.visible = true

# --- Mode selector helpers ---
func _build_mode_selector() -> void:
	if multiplayer_menu == null:
		return
	mode_selector_panel = Panel.new()
	mode_selector_panel.name = "ModeSelector"
	mode_selector_panel.custom_minimum_size = Vector2(520, 220)
	mode_selector_panel.anchor_left = 0.25
	mode_selector_panel.anchor_right = 0.75
	mode_selector_panel.anchor_top = 0.25
	mode_selector_panel.anchor_bottom = 0.55
	mode_selector_panel.offset_left = 0
	mode_selector_panel.offset_top = 0
	mode_selector_panel.offset_right = 0
	mode_selector_panel.offset_bottom = 0
	mode_selector_panel.visible = false

	var vb := VBoxContainer.new()
	vb.anchor_left = 0
	vb.anchor_right = 1
	vb.anchor_top = 0
	vb.anchor_bottom = 1
	vb.offset_left = 16
	vb.offset_right = -16
	vb.offset_top = 16
	vb.offset_bottom = -16
	vb.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = "Choose play mode"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)

	var subtitle := Label.new()
	subtitle.text = "Classic: LAN/Direct IP (ENet)\nGlobal: Node backend (rooms, matchmaking-ready)"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)

	var classic_btn := Button.new()
	classic_btn.text = "Classic (ENet)"
	classic_btn.custom_minimum_size = Vector2(200, 48)
	classic_btn.pressed.connect(_on_choose_classic)

	var global_btn := Button.new()
	global_btn.text = "Global (Node)"
	global_btn.custom_minimum_size = Vector2(200, 48)
	global_btn.pressed.connect(_on_choose_global)

	buttons.add_child(classic_btn)
	buttons.add_child(global_btn)

	vb.add_child(title)
	vb.add_child(subtitle)
	vb.add_child(buttons)
	mode_selector_panel.add_child(vb)
	multiplayer_menu.add_child(mode_selector_panel)

func _build_global_menu() -> void:
	if multiplayer_menu == null:
		return
	global_menu_panel = Panel.new()
	global_menu_panel.name = "GlobalMenu"
	global_menu_panel.custom_minimum_size = Vector2(560, 320)
	global_menu_panel.anchor_left = 0.22
	global_menu_panel.anchor_right = 0.78
	global_menu_panel.anchor_top = 0.18
	global_menu_panel.anchor_bottom = 0.62
	global_menu_panel.offset_left = 0
	global_menu_panel.offset_top = 0
	global_menu_panel.offset_right = 0
	global_menu_panel.offset_bottom = 0
	global_menu_panel.visible = false

	var vb := VBoxContainer.new()
	vb.anchor_left = 0
	vb.anchor_right = 1
	vb.anchor_top = 0
	vb.anchor_bottom = 1
	vb.offset_left = 16
	vb.offset_right = -16
	vb.offset_top = 16
	vb.offset_bottom = -16
	vb.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = "Global Servers"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)

	var blurb := Label.new()
	blurb.text = "Connect via Node backend. Host to create a room, or join with a room code."
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 16)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD

	var url_hb := HBoxContainer.new()
	url_hb.add_theme_constant_override("separation", 8)
	var url_label := Label.new()
	url_label.text = "Server URL"
	url_label.custom_minimum_size = Vector2(110, 32)
	global_server_url_field = LineEdit.new()
	global_server_url_field.text = node_server_url
	url_hb.add_child(url_label)
	url_hb.add_child(global_server_url_field)

	var code_hb := HBoxContainer.new()
	code_hb.add_theme_constant_override("separation", 8)
	var code_label := Label.new()
	code_label.text = "Room Code"
	code_label.custom_minimum_size = Vector2(110, 32)
	global_room_code_field = LineEdit.new()
	global_room_code_field.placeholder_text = "e.g. ABC123"
	code_hb.add_child(code_label)
	code_hb.add_child(global_room_code_field)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)

	global_host_button = Button.new()
	global_host_button.text = "Host (Global)"
	global_host_button.custom_minimum_size = Vector2(200, 48)
	global_host_button.pressed.connect(_on_global_host_pressed)

	global_join_button = Button.new()
	global_join_button.text = "Join (Global)"
	global_join_button.custom_minimum_size = Vector2(200, 48)
	global_join_button.pressed.connect(_on_global_join_pressed)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(140, 44)
	back_btn.pressed.connect(_on_global_back)

	buttons.add_child(global_host_button)
	buttons.add_child(global_join_button)
	buttons.add_child(back_btn)

	vb.add_child(title)
	vb.add_child(blurb)
	vb.add_child(url_hb)
	vb.add_child(code_hb)
	vb.add_child(buttons)
	global_menu_panel.add_child(vb)
	multiplayer_menu.add_child(global_menu_panel)

func _on_choose_classic() -> void:
	play_mode = "classic"
	backend = "enet"
	_show_play_menu()

func _on_choose_global() -> void:
	play_mode = "global"
	backend = "node"
	_show_global_menu()

func _show_play_menu() -> void:
	"""Show classic ENet PlayMenu with Host/Join buttons"""
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if global_menu_panel:
		global_menu_panel.visible = false
	if main_menu:
		main_menu.visible = false
	if play_menu:
		play_menu.visible = true
	# reset host/join buttons to defaults and re-enable
	if host_button:
		host_button.disabled = false
		host_button.text = JsonHandler.find_entry_in_file("ui/host") if JsonHandler.has_method("find_entry_in_file") else "Host"
	if join_button:
		join_button.disabled = false
		join_button.text = JsonHandler.find_entry_in_file("ui/join") if JsonHandler.has_method("find_entry_in_file") else "Join"

func _show_global_menu() -> void:
	"""Show Global (Node backend) menu with dedicated Host/Join controls"""
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if play_menu:
		play_menu.visible = false
	if main_menu:
		main_menu.visible = false
	if global_server_url_field:
		global_server_url_field.text = node_server_url
	if global_room_code_field:
		global_room_code_field.text = ""
	# Reset button states
	if global_host_button:
		global_host_button.disabled = false
		global_host_button.text = "Host (Global)"
	if global_join_button:
		global_join_button.disabled = false
		global_join_button.text = "Join (Global)"
	if global_menu_panel:
		global_menu_panel.visible = true

func _on_global_back() -> void:
	"""Return to mode selector from global menu"""
	if global_menu_panel:
		global_menu_panel.visible = false
	# Reset input fields and button states
	if global_room_code_field:
		global_room_code_field.text = ""
	if global_host_button:
		global_host_button.disabled = false
		global_host_button.text = "Host (Global)"
	if global_join_button:
		global_join_button.disabled = false
		global_join_button.text = "Join (Global)"
	if mode_selector_panel:
		mode_selector_panel.visible = true

func _on_choose_global_connect() -> void:
	# Proceed to node flow using existing host/join UI (but with global backend)
	play_mode = "global"
	backend = "node"
	_show_play_menu()

func _on_global_host_pressed() -> void:
	play_mode = "global"
	backend = "node"
	if global_server_url_field:
		node_server_url = global_server_url_field.text
	var name: String = str(get_display_name_from_field())
	if name == "" or name == "null":
		return
	Global.display_name = name
	if global_host_button:
		global_host_button.text = "Starting server..."
		global_host_button.disabled = true
	# keep classic host button in sync for shared Node flow
	host_button.text = "Starting server..."
	host_button.disabled = true
	if main_menu:
		main_menu.visible = false
	if play_menu:
		play_menu.visible = false
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if global_menu_panel:
		global_menu_panel.visible = false
	_setup_node_backend_host()

func _on_global_join_pressed() -> void:
	play_mode = "global"
	backend = "node"
	if global_server_url_field:
		node_server_url = global_server_url_field.text
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
	# keep classic join button in sync for shared Node flow
	join_button.text = JsonHandler.find_entry_in_file("ui/join_clicked")
	if main_menu:
		main_menu.visible = false
	if play_menu:
		play_menu.visible = false
	if mode_selector_panel:
		mode_selector_panel.visible = false
	if global_menu_panel:
		global_menu_panel.visible = false
	_setup_node_backend_client(room_code)

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
		_setup_node_backend_host()
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
		_setup_node_backend_client(room_code)
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

# ============ Backend Selection Methods ============

func _setup_node_backend_host() -> void:
	host_button.text = "Starting server..."
	host_button.disabled = true
	if global_host_button:
		global_host_button.text = "Starting server..."
		global_host_button.disabled = true

	# Create Node adapter
	node_peer = MultiplayerNodeAdapter.new()
	add_child(node_peer)

	# Connect adapter signals
	node_peer.room_created.connect(_on_room_created)
	node_peer.connection_failed.connect(_on_connection_failed)

	# Connect to Node backend
	if not node_peer.connect_to_server(node_server_url):
		host_button.text = "Host server"
		host_button.disabled = false
		if global_host_button:
			global_host_button.text = "Host (Global)"
			global_host_button.disabled = false
		UIHandler.show_alert("Failed to connect to Node backend", 6, false, UIHandler.alert_colour_error)
		return

	# Send create_room
	await get_tree().create_timer(0.5).timeout
	node_peer.create_room(str(server_version), Global.display_name)

	# Wait for room creation confirmation
	await node_peer.room_created

	# Load world
	var world : World = $World
	world.load_tbw.call_deferred("Frozen Field")

	# add camera
	var camera_inst : Node3D = CAMERA.instantiate()
	world.add_child(camera_inst, true)

	await Signal(world, "map_loaded")
	add_peer(node_peer.get_peer_id())

	get_tree().current_scene.get_node("MultiplayerMenu").visible = false
	get_tree().current_scene.get_node("GameCanvas").visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _setup_node_backend_client(room_code: String = "") -> void:
	join_button.text = JsonHandler.find_entry_in_file("ui/join_clicked")
	if global_join_button:
		global_join_button.text = "Connecting..."
		global_join_button.disabled = true

	# Create Node adapter
	node_peer = MultiplayerNodeAdapter.new()
	add_child(node_peer)

	# Connect adapter signals
	node_peer.room_joined.connect(_on_room_joined)
	node_peer.connection_failed.connect(_on_connection_failed)

	# Connect to Node backend
	if not node_peer.connect_to_server(node_server_url):
		join_button.text = JsonHandler.find_entry_in_file("ui/join_clicked")
		if global_join_button:
			global_join_button.text = "Join (Global)"
			global_join_button.disabled = false
		UIHandler.show_alert("Failed to connect to Node backend", 6, false, UIHandler.alert_colour_error)
		return

	# Send join_room
	await get_tree().create_timer(0.5).timeout
	if room_code.is_empty():
		room_code = join_address.text
	node_peer.join_room(room_code, str(server_version), Global.display_name)

	# Load world
	$World.delete_old_map()
	await Signal($World, "map_loaded")

	# add camera
	var camera_inst : Node3D = CAMERA.instantiate()
	$World.add_child(camera_inst, true)
	camera_inst.global_position = Vector3(70, 190, 0)

	get_tree().current_scene.get_node("MultiplayerMenu").visible = false
	get_tree().current_scene.get_node("GameCanvas").visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	Global.get_world().set_loading_canvas_visiblity(true)
	Global.get_world().set_loading_canvas_text("Connecting to server...")

# Node backend signal handlers
func _on_room_created(room_id: String) -> void:
	print("Room created: ", room_id)
	UIHandler.show_alert("Room created: " + room_id, 6, false, UIHandler.alert_colour_player)

func _on_room_joined(peer_id: int, room_id: String) -> void:
	print("Joined room ", room_id, " as peer ", peer_id)
	UIHandler.show_alert("Connected as peer " + str(peer_id), 4, false, UIHandler.alert_colour_player)

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
