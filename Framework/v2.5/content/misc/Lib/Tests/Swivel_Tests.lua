--[[
    LibPureFiction Framework v2
    Swivel Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Swivel.runAll()
    ```

    Or run specific test groups:

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Swivel.runGroup("Swivel Basics")
    Tests.Swivel.runGroup("Rotation Modes")
    Tests.Swivel.runGroup("Angle Limits")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local Swivel = Lib.Components.Swivel

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
    print("  Swivel Test Suite")
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

-- Create a mock part for testing rotation
local function createMockPart()
    local part = Instance.new("Part")
    part.Name = "MockSwivelPart"
    part.Size = Vector3.new(2, 1, 4)
    part.CFrame = CFrame.new(0, 5, 0)
    part.Anchored = true
    part.Parent = workspace
    return part
end

-- Create a test swivel with a mock part
local function createTestSwivel(id)
    local part = createMockPart()
    local swivel = Swivel:new({
        id = id or "TestSwivel",
        model = part,
    })
    swivel.Sys.onInit(swivel)
    swivel._testPart = part
    return swivel
end

-- Cleanup test swivel
local function cleanupSwivel(swivel)
    swivel.Sys.onStop(swivel)
    if swivel._testPart then
        swivel._testPart:Destroy()
    end
end

-- Capture output signals
local function captureOutput(swivel)
    local captured = {
        rotated = {},
        limitReached = {},
    }

    swivel.Out = {
        Fire = function(self, signal, data)
            if captured[signal] then
                table.insert(captured[signal], data)
            end
        end,
    }

    return captured
end

-- Wait for a short time (for continuous rotation tests)
local function waitFrames(count)
    for _ = 1, count do
        RunService.Heartbeat:Wait()
    end
end

--------------------------------------------------------------------------------
-- BASIC SWIVEL TESTS
--------------------------------------------------------------------------------

test("Swivel.extend creates component class", "Swivel Basics", function()
    assert_not_nil(Swivel, "Swivel should be defined")
    assert_eq(Swivel.name, "Swivel", "Swivel name should be 'Swivel'")
    assert_eq(Swivel.domain, "server", "Swivel domain should be 'server'")
end)

test("Swivel instance initializes with default attributes", "Swivel Basics", function()
    local swivel = createTestSwivel("TestSwivel_Defaults")

    assert_eq(swivel:getAttribute("Axis"), "Y", "Default Axis should be 'Y'")
    assert_eq(swivel:getAttribute("Mode"), "continuous", "Default Mode should be 'continuous'")
    assert_eq(swivel:getAttribute("Speed"), 90, "Default Speed should be 90")
    assert_eq(swivel:getAttribute("StepSize"), 5, "Default StepSize should be 5")
    assert_eq(swivel:getAttribute("MinAngle"), -180, "Default MinAngle should be -180")
    assert_eq(swivel:getAttribute("MaxAngle"), 180, "Default MaxAngle should be 180")

    cleanupSwivel(swivel)
end)

test("Swivel initializes internal state", "Swivel Basics", function()
    local swivel = createTestSwivel("TestSwivel_InternalState")

    assert_eq(swivel._currentAngle, 0, "_currentAngle should be 0 initially")
    assert_eq(swivel._rotating, false, "_rotating should be false initially")
    assert_eq(swivel._direction, 1, "_direction should be 1 initially")
    assert_not_nil(swivel._initialCFrame, "_initialCFrame should be captured")

    cleanupSwivel(swivel)
end)

test("Swivel stores initial CFrame from model", "Swivel Basics", function()
    local part = createMockPart()
    local originalCFrame = part.CFrame

    local swivel = Swivel:new({ id = "TestSwivel_CFrame", model = part })
    swivel.Sys.onInit(swivel)

    assert_eq(swivel._initialCFrame, originalCFrame, "Should store initial CFrame")

    swivel.Sys.onStop(swivel)
    part:Destroy()
end)

--------------------------------------------------------------------------------
-- CONFIGURATION TESTS
--------------------------------------------------------------------------------

test("onConfigure sets axis", "Configuration", function()
    local swivel = createTestSwivel("TestSwivel_ConfigAxis")

    swivel.In.onConfigure(swivel, { axis = "X" })
    assert_eq(swivel:getAttribute("Axis"), "X", "Axis should be 'X'")

    swivel.In.onConfigure(swivel, { axis = "z" })  -- lowercase
    assert_eq(swivel:getAttribute("Axis"), "Z", "Axis should be 'Z' (uppercased)")

    swivel.In.onConfigure(swivel, { axis = "Y" })
    assert_eq(swivel:getAttribute("Axis"), "Y", "Axis should be 'Y'")

    cleanupSwivel(swivel)
end)

test("onConfigure sets mode", "Configuration", function()
    local swivel = createTestSwivel("TestSwivel_ConfigMode")

    swivel.In.onConfigure(swivel, { mode = "stepped" })
    assert_eq(swivel:getAttribute("Mode"), "stepped", "Mode should be 'stepped'")

    swivel.In.onConfigure(swivel, { mode = "CONTINUOUS" })  -- uppercase
    assert_eq(swivel:getAttribute("Mode"), "continuous", "Mode should be 'continuous' (lowercased)")

    cleanupSwivel(swivel)
end)

test("onConfigure sets speed", "Configuration", function()
    local swivel = createTestSwivel("TestSwivel_ConfigSpeed")

    swivel.In.onConfigure(swivel, { speed = 180 })
    assert_eq(swivel:getAttribute("Speed"), 180, "Speed should be 180")

    swivel.In.onConfigure(swivel, { speed = -45 })  -- negative
    assert_eq(swivel:getAttribute("Speed"), 45, "Speed should be absolute value (45)")

    cleanupSwivel(swivel)
end)

test("onConfigure sets stepSize", "Configuration", function()
    local swivel = createTestSwivel("TestSwivel_ConfigStepSize")

    swivel.In.onConfigure(swivel, { stepSize = 15 })
    assert_eq(swivel:getAttribute("StepSize"), 15, "StepSize should be 15")

    cleanupSwivel(swivel)
end)

test("onConfigure sets angle limits", "Configuration", function()
    local swivel = createTestSwivel("TestSwivel_ConfigLimits")

    swivel.In.onConfigure(swivel, { minAngle = -90, maxAngle = 90 })
    assert_eq(swivel:getAttribute("MinAngle"), -90, "MinAngle should be -90")
    assert_eq(swivel:getAttribute("MaxAngle"), 90, "MaxAngle should be 90")

    cleanupSwivel(swivel)
end)

--------------------------------------------------------------------------------
-- DIRECT ANGLE SETTING TESTS
--------------------------------------------------------------------------------

test("onSetAngle sets current angle", "Direct Angle", function()
    local swivel = createTestSwivel("TestSwivel_SetAngle")
    local captured = captureOutput(swivel)

    swivel.In.onSetAngle(swivel, { degrees = 45 })

    assert_eq(swivel._currentAngle, 45, "Current angle should be 45")
    assert_eq(#captured.rotated, 1, "Should fire rotated signal")
    assert_eq(captured.rotated[1].angle, 45, "rotated signal should have angle 45")

    cleanupSwivel(swivel)
end)

test("onSetAngle clamps to MinAngle", "Direct Angle", function()
    local swivel = createTestSwivel("TestSwivel_SetAngleMin")
    local captured = captureOutput(swivel)

    swivel.In.onConfigure(swivel, { minAngle = -45, maxAngle = 45 })
    swivel.In.onSetAngle(swivel, { degrees = -90 })

    assert_eq(swivel._currentAngle, -45, "Angle should clamp to -45")
    assert_eq(#captured.limitReached, 1, "Should fire limitReached")
    assert_eq(captured.limitReached[1].limit, "min", "Should indicate min limit")

    cleanupSwivel(swivel)
end)

test("onSetAngle clamps to MaxAngle", "Direct Angle", function()
    local swivel = createTestSwivel("TestSwivel_SetAngleMax")
    local captured = captureOutput(swivel)

    swivel.In.onConfigure(swivel, { minAngle = -45, maxAngle = 45 })
    swivel.In.onSetAngle(swivel, { degrees = 90 })

    assert_eq(swivel._currentAngle, 45, "Angle should clamp to 45")
    assert_eq(#captured.limitReached, 1, "Should fire limitReached")
    assert_eq(captured.limitReached[1].limit, "max", "Should indicate max limit")

    cleanupSwivel(swivel)
end)

test("onSetAngle with nil degrees does nothing", "Direct Angle", function()
    local swivel = createTestSwivel("TestSwivel_SetAngleNil")
    local captured = captureOutput(swivel)

    swivel._currentAngle = 30
    swivel.In.onSetAngle(swivel, {})  -- No degrees

    assert_eq(swivel._currentAngle, 30, "Angle should remain 30")
    assert_eq(#captured.rotated, 0, "Should not fire rotated")

    cleanupSwivel(swivel)
end)

test("onSetAngle does not fire rotated if angle unchanged", "Direct Angle", function()
    local swivel = createTestSwivel("TestSwivel_SetAngleSame")
    local captured = captureOutput(swivel)

    swivel.In.onSetAngle(swivel, { degrees = 45 })
    assert_eq(#captured.rotated, 1, "Should fire rotated first time")

    swivel.In.onSetAngle(swivel, { degrees = 45 })  -- Same angle
    assert_eq(#captured.rotated, 1, "Should not fire rotated again")

    cleanupSwivel(swivel)
end)

--------------------------------------------------------------------------------
-- STEPPED MODE TESTS
--------------------------------------------------------------------------------

test("Stepped mode rotates one increment forward", "Stepped Mode", function()
    local swivel = createTestSwivel("TestSwivel_SteppedForward")
    local captured = captureOutput(swivel)

    swivel.In.onConfigure(swivel, { mode = "stepped", stepSize = 10 })
    swivel.In.onRotate(swivel, { direction = "forward" })

    assert_eq(swivel._currentAngle, 10, "Angle should be 10")
    assert_eq(swivel._rotating, false, "Should not be continuously rotating")
    assert_eq(#captured.rotated, 1, "Should fire rotated")

    cleanupSwivel(swivel)
end)

test("Stepped mode rotates one increment reverse", "Stepped Mode", function()
    local swivel = createTestSwivel("TestSwivel_SteppedReverse")
    local captured = captureOutput(swivel)

    swivel.In.onConfigure(swivel, { mode = "stepped", stepSize = 10 })
    swivel.In.onRotate(swivel, { direction = "reverse" })

    assert_eq(swivel._currentAngle, -10, "Angle should be -10")
    assert_eq(#captured.rotated, 1, "Should fire rotated")

    cleanupSwivel(swivel)
end)

test("Stepped mode multiple steps accumulate", "Stepped Mode", function()
    local swivel = createTestSwivel("TestSwivel_SteppedMultiple")

    swivel.In.onConfigure(swivel, { mode = "stepped", stepSize = 15 })

    swivel.In.onRotate(swivel, { direction = "forward" })
    assert_eq(swivel._currentAngle, 15, "First step: 15")

    swivel.In.onRotate(swivel, { direction = "forward" })
    assert_eq(swivel._currentAngle, 30, "Second step: 30")

    swivel.In.onRotate(swivel, { direction = "reverse" })
    assert_eq(swivel._currentAngle, 15, "Third step (reverse): 15")

    cleanupSwivel(swivel)
end)

test("Stepped mode respects limits", "Stepped Mode", function()
    local swivel = createTestSwivel("TestSwivel_SteppedLimits")
    local captured = captureOutput(swivel)

    swivel.In.onConfigure(swivel, {
        mode = "stepped",
        stepSize = 30,
        minAngle = -45,
        maxAngle = 45,
    })

    swivel.In.onRotate(swivel, { direction = "forward" })
    assert_eq(swivel._currentAngle, 30, "First step: 30")

    swivel.In.onRotate(swivel, { direction = "forward" })
    assert_eq(swivel._currentAngle, 45, "Second step: clamped to 45")
    assert_eq(#captured.limitReached, 1, "Should fire limitReached")

    cleanupSwivel(swivel)
end)

--------------------------------------------------------------------------------
-- CONTINUOUS MODE TESTS
--------------------------------------------------------------------------------

test("Continuous mode starts rotating on onRotate", "Continuous Mode", function()
    local swivel = createTestSwivel("TestSwivel_ContinuousStart")

    swivel.In.onConfigure(swivel, { mode = "continuous", speed = 90 })
    swivel.In.onRotate(swivel, { direction = "forward" })

    assert_true(swivel._rotating, "Should be rotating")
    assert_true(swivel:isRotating(), "isRotating() should return true")
    assert_not_nil(swivel._heartbeatConnection, "Heartbeat connection should exist")

    cleanupSwivel(swivel)
end)

test("Continuous mode stops on onStop", "Continuous Mode", function()
    local swivel = createTestSwivel("TestSwivel_ContinuousStop")

    swivel.In.onConfigure(swivel, { mode = "continuous", speed = 90 })
    swivel.In.onRotate(swivel, { direction = "forward" })
    assert_true(swivel._rotating, "Should be rotating")

    swivel.In.onStop(swivel)
    assert_false(swivel._rotating, "Should not be rotating")
    assert_false(swivel:isRotating(), "isRotating() should return false")
    assert_nil(swivel._heartbeatConnection, "Heartbeat connection should be nil")

    cleanupSwivel(swivel)
end)

test("Continuous mode changes angle over time", "Continuous Mode", function()
    local swivel = createTestSwivel("TestSwivel_ContinuousAngle")

    swivel.In.onConfigure(swivel, { mode = "continuous", speed = 360 })  -- Fast for testing
    local startAngle = swivel._currentAngle

    swivel.In.onRotate(swivel, { direction = "forward" })

    -- Wait a few frames
    waitFrames(5)

    swivel.In.onStop(swivel)

    assert_true(swivel._currentAngle > startAngle, "Angle should have increased")

    cleanupSwivel(swivel)
end)

test("Continuous mode respects direction", "Continuous Mode", function()
    local swivel = createTestSwivel("TestSwivel_ContinuousDirection")

    swivel.In.onConfigure(swivel, { mode = "continuous", speed = 360 })

    -- Forward
    swivel.In.onRotate(swivel, { direction = "forward" })
    waitFrames(3)
    swivel.In.onStop(swivel)
    local forwardAngle = swivel._currentAngle
    assert_true(forwardAngle > 0, "Forward should increase angle")

    -- Reverse
    swivel.In.onRotate(swivel, { direction = "reverse" })
    waitFrames(3)
    swivel.In.onStop(swivel)
    assert_true(swivel._currentAngle < forwardAngle, "Reverse should decrease angle")

    cleanupSwivel(swivel)
end)

test("Continuous mode stops at limits", "Continuous Mode", function()
    local swivel = createTestSwivel("TestSwivel_ContinuousLimits")
    local captured = captureOutput(swivel)

    swivel.In.onConfigure(swivel, {
        mode = "continuous",
        speed = 1000,  -- Very fast
        minAngle = -10,
        maxAngle = 10,
    })

    swivel.In.onRotate(swivel, { direction = "forward" })

    -- Wait for it to hit the limit
    waitFrames(10)

    -- Should have stopped and fired limitReached
    assert_false(swivel._rotating, "Should stop at limit")
    assert_eq(swivel._currentAngle, 10, "Should be at max angle")
    assert_true(#captured.limitReached > 0, "Should have fired limitReached")

    cleanupSwivel(swivel)
end)

test("Continuous mode onStop has no effect in stepped mode", "Continuous Mode", function()
    local swivel = createTestSwivel("TestSwivel_StoppedStepped")

    swivel.In.onConfigure(swivel, { mode = "stepped", stepSize = 10 })
    swivel.In.onRotate(swivel, { direction = "forward" })

    assert_false(swivel._rotating, "Stepped mode should not set _rotating")

    swivel.In.onStop(swivel)  -- Should do nothing

    assert_false(swivel._rotating, "Still should not be rotating")

    cleanupSwivel(swivel)
end)

--------------------------------------------------------------------------------
-- MODEL ROTATION TESTS
--------------------------------------------------------------------------------

test("Rotation updates model CFrame on Y axis", "Model Rotation", function()
    local swivel = createTestSwivel("TestSwivel_ModelY")
    local part = swivel._testPart
    local originalPos = part.Position

    swivel.In.onConfigure(swivel, { axis = "Y" })
    swivel.In.onSetAngle(swivel, { degrees = 90 })

    -- Position should stay the same
    assert_near(part.Position.X, originalPos.X, 0.01, "X position should not change")
    assert_near(part.Position.Y, originalPos.Y, 0.01, "Y position should not change")
    assert_near(part.Position.Z, originalPos.Z, 0.01, "Z position should not change")

    -- Orientation should change (LookVector should be different)
    -- For Y-axis 90 degree rotation, LookVector should point along X
    local look = part.CFrame.LookVector
    assert_near(math.abs(look.X), 1, 0.01, "LookVector should point along X axis")

    cleanupSwivel(swivel)
end)

test("Rotation updates model CFrame on X axis", "Model Rotation", function()
    local swivel = createTestSwivel("TestSwivel_ModelX")
    local part = swivel._testPart

    swivel.In.onConfigure(swivel, { axis = "X" })
    swivel.In.onSetAngle(swivel, { degrees = 90 })

    -- For X-axis 90 degree rotation, UpVector should point along -Z
    local up = part.CFrame.UpVector
    assert_near(math.abs(up.Z), 1, 0.01, "UpVector should point along Z axis after X rotation")

    cleanupSwivel(swivel)
end)

test("Rotation updates model CFrame on Z axis", "Model Rotation", function()
    local swivel = createTestSwivel("TestSwivel_ModelZ")
    local part = swivel._testPart

    swivel.In.onConfigure(swivel, { axis = "Z" })
    swivel.In.onSetAngle(swivel, { degrees = 90 })

    -- For Z-axis 90 degree rotation, RightVector should point along Y
    local right = part.CFrame.RightVector
    assert_near(math.abs(right.Y), 1, 0.01, "RightVector should point along Y axis after Z rotation")

    cleanupSwivel(swivel)
end)

--------------------------------------------------------------------------------
-- HELPER METHOD TESTS
--------------------------------------------------------------------------------

test("getCurrentAngle returns current angle", "Helper Methods", function()
    local swivel = createTestSwivel("TestSwivel_GetAngle")

    assert_eq(swivel:getCurrentAngle(), 0, "Initial angle should be 0")

    swivel.In.onSetAngle(swivel, { degrees = 45 })
    assert_eq(swivel:getCurrentAngle(), 45, "Angle should be 45")

    cleanupSwivel(swivel)
end)

test("isRotating returns rotation state", "Helper Methods", function()
    local swivel = createTestSwivel("TestSwivel_IsRotating")

    assert_false(swivel:isRotating(), "Should not be rotating initially")

    swivel.In.onConfigure(swivel, { mode = "continuous" })
    swivel.In.onRotate(swivel, { direction = "forward" })

    assert_true(swivel:isRotating(), "Should be rotating after onRotate")

    swivel.In.onStop(swivel)

    assert_false(swivel:isRotating(), "Should not be rotating after onStop")

    cleanupSwivel(swivel)
end)

--------------------------------------------------------------------------------
-- LIFECYCLE TESTS
--------------------------------------------------------------------------------

test("Sys.onStop stops rotation", "Lifecycle", function()
    local swivel = createTestSwivel("TestSwivel_SysStop")

    swivel.In.onConfigure(swivel, { mode = "continuous" })
    swivel.In.onRotate(swivel, { direction = "forward" })
    assert_true(swivel._rotating, "Should be rotating")

    swivel.Sys.onStop(swivel)
    assert_false(swivel._rotating, "Should stop rotating on Sys.onStop")

    cleanupSwivel(swivel)
end)

test("Multiple onRotate calls do not stack connections", "Lifecycle", function()
    local swivel = createTestSwivel("TestSwivel_NoStack")

    swivel.In.onConfigure(swivel, { mode = "continuous" })

    swivel.In.onRotate(swivel, { direction = "forward" })
    local firstConnection = swivel._heartbeatConnection

    swivel.In.onRotate(swivel, { direction = "forward" })
    local secondConnection = swivel._heartbeatConnection

    -- Should be the same connection (no new one created)
    assert_eq(firstConnection, secondConnection, "Should not create new connection")

    cleanupSwivel(swivel)
end)

--------------------------------------------------------------------------------
-- EDGE CASES
--------------------------------------------------------------------------------

test("Swivel works without model", "Edge Cases", function()
    local swivel = Swivel:new({ id = "TestSwivel_NoModel" })
    swivel.Sys.onInit(swivel)
    local captured = captureOutput(swivel)

    -- Should not error
    swivel.In.onSetAngle(swivel, { degrees = 45 })

    assert_eq(swivel._currentAngle, 45, "Should track angle internally")
    assert_eq(#captured.rotated, 1, "Should still fire rotated")

    swivel.Sys.onStop(swivel)
end)

test("Default direction is forward", "Edge Cases", function()
    local swivel = createTestSwivel("TestSwivel_DefaultDirection")

    swivel.In.onConfigure(swivel, { mode = "stepped", stepSize = 10 })
    swivel.In.onRotate(swivel, {})  -- No direction specified

    assert_eq(swivel._currentAngle, 10, "Should default to forward (positive)")

    cleanupSwivel(swivel)
end)

test("Empty onConfigure does not crash", "Edge Cases", function()
    local swivel = createTestSwivel("TestSwivel_EmptyConfig")

    -- Should not error
    swivel.In.onConfigure(swivel, nil)
    swivel.In.onConfigure(swivel, {})

    assert_eq(swivel:getAttribute("Axis"), "Y", "Defaults should remain")

    cleanupSwivel(swivel)
end)

return Tests
