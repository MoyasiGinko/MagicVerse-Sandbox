import { Router, Request, Response } from "express";
import { RoomRepository } from "../database/repositories/roomRepository";

const router = Router();
const roomRepo = new RoomRepository();

// Get all public active rooms (SERVER LIST ENDPOINT)
router.get("/", async (req: Request, res: Response) => {
  try {
    const { gamemode } = req.query;

    const rooms = roomRepo.getAllActiveRooms(gamemode as string | undefined);

    // Transform to include calculated fields
    const roomList = rooms.map((room) => ({
      id: room.id,
      host_username: room.host_username,
      gamemode: room.gamemode,
      map_name: room.map_name,
      current_players: room.current_players,
      max_players: room.max_players,
      created_at: room.created_at,
      is_full: room.current_players >= room.max_players,
    }));

    res.json({
      count: roomList.length,
      rooms: roomList,
    });
  } catch (error) {
    console.error("Error fetching rooms:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Get specific room details
router.get("/:id", async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const room = roomRepo.getRoomById(id);

    if (!room) {
      res.status(404).json({ error: "Room not found" });
      return;
    }

    res.json(room);
  } catch (error) {
    console.error("Error fetching room:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
