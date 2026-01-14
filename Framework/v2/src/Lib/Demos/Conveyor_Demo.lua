--[[
    LibPureFiction Framework v2
    Conveyor System Demo - Fully Automated Showcase

    Demonstrates Dropper + PathFollower + NodePool integration in a tycoon-style system.
    Items spawn, travel along a path, and get collected at the end.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Conveyor.run()
    -- Sit back and watch the automated demo!

    -- To stop early:
    demo.cleanup()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local Dropper = Lib.Components.Dropper
local PathFollower = Lib.Components.PathFollower
local NodePool = Lib.Components.NodePool

local SpawnerCore = require(ReplicatedStorage.Lib.Internal.SpawnerCore)

local Demo = {}

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 5, 0)

    ---------------------------------------------------------------------------
    -- ANNOUNCEMENT SYSTEM
    ---------------------------------------------------------------------------

    local function announce(text)
        print("[DEMO] " .. text)
    end

    ---------------------------------------------------------------------------
    -- CREATE ITEM TEMPLATES
    ---------------------------------------------------------------------------

    local templateFolder = ReplicatedStorage:FindFirstChild("Templates")
    if not templateFolder then
        templateFolder = Instance.new("Folder")
        templateFolder.Name = "Templates"
        templateFolder.Parent = ReplicatedStorage
    end

    -- Create colorful crate templates
    local crateColors = {
        { name = "RedCrate", color = Color3.new(1, 0.2, 0.2), brick = "Bright red" },
        { name = "BlueCrate", color = Color3.new(0.2, 0.4, 1), brick = "Bright blue" },
        { name = "GreenCrate", color = Color3.new(0.2, 1, 0.3), brick = "Bright green" },
        { name = "YellowCrate", color = Color3.new(1, 0.9, 0.2), brick = "Bright yellow" },
        { name = "PurpleCrate", color = Color3.new(0.7, 0.2, 1), brick = "Bright violet" },
    }

    for _, crateInfo in ipairs(crateColors) do
        local existing = templateFolder:FindFirstChild(crateInfo.name)
        if existing then existing:Destroy() end

        local crate = Instance.new("Part")
        crate.Name = crateInfo.name
        crate.Size = Vector3.new(3, 3, 3)
        crate.Color = crateInfo.color
        crate.BrickColor = BrickColor.new(crateInfo.brick)
        crate.Material = Enum.Material.SmoothPlastic
        crate.Anchored = true
        crate.CanCollide = false
        crate.CastShadow = true
        crate.Parent = templateFolder

        -- Add a subtle glow
        local light = Instance.new("PointLight")
        light.Color = crateInfo.color
        light.Brightness = 0.5
        light.Range = 6
        light.Parent = crate
    end

    if not SpawnerCore.isInitialized() then
        SpawnerCore.init({ templates = templateFolder })
    end

    ---------------------------------------------------------------------------
    -- CREATE VISUAL SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "Conveyor_Demo"
    demoFolder.Parent = workspace

    -- Ground plane
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(150, 1, 150)
    ground.Position = Vector3.new(0, -1, 0)
    ground.Anchored = true
    ground.BrickColor = BrickColor.new("Dark stone grey")
    ground.Material = Enum.Material.Slate
    ground.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- CREATE WAYPOINT PATH (S-curve conveyor)
    ---------------------------------------------------------------------------

    local waypointFolder = Instance.new("Folder")
    waypointFolder.Name = "Waypoints"
    waypointFolder.Parent = demoFolder

    -- Define S-curve path positions
    local pathPoints = {
        position + Vector3.new(0, 0, 0),       -- Start (dropper)
        position + Vector3.new(0, 0, -15),     -- Forward
        position + Vector3.new(15, 0, -25),    -- Curve right
        position + Vector3.new(15, 0, -40),    -- Forward
        position + Vector3.new(0, 0, -50),     -- Curve left
        position + Vector3.new(-15, 0, -55),   -- Continue left
        position + Vector3.new(-15, 0, -70),   -- Forward
        position + Vector3.new(0, 0, -80),     -- End (collector)
    }

    local waypoints = {}
    for i, pos in ipairs(pathPoints) do
        local wp = Instance.new("Part")
        wp.Name = "Waypoint_" .. i
        wp.Size = Vector3.new(2, 0.5, 2)
        wp.Position = pos
        wp.Anchored = true
        wp.CanCollide = false
        wp.Material = Enum.Material.Neon

        -- Color waypoints: green start, yellow middle, red end
        if i == 1 then
            wp.BrickColor = BrickColor.new("Bright green")
        elseif i == #pathPoints then
            wp.BrickColor = BrickColor.new("Bright red")
        else
            wp.BrickColor = BrickColor.new("Bright yellow")
            wp.Transparency = 0.5
        end

        wp.Parent = waypointFolder
        table.insert(waypoints, wp)
    end

    -- Draw path lines between waypoints
    local pathLinesFolder = Instance.new("Folder")
    pathLinesFolder.Name = "PathLines"
    pathLinesFolder.Parent = demoFolder

    for i = 1, #waypoints - 1 do
        local start = waypoints[i].Position
        local finish = waypoints[i + 1].Position
        local mid = (start + finish) / 2
        local distance = (finish - start).Magnitude

        local line = Instance.new("Part")
        line.Name = "PathLine_" .. i
        line.Size = Vector3.new(0.5, 0.2, distance)
        line.CFrame = CFrame.new(mid, finish)
        line.Anchored = true
        line.CanCollide = false
        line.BrickColor = BrickColor.new("Medium stone grey")
        line.Material = Enum.Material.SmoothPlastic
        line.Transparency = 0.3
        line.Parent = pathLinesFolder
    end

    ---------------------------------------------------------------------------
    -- CREATE DROPPER MACHINE
    ---------------------------------------------------------------------------

    local dropperMachine = Instance.new("Model")
    dropperMachine.Name = "DropperMachine"
    dropperMachine.Parent = demoFolder

    local dropperBase = Instance.new("Part")
    dropperBase.Name = "Base"
    dropperBase.Size = Vector3.new(6, 4, 6)
    dropperBase.Position = position + Vector3.new(0, 2, 3)
    dropperBase.Anchored = true
    dropperBase.BrickColor = BrickColor.new("Really black")
    dropperBase.Material = Enum.Material.DiamondPlate
    dropperBase.Parent = dropperMachine

    local dropperChute = Instance.new("Part")
    dropperChute.Name = "Chute"
    dropperChute.Size = Vector3.new(4, 2, 4)
    dropperChute.Position = position + Vector3.new(0, 5, 3)
    dropperChute.Anchored = true
    dropperChute.BrickColor = BrickColor.new("Bright orange")
    dropperChute.Material = Enum.Material.Metal
    dropperChute.Parent = dropperMachine

    dropperMachine.PrimaryPart = dropperBase

    ---------------------------------------------------------------------------
    -- CREATE COLLECTOR ZONE
    ---------------------------------------------------------------------------

    local collector = Instance.new("Part")
    collector.Name = "Collector"
    collector.Size = Vector3.new(10, 1, 10)
    collector.Position = pathPoints[#pathPoints] - Vector3.new(0, 0.5, 0)
    collector.Anchored = true
    collector.BrickColor = BrickColor.new("Bright red")
    collector.Material = Enum.Material.Neon
    collector.Transparency = 0.5
    collector.Parent = demoFolder

    -- Collector funnel effect
    local collectorFunnel = Instance.new("Part")
    collectorFunnel.Name = "CollectorFunnel"
    collectorFunnel.Size = Vector3.new(8, 3, 8)
    collectorFunnel.Position = pathPoints[#pathPoints] + Vector3.new(0, -2, 0)
    collectorFunnel.Anchored = true
    collectorFunnel.BrickColor = BrickColor.new("Really black")
    collectorFunnel.Material = Enum.Material.Metal
    collectorFunnel.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- STATUS DISPLAY
    ---------------------------------------------------------------------------

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 500, 0, 150)
    billboard.StudsOffset = Vector3.new(0, 10, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = dropperBase

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 0.2
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.TextColor3 = Color3.new(0, 1, 0)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Code
    statusLabel.Text = "CONVEYOR SYSTEM\nInitializing..."
    statusLabel.Parent = billboard

    -- Phase indicator
    local phaseBillboard = Instance.new("BillboardGui")
    phaseBillboard.Size = UDim2.new(0, 600, 0, 60)
    phaseBillboard.StudsOffset = Vector3.new(0, 14, 0)
    phaseBillboard.AlwaysOnTop = true
    phaseBillboard.Parent = dropperBase

    local phaseLabel = Instance.new("TextLabel")
    phaseLabel.Size = UDim2.new(1, 0, 1, 0)
    phaseLabel.BackgroundTransparency = 0.3
    phaseLabel.BackgroundColor3 = Color3.new(0.2, 0.2, 0.5)
    phaseLabel.TextColor3 = Color3.new(1, 1, 1)
    phaseLabel.TextScaled = true
    phaseLabel.Font = Enum.Font.GothamBold
    phaseLabel.Text = "INITIALIZING"
    phaseLabel.Parent = phaseBillboard

    ---------------------------------------------------------------------------
    -- TRACKING
    ---------------------------------------------------------------------------

    local itemsFolder = Instance.new("Folder")
    itemsFolder.Name = "Items"
    itemsFolder.Parent = demoFolder

    local controller = {
        running = true,
        itemsSpawned = 0,
        itemsCollected = 0,
        activeEntities = {},  -- { [entityId] = { assetId, instance } }
    }

    ---------------------------------------------------------------------------
    -- CREATE NODEPOOL FOR PATHFOLLOWERS
    ---------------------------------------------------------------------------

    local pathFollowerPool = NodePool:new({
        id = "Demo_PathFollowerPool",
    })
    pathFollowerPool.Sys.onInit(pathFollowerPool)

    pathFollowerPool.In.onConfigure(pathFollowerPool, {
        nodeClass = PathFollower,
        poolMode = "elastic",
        minSize = 2,
        maxSize = 15,
        shrinkDelay = 10,
        nodeConfig = {
            Speed = 12,
        },
        -- These signals are sent to the PathFollower when checked out
        checkoutSignals = {
            { signal = "onControl", map = { entity = "instance", entityId = "entityId" } },
            { signal = "onWaypoints", map = { targets = "$waypoints" } },
        },
        -- Auto-release when PathFollower fires "pathComplete"
        releaseOn = "pathComplete",
        -- Shared context - waypoints are the same for all items
        context = {
            waypoints = waypoints,
        },
    })

    -- Wire pool output for collection handling
    pathFollowerPool.Out = {
        Fire = function(self, signal, data)
            if signal == "released" then
                -- PathFollower completed - collect the item
                local entityData = controller.activeEntities[data.entityId]
                if entityData then
                    controller.itemsCollected = controller.itemsCollected + 1

                    -- Visual collection effect
                    local entity = entityData.instance
                    if entity and entity:IsA("BasePart") and entity.Parent then
                        -- Shrink and fade
                        local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
                        local tween = TweenService:Create(entity, tweenInfo, {
                            Size = Vector3.new(0.1, 0.1, 0.1),
                            Transparency = 1,
                        })
                        tween:Play()
                        tween.Completed:Connect(function()
                            -- Return to dropper (despawn)
                            dropper.In.onReturn(dropper, { assetId = entityData.assetId })
                        end)
                    else
                        -- Just despawn
                        dropper.In.onReturn(dropper, { assetId = entityData.assetId })
                    end

                    controller.activeEntities[data.entityId] = nil
                end
            end
        end,
    }

    ---------------------------------------------------------------------------
    -- CREATE DROPPER COMPONENT
    ---------------------------------------------------------------------------

    local dropper = Dropper:new({
        id = "Demo_Dropper",
        model = dropperBase,
    })
    dropper.Sys.onInit(dropper)
    dropper.In.onConfigure(dropper, {
        pool = { "RedCrate", "BlueCrate", "GreenCrate", "YellowCrate", "PurpleCrate" },
        poolMode = "random",
        interval = 2,
        maxActive = 10,
        spawnOffset = Vector3.new(0, 4, -3),
    })

    ---------------------------------------------------------------------------
    -- WIRE DROPPER -> NODEPOOL
    ---------------------------------------------------------------------------

    dropper.Out = {
        Fire = function(self, signal, data)
            if signal == "spawned" then
                controller.itemsSpawned = controller.itemsSpawned + 1

                -- Move spawned item to our folder
                if data.instance then
                    data.instance.Parent = itemsFolder
                end

                -- Track this entity
                controller.activeEntities[data.entityId] = {
                    assetId = data.assetId,
                    instance = data.instance,
                }

                -- Check out a PathFollower from the pool
                -- The pool will automatically send onControl and onWaypoints signals
                pathFollowerPool.In.onCheckout(pathFollowerPool, {
                    entityId = data.entityId,
                    instance = data.instance,
                })

            elseif signal == "despawned" then
                -- Cleanup tracking
                controller.activeEntities[data.entityId] = nil
            end
        end,
    }

    ---------------------------------------------------------------------------
    -- STATUS UPDATE LOOP
    ---------------------------------------------------------------------------

    local statusConnection = RunService.Heartbeat:Connect(function()
        if not controller.running then return end

        local poolStats = pathFollowerPool:getStats()

        statusLabel.Text = string.format(
            "CONVEYOR SYSTEM\nSpawned: %d | Collected: %d\nPool: %d/%d in use",
            controller.itemsSpawned,
            controller.itemsCollected,
            poolStats.inUse,
            poolStats.total
        )
    end)

    ---------------------------------------------------------------------------
    -- HELPER FUNCTIONS
    ---------------------------------------------------------------------------

    local function setPhase(text)
        phaseLabel.Text = text
        announce(text)
    end

    local function setStatus(text, color)
        statusLabel.Text = text
        statusLabel.TextColor3 = color or Color3.new(0, 1, 0)
    end

    ---------------------------------------------------------------------------
    -- AUTOMATED DEMO SEQUENCE
    ---------------------------------------------------------------------------

    task.spawn(function()
        task.wait(1)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 1: INTRODUCTION
        -----------------------------------------------------------------------
        setPhase("PHASE 1: DROPPER + NODEPOOL")
        setStatus("Demonstrating Dropper + NodePool\nPathFollowers are pooled!", Color3.new(0, 0.8, 1))
        task.wait(2)

        -- Start dropper with slow interval
        setStatus("Dropper: onStart()\nNodePool manages PathFollowers", Color3.new(0, 0.8, 1))
        dropper.In.onConfigure(dropper, { interval = 2 })
        dropper.In.onStart(dropper)
        task.wait(8)  -- Let a few items spawn and traverse

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 2: POOLING IN ACTION
        -----------------------------------------------------------------------
        setPhase("PHASE 2: POOL REUSE")
        setStatus("Watch PathFollowers get reused!\nPool grows/shrinks as needed", Color3.new(0, 1, 0.5))
        task.wait(8)  -- Watch items traverse path and pool reuse

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 3: SPEED VARIATION
        -----------------------------------------------------------------------
        setPhase("PHASE 3: FASTER SPAWNING")
        setStatus("Increasing spawn rate\nPool expands automatically", Color3.new(1, 0.8, 0))

        dropper.In.onConfigure(dropper, { interval = 0.8 })

        task.wait(10)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 4: POOL MODES
        -----------------------------------------------------------------------
        setPhase("PHASE 4: SEQUENTIAL COLORS")
        setStatus("Changing to sequential pool\nCrates spawn in order", Color3.new(0.7, 0.3, 1))

        dropper.In.onConfigure(dropper, {
            poolMode = "sequential",
            interval = 1,
        })

        task.wait(10)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 5: BURST DISPENSING
        -----------------------------------------------------------------------
        setPhase("PHASE 5: ON-DEMAND SPAWNING")
        setStatus("Dropper: onDispense()\nBurst spawning", Color3.new(1, 0.3, 0.3))

        -- Stop loop, do manual dispenses
        dropper.In.onStop(dropper)
        task.wait(1)

        -- Burst of 5
        setStatus("Dispensing burst: 5 items\nPool handles the load", Color3.new(1, 0.3, 0.3))
        dropper.In.onDispense(dropper, { count = 5 })
        task.wait(4)

        -- Another burst
        setStatus("Dispensing burst: 5 more items", Color3.new(1, 0.3, 0.3))
        dropper.In.onDispense(dropper, { count = 5 })
        task.wait(6)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 6: CONTINUOUS OPERATION
        -----------------------------------------------------------------------
        setPhase("PHASE 6: CONTINUOUS OPERATION")
        setStatus("Resuming continuous mode\nWatch the system run!", Color3.new(0, 1, 0))

        dropper.In.onConfigure(dropper, {
            interval = 1.2,
            poolMode = "random",
        })
        dropper.In.onStart(dropper)

        -- Let it run for a while
        task.wait(15)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 7: COMPLETE
        -----------------------------------------------------------------------
        setPhase("DEMO COMPLETE")

        local poolStats = pathFollowerPool:getStats()
        setStatus(string.format(
            "All API calls demonstrated!\nSpawned: %d | Collected: %d\nPool peak: %d nodes",
            controller.itemsSpawned,
            controller.itemsCollected,
            poolStats.total
        ), Color3.new(0, 1, 0))

        -- Stop dropper
        dropper.In.onStop(dropper)

        -- Wait for remaining items to finish
        task.wait(12)

        setStatus("SYSTEM OFFLINE\nCall demo.cleanup() to remove", Color3.new(0.5, 0.5, 0.5))

        announce("Demo complete! Spawned: " .. controller.itemsSpawned .. ", Collected: " .. controller.itemsCollected)
    end)

    ---------------------------------------------------------------------------
    -- CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.cleanup()
        controller.running = false
        statusConnection:Disconnect()

        -- Release all from pool
        pathFollowerPool.In.onReleaseAll(pathFollowerPool)
        pathFollowerPool.Sys.onStop(pathFollowerPool)

        -- Stop dropper
        dropper.In.onStop(dropper)
        dropper.In.onDespawnAll(dropper)
        dropper.Sys.onStop(dropper)

        demoFolder:Destroy()
        announce("Demo cleaned up")
    end

    function controls.getStats()
        local poolStats = pathFollowerPool:getStats()
        return {
            itemsSpawned = controller.itemsSpawned,
            itemsCollected = controller.itemsCollected,
            poolInUse = poolStats.inUse,
            poolTotal = poolStats.total,
        }
    end

    -- Manual controls
    function controls.dispense(count)
        dropper.In.onDispense(dropper, { count = count or 1 })
    end

    function controls.setInterval(interval)
        dropper.In.onConfigure(dropper, { interval = interval })
    end

    function controls.start()
        dropper.In.onStart(dropper)
    end

    function controls.stop()
        dropper.In.onStop(dropper)
    end

    print("============================================")
    print("  CONVEYOR SYSTEM - AUTOMATED DEMO")
    print("============================================")
    print("")
    print("Sit back and watch! The demo will showcase:")
    print("  - Phase 1: Dropper + NodePool integration")
    print("  - Phase 2: PathFollower pool reuse")
    print("  - Phase 3: Faster spawning (pool expansion)")
    print("  - Phase 4: Sequential color spawning")
    print("  - Phase 5: On-demand burst dispensing")
    print("  - Phase 6: Continuous operation")
    print("")
    print("To stop early: demo.cleanup()")
    print("")

    return controls
end

return Demo
