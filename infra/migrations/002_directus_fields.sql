-- Warren Directus Field Metadata + Relationships
-- Migration 002: Register field display config + relationships in Directus
-- Run against: directus database
-- Date: 2026-02-15

BEGIN;

-- =============================================================================
-- warren_studios fields
-- =============================================================================
INSERT INTO directus_fields (collection, field, special, interface, display, display_options, options, sort, width, hidden, readonly, required, note) VALUES
  ('warren_studios', 'id',            'uuid',        'input',     'raw',       NULL, NULL, 1,  'full',  true,  true,  false, NULL),
  ('warren_studios', 'name',          NULL,          'input',     'raw',       NULL, NULL, 2,  'half',  false, false, true,  'Studio display name'),
  ('warren_studios', 'slug',          NULL,          'input',     'raw',       NULL, NULL, 3,  'half',  false, false, true,  'URL-safe identifier'),
  ('warren_studios', 'owner_email',   NULL,          'input',     'raw',       NULL, NULL, 4,  'half',  false, false, true,  'Primary contact email'),
  ('warren_studios', 'authentik_uid', NULL,          'input',     'raw',       NULL, NULL, 5,  'half',  false, false, false, 'Authentik SSO user ID (optional)'),
  ('warren_studios', 'created_at',    'date-created','datetime',  'datetime',  NULL, NULL, 6,  'half',  false, true,  false, NULL),
  ('warren_studios', 'updated_at',    'date-updated','datetime',  'datetime',  NULL, NULL, 7,  'half',  false, true,  false, NULL),
  -- O2M alias: games belonging to this studio
  ('warren_studios', 'games',         'o2m',         'list-o2m',  'related-values', '{"template":"{{name}} ({{universe_id}})"}', NULL, 8, 'full', false, false, false, 'Games owned by this studio');

-- =============================================================================
-- warren_games fields
-- =============================================================================
INSERT INTO directus_fields (collection, field, special, interface, display, display_options, options, sort, width, hidden, readonly, required, note) VALUES
  ('warren_games', 'id',           'uuid',        'input',     'raw',       NULL, NULL, 1,  'full',  true,  true,  false, NULL),
  ('warren_games', 'studio_id',    'm2o',         'select-dropdown-m2o', 'related-values', '{"template":"{{name}}"}', NULL, 2,  'half',  false, false, true,  'Owning studio'),
  ('warren_games', 'name',         NULL,          'input',     'raw',       NULL, NULL, 3,  'half',  false, false, true,  'Game display name'),
  ('warren_games', 'universe_id',  NULL,          'input',     'raw',       NULL, NULL, 4,  'half',  false, false, true,  'Roblox Universe ID'),
  ('warren_games', 'created_at',   'date-created','datetime',  'datetime',  NULL, NULL, 5,  'half',  false, true,  false, NULL),
  ('warren_games', 'updated_at',   'date-updated','datetime',  'datetime',  NULL, NULL, 6,  'half',  false, true,  false, NULL),
  -- O2M alias: license for this game (displayed inline)
  ('warren_games', 'license',      'o2m',         'list-o2m',  'related-values', '{"template":"{{tier}} — {{status}}"}', NULL, 7, 'full', false, false, false, 'License (one per game)'),
  -- O2M alias: API keys for this game
  ('warren_games', 'api_keys',     'o2m',         'list-o2m',  'related-values', '{"template":"{{label}} ({{key_prefix}})"}', NULL, 8, 'full', false, false, false, 'API keys');

-- =============================================================================
-- warren_licenses fields
-- =============================================================================
INSERT INTO directus_fields (collection, field, special, interface, display, display_options, options, sort, width, hidden, readonly, required, note) VALUES
  ('warren_licenses', 'id',            'uuid',        'input',     'raw',       NULL, NULL, 1,  'full',  true,  true,  false, NULL),
  ('warren_licenses', 'game_id',       'm2o',         'select-dropdown-m2o', 'related-values', '{"template":"{{name}}"}', NULL, 2,  'half',  false, false, true,  'Licensed game'),
  ('warren_licenses', 'tier',          NULL,          'select-dropdown', 'raw', NULL, '{"choices":[{"text":"Mach 2","value":"mach2"},{"text":"Mach 3","value":"mach3"}]}', 3, 'half', false, false, true, 'License tier'),
  ('warren_licenses', 'status',        NULL,          'select-dropdown', 'labels', NULL, '{"choices":[{"text":"Active","value":"active"},{"text":"Trial","value":"trial"},{"text":"Suspended","value":"suspended"},{"text":"Expired","value":"expired"}]}', 4, 'half', false, false, true, 'License status'),
  ('warren_licenses', 'is_internal',   'boolean',     'boolean',   'boolean',   NULL, NULL, 5,  'half',  false, false, false, 'Internal (Pure Fiction) license — no billing'),
  ('warren_licenses', 'trial_ends_at', NULL,          'datetime',  'datetime',  NULL, NULL, 6,  'half',  false, false, false, NULL),
  ('warren_licenses', 'expires_at',    NULL,          'datetime',  'datetime',  NULL, NULL, 7,  'half',  false, false, false, 'NULL = perpetual'),
  ('warren_licenses', 'created_at',    'date-created','datetime',  'datetime',  NULL, NULL, 8,  'half',  false, true,  false, NULL),
  ('warren_licenses', 'updated_at',    'date-updated','datetime',  'datetime',  NULL, NULL, 9,  'half',  false, true,  false, NULL);

-- =============================================================================
-- warren_api_keys fields
-- =============================================================================
INSERT INTO directus_fields (collection, field, special, interface, display, display_options, options, sort, width, hidden, readonly, required, note) VALUES
  ('warren_api_keys', 'id',           'uuid',        'input',     'raw',       NULL, NULL, 1,  'full',  true,  true,  false, NULL),
  ('warren_api_keys', 'game_id',      'm2o',         'select-dropdown-m2o', 'related-values', '{"template":"{{name}}"}', NULL, 2,  'half',  false, false, true,  'Game this key belongs to'),
  ('warren_api_keys', 'key_hash',     NULL,          'input',     'raw',       NULL, NULL, 3,  'full',  true,  true,  false, 'SHA-256 hash (set by Flow)'),
  ('warren_api_keys', 'key_prefix',   NULL,          'input',     'raw',       NULL, NULL, 4,  'half',  false, true,  false, 'First 12 chars for display (set by Flow)'),
  ('warren_api_keys', 'label',        NULL,          'input',     'raw',       NULL, NULL, 5,  'half',  false, false, true,  'Key label (e.g. production, staging)'),
  ('warren_api_keys', 'is_active',    'boolean',     'boolean',   'boolean',   NULL, NULL, 6,  'half',  false, false, false, NULL),
  ('warren_api_keys', 'last_used_at', NULL,          'datetime',  'datetime',  NULL, NULL, 7,  'half',  false, true,  false, 'Updated by Registry at runtime'),
  ('warren_api_keys', 'created_at',   'date-created','datetime',  'datetime',  NULL, NULL, 8,  'half',  false, true,  false, NULL),
  ('warren_api_keys', 'revoked_at',   NULL,          'datetime',  'datetime',  NULL, NULL, 9,  'half',  false, false, false, NULL);

-- =============================================================================
-- warren_sessions fields (all readonly — runtime data)
-- =============================================================================
INSERT INTO directus_fields (collection, field, special, interface, display, display_options, options, sort, width, hidden, readonly, required, note) VALUES
  ('warren_sessions', 'id',           'uuid',        'input',     'raw',       NULL, NULL, 1,  'full',  true,  true,  false, NULL),
  ('warren_sessions', 'api_key_id',   'm2o',         'select-dropdown-m2o', 'related-values', '{"template":"{{label}} ({{key_prefix}})"}', NULL, 2,  'half',  false, true, false, NULL),
  ('warren_sessions', 'game_id',      'm2o',         'select-dropdown-m2o', 'related-values', '{"template":"{{name}}"}', NULL, 3,  'half',  false, true, false, NULL),
  ('warren_sessions', 'universe_id',  NULL,          'input',     'raw',       NULL, NULL, 4,  'half',  false, true,  false, NULL),
  ('warren_sessions', 'place_id',     NULL,          'input',     'raw',       NULL, NULL, 5,  'half',  false, true,  false, NULL),
  ('warren_sessions', 'job_id',       NULL,          'input',     'raw',       NULL, NULL, 6,  'half',  false, true,  false, NULL),
  ('warren_sessions', 'tier',         NULL,          'input',     'raw',       NULL, NULL, 7,  'half',  false, true,  false, NULL),
  ('warren_sessions', 'scopes',       NULL,          'tags',      'raw',       NULL, NULL, 8,  'full',  false, true,  false, NULL),
  ('warren_sessions', 'token',        NULL,          'input',     'raw',       NULL, NULL, 9,  'full',  true,  true,  false, 'Session bearer token'),
  ('warren_sessions', 'expires_at',   NULL,          'datetime',  'datetime',  NULL, NULL, 10, 'half',  false, true,  false, NULL),
  ('warren_sessions', 'created_at',   'date-created','datetime',  'datetime',  NULL, NULL, 11, 'half',  false, true,  false, NULL);

-- =============================================================================
-- warren_usage_telemetry fields (all readonly — runtime data)
-- =============================================================================
INSERT INTO directus_fields (collection, field, special, interface, display, display_options, options, sort, width, hidden, readonly, required, note) VALUES
  ('warren_usage_telemetry', 'id',              NULL,  'input',     'raw',       NULL, NULL, 1,  'full',  true,  true,  false, NULL),
  ('warren_usage_telemetry', 'game_id',         'm2o', 'select-dropdown-m2o', 'related-values', '{"template":"{{name}}"}', NULL, 2,  'half',  false, true, false, NULL),
  ('warren_usage_telemetry', 'period_start',    NULL,  'datetime',  'datetime',  NULL, NULL, 3,  'half',  false, true,  false, NULL),
  ('warren_usage_telemetry', 'api_calls',       NULL,  'input',     'raw',       NULL, NULL, 4,  'half',  false, true,  false, NULL),
  ('warren_usage_telemetry', 'transport_msgs',  NULL,  'input',     'raw',       NULL, NULL, 5,  'half',  false, true,  false, NULL),
  ('warren_usage_telemetry', 'peak_ccu',        NULL,  'input',     'raw',       NULL, NULL, 6,  'half',  false, true,  false, NULL),
  ('warren_usage_telemetry', 'unique_sessions', NULL,  'input',     'raw',       NULL, NULL, 7,  'half',  false, true,  false, NULL);

-- =============================================================================
-- warren_rate_limits fields
-- =============================================================================
INSERT INTO directus_fields (collection, field, special, interface, display, display_options, options, sort, width, hidden, readonly, required, note) VALUES
  ('warren_rate_limits', 'tier',             NULL,  'input',  'raw',  NULL, NULL, 1,  'half',  false, false, true,  NULL),
  ('warren_rate_limits', 'scope',            NULL,  'input',  'raw',  NULL, NULL, 2,  'half',  false, false, true,  NULL),
  ('warren_rate_limits', 'requests_per_min', NULL,  'input',  'raw',  NULL, NULL, 3,  'half',  false, false, true,  NULL),
  ('warren_rate_limits', 'burst_limit',      NULL,  'input',  'raw',  NULL, NULL, 4,  'half',  false, false, true,  NULL);

-- =============================================================================
-- Relationships
-- =============================================================================
-- games.studio_id → studios (M2O, with O2M alias "games" on studios)
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field)
VALUES ('warren_games', 'studio_id', 'warren_studios', 'games');

-- licenses.game_id → games (M2O, with O2M alias "license" on games)
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field)
VALUES ('warren_licenses', 'game_id', 'warren_games', 'license');

-- api_keys.game_id → games (M2O, with O2M alias "api_keys" on games)
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field)
VALUES ('warren_api_keys', 'game_id', 'warren_games', 'api_keys');

-- sessions.api_key_id → api_keys (M2O, no reverse alias needed)
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field)
VALUES ('warren_sessions', 'api_key_id', 'warren_api_keys', NULL);

-- sessions.game_id → games (M2O, no reverse alias needed)
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field)
VALUES ('warren_sessions', 'game_id', 'warren_games', NULL);

-- usage_telemetry.game_id → games (M2O, no reverse alias needed)
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field)
VALUES ('warren_usage_telemetry', 'game_id', 'warren_games', NULL);

COMMIT;
