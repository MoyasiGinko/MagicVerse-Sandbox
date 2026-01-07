import express, { Request, Response } from "express";
import http from "http";
import config from "./config";
import { setupWebSocket } from "./networking/websocket";
import { runMigrations } from "./database/migrations";
import { RoomRepository } from "./database/repositories/roomRepository";
import authRoutes from "./api/authRoutes";
import roomRoutes from "./api/roomRoutes";
import statsRoutes from "./api/statsRoutes";

const app = express();
const server = http.createServer(app);
const roomRepo = new RoomRepository();

// Middleware
app.use(express.json());

// Run database migrations
console.log("Initializing database...");
runMigrations();

// API Routes
app.use("/api/auth", authRoutes);
app.use("/api/rooms", roomRoutes);
app.use("/api", statsRoutes);

// Health check
app.get("/health", (_req: Request, res: Response) => {
  res.json({ ok: true, env: config.env });
});

// Setup WebSocket
setupWebSocket(server);

// Periodic cleanup of inactive rooms (every 5 minutes)
setInterval(() => {
  const cleaned = roomRepo.cleanupInactiveRooms(60);
  if (cleaned > 0) {
    console.log(`Cleaned up ${cleaned} inactive rooms`);
  }
}, 5 * 60 * 1000);

server.listen(config.port, () => {
  // eslint-disable-next-line no-console
  console.log(`Server is running on port ${config.port}`);
  console.log(`API endpoints available:`);
  console.log(`  - POST /api/auth/register`);
  console.log(`  - POST /api/auth/login`);
  console.log(`  - GET  /api/auth/verify`);
  console.log(`  - GET  /api/rooms (Server List)`);
  console.log(`  - GET  /api/rooms/:id`);
  console.log(`  - GET  /api/users/:id/stats`);
  console.log(`  - GET  /api/leaderboard`);
});
