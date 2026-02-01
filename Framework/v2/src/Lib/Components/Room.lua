--[[
    LibPureFiction Framework v2
    Room.lua - Self-Contained Room Manager Node

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Room is a self-contained node that wraps a blocking volume and converts it
    into a proper room with walls, floor, ceiling, and zone detection.

    A Room:
    - Takes an existing Part (blocking volume)
    - Shrinks it to create interior space
    - Creates 1-stud thick slabs on all 6 sides
    - Converts the interior to a zone detector (CanCollide=false, CanTouch=true)
    - Tracks what enters/exits via an internal Zone node
    - Acts as an orchestrator for everything inside its bounds

    Rooms don't know or care about their place in a larger map. They only
    manage what happens within their 6 sides.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ part, wallThickness?, material?, color? })
            - part: The blocking volume Part to convert
            - wallThickness: Thickness of walls (default 1)
            - material: Material for walls (default SmoothPlastic)
            - color: Color for walls (default gray)

        onStart()
            - Enable zone detection

        onStop()
            - Disable and cleanup

    OUT (emits):
        entityEntered({ entity, entityId, nodeClass, assetId, position })
            - Proxied from internal Zone

        entityExited({ entity, entityId })
            - Proxied from internal Zone

        ready({ roomId, volume, bounds })
            - Fired when room is fully constructed

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- ROOM NODE
--------------------------------------------------------------------------------

local Room = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    wallThickness = 1,
                    material = Enum.Material.SmoothPlastic,
                    color = Color3.fromRGB(140, 140, 150),
                    zoneColor = Color3.fromRGB(100, 150, 200),
                },
                sourcePart = nil,
                container = nil,
                zonePart = nil,
                slabs = {},
                zone = nil,
                orchestrator = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- SLAB CREATION
    ----------------------------------------------------------------------------

    --[[
        Create a single slab on one face of the room.
        face: "N", "S", "E", "W", "U", "D"
    --]]
    local function createSlab(self, face, zoneSize, zonePos, thickness)
        local state = getState(self)
        local config = state.config

        local slab = Instance.new("Part")
        slab.Name = "Slab_" .. face
        slab.Anchored = true
        slab.CanCollide = true
        slab.Material = config.material
        slab.Color = config.color

        local sx, sy, sz = zoneSize.X, zoneSize.Y, zoneSize.Z
        local px, py, pz = zonePos.X, zonePos.Y, zonePos.Z

        if face == "N" then
            -- North wall (+Z)
            slab.Size = Vector3.new(sx + thickness * 2, sy + thickness * 2, thickness)
            slab.Position = Vector3.new(px, py, pz + sz / 2 + thickness / 2)
        elseif face == "S" then
            -- South wall (-Z)
            slab.Size = Vector3.new(sx + thickness * 2, sy + thickness * 2, thickness)
            slab.Position = Vector3.new(px, py, pz - sz / 2 - thickness / 2)
        elseif face == "E" then
            -- East wall (+X)
            slab.Size = Vector3.new(thickness, sy + thickness * 2, sz + thickness * 2)
            slab.Position = Vector3.new(px + sx / 2 + thickness / 2, py, pz)
        elseif face == "W" then
            -- West wall (-X)
            slab.Size = Vector3.new(thickness, sy + thickness * 2, sz + thickness * 2)
            slab.Position = Vector3.new(px - sx / 2 - thickness / 2, py, pz)
        elseif face == "U" then
            -- Ceiling (+Y)
            slab.Size = Vector3.new(sx, thickness, sz)
            slab.Position = Vector3.new(px, py + sy / 2 + thickness / 2, pz)
        elseif face == "D" then
            -- Floor (-Y)
            slab.Size = Vector3.new(sx, thickness, sz)
            slab.Position = Vector3.new(px, py - sy / 2 - thickness / 2, pz)
        end

        -- Make ceiling transparent so we can peek inside
        if face == "U" then
            slab.Transparency = 0.5
        end

        slab.Parent = state.container
        table.insert(state.slabs, slab)

        return slab
    end

    --[[
        Build all 6 slabs around the zone.
    --]]
    local function buildSlabs(self, zoneSize, zonePos, thickness)
        for _, face in ipairs({ "N", "S", "E", "W", "U", "D" }) do
            createSlab(self, face, zoneSize, zonePos, thickness)
        end
    end

    ----------------------------------------------------------------------------
    -- ROOM CONSTRUCTION
    ----------------------------------------------------------------------------

    --[[
        Convert a blocking volume into a room with walls and zone detection.
    --]]
    local function buildRoom(self, sourcePart)
        local state = getState(self)
        local config = state.config
        local thickness = config.wallThickness

        -- Store reference
        state.sourcePart = sourcePart

        -- Get original dimensions and position
        local originalSize = sourcePart.Size
        local originalPos = sourcePart.Position

        -- Calculate zone size (shrink by thickness on each side)
        local zoneSize = Vector3.new(
            originalSize.X - thickness * 2,
            originalSize.Y - thickness * 2,
            originalSize.Z - thickness * 2
        )

        -- Ensure zone isn't negative
        if zoneSize.X <= 0 or zoneSize.Y <= 0 or zoneSize.Z <= 0 then
            self.Err:Fire({
                reason = "room_too_small",
                message = "Source part too small for wall thickness",
                roomId = self.id,
                originalSize = originalSize,
                wallThickness = thickness,
            })
            return false
        end

        -- Create container Model
        local container = Instance.new("Model")
        container.Name = "Room_" .. self.id
        state.container = container

        -- Create zone Part (the interior detection volume)
        local zonePart = Instance.new("Part")
        zonePart.Name = "Zone"
        zonePart.Size = zoneSize
        zonePart.Position = originalPos
        zonePart.Anchored = true
        zonePart.CanCollide = false
        zonePart.CanTouch = true
        zonePart.Transparency = 0.8
        zonePart.Material = Enum.Material.ForceField
        zonePart.Color = config.zoneColor
        zonePart.Parent = container
        state.zonePart = zonePart

        -- Build the 6 slabs
        buildSlabs(self, zoneSize, originalPos, thickness)

        -- Parent container to same parent as source
        container.Parent = sourcePart.Parent

        -- Remove or hide the source part
        sourcePart:Destroy()

        -- Set PrimaryPart for the container
        container.PrimaryPart = zonePart

        -- Update self.model to point to container
        self.model = container

        return true
    end

    ----------------------------------------------------------------------------
    -- ZONE SETUP
    ----------------------------------------------------------------------------

    --[[
        Create and configure the internal Zone node.
    --]]
    local function setupZone(self)
        local state = getState(self)

        -- Get Zone component
        local Zone = require(script.Parent.Zone)

        -- Create Zone node
        local zone = Zone:new({
            id = self.id .. "_Zone",
            model = state.zonePart,
        })

        -- Initialize
        zone.Sys.onInit(zone)

        -- Wire Zone outputs to Room outputs
        local originalFire = zone.Out.Fire
        zone.Out.Fire = function(outSelf, signal, data)
            -- Proxy to Room's Out
            if signal == "entityEntered" or signal == "entityExited" then
                data.roomId = self.id
                self.Out:Fire(signal, data)
            end
            originalFire(outSelf, signal, data)
        end

        state.zone = zone

        return zone
    end

    --[[
        Create the internal Orchestrator stub.
        This is a placeholder that can be configured or replaced downstream.
    --]]
    local function setupOrchestrator(self)
        local state = getState(self)

        -- Get Orchestrator component
        local Orchestrator = require(script.Parent.Orchestrator)

        -- Create empty Orchestrator as stub
        local orchestrator = Orchestrator:new({
            id = self.id .. "_Orchestrator",
        })

        -- Initialize
        orchestrator.Sys.onInit(orchestrator)

        state.orchestrator = orchestrator

        return orchestrator
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "Room",
        domain = "server",

        Sys = {
            onInit = function(self)
                local _ = getState(self)
            end,

            onStart = function(self)
                local state = getState(self)
                if state.zone then
                    state.zone.In.onEnable(state.zone)
                end
            end,

            onStop = function(self)
                local state = getState(self)

                -- Stop zone
                if state.zone then
                    state.zone.Sys.onStop(state.zone)
                end

                -- Stop orchestrator
                if state.orchestrator then
                    state.orchestrator.Sys.onStop(state.orchestrator)
                end

                -- Cleanup geometry
                if state.container then
                    state.container:Destroy()
                end

                cleanupState(self)
            end,
        },

        In = {
            --[[
                Configure and build the room from a source Part.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)
                local config = state.config

                -- Apply config options
                if data.wallThickness then
                    config.wallThickness = data.wallThickness
                end
                if data.material then
                    config.material = data.material
                end
                if data.color then
                    config.color = data.color
                end
                if data.zoneColor then
                    config.zoneColor = data.zoneColor
                end

                -- Build room if part provided
                if data.part then
                    local success = buildRoom(self, data.part)
                    if success then
                        setupZone(self)
                        setupOrchestrator(self)

                        -- Fire ready signal
                        local zonePart = state.zonePart
                        self.Out:Fire("ready", {
                            roomId = self.id,
                            volume = zonePart.Size.X * zonePart.Size.Y * zonePart.Size.Z,
                            bounds = {
                                size = { zonePart.Size.X, zonePart.Size.Y, zonePart.Size.Z },
                                position = { zonePart.Position.X, zonePart.Position.Y, zonePart.Position.Z },
                            },
                        })
                    end
                end
            end,

            --[[
                Configure zone filtering.
            --]]
            onConfigureZone = function(self, data)
                local state = getState(self)
                if state.zone then
                    state.zone.In.onConfigure(state.zone, data)
                end
            end,

            --[[
                Configure the internal orchestrator.
            --]]
            onConfigureOrchestrator = function(self, data)
                local state = getState(self)
                if state.orchestrator then
                    state.orchestrator.In.onConfigure(state.orchestrator, data)
                end
            end,

            --[[
                Enable zone detection.
            --]]
            onEnable = function(self)
                local state = getState(self)
                if state.zone then
                    state.zone.In.onEnable(state.zone)
                end
            end,

            --[[
                Disable zone detection.
            --]]
            onDisable = function(self)
                local state = getState(self)
                if state.zone then
                    state.zone.In.onDisable(state.zone)
                end
            end,
        },

        Out = {
            entityEntered = {},
            entityExited = {},
            ready = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getZonePart = function(self)
            local state = getState(self)
            return state.zonePart
        end,

        getContainer = function(self)
            local state = getState(self)
            return state.container
        end,

        getSlabs = function(self)
            local state = getState(self)
            return state.slabs
        end,

        getBounds = function(self)
            local state = getState(self)
            if state.zonePart then
                return {
                    size = state.zonePart.Size,
                    position = state.zonePart.Position,
                }
            end
            return nil
        end,

        getVolume = function(self)
            local state = getState(self)
            if state.zonePart then
                local s = state.zonePart.Size
                return s.X * s.Y * s.Z
            end
            return 0
        end,

        getOrchestrator = function(self)
            local state = getState(self)
            return state.orchestrator
        end,
    }
end)

return Room
