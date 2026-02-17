--[[
    IGW v2 Pipeline — MountainRoomMasser
    Places room clusters on mountain pad locations.

    Cluster types:
    - False entries: 1-3 rooms on the mountain face (dead ends)
    - Cave systems: 5+ rooms growing inward from an entry pad

    Multiple independent, non-contiguous room clusters in one map.
    Constraint: every room must overlap at least one mountain volume.
    Post-pass: ensures at least one connected path between adjacent layers.
    Blockout mode — rooms are visible colored Parts.
--]]

--------------------------------------------------------------------------------
-- GEOMETRY UTILITIES
--------------------------------------------------------------------------------

local function shuffle(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
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

--- Check if a room touches or overlaps at least one mountain volume.
--- Uses a small tolerance so rooms flush against a face still pass.
local function touchesMountain(pos, dims, mountain, tolerance)
    tolerance = tolerance or 4
    local expanded = {
        dims[1] + tolerance,
        dims[2] + tolerance,
        dims[3] + tolerance,
    }
    for _, vol in ipairs(mountain) do
        if boxesOverlap(pos, expanded, vol.position, vol.dims) then
            return true
        end
    end
    return false
end

local function randomScale(scaleRange, baseUnit)
    local range = scaleRange or { min = 4, max = 12, minY = 4, maxY = 8 }
    baseUnit = baseUnit or 5
    return {
        math.random(range.min, range.max) * baseUnit,
        math.random(range.minY or range.min, range.maxY or range.max) * baseUnit,
        math.random(range.min, range.max) * baseUnit,
    }
end

--- Determine which mountain layer a room center falls in.
--- Returns layer number or nil if outside all volumes.
local function getRoomLayer(room, mountain)
    local cy = room.position[2]
    for _, vol in ipairs(mountain) do
        local minY = vol.position[2] - vol.dims[2] / 2
        local maxY = vol.position[2] + vol.dims[2] / 2
        if cy >= minY and cy <= maxY then
            -- Also check XZ overlap
            local inXZ = true
            for _, axis in ipairs({1, 3}) do
                local half = vol.dims[axis] / 2
                if room.position[axis] < vol.position[axis] - half
                    or room.position[axis] > vol.position[axis] + half then
                    inXZ = false
                    break
                end
            end
            if inXZ then
                return vol.layer
            end
        end
    end
    return nil
end

local function distXZ(posA, posB)
    local dx = posA[1] - posB[1]
    local dz = posA[3] - posB[3]
    return math.sqrt(dx * dx + dz * dz)
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
-- CLUSTER COLORS (blockout visualization)
--------------------------------------------------------------------------------

local CLUSTER_COLORS = {
    { 60, 140, 200 },   -- blue
    { 200, 80,  60 },   -- red
    { 60, 180, 100 },   -- green
    { 180, 120, 200 },  -- purple
    { 200, 180,  60 },  -- yellow
    { 80, 200, 200 },   -- cyan
    { 200, 120,  80 },  -- orange
    { 140, 140, 200 },  -- lavender
}

local FALSE_ENTRY_COLOR = { 160, 160, 160 } -- grey for dead ends
local BRIDGE_COLOR = { 255, 255, 100 }      -- bright yellow for bridge rooms

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

return {
    name = "MountainRoomMasser",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildRooms = function(self, payload)
            local Dom = self._System.Dom
            local t0 = os.clock()

            local mountain = payload.mountain or {}

            -- Config from cascade
            local scaleRange   = self:getAttribute("scaleRange")
                or { min = 4, max = 12, minY = 4, maxY = 8 }
            local baseUnit     = self:getAttribute("baseUnit") or 5
            local gap          = (self:getAttribute("wallThickness") or 1) * 2
            local doorSize     = self:getAttribute("doorSize") or 12

            local falseEntries = self:getAttribute("falseEntries") or 6
            local caveSystems  = self:getAttribute("caveSystems") or 3
            local falseEntryMaxRooms  = self:getAttribute("falseEntryMaxRooms") or 3
            local caveMinRooms = self:getAttribute("caveMinRooms") or 6
            local caveMaxRooms = self:getAttribute("caveMaxRooms") or 15
            local inwardBias   = self:getAttribute("inwardBias") or 60

            local seed = payload.seed or os.time()
            math.randomseed(seed + 1) -- offset from mountain seed

            ----------------------------------------------------------------
            -- Read pads from DOM (tagged with "mountain-pad" class)
            ----------------------------------------------------------------

            local pads = {}
            for _, child in ipairs(Dom.getChildren(payload.dom)) do
                if Dom.hasClass(child, "mountain-pad") then
                    table.insert(pads, {
                        domNode = child,
                        position = Dom.getAttribute(child, "PadPosition"),
                        normal = Dom.getAttribute(child, "PadNormal"),
                        faceWidth = Dom.getAttribute(child, "PadFaceWidth"),
                        faceHeight = Dom.getAttribute(child, "PadFaceHeight"),
                        volumeId = Dom.getAttribute(child, "VolumeId"),
                        layer = Dom.getAttribute(child, "Layer"),
                        face = Dom.getAttribute(child, "Face"),
                    })
                end
            end

            if #pads == 0 then
                warn("[MountainRoomMasser] No mountain-pad elements found in DOM")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            ----------------------------------------------------------------
            -- Select pads for entries
            ----------------------------------------------------------------

            shuffle(pads)

            local totalEntries = falseEntries + caveSystems
            local selectedPads = {}
            for i = 1, math.min(totalEntries, #pads) do
                table.insert(selectedPads, pads[i])
            end

            -- First N are cave systems, rest are false entries
            local clusters = {}
            for i, pad in ipairs(selectedPads) do
                local isCave = i <= caveSystems
                table.insert(clusters, {
                    pad = pad,
                    isCave = isCave,
                    maxRooms = isCave
                        and math.random(caveMinRooms, caveMaxRooms)
                        or math.random(1, falseEntryMaxRooms),
                })
            end

            ----------------------------------------------------------------
            -- Place rooms for each cluster
            ----------------------------------------------------------------

            local allRooms = {}
            local roomOrder = {}
            local nextRoomId = 1
            local clusterMap = {} -- roomId → clusterIdx

            for clusterIdx, cluster in ipairs(clusters) do
                local pad = cluster.pad
                local inward = {
                    -pad.normal[1],
                    -pad.normal[2],
                    -pad.normal[3],
                }

                -- Entry room: center AT the pad position so it straddles
                -- the mountain face (half inside, half outside)
                local entryDims = randomScale(scaleRange, baseUnit)
                local entryPos = {
                    pad.position[1],
                    pad.position[2],
                    pad.position[3],
                }

                -- Verify: entry must touch mountain + not overlap other rooms
                if touchesMountain(entryPos, entryDims, mountain)
                    and not overlapsAnyRoom(entryPos, entryDims, allRooms, nil, gap)
                then
                    local entryRoom = {
                        id = nextRoomId,
                        position = entryPos,
                        dims = entryDims,
                        pathType = cluster.isCave and "cave_entry" or "false_entry",
                        parentId = nil,
                        attachFace = nil,
                        clusterId = clusterIdx,
                    }
                    allRooms[nextRoomId] = entryRoom
                    table.insert(roomOrder, nextRoomId)
                    clusterMap[nextRoomId] = clusterIdx
                    nextRoomId = nextRoomId + 1

                    -- Grow additional rooms from entry
                    local clusterRooms = { entryRoom }
                    local targetCount = cluster.maxRooms

                    for r = 2, targetCount do
                        -- Pick a parent from this cluster to branch from
                        local parentRoom = clusterRooms[math.random(1, #clusterRooms)]

                        local newDims = randomScale(scaleRange, baseUnit)

                        -- Build face list with inward bias
                        local faces = {}
                        for _, f in ipairs(H_FACES) do
                            local isInward = (f.axis == 1 and f.dir == inward[1])
                                or (f.axis == 3 and f.dir == inward[3])
                            if isInward and math.random(1, 100) <= inwardBias then
                                -- Weight inward faces
                                table.insert(faces, 1, f)
                                table.insert(faces, 1, f)
                            end
                            table.insert(faces, f)
                        end
                        -- Vertical occasionally
                        if math.random(1, 100) <= 20 then
                            for _, f in ipairs(V_FACES) do
                                table.insert(faces, f)
                            end
                        end
                        shuffle(faces)

                        for _, face in ipairs(faces) do
                            local newPos = {
                                parentRoom.position[1],
                                parentRoom.position[2],
                                parentRoom.position[3],
                            }
                            newPos[face.axis] = parentRoom.position[face.axis]
                                + face.dir * (parentRoom.dims[face.axis] / 2
                                + newDims[face.axis] / 2 + gap)

                            -- Door overlap check
                            local hasDoorOverlap = true
                            for axis = 1, 3 do
                                if axis ~= face.axis then
                                    local minA = parentRoom.position[axis] - parentRoom.dims[axis] / 2
                                    local maxA = parentRoom.position[axis] + parentRoom.dims[axis] / 2
                                    local minB = newPos[axis] - newDims[axis] / 2
                                    local maxB = newPos[axis] + newDims[axis] / 2
                                    local overlap = math.min(maxA, maxB) - math.max(minA, minB)
                                    if overlap < doorSize + 4 then
                                        hasDoorOverlap = false
                                        break
                                    end
                                end
                            end

                            -- Must touch mountain + have door space + not collide
                            if hasDoorOverlap
                                and touchesMountain(newPos, newDims, mountain)
                                and not overlapsAnyRoom(newPos, newDims, allRooms, nil, gap)
                            then
                                local room = {
                                    id = nextRoomId,
                                    position = newPos,
                                    dims = newDims,
                                    pathType = cluster.isCave and "cave" or "false_entry",
                                    parentId = parentRoom.id,
                                    attachFace = face.name,
                                    clusterId = clusterIdx,
                                }
                                allRooms[nextRoomId] = room
                                table.insert(roomOrder, nextRoomId)
                                table.insert(clusterRooms, room)
                                clusterMap[nextRoomId] = clusterIdx
                                nextRoomId = nextRoomId + 1
                                break
                            end
                        end
                    end

                    cluster.roomCount = #clusterRooms
                end
            end

            ----------------------------------------------------------------
            -- Layer connectivity pass: ensure adjacent layers are connected
            ----------------------------------------------------------------

            -- Determine max layer
            local maxLayer = 0
            for _, vol in ipairs(mountain) do
                if vol.layer > maxLayer then
                    maxLayer = vol.layer
                end
            end

            -- Assign each room to a layer
            local roomLayers = {} -- roomId → layer
            local roomsByLayer = {} -- layer → { roomId, ... }
            for layer = 0, maxLayer do
                roomsByLayer[layer] = {}
            end

            for id, room in pairs(allRooms) do
                local layer = getRoomLayer(room, mountain)
                if layer then
                    roomLayers[id] = layer
                    table.insert(roomsByLayer[layer], id)
                end
            end

            -- Check each adjacent layer pair for a connected room crossing
            local bridgeCount = 0
            for layer = 0, maxLayer - 1 do
                local upperLayer = layer + 1
                local lowerRooms = roomsByLayer[layer] or {}
                local upperRooms = roomsByLayer[upperLayer] or {}

                -- Skip if either layer has no rooms
                if #lowerRooms == 0 or #upperRooms == 0 then
                    continue
                end

                -- Check if any parent-child pair already spans these layers
                local hasConnection = false
                for _, id in ipairs(upperRooms) do
                    local room = allRooms[id]
                    if room.parentId and roomLayers[room.parentId] == layer then
                        hasConnection = true
                        break
                    end
                end
                if not hasConnection then
                    for _, id in ipairs(lowerRooms) do
                        local room = allRooms[id]
                        if room.parentId and roomLayers[room.parentId] == upperLayer then
                            hasConnection = true
                            break
                        end
                    end
                end

                if hasConnection then
                    continue
                end

                -- No connection — find closest pair of rooms between layers
                local bestDist = math.huge
                local bestLower, bestUpper = nil, nil
                for _, lowId in ipairs(lowerRooms) do
                    for _, upId in ipairs(upperRooms) do
                        local d = distXZ(allRooms[lowId].position, allRooms[upId].position)
                        if d < bestDist then
                            bestDist = d
                            bestLower = allRooms[lowId]
                            bestUpper = allRooms[upId]
                        end
                    end
                end

                if not bestLower or not bestUpper then
                    continue
                end

                -- Place a bridge room between them (vertically connecting)
                local bridgeDims = randomScale(scaleRange, baseUnit)
                local bridgePos = {
                    (bestLower.position[1] + bestUpper.position[1]) / 2,
                    (bestLower.position[2] + bestUpper.position[2]) / 2,
                    (bestLower.position[3] + bestUpper.position[3]) / 2,
                }

                -- Make the bridge tall enough to span the gap
                local lowerTop = bestLower.position[2] + bestLower.dims[2] / 2
                local upperBottom = bestUpper.position[2] - bestUpper.dims[2] / 2
                local verticalSpan = math.abs(upperBottom - lowerTop) + gap * 2
                if verticalSpan > bridgeDims[2] then
                    bridgeDims[2] = verticalSpan
                end

                if touchesMountain(bridgePos, bridgeDims, mountain)
                    and not overlapsAnyRoom(bridgePos, bridgeDims, allRooms, nil, gap)
                then
                    local bridgeRoom = {
                        id = nextRoomId,
                        position = bridgePos,
                        dims = bridgeDims,
                        pathType = "bridge",
                        parentId = bestLower.id,
                        attachFace = "U",
                        clusterId = nil,
                    }
                    allRooms[nextRoomId] = bridgeRoom
                    table.insert(roomOrder, nextRoomId)
                    roomLayers[nextRoomId] = layer
                    nextRoomId = nextRoomId + 1
                    bridgeCount = bridgeCount + 1

                    -- Also connect bridge to upper room by making upper
                    -- a child of bridge (if upper has no parent)
                    if not bestUpper.parentId then
                        bestUpper.parentId = bridgeRoom.id
                        bestUpper.attachFace = "U"
                    end
                end
            end

            ----------------------------------------------------------------
            -- Store in payload
            ----------------------------------------------------------------

            payload.rooms = allRooms
            payload.roomOrder = roomOrder
            payload.clusterMap = clusterMap
            payload.portalAssignments = {}
            payload.doors = {}

            ----------------------------------------------------------------
            -- Create blockout Parts (rooms)
            ----------------------------------------------------------------

            for id, room in pairs(allRooms) do
                local rgb
                if room.pathType == "bridge" then
                    rgb = BRIDGE_COLOR
                elseif room.pathType == "false_entry" then
                    rgb = FALSE_ENTRY_COLOR
                else
                    local cIdx = room.clusterId or 1
                    local colorIdx = ((cIdx - 1) % #CLUSTER_COLORS) + 1
                    rgb = CLUSTER_COLORS[colorIdx]
                end

                local roomModel = Dom.createElement("Model", {
                    Name = "Room_" .. id,
                    RoomId = id,
                    RoomPosition = room.position,
                    RoomDims = room.dims,
                    ParentRoomId = room.parentId,
                    AttachFace = room.attachFace,
                })

                local part = Dom.createElement("Part", {
                    Name = "RoomBlock_" .. id,
                    Size = Vector3.new(room.dims[1], room.dims[2], room.dims[3]),
                    Position = Vector3.new(
                        room.position[1], room.position[2], room.position[3]
                    ),
                    Anchored = true,
                    CanCollide = false,
                    Transparency = 0.5,
                    Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
                    Material = Enum.Material.SmoothPlastic,
                })
                Dom.appendChild(roomModel, part)
                Dom.appendChild(payload.dom, roomModel)
            end

            ----------------------------------------------------------------
            -- Spawn + finalize
            ----------------------------------------------------------------

            -- Spawn inside the first cave entry room, at floor level
            local spawnPos = { 0, 55, 0 }
            for _, id in ipairs(roomOrder) do
                local room = allRooms[id]
                if room and (room.pathType == "cave_entry" or room.pathType == "cave") then
                    local floorY = room.position[2] - room.dims[2] / 2 + 3
                    spawnPos = {
                        room.position[1],
                        floorY,
                        room.position[3],
                    }
                    break
                end
            end
            payload.spawn = { position = spawnPos }
            payload.roomCount = nextRoomId - 1
            payload.doorCount = 0

            -- Summary
            local caveCount, falseCount, totalRooms = 0, 0, 0
            for _, cluster in ipairs(clusters) do
                local rc = cluster.roomCount or 0
                totalRooms = totalRooms + rc
                if cluster.isCave then
                    caveCount = caveCount + 1
                else
                    if rc > 0 then falseCount = falseCount + 1 end
                end
            end

            print(string.format(
                "[MountainRoomMasser] %d rooms (%d cave systems, %d false entries, %d bridge) seed %d — %.2fs",
                nextRoomId - 1, caveCount, falseCount, bridgeCount, seed, os.clock() - t0
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
