--[[
    MapGen — Lune Adapter (VPS Map Compute)

    Thin adapter that requires the actual game pipeline nodes and calls
    their handlers with mock self objects. One codebase, different run targets.

    MapGen.generate(params) -> map data table

    Polyfills math.noise via Perlin.lua before requiring any nodes, so the
    same height field code runs on both Roblox (math.noise) and Lune (Perlin).
--]]

--------------------------------------------------------------------------------
-- POLYFILLS (must be set before requiring nodes that capture globals)
--------------------------------------------------------------------------------

-- NOTE: Lune's init.lua resolves ./ to the PARENT directory, not its own.
-- So from mapgen/init.lua, siblings require ./mapgen/X, not ./X.
local Perlin = require("./mapgen/Perlin")

-- math.noise doesn't exist in Lune (and math is frozen, can't polyfill).
-- Pass Perlin.noise2d via opts.noise to computeHeightField instead.

-- Random polyfill (Roblox built-in, not available in Lune)
if not Random then
    local RandomMT = {}
    RandomMT.__index = RandomMT

    function RandomMT:NextNumber(min, max)
        -- LCG: same constants as glibc
        self._s = (self._s * 1103515245 + 12345) % 2147483648
        local t = self._s / 2147483648  -- [0, 1)
        if min and max then
            return min + t * (max - min)
        end
        return t
    end

    function RandomMT:NextInteger(min, max)
        return math.floor(self:NextNumber(min, max + 0.9999999))
    end

    Random = {  -- luacheck: ignore
        new = function(seed)
            return setmetatable({ _s = (seed or os.clock() * 1000) % 2147483648 }, RandomMT)
        end,
    }
end

--------------------------------------------------------------------------------
-- PURE MODULES (no Warren dependency — safe to require before setting global)
--------------------------------------------------------------------------------

local ClassResolver    = require("../../warren/src/ClassResolver")
local BiomeInventory   = require("../../../../Games/igw/src/BiomeInventory")

--------------------------------------------------------------------------------
-- MOCK DOM (lightweight stand-in for Warren's Dom module)
-- Room placer and door planner create DOM nodes; we mock them as plain tables.
--------------------------------------------------------------------------------

local _mockRoot = nil
local mockDom = {
    createElement = function(_, props)
        return { _props = props or {}, _children = {} }
    end,
    appendChild = function(parent, child)
        table.insert(parent._children, child)
    end,
    getChildren = function(node)
        return node._children or {}
    end,
    getAttribute = function(node, key)
        return node._props and node._props[key]
    end,
    setAttribute = function(node, key, val)
        if node._props then node._props[key] = val end
    end,
    setRoot = function(node)
        _mockRoot = node
    end,
    getRoot = function()
        return _mockRoot
    end,
}

--------------------------------------------------------------------------------
-- WARREN GLOBAL (nodes reference Warren.Dom, Warren.ClassResolver, etc.)
-- Must be set BEFORE requiring game nodes that use these at handler call time.
--------------------------------------------------------------------------------

_G.Warren = {
    Dom = mockDom,
    ClassResolver = ClassResolver,
    Styles = {},
    System = {
        BiomeInventory = BiomeInventory,
    },
}

--------------------------------------------------------------------------------
-- REQUIRE ACTUAL GAME FILES (one codebase, different run targets)
-- Paths are relative to parent dir (lune/) due to init.lua resolution.
--------------------------------------------------------------------------------

local InventoryNode    = require("../../../../Games/igw/src/Pipeline/InventoryNode")
local SplinePlannerNode = require("../../../../Games/igw/src/Pipeline/SplinePlannerNode")
local TerrainPainterNode = require("../../../../Games/igw/src/Pipeline/TerrainPainterNode")
local MountainRoomPlacer = require("../../../../Games/igw/src/Pipeline/MountainRoomPlacer")
local DoorPlannerNode    = require("../../../../Games/igw/src/Pipeline/DoorPlanner")

--------------------------------------------------------------------------------
-- MOCK SELF BUILDER
-- Each node handler expects `self` with getAttribute and Out:Fire.
-- Warren modules are accessed via the _G.Warren global (not self._System).
--------------------------------------------------------------------------------

local function makeMockSelf(attrs)
    return {
        getAttribute = function(_, key)
            return attrs[key]
        end,
        Out = { Fire = function() end },
    }
end

--------------------------------------------------------------------------------
-- DEFAULTS (mirrors metadata.lua per-node configs)
--------------------------------------------------------------------------------

local DEFAULTS = {
    biomeName      = "mountain",
    mapWidth       = 4000,
    mapDepth       = 4000,
    origin         = { 0, 0, 0 },
    groundY        = 0,
    noiseAmplitude = 50,
    noiseScale1    = 400,
    noiseScale2    = 160,
    noiseRatio     = 0.65,
    burialFrac     = 0.5,
    maxRooms       = 800,
    downwardBias   = 50,
    scaleRange     = { min = 4, max = 10, minY = 4, maxY = 7 },
    baseUnit       = 10,
    wallThickness  = 2,
    doorSize       = 24,
}

local function withDefaults(params)
    local result = {}
    for k, v in pairs(DEFAULTS) do
        result[k] = v
    end
    if params then
        for k, v in pairs(params) do
            result[k] = v
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- GENERATE
--------------------------------------------------------------------------------

local MapGen = {}

function MapGen.generate(params)
    params = withDefaults(params)

    local seed = params.seed or (os.time() + math.random(1, 9999))
    local startTime = os.clock()

    print(string.format(
        "[MapGen] Generating: biome=%s seed=%d map=%dx%d",
        params.biomeName, seed, params.mapWidth, params.mapDepth
    ))

    -- Shared payload (Houdini blackboard pattern — same as Roblox pipeline)
    local payload = {
        biomeName = params.biomeName,
        seed = seed,
    }

    --------------------------------------------------------------------
    -- 1. Inventory: resolve biome config + roll feature counts
    --------------------------------------------------------------------

    local invSelf = makeMockSelf({})

    InventoryNode.In.onBuildInventory(invSelf, payload)
    -- payload now has: .biomeConfig, .inventory

    --------------------------------------------------------------------
    -- 2. Spline planning: ridges, valleys, point features
    --------------------------------------------------------------------

    local splineSelf = makeMockSelf({
        mapWidth = params.mapWidth,
        mapDepth = params.mapDepth,
        origin   = params.origin,
    })

    SplinePlannerNode.In.onPlanSplines(splineSelf, payload)
    -- payload now has: .splines

    --------------------------------------------------------------------
    -- 3. Height field: pure math (uses exposed computeHeightField)
    --    Not sent over RPC — deterministic from seed + splines + biomeConfig.
    --    Computed here only because RoomPlacer needs it for terrain-following.
    --------------------------------------------------------------------

    local hfResult = TerrainPainterNode.computeHeightField(
        payload.splines,
        payload.biomeConfig,
        {
            mapWidth       = params.mapWidth,
            mapDepth       = params.mapDepth,
            groundY        = params.groundY,
            noiseAmplitude = params.noiseAmplitude,
            noiseScale1    = params.noiseScale1,
            noiseScale2    = params.noiseScale2,
            noiseRatio     = params.noiseRatio,
            seed           = seed,
            noise          = Perlin.noise2d,
            -- No yield on Lune (no frame budget to respect)
        }
    )

    -- Store on payload for RoomPlacer
    payload.heightField      = hfResult.heightField
    payload.heightFieldGridW = hfResult.gridW
    payload.heightFieldGridD = hfResult.gridD
    payload.heightFieldMinX  = hfResult.mapMinX
    payload.heightFieldMinZ  = hfResult.mapMinZ

    --------------------------------------------------------------------
    -- 4. Room placement: BFS flood-fill on terrain
    --------------------------------------------------------------------

    -- DOM root for room models (mock — shared via mockDom.getRoot())
    mockDom.setRoot(mockDom.createElement("Model", { Name = "Root" }))

    local roomSelf = makeMockSelf({
        burialFrac    = params.burialFrac,
        downwardBias  = params.downwardBias,
        maxRooms      = params.maxRooms,
        scaleRange    = params.scaleRange,
        groundY       = params.groundY,
        baseUnit      = params.baseUnit,
        wallThickness = params.wallThickness,
        doorSize      = params.doorSize,
    })

    MountainRoomPlacer.In.onPlaceRooms(roomSelf, payload)
    -- payload now has: .rooms, .roomOrder, .portalAssignments, .doors, .spawn

    --------------------------------------------------------------------
    -- 5. Door planning (phase 1 only — geometry, no CSG)
    --------------------------------------------------------------------

    local doorSelf = makeMockSelf({
        wallThickness = params.wallThickness,
        doorSize      = params.doorSize,
    })

    DoorPlannerNode.In.onPlanDoors(doorSelf, payload)
    -- payload now has: .doors (with planned positions)

    --------------------------------------------------------------------
    -- Result
    --------------------------------------------------------------------

    local elapsed = os.clock() - startTime

    local roomCount = 0
    if payload.rooms then
        for _ in pairs(payload.rooms) do roomCount = roomCount + 1 end
    end

    print(string.format(
        "[MapGen] Complete: %d splines, %d rooms, %d doors (%.2fs)",
        payload.splines and #payload.splines or 0,
        roomCount,
        payload.doors and #payload.doors or 0,
        elapsed
    ))

    -- Return everything EXCEPT heightField (regenerated locally on Roblox)
    return {
        seed        = seed,  -- pool consumers need this to regenerate height field
        biomeConfig = payload.biomeConfig,
        inventory   = payload.inventory,
        splines     = payload.splines,
        -- heightField omitted — deterministic from seed + splines + biomeConfig
        maxH        = hfResult.maxH,
        rooms       = payload.rooms,
        roomOrder   = payload.roomOrder,
        doors       = payload.doors,
        spawn       = payload.spawn or hfResult.spawn,
    }
end

return MapGen
