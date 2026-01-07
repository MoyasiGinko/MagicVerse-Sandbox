What the game is: Tinybox is a physics-first sandbox with bricks, placeable world props, and optional gamemodes layered on top (deathmatch, KOTH, race, balls, hide/seek, etc.). Worlds define gravity, kill planes, respawn timers, songs, environment/sky, and a stack of TBW objects plus voxel-like bricks. Gamemode scaffolding lives in Gamemode.gd and concrete modes are enabled automatically based on map contents (e.g., capture points, team spawns) when a world loads in World.gd:430-520.

Multiplayer architecture: Server-authoritative ENet (port 30815, UDP info on 30816, FASTLZ compression). The host or headless server creates the ENet peer, spawns a World, and listens for LAN discovery/UDP info (Main.gd and InfoServer.gd). Clients connect, perform a version/name/banned check handshake, and the server instantiates their RigidPlayer (Main.gd:400-520). Authority stays on the server for world loads, physics, and property sync. Server pauses when empty and resumes on join (Main.gd:400-520). TBW object property replication uses RPC sync_tbw_obj_properties (World.gd:519-548).

World loading/switching flow:

Clients ask the server to open a TBW (ask_server_to_open_tbw), with rate-limit and “clients allowed?” guard. Server either denies or loads, then announces the switch to everyone (World.gd:250-309).
Loading path: clear old map → reset map props → optionally show loading overlay → parse TBW lines → reset cameras/players → rebuild gamemode list → emit tbw_loaded (World.gd:322-420).
Map properties (songs, gravity, respawn, death limits) are applied while parsing TBW before objects/bricks are spawned (World.gd:361-413; Map.gd).
Bricks and TBW objects are instantiated via the spawnable dictionary (SpawnableObjects.gd). Buildings are loaded with \_server_load_building, which offsets/rotates placements, clamps batching, joins bricks, and re-checks groups; loading is rate-limited to protect servers (World.gd:545-650).
TBW file format (save/load):

Header [tbw] with version, author, inline base64 image (client-only), optional songs, death*limit_low/high, respawn_time, gravity_scale (World.gd:150-240).
[objects] section: each line is type ; prop:value ; .... Types map to TBWObject scenes or Environment. Strings are c-escaped; some props JSON-stringified (events/watchers). Properties are typed by name during load (World.gd:210-335; Global.gd:317-360).
[building] section: bricks with type ; prop:value ...; \_server_load_building parses, optionally recenters to a placement point, and applies rotations (World.gd:545-650).
Save paths: user worlds user://world/*.tbw, buildings user://building/\_.tbw, temp clipboard user://building/temp.tbw, server saves to UserPreferences.os_path (World.gd:100-200). Built-in maps live in res://data/tbw/ and show up in selectors (Global.gd:277-337).
TBW objects and environments: TBWObject is the saveable base with tbw_object_type and a whitelist of persisted properties (position/rotation/scale by default). It can sync properties over RPC (TBWObject.gd). TBWEnvironment holds environment_name for sky/fog presets (TBWEnvrionment.gd). The spawnable registry includes props (water, lifts, signs, pickups, capture points, track pieces), environments, backgrounds, and bricks (SpawnableObjects.gd).

World editing & building workflow:

The in-game Editor and the player Build Tool share EditorBuildTool: two modes (BUILD, SELECT), live previews, rotation/scale shortcuts, property editor integration, and a clipboard TBW (temp.tbw) for copy/paste/selection saves (EditorBuildTool.gd:1-360).
Saving grabs either the whole world or a selection; selections become buildings stored under user://building/\*.tbw and can be pasted with placement rotation, snapped, and joined (World.gd:100-230; EditorBuildTool.gd:330-420).
Property editing writes directly to hovered instances; in player mode it also RPC-syncs to peers (EditorBuildTool.gd:60-160).
Player/camera/bootstrap:

On host: create ENet server, spawn world, optionally UPnP port-map, advertise on LAN, load default or saved server world, spawn shared camera, add host player, unpause physics (Main.gd).
On join: create client peer, wait for map_loaded, spawn camera at staging position, show loading canvas until player is ready, then accept world state from server (Main.gd).
Map gravity/song/respawn values are RPC’d to late joiners via Map.\_on_peer_connected (Map.gd:25-95).
Server list & hosting:

Official list read from server_list.json and can be extended via PR/issue (SERVERS.md).
Dedicated/headless server mode saves server_world.tbw on quit; uses --headless, ports 30815-30816, and can disable client-triggered world loads via server prefs (Main.gd; SERVERS.md).
World Database API (remote map sharing): Optional HTTP API (default Cloudflare Worker endpoint) with GET list/download, POST upload (name, tbw), and report; returns preview images and metadata parsed from TBW (README.md).

External multiplayer backend (Node) coexistence plan

- Goal: add an optional Node-based room server that coexists with current ENet/MultiplayerAPI. Keep Godot RPC/authority semantics intact while enabling more control, observability, and deployment flexibility.
- Backend selector: expose a setting (UI + CLI/pref) to pick transport: default ENet or Node. Host/join flows branch at peer creation in Main.gd; fall back to ENet if Node is unavailable.
- Compatibility constraints: server id stays 1; peer ids are authoritative and used as node names; `get_remote_sender_id()` must map to the same ids; `peer_connected/peer_disconnected` signals must fire identically; remote IP needed for bans/logs; `rpc/rpc_id` ordering/reliability preserved. All map loads still go through ask_server_to_open_tbw/open_tbw and existing cooldowns/permissions in World.gd.
- Wire protocol (Node): WebSocket or TCP; messages for handshake (version/name/ban), room create/join, chat/commands, TBW transfer (plaintext lines), world switch announce, player snapshots, and kicks. Host remains world authority; clients request world loads; server enforces rate limits.
- Godot adapter: implement a custom MultiplayerPeer/bridge that maps Node messages to Godot RPC calls and sender ids. On leave, swap to OfflineMultiplayerPeer. Preserve LAN/UDP paths for ENet; add a simple “Node rooms” join (manual address or list endpoint).
- Node room server responsibilities: room lifecycle, player registry, per-room bans/admin, rate limiting, TBW relay/fan-out, state relay/broadcast, logging/metrics hooks, optional relay/NAT-help. Document ports and NAT/UPnP expectations for host PCs.
- Observability/control: surface active backend, room id, player count, and status in-game; expose admin commands (ban/kick/load map) and metrics in Node.
- Testing matrix: host ENet/join ENet (baseline), host Node/join Node (new), late joins syncing TBW props, gamemode start/end, brick placement, map load rate-limit, and disconnect/teardown.
