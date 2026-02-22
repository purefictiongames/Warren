-- Map pool — pre-built maps for instant serving
-- L1: in-memory (Lune server), L2: Postgres (persists across restarts)
-- Height field is NOT stored — deterministic from seed + splines + biomeConfig

CREATE TABLE warren_map_pool (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    biome_name TEXT NOT NULL,
    seed BIGINT NOT NULL,
    map_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(seed, biome_name)
);

CREATE INDEX idx_map_pool_biome ON warren_map_pool(biome_name);
