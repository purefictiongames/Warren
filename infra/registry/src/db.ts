import pg from "pg";
import { env } from "./env.js";

export const pool = new pg.Pool({ connectionString: env.databaseUrl });

export interface ApiKeyRow {
  id: string;
  game_id: string;
  key_hash: string;
  key_prefix: string;
  is_active: boolean;
}

export interface GameRow {
  id: string;
  studio_id: string;
  name: string;
  universe_id: string; // bigint comes as string from pg
}

export interface LicenseRow {
  id: string;
  game_id: string;
  tier: "mach2" | "mach3";
  status: "active" | "suspended" | "expired" | "trial";
  is_internal: boolean;
  expires_at: string | null;
}

export interface SessionRow {
  id: string;
  api_key_id: string;
  game_id: string;
  universe_id: string;
  place_id: string | null;
  job_id: string | null;
  tier: string;
  scopes: string[];
  token: string;
  expires_at: string;
}

const TIER_SCOPES: Record<string, string[]> = {
  mach2: ["layout.*", "style.*", "dom.*", "factory.*"],
  mach3: [
    "layout.*",
    "style.*",
    "dom.*",
    "factory.*",
    "transport.*",
    "state.*",
    "opencloud.*",
  ],
};

export function scopesForTier(tier: string, isInternal: boolean): string[] {
  if (isInternal) return ["*"];
  return TIER_SCOPES[tier] ?? [];
}

/** Look up an API key by its SHA-256 hash */
export async function findApiKeyByHash(
  hash: string
): Promise<ApiKeyRow | null> {
  const { rows } = await pool.query<ApiKeyRow>(
    `SELECT id, game_id, key_hash, key_prefix, is_active
     FROM warren_api_keys WHERE key_hash = $1`,
    [hash]
  );
  return rows[0] ?? null;
}

/** Get game by ID */
export async function findGame(gameId: string): Promise<GameRow | null> {
  const { rows } = await pool.query<GameRow>(
    `SELECT id, studio_id, name, universe_id FROM warren_games WHERE id = $1`,
    [gameId]
  );
  return rows[0] ?? null;
}

/** Get license for a game */
export async function findLicense(
  gameId: string
): Promise<LicenseRow | null> {
  const { rows } = await pool.query<LicenseRow>(
    `SELECT id, game_id, tier, status, is_internal, expires_at
     FROM warren_licenses WHERE game_id = $1`,
    [gameId]
  );
  return rows[0] ?? null;
}

/** Insert a new session */
export async function createSession(session: {
  apiKeyId: string;
  gameId: string;
  universeId: string;
  placeId: string | null;
  jobId: string | null;
  tier: string;
  scopes: string[];
  token: string;
  expiresAt: Date;
}): Promise<SessionRow> {
  const { rows } = await pool.query<SessionRow>(
    `INSERT INTO warren_sessions
       (api_key_id, game_id, universe_id, place_id, job_id, tier, scopes, token, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING *`,
    [
      session.apiKeyId,
      session.gameId,
      session.universeId,
      session.placeId,
      session.jobId,
      session.tier,
      session.scopes,
      session.token,
      session.expiresAt,
    ]
  );
  return rows[0];
}

/** Find session by token */
export async function findSession(
  token: string
): Promise<SessionRow | null> {
  const { rows } = await pool.query<SessionRow>(
    `SELECT * FROM warren_sessions WHERE token = $1 AND expires_at > now()`,
    [token]
  );
  return rows[0] ?? null;
}

/** Extend session expiry */
export async function refreshSession(
  token: string,
  newExpiry: Date
): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE warren_sessions SET expires_at = $1 WHERE token = $2 AND expires_at > now()`,
    [newExpiry, token]
  );
  return (rowCount ?? 0) > 0;
}

/** Delete session */
export async function revokeSession(token: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    `DELETE FROM warren_sessions WHERE token = $1`,
    [token]
  );
  return (rowCount ?? 0) > 0;
}

/** Update api_keys.last_used_at */
export async function touchApiKey(keyId: string): Promise<void> {
  await pool.query(
    `UPDATE warren_api_keys SET last_used_at = now() WHERE id = $1`,
    [keyId]
  );
}

/** Upsert usage telemetry (hourly bucket) */
export async function reportUsage(
  gameId: string,
  apiCalls: number,
  transportMsgs: number,
  peakCcu: number
): Promise<void> {
  await pool.query(
    `INSERT INTO warren_usage_telemetry (game_id, period_start, api_calls, transport_msgs, peak_ccu, unique_sessions)
     VALUES ($1, date_trunc('hour', now()), $2, $3, $4, 0)
     ON CONFLICT (game_id, period_start)
     DO UPDATE SET
       api_calls = warren_usage_telemetry.api_calls + EXCLUDED.api_calls,
       transport_msgs = warren_usage_telemetry.transport_msgs + EXCLUDED.transport_msgs,
       peak_ccu = GREATEST(warren_usage_telemetry.peak_ccu, EXCLUDED.peak_ccu)`,
    [gameId, apiCalls, transportMsgs, peakCcu]
  );
}
