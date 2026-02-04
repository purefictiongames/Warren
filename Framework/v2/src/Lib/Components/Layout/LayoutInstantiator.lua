--[[
    LibPureFiction Framework v2
    LayoutInstantiator.lua - Create Parts from Layout Data

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LayoutInstantiator takes a Layout table and creates all the parts in the
    world. No procedural logic - just data-driven instantiation.

    This separates "building" from "what to build", enabling:
    - Reload regions from stored layouts (no regeneration)
    - Deterministic part creation from fixed data
    - Easy testing with known layout data

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local LayoutInstantiator = require(...)
    local result = LayoutInstantiator.instantiate(layout, {
        container = workspace,
        name = "Region_1",
    })
    -- result.container, result.spawnPoint, result.pads
    ```

--]]

local LayoutInstantiator = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local VOXEL_SIZE = 4  -- Roblox terrain minimum voxel size

-- Lava cave theme colors (stone walls, lava floor)
local WALL_COLOR = Color3.fromRGB(120, 110, 100)  -- Stone gray
local FLOOR_COLOR = Color3.fromRGB(255, 255, 240)  -- White-hot lava


--------------------------------------------------------------------------------
-- MATERIAL/COLOR CONVERSION
--------------------------------------------------------------------------------

local function getMaterial(materialName)
    if type(materialName) == "string" then
        return Enum.Material[materialName] or Enum.Material.Brick
    end
    return materialName or Enum.Material.Brick
end

local function getColor(colorData)
    if type(colorData) == "table" then
        return Color3.fromRGB(colorData[1], colorData[2], colorData[3])
    end
    return colorData or Color3.fromRGB(140, 110, 90)
end

--------------------------------------------------------------------------------
-- SHELL BUILDING
--------------------------------------------------------------------------------

local function createWallPart(name, position, size, material, color, parent)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = Vector3.new(size[1], size[2], size[3])
    part.Position = Vector3.new(position[1], position[2], position[3])
    part.Anchored = true
    part.Material = material
    part.Color = color
    part.Parent = parent
    return part
end

local function buildShell(room, config, container)
    local pos = room.position
    local dims = room.dims
    local wt = config.wallThickness
    local material = getMaterial(config.material)
    local color = getColor(config.color)

    local roomContainer = Instance.new("Model")
    roomContainer.Name = "Room_" .. room.id
    roomContainer.Parent = container

    local walls = {}

    -- Floor
    walls.Floor = createWallPart(
        "Floor",
        { pos[1], pos[2] - dims[2]/2 - wt/2, pos[3] },
        { dims[1] + 2*wt, wt, dims[3] + 2*wt },
        material, color, roomContainer
    )

    -- Ceiling
    walls.Ceiling = createWallPart(
        "Ceiling",
        { pos[1], pos[2] + dims[2]/2 + wt/2, pos[3] },
        { dims[1] + 2*wt, wt, dims[3] + 2*wt },
        material, color, roomContainer
    )

    -- North (+Z)
    walls.N = createWallPart(
        "Wall_N",
        { pos[1], pos[2], pos[3] + dims[3]/2 + wt/2 },
        { dims[1] + 2*wt, dims[2], wt },
        material, color, roomContainer
    )

    -- South (-Z)
    walls.S = createWallPart(
        "Wall_S",
        { pos[1], pos[2], pos[3] - dims[3]/2 - wt/2 },
        { dims[1] + 2*wt, dims[2], wt },
        material, color, roomContainer
    )

    -- East (+X)
    walls.E = createWallPart(
        "Wall_E",
        { pos[1] + dims[1]/2 + wt/2, pos[2], pos[3] },
        { wt, dims[2], dims[3] },
        material, color, roomContainer
    )

    -- West (-X)
    walls.W = createWallPart(
        "Wall_W",
        { pos[1] - dims[1]/2 - wt/2, pos[2], pos[3] },
        { wt, dims[2], dims[3] },
        material, color, roomContainer
    )

    return roomContainer, walls
end

--------------------------------------------------------------------------------
-- TERRAIN SHELL PAINTING
--------------------------------------------------------------------------------

--[[
    Fill solid terrain block for a room's shell (no carving yet).
--]]
local function fillTerrainShell(roomPos, roomDims, gap, material)
    local terrain = workspace.Terrain
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])

    -- Outer shell size: interior + gap on each side + 1 voxel thickness
    local shellSize = dims + Vector3.new(
        2 * (gap + VOXEL_SIZE),
        2 * (gap + VOXEL_SIZE),
        2 * (gap + VOXEL_SIZE)
    )

    -- Fill solid terrain block
    terrain:FillBlock(CFrame.new(pos), shellSize, material)
end

--[[
    Carve out room interior with Air.
--]]
local function carveTerrainInterior(roomPos, roomDims, gap)
    local terrain = workspace.Terrain
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])

    -- Carve out interior + gap with Air
    local interiorSize = dims + Vector3.new(2 * gap, 2 * gap, 2 * gap)
    terrain:FillBlock(CFrame.new(pos), interiorSize, Enum.Material.Air)
end

--[[
    Paint lava veins through the terrain shell using noise.
    Iterates through shell voxels and replaces some with CrackedLava.
--]]
local function paintLavaVeins(roomPos, roomDims, veinMaterial, noiseScale, threshold)
    local terrain = workspace.Terrain
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])

    noiseScale = noiseScale or 8
    threshold = threshold or 0.55

    -- Shell bounds (outer edge of terrain)
    local shellMin = pos - dims/2 - Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
    local shellMax = pos + dims/2 + Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)

    -- Interior bounds (don't paint inside the room)
    local interiorMin = pos - dims/2
    local interiorMax = pos + dims/2

    -- Iterate through shell region voxel by voxel
    for x = shellMin.X, shellMax.X, VOXEL_SIZE do
        for y = shellMin.Y, shellMax.Y, VOXEL_SIZE do
            for z = shellMin.Z, shellMax.Z, VOXEL_SIZE do
                -- Skip if inside the interior (not in shell)
                local inInterior = x > interiorMin.X and x < interiorMax.X
                    and y > interiorMin.Y and y < interiorMax.Y
                    and z > interiorMin.Z and z < interiorMax.Z

                if not inInterior then
                    -- Use noise to determine if this voxel gets lava
                    local n = math.noise(x / noiseScale, y / noiseScale, z / noiseScale)

                    if n > threshold then
                        terrain:FillBlock(
                            CFrame.new(x, y, z),
                            Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE),
                            veinMaterial
                        )
                    end
                end
            end
        end
    end
end

--[[
    Style walls to match terrain (lava cave theme).
--]]
local function styleWallsAsTerrain(walls)
    for wallName, wall in pairs(walls) do
        if wallName == "Floor" then
            wall.Material = Enum.Material.CrackedLava
            wall.Color = FLOOR_COLOR
        else
            wall.Material = Enum.Material.Cobblestone
            wall.Color = WALL_COLOR
        end
    end
end

--------------------------------------------------------------------------------
-- DOOR CUTTING
--------------------------------------------------------------------------------

local function cutDoor(door, roomContainers, config, useTerrainShell)
    local wt = config.wallThickness

    -- Create cutter part
    local cutterDepth = wt * 8  -- Deep enough to cut through walls
    local cutterSize

    if door.axis == 2 then
        -- Vertical door (ceiling/floor hole)
        cutterSize = Vector3.new(door.width, cutterDepth, door.height)
    else
        -- Horizontal door (wall hole)
        if door.widthAxis == 1 then
            cutterSize = Vector3.new(door.width, door.height, cutterDepth)
        else
            cutterSize = Vector3.new(cutterDepth, door.height, door.width)
        end
    end

    local cutter = Instance.new("Part")
    cutter.Size = cutterSize
    cutter.Position = Vector3.new(door.center[1], door.center[2], door.center[3])
    cutter.Anchored = true
    cutter.CanCollide = false
    cutter.Transparency = 1

    -- Find walls to cut in both rooms
    local roomsToCheck = { door.fromRoom, door.toRoom }

    for _, roomId in ipairs(roomsToCheck) do
        local roomContainer = roomContainers[roomId]
        if roomContainer then
            for _, child in ipairs(roomContainer:GetChildren()) do
                if child:IsA("BasePart") and (
                   child.Name:match("^Wall") or
                   child.Name == "Floor" or
                   child.Name == "Ceiling"
                ) then
                    -- Check if this wall intersects the cutter
                    local wallPos = child.Position
                    local wallSize = child.Size

                    local intersects = true
                    for axis = 1, 3 do
                        local wMin = wallPos[axis == 1 and "X" or axis == 2 and "Y" or "Z"] - wallSize[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2
                        local wMax = wallPos[axis == 1 and "X" or axis == 2 and "Y" or "Z"] + wallSize[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2
                        local cMin = cutter.Position[axis == 1 and "X" or axis == 2 and "Y" or "Z"] - cutter.Size[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2
                        local cMax = cutter.Position[axis == 1 and "X" or axis == 2 and "Y" or "Z"] + cutter.Size[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2

                        if wMax <= cMin or cMax <= wMin then
                            intersects = false
                            break
                        end
                    end

                    if intersects then
                        -- Perform CSG subtraction
                        local success, result = pcall(function()
                            return child:SubtractAsync({ cutter })
                        end)

                        if success and result then
                            result.Name = child.Name
                            result.Parent = roomContainer
                            child:Destroy()
                        end
                    end
                end
            end
        end
    end

    -- Clear terrain in doorway area (terrain isn't affected by CSG)
    if useTerrainShell then
        -- Expand cutter size to clear terrain (account for voxel overlap)
        local terrainClearSize = cutter.Size + Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
        workspace.Terrain:FillBlock(cutter.CFrame, terrainClearSize, Enum.Material.Air)
    end

    cutter:Destroy()
end

--------------------------------------------------------------------------------
-- TRUSS CREATION
--------------------------------------------------------------------------------

local function createTruss(truss, container)
    local part = Instance.new("TrussPart")
    part.Name = "Truss_" .. truss.id
    part.Size = Vector3.new(truss.size[1], truss.size[2], truss.size[3])
    part.Position = Vector3.new(truss.position[1], truss.position[2], truss.position[3])
    part.Anchored = true
    part.Parent = container
    return part
end

--------------------------------------------------------------------------------
-- LIGHT CREATION
--------------------------------------------------------------------------------

local function createLight(light, roomContainers, rooms)
    local roomContainer = roomContainers[light.roomId]
    if not roomContainer then
        roomContainer = workspace
    end

    local fixtureSize = Vector3.new(light.size[1], light.size[2], light.size[3])
    local fixturePos = Vector3.new(light.position[1], light.position[2], light.position[3])

    -- Wall direction mapping (wall the light is mounted on)
    local wallDirs = {
        N = Vector3.new(0, 0, 1),   -- +Z
        S = Vector3.new(0, 0, -1),  -- -Z
        E = Vector3.new(1, 0, 0),   -- +X
        W = Vector3.new(-1, 0, 0),  -- -X
    }
    local wallDir = wallDirs[light.wall] or Vector3.new(0, 0, 1)

    -- Create backing/spacer between light and wall
    local spacerThickness = 1.5
    local spacerSize
    local spacerOffset
    if math.abs(wallDir.X) > 0 then
        -- E/W wall: spacer is thin in X, matches light Y and Z
        spacerSize = Vector3.new(spacerThickness, fixtureSize.Y, fixtureSize.Z)
        spacerOffset = wallDir * (fixtureSize.X/2 + spacerThickness/2)
    else
        -- N/S wall: spacer is thin in Z, matches light X and Y
        spacerSize = Vector3.new(fixtureSize.X, fixtureSize.Y, spacerThickness)
        spacerOffset = wallDir * (fixtureSize.Z/2 + spacerThickness/2)
    end

    local spacer = Instance.new("Part")
    spacer.Name = "Light_" .. light.id .. "_Spacer"
    spacer.Size = spacerSize
    spacer.Position = fixturePos + spacerOffset  -- Behind the light
    spacer.Anchored = true
    spacer.CanCollide = false
    spacer.Material = Enum.Material.Rock
    spacer.Color = WALL_COLOR
    spacer.Parent = roomContainer

    -- Create light fixture
    local fixture = Instance.new("Part")
    fixture.Name = "Light_" .. light.id
    fixture.Size = fixtureSize
    fixture.Position = fixturePos
    fixture.Anchored = true
    fixture.CanCollide = false
    fixture.Material = Enum.Material.Neon
    fixture.Color = Color3.fromRGB(255, 120, 40)  -- Orange-red lava glow
    fixture.Parent = roomContainer

    local pointLight = Instance.new("PointLight")
    pointLight.Name = "PointLight"
    pointLight.Brightness = 0.7  -- Warm glow
    pointLight.Range = 60
    pointLight.Color = Color3.fromRGB(255, 50, 20)  -- Deep red lava glow
    pointLight.Shadows = false
    pointLight.Parent = fixture

    return fixture
end

--------------------------------------------------------------------------------
-- PAD CREATION
--------------------------------------------------------------------------------

local function createPad(pad, roomContainers)
    local roomContainer = roomContainers[pad.roomId]
    if not roomContainer then
        roomContainer = workspace
    end

    local padSize = Vector3.new(6, 1, 6)
    local padPos = Vector3.new(pad.position[1], pad.position[2], pad.position[3])

    -- Create backing/base (same XZ, 1.5 studs thick, below pad)
    local baseThickness = 1.5
    local base = Instance.new("Part")
    base.Name = pad.id .. "_Base"
    base.Size = Vector3.new(padSize.X, baseThickness, padSize.Z)
    base.Position = padPos - Vector3.new(0, (padSize.Y + baseThickness) / 2, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Material = Enum.Material.Neon
    base.Color = FLOOR_COLOR
    base.Parent = roomContainer

    -- Create portal pad
    local part = Instance.new("Part")
    part.Name = pad.id
    part.Size = padSize
    part.Position = padPos
    part.Anchored = true
    part.CanCollide = true
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(180, 50, 255)
    part.Parent = roomContainer

    part:SetAttribute("TeleportPad", true)
    part:SetAttribute("PadId", pad.id)
    part:SetAttribute("RoomId", pad.roomId)

    return part
end

local function createSpawn(spawn, container, regionId)
    local spawnPoint = Instance.new("SpawnLocation")
    spawnPoint.Name = "Spawn_" .. (regionId or "default")
    spawnPoint.Size = Vector3.new(6, 1, 6)
    spawnPoint.Position = Vector3.new(spawn.position[1], spawn.position[2], spawn.position[3])
    spawnPoint.Anchored = true
    spawnPoint.CanCollide = false
    spawnPoint.Neutral = true
    spawnPoint.Transparency = 1
    spawnPoint.Parent = container

    print(string.format("[LayoutInstantiator] Spawn at (%.1f, %.1f, %.1f)",
        spawn.position[1], spawn.position[2], spawn.position[3]))

    return spawnPoint
end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function LayoutInstantiator.instantiate(layout, options)
    options = options or {}

    -- Delete any existing SpawnLocation parts in workspace
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("SpawnLocation") then
            print("[LayoutInstantiator] Removing existing SpawnLocation: " .. child.Name)
            child:Destroy()
        end
    end

    -- Create or use container
    local container
    if options.container then
        container = options.container
    else
        container = Instance.new("Model")
        container.Name = options.name or "Layout"
        container.Parent = workspace
    end

    -- Store region metadata on container
    container:SetAttribute("RegionNum", layout.regionNum or 1)

    local config = layout.config or {
        wallThickness = 1,
        material = "Brick",
        color = { 140, 110, 90 },
    }

    -- Terrain shell configuration (lava cave theme)
    local useTerrainShell = config.useTerrainShell ~= false  -- Default true
    local wallMaterial = Enum.Material.Rock
    local floorMaterial = Enum.Material.CrackedLava

    local roomContainers = {}
    local pads = {}

    -- Clear existing terrain and set material colors (lava cave theme)
    if useTerrainShell then
        workspace.Terrain:Clear()
        workspace.Terrain:SetMaterialColor(Enum.Material.Rock, WALL_COLOR)
        workspace.Terrain:SetMaterialColor(Enum.Material.CrackedLava, FLOOR_COLOR)
    end

    -- PASS 1: Build all room shells, hide walls, fill terrain
    local roomZones = {}
    local allWalls = {}  -- Store walls for later reference
    for id, room in pairs(layout.rooms) do
        local roomContainer, walls = buildShell(room, config, container)
        roomContainers[id] = roomContainer
        allWalls[id] = walls

        -- Style walls to match terrain
        if useTerrainShell then
            styleWallsAsTerrain(walls)
            -- Fill terrain shell (solid block, no carving yet)
            fillTerrainShell(room.position, room.dims, 0, wallMaterial)
        end

        -- Create invisible zone part for player detection
        local zonePart = Instance.new("Part")
        zonePart.Name = "RoomZone_" .. id
        zonePart.Size = Vector3.new(room.dims[1], room.dims[2], room.dims[3])
        zonePart.Position = Vector3.new(room.position[1], room.position[2], room.position[3])
        zonePart.Anchored = true
        zonePart.CanCollide = false
        zonePart.Transparency = 1
        zonePart.Parent = roomContainer
        zonePart:SetAttribute("RoomId", id)
        zonePart:SetAttribute("RegionNum", layout.regionNum or 1)

        roomZones[id] = zonePart
    end

    -- PASS 2: Carve all room interiors (after all shells are filled)
    if useTerrainShell then
        for id, room in pairs(layout.rooms) do
            carveTerrainInterior(room.position, room.dims, 0)
        end
    end

    -- PASS 3: Paint lava veins through granite walls (doubled - lower threshold)
    if useTerrainShell then
        for id, room in pairs(layout.rooms) do
            paintLavaVeins(room.position, room.dims, floorMaterial, 8, 0.35)
        end
    end

    -- PASS 4: Paint floor material (CrackedLava base)
    if useTerrainShell then
        local terrain = workspace.Terrain
        for id, room in pairs(layout.rooms) do
            local pos = Vector3.new(room.position[1], room.position[2], room.position[3])
            local dims = Vector3.new(room.dims[1], room.dims[2], room.dims[3])

            -- Floor is at bottom of room, paint floor material on the exterior floor surface
            local floorY = pos.Y - dims.Y / 2 - VOXEL_SIZE / 2
            local floorPos = Vector3.new(pos.X, floorY, pos.Z)
            local floorSize = Vector3.new(dims.X + VOXEL_SIZE * 2, VOXEL_SIZE, dims.Z + VOXEL_SIZE * 2)
            terrain:FillBlock(CFrame.new(floorPos), floorSize, floorMaterial)
        end
    end

    -- PASS 5: Mix granite patches into lava floors
    if useTerrainShell then
        local terrain = workspace.Terrain
        for id, room in pairs(layout.rooms) do
            local pos = Vector3.new(room.position[1], room.position[2], room.position[3])
            local dims = Vector3.new(room.dims[1], room.dims[2], room.dims[3])

            local floorY = pos.Y - dims.Y / 2 - VOXEL_SIZE / 2
            local minX = pos.X - dims.X / 2 - VOXEL_SIZE
            local maxX = pos.X + dims.X / 2 + VOXEL_SIZE
            local minZ = pos.Z - dims.Z / 2 - VOXEL_SIZE
            local maxZ = pos.Z + dims.Z / 2 + VOXEL_SIZE

            -- Paint granite patches on floor using noise
            for x = minX, maxX, VOXEL_SIZE do
                for z = minZ, maxZ, VOXEL_SIZE do
                    local n = math.noise(x / 12, floorY / 12, z / 12)
                    if n > 0.4 then  -- ~30% granite patches
                        terrain:FillBlock(
                            CFrame.new(x, floorY, z),
                            Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE),
                            wallMaterial
                        )
                    end
                end
            end
        end
    end

    -- Cut all doors
    for _, door in ipairs(layout.doors) do
        cutDoor(door, roomContainers, config, useTerrainShell)
    end

    -- Create all trusses
    for _, truss in ipairs(layout.trusses) do
        createTruss(truss, container)
    end

    -- Create all lights and carve terrain around them
    for _, light in ipairs(layout.lights) do
        local fixture = createLight(light, roomContainers, layout.rooms)
        if useTerrainShell and fixture then
            -- Carve terrain around light fixture with small margin
            local margin = 2
            local carveSize = fixture.Size + Vector3.new(margin * 2, margin * 2, margin * 2)
            workspace.Terrain:FillBlock(fixture.CFrame, carveSize, Enum.Material.Air)
        end
    end

    -- Create all pads and carve terrain around them
    for _, pad in ipairs(layout.pads) do
        local padPart = createPad(pad, roomContainers)
        pads[pad.id] = {
            part = padPart,
            id = pad.id,
            roomId = pad.roomId,
            position = pad.position,
        }
        if useTerrainShell and padPart then
            -- Carve terrain around pad with small margin
            local margin = 2
            local carveSize = padPart.Size + Vector3.new(margin * 2, margin * 2, margin * 2)
            workspace.Terrain:FillBlock(padPart.CFrame, carveSize, Enum.Material.Air)
        end
    end

    -- Create spawn at room 1 center
    local spawnPoint = nil
    if layout.spawn then
        spawnPoint = createSpawn(layout.spawn, container, options.regionId)
    end

    return {
        container = container,
        roomContainers = roomContainers,
        roomZones = roomZones,
        spawnPoint = spawnPoint,
        spawnPosition = layout.spawn and layout.spawn.position,
        pads = pads,
        roomCount = #layout.rooms,
    }
end

return LayoutInstantiator
