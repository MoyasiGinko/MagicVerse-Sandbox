# RemotePlayers - Manages all remote players in the game world
# Spawns/despawns RigidPlayer nodes based on WebSocket messages

extends Node3D
class_name RemotePlayers

var remote_players: Dictionary = {}  # peerId -> RigidPlayer
var player_scene: PackedScene = preload("res://data/scene/character/RigidPlayer.tscn")

func _ready() -> void:
	print("[RemotePlayers] Manager initialized")

func spawn_remote_player(peer_id: int, display_name: String, position: Vector3 = Vector3.ZERO) -> RigidPlayer:
	"""Spawn a new RigidPlayer for a remote peer"""
	if peer_id in remote_players:
		print("[RemotePlayers] ⚠️ Player already exists: peer_id=", peer_id)
		return remote_players[peer_id]

	print("[RemotePlayers] 👤 Spawning RigidPlayer for remote peer: peer_id=", peer_id, " name=", display_name)

	# Instantiate RigidPlayer from scene
	var player: RigidPlayer = player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	# Position in world
	player.global_position = position

	# Add to scene (parent should be World node)
	var world: Node = get_parent()
	if world:
		world.add_child(player, true)
		remote_players[peer_id] = player
		print("[RemotePlayers] ✅ RigidPlayer spawned for peer ", peer_id)
		return player
	else:
		push_error("[RemotePlayers] ❌ Could not find World parent!")
		player.queue_free()
		return null

func despawn_remote_player(peer_id: int) -> void:
	"""Remove a remote player from the world"""
	if peer_id not in remote_players:
		return

	print("[RemotePlayers] 👋 Despawning player: peer_id=", peer_id)
	var player: Node = remote_players[peer_id]
	player.queue_free()
	remote_players.erase(peer_id)

func get_remote_player(peer_id: int) -> RigidPlayer:
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
