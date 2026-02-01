--[[
    LibPureFiction Framework v2
    PathGraphIncremental.lua - Incremental Path Graph Generator

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Generates paths incrementally, one segment at a time, with feedback from
    RoomBlocker for overlap resolution. PathGraph is the source of truth for
    all path data.

    Key architecture:
    - Stores segment "recipes" (direction + length in baseUnits)
    - Absolute positions calculated by walking from start
    - Sends one segment at a time to RoomBlocker
    - On overlap: SHIFTS all downstream points in the segment's direction
    - Generates branches sequentially (main path, then spurs)

    Overlap resolution:
    - When overlap detected, we shift ALL points beyond the current point
      in the segment's direction by the overlap amount
    - Example: Segment goes North, overlap at point B
      -> Shift all points with Z > A.z by the overlap amount
    - This naturally propagates the shift through the entire graph

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit, seed?, spurCount?, ... })
        onGenerate({ start, goals? })
        onSegmentResult({ ok: bool, overlapAmount?: number })
            - Response from RoomBlocker for current segment

    OUT (emits):
        segment({ segmentId, fromPointId, toPointId, fromPos, toPos, isNewPoint })
            - Single segment for RoomBlocker to validate
        branchComplete({ branchIndex, branchType })
            - Emitted when a branch is fully validated
        complete({ seed, totalPoints, totalSegments })
            - Emitted when entire path is complete

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- PATHGRAPH INCREMENTAL NODE
--------------------------------------------------------------------------------

local PathGraphIncremental = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    -- Direction vectors (unit movements in baseUnits)
    local DIRECTIONS = {
        N = { 0, 0, 1 },   -- +Z
        S = { 0, 0, -1 },  -- -Z
        E = { 1, 0, 0 },   -- +X
        W = { -1, 0, 0 },  -- -X
        U = { 0, 1, 0 },   -- +Y
        D = { 0, -1, 0 },  -- -Y
    }

    local OPPOSITES = {
        N = "S", S = "N",
        E = "W", W = "E",
        U = "D", D = "U",
    }

    local DIR_LIST = { "N", "S", "E", "W", "U", "D" }

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Configuration
                config = {
                    baseUnit = 15,
                    seed = nil,
                    spurCount = { min = 2, max = 5 },
                    maxSegmentsPerBranch = 10,
                    bounds = nil,
                },

                -- RNG
                rng = nil,
                seed = nil,

                -- Segment recipes: { id, fromPointId, toPointId, direction, length }
                recipes = {},

                -- Branches: ordered lists of segment IDs
                branches = {},

                -- Points: { [id] = { pos = {x,y,z}, connections = {} } }
                points = {},
                pointCounter = 0,

                -- Build state
                currentBranchIndex = 0,
                currentSegmentInBranch = 0,
                waitingForResponse = false,
                startPointId = nil,
                goalPointIds = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- RNG
    ----------------------------------------------------------------------------

    local function createRNG(seed)
        local rngState
        if type(seed) == "string" then
            rngState = 0
            for i = 1, #seed do
                rngState = rngState + seed:byte(i) * (i * 31)
            end
            rngState = bit32.band(rngState, 0xFFFFFFFF)
            if rngState == 0 then rngState = 1 end
        else
            rngState = seed or os.time()
            if rngState == 0 then rngState = 1 end
        end

        local rng = {}

        function rng:next()
            rngState = bit32.bxor(rngState, bit32.lshift(rngState, 13))
            rngState = bit32.bxor(rngState, bit32.rshift(rngState, 17))
            rngState = bit32.bxor(rngState, bit32.lshift(rngState, 5))
            rngState = bit32.band(rngState, 0xFFFFFFFF)
            return rngState
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
    -- POSITION CALCULATION
    ----------------------------------------------------------------------------

    --[[
        Calculate all point positions from recipes.
        Call this after generating recipes to set initial positions.
    --]]
    local function calculateAllPositions(self)
        local state = getState(self)
        local baseUnit = state.config.baseUnit

        for _, recipe in ipairs(state.recipes) do
            local fromPoint = state.points[recipe.fromPointId]

            if fromPoint then
                local dir = DIRECTIONS[recipe.direction]
                local dist = recipe.length * baseUnit

                local newPos = {
                    fromPoint.pos[1] + dir[1] * dist,
                    fromPoint.pos[2] + dir[2] * dist,
                    fromPoint.pos[3] + dir[3] * dist,
                }

                local toPoint = state.points[recipe.toPointId]
                if toPoint then
                    toPoint.pos = newPos
                end
            end
        end
    end

    --[[
        SHIFT all points that are "beyond" the given position in the given direction.
        This is the key to overlap resolution.

        Example: direction = "N" (north = +Z)
        - We shift all points where point.z > threshold.z
        - We add shiftAmount to their Z coordinate

        This naturally propagates the shift to everything downstream.
    --]]
    local function shiftDownstreamPoints(self, thresholdPos, direction, shiftAmount)
        local state = getState(self)
        local dir = DIRECTIONS[direction]

        -- Determine which axis and direction we're checking
        local axisIndex
        local positive
        if dir[1] ~= 0 then
            axisIndex = 1  -- X axis
            positive = dir[1] > 0
        elseif dir[2] ~= 0 then
            axisIndex = 2  -- Y axis
            positive = dir[2] > 0
        else
            axisIndex = 3  -- Z axis
            positive = dir[3] > 0
        end

        local threshold = thresholdPos[axisIndex]
        local shiftedCount = 0

        print(string.format("[PathGraph] Shifting points: axis=%d, threshold=%.1f, positive=%s, shift=%.1f",
            axisIndex, threshold, tostring(positive), shiftAmount))

        for pointId, point in pairs(state.points) do
            local pointValue = point.pos[axisIndex]

            -- Check if this point is "beyond" the threshold in the direction
            local shouldShift = false
            if positive then
                shouldShift = pointValue > threshold
            else
                shouldShift = pointValue < threshold
            end

            if shouldShift then
                -- Shift the point in the direction
                point.pos[axisIndex] = point.pos[axisIndex] + (positive and shiftAmount or -shiftAmount)
                shiftedCount = shiftedCount + 1
                print(string.format("  Shifted point %d: %.1f -> %.1f",
                    pointId, pointValue, point.pos[axisIndex]))
            end
        end

        print(string.format("[PathGraph] Shifted %d points", shiftedCount))

        return shiftedCount
    end

    ----------------------------------------------------------------------------
    -- BRANCH GENERATION (RECIPES ONLY)
    ----------------------------------------------------------------------------

    --[[
        Create a new point at a position.
    --]]
    local function createPoint(self, x, y, z)
        local state = getState(self)
        state.pointCounter = state.pointCounter + 1
        local id = state.pointCounter

        state.points[id] = {
            pos = { x, y, z },
            connections = {},
        }

        return id
    end

    --[[
        Create a segment recipe.
    --]]
    local function createRecipe(self, fromPointId, toPointId, direction, length)
        local state = getState(self)
        local id = #state.recipes + 1

        local recipe = {
            id = id,
            fromPointId = fromPointId,
            toPointId = toPointId,
            direction = direction,
            length = length,
        }

        table.insert(state.recipes, recipe)

        -- Update connections
        table.insert(state.points[fromPointId].connections, toPointId)
        table.insert(state.points[toPointId].connections, fromPointId)

        return recipe
    end

    --[[
        Generate recipe for main branch (start to goal direction).
    --]]
    local function generateMainBranchRecipe(self, startPos, goalPos)
        local state = getState(self)
        local rng = state.rng
        local baseUnit = state.config.baseUnit
        local maxSegments = state.config.maxSegmentsPerBranch

        -- Create start point
        local startId = createPoint(self, startPos[1], startPos[2], startPos[3])
        state.startPointId = startId

        local branch = {
            segmentIds = {},
            type = "main",
        }

        local currentPointId = startId
        local currentPos = { startPos[1], startPos[2], startPos[3] }
        local lastDirection = nil

        for _ = 1, maxSegments do
            -- Calculate direction bias toward goal
            local dx = goalPos[1] - currentPos[1]
            local dy = goalPos[2] - currentPos[2]
            local dz = goalPos[3] - currentPos[3]

            -- Check if close enough to goal
            if math.abs(dx) < baseUnit and math.abs(dy) < baseUnit and math.abs(dz) < baseUnit then
                break
            end

            -- Prefer directions toward goal
            local preferredDirs = {}
            if math.abs(dx) >= baseUnit then
                table.insert(preferredDirs, dx > 0 and "E" or "W")
            end
            if math.abs(dz) >= baseUnit then
                table.insert(preferredDirs, dz > 0 and "N" or "S")
            end
            if math.abs(dy) >= baseUnit then
                table.insert(preferredDirs, dy > 0 and "U" or "D")
            end

            -- Choose direction (avoid reversal)
            local chosenDir
            if #preferredDirs > 0 then
                rng:shuffle(preferredDirs)
                for _, dir in ipairs(preferredDirs) do
                    if not lastDirection or dir ~= OPPOSITES[lastDirection] then
                        chosenDir = dir
                        break
                    end
                end
            end

            if not chosenDir then
                -- Pick random valid direction
                local validDirs = {}
                for _, dir in ipairs(DIR_LIST) do
                    if not lastDirection or dir ~= OPPOSITES[lastDirection] then
                        table.insert(validDirs, dir)
                    end
                end
                chosenDir = rng:randomChoice(validDirs)
            end

            if not chosenDir then break end

            -- Random length 2-4 baseUnits (ensure some spacing)
            local length = rng:randomInt(2, 4)

            -- Create endpoint (position calculated later)
            local nextPointId = createPoint(self, 0, 0, 0)

            -- Create recipe
            local recipe = createRecipe(self, currentPointId, nextPointId, chosenDir, length)
            table.insert(branch.segmentIds, recipe.id)

            -- Update for next iteration
            local dir = DIRECTIONS[chosenDir]
            currentPos = {
                currentPos[1] + dir[1] * length * baseUnit,
                currentPos[2] + dir[2] * length * baseUnit,
                currentPos[3] + dir[3] * length * baseUnit,
            }
            currentPointId = nextPointId
            lastDirection = chosenDir
        end

        -- Mark last point as goal
        table.insert(state.goalPointIds, currentPointId)

        table.insert(state.branches, branch)

        -- Calculate initial positions from recipes
        calculateAllPositions(self)

        return branch
    end

    --[[
        Generate recipe for a spur branch from an existing point.
    --]]
    local function generateSpurRecipe(self, rootPointId)
        local state = getState(self)
        local rng = state.rng
        local baseUnit = state.config.baseUnit

        local rootPoint = state.points[rootPointId]
        if not rootPoint then return nil end

        local branch = {
            segmentIds = {},
            type = "spur",
            rootPointId = rootPointId,
        }

        local currentPointId = rootPointId
        local lastDirection = nil

        -- Short spur: 1-3 segments
        local spurLength = rng:randomInt(1, 3)

        for _ = 1, spurLength do
            -- Pick random direction (avoid reversal)
            local validDirs = {}
            for _, dir in ipairs(DIR_LIST) do
                if not lastDirection or dir ~= OPPOSITES[lastDirection] then
                    table.insert(validDirs, dir)
                end
            end

            local chosenDir = rng:randomChoice(validDirs)
            if not chosenDir then break end

            local length = rng:randomInt(2, 3)

            local nextPointId = createPoint(self, 0, 0, 0)
            local recipe = createRecipe(self, currentPointId, nextPointId, chosenDir, length)
            table.insert(branch.segmentIds, recipe.id)

            currentPointId = nextPointId
            lastDirection = chosenDir
        end

        if #branch.segmentIds > 0 then
            table.insert(state.branches, branch)
            -- Recalculate positions for new spur
            calculateAllPositions(self)
            return branch
        end

        return nil
    end

    ----------------------------------------------------------------------------
    -- INCREMENTAL BUILD
    ----------------------------------------------------------------------------

    --[[
        Send the current segment to RoomBlocker for validation.
    --]]
    local function sendCurrentSegment(self)
        local state = getState(self)

        if state.currentBranchIndex < 1 or state.currentBranchIndex > #state.branches then
            return false
        end

        local branch = state.branches[state.currentBranchIndex]
        if state.currentSegmentInBranch < 1 or state.currentSegmentInBranch > #branch.segmentIds then
            return false
        end

        local segmentId = branch.segmentIds[state.currentSegmentInBranch]
        local recipe = state.recipes[segmentId]

        local fromPoint = state.points[recipe.fromPointId]
        local toPoint = state.points[recipe.toPointId]

        state.waitingForResponse = true

        -- Emit segment for RoomBlocker
        self.Out:Fire("segment", {
            segmentId = segmentId,
            fromPointId = recipe.fromPointId,
            toPointId = recipe.toPointId,
            fromPos = { fromPoint.pos[1], fromPoint.pos[2], fromPoint.pos[3] },
            toPos = { toPoint.pos[1], toPoint.pos[2], toPoint.pos[3] },
            direction = recipe.direction,
            length = recipe.length,
            isNewPoint = state.currentSegmentInBranch == 1 and state.currentBranchIndex == 1,
        })

        return true
    end

    --[[
        Move to next segment or branch.
    --]]
    local function advanceToNext(self)
        local state = getState(self)

        local branch = state.branches[state.currentBranchIndex]

        if state.currentSegmentInBranch < #branch.segmentIds then
            -- Next segment in current branch
            state.currentSegmentInBranch = state.currentSegmentInBranch + 1
            sendCurrentSegment(self)
        else
            -- Branch complete
            self.Out:Fire("branchComplete", {
                branchIndex = state.currentBranchIndex,
                branchType = branch.type,
            })

            -- Check if we need to generate spurs
            if state.currentBranchIndex == 1 then
                -- Main branch done, generate spurs
                local rng = state.rng
                local spurCount = rng:randomInt(
                    state.config.spurCount.min,
                    state.config.spurCount.max
                )

                -- Collect junction candidates (points with 2 connections on main path)
                local candidates = {}
                for pointId, point in pairs(state.points) do
                    if pointId ~= state.startPointId and #point.connections == 2 then
                        table.insert(candidates, pointId)
                    end
                end

                -- Generate spur recipes
                for _ = 1, math.min(spurCount, #candidates) do
                    if #candidates == 0 then break end
                    local idx = rng:randomInt(1, #candidates)
                    local rootId = table.remove(candidates, idx)
                    generateSpurRecipe(self, rootId)
                end
            end

            -- Move to next branch
            if state.currentBranchIndex < #state.branches then
                state.currentBranchIndex = state.currentBranchIndex + 1
                state.currentSegmentInBranch = 1
                sendCurrentSegment(self)
            else
                -- All done
                self.Out:Fire("complete", {
                    seed = state.seed,
                    totalPoints = state.pointCounter,
                    totalSegments = #state.recipes,
                })
            end
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "PathGraphIncremental",
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
                if data.maxSegmentsPerBranch then config.maxSegmentsPerBranch = data.maxSegmentsPerBranch end
                if data.bounds then config.bounds = data.bounds end
            end,

            onGenerate = function(self, data)
                data = data or {}
                local state = getState(self)
                local config = state.config

                -- Initialize
                state.seed = config.seed or generateSeed()
                state.rng = createRNG(state.seed)
                state.recipes = {}
                state.branches = {}
                state.points = {}
                state.pointCounter = 0
                state.startPointId = nil
                state.goalPointIds = {}
                state.currentBranchIndex = 0
                state.currentSegmentInBranch = 0
                state.waitingForResponse = false

                local startPos = data.start or { 0, 0, 0 }
                local goalPos = (data.goals and data.goals[1]) or { 150, 0, 150 }

                print("[PathGraph] Generating with seed:", state.seed)
                print("[PathGraph] Start:", startPos[1], startPos[2], startPos[3])
                print("[PathGraph] Goal:", goalPos[1], goalPos[2], goalPos[3])

                -- Generate main branch recipe
                generateMainBranchRecipe(self, startPos, goalPos)

                print("[PathGraph] Main branch has", #state.branches[1].segmentIds, "segments")

                -- Start incremental build
                state.currentBranchIndex = 1
                state.currentSegmentInBranch = 1
                sendCurrentSegment(self)
            end,

            --[[
                Handle response from RoomBlocker.
                { ok = true } - segment validated, move to next
                { ok = false, overlapAmount = 15 } - overlap detected, shift and retry
            --]]
            onSegmentResult = function(self, data)
                local state = getState(self)

                if not state.waitingForResponse then
                    print("[PathGraph] WARNING: Received result but not waiting for response")
                    return
                end

                state.waitingForResponse = false

                if data.ok then
                    -- Segment OK, advance to next
                    advanceToNext(self)
                else
                    -- Overlap detected - SHIFT all downstream points
                    local overlapAmount = data.overlapAmount or state.config.baseUnit
                    local baseUnit = state.config.baseUnit

                    -- Add buffer to ensure we clear the overlap
                    local shiftAmount = overlapAmount + baseUnit

                    local branch = state.branches[state.currentBranchIndex]
                    local segmentId = branch.segmentIds[state.currentSegmentInBranch]
                    local recipe = state.recipes[segmentId]
                    local fromPoint = state.points[recipe.fromPointId]

                    print(string.format("[PathGraph] Overlap! Shifting downstream points by %.1f studs in direction %s",
                        shiftAmount, recipe.direction))

                    -- Shift all points beyond the FROM point in the segment's direction
                    shiftDownstreamPoints(self, fromPoint.pos, recipe.direction, shiftAmount)

                    -- Re-send the segment with updated positions
                    sendCurrentSegment(self)
                end
            end,
        },

        Out = {
            segment = {},       -- Single segment for validation
            branchComplete = {}, -- Branch finished
            complete = {},       -- All done
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getPoints = function(self)
            local state = getState(self)
            return state.points
        end,

        getRecipes = function(self)
            local state = getState(self)
            return state.recipes
        end,

        getPath = function(self)
            local state = getState(self)

            -- Build output in standard format
            local output = {
                points = {},
                segments = {},
                start = state.startPointId,
                goals = state.goalPointIds,
                seed = state.seed,
            }

            for id, point in pairs(state.points) do
                output.points[id] = {
                    pos = { point.pos[1], point.pos[2], point.pos[3] },
                    connections = {},
                }
                for _, conn in ipairs(point.connections) do
                    table.insert(output.points[id].connections, conn)
                end
            end

            for _, recipe in ipairs(state.recipes) do
                table.insert(output.segments, {
                    id = recipe.id,
                    from = recipe.fromPointId,
                    to = recipe.toPointId,
                })
            end

            return output
        end,

        getSeed = function(self)
            local state = getState(self)
            return state.seed
        end,
    }
end)

return PathGraphIncremental
