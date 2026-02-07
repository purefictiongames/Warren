--[[
    Warren Framework v2
    PathFollowerCore & PathedConveyor Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.PathedConveyor.runAll()
    ```

    Or run specific test groups:

    ```lua
    Tests.PathedConveyor.runGroup("PathFollowerCore")
    Tests.PathedConveyor.runGroup("Segment Speeds")
    Tests.PathedConveyor.runGroup("PathedConveyor")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local PathedConveyor = Lib.Components.PathedConveyor

-- Access PathFollowerCore directly for testing
local PathFollowerCore = require(ReplicatedStorage.Warren.Internal.PathFollowerCore)

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
    print("  PathFollowerCore & PathedConveyor Tests")
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

-- Create waypoint parts for testing
local function createWaypoints(count, spacing)
    spacing = spacing or 10
    local waypoints = {}
    for i = 1, count do
        local part = Instance.new("Part")
        part.Name = "Waypoint_" .. i
        part.Size = Vector3.new(2, 2, 2)
        part.Position = Vector3.new((i - 1) * spacing, 0, 0)
        part.Anchored = true
        part.Parent = workspace
        table.insert(waypoints, part)
    end
    return waypoints
end

-- Cleanup waypoints
local function cleanupWaypoints(waypoints)
    for _, wp in ipairs(waypoints) do
        if wp and wp.Parent then
            wp:Destroy()
        end
    end
end

-- Create test Vector3 waypoints
local function createVector3Waypoints()
    return {
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),
        Vector3.new(20, 0, 0),
        Vector3.new(30, 0, 0),
    }
end

--------------------------------------------------------------------------------
-- PATHFOLLOWERCORE TESTS
--------------------------------------------------------------------------------

test("PathFollowerCore.new creates instance", "PathFollowerCore", function()
    local path = PathFollowerCore.new()
    assert_not_nil(path, "Should create PathFollowerCore instance")
    assert_eq(path:getWaypointCount(), 0, "Should start with 0 waypoints")
end)

test("PathFollowerCore accepts default speed in constructor", "PathFollowerCore", function()
    local path = PathFollowerCore.new({ defaultSpeed = 25 })
    assert_eq(path:getDefaultSpeed(), 25, "Should use constructor default speed")
end)

test("setWaypoints stores waypoints", "PathFollowerCore", function()
    local path = PathFollowerCore.new()
    local waypoints = createVector3Waypoints()

    local success, err = path:setWaypoints(waypoints)

    assert_true(success, "setWaypoints should succeed")
    assert_eq(path:getWaypointCount(), 4, "Should have 4 waypoints")
    assert_eq(path:getSegmentCount(), 3, "Should have 3 segments")
end)

test("setWaypoints rejects empty array", "PathFollowerCore", function()
    local path = PathFollowerCore.new()

    local success, err = path:setWaypoints({})

    assert_false(success, "setWaypoints should fail for empty array")
    assert_not_nil(err, "Should return error message")
end)

test("setWaypoints rejects single waypoint", "PathFollowerCore", function()
    local path = PathFollowerCore.new()

    local success, err = path:setWaypoints({ Vector3.new(0, 0, 0) })

    assert_false(success, "setWaypoints should fail for single waypoint")
end)

test("setWaypoints accepts Part instances", "PathFollowerCore", function()
    local waypoints = createWaypoints(3, 10)
    local path = PathFollowerCore.new()

    local success = path:setWaypoints(waypoints)

    assert_true(success, "setWaypoints should accept Parts")
    assert_eq(path:getWaypointCount(), 3, "Should have 3 waypoints")

    cleanupWaypoints(waypoints)
end)

test("getWaypointPosition returns correct positions", "PathFollowerCore", function()
    local path = PathFollowerCore.new()
    path:setWaypoints(createVector3Waypoints())

    local pos1 = path:getWaypointPosition(1)
    local pos2 = path:getWaypointPosition(2)

    assert_eq(pos1.X, 0, "First waypoint X should be 0")
    assert_eq(pos2.X, 10, "Second waypoint X should be 10")
end)

test("getDirection returns normalized direction vector", "PathFollowerCore", function()
    local path = PathFollowerCore.new()
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),
    })

    local dir = path:getDirection(1)

    assert_not_nil(dir, "Should return direction")
    assert_near(dir.X, 1, 0.001, "Direction X should be 1")
    assert_near(dir.Y, 0, 0.001, "Direction Y should be 0")
    assert_near(dir.Z, 0, 0.001, "Direction Z should be 0")
end)

test("getSegmentLength returns correct length", "PathFollowerCore", function()
    local path = PathFollowerCore.new()
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),
        Vector3.new(10, 15, 0),  -- 15 units up
    })

    local len1 = path:getSegmentLength(1)
    local len2 = path:getSegmentLength(2)

    assert_near(len1, 10, 0.001, "First segment should be 10 studs")
    assert_near(len2, 15, 0.001, "Second segment should be 15 studs")
end)

test("getTotalLength returns sum of segments", "PathFollowerCore", function()
    local path = PathFollowerCore.new()
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),
        Vector3.new(10, 15, 0),
    })

    local total = path:getTotalLength()

    assert_near(total, 25, 0.001, "Total length should be 25 studs")
end)

--------------------------------------------------------------------------------
-- SEGMENT SPEED TESTS
--------------------------------------------------------------------------------

test("setSegmentSpeed sets per-segment speed", "Segment Speeds", function()
    local path = PathFollowerCore.new({ defaultSpeed = 10 })
    path:setWaypoints(createVector3Waypoints())

    path:setSegmentSpeed(1, 20)
    path:setSegmentSpeed(2, 30)

    assert_eq(path:getSegmentSpeed(1), 20, "Segment 1 speed should be 20")
    assert_eq(path:getSegmentSpeed(2), 30, "Segment 2 speed should be 30")
    assert_eq(path:getSegmentSpeed(3), 10, "Segment 3 should use default")
end)

test("setSegmentSpeeds sets multiple speeds", "Segment Speeds", function()
    local path = PathFollowerCore.new({ defaultSpeed = 10 })
    path:setWaypoints(createVector3Waypoints())

    path:setSegmentSpeeds({
        { segment = 1, speed = 15 },
        { segment = 3, speed = 25 },
    })

    assert_eq(path:getSegmentSpeed(1), 15, "Segment 1 speed should be 15")
    assert_eq(path:getSegmentSpeed(2), 10, "Segment 2 should use default")
    assert_eq(path:getSegmentSpeed(3), 25, "Segment 3 speed should be 25")
end)

test("setAllSpeeds clears per-segment overrides", "Segment Speeds", function()
    local path = PathFollowerCore.new({ defaultSpeed = 10 })
    path:setWaypoints(createVector3Waypoints())

    path:setSegmentSpeed(1, 20)
    path:setSegmentSpeed(2, 30)

    path:setAllSpeeds(50)

    assert_eq(path:getSegmentSpeed(1), 50, "All segments should be 50")
    assert_eq(path:getSegmentSpeed(2), 50, "All segments should be 50")
    assert_eq(path:getSegmentSpeed(3), 50, "All segments should be 50")
end)

test("getSegmentDuration calculates time correctly", "Segment Speeds", function()
    local path = PathFollowerCore.new({ defaultSpeed = 10 })
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(20, 0, 0),  -- 20 studs at 10 speed = 2 seconds
    })

    local duration = path:getSegmentDuration(1)

    assert_near(duration, 2, 0.001, "Duration should be 2 seconds")
end)

test("getTotalDuration sums all segment durations", "Segment Speeds", function()
    local path = PathFollowerCore.new({ defaultSpeed = 10 })
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),  -- 10 studs at 10 speed = 1 second
        Vector3.new(30, 0, 0),  -- 20 studs at 10 speed = 2 seconds
    })

    local total = path:getTotalDuration()

    assert_near(total, 3, 0.001, "Total duration should be 3 seconds")
end)

--------------------------------------------------------------------------------
-- DIRECTION & TRAVERSAL TESTS
--------------------------------------------------------------------------------

test("reverse toggles direction", "Direction", function()
    local path = PathFollowerCore.new()
    path:setWaypoints(createVector3Waypoints())

    assert_true(path:isForward(), "Should start forward")

    path:reverse()
    assert_false(path:isForward(), "Should be reverse after toggle")

    path:reverse()
    assert_true(path:isForward(), "Should be forward after second toggle")
end)

test("setDirection explicitly sets direction", "Direction", function()
    local path = PathFollowerCore.new()
    path:setWaypoints(createVector3Waypoints())

    path:setDirection(false)
    assert_false(path:isForward(), "Should be reverse")

    path:setDirection(true)
    assert_true(path:isForward(), "Should be forward")
end)

test("getTraversalDirection respects direction", "Direction", function()
    local path = PathFollowerCore.new()
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),
    })

    local forwardDir = path:getTraversalDirection(1)
    assert_near(forwardDir.X, 1, 0.001, "Forward should be +X")

    path:reverse()

    local reverseDir = path:getTraversalDirection(1)
    assert_near(reverseDir.X, -1, 0.001, "Reverse should be -X")
end)

test("reset clears current index", "Direction", function()
    local path = PathFollowerCore.new()
    path:setWaypoints(createVector3Waypoints())

    path:setCurrentIndex(3)
    assert_eq(path:getCurrentIndex(), 3, "Index should be 3")

    path:reset()
    assert_eq(path:getCurrentIndex(), 0, "Index should be 0 after reset")
end)

--------------------------------------------------------------------------------
-- POSITION QUERY TESTS
--------------------------------------------------------------------------------

test("findClosestSegment finds nearest segment", "Position Queries", function()
    local path = PathFollowerCore.new()
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),
        Vector3.new(10, 10, 0),
    })

    -- Point near first segment
    local seg1, _, dist1 = path:findClosestSegment(Vector3.new(5, 1, 0))
    assert_eq(seg1, 1, "Should find segment 1")
    assert_near(dist1, 1, 0.1, "Distance should be ~1")

    -- Point near second segment
    local seg2, _, dist2 = path:findClosestSegment(Vector3.new(11, 5, 0))
    assert_eq(seg2, 2, "Should find segment 2")
    assert_near(dist2, 1, 0.1, "Distance should be ~1")
end)

test("getProgressOnSegment returns 0-1 progress", "Position Queries", function()
    local path = PathFollowerCore.new()
    path:setWaypoints({
        Vector3.new(0, 0, 0),
        Vector3.new(10, 0, 0),
    })

    local progressStart = path:getProgressOnSegment(Vector3.new(0, 0, 0), 1)
    local progressMid = path:getProgressOnSegment(Vector3.new(5, 0, 0), 1)
    local progressEnd = path:getProgressOnSegment(Vector3.new(10, 0, 0), 1)

    assert_near(progressStart, 0, 0.01, "Start should be 0")
    assert_near(progressMid, 0.5, 0.01, "Middle should be 0.5")
    assert_near(progressEnd, 1, 0.01, "End should be 1")
end)

--------------------------------------------------------------------------------
-- PATHEDCONVEYOR COMPONENT TESTS
--------------------------------------------------------------------------------

test("PathedConveyor.extend creates component class", "PathedConveyor", function()
    assert_not_nil(PathedConveyor, "PathedConveyor should be defined")
    assert_eq(PathedConveyor.name, "PathedConveyor", "Name should be 'PathedConveyor'")
    assert_eq(PathedConveyor.domain, "server", "Domain should be 'server'")
end)

test("PathedConveyor instance initializes with defaults", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_1" })
    conveyor.Sys.onInit(conveyor)

    assert_eq(conveyor:getAttribute("Speed"), 16, "Default speed should be 16")
    assert_eq(conveyor:getAttribute("ForceMode"), "velocity", "Default ForceMode should be 'velocity'")
    assert_eq(conveyor:getAttribute("AffectsPlayers"), true, "Default AffectsPlayers should be true")
    assert_not_nil(conveyor._path, "Should have _path instance")
end)

test("PathedConveyor.In.onConfigure sets waypoints", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_2" })
    conveyor.Sys.onInit(conveyor)

    conveyor.In.onConfigure(conveyor, {
        waypoints = createVector3Waypoints(),
    })

    assert_eq(conveyor._path:getWaypointCount(), 4, "Should have 4 waypoints")
end)

test("PathedConveyor.In.onConfigure sets speed", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_3" })
    conveyor.Sys.onInit(conveyor)

    conveyor.In.onConfigure(conveyor, {
        waypoints = createVector3Waypoints(),
        speed = 25,
    })

    assert_eq(conveyor:getAttribute("Speed"), 25, "Speed should be 25")
    assert_eq(conveyor._path:getDefaultSpeed(), 25, "Path default speed should be 25")
end)

test("PathedConveyor.In.onSetSpeed sets segment speeds", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_4" })
    conveyor.Sys.onInit(conveyor)

    conveyor.In.onConfigure(conveyor, {
        waypoints = createVector3Waypoints(),
    })

    conveyor.In.onSetSpeed(conveyor, {
        segments = {
            { segment = 1, speed = 10 },
            { segment = 2, speed = 30 },
        }
    })

    assert_eq(conveyor._path:getSegmentSpeed(1), 10, "Segment 1 should be 10")
    assert_eq(conveyor._path:getSegmentSpeed(2), 30, "Segment 2 should be 30")
end)

test("PathedConveyor.In.onReverse toggles direction", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_5" })
    conveyor.Sys.onInit(conveyor)

    conveyor.In.onConfigure(conveyor, {
        waypoints = createVector3Waypoints(),
    })

    local directionChangedFired = false
    conveyor.Out = {
        Fire = function(self, signal, data)
            if signal == "directionChanged" then
                directionChangedFired = true
                assert_false(data.forward, "Should be reverse")
            end
        end,
    }

    assert_true(conveyor._path:isForward(), "Should start forward")

    conveyor.In.onReverse(conveyor)

    assert_false(conveyor._path:isForward(), "Should be reverse after toggle")
    assert_true(directionChangedFired, "Should fire directionChanged")
end)

test("PathedConveyor.In.onEnable fails without waypoints", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_6" })
    conveyor.Sys.onInit(conveyor)

    local errFired = false
    conveyor.Err = {
        Fire = function(self, data)
            errFired = true
            assert_eq(data.reason, "no_path", "Should error with 'no_path'")
        end,
    }

    conveyor.In.onEnable(conveyor)

    assert_true(errFired, "Should fire error")
    assert_false(conveyor._enabled, "Should not be enabled")
end)

test("PathedConveyor.In.onEnable succeeds with waypoints", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_7" })
    conveyor.Sys.onInit(conveyor)

    conveyor.In.onConfigure(conveyor, {
        waypoints = createVector3Waypoints(),
    })

    conveyor.In.onEnable(conveyor)

    assert_true(conveyor._enabled, "Should be enabled")
    assert_not_nil(conveyor._updateConnection, "Should have update connection")

    -- Cleanup
    conveyor.In.onDisable(conveyor)
end)

test("PathedConveyor.In.onDisable stops conveyor", "PathedConveyor", function()
    local conveyor = PathedConveyor:new({ id = "TestConveyor_8" })
    conveyor.Sys.onInit(conveyor)

    conveyor.In.onConfigure(conveyor, {
        waypoints = createVector3Waypoints(),
    })

    conveyor.In.onEnable(conveyor)
    assert_true(conveyor._enabled, "Should be enabled")

    conveyor.In.onDisable(conveyor)

    assert_false(conveyor._enabled, "Should be disabled")
    assert_nil(conveyor._updateConnection, "Update connection should be nil")
end)

--------------------------------------------------------------------------------
-- VISUAL DEMO
--------------------------------------------------------------------------------

--[[
    Run a visual demonstration of PathedConveyor with Droppers.
    Creates a conveyor track loop with droppers that spawn objects onto it.

    Usage:
        local Tests = require(game.ReplicatedStorage.Warren.Tests)
        Tests.PathedConveyor.demo()       -- Run the demo
        Tests.PathedConveyor.cleanup()    -- Clean up when done
--]]

local demoInstances = {}
local demoConveyor = nil
local demoDroppers = {}

function Tests.demo()
    print("\n========================================")
    print("  PathedConveyor Visual Demo")
    print("========================================")
    print("Creating conveyor track with droppers...\n")

    -- Cleanup any previous demo
    Tests.cleanup()

    local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
    local Dropper = Lib.Components.Dropper
    local SpawnerCore = require(ReplicatedStorage.Warren.Internal.SpawnerCore)

    -- Reset SpawnerCore
    SpawnerCore.reset()

    ----------------------------------------------------------------------------
    -- CREATE TEMPLATES
    ----------------------------------------------------------------------------

    local templates = Instance.new("Folder")
    templates.Name = "DemoTemplates"
    templates.Parent = ReplicatedStorage
    table.insert(demoInstances, templates)

    -- Crate template (box that rides the conveyor)
    local crate = Instance.new("Part")
    crate.Name = "Crate"
    crate.Size = Vector3.new(3, 3, 3)
    crate.BrickColor = BrickColor.new("Bright orange")
    crate.Material = Enum.Material.Wood
    crate.Anchored = false
    crate.CanCollide = true
    crate.Parent = templates

    -- Ball template
    local ball = Instance.new("Part")
    ball.Name = "Ball"
    ball.Shape = Enum.PartType.Ball
    ball.Size = Vector3.new(2, 2, 2)
    ball.BrickColor = BrickColor.new("Bright blue")
    ball.Material = Enum.Material.SmoothPlastic
    ball.Anchored = false
    ball.CanCollide = true
    ball.Parent = templates

    -- Barrel template
    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Shape = Enum.PartType.Cylinder
    barrel.Size = Vector3.new(3, 2, 2)
    barrel.BrickColor = BrickColor.new("Reddish brown")
    barrel.Material = Enum.Material.Wood
    barrel.Anchored = false
    barrel.CanCollide = true
    barrel.Parent = templates

    SpawnerCore.init({ templates = templates })

    ----------------------------------------------------------------------------
    -- CREATE CONVEYOR TRACK (rectangular loop)
    ----------------------------------------------------------------------------

    -- Track dimensions
    local trackWidth = 8
    local trackLength = 80
    local trackHeight = 3
    local cornerRadius = 10

    -- Create waypoints in a loop
    local waypoints = {}
    local waypointParts = {}

    -- Define loop path (rectangle corners)
    local pathPoints = {
        Vector3.new(0, trackHeight, 0),
        Vector3.new(trackLength, trackHeight, 0),
        Vector3.new(trackLength, trackHeight, trackLength/2),
        Vector3.new(0, trackHeight, trackLength/2),
    }

    -- Create waypoint parts at each corner
    for i, pos in ipairs(pathPoints) do
        -- Waypoint marker (small, semi-transparent)
        local wp = Instance.new("Part")
        wp.Name = "Waypoint_" .. i
        wp.Size = Vector3.new(2, 2, 2)
        wp.Position = pos
        wp.Anchored = true
        wp.Transparency = 0.5
        wp.BrickColor = BrickColor.new("Bright yellow")
        wp.CanCollide = false
        wp.Parent = workspace
        table.insert(waypoints, wp)
        table.insert(waypointParts, wp)
        table.insert(demoInstances, wp)
    end

    -- Add first waypoint again to close the loop for the conveyor path
    table.insert(waypoints, waypointParts[1])

    -- Create belt surface segments between waypoints
    for i = 1, #pathPoints do
        local startPos = pathPoints[i]
        local endPos = pathPoints[(i % #pathPoints) + 1]

        local midPoint = (startPos + endPos) / 2
        local direction = (endPos - startPos).Unit
        local length = (endPos - startPos).Magnitude

        if length > 0 then
            -- Calculate proper CFrame: position at midpoint, oriented along direction
            -- rightVector = direction, upVector = world up, lookVector = perpendicular
            local upVector = Vector3.new(0, 1, 0)
            local rightVector = direction
            local lookVector = upVector:Cross(rightVector).Unit

            -- Handle case where direction is vertical
            if lookVector.Magnitude < 0.1 then
                lookVector = Vector3.new(0, 0, 1)
            end

            local beltCFrame = CFrame.fromMatrix(
                midPoint - Vector3.new(0, 0.25, 0),  -- Position slightly below waypoint height
                rightVector,
                upVector,
                -lookVector
            )

            local belt = Instance.new("Part")
            belt.Name = "Belt_" .. i
            belt.Size = Vector3.new(length + 1, 0.5, trackWidth)  -- +1 to overlap at corners
            belt.CFrame = beltCFrame
            belt.Anchored = true
            belt.BrickColor = BrickColor.new("Dark stone grey")
            belt.Material = Enum.Material.DiamondPlate
            belt.Parent = workspace
            table.insert(demoInstances, belt)

            -- Add side rails
            for side = -1, 1, 2 do
                local railCFrame = CFrame.fromMatrix(
                    midPoint + Vector3.new(0, 0.25, 0) + lookVector * side * (trackWidth/2 + 0.25),
                    rightVector,
                    upVector,
                    -lookVector
                )

                local rail = Instance.new("Part")
                rail.Name = "Rail_" .. i .. "_" .. side
                rail.Size = Vector3.new(length + 1, 1, 0.5)
                rail.CFrame = railCFrame
                rail.Anchored = true
                rail.BrickColor = BrickColor.new("Black")
                rail.Material = Enum.Material.Metal
                rail.Parent = workspace
                table.insert(demoInstances, rail)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- CREATE PATHEDCONVEYOR
    ----------------------------------------------------------------------------

    demoConveyor = PathedConveyor:new({ id = "DemoConveyor" })
    demoConveyor.Sys.onInit(demoConveyor)

    -- Configure conveyor
    demoConveyor.In.onConfigure(demoConveyor, {
        waypoints = waypoints,
        speed = 12,
        detectionRadius = trackWidth / 2 + 1,  -- Cover the belt width
        affectsPlayers = true,
        forceMode = "velocity",
        updateRate = 0.05,  -- Smooth updates
    })

    -- Set varying speeds per segment
    demoConveyor.In.onSetSpeed(demoConveyor, {
        segments = {
            { segment = 1, speed = 15 },  -- Fast straightaway
            { segment = 2, speed = 8 },   -- Slow turn
            { segment = 3, speed = 15 },  -- Fast return
            { segment = 4, speed = 8 },   -- Slow turn
        }
    })

    -- Wire output signals
    demoConveyor.Out = {
        Fire = function(self, signal, data)
            if signal == "entityEntered" then
                print(string.format("  [Conveyor] Entity entered: %s (segment %d)",
                    data.entityId or "unknown", data.segment or 0))
            elseif signal == "entityExited" then
                print(string.format("  [Conveyor] Entity exited: %s",
                    data.entityId or "unknown"))
            elseif signal == "segmentChanged" then
                print(string.format("  [Conveyor] %s passed waypoint %d (segment %d -> %d)",
                    data.entityId or "unknown",
                    data.waypointIndex or 0,
                    data.fromSegment or 0,
                    data.toSegment or 0))
            end
        end,
    }

    -- Enable conveyor
    demoConveyor.In.onEnable(demoConveyor)
    print("  ✓ Conveyor enabled (speed varies by segment: 15/8/15/8)")

    ----------------------------------------------------------------------------
    -- CREATE DROPPERS ABOVE THE TRACK
    ----------------------------------------------------------------------------

    -- Position droppers above the belt segments (using pathPoints for reference)
    -- Segment 1: (0,0,0) to (80,0,0) - first straightaway
    -- Segment 2: (80,0,0) to (80,0,40) - right side
    -- Segment 3: (80,0,40) to (0,0,40) - return straightaway
    -- Segment 4: (0,0,40) to (0,0,0) - left side
    local dropperConfigs = {
        -- Above segment 1 (first straightaway)
        { pos = Vector3.new(20, trackHeight + 10, 0), template = "Crate", interval = 3 },
        { pos = Vector3.new(50, trackHeight + 10, 0), template = "Ball", interval = 2 },
        -- Above segment 3 (return straightaway)
        { pos = Vector3.new(60, trackHeight + 10, trackLength/2), template = "Barrel", interval = 4 },
        { pos = Vector3.new(25, trackHeight + 10, trackLength/2), template = "Crate", interval = 3.5 },
    }

    for i, config in ipairs(dropperConfigs) do
        -- Create dropper visual (hopper)
        local hopper = Instance.new("Part")
        hopper.Name = "Hopper_" .. i
        hopper.Size = Vector3.new(4, 2, 4)
        hopper.Position = config.pos + Vector3.new(0, 1, 0)
        hopper.Anchored = true
        hopper.BrickColor = BrickColor.new("Medium stone grey")
        hopper.Material = Enum.Material.Metal
        hopper.Parent = workspace
        table.insert(demoInstances, hopper)

        -- Create dropper node
        local dropper = Dropper:new({ id = "DemoDropper_" .. i })
        dropper.Sys.onInit(dropper)

        dropper.In.onConfigure(dropper, {
            templateName = config.template,
            interval = config.interval,
            maxActive = 5,
            spawnPosition = config.pos,
        })

        -- Wire output
        local dropperIndex = i  -- Capture for closure
        dropper.Out = {
            Fire = function(self, signal, data)
                if signal == "spawned" then
                    print(string.format("  [Dropper %d] Spawned %s at %s",
                        dropperIndex, data.templateName,
                        tostring(data.instance and data.instance.Position or "?")))

                    -- Make sure spawned item is not anchored so conveyor can move it
                    if data.instance then
                        if data.instance:IsA("BasePart") then
                            data.instance.Anchored = false
                            data.instance.CanCollide = true
                            print(string.format("    -> Anchored: %s, CanCollide: %s",
                                tostring(data.instance.Anchored),
                                tostring(data.instance.CanCollide)))
                        elseif data.instance:IsA("Model") then
                            for _, part in ipairs(data.instance:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.Anchored = false
                                    part.CanCollide = true
                                end
                            end
                        end
                        table.insert(demoInstances, data.instance)
                    end
                end
            end,
        }

        -- Start the dropper
        dropper.In.onStart(dropper)
        table.insert(demoDroppers, dropper)

        print(string.format("  ✓ Dropper %d: %s every %.1fs", i, config.template, config.interval))
    end

    ----------------------------------------------------------------------------
    -- SPAWN PLATFORM FOR PLAYER
    ----------------------------------------------------------------------------

    local platform = Instance.new("Part")
    platform.Name = "PlayerPlatform"
    platform.Size = Vector3.new(10, 1, 10)
    platform.Position = Vector3.new(-15, trackHeight - 0.5, trackLength/4)
    platform.Anchored = true
    platform.BrickColor = BrickColor.new("Bright green")
    platform.Material = Enum.Material.Grass
    platform.Parent = workspace
    table.insert(demoInstances, platform)

    -- Sign
    local sign = Instance.new("Part")
    sign.Name = "Sign"
    sign.Size = Vector3.new(8, 4, 0.5)
    sign.Position = Vector3.new(-15, trackHeight + 4, trackLength/4 - 5)
    sign.Anchored = true
    sign.BrickColor = BrickColor.new("White")
    sign.Parent = workspace
    table.insert(demoInstances, sign)

    local signGui = Instance.new("SurfaceGui")
    signGui.Face = Enum.NormalId.Front
    signGui.Parent = sign

    local signText = Instance.new("TextLabel")
    signText.Size = UDim2.new(1, 0, 1, 0)
    signText.BackgroundTransparency = 1
    signText.Text = "Step onto the\nconveyor belt!"
    signText.TextScaled = true
    signText.Font = Enum.Font.GothamBold
    signText.TextColor3 = Color3.new(0, 0, 0)
    signText.Parent = signGui

    print("\n========================================")
    print("  Demo Running!")
    print("========================================")
    print("• Stand on the grey conveyor belt to be carried")
    print("• Watch crates, balls, and barrels drop and ride along")
    print("• Segments have different speeds (fast straights, slow turns)")
    print("")
    print("Run Tests.PathedConveyor.cleanup() to stop")
    print("Run Tests.PathedConveyor.reverse() to reverse direction")
    print("========================================\n")
end

function Tests.reverse()
    if demoConveyor then
        demoConveyor.In.onReverse(demoConveyor)
        print("  ✓ Conveyor direction reversed!")
    else
        print("  ✗ No demo running. Run Tests.PathedConveyor.demo() first.")
    end
end

function Tests.cleanup()
    print("Cleaning up demo...")

    -- Stop droppers
    for _, dropper in ipairs(demoDroppers) do
        dropper.In.onStop(dropper)
    end
    demoDroppers = {}

    -- Disable conveyor
    if demoConveyor then
        demoConveyor.In.onDisable(demoConveyor)
        demoConveyor = nil
    end

    -- Destroy all demo instances
    for _, instance in ipairs(demoInstances) do
        if instance and instance.Parent then
            instance:Destroy()
        end
    end
    demoInstances = {}

    -- Reset SpawnerCore
    local SpawnerCore = require(ReplicatedStorage.Warren.Internal.SpawnerCore)
    SpawnerCore.cleanup()
    SpawnerCore.reset()

    print("  ✓ Cleanup complete.")
end

return Tests
