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
@onready var global_server_list_panel: PanelContainer = $GlobalPlayMenu/ServerList
@onready var global_server_list_button: Button = $GlobalPlayMenu/HostHbox/ServerListButton
var global_server_list: GlobalServerList
var room_creation_dialog: RoomCreationDialog
var auth_manager: AuthenticationManager
var game_servers_request: HTTPRequest
var game_server_dialog: AcceptDialog
var game_server_status_label: Label
var game_server_list_container: VBoxContainer
var server_selector_refresh_timer: Timer
var _selector_room_labels: Dictionary = {}
var _selector_servers_snapshot: Array = []
var _selector_refresh_generation: int = 0
var _selector_live_refresh_in_flight: bool = false
var _global_join_in_progress: bool = false
var _last_display_name: String = ""

func _variant_to_int(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return value as int
	if value is bool:
		return 1 if (value as bool) else 0
	if value is float:
		return int(value as float)
	return fallback

func _normalize_server_api_url(raw_url: String) -> String:
	var value := raw_url.strip_edges()
	while value.ends_with("/"):
		value = value.left(value.length() - 1)
	if value == "":
		return ""
	if value.ends_with("/api"):
		return value

	var scheme_pos := value.find("://")
	if scheme_pos == -1:
		return value
	var host_start := scheme_pos + 3
	var path_start := value.find("/", host_start)
	if path_start == -1:
		return value + "/api"

	var path := value.substr(path_start, value.length() - path_start)
	if path == "":
		return value + "/api"
	if path.begins_with("/api"):
		return value
	return value

func _set_selector_details_text(details_label: Label, server_data: Dictionary, current_rooms: int, max_rooms: int) -> void:
	var region := str(server_data.get("region", "global"))
	var is_active_value: Variant = server_data.get("is_active", true)
	var is_active: bool = true
	if is_active_value is bool:
		is_active = is_active_value
	elif is_active_value is int:
		is_active = (is_active_value as int) != 0
	elif is_active_value is float:
		is_active = (is_active_value as float) != 0.0
	var status := "online" if is_active else "offline"

	if max_rooms > 0:
		details_label.text = "Region: %s   Status: %s   Rooms: %d/%d" % [region, status, current_rooms, max_rooms]
	else:
		details_label.text = "Region: %s   Status: %s   Rooms: %d" % [region, status, current_rooms]

func _fetch_live_server_capacity(server_data: Dictionary) -> Dictionary:
	if not Global.is_authenticated or Global.auth_token == "":
		return {}

	var api_url := _normalize_server_api_url(str(server_data.get("api_url", "")))
	if api_url == "":
		return {}

	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(api_url + "/rooms", headers)
	if err != OK:
		req.queue_free()
		return {}

	var result_data: Array = await req.request_completed
	req.queue_free()
	if result_data.size() < 4:
		return {}

	var result: int = _variant_to_int(result_data[0], HTTPRequest.RESULT_CANT_CONNECT)
	var response_code: int = _variant_to_int(result_data[1], 0)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return {}

	var body := result_data[3] as PackedByteArray
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return {}

	var payload := json.data as Dictionary
	var server_capacity: Variant = payload.get("server_capacity", {})
	if server_capacity is Dictionary:
		return (server_capacity as Dictionary).duplicate(true)

	# Fallback if server_capacity is absent on a legacy node build.
	var rooms := payload.get("rooms", []) as Array
	return {
		"current_rooms": rooms.size(),
		"max_rooms": _variant_to_int(server_data.get("max_rooms", -1), -1),
	}

func _refresh_selector_live_room_counts(servers: Array, generation: int) -> void:
	if _selector_live_refresh_in_flight:
		return
	if generation != _selector_refresh_generation:
		return
	if not game_server_dialog or not game_server_dialog.visible:
		return

	_selector_live_refresh_in_flight = true
	for entry_value: Variant in servers:
		if generation != _selector_refresh_generation:
			break
		if not (entry_value is Dictionary):
			continue
		var server_data := entry_value as Dictionary
		var server_id := str(server_data.get("id", ""))
		if server_id == "":
			continue

		var details_label := _selector_room_labels.get(server_id, null) as Label
		if not details_label:
			continue

		var live_capacity: Dictionary = await _fetch_live_server_capacity(server_data)
		if live_capacity.is_empty():
			continue

		var current_rooms := _variant_to_int(live_capacity.get("current_rooms", server_data.get("current_rooms", 0)), 0)
		var max_rooms := _variant_to_int(live_capacity.get("max_rooms", server_data.get("max_rooms", -1)), -1)
		_set_selector_details_text(details_label, server_data, current_rooms, max_rooms)

	_selector_live_refresh_in_flight = false

func _on_server_selector_refresh_tick() -> void:
	if not game_server_dialog or not game_server_dialog.visible:
		if server_selector_refresh_timer:
			server_selector_refresh_timer.stop()
		return
	if _selector_servers_snapshot.is_empty():
		return
	call_deferred("_refresh_selector_live_room_counts", _selector_servers_snapshot, _selector_refresh_generation)

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
	$GlobalPlayMenu/HostHbox/ServerListButton.connect("pressed", _on_global_server_list_pressed)
	$GameModeMenu/Global.connect("pressed", _on_global_mode_selected)
	print("[Menu] GlobalPlayMenu host/join buttons connected")

	game_servers_request = HTTPRequest.new()
	add_child(game_servers_request)
	game_servers_request.request_completed.connect(_on_game_servers_response)

	server_selector_refresh_timer = Timer.new()
	add_child(server_selector_refresh_timer)
	server_selector_refresh_timer.wait_time = 2.0
	server_selector_refresh_timer.one_shot = false
	server_selector_refresh_timer.timeout.connect(_on_server_selector_refresh_tick)

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
		global_server_list.set_all_servers_mode()
		global_server_list_button.text = "All Servers"
		print("[Menu] GlobalServerList connected")

	if global_server_list_panel:
		global_server_list_panel.visible = true

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

	if Global.is_authenticated and Global.auth_token != "" and auth_manager:
		auth_manager.update_display_name(trimmed)
	else:
		print("[Menu] Skipping backend display name update (not authenticated)")

# ===== GLOBAL PLAY MENU FUNCTIONS =====

func _on_global_host_pressed() -> void:
	"""Open room creation dialog"""
	print("[Menu] === HOST BUTTON PRESSED ===")
	if global_server_list and global_server_list.is_all_servers_mode():
		print("[Menu] ⚠️ All Servers mode is for browsing only; select a specific server before creating a room")
		_on_global_server_list_pressed()
		return
	print("[Menu] Opening room creation dialog")
	if room_creation_dialog:
		room_creation_dialog.show_dialog()
		print("[Menu] Room creation dialog opened")
	else:
		print("[Menu] ❌ Room creation dialog not found!")

func _on_global_server_list_pressed() -> void:
	"""Open Django-backed game server selector, then load rooms from selected server"""
	if not Global.is_authenticated or Global.auth_token == "":
		print("[Menu] ❌ Must be authenticated to select a server")
		return

	_ensure_game_server_dialog()
	if not game_server_dialog or not game_server_status_label:
		print("[Menu] ❌ Failed to build game server dialog")
		return

	_clear_game_server_entries()
	_selector_refresh_generation += 1
	_selector_servers_snapshot = []
	_selector_live_refresh_in_flight = false
	game_server_status_label.text = "Loading available servers..."
	game_server_dialog.popup_centered(Vector2i(620, 460))
	if server_selector_refresh_timer:
		server_selector_refresh_timer.start()

	var url := BackendConfig.get_django_api_base_url() + "/game-servers"
	var headers: PackedStringArray = [
		"Authorization: Bearer " + Global.auth_token,
		"Content-Type: application/json"
	]
	var err := game_servers_request.request(url, headers)
	if err != OK:
		game_server_status_label.text = "Failed to query server registry"
		print("[Menu] ❌ Game server list request failed: ", err)

func _ensure_game_server_dialog() -> void:
	if game_server_dialog:
		return

	game_server_dialog = AcceptDialog.new()
	game_server_dialog.title = "Select Game Server"
	game_server_dialog.min_size = Vector2i(620, 460)
	game_server_dialog.dialog_text = ""
	add_child(game_server_dialog)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_server_dialog.add_child(root)

	game_server_status_label = Label.new()
	game_server_status_label.text = ""
	game_server_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(game_server_status_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	root.add_child(spacer)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	game_server_list_container = VBoxContainer.new()
	game_server_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_server_list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_server_list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(game_server_list_container)

	var ok_button := game_server_dialog.get_ok_button()
	if ok_button:
		ok_button.text = "Close"

func _clear_game_server_entries() -> void:
	if not game_server_list_container:
		return
	_selector_room_labels.clear()
	for child in game_server_list_container.get_children():
		child.queue_free()

func _on_game_servers_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if not game_server_status_label:
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		game_server_status_label.text = "Could not load servers from Django registry"
		return

	var json_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK or not (json.data is Dictionary):
		game_server_status_label.text = "Server registry response was invalid"
		return

	var payload := json.data as Dictionary
	var servers := payload.get("servers", []) as Array
	_selector_servers_snapshot = servers.duplicate(true)
	_clear_game_server_entries()

	if servers.is_empty():
		game_server_status_label.text = "No active servers found"
		return

	game_server_status_label.text = "Choose All Servers or a specific server"
	_create_all_servers_entry()
	for entry_value: Variant in servers:
		if not (entry_value is Dictionary):
			continue
		_create_game_server_entry(entry_value as Dictionary)

	call_deferred("_refresh_selector_live_room_counts", _selector_servers_snapshot, _selector_refresh_generation)

func _create_all_servers_entry() -> void:
	if not game_server_list_container:
		return

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 70)
	game_server_list_container.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	var name_label := Label.new()
	name_label.text = "All Servers"
	text_col.add_child(name_label)

	var details_label := Label.new()
	details_label.modulate = Color(1, 1, 1, 0.7)
	details_label.text = "Region: all   Status: mixed   Rooms: aggregated"
	text_col.add_child(details_label)

	var select_button := Button.new()
	select_button.text = "Select"
	select_button.custom_minimum_size = Vector2(90, 0)
	select_button.pressed.connect(_on_all_servers_selected)
	row.add_child(select_button)

func _create_game_server_entry(server_data: Dictionary) -> void:
	if not game_server_list_container:
		return

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 70)
	game_server_list_container.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	var name_label := Label.new()
	var server_name := str(server_data.get("name", "Unnamed Server"))
	var region := str(server_data.get("region", "global"))
	name_label.text = server_name
	text_col.add_child(name_label)

	var details_label := Label.new()
	var current_rooms := _variant_to_int(server_data.get("current_rooms", 0), 0)
	var max_rooms := _variant_to_int(server_data.get("max_rooms", -1), -1)
	_set_selector_details_text(details_label, server_data, current_rooms, max_rooms)
	details_label.modulate = Color(1, 1, 1, 0.7)
	text_col.add_child(details_label)

	var server_id := str(server_data.get("id", ""))
	if server_id != "":
		_selector_room_labels[server_id] = details_label

	var select_button := Button.new()
	select_button.text = "Select"
	select_button.custom_minimum_size = Vector2(90, 0)
	select_button.pressed.connect(_on_game_server_selected.bind(server_data))
	row.add_child(select_button)

func _on_game_server_selected(server_data: Dictionary) -> void:
	BackendConfig.set_selected_game_server(server_data)
	if room_creation_dialog and room_creation_dialog.backend:
		room_creation_dialog.backend.set_selected_server(server_data)
	var selected_name := str(server_data.get("name", "Server List"))
	global_server_list_button.text = selected_name

	if game_server_dialog:
		game_server_dialog.hide()

	if global_server_list_panel:
		global_server_list_panel.visible = true

	if global_server_list:
		global_server_list.set_specific_server_mode(server_data)
		global_server_list.refresh_server_list()

	print("[Menu] 🌐 Selected game server: ", selected_name)

func _on_all_servers_selected() -> void:
	global_server_list_button.text = "All Servers"

	if game_server_dialog:
		game_server_dialog.hide()

	if global_server_list_panel:
		global_server_list_panel.visible = true

	if global_server_list:
		global_server_list.set_all_servers_mode()
		global_server_list.refresh_server_list()

func _on_global_mode_selected() -> void:
	if global_server_list_button:
		global_server_list_button.text = "All Servers"
	if global_server_list_panel:
		global_server_list_panel.visible = true
	if global_server_list:
		global_server_list.set_all_servers_mode()
		global_server_list.refresh_server_list()

func _on_room_created(room_id: String, room_data: Dictionary) -> void:
	"""Handle new room creation - this is the HOST"""
	print("[Menu] === ROOM CREATED SIGNAL RECEIVED (HOST) ===")
	print("[Menu] Room ID: ", room_id)
	print("[Menu] Room data: ", room_data)
	print("[Menu] 🔄 Connecting to WebSocket as HOST...")

	# Get Main node
	var main: Main = get_tree().current_scene as Main
	if not main:
		print("[Menu] ❌ Failed to get Main node")
		return

	# Set play mode to global and backend to node
	main.play_mode = "global"
	main.backend = "node"

	# Extract map and gamemode from room data
	var map_name: String = str(room_data.get("map_name", ""))
	var gamemode: String = str(room_data.get("gamemode", ""))
	print("[Menu] 📋 Room settings - Map: ", map_name, " Gamemode: ", gamemode)

	# Connect to WebSocket as HOST with the room ID, map name, and gamemode
	print("[Menu] ✅ Calling _setup_websocket_host() with room_id: ", room_id, " map: ", map_name, " gamemode: ", gamemode)
	main._setup_websocket_host(room_id, map_name, gamemode)

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

func _on_global_room_selected(room_id: String, room_data: Dictionary) -> void:
	"""Handle room selection from GlobalServerList"""
	if _global_join_in_progress:
		print("[Menu] ⏳ Join already in progress, ignoring duplicate room selection")
		return

	print("[Menu] === ROOM SELECTED FROM SERVER LIST ===")
	print("[Menu] 🎯 Room ID: ", room_id)
	print("[Menu] 📋 Room data: ", room_data)
	if room_data.has("server") and room_data.get("server") is Dictionary:
		var server_data: Dictionary = room_data.get("server") as Dictionary
		BackendConfig.set_selected_game_server(server_data)
		if room_creation_dialog and room_creation_dialog.backend:
			room_creation_dialog.backend.set_selected_server(server_data)
		print("[Menu] 🌐 Selected server stored: ", server_data.get("id", ""))
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
	_global_join_in_progress = true
	if global_server_list:
		global_server_list.set_join_in_progress(true)

	# Extract map and gamemode from room data
	var map_name: String = str(room_data.get("map_name", ""))
	var gamemode: String = str(room_data.get("gamemode", ""))
	print("[Menu] 🗺️  Room settings - Map: ", map_name, " Gamemode: ", gamemode)

	# Connect to WebSocket and join the room using proper MultiplayerPeerExtension
	print("[Menu] ✅ Calling _setup_websocket_client() with room_id: ", room_id)
	await main._setup_websocket_client(room_id)

	# If still in menu scene, allow retries after prior attempt completes.
	if is_inside_tree():
		_global_join_in_progress = false
		if global_server_list:
			global_server_list.set_join_in_progress(false)
			global_server_list.refresh_server_list()

func show_hide(a: String, b: String) -> void:
	"""Show menu A and hide menu B"""
	get_node(a).visible = true
	get_node(b).visible = false
	# WebSocket handles real-time updates automatically
