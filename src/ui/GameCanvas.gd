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

@onready var pause_tip_text : Label = $PauseMenu/ScrollContainer/Pause/Tip

const NUM_OF_TIPS = 17

func _get_node_adapter() -> MultiplayerNodeAdapter:
	return Global.get_node_adapter()

func _refresh_pause_permissions() -> void:
	var change_map_button: Button = $PauseMenu/ScrollContainer/Pause/ChangeMap
	var map_selector: Node = $PauseMenu/ScrollContainer/Pause/MapList
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter == null:
		change_map_button.visible = true
		change_map_button.disabled = false
		if map_selector != null and map_selector.get("disabled") != null:
			map_selector.set("disabled", false)
		return
	var is_host: bool = adapter.is_server()
	change_map_button.visible = is_host
	change_map_button.disabled = !is_host
	if map_selector != null and map_selector.get("disabled") != null:
		map_selector.set("disabled", !is_host)

func _ready() -> void:
	$PauseMenu/ScrollContainer/Pause/ChangeMap.connect("pressed", _send_on_change_map_pressed)
	$PauseMenu/ScrollContainer/Pause/SaveWorld.connect("pressed", _on_save_world_pressed)
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and not adapter.host_changed.is_connected(_on_node_host_changed):
		adapter.host_changed.connect(_on_node_host_changed)
	_refresh_pause_permissions()

func _on_node_host_changed(_new_host_peer_id: int, _is_me_host: bool) -> void:
	_refresh_pause_permissions()

func hide_pause_menu() -> void:
	Global.is_paused = false
	if Global.get_world().get_current_map() is Editor:
		$TestModePauseMenu.visible = false
		Global.get_player().locked = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		$PauseMenu.visible = false
		if Global.get_player() != null:
			Global.get_player().locked = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func show_pause_menu() -> void:
	Global.is_paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# if in editor world, we are testing, so show test pause menu
	if Global.get_world().get_current_map() is Editor:
		var editor : Editor = Global.get_world().get_current_map()
		$TestModePauseMenu.visible = true
		Global.get_player().locked = true
		$TestModePauseMenu/Menu/ReturnToEditor.connect("pressed", editor.exit_test_mode)
	else:
		$PauseMenu.visible = true
		if Global.get_player() != null:
			Global.get_player().locked = true
		_refresh_pause_permissions()
		# show tip on pause screen
		var tipnum : int = randi() % NUM_OF_TIPS
		pause_tip_text.text = JsonHandler.find_entry_in_file(str("tip/", tipnum))

func _process(delta : float) -> void:
	if Input.is_action_just_pressed("pause") && visible:
		# in editor testing mode
		if Global.get_world().get_current_map() is Editor:
			if $TestModePauseMenu.visible:
				hide_pause_menu()
			else:
				show_pause_menu()
		else:
			if $PauseMenu.visible:
				hide_pause_menu()
			else:
				show_pause_menu()

func _send_on_change_map_pressed() -> void:
	var map_selector: Node = $PauseMenu/ScrollContainer/Pause/MapList
	if map_selector == null:
		return
	var selected_lines: Array = map_selector.get("selected_lines") as Array
	var selected_name_value: Variant = map_selector.get("selected_name")
	var selected_name: String = "" if selected_name_value == null else str(selected_name_value)
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null:
		if !adapter.is_server():
			UIHandler.show_alert("Only the room host can change maps.", 4, false, UIHandler.alert_colour_error)
			return
		if selected_lines.is_empty():
			UIHandler.show_alert("No map selected.", 4, false, UIHandler.alert_colour_error)
			return
		Global.set_meta("current_room_map", selected_name)
		var packed_lines := PackedStringArray()
		for line_value: Variant in selected_lines:
			packed_lines.append(str(line_value))
		adapter.load_tbw(packed_lines)
		UIHandler.show_alert(str("Loading world \"", selected_name, "\" for all players..."), 4)
		return
	# load tbw with switching flag
	# clients must wait 15s between loading worlds to avoid spam
	Global.get_world().ask_server_to_open_tbw.rpc_id(1, Global.display_name, selected_name, selected_lines)
	if !multiplayer.is_server():
		UIHandler.show_alert(str("Your request to load \"", selected_name, "\" was sent to the host."), 4)

func _on_save_world_pressed() -> void:
	var world_name : String = $PauseMenu/ScrollContainer/Pause/SaveWorldName.text
	if world_name == "":
		UIHandler.show_alert("Please enter a world name above!", 4, false, UIHandler.alert_colour_error)
	else:
		Global.get_world().save_tbw(str(world_name))
