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

extends AnimatedPanelContainer
class_name VotePanel
signal voting_ended

@onready var grid : GridContainer = get_node("VBoxContainer/GridContainer")
var buttons : Array = []
var maps : Array = []
var player_votes : Dictionary = {}
var vote_timer : Timer
var _pending_selected_map_name: String = ""

func _get_node_adapter() -> MultiplayerNodeAdapter:
	return Global.get_node_adapter()

func _is_node_host() -> bool:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	return adapter != null and adapter.is_server()

func _is_vote_authority() -> bool:
	if _is_node_host():
		return true
	return multiplayer.is_server()

func _get_active_vote_member_count() -> int:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null:
		var room_member_count: int = adapter.room_members.size()
		if room_member_count > 0:
			return room_member_count
	var world: World = Global.get_world()
	if world == null:
		return 0
	return world.rigidplayer_list.size()

func _broadcast_vote_timer(seconds_left: int) -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.is_server():
		adapter.send_rpc_call("remote_vote_timer_update", [seconds_left], 0)
	update_timer_rpc(seconds_left)

func _broadcast_vote_counts() -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.is_server():
		adapter.send_rpc_call("remote_vote_update_counts", [player_votes], 0)
	update_player_votes(player_votes)

func _broadcast_show_panel() -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.is_server():
		adapter.send_rpc_call("remote_vote_show_panel", [maps], 0)
	show_panel(maps)

func _broadcast_voting_ended() -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.is_server():
		adapter.send_rpc_call("remote_vote_ended", [], 0)
	on_voting_ended_rpc()

func _broadcast_hide_panel() -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.is_server():
		adapter.send_rpc_call("remote_vote_hide_panel", [], 0)
	hide_panel()

func _open_selected_map_lines(selected_lines: Array, selected_name: String) -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	Global.set_meta("current_room_map", selected_name)
	if adapter != null and adapter.is_server():
		var packed_lines := PackedStringArray()
		for line_value: Variant in selected_lines:
			packed_lines.append(str(line_value))
		adapter.load_tbw(packed_lines)
		return
	Global.get_world().open_tbw(selected_lines)

func apply_vote_from_peer(from_peer_id: int, idx: int) -> void:
	if !_is_vote_authority():
		return
	if idx < 0 or idx > 5:
		return
	player_votes[str(from_peer_id)] = idx
	_broadcast_vote_counts()

func _ready() -> void:
	super()
	buttons.append(get_node("VBoxContainer/GridContainer/Opt1"))
	buttons.append(get_node("VBoxContainer/GridContainer/Opt2"))
	buttons.append(get_node("VBoxContainer/GridContainer/Opt3"))
	buttons.append(get_node("VBoxContainer/GridContainer/Opt4"))
	buttons.append(get_node("VBoxContainer/GridContainer/Replay"))
	buttons.append(get_node("VBoxContainer/GridContainer/Sandbox"))

	vote_timer = Timer.new()
	vote_timer.wait_time = 20
	vote_timer.one_shot = true
	vote_timer.connect("timeout", _on_vote_timeout)
	add_child(vote_timer)

# only runs as server
func start_voting() -> void:
	if !_is_vote_authority():
		return
	maps = []
	player_votes = {}
	# populate list with random maps
	var req : HTTPRequest = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(self._maps_request_completed)
							# REST API on my website that hosts tinybox world files.
	var error := req.request(str(UserPreferences.database_repo))
	if error != OK:
		push_error("An error occurred in the HTTP request.")

func update_timer() -> void:
	if player_votes.size() >= _get_active_vote_member_count():
		vote_timer.stop()
		_on_vote_timeout()
	if !vote_timer.is_stopped():
		_broadcast_vote_timer(int(vote_timer.time_left))
		await get_tree().create_timer(1).timeout
		update_timer()

# Send timer update to peers
@rpc("any_peer", "call_local", "reliable")
func update_timer_rpc(time : int) -> void:
	get_node("VBoxContainer/HBoxContainer/Timer").text = str(time, "s")

@rpc("any_peer", "call_local", "reliable")
func on_voting_ended_rpc() -> void:
	emit_signal("voting_ended")

# runs as server
func _on_vote_timeout() -> void:
	_broadcast_voting_ended()
	var votes : Array = [0, 0, 0, 0, 0, 0]
	for vote : int in player_votes.values():
		votes[vote] += 1
	var highest_vote : int = 5
	# in this case, highest_vote is idx 0-5
	for i in 6:
		if votes[i] > votes[highest_vote]:
			highest_vote = i
	# If a map option was selected but there are fewer than 4 map entries, fall back safely.
	if highest_vote < 4 and highest_vote >= maps.size():
		highest_vote = 0 if maps.size() > 0 else 5
	# for 1-4, choose map
	# for 5, reload map and restart last gamemode
	# for 6, enter sandbox (do nothing)
	match (highest_vote):
		4:
			# replay
			if _is_node_host():
				Global.server_start_gamemode(Global.last_gamemode_idx, Global.last_gamemode_params, Global.last_gamemode_mods)
			else:
				Global.server_start_gamemode.rpc_id(1, Global.last_gamemode_idx, Global.last_gamemode_params, Global.last_gamemode_mods)
		5:
			# sandbox
			var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
			for player_value: Variant in players_snapshot:
				if player_value == null or !is_instance_valid(player_value):
					continue
				if not (player_value is RigidPlayer):
					continue
				var player: RigidPlayer = player_value as RigidPlayer
				player.change_state.rpc_id(player.get_multiplayer_authority(), RigidPlayer.IDLE)
				player.go_to_spawn()
				player.protect_spawn()
		_:
			var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
			for player_value: Variant in players_snapshot:
				if player_value == null or !is_instance_valid(player_value):
					continue
				if not (player_value is RigidPlayer):
					continue
				var player: RigidPlayer = player_value as RigidPlayer
				player.change_state.rpc_id(player.get_multiplayer_authority(), RigidPlayer.IDLE)
				player.protect_spawn()
			# get map based on ID
			var map_id : int = maps[highest_vote]["id"]

			# built-in
			if map_id == -1:
				var selected_name: String = str(maps[highest_vote]["name"])
				_open_selected_map_lines(Global.get_tbw_lines(selected_name), selected_name)
			else:
				# browser
				_pending_selected_map_name = str(maps[highest_vote]["name"])
				var req : HTTPRequest = HTTPRequest.new()
				add_child(req)
				req.request_completed.connect(self._switch_map)
									# REST API on my website that hosts tinybox world files.
				var error := req.request(str(UserPreferences.database_repo, "?id=", map_id))
				if error != OK:
					push_error("An error occurred in the HTTP request.")
	_broadcast_hide_panel()

func _switch_map(result : int, response_code : int, headers : PackedStringArray, body : PackedByteArray) -> void:
	# get full map tbw now that map has been selected
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var response : Variant = json.get_data()
	if response is Array:
		if response[0] is Dictionary:
			if response[0].has("tbw"):
				var lines : PackedStringArray = str(response[0]["tbw"]).split("\n")
				_open_selected_map_lines(lines, _pending_selected_map_name)

func _maps_request_completed(result : int, response_code : int, headers : PackedStringArray, body : PackedByteArray) -> void:
	if (response_code != 200):
		return

	vote_timer.wait_time = 20
	vote_timer.one_shot = true
	vote_timer.start()
	update_timer()

	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var response : Variant = json.get_data()
	# Add 4 votable maps; 2 from browser, 2 from built-in.
	# Selection of good built in gamemode maps.
	var built_in_maps : Array = [\
		"Icy Inclines",
		"Tunnel Tussle",
		"Acid House",
		"Warp Spire",
		"Quarry Quarrel",
		"Perilous Platforms",
		"Slapdash Central"]

	for i in 2:
		var map_name : String = built_in_maps.pick_random()
		maps.append({"name": map_name, "id": -1, "image": "-1", "author": "Tinybox"})
		# pop from array pool
		built_in_maps.pop_at(built_in_maps.find(map_name))
	if response is Array:
		var response_maps : Array = (response as Array).duplicate()
		for i in 2:
			if response_maps.is_empty():
				break
			var r : Variant = response_maps.pick_random()
			if r is Dictionary:
				var map_name := "(no name)"
				var id : int = -1
				var image : String = ""
				var author : String = ""
				if r.has("name"):
					map_name = r["name"]
				if r.has("image"):
					image = r["image"]
					author = r["author"]
				if r.has("id"):
					id = r["id"] as int
				maps.append({"name": map_name, "id": id, "image": image, "author": author})
			# pop from array pool
			response_maps.pop_at(response_maps.find(r))
	while maps.size() < 4 and not built_in_maps.is_empty():
		var fallback_name : String = built_in_maps.pick_random()
		maps.append({"name": fallback_name, "id": -1, "image": "-1", "author": "Tinybox"})
		built_in_maps.pop_at(built_in_maps.find(fallback_name))
	_broadcast_show_panel()

@rpc("any_peer", "call_local", "reliable")
func show_panel(maps : Array) -> void:
	player_votes = {}
	update_player_votes(player_votes)

	visible = true
	var map_count : int = mini(4, maps.size())
	for i in 4:
		if i >= map_count:
			buttons[i].disabled = true
			buttons[i].get_node("Split/Labels/Title").text = "Unavailable"
			buttons[i].get_node("Split/Labels/Author").text = ""
			buttons[i].get_node("Split/Image").texture = null
			continue
		buttons[i].disabled = false
		buttons[i].get_node("Split/Labels/Title").text = maps[i]["name"]
		buttons[i].get_node("Split/Labels/Author").text = str("by ", maps[i]["author"])
		if buttons[i].is_connected("pressed", _on_vote):
			buttons[i].disconnect("pressed", _on_vote)
		buttons[i].connect("pressed", _on_vote.bind(i))
		var image : Variant
		# built-in
		if (maps[i]["id"] == -1):
			image = Global.get_tbw_image_from_lines(Global.get_tbw_lines(str(maps[i]["name"])))
		# from browser
		else:
			image = Global.get_tbw_image_from_lines([str("image ; ", maps[i]["image"])])
		var tex : ImageTexture
		if image != null:
			image.resize(240, 162)
			tex = ImageTexture.create_from_image(image as Image)
			buttons[i].get_node("Split/Image").texture = tex
	if buttons[4].is_connected("pressed", _on_vote):
		buttons[4].disconnect("pressed", _on_vote)
	if buttons[5].is_connected("pressed", _on_vote):
		buttons[5].disconnect("pressed", _on_vote)
	buttons[4].connect("pressed", _on_vote.bind(4))
	buttons[5].connect("pressed", _on_vote.bind(5))

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_vote(idx : int) -> void:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null:
		if adapter.is_server():
			apply_vote_from_peer(adapter.get_unique_peer_id(), idx)
		else:
			adapter.send_rpc_call("remote_vote_submit", [idx, adapter.get_unique_peer_id()], 1)
		return
	send_vote_to_server.rpc_id(1, idx)

@rpc("any_peer", "call_local", "reliable")
func send_vote_to_server(idx : int) -> void:
	player_votes[str(multiplayer.get_remote_sender_id())] = idx
	update_player_votes.rpc(player_votes)

@rpc("any_peer", "call_local", "reliable")
func update_player_votes(_player_votes : Dictionary) -> void:
	for i in 6:
		var this_map_votes : int = 0
		for vote : Variant in _player_votes.values():
			if str(vote) == str(i):
				this_map_votes += 1
		if this_map_votes == 0:
			# no text for no votes
			buttons[i].get_node("Split/Labels/VoteCount").text = ""
		else:
			buttons[i].get_node("Split/Labels/VoteCount").text = str(this_map_votes, " votes")

@rpc("any_peer", "call_local", "reliable")
func hide_panel() -> void:
	visible = false
	if !Global.is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
