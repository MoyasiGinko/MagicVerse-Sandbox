# 🎯 Quick Debug Reference Card

## Components with Debug Logging

```
FRONTEND (Godot)
├─ RoomCreationDialog.gd .......... 7 methods, ~40 logs
├─ GlobalServerList.gd ........... 10 methods, ~60 logs
└─ MultiplayerMenu.gd ............ 4 methods, ~15 logs

BACKEND (Node.js)
└─ roomRoutes.ts ................. 3 endpoints, ~25 logs

DOCUMENTATION
├─ DEBUG_FLOW.md
├─ DEBUG_LOGGING_COMPLETE.md
├─ ROOM_SYSTEM_COMPLETE.md
└─ DEBUGGING_SESSION_COMPLETE.md (this file)
```

---

## Console Output Identifiers

### Search for these in Godot Output console:

```
[RoomCreation]     → Room creation dialog logs
[GlobalServerList] → Server list component logs
[MultiplayerMenu]  → Menu orchestration logs
```

### Search for these in Backend terminal:

```
[RoomAPI] → Room API endpoint logs
```

---

## Emoji Quick Guide

| Emoji | Meaning     |
| ----- | ----------- |
| ✅    | Success     |
| ❌    | Error       |
| 🔄    | In Progress |
| 📤    | Sending     |
| 📥    | Receiving   |
| 🎯    | Action      |
| 👤    | User        |
| 👥    | Players     |
| 🎮    | Gamemode    |
| 📋    | List        |
| 📭    | Empty       |

---

## Test Workflow

### 1. Start Backend

```bash
cd backend-game-server
npm start
# Watch for: [RoomAPI] logs
```

### 2. Open Godot

```
Run Project → Output Console visible
Watch for: [RoomCreation] [GlobalServerList] logs
```

### 3. Create Room

```
Click "Host Server"
→ See: [RoomCreation] Showing dialog...
Select options
→ Click "Create Room"
→ See: [RoomCreation] === CREATE BUTTON PRESSED ===
→ Check backend: [RoomAPI] 🎯 CREATE ROOM REQUEST received
→ Verify: [RoomCreation] ✅ Room created successfully!
```

### 4. Check Server List

```
Wait 5 seconds (auto-refresh)
→ See: [GlobalServerList] 🔄 Refresh timer triggered
→ Check: [GlobalServerList] ✅ Found X active rooms
→ Verify: New room appears in list
```

### 5. Test Join

```
Click "Join" on room
→ See: [GlobalServerList] 🎯 JOIN BUTTON CLICKED
→ See: [GlobalServerList] 📤 Emitting room_selected signal
→ Verify: [MultiplayerMenu] 📥 Received room_selected signal
```

---

## Common Debug Scenarios

### Room Creation Fails

**Check:**

- ❌ Error log? Check error message
- 🔄 Sending to backend?
- ❌ Bad response code?

**Solution:** See DEBUG_FLOW.md for error scenarios

### Server List Empty

**Check:**

- 🔄 Auto-refresh running?
- ✅ Rooms being fetched?
- 📭 No rooms exist?

**Solution:** Create room and wait 5 seconds for auto-refresh

### Join Button Not Responding

**Check:**

- ✅ Button click logged?
- 📤 Signal emitted?
- 📥 Signal received in menu?

**Solution:** See ROOM_SYSTEM_COMPLETE.md testing section

---

## Documentation Map

| File                          | Purpose                      | When to Read                    |
| ----------------------------- | ---------------------------- | ------------------------------- |
| DEBUG_FLOW.md                 | Flow walkthroughs & examples | Understanding the complete flow |
| DEBUG_LOGGING_COMPLETE.md     | Implementation details       | What was changed and how        |
| ROOM_SYSTEM_COMPLETE.md       | System reference             | Architecture & API details      |
| DEBUGGING_SESSION_COMPLETE.md | This session summary         | What was accomplished           |

---

## Quick Debug Commands

### Godot Console Filter

```
Search box: [RoomCreation]
Search box: [GlobalServerList]
Search box: ❌ (to find errors)
Search box: ✅ (to verify success)
```

### Backend Log Watch

```
Backend terminal will show all [RoomAPI] logs
Press Ctrl+L to clear
Scroll up to see request history
```

---

## Success Indicators

✅ Room creation working:

- Dialog shows when "Host" clicked
- Form validates
- Request sends to backend
- Room appears in list

✅ Server list working:

- Auto-refresh every 5 seconds
- New rooms appear
- Player count updates
- Join button responds

✅ Debug logging working:

- Console fills with colored emoji messages
- Frontend and backend logs correlate
- Error messages appear when things fail

---

## Performance Notes

Expected timings:

- Dialog open: Instant
- HTTP request: 10-100ms
- Room creation: ~100-200ms
- List refresh: ~50-100ms
- Auto-refresh interval: 5 seconds

---

## Support

**If something isn't working:**

1. Check console output for ❌ errors
2. Note the exact error message
3. Review DEBUG_FLOW.md error scenarios
4. Compare your output to expected output
5. Check backend logs for corresponding entries
6. Verify auth token exists: `[RoomCreation] ✓ User authenticated`

---

**Created:** Debugging Session Complete
**Status:** ✅ Ready for Testing
**Components:** 24+ debug points across frontend & backend
**Documentation:** 3 comprehensive guides + this card

🎉 System Ready for Full Testing!
