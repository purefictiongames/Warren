--[[
    Warren Framework v2
    DungeonGeneration_Demo.lua - Sequential Dungeon Generation Demo

    Demonstrates the sequential dungeon generation system:
    - DungeonOrchestrator owns all planning
    - VolumeBuilder places volumes one at a time
    - ShellBuilder builds walls around each volume
    - DoorCutter connects rooms with doorways

    Usage:
    ```lua
    local Demos = require(game.ReplicatedStorage.Warren.Demos)
    Demos.DungeonGeneration.run()
    ```
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Demo = {}

function Demo.run(config)
    config = config or {}

    ---------------------------------------------------------------------------
    -- CLEANUP
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("DungeonGeneration_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end
    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "DungeonGeneration_Demo"
    demoFolder.Parent = workspace

    local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
    local DungeonOrchestrator = Lib.Components.DungeonOrchestrator

    ---------------------------------------------------------------------------
    -- CONFIGURATION
    ---------------------------------------------------------------------------

    local seed = config.seed or os.time()
    local baseUnit = config.baseUnit or 5
    local wallThickness = config.wallThickness or 1
    local mainPathLength = config.mainPathLength or 6
    local spurCount = config.spurCount or 3
    local loopCount = config.loopCount or 0

    print("==========================================")
    print("[DungeonGeneration_Demo] Starting...")
    print(string.format("  Seed: %d", seed))
    print(string.format("  Main Path: %d rooms", mainPathLength))
    print(string.format("  Spurs: %d rooms", spurCount))
    print(string.format("  Loops: %d", loopCount))
    print("==========================================")

    ---------------------------------------------------------------------------
    -- CREATE ORCHESTRATOR
    ---------------------------------------------------------------------------

    local orchestrator = DungeonOrchestrator:new({
        id = "Demo_Orchestrator",
    })
    orchestrator.Sys.onInit(orchestrator)

    -- Track progress
    local roomsBuilt = 0
    local doorsCreated = 0
    local startTime = os.clock()

    -- Wire output signals
    local originalFire = orchestrator.Out.Fire
    orchestrator.Out.Fire = function(outSelf, signal, data)
        if signal == "phaseStarted" then
            print(string.format("[Demo] Phase: %s", data.phase))
        elseif signal == "roomBuilt" then
            roomsBuilt = roomsBuilt + 1
            print(string.format("[Demo] Room %d built (%s) at (%.1f, %.1f, %.1f)",
                data.roomId, data.pathType,
                data.position[1], data.position[2], data.position[3]))
        elseif signal == "doorCut" then
            doorsCreated = doorsCreated + 1
            print(string.format("[Demo] Door: %d <-> %d",
                data.fromRoomId, data.toRoomId))
        elseif signal == "complete" then
            local elapsed = os.clock() - startTime
            local trussCount = orchestrator:getTrussBuilder():getTrussCount()
            print("==========================================")
            print(string.format("[Demo] COMPLETE!"))
            print(string.format("  Rooms: %d", data.totalRooms))
            print(string.format("  Doors: %d", data.totalDoors))
            print(string.format("  Trusses: %d", trussCount))
            print(string.format("  Time: %.2f seconds", elapsed))
            print("==========================================")
        elseif signal == "generationFailed" then
            warn("[Demo] Generation failed: " .. tostring(data.reason))
        end
        originalFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- CONFIGURE AND GENERATE
    ---------------------------------------------------------------------------

    -- Create container in demo folder
    local dungeonContainer = Instance.new("Model")
    dungeonContainer.Name = "Dungeon"
    dungeonContainer.Parent = demoFolder

    -- Configure orchestrator (minDoorSize=6, doorHeight=10 are defaults)
    orchestrator.In.onConfigure(orchestrator, {
        seed = seed,
        baseUnit = baseUnit,
        wallThickness = wallThickness,
        mainPathLength = mainPathLength,
        spurCount = spurCount,
        loopCount = loopCount,
        scaleRange = {
            min = 4,
            max = 12,
            minY = 4,
            maxY = 8,
        },
        material = Enum.Material.Brick,
        color = Color3.fromRGB(140, 110, 90),
        container = dungeonContainer,
    })

    -- Start generation at origin
    local origin = { 0, baseUnit * 2, 0 }  -- Slightly above ground
    orchestrator.In.onGenerate(orchestrator, {
        origin = origin,
    })

    ---------------------------------------------------------------------------
    -- ADD LIGHTING
    ---------------------------------------------------------------------------

    -- Add neon light sources to each room as they're built
    local lightConnection
    lightConnection = orchestrator.Out.Fire
    local baseOriginalFire = orchestrator.Out.Fire
    orchestrator.Out.Fire = function(outSelf, signal, data)
        baseOriginalFire(outSelf, signal, data)

        if signal == "roomBuilt" then
            -- Add a neon light fixture to this room
            task.defer(function()
                local shell = orchestrator:getShellBuilder():getShell(data.roomId)
                if shell and shell.zonePart then
                    -- Create neon light fixture on ceiling
                    local lightSize = math.min(data.dims[1], data.dims[3]) * 0.3
                    local neonLight = Instance.new("Part")
                    neonLight.Name = "NeonLight"
                    neonLight.Size = Vector3.new(lightSize, 0.5, lightSize)
                    neonLight.Position = Vector3.new(
                        data.position[1],
                        data.position[2] + data.dims[2] / 2 - 0.5,  -- Just below ceiling
                        data.position[3]
                    )
                    neonLight.Anchored = true
                    neonLight.CanCollide = false
                    neonLight.Material = Enum.Material.Neon
                    neonLight.Color = Color3.fromRGB(255, 250, 240)
                    neonLight.Parent = shell.container

                    -- Add point light for actual illumination
                    local light = Instance.new("PointLight")
                    light.Name = "RoomLight"
                    light.Brightness = 2
                    light.Range = math.max(data.dims[1], data.dims[2], data.dims[3]) * 2
                    light.Color = Color3.fromRGB(255, 250, 240)
                    light.Parent = neonLight
                end
            end)
        elseif signal == "complete" then
            -- Delete the baseplate after dungeon is complete
            task.defer(function()
                local baseplate = workspace:FindFirstChild("Baseplate")
                if baseplate then
                    baseplate:Destroy()
                    print("[Demo] Baseplate removed")
                end
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- CLEANUP HANDLER
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[DungeonGeneration_Demo] Cleanup...")
            orchestrator.Sys.onStop(orchestrator)
        end
    end)

    return {
        orchestrator = orchestrator,
        folder = demoFolder,
        container = dungeonContainer,
        config = {
            seed = seed,
            baseUnit = baseUnit,
            wallThickness = wallThickness,
            mainPathLength = mainPathLength,
            spurCount = spurCount,
            loopCount = loopCount,
        },
    }
end

return Demo
