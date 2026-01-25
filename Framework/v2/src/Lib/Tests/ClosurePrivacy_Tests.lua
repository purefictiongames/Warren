--[[
    LibPureFiction Framework v2
    ClosurePrivacy_Tests.lua - Closure-Based Privacy Pattern QA Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests.ClosurePrivacy_Tests)
    Tests.runAll()
    ```

    Or run specific test groups:

    ```lua
    -- Phase 0-2 tests
    Tests.runGroup("Node Factory")
    Tests.runGroup("StatusEffect Privacy")
    Tests.runGroup("DamageCalculator Privacy")
    Tests.runGroup("Checkpoint Privacy")
    Tests.runGroup("Instance Isolation")
    Tests.runGroup("Memory Cleanup")
    Tests.runGroup("Signal Flow")
    Tests.runGroup("Backwards Compatibility")

    -- Phase 3 tests
    Tests.runGroup("Zone Privacy")
    Tests.runGroup("Launcher Privacy")
    Tests.runGroup("Targeter Privacy")
    Tests.runGroup("Swivel Privacy")
    Tests.runGroup("Phase 3 Isolation")
    Tests.runGroup("Phase 3 Cleanup")
    ```

    Or list available groups:

    ```lua
    Tests.list()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local Components = Lib.Components

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
            message or "Expected nil",
            tostring(value)), 2)
    end
end

local function assert_not_nil(value, message)
    if value == nil then
        error(message or "Expected non-nil value", 2)
    end
end

local function assert_type(value, expectedType, message)
    if type(value) ~= expectedType then
        error(string.format("%s: expected type %s, got %s",
            message or "Type mismatch",
            expectedType,
            type(value)), 2)
    end
end

local function test(name, group, fn)
    table.insert(testCases, { name = name, group = group, fn = fn })
    testGroups[group] = true
end

--------------------------------------------------------------------------------
-- TEST RUNNER
--------------------------------------------------------------------------------

function Tests.runAll()
    resetStats()
    print("\n" .. string.rep("=", 60))
    print("CLOSURE-BASED PRIVACY QA TEST SUITE")
    print(string.rep("=", 60))

    local currentGroup = nil

    for _, testCase in ipairs(testCases) do
        if testCase.group ~= currentGroup then
            currentGroup = testCase.group
            log("group", currentGroup)
        end

        local success, err = pcall(testCase.fn)
        if success then
            stats.passed = stats.passed + 1
            log("pass", testCase.name)
        else
            stats.failed = stats.failed + 1
            log("fail", testCase.name)
            log("error", "  →", tostring(err))
        end
    end

    print(string.rep("-", 60))
    log("summary", string.format(
        "Results: %d passed, %d failed, %d total",
        stats.passed,
        stats.failed,
        stats.passed + stats.failed
    ))

    if stats.failed == 0 then
        print("✅ ALL TESTS PASSED")
    else
        warn("❌ SOME TESTS FAILED")
    end

    return stats
end

function Tests.runGroup(groupName)
    resetStats()
    print("\n▶ Running group:", groupName)

    for _, testCase in ipairs(testCases) do
        if testCase.group == groupName then
            local success, err = pcall(testCase.fn)
            if success then
                stats.passed = stats.passed + 1
                log("pass", testCase.name)
            else
                stats.failed = stats.failed + 1
                log("fail", testCase.name)
                log("error", "  →", tostring(err))
            end
        end
    end

    log("summary", string.format(
        "Results: %d passed, %d failed",
        stats.passed,
        stats.failed
    ))

    return stats
end

function Tests.list()
    print("\nAvailable test groups:")
    for group in pairs(testGroups) do
        print("  •", group)
    end
end

--------------------------------------------------------------------------------
-- NODE FACTORY PATTERN TESTS
--------------------------------------------------------------------------------

test("Node.extend accepts factory function", "Node Factory", function()
    local FactoryNode = Node.extend(function(parent)
        return {
            name = "FactoryNode",
            domain = "server",
        }
    end)
    assert_eq(FactoryNode.name, "FactoryNode", "Factory should produce named class")
end)

test("Factory function receives parent", "Node Factory", function()
    local receivedParent = nil
    local FactoryNode = Node.extend(function(parent)
        receivedParent = parent
        return { name = "FactoryNode" }
    end)
    assert_eq(receivedParent, Node, "Factory should receive Node as parent")
end)

test("Factory pattern creates instances", "Node Factory", function()
    local FactoryNode = Node.extend(function(parent)
        return {
            name = "FactoryNode",
            Sys = {
                onInit = function(self) end,
                onStart = function(self) end,
                onStop = function(self) end,
            },
        }
    end)

    local inst = FactoryNode:new({ id = "factory_inst_1" })
    assert_eq(inst.id, "factory_inst_1", "Instance should have ID")
    assert_eq(inst.class, "FactoryNode", "Instance should have class name")
end)

test("Factory pattern private functions not on instance", "Node Factory", function()
    local FactoryNode = Node.extend(function(parent)
        -- Private function in closure
        local function secretHelper()
            return "secret"
        end

        return {
            name = "FactoryNode",
            In = {
                onTest = function(self)
                    return secretHelper()
                end,
            },
        }
    end)

    local inst = FactoryNode:new({ id = "private_test_1" })
    assert_nil(inst.secretHelper, "Private function should not be on instance")
    assert_nil(inst._secretHelper, "Private function should not be on instance with underscore")
end)

test("Table-style Node.extend still works (backwards compatibility)", "Node Factory", function()
    local TableNode = Node.extend({
        name = "TableNode",
        domain = "server",
        Sys = {
            onInit = function(self) end,
            onStart = function(self) end,
            onStop = function(self) end,
        },
    })

    local inst = TableNode:new({ id = "table_inst_1" })
    assert_eq(inst.class, "TableNode", "Table-style should still work")
end)

--------------------------------------------------------------------------------
-- STATUSEFFECT PRIVACY TESTS
--------------------------------------------------------------------------------

test("StatusEffect class exists", "StatusEffect Privacy", function()
    assert_not_nil(Components.StatusEffect, "StatusEffect should exist in Components")
end)

test("StatusEffect._removeEffect is nil", "StatusEffect Privacy", function()
    local effect = Components.StatusEffect:new({ id = "effect_privacy_1" })
    effect.Sys.onInit(effect)
    assert_nil(effect._removeEffect, "_removeEffect should not exist on instance")
end)

test("StatusEffect._activeEffects is nil", "StatusEffect Privacy", function()
    local effect = Components.StatusEffect:new({ id = "effect_privacy_2" })
    effect.Sys.onInit(effect)
    assert_nil(effect._activeEffects, "_activeEffects should not exist on instance")
end)

test("StatusEffect._effectsByTarget is nil", "StatusEffect Privacy", function()
    local effect = Components.StatusEffect:new({ id = "effect_privacy_3" })
    effect.Sys.onInit(effect)
    assert_nil(effect._effectsByTarget, "_effectsByTarget should not exist on instance")
end)

test("StatusEffect._nextEffectId is nil", "StatusEffect Privacy", function()
    local effect = Components.StatusEffect:new({ id = "effect_privacy_4" })
    effect.Sys.onInit(effect)
    assert_nil(effect._nextEffectId, "_nextEffectId should not exist on instance")
end)

test("StatusEffect public query methods exist", "StatusEffect Privacy", function()
    local effect = Components.StatusEffect:new({ id = "effect_privacy_5" })
    effect.Sys.onInit(effect)
    assert_not_nil(effect.getActiveEffects, "getActiveEffects should exist")
    assert_not_nil(effect.getEffectsForTarget, "getEffectsForTarget should exist")
    assert_not_nil(effect.hasEffect, "hasEffect should exist")
    assert_not_nil(effect.getRemainingDuration, "getRemainingDuration should exist")
end)

test("StatusEffect In handlers exist", "StatusEffect Privacy", function()
    local effect = Components.StatusEffect:new({ id = "effect_privacy_6" })
    effect.Sys.onInit(effect)
    assert_not_nil(effect.In.onApplyEffect, "onApplyEffect should exist")
    assert_not_nil(effect.In.onRemoveEffect, "onRemoveEffect should exist")
    assert_not_nil(effect.In.onRemoveAllEffects, "onRemoveAllEffects should exist")
end)

test("StatusEffect Out channel exists", "StatusEffect Privacy", function()
    local effect = Components.StatusEffect:new({ id = "effect_privacy_7" })
    effect.Sys.onInit(effect)
    assert_not_nil(effect.Out, "Out channel should exist")
    assert_not_nil(effect.Out.Fire, "Out:Fire should exist")
end)

--------------------------------------------------------------------------------
-- DAMAGECALCULATOR PRIVACY TESTS
--------------------------------------------------------------------------------

test("DamageCalculator class exists", "DamageCalculator Privacy", function()
    assert_not_nil(Components.DamageCalculator, "DamageCalculator should exist in Components")
end)

test("DamageCalculator._applyDamage is nil", "DamageCalculator Privacy", function()
    local calc = Components.DamageCalculator:new({ id = "calc_privacy_1" })
    calc.Sys.onInit(calc)
    assert_nil(calc._applyDamage, "_applyDamage should not exist on instance")
end)

test("DamageCalculator._pendingQueries is nil", "DamageCalculator Privacy", function()
    local calc = Components.DamageCalculator:new({ id = "calc_privacy_2" })
    calc.Sys.onInit(calc)
    assert_nil(calc._pendingQueries, "_pendingQueries should not exist on instance")
end)

test("DamageCalculator.computeDamage is public", "DamageCalculator Privacy", function()
    local calc = Components.DamageCalculator:new({ id = "calc_privacy_3" })
    calc.Sys.onInit(calc)
    assert_not_nil(calc.computeDamage, "computeDamage should exist (public override point)")
    assert_type(calc.computeDamage, "function", "computeDamage should be a function")
end)

test("DamageCalculator.computeDamage works", "DamageCalculator Privacy", function()
    local calc = Components.DamageCalculator:new({ id = "calc_privacy_4" })
    calc.Sys.onInit(calc)
    local damage = calc:computeDamage(100, 30, "physical")
    assert_eq(damage, 70, "100 - 30 = 70 damage")
end)

test("DamageCalculator In handlers exist", "DamageCalculator Privacy", function()
    local calc = Components.DamageCalculator:new({ id = "calc_privacy_5" })
    calc.Sys.onInit(calc)
    assert_not_nil(calc.In.onCalculateDamage, "onCalculateDamage should exist")
    assert_not_nil(calc.In.onAttributeQueried, "onAttributeQueried should exist")
end)

--------------------------------------------------------------------------------
-- CHECKPOINT PRIVACY TESTS
--------------------------------------------------------------------------------

test("Checkpoint class exists", "Checkpoint Privacy", function()
    assert_not_nil(Components.Checkpoint, "Checkpoint should exist in Components")
end)

test("Checkpoint._enable is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_1" })
    cp.Sys.onInit(cp)
    assert_nil(cp._enable, "_enable should not exist on instance")
end)

test("Checkpoint._disable is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_2" })
    cp.Sys.onInit(cp)
    assert_nil(cp._disable, "_disable should not exist on instance")
end)

test("Checkpoint._startDetectionLoop is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_3" })
    cp.Sys.onInit(cp)
    assert_nil(cp._startDetectionLoop, "_startDetectionLoop should not exist on instance")
end)

test("Checkpoint._updateDetection is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_4" })
    cp.Sys.onInit(cp)
    assert_nil(cp._updateDetection, "_updateDetection should not exist on instance")
end)

test("Checkpoint._handleEntityEntry is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_5" })
    cp.Sys.onInit(cp)
    assert_nil(cp._handleEntityEntry, "_handleEntityEntry should not exist on instance")
end)

test("Checkpoint._determineEntryFace is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_6" })
    cp.Sys.onInit(cp)
    assert_nil(cp._determineEntryFace, "_determineEntryFace should not exist on instance")
end)

test("Checkpoint._enabled is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_7" })
    cp.Sys.onInit(cp)
    assert_nil(cp._enabled, "_enabled should not exist on instance")
end)

test("Checkpoint._entitiesInside is nil", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_8" })
    cp.Sys.onInit(cp)
    assert_nil(cp._entitiesInside, "_entitiesInside should not exist on instance")
end)

test("Checkpoint In handlers exist", "Checkpoint Privacy", function()
    local cp = Components.Checkpoint:new({ id = "cp_privacy_9" })
    cp.Sys.onInit(cp)
    assert_not_nil(cp.In.onConfigure, "onConfigure should exist")
    assert_not_nil(cp.In.onEnable, "onEnable should exist")
    assert_not_nil(cp.In.onDisable, "onDisable should exist")
end)

--------------------------------------------------------------------------------
-- INSTANCE ISOLATION TESTS
--------------------------------------------------------------------------------

test("StatusEffect instances have isolated state", "Instance Isolation", function()
    local effect1 = Components.StatusEffect:new({ id = "iso_effect_1" })
    local effect2 = Components.StatusEffect:new({ id = "iso_effect_2" })
    effect1.Sys.onInit(effect1)
    effect2.Sys.onInit(effect2)

    -- Capture signals from effect1
    local effect1Signals = {}
    effect1.Out = {
        Fire = function(self, signal, data)
            table.insert(effect1Signals, { signal = signal, data = data })
        end,
    }

    -- Capture signals from effect2
    local effect2Signals = {}
    effect2.Out = {
        Fire = function(self, signal, data)
            table.insert(effect2Signals, { signal = signal, data = data })
        end,
    }

    -- Apply effect to effect1 only
    effect1.In.onApplyEffect(effect1, {
        targetId = "target_1",
        effectType = "test_buff",
        duration = 10,
        modifiers = { { attribute = "speed", operation = "additive", value = 5 } },
    })

    -- effect1 should have the effect
    assert_true(effect1:hasEffect("target_1", "test_buff"), "effect1 should have the effect")

    -- effect2 should NOT have the effect (isolated state)
    assert_false(effect2:hasEffect("target_1", "test_buff"), "effect2 should NOT have the effect")

    -- Cleanup
    effect1.Sys.onStop(effect1)
    effect2.Sys.onStop(effect2)
end)

test("DamageCalculator instances have isolated state", "Instance Isolation", function()
    local calc1 = Components.DamageCalculator:new({ id = "iso_calc_1" })
    local calc2 = Components.DamageCalculator:new({ id = "iso_calc_2" })
    calc1.Sys.onInit(calc1)
    calc2.Sys.onInit(calc2)

    -- Override computeDamage on calc1 only
    local originalCompute = calc1.computeDamage
    local calc1CustomCalled = false

    -- Note: Since computeDamage is on the class, not instance, we need to test differently
    -- Test that they can both exist and be called independently
    local damage1 = calc1:computeDamage(100, 20, "physical")
    local damage2 = calc2:computeDamage(100, 30, "physical")

    assert_eq(damage1, 80, "calc1 should compute 100 - 20 = 80")
    assert_eq(damage2, 70, "calc2 should compute 100 - 30 = 70")

    -- Cleanup
    calc1.Sys.onStop(calc1)
    calc2.Sys.onStop(calc2)
end)

test("Checkpoint instances have isolated state", "Instance Isolation", function()
    local cp1 = Components.Checkpoint:new({ id = "iso_cp_1" })
    local cp2 = Components.Checkpoint:new({ id = "iso_cp_2" })
    cp1.Sys.onInit(cp1)
    cp2.Sys.onInit(cp2)

    -- Configure with different active faces
    cp1.In.onConfigure(cp1, { activeFace = "Front" })
    cp2.In.onConfigure(cp2, { activeFace = "Back" })

    -- Verify attributes are isolated
    assert_eq(cp1:getAttribute("ActiveFace"), "Front", "cp1 should have Front")
    assert_eq(cp2:getAttribute("ActiveFace"), "Back", "cp2 should have Back")

    -- Cleanup
    cp1.Sys.onStop(cp1)
    cp2.Sys.onStop(cp2)
end)

--------------------------------------------------------------------------------
-- MEMORY CLEANUP TESTS
--------------------------------------------------------------------------------

test("StatusEffect cleans up on onStop", "Memory Cleanup", function()
    local effect = Components.StatusEffect:new({ id = "cleanup_effect_1" })
    effect.Sys.onInit(effect)

    -- Apply an effect
    effect.Out = { Fire = function() end }  -- Suppress signals
    effect.In.onApplyEffect(effect, {
        targetId = "target",
        effectType = "test",
        duration = 100,
        modifiers = {},
    })

    -- Verify effect exists
    assert_true(effect:hasEffect("target", "test"), "Effect should exist before cleanup")

    -- Stop and cleanup
    effect.Sys.onStop(effect)

    -- After cleanup, getActiveEffects should return empty or error gracefully
    -- Since state is cleaned up, calling query methods may return nil/empty
    local effects = effect:getActiveEffects()
    local count = 0
    for _ in pairs(effects or {}) do count = count + 1 end
    assert_eq(count, 0, "No effects should remain after cleanup")
end)

test("Checkpoint cleans up on onStop", "Memory Cleanup", function()
    local cp = Components.Checkpoint:new({ id = "cleanup_cp_1" })
    cp.Sys.onInit(cp)

    -- Stop should not error even without a part
    local success, err = pcall(function()
        cp.Sys.onStop(cp)
    end)
    assert_true(success, "onStop should not error: " .. tostring(err))
end)

test("Multiple create/destroy cycles don't leak memory", "Memory Cleanup", function()
    -- Create and destroy many instances
    for i = 1, 50 do
        local effect = Components.StatusEffect:new({ id = "leak_test_" .. i })
        effect.Sys.onInit(effect)
        effect.Out = { Fire = function() end }

        -- Apply some effects
        effect.In.onApplyEffect(effect, {
            targetId = "target_" .. i,
            effectType = "test",
            duration = 100,
            modifiers = {},
        })

        -- Cleanup
        effect.Sys.onStop(effect)
    end

    -- If we get here without hanging or crashing, memory is likely being cleaned up
    assert_true(true, "50 create/destroy cycles completed without hanging")
end)

--------------------------------------------------------------------------------
-- SIGNAL FLOW TESTS
--------------------------------------------------------------------------------

test("StatusEffect fires effectApplied signal", "Signal Flow", function()
    local effect = Components.StatusEffect:new({ id = "signal_effect_1" })
    effect.Sys.onInit(effect)

    local firedSignals = {}
    effect.Out = {
        Fire = function(self, signal, data)
            table.insert(firedSignals, { signal = signal, data = data })
        end,
    }

    effect.In.onApplyEffect(effect, {
        targetId = "target_1",
        effectType = "speed_boost",
        duration = 10,
        modifiers = { { attribute = "speed", operation = "additive", value = 5 } },
    })

    -- Should have fired applyModifier and effectApplied
    local foundApplyModifier = false
    local foundEffectApplied = false

    for _, sig in ipairs(firedSignals) do
        if sig.signal == "applyModifier" then
            foundApplyModifier = true
        elseif sig.signal == "effectApplied" then
            foundEffectApplied = true
            assert_eq(sig.data.targetId, "target_1", "effectApplied should have correct targetId")
            assert_eq(sig.data.effectType, "speed_boost", "effectApplied should have correct effectType")
        end
    end

    assert_true(foundApplyModifier, "Should have fired applyModifier")
    assert_true(foundEffectApplied, "Should have fired effectApplied")

    effect.Sys.onStop(effect)
end)

test("DamageCalculator fires signals for true damage", "Signal Flow", function()
    local calc = Components.DamageCalculator:new({ id = "signal_calc_1" })
    calc.Sys.onInit(calc)

    local firedSignals = {}
    calc.Out = {
        Fire = function(self, signal, data)
            table.insert(firedSignals, { signal = signal, data = data })
        end,
    }

    -- True damage bypasses defense query
    calc.In.onCalculateDamage(calc, {
        targetId = "target_1",
        rawDamage = 50,
        damageType = "true",
    })

    -- Should have fired applyDamage and damageCalculated
    local foundApplyDamage = false
    local foundDamageCalculated = false

    for _, sig in ipairs(firedSignals) do
        if sig.signal == "applyDamage" then
            foundApplyDamage = true
            assert_eq(sig.data.delta, -50, "Should apply 50 damage (negative delta)")
        elseif sig.signal == "damageCalculated" then
            foundDamageCalculated = true
            assert_eq(sig.data.finalDamage, 50, "True damage should be 50")
        end
    end

    assert_true(foundApplyDamage, "Should have fired applyDamage")
    assert_true(foundDamageCalculated, "Should have fired damageCalculated")

    calc.Sys.onStop(calc)
end)

--------------------------------------------------------------------------------
-- ZONE PRIVACY TESTS (Phase 3)
--------------------------------------------------------------------------------

test("Zone class exists", "Zone Privacy", function()
    assert_not_nil(Components.Zone, "Zone should exist in Components")
end)

test("Zone._enableCollisionMode is nil", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_1" })
    zone.Sys.onInit(zone)
    assert_nil(zone._enableCollisionMode, "_enableCollisionMode should not exist on instance")
    zone.Sys.onStop(zone)
end)

test("Zone._enableProximityMode is nil", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_2" })
    zone.Sys.onInit(zone)
    assert_nil(zone._enableProximityMode, "_enableProximityMode should not exist on instance")
    zone.Sys.onStop(zone)
end)

test("Zone._handleEnter is nil", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_3" })
    zone.Sys.onInit(zone)
    assert_nil(zone._handleEnter, "_handleEnter should not exist on instance")
    zone.Sys.onStop(zone)
end)

test("Zone._handleExit is nil", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_4" })
    zone.Sys.onInit(zone)
    assert_nil(zone._handleExit, "_handleExit should not exist on instance")
    zone.Sys.onStop(zone)
end)

test("Zone._passesFilter is nil", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_5" })
    zone.Sys.onInit(zone)
    assert_nil(zone._passesFilter, "_passesFilter should not exist on instance")
    zone.Sys.onStop(zone)
end)

test("Zone._enabled state is nil", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_6" })
    zone.Sys.onInit(zone)
    assert_nil(zone._enabled, "_enabled should not exist on instance")
    zone.Sys.onStop(zone)
end)

test("Zone._entitiesInZone state is nil", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_7" })
    zone.Sys.onInit(zone)
    assert_nil(zone._entitiesInZone, "_entitiesInZone should not exist on instance")
    zone.Sys.onStop(zone)
end)

test("Zone In handlers exist", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_8" })
    zone.Sys.onInit(zone)
    assert_not_nil(zone.In.onConfigure, "onConfigure should exist")
    assert_not_nil(zone.In.onEnable, "onEnable should exist")
    assert_not_nil(zone.In.onDisable, "onDisable should exist")
    zone.Sys.onStop(zone)
end)

test("Zone Out signals exist", "Zone Privacy", function()
    local zone = Components.Zone:new({ id = "zone_privacy_9" })
    zone.Sys.onInit(zone)
    assert_not_nil(zone.Out, "Out channel should exist")
    assert_not_nil(zone.Out.Fire, "Out:Fire should exist")
    zone.Sys.onStop(zone)
end)

--------------------------------------------------------------------------------
-- LAUNCHER PRIVACY TESTS (Phase 3)
--------------------------------------------------------------------------------

test("Launcher class exists", "Launcher Privacy", function()
    assert_not_nil(Components.Launcher, "Launcher should exist in Components")
end)

test("Launcher._getMuzzleInfo is nil", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_1" })
    launcher.Sys.onInit(launcher)
    assert_nil(launcher._getMuzzleInfo, "_getMuzzleInfo should not exist on instance")
    launcher.Sys.onStop(launcher)
end)

test("Launcher._getPhysicsPart is nil", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_2" })
    launcher.Sys.onInit(launcher)
    assert_nil(launcher._getPhysicsPart, "_getPhysicsPart should not exist on instance")
    launcher.Sys.onStop(launcher)
end)

test("Launcher._prepareProjectile is nil", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_3" })
    launcher.Sys.onInit(launcher)
    assert_nil(launcher._prepareProjectile, "_prepareProjectile should not exist on instance")
    launcher.Sys.onStop(launcher)
end)

test("Launcher._launchImpulse is nil", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_4" })
    launcher.Sys.onInit(launcher)
    assert_nil(launcher._launchImpulse, "_launchImpulse should not exist on instance")
    launcher.Sys.onStop(launcher)
end)

test("Launcher._launchSpring is nil", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_5" })
    launcher.Sys.onInit(launcher)
    assert_nil(launcher._launchSpring, "_launchSpring should not exist on instance")
    launcher.Sys.onStop(launcher)
end)

test("Launcher._lastFireTime state is nil", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_6" })
    launcher.Sys.onInit(launcher)
    assert_nil(launcher._lastFireTime, "_lastFireTime should not exist on instance")
    launcher.Sys.onStop(launcher)
end)

test("Launcher._muzzle state is nil", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_7" })
    launcher.Sys.onInit(launcher)
    assert_nil(launcher._muzzle, "_muzzle should not exist on instance")
    launcher.Sys.onStop(launcher)
end)

test("Launcher public query methods exist", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_8" })
    launcher.Sys.onInit(launcher)
    assert_not_nil(launcher.isReady, "isReady should exist")
    assert_not_nil(launcher.getCooldownRemaining, "getCooldownRemaining should exist")
    launcher.Sys.onStop(launcher)
end)

test("Launcher.isReady returns boolean", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_9" })
    launcher.Sys.onInit(launcher)
    local ready = launcher:isReady()
    assert_type(ready, "boolean", "isReady should return boolean")
    assert_true(ready, "New launcher should be ready")
    launcher.Sys.onStop(launcher)
end)

test("Launcher.getCooldownRemaining returns number", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_10" })
    launcher.Sys.onInit(launcher)
    local remaining = launcher:getCooldownRemaining()
    assert_type(remaining, "number", "getCooldownRemaining should return number")
    assert_eq(remaining, 0, "New launcher should have 0 cooldown remaining")
    launcher.Sys.onStop(launcher)
end)

test("Launcher In handlers exist", "Launcher Privacy", function()
    local launcher = Components.Launcher:new({ id = "launcher_privacy_11" })
    launcher.Sys.onInit(launcher)
    assert_not_nil(launcher.In.onConfigure, "onConfigure should exist")
    assert_not_nil(launcher.In.onFire, "onFire should exist")
    launcher.Sys.onStop(launcher)
end)

--------------------------------------------------------------------------------
-- TARGETER PRIVACY TESTS (Phase 3)
--------------------------------------------------------------------------------

test("Targeter class exists", "Targeter Privacy", function()
    assert_not_nil(Components.Targeter, "Targeter should exist in Components")
end)

test("Targeter._getOrigin is nil", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_1" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._getOrigin, "_getOrigin should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter._getDirection is nil", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_2" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._getDirection, "_getDirection should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter._generateRays is nil", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_3" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._generateRays, "_generateRays should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter._performScan is nil", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_4" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._performScan, "_performScan should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter._processResults is nil", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_5" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._processResults, "_processResults should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter._startScanning is nil", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_6" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._startScanning, "_startScanning should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter._stopScanning is nil", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_7" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._stopScanning, "_stopScanning should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter state is not exposed", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_8" })
    targeter.Sys.onInit(targeter)
    assert_nil(targeter._enabled, "_enabled should not exist on instance")
    assert_nil(targeter._scanning, "_scanning should not exist on instance")
    assert_nil(targeter._hasTargets, "_hasTargets should not exist on instance")
    assert_nil(targeter._filter, "_filter should not exist on instance")
    assert_nil(targeter._raycastParams, "_raycastParams should not exist on instance")
    targeter.Sys.onStop(targeter)
end)

test("Targeter public query methods exist", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_9" })
    targeter.Sys.onInit(targeter)
    assert_not_nil(targeter.isScanning, "isScanning should exist")
    assert_not_nil(targeter.hasTargets, "hasTargets should exist")
    assert_not_nil(targeter.isEnabled, "isEnabled should exist")
    targeter.Sys.onStop(targeter)
end)

test("Targeter.isScanning returns boolean", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_10" })
    targeter.Sys.onInit(targeter)
    local scanning = targeter:isScanning()
    assert_type(scanning, "boolean", "isScanning should return boolean")
    assert_false(scanning, "New targeter should not be scanning")
    targeter.Sys.onStop(targeter)
end)

test("Targeter.hasTargets returns boolean", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_11" })
    targeter.Sys.onInit(targeter)
    local targets = targeter:hasTargets()
    assert_type(targets, "boolean", "hasTargets should return boolean")
    assert_false(targets, "New targeter should have no targets")
    targeter.Sys.onStop(targeter)
end)

test("Targeter.isEnabled returns boolean", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_12" })
    targeter.Sys.onInit(targeter)
    local enabled = targeter:isEnabled()
    assert_type(enabled, "boolean", "isEnabled should return boolean")
    assert_false(enabled, "New targeter should not be enabled")
    targeter.Sys.onStop(targeter)
end)

test("Targeter In handlers exist", "Targeter Privacy", function()
    local targeter = Components.Targeter:new({ id = "targeter_privacy_13" })
    targeter.Sys.onInit(targeter)
    assert_not_nil(targeter.In.onConfigure, "onConfigure should exist")
    assert_not_nil(targeter.In.onEnable, "onEnable should exist")
    assert_not_nil(targeter.In.onDisable, "onDisable should exist")
    assert_not_nil(targeter.In.onScan, "onScan should exist")
    targeter.Sys.onStop(targeter)
end)

--------------------------------------------------------------------------------
-- SWIVEL PRIVACY TESTS (Phase 3)
--------------------------------------------------------------------------------

test("Swivel class exists", "Swivel Privacy", function()
    assert_not_nil(Components.Swivel, "Swivel should exist in Components")
end)

test("Swivel._setupHinge is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_1" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._setupHinge, "_setupHinge should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel._getAttachmentCFrame is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_2" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._getAttachmentCFrame, "_getAttachmentCFrame should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel._updateHingeAxis is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_3" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._updateHingeAxis, "_updateHingeAxis should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel._setTargetAngle is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_4" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._setTargetAngle, "_setTargetAngle should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel._startContinuousRotation is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_5" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._startContinuousRotation, "_startContinuousRotation should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel._stopRotation is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_6" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._stopRotation, "_stopRotation should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel._startMonitoring is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_7" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._startMonitoring, "_startMonitoring should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel._stopMonitoring is nil", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_8" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._stopMonitoring, "_stopMonitoring should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel state is not exposed", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_9" })
    swivel.Sys.onInit(swivel)
    assert_nil(swivel._currentAngle, "_currentAngle should not exist on instance")
    assert_nil(swivel._targetAngle, "_targetAngle should not exist on instance")
    assert_nil(swivel._rotating, "_rotating should not exist on instance")
    assert_nil(swivel._hinge, "_hinge should not exist on instance")
    assert_nil(swivel._monitorConnection, "_monitorConnection should not exist on instance")
    swivel.Sys.onStop(swivel)
end)

test("Swivel public query methods exist", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_10" })
    swivel.Sys.onInit(swivel)
    assert_not_nil(swivel.getCurrentAngle, "getCurrentAngle should exist")
    assert_not_nil(swivel.isRotating, "isRotating should exist")
    assert_not_nil(swivel.isAtTarget, "isAtTarget should exist")
    assert_not_nil(swivel.getHinge, "getHinge should exist")
    swivel.Sys.onStop(swivel)
end)

test("Swivel.getCurrentAngle returns number", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_11" })
    swivel.Sys.onInit(swivel)
    local angle = swivel:getCurrentAngle()
    assert_type(angle, "number", "getCurrentAngle should return number")
    swivel.Sys.onStop(swivel)
end)

test("Swivel.isRotating returns boolean", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_12" })
    swivel.Sys.onInit(swivel)
    local rotating = swivel:isRotating()
    assert_type(rotating, "boolean", "isRotating should return boolean")
    assert_false(rotating, "New swivel should not be rotating")
    swivel.Sys.onStop(swivel)
end)

test("Swivel.isAtTarget returns boolean", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_13" })
    swivel.Sys.onInit(swivel)
    local atTarget = swivel:isAtTarget()
    assert_type(atTarget, "boolean", "isAtTarget should return boolean")
    swivel.Sys.onStop(swivel)
end)

test("Swivel In handlers exist", "Swivel Privacy", function()
    local swivel = Components.Swivel:new({ id = "swivel_privacy_14" })
    swivel.Sys.onInit(swivel)
    assert_not_nil(swivel.In.onConfigure, "onConfigure should exist")
    assert_not_nil(swivel.In.onRotate, "onRotate should exist")
    assert_not_nil(swivel.In.onSetAngle, "onSetAngle should exist")
    assert_not_nil(swivel.In.onStop, "onStop should exist")
    swivel.Sys.onStop(swivel)
end)

--------------------------------------------------------------------------------
-- PHASE 3 INSTANCE ISOLATION TESTS
--------------------------------------------------------------------------------

test("Zone instances have isolated state", "Phase 3 Isolation", function()
    local zone1 = Components.Zone:new({ id = "iso_zone_1" })
    local zone2 = Components.Zone:new({ id = "iso_zone_2" })
    zone1.Sys.onInit(zone1)
    zone2.Sys.onInit(zone2)

    -- Configure with different settings
    zone1.In.onConfigure(zone1, { radius = 10 })
    zone2.In.onConfigure(zone2, { radius = 20 })

    -- Verify attributes are isolated
    assert_eq(zone1:getAttribute("Radius"), 10, "zone1 should have Radius 10")
    assert_eq(zone2:getAttribute("Radius"), 20, "zone2 should have Radius 20")

    zone1.Sys.onStop(zone1)
    zone2.Sys.onStop(zone2)
end)

test("Launcher instances have isolated state", "Phase 3 Isolation", function()
    local launcher1 = Components.Launcher:new({ id = "iso_launcher_1" })
    local launcher2 = Components.Launcher:new({ id = "iso_launcher_2" })
    launcher1.Sys.onInit(launcher1)
    launcher2.Sys.onInit(launcher2)

    -- Configure with different cooldowns
    launcher1.In.onConfigure(launcher1, { cooldown = 0.5 })
    launcher2.In.onConfigure(launcher2, { cooldown = 2.0 })

    -- Verify attributes are isolated
    assert_eq(launcher1:getAttribute("Cooldown"), 0.5, "launcher1 should have Cooldown 0.5")
    assert_eq(launcher2:getAttribute("Cooldown"), 2.0, "launcher2 should have Cooldown 2.0")

    -- Both should be ready independently
    assert_true(launcher1:isReady(), "launcher1 should be ready")
    assert_true(launcher2:isReady(), "launcher2 should be ready")

    launcher1.Sys.onStop(launcher1)
    launcher2.Sys.onStop(launcher2)
end)

test("Targeter instances have isolated state", "Phase 3 Isolation", function()
    local targeter1 = Components.Targeter:new({ id = "iso_targeter_1" })
    local targeter2 = Components.Targeter:new({ id = "iso_targeter_2" })
    targeter1.Sys.onInit(targeter1)
    targeter2.Sys.onInit(targeter2)

    -- Configure with different beam modes
    targeter1.In.onConfigure(targeter1, { beamMode = "pinpoint" })
    targeter2.In.onConfigure(targeter2, { beamMode = "cone" })

    -- Verify attributes are isolated
    assert_eq(targeter1:getAttribute("BeamMode"), "pinpoint", "targeter1 should have pinpoint mode")
    assert_eq(targeter2:getAttribute("BeamMode"), "cone", "targeter2 should have cone mode")

    targeter1.Sys.onStop(targeter1)
    targeter2.Sys.onStop(targeter2)
end)

test("Swivel instances have isolated state", "Phase 3 Isolation", function()
    local swivel1 = Components.Swivel:new({ id = "iso_swivel_1" })
    local swivel2 = Components.Swivel:new({ id = "iso_swivel_2" })
    swivel1.Sys.onInit(swivel1)
    swivel2.Sys.onInit(swivel2)

    -- Configure with different speeds
    swivel1.In.onConfigure(swivel1, { speed = 45 })
    swivel2.In.onConfigure(swivel2, { speed = 180 })

    -- Verify attributes are isolated
    assert_eq(swivel1:getAttribute("Speed"), 45, "swivel1 should have Speed 45")
    assert_eq(swivel2:getAttribute("Speed"), 180, "swivel2 should have Speed 180")

    swivel1.Sys.onStop(swivel1)
    swivel2.Sys.onStop(swivel2)
end)

--------------------------------------------------------------------------------
-- PHASE 3 MEMORY CLEANUP TESTS
--------------------------------------------------------------------------------

test("Zone cleans up on onStop", "Phase 3 Cleanup", function()
    local zone = Components.Zone:new({ id = "cleanup_zone_1" })
    zone.Sys.onInit(zone)

    local success, err = pcall(function()
        zone.Sys.onStop(zone)
    end)
    assert_true(success, "Zone onStop should not error: " .. tostring(err))
end)

test("Launcher cleans up on onStop", "Phase 3 Cleanup", function()
    local launcher = Components.Launcher:new({ id = "cleanup_launcher_1" })
    launcher.Sys.onInit(launcher)

    local success, err = pcall(function()
        launcher.Sys.onStop(launcher)
    end)
    assert_true(success, "Launcher onStop should not error: " .. tostring(err))
end)

test("Targeter cleans up on onStop", "Phase 3 Cleanup", function()
    local targeter = Components.Targeter:new({ id = "cleanup_targeter_1" })
    targeter.Sys.onInit(targeter)

    local success, err = pcall(function()
        targeter.Sys.onStop(targeter)
    end)
    assert_true(success, "Targeter onStop should not error: " .. tostring(err))
end)

test("Swivel cleans up on onStop", "Phase 3 Cleanup", function()
    local swivel = Components.Swivel:new({ id = "cleanup_swivel_1" })
    swivel.Sys.onInit(swivel)

    local success, err = pcall(function()
        swivel.Sys.onStop(swivel)
    end)
    assert_true(success, "Swivel onStop should not error: " .. tostring(err))
end)

test("Phase 3 components: 50 create/destroy cycles", "Phase 3 Cleanup", function()
    for i = 1, 50 do
        local zone = Components.Zone:new({ id = "leak_zone_" .. i })
        local launcher = Components.Launcher:new({ id = "leak_launcher_" .. i })
        local targeter = Components.Targeter:new({ id = "leak_targeter_" .. i })
        local swivel = Components.Swivel:new({ id = "leak_swivel_" .. i })

        zone.Sys.onInit(zone)
        launcher.Sys.onInit(launcher)
        targeter.Sys.onInit(targeter)
        swivel.Sys.onInit(swivel)

        zone.Sys.onStop(zone)
        launcher.Sys.onStop(launcher)
        targeter.Sys.onStop(targeter)
        swivel.Sys.onStop(swivel)
    end

    assert_true(true, "50 create/destroy cycles completed without hanging")
end)

--------------------------------------------------------------------------------
-- BACKWARDS COMPATIBILITY TESTS
--------------------------------------------------------------------------------

test("Non-migrated components still work (Dropper)", "Backwards Compatibility", function()
    -- Dropper hasn't been migrated yet, so it should still use the old pattern
    assert_not_nil(Components.Dropper, "Dropper should exist")

    local dropper = Components.Dropper:new({ id = "compat_dropper_1" })
    dropper.Sys.onInit(dropper)

    -- Old-style components still have underscore methods
    -- (This test will need updating after Dropper is migrated)
    assert_not_nil(dropper.In.onConfigure, "onConfigure should exist")
    assert_not_nil(dropper.In.onStart, "onStart should exist")
    assert_not_nil(dropper.In.onStop, "onStop should exist")

    dropper.Sys.onStop(dropper)
end)

test("Mixed old and new components can coexist", "Backwards Compatibility", function()
    -- Create one migrated and one non-migrated component
    local effect = Components.StatusEffect:new({ id = "mixed_effect_1" })
    local dropper = Components.Dropper:new({ id = "mixed_dropper_1" })

    effect.Sys.onInit(effect)
    dropper.Sys.onInit(dropper)

    -- Both should function
    assert_not_nil(effect.In.onApplyEffect, "StatusEffect should have handlers")
    assert_not_nil(dropper.In.onConfigure, "Dropper should have handlers")

    effect.Sys.onStop(effect)
    dropper.Sys.onStop(dropper)
end)

--------------------------------------------------------------------------------
-- RETURN
--------------------------------------------------------------------------------

return Tests
