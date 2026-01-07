import { getDatabase } from "../connection";

export interface User {
  id: number;
  username: string;
  email: string;
  password_hash: string;
  display_name: string | null;
  created_at: string;
  last_login: string | null;
  is_active: boolean;
}

export interface CreateUserInput {
  username: string;
  email: string;
  password_hash: string;
}

export class UserRepository {
  private db = getDatabase();

  createUser(input: CreateUserInput): User {
    const stmt = this.db.prepare(`
            INSERT INTO users (username, email, password_hash, display_name)
            VALUES (?, ?, ?, ?)
        `);

    const result = stmt.run(
      input.username,
      input.email,
      input.password_hash,
      input.username
    );

    // Create initial stats for the user
    const statsStmt = this.db.prepare(`
            INSERT INTO player_stats (user_id)
            VALUES (?)
        `);
    statsStmt.run(result.lastInsertRowid);

    return this.getUserById(result.lastInsertRowid as number)!;
  }

  getUserById(id: number): User | null {
    const stmt = this.db.prepare("SELECT * FROM users WHERE id = ?");
    return stmt.get(id) as User | null;
  }

  getUserByUsername(username: string): User | null {
    const stmt = this.db.prepare("SELECT * FROM users WHERE username = ?");
    const result = stmt.get(username) as User | null;
    console.log(`[DB] getUserByUsername('${username}'):`, result);
    return result;
  }

  getUserByEmail(email: string): User | null {
    const stmt = this.db.prepare("SELECT * FROM users WHERE email = ?");
    const result = stmt.get(email) as User | null;
    console.log(`[DB] getUserByEmail('${email}'):`, result);
    return result;
  }

  updateLastLogin(userId: number): void {
    const stmt = this.db.prepare(`
            UPDATE users
            SET last_login = CURRENT_TIMESTAMP
            WHERE id = ?
        `);
    stmt.run(userId);
  }

  isUsernameTaken(username: string): boolean {
    const user = this.getUserByUsername(username);
    const taken = user != null;
    console.log(
      `[CHECK] isUsernameTaken('${username}'): ${taken} (user:`,
      user,
      `)`
    );
    return taken;
  }

  isEmailTaken(email: string): boolean {
    const user = this.getUserByEmail(email);
    const taken = user != null;
    console.log(`[CHECK] isEmailTaken('${email}'): ${taken} (user:`, user, `)`);
    return taken;
  }

  getAllUsers(): User[] {
    const stmt = this.db.prepare(
      "SELECT * FROM users WHERE is_active = 1 ORDER BY username ASC"
    );
    return stmt.all() as User[];
  }

  getOnlineUsers(minutesSinceActive: number = 5): User[] {
    const stmt = this.db.prepare(`
      SELECT * FROM users
      WHERE is_active = 1
      AND last_login IS NOT NULL
      AND datetime(last_login) > datetime('now', '-' || ? || ' minutes')
      ORDER BY username ASC
    `);
    return stmt.all(minutesSinceActive) as User[];
  }

  updateDisplayName(userId: number, displayName: string): User | null {
    const stmt = this.db.prepare(`
      UPDATE users
      SET display_name = ?
      WHERE id = ?
    `);
    stmt.run(displayName, userId);
    return this.getUserById(userId);
  }
}
