--[[
    LibPureFiction Framework v2
    TrussBuilder.lua - Climbing Truss Placement

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TrussBuilder places climbing trusses at doorways where needed. It analyzes
    each doorway after it's cut and determines if a truss is required based on:

    - Wall doors (horizontal): If floor height difference > threshold (5 studs)
      -> Place truss centered on door, extending to bottom of doorway

    - Ceiling/floor holes (vertical): Always need a truss
      -> Place truss inside the hole (against left edge), extending floor to floor

    Used by DungeonOrchestrator in the sequential build pipeline:
    VolumeBuilder -> ShellBuilder -> DoorCutter -> TrussBuilder -> next room

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ wallThickness, container, floorThreshold })
        onCheckDoorway({ doorway, roomA, roomB })
        onClear({})

    OUT (emits):
        trussPlaced({ fromRoomId, toRoomId, position, height })
        trussNotNeeded({ fromRoomId, toRoomId, reason })

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- TRUSS BUILDER NODE
--------------------------------------------------------------------------------

local TrussBuilder = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    wallThickness = nil,      -- Required: set by orchestrator
                    floorThreshold = 5,       -- Height diff before truss needed (studs)
                    trussWidth = 2,           -- Width of truss part
                    trussDepth = 1,           -- Depth of truss part
                },
                container = nil,
                trusses = {},  -- Track placed trusses
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- GEOMETRY UTILITIES
    ----------------------------------------------------------------------------

    -- Calculate floor level (bottom of interior) for a room
    local function getFloorLevel(roomPos, roomDims)
        return roomPos[2] - roomDims[2] / 2
    end

    -- Calculate ceiling level (top of interior) for a room
    local function getCeilingLevel(roomPos, roomDims)
        return roomPos[2] + roomDims[2] / 2
    end

    ----------------------------------------------------------------------------
    -- TRUSS PLACEMENT
    ----------------------------------------------------------------------------

    local function placeTruss(self, position, height, fromRoomId, toRoomId)
        local state = getState(self)
        local config = state.config

        -- Create the truss part
        local truss = Instance.new("TrussPart")
        truss.Name = "Truss_" .. tostring(fromRoomId) .. "_" .. tostring(toRoomId)
        truss.Size = Vector3.new(config.trussWidth, height, config.trussDepth)
        truss.Position = Vector3.new(position[1], position[2], position[3])
        truss.Anchored = true
        truss.CanCollide = true
        truss.Material = Enum.Material.DiamondPlate
        truss.Color = Color3.fromRGB(80, 80, 80)

        if state.container then
            truss.Parent = state.container
        end

        local trussData = {
            part = truss,
            fromRoomId = fromRoomId,
            toRoomId = toRoomId,
            position = position,
            height = height,
        }
        table.insert(state.trusses, trussData)

        return trussData
    end

    local function checkHorizontalDoorway(self, doorway, roomA, roomB)
        local state = getState(self)
        local config = state.config

        -- Calculate floor levels for both rooms
        local floorA = getFloorLevel(roomA.position, roomA.dims)
        local floorB = getFloorLevel(roomB.position, roomB.dims)

        local heightDiff = math.abs(floorA - floorB)

        -- Check if truss is needed
        if heightDiff <= config.floorThreshold then
            return nil, "Floor difference (" .. string.format("%.1f", heightDiff) ..
                       ") <= threshold (" .. config.floorThreshold .. ")"
        end

        -- Determine which room is lower
        local lowerRoom = floorA < floorB and roomA or roomB
        local lowerFloor = math.min(floorA, floorB)
        local doorBottom = doorway.center[2] - doorway.height / 2

        -- Truss spans from lower floor to bottom of doorway
        local trussHeight = doorBottom - lowerFloor

        -- Position truss at door center X/Z, vertically centered
        local trussPos = {
            doorway.center[1],
            lowerFloor + trussHeight / 2,
            doorway.center[3],
        }

        -- Inset truss to mount on interior wall surface of the lower room
        -- Offset along doorway axis toward the lower room
        local axis = doorway.axis
        local dirToLower = lowerRoom.position[axis] > doorway.center[axis] and 1 or -1
        local wallThickness = config.wallThickness or 1
        trussPos[axis] = doorway.center[axis] + dirToLower * (wallThickness / 2 + config.trussDepth / 2)

        return placeTruss(self, trussPos, trussHeight, roomA.id, roomB.id)
    end

    local function checkVerticalDoorway(self, doorway, roomA, roomB)
        local state = getState(self)
        local config = state.config

        -- Vertical doorways always need a truss
        -- Determine which room is upper and which is lower
        local upperRoom, lowerRoom
        if roomA.position[2] > roomB.position[2] then
            upperRoom = roomA
            lowerRoom = roomB
        else
            upperRoom = roomB
            lowerRoom = roomA
        end

        -- Calculate truss span: from lower room floor to upper room floor
        local lowerFloor = getFloorLevel(lowerRoom.position, lowerRoom.dims)
        local upperFloor = getFloorLevel(upperRoom.position, upperRoom.dims)
        local trussHeight = upperFloor - lowerFloor

        -- Position truss inside the hole (against left edge)
        -- This avoids collision with the hole lip when climbing
        local trussPos = {
            doorway.center[1],
            doorway.center[2],
            doorway.center[3],
        }

        -- Offset to inside left edge of hole (inward, not outward)
        local offsetAmount = doorway.width / 2 - config.trussWidth / 2 - 0.5  -- Inside with small margin

        if doorway.widthAxis == 1 then
            -- Width is along X, so "left" inside is toward -X edge
            trussPos[1] = doorway.center[1] - offsetAmount
            trussPos[3] = doorway.center[3]
        else
            -- Width is along Z, so "left" inside is toward -Z edge
            trussPos[1] = doorway.center[1]
            trussPos[3] = doorway.center[3] - offsetAmount
        end

        -- Vertically center the truss between floors
        trussPos[2] = lowerFloor + trussHeight / 2

        return placeTruss(self, trussPos, trussHeight, lowerRoom.id, upperRoom.id)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "TrussBuilder",
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
                if data.floorThreshold then config.floorThreshold = data.floorThreshold end
                if data.trussWidth then config.trussWidth = data.trussWidth end
                if data.trussDepth then config.trussDepth = data.trussDepth end

                if data.container then
                    state.container = data.container
                end
            end,

            onCheckDoorway = function(self, data)
                if not data then return end

                local doorway = data.doorway
                local roomA = data.roomA
                local roomB = data.roomB

                if not doorway or not roomA or not roomB then
                    self.Out:Fire("trussNotNeeded", {
                        fromRoomId = roomA and roomA.id,
                        toRoomId = roomB and roomB.id,
                        reason = "Missing doorway or room data",
                    })
                    return
                end

                local trussData, reason

                -- Check if this is a vertical doorway (axis 2 = Y)
                if doorway.axis == 2 then
                    trussData, reason = checkVerticalDoorway(self, doorway, roomA, roomB)
                else
                    -- Horizontal doorway (axis 1 = X, axis 3 = Z)
                    trussData, reason = checkHorizontalDoorway(self, doorway, roomA, roomB)
                end

                if trussData then
                    self.Out:Fire("trussPlaced", {
                        fromRoomId = trussData.fromRoomId,
                        toRoomId = trussData.toRoomId,
                        position = trussData.position,
                        height = trussData.height,
                    })
                else
                    self.Out:Fire("trussNotNeeded", {
                        fromRoomId = roomA.id,
                        toRoomId = roomB.id,
                        reason = reason or "No truss needed",
                    })
                end
            end,

            onClear = function(self)
                local state = getState(self)

                -- Destroy all truss parts
                for _, truss in ipairs(state.trusses) do
                    if truss.part then
                        truss.part:Destroy()
                    end
                end

                state.trusses = {}
            end,
        },

        Out = {
            trussPlaced = {},
            trussNotNeeded = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getTrusses = function(self)
            return getState(self).trusses
        end,

        getTrussCount = function(self)
            return #getState(self).trusses
        end,
    }
end)

return TrussBuilder
