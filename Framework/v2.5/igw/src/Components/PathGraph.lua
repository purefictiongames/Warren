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
    CONFIGURATION OPTIONS
    ============================================================================

    Core:
        baseUnit            Base size unit in studs (default: 15)
        seed                RNG seed for reproducible generation

    Path Structure:
        spurCount           { min, max } branching paths (default: 2-5)
        maxSegmentsPerPath  Rooms per path before branching (default: 10)
        straightness        0-100 tendency to continue same direction (default: 50)
        goalBias            0-100 tendency to move toward goal (default: 70)

    Vertical Movement:
        verticalChance      0-100 chance of U/D vs N/S/E/W (default: 15)
        allowUp             Enable upward movement (default: true)
        allowDown           Enable downward movement (default: true)
        minY / maxY         Vertical position limits (default: -200 to 500)

    Room Sizing:
        sizeRange           { min, max } size multiplier (default: 1.2-2.5)
        heightScale         { min, max } height relative to size (default: 0.8-1.2)
        aspectRatio         { min, max } width/depth ratio (default: 0.6-1.4)
        gridSnap            Snap dimensions to this grid for tiling (default: 5)
        minRoomSize         Minimum room dimension (default: baseUnit)

    Spacing:
        scanDistance        Base units to scan ahead (default: 5)
        roomSpacing         { min, max } extra gap between rooms (default: 0-1)
        wallThickness       Wall thickness for overlap margin (default: 1)
        minDoorSize         Minimum wall overlap needed for door (default: 4)

    Boundaries:
        bounds              { min={x,y,z}, max={x,y,z} } spatial limits (optional)

    Multi-Phase Generation:
        phases              Array of phase configs, each with:
                            - preset: Preset name to apply
                            - rooms: Switch after N rooms
                            - paths: Switch after N paths complete
                            - Plus any direct config overrides

        Example:
        phases = {
            { preset = "Cavern", rooms = 5 },      -- First 5 rooms
            { preset = "Labyrinth", paths = 2 },   -- Next 2 paths
            { preset = "Mine" },                    -- Remaining
        }

    ============================================================================
    PRESETS
    ============================================================================

    PathGraph.Presets.Dungeon   - Tight corridors, vertical drops
    PathGraph.Presets.Cavern    - Wide open cave system
    PathGraph.Presets.Tower     - Tall vertical climb (no down)
    PathGraph.Presets.Mine      - Deep underground (no up)
    PathGraph.Presets.Labyrinth - Sprawling flat maze
    PathGraph.Presets.Station   - Uniform space station rooms
    PathGraph.Presets.Cathedral - Massive open spaces
    PathGraph.Presets.Bunker    - Compact low-ceiling bunker

    Usage: pathGraph.In.onConfigure(pathGraph, PathGraph.Presets.Dungeon)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ ...options })
        onGenerate({ start, goals? })
        onSwitchMode({ preset?, ...overrides })  -- Manual mode switch

    OUT (emits):
        roomLayout({ id, position, dims, connections })
        pathComplete({ pathIndex })
        phaseChanged({ phase, preset, totalPhases })
        complete({ seed, totalRooms, layouts })

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

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
                    -- Core settings
                    baseUnit = 15,
                    seed = nil,

                    -- Path structure
                    spurCount = { min = 2, max = 5 },      -- Number of branching paths
                    maxSegmentsPerPath = 10,               -- Rooms per path before branching
                    straightness = 50,                     -- 0-100: tendency to continue same direction
                    goalBias = 70,                         -- 0-100: tendency to move toward goal

                    -- Vertical movement
                    verticalChance = 15,                   -- 0-100: chance of U/D vs N/S/E/W
                    allowUp = true,                        -- Enable upward movement
                    allowDown = true,                      -- Enable downward movement
                    minY = -200,                           -- Minimum Y position
                    maxY = 500,                            -- Maximum Y position

                    -- Room sizing
                    sizeRange = { 1.2, 2.5 },              -- Room size multiplier range
                    heightScale = { 0.8, 1.2 },            -- Height relative to size
                    aspectRatio = { 0.6, 1.4 },            -- Width/depth ratio variation
                    gridSnap = 5,                          -- Snap dimensions to this grid (for tiling)
                    minRoomSize = nil,                     -- Minimum room dimension (default: baseUnit)

                    -- Spacing and density
                    scanDistance = 5,                      -- Base units to scan ahead
                    roomSpacing = { 0, 1 },                -- Extra spacing between rooms (baseUnits)
                    wallThickness = 1,                     -- Wall thickness for overlap margin calculation
                    minDoorSize = 4,                       -- Minimum wall overlap needed for a door

                    -- Boundaries (nil = unlimited)
                    bounds = nil,                          -- { min = {x,y,z}, max = {x,y,z} }

                    -- Multi-phase generation (nil = single phase)
                    -- Each phase applies a preset after conditions are met
                    -- Example: { { preset = "Cavern", rooms = 5 }, { preset = "Mine", paths = 2 } }
                    phases = nil,
                },

                -- Phase tracking
                currentPhase = 1,
                roomsInPhase = 0,
                pathsInPhase = 0,

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

    -- Check if a potential AABB overlaps ANY existing room (excluding connected room)
    -- Adds margin for wall thickness to prevent shell overlap
    -- Returns: overlaps (bool), overlappingAABB, requiredShift {x, y, z}
    local function checkOverlapWithAll(self, pos, dims, connectedRoomId)
        local state = getState(self)
        local config = state.config

        -- Wall thickness margin: shells extend beyond interiors
        local wallMargin = config.wallThickness or 1

        -- Create expanded AABB that accounts for shell
        local expandedAABB = {
            id = 0,
            minX = pos[1] - dims[1] / 2 - wallMargin,
            maxX = pos[1] + dims[1] / 2 + wallMargin,
            minY = pos[2] - dims[2] / 2 - wallMargin,
            maxY = pos[2] + dims[2] / 2 + wallMargin,
            minZ = pos[3] - dims[3] / 2 - wallMargin,
            maxZ = pos[3] + dims[3] / 2 + wallMargin,
        }

        for _, aabb in ipairs(state.roomAABBs) do
            -- Skip the room we're connecting to (overlap there is intentional)
            if aabb.id ~= connectedRoomId then
                -- Expand existing AABB by wall margin too
                local expandedExisting = {
                    minX = aabb.minX - wallMargin,
                    maxX = aabb.maxX + wallMargin,
                    minY = aabb.minY - wallMargin,
                    maxY = aabb.maxY + wallMargin,
                    minZ = aabb.minZ - wallMargin,
                    maxZ = aabb.maxZ + wallMargin,
                }

                -- Check overlap with expanded bounds
                local overlapsX = expandedAABB.maxX > expandedExisting.minX and expandedAABB.minX < expandedExisting.maxX
                local overlapsY = expandedAABB.maxY > expandedExisting.minY and expandedAABB.minY < expandedExisting.maxY
                local overlapsZ = expandedAABB.maxZ > expandedExisting.minZ and expandedAABB.minZ < expandedExisting.maxZ

                if overlapsX and overlapsY and overlapsZ then
                    -- Calculate required shift to clear overlap on each axis
                    -- Shift in direction that requires least movement
                    local shiftX = 0
                    local shiftY = 0
                    local shiftZ = 0

                    -- X axis: shift left or right
                    local shiftXRight = expandedExisting.maxX - expandedAABB.minX
                    local shiftXLeft = expandedAABB.maxX - expandedExisting.minX
                    shiftX = (shiftXRight < shiftXLeft) and shiftXRight or -shiftXLeft

                    -- Y axis: shift up or down
                    local shiftYUp = expandedExisting.maxY - expandedAABB.minY
                    local shiftYDown = expandedAABB.maxY - expandedExisting.minY
                    shiftY = (shiftYUp < shiftYDown) and shiftYUp or -shiftYDown

                    -- Z axis: shift forward or back
                    local shiftZForward = expandedExisting.maxZ - expandedAABB.minZ
                    local shiftZBack = expandedAABB.maxZ - expandedExisting.minZ
                    shiftZ = (shiftZForward < shiftZBack) and shiftZForward or -shiftZBack

                    return true, aabb, { shiftX, shiftY, shiftZ }
                end
            end
        end
        return false, nil, nil
    end

    -- Calculate the wall overlap area between two adjacent rooms on a given axis
    -- Returns overlap amount on each perpendicular axis
    local function calculateWallOverlap(fromPos, fromDims, toPos, toDims, movementAxis)
        local overlaps = {}

        for axis = 1, 3 do
            if axis ~= movementAxis then
                local fromMin = fromPos[axis] - fromDims[axis] / 2
                local fromMax = fromPos[axis] + fromDims[axis] / 2
                local toMin = toPos[axis] - toDims[axis] / 2
                local toMax = toPos[axis] + toDims[axis] / 2

                local overlapMin = math.max(fromMin, toMin)
                local overlapMax = math.min(fromMax, toMax)
                local overlapSize = math.max(0, overlapMax - overlapMin)

                table.insert(overlaps, overlapSize)
            end
        end

        return overlaps
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
    -- PHASE MANAGEMENT
    ----------------------------------------------------------------------------

    local function applyPreset(self, presetName)
        local state = getState(self)
        local config = state.config
        local preset = PathGraph.Presets and PathGraph.Presets[presetName]

        if not preset then
            warn("[PathGraph] Unknown preset:", presetName)
            return false
        end

        print(string.format("[PathGraph] Switching to %s mode", presetName))

        -- Apply preset values to config
        for key, value in pairs(preset) do
            config[key] = value
        end

        return true
    end

    local function checkPhaseAdvance(self)
        local state = getState(self)
        local config = state.config

        if not config.phases then return end

        local phases = config.phases
        local currentPhase = state.currentPhase

        if currentPhase > #phases then return end

        local phase = phases[currentPhase]
        local shouldAdvance = false

        -- Check room count trigger
        if phase.rooms and state.roomsInPhase >= phase.rooms then
            shouldAdvance = true
        end

        -- Check path count trigger
        if phase.paths and state.pathsInPhase >= phase.paths then
            shouldAdvance = true
        end

        if shouldAdvance then
            state.currentPhase = currentPhase + 1
            state.roomsInPhase = 0
            state.pathsInPhase = 0

            -- Apply next phase's preset if there is one
            if state.currentPhase <= #phases then
                local nextPhase = phases[state.currentPhase]
                if nextPhase.preset then
                    applyPreset(self, nextPhase.preset)
                end
                -- Apply any direct config overrides from the phase
                for key, value in pairs(nextPhase) do
                    if key ~= "preset" and key ~= "rooms" and key ~= "paths" then
                        state.config[key] = value
                    end
                end

                -- Emit phase change signal
                self.Out:Fire("phaseChanged", {
                    phase = state.currentPhase,
                    preset = nextPhase.preset,
                    totalPhases = #phases,
                })
            end
        end
    end

    local function initPhases(self)
        local state = getState(self)
        local config = state.config

        state.currentPhase = 1
        state.roomsInPhase = 0
        state.pathsInPhase = 0

        -- Apply first phase if phases are defined
        if config.phases and #config.phases > 0 then
            local firstPhase = config.phases[1]
            if firstPhase.preset then
                applyPreset(self, firstPhase.preset)
            end
            -- Apply direct config overrides
            for key, value in pairs(firstPhase) do
                if key ~= "preset" and key ~= "rooms" and key ~= "paths" then
                    config[key] = value
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- ROOM CREATION
    ----------------------------------------------------------------------------

    -- Snap a value to the nearest multiple of gridSnap
    local function snapToGrid(value, gridSnap)
        return math.floor(value / gridSnap + 0.5) * gridSnap
    end

    local function getRandomRoomDims(self)
        local state = getState(self)
        local config = state.config
        local rng = state.rng
        local baseUnit = config.baseUnit

        -- Grid snap unit - smaller than baseUnit for more variation
        -- but still divides evenly for interior tiling (default: 5 studs)
        local gridSnap = config.gridSnap or 5

        -- Minimum room size
        local minSize = config.minRoomSize or baseUnit

        -- Generate base size from range
        local range = config.sizeRange
        local scale = rng:randomFloat(range[1], range[2])
        local baseSize = baseUnit * scale

        -- Apply aspect ratio variation (width vs depth)
        local aspectRange = config.aspectRatio
        local aspect = rng:randomFloat(aspectRange[1], aspectRange[2])

        local width = baseSize * math.sqrt(aspect)
        local depth = baseSize / math.sqrt(aspect)

        -- Apply height scale
        local heightRange = config.heightScale
        local heightMult = rng:randomFloat(heightRange[1], heightRange[2])
        local height = baseSize * heightMult

        -- Snap to grid (finer than baseUnit for variation, but still tileable)
        width = math.max(minSize, snapToGrid(width, gridSnap))
        depth = math.max(minSize, snapToGrid(depth, gridSnap))
        height = math.max(minSize, snapToGrid(height, gridSnap))

        return { width, height, depth }
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

        -- Track phase progress
        state.roomsInPhase = state.roomsInPhase + 1
        checkPhaseAdvance(self)

        return id
    end

    ----------------------------------------------------------------------------
    -- DIRECTION SELECTION WITH HORIZON SCAN
    ----------------------------------------------------------------------------

    local function isDirectionAllowed(self, dirKey, fromPos)
        local state = getState(self)
        local config = state.config

        -- Check vertical direction restrictions
        if dirKey == "U" and not config.allowUp then return false end
        if dirKey == "D" and not config.allowDown then return false end

        -- Check Y bounds
        if dirKey == "U" and fromPos[2] >= config.maxY then return false end
        if dirKey == "D" and fromPos[2] <= config.minY then return false end

        -- Check spatial bounds if defined
        if config.bounds then
            local dir = DIRECTIONS[dirKey]
            local testDist = config.baseUnit * 2
            local testPos = {
                fromPos[1] + dir[1] * testDist,
                fromPos[2] + dir[2] * testDist,
                fromPos[3] + dir[3] * testDist,
            }
            if testPos[1] < config.bounds.min[1] or testPos[1] > config.bounds.max[1] then return false end
            if testPos[2] < config.bounds.min[2] or testPos[2] > config.bounds.max[2] then return false end
            if testPos[3] < config.bounds.min[3] or testPos[3] > config.bounds.max[3] then return false end
        end

        return true
    end

    local function pickDirectionWithScan(self, fromRoomId, lastDir)
        local state = getState(self)
        local rng = state.rng
        local config = state.config
        local baseUnit = config.baseUnit
        local scanDist = config.scanDistance * baseUnit

        local room = state.rooms[fromRoomId]
        local fromPos = room.position
        local fromDims = room.dims

        -- Build list of allowed directions
        local allowedDirs = {}
        for _, dirKey in ipairs(DIR_KEYS) do
            -- Skip opposite of last direction
            if lastDir and dirKey == OPPOSITES[lastDir] then
                -- Skip
            elseif not isDirectionAllowed(self, dirKey, fromPos) then
                -- Skip restricted direction
            else
                table.insert(allowedDirs, dirKey)
            end
        end

        if #allowedDirs == 0 then
            return nil, 0
        end

        -- Apply vertical chance filter
        local horizontalDirs = {}
        local verticalDirs = {}
        for _, dirKey in ipairs(allowedDirs) do
            if dirKey == "U" or dirKey == "D" then
                table.insert(verticalDirs, dirKey)
            else
                table.insert(horizontalDirs, dirKey)
            end
        end

        local useVertical = #verticalDirs > 0 and rng:randomInt(1, 100) <= config.verticalChance
        local dirPool = useVertical and verticalDirs or horizontalDirs
        if #dirPool == 0 then
            dirPool = allowedDirs  -- Fallback to all allowed
        end

        -- Scan directions in the pool
        local scanResults = {}
        for _, dirKey in ipairs(dirPool) do
            local distance = scanDirection(self, fromPos, fromDims, dirKey, scanDist, fromRoomId)
            table.insert(scanResults, { dir = dirKey, distance = distance })
        end

        -- Separate into clear and blocked
        local clearDirs = {}
        local blockedDirs = {}

        for _, result in ipairs(scanResults) do
            if result.distance >= scanDist then
                table.insert(clearDirs, result)
            elseif result.distance > baseUnit then
                table.insert(blockedDirs, result)
            end
        end

        -- Apply straightness bias (prefer last direction if clear)
        if lastDir and config.straightness > 0 then
            for _, result in ipairs(clearDirs) do
                if result.dir == lastDir and rng:randomInt(1, 100) <= config.straightness then
                    return result.dir, result.distance
                end
            end
        end

        -- Apply goal bias (prefer directions toward goal)
        if state.goalPos and config.goalBias > 0 and #clearDirs > 0 then
            local goalDirs = {}
            local dx = state.goalPos[1] - fromPos[1]
            local dz = state.goalPos[3] - fromPos[3]

            if math.abs(dx) > 1 then
                table.insert(goalDirs, dx > 0 and "E" or "W")
            end
            if math.abs(dz) > 1 then
                table.insert(goalDirs, dz > 0 and "N" or "S")
            end

            for _, result in ipairs(clearDirs) do
                for _, goalDir in ipairs(goalDirs) do
                    if result.dir == goalDir and rng:randomInt(1, 100) <= config.goalBias then
                        return result.dir, result.distance
                    end
                end
            end
        end

        -- Priority: clear > furthest blocked > nothing
        if #clearDirs > 0 then
            local pick = rng:randomChoice(clearDirs)
            return pick.dir, pick.distance
        elseif #blockedDirs > 0 then
            table.sort(blockedDirs, function(a, b) return a.distance > b.distance end)
            return blockedDirs[1].dir, blockedDirs[1].distance
        else
            return nil, 0
        end
    end

    ----------------------------------------------------------------------------
    -- SEGMENT GENERATION
    ----------------------------------------------------------------------------

    local function generateNextRoom(self)
        local state = getState(self)
        local rng = state.rng
        local config = state.config
        local baseUnit = config.baseUnit

        -- Minimum door size (must have at least this much wall overlap)
        local minDoorSize = config.minDoorSize or 4

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

        -- Generate random dims for new room (snapped to baseUnit grid)
        local toDims = getRandomRoomDims(self)

        -- The room's dimension along movement axis can't exceed available space
        local gridSnap = config.gridSnap or 5
        local maxDimForAxis = snapToGrid(math.max(baseUnit, availableSpace - baseUnit), gridSnap)
        toDims[axis] = math.min(toDims[axis], maxDimForAxis)

        -- Calculate position: place new room so it mates with current room
        -- Distance from center to center = fromDim/2 + toDim/2 (they touch)
        local centerDistance = fromDims[axis] / 2 + toDims[axis] / 2

        local toPos = {
            fromPos[1] + dir[1] * centerDistance,
            fromPos[2] + dir[2] * centerDistance,
            fromPos[3] + dir[3] * centerDistance,
        }

        -- Check for overlap with ALL existing rooms and shift position if needed
        -- We can shift on perpendicular axes without breaking the connection
        local maxAttempts = 10
        for attempt = 1, maxAttempts do
            local overlaps, overlappingAABB, requiredShift = checkOverlapWithAll(self, toPos, toDims, state.currentRoomId)

            if not overlaps then
                break  -- No overlap, good to go
            end

            if attempt == maxAttempts then
                print(string.format("[PathGraph] Room placement failed after %d shift attempts", maxAttempts))
                return false
            end

            -- Shift position on perpendicular axes to clear overlap
            -- Don't shift on movement axis (would break the connection)
            local shifted = false
            for shiftAxis = 1, 3 do
                if shiftAxis ~= axis and math.abs(requiredShift[shiftAxis]) > 0.1 then
                    -- Apply shift, snapped to grid for clean positioning
                    local shiftAmount = requiredShift[shiftAxis]
                    -- Add small extra margin to ensure clearance
                    if shiftAmount > 0 then
                        shiftAmount = shiftAmount + config.wallThickness + 0.5
                    else
                        shiftAmount = shiftAmount - config.wallThickness - 0.5
                    end
                    toPos[shiftAxis] = toPos[shiftAxis] + shiftAmount
                    shifted = true
                    break  -- Try one axis at a time
                end
            end

            if not shifted then
                -- Can't shift on perpendicular axes, overlap is on movement axis
                -- This shouldn't happen if horizon scanning worked, but handle it
                print("[PathGraph] Cannot shift to avoid overlap - movement axis blocked")
                return false
            end

            -- After shifting, verify we still have enough wall overlap for a door
            local wallOverlaps = calculateWallOverlap(fromPos, fromDims, toPos, toDims, axis)
            local minOverlap = math.min(wallOverlaps[1] or 0, wallOverlaps[2] or 0)

            if minOverlap < minDoorSize then
                print(string.format("[PathGraph] Shift reduced wall overlap to %.1f (need %.1f for door) - trying different shift",
                    minOverlap, minDoorSize))
                -- Try shifting the other direction
                -- Revert this shift and try opposite
                -- (This is handled by the loop continuing with updated position)
            else
                print(string.format("[PathGraph] Shifted room to avoid overlap (attempt %d), wall overlap: %.1f",
                    attempt, minOverlap))
            end
        end

        -- Final validation: ensure sufficient wall overlap for door
        local finalOverlaps = calculateWallOverlap(fromPos, fromDims, toPos, toDims, axis)
        local finalMinOverlap = math.min(finalOverlaps[1] or 999, finalOverlaps[2] or 999)

        if finalMinOverlap < minDoorSize then
            print(string.format("[PathGraph] Insufficient wall overlap for door: %.1f < %.1f",
                finalMinOverlap, minDoorSize))
            return false
        end

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

            -- Track phase progress
            state.pathsInPhase = state.pathsInPhase + 1
            checkPhaseAdvance(self)

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

                -- Core settings
                if data.baseUnit then config.baseUnit = data.baseUnit end
                if data.seed then config.seed = data.seed end

                -- Path structure
                if data.spurCount then
                    config.spurCount = {
                        min = data.spurCount.min or config.spurCount.min,
                        max = data.spurCount.max or config.spurCount.max,
                    }
                end
                if data.maxSegmentsPerPath then config.maxSegmentsPerPath = data.maxSegmentsPerPath end
                if data.straightness ~= nil then config.straightness = data.straightness end
                if data.goalBias ~= nil then config.goalBias = data.goalBias end

                -- Vertical movement
                if data.verticalChance ~= nil then config.verticalChance = data.verticalChance end
                if data.allowUp ~= nil then config.allowUp = data.allowUp end
                if data.allowDown ~= nil then config.allowDown = data.allowDown end
                if data.minY ~= nil then config.minY = data.minY end
                if data.maxY ~= nil then config.maxY = data.maxY end

                -- Room sizing
                if data.sizeRange then config.sizeRange = data.sizeRange end
                if data.heightScale then config.heightScale = data.heightScale end
                if data.aspectRatio then config.aspectRatio = data.aspectRatio end
                if data.gridSnap then config.gridSnap = data.gridSnap end
                if data.minRoomSize then config.minRoomSize = data.minRoomSize end

                -- Spacing and density
                if data.scanDistance then config.scanDistance = data.scanDistance end
                if data.roomSpacing then config.roomSpacing = data.roomSpacing end
                if data.wallThickness then config.wallThickness = data.wallThickness end
                if data.minDoorSize then config.minDoorSize = data.minDoorSize end

                -- Boundaries
                if data.bounds then config.bounds = data.bounds end

                -- Multi-phase generation
                if data.phases then config.phases = data.phases end
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

                -- Initialize phase system
                initPhases(self)

                -- Create first room
                local startDims = getRandomRoomDims(self)
                state.startRoomId = createRoom(self, startPos, startDims, nil)

                -- Start main path
                startNewPath(self, state.startRoomId)
                advance(self)
            end,

            --[[
                Manually switch generation mode mid-build.
                Can pass a preset name or direct config overrides.
            --]]
            onSwitchMode = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.preset then
                    applyPreset(self, data.preset)
                end

                -- Apply any direct overrides
                for key, value in pairs(data) do
                    if key ~= "preset" then
                        state.config[key] = value
                    end
                end

                print("[PathGraph] Mode switched manually")
            end,
        },

        Out = {
            roomLayout = {},
            pathComplete = {},
            phaseChanged = {},
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

--------------------------------------------------------------------------------
-- PRESETS
--------------------------------------------------------------------------------
-- Ready-to-use configuration presets for common map types

PathGraph.Presets = {
    -- Classic dungeon: tight corridors, lots of vertical drops
    Dungeon = {
        baseUnit = 12,
        spurCount = { min = 3, max = 6 },
        maxSegmentsPerPath = 10,
        sizeRange = { 1.0, 2.0 },
        heightScale = { 0.8, 1.5 },
        aspectRatio = { 0.5, 2.0 },
        verticalChance = 25,
        straightness = 30,
        goalBias = 50,
    },

    -- Wide open cave system
    Cavern = {
        baseUnit = 20,
        spurCount = { min = 2, max = 4 },
        maxSegmentsPerPath = 6,
        sizeRange = { 1.5, 3.5 },
        heightScale = { 1.0, 2.0 },
        aspectRatio = { 0.8, 1.2 },
        verticalChance = 15,
        straightness = 60,
        goalBias = 40,
    },

    -- Tall vertical tower
    Tower = {
        baseUnit = 15,
        spurCount = { min = 1, max = 2 },
        maxSegmentsPerPath = 12,
        sizeRange = { 1.0, 1.8 },
        heightScale = { 1.2, 2.0 },
        aspectRatio = { 0.9, 1.1 },
        verticalChance = 60,
        allowDown = false,
        straightness = 20,
        goalBias = 30,
    },

    -- Deep underground mine
    Mine = {
        baseUnit = 10,
        spurCount = { min = 4, max = 8 },
        maxSegmentsPerPath = 15,
        sizeRange = { 0.8, 1.5 },
        heightScale = { 0.6, 1.0 },
        aspectRatio = { 0.3, 3.0 },
        verticalChance = 40,
        allowUp = false,
        straightness = 70,
        goalBias = 20,
    },

    -- Sprawling flat maze
    Labyrinth = {
        baseUnit = 12,
        spurCount = { min = 5, max = 10 },
        maxSegmentsPerPath = 20,
        sizeRange = { 0.8, 1.2 },
        heightScale = { 0.6, 0.8 },
        aspectRatio = { 0.4, 2.5 },
        verticalChance = 0,
        straightness = 80,
        goalBias = 60,
    },

    -- Space station with uniform rooms
    Station = {
        baseUnit = 18,
        spurCount = { min = 2, max = 4 },
        maxSegmentsPerPath = 8,
        sizeRange = { 1.0, 1.4 },
        heightScale = { 0.9, 1.1 },
        aspectRatio = { 0.9, 1.1 },
        verticalChance = 10,
        straightness = 50,
        goalBias = 70,
    },

    -- Massive cathedral-like spaces
    Cathedral = {
        baseUnit = 25,
        spurCount = { min = 1, max = 3 },
        maxSegmentsPerPath = 5,
        sizeRange = { 2.0, 4.0 },
        heightScale = { 1.5, 3.0 },
        aspectRatio = { 0.7, 1.3 },
        verticalChance = 5,
        straightness = 40,
        goalBias = 80,
    },

    -- Compact bunker
    Bunker = {
        baseUnit = 10,
        spurCount = { min = 2, max = 3 },
        maxSegmentsPerPath = 6,
        sizeRange = { 1.0, 1.5 },
        heightScale = { 0.5, 0.7 },
        aspectRatio = { 0.8, 1.2 },
        verticalChance = 5,
        straightness = 60,
        goalBias = 50,
        roomSpacing = { 0.5, 1.0 },
    },
}

return PathGraph
