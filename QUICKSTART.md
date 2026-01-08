# 🚀 Quick Start Guide - WebSocket Room System

## Before You Start

1. Backend server running: `cd backend-game-server && npm start`
2. Port 30820 must be available
3. Game client built and running
4. Logged in with valid JWT token

---

## The Big Picture

**Before (Broken):**

- Click "Host" → Room shows current_players=1 forever
- Click "Join" → Doesn't work
- Same player can create unlimited rooms
- Room counts never update

**After (Fixed):**

- Click "Host" → Room created with current_players=0
- WebSocket connects → current_players increments to 1
- Click "Join" → WebSocket joins → current_players increments to 2
- Leave room → current_players decrements
- Room empty → Room deactivates (disappears from list)

---

## Testing in 5 Minutes

### Test 1: Create Room

```
1. Open game, login as User A
2. Click "Host (Global)" button
3. Select gamemode: "Deathmatch"
4. Click "Create Room"
5. ✅ Watch console:
   [GlobalPMBackend] ✅ Room created successfully!
   [NodeAdapter] ✅ Handshake accepted
   [NodeAdapter] ✅ Room created: room_XXXXX (peer 1)
```

Expected: Game world loads, you're in the room as host.

### Test 2: Join Room

```
1. Open SECOND game client (different window/account)
2. Login as User B
3. Click "Join (Global)"
4. See room created by User A with "1/8 players"
5. Click "Join" button
6. ✅ Watch console:
   [NodeAdapter] ✅ Handshake accepted
   [NodeAdapter] ✅ Room joined: room_XXXXX (peer 2)
```

Expected: Game world loads, User A sees "2/8 players", User B is in game.

### Test 3: Leave Room

```
1. User B quits game (Alt+F4 or quit button)
2. ✅ Check server list: should show "1/8 players"
3. User A quits game
4. ✅ Check server list: room should disappear!
```

Expected: Server list empties, room deactivates.

---

## Console Logs to Look For

### ✅ Everything Working

```
[GlobalPMBackend] ✅ Room created successfully! ID: room_XXXXX
[NodeAdapter] ✅ Handshake accepted
[NodeAdapter] ✅ Room created: room_XXXXX (peer 1)
[Main] ✅ Room created successfully!
```

### ⚠️ Something Wrong

```
[NodeAdapter] ❌ Error: invalid_token
→ Check Global.auth_token is not empty

[GlobalPMBackend] ❌ HTTP error: response_code=400
→ Check: Are you trying to create 2 rooms? Expected!

[Main] ❌ Failed to connect to Node backend
→ Is backend running? npm start in backend-game-server
```

---

## What Changed

### Godot Client

- `MultiplayerNodeAdapter.gd` - Added JWT authentication
- `MultiplayerMenu.gd` - Now actually connects via WebSocket
- `Main.gd` - Sends handshake before room operations

### Node.js Backend

- Already implements everything needed
- Just needed Godot to send the handshake properly

### Database

- `player_sessions` table tracks who's actually in rooms
- `current_players` only increments on WebSocket join
- Empty rooms auto-deactivate

---

## Database Check

```sql
-- Run this in SQLite after tests:
SELECT id, host_username, current_players, is_active
FROM rooms
ORDER BY created_at DESC;

-- Should show:
-- Empty test rooms with is_active=0 and current_players=0
-- Active rooms with current_players matching player count
```

---

## If Something Breaks

### Backend won't start

```bash
# Kill any process on port 30820
lsof -ti :30820 | xargs kill -9

# Try again
cd backend-game-server
npm start
```

### Can't join room

- Check: Backend console shows "Handshake accepted"?
- Check: Database shows player_sessions entry?
- Check: current_players incremented?

### Room still appears after leaving

- Check: is_active still = 1?
- Try: Refresh server list
- If still there: Database entry didn't delete properly

### Player counts not updating

- Check: WebSocket message logs?
- Check: addPlayerSession() was called?
- Check: Database player_sessions table has entries?

---

## The Real Flow (What Happens Behind The Scenes)

### Host Creates Room

```
Click "Host"
  → HTTP POST /api/rooms (current_players=0)
  → Get room_id in response
  → Connect to WebSocket
  → Send handshake: {token, version, name}
  → Backend verifies token
  → Send create_room message
  → Backend: addPlayerSession() → current_players=0→1
  → Game loads
✅ Room shows in list with 1 player
```

### Player Joins

```
Click "Join" on room
  → Connect to WebSocket
  → Send handshake: {token, version, name}
  → Backend verifies token
  → Send join_room: {roomId}
  → Backend: addPlayerSession() → current_players=1→2
  → Game loads
✅ All players see count updated
```

### Player Leaves

```
Quit game
  → WebSocket closes
  → Backend: removePlayerSession() → current_players=2→1
  → Broadcast peer_left
✅ All players see count updated
```

### Room Empty

```
Last player leaves
  → WebSocket closes
  → Backend: removePlayerSession() → current_players=1→0
  → Backend: deactivateIfEmpty() → is_active=1→0
✅ Room disappears from server list
```

---

## Key Improvements

| Scenario       | Before                              | After                                |
| -------------- | ----------------------------------- | ------------------------------------ |
| Create room    | Shows current_players=1 immediately | Shows 0, then 1 when WebSocket joins |
| Join room      | Doesn't work, no WebSocket          | Works, connects via WebSocket        |
| Leave room     | Count never updates                 | Count decrements automatically       |
| Multiple rooms | Can create unlimited                | Prevents 2nd room with error         |
| Empty room     | Stays forever                       | Auto-deactivates                     |
| Authentication | Not checked                         | Required on WebSocket                |

---

## Success Checklist

- [ ] Backend running with "Database migrations completed successfully"
- [ ] Can create room: see "Room created successfully" in console
- [ ] Room appears in server list with current_players=1
- [ ] Second player can join: see "Room joined" in console
- [ ] Server list shows current_players=2
- [ ] When players disconnect: count decrements
- [ ] When last player leaves: room disappears from list
- [ ] Try creating 2nd room: get HTTP 400 error ✓ (working as intended)

---

## Documents Available

- **IMPLEMENTATION_COMPLETE.md** - Full technical overview
- **ROOM_CREATION_FLOW.md** - Detailed flow diagrams
- **CODE_CHANGES_REFERENCE.md** - Code snippets of what changed
- **CONSOLE_OUTPUT_REFERENCE.md** - Expected console logs
- **WEBSOCKET_IMPLEMENTATION_SUMMARY.md** - Architecture details

Pick any document for more details!

---

## Questions?

**"Can I see if it's working?"**
→ Check console logs and database during testing

**"What if player disconnects halfway?"**
→ WebSocket cleanup handles it automatically

**"Can a player join multiple rooms?"**
→ No! addPlayerSession() removes from other rooms first

**"Are we handling tokens correctly?"**
→ Yes! Verified on WebSocket handshake before any operations

**"What if I create a room but the game doesn't load?"**
→ Check backend logs for WebSocket errors

---

## Success! 🎉

The system is complete and ready for testing. Go create some rooms and join them!
