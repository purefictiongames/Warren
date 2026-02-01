--[[
    LibPureFiction Framework v2
    ClusterStrategies.lua - Room Volume Placement Strategies

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Pluggable strategies for placing room volumes in space. Each strategy
    implements a different clustering/distribution algorithm.

    All strategies return an array of room definitions:
        { position = {x, y, z}, scale = {sx, sy, sz} }

    Actual dimensions = baseUnit * scale

    ============================================================================
    AVAILABLE STRATEGIES
    ============================================================================

    Grid        - Rooms on a regular grid with random offsets
    Poisson     - Even spacing via Poisson disk sampling
    BSP         - Binary space partitioning (recursive subdivision)
    Organic     - Physics-based settling with repulsion
    Radial      - Rooms radiate outward from center point(s)

    ============================================================================
    USAGE
    ============================================================================

    local strategies = require(path.to.ClusterStrategies)
    local rooms = strategies.Grid.generate(config, rng)

--]]

local ClusterStrategies = {}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- Check if two AABBs overlap (with margin for walls)
local function aabbOverlaps(posA, dimsA, posB, dimsB, margin)
    margin = margin or 0
    local minA = { posA[1] - dimsA[1]/2 - margin, posA[2] - dimsA[2]/2 - margin, posA[3] - dimsA[3]/2 - margin }
    local maxA = { posA[1] + dimsA[1]/2 + margin, posA[2] + dimsA[2]/2 + margin, posA[3] + dimsA[3]/2 + margin }
    local minB = { posB[1] - dimsB[1]/2 - margin, posB[2] - dimsB[2]/2 - margin, posB[3] - dimsB[3]/2 - margin }
    local maxB = { posB[1] + dimsB[1]/2 + margin, posB[2] + dimsB[2]/2 + margin, posB[3] + dimsB[3]/2 + margin }

    if maxA[1] <= minB[1] or minA[1] >= maxB[1] then return false end
    if maxA[2] <= minB[2] or minA[2] >= maxB[2] then return false end
    if maxA[3] <= minB[3] or minA[3] >= maxB[3] then return false end
    return true
end

-- Check if a room overlaps any existing room
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

-- Generate random scale factors within range
local function randomScale(rng, scaleRange)
    return {
        rng:randomInt(scaleRange.min, scaleRange.max),
        rng:randomInt(scaleRange.minY or scaleRange.min, scaleRange.maxY or scaleRange.max),
        rng:randomInt(scaleRange.min, scaleRange.max),
    }
end

--------------------------------------------------------------------------------
-- GRID STRATEGY
--------------------------------------------------------------------------------
-- Places rooms on a regular grid with random offsets and size variation

ClusterStrategies.Grid = {}

function ClusterStrategies.Grid.generate(config, rng)
    local rooms = {}
    local baseUnit = config.baseUnit or 15
    local margin = config.wallThickness or 1

    -- Grid parameters
    local gridSize = config.gridSize or { x = 4, y = 1, z = 4 }
    local gridSpacing = config.gridSpacing or (baseUnit * 4)
    local offsetRange = config.offsetRange or (baseUnit * 1)
    local scaleRange = config.scaleRange or { min = 2, max = 4, minY = 2, maxY = 3 }
    local fillChance = config.fillChance or 70  -- % chance to place room at grid cell

    local origin = config.origin or { 0, 0, 0 }

    for gx = 0, gridSize.x - 1 do
        for gy = 0, gridSize.y - 1 do
            for gz = 0, gridSize.z - 1 do
                -- Random chance to skip this cell
                if rng:randomInt(1, 100) <= fillChance then
                    local scale = randomScale(rng, scaleRange)
                    local dims = {
                        scale[1] * baseUnit,
                        scale[2] * baseUnit,
                        scale[3] * baseUnit,
                    }

                    -- Grid position with random offset
                    local pos = {
                        origin[1] + gx * gridSpacing + rng:randomFloat(-offsetRange, offsetRange),
                        origin[2] + gy * gridSpacing + rng:randomFloat(-offsetRange/2, offsetRange/2),
                        origin[3] + gz * gridSpacing + rng:randomFloat(-offsetRange, offsetRange),
                    }

                    -- Check for overlap with existing rooms
                    if not overlapsAny(pos, dims, rooms, margin * 2) then
                        table.insert(rooms, {
                            position = pos,
                            scale = scale,
                            baseUnit = baseUnit,
                        })
                    end
                end
            end
        end
    end

    return rooms
end

--------------------------------------------------------------------------------
-- POISSON DISK STRATEGY
--------------------------------------------------------------------------------
-- Even spacing via Poisson disk sampling (Bridson's algorithm)

ClusterStrategies.Poisson = {}

function ClusterStrategies.Poisson.generate(config, rng)
    local rooms = {}
    local baseUnit = config.baseUnit or 15
    local margin = config.wallThickness or 1

    local bounds = config.bounds or { x = 200, y = 50, z = 200 }
    local minDist = config.minDistance or (baseUnit * 5)
    local maxAttempts = config.maxAttempts or 30
    local maxRooms = config.maxRooms or 50
    local scaleRange = config.scaleRange or { min = 2, max = 4, minY = 2, maxY = 3 }

    local origin = config.origin or { 0, 0, 0 }

    -- Active list for Bridson's algorithm
    local active = {}

    -- Start with a random point
    local startPos = {
        origin[1] + rng:randomFloat(0, bounds.x),
        origin[2] + rng:randomFloat(0, bounds.y),
        origin[3] + rng:randomFloat(0, bounds.z),
    }
    local startScale = randomScale(rng, scaleRange)

    table.insert(rooms, {
        position = startPos,
        scale = startScale,
        baseUnit = baseUnit,
    })
    table.insert(active, 1)

    while #active > 0 and #rooms < maxRooms do
        -- Pick random active point
        local activeIdx = rng:randomInt(1, #active)
        local roomIdx = active[activeIdx]
        local fromRoom = rooms[roomIdx]
        local fromPos = fromRoom.position

        local found = false

        for _ = 1, maxAttempts do
            -- Generate random point in annulus around fromPos
            local angle1 = rng:randomFloat(0, math.pi * 2)
            local angle2 = rng:randomFloat(-math.pi/4, math.pi/4)  -- Limit vertical spread
            local dist = rng:randomFloat(minDist, minDist * 2)

            local newPos = {
                fromPos[1] + math.cos(angle1) * math.cos(angle2) * dist,
                fromPos[2] + math.sin(angle2) * dist * 0.5,  -- Reduce vertical spread
                fromPos[3] + math.sin(angle1) * math.cos(angle2) * dist,
            }

            -- Check bounds
            if newPos[1] >= origin[1] and newPos[1] <= origin[1] + bounds.x and
               newPos[2] >= origin[2] and newPos[2] <= origin[2] + bounds.y and
               newPos[3] >= origin[3] and newPos[3] <= origin[3] + bounds.z then

                local newScale = randomScale(rng, scaleRange)
                local newDims = {
                    newScale[1] * baseUnit,
                    newScale[2] * baseUnit,
                    newScale[3] * baseUnit,
                }

                -- Check distance from all existing rooms
                local tooClose = false
                for _, room in ipairs(rooms) do
                    local dx = newPos[1] - room.position[1]
                    local dy = newPos[2] - room.position[2]
                    local dz = newPos[3] - room.position[3]
                    local distSq = dx*dx + dy*dy + dz*dz
                    if distSq < minDist * minDist then
                        tooClose = true
                        break
                    end
                end

                if not tooClose and not overlapsAny(newPos, newDims, rooms, margin * 2) then
                    table.insert(rooms, {
                        position = newPos,
                        scale = newScale,
                        baseUnit = baseUnit,
                    })
                    table.insert(active, #rooms)
                    found = true
                    break
                end
            end
        end

        if not found then
            -- Remove from active list
            table.remove(active, activeIdx)
        end
    end

    return rooms
end

--------------------------------------------------------------------------------
-- BSP (Binary Space Partitioning) STRATEGY
--------------------------------------------------------------------------------
-- Recursively subdivide space into rooms

ClusterStrategies.BSP = {}

function ClusterStrategies.BSP.generate(config, rng)
    local rooms = {}
    local baseUnit = config.baseUnit or 15
    local margin = config.wallThickness or 1

    local bounds = config.bounds or { x = 200, y = 50, z = 200 }
    local minSize = config.minRoomSize or (baseUnit * 3)
    local maxDepth = config.maxDepth or 4
    local splitChance = config.splitChance or 80
    local roomChance = config.roomChance or 70

    local origin = config.origin or { 0, 0, 0 }

    local function subdivide(minPos, maxPos, depth)
        local sizeX = maxPos[1] - minPos[1]
        local sizeY = maxPos[2] - minPos[2]
        local sizeZ = maxPos[3] - minPos[3]

        -- Check if we should split further
        local canSplitX = sizeX >= minSize * 2
        local canSplitZ = sizeZ >= minSize * 2
        local canSplitY = sizeY >= minSize * 2 and depth < 2  -- Limit vertical splits

        local shouldSplit = depth < maxDepth and
                           (canSplitX or canSplitZ or canSplitY) and
                           rng:randomInt(1, 100) <= splitChance

        if shouldSplit then
            -- Choose split axis (prefer horizontal)
            local axis
            if canSplitX and canSplitZ then
                axis = rng:randomInt(1, 2) == 1 and 1 or 3
            elseif canSplitX then
                axis = 1
            elseif canSplitZ then
                axis = 3
            elseif canSplitY then
                axis = 2
            else
                shouldSplit = false
            end

            if shouldSplit then
                local splitMin = minPos[axis] + minSize
                local splitMax = maxPos[axis] - minSize
                local splitPos = rng:randomFloat(splitMin, splitMax)

                local minPosA, maxPosA = {minPos[1], minPos[2], minPos[3]}, {maxPos[1], maxPos[2], maxPos[3]}
                local minPosB, maxPosB = {minPos[1], minPos[2], minPos[3]}, {maxPos[1], maxPos[2], maxPos[3]}

                maxPosA[axis] = splitPos
                minPosB[axis] = splitPos

                subdivide(minPosA, maxPosA, depth + 1)
                subdivide(minPosB, maxPosB, depth + 1)
                return
            end
        end

        -- Create room in this cell (with some margin)
        if rng:randomInt(1, 100) <= roomChance then
            local roomMargin = baseUnit
            local roomSizeX = math.max(minSize, sizeX - roomMargin * 2)
            local roomSizeY = math.max(minSize, sizeY - roomMargin * 2)
            local roomSizeZ = math.max(minSize, sizeZ - roomMargin * 2)

            -- Snap to baseUnit
            local scaleX = math.max(2, math.floor(roomSizeX / baseUnit))
            local scaleY = math.max(2, math.floor(roomSizeY / baseUnit))
            local scaleZ = math.max(2, math.floor(roomSizeZ / baseUnit))

            local roomDims = { scaleX * baseUnit, scaleY * baseUnit, scaleZ * baseUnit }

            -- Center room in cell with random offset
            local centerX = (minPos[1] + maxPos[1]) / 2 + rng:randomFloat(-roomMargin/2, roomMargin/2)
            local centerY = (minPos[2] + maxPos[2]) / 2
            local centerZ = (minPos[3] + maxPos[3]) / 2 + rng:randomFloat(-roomMargin/2, roomMargin/2)

            local pos = { centerX, centerY, centerZ }

            if not overlapsAny(pos, roomDims, rooms, margin * 2) then
                table.insert(rooms, {
                    position = pos,
                    scale = { scaleX, scaleY, scaleZ },
                    baseUnit = baseUnit,
                })
            end
        end
    end

    local minPos = { origin[1], origin[2], origin[3] }
    local maxPos = { origin[1] + bounds.x, origin[2] + bounds.y, origin[3] + bounds.z }

    subdivide(minPos, maxPos, 0)

    return rooms
end

--------------------------------------------------------------------------------
-- ORGANIC STRATEGY
--------------------------------------------------------------------------------
-- Physics-based settling with repulsion forces

ClusterStrategies.Organic = {}

function ClusterStrategies.Organic.generate(config, rng)
    local rooms = {}
    local baseUnit = config.baseUnit or 15
    local margin = config.wallThickness or 1

    local numRooms = config.numRooms or 20
    local bounds = config.bounds or { x = 200, y = 50, z = 200 }
    local iterations = config.iterations or 50
    local repulsionStrength = config.repulsionStrength or 2
    local scaleRange = config.scaleRange or { min = 2, max = 4, minY = 2, maxY = 3 }

    local origin = config.origin or { 0, 0, 0 }

    -- Create rooms at random positions
    for _ = 1, numRooms do
        local scale = randomScale(rng, scaleRange)
        local pos = {
            origin[1] + rng:randomFloat(0, bounds.x),
            origin[2] + rng:randomFloat(0, bounds.y),
            origin[3] + rng:randomFloat(0, bounds.z),
        }
        table.insert(rooms, {
            position = pos,
            scale = scale,
            baseUnit = baseUnit,
            velocity = { 0, 0, 0 },
        })
    end

    -- Simulate repulsion
    for _ = 1, iterations do
        -- Calculate forces
        for i, roomA in ipairs(rooms) do
            local force = { 0, 0, 0 }
            local dimsA = {
                roomA.scale[1] * baseUnit,
                roomA.scale[2] * baseUnit,
                roomA.scale[3] * baseUnit,
            }

            for j, roomB in ipairs(rooms) do
                if i ~= j then
                    local dimsB = {
                        roomB.scale[1] * baseUnit,
                        roomB.scale[2] * baseUnit,
                        roomB.scale[3] * baseUnit,
                    }

                    local dx = roomA.position[1] - roomB.position[1]
                    local dy = roomA.position[2] - roomB.position[2]
                    local dz = roomA.position[3] - roomB.position[3]
                    local distSq = dx*dx + dy*dy + dz*dz
                    local dist = math.sqrt(distSq)

                    -- Desired minimum distance
                    local minDist = (dimsA[1] + dimsB[1])/2 + (dimsA[3] + dimsB[3])/2 + margin * 4

                    if dist < minDist and dist > 0.1 then
                        local strength = repulsionStrength * (minDist - dist) / dist
                        force[1] = force[1] + dx * strength
                        force[2] = force[2] + dy * strength * 0.2  -- Reduce vertical force
                        force[3] = force[3] + dz * strength
                    end
                end
            end

            roomA.velocity[1] = roomA.velocity[1] * 0.8 + force[1] * 0.2
            roomA.velocity[2] = roomA.velocity[2] * 0.8 + force[2] * 0.2
            roomA.velocity[3] = roomA.velocity[3] * 0.8 + force[3] * 0.2
        end

        -- Apply velocities
        for _, room in ipairs(rooms) do
            room.position[1] = room.position[1] + room.velocity[1]
            room.position[2] = room.position[2] + room.velocity[2]
            room.position[3] = room.position[3] + room.velocity[3]

            -- Clamp to bounds
            local dims = { room.scale[1] * baseUnit, room.scale[2] * baseUnit, room.scale[3] * baseUnit }
            room.position[1] = math.max(origin[1] + dims[1]/2, math.min(origin[1] + bounds.x - dims[1]/2, room.position[1]))
            room.position[2] = math.max(origin[2] + dims[2]/2, math.min(origin[2] + bounds.y - dims[2]/2, room.position[2]))
            room.position[3] = math.max(origin[3] + dims[3]/2, math.min(origin[3] + bounds.z - dims[3]/2, room.position[3]))
        end
    end

    -- Remove velocity field and check for remaining overlaps
    local validRooms = {}
    for _, room in ipairs(rooms) do
        room.velocity = nil
        local dims = { room.scale[1] * baseUnit, room.scale[2] * baseUnit, room.scale[3] * baseUnit }
        if not overlapsAny(room.position, dims, validRooms, margin * 2) then
            table.insert(validRooms, room)
        end
    end

    return validRooms
end

--------------------------------------------------------------------------------
-- RADIAL STRATEGY
--------------------------------------------------------------------------------
-- Rooms radiate outward from center point(s)

ClusterStrategies.Radial = {}

function ClusterStrategies.Radial.generate(config, rng)
    local rooms = {}
    local baseUnit = config.baseUnit or 15
    local margin = config.wallThickness or 1

    local rings = config.rings or 3
    local roomsPerRing = config.roomsPerRing or 6
    local ringSpacing = config.ringSpacing or (baseUnit * 6)
    local scaleRange = config.scaleRange or { min = 2, max = 4, minY = 2, maxY = 3 }
    local verticalSpread = config.verticalSpread or (baseUnit * 2)

    local origin = config.origin or { 0, 0, 0 }

    -- Center room
    local centerScale = randomScale(rng, scaleRange)
    table.insert(rooms, {
        position = { origin[1], origin[2], origin[3] },
        scale = centerScale,
        baseUnit = baseUnit,
    })

    -- Radiating rings
    for ring = 1, rings do
        local radius = ring * ringSpacing
        local numRooms = roomsPerRing * ring  -- More rooms in outer rings
        local angleOffset = rng:randomFloat(0, math.pi * 2 / numRooms)

        for i = 1, numRooms do
            local angle = angleOffset + (i - 1) * (math.pi * 2 / numRooms)
            local scale = randomScale(rng, scaleRange)
            local dims = { scale[1] * baseUnit, scale[2] * baseUnit, scale[3] * baseUnit }

            local pos = {
                origin[1] + math.cos(angle) * radius + rng:randomFloat(-baseUnit, baseUnit),
                origin[2] + rng:randomFloat(-verticalSpread, verticalSpread),
                origin[3] + math.sin(angle) * radius + rng:randomFloat(-baseUnit, baseUnit),
            }

            if not overlapsAny(pos, dims, rooms, margin * 2) then
                table.insert(rooms, {
                    position = pos,
                    scale = scale,
                    baseUnit = baseUnit,
                })
            end
        end
    end

    return rooms
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
