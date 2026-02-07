--[[
    Warren Framework v2
    VolumeGraph.lua - Volume-First Dungeon Generator

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Volume-first dungeon generation:
    1. Place room volumes using a clustering strategy
    2. Build connectivity graph (which rooms can connect)
    3. Pathfind to determine actual connections
    4. Emit layout data for Room nodes and DoorwayCutter

    This separates spatial placement from connectivity, making it easier
    to guarantee non-overlapping volumes.

    ============================================================================
    CONFIGURATION
    ============================================================================

    Core:
        baseUnit            Base size unit in studs (default: 15)
        seed                RNG seed for reproducible generation
        wallThickness       Wall thickness for margin calculations (default: 1)

    Clustering:
        strategy            Clustering strategy name: "Grid", "Poisson", "BSP",
                           "Organic", "Radial" (default: "Poisson")
        strategyConfig      Strategy-specific configuration (merged with defaults)

    Connectivity:
        connectionMethod    How to build connections: "Delaunay", "MST", "Nearest",
                           "All" (default: "MST")
        maxConnections      Maximum connections per room (default: 4)
        minDoorSize         Minimum wall overlap for door (default: 4)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ ...options })
        onGenerate({ origin? })

    OUT (emits):
        roomLayout({ id, position, dims, connections })
        complete({ seed, totalRooms, layouts })

--]]

local Node = require(script.Parent.Parent.Node)
local ClusterStrategies = require(script.Parent.ClusterStrategies)

--------------------------------------------------------------------------------
-- VOLUMEGRAPH NODE
--------------------------------------------------------------------------------

local VolumeGraph = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    baseUnit = 15,
                    seed = nil,
                    wallThickness = 1,

                    -- Clustering
                    strategy = "Poisson",
                    strategyConfig = {},

                    -- Connectivity
                    connectionMethod = "MST",
                    maxConnections = 4,
                    minDoorSize = 4,
                },
                rng = nil,
                seed = nil,
                rooms = {},
                connections = {},
                layouts = {},
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
    -- ADJACENCY DETECTION
    ----------------------------------------------------------------------------

    -- Check if two rooms are adjacent (share a wall with enough overlap for door)
    local function areAdjacent(roomA, roomB, minDoorSize, wallThickness)
        local posA, dimsA = roomA.position, roomA.dims
        local posB, dimsB = roomB.position, roomB.dims

        -- Check each axis for touching
        for axis = 1, 3 do
            local distCenters = math.abs(posB[axis] - posA[axis])
            local touchDist = dimsA[axis] / 2 + dimsB[axis] / 2

            -- Are they touching on this axis? (within wall thickness tolerance)
            if math.abs(distCenters - touchDist) <= wallThickness * 2 then
                -- Check overlap on perpendicular axes
                local minOverlap = math.huge

                for perpAxis = 1, 3 do
                    if perpAxis ~= axis then
                        local minA = posA[perpAxis] - dimsA[perpAxis] / 2
                        local maxA = posA[perpAxis] + dimsA[perpAxis] / 2
                        local minB = posB[perpAxis] - dimsB[perpAxis] / 2
                        local maxB = posB[perpAxis] + dimsB[perpAxis] / 2

                        local overlapMin = math.max(minA, minB)
                        local overlapMax = math.min(maxA, maxB)
                        local overlap = overlapMax - overlapMin

                        if overlap <= 0 then
                            minOverlap = 0
                            break
                        end
                        minOverlap = math.min(minOverlap, overlap)
                    end
                end

                if minOverlap >= minDoorSize then
                    return true, axis
                end
            end
        end

        return false, nil
    end

    -- Calculate 3D distance between room centers
    local function roomDistance(roomA, roomB)
        local dx = roomA.position[1] - roomB.position[1]
        local dy = roomA.position[2] - roomB.position[2]
        local dz = roomA.position[3] - roomB.position[3]
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end

    ----------------------------------------------------------------------------
    -- CONNECTIVITY ALGORITHMS
    ----------------------------------------------------------------------------

    -- Build all possible connections (rooms that are adjacent)
    local function findAllAdjacencies(rooms, minDoorSize, wallThickness)
        local edges = {}

        for i = 1, #rooms do
            for j = i + 1, #rooms do
                local adjacent, axis = areAdjacent(rooms[i], rooms[j], minDoorSize, wallThickness)
                if adjacent then
                    table.insert(edges, {
                        from = i,
                        to = j,
                        axis = axis,
                        distance = roomDistance(rooms[i], rooms[j]),
                    })
                end
            end
        end

        return edges
    end

    -- Minimum Spanning Tree (Kruskal's algorithm)
    local function buildMST(rooms, edges)
        -- Sort edges by distance
        table.sort(edges, function(a, b) return a.distance < b.distance end)

        -- Union-Find
        local parent = {}
        for i = 1, #rooms do parent[i] = i end

        local function find(x)
            if parent[x] ~= x then
                parent[x] = find(parent[x])
            end
            return parent[x]
        end

        local function union(x, y)
            local px, py = find(x), find(y)
            if px ~= py then
                parent[px] = py
                return true
            end
            return false
        end

        local mstEdges = {}
        for _, edge in ipairs(edges) do
            if union(edge.from, edge.to) then
                table.insert(mstEdges, edge)
            end
            if #mstEdges == #rooms - 1 then break end
        end

        return mstEdges
    end

    -- Add extra connections beyond MST for loops
    local function addExtraConnections(rooms, allEdges, mstEdges, maxConnections, rng)
        -- Track connection count per room
        local connCount = {}
        for i = 1, #rooms do connCount[i] = 0 end

        local usedEdges = {}
        for _, edge in ipairs(mstEdges) do
            usedEdges[edge.from .. "_" .. edge.to] = true
            usedEdges[edge.to .. "_" .. edge.from] = true
            connCount[edge.from] = connCount[edge.from] + 1
            connCount[edge.to] = connCount[edge.to] + 1
        end

        local extraEdges = {}

        -- Shuffle remaining edges
        local remaining = {}
        for _, edge in ipairs(allEdges) do
            local key1 = edge.from .. "_" .. edge.to
            local key2 = edge.to .. "_" .. edge.from
            if not usedEdges[key1] and not usedEdges[key2] then
                table.insert(remaining, edge)
            end
        end

        -- Add some extra edges (30% chance per eligible edge)
        for _, edge in ipairs(remaining) do
            if connCount[edge.from] < maxConnections and connCount[edge.to] < maxConnections then
                if rng:randomInt(1, 100) <= 30 then
                    table.insert(extraEdges, edge)
                    connCount[edge.from] = connCount[edge.from] + 1
                    connCount[edge.to] = connCount[edge.to] + 1
                end
            end
        end

        return extraEdges
    end

    -- Connect each room to its nearest neighbors
    local function buildNearestConnections(rooms, edges, maxConnections)
        -- Group edges by room
        local roomEdges = {}
        for i = 1, #rooms do roomEdges[i] = {} end

        for _, edge in ipairs(edges) do
            table.insert(roomEdges[edge.from], edge)
            table.insert(roomEdges[edge.to], {
                from = edge.to,
                to = edge.from,
                axis = edge.axis,
                distance = edge.distance,
            })
        end

        -- Sort each room's edges by distance
        for i = 1, #rooms do
            table.sort(roomEdges[i], function(a, b) return a.distance < b.distance end)
        end

        -- Select nearest for each room
        local selected = {}
        local usedEdges = {}

        for i = 1, #rooms do
            local count = 0
            for _, edge in ipairs(roomEdges[i]) do
                if count >= maxConnections then break end

                local key = math.min(edge.from, edge.to) .. "_" .. math.max(edge.from, edge.to)
                if not usedEdges[key] then
                    usedEdges[key] = true
                    table.insert(selected, {
                        from = math.min(edge.from, edge.to),
                        to = math.max(edge.from, edge.to),
                        axis = edge.axis,
                        distance = edge.distance,
                    })
                    count = count + 1
                end
            end
        end

        return selected
    end

    ----------------------------------------------------------------------------
    -- MAIN GENERATION
    ----------------------------------------------------------------------------

    local function generate(self, origin)
        local state = getState(self)
        local config = state.config

        -- Initialize RNG
        state.seed = config.seed or generateSeed()
        state.rng = createRNG(state.seed)

        print("[VolumeGraph] Generating with seed:", state.seed)
        print("[VolumeGraph] Strategy:", config.strategy)

        -- Get clustering strategy
        local strategy = ClusterStrategies.get(config.strategy)
        if not strategy then
            warn("[VolumeGraph] Unknown strategy:", config.strategy)
            return
        end

        -- Build strategy config
        local strategyConfig = {
            baseUnit = config.baseUnit,
            wallThickness = config.wallThickness,
            minDoorSize = config.minDoorSize,
            origin = origin or { 0, 0, 0 },
        }
        for k, v in pairs(config.strategyConfig) do
            strategyConfig[k] = v
        end

        -- Generate room volumes
        local rawRooms = strategy.generate(strategyConfig, state.rng)
        print("[VolumeGraph] Placed", #rawRooms, "rooms")

        -- Convert to standard format with dims
        state.rooms = {}
        for i, room in ipairs(rawRooms) do
            local dims = {
                room.scale[1] * room.baseUnit,
                room.scale[2] * room.baseUnit,
                room.scale[3] * room.baseUnit,
            }
            state.rooms[i] = {
                id = i,
                position = room.position,
                dims = dims,
                scale = room.scale,
                connections = {},
                attachedTo = room.attachedTo,  -- Preserve attachment info
            }
        end

        -- Build connections from attachedTo info (primary source - guaranteed by construction)
        -- This is more reliable than geometric adjacency detection
        local connectionCount = 0
        for i, room in ipairs(state.rooms) do
            if room.attachedTo then
                -- Add bidirectional connection
                table.insert(room.connections, room.attachedTo)
                table.insert(state.rooms[room.attachedTo].connections, i)
                connectionCount = connectionCount + 1
            end
        end
        print("[VolumeGraph] Built", connectionCount, "connections from attachedTo info")

        -- Optionally find additional adjacencies for extra loop connections
        if config.connectionMethod ~= "Tree" and config.maxConnections > 1 then
            local allEdges = findAllAdjacencies(state.rooms, config.minDoorSize, config.wallThickness)
            print("[VolumeGraph] Found", #allEdges, "geometric adjacencies")

            -- Add extra connections beyond the tree (creates loops)
            local usedEdges = {}
            for _, room in ipairs(state.rooms) do
                for _, conn in ipairs(room.connections) do
                    local key = math.min(room.id, conn) .. "_" .. math.max(room.id, conn)
                    usedEdges[key] = true
                end
            end

            local extraCount = 0
            for _, edge in ipairs(allEdges) do
                local key = edge.from .. "_" .. edge.to
                if not usedEdges[key] then
                    local roomA = state.rooms[edge.from]
                    local roomB = state.rooms[edge.to]

                    -- Check connection limits
                    if #roomA.connections < config.maxConnections and
                       #roomB.connections < config.maxConnections then
                        -- 30% chance to add extra connection
                        if state.rng:randomInt(1, 100) <= 30 then
                            table.insert(roomA.connections, edge.to)
                            table.insert(roomB.connections, edge.from)
                            usedEdges[key] = true
                            extraCount = extraCount + 1
                        end
                    end
                end
            end
            print("[VolumeGraph] Added", extraCount, "extra loop connections")
        end

        -- Build layouts and emit signals
        state.layouts = {}
        for _, room in ipairs(state.rooms) do
            local layout = {
                id = room.id,
                position = { room.position[1], room.position[2], room.position[3] },
                dims = { room.dims[1], room.dims[2], room.dims[3] },
                connections = {},
            }
            for _, conn in ipairs(room.connections) do
                table.insert(layout.connections, conn)
            end
            table.insert(state.layouts, layout)

            self.Out:Fire("roomLayout", layout)
        end

        -- Complete signal
        self.Out:Fire("complete", {
            seed = state.seed,
            totalRooms = #state.rooms,
            layouts = state.layouts,
        })
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "VolumeGraph",
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

                -- Core
                if data.baseUnit then config.baseUnit = data.baseUnit end
                if data.seed then config.seed = data.seed end
                if data.wallThickness then config.wallThickness = data.wallThickness end

                -- Clustering
                if data.strategy then config.strategy = data.strategy end
                if data.strategyConfig then
                    for k, v in pairs(data.strategyConfig) do
                        config.strategyConfig[k] = v
                    end
                end

                -- Connectivity
                if data.connectionMethod then config.connectionMethod = data.connectionMethod end
                if data.maxConnections then config.maxConnections = data.maxConnections end
                if data.minDoorSize then config.minDoorSize = data.minDoorSize end
            end,

            onGenerate = function(self, data)
                data = data or {}
                local origin = data.origin or { 0, 80, 0 }
                generate(self, origin)
            end,
        },

        Out = {
            roomLayout = {},
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

return VolumeGraph
