# Critical Code Changes Reference

## MultiplayerNodeAdapter.gd

### New Method: send_handshake()

```gdscript
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
```

### New Message Handler

```gdscript
func _on_ws_message() -> void:
	# ... existing code ...
	match msg_type:
		"handshake_accepted":
			_handle_handshake_accepted(msg_data)
		"room_created":
			_handle_room_created(msg_data)
		"room_joined":
			_handle_room_joined(msg_data)
		# ... other cases ...

func _handle_handshake_accepted(data: Dictionary) -> void:
	print("[NodeAdapter] ✅ Handshake accepted")
	print("[NodeAdapter] User ID: ", data.get("user_id", "N/A"))
	print("[NodeAdapter] Username: ", data.get("username", "N/A"))

func _handle_room_created(data: Dictionary) -> void:
	_room_id = data.get("roomId", "")
	_peer_id = data.get("peerId", 1)
	print("[NodeAdapter] ✅ Room created: ", _room_id, " (peer ", _peer_id, ")")
	room_created.emit(_room_id)

func _handle_room_joined(data: Dictionary) -> void:
	_room_id = data.get("roomId", "")
	_peer_id = data.get("peerId", 0)
	# ... peer handling ...
	print("[NodeAdapter] ✅ Room joined: ", _room_id, " (peer ", _peer_id, ")")
	room_joined.emit(_peer_id, _room_id)
```

## Main.gd

### Updated \_setup_node_backend_host()

```gdscript
func _setup_node_backend_host() -> void:
	print("[Main] === SETTING UP NODE BACKEND AS HOST ===")
	# ... button setup ...

	# Create adapter
	node_peer = MultiplayerNodeAdapter.new()
	add_child(node_peer)
	node_peer.room_created.connect(_on_room_created)
	node_peer.connection_failed.connect(_on_connection_failed)

	# Connect to WebSocket
	print("[Main] 🔄 Connecting to Node backend...")
	if not node_peer.connect_to_server(node_server_url):
		# ... error handling ...
		return

	# Wait for connection
	await get_tree().create_timer(0.5).timeout

	# 🔑 KEY CHANGE: Send handshake with JWT token BEFORE create_room
	print("[Main] 🤝 Sending handshake...")
	node_peer.send_handshake(str(server_version), Global.display_name, Global.auth_token)

	# Wait for handshake response
	await get_tree().create_timer(0.3).timeout

	# Now send create_room
	print("[Main] 📤 Sending create_room...")
	node_peer.create_room(str(server_version), Global.display_name)

	# Wait for room creation
	print("[Main] ⏳ Waiting for room_created signal...")
	await node_peer.room_created
	print("[Main] ✅ Room created successfully!")

	# ... load world ...
```

### Updated \_setup_node_backend_client()

```gdscript
func _setup_node_backend_client(room_code: String = "") -> void:
	print("[Main] === SETTING UP NODE BACKEND AS CLIENT ===")
	print("[Main] Room code: ", room_code)
	# ... button setup ...

	# Create adapter
	node_peer = MultiplayerNodeAdapter.new()
	add_child(node_peer)
	node_peer.room_joined.connect(_on_room_joined)
	node_peer.connection_failed.connect(_on_connection_failed)

	# Connect to WebSocket
	print("[Main] 🔄 Connecting to Node backend...")
	if not node_peer.connect_to_server(node_server_url):
		# ... error handling ...
		return

	# Wait for connection
	await get_tree().create_timer(0.5).timeout

	# 🔑 KEY CHANGE: Send handshake with JWT token BEFORE join_room
	print("[Main] 🤝 Sending handshake...")
	node_peer.send_handshake(str(server_version), Global.display_name, Global.auth_token)

	# Wait for handshake response
	await get_tree().create_timer(0.3).timeout

	# Now send join_room with room ID
	if room_code.is_empty():
		room_code = join_address.text
	print("[Main] 📤 Sending join_room for: ", room_code)
	node_peer.join_room(room_code, str(server_version), Global.display_name)

	# ... load world ...
```

## MultiplayerMenu.gd

### New Implementation: \_on_room_created()

```gdscript
func _on_room_created(room_id: String, room_data: Dictionary) -> void:
	"""Handle new room creation - connect via WebSocket"""
	print("[Menu] === ROOM CREATED SIGNAL RECEIVED ===")
	print("[Menu] Room ID: ", room_id)
	print("[Menu] Room data: ", room_data)
	print("[Menu] 🔄 Connecting to WebSocket and hosting room...")

	# Get Main node
	var main: Main = get_tree().current_scene as Main
	if not main:
		print("[Menu] ❌ Failed to get Main node")
		return

	# Set play mode
	main.play_mode = "global"
	main.backend = "node"

	# Connect to WebSocket (triggers handshake + create_room)
	print("[Menu] ✅ Calling _setup_node_backend_host()")
	main._setup_node_backend_host()
```

### New Implementation: \_on_global_room_selected()

```gdscript
func _on_global_room_selected(room_id: String) -> void:
	"""Handle room selection from list - join via WebSocket"""
	print("[Menu] === ROOM SELECTED FROM SERVER LIST ===")
	print("[Menu] 🎯 Room ID: ", room_id)

	# Check authentication
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

	# Set play mode
	main.play_mode = "global"
	main.backend = "node"

	# Connect to WebSocket (triggers handshake + join_room)
	print("[Menu] ✅ Calling _setup_node_backend_client() with room_id: ", room_id)
	main._setup_node_backend_client(room_id)
```

## Backend: websocket.ts (Already Implemented)

### Key Handler: create_room

```typescript
case "create_room": {
	// Require authentication - token already verified in handshake
	if (!session.isAuthenticated) {
		return send(ws, "error", { reason: "authentication_required" });
	}

	// Create room in memory and database
	const room = roomManager.createRoom(...);
	roomRepo.createRoom({...});

	// 🔑 KEY: Add player to session (increments count to 1)
	roomRepo.addPlayerSession(session.userId!, room.id);
	console.log(`[WebSocket] 👑 Host ${session.userId} joined room ${room.id}`);

	// Confirm to client
	send(ws, "room_created", {
		roomId: room.id,
		peerId: 1,
		gamemode: gamemode,
	});
	break;
}
```

### Key Handler: join_room

```typescript
case "join_room": {
	// Require authentication
	if (!session.isAuthenticated) {
		return send(ws, "error", { reason: "authentication_required" });
	}

	// Join room in memory
	const result = roomManager.joinRoom(...);
	if ("error" in result) {
		return send(ws, "error", { reason: result.error });
	}

	// 🔑 KEY: Add player to session (enforces single-room, increments count)
	roomRepo.addPlayerSession(session.userId!, room.id);
	console.log(`[WebSocket] 🎮 Player ${session.userId} joined room ${room.id}`);

	// Confirm to client
	send(ws, "room_joined", {
		roomId: room.id,
		peerId: peerId,
		peers: [...],
	});
	break;
}
```

### Key Handler: Cleanup

```typescript
function cleanupClient(ws: WebSocket) {
  const session = clientSessions.get(ws);
  if (!session) return;

  const { roomId, peerId, userId } = session;
  clientSessions.delete(ws);

  if (roomId && peerId !== null) {
    const room = roomManager.getRoom(roomId);
    if (room) {
      roomManager.leaveRoom(roomId, peerId);

      // 🔑 KEY: Remove player from session (decrements count, may deactivate room)
      if (userId) {
        roomRepo.removePlayerSession(userId, roomId);
        console.log(
          `[WebSocket] 🚪 Player ${userId} disconnected from room ${roomId}`
        );
      }

      broadcast(room, "peer_left", { peerId }, peerId);
    }
  }
}
```

## Backend: roomRepository.ts (Already Implemented)

### addPlayerSession() - Called on WebSocket join

```typescript
addPlayerSession(userId: number, roomId: string): void {
	try {
		// Remove from other rooms
		this.db
			.prepare("DELETE FROM player_sessions WHERE user_id = ?")
			.run(userId);

		// Add to new room
		this.db
			.prepare("INSERT INTO player_sessions (user_id, room_id) VALUES (?, ?)")
			.run(userId, roomId);

		// Increment player count
		this.db
			.prepare("UPDATE rooms SET current_players = current_players + 1 WHERE id = ?")
			.run(roomId);
	} catch (err) {
		console.error(`[RoomRepo] ❌ addPlayerSession error:`, err);
	}
}
```

### removePlayerSession() - Called on WebSocket disconnect

```typescript
removePlayerSession(userId: number, roomId: string): void {
	try {
		// Remove session
		this.db
			.prepare("DELETE FROM player_sessions WHERE user_id = ? AND room_id = ?")
			.run(userId, roomId);

		// Decrement player count
		this.db
			.prepare("UPDATE rooms SET current_players = current_players - 1 WHERE id = ?")
			.run(roomId);

		// Deactivate room if empty
		this.deactivateIfEmpty(roomId);
	} catch (err) {
		console.error(`[RoomRepo] ❌ removePlayerSession error:`, err);
	}
}
```

### getPlayerCurrentRoom() - Called before HTTP room creation

```typescript
getPlayerCurrentRoom(userId: number): Room | null {
	try {
		const result = this.db
			.prepare(`
				SELECT r.* FROM rooms r
				JOIN player_sessions ps ON r.id = ps.room_id
				WHERE ps.user_id = ?
			`)
			.get(userId);
		return result || null;
	} catch (err) {
		console.error(`[RoomRepo] ❌ getPlayerCurrentRoom error:`, err);
		return null;
	}
}
```

## Database Schema Changes

### player_sessions Table (New)

```sql
CREATE TABLE IF NOT EXISTS player_sessions (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	room_id TEXT NOT NULL,
	joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
	UNIQUE(user_id, room_id),  -- Enforces single-room per player
	FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
	FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
)
```

### rooms Table (Updated)

```sql
-- KEY CHANGE: current_players DEFAULT changed from 1 to 0
ALTER TABLE rooms MODIFY COLUMN current_players INTEGER DEFAULT 0;

-- And explicit INSERT includes current_players:
INSERT INTO rooms (..., current_players, ...)
VALUES (..., 0, ...);
```

## Message Flow Sequence

### Room Creation Sequence

```
Client: POST /api/rooms (HTTP)
  ↓
Backend: Creates room with current_players=0
Backend: Returns room_id
  ↓
Client: Receives room_created signal
Client: Calls Main._setup_node_backend_host()
  ↓
Client: Connects WebSocket
Client: Sends handshake message with JWT token
  ↓
Backend: Verifies token, sets session.userId
Backend: Sends handshake_accepted
  ↓
Client: Receives handshake_accepted
Client: Sends create_room message
  ↓
Backend: Calls roomRepo.addPlayerSession(userId, roomId)
Backend: Increments current_players from 0 to 1
Backend: Sends room_created message
  ↓
Client: Receives room_created signal
Client: Loads world
```

### Room Join Sequence

```
Client: Sees room in server list (current_players=1)
Client: Clicks Join button
Client: Calls Main._setup_node_backend_client(room_id)
  ↓
Client: Connects WebSocket
Client: Sends handshake message with JWT token
  ↓
Backend: Verifies token, sets session.userId
Backend: Sends handshake_accepted
  ↓
Client: Receives handshake_accepted
Client: Sends join_room message with roomId
  ↓
Backend: Calls roomRepo.addPlayerSession(userId, roomId)
Backend: Removes user from other rooms (DELETE)
Backend: Increments current_players from 1 to 2
Backend: Sends join_room message with peerId=2
  ↓
Client: Receives room_joined signal
Client: Loads world
  ↓
All players: Receive peer_joined broadcast
```

## Key System Invariants

1. **current_players accuracy**: Only increments on WebSocket addPlayerSession(), never on HTTP creation
2. **Single room per player**: addPlayerSession() removes from all other rooms first
3. **Automatic cleanup**: removePlayerSession() deactivates empty rooms
4. **Authentication required**: Handshake must complete before create_room/join_room allowed
5. **Database is source of truth**: player_sessions table is authoritative for who's in which room
