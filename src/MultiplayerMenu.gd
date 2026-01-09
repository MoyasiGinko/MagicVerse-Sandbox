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

extends CanvasLayer
class_name MultiplayerMenu

@onready var preview_player : RigidPlayer = Global.get_world().get_current_map().get_node("RigidPlayer")
@onready var nametag : LineEdit = $DisplayName
@onready var quit_dialog : PanelContainer = $QuitDialog
@onready var shirt_colour_picker : Control = $AppearanceMenu/ShirtPanel/ShirtPanelContainer/ColorPickerButton
@onready var hair_colour_picker : Control = $AppearanceMenu/HairPanel/HairPanelContainer/ColorPickerButton
var global_server_list: GlobalServerList
var room_creation_dialog: RoomCreationDialog
var auth_manager: AuthenticationManager
var _last_display_name: String = ""

func _ready() -> void:
	auth_manager = AuthenticationManager.new()
	add_child(auth_manager)

	Global.connect("appearance_changed", Callable(preview_player, "change_appearance"))
	$MainMenu/Appearance.connect("pressed", Callable(self, "show_appearance_settings"))
	# play hair swing animation on new hair selected
	#$AppearanceMenu/HairPanel/HairPanelContainer/Picker.connect("item_selected", play_preview_character_appearance_animation)
	$AppearanceMenu/Back.connect("pressed", Callable(self, "hide_appearance_settings"))
	$MainMenu/Play.connect("pressed", show_hide.bind("GameModeMenu", "MainMenu"))
	$GameModeMenu/Back.connect("pressed", show_hide.bind("MainMenu", "GameModeMenu"))
	$ClassicPlayMenu/Back.connect("pressed", show_hide.bind("GameModeMenu", "ClassicPlayMenu"))
	$GlobalPlayMenu/Back.connect("pressed", show_hide.bind("GameModeMenu", "GlobalPlayMenu"))
	$ClassicPlayMenu/HostHbox/Edit.connect("pressed", show_hide.bind("HostSettingsMenu", "ClassicPlayMenu"))
	$HostSettingsMenu/Back.connect("pressed", show_hide.bind("ClassicPlayMenu", "HostSettingsMenu"))
	$MainMenu/Settings.connect("pressed", show_hide.bind("SettingsScroll", "MainMenu"))
	$MainMenu/Credits.connect("pressed", show_hide.bind("CreditsMenu", "MainMenu"))
	$CreditsMenu/Back.connect("pressed", show_hide.bind("MainMenu", "CreditsMenu"))
	$SettingsScroll/SettingsMenu/SaveButton.connect("pressed", show_hide.bind("MainMenu", "SettingsScroll"))
	$MainMenu/Quit.connect("pressed", _on_quit_pressed)

	# Connect QuitDialog buttons
	$"QuitDialog/MarginContainer/Signout & Quit".connect("pressed", _on_quit_sign_out)
	$"QuitDialog/MarginContainer/Quit".connect("pressed", _on_quit_confirmed)
	$"QuitDialog/MarginContainer/Cancel".connect("pressed", _on_quit_cancelled)

	# Connect GlobalPlayMenu buttons (renamed to avoid classic menu collisions)
	$GlobalPlayMenu/HostHbox/HostServer.connect("pressed", _on_global_host_pressed)
	$GlobalPlayMenu/JoinHbox/JoinRoom.connect("pressed", _on_global_join_pressed)
	print("[Menu] GlobalPlayMenu host/join buttons connected")

	shirt_colour_picker.connect("color_changed", Global.set_shirt_colour)
	hair_colour_picker.connect("color_changed", Global.set_hair_colour)
	var pants_colour_picker : Control = $AppearanceMenu/PantsPanel/PantsPanelContainer/ColorPickerButton
	pants_colour_picker.connect("color_changed", Global.set_pants_colour)
	var skin_colour_picker : Control = $AppearanceMenu/SkinPanel/SkinPanelContainer/ColorPickerButton
	skin_colour_picker.connect("color_changed", Global.set_skin_colour)
	var hair_picker : Control = $AppearanceMenu/HairPanel/HairPanelContainer/Picker
	hair_picker.connect("item_selected", Global.set_hair)
	var shirt_picker : Control = $AppearanceMenu/ShirtPanel/ShirtPanelContainer/TypeBoxContainer/TypePicker
	shirt_picker.connect("item_selected", Global.set_shirt)
	var shirt_tex_picker : Button = $AppearanceMenu/ShirtPanel/ShirtPanelContainer/TextureBoxContainer/UploadButton
	shirt_tex_picker.connect("pressed", Global.upload_shirt_texture)
	var shirt_reset : Button = $AppearanceMenu/ShirtPanel/ShirtPanelContainer/TextureResetContainer/ResetButton
	shirt_reset.connect("pressed", Global.reset_shirt_texture)

	# Set to loaded settings
	hair_colour_picker.color = Global.hair_colour
	shirt_colour_picker.color = Global.shirt_colour
	pants_colour_picker.color = Global.pants_colour
	skin_colour_picker.color = Global.skin_colour
	hair_picker.selected = Global.hair
	shirt_picker.selected = Global.shirt

	# Initialize display name from authenticated user
	var current_display: String = Global.player_display_name if Global.player_display_name != "" else Global.display_name
	_last_display_name = current_display
	nametag.text = current_display
	nametag.text_submitted.connect(_on_display_name_submitted)
	nametag.focus_exited.connect(_on_display_name_focus_exited)

	# Connect to GlobalServerList signals
	global_server_list = $GlobalPlayMenu/ServerList
	if global_server_list and global_server_list.has_signal("room_selected"):
		global_server_list.room_selected.connect(_on_global_room_selected)
		print("[Menu] GlobalServerList connected")

	# Connect to RoomCreationDialog signals
	room_creation_dialog = $RoomCreationDialog
	if room_creation_dialog and room_creation_dialog.has_signal("room_created"):
		room_creation_dialog.room_created.connect(_on_room_created)
		print("[Menu] RoomCreationDialog connected")

	print("[Menu] MultiplayerMenu initialization complete!")
	# Default to MainMenu on startup; hide appearance until requested
	$MainMenu.visible = true
	$AppearanceMenu.visible = false
	preview_player.change_appearance()

func show_appearance_settings() -> void:
	"""Show appearance settings menu with animation"""
	$MainMenu.visible = false
	$AppearanceMenu.visible = true
	var map : Node3D = Global.get_world().get_current_map()
	if map.has_node("AnimationPlayer"):
		map.get_node("AnimationPlayer").play("appearance_in")

func hide_appearance_settings() -> void:
	"""Hide appearance settings menu"""
	$MainMenu.visible = true
	$AppearanceMenu.visible = false
	var map : Node3D = Global.get_world().get_current_map()
	if map.has_node("AnimationPlayer"):
		map.get_node("AnimationPlayer").play("appearance_out")
	# Save appearance on back
	Global.save_appearance()

func _on_quit_pressed() -> void:
	"""Show quit dialog"""
	quit_dialog.visible = true

func _on_quit_confirmed() -> void:
	"""Quit to desktop without signing out"""
	get_tree().quit()

func _on_quit_cancelled() -> void:
	"""Cancel - just close the dialog"""
	quit_dialog.visible = false

func _on_quit_sign_out() -> void:
	"""Sign out and quit to desktop"""
	# Clear authentication
	if auth_manager:
		auth_manager.clear_saved_token()
	Global.auth_token = ""
	Global.player_username = ""
	Global.player_display_name = ""
	Global.display_name = ""
	Global.is_authenticated = false

	# Quit the game
	get_tree().quit()

func quit() -> void:
	_on_quit_pressed()

func _process(delta : float) -> void:
	if visible:
		var camera : Camera3D = get_viewport().get_camera_3d()
		# align nametag above player head
		if preview_player != null && camera != null:
			nametag.position = camera.unproject_position(preview_player.global_position + Vector3.UP*1.8)
			nametag.position.x -= nametag.size.x/2
		# rotate character when mouse is outside of panel area
		if $AppearanceMenu.visible && (get_viewport().get_mouse_position().x / get_viewport().size.x < 0.7):
			preview_player.global_rotation.y = (get_viewport().get_mouse_position().x / get_viewport().size.x) * PI * 2 + (PI*-1.3)

func _on_display_name_focus_exited() -> void:
	_commit_display_name(nametag.text)

func _on_display_name_submitted(new_text: String) -> void:
	_commit_display_name(new_text)

func _commit_display_name(raw_text: String) -> void:
	var trimmed := raw_text.strip_edges()
	if trimmed == "":
		nametag.text = _last_display_name
		return

	if trimmed == _last_display_name:
		return

	_last_display_name = trimmed
	nametag.text = trimmed

	# Update global state immediately for UI, backend will persist
	Global.player_display_name = trimmed
	Global.display_name = trimmed

# ===== GLOBAL PLAY MENU FUNCTIONS =====

func _on_global_host_pressed() -> void:
	"""Open room creation dialog"""
	print("[Menu] === HOST BUTTON PRESSED ===")
	print("[Menu] Opening room creation dialog")
	if room_creation_dialog:
		room_creation_dialog.show_dialog()
		print("[Menu] Room creation dialog opened")
	else:
		print("[Menu] ❌ Room creation dialog not found!")

func _on_room_created(room_id: String, room_data: Dictionary) -> void:
	"""Handle new room creation"""
	print("[Menu] === ROOM CREATED SIGNAL RECEIVED ===")
	print("[Menu] Room ID: ", room_id)
	print("[Menu] Room data: ", room_data)
	print("[Menu] 🔄 Connecting to WebSocket and hosting room...")

	# Get Main node
	var main: Main = get_tree().current_scene as Main
	if not main:
		print("[Menu] ❌ Failed to get Main node")
		return

	# Set play mode to global and backend to node
	main.play_mode = "global"
	main.backend = "node"

	# Connect to Node backend as host with the created room ID
	print("[Menu] ✅ Calling _setup_node_backend_host()")
	main._setup_node_backend_host()

func _on_global_join_pressed() -> void:
	"""Join a room by address/ID (manual join via text input)"""
	var address: String = $GlobalPlayMenu/JoinHbox/RoomAddress.text.strip_edges()
	print("[Menu] === JOIN BUTTON PRESSED (manual input) ===")
	if address == "":
		print("[Menu] ❌ No address provided")
		return

	print("[Menu] 🔄 Attempting to join room via address: ", address)
	# TODO: Implement direct room joining logic
	push_warning("Direct room joining not yet implemented")

func _on_global_room_selected(room_id: String) -> void:
	"""Handle room selection from GlobalServerList"""
	print("[Menu] === ROOM SELECTED FROM SERVER LIST ===")
	print("[Menu] 🎯 Room ID: ", room_id)
	if not Global.is_authenticated or Global.auth_token == "":
		print("[Menu] ❌ Not authenticated; cannot join room")
		return
	print("[Menu] ✅ User authenticated")
	print("[Menu] 🔄 Connecting to WebSocket and joining room...")

	# Get Main node
	var main: Main = get_tree().current_scene as Main
	if not main:
		print("[Menu] ❌ Failed to get Main node")
		return

	# Set play mode to global and backend to node
	main.play_mode = "global"
	main.backend = "node"

	# Connect to Node backend as client and join the room
	print("[Menu] ✅ Calling _setup_node_backend_client() with room_id: ", room_id)
	main._setup_node_backend_client(room_id)

func show_hide(a: String, b: String) -> void:
	"""Show menu A and hide menu B"""
	get_node(a).visible = true
	get_node(b).visible = false
	# WebSocket handles real-time updates automatically
