import { config as loadEnv } from "dotenv";

loadEnv();

const PORT = Number(process.env.PORT || 30820);
const ENVIRONMENT = process.env.NODE_ENV || "development";

export const config = {
  port: PORT,
  env: ENVIRONMENT,
};

export default config;
