--[[
    LibPureFiction Framework v2
    Zone Component Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Zone.runAll()
    ```

    Or run specific test groups:

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Zone.runGroup("Zone")
    Tests.Zone.runGroup("Collision Detection")
    Tests.Zone.runGroup("Filtering")
    ```

    Visual demo:
    ```lua
    Tests.Zone.demo()
    Tests.Zone.cleanup()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local Zone = Lib.Components.Zone
local Debug = Lib.System.Debug

--------------------------------------------------------------------------------
-- TEST HARNESS
--------------------------------------------------------------------------------

local Tests = {}
local testCases = {}
local testGroups = {}

local stats = {
    passed = 0,
    failed = 0,
    errors = 0,
}

local function resetStats()
    stats.passed = 0
    stats.failed = 0
    stats.errors = 0
end

local function log(level, ...)
    local msg = table.concat({...}, " ")
    if level == "pass" then
        print("  ✓", msg)
    elseif level == "fail" then
        warn("  ✗", msg)
    elseif level == "error" then
        warn("  ⚠", msg)
    elseif level == "group" then
        print("\n▶", msg)
    elseif level == "summary" then
        print("\n" .. msg)
    else
        print("   ", msg)
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s",
            message or "Assertion failed",
            tostring(expected),
            tostring(actual)), 2)
    end
end

local function assert_true(value, message)
    if not value then
        error(message or "Expected true, got false", 2)
    end
end

local function assert_false(value, message)
    if value then
        error(message or "Expected false, got true", 2)
    end
end

local function assert_nil(value, message)
    if value ~= nil then
        error(string.format("%s: expected nil, got %s",
            message or "Assertion failed",
            tostring(value)), 2)
    end
end

local function assert_not_nil(value, message)
    if value == nil then
        error(message or "Expected non-nil value", 2)
    end
end

local function test(name, group, fn)
    table.insert(testCases, { name = name, group = group, fn = fn })
    testGroups[group] = testGroups[group] or {}
    table.insert(testGroups[group], name)
end

local function runTest(testCase)
    local success, err = pcall(testCase.fn)
    if success then
        log("pass", testCase.name)
        stats.passed = stats.passed + 1
    else
        log("fail", testCase.name)
        log("error", tostring(err))
        stats.failed = stats.failed + 1
    end
end

function Tests.runAll()
    resetStats()
    print("\n========================================")
    print("  Zone Component Test Suite")
    print("========================================")

    local currentGroup = nil
    for _, testCase in ipairs(testCases) do
        if testCase.group ~= currentGroup then
            currentGroup = testCase.group
            log("group", currentGroup)
        end
        runTest(testCase)
    end

    log("summary", string.format(
        "Results: %d passed, %d failed, %d total",
        stats.passed,
        stats.failed,
        stats.passed + stats.failed
    ))

    return stats
end

function Tests.runGroup(groupName)
    resetStats()
    print("\n========================================")
    print("  Running: " .. groupName)
    print("========================================")

    log("group", groupName)
    for _, testCase in ipairs(testCases) do
        if testCase.group == groupName then
            runTest(testCase)
        end
    end

    log("summary", string.format(
        "Results: %d passed, %d failed, %d total",
        stats.passed,
        stats.failed,
        stats.passed + stats.failed
    ))

    return stats
end

function Tests.run(testName)
    resetStats()
    for _, testCase in ipairs(testCases) do
        if testCase.name == testName then
            log("group", testCase.group)
            runTest(testCase)
            break
        end
    end
    return stats
end

function Tests.list()
    print("\nAvailable test groups:")
    for group, tests in pairs(testGroups) do
        print(string.format("  %s (%d tests)", group, #tests))
    end
end

--------------------------------------------------------------------------------
-- TEST HELPERS
--------------------------------------------------------------------------------

-- Create a mock zone part
local function createMockZonePart(name, position, size)
    local part = Instance.new("Part")
    part.Name = name or "Zone"
    part.Position = position or Vector3.new(0, 0, 0)
    part.Size = size or Vector3.new(10, 10, 10)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.5
    return part
end

-- Create a mock entity (Model with NodeId attribute)
local function createMockEntity(name, nodeClass, position)
    local model = Instance.new("Model")
    model.Name = name or "Entity"
    model:SetAttribute("NodeId", name or "Entity_1")
    model:SetAttribute("NodeClass", nodeClass or "TestEntity")

    local part = Instance.new("Part")
    part.Name = "HumanoidRootPart"
    part.Position = position or Vector3.new(0, 0, 0)
    part.Size = Vector3.new(2, 2, 2)
    part.Anchored = true
    part.Parent = model

    model.PrimaryPart = part

    return model
end

--------------------------------------------------------------------------------
-- ZONE BASIC TESTS
--------------------------------------------------------------------------------

test("Zone.extend creates component class", "Zone", function()
    assert_not_nil(Zone, "Zone should be defined")
    assert_eq(Zone.name, "Zone", "Zone name should be 'Zone'")
    assert_eq(Zone.domain, "server", "Zone domain should be 'server'")
end)

test("Zone instance initializes with default attributes", "Zone", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    assert_eq(zone:getAttribute("DetectionMode"), "collision", "Default DetectionMode should be 'collision'")
    assert_eq(zone:getAttribute("Radius"), 10, "Default Radius should be 10")
    assert_eq(zone:getAttribute("PollInterval"), 0.1, "Default PollInterval should be 0.1")
    assert_eq(zone:getAttribute("Enabled"), true, "Default Enabled should be true")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
end)

test("Zone.In.onConfigure sets radius and mode", "Zone", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    zone.In.onConfigure(zone, {
        radius = 25,
        pollInterval = 0.5,
    })

    assert_eq(zone:getAttribute("Radius"), 25, "Radius should be 25")
    assert_eq(zone:getAttribute("PollInterval"), 0.5, "PollInterval should be 0.5")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
end)

test("Zone.In.onEnable and onDisable toggle detection", "Zone", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone:setAttribute("Enabled", false)  -- Start disabled
    zone.Sys.onInit(zone)

    assert_false(zone._enabled, "Zone should start disabled")

    zone.In.onEnable(zone)
    assert_true(zone._enabled, "Zone should be enabled after onEnable")
    assert_true(zone:getAttribute("Enabled"), "Enabled attribute should be true")

    zone.In.onDisable(zone)
    assert_false(zone._enabled, "Zone should be disabled after onDisable")
    assert_false(zone:getAttribute("Enabled"), "Enabled attribute should be false")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
end)

--------------------------------------------------------------------------------
-- FILTERING TESTS
--------------------------------------------------------------------------------

test("Zone._passesFilter allows all when no filter set", "Filtering", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    local entity = createMockEntity("Test1", "Camper")
    entity.Parent = workspace

    assert_true(zone:_passesFilter(entity), "Entity should pass with no filter")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    entity:Destroy()
end)

test("Zone._passesFilter filters by NodeClass", "Filtering", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)
    zone:setAttribute("FilterClass", "Camper")

    local camper = createMockEntity("Camper1", "Camper")
    local zombie = createMockEntity("Zombie1", "Zombie")
    camper.Parent = workspace
    zombie.Parent = workspace

    assert_true(zone:_passesFilter(camper), "Camper should pass filter")
    assert_false(zone:_passesFilter(zombie), "Zombie should not pass filter")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    camper:Destroy()
    zombie:Destroy()
end)

test("Zone._passesFilter filters by CollectionService tag", "Filtering", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)
    zone:setAttribute("FilterTag", "Brainrot")

    local tagged = createMockEntity("Tagged1", "Entity")
    local untagged = createMockEntity("Untagged1", "Entity")
    tagged.Parent = workspace
    untagged.Parent = workspace

    CollectionService:AddTag(tagged, "Brainrot")

    assert_true(zone:_passesFilter(tagged), "Tagged entity should pass filter")
    assert_false(zone:_passesFilter(untagged), "Untagged entity should not pass filter")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    tagged:Destroy()
    untagged:Destroy()
end)

test("Zone.In.onConfigure sets filter via config", "Filtering", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    zone.In.onConfigure(zone, {
        filter = {
            class = "Enemy",
            tag = "Targetable",
        },
    })

    assert_eq(zone._filterClass, "Enemy", "Filter class should be set")
    assert_eq(zone._filterTag, "Targetable", "Filter tag should be set")
    assert_not_nil(zone._filter, "Standard filter should be stored")
    assert_eq(zone._filter.class, "Enemy", "Standard filter class should match")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
end)

--------------------------------------------------------------------------------
-- STANDARD FILTER TESTS (Registry.matches integration)
--------------------------------------------------------------------------------

test("Zone uses standard filter with Registry.matches", "Standard Filter", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    -- Configure with standard filter
    zone.In.onConfigure(zone, {
        filter = {
            class = "Camper",
            spawnSource = "Tent_1",
        },
    })

    -- Create matching entity
    local matching = createMockEntity("Camper1", "Camper")
    matching:SetAttribute("NodeSpawnSource", "Tent_1")
    matching.Parent = workspace

    -- Create non-matching entity (wrong class)
    local wrongClass = createMockEntity("Zombie1", "Zombie")
    wrongClass:SetAttribute("NodeSpawnSource", "Tent_1")
    wrongClass.Parent = workspace

    -- Create non-matching entity (wrong spawnSource)
    local wrongSource = createMockEntity("Camper2", "Camper")
    wrongSource:SetAttribute("NodeSpawnSource", "Tent_2")
    wrongSource.Parent = workspace

    assert_true(zone:_passesFilter(matching), "Matching entity should pass filter")
    assert_false(zone:_passesFilter(wrongClass), "Wrong class should not pass filter")
    assert_false(zone:_passesFilter(wrongSource), "Wrong spawnSource should not pass filter")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    matching:Destroy()
    wrongClass:Destroy()
    wrongSource:Destroy()
end)

test("Zone filters with class array (multiple allowed classes)", "Standard Filter", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    -- Configure with array of allowed classes
    zone.In.onConfigure(zone, {
        filter = {
            class = { "Camper", "Hiker", "Scout" },
        },
    })

    local camper = createMockEntity("Camper1", "Camper")
    local hiker = createMockEntity("Hiker1", "Hiker")
    local zombie = createMockEntity("Zombie1", "Zombie")
    camper.Parent = workspace
    hiker.Parent = workspace
    zombie.Parent = workspace

    assert_true(zone:_passesFilter(camper), "Camper should pass filter")
    assert_true(zone:_passesFilter(hiker), "Hiker should pass filter")
    assert_false(zone:_passesFilter(zombie), "Zombie should not pass filter")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    camper:Destroy()
    hiker:Destroy()
    zombie:Destroy()
end)

test("Zone filters with attribute and operator", "Standard Filter", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    -- Configure filter for entities with Health > 50
    zone.In.onConfigure(zone, {
        filter = {
            attribute = {
                name = "Health",
                value = 50,
                operator = ">",
            },
        },
    })

    local healthy = createMockEntity("Healthy1", "Entity")
    healthy:SetAttribute("Health", 100)
    healthy.Parent = workspace

    local injured = createMockEntity("Injured1", "Entity")
    injured:SetAttribute("Health", 30)
    injured.Parent = workspace

    local atThreshold = createMockEntity("AtThreshold1", "Entity")
    atThreshold:SetAttribute("Health", 50)
    atThreshold.Parent = workspace

    assert_true(zone:_passesFilter(healthy), "Entity with Health > 50 should pass")
    assert_false(zone:_passesFilter(injured), "Entity with Health < 50 should not pass")
    assert_false(zone:_passesFilter(atThreshold), "Entity with Health = 50 should not pass (> not >=)")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    healthy:Destroy()
    injured:Destroy()
    atThreshold:Destroy()
end)

test("Zone filters with custom function", "Standard Filter", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    -- Configure filter with custom function
    zone.In.onConfigure(zone, {
        filter = {
            custom = function(entity)
                -- Only accept entities with names starting with "A"
                return string.sub(entity.Name, 1, 1) == "A"
            end,
        },
    })

    local alice = createMockEntity("Alice", "Entity")
    local bob = createMockEntity("Bob", "Entity")
    alice.Parent = workspace
    bob.Parent = workspace

    assert_true(zone:_passesFilter(alice), "Alice should pass custom filter")
    assert_false(zone:_passesFilter(bob), "Bob should not pass custom filter")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    alice:Destroy()
    bob:Destroy()
end)

test("Zone filters with status", "Standard Filter", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    zone.In.onConfigure(zone, {
        filter = {
            status = "active",
        },
    })

    local active = createMockEntity("Active1", "Entity")
    active:SetAttribute("NodeStatus", "active")
    active.Parent = workspace

    local inactive = createMockEntity("Inactive1", "Entity")
    inactive:SetAttribute("NodeStatus", "idle")
    inactive.Parent = workspace

    assert_true(zone:_passesFilter(active), "Active entity should pass")
    assert_false(zone:_passesFilter(inactive), "Inactive entity should not pass")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    active:Destroy()
    inactive:Destroy()
end)

--------------------------------------------------------------------------------
-- ENTITY DATA TESTS
--------------------------------------------------------------------------------

test("Zone._buildEntityData extracts correct information", "Zone", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    local entity = createMockEntity("TestEntity", "Camper", Vector3.new(5, 10, 15))
    entity:SetAttribute("AssetId", "spawn_42")
    entity.Parent = workspace

    local data = zone:_buildEntityData(entity)

    assert_eq(data.entity, entity, "Entity should match")
    assert_eq(data.entityId, "TestEntity", "EntityId should match NodeId attribute")
    assert_eq(data.nodeClass, "Camper", "NodeClass should match")
    assert_eq(data.assetId, "spawn_42", "AssetId should match")
    assert_not_nil(data.position, "Position should be set")
    assert_eq(data.zoneId, zone.id, "ZoneId should match zone's id")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    entity:Destroy()
end)

--------------------------------------------------------------------------------
-- SIGNAL EMISSION TESTS
--------------------------------------------------------------------------------

test("Zone fires entityEntered on _handleEnter", "Signals", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    local entity = createMockEntity("TestEntity", "Camper")
    entity.Parent = workspace

    local enteredFired = false
    local enteredData = nil
    zone.Out = {
        Fire = function(self, signal, data)
            if signal == "entityEntered" then
                enteredFired = true
                enteredData = data
            end
        end,
    }

    zone:_handleEnter(entity)

    assert_true(enteredFired, "entityEntered should fire")
    assert_eq(enteredData.entityId, "TestEntity", "EntityId should match")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    entity:Destroy()
end)

test("Zone fires entityExited on _handleExit", "Signals", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    local entity = createMockEntity("TestEntity", "Camper")
    entity.Parent = workspace

    -- First enter the zone
    zone._entitiesInZone[entity] = true

    local exitedFired = false
    local exitedData = nil
    zone.Out = {
        Fire = function(self, signal, data)
            if signal == "entityExited" then
                exitedFired = true
                exitedData = data
            end
        end,
    }

    zone:_handleExit(entity)

    assert_true(exitedFired, "entityExited should fire")
    assert_eq(exitedData.entityId, "TestEntity", "EntityId should match")
    assert_nil(zone._entitiesInZone[entity], "Entity should be removed from tracking")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    entity:Destroy()
end)

test("Zone does not fire duplicate entityEntered", "Signals", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    local entity = createMockEntity("TestEntity", "Camper")
    entity.Parent = workspace

    local enterCount = 0
    zone.Out = {
        Fire = function(self, signal, data)
            if signal == "entityEntered" then
                enterCount = enterCount + 1
            end
        end,
    }

    zone:_handleEnter(entity)
    zone:_handleEnter(entity)
    zone:_handleEnter(entity)

    assert_eq(enterCount, 1, "entityEntered should only fire once per entity")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    entity:Destroy()
end)

test("Zone does not fire entityExited for entity not in zone", "Signals", function()
    local zonePart = createMockZonePart()
    zonePart.Parent = workspace

    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    local entity = createMockEntity("TestEntity", "Camper")
    entity.Parent = workspace

    local exitCount = 0
    zone.Out = {
        Fire = function(self, signal, data)
            if signal == "entityExited" then
                exitCount = exitCount + 1
            end
        end,
    }

    zone:_handleExit(entity)  -- Never entered

    assert_eq(exitCount, 0, "entityExited should not fire for entity not in zone")

    zone.Sys.onStop(zone)
    zonePart:Destroy()
    entity:Destroy()
end)

--------------------------------------------------------------------------------
-- VISUAL DEMO
--------------------------------------------------------------------------------

local demoInstances = {}

function Tests.demo()
    print("\n========================================")
    print("  Zone Visual Demo")
    print("========================================")
    print("Watch entities enter/exit the zone...\n")

    -- Reset any previous demo
    Tests.cleanup()

    -- Create zone part (visible red box)
    local zonePart = Instance.new("Part")
    zonePart.Name = "DemoZone"
    zonePart.Size = Vector3.new(15, 5, 15)
    zonePart.Position = Vector3.new(0, 2.5, 0)
    zonePart.Anchored = true
    zonePart.CanCollide = false
    zonePart.Transparency = 0.7
    zonePart.BrickColor = BrickColor.new("Bright red")
    zonePart.Material = Enum.Material.Neon
    zonePart.Parent = workspace
    table.insert(demoInstances, zonePart)

    -- Create zone component
    local zone = Zone:new({ model = zonePart })
    zone.Sys.onInit(zone)

    -- Track events
    zone.Out = {
        Fire = function(self, signal, data)
            if signal == "entityEntered" then
                print(string.format("  [ENTER] %s (%s) at position %s",
                    data.entityId,
                    data.nodeClass,
                    tostring(data.position)))
            elseif signal == "entityExited" then
                print(string.format("  [EXIT] %s", data.entityId))
            end
        end,
    }

    -- Spawn entities that move through the zone
    print("Spawning entities that will pass through the zone...\n")

    task.spawn(function()
        for i = 1, 5 do
            -- Create entity outside zone
            local entity = Instance.new("Model")
            entity.Name = "Entity_" .. i
            entity:SetAttribute("NodeId", "Entity_" .. i)
            entity:SetAttribute("NodeClass", "DemoEntity")

            local part = Instance.new("Part")
            part.Name = "HumanoidRootPart"
            part.Size = Vector3.new(3, 3, 3)
            part.Position = Vector3.new(-25, 3, (i - 3) * 8)
            part.Anchored = true
            part.BrickColor = BrickColor.new("Bright blue")
            part.Material = Enum.Material.SmoothPlastic
            part.Parent = entity

            entity.PrimaryPart = part
            entity.Parent = workspace
            table.insert(demoInstances, entity)

            -- Animate entity moving through zone
            task.spawn(function()
                local startX = -25
                local endX = 25
                local duration = 4
                local startTime = os.clock()

                while os.clock() - startTime < duration do
                    local t = (os.clock() - startTime) / duration
                    local x = startX + (endX - startX) * t
                    part.Position = Vector3.new(x, 3, (i - 3) * 8)
                    task.wait()
                end

                -- Entity has passed through
                part.Position = Vector3.new(endX, 3, (i - 3) * 8)
            end)

            task.wait(0.8)  -- Stagger spawns
        end

        task.wait(5)
        print("\n========================================")
        print("  Demo complete!")
        print("  Run Tests.Zone.cleanup() to remove instances.")
        print("========================================")
    end)

    -- Store zone for cleanup
    table.insert(demoInstances, zone)
end

function Tests.cleanup()
    print("Cleaning up demo instances...")

    for _, instance in ipairs(demoInstances) do
        if typeof(instance) == "table" and instance.Sys then
            -- It's a Zone node
            instance.Sys.onStop(instance)
        elseif typeof(instance) == "Instance" and instance.Parent then
            instance:Destroy()
        end
    end
    demoInstances = {}

    print("Cleanup complete.")
end

return Tests
