# Warren Platform Architecture

> **Status**: Draft — Architecture Spec (no code implementation)
> **Date**: 2026-02-15
> **Branch**: v3.0

---

## Context

Warren is being spun off from Pure Fiction Games as a standalone product. Two tiers built from the same codebase:

- **Mach 2**: Client-side APIs only (layout, style, DOM, factory). Free up to a player threshold, then 3% revenue license.
- **Mach 3**: Full client + server APIs (adds transport, state sync, OpenCloud proxy). Flat annual rate per game. Each game gets a dedicated Warren server process.

Source code stays server-side. The Roblox package is a thin SDK wrapping REST calls. All framework logic runs on Warren infrastructure. An API key + registry system handles licensing, tier enforcement, and usage tracking.

Internal games (IT GETS WORSE) get perpetual internal licenses.

---

## 1. System Overview

```
┌─────────────────────────────────────┐
│         Developer's Game            │
│  ┌─────────────────────────────┐    │
│  │     Warren SDK (Roblox)     │    │
│  │  Thin REST client + cache   │    │
│  └──────────┬──────────────────┘    │
└─────────────┼───────────────────────┘
              │ HTTPS
              ▼
┌──────────────────────────────────────────────┐
│    Warren Platform (VPS)                     │
│                                              │
│  ┌──────────────┐  ┌────────────┐            │
│  │   Registry    │  │  Warren    │            │
│  │  (Node/Hono)  │  │  API       │            │
│  │  Port 8100    │  │  (Lune)    │            │
│  │               │  │  Per-game  │            │
│  │  Runtime auth,│  │  instances │            │
│  │  session mgmt,│  │            │            │
│  │  usage        │  │  Layout,   │            │
│  └───┬──────┬────┘  │  Style,    │            │
│      │      │       │  Transport │            │
│  ┌───▼──┐ ┌─▼────┐  └────────────┘            │
│  │Postgres│ │Redis │                           │
│  │  16   │ │  7   │  ┌────────────────────┐   │
│  └───────┘ └──────┘  │  Directus (CMS)    │   │
│                       │  cms.alpharabbit…  │   │
│                       │                    │   │
│                       │  Admin UI for:     │   │
│                       │  Studios, Games,   │   │
│                       │  Licenses, Keys    │   │
│                       │                    │   │
│                       │  Flows: API key    │   │
│                       │  generation        │   │
│                       └────────┬───────────┘   │
│                                │ reads/writes   │
│                                ▼ warren_* tables  │
│  nginx reverse proxy (TLS)                     │
└──────────────────────────────────────────────┘
```

Four components:

- **Directus** (existing): Admin plane — CRUD for studios, games, licenses, API keys. Operators use the Directus UI at `cms.alpharabbitgames.com` to register games and generate keys. A Directus Flow handles key generation (hash + store). Reads/writes directly to `warren_*` tables in the `directus` database.
- **Registry** (Node.js/Hono): Runtime plane — session auth (validate/refresh/revoke), scope enforcement, rate limiting, usage telemetry. No admin CRUD — that's all Directus. Reads `warren_*` tables for key/license lookups.
- **Warren API** (Lune): Data plane — layout generation, style resolution, factory operations. Shared Mach 2 endpoints. Talks to Postgres via Registry API (not direct).
- **Warren Authority** (Lune, per-game): Mach 3 only — dedicated process per game. Transport, state sync, OpenCloud proxy. Spawned/managed by the Registry when a Mach 3 game connects.

---

## 2. Admin Plane (Directus)

The existing Directus instance at `cms.alpharabbitgames.com` serves as the admin interface for Warren. No custom dashboard needed — Directus provides the UI, permissions, and automation out of the box.

### 2.1 Directus Collection Mapping

Tables live in the `public` schema with a `warren_` prefix (Directus 11 doesn't reliably support multi-schema). Each table is registered as a Directus collection:

| Collection | Purpose | Key Fields |
|------------|---------|------------|
| `warren_studios` | Studio/org management | name, slug, owner_email, authentik_uid |
| `warren_games` | Registered Roblox universes | studio (M2O), name, universe_id |
| `warren_licenses` | One per game | game (O2O), tier dropdown, status dropdown, is_internal toggle |
| `warren_api_keys` | Bearer tokens | game (M2O), key_hash (read-only), key_prefix (read-only), label, is_active toggle |

**Relationships configured in Directus**:
- `games.studio_id` → M2O to `studios`
- `licenses.game_id` → O2O to `games` (displayed inline on game detail)
- `api_keys.game_id` → O2M from `games` (displayed as related list on game detail)

### 2.2 API Key Generation Flow

A Directus Flow triggers on `api_keys.items.create`:

```
Trigger: items.create on warren_api_keys
  → Run Script (custom JS operation):
      1. Generate 48-byte random key → base64url encode → "wrn_" prefix
         e.g. "wrn_k7Bx9mQ2pL..."
      2. SHA-256 hash the raw key → store in key_hash field
      3. First 12 chars → store in key_prefix field
      4. Return raw key in Flow response (shown ONCE in Directus notification)
  → Send Notification:
      Display raw key to admin with "copy and store — this won't be shown again"
```

**Operator workflow**:
1. Navigate to Games collection in Directus
2. Open a game → scroll to API Keys related list → click "+"
3. Enter a label (e.g. "production", "staging")
4. Save → Flow generates the key → raw key shown in notification
5. Copy raw key → store in Roblox Secrets for that universe

### 2.3 Directus Permissions

| Role | Studios | Games | Licenses | API Keys | Sessions | Usage |
|------|---------|-------|----------|----------|----------|-------|
| Admin | CRUD | CRUD | CRUD | CRUD | Read | Read |
| Operator | Read | Read/Update | Read/Update | Create/Read | Read | Read |
| Viewer | Read | Read | Read | Read (no hash) | — | Read |

Sessions and usage telemetry are read-only in Directus — written exclusively by the Registry at runtime.

---

## 3. Registry Service (Node.js / Hono)

Runtime-only service. No admin CRUD — all game/key/license management is done through Directus (Section 2). The Registry only handles session auth, scope enforcement, and usage tracking at runtime.

**Tech stack**: TypeScript, Hono framework, `pg` (Postgres), `ioredis` (Redis)
**Container**: Docker, alongside existing stack
**URL**: `https://registry.warren.gg` (or `registry.alpharabbitgames.com`)

### 3.1 Database Schema (Postgres, `public` schema, `warren_` prefix)

Tables live in the `public` schema with `warren_` prefix (Directus 11 multi-schema support is unreliable). See `infra/migrations/001_warren_schema.sql` for the full DDL.

```sql
-- Prefix: warren_ (in public schema)

-- Studios: Organizations that own games
CREATE TABLE warren_studios (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    slug            TEXT NOT NULL UNIQUE,
    owner_email     TEXT NOT NULL,
    authentik_uid   TEXT,                      -- Optional SSO link
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Games: Registered Roblox universes
CREATE TABLE warren_games (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    studio_id       UUID NOT NULL REFERENCES warren_studios(id),
    name            TEXT NOT NULL,
    universe_id     BIGINT NOT NULL UNIQUE,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Licenses: One per game
CREATE TABLE warren_licenses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id         UUID NOT NULL UNIQUE REFERENCES warren_games(id),
    tier            TEXT NOT NULL CHECK (tier IN ('mach2', 'mach3')),
    status          TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'expired', 'trial')),
    is_internal     BOOLEAN NOT NULL DEFAULT false,
    trial_ends_at   TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,               -- NULL = perpetual
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- API Keys: Bearer tokens tied to games
CREATE TABLE warren_api_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id         UUID NOT NULL REFERENCES warren_games(id),
    key_hash        TEXT NOT NULL UNIQUE,       -- SHA-256 of raw key
    key_prefix      TEXT NOT NULL,              -- First 12 chars for display
    label           TEXT NOT NULL DEFAULT 'default',
    is_active       BOOLEAN NOT NULL DEFAULT true,
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT now(),
    revoked_at      TIMESTAMPTZ
);

-- Sessions: Validated auth sessions
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
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- Usage Telemetry: Hourly buckets
CREATE TABLE warren_usage_telemetry (
    id              BIGSERIAL PRIMARY KEY,
    game_id         UUID NOT NULL REFERENCES warren_games(id),
    period_start    TIMESTAMPTZ NOT NULL,
    api_calls       INTEGER DEFAULT 0,
    transport_msgs  INTEGER DEFAULT 0,
    peak_ccu        INTEGER DEFAULT 0,
    unique_sessions INTEGER DEFAULT 0,
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
```

### 3.2 Redis Keys

```
warren:session:{token}                          → JSON session   TTL 30min
warren:ratelimit:{game_id}:{scope}:{minute}     → counter        TTL 2min
warren:license:{universe_id}                    → JSON license   TTL 5min
warren:layout:{seed}:{config_hash}              → JSON layout    TTL 24hr
```

### 3.3 Registry API Endpoints

The Registry exposes only runtime endpoints. All admin CRUD (studios, games, keys, licenses) is handled through Directus.

**Auth (called by SDK)**

```
POST /v1/auth/validate     — API key + universe → session token + tier + scopes
POST /v1/auth/refresh      — Extend session TTL
POST /v1/auth/revoke       — End session (game shutdown)
```

**Usage (called by SDK, fire-and-forget)**

```
POST /v1/usage/report
```

### 3.4 Auth Flow

```
Game boot
  → SDK reads API key from Roblox Secrets
  → POST /v1/auth/validate { apiKey, universeId, placeId, jobId }
  → Registry: hash key → lookup api_keys → verify game.universe_id matches
    → check license status/tier → generate session token → store in Postgres + Redis
  → Returns { sessionToken, tier, scopes, ttl, expiresAt }
  → SDK caches token, attaches to all subsequent requests
  → Refresh loop runs at TTL/2 interval
  → On game shutdown: POST /v1/auth/revoke
```

---

## 4. Tier Scopes

| Tier | Scopes |
|------|--------|
| **Mach 2** | `layout.*`, `style.*`, `dom.*`, `factory.*` |
| **Mach 3** | Everything in Mach 2 + `transport.*`, `state.*`, `opencloud.*` |
| **Internal** | All scopes, no billing |

Scope check is middleware on every API request. Mach 2 key hitting a `transport.*` endpoint → 403 with upgrade message.

---

## 5. Warren API (Data Plane — Lune)

Shared Lune service handling Mach 2 compute. All endpoints require valid session token.

**Middleware chain**: Auth (Redis → Postgres fallback) → Scope check → Rate limit → Handler → Usage counter

### 5.1 Mach 2 Endpoints

```
POST /v1/layout/generate        — Seed + config → full layout (rooms, doors, trusses, lights, pads, spawn)
POST /v1/layout/enrich          — Predefined rooms → enriched layout
GET  /v1/style/stylesheet       — Full stylesheet (ETag-backed)
POST /v1/style/resolve          — Element + classes → computed style
POST /v1/style/resolve-batch    — Batch resolve for instantiation
POST /v1/factory/geometry       — Geometry spec → instantiation plan (part list)
```

**Caching**: Layout generation is deterministic (same seed + config = same output). Cache key = `layout:{seed}:{hash(config)}`. Redis TTL 24hr. SDK also caches locally. Stylesheets use ETag — 304 if unchanged.

### 5.2 Mach 3 Endpoints (Dedicated Per-Game Process)

Each Mach 3 game gets a dedicated Lune authority process managed by the Registry:

```
POST /v1/transport/send         — Roblox → Lune envelopes
GET  /v1/transport/poll         — Lune → Roblox envelopes
GET  /v1/transport/health
POST /v1/state/snapshot         — Full state snapshot request
POST /v1/state/action           — Submit action (request/response)
POST /v1/opencloud/datastore/*  — Proxied DataStore operations
POST /v1/opencloud/messaging/*  — Proxied MessagingService
```

**Process lifecycle**: Registry spawns a Lune process when first Mach 3 session validates for a game. Process stays alive while active sessions exist. Torn down after idle timeout (configurable, default 15 min no sessions). Registry tracks process PID/port and routes traffic.

**Per-game config**: Each Mach 3 game registers its Open Cloud API key + universe ID in the registry. The dedicated Lune process reads this from the registry at startup. Game's credentials never touch the SDK.

---

## 6. SDK Design (Roblox Package)

Thin Luau module. Zero framework logic — just HTTP wrappers and caching.

### 6.1 Module Structure

```
WarrenSDK/
  init.lua            — Public API, init(), tier gate
  Auth.lua            — validate/refresh/revoke session
  Cache.lua           — In-memory TTL cache with ETag support
  Http.lua            — HttpService wrapper, retry/backoff, error handling
  Layout.lua          — Layout.generate(), Layout.enrich()
  Style.lua           — Style.resolve(), Style.stylesheet()
  Factory.lua         — Factory.geometry()
  Transport.lua       — Transport.start/send/poll (Mach 3)
  State.lua           — State store + sync (Mach 3)
  OpenCloud.lua       — DataStore/Messaging proxy (Mach 3)
  Preloader.lua       — Boot-time preloading
```

### 6.2 Init Flow

```lua
local Warren = require(ReplicatedStorage.WarrenSDK)

local session = Warren.init({
    apiKeySecret = "warren_api_key",   -- Roblox Secrets name
})
-- SDK: reads secret, POST /v1/auth/validate, caches session
-- Returns: { tier, scopes, sessionToken, expiresAt }

-- Preload (during loading screen)
Warren.Preloader.run({
    layoutSeeds = { 0 },              -- Known seeds to pre-cache
    layoutConfig = { ... },
})

-- Use APIs
local layout = Warren.Layout.generate({ seed = 42, config = { ... } })
local style = Warren.Style.resolve("Part", { "cave-wall" })

-- Mach 3 only (gated by tier)
if session.tier == "mach3" then
    Warren.Transport.start()
    Warren.State.startReplica(store)
end
```

### 6.3 Caching Strategy

| Data | Location | TTL | Strategy |
|------|----------|-----|----------|
| Session token | SDK memory + Redis | 30 min | Refresh at 15 min |
| License status | Redis | 5 min | Admin flush on change |
| Layout results | SDK memory + Redis | 24 hr | Deterministic — seed+config=key |
| Stylesheet | SDK memory | Session lifetime | ETag conditional requests |
| Style resolution | SDK memory | Session lifetime | Bulk preload on boot |
| Rate limit counters | Redis | 2 min | Per-minute sliding window |

### 6.4 Error Handling

| Status | Meaning | SDK Behavior |
|--------|---------|--------------|
| **401** | Session expired | Auto-refresh, retry once |
| **403 scope_denied** | Tier too low | Error with upgrade URL |
| **403 license_suspended** | Hard stop | Display message to developer |
| **429** | Rate limited | Exponential backoff (0.5s, 1s, 2s), max 3 retries |
| **5xx** | Server error | Retry with backoff, fail after 3 attempts |
| **Network failure** | Unreachable | Retry with backoff, use cached data if available |

---

## 7. Dedicated Mach 3 Process Management

The Registry acts as a process supervisor for Mach 3 authority servers:

```
Mach 3 game validates → Registry checks for existing process
  → If none: spawn Lune process with game config (port, universe, OC credentials)
  → Store PID + port in warren_game_processes table
  → nginx upstream updated (or Registry proxies directly)
  → Route all transport/state/OC requests to that process

Idle detection: no active sessions for 15 min → graceful shutdown
  → SIGTERM to Lune process → state flushed to DataStore → process exits
  → Registry cleans up process record

Crash recovery: Registry health-checks each process
  → If unhealthy: restart, state recovered from DataStore snapshot
```

---

## 8. Infrastructure Changes

| Change | Details |
|--------|---------|
| **DNS** | `registry.warren.gg` (or `registry.alpharabbitgames.com`) |
| **Docker container** | Registry (Node.js/Hono) on port 8100 |
| **Postgres** | `warren_*` tables in `directus` database (`infra/migrations/001_warren_schema.sql`) |
| **Directus** | Register `warren_*` tables as Directus collections, configure relationships, create API key generation Flow |
| **nginx** | New vhost for registry, update Warren API routing |
| **systemd** | Template unit for Mach 3 per-game processes (`warren-game@.service`) |

---

## 9. Internal Game Migration Path

IT GETS WORSE currently uses the framework directly (all source in ReplicatedStorage). Migration to SDK:

1. Register game in Directus: create studio + game + license (`is_internal = true`, `tier = mach3`)
2. Generate API key via Directus (Flow generates + hashes), store raw key in Roblox Secrets
3. Replace `require(ReplicatedStorage.Warren)` with `require(ReplicatedStorage.WarrenSDK)`
4. Replace direct module calls with SDK REST wrappers
5. Remove Warren source from ReplicatedStorage (only SDK remains)
6. Existing Lune server becomes the dedicated Mach 3 process, managed by Registry

---

## 10. Verification Plan

1. **Schema + Directus**: Run schema migration, register `warren_*` collections in Directus, create test studio + game + license + API key via Directus UI, verify Flow generates hashed key
2. **Auth flow**: SDK init → validate → get session → verify Redis cache → verify scope enforcement (Mach 2 key rejected on transport endpoint)
3. **Layout pipeline**: Generate layout via API → verify matches current direct-call output for same seed
4. **Caching**: Generate same layout twice → verify second call hits cache (Redis + SDK memory)
5. **Mach 3 process**: Validate Mach 3 key → verify dedicated Lune process spawned → transport send/poll works → idle timeout triggers shutdown
6. **Internal game**: IT GETS WORSE migrated to SDK → all existing functionality preserved
