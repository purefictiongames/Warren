--[[
    IGW Phase 3 Pipeline — DependencyResolver
    Ensures procedurally generated dungeons are solvable.

    Guarantees: every gated door has its required item reachable from spawn
    without passing through that gate. No circular dependencies. At least
    one valid path from spawn to exit.

    Algorithm (package dependency resolution):
    1. Build adjacency graph from room tree + doors
    2. Find exit room (furthest from spawn by BFS depth)
    3. Find critical path (unique tree path: spawn → exit)
    4. Place gates on critical path doors (evenly spaced)
    5. Optionally gate some branch entrances
    6. For each gate, place required item in rooms reachable before that gate
    7. Validate via simulated traversal

    Solvability guaranteed by construction:
    - Gates processed in order from spawn → exit
    - Items placed in "before" region (reachable without passing through gate)
    - Dependency chain is acyclic by the tree structure
    - Validation catches edge cases; fallback: all-auto doors

    Pipeline signal: onResolveDependencies(payload)
    Also exports .resolve() for direct use by WorldBridge (chunked path).
--]]

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local GATE_TYPES = { "keyed", "shootThrough", "destructible" }

local GATE_TO_ITEM = {
    keyed = "key",
    shootThrough = "weapon",
    destructible = "bomb",
}

local GATE_CONSUMES = {
    keyed = true,
    shootThrough = false,
    destructible = true,
}

--------------------------------------------------------------------------------
-- GRAPH HELPERS
--------------------------------------------------------------------------------

--- Normalize room keys to numeric (JSON serialization may stringify them)
local function normalizeRooms(rooms)
    local out = {}
    for id, room in pairs(rooms) do
        out[tonumber(id) or id] = room
    end
    return out
end

--- Build adjacency list: roomId → [{neighbor, doorIdx}]
local function buildAdjacency(doors)
    local adj = {}
    for i, door in ipairs(doors) do
        local from = tonumber(door.fromRoom) or door.fromRoom
        local to = tonumber(door.toRoom) or door.toRoom
        if not adj[from] then adj[from] = {} end
        if not adj[to] then adj[to] = {} end
        table.insert(adj[from], { neighbor = to, doorIdx = i })
        table.insert(adj[to], { neighbor = from, doorIdx = i })
    end
    return adj
end

--- BFS from startRoom, returns the furthest room (by hop count)
local function findFurthestRoom(adj, startRoom)
    local visited = { [startRoom] = true }
    local queue = { startRoom }
    local head = 1
    local last = startRoom

    while head <= #queue do
        local room = queue[head]
        head = head + 1
        last = room
        for _, edge in ipairs(adj[room] or {}) do
            if not visited[edge.neighbor] then
                visited[edge.neighbor] = true
                table.insert(queue, edge.neighbor)
            end
        end
    end

    return last
end

--- BFS from startRoom to endRoom. Returns path (room list) and door indices along path.
local function findPath(adj, startRoom, endRoom)
    if startRoom == endRoom then return { startRoom }, {} end

    local visited = { [startRoom] = true }
    local parent = {}
    local queue = { startRoom }
    local head = 1
    local found = false

    while head <= #queue do
        local room = queue[head]
        head = head + 1
        if room == endRoom then found = true; break end
        for _, edge in ipairs(adj[room] or {}) do
            if not visited[edge.neighbor] then
                visited[edge.neighbor] = true
                parent[edge.neighbor] = { room = room, doorIdx = edge.doorIdx }
                table.insert(queue, edge.neighbor)
            end
        end
    end

    if not found then return { startRoom }, {} end

    -- Reconstruct
    local path = {}
    local pathDoors = {}
    local current = endRoom
    while current ~= startRoom do
        table.insert(path, 1, current)
        local p = parent[current]
        table.insert(pathDoors, 1, p.doorIdx)
        current = p.room
    end
    table.insert(path, 1, startRoom)
    return path, pathDoors
end

--- BFS from startRoom, skipping blocked door indices. Returns set of reachable rooms.
local function findReachable(adj, startRoom, blockedDoors)
    local visited = { [startRoom] = true }
    local queue = { startRoom }
    local head = 1

    while head <= #queue do
        local room = queue[head]
        head = head + 1
        for _, edge in ipairs(adj[room] or {}) do
            if not visited[edge.neighbor] and not blockedDoors[edge.doorIdx] then
                visited[edge.neighbor] = true
                table.insert(queue, edge.neighbor)
            end
        end
    end

    return visited
end

--- BFS distance from startRoom within a reachable set
local function bfsDistances(adj, startRoom, reachableSet, blockedDoors)
    local dist = { [startRoom] = 0 }
    local queue = { startRoom }
    local head = 1

    while head <= #queue do
        local room = queue[head]
        head = head + 1
        for _, edge in ipairs(adj[room] or {}) do
            if not dist[edge.neighbor]
                and reachableSet[edge.neighbor]
                and not blockedDoors[edge.doorIdx] then
                dist[edge.neighbor] = dist[room] + 1
                table.insert(queue, edge.neighbor)
            end
        end
    end

    return dist
end

--------------------------------------------------------------------------------
-- GATE PLACEMENT
--------------------------------------------------------------------------------

--- Place gates evenly along critical path doors
local function placeGatesOnPath(critPathDoors, gateCount, rng)
    local gates = {}  -- doorIdx → gateType
    local total = #critPathDoors
    if total == 0 or gateCount == 0 then return gates end

    gateCount = math.min(gateCount, total)
    local step = total / (gateCount + 1)
    local usedPositions = {}

    for i = 1, gateCount do
        local pos = math.floor(step * i + 0.5)
        pos = math.max(1, math.min(total, pos))
        while usedPositions[pos] and pos < total do pos = pos + 1 end
        if not usedPositions[pos] then
            usedPositions[pos] = true
            local doorIdx = critPathDoors[pos]
            gates[doorIdx] = GATE_TYPES[rng:NextInteger(1, #GATE_TYPES)]
        end
    end

    return gates
end

--- Optionally gate branch entrances (connections from critical path to branches)
local function placeBranchGates(adj, critPathSet, branchGateChance, rng, gates, doors)
    for i, door in ipairs(doors) do
        if gates[i] then continue end
        local from = tonumber(door.fromRoom) or door.fromRoom
        local to = tonumber(door.toRoom) or door.toRoom
        local fromOnPath = critPathSet[from]
        local toOnPath = critPathSet[to]
        -- Branch entrance: one side on critical path, other is not
        if (fromOnPath and not toOnPath) or (not fromOnPath and toOnPath) then
            if rng:NextNumber() < branchGateChance then
                gates[i] = GATE_TYPES[rng:NextInteger(1, #GATE_TYPES)]
            end
        end
    end
end

--------------------------------------------------------------------------------
-- ITEM PLACEMENT (DEPENDENCY RESOLUTION)
--------------------------------------------------------------------------------

local function resolveItemPlacements(adj, doors, spawnRoom, gates, critPathDoors, rooms, rng, maxKeyDistance)
    local itemPlacements = {}

    -- Order: critical path gates first (spawn → exit), then branch gates
    local critPathDoorSet = {}
    for _, doorIdx in ipairs(critPathDoors) do critPathDoorSet[doorIdx] = true end

    local orderedGates = {}
    for _, doorIdx in ipairs(critPathDoors) do
        if gates[doorIdx] then
            table.insert(orderedGates, doorIdx)
        end
    end
    for doorIdx, _ in pairs(gates) do
        if not critPathDoorSet[doorIdx] then
            table.insert(orderedGates, doorIdx)
        end
    end

    -- Weapon is reusable — only place one for all shootThrough gates
    local weaponPlaced = false

    for _, doorIdx in ipairs(orderedGates) do
        local gateType = gates[doorIdx]
        local itemType = GATE_TO_ITEM[gateType]
        if not itemType then continue end

        if gateType == "shootThrough" and weaponPlaced then continue end

        -- Block this gate + all gates after it on the critical path
        local blocked = { [doorIdx] = true }
        local pastThis = false
        for _, cpDoorIdx in ipairs(critPathDoors) do
            if cpDoorIdx == doorIdx then pastThis = true end
            if pastThis and cpDoorIdx ~= doorIdx and gates[cpDoorIdx] then
                blocked[cpDoorIdx] = true
            end
        end

        local reachable = findReachable(adj, spawnRoom, blocked)

        -- Distance from gate's "before" side for key-distance control
        local door = doors[doorIdx]
        local from = tonumber(door.fromRoom) or door.fromRoom
        local to = tonumber(door.toRoom) or door.toRoom
        local gateRoom = reachable[from] and from or to
        local distances = bfsDistances(adj, gateRoom, reachable, blocked)

        -- Rank candidates by distance from gate
        local candidates = {}
        for roomId, dist in pairs(distances) do
            if rooms[roomId] and dist > 0 then
                table.insert(candidates, { roomId = roomId, dist = dist })
            end
        end
        table.sort(candidates, function(a, b) return a.dist < b.dist end)

        -- Pick based on maxKeyDistance
        local chosen = nil
        if #candidates > 0 then
            local targetDist = math.max(1, rng:NextInteger(1, math.max(1, maxKeyDistance)))
            local best = candidates[1]
            for _, c in ipairs(candidates) do
                if c.dist <= targetDist then
                    best = c
                else
                    break
                end
            end
            chosen = best.roomId
        end

        if not chosen and reachable[spawnRoom] then
            chosen = spawnRoom
        end

        if chosen then
            table.insert(itemPlacements, {
                itemType = itemType,
                roomId = chosen,
            })
            if gateType == "shootThrough" then
                weaponPlaced = true
            end
        else
            -- Can't place item — remove gate to prevent deadlock
            gates[doorIdx] = nil
            warn("[DependencyResolver] No reachable room for gate " .. doorIdx .. " — removing gate")
        end
    end

    return itemPlacements
end

--------------------------------------------------------------------------------
-- VALIDATION — simulate player traversal
--------------------------------------------------------------------------------

local function validateSolvability(adj, doors, spawnRoom, exitRoom, itemPlacements)
    local itemsInRoom = {}
    for _, p in ipairs(itemPlacements) do
        if not itemsInRoom[p.roomId] then itemsInRoom[p.roomId] = {} end
        table.insert(itemsInRoom[p.roomId], p.itemType)
    end

    local gateMap = {}
    for i, door in ipairs(doors) do
        if door.type and door.type ~= "auto" then
            gateMap[i] = door.type
        end
    end

    local inventory = {}
    local openedGates = {}
    local progress = true

    while progress do
        progress = false

        -- BFS: find all currently reachable rooms
        local reachable = {}
        local visited = { [spawnRoom] = true }
        local queue = { spawnRoom }
        local head = 1
        while head <= #queue do
            local room = queue[head]
            head = head + 1
            reachable[room] = true
            for _, edge in ipairs(adj[room] or {}) do
                if not visited[edge.neighbor] then
                    local gate = gateMap[edge.doorIdx]
                    if not gate or openedGates[edge.doorIdx] then
                        visited[edge.neighbor] = true
                        table.insert(queue, edge.neighbor)
                    end
                end
            end
        end

        -- Collect items in newly reachable rooms
        for roomId, _ in pairs(reachable) do
            if itemsInRoom[roomId] then
                for _, itemType in ipairs(itemsInRoom[roomId]) do
                    inventory[itemType] = (inventory[itemType] or 0) + 1
                end
                itemsInRoom[roomId] = nil
                progress = true
            end
        end

        -- Try to open gates with collected items
        for doorIdx, gateType in pairs(gateMap) do
            if not openedGates[doorIdx] then
                local required = GATE_TO_ITEM[gateType]
                if required and (inventory[required] or 0) > 0 then
                    local door = doors[doorIdx]
                    local from = tonumber(door.fromRoom) or door.fromRoom
                    local to = tonumber(door.toRoom) or door.toRoom
                    if reachable[from] or reachable[to] then
                        openedGates[doorIdx] = true
                        if GATE_CONSUMES[gateType] then
                            inventory[required] = inventory[required] - 1
                        end
                        progress = true
                    end
                end
            end
        end
    end

    -- Final check: is exit reachable?
    local finalVisited = { [spawnRoom] = true }
    local fQueue = { spawnRoom }
    local fHead = 1
    while fHead <= #fQueue do
        local room = fQueue[fHead]
        fHead = fHead + 1
        for _, edge in ipairs(adj[room] or {}) do
            if not finalVisited[edge.neighbor] then
                local gate = gateMap[edge.doorIdx]
                if not gate or openedGates[edge.doorIdx] then
                    finalVisited[edge.neighbor] = true
                    table.insert(fQueue, edge.neighbor)
                end
            end
        end
    end

    return finalVisited[exitRoom] == true
end

--------------------------------------------------------------------------------
-- PUBLIC API — resolve()
--------------------------------------------------------------------------------

--- Pure function: resolve dependencies on a full room/door graph.
--- Returns { doorTypes, doorTypesByIdentity, itemPlacements, exitRoom, criticalPath, valid }
local function resolve(rooms, doors, spawn, config, seed)
    rooms = normalizeRooms(rooms or {})
    doors = doors or {}
    config = config or {}

    local rng = Random.new(seed or os.time())
    local gateCountMin = config.gateCountMin or 1
    local gateCountMax = config.gateCountMax or 3
    local maxKeyDistance = config.maxKeyDistance or 4
    local branchGateChance = config.branchGateChance or 0.3

    -- Determine spawn room
    local spawnRoom = spawn and spawn.roomId
    if spawnRoom then spawnRoom = tonumber(spawnRoom) or spawnRoom end
    if not spawnRoom or not rooms[spawnRoom] then
        for id, _ in pairs(rooms) do
            spawnRoom = id
            break
        end
    end

    -- Empty result for degenerate cases
    local emptyResult = {
        doorTypes = {},
        doorTypesByIdentity = {},
        itemPlacements = {},
        exitRoom = nil,
        criticalPath = {},
        valid = true,
    }
    if not spawnRoom then return emptyResult end

    -- Build graph
    local adj = buildAdjacency(doors)

    -- Find exit (furthest connected room from spawn)
    local exitRoom = findFurthestRoom(adj, spawnRoom)

    -- Find critical path
    local critPath, critPathDoors = findPath(adj, spawnRoom, exitRoom)

    -- Too few doors for gating
    if #critPathDoors < 1 then
        emptyResult.exitRoom = exitRoom
        emptyResult.criticalPath = critPath
        return emptyResult
    end

    -- Place gates on critical path
    local gateCount = rng:NextInteger(gateCountMin, math.min(gateCountMax, #critPathDoors))
    local gates = placeGatesOnPath(critPathDoors, gateCount, rng)

    -- Place gates on branch entrances
    local critPathSet = {}
    for _, roomId in ipairs(critPath) do critPathSet[roomId] = true end
    placeBranchGates(adj, critPathSet, branchGateChance, rng, gates, doors)

    -- Resolve item placements (the core dependency resolution)
    local itemPlacements = resolveItemPlacements(
        adj, doors, spawnRoom, gates, critPathDoors, rooms, rng, maxKeyDistance
    )

    -- Apply gate types to doors
    local doorTypes = {}
    local doorTypesByIdentity = {}
    for i, door in ipairs(doors) do
        local gateType = gates[i] or "auto"
        doorTypes[i] = gateType
        door.type = gateType
        local key = tostring(door.fromRoom) .. "-" .. tostring(door.toRoom)
        doorTypesByIdentity[key] = gateType
    end

    -- Validate
    local valid = validateSolvability(adj, doors, spawnRoom, exitRoom, itemPlacements)
    if not valid then
        warn("[DependencyResolver] Validation failed — falling back to all-auto")
        for i, door in ipairs(doors) do
            doorTypes[i] = "auto"
            door.type = "auto"
            local key = tostring(door.fromRoom) .. "-" .. tostring(door.toRoom)
            doorTypesByIdentity[key] = "auto"
        end
        itemPlacements = {}
    end

    return {
        doorTypes = doorTypes,
        doorTypesByIdentity = doorTypesByIdentity,
        itemPlacements = itemPlacements,
        exitRoom = exitRoom,
        criticalPath = critPath,
        valid = valid,
    }
end

--------------------------------------------------------------------------------
-- PIPELINE NODE
--------------------------------------------------------------------------------

return {
    name = "DependencyResolver",
    domain = "server",

    resolve = resolve,  -- Exposed for direct use by WorldBridge

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onResolveDependencies = function(self, payload)
            local Dom = _G.Warren.Dom

            local config = {
                gateCountMin = self:getAttribute("gateCountMin") or 1,
                gateCountMax = self:getAttribute("gateCountMax") or 3,
                maxKeyDistance = self:getAttribute("maxKeyDistance") or 4,
                branchGateChance = self:getAttribute("branchGateChance") or 0.3,
            }

            local result = resolve(
                payload.rooms,
                payload.doors,
                payload.spawn,
                config,
                payload.seed
            )

            -- Bake results into DOM (planning-phase metadata for downstream nodes)
            local root = Dom.getRoot()
            if root then
                Dom.setAttribute(root, "CriticalPath", result.criticalPath)
                Dom.setAttribute(root, "ExitRoom", result.exitRoom)

                -- Build critical path set for fast lookup
                local critPathSet = {}
                for _, rid in ipairs(result.criticalPath) do
                    critPathSet[tonumber(rid) or rid] = true
                end

                -- Build per-room item lists
                local roomItems = {}
                for _, p in ipairs(result.itemPlacements) do
                    local rid = tonumber(p.roomId) or p.roomId
                    if not roomItems[rid] then roomItems[rid] = {} end
                    table.insert(roomItems[rid], p.itemType)
                end

                -- Annotate each room DomNode
                for _, child in ipairs(Dom.getChildren(root)) do
                    local roomId = Dom.getAttribute(child, "RoomId")
                    if roomId then
                        local rid = tonumber(roomId) or roomId

                        if roomItems[rid] then
                            Dom.setAttribute(child, "ResolverItems", roomItems[rid])
                        end

                        if critPathSet[rid] then
                            Dom.setAttribute(child, "OnCriticalPath", true)
                        end

                        if result.exitRoom
                            and (tonumber(result.exitRoom) or result.exitRoom) == rid then
                            Dom.setAttribute(child, "IsExitRoom", true)
                        end
                    end
                end
            end

            -- Also put on payload (backward compat + chunk path)
            payload.itemPlacements = result.itemPlacements
            payload.exitRoom = result.exitRoom
            payload.criticalPath = result.criticalPath

            -- Summary log
            local gateCounts = {}
            local totalGates = 0
            for _, gateType in pairs(result.doorTypes) do
                if gateType ~= "auto" then
                    gateCounts[gateType] = (gateCounts[gateType] or 0) + 1
                    totalGates = totalGates + 1
                end
            end
            local parts = {}
            for t, c in pairs(gateCounts) do
                table.insert(parts, t .. "=" .. c)
            end
            table.sort(parts)

            print(string.format(
                "[DependencyResolver] %d gates (%s), %d items, path=%d rooms, valid=%s",
                totalGates,
                table.concat(parts, " "),
                #result.itemPlacements,
                #result.criticalPath,
                tostring(result.valid)
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
