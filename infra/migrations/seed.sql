-- Warren Seed Data — IGW studio, game, license, API key
-- Migration: Run after 001_warren_schema.sql and 002_directus_fields.sql
-- Note: API key hash+prefix are patched by registry-deploy.sh at runtime
-- Date: 2026-02-15

BEGIN;

INSERT INTO warren_studios (id, name, slug, owner_email)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'Pure Fiction Records LLC', 'pure-fiction', 'admin@alpharabbitgames.com'
) ON CONFLICT (slug) DO NOTHING;

INSERT INTO warren_games (id, studio_id, name, universe_id)
VALUES (
    'b0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'It Gets Worse', 9710265660
) ON CONFLICT (universe_id) DO NOTHING;

INSERT INTO warren_licenses (id, game_id, tier, status, is_internal)
VALUES (
    'c0000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000001',
    'mach3', 'active', true
) ON CONFLICT (game_id) DO NOTHING;

-- API key: hash+prefix patched by deploy script at runtime
INSERT INTO warren_api_keys (id, game_id, key_hash, key_prefix, label, is_active)
VALUES (
    'd0000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000001',
    'KEY_HASH_PLACEHOLDER', 'KEY_PREFIX_PL', 'production', true
) ON CONFLICT DO NOTHING;

COMMIT;
