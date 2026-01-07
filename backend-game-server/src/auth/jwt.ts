import jwt from "jsonwebtoken";

const JWT_SECRET: string =
  process.env.JWT_SECRET || "your-super-secret-key-change-in-production";
const JWT_EXPIRATION = "7d";

export interface TokenPayload {
  userId: number;
  username: string;
}

export function generateToken(payload: TokenPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRATION });
}

export function verifyToken(token: string): TokenPayload | null {
  try {
    const decoded = jwt.verify(token, JWT_SECRET) as TokenPayload;
    return decoded;
  } catch (error) {
    console.error("Token verification failed:", error);
    return null;
  }
}
