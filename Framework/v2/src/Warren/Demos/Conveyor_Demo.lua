--[[
    Warren Framework v2
    Conveyor System Demo - Signal-Based Architecture

    Uses Out:Fire / In signal pattern, not direct handler calls.
    Demonstrates multi-component orchestration through signals.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Warren.Demos)
    local demo = Demos.Conveyor.run()
    -- Sit back and watch the automated demo!

    -- To stop early:
    demo.cleanup()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))

local Node = require(ReplicatedStorage.Warren.Node)
local Dropper = Lib.Components.Dropper
local PathFollower = Lib.Components.PathFollower
local NodePool = Lib.Components.NodePool

local SpawnerCore = require(ReplicatedStorage.Warren.Internal.SpawnerCore)

local Demo = {}

--------------------------------------------------------------------------------
-- CONVEYOR CONTROLLER NODE
-- Orchestrates Dropper + NodePool through signals
--------------------------------------------------------------------------------

local ConveyorController = Node.extend({
    name = "ConveyorController",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._itemsSpawned = 0
            self._itemsCollected = 0
            self._activeEntities = {}  -- { [entityId] = { assetId, instance } }
        end,
    },

    In = {
        -- Receive spawned notification from Dropper
        onDropperSpawned = function(self, data)
            self._itemsSpawned = self._itemsSpawned + 1

            -- Track this entity
            self._activeEntities[data.entityId] = {
                assetId = data.assetId,
                instance = data.instance,
            }

            -- Fire checkout signal to pool
            self.Out:Fire("poolCheckout", {
                entityId = data.entityId,
                instance = data.instance,
            })
        end,

        onDropperDespawned = function(self, data)
            self._activeEntities[data.entityId] = nil
        end,

        -- Receive release notification from NodePool (path complete)
        onPoolReleased = function(self, data)
            local entityData = self._activeEntities[data.entityId]
            if entityData then
                self._itemsCollected = self._itemsCollected + 1

                -- Signal to return the item to dropper
                -- (collection animation handled by wiring)
                self.Out:Fire("dropperReturn", { assetId = entityData.assetId })
                self._activeEntities[data.entityId] = nil
            end
        end,
    },

    Out = {
        -- Dropper control signals
        dropperStart = {},      -- -> Dropper.In.onStart
        dropperStop = {},       -- -> Dropper.In.onStop
        dropperDispense = {},   -- -> Dropper.In.onDispense
        dropperConfigure = {},  -- -> Dropper.In.onConfigure
        dropperReturn = {},     -- -> Dropper.In.onReturn
        dropperDespawnAll = {}, -- -> Dropper.In.onDespawnAll

        -- Pool control signals
        poolCheckout = {},      -- -> NodePool.In.onCheckout
        poolReleaseAll = {},    -- -> NodePool.In.onReleaseAll
        poolConfigure = {},     -- -> NodePool.In.onConfigure
    },

    -- Controller methods that fire signals
    startDropper = function(self)
        self.Out:Fire("dropperStart", {})
    end,

    stopDropper = function(self)
        self.Out:Fire("dropperStop", {})
    end,

    dispense = function(self, count)
        self.Out:Fire("dropperDispense", { count = count or 1 })
    end,

    configureDropper = function(self, config)
        self.Out:Fire("dropperConfigure", config)
    end,

    releaseAllFromPool = function(self)
        self.Out:Fire("poolReleaseAll", {})
    end,

    despawnAllItems = function(self)
        self.Out:Fire("dropperDespawnAll", {})
    end,

    getStats = function(self)
        return {
            itemsSpawned = self._itemsSpawned,
            itemsCollected = self._itemsCollected,
        }
    end,
})

--------------------------------------------------------------------------------
-- DEMO
--------------------------------------------------------------------------------

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 5, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP EXISTING DEMO (handles Studio persistence between runs)
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("Conveyor_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end

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
    statusLabel.Text = "SIGNAL-BASED CONVEYOR\nInitializing..."
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

    local state = {
        running = true,
    }

    ---------------------------------------------------------------------------
    -- CREATE NODES
    ---------------------------------------------------------------------------

    -- NodePool for PathFollowers
    local pathFollowerPool = NodePool:new({
        id = "Demo_PathFollowerPool",
    })
    pathFollowerPool.Sys.onInit(pathFollowerPool)

    -- Configure pool (setup phase - direct call OK per ARCHITECTURE.md)
    pathFollowerPool.In.onConfigure(pathFollowerPool, {
        nodeClass = PathFollower,
        poolMode = "elastic",
        minSize = 2,
        maxSize = 15,
        shrinkDelay = 10,
        nodeConfig = {
            Speed = 12,
        },
        checkoutSignals = {
            { signal = "onControl", map = { entity = "instance", entityId = "entityId" } },
            { signal = "onWaypoints", map = { targets = "$waypoints" } },
        },
        releaseOn = "pathComplete",
        context = {
            waypoints = waypoints,
        },
    })

    -- Dropper
    local dropper = Dropper:new({
        id = "Demo_Dropper",
        model = dropperBase,
    })
    dropper.Sys.onInit(dropper)

    -- Configure dropper (setup phase - direct call OK per ARCHITECTURE.md)
    dropper.In.onConfigure(dropper, {
        pool = { "RedCrate", "BlueCrate", "GreenCrate", "YellowCrate", "PurpleCrate" },
        poolMode = "random",
        interval = 2,
        maxActive = 10,
        spawnOffset = Vector3.new(0, 4, -3),
    })

    -- Controller
    local controller = ConveyorController:new({ id = "Demo_ConveyorController" })
    controller.Sys.onInit(controller)

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS (manual wiring for demo - in production IPC does this)
    ---------------------------------------------------------------------------

    -- Controller.Out -> Dropper.In and NodePool.In
    controller.Out = {
        Fire = function(self, signal, data)
            -- Dropper signals
            if signal == "dropperStart" then
                dropper.In.onStart(dropper)
            elseif signal == "dropperStop" then
                dropper.In.onStop(dropper)
            elseif signal == "dropperDispense" then
                dropper.In.onDispense(dropper, data)
            elseif signal == "dropperConfigure" then
                dropper.In.onConfigure(dropper, data)
            elseif signal == "dropperReturn" then
                dropper.In.onReturn(dropper, data)
            elseif signal == "dropperDespawnAll" then
                dropper.In.onDespawnAll(dropper)
            -- Pool signals
            elseif signal == "poolCheckout" then
                pathFollowerPool.In.onCheckout(pathFollowerPool, data)
            elseif signal == "poolReleaseAll" then
                pathFollowerPool.In.onReleaseAll(pathFollowerPool)
            elseif signal == "poolConfigure" then
                pathFollowerPool.In.onConfigure(pathFollowerPool, data)
            end
        end,
    }

    -- Dropper.Out -> Controller.In + move items to folder
    dropper.Out = {
        Fire = function(self, signal, data)
            if signal == "spawned" then
                -- Move spawned item to our folder
                if data.instance then
                    data.instance.Parent = itemsFolder
                end
                -- Forward to controller
                controller.In.onDropperSpawned(controller, data)

            elseif signal == "despawned" then
                controller.In.onDropperDespawned(controller, data)
            end
        end,
    }

    -- NodePool.Out -> Controller.In + collection animation
    pathFollowerPool.Out = {
        Fire = function(self, signal, data)
            if signal == "released" then
                -- Get entity data before controller cleans it up
                local entityData = controller._activeEntities[data.entityId]

                -- Collection animation
                if entityData then
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
                            -- Now forward to controller to handle return
                            controller.In.onPoolReleased(controller, data)
                        end)
                    else
                        -- Just forward to controller
                        controller.In.onPoolReleased(controller, data)
                    end
                else
                    controller.In.onPoolReleased(controller, data)
                end
            end
        end,
    }

    ---------------------------------------------------------------------------
    -- STATUS UPDATE LOOP
    ---------------------------------------------------------------------------

    local statusConnection = RunService.Heartbeat:Connect(function()
        if not state.running then return end

        local poolStats = pathFollowerPool:getStats()
        local controllerStats = controller:getStats()

        statusLabel.Text = string.format(
            "SIGNAL-BASED CONVEYOR\nSpawned: %d | Collected: %d\nPool: %d/%d in use",
            controllerStats.itemsSpawned,
            controllerStats.itemsCollected,
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

        if not state.running then return end

        -----------------------------------------------------------------------
        -- PHASE 1: INTRODUCTION
        -----------------------------------------------------------------------
        setPhase("PHASE 1: SIGNAL-BASED ARCHITECTURE")
        setStatus("Controller fires signals\nDropper + Pool respond", Color3.new(0, 0.8, 1))
        task.wait(2)

        -- Start dropper through controller
        setStatus("Controller -> dropperStart signal", Color3.new(0, 0.8, 1))
        controller:configureDropper({ interval = 2 })
        controller:startDropper()
        task.wait(8)

        if not state.running then return end

        -----------------------------------------------------------------------
        -- PHASE 2: POOLING IN ACTION
        -----------------------------------------------------------------------
        setPhase("PHASE 2: POOL REUSE")
        setStatus("spawned -> poolCheckout -> pathComplete -> released\nFull signal flow!", Color3.new(0, 1, 0.5))
        task.wait(8)

        if not state.running then return end

        -----------------------------------------------------------------------
        -- PHASE 3: SPEED VARIATION
        -----------------------------------------------------------------------
        setPhase("PHASE 3: FASTER SPAWNING")
        setStatus("Controller -> dropperConfigure signal\nPool auto-expands", Color3.new(1, 0.8, 0))

        controller:configureDropper({ interval = 0.8 })

        task.wait(10)

        if not state.running then return end

        -----------------------------------------------------------------------
        -- PHASE 4: POOL MODES
        -----------------------------------------------------------------------
        setPhase("PHASE 4: SEQUENTIAL COLORS")
        setStatus("dropperConfigure signal\npoolMode = 'sequential'", Color3.new(0.7, 0.3, 1))

        controller:configureDropper({
            poolMode = "sequential",
            interval = 1,
        })

        task.wait(10)

        if not state.running then return end

        -----------------------------------------------------------------------
        -- PHASE 5: BURST DISPENSING
        -----------------------------------------------------------------------
        setPhase("PHASE 5: ON-DEMAND SIGNALS")
        setStatus("Controller -> dropperDispense signal\nBurst spawning", Color3.new(1, 0.3, 0.3))

        -- Stop loop, do manual dispenses through controller
        controller:stopDropper()
        task.wait(1)

        -- Burst of 5
        setStatus("dropperDispense({ count = 5 })\nSignal-based burst!", Color3.new(1, 0.3, 0.3))
        controller:dispense(5)
        task.wait(4)

        -- Another burst
        setStatus("dropperDispense({ count = 5 })\nAnother burst", Color3.new(1, 0.3, 0.3))
        controller:dispense(5)
        task.wait(6)

        if not state.running then return end

        -----------------------------------------------------------------------
        -- PHASE 6: CONTINUOUS OPERATION
        -----------------------------------------------------------------------
        setPhase("PHASE 6: CONTINUOUS OPERATION")
        setStatus("All signals flowing!\nController orchestrates everything", Color3.new(0, 1, 0))

        controller:configureDropper({
            interval = 1.2,
            poolMode = "random",
        })
        controller:startDropper()

        -- Let it run for a while
        task.wait(15)

        if not state.running then return end

        -----------------------------------------------------------------------
        -- PHASE 7: COMPLETE
        -----------------------------------------------------------------------
        setPhase("DEMO COMPLETE")

        local poolStats = pathFollowerPool:getStats()
        local controllerStats = controller:getStats()
        setStatus(string.format(
            "SIGNAL-BASED ARCHITECTURE\nSpawned: %d | Collected: %d\nPool peak: %d nodes",
            controllerStats.itemsSpawned,
            controllerStats.itemsCollected,
            poolStats.total
        ), Color3.new(0, 1, 0))

        -- Stop dropper through controller
        controller:stopDropper()

        -- Wait for remaining items to finish
        task.wait(12)

        setStatus("SYSTEM OFFLINE\nCall demo.cleanup() to remove", Color3.new(0.5, 0.5, 0.5))

        local finalStats = controller:getStats()
        announce("Demo complete! Spawned: " .. finalStats.itemsSpawned .. ", Collected: " .. finalStats.itemsCollected)
    end)

    ---------------------------------------------------------------------------
    -- CONTROLS (fire signals through controller)
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.cleanup()
        state.running = false
        statusConnection:Disconnect()

        -- Release all from pool through controller
        controller:releaseAllFromPool()
        pathFollowerPool.Sys.onStop(pathFollowerPool)

        -- Stop dropper through controller
        controller:stopDropper()
        controller:despawnAllItems()
        dropper.Sys.onStop(dropper)

        demoFolder:Destroy()
        announce("Demo cleaned up")
    end

    function controls.getStats()
        local poolStats = pathFollowerPool:getStats()
        local controllerStats = controller:getStats()
        return {
            itemsSpawned = controllerStats.itemsSpawned,
            itemsCollected = controllerStats.itemsCollected,
            poolInUse = poolStats.inUse,
            poolTotal = poolStats.total,
        }
    end

    -- Manual controls (through controller signals)
    function controls.dispense(count)
        controller:dispense(count)
    end

    function controls.setInterval(interval)
        controller:configureDropper({ interval = interval })
    end

    function controls.start()
        controller:startDropper()
    end

    function controls.stop()
        controller:stopDropper()
    end

    function controls.getController()
        return controller
    end

    print("============================================")
    print("  SIGNAL-BASED CONVEYOR DEMO")
    print("============================================")
    print("")
    print("Controller fires signals -> Components respond")
    print("Proper Out:Fire / In pattern throughout")
    print("")
    print("Signal flow:")
    print("  Controller -> dropperStart -> Dropper")
    print("  Dropper -> spawned -> Controller")
    print("  Controller -> poolCheckout -> NodePool")
    print("  NodePool -> released -> Controller")
    print("  Controller -> dropperReturn -> Dropper")
    print("")
    print("To stop early: demo.cleanup()")
    print("")

    return controls
end

return Demo
