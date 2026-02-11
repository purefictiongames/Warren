--[[
    LibPureFiction Framework v2
    PathGraph_AutoRun.server.lua - Auto-run PathGraph Demo on Play

    Place this in ServerScriptService to auto-run the demo.
    Generates a new map on each player respawn.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib to be available
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local PathGraph = Lib.Components.PathGraph
local Room = Lib.Components.Room
local DoorwayCutter = Lib.Components.DoorwayCutter

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local currentDemo = nil
local spawnLocation = nil

--------------------------------------------------------------------------------
-- MAP GENERATION
--------------------------------------------------------------------------------

local function generateMap()
    -- Cleanup previous demo
    if currentDemo then
        if currentDemo.folder and currentDemo.folder.Parent then
            currentDemo.folder:Destroy()
        end
        if currentDemo.pathGraph then
            currentDemo.pathGraph.Sys.onStop(currentDemo.pathGraph)
        end
        if currentDemo.doorwayCutter then
            currentDemo.doorwayCutter.Sys.onStop(currentDemo.doorwayCutter)
        end
        for _, room in ipairs(currentDemo.rooms or {}) do
            room.Sys.onStop(room)
        end
    end

    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "PathGraph_Demo"
    demoFolder.Parent = workspace

    local rooms = {}
    local roomLayouts = {}
    local pathGraph = PathGraph:new({ id = "AutoRun_PathGraph" })
    pathGraph.Sys.onInit(pathGraph)

    local doorwayCutter = DoorwayCutter:new({ id = "AutoRun_DoorwayCutter" })
    doorwayCutter.Sys.onInit(doorwayCutter)

    -- Generate random seed
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local seed = ""
    for _ = 1, 12 do
        local idx = math.random(1, #chars)
        seed = seed .. chars:sub(idx, idx)
    end

    local baseUnit = 15

    pathGraph.In.onConfigure(pathGraph, {
        baseUnit = baseUnit,
        seed = seed,
        spurCount = { min = 2, max = 4 },
        maxSegmentsPerPath = 8,
        sizeRange = { 1.2, 2.5 },
        scanDistance = 5,
    })

    doorwayCutter.In.onConfigure(doorwayCutter, {
        baseUnit = 5,
        wallThickness = 1,
        doorHeight = 8,
        container = demoFolder,
    })

    -- Disable baseplate
    local baseplate = workspace:FindFirstChild("Baseplate")
    if baseplate then
        baseplate.CanCollide = false
        baseplate.Transparency = 0.9
    end

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS
    ---------------------------------------------------------------------------

    local pgOriginalFire = pathGraph.Out.Fire
    pathGraph.Out.Fire = function(outSelf, signal, data)
        if signal == "roomLayout" then
            table.insert(roomLayouts, data)

            -- Create blocking volume part for Room node
            local blockPart = Instance.new("Part")
            blockPart.Name = "Block_" .. data.id
            blockPart.Size = Vector3.new(data.dims[1], data.dims[2], data.dims[3])
            blockPart.Position = Vector3.new(data.position[1], data.position[2], data.position[3])
            blockPart.Anchored = true
            blockPart.CanCollide = true
            blockPart.Material = Enum.Material.SmoothPlastic
            blockPart.Transparency = 0.3
            blockPart.Color = Color3.fromRGB(120, 120, 140)
            blockPart.Parent = demoFolder

            -- Create Room node
            local roomId = "Room_" .. data.id
            local room = Room:new({ id = roomId })
            room.Sys.onInit(room)
            room.In.onConfigure(room, {
                part = blockPart,
                wallThickness = 1,
            })
            room.Sys.onStart(room)
            table.insert(rooms, { node = room, layout = data })

        elseif signal == "complete" then
            print("==========================================")
            print("[AutoRun] GENERATION COMPLETE")
            print("  Seed:", data.seed)
            print("  Total Rooms:", data.totalRooms)
            print("==========================================")

            -- Cut doorways
            task.wait()
            doorwayCutter.In.onRoomsComplete(doorwayCutter, {
                layouts = data.layouts,
            })

            -- Add lights to each room
            addLightsToRooms(demoFolder, roomLayouts)

            -- Set spawn to topmost room
            setSpawnToTopmostRoom(roomLayouts)
        end

        pgOriginalFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- START GENERATION
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[AutoRun] Starting generation")
    print("  Seed:", seed)
    print("==========================================")

    local origin = Vector3.new(0, 80, 0)

    pathGraph.In.onGenerate(pathGraph, {
        start = { origin.X, origin.Y, origin.Z },
        goals = { { origin.X + 120, origin.Y, origin.Z + 120 } },
    })

    currentDemo = {
        pathGraph = pathGraph,
        doorwayCutter = doorwayCutter,
        rooms = rooms,
        folder = demoFolder,
        seed = seed,
    }

    return currentDemo
end

--------------------------------------------------------------------------------
-- LIGHTING
--------------------------------------------------------------------------------

function addLightsToRooms(container, layouts)
    for _, layout in ipairs(layouts) do
        local lightPart = Instance.new("Part")
        lightPart.Name = "Light_" .. layout.id
        lightPart.Size = Vector3.new(2, 1, 0.5)
        lightPart.Anchored = true
        lightPart.CanCollide = false
        lightPart.Material = Enum.Material.Neon

        -- Random warm color
        local hue = math.random(20, 50) / 360  -- Warm yellows/oranges
        lightPart.Color = Color3.fromHSV(hue, 0.3, 1)

        -- Position on one wall (pick a random wall)
        local pos = layout.position
        local dims = layout.dims
        local wallOffset = math.random(1, 4)
        local lightPos

        if wallOffset == 1 then
            -- North wall
            lightPos = Vector3.new(pos[1], pos[2] + dims[2] * 0.3, pos[3] + dims[3] / 2 - 1.5)
        elseif wallOffset == 2 then
            -- South wall
            lightPos = Vector3.new(pos[1], pos[2] + dims[2] * 0.3, pos[3] - dims[3] / 2 + 1.5)
        elseif wallOffset == 3 then
            -- East wall
            lightPos = Vector3.new(pos[1] + dims[1] / 2 - 1.5, pos[2] + dims[2] * 0.3, pos[3])
        else
            -- West wall
            lightPos = Vector3.new(pos[1] - dims[1] / 2 + 1.5, pos[2] + dims[2] * 0.3, pos[3])
        end

        lightPart.Position = lightPos
        lightPart.Parent = container

        -- Add PointLight
        local pointLight = Instance.new("PointLight")
        pointLight.Color = lightPart.Color
        pointLight.Brightness = 1
        pointLight.Range = 20
        pointLight.Parent = lightPart
    end

    print("[AutoRun] Added lights to", #layouts, "rooms")
end

--------------------------------------------------------------------------------
-- SPAWN HANDLING
--------------------------------------------------------------------------------

function setSpawnToTopmostRoom(layouts)
    if #layouts == 0 then return end

    -- Find room with highest Y position
    local topRoom = layouts[1]
    for _, layout in ipairs(layouts) do
        if layout.position[2] > topRoom.position[2] then
            topRoom = layout
        end
    end

    -- Create or update spawn location
    if not spawnLocation then
        spawnLocation = Instance.new("SpawnLocation")
        spawnLocation.Name = "DungeonSpawn"
        spawnLocation.Size = Vector3.new(4, 1, 4)
        spawnLocation.Anchored = true
        spawnLocation.CanCollide = false
        spawnLocation.Transparency = 1
        spawnLocation.Neutral = true
        spawnLocation.Parent = workspace
    end

    -- Position spawn at floor level of topmost room
    local floorY = topRoom.position[2] - topRoom.dims[2] / 2 + 3
    spawnLocation.Position = Vector3.new(
        topRoom.position[1],
        floorY,
        topRoom.position[3]
    )

    print("[AutoRun] Spawn set to room", topRoom.id, "at Y =", floorY)
end

local function onPlayerRespawn(player)
    print("[AutoRun] Player respawned, generating new map...")
    task.wait(0.5)  -- Brief delay before regenerating
    generateMap()

    -- Teleport player to new spawn after map generates
    task.wait(1)
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        if spawnLocation then
            player.Character.HumanoidRootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
        end
    end
end

local function onPlayerAdded(player)
    player.CharacterAdded:Connect(function(character)
        -- First spawn generates the initial map
        if not currentDemo then
            generateMap()
            task.wait(1)
        end

        -- Subsequent spawns (respawns) generate new maps
        local humanoid = character:WaitForChild("Humanoid")
        humanoid.Died:Connect(function()
            onPlayerRespawn(player)
        end)
    end)
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

-- Connect player events
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in game (for Studio testing)
for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

print("[AutoRun] PathGraph demo ready - map generates on player spawn")
