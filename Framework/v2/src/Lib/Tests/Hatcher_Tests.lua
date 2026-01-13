--[[
    LibPureFiction Framework v2
    Hatcher & SpawnerCore Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Hatcher.runAll()
    ```

    Or run specific test groups:

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Hatcher.runGroup("SpawnerCore")
    Tests.Hatcher.runGroup("Hatcher")
    Tests.Hatcher.runGroup("Weighted Selection")
    Tests.Hatcher.runGroup("Pity System")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local Hatcher = Lib.Components.Hatcher
local Debug = Lib.System.Debug

-- Access SpawnerCore directly for testing (it's internal but we need to test it)
local SpawnerCore = require(ReplicatedStorage.Lib.Internal.SpawnerCore)

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

local function assert_type(value, expectedType, message)
    local actualType = typeof(value)
    if actualType ~= expectedType then
        error(string.format("%s: expected type %s, got %s",
            message or "Type mismatch",
            expectedType,
            actualType), 2)
    end
end

local function assert_near(actual, expected, tolerance, message)
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %s ± %s, got %s",
            message or "Value not near expected",
            tostring(expected),
            tostring(tolerance),
            tostring(actual)), 2)
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
    print("  Hatcher & SpawnerCore Test Suite")
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

-- Create a mock template folder with test templates
local function createMockTemplates()
    local folder = Instance.new("Folder")
    folder.Name = "MockTemplates"

    -- Common template
    local common = Instance.new("Part")
    common.Name = "CommonItem"
    common.Size = Vector3.new(1, 1, 1)
    common.Parent = folder

    -- Rare template
    local rare = Instance.new("Part")
    rare.Name = "RareItem"
    rare.Size = Vector3.new(2, 2, 2)
    rare.Parent = folder

    -- Legendary template (as a Model)
    local legendary = Instance.new("Model")
    legendary.Name = "LegendaryItem"
    local legendaryPart = Instance.new("Part")
    legendaryPart.Name = "Main"
    legendaryPart.Parent = legendary
    legendary.PrimaryPart = legendaryPart
    legendary.Parent = folder

    return folder
end

-- Create a mock player object
local function createMockPlayer(userId, name)
    return {
        UserId = userId or 12345,
        Name = name or "TestPlayer",
    }
end

--------------------------------------------------------------------------------
-- SPAWNERCORE TESTS
--------------------------------------------------------------------------------

test("SpawnerCore.init initializes module", "SpawnerCore", function()
    SpawnerCore.reset()
    assert_false(SpawnerCore.isInitialized(), "Should not be initialized before init")

    SpawnerCore.init({})
    assert_true(SpawnerCore.isInitialized(), "Should be initialized after init")

    SpawnerCore.reset()
end)

test("SpawnerCore.init accepts template sources", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()

    SpawnerCore.init({ templates = folder })

    local sources = SpawnerCore.getTemplateSources()
    assert_eq(#sources, 1, "Should have one template source")

    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.resolveTemplate finds templates", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()

    SpawnerCore.init({ templates = folder })

    local template = SpawnerCore.resolveTemplate("CommonItem")
    assert_not_nil(template, "Should find CommonItem template")
    assert_eq(template.Name, "CommonItem", "Template name should match")

    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.resolveTemplate returns nil for missing templates", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()

    SpawnerCore.init({ templates = folder })

    local template, err = SpawnerCore.resolveTemplate("NonExistent")
    assert_nil(template, "Should not find non-existent template")
    assert_not_nil(err, "Should return error message")

    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.spawn clones template and assigns ID", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.init({ templates = folder })

    local result = SpawnerCore.spawn({
        templateName = "CommonItem",
        parent = workspace,
    })

    assert_not_nil(result, "Spawn should return result")
    assert_not_nil(result.instance, "Result should have instance")
    assert_not_nil(result.assetId, "Result should have assetId")
    assert_eq(result.instance:GetAttribute("AssetId"), result.assetId, "Instance should have AssetId attribute")

    -- Cleanup
    result.instance:Destroy()
    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.spawn applies attributes", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.init({ templates = folder })

    local result = SpawnerCore.spawn({
        templateName = "CommonItem",
        parent = workspace,
        attributes = {
            Rarity = "Common",
            Value = 100,
        },
    })

    assert_eq(result.instance:GetAttribute("Rarity"), "Common", "Should have Rarity attribute")
    assert_eq(result.instance:GetAttribute("Value"), 100, "Should have Value attribute")

    result.instance:Destroy()
    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.spawn positions instance", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.init({ templates = folder })

    local targetPos = Vector3.new(10, 20, 30)
    local result = SpawnerCore.spawn({
        templateName = "CommonItem",
        parent = workspace,
        position = targetPos,
    })

    local instancePos = result.instance.Position
    assert_near(instancePos.X, targetPos.X, 0.1, "X position should match")
    assert_near(instancePos.Y, targetPos.Y, 0.1, "Y position should match")
    assert_near(instancePos.Z, targetPos.Z, 0.1, "Z position should match")

    result.instance:Destroy()
    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.despawn removes instance and tracking", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.init({ templates = folder })

    local result = SpawnerCore.spawn({
        templateName = "CommonItem",
        parent = workspace,
    })

    local assetId = result.assetId
    assert_not_nil(SpawnerCore.getInstance(assetId), "Instance should be tracked")

    local success = SpawnerCore.despawn(assetId)
    assert_true(success, "Despawn should succeed")
    assert_nil(SpawnerCore.getInstance(assetId), "Instance should no longer be tracked")

    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.getInstanceCount tracks spawned instances", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.init({ templates = folder })

    assert_eq(SpawnerCore.getInstanceCount(), 0, "Should start with 0 instances")

    local result1 = SpawnerCore.spawn({ templateName = "CommonItem", parent = workspace })
    assert_eq(SpawnerCore.getInstanceCount(), 1, "Should have 1 instance")

    local result2 = SpawnerCore.spawn({ templateName = "RareItem", parent = workspace })
    assert_eq(SpawnerCore.getInstanceCount(), 2, "Should have 2 instances")

    SpawnerCore.despawn(result1.assetId)
    assert_eq(SpawnerCore.getInstanceCount(), 1, "Should have 1 instance after despawn")

    result2.instance:Destroy()
    folder:Destroy()
    SpawnerCore.reset()
end)

test("SpawnerCore.cleanup removes all instances", "SpawnerCore", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.init({ templates = folder })

    SpawnerCore.spawn({ templateName = "CommonItem", parent = workspace })
    SpawnerCore.spawn({ templateName = "RareItem", parent = workspace })
    SpawnerCore.spawn({ templateName = "CommonItem", parent = workspace })

    assert_eq(SpawnerCore.getInstanceCount(), 3, "Should have 3 instances")

    SpawnerCore.cleanup()
    assert_eq(SpawnerCore.getInstanceCount(), 0, "Should have 0 instances after cleanup")

    folder:Destroy()
    SpawnerCore.reset()
end)

--------------------------------------------------------------------------------
-- HATCHER COMPONENT TESTS
--------------------------------------------------------------------------------

test("Hatcher.extend creates component class", "Hatcher", function()
    assert_not_nil(Hatcher, "Hatcher should be defined")
    assert_eq(Hatcher.name, "Hatcher", "Hatcher name should be 'Hatcher'")
    assert_eq(Hatcher.domain, "server", "Hatcher domain should be 'server'")
end)

test("Hatcher instance initializes with default attributes", "Hatcher", function()
    local instance = Hatcher:new({ id = "TestHatcher_1" })
    instance.Sys.onInit(instance)  -- Call lifecycle manually for testing

    assert_eq(instance:getAttribute("HatchTime"), 0, "Default HatchTime should be 0")
    assert_eq(instance:getAttribute("Cost"), 0, "Default Cost should be 0")
    assert_eq(instance:getAttribute("CostType"), "", "Default CostType should be empty")
    assert_eq(instance:getAttribute("PityThreshold"), 0, "Default PityThreshold should be 0")
end)

test("Hatcher.In.onConfigure sets pool", "Hatcher", function()
    local instance = Hatcher:new({ id = "TestHatcher_2" })
    instance.Sys.onInit(instance)

    local pool = {
        { template = "CommonItem", rarity = "Common", weight = 60 },
        { template = "RareItem", rarity = "Rare", weight = 30 },
    }

    instance.In.onConfigure(instance, { pool = pool })

    assert_eq(instance._pool, pool, "Pool should be set")
    assert_eq(instance._totalWeight, 90, "Total weight should be 90")
end)

test("Hatcher.In.onConfigure rejects invalid pool", "Hatcher", function()
    local instance = Hatcher:new({ id = "TestHatcher_3" })
    instance.Sys.onInit(instance)

    local errFired = false
    instance.Err = {
        Fire = function(self, data)
            errFired = true
            assert_eq(data.reason, "invalid_pool", "Error reason should be 'invalid_pool'")
        end,
    }

    instance.In.onConfigure(instance, { pool = {} })  -- Empty pool
    assert_nil(instance._pool, "Pool should not be set")
end)

test("Hatcher._selectFromPool uses weighted selection", "Weighted Selection", function()
    local instance = Hatcher:new({ id = "TestHatcher_4" })
    instance.Sys.onInit(instance)

    local pool = {
        { template = "CommonItem", rarity = "Common", weight = 100 },
        { template = "RareItem", rarity = "Rare", weight = 0 },  -- Zero weight = never selected
    }

    instance.In.onConfigure(instance, { pool = pool })

    -- With 100% weight on Common, should always select Common
    for i = 1, 10 do
        local result = instance:_selectFromPool()
        assert_eq(result.template, "CommonItem", "Should always select CommonItem with 100% weight")
    end
end)

test("Hatcher._selectFromPool respects weight distribution", "Weighted Selection", function()
    local instance = Hatcher:new({ id = "TestHatcher_5" })
    instance.Sys.onInit(instance)

    -- 50/50 split
    local pool = {
        { template = "A", rarity = "A", weight = 50 },
        { template = "B", rarity = "B", weight = 50 },
    }

    instance.In.onConfigure(instance, { pool = pool })

    local counts = { A = 0, B = 0 }
    local iterations = 1000

    for i = 1, iterations do
        local result = instance:_selectFromPool()
        counts[result.template] = counts[result.template] + 1
    end

    -- With 50/50 split, each should be roughly 500 ± 100 (generous tolerance)
    assert_true(counts.A > 300 and counts.A < 700,
        string.format("A count should be roughly 500, got %d", counts.A))
    assert_true(counts.B > 300 and counts.B < 700,
        string.format("B count should be roughly 500, got %d", counts.B))
end)

test("Hatcher pity counter increments per player", "Pity System", function()
    local instance = Hatcher:new({ id = "TestHatcher_6" })
    instance.Sys.onInit(instance)

    local player1 = createMockPlayer(1, "Player1")
    local player2 = createMockPlayer(2, "Player2")

    assert_eq(instance:_getPityCount(player1), 0, "Player1 pity should start at 0")
    assert_eq(instance:_getPityCount(player2), 0, "Player2 pity should start at 0")

    instance:_incrementPity(player1)
    instance:_incrementPity(player1)
    instance:_incrementPity(player2)

    assert_eq(instance:_getPityCount(player1), 2, "Player1 pity should be 2")
    assert_eq(instance:_getPityCount(player2), 1, "Player2 pity should be 1")
end)

test("Hatcher pity resets after triggering", "Pity System", function()
    local instance = Hatcher:new({ id = "TestHatcher_7" })
    instance.Sys.onInit(instance)

    local player = createMockPlayer(1, "Player1")

    instance:_incrementPity(player)
    instance:_incrementPity(player)
    instance:_incrementPity(player)

    assert_eq(instance:_getPityCount(player), 3, "Pity should be 3")

    instance:_resetPity(player)

    assert_eq(instance:_getPityCount(player), 0, "Pity should be 0 after reset")
end)

test("Hatcher._shouldTriggerPity respects threshold", "Pity System", function()
    local instance = Hatcher:new({ id = "TestHatcher_8" })
    instance.Sys.onInit(instance)
    instance:setAttribute("PityThreshold", 5)

    local player = createMockPlayer(1, "Player1")

    for i = 1, 4 do
        instance:_incrementPity(player)
        assert_false(instance:_shouldTriggerPity(player),
            string.format("Should not trigger pity at count %d", i))
    end

    instance:_incrementPity(player)  -- Now at 5
    assert_true(instance:_shouldTriggerPity(player), "Should trigger pity at threshold")
end)

test("Hatcher._getPityItem returns item with pity=true", "Pity System", function()
    local instance = Hatcher:new({ id = "TestHatcher_9" })
    instance.Sys.onInit(instance)

    local pool = {
        { template = "Common", rarity = "Common", weight = 90 },
        { template = "Legendary", rarity = "Legendary", weight = 10, pity = true },
    }

    instance.In.onConfigure(instance, { pool = pool })

    local pityItem = instance:_getPityItem()
    assert_not_nil(pityItem, "Should find pity item")
    assert_eq(pityItem.template, "Legendary", "Pity item should be Legendary")
end)

test("Hatcher.In.onSetPity manually sets counter", "Pity System", function()
    local instance = Hatcher:new({ id = "TestHatcher_10" })
    instance.Sys.onInit(instance)

    local player = createMockPlayer(1, "Player1")

    instance.In.onSetPity(instance, { player = player, count = 10 })

    assert_eq(instance:_getPityCount(player), 10, "Pity should be set to 10")
end)

test("Hatcher fires hatchFailed when no pool configured", "Hatcher", function()
    local instance = Hatcher:new({ id = "TestHatcher_11" })
    instance.Sys.onInit(instance)

    local failedFired = false
    instance.Out = {
        Fire = function(self, signal, data)
            if signal == "hatchFailed" then
                failedFired = true
                assert_eq(data.reason, "no_pool", "Reason should be 'no_pool'")
            end
        end,
    }

    instance.In.onHatch(instance, { player = createMockPlayer() })

    assert_true(failedFired, "hatchFailed should be fired")
end)

test("Hatcher fires costCheck when cost > 0", "Hatcher", function()
    local instance = Hatcher:new({ id = "TestHatcher_12" })
    instance.Sys.onInit(instance)
    instance:setAttribute("Cost", 100)
    instance:setAttribute("CostType", "Gems")
    instance:setAttribute("CostConfirmTimeout", 0.1)  -- Short timeout for test

    local pool = {
        { template = "CommonItem", rarity = "Common", weight = 100 },
    }
    instance.In.onConfigure(instance, { pool = pool })

    local costCheckFired = false
    local failedFired = false
    instance.Out = {
        Fire = function(self, signal, data)
            if signal == "costCheck" then
                costCheckFired = true
                assert_eq(data.cost, 100, "Cost should be 100")
                assert_eq(data.costType, "Gems", "CostType should be 'Gems'")
            elseif signal == "hatchFailed" then
                failedFired = true
            end
        end,
    }

    -- Start hatch in a thread (it will wait for confirmation)
    task.spawn(function()
        instance.In.onHatch(instance, { player = createMockPlayer() })
    end)

    task.wait(0.05)  -- Give time for costCheck to fire
    assert_true(costCheckFired, "costCheck should be fired")
end)

test("Hatcher skips costCheck when cost is 0", "Hatcher", function()
    SpawnerCore.reset()
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.init({ templates = folder })

    local instance = Hatcher:new({ id = "TestHatcher_13" })
    instance.Sys.onInit(instance)
    instance:setAttribute("Cost", 0)
    instance:setAttribute("HatchTime", 0)

    local pool = {
        { template = "CommonItem", rarity = "Common", weight = 100 },
    }
    instance.In.onConfigure(instance, { pool = pool })

    local costCheckFired = false
    local hatchStartedFired = false
    instance.Out = {
        Fire = function(self, signal, data)
            if signal == "costCheck" then
                costCheckFired = true
            elseif signal == "hatchStarted" then
                hatchStartedFired = true
            end
        end,
    }

    instance.In.onHatch(instance, { player = createMockPlayer() })

    task.wait(0.1)  -- Give time for async hatch
    assert_false(costCheckFired, "costCheck should NOT be fired when cost is 0")
    assert_true(hatchStartedFired, "hatchStarted should be fired")

    folder:Destroy()
    SpawnerCore.reset()
end)

return Tests
