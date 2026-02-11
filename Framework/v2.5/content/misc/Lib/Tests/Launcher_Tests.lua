--[[
    LibPureFiction Framework v2
    Launcher Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Launcher.runAll()
    ```

    Or run specific test groups:

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Launcher.runGroup("Launcher Basics")
    Tests.Launcher.runGroup("Cooldown")
    Tests.Launcher.runGroup("Launch Methods")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local Launcher = Lib.Components.Launcher

-- Access SpawnerCore directly for testing
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
    print("  Launcher Test Suite")
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

-- Create a mock template folder with projectile templates
local function createMockTemplates()
    local folder = Instance.new("Folder")
    folder.Name = "MockProjectiles"

    -- Create projectile template
    local bullet = Instance.new("Part")
    bullet.Name = "Bullet"
    bullet.Size = Vector3.new(0.5, 0.5, 1)
    bullet.Anchored = true
    bullet.CanCollide = false
    bullet.Parent = folder

    -- Create another projectile
    local rocket = Instance.new("Part")
    rocket.Name = "Rocket"
    rocket.Size = Vector3.new(1, 1, 3)
    rocket.Anchored = true
    rocket.CanCollide = false
    rocket.Parent = folder

    return folder
end

-- Create a mock muzzle part
local function createMuzzlePart()
    local part = Instance.new("Part")
    part.Name = "MockMuzzle"
    part.Size = Vector3.new(1, 1, 2)
    part.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, 0, 0)  -- Facing +Z
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.5
    part.Parent = workspace
    return part
end

-- Create a test launcher with templates initialized
local function createTestLauncher(id)
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage

    SpawnerCore.reset()
    SpawnerCore.init({ templates = folder })

    local muzzle = createMuzzlePart()
    local launcher = Launcher:new({
        id = id or "TestLauncher",
        model = muzzle,
    })
    launcher.Sys.onInit(launcher)

    -- Track for cleanup
    launcher._testFolder = folder
    launcher._testMuzzle = muzzle
    launcher._spawnedProjectiles = {}

    return launcher
end

-- Cleanup test launcher
local function cleanupLauncher(launcher)
    if launcher._testFolder then
        launcher._testFolder:Destroy()
    end
    if launcher._testMuzzle then
        launcher._testMuzzle:Destroy()
    end
    -- Clean up any spawned projectiles
    for _, proj in ipairs(launcher._spawnedProjectiles or {}) do
        if proj and proj.Parent then
            proj:Destroy()
        end
    end
    SpawnerCore.reset()
end

-- Capture output signals
local function captureOutput(launcher)
    local captured = {
        fired = {},
    }

    launcher.Out = {
        Fire = function(self, signal, data)
            if captured[signal] then
                table.insert(captured[signal], data)
                -- Track projectile for cleanup
                if data.projectile then
                    table.insert(launcher._spawnedProjectiles, data.projectile)
                end
            end
        end,
    }

    return captured
end

-- Capture error signals
local function captureErrors(launcher)
    local captured = {}

    launcher.Err = {
        Fire = function(self, data)
            table.insert(captured, data)
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
-- BASIC LAUNCHER TESTS
--------------------------------------------------------------------------------

test("Launcher.extend creates component class", "Launcher Basics", function()
    assert_not_nil(Launcher, "Launcher should be defined")
    assert_eq(Launcher.name, "Launcher", "Launcher name should be 'Launcher'")
    assert_eq(Launcher.domain, "server", "Launcher domain should be 'server'")
end)

test("Launcher instance initializes with default attributes", "Launcher Basics", function()
    local launcher = createTestLauncher("TestLauncher_Defaults")

    assert_eq(launcher:getAttribute("ProjectileTemplate"), "", "Default ProjectileTemplate should be empty")
    assert_eq(launcher:getAttribute("LaunchForce"), 100, "Default LaunchForce should be 100")
    assert_eq(launcher:getAttribute("LaunchMethod"), "impulse", "Default LaunchMethod should be 'impulse'")
    assert_eq(launcher:getAttribute("Cooldown"), 0.5, "Default Cooldown should be 0.5")

    cleanupLauncher(launcher)
end)

test("Launcher initializes internal state", "Launcher Basics", function()
    local launcher = createTestLauncher("TestLauncher_InternalState")

    assert_eq(launcher._lastFireTime, 0, "_lastFireTime should be 0 initially")
    assert_not_nil(launcher._muzzle, "_muzzle should be set from model")

    cleanupLauncher(launcher)
end)

--------------------------------------------------------------------------------
-- CONFIGURATION TESTS
--------------------------------------------------------------------------------

test("onConfigure sets projectile template", "Configuration", function()
    local launcher = createTestLauncher("TestLauncher_ConfigTemplate")

    launcher.In.onConfigure(launcher, { projectileTemplate = "Bullet" })
    assert_eq(launcher:getAttribute("ProjectileTemplate"), "Bullet", "Template should be 'Bullet'")

    cleanupLauncher(launcher)
end)

test("onConfigure sets launch force", "Configuration", function()
    local launcher = createTestLauncher("TestLauncher_ConfigForce")

    launcher.In.onConfigure(launcher, { launchForce = 200 })
    assert_eq(launcher:getAttribute("LaunchForce"), 200, "LaunchForce should be 200")

    launcher.In.onConfigure(launcher, { launchForce = -50 })  -- negative
    assert_eq(launcher:getAttribute("LaunchForce"), 50, "LaunchForce should be absolute value")

    cleanupLauncher(launcher)
end)

test("onConfigure sets launch method", "Configuration", function()
    local launcher = createTestLauncher("TestLauncher_ConfigMethod")

    launcher.In.onConfigure(launcher, { launchMethod = "spring" })
    assert_eq(launcher:getAttribute("LaunchMethod"), "spring", "LaunchMethod should be 'spring'")

    launcher.In.onConfigure(launcher, { launchMethod = "IMPULSE" })  -- uppercase
    assert_eq(launcher:getAttribute("LaunchMethod"), "impulse", "LaunchMethod should be 'impulse'")

    cleanupLauncher(launcher)
end)

test("onConfigure sets cooldown", "Configuration", function()
    local launcher = createTestLauncher("TestLauncher_ConfigCooldown")

    launcher.In.onConfigure(launcher, { cooldown = 1.0 })
    assert_eq(launcher:getAttribute("Cooldown"), 1.0, "Cooldown should be 1.0")

    launcher.In.onConfigure(launcher, { cooldown = -0.5 })  -- negative
    assert_eq(launcher:getAttribute("Cooldown"), 0, "Cooldown should clamp to 0")

    cleanupLauncher(launcher)
end)

--------------------------------------------------------------------------------
-- FIRE TESTS
--------------------------------------------------------------------------------

test("onFire spawns projectile", "Fire", function()
    local launcher = createTestLauncher("TestLauncher_FireSpawn")
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    launcher.In.onFire(launcher)

    assert_eq(#captured.fired, 1, "Should fire one projectile")
    assert_not_nil(captured.fired[1].projectile, "Should have projectile instance")
    assert_not_nil(captured.fired[1].direction, "Should have direction")
    assert_not_nil(captured.fired[1].assetId, "Should have assetId")

    cleanupLauncher(launcher)
end)

test("onFire uses muzzle LookVector for blind fire", "Fire", function()
    local launcher = createTestLauncher("TestLauncher_FireBlind")
    local captured = captureOutput(launcher)

    -- Point muzzle in a specific direction
    launcher._testMuzzle.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.pi / 2, 0)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    launcher.In.onFire(launcher)  -- No targetPosition

    local direction = captured.fired[1].direction
    -- Should be roughly pointing in +X direction (after Y rotation)
    assert_near(math.abs(direction.X), 1, 0.1, "Direction should be along X axis")

    cleanupLauncher(launcher)
end)

test("onFire calculates direction to target", "Fire", function()
    local launcher = createTestLauncher("TestLauncher_FireTargeted")
    local captured = captureOutput(launcher)

    launcher._testMuzzle.CFrame = CFrame.new(0, 10, 0)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    -- Fire at a target above and in front
    launcher.In.onFire(launcher, { targetPosition = Vector3.new(0, 20, 10) })

    local direction = captured.fired[1].direction
    -- Should point toward target
    assert_true(direction.Y > 0, "Direction should have positive Y component")
    assert_true(direction.Z > 0, "Direction should have positive Z component")

    cleanupLauncher(launcher)
end)

test("onFire fails without template", "Fire", function()
    local launcher = createTestLauncher("TestLauncher_FireNoTemplate")
    local captured = captureOutput(launcher)
    local errors = captureErrors(launcher)

    launcher.In.onConfigure(launcher, { cooldown = 0 })
    -- No template configured

    launcher.In.onFire(launcher)

    assert_eq(#captured.fired, 0, "Should not fire without template")
    assert_eq(#errors, 1, "Should have error")
    assert_eq(errors[1].reason, "no_template", "Error should be no_template")

    cleanupLauncher(launcher)
end)

--------------------------------------------------------------------------------
-- COOLDOWN TESTS
--------------------------------------------------------------------------------

test("onFire respects cooldown", "Cooldown", function()
    local launcher = createTestLauncher("TestLauncher_Cooldown")
    local captured = captureOutput(launcher)
    local errors = captureErrors(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 1.0,  -- 1 second cooldown
    })

    -- First fire should succeed
    launcher.In.onFire(launcher)
    assert_eq(#captured.fired, 1, "First fire should succeed")

    -- Immediate second fire should fail
    launcher.In.onFire(launcher)
    assert_eq(#captured.fired, 1, "Second fire should be blocked")
    assert_eq(#errors, 1, "Should have cooldown error")
    assert_eq(errors[1].reason, "cooldown", "Error should be cooldown")
    assert_true(errors[1].remaining > 0, "Should have remaining time")

    cleanupLauncher(launcher)
end)

test("onFire allows fire after cooldown elapsed", "Cooldown", function()
    local launcher = createTestLauncher("TestLauncher_CooldownElapsed")
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0.1,  -- Short cooldown for testing
    })

    launcher.In.onFire(launcher)
    assert_eq(#captured.fired, 1, "First fire should succeed")

    -- Wait for cooldown
    task.wait(0.15)

    launcher.In.onFire(launcher)
    assert_eq(#captured.fired, 2, "Second fire should succeed after cooldown")

    cleanupLauncher(launcher)
end)

test("isReady returns cooldown state", "Cooldown", function()
    local launcher = createTestLauncher("TestLauncher_IsReady")
    captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 1.0,
    })

    assert_true(launcher:isReady(), "Should be ready initially")

    launcher.In.onFire(launcher)

    assert_false(launcher:isReady(), "Should not be ready after fire")

    cleanupLauncher(launcher)
end)

test("getCooldownRemaining returns time remaining", "Cooldown", function()
    local launcher = createTestLauncher("TestLauncher_CooldownRemaining")
    captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 1.0,
    })

    assert_eq(launcher:getCooldownRemaining(), 0, "Should have 0 remaining initially")

    launcher.In.onFire(launcher)

    local remaining = launcher:getCooldownRemaining()
    assert_true(remaining > 0, "Should have remaining time after fire")
    assert_true(remaining <= 1.0, "Remaining should not exceed cooldown")

    cleanupLauncher(launcher)
end)

--------------------------------------------------------------------------------
-- LAUNCH METHOD TESTS
--------------------------------------------------------------------------------

test("Impulse method sets velocity", "Launch Methods", function()
    local launcher = createTestLauncher("TestLauncher_Impulse")
    local captured = captureOutput(launcher)

    launcher._testMuzzle.CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(0, 0, 0)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        launchMethod = "impulse",
        launchForce = 100,
        cooldown = 0,
    })

    launcher.In.onFire(launcher)

    -- Wait a frame for physics
    waitFrames(1)

    local projectile = captured.fired[1].projectile
    if projectile:IsA("BasePart") then
        local velocity = projectile.AssemblyLinearVelocity
        -- Velocity magnitude should be approximately launch force
        local speed = velocity.Magnitude
        assert_gte(speed, 50, "Projectile should have significant velocity")
    end

    cleanupLauncher(launcher)
end)

test("Spring method launches projectile", "Launch Methods", function()
    local launcher = createTestLauncher("TestLauncher_Spring")
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        launchMethod = "spring",
        launchForce = 100,
        cooldown = 0,
    })

    launcher.In.onFire(launcher)

    assert_eq(#captured.fired, 1, "Should fire with spring method")
    assert_not_nil(captured.fired[1].projectile, "Should have projectile")

    cleanupLauncher(launcher)
end)

--------------------------------------------------------------------------------
-- PROJECTILE PREPARATION TESTS
--------------------------------------------------------------------------------

test("Projectile is unanchored after fire", "Projectile Setup", function()
    local launcher = createTestLauncher("TestLauncher_Unanchored")
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    launcher.In.onFire(launcher)

    local projectile = captured.fired[1].projectile
    if projectile:IsA("BasePart") then
        assert_false(projectile.Anchored, "Projectile should be unanchored")
    end

    cleanupLauncher(launcher)
end)

test("Projectile has CanCollide enabled", "Projectile Setup", function()
    local launcher = createTestLauncher("TestLauncher_CanCollide")
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    launcher.In.onFire(launcher)

    local projectile = captured.fired[1].projectile
    if projectile:IsA("BasePart") then
        assert_true(projectile.CanCollide, "Projectile should have CanCollide")
    end

    cleanupLauncher(launcher)
end)

test("Projectile has spawn source attribute", "Projectile Setup", function()
    local launcher = createTestLauncher("TestLauncher_SpawnSource")
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    launcher.In.onFire(launcher)

    local projectile = captured.fired[1].projectile
    local spawnSource = projectile:GetAttribute("NodeSpawnSource")
    assert_eq(spawnSource, launcher.id, "Projectile should have spawn source")

    cleanupLauncher(launcher)
end)

--------------------------------------------------------------------------------
-- OUTPUT SIGNAL TESTS
--------------------------------------------------------------------------------

test("fired signal includes all required fields", "Output Signals", function()
    local launcher = createTestLauncher("TestLauncher_OutputFields")
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    launcher.In.onFire(launcher)

    local data = captured.fired[1]
    assert_not_nil(data.projectile, "Should have projectile")
    assert_not_nil(data.direction, "Should have direction")
    assert_not_nil(data.assetId, "Should have assetId")
    assert_not_nil(data.launcherId, "Should have launcherId")
    assert_eq(data.launcherId, launcher.id, "launcherId should match")

    cleanupLauncher(launcher)
end)

--------------------------------------------------------------------------------
-- EDGE CASES
--------------------------------------------------------------------------------

test("Empty onConfigure does not crash", "Edge Cases", function()
    local launcher = createTestLauncher("TestLauncher_EmptyConfig")

    -- Should not error
    launcher.In.onConfigure(launcher, nil)
    launcher.In.onConfigure(launcher, {})

    assert_eq(launcher:getAttribute("LaunchForce"), 100, "Defaults should remain")

    cleanupLauncher(launcher)
end)

test("Launcher works without model", "Edge Cases", function()
    -- Setup templates
    local folder = createMockTemplates()
    folder.Parent = ReplicatedStorage
    SpawnerCore.reset()
    SpawnerCore.init({ templates = folder })

    local launcher = Launcher:new({ id = "TestLauncher_NoModel" })
    launcher.Sys.onInit(launcher)
    local captured = captureOutput(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0,
    })

    -- Should not error, fires from 0,0,0
    launcher.In.onFire(launcher)

    assert_eq(#captured.fired, 1, "Should fire even without model")

    -- Cleanup
    folder:Destroy()
    SpawnerCore.reset()
end)

test("Multiple rapid fires respect cooldown", "Edge Cases", function()
    local launcher = createTestLauncher("TestLauncher_RapidFire")
    local captured = captureOutput(launcher)
    local errors = captureErrors(launcher)

    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        cooldown = 0.5,
    })

    -- Rapid fire attempts
    for i = 1, 5 do
        launcher.In.onFire(launcher)
    end

    assert_eq(#captured.fired, 1, "Only first fire should succeed")
    assert_eq(#errors, 4, "Should have 4 cooldown errors")

    cleanupLauncher(launcher)
end)

return Tests
