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
  inactive_since: string | null;
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
            INSERT INTO rooms (id, host_user_id, host_username, gamemode, map_name, max_players, current_players, is_public)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?)
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
            SET is_active = ?,
                inactive_since = CASE WHEN ? = 0 THEN CURRENT_TIMESTAMP ELSE NULL END
            WHERE id = ?
        `);
    stmt.run(isActive ? 1 : 0, isActive ? 1 : 0, roomId);
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

  cleanupInactiveRooms(olderThanMinutes: number = 1): number {
    const stmt = this.db.prepare(`
            DELETE FROM rooms
            WHERE is_active = 0
            AND inactive_since IS NOT NULL
            AND datetime(inactive_since) < datetime('now', '-' || ? || ' minutes')
        `);
    const result = stmt.run(olderThanMinutes);
    if (result.changes > 0) {
      console.log(
        `[RoomRepo] 🧹 Cleaned up ${result.changes} inactive room(s) older than ${olderThanMinutes} minute(s)`
      );
    }
    return result.changes;
  }

  // Deactivate room if no players remain
  deactivateIfEmpty(roomId: string): boolean {
    const room = this.getRoomById(roomId);
    if (!room) return false;

    if (room.current_players <= 0) {
      console.log(`[RoomRepo] 📭 Room ${roomId} is empty; marking inactive`);
      this.setRoomActive(roomId, false);
      return true;
    }
    return false;
  }

  // Add player to room session (WebSocket join)
  addPlayerSession(userId: number, roomId: string): boolean {
    try {
      // Check if player is already in this exact room
      const checkStmt = this.db.prepare(
        "SELECT COUNT(*) as count FROM player_sessions WHERE user_id = ? AND room_id = ?"
      );
      const existing = checkStmt.get(userId, roomId) as { count: number };

      if (existing.count > 0) {
        console.log(
          `[RoomRepo] ⚠️  Player ${userId} already in room ${roomId}, skipping duplicate`
        );
        return false; // Already in this room, don't increment again
      }

      // Check if player is in a different room (for logging)
      const checkOtherStmt = this.db.prepare(
        "SELECT room_id FROM player_sessions WHERE user_id = ?"
      );
      const otherRoom = checkOtherStmt.get(userId) as
        | { room_id: string }
        | undefined;

      if (otherRoom) {
        console.log(
          `[RoomRepo] 🔄 Player ${userId} leaving room ${otherRoom.room_id}...`
        );
        // Remove player from other room first (enforces single-room)
        const stmt_remove = this.db.prepare(
          "DELETE FROM player_sessions WHERE user_id = ?"
        );
        stmt_remove.run(userId);

        // Decrement the old room's count
        const oldRoom = this.getRoomById(otherRoom.room_id);
        if (oldRoom) {
          const oldCount = Math.max(0, oldRoom.current_players - 1);
          this.updatePlayerCount(otherRoom.room_id, oldCount);
          console.log(
            `[RoomRepo] 👥 Room ${otherRoom.room_id} player count: ${oldRoom.current_players} -> ${oldCount}`
          );
        }
      }

      // Add to new room
      const stmt_insert = this.db.prepare(`
        INSERT INTO player_sessions (user_id, room_id)
        VALUES (?, ?)
      `);
      stmt_insert.run(userId, roomId);
      console.log(`[RoomRepo] ✅ Player ${userId} added to room ${roomId}`);

      // Update room player count based on actual player_sessions count
      // (not the stale count from the room record)
      const countStmt = this.db.prepare(
        "SELECT COUNT(*) as count FROM player_sessions WHERE room_id = ?"
      );
      const countResult = countStmt.get(roomId) as { count: number };
      const actualCount = countResult.count;
      this.updatePlayerCount(roomId, actualCount);
      console.log(
        `[RoomRepo] 👥 Room ${roomId} updated to actual player count: ${actualCount}`
      );
      return true;
    } catch (error) {
      console.error(`[RoomRepo] ❌ Error adding player session:`, error);
      return false;
    }
  }

  // Remove player from room session (WebSocket disconnect)
  removePlayerSession(userId: number, roomId: string): boolean {
    try {
      const stmt = this.db.prepare(
        "DELETE FROM player_sessions WHERE user_id = ? AND room_id = ?"
      );
      stmt.run(userId, roomId);
      console.log(`[RoomRepo] ❌ Player ${userId} removed from room ${roomId}`);

      // Decrement room player count
      const room = this.getRoomById(roomId);
      if (room) {
        const newCount = Math.max(0, room.current_players - 1);
        this.updatePlayerCount(roomId, newCount);
        console.log(
          `[RoomRepo] 👥 Room ${roomId} player count: ${room.current_players} -> ${newCount}`
        );

        // Deactivate if empty
        this.deactivateIfEmpty(roomId);
      }
      return true;
    } catch (error) {
      console.error(`[RoomRepo] ❌ Error removing player session:`, error);
      return false;
    }
  }

  // Get player's current room (if in one)
  getPlayerCurrentRoom(userId: number): Room | null {
    try {
      const stmt = this.db.prepare(`
        SELECT r.* FROM rooms r
        INNER JOIN player_sessions ps ON r.id = ps.room_id
        WHERE ps.user_id = ? AND r.is_active = 1
        LIMIT 1
      `);
      const result = stmt.get(userId) as Room | null;
      if (result) {
        console.log(
          `[RoomRepo] 🎯 Player ${userId} has active room: ${result.id}`
        );
      } else {
        console.log(`[RoomRepo] ✅ Player ${userId} has no active room`);
      }
      return result;
    } catch (error) {
      console.error(`[RoomRepo] ❌ Error getting player current room:`, error);
      return null;
    }
  }
}
