--[[
    LibPureFiction Framework v2
    PathGraph_Demo.lua - Visual Path Graph + Room Blocker Demonstration

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Demonstrates PathGraph procedural maze generation with RoomBlocker geometry.

    Features:
    - Generates a random maze path with spurs and loops
    - Visualizes segments as neon beams color-coded by direction
    - Marks junctions, dead ends, start, and goal points
    - Creates room/hallway floor blocks via RoomBlocker
    - Displays stats and legend

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    Demos.PathGraph.run()

    -- With custom config:
    Demos.PathGraph.run({
        position = Vector3.new(0, 10, 0),
        baseUnit = 20,
        maxSegments = 80,
        spurCount = { min = 5, max = 10 },
        loopCount = { min = 2, max = 4 },
        -- RoomBlocker options:
        hallScale = 1,      -- Hallway width multiplier
        heightScale = 2,    -- Room height multiplier
        roomScale = 1.5,    -- Dead-end room size
        junctionScale = 2,  -- Junction room size
    })
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local PathGraphDemoOrchestrator = Lib.Components.PathGraphDemoOrchestrator

local Demo = {}

function Demo.run(config)
    config = config or {}

    local position = config.position or Vector3.new(0, 5, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP ALL OLD DEMOS
    ---------------------------------------------------------------------------

    local demosToClean = {
        "Swivel_Demo",
        "Turret_Demo",
        "Launcher_Demo",
        "Targeter_Demo",
        "ShootingGallery_Demo",
        "Conveyor_Demo",
        "Combat_Demo",
        "PathGraph_Demo",
    }

    for _, demoName in ipairs(demosToClean) do
        local existing = workspace:FindFirstChild(demoName)
        if existing then
            existing:Destroy()
        end
    end

    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- CREATE DEMO FOLDER
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "PathGraph_Demo"
    demoFolder.Parent = workspace

    ---------------------------------------------------------------------------
    -- CREATE ORCHESTRATOR
    ---------------------------------------------------------------------------

    local orchestrator = PathGraphDemoOrchestrator:new({
        id = "Demo_PathGraphOrchestrator",
        attributes = {
            visualFolder = demoFolder,
            origin = position,
            showPathLines = config.showPathLines ~= false,
            showRoomBlocks = config.showRoomBlocks ~= false,
        },
    })

    ---------------------------------------------------------------------------
    -- SUBSCRIBE TO SIGNALS
    ---------------------------------------------------------------------------

    local originalOutFire = orchestrator.Out.Fire
    orchestrator.Out.Fire = function(outSelf, signal, data)
        if signal == "pathReceived" then
            print("=== PATH + GEOMETRY GENERATED ===")
            print("  Seed:", data.seed)
            if data.baseUnit then
                print("  Base Unit:", data.baseUnit)
                print("  Rooms:", data.roomCount)
                print("  Hallways:", data.hallwayCount)
            end
        elseif signal == "generationComplete" then
            print("  Total Points:", data.totalPoints)
            print("  Total Segments:", data.totalSegments)
            print("=================================")
        end
        originalOutFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- INITIALIZE AND START
    ---------------------------------------------------------------------------

    orchestrator.Sys.onInit(orchestrator)
    orchestrator.Sys.onStart(orchestrator)

    ---------------------------------------------------------------------------
    -- CONFIGURE
    ---------------------------------------------------------------------------

    print("=== PATHGRAPH + ROOMBLOCKER DEMO ===")
    print("Generating procedural maze with room geometry...")
    print("")

    orchestrator.In.onConfigure(orchestrator, {
        -- PathGraph config
        baseUnit = config.baseUnit or 15,
        seed = config.seed,
        spurCount = config.spurCount or { min = 4, max = 8 },
        loopCount = config.loopCount or { min = 2, max = 4 },
        switchbackChance = config.switchbackChance or 0.25,
        maxSegments = config.maxSegments or 60,
        bounds = config.bounds or {
            x = { -200, 200 },
            y = { 0, 60 },
            z = { -200, 200 },
        },
        mode = "bulk",

        -- RoomBlocker config
        hallScale = config.hallScale or 1,
        heightScale = config.heightScale or 2,
        roomScale = config.roomScale or 1.5,
        junctionScale = config.junctionScale or 2,
    })

    ---------------------------------------------------------------------------
    -- GENERATE PATH
    ---------------------------------------------------------------------------

    orchestrator.In.onGenerate(orchestrator, {
        start = { 0, 0, 0 },
        goals = config.goals or { { 150, 0, 150 } },
    })

    ---------------------------------------------------------------------------
    -- CLEANUP HANDLER
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[PathGraph Demo] Cleanup...")
            orchestrator.Sys.onStop(orchestrator)
        end
    end)

    ---------------------------------------------------------------------------
    -- RETURN ORCHESTRATOR FOR INTERACTION
    ---------------------------------------------------------------------------

    return orchestrator
end

--[[
    Regenerate with new seed (keeps same config).
--]]
function Demo.regenerate(orchestrator, newSeed)
    if not orchestrator then
        print("[PathGraph Demo] No orchestrator. Run Demo.run() first.")
        return
    end

    -- Clear and regenerate
    orchestrator.In.onClear(orchestrator)

    if newSeed then
        orchestrator.In.onConfigure(orchestrator, { seed = newSeed })
    end

    orchestrator.In.onGenerate(orchestrator, {
        start = { 0, 0, 0 },
        goals = { { 150, 0, 150 } },
    })
end

return Demo
