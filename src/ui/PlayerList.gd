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

extends VBoxContainer
signal player_removed

@onready var player_list_entry : PackedScene = preload("res://data/scene/ui/PlayerListEntry.tscn")
@export var show_team_names := true
var _adapter_hooked := false

func _ready() -> void:
	find_players()
	multiplayer.peer_disconnected.connect(remove_player_by_id)
	Global.connect("player_list_information_update", update_list)
	refresh_from_adapter()

func find_players() -> void:
	# add existing players if this is added to scene later.
	# if the players are already in the list, it will skip them
	# in add_player.
	for p : RigidPlayer in Global.get_world().rigidplayer_list:
		add_player(p)
	# also try to populate from node backend room members if available
	var adapter := _get_node_adapter()
	if adapter != null:
		_populate_from_adapter(adapter)

func refresh_from_adapter() -> void:
	var adapter := _get_node_adapter()
	if adapter == null:
		return
	if !_adapter_hooked:
		adapter.peer_joined_with_name.connect(_on_peer_joined_node)
		adapter.peer_disconnected.connect(_on_peer_left_node)
		_adapter_hooked = true
	_remove_duplicate_entries()
	_populate_from_adapter(adapter)

func update_list() -> void:
	for entry in get_children():
		for player : RigidPlayer in Global.get_world().rigidplayer_list:
			# compare IDs
			if str(player.name) == str(entry.name):
				var k : Label = entry.get_node("HBoxContainer/K")
				var d : Label = entry.get_node("HBoxContainer/D")
				var capture : Label = entry.get_node("HBoxContainer/CaptureTime")
				var player_team : Label = entry.get_node("HBoxContainer/Team")
				k.text = str(player.kills)
				d.text = str(player.deaths)
				# if player has capture time
				if player.capture_time > -1:
					capture.visible = true
					capture.text = str(player.capture_time)
				# hide capture value when not being used (-1)
				else:
					capture.visible = false
				player_team.text = str(player.team)
				# set colour to our team colour.
				if Global.get_world().get_current_map().get_teams().get_team(player.team) != null:
					var team_colour : Color = Global.get_world().get_current_map().get_teams().get_team(player.team).colour
					# make our list entry the colour of our team.
					entry.self_modulate = team_colour
	sort_by_teams()

func sort_by_teams() -> void:
	var sorted_nodes:= get_children()

	sorted_nodes.sort_custom(
		func(a: Node, b: Node) -> bool: return a.get_node("HBoxContainer/Team").text < b.get_node("HBoxContainer/Team").text
	)

	for node in get_children():
		remove_child(node)
	for node in sorted_nodes:
		add_child(node)

func add_player(player : RigidPlayer) -> void:
	for l in get_children():
		# if we're already in the list, dont add
		if l.name == str(player.name):
			return

	# Check if player_list_entry scene loaded correctly
	if player_list_entry == null:
		push_error("PlayerListEntry.tscn failed to load")
		return

	# otherwise, continue
	var player_list_entry_i : Control = player_list_entry.instantiate()
	var player_label : Label = player_list_entry_i.get_node("HBoxContainer/Label")
	var player_team : Label = player_list_entry_i.get_node("HBoxContainer/Team")
	var player_k : Label = player_list_entry_i.get_node("HBoxContainer/K")
	var player_d : Label = player_list_entry_i.get_node("HBoxContainer/D")
	player_label.text = str(player.display_name)
	player_team.text = str(player.team)
	if !show_team_names:
		player_team.visible = false
	player_k.text = str(player.kills)
	player_d.text = str(player.deaths)
	# set colour to our team colour.
	if Global.get_world().get_current_map().get_teams().get_team(player.team) != null:
		var team_colour : Color = Global.get_world().get_current_map().get_teams().get_team(player.team).colour
		# make our list entry the colour of our team.
		player_list_entry_i.self_modulate = team_colour
	# make the name of the object equal our id.
	player_list_entry_i.name = str(player.name)
	# if we are host, show the crown
	if str(player.name).to_int() == 1:
		player_list_entry_i.get_node("HBoxContainer/Crown").visible = true
	# show "YOU" tag for ourselves, not if you're host though
	elif player.display_name == Global.display_name:
		player_list_entry_i.get_node("HBoxContainer/You").visible = true
	add_child(player_list_entry_i)
	sort_by_teams()

# Add player from server room data (for Node backend multiplayer)
func add_player_from_server(peer_id: int, player_name: String, team: int = 0) -> void:
	print("[PlayerList] 👥 Adding player from server: peer_id=", peer_id, " name=", player_name)

	for l in get_children():
		# if we're already in the list, dont add
		if l.name == str(peer_id):
			print("[PlayerList] ⚠️ Player already in list, skipping")
			return
		# guard against duplicate display names for same peer
		var label: Label = l.get_node_or_null("HBoxContainer/Label")
		if label and label.text == player_name and str(peer_id).is_valid_int() and l.name.is_valid_int() and int(l.name) == peer_id:
			print("[PlayerList] ⚠️ Duplicate player name entry, skipping")
			return

	# Check if player_list_entry scene loaded correctly
	if player_list_entry == null:
		push_error("PlayerListEntry.tscn failed to load")
		return

	# Create new player list entry
	var player_list_entry_i : Control = player_list_entry.instantiate()
	var player_label : Label = player_list_entry_i.get_node("HBoxContainer/Label")
	var player_team : Label = player_list_entry_i.get_node("HBoxContainer/Team")
	var player_k : Label = player_list_entry_i.get_node("HBoxContainer/K")
	var player_d : Label = player_list_entry_i.get_node("HBoxContainer/D")

	player_label.text = player_name
	player_team.text = str(team)
	if !show_team_names:
		player_team.visible = false
	player_k.text = "0"
	player_d.text = "0"

	# set colour to our team colour.
	if Global.get_world().get_current_map().get_teams().get_team(str(team)) != null:
		var team_colour : Color = Global.get_world().get_current_map().get_teams().get_team(str(team)).colour
		player_list_entry_i.self_modulate = team_colour

	# make the name of the object equal to peer id
	player_list_entry_i.name = str(peer_id)

	# if peer 1, show the crown (host)
	if peer_id == 1:
		player_list_entry_i.get_node("HBoxContainer/Crown").visible = true
	# show "YOU" tag for ourselves
	elif player_name == Global.display_name:
		player_list_entry_i.get_node("HBoxContainer/You").visible = true

	add_child(player_list_entry_i)
	sort_by_teams()
	print("[PlayerList] ✅ Player added to list")

func remove_player_by_id(id : int) -> void:
	remove_player(Global.get_world().get_node_or_null(str(id)) as RigidPlayer)
	_remove_player_entry_by_id(id)

func remove_player(player : RigidPlayer) -> void:
	if player:
		for l in get_children():
			if l.name == str(player.name):
				l.queue_free()

func _remove_duplicate_entries() -> void:
	var seen := {}
	for l in get_children():
		var key := l.name
		if seen.has(key):
			l.queue_free()
			continue
		seen[key] = true

func _remove_player_entry_by_id(peer_id: int) -> void:
	for l in get_children():
		if l.name == str(peer_id):
			l.queue_free()

func _on_peer_joined_node(peer_id: int, peer_name: String) -> void:
	add_player_from_server(peer_id, peer_name, 0)

func _on_peer_left_node(peer_id: int) -> void:
	_remove_player_entry_by_id(peer_id)

func _populate_from_adapter(adapter: MultiplayerNodeAdapter) -> void:
	var peers := adapter.get_all_peers_with_names()
	for peer_data: Variant in peers:
		if typeof(peer_data) == TYPE_DICTIONARY:
			var peer_dict: Dictionary = peer_data as Dictionary
			var peer_id_val: int = peer_dict.get("peerId", 0) as int
			var peer_name: String = peer_dict.get("name", "Unknown") as String
			if peer_id_val <= 0:
				continue
			add_player_from_server(peer_id_val, peer_name, 0)

func _get_node_adapter() -> MultiplayerNodeAdapter:
	var root: Node = get_tree().root
	if root.has_meta("node_adapter"):
		return root.get_meta("node_adapter") as MultiplayerNodeAdapter
	for child: Node in root.get_children():
		if child.has_meta("node_adapter"):
			return child.get_meta("node_adapter") as MultiplayerNodeAdapter
	return null
