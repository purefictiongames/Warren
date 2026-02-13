--[[
    LibPureFiction Framework v2
    TeleportPadBuilder.lua - Teleport Pad Placement

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TeleportPadBuilder places teleport pads in rooms during dungeon generation.
    Pads are glowing neon purple and trigger region teleportation when touched.

    Placement rules:
    - Minimum 1 pad per region
    - Additional pad per every N rooms (configurable, default 25)
    - Pads placed on floor, centered in room
    - Avoids room 1 (spawn room)

    Used by DungeonOrchestrator in the sequential build pipeline.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ container, roomsPerPad, padColor })
        onPlacePad({ roomId, position, dims, container })
        onClear({})

    OUT (emits):
        padPlaced({ roomId, padId, position })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- TELEPORT PAD BUILDER NODE
--------------------------------------------------------------------------------

local TeleportPadBuilder = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    roomsPerPad = 25,  -- Additional pad every N rooms
                    padSize = Vector3.new(6, 1, 6),
                    padColor = Color3.fromRGB(180, 50, 255),  -- Neon purple
                },
                container = nil,
                pads = {},  -- { padId = { part, roomId, position, linkedTo } }
                padCount = 0,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- PAD PLACEMENT
    ----------------------------------------------------------------------------

    local function createPad(self, roomId, position, dims, roomContainer)
        local state = getState(self)
        local config = state.config

        state.padCount = state.padCount + 1
        local padId = "pad_" .. state.padCount

        -- Position on floor, centered
        local floorY = position[2] - dims[2] / 2
        local padPos = Vector3.new(
            position[1],
            floorY + config.padSize.Y / 2 + 0.1,  -- Slightly above floor
            position[3]
        )

        -- Create pad part
        local pad = Instance.new("Part")
        pad.Name = padId
        pad.Size = config.padSize
        pad.Position = padPos
        pad.Anchored = true
        pad.CanCollide = true
        pad.Material = Enum.Material.Neon
        pad.Color = config.padColor

        -- Add identifier attribute
        pad:SetAttribute("TeleportPad", true)
        pad:SetAttribute("PadId", padId)
        pad:SetAttribute("RoomId", roomId)

        -- Parent to room container or main container
        if roomContainer then
            pad.Parent = roomContainer
        elseif state.container then
            pad.Parent = state.container
        else
            pad.Parent = workspace
        end

        -- Store pad data
        local padData = {
            part = pad,
            padId = padId,
            roomId = roomId,
            position = { padPos.X, padPos.Y, padPos.Z },
            linkedTo = nil,  -- Set by RegionManager when linked
        }
        state.pads[padId] = padData

        return padData
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "TeleportPadBuilder",
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

                if data.roomsPerPad then config.roomsPerPad = data.roomsPerPad end
                if data.padSize then config.padSize = data.padSize end
                if data.padColor then config.padColor = data.padColor end

                if data.container then
                    state.container = data.container
                end
            end,

            onPlacePad = function(self, data)
                if not data then return end

                local roomId = data.roomId
                local position = data.position
                local dims = data.dims
                local roomContainer = data.container

                if not roomId or not position or not dims then
                    warn("[TeleportPadBuilder] Missing roomId, position, or dims")
                    return
                end

                local padData = createPad(self, roomId, position, dims, roomContainer)

                self.Out:Fire("padPlaced", {
                    roomId = roomId,
                    padId = padData.padId,
                    position = padData.position,
                })
            end,

            onClear = function(self)
                local state = getState(self)

                -- Destroy all pads
                for _, pad in pairs(state.pads) do
                    if pad.part then
                        pad.part:Destroy()
                    end
                end

                state.pads = {}
                state.padCount = 0
            end,
        },

        Out = {
            padPlaced = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getPads = function(self)
            return getState(self).pads
        end,

        getPad = function(self, padId)
            return getState(self).pads[padId]
        end,

        getPadCount = function(self)
            return getState(self).padCount
        end,

        -- Set link data for a pad
        setPadLink = function(self, padId, targetRegionId, targetPadId)
            local state = getState(self)
            local pad = state.pads[padId]
            if pad then
                pad.linkedTo = {
                    regionId = targetRegionId,
                    padId = targetPadId,
                }
                -- Update attribute on part
                if pad.part then
                    pad.part:SetAttribute("LinkedRegion", targetRegionId)
                    pad.part:SetAttribute("LinkedPad", targetPadId)
                end
            end
        end,
    }
end)

return TeleportPadBuilder
