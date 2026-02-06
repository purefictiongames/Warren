--[[
    LibPureFiction Framework v2
    TitleDiorama.lua - Title Screen 3D Background

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TitleDiorama creates a small 3D scene for the title screen background.
    The camera is positioned at the center of a hub room and slowly rotates
    to show off the environment.

    Layout:
    - Center hub room with ceiling port and truss leading up
    - Upper room connected via the truss
    - At least one horizontal connecting room
    - Decorative portals centered on each room's floor

--]]

local RunService = game:GetService("RunService")

local TitleDiorama = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local WALL_THICKNESS = 4
local WALL_COLOR = Color3.fromRGB(80, 100, 140)  -- Steel blue (matches title palette)
local WALL_MATERIAL = Enum.Material.Brick
local PORTAL_COLOR = Color3.fromRGB(180, 50, 255)  -- Purple neon
local TRUSS_COLOR = Color3.fromRGB(60, 80, 110)

-- Room dimensions (interior)
local HUB_SIZE = Vector3.new(40, 24, 40)
local SIDE_ROOM_SIZE = Vector3.new(30, 20, 24)
local UPPER_ROOM_SIZE = Vector3.new(24, 16, 24)

-- Doorway dimensions
local HORIZONTAL_DOOR_SIZE = Vector3.new(12, 16, WALL_THICKNESS + 2)
local CEILING_PORT_SIZE = Vector3.new(10, WALL_THICKNESS + 2, 10)

-- Camera settings
local CAMERA_HEIGHT = 8  -- Eye level
local ROTATION_SPEED = 0.05  -- Radians per second (slow rotation)

--------------------------------------------------------------------------------
-- GEOMETRY HELPERS
--------------------------------------------------------------------------------

local function createWall(name, size, position, parent)
    local wall = Instance.new("Part")
    wall.Name = name
    wall.Size = size
    wall.Position = position
    wall.Anchored = true
    wall.CanCollide = true
    wall.Material = WALL_MATERIAL
    wall.Color = WALL_COLOR
    wall.TopSurface = Enum.SurfaceType.Smooth
    wall.BottomSurface = Enum.SurfaceType.Smooth
    wall.Parent = parent
    return wall
end

local function createPortal(position, parent)
    local portal = Instance.new("Part")
    portal.Name = "Portal"
    portal.Size = Vector3.new(6, 0.5, 6)
    portal.Position = position
    portal.Anchored = true
    portal.CanCollide = false
    portal.Material = Enum.Material.Neon
    portal.Color = PORTAL_COLOR
    portal.TopSurface = Enum.SurfaceType.Smooth
    portal.BottomSurface = Enum.SurfaceType.Smooth
    portal.Parent = parent
    return portal
end

local function createTruss(position, height, parent)
    local truss = Instance.new("TrussPart")
    truss.Name = "Truss"
    truss.Size = Vector3.new(2, height, 2)
    truss.Position = position
    truss.Anchored = true
    truss.CanCollide = true
    truss.Color = TRUSS_COLOR
    truss.Parent = parent
    return truss
end

local function createLight(position, brightness, range, color, parent)
    -- Create an anchored part to hold the light
    local lightPart = Instance.new("Part")
    lightPart.Name = "LightSource"
    lightPart.Size = Vector3.new(1, 1, 1)
    lightPart.Position = position
    lightPart.Anchored = true
    lightPart.CanCollide = false
    lightPart.Transparency = 1
    lightPart.Parent = parent

    local light = Instance.new("PointLight")
    light.Brightness = brightness or 2
    light.Range = range or 40
    light.Color = color or Color3.new(1, 1, 1)
    light.Shadows = true
    light.Parent = lightPart

    return lightPart
end

--------------------------------------------------------------------------------
-- ROOM BUILDERS
--------------------------------------------------------------------------------

local function buildRoom(centerPos, interiorSize, openings, parent)
    -- openings: { north = bool, south = bool, east = bool, west = bool, ceiling = bool, floor = bool }
    local container = Instance.new("Model")
    container.Name = "Room"

    local t = WALL_THICKNESS
    local sx, sy, sz = interiorSize.X, interiorSize.Y, interiorSize.Z
    local cx, cy, cz = centerPos.X, centerPos.Y, centerPos.Z

    -- Floor (always solid for diorama)
    createWall("Floor",
        Vector3.new(sx + t * 2, t, sz + t * 2),
        Vector3.new(cx, cy - sy/2 - t/2, cz),
        container)

    -- Ceiling (with optional port)
    if not openings.ceiling then
        createWall("Ceiling",
            Vector3.new(sx + t * 2, t, sz + t * 2),
            Vector3.new(cx, cy + sy/2 + t/2, cz),
            container)
    else
        -- Ceiling with hole - create 4 pieces around the port
        local portSize = CEILING_PORT_SIZE
        local halfPort = portSize.X / 2
        local halfRoom = sx / 2

        -- North piece
        createWall("Ceiling_N",
            Vector3.new(sx + t * 2, t, (sz/2 - halfPort)),
            Vector3.new(cx, cy + sy/2 + t/2, cz + halfPort + (sz/2 - halfPort)/2),
            container)
        -- South piece
        createWall("Ceiling_S",
            Vector3.new(sx + t * 2, t, (sz/2 - halfPort)),
            Vector3.new(cx, cy + sy/2 + t/2, cz - halfPort - (sz/2 - halfPort)/2),
            container)
        -- East piece
        createWall("Ceiling_E",
            Vector3.new((sx/2 - halfPort), t, portSize.Z),
            Vector3.new(cx + halfPort + (sx/2 - halfPort)/2, cy + sy/2 + t/2, cz),
            container)
        -- West piece
        createWall("Ceiling_W",
            Vector3.new((sx/2 - halfPort), t, portSize.Z),
            Vector3.new(cx - halfPort - (sx/2 - halfPort)/2, cy + sy/2 + t/2, cz),
            container)
    end

    -- North wall (+Z)
    if not openings.north then
        createWall("Wall_North",
            Vector3.new(sx + t * 2, sy, t),
            Vector3.new(cx, cy, cz + sz/2 + t/2),
            container)
    else
        -- Wall with doorway - create pieces around opening
        local doorH = HORIZONTAL_DOOR_SIZE.Y
        local doorW = HORIZONTAL_DOOR_SIZE.X
        -- Left piece
        createWall("Wall_North_L",
            Vector3.new((sx - doorW)/2 + t, sy, t),
            Vector3.new(cx - doorW/2 - (sx - doorW)/4 - t/2, cy, cz + sz/2 + t/2),
            container)
        -- Right piece
        createWall("Wall_North_R",
            Vector3.new((sx - doorW)/2 + t, sy, t),
            Vector3.new(cx + doorW/2 + (sx - doorW)/4 + t/2, cy, cz + sz/2 + t/2),
            container)
        -- Top piece (above door)
        createWall("Wall_North_T",
            Vector3.new(doorW, sy - doorH, t),
            Vector3.new(cx, cy + doorH/2 + (sy - doorH)/2, cz + sz/2 + t/2),
            container)
    end

    -- South wall (-Z)
    if not openings.south then
        createWall("Wall_South",
            Vector3.new(sx + t * 2, sy, t),
            Vector3.new(cx, cy, cz - sz/2 - t/2),
            container)
    end

    -- East wall (+X)
    if not openings.east then
        createWall("Wall_East",
            Vector3.new(t, sy, sz),
            Vector3.new(cx + sx/2 + t/2, cy, cz),
            container)
    end

    -- West wall (-X)
    if not openings.west then
        createWall("Wall_West",
            Vector3.new(t, sy, sz),
            Vector3.new(cx - sx/2 - t/2, cy, cz),
            container)
    end

    container.Parent = parent
    return container
end

--------------------------------------------------------------------------------
-- DIORAMA CREATION
--------------------------------------------------------------------------------

function TitleDiorama.create()
    local diorama = Instance.new("Model")
    diorama.Name = "TitleDiorama"

    -- Hub room at origin
    local hubCenter = Vector3.new(0, HUB_SIZE.Y / 2, 0)
    local hubRoom = buildRoom(hubCenter, HUB_SIZE, {
        north = true,  -- Opening to side room
        ceiling = true,  -- Opening for truss
    }, diorama)
    hubRoom.Name = "HubRoom"

    -- Portal in hub floor
    createPortal(Vector3.new(0, WALL_THICKNESS / 2 + 0.3, 0), diorama)

    -- Side room (north of hub)
    local sideCenter = Vector3.new(0, SIDE_ROOM_SIZE.Y / 2, HUB_SIZE.Z / 2 + SIDE_ROOM_SIZE.Z / 2 + WALL_THICKNESS)
    local sideRoom = buildRoom(sideCenter, SIDE_ROOM_SIZE, {
        south = true,  -- Opening back to hub (implicitly open since hub has north open)
    }, diorama)
    sideRoom.Name = "SideRoom"

    -- Portal in side room floor
    createPortal(Vector3.new(0, WALL_THICKNESS / 2 + 0.3, sideCenter.Z), diorama)

    -- Upper room (above hub)
    local upperCenter = Vector3.new(0, HUB_SIZE.Y + WALL_THICKNESS + UPPER_ROOM_SIZE.Y / 2, 0)
    local upperRoom = buildRoom(upperCenter, UPPER_ROOM_SIZE, {
        floor = true,  -- Opening for truss (but we build solid floor, truss passes through visually)
    }, diorama)
    upperRoom.Name = "UpperRoom"

    -- Portal in upper room floor
    createPortal(Vector3.new(0, upperCenter.Y - UPPER_ROOM_SIZE.Y / 2 + 0.3, 0), diorama)

    -- Truss from hub floor to upper room
    local trussBottom = WALL_THICKNESS
    local trussTop = upperCenter.Y - UPPER_ROOM_SIZE.Y / 2
    local trussHeight = trussTop - trussBottom
    createTruss(Vector3.new(4, trussBottom + trussHeight / 2, 4), trussHeight, diorama)

    -- Lighting
    -- Main hub light (above center)
    createLight(Vector3.new(0, HUB_SIZE.Y * 0.7, 0), 2, 50, Color3.fromRGB(200, 220, 255), diorama)

    -- Side room light
    createLight(Vector3.new(0, SIDE_ROOM_SIZE.Y * 0.7, sideCenter.Z), 1.5, 35, Color3.fromRGB(200, 220, 255), diorama)

    -- Upper room light
    createLight(Vector3.new(0, upperCenter.Y + 4, 0), 1.5, 30, Color3.fromRGB(200, 220, 255), diorama)

    -- Portal glow lights (purple tint)
    createLight(Vector3.new(0, 3, 0), 1, 15, Color3.fromRGB(180, 100, 255), diorama)
    createLight(Vector3.new(0, 3, sideCenter.Z), 1, 15, Color3.fromRGB(180, 100, 255), diorama)

    diorama.Parent = workspace
    return diorama
end

function TitleDiorama.destroy(diorama)
    if diorama then
        diorama:Destroy()
    end
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

function TitleDiorama.startRotation(camera, onUpdate)
    local angle = 0
    local centerPos = Vector3.new(0, CAMERA_HEIGHT, 0)

    local connection = RunService.RenderStepped:Connect(function(dt)
        angle = angle + ROTATION_SPEED * dt

        -- Camera looks outward from center
        local lookDir = Vector3.new(math.sin(angle), -0.1, math.cos(angle))
        camera.CFrame = CFrame.lookAt(centerPos, centerPos + lookDir)

        if onUpdate then
            onUpdate(angle)
        end
    end)

    return connection
end

return TitleDiorama
