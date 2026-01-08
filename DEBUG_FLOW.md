# Debug Flow Guide - Room Creation & Server List

This document describes the complete debug flow with console logging at every step.

## Debug Console Output Format

All debug messages follow a consistent format:

```
[ComponentName] emoji Description
```

### Emoji Indicators

- ✅ Success/Completion
- ❌ Error/Failure
- 🔄 In Progress/Refresh
- ⚠️ Warning/Caution
- 📥 Receiving data
- 📤 Sending request
- 🎯 Action/Target
- 👤 User/Identity
- 👥 Players/Group
- 🎮 Gamemode/Gaming
- 📋 List/Menu
- 🔗 Connection/Link
- 🔍 Search/Filter
- 📭 Empty state
- 🔌 Network/Connection

---

## Complete Flow: User Creates Room

### 1️⃣ User Clicks "Host Server" Button

**Godot Console Output:**

```
[MultiplayerMenu] 🎯 Host button clicked
[MultiplayerMenu] 📤 Opening RoomCreationDialog
[RoomCreation] 🎯 show_dialog() called
[RoomCreation] ✅ Dialog visible, ready for input
```

### 2️⃣ User Fills Form & Clicks Create

**Godot Console Output:**

```
[RoomCreation] 🎯 Create button pressed
[RoomCreation] 🔄 Starting room creation process...
[RoomCreation] ✅ Form validated successfully
[RoomCreation] 📋 Gamemode: Deathmatch
[RoomCreation] 📋 Map: Default
[RoomCreation] 👥 Max Players: 8
[RoomCreation] 🔐 Public: true
[RoomCreation] 📤 Sending room creation request to server...
```

### 3️⃣ HTTP Request Sent

**Godot Console Output:**

```
[RoomCreation] 📤 HTTP Request Details:
  URL: http://localhost:3000/api/rooms
  Method: POST
  Headers: ["Authorization: Bearer <token>", "Content-Type: application/json"]
  Body: {"gamemode":"Deathmatch","mapName":"Default","maxPlayers":8,"isPublic":true}
[RoomCreation] 🔌 HTTPRequest.request() called
```

**Backend Console Output:**

```
[RoomAPI] 🎯 CREATE ROOM REQUEST received
[RoomAPI] 👤 User ID: 1 Username: TestPlayer
[RoomAPI] 📋 Room Config - Gamemode: Deathmatch Map: Default
[RoomAPI] 👥 Max Players: 8 Public: true
[RoomAPI] ✅ Generated room ID: room_1234567890_abc123xyz
[RoomAPI] 🔄 Creating room in database...
[RoomAPI] ✅ Room created successfully
[RoomAPI] 📤 Sending response with room data
```

### 4️⃣ Response Received & Processed

**Godot Console Output:**

```
[RoomCreation] 📥 Response received from server
[RoomCreation] ✅ Response code: 201
[RoomCreation] ✅ Response body: {"success":true,"room":{...}}
[RoomCreation] 🔄 Parsing JSON response...
[RoomCreation] ✅ JSON parsed successfully
[RoomCreation] ✅ Room data extracted: room_id=room_1234567890_abc123xyz
[RoomCreation] 🎯 Room created successfully! ID: room_1234567890_abc123xyz
[RoomCreation] 📤 Emitting room_created signal
[MultiplayerMenu] 📥 Received room_created signal
[MultiplayerMenu] ✅ Room creation confirmed in MultiplayerMenu
[RoomCreation] 🔄 Dialog closing in 1 second...
[RoomCreation] ✅ Dialog hidden
```

---

## Complete Flow: User Views Server List

### 1️⃣ MultiplayerMenu Appears

**Godot Console Output:**

```
[MultiplayerMenu] ✅ Ready - Initializing
[MultiplayerMenu] 🔗 Connecting GlobalServerList signals
[MultiplayerMenu] 🔗 Connecting RoomCreationDialog signals
[GlobalServerList] ✅ Ready - Server list component initialized
[GlobalServerList] 🔄 Starting auto-refresh timer (5 seconds)
```

### 2️⃣ Auto-Refresh Starts

**Godot Console Output (Every 5 Seconds):**

```
[GlobalServerList] 🔄 Refresh timer triggered
[GlobalServerList] 🔄 Fetching server list from: http://localhost:3000/api/rooms
[GlobalServerList] Auth token: abcdef1234... (first 10 chars)
[GlobalServerList] 🔌 HTTPRequest.request() called
```

**Backend Console Output:**

```
[RoomAPI] 📥 GET ROOMS REQUEST - Fetching active rooms
[RoomAPI] 🔍 No gamemode filter, getting all rooms
[RoomAPI] ✅ Found 3 active rooms
[RoomAPI] 📤 Sending 3 rooms to client
```

### 3️⃣ Response Received & List Updated

**Godot Console Output:**

```
[GlobalServerList] 📥 Response received from server
[GlobalServerList] ✅ Response code: 200
[GlobalServerList] 🔄 Parsing JSON response...
[GlobalServerList] ✅ JSON parsed successfully
[GlobalServerList] 🔄 Clearing old list container...
[GlobalServerList] ✅ Populating with 3 rooms
[GlobalServerList] 📋 Creating entry for room: room_1234567890_abc123xyz
[GlobalServerList] 🎮 Room gamemode: Deathmatch, map: Default
[GlobalServerList] 👤 Room host: TestPlayer
[GlobalServerList] 👥 Room players: 4/8 [Full: false]
[GlobalServerList] 🔗 Connecting join button for room: room_1234567890_abc123xyz
[GlobalServerList] ✅ Adding room entry to container
[GlobalServerList] 📋 Creating entry for room: room_9876543210_xyz789abc
[GlobalServerList] 🎮 Room gamemode: Balls, map: Arena
[GlobalServerList] 👤 Room host: AnotherPlayer
[GlobalServerList] 👥 Room players: 8/8 [Full: true]
[GlobalServerList] 🔗 Connecting join button for room: room_9876543210_xyz789abc
[GlobalServerList] ✅ Adding room entry to container
[GlobalServerList] 📋 Creating entry for room: room_5555555555_def456ghi
[GlobalServerList] 🎮 Room gamemode: Hide and Seek, map: Fortress
[GlobalServerList] 👤 Room host: HideMaster
[GlobalServerList] 👥 Room players: 2/8 [Full: false]
[GlobalServerList] 🔗 Connecting join button for room: room_5555555555_def456ghi
[GlobalServerList] ✅ Adding room entry to container
```

### 4️⃣ User Clicks Join Button

**Godot Console Output:**

```
[GlobalServerList] 🎯 JOIN BUTTON CLICKED for room: room_1234567890_abc123xyz
[GlobalServerList] 📥 Room details: Gamemode=Deathmatch Map=Default
[GlobalServerList] 📤 Emitting room_selected signal with ID: room_1234567890_abc123xyz
[MultiplayerMenu] 📥 Received room_selected signal
[MultiplayerMenu] 🔄 Processing join request for room: room_1234567890_abc123xyz
```

---

## Error Scenarios & Debug Output

### Scenario: No Token Available

**Godot Console Output:**

```
[RoomCreation] 🎯 Create button pressed
[RoomCreation] ❌ AUTH ERROR: Global.auth_token is empty!
[RoomCreation] ❌ Cannot proceed without authentication token
[RoomCreation] ❌ Status: Authentication required. Please sign in again.
```

### Scenario: Network Error During Room Creation

**Godot Console Output:**

```
[RoomCreation] 📤 Sending room creation request to server...
[RoomCreation] 🔌 HTTPRequest.request() called
[RoomCreation] ❌ HTTP Request failed with error: 1
[RoomCreation] ❌ Network error occurred (error code: 1)
[RoomCreation] ❌ Status: Connection failed. Check your internet connection.
```

### Scenario: Invalid Response From Server

**Godot Console Output:**

```
[RoomCreation] 📥 Response received from server
[RoomCreation] ❌ Response code: 400
[RoomCreation] ❌ Error response: {"error":"gamemode is required"}
[RoomCreation] ❌ Status: Server error: gamemode is required
```

### Scenario: Server List Empty (No Rooms)

**Godot Console Output:**

```
[GlobalServerList] ✅ Populating with 0 rooms
[GlobalServerList] ⚠️ No rooms available, showing empty state
[GlobalServerList] 📭 Displaying empty state - no active rooms
```

### Scenario: Server Connection Error

**Godot Console Output:**

```
[GlobalServerList] 🔄 Fetching server list from: http://localhost:3000/api/rooms
[GlobalServerList] ❌ HTTP Request failed with error: 1
[GlobalServerList] ❌ Bad response code: 0
[GlobalServerList] ❌ Displaying error state: Connection Failed
```

---

## Debugging Checklist

### When Room Creation Fails:

- [ ] Check `[RoomCreation] 🎯 Create button pressed` - Did button trigger?
- [ ] Check `[RoomCreation] ❌ AUTH ERROR` - Is auth token present?
- [ ] Check `[RoomAPI] 🎯 CREATE ROOM REQUEST` - Did request reach backend?
- [ ] Check `[RoomAPI] ❌ ERROR creating room` - Any server-side errors?
- [ ] Check `[RoomCreation] 📥 Response received` - Did response return to client?

### When Server List Doesn't Update:

- [ ] Check `[GlobalServerList] 🔄 Refresh timer triggered` - Is refresh running?
- [ ] Check `[GlobalServerList] 🔄 Fetching server list from:` - Correct URL?
- [ ] Check `[RoomAPI] 📥 GET ROOMS REQUEST` - Request reaching backend?
- [ ] Check `[RoomAPI] ✅ Found X active rooms` - Any rooms exist?
- [ ] Check `[GlobalServerList] ✅ Populating with X rooms` - Populating UI?

### When Join Button Doesn't Work:

- [ ] Check `[GlobalServerList] 🎯 JOIN BUTTON CLICKED` - Button click registered?
- [ ] Check `[GlobalServerList] 📤 Emitting room_selected signal` - Signal emitted?
- [ ] Check `[MultiplayerMenu] 📥 Received room_selected signal` - Signal received?

---

## Key Files with Debug Logging

### Frontend

- `src/RoomCreationDialog.gd` - Room creation UI and HTTP logic
- `src/GlobalServerList.gd` - Server list display and refresh
- `src/MultiplayerMenu.gd` - Menu orchestration and signals

### Backend

- `backend-game-server/src/api/roomRoutes.ts` - Room API endpoints
- HTTP request/response logging at every step

---

## Console Timestamp Notes

All debug output is timestamped by the Godot/Node.js console system. Filter debug messages by component name:

- `[RoomCreation]` - Room creation dialog
- `[ServerList]` / `[GlobalServerList]` - Server list component
- `[MultiplayerMenu]` - Menu management
- `[RoomAPI]` - Backend API

---

## Testing Tips

1. **Open both consoles** - Godot Output console + Backend terminal
2. **Create room** - Watch full flow from click to creation
3. **Check auto-refresh** - New room appears in list within 5 seconds
4. **Join room** - Click join and verify signal emission
5. **Watch for emojis** - Easy to spot errors (❌) vs success (✅)
