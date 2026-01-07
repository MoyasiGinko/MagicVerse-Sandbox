import { getDatabase } from "../connection";

export interface User {
  id: number;
  username: string;
  email: string;
  password_hash: string;
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
            INSERT INTO users (username, email, password_hash)
            VALUES (?, ?, ?)
        `);

    const result = stmt.run(input.username, input.email, input.password_hash);

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
    return stmt.get(username) as User | null;
  }

  getUserByEmail(email: string): User | null {
    const stmt = this.db.prepare("SELECT * FROM users WHERE email = ?");
    return stmt.get(email) as User | null;
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
    return this.getUserByUsername(username) !== null;
  }

  isEmailTaken(email: string): boolean {
    return this.getUserByEmail(email) !== null;
  }
}
