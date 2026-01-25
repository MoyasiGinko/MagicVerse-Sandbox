# Tinybox Node.js Backend Adapter
# Bridges WebSocket communication with Godot's multiplayer system
extends Node
class_name MultiplayerNodeAdapter

signal room_created(room_id: String)
signal room_joined(peer_id: int, room_id: String)
signal connection_failed(reason: String)
signal rooms_list_changed  # New signal for room list changes
signal peer_connected(peer_id: int)  # For multiplayer system integration
signal peer_disconnected(peer_id: int)  # For multiplayer system integration
signal peer_joined_with_name(peer_id: int, peer_name: String)  # For player list updates

var ws: WebSocketPeer = null
var server_url: String = "ws://localhost:30820"
var _peer_id: int = 0
var _room_id: String = ""
var _connected_peers: PackedInt32Array = []
var _is_connected: bool = false
var _is_server: bool = false  # Will be true if this peer is the host
var _pending_members: Array = []  # Store members received before World is ready
var room_members: Array = []  # Public accessor for room member list

func _init() -> void:
	ws = WebSocketPeer.new()

func connect_to_server(url: String) -> bool:
	server_url = url
	var err: Error = ws.connect_to_url(server_url)
	if err != OK:
		push_error("Failed to connect to Node backend: " + str(err))
		return false
	_is_connected = false
	return true

func _process(_delta: float) -> void:
	if ws == null:
		return

	ws.poll()
	var state: WebSocketPeer.State = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _is_connected:
			_is_connected = true

		while ws.get_available_packet_count() > 0:
			_on_ws_message()

	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_is_connected = false
			connection_failed.emit("Connection closed")

func _on_ws_message() -> void:
	var packet: PackedByteArray = ws.get_packet()
	var json_str: String = packet.get_string_from_utf8()
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_str)

	if parse_result != OK:
		push_error("Failed to parse JSON: " + json_str)
		return

	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Invalid message format")
		return

	var msg_type: String = data.get("type", "")
	var msg_data: Dictionary = data.get("data", {})

	match msg_type:
		"handshake_accepted":
			_handle_handshake_accepted(msg_data)
		"state":
			_handle_state(msg_data)
		"rpc", "rpc_call":
			_handle_rpc(msg_data)
		"sync":
			_handle_sync(msg_data)
		"error":
			_handle_error(msg_data)
		"room_created":
			_handle_room_created(msg_data)
		"room_joined":
			_handle_room_joined(msg_data)
		"rooms_changed":
			_handle_rooms_changed()
		"peer_joined":
			_handle_peer_joined(msg_data)
		"peer_left":
			_handle_peer_left(msg_data)
		"player_state":
			_handle_player_state(msg_data)
		_:
			push_warning("Unknown message type: " + str(msg_type))

func _handle_handshake_accepted(data: Dictionary) -> void:
	print("[NodeAdapter] ✅ Handshake accepted")

func _handle_room_created(data: Dictionary) -> void:
	_room_id = data.get("roomId", "")
	_peer_id = data.get("peerId", 1)
	print("[NodeAdapter] ✅ Room created: ", _room_id, " (peer ", _peer_id, ")")

	# For host: also trigger room_joined so player list gets populated
	_is_server = (_peer_id == 1)
	room_joined.emit(_peer_id, _room_id)  # Emit room_joined for host too

	room_created.emit(_room_id)
	UIHandler.show_alert("Room created: " + _room_id, 6, false, UIHandler.alert_colour_player)

func _handle_room_joined(data: Dictionary) -> void:
	_room_id = data.get("roomId", "")
	_peer_id = data.get("peerId", 0)
	# Store map and gamemode from backend - joiners need this to load correct room settings
	var map_name: String = data.get("mapName", "Frozen Field") as String
	var gamemode: String = data.get("gamemode", "Deathmatch") as String
	Global.set_meta("current_room_map", map_name)
	Global.set_meta("current_room_gamemode", gamemode)
	Global.set_meta("current_room_id", _room_id)
	print("[NodeAdapter] 🗺️ Room settings stored: map=", map_name, " gamemode=", gamemode)

	# Backend sends 'members' array with {peerId, name, isHost} objects
	var members: Array = data.get("members", [])
	_connected_peers.clear()
	_pending_members.clear()  # Clear pending - Main.gd will spawn existing members from room_members
	room_members.clear()

	var seen_ids := {}
	for member: Variant in members:
		if typeof(member) == TYPE_DICTIONARY:
			var member_dict: Dictionary = member as Dictionary
			var peer_id: int = member_dict.get("peerId", 0) as int
			var peer_name: String = member_dict.get("name", "Unknown") as String
			if seen_ids.has(peer_id):
				continue
			seen_ids[peer_id] = true

			# Add all members to room_members (including self)
			room_members.append({"peerId": peer_id, "name": peer_name})

			# Skip self for connected_peers
			if peer_id == _peer_id:
				continue

			# Add to connected peers list
			if not _connected_peers.has(peer_id):
				_connected_peers.append(peer_id)

			# DON'T add to pending_members - Main.gd will spawn from room_members
			# pending_members is only for peers that join AFTER world is loaded

	# Peer 1 is always the host in the Node backend
	_is_server = (_peer_id == 1)

	print("[NodeAdapter] ✅ Room joined: ", _room_id, " peers=", _connected_peers.size(), " (is_server=", _is_server, ")")

	# Emit peer_connected signal for each connected peer (for Godot's multiplayer system)
	for peer_id in _connected_peers:
		peer_connected.emit(peer_id)

	room_joined.emit(_peer_id, _room_id)

func _handle_state(data: Dictionary) -> void:
	var state_type: String = data.get("type", "")
	match state_type:
		"room_created":
			_room_id = data.get("roomId", "")
			_peer_id = 1  # Host is always peer 1
			_is_server = true
			room_created.emit(_room_id)
			UIHandler.show_alert("Room created: " + _room_id, 6, false, UIHandler.alert_colour_player)
		"room_joined":
			_room_id = data.get("roomId", "")
			_peer_id = data.get("peerId", 0)
			var peers: Array = data.get("peers", [])
			_connected_peers.clear()
			for p: Variant in peers:
				if typeof(p) == TYPE_INT:
					_connected_peers.append(p as int)
				elif typeof(p) == TYPE_FLOAT:
					_connected_peers.append(int(p as float))
			_is_server = (_peer_id == 1)

			# Emit peer_connected signal for each connected peer
			for peer_id in _connected_peers:
				peer_connected.emit(peer_id)

			room_joined.emit(_peer_id, _room_id)
		"peer_joined":
			var peer_id: int = data.get("peerId", 0)
			if peer_id > 0 and not _connected_peers.has(peer_id):
				_connected_peers.append(peer_id)
				print("[NodeAdapter] 👤 Peer joined: ", peer_id)
				peer_connected.emit(peer_id)
		"peer_left":
			var peer_id: int = data.get("peerId", 0)
			if _connected_peers.has(peer_id):
				_connected_peers.erase(peer_id)
				print("[NodeAdapter] 👤 Peer left: ", peer_id)
				peer_disconnected.emit(peer_id)

func _handle_rpc(data: Dictionary) -> void:
	var method_name: String = data.get("method", "")
	var args: Array = data.get("args", [])
	var from_peer: int = data.get("from", 0)
	print("[NodeAdapter] 📥 rpc_call method=", method_name, " from=", from_peer, " args=", args)

	# Route to existing Godot methods on Main or World
	var main: Node = get_tree().current_scene
	if main and main.has_method(method_name):
		match args.size():
			0:
				main.call(method_name)
			1:
				main.call(method_name, args[0])
			2:
				main.call(method_name, args[0], args[1])
			3:
				main.call(method_name, args[0], args[1], args[2])
			_:
				main.callv(method_name, args)
		return

	var world: Node = Global.get_world()
	if world and world.has_method(method_name):
		world.callv(method_name, args)
		return

func _handle_sync(data: Dictionary) -> void:
	# Handle player state snapshots
	var peer_id: int = data.get("peerId", 0)
	var state: Dictionary = data.get("state", {})
	# Forward to world/player sync system
	pass

func _handle_error(data: Dictionary) -> void:
	var code: String = data.get("code", "")
	var message: String = data.get("message", "Unknown error")
	push_error("Backend error: " + message)
	UIHandler.show_alert(message, 8, false, UIHandler.alert_colour_error)
	connection_failed.emit(message)

func _handle_rooms_changed() -> void:
	"""Handle room list change notification from backend"""
	print("[NodeAdapter] 🔔 Rooms list changed on backend, triggering refresh")
	rooms_list_changed.emit()

# Send message to backend
func _send_message(msg_type: String, msg_data: Dictionary) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_error("Cannot send message: WebSocket not open")
		return

	var message: Dictionary = {"type": msg_type, "data": msg_data}
	var json_str: String = JSON.stringify(message)
	ws.send_text(json_str)

# Protocol methods
func send_handshake(version: String, player_name: String, token: String = "") -> void:
	"""Send handshake with authentication token"""
	var handshake_data: Dictionary = {
		"version": version,
		"name": player_name
	}
	if token != "":
		handshake_data["token"] = token
	_send_message("handshake", handshake_data)
	print("[NodeAdapter] 🤝 Sent handshake: version=", version, " name=", player_name, " auth=", token != "")

func create_room(version: String, player_name: String, gamemode: String = "deathmatch", map_name: String = "", max_players: int = 8, is_public: bool = true) -> void:
	_send_message("create_room", {
		"version": version,
		"playerName": player_name,
		"gamemode": gamemode,
		"map_name": map_name,
		"max_players": max_players,
		"is_public": is_public
	})
	print("[NodeAdapter] 📤 Sent create_room request")

func join_room(room_id: String, version: String, player_name: String) -> void:
	print("[NodeAdapter] 🔍 DEBUG: join_room() called")
	print("[NodeAdapter]   - room_id: ", room_id)
	print("[NodeAdapter]   - version: ", version)
	print("[NodeAdapter]   - player_name: ", player_name)
	print("[NodeAdapter]   - WebSocket state: ", ws.get_ready_state() if ws else "NULL")
	print("[NodeAdapter]   - _is_connected: ", _is_connected)

	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("[NodeAdapter] ❌ ERROR: WebSocket not connected! Cannot send join_room")
		return

	var payload: Dictionary = {
		"roomId": room_id,
		"version": version,
		"name": player_name
	}
	print("[NodeAdapter] 📤 Sending join_room with payload: ", payload)
	_send_message("join_room", payload)
	print("[NodeAdapter] ✅ join_room message sent")

func send_chat(text: String) -> void:
	_send_message("chat", {"text": text})

func load_tbw(lines: PackedStringArray) -> void:
	var lines_array: Array = []
	for line in lines:
		lines_array.append(line)
	_send_message("load_tbw", {"lines": lines_array})

func send_player_snapshot(state: Dictionary) -> void:
	_send_message("player_snapshot", state)

func send_rpc_call(method_name: String, args: Array = [], target_peer: int = 0) -> void:
	"""Send an RPC-style call to backend to relay to peers.

	- method_name: Name of method to invoke on remote client
	- args: Positional arguments array
	- target_peer: 0 to broadcast, or a specific peerId
	"""
	var payload: Dictionary = {
		"method": method_name,
		"args": args,
		"targetPeer": target_peer
	}
	print("[NodeAdapter] 📤 rpc_call method=", method_name, " target=", target_peer, " args=", args)
	_send_message("rpc_call", payload)

func kick_peer(peer_id: int) -> void:
	_send_message("kick_peer", {"peerId": peer_id})

func ban_peer(peer_id: int) -> void:
	_send_message("ban_peer", {"peerId": peer_id})

func ping() -> void:
	_send_message("ping", {})

# Cleanup
func close() -> void:
	if ws:
		ws.close()
	_is_connected = false

func get_peer_id() -> int:
	return _peer_id

func get_room_id() -> String:
	return _room_id

func is_backend_connected() -> bool:
	return _is_connected and ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func spawn_pending_members() -> void:
	"""Spawn all pending members after World is ready"""
	if _pending_members.is_empty():
		print("[NodeAdapter] ⚠️ No pending members to spawn")
		return

	var world: Node = Global.get_world()
	if not world:
		print("[NodeAdapter] ❌ World not found, cannot spawn pending members")
		return

	print("[NodeAdapter] 🎭 Spawning ", _pending_members.size(), " pending members...")
	var player_scene: PackedScene = preload("res://data/scene/character/RigidPlayer.tscn")

	for member_data: Variant in _pending_members:
		if typeof(member_data) == TYPE_DICTIONARY:
			var member: Dictionary = member_data as Dictionary
			var peer_id: int = member.get("peerId", 0) as int
			var peer_name: String = member.get("name", "Unknown") as String

			# Check if player already exists (avoid duplicate spawns)
			if world.has_node(str(peer_id)):
				print("[NodeAdapter] ⚠️ Player ", peer_id, " already exists, skipping")
				continue

			# Spawn RigidPlayer for this peer
			var player: RigidPlayer = player_scene.instantiate()
			player.name = str(peer_id)
			player.assigned_player_name = peer_name  # Set remote player's name
			player.set_multiplayer_authority(peer_id)
			world.add_child(player, true)
			print("[NodeAdapter] ✅ Spawned RigidPlayer for peer ", peer_id, " name=", peer_name)

	_pending_members.clear()
	print("[NodeAdapter] 🎉 All pending members spawned!")

# Query methods for multiplayer integration
func get_unique_peer_id() -> int:
	"""Return the ID of this local peer"""
	return _peer_id

func get_all_peers_with_names() -> Array:
	"""Return array of all peers including self, with their names and IDs"""
	var peers: Array = []

	# Prefer authoritative room_members list from backend
	for member_data: Variant in room_members:
		if typeof(member_data) == TYPE_DICTIONARY:
			var member: Dictionary = member_data as Dictionary
			var pid: int = member.get("peerId", 0) as int
			var pname: String = member.get("name", "Unknown") as String
			if pid <= 0:
				continue
			peers.append({
				"peerId": pid,
				"name": pname,
				"is_self": pid == _peer_id
			})

	# If room_members is empty (early join), fall back to pending/self
	if peers.is_empty():
		if _peer_id > 0:
			peers.append({
				"peerId": _peer_id,
				"name": Global.display_name,
				"is_self": true
			})
		for member_data: Variant in _pending_members:
			if typeof(member_data) == TYPE_DICTIONARY:
				var member: Dictionary = member_data as Dictionary
				peers.append({
					"peerId": member.get("peerId", 0),
					"name": member.get("name", "Unknown"),
					"is_self": false
				})

	return peers

func is_server() -> bool:
	"""Return true if this peer is the server/host"""
	return _is_server

func get_connected_peers() -> PackedInt32Array:
	"""Return array of connected peer IDs (excluding self)"""
	return _connected_peers.duplicate()

func is_peer_connected(peer: int) -> bool:
	"""Check if a specific peer is connected"""
	if peer == _peer_id:
		return true  # Local peer is always connected to itself
	return _connected_peers.has(peer)

func _handle_peer_joined(data: Dictionary) -> void:
	"""Handle notification that a new peer joined the room"""
	var peer_id: int = data.get("peerId", 0) as int
	var name: String = data.get("name", "Unknown") as String
	# Ignore duplicate/self join notifications
	if peer_id == _peer_id:
		return
	for member: Dictionary in room_members:
		if member.get("peerId", -1) == peer_id:
			return

	print("[NodeAdapter] 👥 Peer joined: peerId=", peer_id, " name=", name)
	print("[NodeAdapter] 🔍 Attempting to spawn remote player...")

	# Add to room_members
	room_members.append({"peerId": peer_id, "name": name})

	# Add to connected peers list if not already there
	if not _connected_peers.has(peer_id):
		_connected_peers.append(peer_id)
		print("[NodeAdapter] ✅ Added to connected_peers list")

	# Signal that a peer joined (for Godot's multiplayer system)
	peer_connected.emit(peer_id)
	peer_joined_with_name.emit(peer_id, name)  # New signal with name for player list
	print("[NodeAdapter] 📡 Emitted peer_connected signal")

	# Spawn RigidPlayer for this remote peer
	var world: Node = Global.get_world()
	print("[NodeAdapter] 🔍 Looking for World...")

	if not world:
		print("[NodeAdapter] ❌ World not found - storing as pending")
		_pending_members.append({"peerId": peer_id, "name": name})
		return

	print("[NodeAdapter] ✅ World found, spawning RigidPlayer for peer ", peer_id, " name=", name)

	# Load player scene and spawn
	var player_scene: PackedScene = preload("res://data/scene/character/RigidPlayer.tscn")
	var player: RigidPlayer = player_scene.instantiate()
	player.name = str(peer_id)
	player.assigned_player_name = name  # Set the remote player's actual name
	player.set_multiplayer_authority(peer_id)
	player.freeze = true  # Ensure remote players are frozen (moved only by network updates)
	world.add_child(player, true)

	print("[NodeAdapter] ✅ RigidPlayer spawned for peer ", peer_id, " - REMOTE AVATAR NOW VISIBLE")

func _handle_peer_left(data: Dictionary) -> void:
	"""Handle notification that a peer left the room"""
	var peer_id: int = data.get("peerId", 0) as int

	print("[NodeAdapter] 👋 Peer left: peerId=", peer_id)

	# Remove from room_members
	for i in range(room_members.size() - 1, -1, -1):
		if room_members[i].get("peerId", -1) == peer_id:
			room_members.remove_at(i)
			break

	# Remove from connected peers
	_connected_peers.erase(peer_id)

	# Signal that a peer disconnected
	peer_disconnected.emit(peer_id)

	# Despawn RigidPlayer for this peer
	var world: Node = Global.get_world()
	if world and world.has_node(str(peer_id)):
		var player: Node = world.get_node(str(peer_id))
		print("[NodeAdapter] 🗑️ Despawning player ", peer_id)
		player.queue_free()

func _handle_player_state(data: Dictionary) -> void:
	"""Handle incoming player state (position, rotation, velocity, animation state, animation blends)"""
	var peer_id: int = data.get("peerId", 0) as int
	var pos_data: Dictionary = data.get("position", {"x": 0, "y": 0, "z": 0}) as Dictionary
	var rot_data: Dictionary = data.get("rotation", {"x": 0, "y": 0, "z": 0}) as Dictionary
	var vel_data: Dictionary = data.get("velocity", {"x": 0, "y": 0, "z": 0}) as Dictionary
	var anim_state: int = data.get("state", 0) as int
	var anim_data: Dictionary = data.get("anim", {}) as Dictionary

	var position: Vector3 = Vector3(pos_data.get("x", 0) as float, pos_data.get("y", 0) as float, pos_data.get("z", 0) as float)
	var rotation: Vector3 = Vector3(rot_data.get("x", 0) as float, rot_data.get("y", 0) as float, rot_data.get("z", 0) as float)
	var velocity: Vector3 = Vector3(vel_data.get("x", 0) as float, vel_data.get("y", 0) as float, vel_data.get("z", 0) as float)

	# Update RigidPlayer position/rotation directly
	var world: Node = Global.get_world()
	if not world:
		return

	# Find RigidPlayer by peer_id (should be named with peer_id)
	var player_node: Node = world.get_node_or_null(str(peer_id))
	if not player_node:
		print("[NodeAdapter] ⚠️ Player node not found for peer ", peer_id)
		return

	# RigidPlayer will handle remote state updates via its own sync mechanism
	# For now, we can directly update transform if it's a remote player
	if player_node is RigidPlayer:
		var player: RigidPlayer = player_node as RigidPlayer
		# Only update if this is NOT the local player (use is_local_player flag, not get_multiplayer_authority)
		if not player.is_local_player:
			# Ensure remote player physics is frozen
			player.freeze = true
			# Smoothly interpolate position instead of snapping (reduces jitter from collisions)
			var current_pos: Vector3 = player.global_position
			# If distance is very large (teleport), snap; otherwise lerp
			if current_pos.distance_to(position) > 5.0:
				# Large distance = teleport (probably respawn or join)
				player.global_position = position
			else:
				# Small distance = smooth interpolation
				player.global_position = current_pos.lerp(position, 0.5)  # 50% lerp for smooth sync
			player.global_rotation = rotation

			# Sync animation state
			if player._state != anim_state:
				player._state = anim_state

			# Apply all animation blend values directly from network data
			if player.animator != null and not anim_data.is_empty():
				if anim_data.has("blend_run"):
					player.animator["parameters/BlendRun/blend_amount"] = anim_data.get("blend_run", 0.0)
				if anim_data.has("blend_jump"):
					player.animator["parameters/BlendJump/blend_amount"] = anim_data.get("blend_jump", 0.0)
				if anim_data.has("blend_high_jump"):
					player.animator["parameters/BlendHighJump/blend_amount"] = anim_data.get("blend_high_jump", 0.0)
				if anim_data.has("blend_dive"):
					player.animator["parameters/BlendDive/blend_amount"] = anim_data.get("blend_dive", 0.0)
				if anim_data.has("blend_slide"):
					player.animator["parameters/BlendSlide/blend_amount"] = anim_data.get("blend_slide", 0.0)
				if anim_data.has("blend_slide_back"):
					player.animator["parameters/BlendSlideBack/blend_amount"] = anim_data.get("blend_slide_back", 0.0)
				if anim_data.has("blend_roll"):
					player.animator["parameters/BlendRoll/blend_amount"] = anim_data.get("blend_roll", 0.0)
				if anim_data.has("blend_swim"):
					player.animator["parameters/BlendSwim/blend_amount"] = anim_data.get("blend_swim", 0.0)
				if anim_data.has("blend_swim_dash"):
					player.animator["parameters/BlendSwimDash/blend_amount"] = anim_data.get("blend_swim_dash", 0.0)
				if anim_data.has("blend_dead"):
					player.animator["parameters/BlendDead/blend_amount"] = anim_data.get("blend_dead", 0.0)
				if anim_data.has("blend_on_ledge"):
					player.animator["parameters/BlendOnLedge/blend_amount"] = anim_data.get("blend_on_ledge", 0.0)
				if anim_data.has("blend_sit"):
					player.animator["parameters/BlendSit/blend_amount"] = anim_data.get("blend_sit", 0.0)
		else:
			pass

func send_player_state(position: Vector3, rotation: Vector3, velocity: Vector3, anim_state: int, anim_data: Dictionary) -> void:
	"""Send local player state to server (position, rotation, velocity, animation state, animation blends)"""
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_message("player_state", {
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"rotation": {"x": rotation.x, "y": rotation.y, "z": rotation.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"state": anim_state,
		"anim": anim_data,
	})

# Helper method to update server status when we join a room
func _set_is_server(is_server: bool) -> void:
	"""Internal method to set whether this peer is the host/server"""
	_is_server = is_server
	print("[NodeAdapter] 🎮 Server status changed: is_server=", _is_server)
