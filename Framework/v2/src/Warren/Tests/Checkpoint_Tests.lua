--[[
    Warren Framework v2
    Checkpoint Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.Checkpoint.runAll()
    Tests.Checkpoint.demo()     -- Visual demo with conveyor
    Tests.Checkpoint.cleanup()  -- Clean up demo
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local Checkpoint = Lib.Components.Checkpoint

--------------------------------------------------------------------------------
-- TEST HARNESS
--------------------------------------------------------------------------------

local Tests = {}
local testCases = {}
local testGroups = {}

local stats = {
    passed = 0,
    failed = 0,
}

local function resetStats()
    stats.passed = 0
    stats.failed = 0
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
    print("  Checkpoint Tests")
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

function Tests.list()
    print("\nAvailable test groups:")
    for group, tests in pairs(testGroups) do
        print(string.format("  %s (%d tests)", group, #tests))
    end
end

--------------------------------------------------------------------------------
-- TEST HELPERS
--------------------------------------------------------------------------------

local function createTestPart(name, size, position)
    local part = Instance.new("Part")
    part.Name = name or "TestPart"
    part.Size = size or Vector3.new(4, 4, 4)
    part.Position = position or Vector3.new(0, 10, 0)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.5
    part.Parent = workspace
    return part
end

local function cleanupPart(part)
    if part and part.Parent then
        part:Destroy()
    end
end

--------------------------------------------------------------------------------
-- UNIT TESTS
--------------------------------------------------------------------------------

test("Checkpoint.extend creates component class", "Checkpoint", function()
    assert_not_nil(Checkpoint, "Checkpoint should be defined")
    assert_eq(Checkpoint.name, "Checkpoint", "Name should be 'Checkpoint'")
    assert_eq(Checkpoint.domain, "server", "Domain should be 'server'")
end)

test("Checkpoint instance initializes with defaults", "Checkpoint", function()
    local part = createTestPart("CheckpointTest1")
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_1", model = part })
    checkpoint.Sys.onInit(checkpoint)

    assert_eq(checkpoint:getAttribute("ActiveFace"), "Front", "Default ActiveFace should be 'Front'")
    assert_eq(checkpoint:getAttribute("Cooldown"), 0.5, "Default Cooldown should be 0.5")
    assert_not_nil(checkpoint._part, "Should have _part reference")

    cleanupPart(part)
end)

test("Checkpoint.In.onConfigure sets active face", "Checkpoint", function()
    local part = createTestPart("CheckpointTest2")
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_2", model = part })
    checkpoint.Sys.onInit(checkpoint)

    checkpoint.In.onConfigure(checkpoint, {
        activeFace = "Back",
        cooldown = 1.0,
    })

    assert_eq(checkpoint._activeFace, "Back", "ActiveFace should be 'Back'")
    assert_eq(checkpoint._cooldown, 1.0, "Cooldown should be 1.0")
    assert_eq(checkpoint:getAttribute("ActiveFace"), "Back", "Attribute should be updated")

    cleanupPart(part)
end)

test("Checkpoint.In.onConfigure accepts filter", "Checkpoint", function()
    local part = createTestPart("CheckpointTest3")
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_3", model = part })
    checkpoint.Sys.onInit(checkpoint)

    checkpoint.In.onConfigure(checkpoint, {
        filter = { spawnSource = "TestDropper" },
    })

    assert_not_nil(checkpoint._filter, "Should have filter")
    assert_eq(checkpoint._filter.spawnSource, "TestDropper", "Filter should have spawnSource")

    cleanupPart(part)
end)

test("Checkpoint.In.onEnable fails without part", "Checkpoint", function()
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_4" })
    checkpoint.Sys.onInit(checkpoint)

    local errFired = false
    checkpoint.Err = {
        Fire = function(self, data)
            errFired = true
            assert_eq(data.reason, "no_part", "Should error with 'no_part'")
        end,
    }

    checkpoint.In.onEnable(checkpoint)

    assert_true(errFired, "Should fire error")
    assert_eq(checkpoint._enabled, false, "Should not be enabled")
end)

test("Checkpoint.In.onEnable succeeds with part", "Checkpoint", function()
    local part = createTestPart("CheckpointTest5")
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_5", model = part })
    checkpoint.Sys.onInit(checkpoint)

    checkpoint.In.onEnable(checkpoint)

    assert_true(checkpoint._enabled, "Should be enabled")
    assert_not_nil(checkpoint._updateConnection, "Should have update connection")

    checkpoint.In.onDisable(checkpoint)
    cleanupPart(part)
end)

test("Checkpoint.In.onDisable stops detection", "Checkpoint", function()
    local part = createTestPart("CheckpointTest6")
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_6", model = part })
    checkpoint.Sys.onInit(checkpoint)

    checkpoint.In.onEnable(checkpoint)
    assert_true(checkpoint._enabled, "Should be enabled")

    checkpoint.In.onDisable(checkpoint)
    assert_eq(checkpoint._enabled, false, "Should be disabled")
    assert_eq(checkpoint._updateConnection, nil, "Connection should be nil")

    cleanupPart(part)
end)

test("Checkpoint rejects invalid active face", "Checkpoint", function()
    local part = createTestPart("CheckpointTest7")
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_7", model = part })
    checkpoint.Sys.onInit(checkpoint)

    checkpoint.In.onConfigure(checkpoint, {
        activeFace = "InvalidFace",
    })

    -- Should keep default since invalid
    assert_eq(checkpoint._activeFace, "Front", "Should keep default 'Front' for invalid face")

    cleanupPart(part)
end)

test("Checkpoint accepts all valid face names", "Face Detection", function()
    local part = createTestPart("CheckpointTest8")
    local checkpoint = Checkpoint:new({ id = "TestCheckpoint_8", model = part })
    checkpoint.Sys.onInit(checkpoint)

    local validFaces = { "Front", "Back", "Left", "Right", "Top", "Bottom" }

    for _, face in ipairs(validFaces) do
        checkpoint.In.onConfigure(checkpoint, { activeFace = face })
        assert_eq(checkpoint._activeFace, face, "Should accept face: " .. face)
    end

    cleanupPart(part)
end)

--------------------------------------------------------------------------------
-- VISUAL DEMO
--------------------------------------------------------------------------------

local demoInstances = {}
local demoCheckpoints = {}

function Tests.demo()
    print("\n========================================")
    print("  Checkpoint Visual Demo")
    print("========================================")
    print("Creating checkpoints along a path...\n")

    Tests.cleanup()

    local PathedConveyor = Lib.Components.PathedConveyor
    local Dropper = Lib.Components.Dropper
    local SpawnerCore = require(ReplicatedStorage.Warren.Internal.SpawnerCore)

    SpawnerCore.reset()

    -- Create templates
    local templates = Instance.new("Folder")
    templates.Name = "CheckpointDemoTemplates"
    templates.Parent = ReplicatedStorage
    table.insert(demoInstances, templates)

    local crate = Instance.new("Part")
    crate.Name = "DemoCrate"
    crate.Size = Vector3.new(2, 2, 2)
    crate.BrickColor = BrickColor.new("Bright blue")
    crate.Material = Enum.Material.SmoothPlastic
    crate.Anchored = false
    crate.CanCollide = true
    crate.Parent = templates

    SpawnerCore.init({ templates = templates })

    -- Create a straight conveyor path with checkpoints at each end
    local trackHeight = 5
    local trackLength = 60

    -- Waypoints
    local wp1 = Instance.new("Part")
    wp1.Name = "WP1"
    wp1.Size = Vector3.new(2, 2, 2)
    wp1.Position = Vector3.new(0, trackHeight, 0)
    wp1.Anchored = true
    wp1.Transparency = 0.5
    wp1.BrickColor = BrickColor.new("Bright yellow")
    wp1.CanCollide = false
    wp1.Parent = workspace
    table.insert(demoInstances, wp1)

    local wp2 = Instance.new("Part")
    wp2.Name = "WP2"
    wp2.Size = Vector3.new(2, 2, 2)
    wp2.Position = Vector3.new(trackLength, trackHeight, 0)
    wp2.Anchored = true
    wp2.Transparency = 0.5
    wp2.BrickColor = BrickColor.new("Bright yellow")
    wp2.CanCollide = false
    wp2.Parent = workspace
    table.insert(demoInstances, wp2)

    -- Belt surface
    local belt = Instance.new("Part")
    belt.Name = "BeltSurface"
    belt.Size = Vector3.new(trackLength, 0.5, 6)
    belt.Position = Vector3.new(trackLength / 2, trackHeight - 0.5, 0)
    belt.Anchored = true
    belt.BrickColor = BrickColor.new("Dark stone grey")
    belt.Material = Enum.Material.DiamondPlate
    belt.Parent = workspace
    table.insert(demoInstances, belt)

    -- Create checkpoints at strategic points
    local checkpointPositions = {
        { pos = Vector3.new(15, trackHeight + 1, 0), name = "Checkpoint_A", face = "Left" },
        { pos = Vector3.new(30, trackHeight + 1, 0), name = "Checkpoint_B", face = "Left" },
        { pos = Vector3.new(45, trackHeight + 1, 0), name = "Checkpoint_C", face = "Left" },
    }

    for i, config in ipairs(checkpointPositions) do
        -- Visual checkpoint box (gate-like frame)
        local cpPart = Instance.new("Part")
        cpPart.Name = config.name
        cpPart.Size = Vector3.new(2, 6, 8)  -- Thin gate across the path
        cpPart.Position = config.pos
        cpPart.Anchored = true
        cpPart.CanCollide = false
        cpPart.Transparency = 0.5
        cpPart.BrickColor = BrickColor.new("Bright green")
        cpPart.Material = Enum.Material.Neon
        cpPart.Parent = workspace
        table.insert(demoInstances, cpPart)

        -- Add arrow showing active face direction
        local arrow = Instance.new("Part")
        arrow.Name = config.name .. "_Arrow"
        arrow.Size = Vector3.new(3, 0.5, 1)
        arrow.CFrame = CFrame.new(config.pos + Vector3.new(-3, 2, 0))  -- Point into the checkpoint
        arrow.Anchored = true
        arrow.CanCollide = false
        arrow.Transparency = 0.3
        arrow.BrickColor = BrickColor.new("Lime green")
        arrow.Material = Enum.Material.Neon
        arrow.Parent = workspace
        table.insert(demoInstances, arrow)

        -- Arrowhead
        local arrowHead = Instance.new("WedgePart")
        arrowHead.Name = config.name .. "_ArrowHead"
        arrowHead.Size = Vector3.new(0.5, 1.5, 1.5)
        arrowHead.CFrame = CFrame.new(config.pos + Vector3.new(-1, 2, 0)) * CFrame.Angles(0, 0, math.rad(-90))
        arrowHead.Anchored = true
        arrowHead.CanCollide = false
        arrowHead.Transparency = 0.3
        arrowHead.BrickColor = BrickColor.new("Lime green")
        arrowHead.Material = Enum.Material.Neon
        arrowHead.Parent = workspace
        table.insert(demoInstances, arrowHead)

        -- Label
        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 120, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = cpPart

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = config.name .. "\n[" .. config.face .. "]"
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard

        -- Create Checkpoint component
        local checkpoint = Checkpoint:new({ id = config.name, model = cpPart })
        checkpoint.Sys.onInit(checkpoint)

        checkpoint.In.onConfigure(checkpoint, {
            activeFace = config.face,
            cooldown = 0.5,
        })

        -- Wire output with visual feedback
        local cpIndex = i
        checkpoint.Out = {
            Fire = function(self, signal, data)
                if signal == "crossed" then
                    local activeMarker = data.isActiveFace and " [ACTIVE FACE]" or ""
                    print(string.format("  [%s] Entity crossed: %s, face=%s%s",
                        config.name, data.entityId, data.face, activeMarker))

                    -- Visual feedback: flash the entire checkpoint gate
                    task.spawn(function()
                        local flashColor = data.isActiveFace
                            and BrickColor.new("Lime green")
                            or BrickColor.new("Bright orange")

                        local originalGateColor = cpPart.BrickColor
                        local originalGateTransparency = cpPart.Transparency
                        local originalArrowColor = arrow.BrickColor
                        local originalArrowTransparency = arrow.Transparency
                        local originalHeadColor = arrowHead.BrickColor
                        local originalHeadTransparency = arrowHead.Transparency

                        -- Flash bright
                        cpPart.BrickColor = flashColor
                        cpPart.Transparency = 0.2
                        arrow.BrickColor = flashColor
                        arrow.Transparency = 0
                        arrowHead.BrickColor = flashColor
                        arrowHead.Transparency = 0

                        task.wait(0.1)
                        cpPart.Transparency = 0.4
                        task.wait(0.1)
                        cpPart.Transparency = 0.2
                        task.wait(0.1)

                        -- Restore
                        cpPart.BrickColor = originalGateColor
                        cpPart.Transparency = originalGateTransparency
                        arrow.BrickColor = originalArrowColor
                        arrow.Transparency = originalArrowTransparency
                        arrowHead.BrickColor = originalHeadColor
                        arrowHead.Transparency = originalHeadTransparency
                    end)
                end
            end,
        }

        checkpoint.In.onEnable(checkpoint)
        table.insert(demoCheckpoints, checkpoint)

        print(string.format("  ✓ %s created (active face: %s)", config.name, config.face))
    end

    -- Create conveyor
    local conveyor = PathedConveyor:new({ id = "DemoConveyor" })
    conveyor.Sys.onInit(conveyor)

    conveyor.In.onConfigure(conveyor, {
        waypoints = { wp1, wp2 },
        speed = 12,
        detectionRadius = 4,
        affectsPlayers = true,
    })

    conveyor.Out = {
        Fire = function(self, signal, data)
            -- Suppress conveyor output for cleaner demo
        end,
    }

    conveyor.In.onEnable(conveyor)
    table.insert(demoCheckpoints, conveyor)

    -- Create dropper
    local dropper = Dropper:new({ id = "DemoDropper" })
    dropper.Sys.onInit(dropper)

    dropper.In.onConfigure(dropper, {
        templateName = "DemoCrate",
        interval = 3,
        maxActive = 10,
        spawnPosition = Vector3.new(-5, trackHeight + 5, 0),
    })

    dropper.Out = {
        Fire = function(self, signal, data)
            if signal == "spawned" then
                print(string.format("  [Dropper] Spawned: %s", data.entityId))
                if data.instance and data.instance:IsA("BasePart") then
                    data.instance.Anchored = false
                    data.instance.CanCollide = true
                    table.insert(demoInstances, data.instance)
                end
            end
        end,
    }

    dropper.In.onStart(dropper)
    table.insert(demoCheckpoints, dropper)

    print("\n========================================")
    print("  Demo Running!")
    print("========================================")
    print("• Crates spawn and ride the conveyor")
    print("• Watch checkpoints fire as crates pass")
    print("• Each checkpoint reports which face was crossed")
    print("")
    print("Run Tests.Checkpoint.cleanup() to stop")
    print("========================================\n")
end

function Tests.cleanup()
    print("Cleaning up Checkpoint demo...")

    for _, component in ipairs(demoCheckpoints) do
        if component.In and component.In.onDisable then
            component.In.onDisable(component)
        end
        if component.In and component.In.onStop then
            component.In.onStop(component)
        end
    end
    demoCheckpoints = {}

    for _, instance in ipairs(demoInstances) do
        if instance and instance.Parent then
            instance:Destroy()
        end
    end
    demoInstances = {}

    local SpawnerCore = require(ReplicatedStorage.Warren.Internal.SpawnerCore)
    SpawnerCore.cleanup()
    SpawnerCore.reset()

    print("  ✓ Cleanup complete.")
end

return Tests
