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

extends AnimatedList

@onready var selector : OptionButton = $GamemodeSelector
@onready var button : Button = $StartGamemode
@onready var end_button : Button = $EndGamemode
@onready var param_list : VBoxContainer = $ParameterList
@onready var modifier_list : VBoxContainer = $ModifierList
@onready var adjuster_label : PackedScene = load("res://data/scene/ui/AdjusterLabel.tscn")
var gamemode_names_list : Array = []
var selected_mode_params : Array = []
var selected_mode_mods : Array = []
var _suppress_broadcast: bool = false

func _get_node_adapter() -> MultiplayerNodeAdapter:
	var root: Node = get_tree().root
	if root.has_meta("node_adapter"):
		return root.get_meta("node_adapter") as MultiplayerNodeAdapter
	for child: Node in root.get_children():
		if child.has_meta("node_adapter"):
			return child.get_meta("node_adapter") as MultiplayerNodeAdapter
	return null

func _is_host_authority() -> bool:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null:
		return adapter.is_server()
	return multiplayer.is_server()

func _set_adjuster_interactable(adjuster_container: Node, is_host: bool) -> void:
	if not adjuster_container.has_node("List/Adjuster"):
		return
	var adjuster_node: Node = adjuster_container.get_node("List/Adjuster")
	for button_name: String in ["DownBig", "Down", "Up", "UpBig"]:
		var button_node: Node = adjuster_node.get_node_or_null(button_name)
		if button_node != null and button_node is BaseButton:
			(button_node as BaseButton).disabled = !is_host

func _apply_host_ui_permissions() -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter == null:
		button.visible = true
		button.disabled = false
		end_button.visible = true
		end_button.disabled = false
		selector.disabled = false
		for c: Node in param_list.get_children():
			_set_adjuster_interactable(c, true)
			if c is CheckBox:
				(c as CheckBox).disabled = false
		for c: Node in modifier_list.get_children():
			_set_adjuster_interactable(c, true)
			if c is CheckBox:
				(c as CheckBox).disabled = false
		return
	var is_host: bool = adapter.is_server()
	button.visible = is_host
	button.disabled = !is_host
	end_button.visible = is_host
	end_button.disabled = !is_host
	selector.disabled = !is_host
	for c: Node in param_list.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
		_set_adjuster_interactable(c, is_host)
		if c is CheckBox:
			(c as CheckBox).disabled = !is_host
	for c: Node in modifier_list.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
		_set_adjuster_interactable(c, is_host)
		if c is CheckBox:
			(c as CheckBox).disabled = !is_host

func _broadcast_menu_state_if_host() -> void:
	if _suppress_broadcast:
		return
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter == null or !adapter.is_server():
		return
	adapter.send_rpc_call("remote_gamemode_menu_sync", [selector.selected, selected_mode_params.duplicate(true), selected_mode_mods.duplicate(true)], 0)

func _apply_adjuster_values(params: Array, mods: Array) -> void:
	var param_idx: int = 0
	for c: Node in param_list.get_children():
		if c.has_node("List/Adjuster"):
			if param_idx < params.size():
				var adj: Adjuster = c.get_node("List/Adjuster") as Adjuster
				if adj != null:
					adj.set_value(int(params[param_idx] as float))
			param_idx += 1
	var mod_adj_idx: int = 0
	var mod_toggle_idx: int = 3
	for c: Node in modifier_list.get_children():
		if c.has_node("List/Adjuster"):
			if mod_adj_idx < 3 and mod_adj_idx < mods.size():
				var adj: Adjuster = c.get_node("List/Adjuster") as Adjuster
				if adj != null:
					adj.set_value(int(mods[mod_adj_idx] as float))
			mod_adj_idx += 1
		elif c is CheckBox:
			if mod_toggle_idx < mods.size():
				var toggle_variant: Variant = mods[mod_toggle_idx]
				var toggle_value: bool = false
				if typeof(toggle_variant) == TYPE_BOOL:
					toggle_value = toggle_variant as bool
				elif typeof(toggle_variant) == TYPE_INT:
					toggle_value = (toggle_variant as int) != 0
				elif typeof(toggle_variant) == TYPE_FLOAT:
					toggle_value = (toggle_variant as float) != 0.0
				(c as CheckBox).button_pressed = toggle_value

func apply_remote_gamemode_state(idx: int, params: Array, mods: Array) -> void:
	_suppress_broadcast = true
	if idx >= 0 and idx < selector.get_item_count():
		selector.select(idx)
		_on_item_selected(idx)
	selected_mode_params = params.duplicate(true)
	selected_mode_mods = mods.duplicate(true)
	_apply_adjuster_values(selected_mode_params, selected_mode_mods)
	_suppress_broadcast = false
	_apply_host_ui_permissions()

func get_selector_item_count() -> int:
	return selector.get_item_count()

func _ready() -> void:
	super()
	# automatically populate gamemode list based on map
	Global.get_world().connect("tbw_loaded", _on_tbw_loaded)
	button.connect("pressed", _on_start_gamemode_pressed)
	end_button.connect("pressed", _on_end_gamemode_pressed)
	selector.connect("item_selected", _on_item_selected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and not adapter.host_changed.is_connected(_on_node_host_changed):
		adapter.host_changed.connect(_on_node_host_changed)
	_apply_host_ui_permissions()

func _on_node_host_changed(_new_host_peer_id: int, _is_me_host: bool) -> void:
	_apply_host_ui_permissions()
	_broadcast_menu_state_if_host()

func _on_start_gamemode_pressed() -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.is_server():
		Global.server_start_gamemode(selector.selected, selected_mode_params, selected_mode_mods)
		return
	if adapter != null:
		return
	Global.server_start_gamemode.rpc_id(1, selector.selected, selected_mode_params, selected_mode_mods)

func _on_peer_connected(id : int) -> void:
	# only execute from the owner
	if !multiplayer.is_server(): return
	_populate_client_gamemode_list.rpc_id(id, gamemode_names_list)

func _on_end_gamemode_pressed() -> void:
	var adapter := _get_node_adapter()
	if adapter != null:
		if !adapter.is_server():
			return
	else:
		if !multiplayer.is_server(): return
	var e : Event = Event.new(Event.EventType.END_ACTIVE_GAMEMODE, [])
	e.start()
	if adapter != null:
		adapter.send_rpc_call("remote_end_gamemode", [])

func _on_tbw_loaded() -> void:
	# delete old list
	selector.clear()
	# for populating client lists
	gamemode_names_list = []
	# add new gamemodes
	for gm : Gamemode in Global.get_world().gamemode_list:
		gamemode_names_list.append(gm.gamemode_name)
	# as server: populate all peers' gamemode lists
	# including self
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null:
		_populate_client_gamemode_list(gamemode_names_list)
	else:
		if !multiplayer.is_server():
			return
		_populate_client_gamemode_list.rpc(gamemode_names_list)
	_apply_host_ui_permissions()

@rpc("any_peer", "call_local", "reliable")
func _populate_client_gamemode_list(gamemode_names : Array) -> void:
	if multiplayer.get_remote_sender_id() != 1 && multiplayer.get_remote_sender_id() != get_multiplayer_authority() && multiplayer.get_remote_sender_id() != 0:
		return
	# delete old list
	selector.clear()
	# add new gamemodes
	for gm : String in gamemode_names:
		selector.add_item(gm)

	# Select the currently active gamemode from Global metadata
	var current_gamemode: String = Global.get_meta("current_room_gamemode") if Global.has_meta("current_room_gamemode") else ""
	if current_gamemode != "":
		# Find and select the matching gamemode
		for i in range(selector.get_item_count()):
			if selector.get_item_text(i) == current_gamemode:
				selector.select(i)
				_on_item_selected(i)
				print("[GamemodeMenu] ✅ Selected active gamemode: ", current_gamemode)
				return

	# Fallback: load default params
	_on_item_selected(0)

func _on_item_selected(index : int) -> void:
	# The selected mode from the dropdown
	var gm : String = selector.get_item_text(index)
	# clear existing params to default
	selected_mode_params = [0, 0]
	selected_mode_mods = [0, 0, 0, false]
	for c : Node in param_list.get_children():
		c.queue_free()
	for c : Node in modifier_list.get_children():
		c.queue_free()
	# load new params

	# time limit for all
	add_param_or_mod_adjuster(true, 0, 10, "Time limit (mins)", 1, 999)
	# player speed and jump modifier
	add_param_or_mod_adjuster(false, 0, 5, "Player speed", 5, 10)
	add_param_or_mod_adjuster(false, 2, 1, "Player jump multiplier", 1, 5, true)
	# player health modifier
	add_param_or_mod_adjuster(false, 1, 20, "Player maximum health", 1, 100)
	# low grav toggle modifier
	add_param_or_mod_toggle(false, 3, false, "Low gravity")

	# gamemode-specific
	match (gm):
			"Deathmatch", "Team Deathmatch":
				pass
			"Hide & Seek":
				# change number of starting seekers
				add_param_or_mod_adjuster(true, 1, 1, "# of Seekers", 1, Global.get_world().rigidplayer_list.size() - 1)
			"Capture", "Team Capture":
				# change limit for capture time
				add_param_or_mod_adjuster(true, 1, 60, "Capture Time Limit (s)", 15, 240)
			"Home Run", "Team Home Run":
				# change bat knockback force
				add_param_or_mod_adjuster(true, 1, 10, "Bat Hit Force", 5, 50)
	_apply_host_ui_permissions()
	_broadcast_menu_state_if_host()

func _update_gamemode_params(new_param : int, param_idx : int) -> void:
	selected_mode_params[param_idx] = new_param
	_broadcast_menu_state_if_host()

func _update_gamemode_mods(new_mod : int, mod_idx : int) -> void:
	selected_mode_mods[mod_idx] = new_mod
	_broadcast_menu_state_if_host()

func add_param_or_mod_adjuster(parameter : bool, adj_idx : int, def_val : int, label : String, min_val : int, max_val : int, is_multiplier : bool = false) -> void:
	var adjuster : Control = adjuster_label.instantiate()
	if parameter:
		param_list.add_child(adjuster)
	else:
		modifier_list.add_child(adjuster)
	adjuster.get_node("List/Label").text = label
	var c_adj := adjuster.get_node("List/Adjuster") as Adjuster
	if parameter:
		c_adj.connect("value_changed", _update_gamemode_params.bind(adj_idx))
	else:
		c_adj.connect("value_changed", _update_gamemode_mods.bind(adj_idx))
	c_adj.set_min(min_val)
	c_adj.set_max(max_val)
	c_adj.is_multiplier = is_multiplier
	c_adj.set_value(def_val)
	# different bg colour for modifiers
	if !parameter:
		adjuster.self_modulate = Color("#00f5bd")

func add_param_or_mod_toggle(parameter : bool, adj_idx : int, def_val : bool, label : String) -> void:
	var checkbox : CheckBox = CheckBox.new()
	if parameter:
		param_list.add_child(checkbox)
	else:
		modifier_list.add_child(checkbox)
	checkbox.text = label.capitalize()
	checkbox.button_pressed = def_val as bool
	if parameter:
		checkbox.connect("toggled", _update_gamemode_params.bind(adj_idx))
	else:
		checkbox.connect("toggled", _update_gamemode_mods.bind(adj_idx))
	if parameter:
		checkbox.self_modulate = Color("#fdc0bd")
	else:
		checkbox.self_modulate = Color("#00f5bd")
# Public method to programmatically select a gamemode by index
func select_gamemode(index: int) -> void:
	if index >= 0 and index < selector.get_item_count():
		selector.select(index)
		_on_item_selected(index)
		print("[GamemodeMenu] Gamemode selected: ", selector.get_item_text(index))
	else:
		print("[GamemodeMenu] Invalid gamemode index: ", index)
