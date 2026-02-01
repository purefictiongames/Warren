--[[
    LibPureFiction Framework v2
    PathGraph.lua - Incremental Path Graph Generator

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Generates paths incrementally, one segment at a time. Each segment is
    validated by RoomBlocker before moving to the next.

    Architecture:
    - All paths are the same - just segments from point to point
    - The "main" path is simply the first one (starts from origin)
    - "Spurs" are just paths that start from existing junction points
    - Positions are calculated once and never recalculated
    - On overlap: adjust current point, retry until OK

    The math is simple recursive arithmetic:
        Point[n].pos = Point[n-1].pos + direction * length * baseUnit
        (adjusted for overlaps)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit, seed?, spurCount?, ... })
        onGenerate({ start, goals? })
        onSegmentResult({ ok: bool, overlapAmount?: number })

    OUT (emits):
        segment({ fromPointId, toPointId, fromPos, toPos, direction })
        pathComplete({ pathIndex })
        complete({ seed, totalPoints, totalSegments })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- PATHGRAPH NODE
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

    local OPPOSITES = {
        N = "S", S = "N",
        E = "W", W = "E",
        U = "D", D = "U",
    }

    -- Direction lists for weighted selection
    local DIR_HORIZONTAL = { "N", "S", "E", "W" }
    local DIR_VERTICAL = { "U", "D" }

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    baseUnit = 15,
                    seed = nil,
                    spurCount = { min = 2, max = 5 },
                    maxSegmentsPerPath = 10,
                    verticalChance = 15, -- % chance to pick vertical direction
                },

                rng = nil,
                seed = nil,

                -- Points: { [id] = { pos, connections, built } }
                points = {},
                pointCounter = 0,

                -- Segments: { { id, fromId, toId, direction, length } }
                segments = {},

                -- Path tracking
                paths = {},           -- { { startPointId, segmentIds } }
                currentPathIndex = 0,
                segmentsInCurrentPath = 0,

                -- Current segment being validated
                currentSegment = nil,
                currentFromPointId = nil,
                lastDirection = nil,

                -- Goal for pathfinding bias
                goalPos = nil,

                -- State
                waitingForResponse = false,
                startPointId = nil,
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
    -- POINT MANAGEMENT
    ----------------------------------------------------------------------------

    local function createPoint(self, x, y, z)
        local state = getState(self)
        state.pointCounter = state.pointCounter + 1
        local id = state.pointCounter

        state.points[id] = {
            pos = { x, y, z },
            connections = {},
            built = false,
        }

        return id
    end

    local function connectPoints(self, fromId, toId)
        local state = getState(self)
        local fromPoint = state.points[fromId]
        local toPoint = state.points[toId]

        if fromPoint and toPoint then
            table.insert(fromPoint.connections, toId)
            table.insert(toPoint.connections, fromId)
        end
    end

    ----------------------------------------------------------------------------
    -- SEGMENT GENERATION
    ----------------------------------------------------------------------------

    --[[
        Pick direction for next segment.
        Prefers directions toward goal, avoids reversal.
    --]]
    local function pickDirection(self, fromPos, lastDir)
        local state = getState(self)
        local rng = state.rng
        local goalPos = state.goalPos
        local baseUnit = state.config.baseUnit
        local verticalChance = state.config.verticalChance

        -- Decide if this will be a vertical move
        local useVertical = rng:randomInt(1, 100) <= verticalChance
        local dirPool = useVertical and DIR_VERTICAL or DIR_HORIZONTAL

        -- Build list of valid directions (no reversal)
        local validDirs = {}
        for _, dir in ipairs(dirPool) do
            if not lastDir or dir ~= OPPOSITES[lastDir] then
                table.insert(validDirs, dir)
            end
        end

        -- If vertical pool is empty (e.g., last was U and we rolled vertical again),
        -- fall back to horizontal
        if #validDirs == 0 then
            for _, dir in ipairs(DIR_HORIZONTAL) do
                if not lastDir or dir ~= OPPOSITES[lastDir] then
                    table.insert(validDirs, dir)
                end
            end
        end

        if #validDirs == 0 then
            return nil
        end

        -- If horizontal and we have a goal, prefer directions toward it
        if not useVertical and goalPos then
            local dx = goalPos[1] - fromPos[1]
            local dz = goalPos[3] - fromPos[3]

            local preferredDirs = {}
            if math.abs(dx) >= baseUnit then
                table.insert(preferredDirs, dx > 0 and "E" or "W")
            end
            if math.abs(dz) >= baseUnit then
                table.insert(preferredDirs, dz > 0 and "N" or "S")
            end

            -- Filter to valid directions
            local biasedDirs = {}
            for _, pref in ipairs(preferredDirs) do
                for _, valid in ipairs(validDirs) do
                    if pref == valid then
                        table.insert(biasedDirs, pref)
                        break
                    end
                end
            end

            -- 70% chance to pick biased direction
            if #biasedDirs > 0 and rng:randomInt(1, 10) <= 7 then
                return rng:randomChoice(biasedDirs)
            end
        end

        return rng:randomChoice(validDirs)
    end

    --[[
        Generate and send the next segment.
    --]]
    local function generateNextSegment(self)
        local state = getState(self)
        local rng = state.rng
        local baseUnit = state.config.baseUnit

        local fromPoint = state.points[state.currentFromPointId]
        if not fromPoint then
            print("[PathGraph] ERROR: No from point")
            return false
        end

        local fromPos = fromPoint.pos

        -- Pick direction
        local direction = pickDirection(self, fromPos, state.lastDirection)
        if not direction then
            print("[PathGraph] No valid direction available")
            return false
        end

        -- Pick length (2-4 base units)
        local length = rng:randomInt(2, 4)

        -- Calculate target position
        local dir = DIRECTIONS[direction]
        local dist = length * baseUnit
        local toPos = {
            fromPos[1] + dir[1] * dist,
            fromPos[2] + dir[2] * dist,
            fromPos[3] + dir[3] * dist,
        }

        -- Create the target point (position may be adjusted on overlap)
        local toPointId = createPoint(self, toPos[1], toPos[2], toPos[3])

        -- Store current segment info for potential adjustment
        state.currentSegment = {
            fromPointId = state.currentFromPointId,
            toPointId = toPointId,
            direction = direction,
            length = length,
        }

        state.waitingForResponse = true

        -- Send to RoomBlocker
        print(string.format("[PathGraph] Segment: %d -> %d, dir=%s, len=%d",
            state.currentFromPointId, toPointId, direction, length))
        print(string.format("  fromPos: %.1f, %.1f, %.1f", fromPos[1], fromPos[2], fromPos[3]))
        print(string.format("  toPos: %.1f, %.1f, %.1f", toPos[1], toPos[2], toPos[3]))

        self.Out:Fire("segment", {
            fromPointId = state.currentFromPointId,
            toPointId = toPointId,
            fromPos = { fromPos[1], fromPos[2], fromPos[3] },
            toPos = { toPos[1], toPos[2], toPos[3] },
            direction = direction,
        })

        return true
    end

    --[[
        Resend current segment with adjusted position.
    --]]
    local function resendAdjustedSegment(self, adjustment)
        local state = getState(self)
        local seg = state.currentSegment
        local baseUnit = state.config.baseUnit

        local fromPoint = state.points[seg.fromPointId]
        local toPoint = state.points[seg.toPointId]
        local dir = DIRECTIONS[seg.direction]

        -- Adjust the TO point position in the segment direction
        local shiftAmount = adjustment + baseUnit -- Add buffer
        toPoint.pos[1] = toPoint.pos[1] + dir[1] * shiftAmount
        toPoint.pos[2] = toPoint.pos[2] + dir[2] * shiftAmount
        toPoint.pos[3] = toPoint.pos[3] + dir[3] * shiftAmount

        print(string.format("[PathGraph] Adjusted toPos by %.1f: %.1f, %.1f, %.1f",
            shiftAmount, toPoint.pos[1], toPoint.pos[2], toPoint.pos[3]))

        state.waitingForResponse = true

        -- Resend with new position
        self.Out:Fire("segment", {
            fromPointId = seg.fromPointId,
            toPointId = seg.toPointId,
            fromPos = { fromPoint.pos[1], fromPoint.pos[2], fromPoint.pos[3] },
            toPos = { toPoint.pos[1], toPoint.pos[2], toPoint.pos[3] },
            direction = seg.direction,
        })
    end

    --[[
        Current segment was accepted. Finalize and move to next.
    --]]
    local function finalizeSegment(self)
        local state = getState(self)
        local seg = state.currentSegment

        -- Connect points
        connectPoints(self, seg.fromPointId, seg.toPointId)

        -- Mark points as built
        state.points[seg.fromPointId].built = true
        state.points[seg.toPointId].built = true

        -- Record segment
        local segmentRecord = {
            id = #state.segments + 1,
            fromId = seg.fromPointId,
            toId = seg.toPointId,
            direction = seg.direction,
        }
        table.insert(state.segments, segmentRecord)

        -- Add to current path
        local currentPath = state.paths[state.currentPathIndex]
        table.insert(currentPath.segmentIds, segmentRecord.id)

        -- Update state for next segment
        state.currentFromPointId = seg.toPointId
        state.lastDirection = seg.direction
        state.segmentsInCurrentPath = state.segmentsInCurrentPath + 1
        state.currentSegment = nil
    end

    --[[
        Start a new path from a junction point.
    --]]
    local function startNewPath(self, fromPointId)
        local state = getState(self)

        state.currentPathIndex = state.currentPathIndex + 1
        state.paths[state.currentPathIndex] = {
            startPointId = fromPointId,
            segmentIds = {},
        }
        state.currentFromPointId = fromPointId
        state.lastDirection = nil
        state.segmentsInCurrentPath = 0

        print(string.format("[PathGraph] Starting path %d from point %d",
            state.currentPathIndex, fromPointId))
    end

    --[[
        Find junction points that can spawn new paths.
    --]]
    local function findJunctionCandidates(self)
        local state = getState(self)
        local candidates = {}

        for pointId, point in pairs(state.points) do
            -- Points with exactly 2 connections are corridor points - good for branching
            -- Points with 1 connection are dead ends
            -- Points with 3+ already have branches
            if point.built and #point.connections == 2 and pointId ~= state.startPointId then
                table.insert(candidates, pointId)
            end
        end

        return candidates
    end

    --[[
        Check if current path should end.
    --]]
    local function shouldEndPath(self)
        local state = getState(self)
        local maxSegs = state.config.maxSegmentsPerPath

        -- End if we've hit max segments
        if state.segmentsInCurrentPath >= maxSegs then
            return true
        end

        -- For main path, also check if we're near goal
        if state.currentPathIndex == 1 and state.goalPos then
            local currentPoint = state.points[state.currentFromPointId]
            local pos = currentPoint.pos
            local goal = state.goalPos
            local baseUnit = state.config.baseUnit

            local dx = math.abs(goal[1] - pos[1])
            local dz = math.abs(goal[3] - pos[3])

            if dx < baseUnit * 2 and dz < baseUnit * 2 then
                return true
            end
        end

        return false
    end

    --[[
        Advance to next segment or next path.
    --]]
    local function advance(self)
        local state = getState(self)

        -- Check if current path should end
        if shouldEndPath(self) then
            print(string.format("[PathGraph] Path %d complete with %d segments",
                state.currentPathIndex, state.segmentsInCurrentPath))

            self.Out:Fire("pathComplete", {
                pathIndex = state.currentPathIndex,
            })

            -- Try to start a spur
            local candidates = findJunctionCandidates(self)
            local spurCount = state.rng:randomInt(
                state.config.spurCount.min,
                state.config.spurCount.max
            )

            -- Only start more paths if we haven't exceeded spur count
            -- (path 1 is main, paths 2+ are spurs)
            if state.currentPathIndex <= spurCount and #candidates > 0 then
                local idx = state.rng:randomInt(1, #candidates)
                local junctionId = candidates[idx]
                startNewPath(self, junctionId)
                generateNextSegment(self)
            else
                -- All done
                print("[PathGraph] Generation complete")
                self.Out:Fire("complete", {
                    seed = state.seed,
                    totalPoints = state.pointCounter,
                    totalSegments = #state.segments,
                })
            end
        else
            -- Continue current path
            generateNextSegment(self)
        end
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
                if data.maxSegmentsPerPath then
                    config.maxSegmentsPerPath = data.maxSegmentsPerPath
                end
                if data.verticalChance then
                    config.verticalChance = data.verticalChance
                end
            end,

            onGenerate = function(self, data)
                data = data or {}
                local state = getState(self)
                local config = state.config

                -- Reset state
                state.seed = config.seed or generateSeed()
                state.rng = createRNG(state.seed)
                state.points = {}
                state.pointCounter = 0
                state.segments = {}
                state.paths = {}
                state.currentPathIndex = 0
                state.currentSegment = nil
                state.currentFromPointId = nil
                state.lastDirection = nil
                state.waitingForResponse = false

                local startPos = data.start or { 0, 0, 0 }
                state.goalPos = (data.goals and data.goals[1]) or { 150, 0, 150 }

                print("[PathGraph] Generating with seed:", state.seed)
                print(string.format("[PathGraph] Start: %.1f, %.1f, %.1f",
                    startPos[1], startPos[2], startPos[3]))
                print(string.format("[PathGraph] Goal: %.1f, %.1f, %.1f",
                    state.goalPos[1], state.goalPos[2], state.goalPos[3]))

                -- Create start point
                state.startPointId = createPoint(self, startPos[1], startPos[2], startPos[3])

                -- Start first path
                startNewPath(self, state.startPointId)
                generateNextSegment(self)
            end,

            --[[
                Handle response from RoomBlocker.
            --]]
            onSegmentResult = function(self, data)
                local state = getState(self)

                if not state.waitingForResponse then
                    print("[PathGraph] WARNING: Unexpected segment result")
                    return
                end

                state.waitingForResponse = false

                if data.ok then
                    -- Segment accepted - finalize and continue
                    finalizeSegment(self)
                    advance(self)
                else
                    -- Overlap - adjust and retry
                    local overlapAmount = data.overlapAmount or state.config.baseUnit
                    print(string.format("[PathGraph] Overlap of %.1f, adjusting...", overlapAmount))
                    resendAdjustedSegment(self, overlapAmount)
                end
            end,
        },

        Out = {
            segment = {},
            pathComplete = {},
            complete = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getPoints = function(self)
            local state = getState(self)
            return state.points
        end,

        getSegments = function(self)
            local state = getState(self)
            return state.segments
        end,

        getPath = function(self)
            local state = getState(self)

            local output = {
                points = {},
                segments = {},
                start = state.startPointId,
                goals = {}, -- Could track goal points if needed
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

            for _, seg in ipairs(state.segments) do
                table.insert(output.segments, {
                    id = seg.id,
                    from = seg.fromId,
                    to = seg.toId,
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

return PathGraph
