--[[
    Warren Framework v2
    Dropper Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.Dropper.runAll()
    ```

    Or run specific test groups:

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.Dropper.runGroup("Pool Selection")
    Tests.Dropper.runGroup("Capacity")
    Tests.Dropper.runGroup("onDispense")
    Tests.Dropper.runGroup("onRefill")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local Node = Lib.Node
local Dropper = Lib.Components.Dropper

-- Access SpawnerCore directly for testing
local SpawnerCore = require(ReplicatedStorage.Warren.Internal.SpawnerCore)

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

local function assert_contains(tbl, value, message)
    for _, v in ipairs(tbl) do
        if v == value then return end
    end
    error(message or string.format("Table does not contain %s", tostring(value)), 2)
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
    print("  Dropper Test Suite")
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

    -- Create multiple templates for pool testing
    local templates = { "Sword", "Shield", "Potion", "Helmet", "Boots" }
    for _, name in ipairs(templates) do
        local part = Instance.new("Part")
        part.Name = name
        part.Size = Vector3.new(1, 1, 1)
        part.Anchored = true
        part.Parent = folder
    end

    return folder
end

-- Create a mock dropper instance with templates initialized
local function createTestDropper(id)
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.reset()
    SpawnerCore.init({ templates = folder })

    local dropper = Dropper:new({ id = id or "TestDropper" })
    dropper.Sys.onInit(dropper)

    -- Track for cleanup
    dropper._testFolder = folder

    return dropper
end

-- Cleanup a test dropper
local function cleanupDropper(dropper)
    if dropper._testFolder then
        dropper._testFolder:Destroy()
    end
    dropper:_despawnAll()
    SpawnerCore.reset()
end

-- Capture output signals
local function captureOutput(dropper)
    local captured = {
        spawned = {},
        despawned = {},
        depleted = {},
        loopStarted = {},
        loopStopped = {},
    }

    dropper.Out = {
        Fire = function(self, signal, data)
            if captured[signal] then
                table.insert(captured[signal], data)
            end
        end,
    }

    return captured
end

--------------------------------------------------------------------------------
-- BASIC DROPPER TESTS
--------------------------------------------------------------------------------

test("Dropper.extend creates component class", "Dropper Basics", function()
    assert_not_nil(Dropper, "Dropper should be defined")
    assert_eq(Dropper.name, "Dropper", "Dropper name should be 'Dropper'")
    assert_eq(Dropper.domain, "server", "Dropper domain should be 'server'")
end)

test("Dropper instance initializes with default attributes", "Dropper Basics", function()
    local dropper = createTestDropper("TestDropper_Defaults")

    assert_eq(dropper:getAttribute("Interval"), 2, "Default Interval should be 2")
    assert_eq(dropper:getAttribute("MaxActive"), 0, "Default MaxActive should be 0")
    assert_eq(dropper:getAttribute("PoolMode"), "single", "Default PoolMode should be 'single'")
    assert_eq(dropper:getAttribute("AutoStart"), false, "Default AutoStart should be false")

    cleanupDropper(dropper)
end)

test("Dropper initializes pool state", "Dropper Basics", function()
    local dropper = createTestDropper("TestDropper_PoolState")

    assert_nil(dropper._pool, "_pool should be nil initially")
    assert_eq(dropper._poolIndex, 0, "_poolIndex should be 0 initially")
    assert_nil(dropper._capacity, "_capacity should be nil initially")
    assert_nil(dropper._remaining, "_remaining should be nil initially")

    cleanupDropper(dropper)
end)

--------------------------------------------------------------------------------
-- POOL CONFIGURATION TESTS
--------------------------------------------------------------------------------

test("onConfigure sets pool array", "Pool Configuration", function()
    local dropper = createTestDropper("TestDropper_Pool1")

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield", "Potion" },
    })

    assert_not_nil(dropper._pool, "Pool should be set")
    assert_eq(#dropper._pool, 3, "Pool should have 3 items")
    assert_eq(dropper._pool[1], "Sword", "First item should be Sword")
    assert_eq(dropper._pool[2], "Shield", "Second item should be Shield")
    assert_eq(dropper._pool[3], "Potion", "Third item should be Potion")

    cleanupDropper(dropper)
end)

test("onConfigure sets poolMode", "Pool Configuration", function()
    local dropper = createTestDropper("TestDropper_PoolMode")

    dropper.In.onConfigure(dropper, {
        poolMode = "sequential",
    })

    assert_eq(dropper:getAttribute("PoolMode"), "sequential", "PoolMode should be 'sequential'")

    dropper.In.onConfigure(dropper, {
        poolMode = "random",
    })

    assert_eq(dropper:getAttribute("PoolMode"), "random", "PoolMode should be 'random'")

    cleanupDropper(dropper)
end)

test("onConfigure resets poolIndex when pool changes", "Pool Configuration", function()
    local dropper = createTestDropper("TestDropper_PoolReset")

    dropper._poolIndex = 5  -- Simulate previous usage

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield" },
    })

    assert_eq(dropper._poolIndex, 0, "poolIndex should reset to 0 when pool changes")

    cleanupDropper(dropper)
end)

--------------------------------------------------------------------------------
-- POOL SELECTION TESTS
--------------------------------------------------------------------------------

test("_selectTemplate returns single template when no pool", "Pool Selection", function()
    local dropper = createTestDropper("TestDropper_SingleTemplate")

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
    })

    local template = dropper:_selectTemplate()
    assert_eq(template, "Sword", "Should return single templateName")

    cleanupDropper(dropper)
end)

test("_selectTemplate returns override when provided", "Pool Selection", function()
    local dropper = createTestDropper("TestDropper_Override")

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield", "Potion" },
        poolMode = "sequential",
    })

    local template = dropper:_selectTemplate("Helmet")
    assert_eq(template, "Helmet", "Should return override template")

    -- Pool index should not change
    assert_eq(dropper._poolIndex, 0, "poolIndex should not change on override")

    cleanupDropper(dropper)
end)

test("_selectTemplate sequential mode cycles through pool", "Pool Selection", function()
    local dropper = createTestDropper("TestDropper_Sequential")

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield", "Potion" },
        poolMode = "sequential",
    })

    -- First cycle
    assert_eq(dropper:_selectTemplate(), "Sword", "First should be Sword")
    assert_eq(dropper:_selectTemplate(), "Shield", "Second should be Shield")
    assert_eq(dropper:_selectTemplate(), "Potion", "Third should be Potion")

    -- Second cycle (wraps around)
    assert_eq(dropper:_selectTemplate(), "Sword", "Fourth should wrap to Sword")
    assert_eq(dropper:_selectTemplate(), "Shield", "Fifth should be Shield")

    cleanupDropper(dropper)
end)

test("_selectTemplate random mode picks from pool", "Pool Selection", function()
    local dropper = createTestDropper("TestDropper_Random")

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield", "Potion" },
        poolMode = "random",
    })

    local validTemplates = { Sword = true, Shield = true, Potion = true }
    local seenTemplates = {}

    -- Run multiple times to verify randomness
    for i = 1, 30 do
        local template = dropper:_selectTemplate()
        assert_true(validTemplates[template], "Template should be from pool")
        seenTemplates[template] = true
    end

    -- With 30 iterations, we should have seen all 3 templates
    local seenCount = 0
    for _ in pairs(seenTemplates) do seenCount = seenCount + 1 end
    assert_true(seenCount >= 2, "Should see at least 2 different templates in 30 picks")

    cleanupDropper(dropper)
end)

test("_selectTemplate single mode uses first pool item", "Pool Selection", function()
    local dropper = createTestDropper("TestDropper_SingleMode")

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield", "Potion" },
        poolMode = "single",
    })

    -- Should always return first item
    for i = 1, 5 do
        assert_eq(dropper:_selectTemplate(), "Sword", "Should always return first item")
    end

    cleanupDropper(dropper)
end)

--------------------------------------------------------------------------------
-- CAPACITY TESTS
--------------------------------------------------------------------------------

test("onConfigure sets capacity", "Capacity", function()
    local dropper = createTestDropper("TestDropper_Capacity1")

    dropper.In.onConfigure(dropper, {
        capacity = 10,
    })

    assert_eq(dropper._capacity, 10, "_capacity should be 10")
    assert_eq(dropper._remaining, 10, "_remaining should be 10")
    assert_eq(dropper:getAttribute("Capacity"), 10, "Capacity attribute should be 10")

    cleanupDropper(dropper)
end)

test("_canSpawn respects capacity", "Capacity", function()
    local dropper = createTestDropper("TestDropper_CapacityCheck")

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 2,
    })

    assert_true(dropper:_canSpawn(), "Should be able to spawn with capacity 2")

    dropper._remaining = 0

    assert_false(dropper:_canSpawn(), "Should not be able to spawn with 0 remaining")

    cleanupDropper(dropper)
end)

test("_spawn decrements remaining capacity", "Capacity", function()
    local dropper = createTestDropper("TestDropper_DecrementCapacity")
    captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 5,
    })

    assert_eq(dropper._remaining, 5, "Should start with 5 remaining")

    dropper:_spawn()
    assert_eq(dropper._remaining, 4, "Should have 4 remaining after spawn")

    dropper:_spawn()
    assert_eq(dropper._remaining, 3, "Should have 3 remaining after spawn")

    cleanupDropper(dropper)
end)

test("_spawn fires depleted when capacity exhausted", "Capacity", function()
    local dropper = createTestDropper("TestDropper_Depleted")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 2,
    })

    dropper:_spawn()
    assert_eq(#captured.depleted, 0, "Should not fire depleted after first spawn")

    dropper:_spawn()
    assert_eq(#captured.depleted, 1, "Should fire depleted when capacity exhausted")
    assert_eq(captured.depleted[1].dropperId, dropper.id, "depleted should include dropperId")

    cleanupDropper(dropper)
end)

test("unlimited capacity does not fire depleted", "Capacity", function()
    local dropper = createTestDropper("TestDropper_UnlimitedCapacity")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        -- No capacity = unlimited
    })

    for i = 1, 10 do
        dropper:_spawn()
    end

    assert_eq(#captured.depleted, 0, "Should never fire depleted with unlimited capacity")
    assert_nil(dropper._remaining, "_remaining should be nil for unlimited")

    cleanupDropper(dropper)
end)

test("Remaining attribute is updated on spawn", "Capacity", function()
    local dropper = createTestDropper("TestDropper_RemainingAttr")
    captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 3,
    })

    dropper:_spawn()
    assert_eq(dropper:getAttribute("Remaining"), 2, "Remaining attribute should be 2")

    dropper:_spawn()
    assert_eq(dropper:getAttribute("Remaining"), 1, "Remaining attribute should be 1")

    dropper:_spawn()
    assert_eq(dropper:getAttribute("Remaining"), 0, "Remaining attribute should be 0")

    cleanupDropper(dropper)
end)

--------------------------------------------------------------------------------
-- ONDISPENSE TESTS
--------------------------------------------------------------------------------

test("onDispense spawns one item by default", "onDispense", function()
    local dropper = createTestDropper("TestDropper_DispenseOne")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
    })

    dropper.In.onDispense(dropper)

    assert_eq(#captured.spawned, 1, "Should spawn exactly one item")

    cleanupDropper(dropper)
end)

test("onDispense spawns specified count", "onDispense", function()
    local dropper = createTestDropper("TestDropper_DispenseCount")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
    })

    dropper.In.onDispense(dropper, { count = 3 })

    assert_eq(#captured.spawned, 3, "Should spawn exactly 3 items")

    cleanupDropper(dropper)
end)

test("onDispense respects capacity limit", "onDispense", function()
    local dropper = createTestDropper("TestDropper_DispenseCapacity")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 2,
    })

    -- Try to spawn 5, but capacity is 2
    dropper.In.onDispense(dropper, { count = 5 })

    assert_eq(#captured.spawned, 2, "Should only spawn 2 items (capacity limit)")
    assert_eq(#captured.depleted, 1, "Should fire depleted")

    cleanupDropper(dropper)
end)

test("onDispense respects maxActive limit", "onDispense", function()
    local dropper = createTestDropper("TestDropper_DispenseMaxActive")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        maxActive = 3,
    })

    -- Try to spawn 5, but maxActive is 3
    dropper.In.onDispense(dropper, { count = 5 })

    assert_eq(#captured.spawned, 3, "Should only spawn 3 items (maxActive limit)")

    cleanupDropper(dropper)
end)

test("onDispense uses template override", "onDispense", function()
    local dropper = createTestDropper("TestDropper_DispenseOverride")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
    })

    dropper.In.onDispense(dropper, { templateName = "Shield" })

    assert_eq(#captured.spawned, 1, "Should spawn one item")
    assert_eq(captured.spawned[1].templateName, "Shield", "Should use override template")

    cleanupDropper(dropper)
end)

test("onDispense uses pool selection", "onDispense", function()
    local dropper = createTestDropper("TestDropper_DispensePool")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield", "Potion" },
        poolMode = "sequential",
    })

    dropper.In.onDispense(dropper, { count = 3 })

    assert_eq(#captured.spawned, 3, "Should spawn 3 items")
    assert_eq(captured.spawned[1].templateName, "Sword", "First should be Sword")
    assert_eq(captured.spawned[2].templateName, "Shield", "Second should be Shield")
    assert_eq(captured.spawned[3].templateName, "Potion", "Third should be Potion")

    cleanupDropper(dropper)
end)

test("onDispense with empty data spawns one", "onDispense", function()
    local dropper = createTestDropper("TestDropper_DispenseEmpty")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
    })

    dropper.In.onDispense(dropper)  -- No data argument

    assert_eq(#captured.spawned, 1, "Should spawn one item with no data")

    cleanupDropper(dropper)
end)

--------------------------------------------------------------------------------
-- ONREFILL TESTS
--------------------------------------------------------------------------------

test("onRefill restores full capacity", "onRefill", function()
    local dropper = createTestDropper("TestDropper_RefillFull")
    captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 10,
    })

    -- Drain capacity
    for i = 1, 10 do
        dropper:_spawn()
    end

    assert_eq(dropper._remaining, 0, "Should be empty")

    dropper.In.onRefill(dropper)

    assert_eq(dropper._remaining, 10, "Should be refilled to 10")
    assert_eq(dropper:getAttribute("Remaining"), 10, "Remaining attribute should be 10")

    cleanupDropper(dropper)
end)

test("onRefill with amount adds partial refill", "onRefill", function()
    local dropper = createTestDropper("TestDropper_RefillPartial")
    captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 10,
    })

    -- Drain completely
    for i = 1, 10 do
        dropper:_spawn()
    end

    assert_eq(dropper._remaining, 0, "Should be empty")

    dropper.In.onRefill(dropper, { amount = 3 })

    assert_eq(dropper._remaining, 3, "Should have 3 remaining")

    dropper.In.onRefill(dropper, { amount = 5 })

    assert_eq(dropper._remaining, 8, "Should have 8 remaining")

    cleanupDropper(dropper)
end)

test("onRefill caps at capacity", "onRefill", function()
    local dropper = createTestDropper("TestDropper_RefillCap")
    captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 10,
    })

    -- Partial use
    dropper:_spawn()
    dropper:_spawn()
    assert_eq(dropper._remaining, 8, "Should have 8 remaining")

    -- Try to overfill
    dropper.In.onRefill(dropper, { amount = 100 })

    assert_eq(dropper._remaining, 10, "Should cap at capacity (10)")

    cleanupDropper(dropper)
end)

test("onRefill does nothing with unlimited capacity", "onRefill", function()
    local dropper = createTestDropper("TestDropper_RefillUnlimited")
    captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        -- No capacity = unlimited
    })

    dropper.In.onRefill(dropper)

    assert_nil(dropper._remaining, "_remaining should still be nil")

    cleanupDropper(dropper)
end)

test("onRefill enables spawning after depletion", "onRefill", function()
    local dropper = createTestDropper("TestDropper_RefillRespawn")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 2,
    })

    -- Exhaust capacity
    dropper.In.onDispense(dropper, { count = 2 })
    assert_eq(#captured.spawned, 2, "Should spawn 2")
    assert_eq(#captured.depleted, 1, "Should fire depleted")

    -- Try to spawn more (should fail)
    dropper.In.onDispense(dropper, { count = 1 })
    assert_eq(#captured.spawned, 2, "Should still be 2 (can't spawn)")

    -- Refill
    dropper.In.onRefill(dropper, { amount = 1 })

    -- Now can spawn again
    dropper.In.onDispense(dropper, { count = 1 })
    assert_eq(#captured.spawned, 3, "Should now have 3 spawned")

    cleanupDropper(dropper)
end)

--------------------------------------------------------------------------------
-- SPAWNED OUTPUT TESTS
--------------------------------------------------------------------------------

test("spawned signal includes templateName", "Output Signals", function()
    local dropper = createTestDropper("TestDropper_SpawnedTemplate")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        pool = { "Sword", "Shield" },
        poolMode = "sequential",
    })

    dropper.In.onDispense(dropper, { count = 2 })

    assert_eq(captured.spawned[1].templateName, "Sword", "First spawned should have templateName 'Sword'")
    assert_eq(captured.spawned[2].templateName, "Shield", "Second spawned should have templateName 'Shield'")

    cleanupDropper(dropper)
end)

test("spawned signal includes all required fields", "Output Signals", function()
    local dropper = createTestDropper("TestDropper_SpawnedFields")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
    })

    dropper.In.onDispense(dropper)

    local data = captured.spawned[1]
    assert_not_nil(data.assetId, "spawned should include assetId")
    assert_not_nil(data.instance, "spawned should include instance")
    assert_not_nil(data.entityId, "spawned should include entityId")
    assert_not_nil(data.templateName, "spawned should include templateName")
    assert_not_nil(data.dropperId, "spawned should include dropperId")
    assert_eq(data.dropperId, dropper.id, "dropperId should match dropper.id")

    cleanupDropper(dropper)
end)

--------------------------------------------------------------------------------
-- COMBINED LIMITS TESTS
--------------------------------------------------------------------------------

test("capacity and maxActive work together", "Combined Limits", function()
    local dropper = createTestDropper("TestDropper_CombinedLimits")
    local captured = captureOutput(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "Sword",
        capacity = 10,
        maxActive = 3,
    })

    -- First dispense: maxActive limits to 3
    dropper.In.onDispense(dropper, { count = 5 })
    assert_eq(#captured.spawned, 3, "Should be limited by maxActive")
    assert_eq(dropper._remaining, 7, "Capacity should be 7")

    -- Return one to make room
    local assetId = captured.spawned[1].assetId
    dropper.In.onReturn(dropper, { assetId = assetId })

    -- Now can spawn one more (maxActive allows it)
    dropper.In.onDispense(dropper, { count = 1 })
    assert_eq(#captured.spawned, 4, "Should spawn 4th item")
    assert_eq(dropper._remaining, 6, "Capacity should be 6")

    cleanupDropper(dropper)
end)

return Tests
