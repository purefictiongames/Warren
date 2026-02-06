--[[
    LibPureFiction Framework v2
    TitleDiorama.lua - Title Screen 3D Background

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TitleDiorama creates a small 3D scene for the title screen background
    using the same Layout pipeline as RegionManager. This ensures visual
    consistency between the title screen and gameplay.

    We only define room volumes and connections - the pipeline calculates
    doors, trusses, lights, and pads automatically.

    Layout:
    - Center hub room with ceiling port and truss leading up
    - Upper room connected via the truss
    - One horizontal connecting room (north)

--]]

local RunService = game:GetService("RunService")

local LayoutBuilder = require(script.Parent.Layout.LayoutBuilder)
local LayoutInstantiator = require(script.Parent.Layout.LayoutInstantiator)

local TitleDiorama = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Room dimensions (interior)
local HUB_SIZE = { 40, 24, 40 }        -- Main viewing room
local SIDE_ROOM_SIZE = { 30, 20, 24 }  -- Horizontal room (north)
local UPPER_ROOM_SIZE = { 24, 16, 24 } -- Room above hub

-- Layout configuration
local WALL_THICKNESS = 1

-- Camera settings
local CAMERA_HEIGHT = 8  -- Eye level
local ROTATION_SPEED = 0.05  -- Radians per second (slow rotation)

--------------------------------------------------------------------------------
-- LAYOUT CREATION
--------------------------------------------------------------------------------

--[[
    Creates a predefined layout for the title screen diorama.
    We only define room volumes and connections - the pipeline fills in:
    - Door positions and dimensions
    - Truss placement for vertical connections
    - Light placement in each room
    - Pad (portal) placement on floors
--]]
local function createDioramaLayout()
    -- Calculate room positions
    -- Hub room centered at origin, floor at Y=0
    local hubCenter = { 0, HUB_SIZE[2] / 2, 0 }

    -- Side room north of hub (shares floor level)
    local sideZ = HUB_SIZE[3] / 2 + SIDE_ROOM_SIZE[3] / 2 + WALL_THICKNESS * 2
    local sideCenter = { 0, SIDE_ROOM_SIZE[2] / 2, sideZ }

    -- Upper room above hub
    local upperY = HUB_SIZE[2] + WALL_THICKNESS * 2 + UPPER_ROOM_SIZE[2] / 2
    local upperCenter = { 0, upperY, 0 }

    -- Let the pipeline calculate doors, trusses, lights, and pads
    return LayoutBuilder.fromRooms({
        rooms = {
            [1] = {
                id = 1,
                position = hubCenter,
                dims = HUB_SIZE,
                parentId = nil,
                attachFace = nil,
            },
            [2] = {
                id = 2,
                position = sideCenter,
                dims = SIDE_ROOM_SIZE,
                parentId = 1,
                attachFace = "N",  -- Connected to hub via north face
            },
            [3] = {
                id = 3,
                position = upperCenter,
                dims = UPPER_ROOM_SIZE,
                parentId = 1,
                attachFace = "U",  -- Connected to hub via ceiling
            },
        },
        config = {
            regionNum = 0,  -- Title screen uses first palette
            wallThickness = WALL_THICKNESS,
            doorSize = 12,
            useTerrainShell = true,
        },
    })
end

--------------------------------------------------------------------------------
-- DIORAMA CREATION
--------------------------------------------------------------------------------

function TitleDiorama.create()
    -- Generate the layout (rooms defined, pipeline fills in details)
    local layout = createDioramaLayout()

    -- Instantiate using the standard build pipeline
    local result = LayoutInstantiator.instantiate(layout, {
        name = "TitleDiorama",
    })

    return result.container
end

function TitleDiorama.destroy(diorama)
    if diorama then
        diorama:Destroy()
    end
    -- Note: Don't clear terrain here - LayoutInstantiator.instantiate()
    -- clears terrain when building the gameplay region
end

--------------------------------------------------------------------------------
-- CAMERA CONTROL
--------------------------------------------------------------------------------

function TitleDiorama.createCamera()
    local camera = Instance.new("Camera")
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = 70
    return camera
end

--[[
    Convert HSV to RGB Color3.
    h: 0-1 (hue), s: 0-1 (saturation), v: 0-1 (value)
--]]
local function hsvToColor3(h, s, v)
    local r, g, b

    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    i = i % 6

    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end

    return Color3.new(r, g, b)
end

--[[
    Find all PointLights in the diorama.
--]]
local function findLights(diorama)
    local lights = {}
    for _, descendant in ipairs(diorama:GetDescendants()) do
        if descendant:IsA("PointLight") then
            table.insert(lights, descendant)
        end
    end
    return lights
end

function TitleDiorama.startRotation(camera, diorama, onUpdate)
    local angle = 0
    local centerPos = Vector3.new(0, CAMERA_HEIGHT, 0)

    -- Find all lights for color cycling
    local lights = diorama and findLights(diorama) or {}
    local COLOR_CYCLE_SPEED = 0.1  -- How fast colors cycle (slower than rotation)

    local connection = RunService.RenderStepped:Connect(function(dt)
        angle = angle + ROTATION_SPEED * dt

        -- Camera looks outward from center
        local lookDir = Vector3.new(math.sin(angle), -0.1, math.cos(angle))
        camera.CFrame = CFrame.lookAt(centerPos, centerPos + lookDir)

        -- Cycle light colors through the spectrum
        local hue = (angle * COLOR_CYCLE_SPEED) % 1
        local color = hsvToColor3(hue, 0.7, 1)  -- 70% saturation, full brightness

        for _, light in ipairs(lights) do
            light.Color = color
            -- Also update the neon fixture color if parent is a Part
            local fixture = light.Parent
            if fixture and fixture:IsA("BasePart") then
                fixture.Color = color
            end
        end

        if onUpdate then
            onUpdate(angle)
        end
    end)

    return connection
end

return TitleDiorama
