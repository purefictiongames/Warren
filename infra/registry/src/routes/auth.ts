import { Hono } from "hono";
import { createHash, randomBytes } from "node:crypto";
import { env } from "../env.js";
import {
  findApiKeyByHash,
  findGame,
  findLicense,
  createSession,
  findSession,
  refreshSession,
  revokeSession,
  touchApiKey,
  scopesForTier,
} from "../db.js";
import {
  cacheSession,
  getCachedSession,
  removeCachedSession,
  extendSessionTtl,
} from "../redis.js";

export const auth = new Hono();

/**
 * POST /v1/auth/validate
 * Body: { apiKey, universeId, placeId?, jobId? }
 * Returns: { sessionToken, tier, scopes, ttl, expiresAt }
 */
auth.post("/validate", async (c) => {
  const body = await c.req.json<{
    apiKey: string;
    universeId: number;
    placeId?: number;
    jobId?: string;
  }>();

  if (!body.apiKey || !body.universeId) {
    return c.json({ error: "apiKey and universeId are required" }, 400);
  }

  // Hash the incoming key
  const keyHash = createHash("sha256").update(body.apiKey).digest("hex");

  // Look up key
  const apiKey = await findApiKeyByHash(keyHash);
  if (!apiKey) {
    return c.json({ error: "invalid_api_key" }, 401);
  }
  if (!apiKey.is_active) {
    return c.json({ error: "api_key_revoked" }, 401);
  }

  // Look up game
  const game = await findGame(apiKey.game_id);
  if (!game) {
    return c.json({ error: "game_not_found" }, 404);
  }

  // Verify universe matches
  if (game.universe_id !== String(body.universeId)) {
    return c.json({ error: "universe_mismatch" }, 403);
  }

  // Check license
  const license = await findLicense(game.id);
  if (!license) {
    return c.json({ error: "no_license" }, 403);
  }
  if (license.status === "suspended") {
    return c.json({ error: "license_suspended" }, 403);
  }
  if (license.status === "expired") {
    return c.json({ error: "license_expired" }, 403);
  }
  if (
    license.expires_at &&
    new Date(license.expires_at) < new Date()
  ) {
    return c.json({ error: "license_expired" }, 403);
  }

  // Generate session
  const token = randomBytes(env.sessionTokenBytes).toString("hex");
  const expiresAt = new Date(Date.now() + env.sessionTtl * 1000);
  const scopes = scopesForTier(license.tier, license.is_internal);

  const session = await createSession({
    apiKeyId: apiKey.id,
    gameId: game.id,
    universeId: game.universe_id,
    placeId: body.placeId ? String(body.placeId) : null,
    jobId: body.jobId ?? null,
    tier: license.tier,
    scopes,
    token,
    expiresAt,
  });

  // Cache in Redis
  await cacheSession(token, {
    id: session.id,
    apiKeyId: apiKey.id,
    gameId: game.id,
    universeId: game.universe_id,
    tier: license.tier,
    scopes,
    expiresAt: expiresAt.toISOString(),
  });

  // Touch last_used_at (fire and forget)
  touchApiKey(apiKey.id).catch(() => {});

  return c.json({
    sessionToken: token,
    tier: license.tier,
    scopes,
    ttl: env.sessionTtl,
    expiresAt: expiresAt.toISOString(),
  });
});

/**
 * POST /v1/auth/refresh
 * Header: Authorization: Bearer <sessionToken>
 * Returns: { sessionToken, ttl, expiresAt }
 */
auth.post("/refresh", async (c) => {
  const token = extractToken(c.req.header("Authorization"));
  if (!token) {
    return c.json({ error: "missing_token" }, 401);
  }

  const newExpiry = new Date(Date.now() + env.sessionTtl * 1000);
  const updated = await refreshSession(token, newExpiry);
  if (!updated) {
    return c.json({ error: "session_not_found_or_expired" }, 401);
  }

  // Extend Redis TTL
  await extendSessionTtl(token);

  return c.json({
    sessionToken: token,
    ttl: env.sessionTtl,
    expiresAt: newExpiry.toISOString(),
  });
});

/**
 * POST /v1/auth/revoke
 * Header: Authorization: Bearer <sessionToken>
 */
auth.post("/revoke", async (c) => {
  const token = extractToken(c.req.header("Authorization"));
  if (!token) {
    return c.json({ error: "missing_token" }, 401);
  }

  await revokeSession(token);
  await removeCachedSession(token);

  return c.json({ ok: true });
});

function extractToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = header.match(/^Bearer\s+(\S+)$/i);
  return match?.[1] ?? null;
}
