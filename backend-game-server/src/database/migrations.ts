import { getDatabase } from "./connection";

export function runMigrations(): void {
  const db = getDatabase();

  console.log("Running database migrations...");

  // Users table
  db.exec(`
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_login DATETIME,
            is_active BOOLEAN DEFAULT 1
        )
    `);

  // Player stats table
  db.exec(`
        CREATE TABLE IF NOT EXISTS player_stats (
            user_id INTEGER PRIMARY KEY,
            kills INTEGER DEFAULT 0,
            deaths INTEGER DEFAULT 0,
            wins INTEGER DEFAULT 0,
            losses INTEGER DEFAULT 0,
            playtime_seconds INTEGER DEFAULT 0,
            matches_played INTEGER DEFAULT 0,
            last_match DATETIME,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    `);

  // Rooms table
  db.exec(`
        CREATE TABLE IF NOT EXISTS rooms (
            id TEXT PRIMARY KEY,
            host_user_id INTEGER NOT NULL,
            host_username TEXT NOT NULL,
            gamemode TEXT NOT NULL,
            map_name TEXT,
            max_players INTEGER DEFAULT 8,
            current_players INTEGER DEFAULT 1,
            is_public BOOLEAN DEFAULT 1,
            is_active BOOLEAN DEFAULT 1,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            started_at DATETIME,
            FOREIGN KEY (host_user_id) REFERENCES users(id)
        )
    `);

  // Match history table
  db.exec(`
        CREATE TABLE IF NOT EXISTS match_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            room_id TEXT NOT NULL,
            gamemode TEXT NOT NULL,
            winner_user_id INTEGER,
            started_at DATETIME,
            ended_at DATETIME,
            duration_seconds INTEGER
        )
    `);

  // Create indexes for better query performance
  db.exec(`
        CREATE INDEX IF NOT EXISTS idx_rooms_gamemode ON rooms(gamemode);
        CREATE INDEX IF NOT EXISTS idx_rooms_is_active ON rooms(is_active);
        CREATE INDEX IF NOT EXISTS idx_rooms_is_public ON rooms(is_public);
        CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
        CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
    `);

  console.log("Database migrations completed successfully");
}
