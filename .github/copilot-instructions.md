# Copilot instructions for Tinybox

## Big picture

- Godot 4.5 project with server-authoritative multiplayer via ENet; world loads, physics authority, and replication are driven by the host/server. See [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) and [src/Main.gd](src/Main.gd).
- World loading is centralized in the World singleton: clients request map opens, server enforces rate limits and broadcasts map switches. Key logic lives in [src/World.gd](src/World.gd).
- TBW is the save/load format for maps and buildings; TBW parsing/writing and property typing are part of the world load path. See [src/World.gd](src/World.gd) and [src/Global.gd](src/Global.gd).
- Spawnable objects are registered in a shared dictionary and instantiated during TBW load. See [src/SpawnableObjects.gd](src/SpawnableObjects.gd).
- Optional external Node.js room server exists under backend-game-server for WebSocket-based rooms and Worlds API. See [backend-game-server/README.md](backend-game-server/README.md) and [WORLDS_API.md](WORLDS_API.md).

## Developer workflows

- Open the project in Godot 4.5; link a Blender 4.4+ executable before importing assets. See [README.md](README.md).
- Dedicated/headless server runs from the game binary with `--headless` and uses ports 30815-30816. See [docs/SERVERS.md](docs/SERVERS.md).
- Backend server: `npm install` then `npm start` in backend-game-server; tests use `npm test`. See [backend-game-server/package.json](backend-game-server/package.json).

## Project-specific conventions

- GDScript is statically typed; follow existing type annotations. See [README.md](README.md).
- Multiplayer authority: host/server owns world loads and physics; clients request changes via RPC and wait for server announcements. See [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) and [src/World.gd](src/World.gd).
- TBW object persistence is explicit: only whitelisted properties are saved/synced; base class is in [src/TBWObject.gd](src/TBWObject.gd).
- In-game editor and build tool share logic; copy/paste uses a temp TBW file for selections. See [src/EditorBuildTool.gd](src/EditorBuildTool.gd).

## Integration points

- World Database API defaults to a remote endpoint but can be self-hosted; request/response schema is in [README.md](README.md) and [WORLDS_API.md](WORLDS_API.md).
- Server list is fetched from a JSON file referenced in [docs/SERVERS.md](docs/SERVERS.md); additions are via PR/issue.
- External Node room server uses WebSocket JSON envelopes and exposes a Worlds API at `http://localhost:30820/api/worlds`. See [backend-game-server/README.md](backend-game-server/README.md) and [WORLDS_API.md](WORLDS_API.md).
