--[[
    LibPureFiction Framework v2
    RoomBlocker.lua - Path-to-Geometry Block Generator

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    RoomBlocker converts PathGraph output into block geometry for rooms and
    hallways. It creates simple box volumes that can be used for:
    - Collision/navmesh generation
    - Visual blockout/greybox levels
    - Input to more detailed room generators

    The node derives the base unit by finding the GCD of all segment lengths,
    ensuring consistency with the original PathGraph generation.

    ============================================================================
    GEOMETRY RULES
    ============================================================================

    All geometry is created as full-height 3D volumes (extruded boxes).

    HALLWAYS (along segments):
        - Width/depth = baseUnit × hallScale
        - Height = baseUnit × heightScale
        - Length = segment length
        - Stretched along segment direction
        - Bottom aligned to floor level

    ROOMS (at points):
        - Size based on connection count:
            - 1 connection (dead end): baseUnit × roomScale
            - 2 connections (corridor): baseUnit × hallScale (same as hall)
            - 3+ connections (junction): baseUnit × junctionScale
        - Height = baseUnit × heightScale
        - Bottom aligned to floor level
        - Centered horizontally on point position

    ============================================================================
    OVERLAP RESOLUTION
    ============================================================================

    RoomBlocker processes rooms in BFS order from the start point. Before
    placing each room, it checks for overlap with previously placed geometry.

    If overlap is detected:
    1. Calculate shift direction ALONG THE HALLWAY (not perpendicular)
    2. Shift the current point AND all downstream points by 1 baseUnit
    3. This effectively extends the hallway, maintaining orthogonality
    4. Repeat until no overlap (max 10 attempts)
    5. Update PathGraph with final positions

    Key: Shifts are along hallway directions, preserving orthogonal paths.
    PathGraph is updated to match, keeping it as the source of truth.

    ============================================================================
    HEIGHT VARIATION
    ============================================================================

    Room heights vary by type using multipliers on the base heightScale:

        - junctionHeightMult (1.5): Large intersection rooms - tall ceilings
        - startHeightMult (1.5): Starting room - grand entrance
        - goalHeightMult (1.5): Goal rooms - dramatic destination
        - deadendHeightMult (1.0): Dead-end rooms - normal height
        - corridorHeightMult (0.8): Corridor points - slightly cramped
        - hallHeightMult (1.0): Hallway segments - standard passage

    Final height = baseUnit × heightScale × typeHeightMult

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ hallScale?, heightScale?, roomScale?, junctionScale?,
                      junctionHeightMult?, startHeightMult?, goalHeightMult?,
                      pathGraphRef?, container?, ... })
            - Configure geometry parameters
            - pathGraphRef: Reference to PathGraph for overlap resolution updates

        onBuildFromPath(pathData)
            - Build geometry from PathGraph output
            - pathData: { points, segments, start, goals, seed }

        onClear()
            - Remove all generated geometry

    OUT (emits):
        built({ baseUnit, roomCount, hallwayCount, totalParts, shiftsApplied })
            - Emitted after geometry is built

        cleared()
            - Emitted after geometry is cleared

        geometry({ rooms, hallways })
            - Detailed geometry data for downstream nodes

        pointsShifted({ updates, shiftCount })
            - Emitted when overlaps required shifting points
            - updates: { [pointId] = {x, y, z}, ... }

    ============================================================================
    OUTPUT FORMAT
    ============================================================================

    The `geometry` signal provides:
    ```lua
    {
        rooms = {
            { pointId = 1, pos = {x,y,z}, size = {w,h,d}, type = "start" },
            { pointId = 2, pos = {x,y,z}, size = {w,h,d}, type = "junction" },
            { pointId = 3, pos = {x,y,z}, size = {w,h,d}, type = "deadend" },
        },
        hallways = {
            { segmentId = 1, from = 1, to = 2, pos = {x,y,z}, size = {w,h,d}, axis = "Z" },
        },
        baseUnit = 15,
    }
    ```

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local roomBlocker = RoomBlocker:new({ id = "RoomBlocker_1" })
    roomBlocker.Sys.onInit(roomBlocker)

    roomBlocker.In.onConfigure(roomBlocker, {
        hallScale = 1,
        heightScale = 2,
        roomScale = 1.5,
        junctionScale = 2,
    })

    -- Wire from PathGraph
    pathGraph.Out:Fire("path", pathData)
    roomBlocker.In.onBuildFromPath(roomBlocker, pathData)
    ```

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- ROOMBLOCKER NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local RoomBlocker = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Configuration
                config = {
                    hallScale = 1,       -- Hallway width as multiple of baseUnit
                    heightScale = 2,     -- Base height as multiple of baseUnit
                    roomScale = 1.5,     -- Dead-end room size multiplier
                    junctionScale = 2,   -- Junction room size multiplier
                    corridorScale = 1,   -- Corridor point size (same as hall)
                    -- Height multipliers per room type (applied on top of heightScale)
                    junctionHeightMult = 1.5,  -- Junctions are taller
                    startHeightMult = 1.5,     -- Start room is taller
                    goalHeightMult = 1.5,      -- Goal rooms are taller
                    deadendHeightMult = 1.0,   -- Dead ends normal height
                    corridorHeightMult = 0.8,  -- Corridors slightly shorter
                    hallHeightMult = 1.0,      -- Hallways normal height
                },

                -- Generation state
                pathData = nil,
                baseUnit = 15,

                -- Generated geometry
                parts = {},           -- Roblox Part instances
                geometryData = {      -- Structured data for downstream
                    rooms = {},
                    hallways = {},
                    baseUnit = 15,
                },

                -- Visual container
                container = nil,

                -- PathGraph reference for position updates
                pathGraphRef = nil,

                -- Spatial registry for overlap detection
                -- Each entry: { minX, minY, minZ, maxX, maxY, maxZ, id, type }
                placedAABBs = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- GCD CALCULATION
    ----------------------------------------------------------------------------

    --[[
        Calculate GCD of two numbers using Euclidean algorithm.
    --]]
    local function gcd(a, b)
        a = math.abs(math.floor(a + 0.5))
        b = math.abs(math.floor(b + 0.5))

        if a == 0 then return b end
        if b == 0 then return a end

        while b ~= 0 do
            a, b = b, a % b
        end

        return a
    end

    --[[
        Calculate GCD of an array of numbers.
    --]]
    local function gcdArray(numbers)
        if #numbers == 0 then return 1 end
        if #numbers == 1 then return numbers[1] end

        local result = numbers[1]
        for i = 2, #numbers do
            result = gcd(result, numbers[i])
            if result == 1 then
                return 1 -- Can't get smaller than 1
            end
        end

        return result
    end

    --[[
        Derive base unit from path data by finding GCD of all segment lengths.
    --]]
    local function deriveBaseUnit(pathData)
        local lengths = {}

        for _, seg in ipairs(pathData.segments) do
            local fromPoint = pathData.points[seg.from]
            local toPoint = pathData.points[seg.to]

            if fromPoint and toPoint then
                local dx = math.abs(toPoint.pos[1] - fromPoint.pos[1])
                local dy = math.abs(toPoint.pos[2] - fromPoint.pos[2])
                local dz = math.abs(toPoint.pos[3] - fromPoint.pos[3])

                -- For orthogonal segments, only one axis has non-zero length
                local length = dx + dy + dz
                if length > 0 then
                    table.insert(lengths, length)
                end
            end
        end

        local baseUnit = gcdArray(lengths)

        -- Sanity check - base unit should be reasonable
        if baseUnit < 1 then baseUnit = 1 end
        if baseUnit > 100 then baseUnit = 15 end -- Fallback

        return baseUnit
    end

    ----------------------------------------------------------------------------
    -- ROOM TYPE HELPERS (needed before AABB calculation)
    ----------------------------------------------------------------------------

    --[[
        Determine room type based on point properties.
    --]]
    local function getRoomType(pathData, pointId, connectionCount)
        if pointId == pathData.start then
            return "start"
        end

        for _, goalId in ipairs(pathData.goals or {}) do
            if pointId == goalId then
                return "goal"
            end
        end

        if connectionCount == 1 then
            return "deadend"
        elseif connectionCount == 2 then
            return "corridor"
        else
            return "junction"
        end
    end

    --[[
        Get room scale based on type.
    --]]
    local function getRoomScale(self, roomType)
        local state = getState(self)
        local config = state.config

        if roomType == "start" or roomType == "goal" then
            return config.junctionScale
        elseif roomType == "junction" then
            return config.junctionScale
        elseif roomType == "deadend" then
            return config.roomScale
        else -- corridor
            return config.corridorScale
        end
    end

    --[[
        Get height multiplier based on room type.
    --]]
    local function getRoomHeightMult(self, roomType)
        local state = getState(self)
        local config = state.config

        if roomType == "start" then
            return config.startHeightMult or 1.5
        elseif roomType == "goal" then
            return config.goalHeightMult or 1.5
        elseif roomType == "junction" then
            return config.junctionHeightMult or 1.5
        elseif roomType == "deadend" then
            return config.deadendHeightMult or 1.0
        else -- corridor
            return config.corridorHeightMult or 0.8
        end
    end

    ----------------------------------------------------------------------------
    -- AABB OVERLAP DETECTION
    ----------------------------------------------------------------------------

    --[[
        Create an AABB from center position and size.
        Returns { minX, minY, minZ, maxX, maxY, maxZ }
    --]]
    local function createAABB(centerX, centerY, centerZ, sizeX, sizeY, sizeZ)
        local halfX = sizeX / 2
        local halfY = sizeY / 2
        local halfZ = sizeZ / 2
        return {
            minX = centerX - halfX,
            minY = centerY - halfY,
            minZ = centerZ - halfZ,
            maxX = centerX + halfX,
            maxY = centerY + halfY,
            maxZ = centerZ + halfZ,
        }
    end

    --[[
        Check if two AABBs overlap.
        Uses a small epsilon to allow touching but not overlapping.
    --]]
    local function aabbsOverlap(a, b, epsilon)
        epsilon = epsilon or 0.1
        return (a.minX < b.maxX - epsilon and a.maxX > b.minX + epsilon) and
               (a.minY < b.maxY - epsilon and a.maxY > b.minY + epsilon) and
               (a.minZ < b.maxZ - epsilon and a.maxZ > b.minZ + epsilon)
    end

    --[[
        Check if a new AABB overlaps with any existing placed geometry.
        Returns the first overlapping AABB or nil.
    --]]
    local function checkOverlap(self, newAABB)
        local state = getState(self)
        for _, placed in ipairs(state.placedAABBs) do
            if aabbsOverlap(newAABB, placed) then
                return placed
            end
        end
        return nil
    end

    --[[
        Register an AABB in the spatial registry.
    --]]
    local function registerAABB(self, aabb, id, geomType)
        local state = getState(self)
        aabb.id = id
        aabb.type = geomType
        table.insert(state.placedAABBs, aabb)
    end

    --[[
        Calculate room AABB without creating the part.
    --]]
    local function calculateRoomAABB(self, point, roomType)
        local state = getState(self)
        local config = state.config
        local baseUnit = state.baseUnit

        local scale = getRoomScale(self, roomType)
        local heightMult = getRoomHeightMult(self, roomType)
        local size = baseUnit * scale
        local height = baseUnit * config.heightScale * heightMult

        local pos = point.pos
        local centerY = pos[2] + height / 2

        return createAABB(pos[1], centerY, pos[3], size, height, size), size, height
    end

    --[[
        Calculate hallway AABB without creating the part.
    --]]
    local function calculateHallwayAABB(self, fromPoint, toPoint)
        local state = getState(self)
        local config = state.config
        local baseUnit = state.baseUnit

        local fromPos = fromPoint.pos
        local toPos = toPoint.pos

        local dx = toPos[1] - fromPos[1]
        local dy = toPos[2] - fromPos[2]
        local dz = toPos[3] - fromPos[3]

        local length = math.abs(dx) + math.abs(dy) + math.abs(dz)
        if length < 1 then return nil end

        local midX = (fromPos[1] + toPos[1]) / 2
        local midY = (fromPos[2] + toPos[2]) / 2
        local midZ = (fromPos[3] + toPos[3]) / 2

        local hallSize = baseUnit * config.hallScale
        local hallHeightMult = config.hallHeightMult or 1.0
        local height = baseUnit * config.heightScale * hallHeightMult

        local sizeX, sizeY, sizeZ, axis

        if math.abs(dx) > 0.1 then
            axis = "X"
            sizeX = length
            sizeY = height
            sizeZ = hallSize
        elseif math.abs(dz) > 0.1 then
            axis = "Z"
            sizeX = hallSize
            sizeY = height
            sizeZ = length
        else
            axis = "Y"
            sizeX = hallSize
            sizeY = length
            sizeZ = hallSize
        end

        local floorY = math.min(fromPos[2], toPos[2])
        local centerY = (axis == "Y") and midY or (floorY + height / 2)

        return createAABB(midX, centerY, midZ, sizeX, sizeY, sizeZ), sizeX, sizeY, sizeZ, axis
    end

    --[[
        Get downstream points from a given point (BFS traversal away from source).
        Returns a set of point IDs that are "downstream" from the given point.
    --]]
    local function getDownstreamPoints(pathData, pointId, cameFromId)
        local downstream = {}
        local queue = { pointId }
        local visited = { [pointId] = true }
        if cameFromId then
            visited[cameFromId] = true  -- Don't go back
        end

        while #queue > 0 do
            local current = table.remove(queue, 1)
            downstream[current] = true

            local point = pathData.points[current]
            if point then
                for _, connId in ipairs(point.connections) do
                    if not visited[connId] then
                        visited[connId] = true
                        table.insert(queue, connId)
                    end
                end
            end
        end

        return downstream
    end

    --[[
        Shift a point position by the given offset.
    --]]
    local function shiftPoint(pathData, pointId, offsetX, offsetY, offsetZ)
        local point = pathData.points[pointId]
        if point then
            point.pos[1] = point.pos[1] + offsetX
            point.pos[2] = point.pos[2] + offsetY
            point.pos[3] = point.pos[3] + offsetZ
        end
    end

    --[[
        Calculate shift direction along the hallway axis.
        This maintains orthogonality by extending the hallway rather than shifting perpendicular.
    --]]
    local function calculateShiftAlongHallway(pathData, pointId, cameFromId)
        if not cameFromId then
            -- Start point has no incoming hallway, shift along X by default
            return 1, 0, 0
        end

        local currentPoint = pathData.points[pointId]
        local fromPoint = pathData.points[cameFromId]

        if not currentPoint or not fromPoint then
            return 1, 0, 0
        end

        -- Get direction from cameFrom to current (the hallway direction)
        local dx = currentPoint.pos[1] - fromPoint.pos[1]
        local dy = currentPoint.pos[2] - fromPoint.pos[2]
        local dz = currentPoint.pos[3] - fromPoint.pos[3]

        -- Normalize to unit direction along dominant axis
        local ax, ay, az = math.abs(dx), math.abs(dy), math.abs(dz)

        if ax >= ay and ax >= az then
            return dx > 0 and 1 or -1, 0, 0
        elseif az >= ax and az >= ay then
            return 0, 0, dz > 0 and 1 or -1
        else
            return 0, dy > 0 and 1 or -1, 0
        end
    end

    ----------------------------------------------------------------------------
    -- GEOMETRY CREATION
    ----------------------------------------------------------------------------

    --[[
        Get color based on room type.
    --]]
    local function getRoomColor(roomType)
        local colors = {
            start = Color3.fromRGB(100, 200, 100),     -- Green
            goal = Color3.fromRGB(200, 180, 50),       -- Gold
            junction = Color3.fromRGB(150, 150, 200),  -- Light blue
            deadend = Color3.fromRGB(200, 100, 100),   -- Red
            corridor = Color3.fromRGB(120, 120, 140),  -- Gray
        }
        return colors[roomType] or Color3.fromRGB(128, 128, 128)
    end

    --[[
        Create a room block at a point.
    --]]
    local function createRoomBlock(self, pointId, point, roomType)
        local state = getState(self)
        local config = state.config
        local baseUnit = state.baseUnit

        local scale = getRoomScale(self, roomType)
        local heightMult = getRoomHeightMult(self, roomType)
        local size = baseUnit * scale
        local height = baseUnit * config.heightScale * heightMult

        local pos = point.pos

        -- Create full-height room volume
        local room = Instance.new("Part")
        room.Name = "Room_" .. pointId
        room.Size = Vector3.new(size, height, size)
        -- Position so bottom of box is at floor level
        room.Position = Vector3.new(pos[1], pos[2] + height / 2, pos[3])
        room.Anchored = true
        room.CanCollide = true
        room.Material = Enum.Material.SmoothPlastic
        room.Color = getRoomColor(roomType)
        room.Transparency = 0.3
        room.Parent = state.container

        table.insert(state.parts, room)

        -- Debug: print first room created
        if #state.parts == 1 then
            print("[RoomBlocker] First room:", room.Name, "Pos:", room.Position, "Size:", room.Size)
        end

        -- Store geometry data
        table.insert(state.geometryData.rooms, {
            pointId = pointId,
            pos = { pos[1], pos[2], pos[3] },
            size = { size, height, size },
            type = roomType,
            connectionCount = #point.connections,
        })

        return room
    end

    --[[
        Create a hallway block along a segment.
    --]]
    local function createHallwayBlock(self, segment, fromPoint, toPoint)
        local state = getState(self)
        local config = state.config
        local baseUnit = state.baseUnit

        local fromPos = fromPoint.pos
        local toPos = toPoint.pos

        -- Calculate direction and length
        local dx = toPos[1] - fromPos[1]
        local dy = toPos[2] - fromPos[2]
        local dz = toPos[3] - fromPos[3]

        local length = math.abs(dx) + math.abs(dy) + math.abs(dz)
        if length < 1 then return nil end

        -- Determine axis and dimensions
        local axis
        local midX = (fromPos[1] + toPos[1]) / 2
        local midY = (fromPos[2] + toPos[2]) / 2
        local midZ = (fromPos[3] + toPos[3]) / 2

        local hallSize = baseUnit * config.hallScale
        local hallHeightMult = config.hallHeightMult or 1.0
        local height = baseUnit * config.heightScale * hallHeightMult

        local sizeX, sizeY, sizeZ

        if math.abs(dx) > 0.1 then
            -- X-axis hallway
            axis = "X"
            sizeX = length
            sizeY = height
            sizeZ = hallSize
        elseif math.abs(dz) > 0.1 then
            -- Z-axis hallway
            axis = "Z"
            sizeX = hallSize
            sizeY = height
            sizeZ = length
        else
            -- Y-axis (vertical shaft)
            axis = "Y"
            sizeX = hallSize
            sizeY = length
            sizeZ = hallSize
        end

        -- Create full-height hallway volume
        local hall = Instance.new("Part")
        hall.Name = "Hall_" .. segment.id

        hall.Size = Vector3.new(sizeX, sizeY, sizeZ)

        -- Position so bottom is at floor level
        local floorY = math.min(fromPos[2], toPos[2])
        if axis == "Y" then
            -- Vertical shaft: center on midpoint
            hall.Position = Vector3.new(midX, midY, midZ)
        else
            -- Horizontal hallway: bottom at floor level
            hall.Position = Vector3.new(midX, floorY + height / 2, midZ)
        end

        hall.Anchored = true
        hall.CanCollide = true
        hall.Material = Enum.Material.SmoothPlastic
        hall.Color = Color3.fromRGB(100, 100, 120)
        hall.Transparency = 0.3
        hall.Parent = state.container

        table.insert(state.parts, hall)

        -- Store geometry data
        table.insert(state.geometryData.hallways, {
            segmentId = segment.id,
            from = segment.from,
            to = segment.to,
            pos = { midX, floorY, midZ },
            size = { sizeX, sizeY, sizeZ },
            axis = axis,
            length = length,
        })

        return hall
    end

    --[[
        Build all geometry from path data with overlap detection and resolution.
        Processes rooms in BFS order from start, shifting downstream points when overlaps occur.
    --]]
    local function buildGeometry(self, pathData)
        local state = getState(self)

        -- Work directly on pathData - shifts will be along hallway directions
        -- to maintain orthogonality. PathGraph will be updated with final positions.
        state.pathData = pathData

        -- Derive base unit from segment lengths
        state.baseUnit = deriveBaseUnit(pathData)
        state.geometryData.baseUnit = state.baseUnit

        print("[RoomBlocker] Derived baseUnit:", state.baseUnit)

        -- Create container if needed
        if not state.container then
            print("[RoomBlocker] WARNING: Container not set, checking attribute...")
            state.container = self:getAttribute("container")
            if not state.container then
                print("[RoomBlocker] Creating new container folder")
                state.container = Instance.new("Folder")
                state.container.Name = self.id .. "_Geometry"
                state.container.Parent = workspace
            end
        else
            print("[RoomBlocker] Using existing container:", state.container.Name)
        end

        -- Clear existing geometry data and spatial registry
        state.geometryData.rooms = {}
        state.geometryData.hallways = {}
        state.placedAABBs = {}

        -- Track which segments we've built (keyed by "from-to" sorted)
        local builtSegments = {}
        local function segmentKey(a, b)
            if a < b then return a .. "-" .. b else return b .. "-" .. a end
        end


        -- BFS traversal from start point
        local queue = {}
        local visited = {}
        local processOrder = {}

        -- Start from the start point
        if pathData.start and pathData.points[pathData.start] then
            table.insert(queue, { pointId = pathData.start, cameFrom = nil })
            visited[pathData.start] = true
        end

        -- BFS to determine processing order
        while #queue > 0 do
            local current = table.remove(queue, 1)
            table.insert(processOrder, current)

            local point = pathData.points[current.pointId]
            if point then
                for _, connId in ipairs(point.connections) do
                    if not visited[connId] then
                        visited[connId] = true
                        table.insert(queue, { pointId = connId, cameFrom = current.pointId })
                    end
                end
            end
        end

        -- Debug: count total points
        local totalPoints = 0
        for _ in pairs(pathData.points) do totalPoints = totalPoints + 1 end
        print("[RoomBlocker] BFS processOrder:", #processOrder, "points, pathData has:", totalPoints, "points")

        -- Process rooms in BFS order with overlap detection
        local shiftsApplied = 0
        for _, entry in ipairs(processOrder) do
            local pointId = entry.pointId
            local cameFrom = entry.cameFrom
            local point = pathData.points[pointId]

            if point then
                local roomType = getRoomType(pathData, pointId, #point.connections)
                local roomAABB = calculateRoomAABB(self, point, roomType)

                -- Check for overlap with existing geometry
                local overlap = checkOverlap(self, roomAABB)
                local shiftAttempts = 0
                local maxShiftAttempts = 10

                while overlap and shiftAttempts < maxShiftAttempts do
                    shiftAttempts = shiftAttempts + 1

                    -- Calculate shift direction ALONG the hallway (maintains orthogonality)
                    local shiftX, shiftY, shiftZ = calculateShiftAlongHallway(pathData, pointId, cameFrom)
                    local shiftAmount = state.baseUnit

                    -- Get all downstream points (everything reachable from this point, excluding where we came from)
                    local downstream = getDownstreamPoints(pathData, pointId, cameFrom)

                    -- Shift all downstream points along the hallway direction
                    for downstreamId in pairs(downstream) do
                        shiftPoint(pathData, downstreamId, shiftX * shiftAmount, shiftY * shiftAmount, shiftZ * shiftAmount)
                    end

                    shiftsApplied = shiftsApplied + 1

                    -- Recalculate AABB with new position
                    roomAABB = calculateRoomAABB(self, point, roomType)
                    overlap = checkOverlap(self, roomAABB)
                end

                if overlap then
                    print("[RoomBlocker] WARNING: Could not resolve overlap for point", pointId, "after", maxShiftAttempts, "attempts")
                end

                -- Register and create the room
                registerAABB(self, roomAABB, pointId, "room")
                createRoomBlock(self, pointId, point, roomType)

                -- Build hallways to this point (from previously visited neighbors)
                for _, connId in ipairs(point.connections) do
                    local key = segmentKey(pointId, connId)
                    if visited[connId] and not builtSegments[key] then
                        builtSegments[key] = true

                        -- Find the segment
                        for _, segment in ipairs(pathData.segments) do
                            if (segment.from == pointId and segment.to == connId) or
                               (segment.from == connId and segment.to == pointId) then
                                local fromPoint = pathData.points[segment.from]
                                local toPoint = pathData.points[segment.to]

                                if fromPoint and toPoint then
                                    local hallAABB = calculateHallwayAABB(self, fromPoint, toPoint)
                                    if hallAABB then
                                        -- Note: We don't check hallway overlaps since they connect rooms
                                        -- and overlapping with rooms at endpoints is expected
                                        registerAABB(self, hallAABB, segment.id, "hallway")
                                        createHallwayBlock(self, segment, fromPoint, toPoint)
                                    end
                                end
                                break
                            end
                        end
                    end
                end
            end
        end

        if shiftsApplied > 0 then
            print("[RoomBlocker] Applied", shiftsApplied, "shifts along hallway directions")

            -- Update PathGraph with final positions (maintains orthogonality)
            if state.pathGraphRef then
                local updates = {}
                for pointId, point in pairs(pathData.points) do
                    updates[pointId] = { point.pos[1], point.pos[2], point.pos[3] }
                end

                state.pathGraphRef.In.onUpdatePoints(state.pathGraphRef, {
                    updates = updates,
                    reemit = false,
                })
                print("[RoomBlocker] Updated PathGraph with shifted positions")
            end

            -- Emit signal for orchestrator
            self.Out:Fire("pointsShifted", {
                shiftCount = shiftsApplied,
            })
        end

        print("[RoomBlocker] Created", #state.parts, "parts in container:", state.container.Name)
        print("[RoomBlocker] Container child count:", #state.container:GetChildren())

        -- Emit signals
        self.Out:Fire("geometry", state.geometryData)

        self.Out:Fire("built", {
            baseUnit = state.baseUnit,
            roomCount = #state.geometryData.rooms,
            hallwayCount = #state.geometryData.hallways,
            totalParts = #state.parts,
            shiftsApplied = shiftsApplied,
        })
    end

    --[[
        Clear all generated geometry.
    --]]
    local function clearGeometry(self)
        local state = getState(self)

        -- Destroy all parts
        for _, part in ipairs(state.parts) do
            if part and part.Parent then
                part:Destroy()
            end
        end

        state.parts = {}
        state.geometryData = {
            rooms = {},
            hallways = {},
            baseUnit = state.baseUnit,
        }

        self.Out:Fire("cleared", {})
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
                clearGeometry(self)
                cleanupState(self)
            end,
        },

        In = {
            --[[
                Configure geometry parameters.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)
                local config = state.config

                if data.hallScale then config.hallScale = data.hallScale end
                if data.heightScale then config.heightScale = data.heightScale end
                if data.roomScale then config.roomScale = data.roomScale end
                if data.junctionScale then config.junctionScale = data.junctionScale end
                if data.corridorScale then config.corridorScale = data.corridorScale end

                -- Height multipliers per room type
                if data.junctionHeightMult then config.junctionHeightMult = data.junctionHeightMult end
                if data.startHeightMult then config.startHeightMult = data.startHeightMult end
                if data.goalHeightMult then config.goalHeightMult = data.goalHeightMult end
                if data.deadendHeightMult then config.deadendHeightMult = data.deadendHeightMult end
                if data.corridorHeightMult then config.corridorHeightMult = data.corridorHeightMult end
                if data.hallHeightMult then config.hallHeightMult = data.hallHeightMult end

                -- Allow setting container
                if data.container then
                    state.container = data.container
                    print("[RoomBlocker] Container set via configure:", state.container.Name)
                end

                -- PathGraph reference for position update notifications
                if data.pathGraphRef then
                    state.pathGraphRef = data.pathGraphRef
                    print("[RoomBlocker] PathGraph reference set")
                end
            end,

            --[[
                Build geometry from PathGraph output.
            --]]
            onBuildFromPath = function(self, pathData)
                if not pathData then
                    self.Err:Fire({ reason = "no_path_data", message = "Path data required" })
                    return
                end

                if not pathData.points or not pathData.segments then
                    self.Err:Fire({ reason = "invalid_path_data", message = "Path data must have points and segments" })
                    return
                end

                -- Clear existing geometry first
                clearGeometry(self)

                -- Build new geometry
                buildGeometry(self, pathData)
            end,

            --[[
                Clear all generated geometry.
            --]]
            onClear = function(self)
                clearGeometry(self)
            end,
        },

        Out = {
            built = {},         -- { baseUnit, roomCount, hallwayCount, totalParts, shiftsApplied }
            cleared = {},       -- {}
            geometry = {},      -- { rooms, hallways, baseUnit }
            pointsShifted = {}, -- { updates, shiftCount } - emitted when overlaps required shifts
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        --[[
            Get the derived base unit.
        --]]
        getBaseUnit = function(self)
            local state = getState(self)
            return state.baseUnit
        end,

        --[[
            Get all geometry data.
        --]]
        getGeometry = function(self)
            local state = getState(self)
            return state.geometryData
        end,

        --[[
            Get room data for a specific point.
        --]]
        getRoomForPoint = function(self, pointId)
            local state = getState(self)
            for _, room in ipairs(state.geometryData.rooms) do
                if room.pointId == pointId then
                    return room
                end
            end
            return nil
        end,

        --[[
            Get hallway data for a specific segment.
        --]]
        getHallwayForSegment = function(self, segmentId)
            local state = getState(self)
            for _, hallway in ipairs(state.geometryData.hallways) do
                if hallway.segmentId == segmentId then
                    return hallway
                end
            end
            return nil
        end,

        --[[
            Get the geometry container.
        --]]
        getContainer = function(self)
            local state = getState(self)
            return state.container
        end,
    }
end)

return RoomBlocker
