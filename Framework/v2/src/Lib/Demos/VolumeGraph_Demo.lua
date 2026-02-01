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
    local roomContainers = {}  -- Map room ID to container
    local layouts = nil

    local baseUnit = config.baseUnit or 15
    local wallThickness = config.wallThickness or 1

    ---------------------------------------------------------------------------
    -- STAGE 1: GENERATE ROOM LAYOUTS
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] STAGE 1: Generating room layouts")
    print("==========================================")

    local volumeGraph = VolumeGraph:new({ id = "Demo_VolumeGraph" })
    volumeGraph.Sys.onInit(volumeGraph)

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

    -- Collect layouts from generation
    local generationComplete = false
    local vgOriginalFire = volumeGraph.Out.Fire
    volumeGraph.Out.Fire = function(outSelf, signal, data)
        if signal == "complete" then
            layouts = data.layouts
            generationComplete = true
            print(string.format("[Demo] Generated %d room layouts", #layouts))
        end
        vgOriginalFire(outSelf, signal, data)
    end

    local origin = config.origin or { 0, 80, 0 }
    volumeGraph.In.onGenerate(volumeGraph, { origin = origin })

    -- Wait for generation
    while not generationComplete do
        task.wait()
    end

    if not layouts or #layouts == 0 then
        warn("[Demo] No layouts generated!")
        return nil
    end

    ---------------------------------------------------------------------------
    -- STAGE 2: BUILD ROOM GEOMETRY
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] STAGE 2: Building room geometry")
    print("==========================================")

    for _, layout in ipairs(layouts) do
        print(string.format("[Demo] Building Room %d at (%.1f, %.1f, %.1f)",
            layout.id, layout.position[1], layout.position[2], layout.position[3]))

        -- Create blocking volume part
        local blockPart = Instance.new("Part")
        blockPart.Name = "Block_" .. layout.id
        blockPart.Size = Vector3.new(layout.dims[1], layout.dims[2], layout.dims[3])
        blockPart.Position = Vector3.new(layout.position[1], layout.position[2], layout.position[3])
        blockPart.Anchored = true
        blockPart.CanCollide = false
        blockPart.Transparency = 1
        blockPart.Parent = demoFolder

        -- Create Room node
        local roomId = "Room_" .. layout.id
        local room = Room:new({ id = roomId })
        room.Sys.onInit(room)

        room.In.onConfigure(room, {
            part = blockPart,
            wallThickness = wallThickness,
        })
        room.Sys.onStart(room)

        table.insert(rooms, room)
        roomContainers[layout.id] = room:getContainer()
    end

    print(string.format("[Demo] Built %d rooms", #rooms))
    task.wait(0.1)  -- Let geometry settle

    ---------------------------------------------------------------------------
    -- STAGE 3: CUT DOORWAYS
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] STAGE 3: Cutting doorways")
    print("==========================================")

    local doorwayCutter = DoorwayCutter:new({ id = "Demo_DoorwayCutter" })
    doorwayCutter.Sys.onInit(doorwayCutter)

    doorwayCutter.In.onConfigure(doorwayCutter, {
        baseUnit = config.doorBaseUnit or 5,
        wallThickness = wallThickness,
        doorHeight = config.doorHeight or 8,
        container = demoFolder,
    })

    -- Cut doorways (without ladders/poles for now)
    doorwayCutter.In.onRoomsComplete(doorwayCutter, {
        layouts = layouts,
    })

    task.wait(0.1)  -- Let CSG operations complete

    ---------------------------------------------------------------------------
    -- STAGE 4: ADD LIGHTS
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] STAGE 4: Adding lights")
    print("==========================================")

    Demo.addLights(demoFolder, layouts)

    ---------------------------------------------------------------------------
    -- STAGE 5: ADD CLIMBING AIDS (ladders/poles)
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] STAGE 5: Adding climbing aids")
    print("==========================================")

    Demo.addClimbingAids(demoFolder, layouts, wallThickness)

    ---------------------------------------------------------------------------
    -- STAGE 6: RELOCATE SPAWN POINT
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] STAGE 6: Relocating spawn point")
    print("==========================================")

    Demo.moveSpawnToFirstRoom(layouts)

    -- Disable baseplate
    local baseplate = workspace:FindFirstChild("Baseplate")
    if baseplate then
        baseplate.CanCollide = false
        baseplate.Transparency = 0.8
    end

    ---------------------------------------------------------------------------
    -- CLEANUP HANDLER
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] COMPLETE")
    print("==========================================")

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[Demo] Cleanup...")
            volumeGraph.Sys.onStop(volumeGraph)
            doorwayCutter.Sys.onStop(doorwayCutter)
            for _, room in ipairs(rooms) do
                room.Sys.onStop(room)
            end
        end
    end)

    return {
        volumeGraph = volumeGraph,
        doorwayCutter = doorwayCutter,
        rooms = rooms,
        layouts = layouts,
        folder = demoFolder,
    }
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function Demo.addLights(container, layouts)
    local lightCount = 0
    for _, layout in ipairs(layouts) do
        local lightPart = Instance.new("Part")
        lightPart.Name = "Light_" .. layout.id
        lightPart.Size = Vector3.new(2, 1, 0.5)
        lightPart.Anchored = true
        lightPart.CanCollide = false
        lightPart.Material = Enum.Material.Neon

        local hue = math.random(20, 50) / 360
        lightPart.Color = Color3.fromHSV(hue, 0.3, 1)

        local pos = layout.position
        local dims = layout.dims
        lightPart.Position = Vector3.new(
            pos[1] + math.random(-2, 2),
            pos[2] + dims[2] / 2 - 1.5,
            pos[3] + math.random(-2, 2)
        )
        lightPart.Parent = container

        local pointLight = Instance.new("PointLight")
        pointLight.Color = lightPart.Color
        pointLight.Brightness = 1
        pointLight.Range = math.max(dims[1], dims[3]) * 0.8
        pointLight.Parent = lightPart

        lightCount = lightCount + 1
    end
    print(string.format("[Demo] Added %d lights", lightCount))
end

function Demo.addClimbingAids(container, layouts, wallThickness)
    local ladderCount = 0
    local poleCount = 0

    -- Build room lookup
    local roomsById = {}
    for _, layout in ipairs(layouts) do
        roomsById[layout.id] = layout
    end

    -- Check each connection for height differences
    local processed = {}
    for _, layout in ipairs(layouts) do
        for _, connId in ipairs(layout.connections) do
            local key = layout.id < connId
                and (layout.id .. "_" .. connId)
                or (connId .. "_" .. layout.id)

            if not processed[key] then
                processed[key] = true

                local roomA = layout
                local roomB = roomsById[connId]

                if roomB then
                    local floorA = roomA.position[2] - roomA.dims[2] / 2
                    local floorB = roomB.position[2] - roomB.dims[2] / 2
                    local floorDiff = math.abs(floorA - floorB)

                    -- Find adjacency axis
                    local axis = nil
                    for a = 1, 3 do
                        local dist = math.abs(roomB.position[a] - roomA.position[a])
                        local touchDist = roomA.dims[a]/2 + roomB.dims[a]/2 + 2*wallThickness
                        if math.abs(dist - touchDist) < 1 then
                            axis = a
                            break
                        end
                    end

                    if axis == 2 then
                        -- Vertical connection (ceiling/floor) - add pole
                        local lowerFloor = math.min(floorA, floorB)
                        local higherCeiling = math.max(
                            roomA.position[2] + roomA.dims[2]/2,
                            roomB.position[2] + roomB.dims[2]/2
                        )
                        local poleHeight = higherCeiling - lowerFloor

                        -- Find door center (overlap area)
                        local doorX = (roomA.position[1] + roomB.position[1]) / 2
                        local doorZ = (roomA.position[3] + roomB.position[3]) / 2

                        local pole = Instance.new("TrussPart")
                        pole.Name = "Pole_" .. roomA.id .. "_" .. roomB.id
                        pole.Size = Vector3.new(2, poleHeight, 2)
                        pole.Position = Vector3.new(doorX - 3, lowerFloor + poleHeight/2, doorZ - 3)
                        pole.Anchored = true
                        pole.Material = Enum.Material.Metal
                        pole.Color = Color3.fromRGB(60, 60, 70)
                        pole.Parent = container
                        poleCount = poleCount + 1

                    elseif floorDiff >= 3 then
                        -- Horizontal connection with height difference - add ladders
                        local lowerFloor = math.min(floorA, floorB)
                        local higherFloor = math.max(floorA, floorB)
                        local ladderHeight = higherFloor - lowerFloor

                        -- Find door center
                        local doorX = (roomA.position[1] + roomB.position[1]) / 2
                        local doorZ = (roomA.position[3] + roomB.position[3]) / 2

                        -- Add ladder on both sides
                        for _, offset in ipairs({ -1.5, 1.5 }) do
                            local ladderPos
                            if axis == 1 then  -- X wall
                                ladderPos = Vector3.new(doorX + offset, lowerFloor + ladderHeight/2, doorZ)
                            else  -- Z wall
                                ladderPos = Vector3.new(doorX, lowerFloor + ladderHeight/2, doorZ + offset)
                            end

                            local ladder = Instance.new("TrussPart")
                            ladder.Name = "Ladder_" .. roomA.id .. "_" .. roomB.id
                            ladder.Size = Vector3.new(2, ladderHeight, 2)
                            ladder.Position = ladderPos
                            ladder.Anchored = true
                            ladder.Material = Enum.Material.Metal
                            ladder.Color = Color3.fromRGB(80, 80, 80)
                            ladder.Parent = container
                            ladderCount = ladderCount + 1
                        end
                    end
                end
            end
        end
    end

    print(string.format("[Demo] Added %d ladders, %d poles", ladderCount, poleCount))
end

function Demo.moveSpawnToFirstRoom(layouts)
    if not layouts or #layouts == 0 then
        warn("[Demo] No layouts for spawn relocation!")
        return
    end

    local firstRoom = layouts[1]
    local pos = firstRoom.position
    local dims = firstRoom.dims

    local spawnPos = Vector3.new(
        pos[1],
        pos[2] - dims[2] / 2 + 3,
        pos[3]
    )

    local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")

    if spawnLocation then
        spawnLocation.Position = spawnPos
        spawnLocation.Anchored = true
        print("[Demo] Moved SpawnLocation to first room at", spawnPos)
    else
        spawnLocation = Instance.new("SpawnLocation")
        spawnLocation.Name = "SpawnLocation"
        spawnLocation.Size = Vector3.new(6, 1, 6)
        spawnLocation.Position = spawnPos
        spawnLocation.Anchored = true
        spawnLocation.CanCollide = true
        spawnLocation.Material = Enum.Material.SmoothPlastic
        spawnLocation.Color = Color3.fromRGB(100, 100, 100)
        spawnLocation.Parent = workspace
        print("[Demo] Created SpawnLocation in first room at", spawnPos)
    end
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

return Demo
