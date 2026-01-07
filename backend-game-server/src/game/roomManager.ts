import { nanoid } from "nanoid";

export interface RoomClient {
  peerId: number;
  name: string;
  version: string;
  isHost: boolean;
}

export interface GameRoom {
  id: string;
  hostPeerId: number;
  version: string;
  clients: Map<number, RoomClient>;
  nextPeerId: number;
  currentTbw: string[];
  bannedIps: Set<string>;
}

export class RoomManager {
  private rooms: Map<string, GameRoom>;

  constructor() {
    this.rooms = new Map();
  }

  createRoom(version: string, hostName: string, hostIp: string): GameRoom {
    const roomId = nanoid(6);
    const room: GameRoom = {
      id: roomId,
      hostPeerId: 1,
      version,
      clients: new Map(),
      nextPeerId: 2,
      currentTbw: [],
      bannedIps: new Set(),
    };
    room.clients.set(1, {
      peerId: 1,
      name: hostName,
      version,
      isHost: true,
    });
    this.rooms.set(roomId, room);
    return room;
  }

  getRoom(roomId: string): GameRoom | undefined {
    return this.rooms.get(roomId);
  }

  deleteRoom(roomId: string): void {
    this.rooms.delete(roomId);
  }

  joinRoom(
    roomId: string,
    version: string,
    playerName: string,
    clientIp: string
  ): { room: GameRoom; peerId: number } | { error: string } {
    const room = this.rooms.get(roomId);
    if (!room) return { error: "room_not_found" };
    if (room.version !== version) return { error: "version_mismatch" };
    if (room.bannedIps.has(clientIp)) return { error: "banned" };
    for (const client of room.clients.values()) {
      if (client.name.toLowerCase() === playerName.toLowerCase()) {
        return { error: "name_taken" };
      }
    }
    const peerId = room.nextPeerId++;
    room.clients.set(peerId, {
      peerId,
      name: playerName,
      version,
      isHost: false,
    });
    return { room, peerId };
  }

  leaveRoom(roomId: string, peerId: number): void {
    const room = this.rooms.get(roomId);
    if (!room) return;
    room.clients.delete(peerId);
    if (room.clients.size === 0) {
      this.deleteRoom(roomId);
    }
  }

  banPlayer(roomId: string, playerIp: string): void {
    const room = this.rooms.get(roomId);
    if (room) {
      room.bannedIps.add(playerIp);
    }
  }

  updateTbw(roomId: string, lines: string[]): void {
    const room = this.rooms.get(roomId);
    if (room) {
      room.currentTbw = lines;
    }
  }

  getRoomMembers(roomId: string): RoomClient[] {
    const room = this.rooms.get(roomId);
    if (!room) return [];
    return Array.from(room.clients.values());
  }
}
