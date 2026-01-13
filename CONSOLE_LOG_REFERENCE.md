# Remaining Console Logs - Quick Reference

After cleanup, these are the essential logs you'll see during multiplayer testing.

## Expected Log Sequence (Normal Operation)

```
[Main] ✅ Initialization complete                           # Game started

# Server creates room
[NodeAdapter] Connecting to ws://localhost:30820             # WebSocket connecting
[NodeAdapter] WebSocket connected                            # WebSocket open
[NodeAdapter] 🤝 Sent handshake: version=... name=... auth=true    # Server auth
[NodeAdapter] ✅ Handshake accepted                          # Auth successful
[NodeAdapter] 📤 Sending create_room...                      # Creating room
[NodeAdapter] ✅ Room created: [ROOM_ID] (peer 1)            # Room created successfully
[Main] 🔗 Joining room: [ROOM_ID] on server: ws://localhost:30820  # Room joined

# Client joins room
[Main] 🔗 Joining room: [ROOM_ID] on server: ws://localhost:30820  # Client connecting
[NodeAdapter] Connecting to ws://localhost:30820
[NodeAdapter] WebSocket connected
[NodeAdapter] 🤝 Sent handshake: version=... name=... auth=true
[NodeAdapter] ✅ Handshake accepted
[NodeAdapter] 📥 Requesting to join room: [ROOM_ID]
[NodeAdapter] ✅ Room joined: [ROOM_ID] peers=1 (is_server=false)  # Client joined

# Remote player spawning
[RemotePlayers] 👤 Spawned remote player: peer_id=1 name=Player1    # Avatar created
[RemotePlayers] 👤 Spawned remote player: peer_id=2 name=Player2    # Avatar created on other client
```

## Error Log Examples

```
[NodeAdapter] Failed to connect to ws://localhost:30820: [error details]  # Connection failed
[NodeAdapter] ❌ ERROR: Cannot send message - WebSocket not open!        # WebSocket died
[NodeAdapter] Error from backend: [reason]                              # Backend error
[NodeAdapter] Only host can kick peers                                  # Permission error
```

## Debug Tips

1. **Connection Issues?**

   - Look for "Connecting to ws://localhost:30820"
   - Look for "WebSocket connected"
   - If either is missing, backend not responding

2. **Room Join Issues?**

   - Look for "✅ Room joined" or "✅ Room created"
   - If missing, server didn't respond

3. **Avatar Not Showing?**

   - Look for "👤 Spawned remote player"
   - If missing, RemotePlayers never received the peer_joined signal

4. **Movement Not Syncing?**
   - No log for this anymore (removed from sync loop to avoid spam)
   - Check error logs - if no errors, movement sync is working silently

## What Logs Were Removed

**Verbose Details (removed to reduce noise):**

- Individual adapter lookup attempts
- WebSocket object details
- Message JSON content
- Member enumeration lists
- Individual authority checks

**Loop-Based Logs (removed to prevent spam):**

- State sync confirmation every 0.1 seconds
- Individual initialization confirmation messages

**Expected Behavior Logs (removed - not errors):**

- "Not local player, returning early"
- "Player already exists, skipping"
- "Player not found" on late operations

## When to Check Logs

✅ **Check during**

- Initial connection (look for WebSocket + handshake)
- Room creation/joining (look for room_created/room_joined)
- Player spawning (look for "Spawned remote player")

⚠️ **If something breaks**

- All errors will now be clearly visible
- No background noise to filter through
- Error messages will stand out immediately

## New Console Behavior

The console is now much cleaner:

- **5-10 connection logs** when joining
- **2-3 spawn logs** per remote player
- **Errors appear immediately** with no noise
- **State sync is silent** but working

This makes it MUCH easier to identify actual problems vs. normal operation.
