--[[
    WorldManager — Chunked World Serving

    Wraps MapGen + Chunker. Pulls from pool (or generates), then splits
    into spatial chunks at serve-time.

    API:
        createWorld(biomeName) → worldId, global
        getChunks(worldId, coordsList) → { [key] = chunkData }
        destroyWorld(worldId)

    In-memory world store (one world per game session). Pool stores monolithic
    maps; chunker runs at serve-time (microseconds).
--]]

local stdio = require("@lune/stdio")

local MapGen  = require("../mapgen")
local Pool    = require("./pool")
local Chunker = require("./chunker")

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _worlds = {}  -- worldId → { global, chunks }
local _nextId = 1

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

local WorldManager = {}

--- Create a new world: fetch or generate map, then chunk-split.
--- @param biomeName string
--- @return string worldId, table global
function WorldManager.createWorld(biomeName)
    biomeName = biomeName or "mountain"
    local startTime = os.clock()

    -- Pool-first: instant if available
    local mapData = Pool.pull(biomeName)

    if not mapData then
        stdio.write("[WorldManager] Pool empty for " .. biomeName .. ", generating...\n")
        mapData = MapGen.generate({ biomeName = biomeName })
    end

    -- Chunk-split (pure function, microseconds)
    local splitResult = Chunker.split(mapData, {
        chunkSize = 512,
        mapWidth  = 4000,
        mapDepth  = 4000,
    })

    local worldId = "world_" .. _nextId
    _nextId = _nextId + 1

    _worlds[worldId] = {
        global = splitResult.global,
        chunks = splitResult.chunks,
    }

    local elapsed = os.clock() - startTime
    local chunkCount = 0
    for _ in pairs(splitResult.chunks) do chunkCount = chunkCount + 1 end

    stdio.write(string.format(
        "[WorldManager] Created %s: biome=%s seed=%s chunks=%d (%.3fs)\n",
        worldId, biomeName,
        tostring(splitResult.global.seed),
        chunkCount, elapsed
    ))

    return worldId, splitResult.global
end

--- Get chunk data for a list of chunk coordinates.
--- @param worldId string
--- @param coordsList table — array of { cx, cz } or "cx,cz" strings
--- @return table — { [key] = chunkData } (missing chunks = empty table for that key)
function WorldManager.getChunks(worldId, coordsList)
    local world = _worlds[worldId]
    if not world then
        error("[WorldManager] Unknown worldId: " .. tostring(worldId))
    end

    local result = {}

    for _, coord in ipairs(coordsList) do
        local key
        if type(coord) == "string" then
            key = coord
        elseif type(coord) == "table" then
            key = coord.cx .. "," .. coord.cz
        else
            key = tostring(coord)
        end

        local chunk = world.chunks[key]
        if chunk then
            result[key] = chunk
        end
    end

    return result
end

--- Destroy a world and free its memory.
--- @param worldId string
function WorldManager.destroyWorld(worldId)
    if _worlds[worldId] then
        _worlds[worldId] = nil
        stdio.write("[WorldManager] Destroyed " .. worldId .. "\n")
    end
end

--- Get the global data for a world (for late-join scenarios).
--- @param worldId string
--- @return table? global
function WorldManager.getGlobal(worldId)
    local world = _worlds[worldId]
    return world and world.global
end

return WorldManager
