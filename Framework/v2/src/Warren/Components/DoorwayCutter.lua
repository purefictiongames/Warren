--[[
    Warren Framework v2
    DoorwayCutter.lua - Creates Doorway Gaps Between Adjacent Rooms

    Copyright (c) 2025-2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    After rooms are built, DoorwayCutter analyzes connected room pairs to find
    their shared wall surfaces. It then creates door openings by splitting wall
    slabs into sections around the door gap.

    Slab-Based Approach:
    - Each room has 6 wall slabs (Floor, Ceiling, North, South, East, West)
    - Door cutting finds the wall slab facing the connected room
    - Splits that slab into sections: above door, left of door, right of door
    - Simple geometry, no CSG

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit?, wallThickness?, container? })
        onRoomsComplete({ layouts })

    OUT (emits):
        doorwayCreated({ fromRoomId, toRoomId, position, size, axis })
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

    local AXIS_TO_WALLS = {
        [1] = { pos = "East", neg = "West" },
        [2] = { pos = "Ceiling", neg = "Floor" },
        [3] = { pos = "North", neg = "South" },
    }

    local function findAdjacencyAxis(self, roomA, roomB)
        local state = getState(self)
        local wallThickness = state.config.wallThickness

        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        for axis = 1, 3 do
            local distCenters = math.abs(posB[axis] - posA[axis])
            local shellTouchDist = dimsA[axis] / 2 + dimsB[axis] / 2 + 2 * wallThickness

            if math.abs(distCenters - shellTouchDist) < 1 then
                local direction = posB[axis] > posA[axis] and 1 or -1
                return axis, direction
            end
        end

        return nil, nil
    end

    local function calculateSharedWall(self, roomA, roomB, axis, direction)
        local state = getState(self)
        local wallThickness = state.config.wallThickness

        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        local wallPos = posA[axis] + (dimsA[axis] / 2 + wallThickness) * direction

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
        }
    end

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

    local function findWallsToSplit(self, axis, direction, fromRoomId, toRoomId)
        local state = getState(self)
        local container = state.container
        if not container then return {} end

        local wallNames = AXIS_TO_WALLS[axis]
        local wallAName = direction > 0 and wallNames.pos or wallNames.neg
        local wallBName = direction > 0 and wallNames.neg or wallNames.pos

        local walls = {}

        -- Try multiple naming conventions
        local searchNames = {
            "Room_Room_" .. fromRoomId,
            "Room_" .. fromRoomId,
        }

        for _, searchName in ipairs(searchNames) do
            local roomContainer = container:FindFirstChild(searchName)
            if roomContainer then
                local wall = roomContainer:FindFirstChild(wallAName)
                if wall then
                    table.insert(walls, wall)
                    break
                end
            end
        end

        searchNames = {
            "Room_Room_" .. toRoomId,
            "Room_" .. toRoomId,
        }

        for _, searchName in ipairs(searchNames) do
            local roomContainer = container:FindFirstChild(searchName)
            if roomContainer then
                local wall = roomContainer:FindFirstChild(wallBName)
                if wall then
                    table.insert(walls, wall)
                    break
                end
            end
        end

        return walls
    end

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

        local doorWidthMin, doorWidthMax, doorHeightMin, doorHeightMax
        local wallWidthMin, wallWidthMax, wallHeightMin, wallHeightMax

        if widthAxis == 1 then
            doorWidthMin = doorCenter.X - doorWidth / 2
            doorWidthMax = doorCenter.X + doorWidth / 2
            wallWidthMin = wallPos.X - wallSize.X / 2
            wallWidthMax = wallPos.X + wallSize.X / 2
        elseif widthAxis == 3 then
            doorWidthMin = doorCenter.Z - doorWidth / 2
            doorWidthMax = doorCenter.Z + doorWidth / 2
            wallWidthMin = wallPos.Z - wallSize.Z / 2
            wallWidthMax = wallPos.Z + wallSize.Z / 2
        end

        if heightAxis == 2 then
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

        -- Above door
        if doorHeightMax < wallHeightMax - 0.5 then
            local aboveHeight = wallHeightMax - doorHeightMax
            local aboveY = doorHeightMax + aboveHeight / 2
            createPart(wall.Name .. "_Above", Vector3.new(wallSize.X, aboveHeight, wallSize.Z), Vector3.new(wallPos.X, aboveY, wallPos.Z))
        end

        -- Left of door
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

        -- Right of door
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

        -- Below door
        if doorHeightMin > wallHeightMin + 0.5 then
            local belowHeight = doorHeightMin - wallHeightMin
            local belowY = wallHeightMin + belowHeight / 2
            createPart(wall.Name .. "_Below", Vector3.new(wallSize.X, belowHeight, wallSize.Z), Vector3.new(wallPos.X, belowY, wallPos.Z))
        end

        wall:Destroy()
        return newParts
    end

    local function createDoorway(self, doorway, sharedWall, fromRoomId, toRoomId)
        local state = getState(self)

        local walls = findWallsToSplit(self, sharedWall.axis, sharedWall.direction, fromRoomId, toRoomId)

        print(string.format("[DoorwayCutter] Found %d walls to split for doorway %d<->%d",
            #walls, fromRoomId, toRoomId))

        for _, wall in ipairs(walls) do
            splitWall(wall, doorway)
        end

        local doorwayData = {
            fromRoomId = fromRoomId,
            toRoomId = toRoomId,
            center = doorway.center,
            width = doorway.width,
            height = doorway.height,
            axis = sharedWall.axis,
        }

        table.insert(state.doorways, doorwayData)
        return doorwayData
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
                                    local doorwayData = createDoorway(self, doorway, sharedWall, roomA.id, connId)
                                    doorwayCount = doorwayCount + 1

                                    self.Out:Fire("doorwayCreated", {
                                        fromRoomId = roomA.id,
                                        toRoomId = connId,
                                        position = doorway.center,
                                        width = doorway.width,
                                        height = doorway.height,
                                        axis = sharedWall.axis,
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
                    warn("[DoorwayCutter] No layout data!")
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
