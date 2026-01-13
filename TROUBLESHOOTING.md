# Multiplayer Troubleshooting Guide

## Quick Diagnostic Checklist

When testing, watch the console for these messages:

### Successful Flow Indicators

```
[NodeAdapter] ✅ Room joined with X members
[NodeAdapter] 👤 Found existing peer: 1 name=user1
[NodeAdapter] 📡 Emitted peer_connected signal for peer: 1
[RigidPlayer] 🎮 Initializing player: name=1 peer_id=1 is_authority=true
[RigidPlayer] ✅ Is local player, initializing controls and camera
[RigidPlayer] 📍 Spawns set to: 3 spawn points
[RigidPlayer] 📍 Going to spawn at: (x, y, z)
[RemotePlayer] 🎭 Spawning remote player: peer_id=1 name=user1 pos=(x, y, z)
[RigidPlayer] 📡 Sent player state: pos=(x, y, z) rot=(x, y, z)
```

### Problems & Solutions

#### Problem: Player doesn't move

```
❌ Look for: [RigidPlayer] 📡 Sent player state messages NOT appearing
```

**Cause:** Adapter not found in `_send_player_state_to_server()`
**Fix:** Check that `Main.gd` stores adapter in metadata at line ~867

#### Problem: Player spawns in wrong location

```
❌ Look for: [RigidPlayer] 📍 Going to spawn at: message NOT appearing
```

**Cause:** RPC call in `_on_tbw_loaded()` failing
**Fix:** Verify line ~809 detects Node backend correctly

#### Problem: Can't see other player's avatar

```
❌ Look for: [RemotePlayer] 🎭 Spawning remote player messages NOT appearing
          or [NodeAdapter] 👥 Peer joined messages NOT appearing
```

**Causes:**

1. Backend not sending "peer_joined" message
2. RemotePlayers manager not created yet
3. World not found when peer_joined processed

**Debug Steps:**

1. Check [NodeAdapter] logs - should show peer_joined
2. Check if World exists at that time
3. Check if RemotePlayers manager was added to World
4. Check console for ❌ errors

#### Problem: Team list shows only names, not player objects

```
❌ Look for: Actual player not appearing in list
```

**Cause:** `update_info()` RPC calls not executing
**Fix:** Verify line ~680 detects Node backend and calls functions directly

#### Problem: GameCanvas not showing for User 2

```
❌ Look for: GameCanvas visibility not set
```

**Cause:** Game initialization completes before player loads
**Fix:** Check line ~968 visibility timing

---

## Console Message Legend

### ✅ Green Check - Working

```
[NodeAdapter] ✅ Message
[RigidPlayer] ✅ Message
[RemotePlayer] ✅ Message
```

### 📡 Signal/Network Messages

```
[NodeAdapter] 📡 Message
[RigidPlayer] 📡 Message
```

### 🔍 Debug Info

```
[NodeAdapter] 🔍 Message
[RigidPlayer] 🔍 Message
```

### ⚠️ Warnings (Non-Fatal)

```
[NodeAdapter] ⚠️ Message
```

### ❌ Errors (Critical)

```
[NodeAdapter] ❌ Message
[RigidPlayer] ❌ Message
```

---

## Performance Metrics

### Expected Values

| Metric                          | Expected | Unit            |
| ------------------------------- | -------- | --------------- |
| Player State Frequency          | 10       | Hz              |
| Player State Interval           | 0.1      | seconds         |
| Avatar Interpolation Speed      | 0.15     | lerp factor     |
| Avatar Interpolation Smoothness | ~150ms   | to reach target |

### How to Verify

1. **State Sync Working:** Count "[RigidPlayer] 📡 Sent player state" messages per second (should be ~10)
2. **Avatar Updates:** Count "[NodeAdapter] 📍 Updated state for peer" messages per second (should be ~10 per player)
3. **Avatar Smoothness:** Watch avatars move - should be smooth, not jerky

---

## Network Testing

### Test 1: Single User Movement

1. User 1 joins alone
2. Console should show own position updates
3. No avatar should spawn (no other players)

### Test 2: Second User Joins

1. User 1 in game
2. User 2 joins with same room code
3. Console should show:
   - User 2's player initialization
   - User 1 sees peer_joined message
   - User 1's RemotePlayers spawns User 2's avatar

### Test 3: Continuous Movement Sync

1. Both users in game
2. User 1 walks in a circle
3. User 2 should see smooth avatar movement in same circle
4. Console should show continuous state updates

### Test 4: Camera-Avatar Verification

1. Spawn at checkpoint (y≈0)
2. Camera at y=190 looking down
3. Both character capsules should be visible and not overlapping

---

## Common Issues & Quick Fixes

| Issue              | Quick Fix                 | Verification                    |
| ------------------ | ------------------------- | ------------------------------- |
| Player not moving  | Restart game              | Check WASD input works          |
| Avatar not visible | Close and rejoin          | Check RemotePlayer console logs |
| Team list empty    | Refresh UI                | Check if player added to list   |
| Can't spawn        | Verify spawn points exist | Check map has spawns for team   |
| GameCanvas hidden  | Toggle pause menu         | Check Main.gd visibility code   |

---

## Node Backend vs ENet Differences

### Node Backend (Current)

- ✅ Uses WebSocket protocol
- ✅ Centralized room management
- ❌ RPC system disabled (OfflineMultiplayerPeer)
- ✅ Works up to 10-15 concurrent players
- ✅ Automatic host detection

### ENet (Legacy)

- ❌ Peer-to-peer (each player connects to others)
- ✅ RPC system fully functional
- ✅ Distributed gameplay logic
- ❌ Complex NAT/firewall issues
- ❌ Manual host IP setup

---

## Testing Environment Setup

### For Development

1. **Backend Running:**

   ```bash
   cd backend-game-server
   npm run dev
   # Should show: "WebSocket server listening on port 30820"
   ```

2. **Game Running:**

   - Start Godot with Node backend enabled
   - Global mode selected
   - Player 1 creates room
   - Player 2 joins with room code

3. **Monitoring:**
   - Godot debugger console (bottom panel)
   - Backend console (npm run dev terminal)
   - Network traffic (if using Wireshark)

---

## Logs to Keep

When reporting issues, collect:

1. Full console output from both players
2. Backend console output (npm terminal)
3. Time when issue occurred
4. Room code and player names
5. Steps to reproduce

---
