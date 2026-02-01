--[[
    LibPureFiction Framework v2
    DoorwayCutter.lua - Creates Doorway Gaps Between Adjacent Rooms

    Copyright (c) 2025-2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    After rooms are built, DoorwayCutter analyzes connected room pairs to find
    their shared wall surfaces. It then creates door openings by splitting wall
    slabs into sections around the door gap.

    Slab-Based Approach (2026-02-01):
    - Each room has 6 wall slabs (Floor, Ceiling, North, South, East, West)
    - Door cutting finds the wall slab facing the connected room
    - Splits that slab into sections: above door, left of door, right of door
    - Simple geometry, no CSG artifacts

    Flow:
    1. Receive roomsComplete signal with layout data
    2. For each room connection, find the shared wall area
    3. Determine door size based on shared area
    4. Find and split the wall slabs at the doorway
    5. Emit doorway signals for each created opening

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit?, wallThickness?, container? })
        onRoomsComplete({ layouts })

    OUT (emits):
        doorwayCreated({ fromRoomId, toRoomId, position, size })
        complete({ totalDoorways })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- DOORWAYCUTTER NODE
--------------------------------------------------------------------------------

local DoorwayCutter = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    baseUnit = 5,
                    wallThickness = 1,
                    minDoorSize = 4,
                    doorHeight = 8,
                },
                container = nil,
                doorways = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- GEOMETRY UTILITIES
    ----------------------------------------------------------------------------

    -- Map axis to wall names
    local AXIS_TO_WALLS = {
        [1] = { pos = "East", neg = "West" },   -- X axis
        [2] = { pos = "Ceiling", neg = "Floor" }, -- Y axis
        [3] = { pos = "North", neg = "South" },  -- Z axis
    }

    --[[
        Find the axis along which two rooms are adjacent.
        Returns: axis (1=X, 2=Y, 3=Z), direction (+1 or -1 from A to B), or nil
    --]]
    local function findAdjacencyAxis(self, roomA, roomB)
        local state = getState(self)
        local wallThickness = state.config.wallThickness

        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        for axis = 1, 3 do
            local distCenters = math.abs(posB[axis] - posA[axis])
            -- Shells touch: inner dims/2 + wall + inner dims/2 + wall
            local shellTouchDist = dimsA[axis] / 2 + dimsB[axis] / 2 + 2 * wallThickness

            if math.abs(distCenters - shellTouchDist) < 1 then
                local direction = posB[axis] > posA[axis] and 1 or -1
                return axis, direction
            end
        end

        return nil, nil
    end

    --[[
        Calculate the shared wall rectangle between two adjacent rooms.
    --]]
    local function calculateSharedWall(self, roomA, roomB, axis, direction)
        local state = getState(self)
        local wallThickness = state.config.wallThickness

        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        -- Wall position is at the shell boundary
        local wallPos = posA[axis] + (dimsA[axis] / 2 + wallThickness) * direction

        -- Find overlap on perpendicular axes
        local perpAxes = {}
        for i = 1, 3 do
            if i ~= axis then
                table.insert(perpAxes, i)
            end
        end

        local ranges = {}
        for _, perpAxis in ipairs(perpAxes) do
            local minA = posA[perpAxis] - dimsA[perpAxis] / 2
            local maxA = posA[perpAxis] + dimsA[perpAxis] / 2
            local minB = posB[perpAxis] - dimsB[perpAxis] / 2
            local maxB = posB[perpAxis] + dimsB[perpAxis] / 2

            local overlapMin = math.max(minA, minB)
            local overlapMax = math.min(maxA, maxB)

            if overlapMax <= overlapMin then
                return nil
            end

            ranges[perpAxis] = {
                min = overlapMin,
                max = overlapMax,
                size = overlapMax - overlapMin,
                center = (overlapMin + overlapMax) / 2,
            }
        end

        -- Build wall info
        local center = { 0, 0, 0 }
        center[axis] = wallPos

        local widthAxis, heightAxis
        if axis == 2 then
            widthAxis = 1
            heightAxis = 3
        else
            heightAxis = 2
            widthAxis = (axis == 1) and 3 or 1
        end

        center[widthAxis] = ranges[widthAxis].center
        center[heightAxis] = ranges[heightAxis].center

        return {
            center = center,
            width = ranges[widthAxis].size,
            height = ranges[heightAxis].size,
            widthAxis = widthAxis,
            heightAxis = heightAxis,
            axis = axis,
            direction = direction,
            ranges = ranges,
        }
    end

    --[[
        Calculate door size and position within the shared wall area.
    --]]
    local function calculateDoorway(self, sharedWall)
        local state = getState(self)
        local config = state.config

        local minSize = config.minDoorSize
        local margin = 2

        local availableWidth = sharedWall.width - margin * 2
        local availableHeight = sharedWall.height - margin * 2

        if availableWidth < minSize or availableHeight < minSize then
            return nil
        end

        local doorWidth = math.min(availableWidth * 0.75, 12)
        doorWidth = math.max(doorWidth, minSize)

        local doorHeight = math.min(availableHeight * 0.8, 10)
        doorHeight = math.max(doorHeight, minSize)

        doorWidth = math.min(doorWidth, availableWidth)
        doorHeight = math.min(doorHeight, availableHeight)

        local doorCenter = {
            sharedWall.center[1],
            sharedWall.center[2],
            sharedWall.center[3],
        }

        -- Position door at bottom of shared wall + margin
        local wallBottom = sharedWall.center[sharedWall.heightAxis] - sharedWall.height / 2
        doorCenter[sharedWall.heightAxis] = wallBottom + margin + doorHeight / 2

        return {
            center = doorCenter,
            width = doorWidth,
            height = doorHeight,
            widthAxis = sharedWall.widthAxis,
            heightAxis = sharedWall.heightAxis,
        }
    end

    --[[
        Find wall slabs that need to be split for this doorway.
        Returns walls from both rooms at the doorway location.
    --]]
    local function findWallsToSplit(self, axis, direction, fromRoomId, toRoomId)
        local state = getState(self)
        local container = state.container
        if not container then return {} end

        local wallNames = AXIS_TO_WALLS[axis]
        -- Room A's wall facing B, and Room B's wall facing A
        local wallAName = direction > 0 and wallNames.pos or wallNames.neg
        local wallBName = direction > 0 and wallNames.neg or wallNames.pos

        local walls = {}

        -- Find Room A's wall
        local roomAContainer = container:FindFirstChild("Room_Room_" .. fromRoomId)
            or container:FindFirstChild("Room_" .. fromRoomId)
        if roomAContainer then
            local wall = roomAContainer:FindFirstChild(wallAName)
            if wall then
                table.insert(walls, wall)
            end
        end

        -- Find Room B's wall
        local roomBContainer = container:FindFirstChild("Room_Room_" .. toRoomId)
            or container:FindFirstChild("Room_" .. toRoomId)
        if roomBContainer then
            local wall = roomBContainer:FindFirstChild(wallBName)
            if wall then
                table.insert(walls, wall)
            end
        end

        return walls
    end

    --[[
        Split a wall slab to create a door gap.
        Creates sections: above door, left of door, right of door.
    --]]
    local function splitWall(wall, doorway)
        local parent = wall.Parent
        local wallPos = wall.Position
        local wallSize = wall.Size
        local material = wall.Material
        local color = wall.Color

        local doorCenter = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])
        local doorWidth = doorway.width
        local doorHeight = doorway.height
        local widthAxis = doorway.widthAxis
        local heightAxis = doorway.heightAxis

        -- Get door bounds
        local doorWidthMin, doorWidthMax, doorHeightMin, doorHeightMax
        local wallWidthMin, wallWidthMax, wallHeightMin, wallHeightMax

        if widthAxis == 1 then -- X
            doorWidthMin = doorCenter.X - doorWidth / 2
            doorWidthMax = doorCenter.X + doorWidth / 2
            wallWidthMin = wallPos.X - wallSize.X / 2
            wallWidthMax = wallPos.X + wallSize.X / 2
        elseif widthAxis == 3 then -- Z
            doorWidthMin = doorCenter.Z - doorWidth / 2
            doorWidthMax = doorCenter.Z + doorWidth / 2
            wallWidthMin = wallPos.Z - wallSize.Z / 2
            wallWidthMax = wallPos.Z + wallSize.Z / 2
        end

        if heightAxis == 2 then -- Y
            doorHeightMin = doorCenter.Y - doorHeight / 2
            doorHeightMax = doorCenter.Y + doorHeight / 2
            wallHeightMin = wallPos.Y - wallSize.Y / 2
            wallHeightMax = wallPos.Y + wallSize.Y / 2
        end

        local newParts = {}

        local function createPart(name, size, position)
            if size.X < 0.1 or size.Y < 0.1 or size.Z < 0.1 then return nil end
            local part = Instance.new("Part")
            part.Name = name
            part.Size = size
            part.Position = position
            part.Anchored = true
            part.CanCollide = true
            part.Material = material
            part.Color = color
            part.Parent = parent
            table.insert(newParts, part)
            return part
        end

        -- Section ABOVE door (full width, from door top to wall top)
        if doorHeightMax < wallHeightMax - 0.5 then
            local aboveHeight = wallHeightMax - doorHeightMax
            local aboveY = doorHeightMax + aboveHeight / 2

            local aboveSize = Vector3.new(wallSize.X, aboveHeight, wallSize.Z)
            local abovePos = Vector3.new(wallPos.X, aboveY, wallPos.Z)

            createPart(wall.Name .. "_Above", aboveSize, abovePos)
        end

        -- Section LEFT of door (from wall left to door left, door height only)
        if doorWidthMin > wallWidthMin + 0.5 then
            local leftWidth = doorWidthMin - wallWidthMin
            local leftCenter = wallWidthMin + leftWidth / 2

            local leftSize, leftPos
            if widthAxis == 1 then
                leftSize = Vector3.new(leftWidth, doorHeight, wallSize.Z)
                leftPos = Vector3.new(leftCenter, doorCenter.Y, wallPos.Z)
            else
                leftSize = Vector3.new(wallSize.X, doorHeight, leftWidth)
                leftPos = Vector3.new(wallPos.X, doorCenter.Y, leftCenter)
            end

            createPart(wall.Name .. "_Left", leftSize, leftPos)
        end

        -- Section RIGHT of door (from door right to wall right, door height only)
        if doorWidthMax < wallWidthMax - 0.5 then
            local rightWidth = wallWidthMax - doorWidthMax
            local rightCenter = doorWidthMax + rightWidth / 2

            local rightSize, rightPos
            if widthAxis == 1 then
                rightSize = Vector3.new(rightWidth, doorHeight, wallSize.Z)
                rightPos = Vector3.new(rightCenter, doorCenter.Y, wallPos.Z)
            else
                rightSize = Vector3.new(wallSize.X, doorHeight, rightWidth)
                rightPos = Vector3.new(wallPos.X, doorCenter.Y, rightCenter)
            end

            createPart(wall.Name .. "_Right", rightSize, rightPos)
        end

        -- Section BELOW door (full width, from wall bottom to door bottom)
        if doorHeightMin > wallHeightMin + 0.5 then
            local belowHeight = doorHeightMin - wallHeightMin
            local belowY = wallHeightMin + belowHeight / 2

            local belowSize = Vector3.new(wallSize.X, belowHeight, wallSize.Z)
            local belowPos = Vector3.new(wallPos.X, belowY, wallPos.Z)

            createPart(wall.Name .. "_Below", belowSize, belowPos)
        end

        -- Destroy original wall
        wall:Destroy()

        return newParts
    end

    --[[
        Create ladders for doors between rooms at different Y levels.
        Places a ladder on BOTH sides of the opening for access from either room.
        Only for horizontal walls (N/S/E/W), not ceiling/floor.
    --]]
    local function createLadders(self, doorway, sharedWall, roomA, roomB)
        local state = getState(self)
        local container = state.container

        -- Only for horizontal walls (axis 1 or 3, not 2)
        if sharedWall.axis == 2 then return {} end

        -- Get floor levels of both rooms
        local floorA = roomA.position[2] - roomA.dims[2] / 2
        local floorB = roomB.position[2] - roomB.dims[2] / 2

        -- Only need ladders if rooms are at significantly different Y levels
        local floorDiff = math.abs(floorA - floorB)
        if floorDiff < 3 then return {} end  -- Same level or jumpable

        print(string.format("[DoorwayCutter] Adding ladders on both sides, floor difference is %.1f studs", floorDiff))

        local ladders = {}
        local lowerFloor = math.min(floorA, floorB)
        local higherFloor = math.max(floorA, floorB)
        local ladderHeight = higherFloor - lowerFloor
        local ladderWidth = 2

        local doorCenter = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])
        local wallAxis = sharedWall.axis
        local offsetDist = ladderWidth / 2 + 0.5

        -- Create ladder on both sides of the doorway
        for _, offsetDir in ipairs({ -1, 1 }) do
            local ladderPos
            if wallAxis == 1 then  -- X axis wall (East/West)
                ladderPos = Vector3.new(
                    doorCenter.X + offsetDir * offsetDist,
                    lowerFloor + ladderHeight / 2,
                    doorCenter.Z
                )
            elseif wallAxis == 3 then  -- Z axis wall (North/South)
                ladderPos = Vector3.new(
                    doorCenter.X,
                    lowerFloor + ladderHeight / 2,
                    doorCenter.Z + offsetDir * offsetDist
                )
            end

            local ladder = Instance.new("TrussPart")
            ladder.Name = "Ladder_" .. roomA.id .. "_" .. roomB.id .. "_" .. (offsetDir > 0 and "A" or "B")
            ladder.Size = Vector3.new(ladderWidth, ladderHeight, ladderWidth)
            ladder.Position = ladderPos
            ladder.Anchored = true
            ladder.Material = Enum.Material.Metal
            ladder.Color = Color3.fromRGB(80, 80, 80)
            ladder.Parent = container
            table.insert(ladders, ladder)
        end

        return ladders
    end

    --[[
        Create a climbing pole for ceiling openings.
        Extends from ceiling to floor so players can climb back up.
    --]]
    local function createCeilingPole(self, doorway, sharedWall, roomA, roomB)
        local state = getState(self)
        local container = state.container

        -- Only for ceiling openings (axis 2, direction +1)
        if sharedWall.axis ~= 2 then return nil end

        local doorCenter = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])

        -- Get floor and ceiling levels
        local floorA = roomA.position[2] - roomA.dims[2] / 2
        local floorB = roomB.position[2] - roomB.dims[2] / 2
        local ceilingA = roomA.position[2] + roomA.dims[2] / 2
        local ceilingB = roomB.position[2] + roomB.dims[2] / 2

        -- Pole goes from lower floor to upper ceiling
        local lowestFloor = math.min(floorA, floorB)
        local highestCeiling = math.max(ceilingA, ceilingB)
        local poleHeight = highestCeiling - lowestFloor

        print(string.format("[DoorwayCutter] Adding ceiling pole, height %.1f studs", poleHeight))

        -- Position pole at one corner of the opening
        local poleWidth = 2
        local polePos = Vector3.new(
            doorCenter.X - doorway.width / 2 + poleWidth / 2,
            lowestFloor + poleHeight / 2,
            doorCenter.Z - doorway.height / 2 + poleWidth / 2  -- height is Z for ceiling
        )

        local pole = Instance.new("TrussPart")
        pole.Name = "CeilingPole_" .. roomA.id .. "_" .. roomB.id
        pole.Size = Vector3.new(poleWidth, poleHeight, poleWidth)
        pole.Position = polePos
        pole.Anchored = true
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(60, 60, 70)
        pole.Parent = container

        return pole
    end

    --[[
        Create a doorway between two rooms by splitting their wall slabs.
    --]]
    local function createDoorway(self, doorway, sharedWall, fromRoomId, toRoomId, roomA, roomB)
        local state = getState(self)

        -- Find walls to split
        local walls = findWallsToSplit(self, sharedWall.axis, sharedWall.direction, fromRoomId, toRoomId)

        print(string.format("[DoorwayCutter] Found %d walls to split for doorway %d<->%d",
            #walls, fromRoomId, toRoomId))

        -- Split each wall
        for _, wall in ipairs(walls) do
            splitWall(wall, doorway)
        end

        -- Add climbing aids if needed
        local climbingAids = {}
        if sharedWall.axis == 2 then
            -- Ceiling opening - add pole
            local pole = createCeilingPole(self, doorway, sharedWall, roomA, roomB)
            if pole then table.insert(climbingAids, pole) end
        else
            -- Horizontal wall - add ladders if rooms at different levels
            local ladders = createLadders(self, doorway, sharedWall, roomA, roomB)
            for _, ladder in ipairs(ladders) do
                table.insert(climbingAids, ladder)
            end
        end

        table.insert(state.doorways, {
            fromRoomId = fromRoomId,
            toRoomId = toRoomId,
            center = doorway.center,
            width = doorway.width,
            height = doorway.height,
            climbingAids = climbingAids,
        })

        return true
    end

    ----------------------------------------------------------------------------
    -- MAIN PROCESSING
    ----------------------------------------------------------------------------

    local function processConnections(self, layouts)
        local state = getState(self)

        local roomsById = {}
        for _, layout in ipairs(layouts) do
            roomsById[layout.id] = layout
        end

        local processed = {}
        local doorwayCount = 0

        for _, layout in ipairs(layouts) do
            local roomA = layout

            for _, connId in ipairs(layout.connections) do
                local key = roomA.id < connId
                    and (roomA.id .. "_" .. connId)
                    or (connId .. "_" .. roomA.id)

                if not processed[key] then
                    processed[key] = true

                    local roomB = roomsById[connId]
                    if roomB then
                        local axis, direction = findAdjacencyAxis(self, roomA, roomB)

                        if axis then
                            local sharedWall = calculateSharedWall(self, roomA, roomB, axis, direction)

                            if sharedWall then
                                local doorway = calculateDoorway(self, sharedWall)

                                if doorway then
                                    createDoorway(self, doorway, sharedWall, roomA.id, connId, roomA, roomB)
                                    doorwayCount = doorwayCount + 1

                                    self.Out:Fire("doorwayCreated", {
                                        fromRoomId = roomA.id,
                                        toRoomId = connId,
                                        position = doorway.center,
                                        width = doorway.width,
                                        height = doorway.height,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        print(string.format("[DoorwayCutter] Created %d doorways", doorwayCount))

        self.Out:Fire("complete", {
            totalDoorways = doorwayCount,
        })
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "DoorwayCutter",
        domain = "server",

        Sys = {
            onInit = function(self)
                local _ = getState(self)
            end,

            onStart = function(self) end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)
                local config = state.config

                if data.baseUnit then config.baseUnit = data.baseUnit end
                if data.wallThickness then config.wallThickness = data.wallThickness end
                if data.minDoorSize then config.minDoorSize = data.minDoorSize end
                if data.doorHeight then config.doorHeight = data.doorHeight end

                if data.container then
                    state.container = data.container
                end
            end,

            onRoomsComplete = function(self, data)
                if not data or not data.layouts then
                    return
                end

                print(string.format("[DoorwayCutter] Processing %d room layouts", #data.layouts))

                task.wait()
                processConnections(self, data.layouts)
            end,
        },

        Out = {
            doorwayCreated = {},
            complete = {},
        },

        getDoorways = function(self)
            return getState(self).doorways
        end,
    }
end)

return DoorwayCutter
