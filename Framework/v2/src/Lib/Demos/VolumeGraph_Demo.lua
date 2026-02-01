--[[
    LibPureFiction Framework v2
    VolumeGraph_Demo.lua - Volume-First Dungeon Generator Demo

    Usage:
    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    Demos.VolumeGraph.run()

    -- With specific strategy
    Demos.VolumeGraph.run({ strategy = "BSP" })
    Demos.VolumeGraph.run({ strategy = "Grid" })
    Demos.VolumeGraph.run({ strategy = "Organic" })
    Demos.VolumeGraph.run({ strategy = "Radial" })
    Demos.VolumeGraph.run({ strategy = "Poisson" })
    ```
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Demo = {}

function Demo.run(config)
    config = config or {}

    ---------------------------------------------------------------------------
    -- CLEANUP
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("VolumeGraph_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end
    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "VolumeGraph_Demo"
    demoFolder.Parent = workspace

    local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
    local VolumeGraph = Lib.Components.VolumeGraph
    local Room = Lib.Components.Room
    local DoorwayCutter = Lib.Components.DoorwayCutter

    local rooms = {}
    local doorwayCutter = nil

    ---------------------------------------------------------------------------
    -- CREATE VOLUMEGRAPH
    ---------------------------------------------------------------------------

    local volumeGraph = VolumeGraph:new({ id = "Demo_VolumeGraph" })
    volumeGraph.Sys.onInit(volumeGraph)

    local baseUnit = config.baseUnit or 15
    local wallThickness = config.wallThickness or 1

    -- Build config
    local graphConfig = {
        baseUnit = baseUnit,
        wallThickness = wallThickness,
        seed = config.seed,
        strategy = config.strategy or "Poisson",
        strategyConfig = config.strategyConfig or {
            bounds = { x = 250, y = 60, z = 250 },
            scaleRange = { min = 2, max = 5, minY = 2, maxY = 4 },
        },
        connectionMethod = config.connectionMethod or "MST",
        maxConnections = config.maxConnections or 4,
        minDoorSize = config.minDoorSize or 4,
    }

    volumeGraph.In.onConfigure(volumeGraph, graphConfig)

    ---------------------------------------------------------------------------
    -- CREATE DOORWAY CUTTER
    ---------------------------------------------------------------------------

    doorwayCutter = DoorwayCutter:new({ id = "Demo_DoorwayCutter" })
    doorwayCutter.Sys.onInit(doorwayCutter)

    doorwayCutter.In.onConfigure(doorwayCutter, {
        baseUnit = config.doorBaseUnit or 5,
        wallThickness = wallThickness,
        doorHeight = config.doorHeight or 8,
        container = demoFolder,
    })

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS
    ---------------------------------------------------------------------------

    local vgOriginalFire = volumeGraph.Out.Fire
    volumeGraph.Out.Fire = function(outSelf, signal, data)
        if signal == "roomLayout" then
            print(string.format("[Demo] Room %d at (%.1f, %.1f, %.1f) dims (%.1f, %.1f, %.1f)",
                data.id, data.position[1], data.position[2], data.position[3],
                data.dims[1], data.dims[2], data.dims[3]))

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

            room.In.onConfigure(room, {
                part = blockPart,
                wallThickness = wallThickness,
            })
            room.Sys.onStart(room)
            table.insert(rooms, room)

        elseif signal == "complete" then
            print("==========================================")
            print("[Demo] GENERATION COMPLETE")
            print("  Seed:", data.seed)
            print("  Total Rooms:", data.totalRooms)
            print("==========================================")

            -- Draw connections
            if config.showDebug then
                Demo.drawConnections(data.layouts, demoFolder)
            end

            -- Trigger doorway cutting after rooms are built
            print("[Demo] Cutting doorways...")
            doorwayCutter.In.onRoomsComplete(doorwayCutter, {
                layouts = data.layouts,
            })

            -- Add lights to rooms
            Demo.addLights(demoFolder, data.layouts)
        end

        vgOriginalFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- START GENERATION
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] Starting VolumeGraph generation")
    print("  Strategy:", graphConfig.strategy)
    print("  BaseUnit:", baseUnit)
    print("==========================================")

    local origin = config.origin or { 0, 80, 0 }

    -- Disable baseplate collision
    local baseplate = workspace:FindFirstChild("Baseplate")
    if baseplate then
        baseplate.CanCollide = false
        baseplate.Transparency = 0.8
    end

    volumeGraph.In.onGenerate(volumeGraph, {
        origin = origin,
    })

    ---------------------------------------------------------------------------
    -- CLEANUP HANDLER
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[Demo] Cleanup...")
            volumeGraph.Sys.onStop(volumeGraph)
            if doorwayCutter then
                doorwayCutter.Sys.onStop(doorwayCutter)
            end
            for _, room in ipairs(rooms) do
                room.Sys.onStop(room)
            end
        end
    end)

    return {
        volumeGraph = volumeGraph,
        doorwayCutter = doorwayCutter,
        rooms = rooms,
        folder = demoFolder,
    }
end

function Demo.drawConnections(layouts, container)
    local roomsById = {}
    for _, layout in ipairs(layouts) do
        roomsById[layout.id] = layout
    end

    local drawn = {}

    for _, layout in ipairs(layouts) do
        for _, connId in ipairs(layout.connections) do
            local key = layout.id < connId and (layout.id .. "_" .. connId) or (connId .. "_" .. layout.id)

            if not drawn[key] then
                drawn[key] = true

                local connLayout = roomsById[connId]
                if connLayout then
                    local fromVec = Vector3.new(layout.position[1], layout.position[2], layout.position[3])
                    local toVec = Vector3.new(connLayout.position[1], connLayout.position[2], connLayout.position[3])

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

        -- Position on ceiling
        local pos = layout.position
        local dims = layout.dims
        local lightPos = Vector3.new(
            pos[1] + math.random(-2, 2),
            pos[2] + dims[2] / 2 - 1.5,
            pos[3] + math.random(-2, 2)
        )

        lightPart.Position = lightPos
        lightPart.Parent = container

        local pointLight = Instance.new("PointLight")
        pointLight.Color = lightPart.Color
        pointLight.Brightness = 1
        pointLight.Range = math.max(dims[1], dims[3]) * 0.8
        pointLight.Parent = lightPart
    end
end

return Demo
