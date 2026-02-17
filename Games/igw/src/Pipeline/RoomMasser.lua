--[[
    IGW v2 Pipeline — RoomMasser
    Tree-growth room placement algorithm.
    Creates Model elements for each room in the DOM tree.
--]]

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
-- GEOMETRY UTILITIES (all inline, no shared modules)
--------------------------------------------------------------------------------

local function shuffle(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

local function shellsOverlap(posA, dimsA, posB, dimsB, gap)
    local shellA = { dimsA[1] + gap, dimsA[2] + gap, dimsA[3] + gap }
    local shellB = { dimsB[1] + gap, dimsB[2] + gap, dimsB[3] + gap }

    for axis = 1, 3 do
        local minA = posA[axis] - shellA[axis] / 2
        local maxA = posA[axis] + shellA[axis] / 2
        local minB = posB[axis] - shellB[axis] / 2
        local maxB = posB[axis] + shellB[axis] / 2
        if maxA <= minB + 0.01 or maxB <= minA + 0.01 then
            return false
        end
    end
    return true
end

local function overlapsAny(pos, dims, rooms, excludeId, gap)
    for id, room in pairs(rooms) do
        if id ~= excludeId then
            if shellsOverlap(pos, dims, room.position, room.dims, gap) then
                return true
            end
        end
    end
    return false
end

local function calculateAttachmentPosition(parentPos, parentDims, newDims, face, gap)
    local newPos = { parentPos[1], parentPos[2], parentPos[3] }
    newPos[face.axis] = parentPos[face.axis] +
        face.dir * (parentDims[face.axis]/2 + newDims[face.axis]/2 + gap)
    return newPos
end

local function hasSufficientDoorOverlap(posA, dimsA, posB, dimsB, touchAxis, doorSize)
    local margin = 2
    local requiredOverlap = doorSize + 2 * margin

    for axis = 1, 3 do
        if axis ~= touchAxis then
            local minA = posA[axis] - dimsA[axis] / 2
            local maxA = posA[axis] + dimsA[axis] / 2
            local minB = posB[axis] - dimsB[axis] / 2
            local maxB = posB[axis] + dimsB[axis] / 2
            local overlap = math.min(maxA, maxB) - math.max(minA, minB)
            if overlap < requiredOverlap then
                return false
            end
        end
    end
    return true
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

local function getAttachmentFaces(verticalChance)
    local faces = {}
    for _, f in ipairs(H_FACES) do
        table.insert(faces, { axis = f.axis, dir = f.dir, name = f.name })
    end
    if math.random(1, 100) <= verticalChance then
        for _, f in ipairs(V_FACES) do
            table.insert(faces, { axis = f.axis, dir = f.dir, name = f.name })
        end
    end
    shuffle(faces)
    return faces
end

local function tryAttachRoom(rooms, parentRoom, newDims, face, gap, doorSize)
    local newPos = calculateAttachmentPosition(
        parentRoom.position, parentRoom.dims, newDims, face, gap
    )
    if not hasSufficientDoorOverlap(
        parentRoom.position, parentRoom.dims,
        newPos, newDims,
        face.axis, doorSize
    ) then
        return nil
    end
    if overlapsAny(newPos, newDims, rooms, parentRoom.id, gap) then
        return nil
    end
    return newPos
end

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

return {
    name = "RoomMasser",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local Dom = self._System.Dom
            local seed = payload.seed or os.time()
            local wallThickness = self:getAttribute("wallThickness") or 1
            local gap = 2 * wallThickness
            local doorSize = self:getAttribute("doorSize") or 12
            local verticalChance = self:getAttribute("verticalChance") or 30
            local minVerticalRatio = self:getAttribute("minVerticalRatio") or 0.2
            local origin = self:getAttribute("origin") or { 0, 20, 0 }
            local mainPathLength = self:getAttribute("mainPathLength") or 8
            local spurCount = self:getAttribute("spurCount") or 4
            local scaleRange = self:getAttribute("scaleRange") or { min = 4, max = 12, minY = 4, maxY = 8 }
            local baseUnit = self:getAttribute("baseUnit") or 5

            math.randomseed(seed)

            -- Build inventory
            local inventory = {}
            local roomId = 1

            for i = 1, mainPathLength do
                table.insert(inventory, {
                    id = roomId,
                    dims = randomScale(scaleRange, baseUnit),
                    pathType = "main",
                    parentIdx = i > 1 and (i - 1) or nil,
                })
                roomId = roomId + 1
            end

            for i = 1, spurCount do
                local branchFromIdx = math.random(1, mainPathLength)
                table.insert(inventory, {
                    id = roomId,
                    dims = randomScale(scaleRange, baseUnit),
                    pathType = "spur",
                    parentIdx = branchFromIdx,
                })
                roomId = roomId + 1
            end

            -- Place rooms
            local rooms = {}
            local roomOrder = {}
            local verticalCount = 0
            local totalRooms = #inventory

            for i, entry in ipairs(inventory) do
                if entry.parentIdx == nil then
                    -- First room at origin
                    rooms[entry.id] = {
                        id = entry.id,
                        position = { origin[1], origin[2], origin[3] },
                        dims = entry.dims,
                        pathType = entry.pathType,
                        parentId = nil,
                        attachFace = nil,
                    }
                    table.insert(roomOrder, entry.id)
                else
                    local parentId = roomOrder[entry.parentIdx]
                    local parentRoom = rooms[parentId]
                    if parentRoom then
                        -- Check if we should force vertical
                        local forceVertical = false
                        local roomsRemaining = totalRooms - i + 1
                        local minRequired = math.ceil(totalRooms * minVerticalRatio)
                        local verticalsNeeded = minRequired - verticalCount
                        if verticalsNeeded > 0 and verticalsNeeded >= roomsRemaining then
                            forceVertical = true
                        end

                        local faces
                        if forceVertical then
                            faces = {}
                            for _, f in ipairs(V_FACES) do
                                table.insert(faces, { axis = f.axis, dir = f.dir, name = f.name })
                            end
                            shuffle(faces)
                        else
                            faces = getAttachmentFaces(verticalChance)
                        end

                        local placed = false
                        for _, face in ipairs(faces) do
                            local newPos = tryAttachRoom(rooms, parentRoom, entry.dims, face, gap, doorSize)
                            if newPos then
                                rooms[entry.id] = {
                                    id = entry.id,
                                    position = newPos,
                                    dims = entry.dims,
                                    pathType = entry.pathType,
                                    parentId = parentId,
                                    attachFace = face.name,
                                }
                                table.insert(roomOrder, entry.id)
                                if face.name == "U" or face.name == "D" then
                                    verticalCount = verticalCount + 1
                                end
                                placed = true
                                break
                            end
                        end

                        -- Fallback to horizontal if vertical forced but failed
                        if not placed and forceVertical then
                            local hFaces = {}
                            for _, f in ipairs(H_FACES) do
                                table.insert(hFaces, { axis = f.axis, dir = f.dir, name = f.name })
                            end
                            shuffle(hFaces)
                            for _, face in ipairs(hFaces) do
                                local newPos = tryAttachRoom(rooms, parentRoom, entry.dims, face, gap, doorSize)
                                if newPos then
                                    rooms[entry.id] = {
                                        id = entry.id,
                                        position = newPos,
                                        dims = entry.dims,
                                        pathType = entry.pathType,
                                        parentId = parentId,
                                        attachFace = face.name,
                                    }
                                    table.insert(roomOrder, entry.id)
                                    placed = true
                                    break
                                end
                            end
                        end

                        if not placed then
                            warn("[RoomMasser] Failed to place room " .. entry.id)
                        end
                    end
                end
            end

            -- Compute portal assignments (spur rooms → target biomes)
            local portalAssignments = {}
            local biomeName = payload.biomeName
            local worldMap = payload.worldMap or {}
            local mapEntry = worldMap[biomeName]
            local neighbors = mapEntry and mapEntry.connects or {}
            if #neighbors > 0 then
                local spurIdx = 0
                for _, id in ipairs(roomOrder) do
                    local room = rooms[id]
                    if room and room.pathType == "spur" then
                        spurIdx = spurIdx + 1
                        portalAssignments[id] = neighbors[((spurIdx - 1) % #neighbors) + 1]
                    end
                end
            end
            payload.portalAssignments = portalAssignments

            local portalCount = 0
            for _ in pairs(portalAssignments) do portalCount = portalCount + 1 end
            if portalCount > 0 then
                print(string.format("[RoomMasser] Portal assignments: %d spur rooms → target biomes", portalCount))
                for roomId, target in pairs(portalAssignments) do
                    print(string.format("[RoomMasser]   Room %d → %s", roomId, target))
                end
            end

            -- Create DOM Model elements for each room
            for id, room in pairs(rooms) do
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

            -- Attach sidecar data for downstream math
            payload.rooms = rooms
            payload.gap = gap

            print(string.format("[RoomMasser] Placed %d rooms (seed %d)", totalRooms, seed))

            self.Out:Fire("buildPass", payload)
        end,
    },
}
