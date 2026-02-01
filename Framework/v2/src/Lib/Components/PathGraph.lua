--[[
    LibPureFiction Framework v2
    PathGraph.lua - Path & Room Volume Generator

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Generates dungeon topology with room volumes. PathGraph owns both point
    positions AND room dimensions. It scans the horizon before choosing
    directions to avoid collisions by construction.

    Flow:
    1. Create point, pick room dims, store AABB
    2. Scan all 6 directions for available space
    3. Pick direction: clear horizon (random) > furthest distance > terminate
    4. Place next point outside current room
    5. Pick dims constrained by available space
    6. Emit layout table for downstream Room creation

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ baseUnit, seed?, spurCount?, ... })
        onGenerate({ start, goals? })

    OUT (emits):
        roomLayout({ id, position, dims, connections })
        pathComplete({ pathIndex })
        complete({ seed, totalRooms, layouts })

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

    local DIRECTIONS = {
        N = { 0, 0, 1 },
        S = { 0, 0, -1 },
        E = { 1, 0, 0 },
        W = { -1, 0, 0 },
        U = { 0, 1, 0 },
        D = { 0, -1, 0 },
    }

    local DIR_KEYS = { "N", "S", "E", "W", "U", "D" }

    local OPPOSITES = {
        N = "S", S = "N",
        E = "W", W = "E",
        U = "D", D = "U",
    }

    -- Maps direction to axis index: X=1, Y=2, Z=3
    local DIR_TO_AXIS = {
        E = 1, W = 1,
        U = 2, D = 2,
        N = 3, S = 3,
    }

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    baseUnit = 15,
                    seed = nil,
                    spurCount = { min = 2, max = 5 },
                    maxSegmentsPerPath = 10,
                    sizeRange = { 1.2, 2.5 },
                    scanDistance = 5, -- baseUnits to scan ahead
                },

                rng = nil,
                seed = nil,

                rooms = {},        -- id -> { position, dims, connections }
                roomAABBs = {},    -- array of { id, minX, maxX, minY, maxY, minZ, maxZ }
                roomCounter = 0,

                paths = {},
                currentPathIndex = 0,
                segmentsInCurrentPath = 0,
                currentRoomId = nil,
                lastDirection = nil,

                goalPos = nil,
                startRoomId = nil,
                layouts = {},      -- collected layout tables for final output
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

        function rng:randomFloat(min, max)
            local val = self:next() / 0xFFFFFFFF
            return min + val * (max - min)
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
    -- AABB UTILITIES
    ----------------------------------------------------------------------------

    local function createAABB(id, pos, dims)
        return {
            id = id,
            minX = pos[1] - dims[1] / 2,
            maxX = pos[1] + dims[1] / 2,
            minY = pos[2] - dims[2] / 2,
            maxY = pos[2] + dims[2] / 2,
            minZ = pos[3] - dims[3] / 2,
            maxZ = pos[3] + dims[3] / 2,
        }
    end

    local function aabbOverlaps(a, b)
        if a.maxX <= b.minX or a.minX >= b.maxX then return false end
        if a.maxY <= b.minY or a.minY >= b.maxY then return false end
        if a.maxZ <= b.minZ or a.minZ >= b.maxZ then return false end
        return true
    end

    -- Find distance from a point to the nearest AABB in a given direction
    -- Returns distance to first obstacle, or scanDist if clear
    local function scanDirection(self, fromPos, fromDims, direction, scanDist, excludeId)
        local state = getState(self)
        local dir = DIRECTIONS[direction]
        local axis = DIR_TO_AXIS[direction]

        -- Start scanning from the edge of the current room
        local startOffset = fromDims[axis] / 2

        local minDistance = scanDist

        for _, aabb in ipairs(state.roomAABBs) do
            if aabb.id ~= excludeId then
                -- Check if this AABB is in our scan path
                -- We need to see if a ray from fromPos in direction hits this AABB

                local axisMin, axisMax
                if axis == 1 then
                    axisMin, axisMax = aabb.minX, aabb.maxX
                elseif axis == 2 then
                    axisMin, axisMax = aabb.minY, aabb.maxY
                else
                    axisMin, axisMax = aabb.minZ, aabb.maxZ
                end

                local fromAxisPos = fromPos[axis]
                local dirSign = dir[axis] -- +1 or -1

                -- Distance to the near edge of the AABB along this axis
                local distToAABB
                if dirSign > 0 then
                    distToAABB = axisMin - fromAxisPos - startOffset
                else
                    distToAABB = fromAxisPos - startOffset - axisMax
                end

                -- Only consider if AABB is ahead of us
                if distToAABB > 0 and distToAABB < minDistance then
                    -- Check if we'd actually hit this AABB (overlaps on other axes)
                    local wouldHit = true

                    -- Check perpendicular axes
                    for checkAxis = 1, 3 do
                        if checkAxis ~= axis then
                            local checkMin, checkMax
                            if checkAxis == 1 then
                                checkMin, checkMax = aabb.minX, aabb.maxX
                            elseif checkAxis == 2 then
                                checkMin, checkMax = aabb.minY, aabb.maxY
                            else
                                checkMin, checkMax = aabb.minZ, aabb.maxZ
                            end

                            local ourMin = fromPos[checkAxis] - fromDims[checkAxis] / 2
                            local ourMax = fromPos[checkAxis] + fromDims[checkAxis] / 2

                            if ourMax <= checkMin or ourMin >= checkMax then
                                wouldHit = false
                                break
                            end
                        end
                    end

                    if wouldHit then
                        minDistance = distToAABB
                    end
                end
            end
        end

        return minDistance
    end

    ----------------------------------------------------------------------------
    -- ROOM CREATION
    ----------------------------------------------------------------------------

    local function getRandomDim(self)
        local state = getState(self)
        local config = state.config
        local range = config.sizeRange
        local scale = state.rng:randomFloat(range[1], range[2])
        return config.baseUnit * scale
    end

    local function createRoom(self, pos, dims, fromRoomId)
        local state = getState(self)
        state.roomCounter = state.roomCounter + 1
        local id = state.roomCounter

        local room = {
            position = { pos[1], pos[2], pos[3] },
            dims = { dims[1], dims[2], dims[3] },
            connections = {},
        }

        state.rooms[id] = room

        local aabb = createAABB(id, pos, dims)
        table.insert(state.roomAABBs, aabb)

        -- Connect to previous room
        if fromRoomId and state.rooms[fromRoomId] then
            table.insert(room.connections, fromRoomId)
            table.insert(state.rooms[fromRoomId].connections, id)
        end

        -- Create and emit layout table
        local layout = {
            id = id,
            position = { pos[1], pos[2], pos[3] },
            dims = { dims[1], dims[2], dims[3] },
            connections = {},
        }
        for _, conn in ipairs(room.connections) do
            table.insert(layout.connections, conn)
        end

        table.insert(state.layouts, layout)

        print(string.format("[PathGraph] Room %d at (%.1f, %.1f, %.1f) dims (%.1f, %.1f, %.1f)",
            id, pos[1], pos[2], pos[3], dims[1], dims[2], dims[3]))

        self.Out:Fire("roomLayout", layout)

        return id
    end

    ----------------------------------------------------------------------------
    -- DIRECTION SELECTION WITH HORIZON SCAN
    ----------------------------------------------------------------------------

    local function pickDirectionWithScan(self, fromRoomId, lastDir)
        local state = getState(self)
        local rng = state.rng
        local config = state.config
        local baseUnit = config.baseUnit
        local scanDist = config.scanDistance * baseUnit

        local room = state.rooms[fromRoomId]
        local fromPos = room.position
        local fromDims = room.dims

        -- Scan all directions
        local scanResults = {}
        for _, dirKey in ipairs(DIR_KEYS) do
            -- Skip opposite of last direction
            if not lastDir or dirKey ~= OPPOSITES[lastDir] then
                local distance = scanDirection(self, fromPos, fromDims, dirKey, scanDist, fromRoomId)
                table.insert(scanResults, { dir = dirKey, distance = distance })
            end
        end

        if #scanResults == 0 then
            return nil, 0
        end

        -- Separate into clear (full scan distance) and partially blocked
        local clearDirs = {}
        local blockedDirs = {}

        for _, result in ipairs(scanResults) do
            if result.distance >= scanDist then
                table.insert(clearDirs, result)
            elseif result.distance > baseUnit then
                -- Only consider if there's at least 1 baseUnit of space
                table.insert(blockedDirs, result)
            end
        end

        -- Priority: clear > furthest blocked > nothing
        if #clearDirs > 0 then
            -- Pick random from clear directions
            local pick = rng:randomChoice(clearDirs)
            return pick.dir, pick.distance
        elseif #blockedDirs > 0 then
            -- Pick the one with most space
            table.sort(blockedDirs, function(a, b) return a.distance > b.distance end)
            return blockedDirs[1].dir, blockedDirs[1].distance
        else
            -- No valid direction
            return nil, 0
        end
    end

    ----------------------------------------------------------------------------
    -- SEGMENT GENERATION
    ----------------------------------------------------------------------------

    local function generateNextRoom(self)
        local state = getState(self)
        local rng = state.rng
        local baseUnit = state.config.baseUnit

        local fromRoom = state.rooms[state.currentRoomId]
        if not fromRoom then
            print("[PathGraph] ERROR: No current room")
            return false
        end

        local fromPos = fromRoom.position
        local fromDims = fromRoom.dims

        -- Pick direction with horizon scanning
        local direction, availableSpace = pickDirectionWithScan(self, state.currentRoomId, state.lastDirection)

        if not direction then
            print("[PathGraph] No valid direction - path terminated")
            return false
        end

        local dir = DIRECTIONS[direction]
        local axis = DIR_TO_AXIS[direction]

        -- Generate random dims for new room, but constrain by available space
        local toDims = { getRandomDim(self), getRandomDim(self), getRandomDim(self) }

        -- The room's dimension along movement axis can't exceed available space
        -- (minus some margin for the room to fit)
        local maxDimForAxis = math.max(baseUnit, availableSpace - baseUnit)
        toDims[axis] = math.min(toDims[axis], maxDimForAxis)

        -- Calculate position: place new room so it mates with current room
        -- Distance from center to center = fromDim/2 + toDim/2 (they touch)
        local centerDistance = fromDims[axis] / 2 + toDims[axis] / 2

        local toPos = {
            fromPos[1] + dir[1] * centerDistance,
            fromPos[2] + dir[2] * centerDistance,
            fromPos[3] + dir[3] * centerDistance,
        }

        -- Create the room
        local toRoomId = createRoom(self, toPos, toDims, state.currentRoomId)

        -- Update state
        state.currentRoomId = toRoomId
        state.lastDirection = direction
        state.segmentsInCurrentPath = state.segmentsInCurrentPath + 1

        return true
    end

    ----------------------------------------------------------------------------
    -- PATH MANAGEMENT
    ----------------------------------------------------------------------------

    local function startNewPath(self, fromRoomId)
        local state = getState(self)

        state.currentPathIndex = state.currentPathIndex + 1
        state.paths[state.currentPathIndex] = {
            startRoomId = fromRoomId,
            roomIds = { fromRoomId },
        }
        state.currentRoomId = fromRoomId
        state.lastDirection = nil
        state.segmentsInCurrentPath = 0

        print(string.format("[PathGraph] Starting path %d from room %d",
            state.currentPathIndex, fromRoomId))
    end

    local function findJunctionCandidates(self)
        local state = getState(self)
        local candidates = {}

        for roomId, room in pairs(state.rooms) do
            -- Rooms with exactly 2 connections are good junction points
            if #room.connections == 2 and roomId ~= state.startRoomId then
                table.insert(candidates, roomId)
            end
        end

        return candidates
    end

    local function shouldEndPath(self)
        local state = getState(self)
        return state.segmentsInCurrentPath >= state.config.maxSegmentsPerPath
    end

    local function advance(self)
        local state = getState(self)

        if shouldEndPath(self) then
            print(string.format("[PathGraph] Path %d complete", state.currentPathIndex))

            self.Out:Fire("pathComplete", { pathIndex = state.currentPathIndex })

            local candidates = findJunctionCandidates(self)
            local spurCount = state.rng:randomInt(
                state.config.spurCount.min,
                state.config.spurCount.max
            )

            if state.currentPathIndex <= spurCount and #candidates > 0 then
                local idx = state.rng:randomInt(1, #candidates)
                startNewPath(self, candidates[idx])
                if not generateNextRoom(self) then
                    -- Can't continue this spur, try another or finish
                    advance(self)
                else
                    advance(self)
                end
            else
                print("[PathGraph] Generation complete")
                self.Out:Fire("complete", {
                    seed = state.seed,
                    totalRooms = state.roomCounter,
                    layouts = state.layouts,
                })
            end
        else
            if not generateNextRoom(self) then
                -- Path is blocked, end it early
                state.segmentsInCurrentPath = state.config.maxSegmentsPerPath
                advance(self)
            else
                advance(self)
            end
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
                if data.sizeRange then
                    config.sizeRange = data.sizeRange
                end
                if data.scanDistance then
                    config.scanDistance = data.scanDistance
                end
            end,

            onGenerate = function(self, data)
                data = data or {}
                local state = getState(self)
                local config = state.config

                -- Reset state
                state.seed = config.seed or generateSeed()
                state.rng = createRNG(state.seed)
                state.rooms = {}
                state.roomAABBs = {}
                state.roomCounter = 0
                state.paths = {}
                state.currentPathIndex = 0
                state.currentRoomId = nil
                state.lastDirection = nil
                state.layouts = {}

                local startPos = data.start or { 0, 0, 0 }
                state.goalPos = (data.goals and data.goals[1]) or { 150, 0, 150 }

                print("[PathGraph] Generating with seed:", state.seed)

                -- Create first room
                local startDims = { getRandomDim(self), getRandomDim(self), getRandomDim(self) }
                state.startRoomId = createRoom(self, startPos, startDims, nil)

                -- Start main path
                startNewPath(self, state.startRoomId)
                advance(self)
            end,
        },

        Out = {
            roomLayout = {},
            pathComplete = {},
            complete = {},
        },

        getRooms = function(self)
            return getState(self).rooms
        end,

        getLayouts = function(self)
            return getState(self).layouts
        end,

        getSeed = function(self)
            return getState(self).seed
        end,
    }
end)

return PathGraph
