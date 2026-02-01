--[[
    LibPureFiction Framework v2
    DoorwayCutter.lua - Creates Doorway Geometry Between Adjacent Rooms

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    After rooms are built, DoorwayCutter analyzes connected room pairs to find
    their shared wall surfaces. It then creates door openings sized appropriately
    for the available wall space.

    Flow:
    1. Receive roomsComplete signal with layout data
    2. For each room connection, find the shared wall area
    3. Select door size (base unit 5 studs) constrained by shared area
    4. Create door box that cuts through both walls
    5. Emit doorway signals for each created opening

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit?, wallThickness?, container? })
        onRoomsComplete({ layouts, rooms })

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
                    baseUnit = 5,        -- Door base size unit
                    wallThickness = 1,   -- Thickness of room walls
                    minDoorSize = 4,     -- Minimum door dimension
                    doorHeight = 8,      -- Default door height
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

    --[[
        Find the axis along which two rooms are adjacent.
        Returns: axis (1=X, 2=Y, 3=Z), direction (+1 or -1 from A to B), or nil if not adjacent
    --]]
    local function findAdjacencyAxis(roomA, roomB)
        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        for axis = 1, 3 do
            local distCenters = math.abs(posB[axis] - posA[axis])
            local touchDist = dimsA[axis] / 2 + dimsB[axis] / 2

            -- Check if they touch on this axis (within small tolerance)
            if math.abs(distCenters - touchDist) < 0.1 then
                local direction = posB[axis] > posA[axis] and 1 or -1
                return axis, direction
            end
        end

        return nil, nil
    end

    --[[
        Calculate the shared wall rectangle between two adjacent rooms.
        Returns: { center = {x,y,z}, width, height, axis, normal }
    --]]
    local function calculateSharedWall(roomA, roomB, axis, direction)
        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        -- Wall position is at the boundary between the two rooms
        local wallPos = posA[axis] + (dimsA[axis] / 2) * direction

        -- Find the intersection rectangle on the two perpendicular axes
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
                -- No overlap, shouldn't happen for connected rooms
                return nil
            end

            ranges[perpAxis] = {
                min = overlapMin,
                max = overlapMax,
                size = overlapMax - overlapMin,
                center = (overlapMin + overlapMax) / 2,
            }
        end

        -- Build the wall info
        local center = { 0, 0, 0 }
        center[axis] = wallPos

        local width, height
        local widthAxis, heightAxis

        -- Determine which perpendicular axis is width vs height
        -- Convention: Y is usually height, others are width
        if axis == 2 then
            -- Wall is horizontal (floor/ceiling) - unusual for doors
            widthAxis = 1
            heightAxis = 3
        else
            -- Wall is vertical
            heightAxis = 2
            widthAxis = (axis == 1) and 3 or 1
        end

        center[widthAxis] = ranges[widthAxis].center
        center[heightAxis] = ranges[heightAxis].center

        width = ranges[widthAxis].size
        height = ranges[heightAxis].size

        print(string.format("[DoorwayCutter] Shared wall: center=(%.1f,%.1f,%.1f) size=%.1fx%.1f axis=%d",
            center[1], center[2], center[3], width, height, axis))

        return {
            center = center,
            width = width,
            height = height,
            widthAxis = widthAxis,
            heightAxis = heightAxis,
            axis = axis,
            direction = direction,
            -- Store range info for debugging
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
        local margin = 2  -- Keep doors away from edges

        -- Available space after margin
        local availableWidth = sharedWall.width - margin * 2
        local availableHeight = sharedWall.height - margin * 2

        if availableWidth < minSize or availableHeight < minSize then
            -- Shared wall too small for a door
            print(string.format("[DoorwayCutter] Shared wall too small: %.1fx%.1f",
                sharedWall.width, sharedWall.height))
            return nil
        end

        -- Door size: 60-80% of available space, clamped to reasonable bounds
        local doorWidth = math.min(availableWidth * 0.75, 12)  -- Max 12 studs wide
        doorWidth = math.max(doorWidth, minSize)

        local doorHeight = math.min(availableHeight * 0.8, 10)  -- Max 10 studs tall
        doorHeight = math.max(doorHeight, minSize)

        -- Ensure door fits within available space
        doorWidth = math.min(doorWidth, availableWidth)
        doorHeight = math.min(doorHeight, availableHeight)

        -- Position: centered within the shared wall area
        local doorCenter = {
            sharedWall.center[1],
            sharedWall.center[2],
            sharedWall.center[3],
        }

        -- Put door at bottom of shared wall area (floor level)
        local wallBottom = sharedWall.center[sharedWall.heightAxis] - sharedWall.height / 2
        doorCenter[sharedWall.heightAxis] = wallBottom + margin + doorHeight / 2

        -- Door depth: needs to cut through both walls plus extra
        local doorDepth = config.wallThickness * 4 + 1

        -- Build size vector based on wall orientation
        local doorSize = { 0, 0, 0 }
        doorSize[sharedWall.axis] = doorDepth
        doorSize[sharedWall.widthAxis] = doorWidth
        doorSize[sharedWall.heightAxis] = doorHeight

        print(string.format("[DoorwayCutter] Door: %.1fx%.1f in shared wall %.1fx%.1f",
            doorWidth, doorHeight, sharedWall.width, sharedWall.height))

        return {
            center = doorCenter,
            size = doorSize,
        }
    end

    --[[
        Find wall parts that intersect with the doorway position.
    --]]
    local function findWallsToCut(self, doorway, fromRoomId, toRoomId)
        local state = getState(self)
        local container = state.container
        if not container then
            warn("[DoorwayCutter] No container set!")
            return {}
        end

        local doorPos = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])
        local doorSize = Vector3.new(doorway.size[1], doorway.size[2], doorway.size[3])

        local walls = {}
        local slabCount = 0

        -- Search for Room models and their wall slabs
        for _, child in ipairs(container:GetDescendants()) do
            if child:IsA("BasePart") and child.Name:match("^Slab_") then
                slabCount = slabCount + 1

                -- Check if this slab intersects with our door region
                local slabPos = child.Position
                local slabSize = child.Size

                -- Simple AABB intersection check with some margin
                local margin = 0.5
                local slabMin = slabPos - slabSize / 2 - Vector3.new(margin, margin, margin)
                local slabMax = slabPos + slabSize / 2 + Vector3.new(margin, margin, margin)
                local doorMin = doorPos - doorSize / 2
                local doorMax = doorPos + doorSize / 2

                local overlaps =
                    slabMin.X < doorMax.X and slabMax.X > doorMin.X and
                    slabMin.Y < doorMax.Y and slabMax.Y > doorMin.Y and
                    slabMin.Z < doorMax.Z and slabMax.Z > doorMin.Z

                if overlaps then
                    table.insert(walls, child)
                end
            end
        end

        print(string.format("[DoorwayCutter] Searched %d slabs, found %d intersecting", slabCount, #walls))

        return walls
    end

    --[[
        Cut a hole through a wall using CSG subtraction.
    --]]
    local function cutWall(self, wall, cutterPart)
        local parent = wall.Parent
        local wallName = wall.Name
        local wallMaterial = wall.Material
        local wallColor = wall.Color
        local wallTransparency = wall.Transparency
        local wallCFrame = wall.CFrame

        print(string.format("[DoorwayCutter] Cutting wall %s at %s", wallName, tostring(wall.Position)))

        local success, result = pcall(function()
            return wall:SubtractAsync({ cutterPart })
        end)

        if success and result then
            result.Name = wallName
            result.Material = wallMaterial
            result.Color = wallColor
            result.Transparency = wallTransparency
            result.Anchored = true
            result.CanCollide = true
            result.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
            result.Parent = parent

            wall:Destroy()

            print(string.format("[DoorwayCutter] Successfully cut %s", wallName))
            return result
        else
            warn("[DoorwayCutter] CSG subtract failed for " .. wallName .. ":", tostring(result))
            return nil
        end
    end

    --[[
        Remove one of two overlapping walls at shared boundary.
        After cutting, we have two walls with holes - keep one, delete the other.
    --]]
    local function removeOverlappingWall(self, walls)
        if #walls < 2 then return end

        -- If we found 2+ walls at the shared boundary, delete all but the first
        -- (they're overlapping and causing z-fighting)
        for i = 2, #walls do
            local wall = walls[i]
            if wall and wall.Parent then
                print(string.format("[DoorwayCutter] Removing duplicate wall: %s", wall.Name))
                wall:Destroy()
            end
        end
    end

    --[[
        Create the door cutter and cut through walls.
    --]]
    local function createDoorway(self, doorway, sharedWall, fromRoomId, toRoomId)
        local state = getState(self)

        -- Create cutter part
        local cutterPart = Instance.new("Part")
        cutterPart.Name = string.format("DoorCutter_%d_%d", fromRoomId, toRoomId)
        cutterPart.Size = Vector3.new(doorway.size[1], doorway.size[2], doorway.size[3])
        cutterPart.Position = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])
        cutterPart.Anchored = true
        cutterPart.CanCollide = false
        cutterPart.Parent = state.container

        -- Find walls to cut
        local walls = findWallsToCut(self, doorway, fromRoomId, toRoomId)

        print(string.format("[DoorwayCutter] Found %d walls to cut for doorway %d<->%d",
            #walls, fromRoomId, toRoomId))

        -- Cut each wall and collect the results
        local cutWalls = {}
        for _, wall in ipairs(walls) do
            local result = cutWall(self, wall, cutterPart)
            if result then
                table.insert(cutWalls, result)
            end
        end

        -- Remove duplicate overlapping walls (keep only one with the hole)
        removeOverlappingWall(self, cutWalls)

        -- Destroy the cutter part after cutting holes
        cutterPart:Destroy()

        table.insert(state.doorways, {
            part = nil,  -- Part destroyed after cutting
            fromRoomId = fromRoomId,
            toRoomId = toRoomId,
            center = doorway.center,
            size = doorway.size,
        })

        return cutterPart
    end

    ----------------------------------------------------------------------------
    -- MAIN PROCESSING
    ----------------------------------------------------------------------------

    local function processConnections(self, layouts)
        local state = getState(self)

        -- Build room lookup
        local roomsById = {}
        for _, layout in ipairs(layouts) do
            roomsById[layout.id] = layout
        end

        -- Track processed pairs to avoid duplicates
        local processed = {}
        local doorwayCount = 0

        for _, layout in ipairs(layouts) do
            local roomA = layout

            for _, connId in ipairs(layout.connections) do
                -- Create unique key for this pair
                local key = roomA.id < connId
                    and (roomA.id .. "_" .. connId)
                    or (connId .. "_" .. roomA.id)

                if not processed[key] then
                    processed[key] = true

                    local roomB = roomsById[connId]
                    if roomB then
                        -- Find adjacency
                        local axis, direction = findAdjacencyAxis(roomA, roomB)

                        if axis then
                            -- Calculate shared wall
                            local sharedWall = calculateSharedWall(roomA, roomB, axis, direction)

                            if sharedWall then
                                -- Calculate doorway
                                local doorway = calculateDoorway(self, sharedWall)

                                if doorway then
                                    -- Create doorway and cut through walls
                                    createDoorway(self, doorway, sharedWall, roomA.id, connId)
                                    doorwayCount = doorwayCount + 1

                                    print(string.format(
                                        "[DoorwayCutter] Doorway %d<->%d at (%.1f, %.1f, %.1f) size (%.1f, %.1f, %.1f)",
                                        roomA.id, connId,
                                        doorway.center[1], doorway.center[2], doorway.center[3],
                                        doorway.size[1], doorway.size[2], doorway.size[3]
                                    ))

                                    self.Out:Fire("doorwayCreated", {
                                        fromRoomId = roomA.id,
                                        toRoomId = connId,
                                        position = doorway.center,
                                        size = doorway.size,
                                    })
                                else
                                    print(string.format(
                                        "[DoorwayCutter] Shared wall too small for door: %d<->%d",
                                        roomA.id, connId
                                    ))
                                end
                            end
                        else
                            print(string.format(
                                "[DoorwayCutter] Rooms not adjacent: %d<->%d",
                                roomA.id, connId
                            ))
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
                local state = getState(self)
                for _, doorway in ipairs(state.doorways) do
                    if doorway.part and doorway.part.Parent then
                        doorway.part:Destroy()
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
                if data.wallThickness then config.wallThickness = data.wallThickness end
                if data.minDoorSize then config.minDoorSize = data.minDoorSize end
                if data.doorHeight then config.doorHeight = data.doorHeight end

                if data.container then
                    state.container = data.container
                end
            end,

            onRoomsComplete = function(self, data)
                if not data or not data.layouts then
                    print("[DoorwayCutter] No layout data received")
                    return
                end

                print(string.format("[DoorwayCutter] Processing %d room layouts", #data.layouts))

                -- Wait a frame for all geometry to be ready
                task.wait()

                -- Debug: count parts in container
                local state = getState(self)
                if state.container then
                    local partCount = 0
                    local slabCount = 0
                    for _, child in ipairs(state.container:GetDescendants()) do
                        if child:IsA("BasePart") then
                            partCount = partCount + 1
                            if child.Name:match("^Slab_") then
                                slabCount = slabCount + 1
                            end
                        end
                    end
                    print(string.format("[DoorwayCutter] Container has %d parts, %d slabs", partCount, slabCount))
                else
                    warn("[DoorwayCutter] No container!")
                end

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
