import { Hono } from "hono";
import { reportUsage } from "../db.js";
import { getCachedSession } from "../redis.js";
import { findSession } from "../db.js";

export const usage = new Hono();

/**
 * POST /v1/usage/report
 * Header: Authorization: Bearer <sessionToken>
 * Body: { apiCalls?, transportMsgs?, peakCcu? }
 *
 * Fire-and-forget from SDK. Always returns 202.
 */
usage.post("/report", async (c) => {
  const token = extractToken(c.req.header("Authorization"));
  if (!token) {
    return c.json({ error: "missing_token" }, 401);
  }

  // Resolve session: Redis first, Postgres fallback
  let gameId: string | null = null;

  const cached = await getCachedSession(token);
  if (cached) {
    gameId = cached.gameId;
  } else {
    const session = await findSession(token);
    if (session) {
      gameId = session.game_id;
    }
  }

  if (!gameId) {
    return c.json({ error: "session_not_found" }, 401);
  }

  const body = await c.req.json<{
    apiCalls?: number;
    transportMsgs?: number;
    peakCcu?: number;
  }>();

  // Upsert into hourly bucket (fire and forget)
  reportUsage(
    gameId,
    body.apiCalls ?? 0,
    body.transportMsgs ?? 0,
    body.peakCcu ?? 0
  ).catch(() => {});

  return c.json({ ok: true }, 202);
});

function extractToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = header.match(/^Bearer\s+(\S+)$/i);
  return match?.[1] ?? null;
}
