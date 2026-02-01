--[[
    LibPureFiction Framework v2
    ClusterStrategies.lua - Room Volume Placement Strategies

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Growth-based strategies for placing room volumes. Each strategy uses a
    different algorithm for choosing WHERE to attach new rooms, but all
    guarantee that each room (except the first) adjoins at least one other.

    "Adjoins" means walls touch with enough shared area for a door.

    All strategies return an array of room definitions:
        { position = {x, y, z}, scale = {sx, sy, sz}, attachedTo = parentId }

    Actual dimensions = baseUnit * scale

    ============================================================================
    AVAILABLE STRATEGIES
    ============================================================================

    Grid        - Grows outward preferring cardinal directions
    Poisson     - Random attachment points with even distribution
    BSP         - Alternating axis growth (binary tree pattern)
    Organic     - Random branching with occasional backtracking
    Radial      - Grows outward from center in rings

    ============================================================================
    USAGE
    ============================================================================

    local strategies = require(path.to.ClusterStrategies)
    local rooms = strategies.Poisson.generate(config, rng)

--]]

local ClusterStrategies = {}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- Face definitions: axis index and direction
local FACES = {
    { axis = 1, dir =  1, name = "E" },  -- +X
    { axis = 1, dir = -1, name = "W" },  -- -X
    { axis = 2, dir =  1, name = "U" },  -- +Y (up)
    { axis = 2, dir = -1, name = "D" },  -- -Y (down)
    { axis = 3, dir =  1, name = "N" },  -- +Z
    { axis = 3, dir = -1, name = "S" },  -- -Z
}

-- Horizontal faces only (for most strategies)
local H_FACES = {
    { axis = 1, dir =  1, name = "E" },
    { axis = 1, dir = -1, name = "W" },
    { axis = 3, dir =  1, name = "N" },
    { axis = 3, dir = -1, name = "S" },
}

-- Check if two AABBs overlap (penetrate, not just touch)
local function aabbOverlaps(posA, dimsA, posB, dimsB, margin)
    margin = margin or 0
    for axis = 1, 3 do
        local minA = posA[axis] - dimsA[axis]/2 + margin
        local maxA = posA[axis] + dimsA[axis]/2 - margin
        local minB = posB[axis] - dimsB[axis]/2 + margin
        local maxB = posB[axis] + dimsB[axis]/2 - margin
        if maxA <= minB or minA >= maxB then
            return false
        end
    end
    return true
end

-- Check if a room overlaps (penetrates) any existing room
local function overlapsAny(pos, dims, rooms, margin)
    for _, room in ipairs(rooms) do
        local roomDims = {
            room.scale[1] * room.baseUnit,
            room.scale[2] * room.baseUnit,
            room.scale[3] * room.baseUnit,
        }
        if aabbOverlaps(pos, dims, room.position, roomDims, margin) then
            return true
        end
    end
    return false
end

-- Calculate wall overlap between two touching rooms
-- Returns overlap area on perpendicular axes (for door sizing)
local function calculateWallOverlap(posA, dimsA, posB, dimsB, touchAxis)
    local overlaps = {}
    for axis = 1, 3 do
        if axis ~= touchAxis then
            local minA = posA[axis] - dimsA[axis]/2
            local maxA = posA[axis] + dimsA[axis]/2
            local minB = posB[axis] - dimsB[axis]/2
            local maxB = posB[axis] + dimsB[axis]/2
            local overlapMin = math.max(minA, minB)
            local overlapMax = math.min(maxA, maxB)
            overlaps[axis] = math.max(0, overlapMax - overlapMin)
        end
    end
    return overlaps
end

-- Generate random scale factors within range
local function randomScale(rng, scaleRange)
    return {
        rng:randomInt(scaleRange.min, scaleRange.max),
        rng:randomInt(scaleRange.minY or scaleRange.min, scaleRange.maxY or scaleRange.max),
        rng:randomInt(scaleRange.min, scaleRange.max),
    }
end

-- Shuffle array in place
local function shuffle(arr, rng)
    for i = #arr, 2, -1 do
        local j = rng:randomInt(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

-- Try to attach a new room to a parent room on a specific face
-- Returns position if successful, nil if would overlap
local function tryAttachRoom(parentRoom, newScale, face, rooms, baseUnit, minDoorSize, wallThickness, rng)
    local parentPos = parentRoom.position
    local parentDims = {
        parentRoom.scale[1] * baseUnit,
        parentRoom.scale[2] * baseUnit,
        parentRoom.scale[3] * baseUnit,
    }
    local newDims = {
        newScale[1] * baseUnit,
        newScale[2] * baseUnit,
        newScale[3] * baseUnit,
    }

    -- Calculate base position: new room touching parent on this face
    local newPos = { parentPos[1], parentPos[2], parentPos[3] }

    -- Move along touch axis so walls touch
    newPos[face.axis] = parentPos[face.axis] +
        face.dir * (parentDims[face.axis]/2 + newDims[face.axis]/2)

    -- Calculate max offset on perpendicular axes while maintaining door overlap
    for axis = 1, 3 do
        if axis ~= face.axis then
            local parentHalf = parentDims[axis] / 2
            local newHalf = newDims[axis] / 2

            -- Max offset while keeping minDoorSize overlap
            local maxOffset = parentHalf + newHalf - minDoorSize

            if maxOffset > 0 then
                -- Random offset within valid range
                local offset = rng:randomFloat(-maxOffset, maxOffset)
                newPos[axis] = parentPos[axis] + offset
            end
        end
    end

    -- Verify we have enough overlap for a door
    local overlap = calculateWallOverlap(parentPos, parentDims, newPos, newDims, face.axis)
    local minOverlap = math.huge
    for axis, val in pairs(overlap) do
        minOverlap = math.min(minOverlap, val)
    end

    if minOverlap < minDoorSize then
        return nil
    end

    -- Check for overlap with other rooms (skip parent)
    for i, room in ipairs(rooms) do
        if room ~= parentRoom then
            local roomDims = {
                room.scale[1] * baseUnit,
                room.scale[2] * baseUnit,
                room.scale[3] * baseUnit,
            }
            if aabbOverlaps(newPos, newDims, room.position, roomDims, wallThickness) then
                return nil
            end
        end
    end

    return newPos
end

-- Core growth function used by all strategies
-- parentSelector: function(rooms, rng) -> parentRoom, returns which room to attach to
-- faceSelector: function(parentRoom, rng) -> faces table, returns faces to try (in order)
local function growRooms(config, rng, parentSelector, faceSelector)
    local rooms = {}
    local baseUnit = config.baseUnit or 15
    local wallThickness = config.wallThickness or 1
    local minDoorSize = config.minDoorSize or 4
    local scaleRange = config.scaleRange or { min = 2, max = 5, minY = 2, maxY = 4 }
    local maxRooms = config.maxRooms or 25
    local maxAttempts = config.maxAttempts or 50
    local origin = config.origin or { 0, 0, 0 }

    -- First room at origin
    local startScale = randomScale(rng, scaleRange)
    table.insert(rooms, {
        position = { origin[1], origin[2], origin[3] },
        scale = startScale,
        baseUnit = baseUnit,
        attachedTo = nil,
    })

    -- Grow additional rooms
    local attempts = 0
    while #rooms < maxRooms and attempts < maxAttempts * maxRooms do
        attempts = attempts + 1

        -- Select parent room
        local parentRoom, parentIdx = parentSelector(rooms, rng)
        if not parentRoom then break end

        -- Get faces to try
        local faces = faceSelector(parentRoom, rng)

        -- Try to attach on each face
        local newScale = randomScale(rng, scaleRange)

        for _, face in ipairs(faces) do
            local newPos = tryAttachRoom(
                parentRoom, newScale, face, rooms,
                baseUnit, minDoorSize, wallThickness, rng
            )

            if newPos then
                table.insert(rooms, {
                    position = newPos,
                    scale = newScale,
                    baseUnit = baseUnit,
                    attachedTo = parentIdx,
                })
                break
            end
        end
    end

    return rooms
end

--------------------------------------------------------------------------------
-- GRID STRATEGY
--------------------------------------------------------------------------------
-- Grows outward preferring cardinal directions, like a city grid

ClusterStrategies.Grid = {}

function ClusterStrategies.Grid.generate(config, rng)
    -- Prefer rooms on outer edges, cardinal directions
    local function parentSelector(rooms, rng)
        -- Weight toward more recent rooms (outer edge)
        local weights = {}
        local totalWeight = 0
        for i, _ in ipairs(rooms) do
            local weight = i  -- Later rooms have higher weight
            weights[i] = weight
            totalWeight = totalWeight + weight
        end

        local pick = rng:randomFloat(0, totalWeight)
        local cumulative = 0
        for i, weight in ipairs(weights) do
            cumulative = cumulative + weight
            if pick <= cumulative then
                return rooms[i], i
            end
        end
        return rooms[#rooms], #rooms
    end

    local function faceSelector(_, rng)
        -- Shuffle horizontal faces
        local faces = { H_FACES[1], H_FACES[2], H_FACES[3], H_FACES[4] }
        shuffle(faces, rng)
        return faces
    end

    return growRooms(config, rng, parentSelector, faceSelector)
end

--------------------------------------------------------------------------------
-- POISSON STRATEGY
--------------------------------------------------------------------------------
-- Random attachment with even distribution (all rooms equally likely parents)

ClusterStrategies.Poisson = {}

function ClusterStrategies.Poisson.generate(config, rng)
    local function parentSelector(rooms, rng)
        local idx = rng:randomInt(1, #rooms)
        return rooms[idx], idx
    end

    local function faceSelector(_, rng)
        local faces = { H_FACES[1], H_FACES[2], H_FACES[3], H_FACES[4] }
        shuffle(faces, rng)
        return faces
    end

    return growRooms(config, rng, parentSelector, faceSelector)
end

--------------------------------------------------------------------------------
-- BSP STRATEGY
--------------------------------------------------------------------------------
-- Alternating axis growth (binary tree pattern)

ClusterStrategies.BSP = {}

function ClusterStrategies.BSP.generate(config, rng)
    local lastAxis = 1

    local function parentSelector(rooms, rng)
        -- Prefer rooms with fewer children (balanced tree)
        local childCount = {}
        for i = 1, #rooms do childCount[i] = 0 end

        for _, room in ipairs(rooms) do
            if room.attachedTo then
                childCount[room.attachedTo] = childCount[room.attachedTo] + 1
            end
        end

        -- Find rooms with minimum children
        local minChildren = math.huge
        for i, count in ipairs(childCount) do
            minChildren = math.min(minChildren, count)
        end

        local candidates = {}
        for i, count in ipairs(childCount) do
            if count == minChildren then
                table.insert(candidates, i)
            end
        end

        local idx = candidates[rng:randomInt(1, #candidates)]
        return rooms[idx], idx
    end

    local function faceSelector(_, rng)
        -- Alternate axis
        lastAxis = (lastAxis == 1) and 3 or 1

        local faces
        if lastAxis == 1 then
            faces = { H_FACES[1], H_FACES[2] }  -- E, W
        else
            faces = { H_FACES[3], H_FACES[4] }  -- N, S
        end
        shuffle(faces, rng)
        return faces
    end

    return growRooms(config, rng, parentSelector, faceSelector)
end

--------------------------------------------------------------------------------
-- ORGANIC STRATEGY
--------------------------------------------------------------------------------
-- Random branching with preference for recent rooms (creates tendrils)

ClusterStrategies.Organic = {}

function ClusterStrategies.Organic.generate(config, rng)
    local function parentSelector(rooms, rng)
        -- Strong preference for recent rooms (branching tendrils)
        -- But occasionally backtrack (30% chance)
        if rng:randomInt(1, 100) <= 30 and #rooms > 3 then
            -- Backtrack to random earlier room
            local idx = rng:randomInt(1, math.max(1, #rooms - 3))
            return rooms[idx], idx
        else
            -- Pick from last few rooms
            local start = math.max(1, #rooms - 2)
            local idx = rng:randomInt(start, #rooms)
            return rooms[idx], idx
        end
    end

    local function faceSelector(_, rng)
        local faces = { H_FACES[1], H_FACES[2], H_FACES[3], H_FACES[4] }
        shuffle(faces, rng)
        return faces
    end

    return growRooms(config, rng, parentSelector, faceSelector)
end

--------------------------------------------------------------------------------
-- RADIAL STRATEGY
--------------------------------------------------------------------------------
-- Grows outward from center in roughly circular pattern

ClusterStrategies.Radial = {}

function ClusterStrategies.Radial.generate(config, rng)
    local origin = config.origin or { 0, 0, 0 }

    local function parentSelector(rooms, rng)
        -- Pick room closest to "outward" edge (furthest from origin)
        -- But with some randomness
        local maxDist = 0
        for _, room in ipairs(rooms) do
            local dx = room.position[1] - origin[1]
            local dz = room.position[3] - origin[3]
            local dist = math.sqrt(dx*dx + dz*dz)
            maxDist = math.max(maxDist, dist)
        end

        -- Find rooms near the outer edge
        local threshold = maxDist * 0.6
        local candidates = {}
        for i, room in ipairs(rooms) do
            local dx = room.position[1] - origin[1]
            local dz = room.position[3] - origin[3]
            local dist = math.sqrt(dx*dx + dz*dz)
            if dist >= threshold or #rooms <= 3 then
                table.insert(candidates, i)
            end
        end

        if #candidates == 0 then
            candidates = {#rooms}
        end

        local idx = candidates[rng:randomInt(1, #candidates)]
        return rooms[idx], idx
    end

    local function faceSelector(parentRoom, rng)
        -- Prefer faces pointing away from origin
        local dx = parentRoom.position[1] - origin[1]
        local dz = parentRoom.position[3] - origin[3]

        local faces = {}

        -- Add faces based on direction from origin
        if dx >= 0 then
            table.insert(faces, H_FACES[1])  -- E (+X)
        end
        if dx <= 0 then
            table.insert(faces, H_FACES[2])  -- W (-X)
        end
        if dz >= 0 then
            table.insert(faces, H_FACES[3])  -- N (+Z)
        end
        if dz <= 0 then
            table.insert(faces, H_FACES[4])  -- S (-Z)
        end

        -- If near center, all faces
        if #faces < 2 then
            faces = { H_FACES[1], H_FACES[2], H_FACES[3], H_FACES[4] }
        end

        shuffle(faces, rng)
        return faces
    end

    return growRooms(config, rng, parentSelector, faceSelector)
end

--------------------------------------------------------------------------------
-- STRATEGY REGISTRY
--------------------------------------------------------------------------------

ClusterStrategies.strategies = {
    Grid = ClusterStrategies.Grid,
    Poisson = ClusterStrategies.Poisson,
    BSP = ClusterStrategies.BSP,
    Organic = ClusterStrategies.Organic,
    Radial = ClusterStrategies.Radial,
}

function ClusterStrategies.get(name)
    return ClusterStrategies.strategies[name]
end

function ClusterStrategies.list()
    local names = {}
    for name, _ in pairs(ClusterStrategies.strategies) do
        table.insert(names, name)
    end
    return names
end

return ClusterStrategies
