--[[
    LibPureFiction Framework v2
    DoorwayCutter.lua - Creates Doorway Geometry Between Adjacent Rooms

    Copyright (c) 2025-2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    After rooms are built, DoorwayCutter analyzes connected room pairs to find
    their shared wall surfaces. It then creates door openings sized appropriately
    for the available wall space.

    Works with CSG shell-based rooms (2026-02-01 refactor):
    - Each room has 1 shell (hollow box created by CSG subtraction)
    - Doorway cutting finds 2 shells (one per room) and cuts both
    - Simpler than the old 6-slab approach (no overlapping wall removal needed)

    Flow:
    1. Receive roomsComplete signal with layout data
    2. For each room connection, find the shared wall area
    3. Select door size (base unit 5 studs) constrained by shared area
    4. Create door cutter box
    5. Cut through both room shells using CSG SubtractAsync
    6. Emit doorway signals for each created opening

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

        Note: Room dims are INNER dimensions. Outer shells extend by wallThickness on each side.
        When shells touch, inner volumes have a gap of 2*wallThickness between them.
    --]]
    local function findAdjacencyAxis(self, roomA, roomB)
        local state = getState(self)
        local wallThickness = state.config.wallThickness

        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        for axis = 1, 3 do
            local distCenters = math.abs(posB[axis] - posA[axis])
            -- When outer shells touch, inner volumes are separated by 2*wallThickness
            -- Inner touch dist: dimsA/2 + dimsB/2
            -- Shell touch dist: dimsA/2 + wallThickness + dimsB/2 + wallThickness
            local shellTouchDist = dimsA[axis] / 2 + dimsB[axis] / 2 + 2 * wallThickness

            -- Check if shells touch on this axis (within tolerance)
            if math.abs(distCenters - shellTouchDist) < 1 then
                local direction = posB[axis] > posA[axis] and 1 or -1
                return axis, direction
            end
        end

        return nil, nil
    end

    --[[
        Calculate the shared wall rectangle between two adjacent rooms.
        Returns: { center = {x,y,z}, width, height, axis, normal }

        Note: With shells touching, the shared wall surface is between the two shells.
        Each shell extends wallThickness beyond the inner dims.
    --]]
    local function calculateSharedWall(self, roomA, roomB, axis, direction)
        local state = getState(self)
        local wallThickness = state.config.wallThickness

        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        -- Wall position is at the shell boundary (inner edge + wallThickness)
        -- This is where the two room shells meet
        local wallPos = posA[axis] + (dimsA[axis] / 2 + wallThickness) * direction

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
        local sideMargin = 2  -- Keep doors away from side edges
        local floorCut = 1    -- Cut slightly into floor to ensure clean threshold

        -- Available space (margin on sides, but door goes to floor)
        local availableWidth = sharedWall.width - sideMargin * 2
        local availableHeight = sharedWall.height  -- Full height available

        if availableWidth < minSize or availableHeight < minSize then
            -- Shared wall too small for a door
            print(string.format("[DoorwayCutter] Shared wall too small: %.1fx%.1f",
                sharedWall.width, sharedWall.height))
            return nil
        end

        -- Door size: 60-80% of available space, clamped to reasonable bounds
        local doorWidth = math.min(availableWidth * 0.75, 12)  -- Max 12 studs wide
        doorWidth = math.max(doorWidth, minSize)

        local doorHeight = math.min(availableHeight * 0.85, 12)  -- Max 12 studs tall
        doorHeight = math.max(doorHeight, minSize)

        -- Ensure door fits within available space
        doorWidth = math.min(doorWidth, availableWidth)
        doorHeight = math.min(doorHeight, availableHeight)

        -- Position: centered horizontally, starts at floor level
        local doorCenter = {
            sharedWall.center[1],
            sharedWall.center[2],
            sharedWall.center[3],
        }

        -- Put door at floor level (cut slightly below to ensure no lip)
        local wallBottom = sharedWall.center[sharedWall.heightAxis] - sharedWall.height / 2
        doorCenter[sharedWall.heightAxis] = wallBottom - floorCut + doorHeight / 2

        -- Door depth: cut generously through both walls and floor
        local doorDepth = config.wallThickness * 6 + 2

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
        Find shell parts that intersect with the doorway position.
        With the CSG shell approach, each room has 1 shell instead of 6 slabs.
    --]]
    local function findShellsToCut(self, doorway, fromRoomId, toRoomId)
        local state = getState(self)
        local container = state.container
        if not container then
            warn("[DoorwayCutter] No container set!")
            return {}
        end

        local doorPos = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])
        local doorSize = Vector3.new(doorway.size[1], doorway.size[2], doorway.size[3])

        local shells = {}
        local shellCount = 0

        -- Search for Room models and their shells
        for _, child in ipairs(container:GetDescendants()) do
            if child:IsA("BasePart") and child.Name == "Shell" then
                shellCount = shellCount + 1

                -- Get the shell's bounding box (CSG parts may have complex geometry)
                local shellCF = child.CFrame
                local shellSize = child.Size

                -- Simple AABB intersection check with some margin
                local margin = 0.5
                local shellPos = shellCF.Position
                local shellMin = shellPos - shellSize / 2 - Vector3.new(margin, margin, margin)
                local shellMax = shellPos + shellSize / 2 + Vector3.new(margin, margin, margin)
                local doorMin = doorPos - doorSize / 2
                local doorMax = doorPos + doorSize / 2

                local overlaps =
                    shellMin.X < doorMax.X and shellMax.X > doorMin.X and
                    shellMin.Y < doorMax.Y and shellMax.Y > doorMin.Y and
                    shellMin.Z < doorMax.Z and shellMax.Z > doorMin.Z

                if overlaps then
                    table.insert(shells, child)
                end
            end
        end

        print(string.format("[DoorwayCutter] Searched %d shells, found %d intersecting", shellCount, #shells))

        return shells
    end

    --[[
        Cut a hole through a shell using CSG subtraction.
    --]]
    local function cutShell(self, shell, cutterPart)
        local parent = shell.Parent
        local shellName = shell.Name
        local shellMaterial = shell.Material
        local shellColor = shell.Color
        local shellTransparency = shell.Transparency

        print(string.format("[DoorwayCutter] Cutting shell at %s", tostring(shell.Position)))

        local success, result = pcall(function()
            return shell:SubtractAsync({ cutterPart })
        end)

        if success and result then
            result.Name = shellName
            result.Material = shellMaterial
            result.Color = shellColor
            result.Transparency = shellTransparency
            result.Anchored = true
            result.CanCollide = true
            result.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
            result.Parent = parent

            shell:Destroy()

            print(string.format("[DoorwayCutter] Successfully cut shell"))
            return result
        else
            warn("[DoorwayCutter] CSG subtract failed:", tostring(result))
            return nil
        end
    end

    --[[
        Create the door cutter and cut through shells.
        With CSG shell approach, we cut 1 shell per room (2 total for each doorway).
    --]]
    local function createDoorway(self, doorway, sharedWall, fromRoomId, toRoomId)
        local state = getState(self)

        -- Create cutter part
        -- CRITICAL: Must be in workspace for SubtractAsync to work
        local cutterPart = Instance.new("Part")
        cutterPart.Name = string.format("DoorCutter_%d_%d", fromRoomId, toRoomId)
        cutterPart.Size = Vector3.new(doorway.size[1], doorway.size[2], doorway.size[3])
        cutterPart.Position = Vector3.new(doorway.center[1], doorway.center[2], doorway.center[3])
        cutterPart.Anchored = true
        cutterPart.CanCollide = false
        cutterPart.Parent = workspace  -- Must be in DataModel for CSG

        -- Find shells to cut (should be 2: one per room)
        local shells = findShellsToCut(self, doorway, fromRoomId, toRoomId)

        print(string.format("[DoorwayCutter] Found %d shells to cut for doorway %d<->%d",
            #shells, fromRoomId, toRoomId))

        -- Cut each shell
        for _, shell in ipairs(shells) do
            cutShell(self, shell, cutterPart)
        end

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
                        local axis, direction = findAdjacencyAxis(self, roomA, roomB)

                        if axis then
                            -- Calculate shared wall
                            local sharedWall = calculateSharedWall(self, roomA, roomB, axis, direction)

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
                    local shellCount = 0
                    for _, child in ipairs(state.container:GetDescendants()) do
                        if child:IsA("BasePart") then
                            partCount = partCount + 1
                            if child.Name == "Shell" then
                                shellCount = shellCount + 1
                            end
                        end
                    end
                    print(string.format("[DoorwayCutter] Container has %d parts, %d shells", partCount, shellCount))
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
