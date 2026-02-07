--[[
    Warren Framework v2
    Room.lua - Self-Contained Room Manager Node

    Copyright (c) 2025-2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Room is a self-contained node that wraps a blocking volume and converts it
    into a proper room with walls, floor, ceiling, and zone detection.

    A Room:
    - Takes an existing Part (blocking volume) that defines INTERIOR space
    - Creates 6 wall slabs around it (floor, ceiling, N/S/E/W walls)
    - Interior volume becomes zone detector (CanCollide=false, CanTouch=true)
    - Tracks what enters/exits via an internal Zone node
    - Provides mounting helpers for placing objects on interior walls

    Slab-Based Approach (2026-02-01 - reverted from CSG):
    - CSG shells created collision artifacts (invisible wedges at corners)
    - Simple box slabs have clean, predictable collision
    - 6 wall parts + 1 zone part = 7 parts total
    - Door cutting just removes/splits the appropriate wall slab

    Wall Layout:
        +Y = Ceiling
        -Y = Floor
        +Z = North wall
        -Z = South wall
        +X = East wall
        -X = West wall

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ part, wallThickness?, material?, color? })
            - part: The blocking volume Part (defines interior dimensions)
            - wallThickness: Thickness of walls (default 1)
            - material: Material for walls (default Brick)
            - color: Color for walls (default warm brown)

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
                    material = Enum.Material.Brick,
                    color = Color3.fromRGB(120, 90, 70),
                    zoneColor = Color3.fromRGB(100, 150, 200),
                },
                sourcePart = nil,
                container = nil,
                zonePart = nil,
                walls = {},  -- { Floor, Ceiling, North, South, East, West }
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
    -- WALL SLAB CONSTRUCTION
    ----------------------------------------------------------------------------

    --[[
        Build 6 wall slabs around the interior volume.
        Simple box parts with clean collision - no CSG artifacts.
    --]]
    local function buildWalls(self, interiorSize, position, thickness)
        local state = getState(self)
        local config = state.config
        local walls = {}

        -- Wall definitions: { name, size, offset from center }
        local wallDefs = {
            -- Floor (-Y)
            {
                name = "Floor",
                size = Vector3.new(
                    interiorSize.X + thickness * 2,
                    thickness,
                    interiorSize.Z + thickness * 2
                ),
                offset = Vector3.new(0, -(interiorSize.Y + thickness) / 2, 0),
            },
            -- Ceiling (+Y)
            {
                name = "Ceiling",
                size = Vector3.new(
                    interiorSize.X + thickness * 2,
                    thickness,
                    interiorSize.Z + thickness * 2
                ),
                offset = Vector3.new(0, (interiorSize.Y + thickness) / 2, 0),
            },
            -- North wall (+Z)
            {
                name = "North",
                size = Vector3.new(
                    interiorSize.X + thickness * 2,
                    interiorSize.Y,
                    thickness
                ),
                offset = Vector3.new(0, 0, (interiorSize.Z + thickness) / 2),
            },
            -- South wall (-Z)
            {
                name = "South",
                size = Vector3.new(
                    interiorSize.X + thickness * 2,
                    interiorSize.Y,
                    thickness
                ),
                offset = Vector3.new(0, 0, -(interiorSize.Z + thickness) / 2),
            },
            -- East wall (+X)
            {
                name = "East",
                size = Vector3.new(
                    thickness,
                    interiorSize.Y,
                    interiorSize.Z
                ),
                offset = Vector3.new((interiorSize.X + thickness) / 2, 0, 0),
            },
            -- West wall (-X)
            {
                name = "West",
                size = Vector3.new(
                    thickness,
                    interiorSize.Y,
                    interiorSize.Z
                ),
                offset = Vector3.new(-(interiorSize.X + thickness) / 2, 0, 0),
            },
        }

        for _, def in ipairs(wallDefs) do
            local wall = Instance.new("Part")
            wall.Name = def.name
            wall.Size = def.size
            wall.Position = position + def.offset
            wall.Anchored = true
            wall.CanCollide = true
            wall.Material = config.material
            wall.Color = config.color
            wall.Parent = state.container

            walls[def.name] = wall
        end

        state.walls = walls
        return walls
    end

    ----------------------------------------------------------------------------
    -- ROOM CONSTRUCTION
    ----------------------------------------------------------------------------

    --[[
        Convert a blocking volume into a room with wall slabs and zone detection.
        The source part defines the INTERIOR dimensions.
    --]]
    local function buildRoom(self, sourcePart)
        local state = getState(self)
        local config = state.config
        local thickness = config.wallThickness

        -- Store reference
        state.sourcePart = sourcePart

        -- Get original dimensions and position
        local interiorSize = sourcePart.Size
        local interiorPos = sourcePart.Position

        -- Validate minimum size
        if interiorSize.X <= 0 or interiorSize.Y <= 0 or interiorSize.Z <= 0 then
            self.Err:Fire({
                reason = "room_too_small",
                message = "Source part has invalid dimensions",
                roomId = self.id,
                originalSize = interiorSize,
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
        zonePart.Size = interiorSize
        zonePart.Position = interiorPos
        zonePart.Anchored = true
        zonePart.CanCollide = false
        zonePart.CanTouch = true
        zonePart.Transparency = 1  -- Invisible
        zonePart.Material = Enum.Material.ForceField
        zonePart.Color = config.zoneColor
        zonePart.Parent = container
        state.zonePart = zonePart

        -- Build wall slabs around the interior
        buildWalls(self, interiorSize, interiorPos, thickness)

        -- Parent container to same parent as source
        container.Parent = sourcePart.Parent

        -- Remove the source part (it was just a placeholder)
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
            return getState(self).zonePart
        end,

        getContainer = function(self)
            return getState(self).container
        end,

        getWalls = function(self)
            return getState(self).walls
        end,

        getWall = function(self, name)
            return getState(self).walls[name]
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
            return getState(self).orchestrator
        end,

        ------------------------------------------------------------------------
        -- MOUNTING HELPERS
        ------------------------------------------------------------------------

        --[[
            Get the CFrame for a specific interior wall face.
            face: "N" (+Z), "S" (-Z), "E" (+X), "W" (-X), "U" (+Y ceiling), "D" (-Y floor)

            Returns the CFrame at the center of that interior face.
            The CFrame's lookVector points INTO the room (away from wall).
        --]]
        getWallCFrame = function(self, face)
            local state = getState(self)
            if not state.zonePart then return nil end

            local zone = state.zonePart
            local size = zone.Size
            local cf = zone.CFrame

            if face == "N" then
                return cf * CFrame.new(0, 0, size.Z / 2) * CFrame.Angles(0, math.pi, 0)
            elseif face == "S" then
                return cf * CFrame.new(0, 0, -size.Z / 2)
            elseif face == "E" then
                return cf * CFrame.new(size.X / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
            elseif face == "W" then
                return cf * CFrame.new(-size.X / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
            elseif face == "U" then
                return cf * CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(math.pi / 2, 0, 0)
            elseif face == "D" then
                return cf * CFrame.new(0, -size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
            end

            return nil
        end,

        --[[
            Get the size of a specific interior wall face.
            face: "N", "S", "E", "W", "U", "D"

            Returns Vector2 (width, height) from viewer's perspective.
        --]]
        getWallSize = function(self, face)
            local state = getState(self)
            if not state.zonePart then return nil end

            local size = state.zonePart.Size

            if face == "N" or face == "S" then
                return Vector2.new(size.X, size.Y)
            elseif face == "E" or face == "W" then
                return Vector2.new(size.Z, size.Y)
            elseif face == "U" or face == "D" then
                return Vector2.new(size.X, size.Z)
            end

            return nil
        end,

        --[[
            Mount an object to an interior wall face.
            face: "N", "S", "E", "W", "U", "D"
            offset: Vector3 offset from wall center
            object: The Part or Model to mount
        --]]
        mountToWall = function(self, face, offset, object)
            local wallCF = self:getWallCFrame(face)
            if not wallCF then return false end

            offset = offset or Vector3.new(0, 0, 0)
            local mountCF = wallCF * CFrame.new(offset.X, offset.Y, offset.Z)

            if object:IsA("Model") then
                if object.PrimaryPart then
                    object:SetPrimaryPartCFrame(mountCF)
                else
                    object:MoveTo(mountCF.Position)
                end
            elseif object:IsA("BasePart") then
                object.CFrame = mountCF
            end

            return true
        end,
    }
end)

return Room
