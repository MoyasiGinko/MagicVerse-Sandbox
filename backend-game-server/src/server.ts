import express, { Request, Response } from "express";
import http from "http";
import config from "./config";
import { setupWebSocket } from "./networking/websocket";

const app = express();
const server = http.createServer(app);

app.get("/health", (_req: Request, res: Response) => {
  res.json({ ok: true, env: config.env });
});

setupWebSocket(server);

server.listen(config.port, () => {
  // eslint-disable-next-line no-console
  console.log(`Server is running on port ${config.port}`);
});
