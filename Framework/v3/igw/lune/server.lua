--[[
    It Gets Worse — Lune Authority Server
    lune/server.lua

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the Lune-side entry point for IGW. It boots Warren in headless
    mode and serves as the authoritative backend for:

        - Dungeon seed persistence (generate, store, retrieve via Open Cloud)
        - Player data management (visited rooms, region progress, save/load)
        - Seed generation authority (Lune generates seeds, Roblox materializes)

    Roblox game servers connect via Warren.Transport (HTTP polling) and
    send action requests. This server processes them and pushes state
    updates back.

    ============================================================================
    RUNNING
    ============================================================================

    ```bash
    lune run lune/server.lua
    ```

    Environment variables:
        ROBLOX_UNIVERSE_ID   - Your Roblox universe ID
        ROBLOX_API_KEY       - Open Cloud API key
        WARREN_AUTH_TOKEN     - Shared secret for transport auth
        WARREN_PORT          - HTTP port (default 8080)

--]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

-- Roblox exposes `task` as a built-in global; Lune requires explicit import
_G.task = require("@lune/task")

-- Load Warren framework (dual-runtime modules detect Lune via `script == nil`)
local Warren = require("../../warren/src")

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local config = {
    universeId = process.env.ROBLOX_UNIVERSE_ID or "84800242213166",
    apiKey = process.env.ROBLOX_API_KEY or "",
    authToken = process.env.WARREN_AUTH_TOKEN or "igw-dev-token",
    port = tonumber(process.env.WARREN_PORT) or 8090,
    pushInterval = 0.1,
}

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------

stdio.write("=== IT GETS WORSE — Lune Authority Server ===\n")
stdio.write("Warren v" .. Warren._VERSION .. "\n\n")

local ctx = Warren.Boot.start({
    universeId = config.universeId,
    apiKey = config.apiKey,
    authToken = config.authToken,
    port = config.port,
    pushInterval = config.pushInterval,

    onReady = function(ctx)
        stdio.write("\n[IGW] Server ready. Registering action handlers...\n")
    end,
})

--------------------------------------------------------------------------------
-- STATE INITIALIZATION
--------------------------------------------------------------------------------

local store = ctx.store
local datastore = ctx.datastore

-- DataStore name (matches Roblox-side RegionManager)
local DATASTORE_NAME = "DungeonData_v1"

--------------------------------------------------------------------------------
-- SEED GENERATION (authority)
--------------------------------------------------------------------------------

local function generateSeed()
    return os.time() + math.random(1, 100000)
end

--------------------------------------------------------------------------------
-- LAYOUT GENERATION (authority — keeps generation code off client)
--------------------------------------------------------------------------------

local net = require("@lune/net")
local serde = require("@lune/serde")

local LayoutBuilder = require("../src/Components/Layout/LayoutBuilder")
local Styles = Warren.Styles
local ClassResolver = Warren.ClassResolver

--------------------------------------------------------------------------------
-- STYLE RESOLUTION (pre-resolve on server, send alongside layout)
--------------------------------------------------------------------------------

-- Palette names (same list as StyleBridge.getPaletteClass)
local PALETTE_NAMES = {
    "palette-classic-lava",
    "palette-blue-inferno",
    "palette-toxic-depths",
    "palette-void-abyss",
    "palette-golden-forge",
    "palette-frozen-fire",
    "palette-blood-sanctum",
    "palette-solar-furnace",
    "palette-nether-realm",
    "palette-spectral-cavern",
}

-- Maps element role class -> which palette color property to use for Color
local COLOR_ROLE_MAP = {
    ["cave-wall"]           = "wallColor",
    ["cave-ceiling"]        = "wallColor",
    ["cave-floor"]          = "floorColor",
    ["cave-light-fixture"]  = "fixtureColor",
    ["cave-light-spacer"]   = "wallColor",
    ["cave-pad-base"]       = "floorColor",
    ["cave-point-light"]    = "lightColor",
}

-- Class combos that DomBuilder.buildTree() produces (with palette)
local PALETTE_CLASSES = {
    "cave-wall", "cave-ceiling", "cave-floor",
    "cave-light-spacer", "cave-light-fixture",
    "cave-point-light", "cave-pad-base",
}

-- Non-palette classes
local PLAIN_CLASSES = {
    "cave-zone", "cave-truss", "cave-pad", "cave-spawn",
}

local function resolveStylesForRegion(regionNum)
    local paletteClass = PALETTE_NAMES[((regionNum - 1) % #PALETTE_NAMES) + 1]
    local reservedKeys = { id = true, class = true, type = true }
    local resolvedClasses = {}

    -- Resolve palette-bearing class combos
    for _, baseClass in ipairs(PALETTE_CLASSES) do
        local classStr = baseClass .. " " .. paletteClass
        local resolved = ClassResolver.resolve(
            { class = classStr }, Styles, { reservedKeys = reservedKeys }
        )

        -- Apply color role mapping (same logic as StyleBridge.createResolver)
        local roleKey = COLOR_ROLE_MAP[baseClass]
        if roleKey and resolved[roleKey] and not resolved.Color then
            resolved.Color = resolved[roleKey]
        end

        -- Clean up palette meta-properties (not real Instance properties)
        resolved.wallColor = nil
        resolved.floorColor = nil
        resolved.lightColor = nil
        resolved.fixtureColor = nil

        resolvedClasses[classStr] = resolved
    end

    -- Resolve plain classes (no palette)
    for _, className in ipairs(PLAIN_CLASSES) do
        resolvedClasses[className] = ClassResolver.resolve(
            { class = className }, Styles, { reservedKeys = reservedKeys }
        )
    end

    -- Resolve palette colors for terrain painting (kept as RGB tables)
    local paletteResolved = ClassResolver.resolve(
        { class = paletteClass }, Styles, { reservedKeys = reservedKeys }
    )

    return {
        resolvedClasses = resolvedClasses,
        palette = {
            wallColor = paletteResolved.wallColor,
            floorColor = paletteResolved.floorColor,
            lightColor = paletteResolved.lightColor,
            fixtureColor = paletteResolved.fixtureColor,
        },
        paletteClass = paletteClass,
    }
end

-- Named handler (shared by Transport and RPC dispatch)
local function handleLayoutGenerate(payload)
    if not payload.config then
        return { status = "rejected", reason = "missing_config" }
    end

    local layout = LayoutBuilder.generate(payload.config)
    local styles = resolveStylesForRegion(payload.config.regionNum or 1)

    stdio.write("[IGW] Generated layout: seed=" .. (payload.config.seed or "?")
        .. ", region=" .. (payload.config.regionNum or "?")
        .. ", rooms=" .. (layout.rooms and #layout.rooms or 0)
        .. ", styles=" .. (styles.paletteClass or "?") .. "\n")

    return { status = "ok", layout = layout, styles = styles }
end

-- Register with Transport (existing envelope-based flow)
ctx.onAction("layout.action.generate", handleLayoutGenerate)

--------------------------------------------------------------------------------
-- ACTION HANDLERS
--------------------------------------------------------------------------------

--[[
    Handle seed request from Roblox.
    Generates a new seed and stores it in the state store.
    Roblox uses this seed to deterministically generate the layout.
]]
ctx.onAction("state.action.generateSeed", function(payload)
    local regionNum = payload.regionNum
    local playerId = payload.playerId

    if not regionNum or not playerId then
        return { status = "rejected", reason = "missing_regionNum_or_playerId" }
    end

    local seed = generateSeed()

    -- Store seed in state (will sync to Roblox via diff)
    local path = "dungeon." .. playerId .. ".regions.region_" .. regionNum
    store:set(path .. ".seed", seed)
    store:set(path .. ".regionNum", regionNum)

    stdio.write("[IGW] Generated seed " .. seed .. " for region " .. regionNum
        .. " (player " .. playerId .. ")\n")

    return {
        status = "ok",
        seed = seed,
        regionNum = regionNum,
    }
end)

--[[
    Handle player data save request from Roblox.
    Persists dungeon state to Open Cloud DataStore.
]]
ctx.onAction("state.action.savePlayerData", function(payload)
    local playerId = payload.playerId
    local saveData = payload.data

    if not playerId or not saveData then
        return { status = "rejected", reason = "missing_playerId_or_data" }
    end

    local key = "player_" .. playerId

    local ok, err = pcall(function()
        datastore:setEntry(DATASTORE_NAME, key, saveData)
    end)

    if ok then
        stdio.write("[IGW] Saved data for player " .. playerId .. "\n")
        return { status = "ok" }
    else
        stdio.write("[IGW] Save failed for player " .. playerId .. ": " .. tostring(err) .. "\n")
        return { status = "error", reason = tostring(err) }
    end
end)

--[[
    Handle player data load request from Roblox.
    Retrieves dungeon state from Open Cloud DataStore.
]]
ctx.onAction("state.action.loadPlayerData", function(payload)
    local playerId = payload.playerId

    if not playerId then
        return { status = "rejected", reason = "missing_playerId" }
    end

    local key = "player_" .. playerId

    local ok, data = pcall(function()
        return datastore:getEntry(DATASTORE_NAME, key)
    end)

    if ok and data then
        stdio.write("[IGW] Loaded data for player " .. playerId
            .. " (" .. (data.regionCount or 0) .. " regions)\n")

        -- Push player data into state store for sync
        store:set("dungeon." .. playerId .. ".saveData", data)

        return {
            status = "ok",
            data = data,
        }
    elseif ok then
        stdio.write("[IGW] No saved data for player " .. playerId .. "\n")
        return {
            status = "ok",
            data = nil,
        }
    else
        stdio.write("[IGW] Load failed for player " .. playerId .. ": " .. tostring(data) .. "\n")
        return { status = "error", reason = tostring(data) }
    end
end)

--[[
    Handle clear save data request from Roblox.
    Deletes dungeon state from Open Cloud DataStore.
]]
ctx.onAction("state.action.clearPlayerData", function(payload)
    local playerId = payload.playerId

    if not playerId then
        return { status = "rejected", reason = "missing_playerId" }
    end

    local key = "player_" .. playerId

    local ok, err = pcall(function()
        datastore:deleteEntry(DATASTORE_NAME, key)
    end)

    if ok then
        -- Clear from state store too
        store:delete("dungeon." .. playerId)
        stdio.write("[IGW] Cleared data for player " .. playerId .. "\n")
        return { status = "ok" }
    else
        stdio.write("[IGW] Clear failed for player " .. playerId .. ": " .. tostring(err) .. "\n")
        return { status = "error", reason = tostring(err) }
    end
end)

--[[
    Handle player room visit tracking.
    Records which rooms the player has visited (for minimap).
]]
ctx.onAction("state.action.visitRoom", function(payload)
    local playerId = payload.playerId
    local regionNum = payload.regionNum
    local roomId = payload.roomId

    if not playerId or not regionNum or not roomId then
        return { status = "rejected", reason = "missing_fields" }
    end

    local path = "dungeon." .. playerId .. ".visited." .. regionNum .. "." .. roomId
    store:set(path, true)

    return { status = "ok" }
end)

--------------------------------------------------------------------------------
-- SYNCHRONOUS RPC SERVER (Registry → Lune compute calls)
--------------------------------------------------------------------------------
-- Separate from Transport's async /send /poll protocol.
-- The Registry proxies stateless compute (layout, styles) through this endpoint.
-- State-related handlers (save/load/clear/visit) stay Transport-only.

local rpcHandlers = {
    ["layout.action.generate"] = handleLayoutGenerate,
}

local rpcPort = config.port + 1  -- 8091
net.serve(rpcPort, {
    address = "0.0.0.0",
    handleRequest = function(request)
        if request.method ~= "POST" or request.path ~= "/rpc" then
            return { status = 404, body = '{"error":"not_found"}' }
        end

        -- Auth check (same token as Transport)
        local auth = request.headers["authorization"] or ""
        if auth ~= "Bearer " .. config.authToken then
            return { status = 401, body = '{"error":"unauthorized"}' }
        end

        local body = serde.decode("json", request.body)
        local handler = rpcHandlers[body.action]
        if not handler then
            return { status = 404, body = serde.encode("json", { error = "action_not_found", action = body.action }) }
        end

        local ok, result = pcall(handler, body.payload)
        if ok then
            return { status = 200, body = serde.encode("json", result) }
        else
            return { status = 500, body = serde.encode("json", { error = tostring(result) }) }
        end
    end,
})

stdio.write("[IGW] RPC server listening on port " .. rpcPort .. "\n")

--------------------------------------------------------------------------------
-- KEEP ALIVE
--------------------------------------------------------------------------------

stdio.write("[IGW] Action handlers registered. Transport on port " .. config.port .. "\n")
stdio.write("[IGW] Press Ctrl+C to stop.\n\n")

-- Lune's net.serve runs in the background — script stays alive
-- until the process is killed
