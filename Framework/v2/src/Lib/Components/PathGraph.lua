--[[
    LibPureFiction Framework v2
    PathGraph.lua - Procedural Path/Maze Graph Generator

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    PathGraph generates abstract navigation graphs for procedural maps.
    It creates the topology (points and connections) without actual geometry.
    Downstream nodes translate this into room layouts, HUD maps, etc.

    The output is a graph structure:
    - Points: Vertices with 3D positions and connection lists
    - Segments: Edges connecting points

    Key features:
    - Seed-based deterministic generation (reproducible maps)
    - Spatial index prevents overlapping/intersecting paths
    - Through-path generation (start to goal(s))
    - Spur generation (dead-end branches)
    - Loop generation (paths that reconnect)
    - Recursive composition (extend existing paths)
    - Bulk or streamed output modes
    - Sync mode for room packer adjustments

    ============================================================================
    OUTPUT FORMAT
    ============================================================================

    ```lua
    {
        points = {
            [1] = { pos = {0, 0, 0}, connections = {2} },
            [2] = { pos = {0, 0, 45}, connections = {1, 3, 5} },
            [3] = { pos = {45, 0, 45}, connections = {2, 4} },
            [4] = { pos = {45, 0, 90}, connections = {3} },
            [5] = { pos = {-30, 0, 45}, connections = {2} },
        },
        segments = {
            { id = 1, from = 1, to = 2 },
            { id = 2, from = 2, to = 3 },
            { id = 3, from = 3, to = 4 },
            { id = 4, from = 2, to = 5 },
        },
        start = 1,
        goals = {4},
        seed = "abc123",
    }
    ```

    Point connection count indicates type:
    - 1 connection: terminus (start, goal, or spur dead-end)
    - 2 connections: corridor/through point
    - 3+ connections: junction

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit, seed?, spurCount?, loopCount?, ... })
        onGenerate({ start, goals?, existingPath? })
        onRequestPage() - (Streamed mode)
        onAdjust({ pointId, newPos }) - (Sync mode)
        onExtend({ existingPath, start, goals? })

    OUT (emits):
        path({ points, segments, start, goals, seed, page?, isComplete? })
        complete({ seed, totalPoints, totalSegments })
        pageBuffered({ page }) - (Streamed mode)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local pathGraph = PathGraph:new({ id = "Maze_1" })
    pathGraph.Sys.onInit(pathGraph)

    pathGraph.In.onConfigure(pathGraph, {
        baseUnit = 15,
        spurCount = { min = 3, max = 8 },
        loopCount = { min = 1, max = 3 },
        maxSegments = 50,
    })

    pathGraph.In.onGenerate(pathGraph, {
        start = {0, 0, 0},
        goals = {{300, 0, 300}},
    })
    ```

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- PATHGRAPH NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local PathGraph = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    -- Direction vectors (unit movements)
    local DIRECTIONS = {
        N = { 0, 0, 1 },   -- +Z
        S = { 0, 0, -1 },  -- -Z
        E = { 1, 0, 0 },   -- +X
        W = { -1, 0, 0 },  -- -X
        U = { 0, 1, 0 },   -- +Y
        D = { 0, -1, 0 },  -- -Y
    }

    -- Opposite directions (for reversal prevention)
    local OPPOSITES = {
        N = "S", S = "N",
        E = "W", W = "E",
        U = "D", D = "U",
    }

    -- Direction list for random selection
    local DIR_LIST = { "N", "S", "E", "W", "U", "D" }

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Configuration
                config = {
                    baseUnit = 15,
                    seed = nil,
                    spurCount = { min = 2, max = 6 },
                    loopCount = { min = 1, max = 3 },
                    switchbackChance = 0.2,
                    maxSegments = 100,
                    bounds = nil,
                    mode = "bulk",
                    pageSize = 10,
                },

                -- RNG state
                rng = nil,
                seed = nil,

                -- Generation state
                generating = false,
                points = {},           -- { [id] = { pos = {x,y,z}, connections = {} } }
                segments = {},         -- { { id, from, to } }
                pointCounter = 0,
                segmentCounter = 0,
                startPointId = nil,
                goalPointIds = {},

                -- Spatial index for collision detection
                -- Key: "x,y,z" -> pointId
                positionIndex = {},

                -- Streamed mode state
                currentPage = 0,
                bufferedPage = nil,
                isComplete = false,
                handshakeReceived = false,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- RNG (Seeded Random Number Generator)
    ----------------------------------------------------------------------------

    local function createRNG(seed)
        local state
        if type(seed) == "string" then
            state = 0
            for i = 1, #seed do
                state = state + seed:byte(i) * (i * 31)
            end
            state = bit32.band(state, 0xFFFFFFFF)
            if state == 0 then state = 1 end
        else
            state = seed or os.time()
            if state == 0 then state = 1 end
        end

        local rng = {}

        function rng:next()
            state = bit32.bxor(state, bit32.lshift(state, 13))
            state = bit32.bxor(state, bit32.rshift(state, 17))
            state = bit32.bxor(state, bit32.lshift(state, 5))
            state = bit32.band(state, 0xFFFFFFFF)
            return state
        end

        function rng:random()
            return self:next() / 0x100000000
        end

        function rng:randomInt(min, max)
            return min + (self:next() % (max - min + 1))
        end

        function rng:randomChoice(array)
            if #array == 0 then return nil end
            return array[self:randomInt(1, #array)]
        end

        function rng:shuffle(array)
            for i = #array, 2, -1 do
                local j = self:randomInt(1, i)
                array[i], array[j] = array[j], array[i]
            end
            return array
        end

        return rng
    end

    local function generateSeed()
        local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        local result = ""
        for _ = 1, 12 do
            local idx = math.random(1, #chars)
            result = result .. chars:sub(idx, idx)
        end
        return result
    end

    ----------------------------------------------------------------------------
    -- SPATIAL INDEX
    ----------------------------------------------------------------------------

    local function posKey(x, y, z)
        -- Round to base unit to handle floating point
        return string.format("%d,%d,%d",
            math.floor(x + 0.5),
            math.floor(y + 0.5),
            math.floor(z + 0.5))
    end

    local function posKeyFromArray(pos)
        return posKey(pos[1], pos[2], pos[3])
    end

    --[[
        Check if a position is already occupied by a point.
        Returns pointId if occupied, nil if free.
    --]]
    local function getPointAtPosition(self, x, y, z)
        local state = getState(self)
        local key = posKey(x, y, z)
        return state.positionIndex[key]
    end

    --[[
        Register a point's position in the spatial index.
    --]]
    local function registerPosition(self, pointId, x, y, z)
        local state = getState(self)
        local key = posKey(x, y, z)
        state.positionIndex[key] = pointId
    end

    ----------------------------------------------------------------------------
    -- BOUNDS CHECKING
    ----------------------------------------------------------------------------

    local function isInBounds(self, x, y, z)
        local state = getState(self)
        local bounds = state.config.bounds

        if not bounds then
            return true
        end

        if bounds.x and (x < bounds.x[1] or x > bounds.x[2]) then
            return false
        end
        if bounds.y and (y < bounds.y[1] or y > bounds.y[2]) then
            return false
        end
        if bounds.z and (z < bounds.z[1] or z > bounds.z[2]) then
            return false
        end

        return true
    end

    ----------------------------------------------------------------------------
    -- POINT & SEGMENT MANAGEMENT
    ----------------------------------------------------------------------------

    --[[
        Create a new point at a specific position.
        Returns pointId, or nil if position is occupied.
    --]]
    local function createPoint(self, x, y, z)
        local state = getState(self)

        -- Check if position is already occupied
        local existingId = getPointAtPosition(self, x, y, z)
        if existingId then
            return nil, existingId -- Return existing point ID
        end

        -- Check bounds
        if not isInBounds(self, x, y, z) then
            return nil, nil
        end

        state.pointCounter = state.pointCounter + 1
        local id = state.pointCounter

        state.points[id] = {
            pos = { x, y, z },
            connections = {},
        }

        -- Register in spatial index
        registerPosition(self, id, x, y, z)

        return id, nil
    end

    --[[
        Check if two points are already connected.
    --]]
    local function areConnected(self, pointA, pointB)
        local state = getState(self)
        local pointDataA = state.points[pointA]
        if not pointDataA then return false end

        for _, conn in ipairs(pointDataA.connections) do
            if conn == pointB then
                return true
            end
        end
        return false
    end

    --[[
        Create a segment between two points.
        Returns segment, or nil if already connected.
    --]]
    local function createSegment(self, fromId, toId)
        local state = getState(self)

        -- Don't create duplicate connections
        if areConnected(self, fromId, toId) then
            return nil
        end

        state.segmentCounter = state.segmentCounter + 1

        local segment = {
            id = state.segmentCounter,
            from = fromId,
            to = toId,
        }

        table.insert(state.segments, segment)

        -- Update point connections
        table.insert(state.points[fromId].connections, toId)
        table.insert(state.points[toId].connections, fromId)

        return segment
    end

    --[[
        Get the direction from one point to another.
    --]]
    local function getDirection(fromPos, toPos)
        local dx = toPos[1] - fromPos[1]
        local dy = toPos[2] - fromPos[2]
        local dz = toPos[3] - fromPos[3]

        -- Determine primary axis
        local ax, ay, az = math.abs(dx), math.abs(dy), math.abs(dz)

        if ax >= ay and ax >= az then
            return dx > 0 and "E" or "W"
        elseif az >= ax and az >= ay then
            return dz > 0 and "N" or "S"
        else
            return dy > 0 and "U" or "D"
        end
    end

    --[[
        Get the last direction used to reach a point.
    --]]
    local function getLastDirection(self, pointId)
        local state = getState(self)
        local pointData = state.points[pointId]
        if not pointData or #pointData.connections == 0 then
            return nil
        end

        -- Find the segment that ends at this point (most recent)
        for i = #state.segments, 1, -1 do
            local seg = state.segments[i]
            if seg.to == pointId then
                local fromPos = state.points[seg.from].pos
                local toPos = pointData.pos
                return getDirection(fromPos, toPos)
            end
        end

        return nil
    end

    --[[
        Get valid directions from a point (excludes reversal and occupied positions).
    --]]
    local function getValidDirections(self, pointId, allowVertical)
        local state = getState(self)
        local pointData = state.points[pointId]
        if not pointData then return {} end

        local lastDir = getLastDirection(self, pointId)
        local opposite = lastDir and OPPOSITES[lastDir]
        local baseUnit = state.config.baseUnit
        local pos = pointData.pos

        local valid = {}
        for _, dir in ipairs(DIR_LIST) do
            -- Skip opposite direction (no immediate reversal)
            if dir ~= opposite then
                -- Skip vertical if not allowed
                if allowVertical or (dir ~= "U" and dir ~= "D") then
                    -- Check if at least one step in this direction is valid
                    local vec = DIRECTIONS[dir]
                    local newX = pos[1] + vec[1] * baseUnit
                    local newY = pos[2] + vec[2] * baseUnit
                    local newZ = pos[3] + vec[3] * baseUnit

                    if isInBounds(self, newX, newY, newZ) then
                        table.insert(valid, dir)
                    end
                end
            end
        end

        return valid
    end

    --[[
        Check if segment budget is exhausted.
    --]]
    local function isBudgetExhausted(self)
        local state = getState(self)
        return #state.segments >= state.config.maxSegments
    end

    ----------------------------------------------------------------------------
    -- PATH GENERATION ALGORITHMS
    ----------------------------------------------------------------------------

    --[[
        Try to extend path in a direction.
        Returns new pointId and position, or existing pointId if collision.
    --]]
    local function extendPath(self, fromId, dir, units)
        local state = getState(self)
        local baseUnit = state.config.baseUnit
        local fromData = state.points[fromId]
        local fromPos = fromData.pos

        local vec = DIRECTIONS[dir]
        local dist = baseUnit * units

        local newX = fromPos[1] + vec[1] * dist
        local newY = fromPos[2] + vec[2] * dist
        local newZ = fromPos[3] + vec[3] * dist

        -- Check for collision with existing point
        local existingId = getPointAtPosition(self, newX, newY, newZ)
        if existingId then
            -- Connect to existing point (creates a loop)
            if existingId ~= fromId and not areConnected(self, fromId, existingId) then
                createSegment(self, fromId, existingId)
                return existingId, state.points[existingId].pos, true -- true = was collision
            end
            return nil, nil, true
        end

        -- Check bounds
        if not isInBounds(self, newX, newY, newZ) then
            return nil, nil, false
        end

        -- Create new point
        local newId = createPoint(self, newX, newY, newZ)
        if newId then
            createSegment(self, fromId, newId)
            return newId, { newX, newY, newZ }, false
        end

        return nil, nil, false
    end

    --[[
        Generate a random walk path from a starting point.
    --]]
    local function generateRandomWalk(self, startId, minSteps, maxSteps, allowVertical)
        local state = getState(self)
        local rng = state.rng

        local currentId = startId
        local steps = rng:randomInt(minSteps, maxSteps)

        for _ = 1, steps do
            if isBudgetExhausted(self) then
                break
            end

            local validDirs = getValidDirections(self, currentId, allowVertical)
            if #validDirs == 0 then
                break
            end

            rng:shuffle(validDirs)

            local moved = false
            for _, dir in ipairs(validDirs) do
                local units = rng:randomInt(1, 4)
                local newId, _, wasCollision = extendPath(self, currentId, dir, units)

                if newId then
                    currentId = newId
                    moved = true
                    break
                elseif wasCollision then
                    -- Collision created a loop, try different direction
                end
            end

            if not moved then
                break
            end
        end

        return currentId
    end

    --[[
        Generate a biased walk toward a target position.
    --]]
    local function generateBiasedWalk(self, startId, targetPos, allowVertical)
        local state = getState(self)
        local rng = state.rng
        local baseUnit = state.config.baseUnit
        local switchbackChance = state.config.switchbackChance

        local currentId = startId
        local maxIterations = state.config.maxSegments * 2

        for _ = 1, maxIterations do
            if isBudgetExhausted(self) then
                break
            end

            local currentPos = state.points[currentId].pos

            -- Check if we've reached the target
            local dx = targetPos[1] - currentPos[1]
            local dy = targetPos[2] - currentPos[2]
            local dz = targetPos[3] - currentPos[3]

            if math.abs(dx) < baseUnit and math.abs(dy) < baseUnit and math.abs(dz) < baseUnit then
                break
            end

            -- Determine preferred directions
            local preferredDirs = {}
            if math.abs(dx) >= baseUnit then
                table.insert(preferredDirs, dx > 0 and "E" or "W")
            end
            if math.abs(dz) >= baseUnit then
                table.insert(preferredDirs, dz > 0 and "N" or "S")
            end
            if allowVertical and math.abs(dy) >= baseUnit then
                table.insert(preferredDirs, dy > 0 and "U" or "D")
            end

            local validDirs = getValidDirections(self, currentId, allowVertical)
            if #validDirs == 0 then
                break
            end

            -- Choose direction
            local chosenDir
            if #preferredDirs > 0 and rng:random() > switchbackChance then
                rng:shuffle(preferredDirs)
                for _, dir in ipairs(preferredDirs) do
                    for _, valid in ipairs(validDirs) do
                        if dir == valid then
                            chosenDir = dir
                            break
                        end
                    end
                    if chosenDir then break end
                end
            end

            if not chosenDir then
                chosenDir = rng:randomChoice(validDirs)
            end

            if not chosenDir then
                break
            end

            -- Calculate distance
            local vec = DIRECTIONS[chosenDir]
            local maxDist
            if chosenDir == "E" or chosenDir == "W" then
                maxDist = math.abs(dx)
            elseif chosenDir == "N" or chosenDir == "S" then
                maxDist = math.abs(dz)
            else
                maxDist = math.abs(dy)
            end

            local units = math.max(1, math.floor(maxDist / baseUnit))
            units = math.min(units, 4)
            units = rng:randomInt(1, units)

            local newId, _, _ = extendPath(self, currentId, chosenDir, units)
            if newId then
                currentId = newId
            else
                -- Try with just 1 unit
                newId, _, _ = extendPath(self, currentId, chosenDir, 1)
                if newId then
                    currentId = newId
                else
                    break
                end
            end
        end

        return currentId
    end

    --[[
        Generate the through path (main route from start to goal).
    --]]
    local function generateThroughPath(self, startPos, goalPos)
        local state = getState(self)

        -- Create start point
        local startId = createPoint(self, startPos[1], startPos[2], startPos[3])
        if not startId then
            -- Position occupied (shouldn't happen for start)
            return nil
        end

        state.startPointId = startId

        -- Generate path toward goal
        local endId
        if goalPos then
            endId = generateBiasedWalk(self, startId, goalPos, true)
        else
            endId = generateRandomWalk(self, startId, 5, 15, true)
        end

        table.insert(state.goalPointIds, endId)

        return endId
    end

    --[[
        Generate a spur from an existing point.
    --]]
    local function generateSpur(self, branchPointId)
        local state = getState(self)
        local rng = state.rng

        local spurLength = rng:randomInt(2, 5)
        local endId = generateRandomWalk(self, branchPointId, spurLength, spurLength, true)

        return endId
    end

    --[[
        Generate spurs branching off existing paths.
    --]]
    local function generateSpurs(self)
        local state = getState(self)
        local rng = state.rng
        local spurCount = rng:randomInt(state.config.spurCount.min, state.config.spurCount.max)

        -- Collect candidate points
        local candidates = {}
        for pointId, point in pairs(state.points) do
            if pointId ~= state.startPointId then
                local isGoal = false
                for _, goalId in ipairs(state.goalPointIds) do
                    if pointId == goalId then
                        isGoal = true
                        break
                    end
                end

                if not isGoal then
                    local weight = (#point.connections == 2) and 3 or 1
                    for _ = 1, weight do
                        table.insert(candidates, pointId)
                    end
                end
            end
        end

        for _ = 1, spurCount do
            if isBudgetExhausted(self) or #candidates == 0 then
                break
            end

            local branchPointId = rng:randomChoice(candidates)
            generateSpur(self, branchPointId)
        end
    end

    --[[
        Generate a loop from an existing point.
    --]]
    local function generateLoop(self, branchPointId)
        local state = getState(self)
        local rng = state.rng
        local baseUnit = state.config.baseUnit

        local branchPos = state.points[branchPointId].pos

        -- Find nearby points to connect to
        local candidates = {}
        for pointId, point in pairs(state.points) do
            if pointId ~= branchPointId and not areConnected(self, branchPointId, pointId) then
                local pos = point.pos
                local dx = math.abs(pos[1] - branchPos[1])
                local dy = math.abs(pos[2] - branchPos[2])
                local dz = math.abs(pos[3] - branchPos[3])
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

                if dist >= baseUnit * 3 and dist <= baseUnit * 10 then
                    table.insert(candidates, { id = pointId, pos = pos, dist = dist })
                end
            end
        end

        if #candidates == 0 then
            return false
        end

        local target = rng:randomChoice(candidates)

        -- Walk toward target
        local loopEndId = generateBiasedWalk(self, branchPointId, target.pos, true)

        -- Check if we're close enough to connect
        local loopEndPos = state.points[loopEndId].pos
        local dx = math.abs(loopEndPos[1] - target.pos[1])
        local dy = math.abs(loopEndPos[2] - target.pos[2])
        local dz = math.abs(loopEndPos[3] - target.pos[3])

        if dx <= baseUnit and dy <= baseUnit and dz <= baseUnit then
            -- Close enough, connect directly
            if not areConnected(self, loopEndId, target.id) and loopEndId ~= target.id then
                createSegment(self, loopEndId, target.id)
                return true
            end
        end

        return false
    end

    --[[
        Generate loops.
    --]]
    local function generateLoops(self)
        local state = getState(self)
        local rng = state.rng
        local loopCount = rng:randomInt(state.config.loopCount.min, state.config.loopCount.max)

        local candidates = {}
        for pointId, point in pairs(state.points) do
            if #point.connections == 2 then
                table.insert(candidates, pointId)
            end
        end

        local loopsCreated = 0
        local attempts = 0
        local maxAttempts = loopCount * 5

        while loopsCreated < loopCount and attempts < maxAttempts do
            attempts = attempts + 1

            if isBudgetExhausted(self) or #candidates == 0 then
                break
            end

            local branchPointId = rng:randomChoice(candidates)
            if generateLoop(self, branchPointId) then
                loopsCreated = loopsCreated + 1
            end
        end
    end

    ----------------------------------------------------------------------------
    -- OUTPUT GENERATION
    ----------------------------------------------------------------------------

    local function buildOutput(self, isComplete, page)
        local state = getState(self)

        local output = {
            points = {},
            segments = {},
            start = state.startPointId,
            goals = state.goalPointIds,
            seed = state.seed,
        }

        -- Copy points with positions
        for id, point in pairs(state.points) do
            output.points[id] = {
                pos = { point.pos[1], point.pos[2], point.pos[3] },
                connections = {},
            }
            for _, conn in ipairs(point.connections) do
                table.insert(output.points[id].connections, conn)
            end
        end

        -- Copy segments
        for _, seg in ipairs(state.segments) do
            table.insert(output.segments, {
                id = seg.id,
                from = seg.from,
                to = seg.to,
            })
        end

        if page then
            output.page = page
        end
        output.isComplete = isComplete

        return output
    end

    local function buildPage(self, pageNum)
        local state = getState(self)
        local pageSize = state.config.pageSize
        local startIdx = (pageNum - 1) * pageSize + 1
        local endIdx = math.min(startIdx + pageSize - 1, #state.segments)

        local output = {
            points = {},
            segments = {},
            start = state.startPointId,
            goals = state.goalPointIds,
            seed = state.seed,
            page = pageNum,
            isComplete = endIdx >= #state.segments,
        }

        local neededPoints = {}
        for i = startIdx, endIdx do
            local seg = state.segments[i]
            if seg then
                neededPoints[seg.from] = true
                neededPoints[seg.to] = true
            end
        end

        for id in pairs(neededPoints) do
            local point = state.points[id]
            if point then
                output.points[id] = {
                    pos = { point.pos[1], point.pos[2], point.pos[3] },
                    connections = {},
                }
                for _, conn in ipairs(point.connections) do
                    table.insert(output.points[id].connections, conn)
                end
            end
        end

        for i = startIdx, endIdx do
            local seg = state.segments[i]
            if seg then
                table.insert(output.segments, {
                    id = seg.id,
                    from = seg.from,
                    to = seg.to,
                })
            end
        end

        return output
    end

    ----------------------------------------------------------------------------
    -- MAIN GENERATION
    ----------------------------------------------------------------------------

    local function runGeneration(self, data)
        local state = getState(self)
        local config = state.config

        -- Initialize
        state.seed = config.seed or generateSeed()
        state.rng = createRNG(state.seed)

        state.points = {}
        state.segments = {}
        state.pointCounter = 0
        state.segmentCounter = 0
        state.startPointId = nil
        state.goalPointIds = {}
        state.positionIndex = {}
        state.generating = true

        local startPos = data.start or { 0, 0, 0 }
        if type(startPos) ~= "table" then
            startPos = { 0, 0, 0 }
        end

        local goalPos = nil
        if data.goals and #data.goals > 0 then
            goalPos = data.goals[1]
        end

        generateThroughPath(self, startPos, goalPos)
        generateSpurs(self)
        generateLoops(self)

        state.generating = false
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "PathGraph",
        domain = "server",

        Sys = {
            onInit = function(self)
                local _ = getState(self)
            end,

            onStart = function(self)
            end,

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
                if data.seed then config.seed = data.seed end
                if data.spurCount then
                    config.spurCount = {
                        min = data.spurCount.min or config.spurCount.min,
                        max = data.spurCount.max or config.spurCount.max,
                    }
                end
                if data.loopCount then
                    config.loopCount = {
                        min = data.loopCount.min or config.loopCount.min,
                        max = data.loopCount.max or config.loopCount.max,
                    }
                end
                if data.switchbackChance then config.switchbackChance = data.switchbackChance end
                if data.maxSegments then config.maxSegments = data.maxSegments end
                if data.bounds then config.bounds = data.bounds end
                if data.mode then config.mode = data.mode end
                if data.pageSize then config.pageSize = data.pageSize end
            end,

            onGenerate = function(self, data)
                data = data or {}
                local state = getState(self)
                local config = state.config

                runGeneration(self, data)

                if config.mode == "streamed" then
                    state.currentPage = 0
                    state.handshakeReceived = false
                    state.isComplete = false
                    state.bufferedPage = buildPage(self, 1)
                    self.Out:Fire("pageBuffered", { page = 1 })
                else
                    local output = buildOutput(self, true)
                    self.Out:Fire("path", output)
                    self.Out:Fire("complete", {
                        seed = state.seed,
                        totalPoints = state.pointCounter,
                        totalSegments = #state.segments,
                    })
                end
            end,

            onRequestPage = function(self)
                local state = getState(self)

                if state.isComplete then return end

                if not state.handshakeReceived then
                    state.handshakeReceived = true
                    return
                end

                if state.bufferedPage then
                    self.Out:Fire("path", state.bufferedPage)

                    if state.bufferedPage.isComplete then
                        state.isComplete = true
                        self.Out:Fire("complete", {
                            seed = state.seed,
                            totalPoints = state.pointCounter,
                            totalSegments = #state.segments,
                        })
                        state.bufferedPage = nil
                        return
                    end

                    state.currentPage = state.currentPage + 1
                    state.bufferedPage = buildPage(self, state.currentPage + 1)
                    self.Out:Fire("pageBuffered", { page = state.currentPage + 1 })
                end
            end,

            onAdjust = function(self, data)
                if not data or not data.pointId or not data.newPos then return end

                local state = getState(self)
                local point = state.points[data.pointId]
                if point then
                    -- Update spatial index
                    local oldKey = posKeyFromArray(point.pos)
                    state.positionIndex[oldKey] = nil

                    point.pos = { data.newPos[1], data.newPos[2], data.newPos[3] }

                    local newKey = posKeyFromArray(point.pos)
                    state.positionIndex[newKey] = data.pointId
                end
            end,

            --[[
                Batch update multiple point positions.
                data = {
                    updates = { [pointId] = {x, y, z}, ... },
                    reemit = true/false  -- Whether to re-emit path signal
                }
            --]]
            onUpdatePoints = function(self, data)
                if not data or not data.updates then return end

                local state = getState(self)

                for pointId, newPos in pairs(data.updates) do
                    local point = state.points[pointId]
                    if point then
                        -- Update spatial index
                        local oldKey = posKeyFromArray(point.pos)
                        state.positionIndex[oldKey] = nil

                        point.pos = { newPos[1], newPos[2], newPos[3] }

                        local newKey = posKeyFromArray(point.pos)
                        state.positionIndex[newKey] = pointId
                    end
                end

                -- Optionally re-emit updated path
                if data.reemit then
                    local output = buildOutput(self, true)
                    self.Out:Fire("pathUpdated", output)
                end
            end,

            onExtend = function(self, data)
                if not data or not data.existingPath then return end

                local state = getState(self)
                local existing = data.existingPath

                local idMap = {}
                for oldId, point in pairs(existing.points) do
                    local newId = createPoint(self, point.pos[1], point.pos[2], point.pos[3])
                    if newId then
                        idMap[oldId] = newId
                    end
                end

                for _, seg in ipairs(existing.segments) do
                    local fromId = idMap[seg.from]
                    local toId = idMap[seg.to]
                    if fromId and toId then
                        createSegment(self, fromId, toId)
                    end
                end

                if existing.start and idMap[existing.start] then
                    state.startPointId = idMap[existing.start]
                end

                for _, goalId in ipairs(existing.goals or {}) do
                    if idMap[goalId] then
                        table.insert(state.goalPointIds, idMap[goalId])
                    end
                end

                if data.addSpurs then generateSpurs(self) end
                if data.addLoops then generateLoops(self) end

                local output = buildOutput(self, true)
                self.Out:Fire("path", output)
            end,
        },

        Out = {
            path = {},
            pathUpdated = {},  -- Emitted after onUpdatePoints with reemit=true
            complete = {},
            pageBuffered = {},
        },

        getPath = function(self)
            return buildOutput(self, true)
        end,

        getPoint = function(self, pointId)
            local state = getState(self)
            return state.points[pointId]
        end,

        getPointPosition = function(self, pointId)
            local state = getState(self)
            local point = state.points[pointId]
            return point and point.pos
        end,

        getAllPositions = function(self)
            local state = getState(self)
            local positions = {}
            for id, point in pairs(state.points) do
                positions[id] = { point.pos[1], point.pos[2], point.pos[3] }
            end
            return positions
        end,

        getSeed = function(self)
            local state = getState(self)
            return state.seed
        end,
    }
end)

return PathGraph
