--[[
    It Gets Worse — PlaceGraph
    Declarative multi-Place navigation graph.

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    PlaceGraph declares which Places exist in the Experience and how players
    navigate between them. Bootstrap reads it at startup to determine context
    (which views to show, whether to create TitleScreen, etc.) instead of
    sniffing PrivateServerId at runtime.

    This is a data module, not a Node. It has no signals, no state, and no
    lifecycle. Any script can require it directly.

    ============================================================================
    SETUP
    ============================================================================

    After publishing both Places in Roblox Studio, fill in the placeId fields:

        PlaceGraph.places.start.placeId    = <your start Place ID>
        PlaceGraph.places.gameplay.placeId = <your gameplay Place ID>

    PlaceIds of 0 are treated as "not yet configured". In Studio (PlaceId 0),
    resolve() falls back to "start" so title screen works in Play Solo.

    ============================================================================
    NAVIGATION MODEL
    ============================================================================

    | Web Concept          | Framework Equivalent                        |
    |----------------------|---------------------------------------------|
    | Pages                | Places                                      |
    | <a href> / backlink  | PlaceGraph.navigateTo() / TeleportData      |
    | Route table          | PlaceGraph.places + PlaceGraph.links         |
    | URL determines view  | game.PlaceId → resolve() → initialView       |

--]]

local TeleportService = game:GetService("TeleportService")

local PlaceGraph = {}

--------------------------------------------------------------------------------
-- PLACE DEFINITIONS
--------------------------------------------------------------------------------
-- Fill in placeIds after publishing both Places.
-- placeId = 0 means "not yet configured" (Studio fallback).

PlaceGraph.places = {
    start = {
        placeId = 84800242213166,
        initialView = "title",
        views = { "title", "lobby" },
    },
    gameplay = {
        placeId = 95328643214618,
        initialView = "gameplay",
        views = { "gameplay" },
    },
}

--------------------------------------------------------------------------------
-- LINK DEFINITIONS
--------------------------------------------------------------------------------

PlaceGraph.links = {
    { from = "start",    to = "gameplay", method = "reserve" },
    { from = "gameplay", to = "start",    destination = "lobby" },
    { from = "gameplay", to = "start",    destination = "title" },
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

-- Build reverse lookup: placeId → placeName (lazily cached)
local _placeIdMap = nil

local function getPlaceIdMap()
    if _placeIdMap then return _placeIdMap end
    _placeIdMap = {}
    for name, def in pairs(PlaceGraph.places) do
        if def.placeId ~= 0 then
            _placeIdMap[def.placeId] = name
        end
    end
    return _placeIdMap
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Resolve a PlaceId to its place name and config.
    Falls back to "start" for PlaceId 0 (Studio) or unknown IDs.

    @param placeId number - game.PlaceId
    @return name string, config table
--]]
function PlaceGraph.resolve(placeId)
    local map = getPlaceIdMap()
    local name = map[placeId]
    if name then
        return name, PlaceGraph.places[name]
    end
    -- Fallback: Studio (PlaceId 0) or unconfigured → start
    return "start", PlaceGraph.places.start
end

--[[
    Get a place definition by name.

    @param name string - "start" or "gameplay"
    @return table - Place config (placeId, initialView, views)
--]]
function PlaceGraph.getPlace(name)
    return PlaceGraph.places[name]
end

--[[
    Check if the current server is a gameplay server.
    Equivalent to the old `isReservedServer` check.

    @return boolean
--]]
function PlaceGraph.isGameplayServer()
    local name = PlaceGraph.resolve(game.PlaceId)
    return name == "gameplay"
end

--[[
    Navigate a player to a target place.
    Uses TeleportService:Teleport with optional TeleportData.

    @param target string - Place name ("start", "gameplay")
    @param player Player - The player to teleport
    @param teleportData table? - Optional data (e.g. { destination = "lobby" })
--]]
function PlaceGraph.navigateTo(target, player, teleportData)
    local place = PlaceGraph.places[target]
    if not place then
        warn("[PlaceGraph] Unknown target place:", target)
        return
    end
    local success, err = pcall(function()
        TeleportService:Teleport(place.placeId, player, nil, teleportData)
    end)
    if not success then
        warn("[PlaceGraph] navigateTo failed:", target, "placeId:", place.placeId, "error:", err)
    end
end

--[[
    Reserve a private server on the target place and teleport players to it.
    Used by LobbyManager for co-op dungeon entry.

    @param target string - Place name (usually "gameplay")
    @param players {Player} - Array of players to teleport
    @return boolean success, string? reservedCode
--]]
function PlaceGraph.reserveAndTeleport(target, players)
    local place = PlaceGraph.places[target]
    if not place then
        warn("[PlaceGraph] Unknown target place:", target)
        return false
    end

    local success, code = pcall(function()
        return TeleportService:ReserveServer(place.placeId)
    end)

    if not success or not code then
        return false
    end

    local teleportSuccess = pcall(function()
        TeleportService:TeleportToPrivateServer(place.placeId, code, players)
    end)

    return teleportSuccess, code
end

return PlaceGraph
