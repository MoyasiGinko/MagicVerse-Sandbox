import express, { Request, Response } from "express";
import { UserRepository } from "../database/repositories/userRepository";

const router = express.Router();
const userRepo = new UserRepository();

/**
 * GET /api/users
 * Get all active users
 */
router.get("/", (_req: Request, res: Response) => {
  try {
    const users = userRepo.getAllUsers();

    // Return user info without password hashes
    const safeUsers = users.map((user) => ({
      id: user.id,
      username: user.username,
      created_at: user.created_at,
      last_login: user.last_login,
      is_active: user.is_active,
    }));

    res.json({
      success: true,
      total: safeUsers.length,
      users: safeUsers,
    });
  } catch (error) {
    console.error("Error fetching users:", error);
    res.status(500).json({
      error: "Failed to fetch users",
    });
  }
});

/**
 * GET /api/users/online
 * Get all online users (active in last N minutes)
 */
router.get("/online", (req: Request, res: Response) => {
  try {
    // Allow customizing the active window via query param (default 5 minutes)
    const minutesSinceActive = parseInt(req.query.minutes as string) || 5;

    const onlineUsers = userRepo.getOnlineUsers(minutesSinceActive);

    // Return user info without password hashes
    const safeUsers = onlineUsers.map((user) => ({
      id: user.id,
      username: user.username,
      created_at: user.created_at,
      last_login: user.last_login,
      is_active: user.is_active,
    }));

    res.json({
      success: true,
      total: safeUsers.length,
      minutesSinceActive: minutesSinceActive,
      users: safeUsers,
    });
  } catch (error) {
    console.error("Error fetching online users:", error);
    res.status(500).json({
      error: "Failed to fetch online users",
    });
  }
});

export default router;
