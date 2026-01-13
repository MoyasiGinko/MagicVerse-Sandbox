# Multiplayer Flow Diagrams

## Complete System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         GAME SERVER (Node.js)                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │           WebSocket Server (Port 30820)                   │  │
│  │                                                           │  │
│  │  Room Manager: Tracks players per room                  │  │
│  │  State Relay: Broadcasts player positions at 10 Hz      │  │
│  │  Peer Management: Assigns peer IDs (1=host, 2+=joiners)│  │
│  └───────────────────────────────────────────────────────────┘  │
└────────────▲──────────────────────────────────────────────────────┘
             │ WebSocket JSON
       ┌─────┴──────────────────────┬──────────────────────┐
       │                            │                      │
       │                            │                      │
    ┌──┴──────────────┐      ┌──────┴──────────┐    ┌─────┴────────────┐
    │  USER 1 (Host)  │      │  USER 2 (Join)  │    │  USER 3 (Join)   │
    │  Peer ID = 1    │      │  Peer ID = 2    │    │  Peer ID = 3     │
    ├─────────────────┤      ├─────────────────┤    ├──────────────────┤
    │  Godot Engine   │      │  Godot Engine   │    │  Godot Engine    │
    │                 │      │                 │    │                  │
    │ MultiplayerNode │      │ MultiplayerNode │    │ MultiplayerNode  │
    │ Adapter         │      │ Adapter         │    │ Adapter          │
    │                 │      │                 │    │                  │
    │ RigidPlayer     │      │ RigidPlayer     │    │ RigidPlayer      │
    │ (name="1")      │      │ (name="2")      │    │ (name="3")       │
    │                 │      │                 │    │                  │
    │ RemotePlayers   │      │ RemotePlayers   │    │ RemotePlayers    │
    │ - RemotePlayer_2│      │ - RemotePlayer_1│    │ - RemotePlayer_1 │
    │ - RemotePlayer_3│      │ - RemotePlayer_3│    │ - RemotePlayer_2 │
    └─────────────────┘      └─────────────────┘    └──────────────────┘
```

## Sequence Diagram: Two Players Joining

```
USER 1 Timeline                     BACKEND              USER 2 Timeline

Start Godot                                             Start Godot
    |                                                        |
    +---> WebSocket Connect ---->|
    |                            |
    +---> Send handshake ------->|
    |                            |  Assign peer_id = 1
    |<----- handshake_accepted -<+
    |                            |
    |<--- Press Host Button ---  |
    |                            |
    +---> create_room -----------|
    |                            |  Create room in DB
    |<----- room_created --------+
    |                            |
    | Show room code to user     |
    | [Waiting for Player 2...]  |
    |                            |
    |                            |  [User 2 joins at T=5s]
    |                            |
    |                            |                    WebSocket Connect -->|
    |                            |                    Send handshake ---->|
    |                            |                    Assign peer_id = 2<-+
    |                            |<-- join_room -----  <--
    |                            |
    |                            |  Get members:
    |                            |  [{peer_id:1, name:'user1', host:true}]
    |                            |
    | peer_joined signal         |  Broadcast peer_joined  -->  player_state
    | spawns RemotePlayer_2 -----+                             now syncs
    |                            |
    [Game Starts - Both Players Visible]
    |
    +---> _physics_process ----->|
    |      - Detect local player |
    |      - Process input (WASD)|
    |      - Update position     |
    |      - Timer += delta      |
    |      If timer >= 0.1:      |
    |        send_player_state()--+---> Broadcast to others
    |                            |
    |<----- player_state --------+
    |      Update RemotePlayer_2 |
    |      Smooth interpolation  |
    |                            |
    User 1 sees User 2's avatar
    moving smoothly
```

## Player State Sync Loop (10 Hz)

```
┌───────────────────────────────────────────────────────────────────┐
│                        Frame N (every 0.1s)                        │
└───────────────────────────────────────────────────────────────────┘

USER 1's _physics_process(delta):
    is_local_player = (int("1") == adapter.get_unique_peer_id())
    ↓ true
    _state_sync_timer += delta
    ↓ (0.1 reached)
    _send_player_state_to_server():
        adapter.send_player_state(pos, rot, vel)
        ↓
        ws.send(JSON: {
            type: "player_state",
            data: {
                position: {x: 10.5, y: 0.5, z: 20.3},
                rotation: {x: 0, y: 1.57, z: 0},
                velocity: {x: 2.5, y: 0, z: 1.3}
            }
        })
    ↓
    BACKEND receives player_state
    ↓
    broadcast(room, "player_state", data, exclude_sender=1)
    ↓
    Send to USER 2 WebSocket
    ↓
    USER 2 _process() in websocket
    ↓
    _on_ws_message()
    ↓
    _handle_player_state(data: {peerId: 1, position: {...}, ...})
    ↓
    world.get_node("RemotePlayers").update_remote_player_state(1, pos, rot, vel)
    ↓
    remote_players[1].update_state(pos, rot, vel)
    ↓
    RemotePlayer_1's _process(delta):
        smooth_position.lerp(target_position, 0.15)
        global_position = smooth_position
        ↓
        USER 2's Screen:
        ✓ Avatar moves smoothly toward new position
```

## Authority Detection (Fixed)

```
RigidPlayer._ready():
    │
    ├─> Detect if USING NODE BACKEND:
    │   Method 1: root.has_meta("node_adapter")?
    │   Method 2: root.get_children() has metadata?
    │   Method 3: find_child("Main").has_meta()?
    │   ↓
    │   Found adapter ✓
    │
    ├─> Compare peer IDs:
    │   int(player.name) == adapter.get_unique_peer_id()
    │   ↓
    │   For User 1: int("1") == 1 → TRUE → is_local_player
    │   For User 2: int("2") == 2 → TRUE → is_local_player
    │
    ├─> Initialize if local:
    │   get_tool_inventory().reset()
    │   set_camera()
    │   connect input signals
    │   update_info()
    │   set_spawns()
    │   go_to_spawn()
    │
    └─> Return early if NOT local (won't happen for local player)

_physics_process():
    │
    ├─> Same authority detection
    │   ↓
    │   If LOCAL: Process input, send state
    │   If REMOTE: Early return (no processing)
    │
    └─> Allow movement and sync
```

## Avatar Spawning Flow

### Scenario 1: User 1 Creates Room (Alone)

```
Main.gd:
    ├─> Spawn local player (peer_id=1)
    ├─> Create RemotePlayers manager
    ├─> Call spawn_pending_members()
    │   └─> No pending members yet (alone)
    └─> World loaded, waiting...

User 1's Screen:
    ├─> Own character visible ✓
    └─> No remote avatars (alone)
```

### Scenario 2: User 2 Joins

```
Backend:
    ├─> Receive join_room from User 2
    ├─> Assign peer_id = 2
    ├─> Send room_joined to User 2 with members=[{peer_id:1, name:'user1'}]
    └─> Broadcast peer_joined(peer_id=2, name='user2') to User 1

User 2's adapter:
    ├─> Receive room_joined
    ├─> Store member {peer_id:1, name:'user1'} in _pending_members
    └─> spawn_pending_members() when RemotePlayers ready
        └─> remote_players.spawn_remote_player(1, 'user1')
            └─> Create RemotePlayer with peer_id=1, player_name='user1'
                └─> In _ready():
                    ├─> Create capsule mesh (random color)
                    ├─> Add Label3D above capsule
                    └─> Set initial position

User 1's adapter:
    ├─> Receive peer_joined(2, 'user2')
    ├─> Check: World exists? YES ✓
    ├─> Check: RemotePlayers exists? YES ✓
    └─> Call spawn_remote_player(2, 'user2')
        └─> Create RemotePlayer with peer_id=2, player_name='user2'
            └─> Same as above

User 1's Screen:
    ├─> Own character (1) visible ✓
    ├─> Remote player 2 avatar appears ✓
    └─> Both in game world

User 2's Screen:
    ├─> Own character (2) visible ✓
    ├─> Remote player 1 avatar appears ✓
    └─> Both in game world

Starting Frame 1 of sync:
    └─> User 1 _physics_process → sends player_state(1)
        → Backend broadcasts to User 2
        → User 2 updates RemotePlayer_1 position
        → User 2 sees User 1's avatar move
```

## Error Recovery Flow

```
Missing World Node:
    ├─> [NodeAdapter] ❌ World not found
    └─> RemotePlayer NOT spawned
        └─> User can't see other player

Missing RemotePlayers Manager:
    ├─> [NodeAdapter] ⚠️ RemotePlayers not found
    ├─> Store in _pending_members
    └─> When spawn_pending_members() called:
        └─> Check again: RemotePlayers exists now?
            ├─> YES → Spawn all pending
            └─> NO → Still not ready

Adapter Not Found:
    ├─> State sync in RigidPlayer fails
    ├─> No movement synced
    └─> Console: [RigidPlayer] 📡 Sent player state NOT appearing

Peer Joined Message Not Received:
    ├─> User 1 doesn't spawn User 2's avatar
    ├─> But User 2's pending_members spawn User 1
    └─> Result: One-way visibility (User 2 sees User 1, not vice versa)
```

## Performance Timeline

```
┌─── Frame 1 (0.000s) ──────────────────────────────────────────┐
│ Game running, player moving                                   │
└────────────────────────────────────────────────────────────────┘

┌─── Frame 10 (0.033s) ─────────────────────────────────────────┐
│ Still accumulating delta time...                              │
└────────────────────────────────────────────────────────────────┘

┌─── Frame 30 (0.100s) ─────────────────────────────────────────┐
│ _state_sync_timer >= 0.1 TRIGGERED!                          │
│ ├─> send_player_state() called                               │
│ ├─> WebSocket message sent                                   │
│ ├─> _state_sync_timer reset to 0.0                           │
│ └─> Next sync in ~30 more frames (0.1s)                      │
└────────────────────────────────────────────────────────────────┘

┌─── Frame 60 (0.200s) ─────────────────────────────────────────┐
│ player_state message from other user received                 │
│ ├─> _handle_player_state() updates target position           │
│ └─> RemotePlayer._process() interpolates each frame          │
│     └─> Smooth movement from old pos to new pos over ~7 frames
└────────────────────────────────────────────────────────────────┘

RESULT:
┌─ User 1's View ─────────────────┬─ User 2's View ─────────────────┐
│ Own character: Responsive       │ Own character: Responsive       │
│ User 2's avatar: Updates every  │ User 1's avatar: Updates every  │
│               0.1s, smooth      │               0.1s, smooth      │
│               interpolation     │               interpolation     │
└────────────────────────────────────────────────────────────────────┘
```

---

## Summary of Message Flow

### Key Messages

1. **handshake** → Backend assigns peer_id
2. **create_room** → Backend creates room
3. **join_room** → Backend assigns peer_id, sends members list
4. **room_joined** → Client receives room confirmation + existing members
5. **peer_joined** → Backend broadcasts new joiner to existing clients
6. **player_state** → Broadcasted every 0.1s to sync positions
7. **peer_left** → When a player disconnects

### Message Count Per Second

```
Single Player (alone):
  ├─> send: 10 player_state per second
  └─> receive: 0 player_state per second

Two Players:
  ├─> send: 10 player_state per second (to backend)
  ├─> receive: 10 player_state per second (from other player)
  └─> total: 20 messages/sec per client, 20 messages total in backend

Three Players:
  ├─> send: 10 player_state per client to backend = 30 total
  ├─> receive: 20 player_state per client from others = 60 total
  └─> backend: 30 incoming, ~20 outgoing per client = 60-90 total

Scale: N players × 10 Hz × 2 directions = manageable bandwidth
```

---
