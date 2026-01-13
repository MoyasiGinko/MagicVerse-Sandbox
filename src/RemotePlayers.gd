# RemotePlayers - Manages all remote players in the game world
# Spawns/despawns RemotePlayer nodes based on WebSocket messages

extends Node3D
class_name RemotePlayers

var remote_players: Dictionary = {}  # peerId -> RemotePlayer
var remote_player_scene: GDScript = preload("res://src/RemotePlayer.gd")

func _ready() -> void:
	pass

func spawn_remote_player(peer_id: int, name: String, position: Vector3 = Vector3.ZERO) -> RemotePlayer:
	"""Spawn a new remote player"""
	if peer_id in remote_players:
		return remote_players[peer_id]

	print("[RemotePlayers] 👤 Spawned remote player: peer_id=", peer_id, " name=", name)

	# Create RemotePlayer instance
	var remote_player: RemotePlayer = RemotePlayer.new()
	remote_player.name = "RemotePlayer_" + str(peer_id)
	remote_player.peer_id = peer_id
	remote_player.player_name = name

	# Position in world
	remote_player.global_position = position

	# Add to scene
	add_child(remote_player)
	remote_players[peer_id] = remote_player

	return remote_player

func despawn_remote_player(peer_id: int) -> void:
	"""Remove a remote player from the world"""
	if peer_id not in remote_players:
		return

	var player: Node = remote_players[peer_id]
	player.queue_free()
	remote_players.erase(peer_id)

func update_remote_player_state(peer_id: int, position: Vector3, rotation: Vector3, velocity: Vector3) -> void:
	"""Update a remote player's position and rotation"""
	if peer_id not in remote_players:
		return

	remote_players[peer_id].update_state(position, rotation, velocity)

func get_remote_player(peer_id: int) -> RemotePlayer:
	"""Get a remote player by peer ID"""
	return remote_players.get(peer_id)

func get_all_remote_players() -> Array:
	"""Get all remote player nodes"""
	return remote_players.values()

func clear_all_remote_players() -> void:
	"""Remove all remote players (e.g., when leaving room)"""
	for player: Variant in remote_players.values():
		player.queue_free()
	remote_players.clear()
