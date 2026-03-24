import { config as loadEnv } from "dotenv";

loadEnv();

const PORT = Number(process.env.PORT || 30820);
const ENVIRONMENT = process.env.NODE_ENV || "development";
const DJANGO_REGISTRY_BASE_URL =
  process.env.DJANGO_REGISTRY_BASE_URL || "http://localhost:8000/api";

export const config = {
  port: PORT,
  env: ENVIRONMENT,
  djangoRegistryBaseUrl: DJANGO_REGISTRY_BASE_URL,
};

export default config;
