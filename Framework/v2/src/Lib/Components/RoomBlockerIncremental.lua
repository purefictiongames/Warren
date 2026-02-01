--[[
    LibPureFiction Framework v2
    RoomBlockerIncremental.lua - Incremental Room Geometry Builder

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Works with PathGraphIncremental to build room geometry one segment at a time.
    Detects overlaps and reports back to PathGraph for resolution.

    Key architecture:
    - Receives one segment at a time from PathGraph
    - Builds FROM room first (if not already built)
    - Checks if TO room would overlap with existing geometry
    - If overlap: reports overlap amount to PathGraph (PathGraph will shift points)
    - If OK: builds TO room and hallway

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ hallScale, heightScale, roomScale, junctionScale, container })
        onSegment({ segmentId, fromPointId, toPointId, fromPos, toPos, direction, length })
        onClear()

    OUT (emits):
        segmentResult({ ok: bool, overlapAmount?: number })
        built({ totalParts })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- ROOMBLOCKER INCREMENTAL NODE
--------------------------------------------------------------------------------

local RoomBlockerIncremental = Node.extend(function(parent)
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
                    roomScale = 1.5,
                    junctionScale = 2,
                    corridorScale = 1,
                    junctionHeightMult = 1.5,
                    corridorHeightMult = 0.8,
                    hallHeightMult = 1.0,
                },

                container = nil,
                parts = {},

                -- AABB registry for overlap detection
                -- { minX, minY, minZ, maxX, maxY, maxZ, pointId, type }
                placedAABBs = {},

                -- Track which points have rooms
                builtPoints = {}, -- { [pointId] = true }

                -- Track segments we've built
                builtSegments = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
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
        -- Check if they overlap at all
        if a.maxX <= b.minX or a.minX >= b.maxX then return nil end
        if a.maxY <= b.minY or a.minY >= b.maxY then return nil end
        if a.maxZ <= b.minZ or a.minZ >= b.maxZ then return nil end

        -- Calculate overlap on each axis
        local overlapX = math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX)
        local overlapZ = math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ)

        -- Return the minimum horizontal overlap (the push needed to separate)
        return math.min(overlapX, overlapZ)
    end

    --[[
        Check new AABB against all placed geometry.
        Returns total overlap amount or 0 if no overlap.
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
    -- ROOM SIZING
    ----------------------------------------------------------------------------

    local function getRoomSize(self, connectionCount)
        local state = getState(self)
        local config = state.config
        local baseUnit = config.baseUnit

        local scale
        if connectionCount >= 3 then
            scale = config.junctionScale
        elseif connectionCount == 1 then
            scale = config.roomScale
        else
            scale = config.corridorScale
        end

        return baseUnit * scale
    end

    local function getRoomHeight(self, connectionCount)
        local state = getState(self)
        local config = state.config
        local baseUnit = config.baseUnit

        local mult
        if connectionCount >= 3 then
            mult = config.junctionHeightMult
        elseif connectionCount == 1 then
            mult = 1.0
        else
            mult = config.corridorHeightMult
        end

        return baseUnit * config.heightScale * mult
    end

    ----------------------------------------------------------------------------
    -- GEOMETRY CREATION
    ----------------------------------------------------------------------------

    local function createRoomPart(self, pointId, pos, connectionCount)
        local state = getState(self)

        local size = getRoomSize(self, connectionCount)
        local height = getRoomHeight(self, connectionCount)

        local room = Instance.new("Part")
        room.Name = "Room_" .. pointId
        room.Size = Vector3.new(size, height, size)
        room.Position = Vector3.new(pos[1], pos[2] + height / 2, pos[3])
        room.Anchored = true
        room.CanCollide = true
        room.Material = Enum.Material.SmoothPlastic
        room.Transparency = 0.3

        -- Color by connection count
        if connectionCount >= 3 then
            room.Color = Color3.fromRGB(150, 150, 200) -- Junction - blue
        elseif connectionCount == 1 then
            room.Color = Color3.fromRGB(200, 100, 100) -- Dead end - red
        else
            room.Color = Color3.fromRGB(120, 120, 140) -- Corridor - gray
        end

        room.Parent = state.container
        table.insert(state.parts, room)

        -- Register AABB
        local aabb = createAABB(pos[1], pos[2] + height / 2, pos[3], size, height, size)
        aabb.pointId = pointId
        aabb.type = "room"
        table.insert(state.placedAABBs, aabb)

        state.builtPoints[pointId] = true

        return room, size, height
    end

    local function createHallwayPart(self, segmentId, fromPos, toPos)
        local state = getState(self)
        local config = state.config
        local baseUnit = config.baseUnit

        local dx = toPos[1] - fromPos[1]
        local dy = toPos[2] - fromPos[2]
        local dz = toPos[3] - fromPos[3]

        local length = math.abs(dx) + math.abs(dy) + math.abs(dz)
        if length < 1 then return nil end

        local midX = (fromPos[1] + toPos[1]) / 2
        local midY = (fromPos[2] + toPos[2]) / 2
        local midZ = (fromPos[3] + toPos[3]) / 2

        local hallSize = baseUnit * config.hallScale
        local height = baseUnit * config.heightScale * config.hallHeightMult

        local sizeX, sizeY, sizeZ
        local posY
        local isVertical = false

        if math.abs(dx) > 0.1 then
            -- East/West hallway
            sizeX = length
            sizeY = height
            sizeZ = hallSize
            posY = math.min(fromPos[2], toPos[2]) + height / 2
        elseif math.abs(dz) > 0.1 then
            -- North/South hallway
            sizeX = hallSize
            sizeY = height
            sizeZ = length
            posY = math.min(fromPos[2], toPos[2]) + height / 2
        else
            -- Up/Down vertical shaft
            isVertical = true
            sizeX = hallSize
            sizeY = math.abs(dy)
            sizeZ = hallSize
            posY = midY
        end

        local hall = Instance.new("Part")
        hall.Name = (isVertical and "Shaft_" or "Hall_") .. segmentId
        hall.Size = Vector3.new(sizeX, sizeY, sizeZ)
        hall.Position = Vector3.new(midX, posY, midZ)
        hall.Anchored = true
        hall.CanCollide = true
        hall.Material = Enum.Material.SmoothPlastic
        hall.Color = isVertical and Color3.fromRGB(80, 120, 100) or Color3.fromRGB(100, 100, 120)
        hall.Transparency = 0.3
        hall.Parent = state.container

        table.insert(state.parts, hall)

        -- Register hallway AABB
        local aabb = createAABB(midX, posY, midZ, sizeX, sizeY, sizeZ)
        aabb.segmentId = segmentId
        aabb.type = "hall"
        table.insert(state.placedAABBs, aabb)

        state.builtSegments[segmentId] = true

        return hall
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "RoomBlockerIncremental",
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
                if data.roomScale then config.roomScale = data.roomScale end
                if data.junctionScale then config.junctionScale = data.junctionScale end
                if data.corridorScale then config.corridorScale = data.corridorScale end
                if data.junctionHeightMult then config.junctionHeightMult = data.junctionHeightMult end
                if data.corridorHeightMult then config.corridorHeightMult = data.corridorHeightMult end
                if data.hallHeightMult then config.hallHeightMult = data.hallHeightMult end

                if data.container then
                    state.container = data.container
                end
            end,

            --[[
                Receive a segment from PathGraph.
                Build FROM room first, check TO room for overlap, report result.
            --]]
            onSegment = function(self, data)
                local state = getState(self)

                if not data then
                    self.Out:Fire("segmentResult", { ok = false, overlapAmount = 0 })
                    return
                end

                local toPointId = data.toPointId
                local toPos = data.toPos
                local fromPointId = data.fromPointId
                local fromPos = data.fromPos

                -- Assume 2 connections for corridor sizing
                local connectionCount = 2

                -- STEP 1: Build FROM room first (if not already built)
                if not state.builtPoints[fromPointId] then
                    print("[RoomBlocker] Building FROM room", fromPointId)
                    createRoomPart(self, fromPointId, fromPos, connectionCount)
                end

                -- STEP 2: Calculate TO room AABB and check for overlap
                local size = getRoomSize(self, connectionCount)
                local height = getRoomHeight(self, connectionCount)
                local newAABB = createAABB(toPos[1], toPos[2] + height / 2, toPos[3], size, height, size)

                -- Check overlap against all geometry EXCEPT the FROM room (hallway connects them)
                local overlapAmount = checkOverlap(self, newAABB, fromPointId)

                if overlapAmount > 0 then
                    -- Overlap detected - report to PathGraph
                    print("[RoomBlocker] OVERLAP:", overlapAmount, "studs at point", toPointId,
                        "pos:", toPos[1], toPos[2], toPos[3])
                    self.Out:Fire("segmentResult", {
                        ok = false,
                        overlapAmount = overlapAmount,
                    })
                else
                    -- No overlap - build geometry
                    print("[RoomBlocker] OK - building TO room", toPointId)

                    if not state.builtPoints[toPointId] then
                        createRoomPart(self, toPointId, toPos, connectionCount)
                    end

                    if not state.builtSegments[data.segmentId] then
                        createHallwayPart(self, data.segmentId, fromPos, toPos)
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
            segmentResult = {}, -- { ok, overlapAmount? }
            built = {},         -- { totalParts }
            cleared = {},
        },

        getContainer = function(self)
            local state = getState(self)
            return state.container
        end,
    }
end)

return RoomBlockerIncremental
