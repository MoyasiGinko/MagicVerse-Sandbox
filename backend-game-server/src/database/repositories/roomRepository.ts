import { getDatabase } from "../connection";

export interface Room {
  id: string;
  host_user_id: number;
  host_username: string;
  gamemode: string;
  map_name: string | null;
  max_players: number;
  current_players: number;
  is_public: boolean;
  is_active: boolean;
  created_at: string;
  started_at: string | null;
}

export interface CreateRoomInput {
  id: string;
  hostUserId: number;
  hostUsername: string;
  gamemode: string;
  mapName?: string;
  maxPlayers?: number;
  isPublic?: boolean;
}

export class RoomRepository {
  private db = getDatabase();

  createRoom(input: CreateRoomInput): Room {
    const stmt = this.db.prepare(`
            INSERT INTO rooms (id, host_user_id, host_username, gamemode, map_name, max_players, is_public)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        `);

    stmt.run(
      input.id,
      input.hostUserId,
      input.hostUsername,
      input.gamemode,
      input.mapName || null,
      input.maxPlayers || 8,
      input.isPublic !== false ? 1 : 0
    );

    return this.getRoomById(input.id)!;
  }

  getRoomById(id: string): Room | null {
    const stmt = this.db.prepare("SELECT * FROM rooms WHERE id = ?");
    return stmt.get(id) as Room | null;
  }

  getAllActiveRooms(gamemode?: string): Room[] {
    let query = "SELECT * FROM rooms WHERE is_active = 1 AND is_public = 1";
    const params: any[] = [];

    if (gamemode) {
      query += " AND gamemode = ?";
      params.push(gamemode);
    }

    query += " ORDER BY created_at DESC";

    const stmt = this.db.prepare(query);
    return stmt.all(...params) as Room[];
  }

  updatePlayerCount(roomId: string, count: number): void {
    const stmt = this.db.prepare(`
            UPDATE rooms
            SET current_players = ?
            WHERE id = ?
        `);
    stmt.run(count, roomId);
  }

  setRoomActive(roomId: string, isActive: boolean): void {
    const stmt = this.db.prepare(`
            UPDATE rooms
            SET is_active = ?
            WHERE id = ?
        `);
    stmt.run(isActive ? 1 : 0, roomId);
  }

  setRoomStarted(roomId: string): void {
    const stmt = this.db.prepare(`
            UPDATE rooms
            SET started_at = CURRENT_TIMESTAMP
            WHERE id = ?
        `);
    stmt.run(roomId);
  }

  deleteRoom(roomId: string): void {
    const stmt = this.db.prepare("DELETE FROM rooms WHERE id = ?");
    stmt.run(roomId);
  }

  cleanupInactiveRooms(olderThanMinutes: number = 60): number {
    const stmt = this.db.prepare(`
            DELETE FROM rooms
            WHERE is_active = 0
            AND datetime(created_at) < datetime('now', '-' || ? || ' minutes')
        `);
    const result = stmt.run(olderThanMinutes);
    return result.changes;
  }
}
