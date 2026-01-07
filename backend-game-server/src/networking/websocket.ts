import { WebSocketServer, WebSocket, RawData } from "ws";
import http from "http";
import { logInfo, logError } from "../utils/logger";
import { RoomManager, GameRoom } from "../game/roomManager";

type Message = { type: string; data?: unknown };

type ClientSession = {
  ws: WebSocket;
  peerId: number | null;
  roomId: string | null;
  name: string;
  version: string;
  ip: string;
};

const roomManager = new RoomManager();
const clientSessions = new Map<WebSocket, ClientSession>();

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
  const { roomId, peerId } = session;
  clientSessions.delete(ws);
  if (roomId && peerId !== null) {
    const room = roomManager.getRoom(roomId);
    if (room) {
      roomManager.leaveRoom(roomId, peerId);
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
    };
    clientSessions.set(ws, session);
    logInfo(`ws: client connected from ${ip}`);

    ws.on("message", (raw: RawData) => {
      const msg = validateJson(raw.toString());
      if (!msg) {
        return send(ws, "error", { reason: "bad_json" });
      }

      switch (msg.type) {
        case "create_room": {
          if (
            !msg.data ||
            typeof (msg.data as any).version !== "string" ||
            typeof (msg.data as any).name !== "string"
          ) {
            return send(ws, "error", { reason: "invalid_create_room" });
          }
          const room = roomManager.createRoom(
            (msg.data as any).version,
            (msg.data as any).name,
            ip
          );
          session.peerId = 1;
          session.name = (msg.data as any).name;
          session.version = (msg.data as any).version;
          session.roomId = room.id;
          send(ws, "room_created", { roomId: room.id, peerId: 1 });
          logInfo(`room created: roomId=${room.id} host=${session.name}`);
          break;
        }

        case "join_room": {
          if (
            !msg.data ||
            typeof (msg.data as any).roomId !== "string" ||
            typeof (msg.data as any).version !== "string" ||
            typeof (msg.data as any).name !== "string"
          ) {
            return send(ws, "error", { reason: "invalid_join_room" });
          }
          const result = roomManager.joinRoom(
            (msg.data as any).roomId,
            (msg.data as any).version,
            (msg.data as any).name,
            ip
          );
          if ("error" in result) {
            return send(ws, "error", { reason: result.error });
          }
          const { room, peerId } = result;
          session.peerId = peerId;
          session.name = (msg.data as any).name;
          session.version = (msg.data as any).version;
          session.roomId = room.id;
          const members = roomManager.getRoomMembers(room.id);
          send(ws, "room_joined", {
            roomId: room.id,
            peerId,
            members: members.map((c) => ({
              peerId: c.peerId,
              name: c.name,
              isHost: c.isHost,
            })),
            currentTbw: room.currentTbw,
          });
          broadcast(
            room,
            "peer_joined",
            { peerId, name: session.name },
            peerId
          );
          logInfo(
            `peer joined: roomId=${room.id} peerId=${peerId} name=${session.name}`
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
