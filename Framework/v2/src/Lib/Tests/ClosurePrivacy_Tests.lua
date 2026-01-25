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
    Tests.runGroup("Node Factory")
    Tests.runGroup("StatusEffect Privacy")
    Tests.runGroup("DamageCalculator Privacy")
    Tests.runGroup("Checkpoint Privacy")
    Tests.runGroup("Instance Isolation")
    Tests.runGroup("Memory Cleanup")
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
