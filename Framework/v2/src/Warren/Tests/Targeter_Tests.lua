--[[
    Warren Framework v2
    Targeter Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.Targeter.runAll()
    ```

    Or run specific test groups:

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.Targeter.runGroup("Targeter Basics")
    Tests.Targeter.runGroup("Beam Modes")
    Tests.Targeter.runGroup("Tracking Modes")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local Node = Lib.Node
local Targeter = Lib.Components.Targeter

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

local function assert_gte(actual, expected, message)
    if actual < expected then
        error(string.format("%s: expected >= %s, got %s",
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
    print("  Targeter Test Suite")
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

-- Create a mock scanner part (origin for raycasting)
local function createScannerPart()
    local part = Instance.new("Part")
    part.Name = "MockScanner"
    part.Size = Vector3.new(1, 1, 2)
    part.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, 0, 0)  -- Facing +Z
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.5
    part.Parent = workspace
    return part
end

-- Create a target part in front of the scanner
local function createTargetPart(position, nodeClass)
    local part = Instance.new("Part")
    part.Name = "Target"
    part.Size = Vector3.new(4, 4, 4)
    part.CFrame = CFrame.new(position)
    part.Anchored = true
    part.CanCollide = true
    part.Parent = workspace

    if nodeClass then
        part:SetAttribute("NodeClass", nodeClass)
    end

    return part
end

-- Create a test targeter with a scanner part
local function createTestTargeter(id)
    local scanner = createScannerPart()
    local targeter = Targeter:new({
        id = id or "TestTargeter",
        model = scanner,
    })
    targeter.Sys.onInit(targeter)
    targeter._testScanner = scanner
    targeter._testTargets = {}
    return targeter
end

-- Cleanup test targeter and targets
local function cleanupTargeter(targeter)
    targeter.Sys.onStop(targeter)
    if targeter._testScanner then
        targeter._testScanner:Destroy()
    end
    for _, target in ipairs(targeter._testTargets or {}) do
        if target and target.Parent then
            target:Destroy()
        end
    end
end

-- Add a target to the test setup
local function addTarget(targeter, position, nodeClass)
    local target = createTargetPart(position, nodeClass)
    table.insert(targeter._testTargets, target)
    return target
end

-- Capture output signals
local function captureOutput(targeter)
    local captured = {
        acquired = {},
        tracking = {},
        lost = {},
    }

    targeter.Out = {
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
-- BASIC TARGETER TESTS
--------------------------------------------------------------------------------

test("Targeter.extend creates component class", "Targeter Basics", function()
    assert_not_nil(Targeter, "Targeter should be defined")
    assert_eq(Targeter.name, "Targeter", "Targeter name should be 'Targeter'")
    assert_eq(Targeter.domain, "server", "Targeter domain should be 'server'")
end)

test("Targeter instance initializes with default attributes", "Targeter Basics", function()
    local targeter = createTestTargeter("TestTargeter_Defaults")

    assert_eq(targeter:getAttribute("BeamMode"), "pinpoint", "Default BeamMode should be 'pinpoint'")
    assert_eq(targeter:getAttribute("BeamRadius"), 1, "Default BeamRadius should be 1")
    assert_eq(targeter:getAttribute("RayCount"), 8, "Default RayCount should be 8")
    assert_eq(targeter:getAttribute("Range"), 100, "Default Range should be 100")
    assert_eq(targeter:getAttribute("ScanMode"), "continuous", "Default ScanMode should be 'continuous'")
    assert_eq(targeter:getAttribute("Interval"), 0.5, "Default Interval should be 0.5")
    assert_eq(targeter:getAttribute("TrackingMode"), "once", "Default TrackingMode should be 'once'")

    cleanupTargeter(targeter)
end)

test("Targeter initializes internal state", "Targeter Basics", function()
    local targeter = createTestTargeter("TestTargeter_InternalState")

    assert_false(targeter._enabled, "_enabled should be false initially")
    assert_false(targeter._scanning, "_scanning should be false initially")
    assert_false(targeter._hasTargets, "_hasTargets should be false initially")
    assert_not_nil(targeter._origin, "_origin should be set from model")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- CONFIGURATION TESTS
--------------------------------------------------------------------------------

test("onConfigure sets beam mode", "Configuration", function()
    local targeter = createTestTargeter("TestTargeter_ConfigBeam")

    targeter.In.onConfigure(targeter, { beamMode = "cylinder" })
    assert_eq(targeter:getAttribute("BeamMode"), "cylinder", "BeamMode should be 'cylinder'")

    targeter.In.onConfigure(targeter, { beamMode = "CONE" })  -- uppercase
    assert_eq(targeter:getAttribute("BeamMode"), "cone", "BeamMode should be 'cone'")

    cleanupTargeter(targeter)
end)

test("onConfigure sets beam radius", "Configuration", function()
    local targeter = createTestTargeter("TestTargeter_ConfigRadius")

    targeter.In.onConfigure(targeter, { beamRadius = 5 })
    assert_eq(targeter:getAttribute("BeamRadius"), 5, "BeamRadius should be 5")

    targeter.In.onConfigure(targeter, { beamRadius = -3 })  -- negative
    assert_eq(targeter:getAttribute("BeamRadius"), 3, "BeamRadius should be absolute value")

    cleanupTargeter(targeter)
end)

test("onConfigure sets range", "Configuration", function()
    local targeter = createTestTargeter("TestTargeter_ConfigRange")

    targeter.In.onConfigure(targeter, { range = 200 })
    assert_eq(targeter:getAttribute("Range"), 200, "Range should be 200")

    cleanupTargeter(targeter)
end)

test("onConfigure sets scan mode", "Configuration", function()
    local targeter = createTestTargeter("TestTargeter_ConfigScan")

    targeter.In.onConfigure(targeter, { scanMode = "interval" })
    assert_eq(targeter:getAttribute("ScanMode"), "interval", "ScanMode should be 'interval'")

    targeter.In.onConfigure(targeter, { scanMode = "pulse" })
    assert_eq(targeter:getAttribute("ScanMode"), "pulse", "ScanMode should be 'pulse'")

    cleanupTargeter(targeter)
end)

test("onConfigure sets tracking mode", "Configuration", function()
    local targeter = createTestTargeter("TestTargeter_ConfigTracking")

    targeter.In.onConfigure(targeter, { trackingMode = "lock" })
    assert_eq(targeter:getAttribute("TrackingMode"), "lock", "TrackingMode should be 'lock'")

    cleanupTargeter(targeter)
end)

test("onConfigure sets filter", "Configuration", function()
    local targeter = createTestTargeter("TestTargeter_ConfigFilter")

    targeter.In.onConfigure(targeter, { filter = { class = "Enemy" } })
    assert_eq(targeter._filter.class, "Enemy", "Filter class should be 'Enemy'")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- ENABLE/DISABLE TESTS
--------------------------------------------------------------------------------

test("onEnable starts scanning", "Enable/Disable", function()
    local targeter = createTestTargeter("TestTargeter_Enable")

    targeter.In.onEnable(targeter)

    assert_true(targeter._enabled, "_enabled should be true")
    assert_true(targeter._scanning, "_scanning should be true")
    assert_true(targeter:isEnabled(), "isEnabled() should return true")
    assert_true(targeter:isScanning(), "isScanning() should return true")

    cleanupTargeter(targeter)
end)

test("onDisable stops scanning", "Enable/Disable", function()
    local targeter = createTestTargeter("TestTargeter_Disable")

    targeter.In.onEnable(targeter)
    assert_true(targeter._scanning, "Should be scanning")

    targeter.In.onDisable(targeter)

    assert_false(targeter._enabled, "_enabled should be false")
    assert_false(targeter._scanning, "_scanning should be false")
    assert_false(targeter:isEnabled(), "isEnabled() should return false")
    assert_false(targeter:isScanning(), "isScanning() should return false")

    cleanupTargeter(targeter)
end)

test("onDisable fires lost if had targets (lock mode)", "Enable/Disable", function()
    local targeter = createTestTargeter("TestTargeter_DisableLost")
    local captured = captureOutput(targeter)

    targeter.In.onConfigure(targeter, { trackingMode = "lock" })
    targeter._hasTargets = true  -- Simulate having targets

    targeter.In.onEnable(targeter)
    targeter.In.onDisable(targeter)

    assert_eq(#captured.lost, 1, "Should fire lost signal")

    cleanupTargeter(targeter)
end)

test("Double enable does not restart scanning", "Enable/Disable", function()
    local targeter = createTestTargeter("TestTargeter_DoubleEnable")

    targeter.In.onEnable(targeter)
    local firstConnection = targeter._scanConnection

    targeter.In.onEnable(targeter)  -- Second enable
    local secondConnection = targeter._scanConnection

    assert_eq(firstConnection, secondConnection, "Should be same connection")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- PULSE MODE TESTS
--------------------------------------------------------------------------------

test("Pulse mode does not auto-scan", "Pulse Mode", function()
    local targeter = createTestTargeter("TestTargeter_PulseNoAuto")

    targeter.In.onConfigure(targeter, { scanMode = "pulse" })
    targeter.In.onEnable(targeter)

    assert_true(targeter._enabled, "Should be enabled")
    assert_false(targeter._scanning, "Should not be scanning (pulse mode)")

    cleanupTargeter(targeter)
end)

test("Pulse mode responds to onScan", "Pulse Mode", function()
    local targeter = createTestTargeter("TestTargeter_PulseScan")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z and add target
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)
    local target = addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        range = 50,
    })

    targeter.In.onScan(targeter)

    assert_eq(#captured.acquired, 1, "Should fire acquired on manual scan")
    assert_eq(#captured.acquired[1].targets, 1, "Should detect 1 target")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- INTERVAL MODE TESTS
--------------------------------------------------------------------------------

test("Interval mode scans at configured interval", "Interval Mode", function()
    local targeter = createTestTargeter("TestTargeter_IntervalScan")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z and add target
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)
    addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "interval",
        interval = 0.1,  -- Short interval for testing
        range = 50,
    })

    targeter.In.onEnable(targeter)

    -- Wait for a couple intervals
    task.wait(0.25)

    targeter.In.onDisable(targeter)

    -- Should have fired acquired at least once (first detection)
    assert_gte(#captured.acquired, 1, "Should have fired acquired")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- TRACKING MODE TESTS (ONCE)
--------------------------------------------------------------------------------

test("Once mode fires acquired only on first detection", "Tracking Once", function()
    local targeter = createTestTargeter("TestTargeter_OnceFirst")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z and add target
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)
    addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        trackingMode = "once",
        range = 50,
    })

    -- First scan
    targeter.In.onScan(targeter)
    assert_eq(#captured.acquired, 1, "Should fire acquired on first detection")

    -- Second scan (target still there)
    targeter.In.onScan(targeter)
    assert_eq(#captured.acquired, 1, "Should NOT fire acquired again")

    cleanupTargeter(targeter)
end)

test("Once mode resets after target lost", "Tracking Once", function()
    local targeter = createTestTargeter("TestTargeter_OnceReset")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)
    local target = addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        trackingMode = "once",
        range = 50,
    })

    -- First detection
    targeter.In.onScan(targeter)
    assert_eq(#captured.acquired, 1, "Should fire acquired")

    -- Remove target
    target:Destroy()
    targeter._testTargets = {}

    -- Scan with no target
    targeter.In.onScan(targeter)
    assert_false(targeter._hasTargets, "Should have no targets")

    -- Add target again
    addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    -- Should fire acquired again
    targeter.In.onScan(targeter)
    assert_eq(#captured.acquired, 2, "Should fire acquired again after re-detection")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- TRACKING MODE TESTS (LOCK)
--------------------------------------------------------------------------------

test("Lock mode fires acquired then tracking", "Tracking Lock", function()
    local targeter = createTestTargeter("TestTargeter_LockTracking")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z and add target
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)
    addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        trackingMode = "lock",
        range = 50,
    })

    -- First scan - acquired
    targeter.In.onScan(targeter)
    assert_eq(#captured.acquired, 1, "Should fire acquired on first detection")
    assert_eq(#captured.tracking, 0, "Should not fire tracking yet")

    -- Second scan - tracking
    targeter.In.onScan(targeter)
    assert_eq(#captured.acquired, 1, "Should not fire acquired again")
    assert_eq(#captured.tracking, 1, "Should fire tracking")

    -- Third scan - still tracking
    targeter.In.onScan(targeter)
    assert_eq(#captured.tracking, 2, "Should fire tracking again")

    cleanupTargeter(targeter)
end)

test("Lock mode fires lost when target leaves", "Tracking Lock", function()
    local targeter = createTestTargeter("TestTargeter_LockLost")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)
    local target = addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        trackingMode = "lock",
        range = 50,
    })

    -- Acquire target
    targeter.In.onScan(targeter)
    assert_eq(#captured.acquired, 1, "Should acquire target")

    -- Remove target
    target:Destroy()
    targeter._testTargets = {}

    -- Scan again
    targeter.In.onScan(targeter)
    assert_eq(#captured.lost, 1, "Should fire lost")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- FILTER TESTS
--------------------------------------------------------------------------------

test("Filter by class includes matching targets", "Filtering", function()
    local targeter = createTestTargeter("TestTargeter_FilterClass")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)

    -- Add enemy target
    addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        range = 50,
        filter = { class = "Enemy" },
    })

    targeter.In.onScan(targeter)

    assert_eq(#captured.acquired, 1, "Should detect enemy")
    assert_eq(#captured.acquired[1].targets, 1, "Should have 1 target")

    cleanupTargeter(targeter)
end)

test("Filter by class excludes non-matching targets", "Filtering", function()
    local targeter = createTestTargeter("TestTargeter_FilterExclude")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)

    -- Add friendly target (should be excluded)
    addTarget(targeter, Vector3.new(0, 10, -20), "Friendly")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        range = 50,
        filter = { class = "Enemy" },
    })

    targeter.In.onScan(targeter)

    assert_eq(#captured.acquired, 0, "Should not detect friendly")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- TARGET SORTING TESTS
--------------------------------------------------------------------------------

test("Targets are sorted by distance (closest first)", "Target Sorting", function()
    local targeter = createTestTargeter("TestTargeter_Sorting")
    local captured = captureOutput(targeter)

    -- Position scanner to face -Z
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)

    -- Add targets at different distances
    addTarget(targeter, Vector3.new(0, 10, -30), "Enemy")  -- Far
    addTarget(targeter, Vector3.new(0, 10, -10), "Enemy")  -- Close
    addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")  -- Medium

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        beamMode = "cylinder",  -- Use cylinder to hit multiple
        beamRadius = 3,
        range = 50,
    })

    targeter.In.onScan(targeter)

    assert_eq(#captured.acquired, 1, "Should have acquired")
    local targets = captured.acquired[1].targets
    assert_gte(#targets, 1, "Should have at least 1 target")

    -- Verify sorting (if multiple targets detected)
    if #targets >= 2 then
        assert_true(targets[1].distance <= targets[2].distance,
            "First target should be closer than second")
    end

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- BEAM MODE TESTS
--------------------------------------------------------------------------------

test("Pinpoint mode generates single ray", "Beam Modes", function()
    local targeter = createTestTargeter("TestTargeter_Pinpoint")

    targeter.In.onConfigure(targeter, { beamMode = "pinpoint" })

    local rays = targeter:_generateRays()

    assert_eq(#rays, 1, "Pinpoint should generate 1 ray")

    cleanupTargeter(targeter)
end)

test("Cylinder mode generates multiple rays", "Beam Modes", function()
    local targeter = createTestTargeter("TestTargeter_Cylinder")

    targeter.In.onConfigure(targeter, {
        beamMode = "cylinder",
        rayCount = 8,
    })

    local rays = targeter:_generateRays()

    -- Center ray + 8 ring rays = 9 total
    assert_eq(#rays, 9, "Cylinder should generate 9 rays (center + 8)")

    cleanupTargeter(targeter)
end)

test("Cone mode generates multiple rays", "Beam Modes", function()
    local targeter = createTestTargeter("TestTargeter_Cone")

    targeter.In.onConfigure(targeter, {
        beamMode = "cone",
        rayCount = 6,
    })

    local rays = targeter:_generateRays()

    -- Center ray + 6 spread rays = 7 total
    assert_eq(#rays, 7, "Cone should generate 7 rays (center + 6)")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- HELPER METHOD TESTS
--------------------------------------------------------------------------------

test("isScanning returns scanning state", "Helper Methods", function()
    local targeter = createTestTargeter("TestTargeter_IsScanning")

    assert_false(targeter:isScanning(), "Should not be scanning initially")

    targeter.In.onEnable(targeter)
    assert_true(targeter:isScanning(), "Should be scanning after enable")

    targeter.In.onDisable(targeter)
    assert_false(targeter:isScanning(), "Should not be scanning after disable")

    cleanupTargeter(targeter)
end)

test("hasTargets returns target state", "Helper Methods", function()
    local targeter = createTestTargeter("TestTargeter_HasTargets")
    captureOutput(targeter)

    -- Position scanner to face -Z
    targeter._testScanner.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi, 0)
    addTarget(targeter, Vector3.new(0, 10, -20), "Enemy")

    targeter.In.onConfigure(targeter, {
        scanMode = "pulse",
        range = 50,
    })

    assert_false(targeter:hasTargets(), "Should have no targets initially")

    targeter.In.onScan(targeter)
    assert_true(targeter:hasTargets(), "Should have targets after scan")

    cleanupTargeter(targeter)
end)

test("isEnabled returns enabled state", "Helper Methods", function()
    local targeter = createTestTargeter("TestTargeter_IsEnabled")

    assert_false(targeter:isEnabled(), "Should not be enabled initially")

    targeter.In.onEnable(targeter)
    assert_true(targeter:isEnabled(), "Should be enabled after onEnable")

    targeter.In.onDisable(targeter)
    assert_false(targeter:isEnabled(), "Should not be enabled after onDisable")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- LIFECYCLE TESTS
--------------------------------------------------------------------------------

test("Sys.onStop stops scanning", "Lifecycle", function()
    local targeter = createTestTargeter("TestTargeter_SysStop")

    targeter.In.onEnable(targeter)
    assert_true(targeter._scanning, "Should be scanning")

    targeter.Sys.onStop(targeter)
    assert_false(targeter._scanning, "Should stop scanning on Sys.onStop")

    cleanupTargeter(targeter)
end)

--------------------------------------------------------------------------------
-- EDGE CASES
--------------------------------------------------------------------------------

test("Empty onConfigure does not crash", "Edge Cases", function()
    local targeter = createTestTargeter("TestTargeter_EmptyConfig")

    -- Should not error
    targeter.In.onConfigure(targeter, nil)
    targeter.In.onConfigure(targeter, {})

    assert_eq(targeter:getAttribute("BeamMode"), "pinpoint", "Defaults should remain")

    cleanupTargeter(targeter)
end)

test("Targeter works without model", "Edge Cases", function()
    local targeter = Targeter:new({ id = "TestTargeter_NoModel" })
    targeter.Sys.onInit(targeter)

    -- Should not error
    targeter.In.onConfigure(targeter, { scanMode = "pulse" })
    targeter.In.onScan(targeter)  -- Will scan from 0,0,0

    targeter.Sys.onStop(targeter)
end)

return Tests
