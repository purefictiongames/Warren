--[[
    LibPureFiction Framework v2
    ConveyorBelt Visual Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Visual demonstration of component composition:
    - Dropper: Spawns entities at intervals
    - PathFollower: Guides entities through waypoints
    - Zone: Detects arrivals at end, signals back to Dropper
    - Dropper: Despawns returned entities

    This creates a continuous loop where entities spawn, travel a path,
    and despawn when they reach the end zone.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.ConveyorBelt.demo()     -- Run the visual demo
    Tests.ConveyorBelt.cleanup()  -- Remove all demo instances
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local Dropper = Lib.Components.Dropper
local PathFollower = Lib.Components.PathFollower
local Zone = Lib.Components.Zone
local NodePool = Lib.Components.NodePool

--------------------------------------------------------------------------------
-- TEST HARNESS
--------------------------------------------------------------------------------

local Tests = {}
local demoInstances = {}
local activeComponents = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

-- Create a waypoint marker (visual only)
local function createWaypoint(name, position, color)
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = Enum.PartType.Cylinder
    part.Size = Vector3.new(1, 4, 4)
    part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.3
    part.BrickColor = color or BrickColor.new("Bright yellow")
    part.Material = Enum.Material.Neon
    part.Parent = workspace
    table.insert(demoInstances, part)

    -- Add label
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    return part
end

-- Create the dropper platform (spawn point)
local function createDropperPlatform(position)
    local part = Instance.new("Part")
    part.Name = "DropperPlatform"
    part.Size = Vector3.new(6, 1, 6)
    part.Position = position
    part.Anchored = true
    part.CanCollide = true
    part.BrickColor = BrickColor.new("Bright green")
    part.Material = Enum.Material.SmoothPlastic
    part.Parent = workspace
    table.insert(demoInstances, part)

    -- Add arrow pointing down
    local arrow = Instance.new("Part")
    arrow.Name = "SpawnArrow"
    arrow.Size = Vector3.new(1, 3, 1)
    arrow.Position = position + Vector3.new(0, 4, 0)
    arrow.Anchored = true
    arrow.CanCollide = false
    arrow.BrickColor = BrickColor.new("Bright green")
    arrow.Material = Enum.Material.Neon
    arrow.Transparency = 0.5
    arrow.Parent = workspace
    table.insert(demoInstances, arrow)

    return part
end

-- Create the end zone (detection area)
local function createEndZone(position)
    local part = Instance.new("Part")
    part.Name = "EndZone"
    part.Size = Vector3.new(8, 6, 8)
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.7
    part.BrickColor = BrickColor.new("Bright red")
    part.Material = Enum.Material.Neon
    part.Parent = workspace
    table.insert(demoInstances, part)

    -- Add label
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 120, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "END ZONE"
    label.TextColor3 = Color3.new(1, 0.3, 0.3)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    return part
end

-- Create a simple template for spawning
local function createTemplate()
    -- Check if template already exists
    local templates = ReplicatedStorage:FindFirstChild("Templates")
    if not templates then
        templates = Instance.new("Folder")
        templates.Name = "Templates"
        templates.Parent = ReplicatedStorage
    end

    if templates:FindFirstChild("ConveyorCrate") then
        return templates.ConveyorCrate
    end

    -- Create crate template
    local crate = Instance.new("Model")
    crate.Name = "ConveyorCrate"

    local part = Instance.new("Part")
    part.Name = "Body"
    part.Size = Vector3.new(3, 3, 3)
    part.Anchored = true
    part.CanCollide = false
    part.BrickColor = BrickColor.new("Bright blue")
    part.Material = Enum.Material.SmoothPlastic
    part.Parent = crate

    crate.PrimaryPart = part
    crate.Parent = templates
    table.insert(demoInstances, crate)

    return crate
end

-- Draw path lines between waypoints
local function drawPathLines(waypoints)
    for i = 1, #waypoints - 1 do
        local from = waypoints[i].Position
        local to = waypoints[i + 1].Position

        local distance = (to - from).Magnitude
        local midpoint = (from + to) / 2

        local line = Instance.new("Part")
        line.Name = "PathLine_" .. i
        line.Size = Vector3.new(0.3, 0.3, distance)
        line.CFrame = CFrame.lookAt(midpoint, to)
        line.Anchored = true
        line.CanCollide = false
        line.Transparency = 0.5
        line.BrickColor = BrickColor.new("White")
        line.Material = Enum.Material.Neon
        line.Parent = workspace
        table.insert(demoInstances, line)
    end
end

--------------------------------------------------------------------------------
-- VISUAL DEMO
--------------------------------------------------------------------------------

function Tests.demo()
    print("\n========================================")
    print("  ConveyorBelt Visual Demo")
    print("========================================")
    print("Components: Dropper -> NodePool<PathFollower> -> Zone -> Dropper")
    print("Watch entities spawn, travel, and despawn...\n")

    -- Reset any previous demo
    Tests.cleanup()

    -- Create template
    createTemplate()

    -- Layout (non-linear L-shaped path)
    -- Offset from spawn to avoid player collision
    --
    --  [Dropper] ---> [WP1] ---> [WP2]
    --                              |
    --                              v
    --                           [WP3/Zone]
    --
    local baseOffset = Vector3.new(30, 0, 30)  -- Move away from spawn
    local dropperPos = Vector3.new(0, 5, 0) + baseOffset
    local wp1Pos = Vector3.new(15, 5, 0) + baseOffset
    local wp2Pos = Vector3.new(30, 5, 0) + baseOffset
    local wp3Pos = Vector3.new(30, 5, 20) + baseOffset  -- Turn corner

    -- Create 3D elements
    local dropperPlatform = createDropperPlatform(dropperPos)
    local waypoint1 = createWaypoint("WP1", wp1Pos, BrickColor.new("Bright yellow"))
    local waypoint2 = createWaypoint("WP2", wp2Pos, BrickColor.new("Bright orange"))
    local waypoint3 = createWaypoint("WP3", wp3Pos, BrickColor.new("Bright red"))
    local endZonePart = createEndZone(wp3Pos)

    -- Draw path lines
    drawPathLines({ dropperPlatform, waypoint1, waypoint2, waypoint3 })

    -- Waypoints array for PathFollowers
    local waypoints = { waypoint1, waypoint2, waypoint3 }

    -- =========================================================================
    -- CREATE COMPONENTS
    -- =========================================================================

    -- Dropper: Spawns entities at intervals
    local dropper = Dropper:new({
        id = "ConveyorDropper",
        model = dropperPlatform,
    })
    dropper.Sys.onInit(dropper)
    table.insert(activeComponents, dropper)

    -- NodePool: Manages PathFollower instances (elastic mode)
    local pathPool = NodePool:new({
        id = "PathFollowerPool",
    })
    pathPool.Sys.onInit(pathPool)
    table.insert(activeComponents, pathPool)

    -- Zone: Detects entities at end of path
    local zone = Zone:new({
        id = "EndZone",
        model = endZonePart,
    })
    zone.Sys.onInit(zone)
    table.insert(activeComponents, zone)

    -- =========================================================================
    -- CONFIGURE COMPONENTS
    -- =========================================================================

    -- Configure dropper
    dropper.In.onConfigure(dropper, {
        templateName = "ConveyorCrate",
        interval = 2,
        maxActive = 20,
        spawnPosition = dropperPos + Vector3.new(0, 2, 0),
    })

    -- Configure PathFollower pool (elastic: grows on demand, shrinks when idle)
    pathPool.In.onConfigure(pathPool, {
        nodeClass = "PathFollower",
        poolMode = "elastic",
        minSize = 2,            -- Keep at least 2 warm
        maxSize = 15,           -- Cap at 15
        shrinkDelay = 10,       -- Destroy idle nodes after 10 seconds
        nodeConfig = {
            speed = 16,
        },
        checkoutSignals = {
            { signal = "onControl", map = { entity = "entity", entityId = "entityId" } },
            { signal = "onWaypoints", map = { targets = "$waypoints" } },
        },
        releaseOn = "pathComplete",  -- Auto-release when path is done
        context = {
            waypoints = waypoints,
        },
    })

    -- Configure zone with filter (only detect entities from our dropper)
    zone.In.onConfigure(zone, {
        filter = {
            spawnSource = "ConveyorDropper",
        },
    })

    -- =========================================================================
    -- WIRE COMPONENTS
    -- =========================================================================

    -- Track stats for display
    local stats = {
        spawned = 0,
        despawned = 0,
        inTransit = 0,
        poolCheckedOut = 0,
        poolReleased = 0,
    }

    -- Wire: Dropper.spawned -> NodePool.onCheckout
    dropper.Out = {
        Fire = function(self, signal, data)
            if signal == "spawned" then
                stats.spawned = stats.spawned + 1
                stats.inTransit = stats.inTransit + 1

                print(string.format("  [SPAWN] %s (total: %d, in transit: %d)",
                    data.entityId, stats.spawned, stats.inTransit))

                -- Request a PathFollower from the pool
                pathPool.In.onCheckout(pathPool, {
                    entity = data.instance,
                    entityId = data.entityId,
                    assetId = data.assetId,
                })

            elseif signal == "despawned" then
                stats.despawned = stats.despawned + 1
                stats.inTransit = stats.inTransit - 1

                print(string.format("  [DESPAWN] %s (total despawned: %d, in transit: %d)",
                    data.entityId or data.assetId, stats.despawned, stats.inTransit))

            elseif signal == "loopStarted" then
                print("  [DROPPER] Spawn loop started")
            elseif signal == "loopStopped" then
                print("  [DROPPER] Spawn loop stopped")
            end
        end,
    }

    -- Wire: NodePool events (for logging)
    pathPool.Out = {
        Fire = function(self, signal, data)
            if signal == "checkedOut" then
                stats.poolCheckedOut = stats.poolCheckedOut + 1
                local poolStats = pathPool:getStats()
                print(string.format("  [POOL] Checked out %s for %s (pool: %d available, %d in use)",
                    data.nodeId, data.entityId, poolStats.available, poolStats.inUse))

            elseif signal == "released" then
                stats.poolReleased = stats.poolReleased + 1
                local poolStats = pathPool:getStats()
                print(string.format("  [POOL] Released %s from %s (pool: %d available, %d in use)",
                    data.nodeId, data.entityId, poolStats.available, poolStats.inUse))

            elseif signal == "exhausted" then
                print(string.format("  [POOL] EXHAUSTED! Cannot checkout for %s (at max: %d)",
                    data.entityId, data.maxSize))

            elseif signal == "nodeCreated" then
                print(string.format("  [POOL] Created new node: %s", data.nodeId))

            elseif signal == "nodeDestroyed" then
                print(string.format("  [POOL] Destroyed idle node: %s", data.nodeId))
            end
        end,
    }

    -- Wire: Zone.entityEntered -> Dropper.onReturn
    zone.Out = {
        Fire = function(self, signal, data)
            if signal == "entityEntered" then
                print(string.format("  [ZONE] Entity entered: %s", data.entityId))

                -- Signal dropper to despawn this entity
                if data.assetId then
                    dropper.In.onReturn(dropper, { assetId = data.assetId })
                end
            end
        end,
    }

    -- =========================================================================
    -- START
    -- =========================================================================

    -- Start the dropper
    dropper.In.onStart(dropper)

    print("\nDemo running! Entities spawn every 2 seconds.")
    print("NodePool will grow on demand and shrink when idle.")
    print("Run Tests.ConveyorBelt.cleanup() to stop.\n")
    print("----------------------------------------")
end

function Tests.cleanup()
    print("\nCleaning up ConveyorBelt demo...")

    -- Stop components
    for _, component in ipairs(activeComponents) do
        if component.Sys and component.Sys.onStop then
            component.Sys.onStop(component)
        end
    end
    activeComponents = {}

    -- Destroy 3D instances
    for _, instance in ipairs(demoInstances) do
        if typeof(instance) == "Instance" and instance.Parent then
            instance:Destroy()
        end
    end
    demoInstances = {}

    print("Cleanup complete.\n")
end

function Tests.stats()
    print("\n--- ConveyorBelt Stats ---")
    -- Would need to track stats externally or in module state
    print("Run demo() first to see live stats in console")
end

return Tests
