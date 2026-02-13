--[[
    LibPureFiction Framework v2
    LightBuilder.lua - Room Lighting Placement

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LightBuilder places lighting fixtures in rooms. It receives room geometry
    and creates a neon ceiling light with an attached PointLight for illumination.

    Used by DungeonOrchestrator in the sequential build pipeline:
    VolumeBuilder -> ShellBuilder -> DoorCutter -> TrussBuilder -> LightBuilder -> next room

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ container, brightness, lightColor })
        onAddLight({ roomId, position, dims, container })
        onClear({})

    OUT (emits):
        lightPlaced({ roomId, position })

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- LIGHT BUILDER NODE
--------------------------------------------------------------------------------

local LightBuilder = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    brightness = 0.5,
                    range = nil,  -- Auto-calculated from room size if nil
                    lightColor = Color3.fromRGB(255, 245, 230),
                    neonColor = Color3.fromRGB(200, 195, 180),  -- Dimmer neon
                    fixtureHeight = 0.5,
                },
                container = nil,
                lights = {},  -- Track placed lights
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- LIGHT PLACEMENT
    ----------------------------------------------------------------------------

    -- Wall definitions: face name -> position offset and size axes
    local WALLS = {
        N = { axis = 3, dir = 1,  sizeAxis = 1 },  -- +Z wall, strip along X
        S = { axis = 3, dir = -1, sizeAxis = 1 },  -- -Z wall, strip along X
        E = { axis = 1, dir = 1,  sizeAxis = 3 },  -- +X wall, strip along Z
        W = { axis = 1, dir = -1, sizeAxis = 3 },  -- -X wall, strip along Z
    }

    local WALL_ORDER = { "N", "S", "E", "W" }  -- Preference order

    local function placeLight(self, roomId, position, dims, roomContainer, doorFaces)
        local state = getState(self)
        local config = state.config
        doorFaces = doorFaces or {}

        -- Pick a wall without a door
        local chosenWall = nil
        for _, faceName in ipairs(WALL_ORDER) do
            if not doorFaces[faceName] then
                chosenWall = WALLS[faceName]
                chosenWall.name = faceName
                break
            end
        end

        -- Fallback to north if all walls have doors (shouldn't happen)
        if not chosenWall then
            chosenWall = WALLS.N
            chosenWall.name = "N"
        end

        -- Calculate strip size based on wall width
        local wallWidth = dims[chosenWall.sizeAxis]
        local stripWidth = wallWidth * 0.5
        stripWidth = math.clamp(stripWidth, 4, 12)

        -- Position near ceiling on chosen wall interior surface
        -- Place above door height (doors are ~12 studs) to avoid overlap with future doors
        local lightPos = {
            position[1],
            position[2] + dims[2] / 2 - 2,  -- Near ceiling, 2 studs down
            position[3],
        }
        lightPos[chosenWall.axis] = position[chosenWall.axis] +
            chosenWall.dir * (dims[chosenWall.axis] / 2 - 0.1)

        -- Create neon strip with correct orientation
        local sizeVec
        if chosenWall.sizeAxis == 1 then
            sizeVec = Vector3.new(stripWidth, 1, 0.3)
        else
            sizeVec = Vector3.new(0.3, 1, stripWidth)
        end

        local fixture = Instance.new("Part")
        fixture.Name = "LightStrip_" .. tostring(roomId)
        fixture.Size = sizeVec
        fixture.Position = Vector3.new(lightPos[1], lightPos[2], lightPos[3])
        fixture.Anchored = true
        fixture.CanCollide = false
        fixture.Material = Enum.Material.Neon
        fixture.Color = Color3.fromRGB(255, 250, 240)  -- Bright warm white

        -- Add PointLight for actual illumination
        local light = Instance.new("PointLight")
        light.Name = "Light"
        light.Brightness = 0.75
        light.Range = math.max(dims[1], dims[2], dims[3]) * 1.5
        light.Color = Color3.fromRGB(255, 245, 230)
        light.Shadows = false
        light.Parent = fixture

        -- Parent to room container if provided, otherwise main container
        if roomContainer then
            fixture.Parent = roomContainer
        elseif state.container then
            fixture.Parent = state.container
        else
            fixture.Parent = workspace
        end

        local lightData = {
            fixture = fixture,
            roomId = roomId,
            position = { lightPos.X, lightPos.Y, lightPos.Z },
        }
        table.insert(state.lights, lightData)

        return lightData
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "LightBuilder",
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

                if data.brightness then config.brightness = data.brightness end
                if data.range then config.range = data.range end
                if data.lightColor then config.lightColor = data.lightColor end
                if data.neonColor then config.neonColor = data.neonColor end
                if data.fixtureHeight then config.fixtureHeight = data.fixtureHeight end

                if data.container then
                    state.container = data.container
                end
            end,

            onAddLight = function(self, data)
                if not data then return end

                local roomId = data.roomId
                local position = data.position
                local dims = data.dims
                local roomContainer = data.container
                local doorFaces = data.doorFaces

                if not roomId or not position or not dims then
                    warn("[LightBuilder] Missing roomId, position, or dims")
                    return
                end

                local lightData = placeLight(self, roomId, position, dims, roomContainer, doorFaces)

                self.Out:Fire("lightPlaced", {
                    roomId = roomId,
                    position = lightData.position,
                })
            end,

            onClear = function(self)
                local state = getState(self)

                -- Destroy all light fixtures
                for _, light in ipairs(state.lights) do
                    if light.fixture then
                        light.fixture:Destroy()
                    end
                end

                state.lights = {}
            end,
        },

        Out = {
            lightPlaced = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getLights = function(self)
            return getState(self).lights
        end,

        getLightCount = function(self)
            return #getState(self).lights
        end,
    }
end)

return LightBuilder
