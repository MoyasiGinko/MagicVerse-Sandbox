import http from "http";
import https from "https";
import { URL } from "url";
import { config } from "../config";

interface RegistryPayload {
  id: string;
  name: string;
  region: string;
  api_url: string;
  ws_url: string;
  is_public: boolean;
  is_active: boolean;
  current_players: number;
  max_players: number;
  build_version: string;
}

const REGISTRY_BASE_URL = (
  process.env.DJANGO_REGISTRY_BASE_URL || "http://localhost:8000/api"
).replace(/\/+$/, "");

const SERVER_ID =
  process.env.GAME_SERVER_ID || `node-${config.port.toString()}`;
const SERVER_NAME =
  process.env.GAME_SERVER_NAME || `Node Server ${config.port}`;
const SERVER_REGION = process.env.GAME_SERVER_REGION || "global";
const SERVER_PUBLIC =
  (process.env.GAME_SERVER_PUBLIC || "true").toLowerCase() !== "false";
const SERVER_BUILD = process.env.GAME_SERVER_BUILD || "";

const PUBLIC_API_URL =
  process.env.PUBLIC_API_URL || `http://localhost:${config.port}/api`;
const PUBLIC_WS_URL =
  process.env.PUBLIC_WS_URL || `ws://localhost:${config.port}`;

function requestJson(url: string, payload: object): Promise<void> {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const data = JSON.stringify(payload);

    const options: http.RequestOptions = {
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port,
      path: target.pathname + target.search,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(data),
      },
      timeout: 5000,
    };

    const transport = target.protocol === "https:" ? https : http;
    const req = transport.request(options, (res) => {
      if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
        reject(
          new Error(
            `Registry request failed with status ${res.statusCode || 0}`,
          ),
        );
        return;
      }
      resolve();
    });

    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy(new Error("Registry request timed out"));
    });

    req.write(data);
    req.end();
  });
}

function buildPayload(
  currentPlayers: number,
  maxPlayers: number,
): RegistryPayload {
  return {
    id: SERVER_ID,
    name: SERVER_NAME,
    region: SERVER_REGION,
    api_url: PUBLIC_API_URL,
    ws_url: PUBLIC_WS_URL,
    is_public: SERVER_PUBLIC,
    is_active: true,
    current_players: currentPlayers,
    max_players: maxPlayers,
    build_version: SERVER_BUILD,
  };
}

export async function registerGameServer(
  currentPlayers: number,
  maxPlayers: number,
): Promise<void> {
  const payload = buildPayload(currentPlayers, maxPlayers);
  await requestJson(`${REGISTRY_BASE_URL}/game-servers`, payload);
}

export async function heartbeatGameServer(
  currentPlayers: number,
  maxPlayers: number,
): Promise<void> {
  await requestJson(
    `${REGISTRY_BASE_URL}/game-servers/${encodeURIComponent(SERVER_ID)}/heartbeat`,
    {
      current_players: currentPlayers,
      max_players: maxPlayers,
      is_active: true,
    },
  );
}
