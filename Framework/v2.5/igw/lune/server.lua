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

-- Load Warren framework
local Warren = require("../warren/src")

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local config = {
    universeId = process.env.ROBLOX_UNIVERSE_ID or "84800242213166",
    apiKey = process.env.ROBLOX_API_KEY or "",
    authToken = process.env.WARREN_AUTH_TOKEN or "igw-dev-token",
    port = tonumber(process.env.WARREN_PORT) or 8080,
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
-- KEEP ALIVE
--------------------------------------------------------------------------------

stdio.write("[IGW] Action handlers registered. Listening on port " .. config.port .. "\n")
stdio.write("[IGW] Press Ctrl+C to stop.\n\n")

-- Lune's net.serve runs in the background — script stays alive
-- until the process is killed
