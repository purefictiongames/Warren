--[[
    LibPureFiction Framework v2
    ShellBuilder.lua - Room Shell Construction

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    ShellBuilder constructs wall geometry around a volume. It receives
    interior dimensions and position, then creates 6 wall slabs plus an
    interior zone part.

    Used by DungeonOrchestrator in the sequential build pipeline:
    VolumeBuilder -> ShellBuilder -> DoorCutter -> next room

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
        onConfigure({ wallThickness, material, color, container })
        onBuildShell({ roomId, position, dims })
        onClear({})

    OUT (emits):
        shellComplete({ roomId, container, zonePart, walls })

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- SHELL BUILDER NODE
--------------------------------------------------------------------------------

local ShellBuilder = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    wallThickness = nil,  -- Required: set by orchestrator
                    material = Enum.Material.Brick,  -- Default, can be overridden
                    color = Color3.fromRGB(120, 90, 70),  -- Default, can be overridden
                    zoneColor = Color3.fromRGB(100, 150, 200),
                },
                container = nil,
                shells = {},  -- { [roomId] = { container, zonePart, walls } }
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- WALL SLAB CONSTRUCTION (from Room.lua)
    ----------------------------------------------------------------------------

    --[[
        Build 6 wall slabs around the interior volume.
        Simple box parts with clean collision - no CSG artifacts.
    --]]
    local function buildWalls(self, roomId, interiorSize, position, roomContainer)
        local state = getState(self)
        local config = state.config
        local thickness = config.wallThickness
        local walls = {}

        -- Convert position array to Vector3 if needed
        local posVec = Vector3.new(position[1], position[2], position[3])
        local sizeVec = Vector3.new(interiorSize[1], interiorSize[2], interiorSize[3])

        -- Wall definitions: { name, size, offset from center }
        local wallDefs = {
            -- Floor (-Y)
            {
                name = "Floor",
                size = Vector3.new(
                    sizeVec.X + thickness * 2,
                    thickness,
                    sizeVec.Z + thickness * 2
                ),
                offset = Vector3.new(0, -(sizeVec.Y + thickness) / 2, 0),
            },
            -- Ceiling (+Y)
            {
                name = "Ceiling",
                size = Vector3.new(
                    sizeVec.X + thickness * 2,
                    thickness,
                    sizeVec.Z + thickness * 2
                ),
                offset = Vector3.new(0, (sizeVec.Y + thickness) / 2, 0),
            },
            -- North wall (+Z)
            {
                name = "North",
                size = Vector3.new(
                    sizeVec.X + thickness * 2,
                    sizeVec.Y,
                    thickness
                ),
                offset = Vector3.new(0, 0, (sizeVec.Z + thickness) / 2),
            },
            -- South wall (-Z)
            {
                name = "South",
                size = Vector3.new(
                    sizeVec.X + thickness * 2,
                    sizeVec.Y,
                    thickness
                ),
                offset = Vector3.new(0, 0, -(sizeVec.Z + thickness) / 2),
            },
            -- East wall (+X)
            {
                name = "East",
                size = Vector3.new(
                    thickness,
                    sizeVec.Y,
                    sizeVec.Z
                ),
                offset = Vector3.new((sizeVec.X + thickness) / 2, 0, 0),
            },
            -- West wall (-X)
            {
                name = "West",
                size = Vector3.new(
                    thickness,
                    sizeVec.Y,
                    sizeVec.Z
                ),
                offset = Vector3.new(-(sizeVec.X + thickness) / 2, 0, 0),
            },
        }

        for _, def in ipairs(wallDefs) do
            local wall = Instance.new("Part")
            wall.Name = def.name
            wall.Size = def.size
            wall.Position = posVec + def.offset
            wall.Anchored = true
            wall.CanCollide = true
            wall.Material = config.material
            wall.Color = config.color
            wall.Parent = roomContainer

            walls[def.name] = wall
        end

        return walls
    end

    --[[
        Build a complete shell: container, zone part, and walls.
    --]]
    local function buildShell(self, roomId, position, dims)
        local state = getState(self)
        local config = state.config

        -- Convert arrays to Vector3
        local posVec = Vector3.new(position[1], position[2], position[3])
        local sizeVec = Vector3.new(dims[1], dims[2], dims[3])

        -- Create container Model
        local roomContainer = Instance.new("Model")
        roomContainer.Name = "Room_" .. tostring(roomId)

        -- Create zone Part (the interior detection volume)
        local zonePart = Instance.new("Part")
        zonePart.Name = "Zone"
        zonePart.Size = sizeVec
        zonePart.Position = posVec
        zonePart.Anchored = true
        zonePart.CanCollide = false
        zonePart.CanTouch = true
        zonePart.Transparency = 1  -- Invisible
        zonePart.Material = Enum.Material.ForceField
        zonePart.Color = config.zoneColor
        zonePart.Parent = roomContainer

        -- Build wall slabs around the interior
        local walls = buildWalls(self, roomId, dims, position, roomContainer)

        -- Set PrimaryPart for the container
        roomContainer.PrimaryPart = zonePart

        -- Parent to main container
        if state.container then
            roomContainer.Parent = state.container
        end

        -- Store shell data
        local shellData = {
            container = roomContainer,
            zonePart = zonePart,
            walls = walls,
        }
        state.shells[roomId] = shellData

        return shellData
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "ShellBuilder",
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
                if data.material then config.material = data.material end
                if data.color then config.color = data.color end
                if data.zoneColor then config.zoneColor = data.zoneColor end

                if data.container then
                    state.container = data.container
                end
            end,

            onBuildShell = function(self, data)
                if not data then return end

                local roomId = data.roomId
                local position = data.position
                local dims = data.dims

                if not roomId or not position or not dims then
                    warn("[ShellBuilder] Missing roomId, position, or dims")
                    return
                end

                local shellData = buildShell(self, roomId, position, dims)

                self.Out:Fire("shellComplete", {
                    roomId = roomId,
                    container = shellData.container,
                    zonePart = shellData.zonePart,
                    walls = shellData.walls,
                })
            end,

            onClear = function(self)
                local state = getState(self)

                -- Destroy all shell containers
                for _, shell in pairs(state.shells) do
                    if shell.container then
                        shell.container:Destroy()
                    end
                end

                state.shells = {}
            end,
        },

        Out = {
            shellComplete = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getShell = function(self, roomId)
            return getState(self).shells[roomId]
        end,

        getAllShells = function(self)
            return getState(self).shells
        end,

        getWall = function(self, roomId, wallName)
            local shell = getState(self).shells[roomId]
            if shell and shell.walls then
                return shell.walls[wallName]
            end
            return nil
        end,

        getContainer = function(self)
            return getState(self).container
        end,
    }
end)

return ShellBuilder
