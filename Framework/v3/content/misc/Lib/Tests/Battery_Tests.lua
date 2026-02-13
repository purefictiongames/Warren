--[[
    LibPureFiction Framework v2
    Battery Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Battery.runAll()
    ```

    Or run specific test groups:

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Battery.runGroup("Battery Basics")
    Tests.Battery.runGroup("Power Draw")
    Tests.Battery.runGroup("Recharge")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Battery = Lib.Components.Battery

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

local function assert_not_nil(value, message)
    if value == nil then
        error(message or "Expected non-nil value", 2)
    end
end

local function assert_near(actual, expected, tolerance, message)
    tolerance = tolerance or 0.01
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected ~%s, got %s (tolerance: %s)",
            message or "Assertion failed",
            tostring(expected),
            tostring(actual),
            tostring(tolerance)), 2)
    end
end

local function assert_gte(actual, expected, message)
    if actual < expected then
        error(string.format("%s: expected >= %s, got %s",
            message or "Assertion failed",
            tostring(expected),
            tostring(actual)), 2)
    end
end

local function assert_lte(actual, expected, message)
    if actual > expected then
        error(string.format("%s: expected <= %s, got %s",
            message or "Assertion failed",
            tostring(expected),
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
    print("  Battery Test Suite")
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

-- Create a test battery
local function createTestBattery(id, config)
    local battery = Battery:new({
        id = id or "TestBattery",
    })
    battery.Sys.onInit(battery)

    if config then
        battery.In.onConfigure(battery, config)
    end

    return battery
end

-- Cleanup test battery
local function cleanupBattery(battery)
    battery.Sys.onStop(battery)
end

-- Capture output signals
local function captureOutput(battery)
    local captured = {
        batteryPresent = {},
        powerDrawn = {},
        powerChanged = {},
        powerDepleted = {},
        powerRestored = {},
    }

    battery.Out = {
        Fire = function(self, signal, data)
            if captured[signal] then
                table.insert(captured[signal], data)
            end
        end,
    }

    return captured
end

-- Wait for a short time
local function waitFrames(count)
    for _ = 1, count do
        RunService.Heartbeat:Wait()
    end
end

--------------------------------------------------------------------------------
-- BASIC TESTS
--------------------------------------------------------------------------------

test("Battery.extend creates component class", "Battery Basics", function()
    assert_eq(Battery.name, "Battery", "Battery name should be 'Battery'")
    assert_eq(Battery.domain, "server", "Battery domain should be 'server'")
end)

test("Battery initializes with default attributes", "Battery Basics", function()
    local battery = createTestBattery("TestBattery_Defaults")

    assert_eq(battery:getAttribute("Capacity"), 100, "Default Capacity should be 100")
    assert_eq(battery:getAttribute("RechargeRate"), 10, "Default RechargeRate should be 10")

    cleanupBattery(battery)
end)

test("Battery starts at full capacity", "Battery Basics", function()
    local battery = createTestBattery("TestBattery_FullStart")
    local captured = captureOutput(battery)

    battery.Sys.onStart(battery)

    -- Should emit initial power state
    assert_true(#captured.powerChanged >= 1, "Should emit powerChanged on start")
    assert_eq(captured.powerChanged[1].current, 100, "Should start at full capacity")
    assert_eq(captured.powerChanged[1].max, 100, "Max should be capacity")
    assert_eq(captured.powerChanged[1].percent, 1, "Percent should be 1")

    cleanupBattery(battery)
end)

test("Battery respects StartingCharge attribute", "Battery Basics", function()
    local battery = Battery:new({ id = "TestBattery_StartingCharge" })
    battery:setAttribute("StartingCharge", 50)
    battery.Sys.onInit(battery)
    local captured = captureOutput(battery)

    battery.Sys.onStart(battery)

    assert_eq(captured.powerChanged[1].current, 50, "Should start at StartingCharge")

    cleanupBattery(battery)
end)

--------------------------------------------------------------------------------
-- CONFIGURATION TESTS
--------------------------------------------------------------------------------

test("onConfigure sets capacity", "Configuration", function()
    local battery = createTestBattery("TestBattery_ConfigCapacity")

    battery.In.onConfigure(battery, { capacity = 200 })

    assert_eq(battery:getAttribute("Capacity"), 200, "Capacity should be 200")

    cleanupBattery(battery)
end)

test("onConfigure sets recharge rate", "Configuration", function()
    local battery = createTestBattery("TestBattery_ConfigRechargeRate")

    battery.In.onConfigure(battery, { rechargeRate = 25 })

    assert_eq(battery:getAttribute("RechargeRate"), 25, "RechargeRate should be 25")

    cleanupBattery(battery)
end)

test("onConfigure caps current to capacity", "Configuration", function()
    local battery = createTestBattery("TestBattery_CapCurrent")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Set current to 100 (default capacity)
    battery.In.onConfigure(battery, { current = 100 })
    -- Now reduce capacity below current
    battery.In.onConfigure(battery, { capacity = 50 })

    -- Find the last powerChanged
    local last = captured.powerChanged[#captured.powerChanged]
    assert_lte(last.current, 50, "Current should be capped to new capacity")

    cleanupBattery(battery)
end)

test("onConfigure allows setting current directly", "Configuration", function()
    local battery = createTestBattery("TestBattery_SetCurrent")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    battery.In.onConfigure(battery, { current = 75 })

    local last = captured.powerChanged[#captured.powerChanged]
    assert_eq(last.current, 75, "Current should be 75")

    cleanupBattery(battery)
end)

--------------------------------------------------------------------------------
-- POWER DRAW TESTS
--------------------------------------------------------------------------------

test("onDraw deducts power", "Power Draw", function()
    local battery = createTestBattery("TestBattery_Draw")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    battery.In.onDraw(battery, { amount = 25 })

    -- Check powerDrawn response
    assert_eq(#captured.powerDrawn, 1, "Should emit powerDrawn")
    assert_eq(captured.powerDrawn[1].granted, 25, "Should grant 25")
    assert_eq(captured.powerDrawn[1].remaining, 75, "Remaining should be 75")
    assert_eq(captured.powerDrawn[1].capacity, 100, "Capacity should be 100")

    cleanupBattery(battery)
end)

test("onDraw grants only available power", "Power Draw", function()
    local battery = createTestBattery("TestBattery_DrawPartial")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Set current to 10
    battery.In.onConfigure(battery, { current = 10 })

    -- Request more than available
    battery.In.onDraw(battery, { amount = 50 })

    assert_eq(captured.powerDrawn[1].granted, 10, "Should only grant available 10")
    assert_eq(captured.powerDrawn[1].remaining, 0, "Remaining should be 0")

    cleanupBattery(battery)
end)

test("onDraw emits powerDepleted when empty", "Power Draw", function()
    local battery = createTestBattery("TestBattery_DrawDepleted")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Drain all power
    battery.In.onDraw(battery, { amount = 100 })

    assert_eq(#captured.powerDepleted, 1, "Should emit powerDepleted")

    cleanupBattery(battery)
end)

test("onDraw only emits powerDepleted once", "Power Draw", function()
    local battery = createTestBattery("TestBattery_DrawDepletedOnce")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Drain all power
    battery.In.onDraw(battery, { amount = 100 })
    -- Try to draw more
    battery.In.onDraw(battery, { amount = 10 })
    battery.In.onDraw(battery, { amount = 10 })

    assert_eq(#captured.powerDepleted, 1, "Should only emit powerDepleted once")

    cleanupBattery(battery)
end)

test("onDraw passes through _passthrough data", "Power Draw", function()
    local battery = createTestBattery("TestBattery_DrawPassthrough")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    battery.In.onDraw(battery, {
        amount = 10,
        _passthrough = { correlationId = "test123" },
    })

    assert_eq(captured.powerDrawn[1]._passthrough.correlationId, "test123", "Should pass through data")

    cleanupBattery(battery)
end)

test("Multiple draws accumulate correctly", "Power Draw", function()
    local battery = createTestBattery("TestBattery_MultipleDraw")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    battery.In.onDraw(battery, { amount = 20 })
    battery.In.onDraw(battery, { amount = 30 })
    battery.In.onDraw(battery, { amount = 10 })

    -- Total drawn: 60, remaining: 40
    local lastDrawn = captured.powerDrawn[#captured.powerDrawn]
    assert_eq(lastDrawn.remaining, 40, "Remaining should be 40 after 60 drawn")

    cleanupBattery(battery)
end)

--------------------------------------------------------------------------------
-- RECHARGE TESTS
--------------------------------------------------------------------------------

test("Battery auto-recharges when below capacity", "Recharge", function()
    local battery = createTestBattery("TestBattery_AutoRecharge", {
        rechargeRate = 100,  -- Fast recharge for testing
    })
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Drain some power
    battery.In.onDraw(battery, { amount = 50 })

    -- Wait for recharge
    waitFrames(10)

    -- Check if power increased
    local lastChanged = captured.powerChanged[#captured.powerChanged]
    assert_true(lastChanged.current > 50, "Power should have increased from auto-recharge")

    cleanupBattery(battery)
end)

test("onRecharge adds power", "Recharge", function()
    local battery = createTestBattery("TestBattery_ExternalRecharge")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Drain power
    battery.In.onConfigure(battery, { current = 20 })

    -- External recharge
    battery.In.onRecharge(battery, { amount = 30 })

    local lastChanged = captured.powerChanged[#captured.powerChanged]
    assert_eq(lastChanged.current, 50, "Power should be 50 after recharge")

    cleanupBattery(battery)
end)

test("onRecharge caps at capacity", "Recharge", function()
    local battery = createTestBattery("TestBattery_RechargeCap")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Drain a little
    battery.In.onDraw(battery, { amount = 10 })

    -- Recharge more than capacity
    battery.In.onRecharge(battery, { amount = 500 })

    local lastChanged = captured.powerChanged[#captured.powerChanged]
    assert_eq(lastChanged.current, 100, "Power should cap at capacity")

    cleanupBattery(battery)
end)

test("onRecharge emits powerRestored when coming from zero", "Recharge", function()
    local battery = createTestBattery("TestBattery_RechargeRestored")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Drain completely
    battery.In.onDraw(battery, { amount = 100 })
    assert_eq(#captured.powerDepleted, 1, "Should be depleted")

    -- Recharge
    battery.In.onRecharge(battery, { amount = 10 })

    assert_eq(#captured.powerRestored, 1, "Should emit powerRestored")

    cleanupBattery(battery)
end)

--------------------------------------------------------------------------------
-- DISCOVERY TESTS
--------------------------------------------------------------------------------

test("onDiscoverBattery responds with batteryPresent", "Discovery", function()
    local battery = createTestBattery("TestBattery_Discovery")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    battery.In.onDiscoverBattery(battery, { requesterId = "Launcher1" })

    assert_eq(#captured.batteryPresent, 1, "Should emit batteryPresent")
    assert_eq(captured.batteryPresent[1].batteryId, "TestBattery_Discovery", "Should include batteryId")
    assert_eq(captured.batteryPresent[1].capacity, 100, "Should include capacity")
    assert_eq(captured.batteryPresent[1].current, 100, "Should include current")

    cleanupBattery(battery)
end)

--------------------------------------------------------------------------------
-- MULTIPLE CONSUMER TESTS
--------------------------------------------------------------------------------

test("Battery handles draws from multiple consumers", "Multiple Consumers", function()
    local battery = createTestBattery("TestBattery_MultiConsumer", {
        capacity = 100,
    })
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Simulate multiple consumers drawing
    battery.In.onDraw(battery, { amount = 10, _passthrough = { consumerId = "A" } })
    battery.In.onDraw(battery, { amount = 15, _passthrough = { consumerId = "B" } })
    battery.In.onDraw(battery, { amount = 5, _passthrough = { consumerId = "A" } })
    battery.In.onDraw(battery, { amount = 20, _passthrough = { consumerId = "C" } })

    -- Total: 50 drawn
    local lastDrawn = captured.powerDrawn[#captured.powerDrawn]
    assert_eq(lastDrawn.remaining, 50, "Total remaining should be 50")

    -- Each draw should have correct passthrough
    assert_eq(captured.powerDrawn[1]._passthrough.consumerId, "A", "First draw from A")
    assert_eq(captured.powerDrawn[2]._passthrough.consumerId, "B", "Second draw from B")
    assert_eq(captured.powerDrawn[4]._passthrough.consumerId, "C", "Fourth draw from C")

    cleanupBattery(battery)
end)

test("Battery depletes fairly across consumers", "Multiple Consumers", function()
    local battery = createTestBattery("TestBattery_FairDepletion", {
        capacity = 30,
        current = 30,
    })
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    -- Three consumers each request 20 (only 30 available)
    battery.In.onDraw(battery, { amount = 20, _passthrough = { consumerId = "A" } })
    battery.In.onDraw(battery, { amount = 20, _passthrough = { consumerId = "B" } })
    battery.In.onDraw(battery, { amount = 20, _passthrough = { consumerId = "C" } })

    -- First gets full 20, second gets 10, third gets 0
    assert_eq(captured.powerDrawn[1].granted, 20, "First consumer gets 20")
    assert_eq(captured.powerDrawn[2].granted, 10, "Second consumer gets remaining 10")
    assert_eq(captured.powerDrawn[3].granted, 0, "Third consumer gets 0")

    cleanupBattery(battery)
end)

--------------------------------------------------------------------------------
-- EDGE CASES
--------------------------------------------------------------------------------

test("Empty onConfigure does not crash", "Edge Cases", function()
    local battery = createTestBattery("TestBattery_EmptyConfig")

    battery.In.onConfigure(battery, nil)
    battery.In.onConfigure(battery, {})

    assert_eq(battery:getAttribute("Capacity"), 100, "Defaults should remain")

    cleanupBattery(battery)
end)

test("onDraw with nil data does not crash", "Edge Cases", function()
    local battery = createTestBattery("TestBattery_NilDraw")
    battery.Sys.onStart(battery)

    -- Should not error
    battery.In.onDraw(battery, nil)
    battery.In.onDraw(battery, {})

    cleanupBattery(battery)
end)

test("onRecharge with nil data does not crash", "Edge Cases", function()
    local battery = createTestBattery("TestBattery_NilRecharge")
    battery.Sys.onStart(battery)

    -- Should not error
    battery.In.onRecharge(battery, nil)
    battery.In.onRecharge(battery, {})

    cleanupBattery(battery)
end)

test("Negative draw amount is treated as zero", "Edge Cases", function()
    local battery = createTestBattery("TestBattery_NegativeDraw")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    battery.In.onDraw(battery, { amount = -50 })

    assert_eq(captured.powerDrawn[1].granted, 0, "Negative amount should grant 0")
    assert_eq(captured.powerDrawn[1].remaining, 100, "Power should not change")

    cleanupBattery(battery)
end)

test("Negative recharge amount is treated as zero", "Edge Cases", function()
    local battery = createTestBattery("TestBattery_NegativeRecharge")
    local captured = captureOutput(battery)
    battery.Sys.onStart(battery)

    battery.In.onConfigure(battery, { current = 50 })
    battery.In.onRecharge(battery, { amount = -30 })

    local lastChanged = captured.powerChanged[#captured.powerChanged]
    assert_eq(lastChanged.current, 50, "Power should not change with negative recharge")

    cleanupBattery(battery)
end)

--------------------------------------------------------------------------------
-- VISUAL TESTS
--------------------------------------------------------------------------------

test("Battery creates default part when no model provided", "Visual", function()
    local battery = createTestBattery("TestBattery_DefaultPart")
    battery.Sys.onStart(battery)

    assert_not_nil(battery.model, "Should have a model")
    assert_true(battery.model:IsA("BasePart"), "Model should be a BasePart")
    assert_eq(battery.model.Name, "TestBattery_DefaultPart_Battery", "Part name should match")

    cleanupBattery(battery)
end)

test("Battery uses provided model", "Visual", function()
    local customPart = Instance.new("Part")
    customPart.Name = "CustomBattery"
    customPart.Parent = workspace

    local battery = Battery:new({
        id = "TestBattery_CustomModel",
        model = customPart,
    })
    battery.Sys.onInit(battery)
    battery.Sys.onStart(battery)

    assert_eq(battery.model, customPart, "Should use provided model")

    battery.Sys.onStop(battery)
    customPart:Destroy()
end)

test("Battery visibility can be configured", "Visual", function()
    local battery = createTestBattery("TestBattery_Visibility")
    battery.Sys.onStart(battery)

    -- Default should be visible
    assert_eq(battery.model.Transparency, 0, "Should be visible by default")

    -- Configure to invisible
    battery.In.onConfigure(battery, { visible = false })
    assert_eq(battery.model.Transparency, 1, "Should be invisible after config")

    -- Configure back to visible
    battery.In.onConfigure(battery, { visible = true })
    assert_eq(battery.model.Transparency, 0, "Should be visible again")

    cleanupBattery(battery)
end)

test("Battery can be created invisible", "Visual", function()
    local battery = Battery:new({ id = "TestBattery_InitInvisible" })
    battery:setAttribute("Visible", false)
    battery.Sys.onInit(battery)
    battery.Sys.onStart(battery)

    assert_eq(battery.model.Transparency, 1, "Should be invisible from init")

    cleanupBattery(battery)
end)

test("Default part is cleaned up on stop", "Visual", function()
    local battery = createTestBattery("TestBattery_Cleanup")
    battery.Sys.onStart(battery)

    local part = battery.model
    assert_not_nil(part, "Should have part")
    assert_not_nil(part.Parent, "Part should be parented")

    cleanupBattery(battery)

    assert_eq(part.Parent, nil, "Part should be destroyed on cleanup")
end)

test("Provided model is NOT destroyed on stop", "Visual", function()
    local customPart = Instance.new("Part")
    customPart.Name = "CustomBattery"
    customPart.Parent = workspace

    local battery = Battery:new({
        id = "TestBattery_NoDestroyProvided",
        model = customPart,
    })
    battery.Sys.onInit(battery)
    battery.Sys.onStart(battery)
    battery.Sys.onStop(battery)

    assert_not_nil(customPart.Parent, "Provided model should NOT be destroyed")

    customPart:Destroy()
end)

return Tests
