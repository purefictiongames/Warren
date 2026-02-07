--[[
    Warren Framework v2
    PathGraph_Demo.lua - Path + Room Volume Demo

    Usage:
    ```lua
    local Demos = require(game.ReplicatedStorage.Warren.Demos)
    Demos.PathGraph.run()
    ```
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Demo = {}

function Demo.run(config)
    config = config or {}

    ---------------------------------------------------------------------------
    -- CLEANUP
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("PathGraph_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end
    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "PathGraph_Demo"
    demoFolder.Parent = workspace

    local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
    local PathGraph = Lib.Components.PathGraph
    local Room = Lib.Components.Room
    local DoorwayCutter = Lib.Components.DoorwayCutter

    local rooms = {}
    local doorwayCutter = nil

    ---------------------------------------------------------------------------
    -- CREATE PATHGRAPH
    ---------------------------------------------------------------------------

    local pathGraph = PathGraph:new({ id = "Demo_PathGraph" })
    pathGraph.Sys.onInit(pathGraph)

    local baseUnit = config.baseUnit or 15

    local seed = config.seed
    if not seed then
        local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        seed = ""
        for _ = 1, 12 do
            local idx = math.random(1, #chars)
            seed = seed .. chars:sub(idx, idx)
        end
    end

    -- Apply preset if specified, then override with config
    local graphConfig = {}

    if config.preset and PathGraph.Presets[config.preset] then
        print("[Demo] Using preset:", config.preset)
        for k, v in pairs(PathGraph.Presets[config.preset]) do
            graphConfig[k] = v
        end
    end

    -- Apply explicit config (overrides preset)
    graphConfig.baseUnit = config.baseUnit or graphConfig.baseUnit or baseUnit
    graphConfig.seed = seed
    graphConfig.spurCount = config.spurCount or graphConfig.spurCount or { min = 2, max = 4 }
    graphConfig.maxSegmentsPerPath = config.maxSegments or graphConfig.maxSegmentsPerPath or 8
    graphConfig.sizeRange = config.sizeRange or graphConfig.sizeRange or { 1.2, 2.5 }
    graphConfig.scanDistance = config.scanDistance or graphConfig.scanDistance or 5
    graphConfig.verticalChance = config.verticalChance or graphConfig.verticalChance
    graphConfig.straightness = config.straightness or graphConfig.straightness
    graphConfig.goalBias = config.goalBias or graphConfig.goalBias
    graphConfig.heightScale = config.heightScale or graphConfig.heightScale
    graphConfig.aspectRatio = config.aspectRatio or graphConfig.aspectRatio
    graphConfig.allowUp = config.allowUp
    graphConfig.allowDown = config.allowDown

    pathGraph.In.onConfigure(pathGraph, graphConfig)

    ---------------------------------------------------------------------------
    -- CREATE DOORWAY CUTTER
    ---------------------------------------------------------------------------

    doorwayCutter = DoorwayCutter:new({ id = "Demo_DoorwayCutter" })
    doorwayCutter.Sys.onInit(doorwayCutter)

    doorwayCutter.In.onConfigure(doorwayCutter, {
        baseUnit = config.doorBaseUnit or 5,
        wallThickness = config.wallThickness or 1,
        doorHeight = config.doorHeight or 8,
        container = demoFolder,
    })

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS
    ---------------------------------------------------------------------------

    local pgOriginalFire = pathGraph.Out.Fire
    pathGraph.Out.Fire = function(outSelf, signal, data)
        if signal == "roomLayout" then
            print(string.format("[Demo] Room %d defined at (%.1f, %.1f, %.1f)",
                data.id, data.position[1], data.position[2], data.position[3]))

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

            -- Create Room node from the blocking volume
            local roomId = "Room_" .. data.id
            local room = Room:new({ id = roomId })
            room.Sys.onInit(room)

            local roomOriginalFire = room.Out.Fire
            room.Out.Fire = function(roomOutSelf, roomSignal, roomData)
                if roomSignal == "ready" then
                    print(string.format("[Demo] %s ready", roomId))
                end
                roomOriginalFire(roomOutSelf, roomSignal, roomData)
            end

            room.In.onConfigure(room, {
                part = blockPart,
                wallThickness = config.wallThickness or 1,
            })
            room.Sys.onStart(room)
            table.insert(rooms, room)

        elseif signal == "pathComplete" then
            print(string.format("[Demo] Path %d complete", data.pathIndex))

        elseif signal == "complete" then
            print("==========================================")
            print("[Demo] GENERATION COMPLETE")
            print("  Seed:", data.seed)
            print("  Total Rooms:", data.totalRooms)
            print("==========================================")

            -- Draw connections between rooms (hidden by default for gameplay)
            if config.showDebug then
                Demo.drawConnections(pathGraph, demoFolder)
            end

            -- Trigger doorway cutting after rooms are built
            print("[Demo] Cutting doorways...")
            doorwayCutter.In.onRoomsComplete(doorwayCutter, {
                layouts = data.layouts,
            })

            -- Add lights to rooms
            Demo.addLights(demoFolder, data.layouts)
        end

        pgOriginalFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- START GENERATION
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] Starting generation")
    print("  Seed:", seed)
    print("  BaseUnit:", baseUnit)
    print("==========================================")

    -- Start high enough that downward paths don't go below baseplate
    local origin = config.position or Vector3.new(0, 80, 0)

    -- Disable baseplate collision so underground rooms are accessible
    local baseplate = workspace:FindFirstChild("Baseplate")
    if baseplate then
        baseplate.CanCollide = false
        baseplate.Transparency = 0.8
    end

    pathGraph.In.onGenerate(pathGraph, {
        start = { origin.X, origin.Y, origin.Z },
        goals = config.goals or { { origin.X + 120, origin.Y, origin.Z + 120 } },
    })

    ---------------------------------------------------------------------------
    -- CLEANUP HANDLER
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[Demo] Cleanup...")
            pathGraph.Sys.onStop(pathGraph)
            if doorwayCutter then
                doorwayCutter.Sys.onStop(doorwayCutter)
            end
            for _, room in ipairs(rooms) do
                room.Sys.onStop(room)
            end
        end
    end)

    return {
        pathGraph = pathGraph,
        doorwayCutter = doorwayCutter,
        rooms = rooms,
        folder = demoFolder,
    }
end

function Demo.drawConnections(pathGraph, container)
    local roomData = pathGraph:getRooms()
    if not roomData then return end

    local drawn = {}

    for roomId, room in pairs(roomData) do
        for _, connId in ipairs(room.connections) do
            -- Create unique key to avoid drawing twice
            local key = roomId < connId and (roomId .. "_" .. connId) or (connId .. "_" .. roomId)

            if not drawn[key] then
                drawn[key] = true

                local connRoom = roomData[connId]
                if connRoom then
                    local fromVec = Vector3.new(room.position[1], room.position[2], room.position[3])
                    local toVec = Vector3.new(connRoom.position[1], connRoom.position[2], connRoom.position[3])

                    local midpoint = (fromVec + toVec) / 2
                    local length = (toVec - fromVec).Magnitude

                    if length > 0.1 then
                        local beam = Instance.new("Part")
                        beam.Name = "Connection_" .. key
                        beam.Size = Vector3.new(0.5, 0.5, length)
                        beam.CFrame = CFrame.lookAt(midpoint, toVec)
                        beam.Anchored = true
                        beam.CanCollide = false
                        beam.Material = Enum.Material.Neon
                        beam.Color = Color3.fromRGB(0, 255, 150)
                        beam.Parent = container
                    end
                end
            end
        end
    end

    -- Draw room center markers
    for roomId, room in pairs(roomData) do
        local worldPos = Vector3.new(room.position[1], room.position[2], room.position[3])

        local sphere = Instance.new("Part")
        sphere.Name = "Center_" .. roomId
        sphere.Shape = Enum.PartType.Ball
        sphere.Size = Vector3.new(1.5, 1.5, 1.5)
        sphere.Position = worldPos
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.Material = Enum.Material.Neon

        if roomId == 1 then
            sphere.Color = Color3.fromRGB(0, 255, 0) -- Start room
            sphere.Size = Vector3.new(2.5, 2.5, 2.5)
        elseif #room.connections >= 3 then
            sphere.Color = Color3.fromRGB(255, 255, 255) -- Junction
        elseif #room.connections == 1 then
            sphere.Color = Color3.fromRGB(255, 100, 100) -- Dead end
        else
            sphere.Color = Color3.fromRGB(150, 150, 200) -- Normal
        end

        sphere.Parent = container
    end
end

function Demo.addLights(container, layouts)
    for _, layout in ipairs(layouts) do
        local lightPart = Instance.new("Part")
        lightPart.Name = "Light_" .. layout.id
        lightPart.Size = Vector3.new(2, 1, 0.5)
        lightPart.Anchored = true
        lightPart.CanCollide = false
        lightPart.Material = Enum.Material.Neon

        -- Random warm color
        local hue = math.random(20, 50) / 360
        lightPart.Color = Color3.fromHSV(hue, 0.3, 1)

        -- Position on one wall
        local pos = layout.position
        local dims = layout.dims
        local wallOffset = math.random(1, 4)
        local lightPos

        if wallOffset == 1 then
            lightPos = Vector3.new(pos[1], pos[2] + dims[2] * 0.3, pos[3] + dims[3] / 2 - 1.5)
        elseif wallOffset == 2 then
            lightPos = Vector3.new(pos[1], pos[2] + dims[2] * 0.3, pos[3] - dims[3] / 2 + 1.5)
        elseif wallOffset == 3 then
            lightPos = Vector3.new(pos[1] + dims[1] / 2 - 1.5, pos[2] + dims[2] * 0.3, pos[3])
        else
            lightPos = Vector3.new(pos[1] - dims[1] / 2 + 1.5, pos[2] + dims[2] * 0.3, pos[3])
        end

        lightPart.Position = lightPos
        lightPart.Parent = container

        local pointLight = Instance.new("PointLight")
        pointLight.Color = lightPart.Color
        pointLight.Brightness = 1
        pointLight.Range = 20
        pointLight.Parent = lightPart
    end
end

return Demo
