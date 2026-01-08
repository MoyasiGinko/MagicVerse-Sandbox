# Room Creation & Join Flow - WebSocket Implementation

## Status: ✅ Implementation Complete

Database migrations and WebSocket authentication are now fully integrated. The backend server is running on port 30820.

## Complete Flow Diagram

### HOST ROOM FLOW

```
User clicks "Host (Global)"
    ↓
RoomCreationDialog shows
    ↓
User submits form (gamemode, etc.)
    ↓
GlobalPlayMenuBackend.create_room(config)
    ↓
POST /api/rooms with JWT token
    ↓
Backend checks: getPlayerCurrentRoom() == null?
    ↓
[NO] → Return 400 with existing_room_id
    ↓
[YES] → Create room with current_players=0
    ↓
Return 201 with room data (id, gamemode, etc.)
    ↓
GlobalPlayMenuBackend emits: room_created(room_id, room_data)
    ↓
MultiplayerMenu._on_room_created() receives signal
    ↓
Calls Main._setup_node_backend_host()
    ↓
Main creates MultiplayerNodeAdapter
    ↓
Connects to WebSocket: ws://localhost:30820
    ↓
Waits 0.5s for connection
    ↓
Sends handshake: {type: "handshake", data: {version, name, token}}
    ↓
WebSocket verifies JWT token
    ↓
Responds: {type: "handshake_accepted", data: {user_id, username}}
    ↓
Main waits 0.3s
    ↓
Main sends: {type: "create_room", data: {version, playerName, gamemode, ...}}
    ↓
WebSocket backend:
  - Creates room in memory
  - Calls roomRepo.addPlayerSession(user_id, room_id)
    → Increments current_players from 0 to 1
  - Sends back: {type: "room_created", data: {roomId, peerId: 1, gamemode}}
    ↓
MultiplayerNodeAdapter emits: room_created
    ↓
Main waits for room_created signal
    ↓
Loads world, spawns camera, loads TBW map
    ↓
Shows game canvas, hides menu
    ↓
Room is now active with host as only player
```

### JOIN ROOM FLOW

```
User sees server list with available rooms
    ↓
User clicks Join on a room
    ↓
GlobalServerList._on_room_join_clicked(room_id)
    ↓
Emits: room_selected(room_id)
    ↓
MultiplayerMenu._on_global_room_selected(room_id)
    ↓
Checks: is_authenticated && auth_token != ""?
    ↓
[NO] → Print error, return
    ↓
[YES] → Calls Main._setup_node_backend_client(room_id)
    ↓
Main creates MultiplayerNodeAdapter
    ↓
Connects to WebSocket: ws://localhost:30820
    ↓
Waits 0.5s for connection
    ↓
Sends handshake: {type: "handshake", data: {version, name, token}}
    ↓
WebSocket verifies JWT token
    ↓
Responds: {type: "handshake_accepted", data: {user_id, username}}
    ↓
Main waits 0.3s
    ↓
Main sends: {type: "join_room", data: {roomId, version, playerName}}
    ↓
WebSocket backend:
  - Calls roomRepo.addPlayerSession(user_id, room_id)
    → Removes user from any other rooms
    → Increments current_players
    → Enforces UNIQUE(user_id, room_id) constraint
  - Adds player to room peers
  - Sends back: {type: "room_joined", data: {roomId, peerId, peers}}
    ↓
MultiplayerNodeAdapter emits: room_joined
    ↓
Main waits for room_joined signal
    ↓
Loads world, spawns camera, loads TBW map
    ↓
Shows game canvas, hides menu
    ↓
Player is now in room with others
```

## Key Implementation Details

### 1. Authentication

- All WebSocket connections require JWT token in handshake
- Token sent in handshake message: `{type: "handshake", data: {token, version, name}}`
- Backend verifies with `verifyToken()` and sets `session.userId`

### 2. Player Session Tracking

- Database table: `player_sessions(id, user_id, room_id, joined_at, UNIQUE(user_id, room_id))`
- When player joins: `roomRepo.addPlayerSession(userId, roomId)`
  - Removes player from any other active rooms
  - Adds new session record
  - Increments room.current_players
- When player disconnects: `roomRepo.removePlayerSession(userId, roomId)`
  - Deletes session record
  - Decrements room.current_players
  - If room empty: calls `deactivateIfEmpty()` to set `is_active=0`

### 3. Room Count Accuracy

- Rooms start with `current_players=0` (explicit INSERT)
- Count only increments when WebSocket connection is established
- Count decrements when WebSocket disconnects
- Empty rooms auto-deactivate (not deleted, just marked inactive)

### 4. Duplicate Room Prevention

- HTTP endpoint checks: `getPlayerCurrentRoom(userId)` before creating
- WebSocket `addPlayerSession()` enforces DB constraint: UNIQUE(user_id, room_id)
- If user tries to join multiple rooms: first join succeeds, second returns error or removes from first

## Testing Checklist

### Manual Testing Steps

1. **Room Creation Test**

   ```
   [ ] Login to game with Test User 1
   [ ] Click "Host (Global)" button
   [ ] Check console logs:
       - "[Menu] === ROOM CREATED SIGNAL RECEIVED ==="
       - "[Main] === SETTING UP NODE BACKEND AS HOST ==="
       - "[Main] 🤝 Sending handshake..."
       - "[NodeAdapter] ✅ Handshake accepted"
       - "[Main] 📤 Sending create_room..."
       - "[NodeAdapter] ✅ Room created: room_XXXXX (peer 1)"
   [ ] Game world loads successfully
   [ ] Room shows on server list with current_players=1
   ```

2. **Join Room Test**

   ```
   [ ] Login with Test User 2
   [ ] Click "Join (Global)" tab
   [ ] See room created by User 1 in list with current_players=1
   [ ] Click Join button on that room
   [ ] Check console logs:
       - "[Menu] === ROOM SELECTED FROM SERVER LIST ==="
       - "[Main] === SETTING UP NODE BACKEND AS CLIENT ==="
       - "[Main] 🤝 Sending handshake..."
       - "[NodeAdapter] ✅ Handshake accepted"
       - "[Main] 📤 Sending join_room..."
       - "[NodeAdapter] ✅ Room joined: room_XXXXX (peer 2)"
   [ ] Game world loads successfully
   [ ] User 1 sees User 2 joining (player count updates to 2)
   ```

3. **Leave Room Test**

   ```
   [ ] User 2 disconnects/quits game
   [ ] Check console logs on backend:
       - "[WebSocket] 🚪 Player {user_id} disconnected from room {room_id}"
   [ ] Server list shows current_players decreased to 1
   [ ] User 1 still in game
   ```

4. **Host Leave Test**

   ```
   [ ] User 1 (host) disconnects
   [ ] Backend decrements current_players to 0
   [ ] Room deactivates (is_active=0)
   [ ] Room disappears from server list
   [ ] User 2 (if still in room) experiences room closure
   ```

5. **Duplicate Room Prevention Test**

   ```
   [ ] User 1 tries to create 2 rooms in quick succession
   [ ] First room creation succeeds
   [ ] Second room creation returns HTTP 400:
       {
         "error": "You already have an active room...",
         "existing_room_id": "room_XXXXX"
       }
   [ ] Only 1 room shows in list for User 1
   ```

6. **Legacy Rooms Cleanup**
   ```
   [ ] Check database: SELECT * FROM rooms WHERE current_players = 1;
   [ ] These are old rooms (should be 0 if created after fixes)
   [ ] Option: DELETE FROM rooms WHERE current_players = 1;
   [ ] Or: UPDATE rooms SET is_active = 0 WHERE current_players = 1;
   ```

## Console Log Reference

### Godot Client Logs

- `[Menu]` - MultiplayerMenu.gd
- `[Main]` - Main.gd
- `[NodeAdapter]` - MultiplayerNodeAdapter.gd
- `[GlobalPMBackend]` - GlobalPlayMenuBackend.gd
- `[ServerList]` - GlobalServerList.gd

### Node.js Backend Logs

- `[RoomAPI]` - Room creation/fetch endpoints
- `[WebSocket]` - WebSocket connection handling
- Shows: User authentication, room creation, player session management

## Debugging Common Issues

### "Failed to connect to Node backend"

- Check if backend server is running: `npm start` in backend-game-server
- Verify port 30820 is not in use: `netstat -an | grep 30820`
- Check firewall allows localhost:30820

### "authentication_required" WebSocket error

- Verify `Global.auth_token` is not empty before WebSocket connect
- Check JWT token is valid: decode at jwt.io
- Verify token not expired

### Room doesn't appear in list (current_players=0)

- Check backend database: `SELECT * FROM rooms WHERE id = 'room_XXXXX';`
- If current_players=0, join the room to increment it
- WebSocket join must complete before server list refreshes

### Player joins but count doesn't increment

- Backend WebSocket addPlayerSession() may have failed
- Check backend logs for `addPlayerSession()` call
- Verify player_sessions table has the entry: `SELECT * FROM player_sessions WHERE user_id = X;`

### Empty room doesn't disappear

- Room deactivates (is_active=0) when last player leaves
- Server list only shows `is_active=1` rooms
- If room still showing: check if another player still connected

## Next Steps

1. ✅ Implement WebSocket handshake with JWT authentication
2. ✅ Update room creation to start with current_players=0
3. ✅ Update WebSocket handlers for session management
4. ✅ Implement client-side WebSocket connection
5. 🔄 **TEST END-TO-END**: Create room → Join → Verify counts
6. 🔄 **CLEANUP**: Delete or deactivate legacy rooms with current_players=1
7. 🔄 **EDGE CASES**: Handle connection timeouts, room full, invalid tokens

## Database Queries for Debugging

```sql
-- Check all rooms and their player counts
SELECT id, host_username, gamemode, current_players, is_active FROM rooms ORDER BY created_at DESC;

-- Check active player sessions
SELECT * FROM player_sessions ORDER BY joined_at DESC;

-- Check room membership
SELECT ps.user_id, ps.room_id, r.host_username FROM player_sessions ps
JOIN rooms r ON ps.room_id = r.id ORDER BY ps.joined_at DESC;

-- Find user's current room
SELECT * FROM player_sessions WHERE user_id = 123;

-- Cleanup old rooms with wrong player count
DELETE FROM rooms WHERE current_players = 1 AND created_at < datetime('now', '-1 hour');
```

## Architecture Notes

- **Separation of Concerns**: HTTP for room creation, WebSocket for real-time state
- **Single Source of Truth**: Database player_sessions table is authoritative
- **Automatic Cleanup**: Empty rooms deactivate automatically on last disconnect
- **Single Room Enforcement**: UNIQUE constraint + addPlayerSession logic
- **Type Safety**: Godot GDScript with strict type checking, Node.js with TypeScript
