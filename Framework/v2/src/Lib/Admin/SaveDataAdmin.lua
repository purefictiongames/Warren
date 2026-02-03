--[[
    LibPureFiction Framework v2
    SaveDataAdmin.lua - Standalone Admin Utilities for Save Data

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Standalone admin utilities for managing player save data from Studio
    command bar. Works in EDIT MODE - no play session required.

    ============================================================================
    USAGE (Studio Command Bar)
    ============================================================================

    ```lua
    local Admin = require(game.ReplicatedStorage.Lib.Admin.SaveDataAdmin)

    -- Clear save data
    Admin.clear()                    -- Prompts for UserId
    Admin.clear(12345678)            -- By UserId

    -- View save data
    Admin.view()                     -- Prompts for UserId
    Admin.view(12345678)             -- By UserId

    -- Dump raw data (for debugging)
    Admin.dump(12345678)
    ```

    TODO: Integrate into proper admin panel UI later.
    See RegionManager.lua for related TODO notes.

--]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DATASTORE_NAME = "DungeonData_v1"

local SaveDataAdmin = {}

-- Resolve username or userId to userId
local function resolveUserId(userIdOrName)
    if type(userIdOrName) == "number" then
        return userIdOrName
    elseif type(userIdOrName) == "string" then
        -- Look up by username
        local success, userId = pcall(function()
            return Players:GetUserIdFromNameAsync(userIdOrName)
        end)
        if success then
            print("[SaveDataAdmin] Resolved", userIdOrName, "to UserId:", userId)
            return userId
        else
            warn("[SaveDataAdmin] Could not find user:", userIdOrName)
            return nil
        end
    else
        warn("[SaveDataAdmin] Invalid argument - use UserId number or username string")
        return nil
    end
end

-- Get or create DataStore connection
local function getDataStore()
    local success, store = pcall(function()
        return DataStoreService:GetDataStore(DATASTORE_NAME)
    end)
    if success then
        return store
    else
        warn("[SaveDataAdmin] DataStore not available:", store)
        return nil
    end
end

--[[
    Clear save data for a player.
    @param userIdOrName: number|string - UserId or username
]]
function SaveDataAdmin.clear(userIdOrName)
    if not userIdOrName then
        warn("[SaveDataAdmin] Usage: Admin.clear(userIdOrName)")
        warn("[SaveDataAdmin] Example: Admin.clear(12345678) or Admin.clear(\"Username\")")
        return false
    end

    local userId = resolveUserId(userIdOrName)
    if not userId then return false end

    local store = getDataStore()
    if not store then return false end

    local key = "player_" .. tostring(userId)
    local success, err = pcall(function()
        store:RemoveAsync(key)
    end)

    if success then
        print("[SaveDataAdmin] Cleared save data for UserId:", userId)
    else
        warn("[SaveDataAdmin] Failed to clear data:", err)
    end

    return success
end

--[[
    View save data summary for a player.
    @param userIdOrName: number|string - UserId or username
]]
function SaveDataAdmin.view(userIdOrName)
    if not userIdOrName then
        warn("[SaveDataAdmin] Usage: Admin.view(userIdOrName)")
        warn("[SaveDataAdmin] Example: Admin.view(12345678) or Admin.view(\"Username\")")
        return nil
    end

    local userId = resolveUserId(userIdOrName)
    if not userId then return nil end

    local store = getDataStore()
    if not store then return nil end

    local key = "player_" .. tostring(userId)
    local success, data = pcall(function()
        return store:GetAsync(key)
    end)

    if not success then
        warn("[SaveDataAdmin] Failed to read data:", data)
        return nil
    end

    if not data then
        print("[SaveDataAdmin] No save data for UserId:", userId)
        return nil
    end

    print("[SaveDataAdmin] Save data for UserId", userId)
    print("  - Version:", data.version)
    print("  - Region count:", data.regionCount)
    print("  - Active region:", data.activeRegionId)
    print("  - Unlinked pads:", data.unlinkedPadCount)

    if data.regions then
        for regionId, region in pairs(data.regions) do
            if region.seed then
                print(string.format("  - %s: seed=%d, padCount=%d, type=%s",
                    regionId,
                    region.seed,
                    region.padCount or 0,
                    region.mapType or "unknown"))
            elseif region.layout then
                local roomCount = 0
                if region.layout.rooms then
                    for _ in pairs(region.layout.rooms) do
                        roomCount = roomCount + 1
                    end
                end
                print("  - " .. regionId .. ": (legacy) " .. roomCount .. " rooms")
            end
        end
    end

    return data
end

--[[
    Dump raw save data structure (for debugging).
    @param userIdOrName: number|string - UserId or username
]]
function SaveDataAdmin.dump(userIdOrName)
    if not userIdOrName then
        warn("[SaveDataAdmin] Usage: Admin.dump(userIdOrName)")
        warn("[SaveDataAdmin] Example: Admin.dump(12345678) or Admin.dump(\"Username\")")
        return nil
    end

    local userId = resolveUserId(userIdOrName)
    if not userId then return nil end

    local store = getDataStore()
    if not store then return nil end

    local key = "player_" .. tostring(userId)
    local success, data = pcall(function()
        return store:GetAsync(key)
    end)

    if not success then
        warn("[SaveDataAdmin] Failed to read data:", data)
        return nil
    end

    if not data then
        print("[SaveDataAdmin] No save data for UserId:", userId)
        return nil
    end

    print("[SaveDataAdmin] === RAW DATA DUMP for UserId", userId, "===")

    -- Print the entire structure
    local function printTable(tbl, indent)
        indent = indent or ""
        for key, value in pairs(tbl) do
            if type(value) == "table" then
                print(indent .. tostring(key) .. ":")
                printTable(value, indent .. "  ")
            else
                print(indent .. tostring(key) .. " = " .. tostring(value))
            end
        end
    end

    printTable(data)
    print("[SaveDataAdmin] === END RAW DATA DUMP ===")

    return data
end

--[[
    Print help information.
]]
function SaveDataAdmin.help()
    print([[
SaveDataAdmin - Studio Command Bar Utilities (works in Edit Mode)

Usage:
    local Admin = require(game.ReplicatedStorage.Lib.Admin.SaveDataAdmin)

    Admin.clear("Username")  -- Clear save data by username
    Admin.clear(12345678)    -- Clear save data by UserId
    Admin.view("Username")   -- View save data summary
    Admin.dump("Username")   -- Dump raw data structure
    Admin.help()             -- Show this help

Example:
    Admin.clear("Wh1t3P0ny80")
    Admin.view("Wh1t3P0ny80")
]])
end

return SaveDataAdmin
