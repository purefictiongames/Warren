--[[
    LibPureFiction Framework v2
    VolumeGraph_Demo.lua - Volume-First Dungeon Generator Demo

    Usage:
    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    Demos.VolumeGraph.run()
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
    local finalLayouts = nil

    local baseUnit = config.baseUnit or 15
    local wallThickness = config.wallThickness or 1

    ---------------------------------------------------------------------------
    -- CREATE VOLUMEGRAPH
    ---------------------------------------------------------------------------

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
            blockPart.CanCollide = false
            blockPart.Transparency = 1
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

            finalLayouts = data.layouts

            -- Cut doorways
            print("[Demo] Cutting doorways...")
            doorwayCutter.In.onRoomsComplete(doorwayCutter, {
                layouts = data.layouts,
            })

            -- Add lights
            print("[Demo] Adding lights...")
            Demo.addLights(demoFolder, data.layouts)

            -- Add climbing aids
            print("[Demo] Adding climbing aids...")
            Demo.addClimbingAids(demoFolder, data.layouts, wallThickness)

            -- Move spawn
            print("[Demo] Moving spawn point...")
            Demo.moveSpawnToFirstRoom(data.layouts)
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

    -- Disable baseplate
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
        layouts = finalLayouts,
        folder = demoFolder,
    }
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function Demo.addLights(container, layouts)
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
    end
end

function Demo.addClimbingAids(container, layouts, wallThickness)
    local roomsById = {}
    for _, layout in ipairs(layouts) do
        roomsById[layout.id] = layout
    end

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

                    local doorX = (roomA.position[1] + roomB.position[1]) / 2
                    local doorZ = (roomA.position[3] + roomB.position[3]) / 2

                    if axis == 2 then
                        -- Vertical connection - add pole
                        local lowerFloor = math.min(floorA, floorB)
                        local higherCeiling = math.max(
                            roomA.position[2] + roomA.dims[2]/2,
                            roomB.position[2] + roomB.dims[2]/2
                        )
                        local poleHeight = higherCeiling - lowerFloor

                        local pole = Instance.new("TrussPart")
                        pole.Name = "Pole_" .. roomA.id .. "_" .. roomB.id
                        pole.Size = Vector3.new(2, poleHeight, 2)
                        pole.Position = Vector3.new(doorX - 3, lowerFloor + poleHeight/2, doorZ - 3)
                        pole.Anchored = true
                        pole.Material = Enum.Material.Metal
                        pole.Color = Color3.fromRGB(60, 60, 70)
                        pole.Parent = container

                    elseif axis and math.abs(floorA - floorB) >= 3 then
                        -- Horizontal with height diff - add ladders on both sides
                        local lowerFloor = math.min(floorA, floorB)
                        local higherFloor = math.max(floorA, floorB)
                        local ladderHeight = higherFloor - lowerFloor

                        for _, offset in ipairs({ -1.5, 1.5 }) do
                            local ladderPos
                            if axis == 1 then
                                ladderPos = Vector3.new(doorX + offset, lowerFloor + ladderHeight/2, doorZ)
                            else
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
                        end
                    end
                end
            end
        end
    end
end

function Demo.moveSpawnToFirstRoom(layouts)
    if not layouts or #layouts == 0 then return end

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
        print("[Demo] Moved SpawnLocation to", spawnPos)
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
        print("[Demo] Created SpawnLocation at", spawnPos)
    end
end

return Demo
