--[[
    LibPureFiction Framework v2
    RoomBlocker.lua - Incremental Room Geometry Builder

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Works with PathGraph to build room geometry one segment at a time.
    This module is the collision authority - it decides if geometry fits.

    Flow:
    1. Receive segment from PathGraph (fromPos, toPos)
    2. Build FROM room if not already built
    3. Check if TO room would overlap existing geometry
    4. If OK: build TO room and hallway, report ok
    5. If NOT OK: report overlap amount (PathGraph will adjust and retry)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit, hallScale, heightScale, ... })
        onSegment({ fromPointId, toPointId, fromPos, toPos, direction })
        onClear()

    OUT (emits):
        segmentResult({ ok: bool, overlapAmount?: number })
        built({ totalParts })

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- ROOMBLOCKER NODE
--------------------------------------------------------------------------------

local RoomBlocker = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    baseUnit = 15,
                    hallScale = 1,
                    heightScale = 2,
                    -- Size ranges for variation (min, max multipliers of baseUnit)
                    roomSizeRange = { 1.2, 2.0 },
                    hallSizeRange = { 0.6, 1.0 },
                    heightRange = { 1.5, 2.5 },
                },

                rng = nil,

                container = nil,
                parts = {},

                -- AABB registry: { minX, minY, minZ, maxX, maxY, maxZ, pointId?, type }
                placedAABBs = {},

                -- Track built points: { [pointId] = { size, height } }
                builtPoints = {},

                -- Track built segments
                builtSegments = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- RNG (mirrors PathGraph's RNG for consistency)
    ----------------------------------------------------------------------------

    local function createRNG(seed)
        local rngState
        if type(seed) == "string" then
            rngState = 0
            for i = 1, #seed do
                rngState = rngState + seed:byte(i) * (i * 31)
            end
            rngState = bit32.band(rngState, 0xFFFFFFFF)
            if rngState == 0 then rngState = 1 end
        else
            rngState = seed or os.time()
            if rngState == 0 then rngState = 1 end
        end

        local rng = {}

        function rng:next()
            rngState = bit32.bxor(rngState, bit32.lshift(rngState, 13))
            rngState = bit32.bxor(rngState, bit32.rshift(rngState, 17))
            rngState = bit32.bxor(rngState, bit32.lshift(rngState, 5))
            rngState = bit32.band(rngState, 0xFFFFFFFF)
            return rngState
        end

        function rng:randomFloat(min, max)
            local val = self:next() / 0xFFFFFFFF
            return min + val * (max - min)
        end

        return rng
    end

    ----------------------------------------------------------------------------
    -- AABB UTILITIES
    ----------------------------------------------------------------------------

    local function createAABB(centerX, centerY, centerZ, sizeX, sizeY, sizeZ)
        return {
            minX = centerX - sizeX / 2,
            minY = centerY - sizeY / 2,
            minZ = centerZ - sizeZ / 2,
            maxX = centerX + sizeX / 2,
            maxY = centerY + sizeY / 2,
            maxZ = centerZ + sizeZ / 2,
        }
    end

    --[[
        Check if two AABBs overlap. Returns overlap amount or nil.
    --]]
    local function getOverlapAmount(a, b)
        -- No overlap if separated on any axis
        if a.maxX <= b.minX or a.minX >= b.maxX then return nil end
        if a.maxY <= b.minY or a.minY >= b.maxY then return nil end
        if a.maxZ <= b.minZ or a.minZ >= b.maxZ then return nil end

        -- Calculate penetration on each axis
        local overlapX = math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX)
        local overlapY = math.min(a.maxY, b.maxY) - math.max(a.minY, b.minY)
        local overlapZ = math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ)

        -- Return minimum overlap on any axis (the push distance needed)
        return math.min(overlapX, overlapY, overlapZ)
    end

    --[[
        Check new AABB against all placed geometry.
        Returns max overlap amount or 0 if no overlap.
    --]]
    local function checkOverlap(self, newAABB, excludePointId)
        local state = getState(self)
        local maxOverlap = 0

        for _, placed in ipairs(state.placedAABBs) do
            if placed.pointId ~= excludePointId then
                local overlap = getOverlapAmount(newAABB, placed)
                if overlap and overlap > maxOverlap then
                    maxOverlap = overlap
                end
            end
        end

        return maxOverlap
    end

    ----------------------------------------------------------------------------
    -- ROOM SIZING (with random variation)
    ----------------------------------------------------------------------------

    local function getRandomRoomSize(self)
        local state = getState(self)
        local config = state.config
        local rng = state.rng
        local range = config.roomSizeRange

        local scale = rng:randomFloat(range[1], range[2])
        return config.baseUnit * scale
    end

    local function getRandomHallSize(self)
        local state = getState(self)
        local config = state.config
        local rng = state.rng
        local range = config.hallSizeRange

        local scale = rng:randomFloat(range[1], range[2])
        return config.baseUnit * scale
    end

    local function getRandomHeight(self)
        local state = getState(self)
        local config = state.config
        local rng = state.rng
        local range = config.heightRange

        local scale = rng:randomFloat(range[1], range[2])
        return config.baseUnit * scale
    end

    ----------------------------------------------------------------------------
    -- GEOMETRY CREATION
    ----------------------------------------------------------------------------

    local function createRoomPart(self, pointId, pos, size, height)
        local state = getState(self)

        local room = Instance.new("Part")
        room.Name = "Room_" .. pointId
        room.Size = Vector3.new(size, height, size)
        room.Position = Vector3.new(pos[1], pos[2] + height / 2, pos[3])
        room.Anchored = true
        room.CanCollide = true
        room.Material = Enum.Material.SmoothPlastic
        room.Transparency = 0.3
        room.Color = Color3.fromRGB(120, 120, 140)
        room.Parent = state.container

        table.insert(state.parts, room)

        -- Register AABB
        local aabb = createAABB(pos[1], pos[2] + height / 2, pos[3], size, height, size)
        aabb.pointId = pointId
        aabb.type = "room"
        table.insert(state.placedAABBs, aabb)

        -- Track built point
        state.builtPoints[pointId] = { size = size, height = height }

        return room
    end

    local function createHallwayPart(self, segmentKey, fromPos, toPos)
        local state = getState(self)

        local dx = toPos[1] - fromPos[1]
        local dy = toPos[2] - fromPos[2]
        local dz = toPos[3] - fromPos[3]

        local length = math.sqrt(dx*dx + dy*dy + dz*dz)
        if length < 1 then return nil end

        local midX = (fromPos[1] + toPos[1]) / 2
        local midY = (fromPos[2] + toPos[2]) / 2
        local midZ = (fromPos[3] + toPos[3]) / 2

        -- Random hall dimensions
        local hallSize = getRandomHallSize(self)
        local hallHeight = getRandomHeight(self) * 0.8

        local sizeX, sizeY, sizeZ
        local isVertical = false

        if math.abs(dx) > math.abs(dz) and math.abs(dx) > math.abs(dy) then
            -- East/West hallway
            sizeX = math.abs(dx)
            sizeY = hallHeight
            sizeZ = hallSize
        elseif math.abs(dz) > math.abs(dy) then
            -- North/South hallway
            sizeX = hallSize
            sizeY = hallHeight
            sizeZ = math.abs(dz)
        else
            -- Vertical shaft
            isVertical = true
            sizeX = hallSize
            sizeY = math.abs(dy)
            sizeZ = hallSize
        end

        local posY = midY + hallHeight / 2

        local hall = Instance.new("Part")
        hall.Name = (isVertical and "Shaft_" or "Hall_") .. segmentKey
        hall.Size = Vector3.new(sizeX, sizeY, sizeZ)
        hall.Position = Vector3.new(midX, posY, midZ)
        hall.Anchored = true
        hall.CanCollide = true
        hall.Material = Enum.Material.SmoothPlastic
        hall.Color = Color3.fromRGB(100, 100, 120)
        hall.Transparency = 0.3
        hall.Parent = state.container

        table.insert(state.parts, hall)

        -- Register hallway AABB
        local aabb = createAABB(midX, posY, midZ, sizeX, sizeY, sizeZ)
        aabb.type = "hall"
        table.insert(state.placedAABBs, aabb)

        state.builtSegments[segmentKey] = true

        return hall
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "RoomBlocker",
        domain = "server",

        Sys = {
            onInit = function(self)
                local _ = getState(self)
            end,

            onStart = function(self)
            end,

            onStop = function(self)
                local state = getState(self)
                for _, part in ipairs(state.parts) do
                    if part and part.Parent then
                        part:Destroy()
                    end
                end
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)
                local config = state.config

                if data.baseUnit then config.baseUnit = data.baseUnit end
                if data.hallScale then config.hallScale = data.hallScale end
                if data.heightScale then config.heightScale = data.heightScale end
                if data.roomSizeRange then config.roomSizeRange = data.roomSizeRange end
                if data.hallSizeRange then config.hallSizeRange = data.hallSizeRange end
                if data.heightRange then config.heightRange = data.heightRange end

                if data.container then
                    state.container = data.container
                end

                -- Initialize RNG (use seed if provided, otherwise use a default)
                local seed = data.seed or "roomblocker"
                state.rng = createRNG(seed)
            end,

            --[[
                Receive a segment from PathGraph.
                Build FROM room if needed, check TO room for overlap.
            --]]
            onSegment = function(self, data)
                local state = getState(self)

                if not data then
                    self.Out:Fire("segmentResult", { ok = false, overlapAmount = 0 })
                    return
                end

                -- Initialize RNG if not already done (fallback)
                if not state.rng then
                    state.rng = createRNG("roomblocker")
                end

                local fromPointId = data.fromPointId
                local toPointId = data.toPointId
                local fromPos = data.fromPos
                local toPos = data.toPos

                -- STEP 1: Build FROM room if not already built
                if not state.builtPoints[fromPointId] then
                    local fromSize = getRandomRoomSize(self)
                    local fromHeight = getRandomHeight(self)
                    print(string.format("[RoomBlocker] Building FROM room %d (%.1fx%.1f) at %.1f, %.1f, %.1f",
                        fromPointId, fromSize, fromHeight, fromPos[1], fromPos[2], fromPos[3]))
                    createRoomPart(self, fromPointId, fromPos, fromSize, fromHeight)
                end

                -- STEP 2: Check if TO room would overlap (use random size for checking)
                local toSize = getRandomRoomSize(self)
                local toHeight = getRandomHeight(self)
                local toAABB = createAABB(toPos[1], toPos[2] + toHeight / 2, toPos[3], toSize, toHeight, toSize)
                local overlapAmount = checkOverlap(self, toAABB, fromPointId)

                if overlapAmount > 0 then
                    -- Overlap detected - need to re-roll size on retry
                    print(string.format("[RoomBlocker] OVERLAP: %.1f studs at point %d (%.1f, %.1f, %.1f)",
                        overlapAmount, toPointId, toPos[1], toPos[2], toPos[3]))

                    self.Out:Fire("segmentResult", {
                        ok = false,
                        overlapAmount = overlapAmount,
                    })
                else
                    -- No overlap - build geometry with the size we checked
                    print(string.format("[RoomBlocker] OK - building TO room %d (%.1fx%.1f) at %.1f, %.1f, %.1f",
                        toPointId, toSize, toHeight, toPos[1], toPos[2], toPos[3]))

                    createRoomPart(self, toPointId, toPos, toSize, toHeight)

                    local segmentKey = fromPointId .. "_" .. toPointId
                    if not state.builtSegments[segmentKey] then
                        createHallwayPart(self, segmentKey, fromPos, toPos)
                    end

                    self.Out:Fire("segmentResult", { ok = true })
                    self.Out:Fire("built", { totalParts = #state.parts })
                end
            end,

            onClear = function(self)
                local state = getState(self)

                for _, part in ipairs(state.parts) do
                    if part and part.Parent then
                        part:Destroy()
                    end
                end

                state.parts = {}
                state.placedAABBs = {}
                state.builtPoints = {}
                state.builtSegments = {}

                self.Out:Fire("cleared", {})
            end,
        },

        Out = {
            segmentResult = {},
            built = {},
            cleared = {},
        },

        getContainer = function(self)
            local state = getState(self)
            return state.container
        end,

        getBuiltPoints = function(self)
            local state = getState(self)
            return state.builtPoints
        end,
    }
end)

return RoomBlocker
