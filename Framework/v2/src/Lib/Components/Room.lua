--[[
    LibPureFiction Framework v2
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
    - Creates a CSG hollow shell around it (outer - inner = walls)
    - Interior volume becomes zone detector (CanCollide=false, CanTouch=true)
    - Tracks what enters/exits via an internal Zone node
    - Provides mounting helpers for placing objects on interior walls

    CSG Shell Approach (2026-02-01 refactor):
    - Previously: 6 separate wall slabs (7 parts total)
    - Now: 1 CSG shell + 1 zone part (2 parts total)
    - Benefits: Fewer parts, simpler doorway cutting, cleaner geometry
    - Interior volume serves dual purpose: zone detection + mounting reference

    Mounting Reference:
    The zone part's faces correspond to interior wall surfaces:
        +Z face = North wall interior
        -Z face = South wall interior
        +X face = East wall interior
        -X face = West wall interior
        +Y face = Ceiling interior
        -Y face = Floor interior

    Rooms don't know or care about their place in a larger map. They only
    manage what happens within their 6 sides.

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
                shell = nil,  -- CSG shell (replaces slabs)
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
    -- CSG SHELL CONSTRUCTION
    ----------------------------------------------------------------------------

    --[[
        Build a hollow shell using CSG subtraction.

        New approach (CSG Shell):
        - Inner volume = original room dims (this IS the interior)
        - Outer volume = inner + (wallThickness * 2) on each axis
        - Shell = Outer:SubtractAsync({Inner})

        Benefits:
        - 2 parts per room (shell + zone) vs 7 parts (6 slabs + zone)
        - Simpler doorway cutting (cut 1 shell vs 2+ slabs)
        - Inner volume serves dual purpose: zone detector + mounting reference
    --]]
    local function buildShell(self, innerSize, position, thickness)
        local state = getState(self)
        local config = state.config

        -- Create outer volume (shell boundary)
        local outerSize = Vector3.new(
            innerSize.X + thickness * 2,
            innerSize.Y + thickness * 2,
            innerSize.Z + thickness * 2
        )

        -- CRITICAL: Parts must be parented to workspace for SubtractAsync to work
        -- Cannot parent to container that isn't in DataModel yet
        local outerPart = Instance.new("Part")
        outerPart.Name = "Outer_Temp"
        outerPart.Size = outerSize
        outerPart.Position = position
        outerPart.Anchored = true
        outerPart.CanCollide = true
        outerPart.Material = config.material
        outerPart.Color = config.color
        outerPart.Parent = workspace  -- Must be in DataModel for CSG

        -- Create inner volume (to subtract)
        local innerPart = Instance.new("Part")
        innerPart.Name = "Inner_Temp"
        innerPart.Size = innerSize
        innerPart.Position = position
        innerPart.Anchored = true
        innerPart.Parent = workspace  -- Must be in DataModel for CSG

        -- Perform CSG subtraction to create hollow shell
        local success, shell = pcall(function()
            return outerPart:SubtractAsync({ innerPart })
        end)

        -- Cleanup temp parts
        outerPart:Destroy()
        innerPart:Destroy()

        if not success or not shell then
            self.Err:Fire({
                reason = "csg_failed",
                message = "CSG SubtractAsync failed",
                roomId = self.id,
                error = tostring(shell),
            })
            return nil
        end

        -- Configure shell
        shell.Name = "Shell"
        shell.Anchored = true
        shell.CanCollide = true
        shell.Transparency = 0  -- Fully opaque
        shell.Material = config.material
        shell.Color = config.color
        shell.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
        shell.Parent = state.container

        state.shell = shell
        return shell
    end

    ----------------------------------------------------------------------------
    -- ROOM CONSTRUCTION
    ----------------------------------------------------------------------------

    --[[
        Convert a blocking volume into a room with CSG shell and zone detection.

        The source part defines the INTERIOR dimensions (not shrunk).
        Walls are built OUTSIDE the interior space.
    --]]
    local function buildRoom(self, sourcePart)
        local state = getState(self)
        local config = state.config
        local thickness = config.wallThickness

        -- Store reference
        state.sourcePart = sourcePart

        -- Get original dimensions and position
        -- These ARE the interior dimensions (no shrinking)
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
        -- This serves dual purpose:
        -- 1. Zone detector (CanCollide=false, CanTouch=true)
        -- 2. Mounting reference (CFrame math against real Part surfaces)
        local zonePart = Instance.new("Part")
        zonePart.Name = "Zone"
        zonePart.Size = interiorSize
        zonePart.Position = interiorPos
        zonePart.Anchored = true
        zonePart.CanCollide = false
        zonePart.CanTouch = true
        zonePart.Transparency = 1  -- Invisible but functional
        zonePart.Material = Enum.Material.ForceField
        zonePart.Color = config.zoneColor
        zonePart.Parent = container
        state.zonePart = zonePart

        -- Build the CSG shell around the interior
        local shell = buildShell(self, interiorSize, interiorPos, thickness)
        if not shell then
            container:Destroy()
            return false
        end

        -- Parent container to same parent as source
        container.Parent = sourcePart.Parent

        -- Remove the source part
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

        getShell = function(self)
            local state = getState(self)
            return state.shell
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
                -- North wall (+Z face) - lookVector points -Z (into room)
                return cf * CFrame.new(0, 0, size.Z / 2) * CFrame.Angles(0, math.pi, 0)
            elseif face == "S" then
                -- South wall (-Z face) - lookVector points +Z (into room)
                return cf * CFrame.new(0, 0, -size.Z / 2)
            elseif face == "E" then
                -- East wall (+X face) - lookVector points -X (into room)
                return cf * CFrame.new(size.X / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
            elseif face == "W" then
                -- West wall (-X face) - lookVector points +X (into room)
                return cf * CFrame.new(-size.X / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
            elseif face == "U" then
                -- Ceiling (+Y face) - lookVector points -Y (into room)
                return cf * CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(math.pi / 2, 0, 0)
            elseif face == "D" then
                -- Floor (-Y face) - lookVector points +Y (into room)
                return cf * CFrame.new(0, -size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
            end

            return nil
        end,

        --[[
            Get the size of a specific interior wall face.
            face: "N", "S", "E", "W", "U", "D"

            Returns Vector2 (width, height) from viewer's perspective facing the wall.
        --]]
        getWallSize = function(self, face)
            local state = getState(self)
            if not state.zonePart then return nil end

            local size = state.zonePart.Size

            if face == "N" or face == "S" then
                -- Z-facing walls: width = X, height = Y
                return Vector2.new(size.X, size.Y)
            elseif face == "E" or face == "W" then
                -- X-facing walls: width = Z, height = Y
                return Vector2.new(size.Z, size.Y)
            elseif face == "U" or face == "D" then
                -- Y-facing walls (floor/ceiling): width = X, height = Z
                return Vector2.new(size.X, size.Z)
            end

            return nil
        end,

        --[[
            Mount an object to an interior wall face.
            face: "N", "S", "E", "W", "U", "D"
            offset: Vector3 offset from wall center (X = right, Y = up, Z = depth from wall)
            object: The Part or Model to mount

            The object will be positioned relative to the wall face,
            with Z offset moving away from the wall into the room.
        --]]
        mountToWall = function(self, face, offset, object)
            local wallCF = self:getWallCFrame(face)
            if not wallCF then return false end

            offset = offset or Vector3.new(0, 0, 0)

            -- Apply offset in wall-local space
            -- X = right along wall, Y = up along wall, Z = into room
            local mountCF = wallCF * CFrame.new(offset.X, offset.Y, offset.Z)

            if object:IsA("Model") then
                if object.PrimaryPart then
                    object:SetPrimaryPartCFrame(mountCF)
                else
                    -- Try to move model by its bounding box center
                    local _, size = object:GetBoundingBox()
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
