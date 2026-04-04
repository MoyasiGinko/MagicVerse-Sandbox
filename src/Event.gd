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
class_name Event

enum EventType {
	# 1 additonal arg
	TELEPORT_ALL_PLAYERS,
	LOCK_PLAYER_STATES,
	WAIT_FOR_SECONDS,
	# base
	MOVE_ALL_PLAYERS_TO_SPAWN,
	BALANCE_TEAMS,
	CLEAR_LEADERBOARD,
	SHOW_PODIUM,
	SHOW_WORLD_PREVIEW,
	END_ACTIVE_GAMEMODE
}

var event_type : EventType = EventType.TELEPORT_ALL_PLAYERS
var args : Array = []

func _init(e_event_type : EventType, e_args : Array = []) -> void:
	event_type = e_event_type
	args = e_args

func start() -> int:
	# add self to tree
	Global.get_world().add_child(self)
	# only server runs events
	if !multiplayer.is_server():
		queue_free()
		return -1

	match (event_type):
		EventType.TELEPORT_ALL_PLAYERS:
			var players : Array = Global.get_world().rigidplayer_list.duplicate()
			for player_value: Variant in players:
				if player_value == null or !is_instance_valid(player_value):
					continue
				if not (player_value is RigidPlayer):
					continue
				var player: RigidPlayer = player_value as RigidPlayer
				player.protect_spawn()
				# assuming vec3 may be string formatted
				player.teleport.rpc(Global.string_to_vec3(str(args[0])))
		EventType.MOVE_ALL_PLAYERS_TO_SPAWN:
			var players : Array = Global.get_world().rigidplayer_list.duplicate()
			for player_value: Variant in players:
				if player_value == null or !is_instance_valid(player_value):
					continue
				if not (player_value is RigidPlayer):
					continue
				var player: RigidPlayer = player_value as RigidPlayer
				player.set_spawns.rpc(Global.get_world().get_spawnpoint_for_team(player.team))
				player.protect_spawn()
				player.go_to_spawn.rpc()
		EventType.BALANCE_TEAMS:
			var teams : Teams = Global.get_world().get_current_map().get_teams()
			var participants : Array = Global.get_world().rigidplayer_list.duplicate()
			for i in range(participants.size()):
				var participant_value: Variant = participants[i]
				if participant_value == null or !is_instance_valid(participant_value):
					continue
				if not (participant_value is RigidPlayer):
					continue
				var participant: RigidPlayer = participant_value as RigidPlayer
				if (i % 2) == 0:
					participant.update_team.rpc(teams.get_team_list()[1].name)
				else:
					participant.update_team.rpc(teams.get_team_list()[2].name)
				# update info on player's client side
				participant.update_info.rpc_id(participant.get_multiplayer_authority(), participant.get_multiplayer_authority())
		EventType.CLEAR_LEADERBOARD:
			var players : Array = Global.get_world().rigidplayer_list.duplicate()
			for player_value: Variant in players:
				if player_value == null or !is_instance_valid(player_value):
					continue
				if not (player_value is RigidPlayer):
					continue
				var player: RigidPlayer = player_value as RigidPlayer
				player.update_kills(0)
				player.update_deaths(0)
				player.update_capture_time(-1)
				player.update_checkpoint(0)
		EventType.END_ACTIVE_GAMEMODE:
			var gamemodes: Array = Global.get_world().gamemode_list.duplicate()
			for gamemode_value: Variant in gamemodes:
				if gamemode_value == null or !is_instance_valid(gamemode_value):
					continue
				if not (gamemode_value is Gamemode):
					continue
				var gamemode: Gamemode = gamemode_value as Gamemode
				if gamemode.running:
					gamemode.end([args])
		EventType.SHOW_PODIUM:
			if args.size() > 1:
				# arg 0: player 1 id or team id
				if args[1] == "player":
					var players : Array = Global.get_world().rigidplayer_list.duplicate()
					for player_value: Variant in players:
						if player_value == null or !is_instance_valid(player_value):
							continue
						if not (player_value is RigidPlayer):
							continue
						var player: RigidPlayer = player_value as RigidPlayer
						if player.name == str(args[0]):
							player.change_state.rpc_id(player.get_multiplayer_authority(), RigidPlayer.DUMMY)
							# show animation
							var camera : Camera = get_viewport().get_camera_3d()
							if camera is Camera:
								camera.play_podium_animation.rpc(str(args[0]).to_int())
								UIHandler.show_win_label.rpc(str(player.display_name, " wins!"))
							# show podium for voting period
							var voting : VotePanel = get_tree().current_scene.get_node("GameCanvas/VotePanel") as VotePanel
							await voting.voting_ended
							player.change_state.rpc_id(player.get_multiplayer_authority(), RigidPlayer.IDLE)
							UIHandler.hide_win_label.rpc()
				# team name
				elif args[1] == "team":
					var players : Array = Global.get_world().rigidplayer_list.duplicate()
					var winners : Array = []
					for player_value: Variant in players:
						if player_value == null or !is_instance_valid(player_value):
							continue
						if not (player_value is RigidPlayer):
							continue
						var player: RigidPlayer = player_value as RigidPlayer
						print(player.team, " player team, ", str(args[0]))
						if player.team == str(args[0]):
							winners.append(player)
					for winner_value: Variant in winners:
						if winner_value == null or !is_instance_valid(winner_value):
							continue
						if not (winner_value is RigidPlayer):
							continue
						var player: RigidPlayer = winner_value as RigidPlayer
						if winners.is_empty() or winners[0] == null or !is_instance_valid(winners[0]):
							continue
						var podium_anchor: RigidPlayer = winners[0] as RigidPlayer
						player.teleport.rpc_id(player.get_multiplayer_authority(), Vector3(podium_anchor.global_position.x + randf() as float, podium_anchor.global_position.y as float, podium_anchor.global_position.z + randf() as float))
						await get_tree().physics_frame
						player.change_state.rpc_id(player.get_multiplayer_authority(), RigidPlayer.DUMMY)
					# show animation
					var camera : Camera = get_viewport().get_camera_3d()
					if camera is Camera && !winners.is_empty():
						camera.play_podium_animation.rpc(winners[0].get_multiplayer_authority())
						UIHandler.show_win_label.rpc(str(args[0], " team wins!"))
					var voting : VotePanel = get_tree().current_scene.get_node("GameCanvas/VotePanel") as VotePanel
					await voting.voting_ended
					for winner_value: Variant in winners:
						if winner_value == null or !is_instance_valid(winner_value):
							continue
						if not (winner_value is RigidPlayer):
							continue
						var winner: RigidPlayer = winner_value as RigidPlayer
						winner.change_state.rpc_id(winner.get_multiplayer_authority(), RigidPlayer.IDLE)
						winner.protect_spawn()
					UIHandler.hide_win_label.rpc()
		EventType.WAIT_FOR_SECONDS:
			# arg 0: seconds to wait
			# arg 1: whether or not to show countdown
			# arg 2: prefix text
			if args.size() > 0:
				for i : int in range(args[0]):
					# if showing countdown
					# make prefix nothing by default
					var prefix : String = ""
					# if args 2 exists, it's the prefix
					if args[2] as String:
						prefix = args[2]
					if args[1] as bool:
						UIHandler.show_alert.rpc(str(prefix, args[0] as int - i), 1, false, Color.SEA_GREEN)
					await get_tree().create_timer(1).timeout
		EventType.SHOW_WORLD_PREVIEW:
			# arg 0: gamemode name
			# arg 1: subtitle
			# show animation
			var has_previews : bool = false
			for obj in Global.get_world().get_children():
				if obj is CameraPreviewPoint:
					has_previews = true
			if has_previews:
				var camera : Camera = get_viewport().get_camera_3d()
				if camera is Camera:
					# camera movements
					camera.play_preview_animation.rpc()
					# play preview overlay
					if args.size() < 1:
						# don't show name if there is none
						args[0] = ""
					if args.size() < 2:
						# don't show subtitle if there is none
						args[1] = ""
					UIHandler.play_preview_animation_overlay.rpc(str(args[0]), str(args[1]))
					# wait for animation to finish before running next events
					await get_tree().create_timer(10).timeout
			# fallback
			else:
				UIHandler.show_alert.rpc(str("Gamemode started: ", args[0]), 5, false, UIHandler.alert_colour_gold)
		_:
			printerr("Failed to run event because the event type is not valid.")

	queue_free()
	return 0
