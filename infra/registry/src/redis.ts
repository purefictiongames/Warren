import Redis from "ioredis";
import { env } from "./env.js";

export const redis = new Redis(env.redisUrl);

export interface CachedSession {
  id: string;
  apiKeyId: string;
  gameId: string;
  universeId: string;
  tier: string;
  scopes: string[];
  expiresAt: string;
}

const SESSION_PREFIX = "warren:session:";

/** Cache a session in Redis */
export async function cacheSession(
  token: string,
  session: CachedSession
): Promise<void> {
  await redis.set(
    SESSION_PREFIX + token,
    JSON.stringify(session),
    "EX",
    env.sessionTtl
  );
}

/** Get cached session from Redis */
export async function getCachedSession(
  token: string
): Promise<CachedSession | null> {
  const raw = await redis.get(SESSION_PREFIX + token);
  if (!raw) return null;
  return JSON.parse(raw) as CachedSession;
}

/** Remove cached session */
export async function removeCachedSession(token: string): Promise<void> {
  await redis.del(SESSION_PREFIX + token);
}

/** Extend cached session TTL */
export async function extendSessionTtl(token: string): Promise<void> {
  await redis.expire(SESSION_PREFIX + token, env.sessionTtl);
}
