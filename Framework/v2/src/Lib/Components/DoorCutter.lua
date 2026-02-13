--[[
    LibPureFiction Framework v2
    DoorCutter.lua - Creates Door Openings Between Adjacent Rooms

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    DoorCutter creates door openings between two adjacent rooms. It receives
    roomA and roomB geometry, calculates the shared wall region, and cuts
    a door hole using CSG negate operations.

    Used by DungeonOrchestrator in the sequential build pipeline:
    VolumeBuilder -> ShellBuilder -> DoorCutter -> next room

    CSG Approach:
    - Creates a door-shaped part at the shared wall location
    - Uses SubtractAsync to cut holes in both walls simultaneously
    - Cleaner than slab splitting for complex doorway shapes

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ minDoorSize, doorHeight, wallThickness, container })
        onCutDoor({ roomA, roomB })  -- each has { id, position, dims }
        onClear({})

    OUT (emits):
        doorComplete({ fromRoomId, toRoomId, position, width, height })
        doorFailed({ fromRoomId, toRoomId, reason })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- DOOR CUTTER NODE
--------------------------------------------------------------------------------

local DoorCutter = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    doorSize = nil,       -- Required: set by orchestrator (doors are square)
                    wallThickness = nil,  -- Required: set by orchestrator
                    -- Derived values (from GeometryContext, with fallbacks)
                    gap = nil,            -- 2 * wallThickness (shell-to-shell distance)
                    cutterDepth = nil,    -- wallThickness * 8 (CSG cutter depth)
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
    -- GEOMETRY UTILITIES (from DoorwayCutter.lua)
    ----------------------------------------------------------------------------

    local AXIS_TO_WALLS = {
        [1] = { pos = "East", neg = "West" },
        [2] = { pos = "Ceiling", neg = "Floor" },
        [3] = { pos = "North", neg = "South" },
    }

    local function findAdjacencyAxis(self, roomA, roomB)
        local state = getState(self)
        local config = state.config
        -- Use derived gap value (2 * wallThickness) from GeometryContext
        local gap = config.gap or (2 * config.wallThickness)

        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        for axis = 1, 3 do
            local distCenters = math.abs(posB[axis] - posA[axis])
            local shellTouchDist = dimsA[axis] / 2 + dimsB[axis] / 2 + gap

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

        local doorSize = config.doorSize  -- Doors are square
        local margin = 2

        local availableWidth = sharedWall.width - margin * 2
        local availableHeight = sharedWall.height - margin * 2

        -- Need enough space for the square door
        if availableWidth < doorSize or availableHeight < doorSize then
            return nil
        end

        -- Door is square: doorSize x doorSize
        local doorWidth = doorSize
        local doorHeight = doorSize

        local doorCenter = {
            sharedWall.center[1],
            sharedWall.center[2],
            sharedWall.center[3],
        }

        -- Position door at floor level (with small margin above floor)
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

    ----------------------------------------------------------------------------
    -- CSG DOOR CUTTING
    ----------------------------------------------------------------------------

    local function findWallPart(self, roomId, wallName)
        local state = getState(self)
        local container = state.container
        if not container then return nil end

        -- Try multiple naming conventions
        local searchNames = {
            "Room_" .. tostring(roomId),
        }

        for _, searchName in ipairs(searchNames) do
            local roomContainer = container:FindFirstChild(searchName)
            if roomContainer then
                local wall = roomContainer:FindFirstChild(wallName)
                if wall then
                    return wall
                end
            end
        end

        return nil
    end

    local function cutDoorWithCSG(self, wallPart, doorway, sharedWall)
        local state = getState(self)
        local config = state.config
        -- Use derived cutterDepth from GeometryContext (wallThickness * 8)
        local cutterDepth = config.cutterDepth or (config.wallThickness * 8)

        if not wallPart then return false end

        -- Create the door cutter part
        local doorCutter = Instance.new("Part")
        doorCutter.Name = "DoorCutter"
        doorCutter.Anchored = true
        doorCutter.CanCollide = false

        -- Size the cutter to punch through the wall
        local cutterSize = Vector3.new(0, 0, 0)
        local cutterPos = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])

        if sharedWall.axis == 1 then
            -- X-axis adjacency (East/West walls) - door faces X
            cutterSize = Vector3.new(
                cutterDepth,  -- Punch through wall thickness
                doorway.height,
                doorway.width
            )
        elseif sharedWall.axis == 2 then
            -- Y-axis adjacency (Ceiling/Floor) - door faces Y
            cutterSize = Vector3.new(
                doorway.width,
                cutterDepth,
                doorway.height
            )
        else
            -- Z-axis adjacency (North/South walls) - door faces Z
            cutterSize = Vector3.new(
                doorway.width,
                doorway.height,
                cutterDepth
            )
        end

        doorCutter.Size = cutterSize
        doorCutter.Position = cutterPos
        doorCutter.Parent = workspace

        -- Perform CSG subtraction
        local success, result = pcall(function()
            local newPart = wallPart:SubtractAsync({ doorCutter })
            return newPart
        end)

        -- Clean up cutter
        doorCutter:Destroy()

        if success and result then
            -- Replace the original wall with the CSG result
            result.Name = wallPart.Name
            result.Parent = wallPart.Parent
            result.Anchored = true
            result.CanCollide = true
            result.Material = wallPart.Material
            result.Color = wallPart.Color

            wallPart:Destroy()
            return true
        else
            warn("[DoorCutter] CSG subtraction failed for wall: " .. wallPart.Name)
            return false
        end
    end

    local function createDoorway(self, roomA, roomB, doorway, sharedWall)
        local state = getState(self)

        local wallNames = AXIS_TO_WALLS[sharedWall.axis]
        local wallAName = sharedWall.direction > 0 and wallNames.pos or wallNames.neg
        local wallBName = sharedWall.direction > 0 and wallNames.neg or wallNames.pos

        -- Find and cut wall A
        local wallA = findWallPart(self, roomA.id, wallAName)
        if wallA then
            cutDoorWithCSG(self, wallA, doorway, sharedWall)
        end

        -- Find and cut wall B
        local wallB = findWallPart(self, roomB.id, wallBName)
        if wallB then
            cutDoorWithCSG(self, wallB, doorway, sharedWall)
        end

        local doorwayData = {
            fromRoomId = roomA.id,
            toRoomId = roomB.id,
            center = doorway.center,
            width = doorway.width,
            height = doorway.height,
            axis = sharedWall.axis,
        }

        table.insert(state.doorways, doorwayData)
        return doorwayData
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "DoorCutter",
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

                if data.doorSize then config.doorSize = data.doorSize end
                if data.wallThickness then config.wallThickness = data.wallThickness end
                -- Derived values from GeometryContext
                if data.gap then config.gap = data.gap end
                if data.cutterDepth then config.cutterDepth = data.cutterDepth end

                if data.container then
                    state.container = data.container
                end
            end,

            onCutDoor = function(self, data)
                if not data then return end

                local roomA = data.roomA
                local roomB = data.roomB

                if not roomA or not roomB then
                    self.Out:Fire("doorFailed", {
                        fromRoomId = roomA and roomA.id,
                        toRoomId = roomB and roomB.id,
                        reason = "Missing room data",
                    })
                    return
                end

                -- Find adjacency axis
                local axis, direction = findAdjacencyAxis(self, roomA, roomB)

                if not axis then
                    self.Out:Fire("doorFailed", {
                        fromRoomId = roomA.id,
                        toRoomId = roomB.id,
                        reason = "Rooms are not adjacent",
                    })
                    return
                end

                -- Calculate shared wall region
                local sharedWall = calculateSharedWall(self, roomA, roomB, axis, direction)

                if not sharedWall then
                    self.Out:Fire("doorFailed", {
                        fromRoomId = roomA.id,
                        toRoomId = roomB.id,
                        reason = "No wall overlap found",
                    })
                    return
                end

                -- Calculate doorway dimensions and position
                local doorway = calculateDoorway(self, sharedWall)

                if not doorway then
                    self.Out:Fire("doorFailed", {
                        fromRoomId = roomA.id,
                        toRoomId = roomB.id,
                        reason = "Wall overlap too small for door",
                    })
                    return
                end

                -- Cut the door
                local doorwayData = createDoorway(self, roomA, roomB, doorway, sharedWall)

                self.Out:Fire("doorComplete", {
                    fromRoomId = doorwayData.fromRoomId,
                    toRoomId = doorwayData.toRoomId,
                    position = doorwayData.center,
                    width = doorwayData.width,
                    height = doorwayData.height,
                    axis = doorwayData.axis,
                    widthAxis = doorway.widthAxis,
                })
            end,

            onClear = function(self)
                local state = getState(self)
                state.doorways = {}
            end,
        },

        Out = {
            doorComplete = {},
            doorFailed = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getDoorways = function(self)
            return getState(self).doorways
        end,

        getDoorwayCount = function(self)
            return #getState(self).doorways
        end,
    }
end)

return DoorCutter
