# Expected Console Output - Full Room Lifecycle

This document shows exactly what you should see in the console logs when the system works correctly.

## Scenario 1: Create Room (Host)

### Step 1: Click "Host (Global)" Button

```
[Menu] === HOST BUTTON PRESSED ===
[Menu] Opening room creation dialog
[Menu] Room creation dialog opened
```

### Step 2: Submit Room Creation Form

```
[GlobalPMBackend] 📤 POST room: http://localhost:30820/api/rooms body: {"gamemode":"deathmatch","mapName":"Frozen Field","maxPlayers":8,"isPublic":true}
```

### Step 3: HTTP Response - Room Created

```
[GlobalPMBackend] 📥 Create response: 201 result: 0
[GlobalPMBackend] ✅ Room created successfully! ID: room_1735065912345_abc123def
[Menu] === ROOM CREATED SIGNAL RECEIVED ===
[Menu] Room ID: room_1735065912345_abc123def
[Menu] Room data: {id: room_1735065912345_abc123def, host_username: testuser, gamemode: deathmatch, map_name: Frozen Field, max_players: 8, current_players: 0, is_public: true}
[Menu] 🔄 Connecting to WebSocket and hosting room...
[Menu] ✅ Calling _setup_node_backend_host()
```

### Step 4: WebSocket Connection - Handshake

```
[Main] === SETTING UP NODE BACKEND AS HOST ===
[Main] 🔄 Connecting to Node backend...
```

Wait ~0.5 seconds for connection...

```
[Main] 🤝 Sending handshake...
[NodeAdapter] 🤝 Sent handshake: version=0.0.1 name=testuser auth=true
```

Wait ~0.3 seconds...

```
[NodeAdapter] ✅ Handshake accepted
[NodeAdapter] User ID: 1
[NodeAdapter] Username: testuser
```

### Step 5: WebSocket - Send create_room

```
[Main] 📤 Sending create_room...
[NodeAdapter] 📤 Sent create_room request
[Main] ⏳ Waiting for room_created signal...
```

### Step 6: WebSocket - Receive room_created

```
[NodeAdapter] ✅ Room created: room_1735065912345_abc123def (peer 1)
[Main] ✅ Room created successfully!
```

### Step 7: Load World

```
[Main] Loading world from TBW: Frozen Field
[Main] World loaded successfully
[Main] Spawning camera
[Main] Camera spawned at position: (0, 5, 0)
[Menu] Hiding menu, showing game canvas
```

### Backend Console During Host Creation

```
[RoomAPI] 🎯 CREATE ROOM REQUEST received
[RoomAPI] 👤 User ID: 1 Username: testuser
[RoomAPI] 📋 Room Config - Gamemode: deathmatch Map: Frozen Field
[RoomAPI] 👥 Max Players: 8 Public: true
[RoomAPI] ✅ Generated room ID: room_1735065912345_abc123def
[RoomAPI] 🔄 Creating room in database...
[RoomAPI] ✅ Room created successfully (current_players=0, awaiting WebSocket join)
[RoomAPI] 📤 Sending response with room data

[WebSocket] ✅ Handshake accepted for testuser (user_id=1)
[WebSocket] 👑 Host 1 joined room room_1735065912345_abc123def
```

---

## Scenario 2: Join Room (Client)

### Step 1: See Server List

```
[GlobalPMBackend] 📤 GET rooms: http://localhost:30820/api/rooms
[GlobalPMBackend] 📥 Rooms response: 200 result: 0
[GlobalPMBackend] ✅ Fetched 1 rooms
[ServerList] 📥 Rooms received: 1 room(s)
[ServerList] Room: room_1735065912345_abc123def - deathmatch (1/8) - Host: testuser
```

### Step 2: Click Join Button

```
[ServerList] === ROOM JOIN CLICKED ===
[ServerList] 🎯 Room ID: room_1735065912345_abc123def
[ServerList] 👤 Room host: testuser
[ServerList] 📊 Room stats: 1/8 players, gamemode: deathmatch, is_public: true
[ServerList] 📤 Emitting room_selected signal
```

### Step 3: Menu Receives Selection

```
[Menu] === ROOM SELECTED FROM SERVER LIST ===
[Menu] 🎯 Room ID: room_1735065912345_abc123def
[Menu] ✅ User authenticated
[Menu] 🔄 Connecting to WebSocket and joining room...
[Menu] ✅ Calling _setup_node_backend_client() with room_id: room_1735065912345_abc123def
```

### Step 4: WebSocket Connection - Handshake

```
[Main] === SETTING UP NODE BACKEND AS CLIENT ===
[Main] Room code: room_1735065912345_abc123def
[Main] 🔄 Connecting to Node backend...
```

Wait ~0.5 seconds...

```
[Main] 🤝 Sending handshake...
[NodeAdapter] 🤝 Sent handshake: version=0.0.1 name=otheruser auth=true
```

Wait ~0.3 seconds...

```
[NodeAdapter] ✅ Handshake accepted
[NodeAdapter] User ID: 2
[NodeAdapter] Username: otheruser
```

### Step 5: WebSocket - Send join_room

```
[Main] 📤 Sending join_room for: room_1735065912345_abc123def
[NodeAdapter] 📤 Sent join_room request
```

### Step 6: WebSocket - Receive room_joined

```
[NodeAdapter] ✅ Room joined: room_1735065912345_abc123def (peer 2)
[Main] ✅ Room joined successfully!
```

### Step 7: Load World

```
[Main] Loading world from TBW: Frozen Field
[Main] World loaded successfully
[Main] Spawning camera
[Main] Camera spawned at position: (0, 5, 0)
[Menu] Hiding menu, showing game canvas
```

### Backend Console During Join

```
[WebSocket] ✅ Handshake accepted for otheruser (user_id=2)
[WebSocket] 🎮 Player 2 joined room room_1735065912345_abc123def
```

### Host Console Sees New Player

```
[NodeAdapter] peer_joined: peerId=2
[Main] Player 2 (otheruser) has joined the room
```

---

## Scenario 3: Player Disconnects

### Step 1: Player Quits Game

```
[Main] === QUITTING GAME ===
[Main] Cleaning up multiplayer peer...
[NodeAdapter] Closing WebSocket connection
```

### Backend Console - Sees Disconnect

```
[WebSocket] 🚪 Player 2 disconnected from room room_1735065912345_abc123def
[WebSocket] Removed session for user 2
```

### Server List Refreshes

```
[GlobalPMBackend] 📤 GET rooms: http://localhost:30820/api/rooms
[GlobalPMBackend] 📥 Rooms response: 200 result: 0
[ServerList] 📥 Rooms received: 1 room(s)
[ServerList] Room: room_1735065912345_abc123def - deathmatch (1/8) - Host: testuser
```

### If Host Was Last Player

```
[WebSocket] 🚪 Player 1 disconnected from room room_1735065912345_abc123def
[WebSocket] Room is now empty, deactivating...
[WebSocket] 🔴 Room room_1735065912345_abc123def deactivated (current_players=0)
```

Next refresh:

```
[GlobalPMBackend] 📤 GET rooms: http://localhost:30820/api/rooms
[GlobalPMBackend] 📥 Rooms response: 200 result: 0
[ServerList] 📥 Rooms received: 0 room(s)
[ServerList] ℹ️ No active rooms available
```

---

## Error Scenarios

### Error: Duplicate Room Creation

```
[Menu] === HOST BUTTON PRESSED ===
[GlobalPMBackend] 📤 POST room: http://localhost:30820/api/rooms body: {...}
[GlobalPMBackend] 📥 Create response: 400 result: 0
[GlobalPMBackend] ❌ HTTP error: response_code=400 result=0
```

Console from backend:

```
[RoomAPI] ❌ User already has active room: room_1735065912345_abc123def
```

### Error: Authentication Required (No Token)

```
[Menu] === ROOM SELECTED FROM SERVER LIST ===
[Menu] ❌ Not authenticated; cannot join room
```

### Error: WebSocket Connection Failed

```
[Main] 🔄 Connecting to Node backend...
[Main] ❌ Failed to connect to Node backend
[Menu] Alert: "Failed to connect to Node backend"
```

Backend not running? Start with:

```bash
cd backend-game-server
npm start
```

### Error: Handshake Failed (Invalid Token)

```
[Main] 🤝 Sending handshake...
[NodeAdapter] 🤝 Sent handshake: version=0.0.1 name=testuser auth=true
[NodeAdapter] ❌ Error: invalid_token
[Main] ❌ Authentication failed
[Menu] Alert: "Authentication failed"
```

---

## Database State During Lifecycle

### After Room Creation (HTTP POST)

```sql
SELECT * FROM rooms WHERE id = 'room_1735065912345_abc123def';
-- Expected output:
-- id: room_1735065912345_abc123def
-- host_user_id: 1
-- host_username: testuser
-- gamemode: deathmatch
-- current_players: 0 ⬅️ Not yet joined via WebSocket!
-- is_active: 1

SELECT * FROM player_sessions;
-- Expected: EMPTY (no sessions yet)
```

### After WebSocket Host Join

```sql
SELECT * FROM rooms WHERE id = 'room_1735065912345_abc123def';
-- Expected output:
-- current_players: 1 ⬅️ Incremented by addPlayerSession()
-- is_active: 1

SELECT * FROM player_sessions;
-- Expected:
-- id: 1
-- user_id: 1 (testuser)
-- room_id: room_1735065912345_abc123def
-- joined_at: 2026-01-08 12:30:00
```

### After Second Player Joins via WebSocket

```sql
SELECT * FROM rooms WHERE id = 'room_1735065912345_abc123def';
-- Expected output:
-- current_players: 2 ⬅️ Incremented again

SELECT * FROM player_sessions;
-- Expected:
-- Row 1: user_id=1, room_id=room_1735...
-- Row 2: user_id=2, room_id=room_1735... ⬅️ New entry
```

### After Last Player Disconnects

```sql
SELECT * FROM rooms WHERE id = 'room_1735065912345_abc123def';
-- Expected output:
-- current_players: 0
-- is_active: 0 ⬅️ Deactivated!

SELECT * FROM player_sessions WHERE room_id = 'room_1735...';
-- Expected: EMPTY (all sessions deleted)
```

---

## Success Indicators

✅ **Room Creation Works** when you see:

- `[GlobalPMBackend] ✅ Room created successfully!`
- `[NodeAdapter] ✅ Handshake accepted`
- `[NodeAdapter] ✅ Room created: room_XXXXX (peer 1)`
- Game world loads successfully

✅ **Room Join Works** when you see:

- `[ServerList] Room: room_XXXXX - ... (1/8)`
- `[NodeAdapter] ✅ Handshake accepted`
- `[NodeAdapter] ✅ Room joined: room_XXXXX (peer 2)`
- Game world loads successfully
- Current players count increases on server list

✅ **Auto-Deactivate Works** when you see:

- Player disconnects
- Backend: `[WebSocket] 🚪 Player X disconnected`
- Room disappears from server list next refresh
- Database: `is_active=0` for that room

✅ **Database Consistent** when you verify:

- `current_players` matches player_sessions count for each room
- `is_active=1` only for rooms with players
- `is_active=0` for empty rooms (cleaned up by background task)

---

## Debugging Checklist

If something isn't working, check in this order:

1. **Backend Running?**

   ```bash
   lsof -i :30820
   # Should show: node or ts-node process
   ```

2. **Database Migrations Completed?**

   ```
   Backend logs should show:
   "Database migrations completed successfully"
   ```

3. **JWT Token Valid?**

   ```
   Check Global.auth_token in Godot debugger
   Should start with "eyJ" (valid JWT)
   ```

4. **WebSocket Connection Established?**

   ```
   Console should show:
   "[NodeAdapter] ✅ Handshake accepted"
   ```

5. **Database Consistency?**

   ```sql
   -- Check each room's player count
   SELECT id, current_players,
          (SELECT COUNT(*) FROM player_sessions ps WHERE ps.room_id = r.id) as session_count
   FROM rooms r;
   -- current_players should equal session_count
   ```

6. **Check Backend Logs**
   ```
   npm start output should show:
   - Handshake accepted logs
   - create_room/join_room logs
   - peer_joined/peer_left logs
   ```
