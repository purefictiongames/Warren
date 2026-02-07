--[[
    Warren Framework v2
    VolumeBuilder.lua - Room Volume Placement

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    VolumeBuilder places room volumes in 3D space. It has no knowledge of the
    dungeon inventory - it simply receives geometry and places it, tracking
    placed AABBs for collision detection.

    Placement Strategy:
    - New rooms attach to a parent room on one of 6 faces (E/W/N/S/U/D)
    - Rooms are center-aligned on perpendicular axes (no random offset)
    - This guarantees maximum door overlap between parent and child
    - Overlap checking against ALL other rooms prevents volumetric collisions

    Used by DungeonOrchestrator in the sequential build pipeline:
    VolumeBuilder -> ShellBuilder -> DoorCutter -> next room

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ wallThickness, minDoorSize })
        onPlaceOrigin({ roomId, dims, position })    -- first room
        onPlaceRoom({ roomId, dims, parentRoomId })  -- subsequent rooms
        onClear({})

    OUT (emits):
        placed({ roomId, position, dims, parentRoomId, attachFace })
        failed({ roomId, reason })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- VOLUME BUILDER NODE
--------------------------------------------------------------------------------

local VolumeBuilder = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    wallThickness = nil,  -- Required: set by orchestrator
                    doorSize = nil,       -- Required: set by orchestrator (doors are square)
                    verticalChance = 30,  -- % chance to try vertical connections (default 30%)
                },
                placedRooms = {},  -- { [roomId] = { id, position, dims, parentRoomId, attachFace } }
                roomsArray = {},   -- Array for iteration order
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- FACE DEFINITIONS
    ----------------------------------------------------------------------------

    -- Face definitions: axis index and direction
    local FACES = {
        { axis = 1, dir =  1, name = "E" },  -- +X
        { axis = 1, dir = -1, name = "W" },  -- -X
        { axis = 2, dir =  1, name = "U" },  -- +Y (up)
        { axis = 2, dir = -1, name = "D" },  -- -Y (down)
        { axis = 3, dir =  1, name = "N" },  -- +Z
        { axis = 3, dir = -1, name = "S" },  -- -Z
    }

    -- Horizontal faces only (most common for dungeon layouts)
    local H_FACES = {
        { axis = 1, dir =  1, name = "E" },
        { axis = 1, dir = -1, name = "W" },
        { axis = 3, dir =  1, name = "N" },
        { axis = 3, dir = -1, name = "S" },
    }

    -- Vertical faces only
    local V_FACES = {
        { axis = 2, dir =  1, name = "U" },
        { axis = 2, dir = -1, name = "D" },
    }

    ----------------------------------------------------------------------------
    -- GEOMETRY UTILITIES
    ----------------------------------------------------------------------------

    -- Check if two AABBs overlap (penetrate each other)
    -- Uses shell dimensions (interior + wallThickness on each side)
    local function shellsOverlap(posA, dimsA, posB, dimsB, wallThickness)
        -- Shell dimensions = interior + 2*wallThickness per axis
        local shellA = {
            dimsA[1] + 2 * wallThickness,
            dimsA[2] + 2 * wallThickness,
            dimsA[3] + 2 * wallThickness,
        }
        local shellB = {
            dimsB[1] + 2 * wallThickness,
            dimsB[2] + 2 * wallThickness,
            dimsB[3] + 2 * wallThickness,
        }

        -- Check for separation on any axis (if separated on any axis, no overlap)
        for axis = 1, 3 do
            local minA = posA[axis] - shellA[axis] / 2
            local maxA = posA[axis] + shellA[axis] / 2
            local minB = posB[axis] - shellB[axis] / 2
            local maxB = posB[axis] + shellB[axis] / 2

            -- Allow touching (<=) but not penetrating (<)
            -- Small epsilon to handle floating point
            local epsilon = 0.01
            if maxA <= minB + epsilon or maxB <= minA + epsilon then
                return false  -- Separated on this axis, no overlap
            end
        end

        return true  -- Overlapping on all axes = collision
    end

    -- Check if a new room's shell overlaps any existing room's shell
    -- excludeRoomId: don't check against parent (they're supposed to touch)
    local function overlapsAnyRoom(pos, dims, placedRooms, excludeRoomId, wallThickness)
        for roomId, room in pairs(placedRooms) do
            if roomId ~= excludeRoomId then
                if shellsOverlap(pos, dims, room.position, room.dims, wallThickness) then
                    return true, roomId
                end
            end
        end
        return false, nil
    end

    -- Shuffle array in place
    local function shuffle(arr)
        for i = #arr, 2, -1 do
            local j = math.random(1, i)
            arr[i], arr[j] = arr[j], arr[i]
        end
    end

    -- Get faces to try for attachment (shuffled for variety)
    local function getAttachmentFaces(verticalChance)
        verticalChance = verticalChance or 30
        local faces = {}

        -- Always include horizontal faces
        for _, face in ipairs(H_FACES) do
            table.insert(faces, { axis = face.axis, dir = face.dir, name = face.name })
        end

        -- Occasionally add vertical faces
        if math.random(1, 100) <= verticalChance then
            for _, face in ipairs(V_FACES) do
                table.insert(faces, { axis = face.axis, dir = face.dir, name = face.name })
            end
        end

        shuffle(faces)
        return faces
    end

    ----------------------------------------------------------------------------
    -- ROOM PLACEMENT
    ----------------------------------------------------------------------------

    -- Calculate position for new room attached to parent on given face
    -- Rooms are CENTER-ALIGNED on perpendicular axes (no random offset)
    local function calculateAttachmentPosition(parentPos, parentDims, newDims, face, wallThickness)
        -- Start at parent's center
        local newPos = { parentPos[1], parentPos[2], parentPos[3] }

        -- Move along attachment axis so shells touch
        -- Shell edge of parent: parentPos + parentDims/2 + wallThickness
        -- Shell edge of new: newPos - newDims/2 - wallThickness
        -- For touching: newPos = parentPos + parentDims/2 + newDims/2 + 2*wallThickness
        newPos[face.axis] = parentPos[face.axis] +
            face.dir * (parentDims[face.axis]/2 + newDims[face.axis]/2 + 2 * wallThickness)

        -- Perpendicular axes: stay centered (no offset)
        -- This guarantees maximum overlap for door placement

        return newPos
    end

    -- Check if two rooms have sufficient overlap for a door
    local function hasSufficientDoorOverlap(posA, dimsA, posB, dimsB, touchAxis, doorSize)
        -- Door needs overlap on both perpendicular axes
        local margin = 2  -- DoorCutter uses margin=2
        local requiredOverlap = doorSize + 2 * margin

        for axis = 1, 3 do
            if axis ~= touchAxis then
                -- Calculate overlap on this axis
                local minA = posA[axis] - dimsA[axis] / 2
                local maxA = posA[axis] + dimsA[axis] / 2
                local minB = posB[axis] - dimsB[axis] / 2
                local maxB = posB[axis] + dimsB[axis] / 2

                local overlapMin = math.max(minA, minB)
                local overlapMax = math.min(maxA, maxB)
                local overlap = overlapMax - overlapMin

                if overlap < requiredOverlap then
                    return false
                end
            end
        end

        return true
    end

    -- Try to attach a new room to parent on a specific face
    local function tryAttachOnFace(self, parentRoom, newDims, face)
        local state = getState(self)
        local config = state.config
        local wallThickness = config.wallThickness
        local doorSize = config.doorSize

        local parentPos = parentRoom.position
        local parentDims = parentRoom.dims

        -- Calculate position (center-aligned on perpendicular axes)
        local newPos = calculateAttachmentPosition(
            parentPos, parentDims, newDims, face, wallThickness
        )

        -- Check door overlap with parent
        if not hasSufficientDoorOverlap(parentPos, parentDims, newPos, newDims, face.axis, doorSize) then
            return nil, "Insufficient door overlap"
        end

        -- Check for volumetric collision with ALL other rooms
        local overlaps, collidingRoomId = overlapsAnyRoom(
            newPos, newDims, state.placedRooms, parentRoom.id, wallThickness
        )

        if overlaps then
            return nil, "Overlaps room " .. tostring(collidingRoomId)
        end

        return newPos, face.name
    end

    -- Place the first room at a given position
    local function placeOriginRoom(self, roomId, dims, position)
        local state = getState(self)

        local room = {
            id = roomId,
            position = { position[1], position[2], position[3] },
            dims = { dims[1], dims[2], dims[3] },
            parentRoomId = nil,
            attachFace = nil,
        }

        state.placedRooms[roomId] = room
        table.insert(state.roomsArray, room)

        return room
    end

    -- Place a room attached to a parent room
    local function placeAttachedRoom(self, roomId, dims, parentRoomId, forceVertical)
        local state = getState(self)

        local parentRoom = state.placedRooms[parentRoomId]
        if not parentRoom then
            return nil, "Parent room not found: " .. tostring(parentRoomId)
        end

        -- Get faces to try
        local faces
        if forceVertical then
            -- Only try vertical faces when forced
            faces = {}
            for _, face in ipairs(V_FACES) do
                table.insert(faces, { axis = face.axis, dir = face.dir, name = face.name })
            end
            shuffle(faces)
        else
            -- Normal behavior: mostly horizontal with some vertical chance
            faces = getAttachmentFaces(state.config.verticalChance)
        end
        local errors = {}

        for _, face in ipairs(faces) do
            local newPos, result = tryAttachOnFace(self, parentRoom, dims, face)

            if newPos then
                local room = {
                    id = roomId,
                    position = newPos,
                    dims = { dims[1], dims[2], dims[3] },
                    parentRoomId = parentRoomId,
                    attachFace = result,  -- result is the face name when successful
                }

                state.placedRooms[roomId] = room
                table.insert(state.roomsArray, room)

                return room, nil
            else
                table.insert(errors, face.name .. ": " .. (result or "unknown"))
            end
        end

        -- If forceVertical failed, fall back to horizontal faces
        if forceVertical then
            local horizontalFaces = {}
            for _, face in ipairs(H_FACES) do
                table.insert(horizontalFaces, { axis = face.axis, dir = face.dir, name = face.name })
            end
            shuffle(horizontalFaces)

            for _, face in ipairs(horizontalFaces) do
                local newPos, result = tryAttachOnFace(self, parentRoom, dims, face)

                if newPos then
                    local room = {
                        id = roomId,
                        position = newPos,
                        dims = { dims[1], dims[2], dims[3] },
                        parentRoomId = parentRoomId,
                        attachFace = result,
                    }

                    state.placedRooms[roomId] = room
                    table.insert(state.roomsArray, room)

                    return room, nil
                else
                    table.insert(errors, face.name .. ": " .. (result or "unknown"))
                end
            end
        end

        return nil, "No valid face found. Tried: " .. table.concat(errors, ", ")
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "VolumeBuilder",
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

                if data.wallThickness then config.wallThickness = data.wallThickness end
                if data.doorSize then config.doorSize = data.doorSize end
                if data.verticalChance then config.verticalChance = data.verticalChance end
            end,

            onPlaceOrigin = function(self, data)
                if not data then return end

                local roomId = data.roomId
                local dims = data.dims
                local position = data.position or { 0, 0, 0 }

                if not roomId or not dims then
                    self.Out:Fire("failed", { roomId = roomId, reason = "Missing roomId or dims" })
                    return
                end

                local room = placeOriginRoom(self, roomId, dims, position)

                self.Out:Fire("placed", {
                    roomId = room.id,
                    position = room.position,
                    dims = room.dims,
                    parentRoomId = room.parentRoomId,
                    attachFace = room.attachFace,
                })
            end,

            onPlaceRoom = function(self, data)
                if not data then return end

                local roomId = data.roomId
                local dims = data.dims
                local parentRoomId = data.parentRoomId
                local forceVertical = data.forceVertical or false

                if not roomId or not dims or not parentRoomId then
                    self.Out:Fire("failed", {
                        roomId = roomId,
                        reason = "Missing roomId, dims, or parentRoomId"
                    })
                    return
                end

                local room, err = placeAttachedRoom(self, roomId, dims, parentRoomId, forceVertical)

                if room then
                    self.Out:Fire("placed", {
                        roomId = room.id,
                        position = room.position,
                        dims = room.dims,
                        parentRoomId = room.parentRoomId,
                        attachFace = room.attachFace,
                    })
                else
                    self.Out:Fire("failed", { roomId = roomId, reason = err })
                end
            end,

            onClear = function(self)
                local state = getState(self)
                state.placedRooms = {}
                state.roomsArray = {}
            end,
        },

        Out = {
            placed = {},
            failed = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getRoom = function(self, roomId)
            return getState(self).placedRooms[roomId]
        end,

        getAllRooms = function(self)
            return getState(self).roomsArray
        end,

        getRoomCount = function(self)
            return #getState(self).roomsArray
        end,

        -- Exported for reference
        FACES = FACES,
        H_FACES = H_FACES,
        V_FACES = V_FACES,
    }
end)

return VolumeBuilder
