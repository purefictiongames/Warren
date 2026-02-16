-- Warren Platform Schema
-- Migration 001: Core tables for studios, games, licenses, API keys, sessions, usage
-- Target: directus database, public schema, warren_ prefix
-- Date: 2026-02-15
--
-- Tables live in public schema with warren_ prefix so Directus can register
-- them as collections without multi-schema hacks.

BEGIN;

-- Studios: Organizations that own games
CREATE TABLE warren_studios (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    slug            TEXT NOT NULL UNIQUE,
    owner_email     TEXT NOT NULL,
    authentik_uid   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Games: Registered Roblox universes
CREATE TABLE warren_games (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    studio_id       UUID NOT NULL REFERENCES warren_studios(id),
    name            TEXT NOT NULL,
    universe_id     BIGINT NOT NULL UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Licenses: One per game
CREATE TABLE warren_licenses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id         UUID NOT NULL UNIQUE REFERENCES warren_games(id),
    tier            TEXT NOT NULL CHECK (tier IN ('mach2', 'mach3')),
    status          TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'expired', 'trial')),
    is_internal     BOOLEAN NOT NULL DEFAULT false,
    trial_ends_at   TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- API Keys: Bearer tokens tied to games
CREATE TABLE warren_api_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id         UUID NOT NULL REFERENCES warren_games(id),
    key_hash        TEXT NOT NULL UNIQUE,
    key_prefix      TEXT NOT NULL,
    label           TEXT NOT NULL DEFAULT 'default',
    is_active       BOOLEAN NOT NULL DEFAULT true,
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at      TIMESTAMPTZ
);

-- Sessions: Validated auth sessions (runtime, written by Registry)
CREATE TABLE warren_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_key_id      UUID NOT NULL REFERENCES warren_api_keys(id),
    game_id         UUID NOT NULL REFERENCES warren_games(id),
    universe_id     BIGINT NOT NULL,
    place_id        BIGINT,
    job_id          TEXT,
    tier            TEXT NOT NULL,
    scopes          TEXT[] NOT NULL,
    token           TEXT NOT NULL UNIQUE,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Usage Telemetry: Hourly buckets (runtime, written by Registry)
CREATE TABLE warren_usage_telemetry (
    id              BIGSERIAL PRIMARY KEY,
    game_id         UUID NOT NULL REFERENCES warren_games(id),
    period_start    TIMESTAMPTZ NOT NULL,
    api_calls       INTEGER NOT NULL DEFAULT 0,
    transport_msgs  INTEGER NOT NULL DEFAULT 0,
    peak_ccu        INTEGER NOT NULL DEFAULT 0,
    unique_sessions INTEGER NOT NULL DEFAULT 0,
    UNIQUE(game_id, period_start)
);

-- Rate Limits: Per-tier defaults
CREATE TABLE warren_rate_limits (
    tier            TEXT NOT NULL,
    scope           TEXT NOT NULL,
    requests_per_min INTEGER NOT NULL,
    burst_limit     INTEGER NOT NULL,
    PRIMARY KEY (tier, scope)
);

-- Seed default rate limits
INSERT INTO warren_rate_limits (tier, scope, requests_per_min, burst_limit) VALUES
    ('mach2', 'layout',    60,  10),
    ('mach2', 'style',    120,  20),
    ('mach2', 'dom',      120,  20),
    ('mach2', 'factory',   60,  10),
    ('mach3', 'layout',   120,  20),
    ('mach3', 'style',    240,  40),
    ('mach3', 'dom',      240,  40),
    ('mach3', 'factory',  120,  20),
    ('mach3', 'transport', 300,  50),
    ('mach3', 'state',    300,  50),
    ('mach3', 'opencloud', 60,  10);

-- Indexes for common lookups
CREATE INDEX idx_warren_games_studio ON warren_games(studio_id);
CREATE INDEX idx_warren_games_universe ON warren_games(universe_id);
CREATE INDEX idx_warren_licenses_game ON warren_licenses(game_id);
CREATE INDEX idx_warren_api_keys_game ON warren_api_keys(game_id);
CREATE INDEX idx_warren_api_keys_hash ON warren_api_keys(key_hash);
CREATE INDEX idx_warren_sessions_token ON warren_sessions(token);
CREATE INDEX idx_warren_sessions_game ON warren_sessions(game_id);
CREATE INDEX idx_warren_sessions_expires ON warren_sessions(expires_at);
CREATE INDEX idx_warren_usage_game_period ON warren_usage_telemetry(game_id, period_start);

COMMIT;
