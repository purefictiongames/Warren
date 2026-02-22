--[[
    MapGen Pool — Pre-built Map Pool Manager

    Two-tier cache for instant map serving:
        L1: In-memory (this module) — instant pop
        L2: Postgres via Registry REST — persists across restarts

    Usage:
        Pool.init({ registryUrl?, registryToken? })
        local mapData = Pool.pull("mountain")  -- instant or nil
        Pool.count("mountain")                 -- current pool size

    Background worker refills the pool as maps are consumed.
    Without registryUrl, operates as memory-only (dev mode).
--]]

local net = require("@lune/net")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

-- pool.lua is inside mapgen/ — go up to lune/ then back into mapgen/init.lua
local MapGen = require("../mapgen")

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local TARGET_PER_BIOME = 3
local BIOMES = { "mountain" }
local REFILL_DELAY = 0.5  -- seconds between background generations

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _pool = {}  -- biome → array of mapData
for _, biome in ipairs(BIOMES) do
    _pool[biome] = {}
end

local _registryUrl = nil   -- nil = memory-only mode
local _registryToken = nil
local _filling = false

--------------------------------------------------------------------------------
-- REGISTRY HTTP HELPERS
--------------------------------------------------------------------------------

local function _registryGet(path)
    if not _registryUrl then return nil end

    local ok, response = pcall(net.request, {
        url = _registryUrl .. path,
        method = "GET",
        headers = { ["Content-Type"] = "application/json" },
    })

    if not ok then
        stdio.write("[Pool] Registry GET failed: " .. tostring(response) .. "\n")
        return nil
    end

    if not response.ok then
        stdio.write("[Pool] Registry GET " .. path .. " → " .. tostring(response.statusCode) .. "\n")
        return nil
    end

    return serde.decode("json", response.body)
end

local function _registryPost(path, body)
    if not _registryUrl then return false end

    local ok, response = pcall(net.request, {
        url = _registryUrl .. path,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = serde.encode("json", body),
    })

    if not ok then
        stdio.write("[Pool] Registry POST failed: " .. tostring(response) .. "\n")
        return false
    end

    if not response.ok then
        stdio.write("[Pool] Registry POST " .. path .. " → " .. tostring(response.statusCode) .. "\n")
        return false
    end

    return true
end

--------------------------------------------------------------------------------
-- INTERNAL
--------------------------------------------------------------------------------

local function _loadFromRegistry(biomeName, limit)
    local data = _registryGet("/v1/pool/load/" .. biomeName .. "?limit=" .. tostring(limit))
    if not data or not data.maps then
        return {}
    end
    -- Each entry has { seed, map_data }
    local results = {}
    for _, entry in ipairs(data.maps) do
        local mapData = entry.map_data
        -- Ensure seed is on mapData (Registry stores it separately)
        if mapData and not mapData.seed and entry.seed then
            mapData.seed = entry.seed
        end
        table.insert(results, mapData)
    end
    return results
end

local function _pushToRegistry(biomeName, mapData)
    return _registryPost("/v1/pool/store", {
        biome_name = biomeName,
        seed       = mapData.seed,
        map_data   = mapData,
    })
end

local function _generateOne(biomeName)
    local startTime = os.clock()
    local mapData = MapGen.generate({ biomeName = biomeName })
    local elapsed = os.clock() - startTime
    stdio.write(string.format(
        "[Pool] Generated %s map (seed=%s) in %.2fs\n",
        biomeName, tostring(mapData.seed), elapsed
    ))
    return mapData
end

local function _shortfall(biomeName)
    return TARGET_PER_BIOME - #(_pool[biomeName] or {})
end

--------------------------------------------------------------------------------
-- BACKGROUND REFILL
--------------------------------------------------------------------------------

local function _refillAll()
    if _filling then return end
    _filling = true

    task.spawn(function()
        for _, biomeName in ipairs(BIOMES) do
            while _shortfall(biomeName) > 0 do
                local mapData = _generateOne(biomeName)

                -- Push to memory
                if not _pool[biomeName] then
                    _pool[biomeName] = {}
                end
                table.insert(_pool[biomeName], mapData)

                -- Push to Registry (fire-and-forget)
                _pushToRegistry(biomeName, mapData)

                stdio.write(string.format(
                    "[Pool] %s pool: %d/%d\n",
                    biomeName, #_pool[biomeName], TARGET_PER_BIOME
                ))

                -- Prevent CPU saturation
                if _shortfall(biomeName) > 0 then
                    task.wait(REFILL_DELAY)
                end
            end
        end

        _filling = false
    end)
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

local Pool = {}

--- Initialize the pool.
--- @param opts { registryUrl?: string, registryToken?: string }
function Pool.init(opts)
    opts = opts or {}
    _registryUrl = opts.registryUrl
    _registryToken = opts.registryToken

    -- Hydrate from Registry (Postgres L2)
    if _registryUrl then
        stdio.write("[Pool] Hydrating from Registry: " .. _registryUrl .. "\n")
        for _, biomeName in ipairs(BIOMES) do
            local maps = _loadFromRegistry(biomeName, TARGET_PER_BIOME)
            _pool[biomeName] = maps
            stdio.write(string.format(
                "[Pool] Loaded %d %s maps from Registry\n",
                #maps, biomeName
            ))
        end
    else
        stdio.write("[Pool] Memory-only mode (no WARREN_REGISTRY_URL)\n")
    end

    -- Fill any shortfall in background
    _refillAll()
end

--- Pop a map from the pool. Returns mapData or nil.
--- Triggers background refill after each pop.
function Pool.pull(biomeName)
    local biomePool = _pool[biomeName]
    if not biomePool or #biomePool == 0 then
        return nil
    end

    -- FIFO: remove from front
    local mapData = table.remove(biomePool, 1)

    stdio.write(string.format(
        "[Pool] Served %s map (seed=%s), %d remaining\n",
        biomeName, tostring(mapData.seed), #biomePool
    ))

    -- Trigger background refill
    _refillAll()

    return mapData
end

--- Current pool size for a biome.
function Pool.count(biomeName)
    return #(_pool[biomeName] or {})
end

return Pool
