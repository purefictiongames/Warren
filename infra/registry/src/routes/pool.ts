import { Hono } from "hono";
import { pool } from "../db.js";

export const poolRoutes = new Hono();

interface MapPoolRow {
  id: string;
  biome_name: string;
  seed: string; // bigint comes as string from pg
  map_data: unknown;
  created_at: string;
}

/**
 * POST /v1/pool/store
 * Body: { biome_name, seed, map_data }
 * Stores a pre-built map in the pool.
 */
poolRoutes.post("/store", async (c) => {
  const body = await c.req.json<{
    biome_name?: string;
    seed?: number;
    map_data?: unknown;
  }>();

  if (!body.biome_name || body.seed == null || !body.map_data) {
    return c.json({ error: "biome_name, seed, and map_data are required" }, 400);
  }

  await pool.query(
    `INSERT INTO warren_map_pool (biome_name, seed, map_data)
     VALUES ($1, $2, $3)
     ON CONFLICT (seed, biome_name) DO NOTHING`,
    [body.biome_name, body.seed, JSON.stringify(body.map_data)]
  );

  return c.json({ status: "ok" });
});

/**
 * GET /v1/pool/load/:biome?limit=3
 * Atomic pop: returns AND deletes rows from the pool.
 */
poolRoutes.get("/load/:biome", async (c) => {
  const biome = c.req.param("biome");
  const limit = parseInt(c.req.query("limit") || "3", 10);

  const { rows } = await pool.query<MapPoolRow>(
    `DELETE FROM warren_map_pool
     WHERE id IN (
       SELECT id FROM warren_map_pool
       WHERE biome_name = $1
       ORDER BY created_at
       LIMIT $2
     )
     RETURNING *`,
    [biome, limit]
  );

  return c.json({
    maps: rows.map((r) => ({
      seed: parseInt(r.seed, 10),
      map_data: r.map_data,
    })),
  });
});

/**
 * GET /v1/pool/count/:biome
 * Returns the number of maps in the pool for a biome.
 */
poolRoutes.get("/count/:biome", async (c) => {
  const biome = c.req.param("biome");

  const { rows } = await pool.query<{ count: string }>(
    `SELECT COUNT(*) AS count FROM warren_map_pool WHERE biome_name = $1`,
    [biome]
  );

  return c.json({ count: parseInt(rows[0].count, 10) });
});
