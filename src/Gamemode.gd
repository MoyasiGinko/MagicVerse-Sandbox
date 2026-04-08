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
class_name Gamemode
signal gamemode_ended

var params : Array
var mods : Array
var gamemode_name := "Gamemode"
var gamemode_subtitle := "A new gamemode has been started!"
var running := false
var _force_local_sync : bool = false
# defaults to 600 seconds or 10 mins
var time_limit_seconds : int = 600
@onready var game_timer : Timer = Timer.new()
@onready var timer_ui : GameTimer = get_tree().current_scene.get_node("GameCanvas/Timer") as ProgressBar
@onready var vote_panel : VotePanel = get_tree().current_scene.get_node("GameCanvas/VotePanel") as VotePanel

func _get_node_adapter() -> MultiplayerNodeAdapter:
	return Global.get_node_adapter()

func _is_node_host() -> bool:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	return adapter != null and adapter.is_server()

func _is_node_client_replica() -> bool:
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	return adapter != null and !adapter.is_server()

func _connect_player_join_sync() -> void:
	if multiplayer.is_server() and !multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and !adapter.peer_connected.is_connected(_on_peer_connected):
		adapter.peer_connected.connect(_on_peer_connected)

func _disconnect_player_join_sync() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.peer_connected.is_connected(_on_peer_connected):
		adapter.peer_connected.disconnect(_on_peer_connected)

func start(_params : Array, _mods : Array, force_local : bool = false) -> void:
	# only server starts games
	_force_local_sync = force_local
	if !multiplayer.is_server() and !_force_local_sync: return
	# make sure if someone joins mid-game the properties sync
	_connect_player_join_sync()

	params = _params
	mods = _mods

	print(get_multiplayer_authority(), " - Started gamemode: ", gamemode_name, " with params ", params, " and modifiers ", mods)
	# clear player inventories
	var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
	for p_value: Variant in players_snapshot:
		if p_value == null or !is_instance_valid(p_value):
			continue
		if not (p_value is RigidPlayer):
			continue
		var p: RigidPlayer = p_value as RigidPlayer
		set_parameters(p)
	if params.size() > 0:
		# the time limit chooser is in minutes but this is in
		# seconds so we convert
		time_limit_seconds = params[0] * 60
	if _force_local_sync and Global.has_meta("pending_active_gamemode_started_at_ms"):
		var started_var: Variant = Global.get_meta("pending_active_gamemode_started_at_ms")
		var started_at_ms: int = int(started_var as float)
		if started_at_ms > 0:
			var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
			if Global.has_meta("pending_active_gamemode_server_now_ms"):
				var server_now_var: Variant = Global.get_meta("pending_active_gamemode_server_now_ms")
				var server_now_ms: int = int(server_now_var as float)
				if server_now_ms > 0:
					now_ms = server_now_ms
			if _is_node_client_replica():
				# Node replicas show timer after preview; account for that elapsed time up front.
				now_ms += 10000
			var elapsed_secs: int = maxi(0, int((now_ms - started_at_ms) / 1000))
			time_limit_seconds = maxi(1, time_limit_seconds - elapsed_secs)
		Global.remove_meta("pending_active_gamemode_started_at_ms")
		if Global.has_meta("pending_active_gamemode_server_now_ms"):
			Global.remove_meta("pending_active_gamemode_server_now_ms")
	elif _force_local_sync and Global.has_meta("pending_active_gamemode_remaining_secs"):
		var remaining_var: Variant = Global.get_meta("pending_active_gamemode_remaining_secs")
		var remaining_secs: int = int(remaining_var as float)
		if remaining_secs > 0:
			time_limit_seconds = remaining_secs
		Global.remove_meta("pending_active_gamemode_remaining_secs")
	run()

# Sync parameters on player join.
func _on_peer_connected(id : int) -> void:
	var joined_player : RigidPlayer
	while joined_player == null:
		joined_player = Global.get_world().get_node_or_null(str(id)) as RigidPlayer
		await get_tree().physics_frame
	set_parameters(joined_player)
	if running:
		set_run_parameters(joined_player)
	if timer_ui != null:
		timer_ui.set_visible_rpc.rpc_id(id, true)
		timer_ui.set_max_val_rpc.rpc_id(id, time_limit_seconds)

func set_parameters(p : RigidPlayer) -> void:
	if p == null or !is_instance_valid(p):
		return
	if _force_local_sync:
		p.get_tool_inventory().delete_all_tools()
		if mods.size() > 0:
			p.set_move_speed(mods[0] as float)
		if mods.size() > 1:
			# set player health locally
			p.set_max_health(mods[1] as int)
			# Use sync-health path so late/rejoin clients fill correctly even during spawn protection.
			p._receive_server_health(p.max_health as int)
		if mods.size() > 2:
			# jump force is a multiplier
			p.set_jump_force(2.4 * mods[2] as float)
		if mods.size() > 3:
			Global.get_world().get_current_map().set_gravity(mods[3] as bool)
	else:
		var adapter: MultiplayerNodeAdapter = _get_node_adapter()
		p.get_tool_inventory().delete_all_tools.rpc()
		if mods.size() > 0:
			p.set_move_speed.rpc(mods[0] as float)
		if mods.size() > 1:
			# set player health as server
			p.set_max_health(mods[1] as int)
			# fill the health
			p.set_health(p.max_health as int)
			if adapter != null and adapter.is_server() and !p.is_local_player:
				adapter.send_rpc_call("remote_set_health", [p.get_multiplayer_authority(), p.max_health], p.get_multiplayer_authority())
		if mods.size() > 2:
			# jump force is a multiplier
			p.set_jump_force.rpc(2.4 * mods[2] as float)
		if mods.size() > 3:
			# set low gravity toggle to on
			Global.get_world().get_current_map().set_gravity.rpc(mods[3] as bool)

func set_run_parameters(p : RigidPlayer) -> void:
	pass

func _clear_leaderboard_local() -> void:
	var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
	for player_value: Variant in players_snapshot:
		if player_value == null or !is_instance_valid(player_value):
			continue
		if not (player_value is RigidPlayer):
			continue
		var player: RigidPlayer = player_value as RigidPlayer
		player.update_kills(0)
		player.update_deaths(0)
		player.update_capture_time(-1)
		player.update_checkpoint(0)

func _balance_teams_local() -> void:
	var teams : Teams = Global.get_world().get_current_map().get_teams()
	var participants : Array = Global.get_world().rigidplayer_list.duplicate()
	for i : int in range(participants.size()):
		var player_value: Variant = participants[i]
		if player_value == null or !is_instance_valid(player_value):
			continue
		if not (player_value is RigidPlayer):
			continue
		var player: RigidPlayer = player_value as RigidPlayer
		if (i % 2) == 0:
			player.update_team(str(teams.get_team_list()[1].name))
		else:
			player.update_team(str(teams.get_team_list()[2].name))
		player.update_info(player.get_multiplayer_authority())

func _move_all_players_to_spawn_local() -> void:
	var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
	for player_value: Variant in players_snapshot:
		if player_value == null or !is_instance_valid(player_value):
			continue
		if not (player_value is RigidPlayer):
			continue
		var player: RigidPlayer = player_value as RigidPlayer
		player.set_spawns(Global.get_world().get_spawnpoint_for_team(player.team))
		player.protect_spawn()
		player.go_to_spawn()

func _reset_teams_to_default_local() -> void:
	var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
	for player_value: Variant in players_snapshot:
		if player_value == null or !is_instance_valid(player_value):
			continue
		if not (player_value is RigidPlayer):
			continue
		var player: RigidPlayer = player_value as RigidPlayer
		player.update_team("Default")

func run() -> void:
	# only server starts games
	if !multiplayer.is_server() and !_force_local_sync: return
	if _is_node_client_replica():
		var game_canvas: CanvasItem = get_tree().current_scene.get_node_or_null("GameCanvas") as CanvasItem
		if game_canvas != null:
			game_canvas.visible = false
		var cam: Camera = get_viewport().get_camera_3d() as Camera
		if cam != null:
			cam.play_preview_animation(10)
		UIHandler.play_preview_animation_overlay(gamemode_name, gamemode_subtitle)
		await get_tree().create_timer(10).timeout
		if game_canvas != null:
			game_canvas.visible = true
		running = true
		if timer_ui != null:
			timer_ui.set_visible_rpc(true)
			timer_ui.set_max_val_rpc(time_limit_seconds)
			timer_ui.apply_timer_from_node(gamemode_name, float(time_limit_seconds), time_limit_seconds)
		return
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null and adapter.is_server() and !_force_local_sync:
		var world_pre: World = Global.get_world()
		if world_pre != null:
			var gm_idx_pre: int = world_pre.gamemode_list.find(self)
			if gm_idx_pre >= 0:
				var preview_duration_ms: int = 10000
				var started_ms_pre: int = int(Time.get_unix_time_from_system() * 1000.0) + preview_duration_ms
				adapter.send_rpc_call("remote_start_gamemode", [gm_idx_pre, params.duplicate(true), mods.duplicate(true), started_ms_pre], 0)
				adapter.send_rpc_call("remote_gamemode_menu_sync", [gm_idx_pre, params.duplicate(true), mods.duplicate(true)], 0)
	var preview_event : Event = Event.new(Event.EventType.SHOW_WORLD_PREVIEW, [gamemode_name, gamemode_subtitle])
	await preview_event.start()

	running = true
	# start default timer
	game_timer.one_shot = true
	game_timer.wait_time = time_limit_seconds
	game_timer.connect("timeout", end.bind([]))
	add_child(game_timer)
	game_timer.start()
	if timer_ui != null:
		if _force_local_sync:
			timer_ui.set_visible_rpc(true)
			timer_ui.set_max_val_rpc(time_limit_seconds)
		else:
			timer_ui.set_visible_rpc.rpc(true)
			timer_ui.set_max_val_rpc.rpc(time_limit_seconds)
		update_timer()

func update_timer() -> void:
	if not running:
		return
	if game_timer == null or !is_instance_valid(game_timer):
		return
	if timer_ui == null or !is_instance_valid(timer_ui):
		return
	var adapter: MultiplayerNodeAdapter = _get_node_adapter()
	if adapter != null:
		if adapter.is_server():
			var remaining: float = maxf(0.0, game_timer.time_left)
			timer_ui.apply_timer_from_node(gamemode_name, remaining, time_limit_seconds)
			adapter.send_rpc_call("remote_gamemode_timer_sync", [gamemode_name, remaining, time_limit_seconds], 0)
		else:
			# Node clients receive authoritative timer packets from host.
			pass
	elif _force_local_sync:
		var timer_text : Label = timer_ui.get_node_or_null("Label")
		if timer_text != null:
			var mins := str(int(game_timer.time_left as int / 60))
			var seconds := str('%02d' % (int(game_timer.time_left as int) % 60))
			timer_text.text = str(gamemode_name, " - ", mins, ":", seconds)
			timer_ui.value = game_timer.time_left
	else:
		timer_ui.update_timer.rpc(gamemode_name, game_timer.time_left)
	# update every 1s
	await get_tree().create_timer(1).timeout
	if running and is_instance_valid(self):
		update_timer()

func _build_node_match_report_payload(args: Array) -> Dictionary:
	var elapsed_seconds: int = time_limit_seconds
	if game_timer != null and is_instance_valid(game_timer):
		elapsed_seconds = maxi(0, time_limit_seconds - int(floor(game_timer.time_left)))

	var winner_kind: String = ""
	var winner_value: Variant = null
	if args.size() > 1:
		winner_kind = str(args[1])
		winner_value = args[0]

	var leaderboard: Array = []
	var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
	for player_value: Variant in players_snapshot:
		if player_value == null or !is_instance_valid(player_value):
			continue
		if not (player_value is RigidPlayer):
			continue
		var player: RigidPlayer = player_value as RigidPlayer
		var won: bool = false
		if winner_kind == "player":
			won = int(player.get_multiplayer_authority()) == int(winner_value as float)
		elif winner_kind == "team":
			won = player.team == str(winner_value)
		leaderboard.append({
			"peer_id": int(player.get_multiplayer_authority()),
			"kills": int(player.kills),
			"deaths": int(player.deaths),
			"capture_time": int(player.capture_time),
			"checkpoint": int(player.checkpoint),
			"playtime_seconds": elapsed_seconds,
			"won": won,
		})

	var payload: Dictionary = {
		"gamemode": gamemode_name,
		"duration_seconds": elapsed_seconds,
		"winner_type": winner_kind,
		"leaderboard": leaderboard,
	}
	if winner_kind == "player" and winner_value != null:
		payload["winner_peer_id"] = int(winner_value as float)
	elif winner_kind == "team" and winner_value != null:
		payload["winner_team"] = str(winner_value)
	return payload

func end(params : Array) -> void:
	# only server ends games
	if !multiplayer.is_server() and !_force_local_sync: return
	_disconnect_player_join_sync()
	print(get_multiplayer_authority(), " - Ended gamemode: ", gamemode_name)
	# cleanup and run any final stuff
	var players_snapshot: Array = Global.get_world().rigidplayer_list.duplicate()
	for p_value: Variant in players_snapshot:
		if p_value == null or !is_instance_valid(p_value):
			continue
		if not (p_value is RigidPlayer):
			continue
		var p: RigidPlayer = p_value as RigidPlayer
		if _force_local_sync:
			p.get_tool_inventory().reset()
		else:
			p.get_tool_inventory().reset.rpc()
		p.update_kills(0)
		p.update_deaths(0)
		p.update_capture_time(-1)
		p.update_checkpoint(0)
		# reset player stuff
		p.set_max_health(20)
		if _force_local_sync:
			p.set_move_speed(5)
			p.set_jump_force(2.4)
		else:
			p.set_move_speed.rpc(5)
			p.set_jump_force.rpc(2.4)
		# reset map gravity, in case it changed
		if _force_local_sync:
			Global.get_world().get_current_map().set_gravity(false)
		else:
			Global.get_world().get_current_map().set_gravity.rpc(false)
	# never free gamemodes because they are saved as part of the world
	emit_signal("gamemode_ended")
	running = false
	if timer_ui != null:
		if _force_local_sync:
			timer_ui.set_visible_rpc(false)
		else:
			timer_ui.set_visible_rpc.rpc(false)
	# stop timer
	if game_timer.is_connected("timeout", end.bind([])):
		game_timer.disconnect("timeout", end.bind([]))
	game_timer.stop()
	if not _force_local_sync:
		var adapter: MultiplayerNodeAdapter = Global.get_node_adapter()
		if adapter != null and adapter.is_server():
			adapter.send_rpc_call("remote_end_gamemode", [_build_node_match_report_payload(params)])
	# show vote screen
	# only runs as server
	vote_panel.start_voting()
	_force_local_sync = false
