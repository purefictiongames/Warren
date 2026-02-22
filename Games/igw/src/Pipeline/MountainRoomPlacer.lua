--[[
    IGW v2 Pipeline — MountainRoomPlacer

    BFS flood-fill maze on terrain. Seeds at the main-spine peak, then
    grows outward via face-attachment in all horizontal directions.
    Each room tries ALL 4 horizontal faces, creating natural hub
    intersections. Rooms follow terrain contour via clamped Y adjustment.
    Growth continues until no more rooms fit or maxRooms is reached.

    Input (payload): splines, heightField, heightFieldGridW/D,
                     heightFieldMinX/Z, seed, dom
    Output (payload): rooms, roomOrder, portalAssignments = {}, doors = {},
                      spawn, DOM room Models

    Signal: onPlaceRooms(payload) → fires nodeComplete
--]]

local VOXEL = 4
local floor = math.floor
local max   = math.max
local min   = math.min
local sqrt  = math.sqrt

--------------------------------------------------------------------------------
-- GEOMETRY UTILITIES
--------------------------------------------------------------------------------

local function shuffle(arr, rng)
    for i = #arr, 2, -1 do
        local j = rng:NextInteger(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

local function boxesOverlap(posA, dimsA, posB, dimsB)
    for axis = 1, 3 do
        local minA = posA[axis] - dimsA[axis] / 2
        local maxA = posA[axis] + dimsA[axis] / 2
        local minB = posB[axis] - dimsB[axis] / 2
        local maxB = posB[axis] + dimsB[axis] / 2
        if maxA <= minB + 0.01 or maxB <= minA + 0.01 then
            return false
        end
    end
    return true
end

local function overlapsAnyRoom(pos, dims, allRooms, excludeId, gap)
    local expanded = { dims[1] + gap, dims[2] + gap, dims[3] + gap }
    for id, room in pairs(allRooms) do
        if id ~= excludeId then
            if boxesOverlap(pos, expanded, room.position, room.dims) then
                return true
            end
        end
    end
    return false
end

local function randomScale(scaleRange, baseUnit, rng)
    local range = scaleRange or { min = 4, max = 10, minY = 4, maxY = 7 }
    baseUnit = baseUnit or 5
    return {
        rng:NextInteger(range.min, range.max) * baseUnit,
        rng:NextInteger(range.minY or range.min, range.maxY or range.max) * baseUnit,
        rng:NextInteger(range.min, range.max) * baseUnit,
    }
end

--------------------------------------------------------------------------------
-- FACE DEFINITIONS
--------------------------------------------------------------------------------

local H_FACES = {
    { axis = 1, dir =  1, name = "E" },
    { axis = 1, dir = -1, name = "W" },
    { axis = 3, dir =  1, name = "N" },
    { axis = 3, dir = -1, name = "S" },
}

local V_FACES = {
    { axis = 2, dir =  1, name = "U" },
    { axis = 2, dir = -1, name = "D" },
}

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

return {
    name = "MountainRoomPlacer",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onPlaceRooms = function(self, payload)
            local Dom = self._System.Dom
            local t0 = os.clock()

            ----------------------------------------------------------------
            -- Height field from payload
            ----------------------------------------------------------------

            local hField  = payload.heightField
            local gridW   = payload.heightFieldGridW
            local gridD   = payload.heightFieldGridD
            local mapMinX = payload.heightFieldMinX
            local mapMinZ = payload.heightFieldMinZ

            if not hField then
                warn("[MountainRoomPlacer] No height field on payload, skipping")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            local mapMaxX = mapMinX + gridW * VOXEL
            local mapMaxZ = mapMinZ + gridD * VOXEL
            local MAP_MARGIN = 40

            local function sampleHeight(wx, wz)
                local xi = max(1, min(gridW, floor((wx - mapMinX) / VOXEL) + 1))
                local zi = max(1, min(gridD, floor((wz - mapMinZ) / VOXEL) + 1))
                return hField[xi][zi]
            end

            local function roomInBounds(pos, dims)
                local halfW = dims[1] / 2
                local halfD = dims[3] / 2
                if pos[1] - halfW < mapMinX + MAP_MARGIN then return false end
                if pos[1] + halfW > mapMaxX - MAP_MARGIN then return false end
                if pos[3] - halfD < mapMinZ + MAP_MARGIN then return false end
                if pos[3] + halfD > mapMaxZ - MAP_MARGIN then return false end
                return true
            end

            ----------------------------------------------------------------
            -- Config
            ----------------------------------------------------------------

            local burialFrac     = self:getAttribute("burialFrac") or 0.5
            local downwardBias   = self:getAttribute("downwardBias") or 50
            local maxRooms       = self:getAttribute("maxRooms") or 800
            local scaleRange     = self:getAttribute("scaleRange")
                or { min = 4, max = 10, minY = 4, maxY = 7 }
            local groundY        = self:getAttribute("groundY") or 0
            local baseUnit       = self:getAttribute("baseUnit") or 10
            local gap            = (self:getAttribute("wallThickness") or 1) * 2
            local doorSize       = self:getAttribute("doorSize") or 24
            local minDoorOverlap = doorSize + 4

            local seed = (payload.seed or os.time()) + 55555
            local rng = Random.new(seed)

            ----------------------------------------------------------------
            -- Find seed position: highest CP on main spine
            ----------------------------------------------------------------

            local splines = payload.splines or {}
            local bestCP, bestElev = nil, -math.huge

            for _, sp in ipairs(splines) do
                if sp.subclass == "main_spine" then
                    for _, cp in ipairs(sp.controlPoints) do
                        if cp.elevation > bestElev then
                            bestElev = cp.elevation
                            bestCP = cp
                        end
                    end
                end
            end

            if not bestCP then
                warn("[MountainRoomPlacer] No main_spine CPs found, skipping")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            ----------------------------------------------------------------
            -- Room state
            ----------------------------------------------------------------

            local allRooms = {}
            local roomOrder = {}
            local nextRoomId = 1

            ----------------------------------------------------------------
            -- Place seed room at peak
            ----------------------------------------------------------------

            local seedDims = randomScale(scaleRange, baseUnit, rng)
            local surfaceY = sampleHeight(bestCP.x, bestCP.z)
            local seedY = surfaceY - seedDims[2] * (burialFrac - 0.5)
            local seedPos = { bestCP.x, seedY, bestCP.z }

            if not roomInBounds(seedPos, seedDims) then
                warn("[MountainRoomPlacer] Seed out of bounds, skipping")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            local seedRoom = {
                id = nextRoomId,
                position = seedPos,
                dims = seedDims,
                pathType = "mountain_seed",
                parentId = nil,
                attachFace = nil,
            }
            allRooms[nextRoomId] = seedRoom
            table.insert(roomOrder, nextRoomId)
            nextRoomId = nextRoomId + 1

            ----------------------------------------------------------------
            -- BFS flood-fill
            ----------------------------------------------------------------

            local frontier = { seedRoom }
            local head = 1
            local hubCount = 0  -- rooms that placed 3+ children

            while head <= #frontier and nextRoomId <= maxRooms do
                local current = frontier[head]
                head = head + 1

                -- Build face list: all 4 horizontal + occasional vertical
                local faces = {}
                for _, f in ipairs(H_FACES) do
                    table.insert(faces, f)
                end
                if rng:NextInteger(1, 100) <= downwardBias then
                    table.insert(faces, V_FACES[2])  -- D
                end
                if rng:NextInteger(1, 100) <= 10 then
                    table.insert(faces, V_FACES[1])  -- U
                end
                shuffle(faces, rng)

                local childCount = 0

                for _, face in ipairs(faces) do
                    if nextRoomId > maxRooms then break end

                    local newDims = randomScale(scaleRange, baseUnit, rng)

                    -- Compute face-attached position
                    local newPos = {
                        current.position[1],
                        current.position[2],
                        current.position[3],
                    }
                    newPos[face.axis] = current.position[face.axis]
                        + face.dir * (current.dims[face.axis] / 2
                        + newDims[face.axis] / 2 + gap)

                    -- Terrain-following Y (horizontal faces only)
                    if face.axis ~= 2 then
                        local surfY = sampleHeight(newPos[1], newPos[3])
                        local desiredY = surfY - newDims[2] * (burialFrac - 0.5)
                        local maxShift = current.dims[2] / 2 + newDims[2] / 2
                            - minDoorOverlap
                        maxShift = max(0, maxShift)
                        local shift = max(-maxShift,
                            min(maxShift, desiredY - newPos[2]))
                        newPos[2] = newPos[2] + shift

                        -- Reject if room floats entirely above terrain
                        if newPos[2] - newDims[2] / 2 > surfY then
                            continue
                        end
                    end

                    -- Door overlap check (non-touch axes must share enough face)
                    local hasDoorOverlap = true
                    for axis = 1, 3 do
                        if axis ~= face.axis then
                            local minA = current.position[axis]
                                - current.dims[axis] / 2
                            local maxA = current.position[axis]
                                + current.dims[axis] / 2
                            local minB = newPos[axis] - newDims[axis] / 2
                            local maxB = newPos[axis] + newDims[axis] / 2
                            local overlap = min(maxA, maxB) - max(minA, minB)
                            if overlap < minDoorOverlap then
                                hasDoorOverlap = false
                                break
                            end
                        end
                    end
                    if not hasDoorOverlap then continue end

                    -- Skip below ground
                    if newPos[2] - newDims[2] / 2 < groundY then
                        continue
                    end

                    -- Bounds + collision
                    if not roomInBounds(newPos, newDims) then continue end
                    if overlapsAnyRoom(newPos, newDims, allRooms, nil, gap) then
                        continue
                    end

                    -- Place room
                    local room = {
                        id = nextRoomId,
                        position = newPos,
                        dims = newDims,
                        pathType = "mountain_room",
                        parentId = current.id,
                        attachFace = face.name,
                    }
                    allRooms[nextRoomId] = room
                    table.insert(roomOrder, nextRoomId)
                    table.insert(frontier, room)
                    nextRoomId = nextRoomId + 1
                    childCount = childCount + 1
                end

                if childCount >= 3 then
                    hubCount = hubCount + 1
                end
            end

            ----------------------------------------------------------------
            -- Store in payload
            ----------------------------------------------------------------

            payload.rooms = allRooms
            payload.roomOrder = roomOrder
            payload.portalAssignments = {}
            payload.doors = {}

            ----------------------------------------------------------------
            -- Create DOM room Models
            ----------------------------------------------------------------

            for id, room in pairs(allRooms) do
                local roomModel = Dom.createElement("Model", {
                    Name = "Room_" .. id,
                    RoomId = id,
                    RoomPosition = room.position,
                    RoomDims = room.dims,
                    ParentRoomId = room.parentId,
                    AttachFace = room.attachFace,
                })
                Dom.appendChild(payload.dom, roomModel)
            end

            ----------------------------------------------------------------
            -- Set spawn inside seed room (at floor level)
            ----------------------------------------------------------------

            if #roomOrder > 0 then
                local firstRoom = allRooms[roomOrder[1]]
                local floorY = firstRoom.position[2] - firstRoom.dims[2] / 2 + 3
                payload.spawn = {
                    position = {
                        firstRoom.position[1],
                        floorY,
                        firstRoom.position[3],
                    },
                }
            end

            payload.roomCount = nextRoomId - 1
            payload.doorCount = 0

            ----------------------------------------------------------------
            -- Summary
            ----------------------------------------------------------------

            local totalRooms = nextRoomId - 1
            local deadEnds = 0
            local childCounts = {}
            for _, room in pairs(allRooms) do
                childCounts[room.id] = 0
            end
            for _, room in pairs(allRooms) do
                if room.parentId then
                    childCounts[room.parentId] = (childCounts[room.parentId] or 0) + 1
                end
            end
            for _, c in pairs(childCounts) do
                if c == 0 then deadEnds = deadEnds + 1 end
            end

            print(string.format(
                "[MountainRoomPlacer] %d rooms, %d hubs (3+ exits), %d dead ends (seed %d) — %.2fs",
                totalRooms, hubCount, deadEnds, seed, os.clock() - t0
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
