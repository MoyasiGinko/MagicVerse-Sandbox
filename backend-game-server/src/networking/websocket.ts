import { WebSocketServer, WebSocket, RawData } from "ws";
import http from "http";
import { logInfo, logError } from "../utils/logger";
import { RoomManager, GameRoom } from "../game/roomManager";
import { verifyToken } from "../auth/jwt";
import { RoomRepository } from "../database/repositories/roomRepository";
import { UserRepository } from "../database/repositories/userRepository";

type Message = { type: string; data?: unknown };

type ClientSession = {
  ws: WebSocket;
  peerId: number | null;
  roomId: string | null;
  name: string;
  version: string;
  ip: string;
  userId: number | null; // Added for authenticated users
  isAuthenticated: boolean; // Track if user is authenticated
};

const roomManager = new RoomManager();
const clientSessions = new Map<WebSocket, ClientSession>();
const roomRepo = new RoomRepository();
const userRepo = new UserRepository();

function getClientIp(ws: WebSocket): string {
  const remoteAddr =
    (ws as any).remoteAddress ||
    (ws as any)._socket?.remoteAddress ||
    "unknown";
  return remoteAddr === "::1" || remoteAddr === "127.0.0.1"
    ? "localhost"
    : remoteAddr;
}

function send(ws: WebSocket, type: string, data: unknown = {}) {
  try {
    ws.send(JSON.stringify({ type, data } satisfies Message));
  } catch (e) {
    logError(`send failed: ${String(e)}`);
  }
}

function broadcast(
  room: GameRoom,
  type: string,
  data: unknown,
  excludePeerId?: number
) {
  for (const client of room.clients.values()) {
    if (excludePeerId && client.peerId === excludePeerId) continue;
    const session = Array.from(clientSessions.values()).find(
      (s) => s.roomId === room.id && s.peerId === client.peerId
    );
    if (session) {
      send(session.ws, type, data);
    }
  }
}

function broadcastToAll(type: string, data: unknown) {
  /**Broadcast to all connected WebSocket clients*/
  for (const session of clientSessions.values()) {
    send(session.ws, type, data);
  }
}

function validateJson(raw: string): Message | null {
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed.type === "string") return parsed as Message;
    return null;
  } catch {
    return null;
  }
}

function cleanupClient(ws: WebSocket) {
  const session = clientSessions.get(ws);
  if (!session) return;
  const { roomId, peerId, userId, isAuthenticated, name } = session;

  // Broadcast user_offline to all clients if authenticated
  if (isAuthenticated && userId) {
    broadcastToAll("user_offline", {
      user_id: userId,
      username: name,
    });
    logInfo(`Broadcasting user_offline for user ${userId}`);
  }

  clientSessions.delete(ws);
  if (roomId && peerId !== null) {
    const room = roomManager.getRoom(roomId);
    if (room) {
      // Check if leaving player was the host
      const leavingMember = room.clients.get(peerId);
      const wasHost = leavingMember?.isHost || false;

      roomManager.leaveRoom(roomId, peerId);

      // Remove player from session (decrements player count)
      if (userId) {
        roomRepo.removePlayerSession(userId, roomId);
        console.log(
          `[WebSocket] 🚪 Player ${userId} disconnected from room ${roomId}`
        );
      }

      // If the host left and there are still players, promote the next player
      const remainingMembers = roomManager.getRoomMembers(roomId);
      if (wasHost && remainingMembers.length > 0) {
        // Promote first remaining member to host
        remainingMembers[0].isHost = true;
        console.log(
          `[WebSocket] 👑 Player ${remainingMembers[0].name} promoted to host (previous host left)`
        );
        // Notify all players about the new host
        broadcast(room, "host_changed", {
          newHostPeerId: remainingMembers[0].peerId,
          newHostName: remainingMembers[0].name,
        });
      }

      broadcast(room, "peer_left", { peerId }, peerId);
      logInfo(`peer left: roomId=${roomId} peerId=${peerId}`);
    }
  }
}

export function setupWebSocket(server: http.Server) {
  const wss = new WebSocketServer({ server });

  wss.on("connection", (ws: WebSocket) => {
    const ip = getClientIp(ws);
    const session: ClientSession = {
      ws,
      peerId: null,
      roomId: null,
      name: "",
      version: "",
      ip,
      userId: null,
      isAuthenticated: false,
    };
    clientSessions.set(ws, session);
    logInfo(`ws: client connected from ${ip}`);

    ws.on("message", (raw: RawData) => {
      const msg = validateJson(raw.toString());
      if (!msg) {
        return send(ws, "error", { reason: "bad_json" });
      }

      switch (msg.type) {
        case "handshake": {
          // Handle authentication with JWT token
          if (
            !msg.data ||
            typeof (msg.data as any).version !== "string" ||
            typeof (msg.data as any).name !== "string"
          ) {
            return send(ws, "error", { reason: "invalid_handshake" });
          }

          const token = (msg.data as any).token;
          if (token) {
            // Verify JWT token
            const user = verifyToken(token);
            if (user) {
              session.userId = user.userId;
              session.isAuthenticated = true;
              session.name = user.username;
              logInfo(
                `authenticated user: userId=${user.userId} username=${user.username}`
              );
            } else {
              return send(ws, "error", { reason: "invalid_token" });
            }
          } else {
            // Allow unauthenticated connections for classic mode
            session.name = (msg.data as any).name;
          }

          session.version = (msg.data as any).version;
          send(ws, "handshake_accepted", {
            peer_id: session.peerId || 0,
            user_id: session.userId,
            username: session.name,
          });
          logInfo(
            `handshake: name=${session.name} auth=${session.isAuthenticated}`
          );

          // Broadcast user_online to all clients if authenticated
          if (session.isAuthenticated && session.userId) {
            broadcastToAll("user_online", {
              user_id: session.userId,
              username: session.name,
            });
            logInfo(`Broadcasting user_online for user ${session.userId}`);
          }

          break;
        }

        case "create_room": {
          // Require authentication for global mode
          if (!session.isAuthenticated) {
            return send(ws, "error", { reason: "authentication_required" });
          }

          // For global mode, the room should already exist from HTTP POST
          // Check if user already has a room
          const existingRoom = roomRepo.getPlayerCurrentRoom(session.userId!);

          if (!existingRoom) {
            return send(ws, "error", {
              reason: "no_room_found",
              message: "Room must be created via HTTP POST /api/rooms first",
            });
          }

          // Use the existing room from database
          const roomId = existingRoom.id;

          // Create room in memory if it doesn't exist yet
          let room = roomManager.getRoom(roomId);
          if (!room) {
            room = roomManager.createRoomWithId(
              roomId,
              session.version,
              session.name,
              ip
            );
          }

          // Host already added to player_sessions in HTTP POST
          // Just update session and respond
          console.log(
            `[WebSocket] 👑 Host ${session.userId} confirming room ${roomId}`
          );

          session.peerId = 1;
          session.roomId = roomId;
          send(ws, "room_created", {
            roomId: roomId,
            peerId: 1,
            gamemode: existingRoom.gamemode,
            mapName: existingRoom.map_name,
          });
          logInfo(
            `room created: roomId=${roomId} gamemode=${existingRoom.gamemode} host=${session.name}`
          );
          break;
        }

        case "join_room": {
          // Require authentication for global mode
          if (!session.isAuthenticated) {
            console.log(`[WebSocket] ❌ join_room: User not authenticated`);
            return send(ws, "error", { reason: "authentication_required" });
          }

          if (
            !msg.data ||
            typeof (msg.data as any).roomId !== "string" ||
            typeof (msg.data as any).version !== "string" ||
            typeof (msg.data as any).name !== "string"
          ) {
            console.log(`[WebSocket] ❌ join_room: Invalid data format`);
            return send(ws, "error", { reason: "invalid_join_room" });
          }

          const roomId = (msg.data as any).roomId;
          const version = (msg.data as any).version;
          const playerName = (msg.data as any).name;

          console.log(
            `[WebSocket] 📥 join_room request: user=${session.userId} room=${roomId} name=${playerName}`
          );
          console.log(
            `[WebSocket] 📥 join_room request: user=${session.userId} room=${roomId} name=${playerName}`
          );

          // Check if room exists in memory; if not, try to load from database
          let room = roomManager.getRoom(roomId);
          if (!room) {
            // Room not in memory yet; create it from database info
            const dbRoom = roomRepo.getRoomById(roomId);
            if (!dbRoom) {
              console.log(
                `[WebSocket] ❌ join_room: Room ${roomId} not found in database`
              );
              return send(ws, "error", { reason: "room_not_found" });
            }
            // Create room in memory with info from database
            room = roomManager.createRoomWithId(
              roomId,
              version,
              dbRoom.host_username,
              ip
            );
            console.log(
              `[WebSocket] 📂 Loaded room ${roomId} from database into memory`
            );
          }

          const result = roomManager.joinRoom(roomId, version, playerName, ip);
          if ("error" in result) {
            console.log(
              `[WebSocket] ❌ join_room: RoomManager error - ${result.error}`
            );
            return send(ws, "error", { reason: result.error });
          }
          const { room: updatedRoom, peerId } = result;
          session.peerId = peerId;
          session.name = playerName;
          session.version = version;
          session.roomId = roomId;

          // Add player to room session (enforces single-room, increments player count)
          const sessionAdded = roomRepo.addPlayerSession(
            session.userId!,
            roomId
          );
          if (!sessionAdded) {
            console.log(
              `[WebSocket] ⚠️  Player ${session.userId} already in room ${roomId}, sending existing session info`
            );
            // Player already in room - just send them the room_joined confirmation again
            const members = roomManager.getRoomMembers(roomId);
            const dbRoom = roomRepo.getRoomById(roomId);
            return send(ws, "room_joined", {
              roomId: roomId,
              peerId,
              members: members.map((c) => ({
                peerId: c.peerId,
                name: c.name,
                isHost: c.isHost,
              })),
              gamemode: dbRoom?.gamemode || "Deathmatch",
              mapName: dbRoom?.map_name || "Frozen Field",
              currentTbw: updatedRoom.currentTbw,
            });
          }
          console.log(
            `[WebSocket] 🎮 Player ${session.userId} joined room ${roomId}`
          );

          // Check if room was empty and promote this player to host
          const memberCount = roomManager.getRoomMembers(roomId).length;
          if (memberCount === 1) {
            // This is the first player joining - make them the host
            const updatedMember = roomManager.getRoomMembers(roomId)[0];
            updatedMember.isHost = true;
            console.log(
              `[WebSocket] 👑 Player ${session.userId} promoted to host (first member in empty room)`
            );
          }

          // Player count already updated by addPlayerSession, no need to update again

          const members = roomManager.getRoomMembers(roomId);
          console.log(
            `[WebSocket] 👥 Room ${roomId} members:`,
            members.map((m) => `peer=${m.peerId} name=${m.name}`)
          );

          // Get room info from database to include gamemode and map
          const dbRoom = roomRepo.getRoomById(roomId);

          send(ws, "room_joined", {
            roomId: roomId,
            peerId,
            members: members.map((c) => ({
              peerId: c.peerId,
              name: c.name,
              isHost: c.isHost,
            })),
            gamemode: dbRoom?.gamemode || "Deathmatch",
            mapName: dbRoom?.map_name || "Frozen Field",
            currentTbw: updatedRoom.currentTbw,
          });

          console.log(
            `[WebSocket] 📢 Broadcasting peer_joined to room: peerId=${peerId} name=${session.name}`
          );
          broadcast(
            updatedRoom,
            "peer_joined",
            { peerId, name: session.name },
            peerId
          );
          logInfo(
            `peer joined: roomId=${roomId} peerId=${peerId} name=${session.name}`
          );
          break;
        }

        case "chat": {
          if (!session.roomId || session.peerId === null) {
            return send(ws, "error", { reason: "not_in_room" });
          }
          const room = roomManager.getRoom(session.roomId);
          if (!room) return send(ws, "error", { reason: "room_not_found" });
          const text =
            typeof (msg.data as any)?.text === "string"
              ? (msg.data as any).text.slice(0, 500)
              : "";
          broadcast(room, "chat", {
            from: session.peerId,
            fromName: session.name,
            text,
          });
          logInfo(
            `chat: roomId=${room.id} peerId=${session.peerId} msg=${text.slice(
              0,
              50
            )}`
          );
          break;
        }

        case "load_tbw": {
          if (!session.roomId || session.peerId === null) {
            return send(ws, "error", { reason: "not_in_room" });
          }
          const room = roomManager.getRoom(session.roomId);
          if (!room) return send(ws, "error", { reason: "room_not_found" });
          if (!room.clients.get(session.peerId)?.isHost) {
            return send(ws, "error", { reason: "not_host" });
          }
          const lines = Array.isArray((msg.data as any)?.lines)
            ? (msg.data as any).lines.slice(0, 200000)
            : [];
          roomManager.updateTbw(room.id, lines);
          broadcast(room, "tbw", { lines });
          logInfo(`tbw broadcast: roomId=${room.id} lines=${lines.length}`);
          break;
        }

        case "player_snapshot": {
          if (!session.roomId || session.peerId === null) {
            return send(ws, "error", { reason: "not_in_room" });
          }
          const room = roomManager.getRoom(session.roomId);
          if (!room) return send(ws, "error", { reason: "room_not_found" });
          broadcast(
            room,
            "player_snapshot",
            {
              from: session.peerId,
              payload: (msg.data as any)?.payload ?? {},
            },
            session.peerId
          );
          break;
        }

        case "player_state": {
          // Relay player state (position, rotation, velocity) to all other clients
          if (!session.roomId || session.peerId === null) {
            return send(ws, "error", { reason: "not_in_room" });
          }
          const room = roomManager.getRoom(session.roomId);
          if (!room) return send(ws, "error", { reason: "room_not_found" });

          const stateData = (msg.data as any) || {};
          broadcast(
            room,
            "player_state",
            {
              peerId: session.peerId,
              position: stateData.position || { x: 0, y: 0, z: 0 },
              rotation: stateData.rotation || { x: 0, y: 0, z: 0 },
              velocity: stateData.velocity || { x: 0, y: 0, z: 0 },
            },
            session.peerId
          );
          break;
        }

        case "kick": {
          if (!session.roomId || session.peerId === null) {
            return send(ws, "error", { reason: "not_in_room" });
          }
          const room = roomManager.getRoom(session.roomId);
          if (!room) return send(ws, "error", { reason: "room_not_found" });
          if (!room.clients.get(session.peerId)?.isHost) {
            return send(ws, "error", { reason: "not_host" });
          }
          const targetPeerId = (msg.data as any)?.peerId;
          if (typeof targetPeerId !== "number") {
            return send(ws, "error", { reason: "invalid_target" });
          }
          const targetSession = Array.from(clientSessions.values()).find(
            (s) => s.roomId === room.id && s.peerId === targetPeerId
          );
          if (targetSession) {
            send(targetSession.ws, "kicked", { reason: "host_kick" });
            cleanupClient(targetSession.ws);
          }
          logInfo(`kick: roomId=${room.id} target=${targetPeerId}`);
          break;
        }

        case "ban": {
          if (!session.roomId || session.peerId === null) {
            return send(ws, "error", { reason: "not_in_room" });
          }
          const room = roomManager.getRoom(session.roomId);
          if (!room) return send(ws, "error", { reason: "room_not_found" });
          if (!room.clients.get(session.peerId)?.isHost) {
            return send(ws, "error", { reason: "not_host" });
          }
          const targetIp = (msg.data as any)?.ip;
          if (typeof targetIp !== "string") {
            return send(ws, "error", { reason: "invalid_target" });
          }
          roomManager.banPlayer(room.id, targetIp);
          logInfo(`ban: roomId=${room.id} ip=${targetIp}`);
          break;
        }

        case "ping": {
          send(ws, "pong", { ts: Date.now() });
          break;
        }

        case "rpc_call": {
          // Handle RPC calls - relay to target peer(s)
          if (!session.roomId || session.peerId === null) {
            return send(ws, "error", { reason: "not_in_room" });
          }
          const room = roomManager.getRoom(session.roomId);
          if (!room) return send(ws, "error", { reason: "room_not_found" });

          const targetPeer = (msg.data as any)?.targetPeer || 0;
          const method = (msg.data as any)?.method || "";
          const args = (msg.data as any)?.args || [];

          const rpcData = {
            fromPeer: session.peerId,
            method,
            args,
          };

          if (targetPeer === 0) {
            // Broadcast to all peers in room
            broadcast(room, "rpc_call", rpcData, session.peerId);
          } else {
            // Send to specific peer
            const targetSession = Array.from(clientSessions.values()).find(
              (s) => s.roomId === room.id && s.peerId === targetPeer
            );
            if (targetSession) {
              send(targetSession.ws, "rpc_call", rpcData);
            }
          }
          break;
        }

        default:
          send(ws, "error", { reason: "unknown_type" });
      }
    });

    ws.on("close", () => {
      cleanupClient(ws);
      logInfo(`ws: client disconnected from ${ip}`);
    });

    ws.on("error", (error: Error) => {
      logError(`ws error from ${ip}: ${error.message}`);
      cleanupClient(ws);
    });
  });

  wss.on("error", (error: Error) => {
    logError(`wss error: ${error.message}`);
  });

  return wss;
}

// Export broadcast function for use in other modules
export function notifyAllClientsRoomsChanged() {
  broadcastToAll("rooms_changed", {});
}
