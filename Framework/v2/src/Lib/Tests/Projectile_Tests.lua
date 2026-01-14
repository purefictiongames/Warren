--[[
    LibPureFiction Framework v2
    Projectile Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Projectile.runAll()
    ```

    Or run specific test groups:

    ```lua
    Tests.Projectile.runGroup("Basics")
    Tests.Projectile.runGroup("Configuration")
    Tests.Projectile.runGroup("Launch")
    Tests.Projectile.runGroup("Movement")
    Tests.Projectile.demo()  -- Visual demo
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local Components = Lib.Components
local Projectile = Components.Projectile

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
        print("  [PASS]", msg)
    elseif level == "fail" then
        warn("  [FAIL]", msg)
    elseif level == "error" then
        warn("  [ERR]", msg)
    elseif level == "group" then
        print("\n>>", msg)
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
        error(string.format("%s: expected ~%s, got %s (tolerance %s)",
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
    print("  Projectile Test Suite")
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
        "Results: %d passed, %d failed",
        stats.passed, stats.failed
    ))
end

function Tests.runGroup(group)
    resetStats()
    print("\n========================================")
    print("  Projectile:", group)
    print("========================================")

    log("group", group)
    for _, testCase in ipairs(testCases) do
        if testCase.group == group then
            runTest(testCase)
        end
    end

    log("summary", string.format(
        "Results: %d passed, %d failed",
        stats.passed, stats.failed
    ))
end

function Tests.run(name)
    resetStats()
    for _, testCase in ipairs(testCases) do
        if testCase.name == name then
            runTest(testCase)
            return
        end
    end
    warn("Test not found:", name)
end

function Tests.list()
    print("\nAvailable test groups:")
    for group in pairs(testGroups) do
        print("  -", group)
    end
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function createTestPart(name)
    local part = Instance.new("Part")
    part.Name = name or "TestProjectile"
    part.Size = Vector3.new(1, 1, 2)
    part.Anchored = true
    part.CanCollide = false
    part.Parent = workspace
    return part
end

local function createTestProjectile(id, part)
    part = part or createTestPart(id)
    local projectile = Projectile:new({ id = id or "TestProjectile", model = part })
    projectile.Sys.onInit(projectile)
    return projectile, part
end

local function cleanupPart(part)
    if part and part.Parent then
        part:Destroy()
    end
end

local function cleanupProjectile(projectile, part)
    if projectile and projectile.Sys and projectile.Sys.onStop then
        projectile.Sys.onStop(projectile)
    end
    cleanupPart(part)
end

--------------------------------------------------------------------------------
-- BASIC TESTS
--------------------------------------------------------------------------------

test("Projectile extends Node", "Basics", function()
    assert_eq(Projectile.name, "Projectile", "Has correct name")
    assert_not_nil(Projectile.Sys, "Has Sys handlers")
    assert_not_nil(Projectile.In, "Has In handlers")
    assert_not_nil(Projectile.Out, "Has Out schema")
end)

test("Projectile creates instance", "Basics", function()
    local proj, part = createTestProjectile("TestProj1")
    assert_not_nil(proj, "Instance created")
    assert_eq(proj.id, "TestProj1", "Has correct ID")
    assert_eq(proj.class, "Projectile", "Has correct class")
    cleanupProjectile(proj, part)
end)

test("Projectile initializes with defaults", "Basics", function()
    local proj, part = createTestProjectile("TestProj2")
    assert_eq(proj:getAttribute("Speed"), 50, "Default speed")
    assert_eq(proj:getAttribute("Lifespan"), 5, "Default lifespan")
    assert_eq(proj:getAttribute("MaxDistance"), 500, "Default max distance")
    assert_eq(proj:getAttribute("Damage"), 10, "Default damage")
    assert_eq(proj:getAttribute("MovementType"), "linear", "Default movement type")
    assert_eq(proj:getAttribute("CollisionMode"), "touch", "Default collision mode")
    assert_eq(proj:getAttribute("OnHit"), "despawn", "Default on hit")
    cleanupProjectile(proj, part)
end)

test("Projectile initializes flight state", "Basics", function()
    local proj, part = createTestProjectile("TestProj3")
    assert_false(proj._flying, "Not flying initially")
    assert_eq(proj._distanceTraveled, 0, "No distance traveled")
    cleanupProjectile(proj, part)
end)

--------------------------------------------------------------------------------
-- CONFIGURATION TESTS
--------------------------------------------------------------------------------

test("onConfigure sets speed", "Configuration", function()
    local proj, part = createTestProjectile()
    proj.In.onConfigure(proj, { speed = 100 })
    assert_eq(proj:getAttribute("Speed"), 100, "Speed updated")
    cleanupProjectile(proj, part)
end)

test("onConfigure sets lifespan", "Configuration", function()
    local proj, part = createTestProjectile()
    proj.In.onConfigure(proj, { lifespan = 10 })
    assert_eq(proj:getAttribute("Lifespan"), 10, "Lifespan updated")
    cleanupProjectile(proj, part)
end)

test("onConfigure sets damage", "Configuration", function()
    local proj, part = createTestProjectile()
    proj.In.onConfigure(proj, { damage = 50 })
    assert_eq(proj:getAttribute("Damage"), 50, "Damage updated")
    cleanupProjectile(proj, part)
end)

test("onConfigure sets movement type", "Configuration", function()
    local proj, part = createTestProjectile()
    proj.In.onConfigure(proj, { movementType = "ballistic" })
    assert_eq(proj:getAttribute("MovementType"), "ballistic", "Movement type updated")
    cleanupProjectile(proj, part)
end)

test("onConfigure sets collision mode", "Configuration", function()
    local proj, part = createTestProjectile()
    proj.In.onConfigure(proj, { collisionMode = "raycast" })
    assert_eq(proj:getAttribute("CollisionMode"), "raycast", "Collision mode updated")
    cleanupProjectile(proj, part)
end)

test("onConfigure sets onHit behavior", "Configuration", function()
    local proj, part = createTestProjectile()
    proj.In.onConfigure(proj, { onHit = "pierce" })
    assert_eq(proj:getAttribute("OnHit"), "pierce", "OnHit updated")
    cleanupProjectile(proj, part)
end)

test("onConfigure sets multiple values", "Configuration", function()
    local proj, part = createTestProjectile()
    proj.In.onConfigure(proj, {
        speed = 200,
        damage = 75,
        lifespan = 3,
        maxDistance = 1000,
    })
    assert_eq(proj:getAttribute("Speed"), 200, "Speed")
    assert_eq(proj:getAttribute("Damage"), 75, "Damage")
    assert_eq(proj:getAttribute("Lifespan"), 3, "Lifespan")
    assert_eq(proj:getAttribute("MaxDistance"), 1000, "MaxDistance")
    cleanupProjectile(proj, part)
end)

test("onConfigure stores collision filter", "Configuration", function()
    local proj, part = createTestProjectile()
    local filter = { class = "Enemy" }
    proj.In.onConfigure(proj, { collisionFilter = filter })
    assert_eq(proj._collisionFilter, filter, "Filter stored")
    cleanupProjectile(proj, part)
end)

--------------------------------------------------------------------------------
-- LAUNCH TESTS
--------------------------------------------------------------------------------

test("onLaunch fires launched signal", "Launch", function()
    local proj, part = createTestProjectile()
    local launchedData = nil

    local origFire = proj.Out.Fire
    proj.Out.Fire = function(self, signal, data)
        if signal == "launched" then
            launchedData = data
        end
        origFire(self, signal, data)
    end

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    assert_not_nil(launchedData, "Launched signal fired")
    assert_eq(launchedData.projectileId, proj.id, "Has projectile ID")
    assert_near(launchedData.direction.Z, -1, 0.01, "Direction correct")

    cleanupProjectile(proj, part)
end)

test("onLaunch sets flying state", "Launch", function()
    local proj, part = createTestProjectile()

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    assert_true(proj._flying, "Flying state set")

    cleanupProjectile(proj, part)
end)

test("onLaunch errors without origin", "Launch", function()
    local proj, part = createTestProjectile()
    local errFired = false

    proj.Err = {
        Fire = function(self, data)
            errFired = true
            assert_eq(data.reason, "launchFailed", "Correct error reason")
        end,
    }

    proj.In.onLaunch(proj, { direction = Vector3.new(0, 0, -1) })

    assert_true(errFired, "Error fired")
    cleanupProjectile(proj, part)
end)

test("onLaunch errors without direction", "Launch", function()
    local proj, part = createTestProjectile()
    local errFired = false

    proj.Err = {
        Fire = function(self, data)
            errFired = true
        end,
    }

    proj.In.onLaunch(proj, { origin = Vector3.new(0, 0, 0) })

    assert_true(errFired, "Error fired")
    cleanupProjectile(proj, part)
end)

test("onLaunch errors if already flying", "Launch", function()
    local proj, part = createTestProjectile()
    local errCount = 0

    proj.Err = {
        Fire = function(self, data)
            errCount = errCount + 1
        end,
    }

    -- First launch succeeds
    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    -- Second launch should error
    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    assert_eq(errCount, 1, "Error fired on second launch")
    cleanupProjectile(proj, part)
end)

test("onLaunch accepts speed override", "Launch", function()
    local proj, part = createTestProjectile()

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
        speed = 150,
    })

    assert_eq(proj._currentSpeed, 150, "Speed override applied")
    cleanupProjectile(proj, part)
end)

test("onLaunch accepts damage override", "Launch", function()
    local proj, part = createTestProjectile()

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
        damage = 999,
    })

    assert_eq(proj:getAttribute("Damage"), 999, "Damage override applied")
    cleanupProjectile(proj, part)
end)

test("onLaunch positions model at origin", "Launch", function()
    local proj, part = createTestProjectile()
    local origin = Vector3.new(10, 20, 30)

    proj.In.onLaunch(proj, {
        origin = origin,
        direction = Vector3.new(0, 0, -1),
    })

    local pos = part.Position
    assert_near(pos.X, origin.X, 0.1, "X position")
    assert_near(pos.Y, origin.Y, 0.1, "Y position")
    assert_near(pos.Z, origin.Z, 0.1, "Z position")

    cleanupProjectile(proj, part)
end)

--------------------------------------------------------------------------------
-- ABORT TESTS
--------------------------------------------------------------------------------

test("onAbort stops flight", "Abort", function()
    local proj, part = createTestProjectile()

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    assert_true(proj._flying, "Flying after launch")

    proj.In.onAbort(proj)

    assert_false(proj._flying, "Not flying after abort")
    cleanupProjectile(proj, part)
end)

test("onAbort fires expired signal with reason 'aborted'", "Abort", function()
    local proj, part = createTestProjectile()
    local expiredData = nil

    local origFire = proj.Out.Fire
    proj.Out.Fire = function(self, signal, data)
        if signal == "expired" then
            expiredData = data
        end
        origFire(self, signal, data)
    end

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    proj.In.onAbort(proj)

    assert_not_nil(expiredData, "Expired signal fired")
    assert_eq(expiredData.reason, "aborted", "Reason is 'aborted'")

    cleanupProjectile(proj, part)
end)

test("onAbort does nothing if not flying", "Abort", function()
    local proj, part = createTestProjectile()
    local expiredFired = false

    local origFire = proj.Out.Fire
    proj.Out.Fire = function(self, signal, data)
        if signal == "expired" then
            expiredFired = true
        end
        origFire(self, signal, data)
    end

    proj.In.onAbort(proj)

    assert_false(expiredFired, "No expired signal when not flying")
    cleanupProjectile(proj, part)
end)

--------------------------------------------------------------------------------
-- MOVEMENT TESTS (Basic - requires waiting)
--------------------------------------------------------------------------------

test("Linear projectile moves in direction", "Movement", function()
    local proj, part = createTestProjectile()

    local startPos = Vector3.new(0, 10, 0)
    local direction = Vector3.new(0, 0, -1)

    proj.In.onConfigure(proj, { speed = 100, collisionMode = "none" })
    proj.In.onLaunch(proj, {
        origin = startPos,
        direction = direction,
    })

    -- Wait a short time
    task.wait(0.1)

    local currentPos = part.Position
    -- Should have moved in -Z direction
    assert_true(currentPos.Z < startPos.Z, "Moved in -Z direction")

    cleanupProjectile(proj, part)
end)

test("Projectile tracks distance traveled", "Movement", function()
    local proj, part = createTestProjectile()

    proj.In.onConfigure(proj, { speed = 100, collisionMode = "none" })
    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    task.wait(0.1)

    assert_true(proj._distanceTraveled > 0, "Distance tracked")

    cleanupProjectile(proj, part)
end)

test("Projectile expires after lifespan", "Movement", function()
    local proj, part = createTestProjectile()
    local expiredData = nil

    local origFire = proj.Out.Fire
    proj.Out.Fire = function(self, signal, data)
        if signal == "expired" then
            expiredData = data
        end
        origFire(self, signal, data)
    end

    proj.In.onConfigure(proj, {
        speed = 100,
        lifespan = 0.2,
        collisionMode = "none",
    })

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    task.wait(0.3)

    assert_not_nil(expiredData, "Expired signal fired")
    assert_eq(expiredData.reason, "lifespan", "Reason is 'lifespan'")
    assert_false(proj._flying, "No longer flying")

    cleanupProjectile(proj, part)
end)

test("Projectile expires after max distance", "Movement", function()
    local proj, part = createTestProjectile()
    local expiredData = nil

    local origFire = proj.Out.Fire
    proj.Out.Fire = function(self, signal, data)
        if signal == "expired" then
            expiredData = data
        end
        origFire(self, signal, data)
    end

    proj.In.onConfigure(proj, {
        speed = 200,
        maxDistance = 10,
        lifespan = 10,  -- Long lifespan so distance triggers first
        collisionMode = "none",
    })

    proj.In.onLaunch(proj, {
        origin = Vector3.new(0, 10, 0),
        direction = Vector3.new(0, 0, -1),
    })

    task.wait(0.2)

    assert_not_nil(expiredData, "Expired signal fired")
    assert_eq(expiredData.reason, "maxDistance", "Reason is 'maxDistance'")

    cleanupProjectile(proj, part)
end)

--------------------------------------------------------------------------------
-- BALLISTIC TESTS
--------------------------------------------------------------------------------

test("Ballistic projectile falls with gravity", "Ballistic", function()
    local proj, part = createTestProjectile()

    local startPos = Vector3.new(0, 50, 0)

    proj.In.onConfigure(proj, {
        movementType = "ballistic",
        speed = 50,
        gravity = 196.2,
        collisionMode = "none",
    })

    proj.In.onLaunch(proj, {
        origin = startPos,
        direction = Vector3.new(1, 0, 0),  -- Horizontal
    })

    task.wait(0.2)

    local currentPos = part.Position
    -- Should have dropped due to gravity
    assert_true(currentPos.Y < startPos.Y, "Dropped due to gravity")
    -- Should have moved horizontally too
    assert_true(currentPos.X > startPos.X, "Moved horizontally")

    cleanupProjectile(proj, part)
end)

--------------------------------------------------------------------------------
-- VISUAL DEMO
--------------------------------------------------------------------------------

local demoFolder = nil

function Tests.demo()
    Tests.cleanup()

    demoFolder = Instance.new("Folder")
    demoFolder.Name = "ProjectileDemo"
    demoFolder.Parent = workspace

    -- Create a floor
    local floor = Instance.new("Part")
    floor.Name = "Floor"
    floor.Size = Vector3.new(100, 1, 100)
    floor.Position = Vector3.new(0, 0, 0)
    floor.Anchored = true
    floor.BrickColor = BrickColor.new("Dark stone grey")
    floor.Parent = demoFolder

    -- Create a target
    local target = Instance.new("Part")
    target.Name = "Target"
    target.Size = Vector3.new(5, 5, 5)
    target.Position = Vector3.new(0, 5, -50)
    target.Anchored = true
    target.BrickColor = BrickColor.new("Bright red")
    target:SetAttribute("NodeClass", "Enemy")
    target.Parent = demoFolder

    -- Create projectile
    local bullet = Instance.new("Part")
    bullet.Name = "Bullet"
    bullet.Size = Vector3.new(0.5, 0.5, 2)
    bullet.Anchored = true
    bullet.CanCollide = false
    bullet.BrickColor = BrickColor.new("Bright yellow")
    bullet.Parent = demoFolder

    local projectile = Projectile:new({ id = "DemoBullet", model = bullet })
    projectile.Sys.onInit(projectile)

    -- Configure
    projectile.In.onConfigure(projectile, {
        speed = 80,
        damage = 25,
        lifespan = 5,
        collisionFilter = { class = "Enemy" },
    })

    -- Wire signals
    projectile.Out.Fire = function(self, signal, data)
        if signal == "launched" then
            print("[Demo] Projectile launched!")
        elseif signal == "hit" then
            print("[Demo] HIT!", data.target.Name, "at", tostring(data.position))
            -- Flash the target
            local origColor = data.target.BrickColor
            data.target.BrickColor = BrickColor.new("White")
            task.delay(0.1, function()
                if data.target.Parent then
                    data.target.BrickColor = origColor
                end
            end)
        elseif signal == "expired" then
            print("[Demo] Projectile expired:", data.reason)
        end
    end

    -- Launch
    print("[Demo] Launching projectile toward target...")
    projectile.In.onLaunch(projectile, {
        origin = Vector3.new(0, 5, 0),
        direction = Vector3.new(0, 0, -1),
    })

    print("[Demo] Demo running. Call Tests.Projectile.cleanup() to remove.")
end

function Tests.demoBalllistic()
    Tests.cleanup()

    demoFolder = Instance.new("Folder")
    demoFolder.Name = "ProjectileDemo"
    demoFolder.Parent = workspace

    -- Create a floor
    local floor = Instance.new("Part")
    floor.Name = "Floor"
    floor.Size = Vector3.new(200, 1, 200)
    floor.Position = Vector3.new(0, 0, 0)
    floor.Anchored = true
    floor.BrickColor = BrickColor.new("Dark stone grey")
    floor.Parent = demoFolder

    -- Create projectile (cannonball)
    local ball = Instance.new("Part")
    ball.Name = "Cannonball"
    ball.Shape = Enum.PartType.Ball
    ball.Size = Vector3.new(3, 3, 3)
    ball.Anchored = true
    ball.CanCollide = false
    ball.BrickColor = BrickColor.new("Black")
    ball.Parent = demoFolder

    local projectile = Projectile:new({ id = "DemoCannonball", model = ball })
    projectile.Sys.onInit(projectile)

    -- Configure for ballistic
    projectile.In.onConfigure(projectile, {
        speed = 60,
        movementType = "ballistic",
        gravity = 50,  -- Lower gravity for dramatic arc
        lifespan = 10,
        collisionMode = "none",  -- Let it arc freely
    })

    -- Wire signals
    projectile.Out.Fire = function(self, signal, data)
        if signal == "launched" then
            print("[Demo] Cannonball launched!")
        elseif signal == "expired" then
            print("[Demo] Cannonball landed/expired:", data.reason)
        end
    end

    -- Launch at 45 degree angle
    local angle = math.rad(45)
    local direction = Vector3.new(0, math.sin(angle), -math.cos(angle)).Unit

    print("[Demo] Launching cannonball in ballistic arc...")
    projectile.In.onLaunch(projectile, {
        origin = Vector3.new(0, 5, 50),
        direction = direction,
    })

    print("[Demo] Demo running. Call Tests.Projectile.cleanup() to remove.")
end

function Tests.cleanup()
    if demoFolder then
        demoFolder:Destroy()
        demoFolder = nil
    end
    print("[Demo] Cleanup complete")
end

return Tests
