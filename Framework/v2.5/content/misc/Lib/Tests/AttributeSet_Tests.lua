--[[
    LibPureFiction Framework v2
    AttributeSet Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.AttributeSet.runAll()
    ```

    Or run specific test groups:

    ```lua
    Tests.AttributeSet.runGroup("Base Values")
    Tests.AttributeSet.runGroup("Modifiers")
    Tests.AttributeSet.runGroup("Derived Values")
    Tests.AttributeSet.runGroup("Subscriptions")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local AttributeSet = require(ReplicatedStorage.Lib.Internal.AttributeSet)

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

local function assert_approx(actual, expected, tolerance, message)
    tolerance = tolerance or 0.001
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
    print("  AttributeSet Test Suite")
    print("========================================")

    local currentGroup = nil
    for _, testCase in ipairs(testCases) do
        if testCase.group ~= currentGroup then
            currentGroup = testCase.group
            log("group", currentGroup)
        end
        runTest(testCase)
    end

    print("\n----------------------------------------")
    log("summary", string.format(
        "Results: %d passed, %d failed",
        stats.passed, stats.failed
    ))
    print("----------------------------------------")

    return stats
end

function Tests.runGroup(groupName)
    resetStats()
    print("\n========================================")
    print("  AttributeSet Tests:", groupName)
    print("========================================")

    for _, testCase in ipairs(testCases) do
        if testCase.group == groupName then
            runTest(testCase)
        end
    end

    print("\n----------------------------------------")
    log("summary", string.format(
        "Results: %d passed, %d failed",
        stats.passed, stats.failed
    ))
    print("----------------------------------------")

    return stats
end

--------------------------------------------------------------------------------
-- TEST CASES: BASE VALUES
--------------------------------------------------------------------------------

test("Creates attribute set with schema", "Base Values", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
        mana = { type = "number", default = 50 },
    })

    assert_not_nil(attrs, "Should create attribute set")
    assert_eq(attrs:get("health"), 100, "Health should be 100")
    assert_eq(attrs:get("mana"), 50, "Mana should be 50")
end)

test("getBase returns base value", "Base Values", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    assert_eq(attrs:getBase("health"), 100, "Base health should be 100")
end)

test("setBase updates value and triggers recompute", "Base Values", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    attrs:setBase("health", 75)
    assert_eq(attrs:get("health"), 75, "Health should be 75")
    assert_eq(attrs:getBase("health"), 75, "Base health should be 75")
end)

test("Respects min constraint", "Base Values", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100, min = 0 },
    })

    attrs:setBase("health", -50)
    assert_eq(attrs:get("health"), 0, "Health should be clamped to 0")
end)

test("Respects max constraint", "Base Values", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100, max = 100 },
    })

    attrs:setBase("health", 150)
    assert_eq(attrs:get("health"), 100, "Health should be clamped to 100")
end)

test("getAll returns all values", "Base Values", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
        mana = { type = "number", default = 50 },
    })

    local all = attrs:getAll()
    assert_eq(all.health, 100, "Health should be 100")
    assert_eq(all.mana, 50, "Mana should be 50")
end)

--------------------------------------------------------------------------------
-- TEST CASES: MODIFIERS
--------------------------------------------------------------------------------

test("Applies additive modifier", "Modifiers", function()
    local attrs = AttributeSet.new({
        defense = { type = "number", default = 10 },
    })

    local modId = attrs:applyModifier("defense", {
        operation = "additive",
        value = 5,
        source = "armor",
    })

    assert_not_nil(modId, "Should return modifier ID")
    assert_eq(attrs:get("defense"), 15, "Defense should be 10 + 5 = 15")
end)

test("Applies multiplicative modifier", "Modifiers", function()
    local attrs = AttributeSet.new({
        damage = { type = "number", default = 100 },
    })

    attrs:applyModifier("damage", {
        operation = "multiplicative",
        value = 1.5,
        source = "buff",
    })

    assert_eq(attrs:get("damage"), 150, "Damage should be 100 * 1.5 = 150")
end)

test("Applies override modifier", "Modifiers", function()
    local attrs = AttributeSet.new({
        speed = { type = "number", default = 16 },
    })

    attrs:applyModifier("speed", {
        operation = "override",
        value = 0,
        source = "stun",
    })

    assert_eq(attrs:get("speed"), 0, "Speed should be overridden to 0")
end)

test("Stacks multiple additive modifiers", "Modifiers", function()
    local attrs = AttributeSet.new({
        defense = { type = "number", default = 10 },
    })

    attrs:applyModifier("defense", { operation = "additive", value = 5, source = "armor" })
    attrs:applyModifier("defense", { operation = "additive", value = 3, source = "shield" })
    attrs:applyModifier("defense", { operation = "additive", value = 2, source = "ring" })

    assert_eq(attrs:get("defense"), 20, "Defense should be 10 + 5 + 3 + 2 = 20")
end)

test("Stacks multiple modifiers from same source", "Modifiers", function()
    local attrs = AttributeSet.new({
        defense = { type = "number", default = 10 },
    })

    attrs:applyModifier("defense", { operation = "additive", value = 5, source = "armor" })
    attrs:applyModifier("defense", { operation = "additive", value = 5, source = "armor" })

    assert_eq(attrs:get("defense"), 20, "Defense should be 10 + 5 + 5 = 20")
end)

test("Combines additive then multiplicative", "Modifiers", function()
    local attrs = AttributeSet.new({
        damage = { type = "number", default = 100 },
    })

    attrs:applyModifier("damage", { operation = "additive", value = 50, source = "weapon" })
    attrs:applyModifier("damage", { operation = "multiplicative", value = 2, source = "crit" })

    -- (100 + 50) * 2 = 300
    assert_eq(attrs:get("damage"), 300, "Damage should be (100 + 50) * 2 = 300")
end)

test("Override takes precedence over other modifiers", "Modifiers", function()
    local attrs = AttributeSet.new({
        speed = { type = "number", default = 16 },
    })

    attrs:applyModifier("speed", { operation = "additive", value = 10, source = "boots" })
    attrs:applyModifier("speed", { operation = "override", value = 0, source = "freeze" })

    assert_eq(attrs:get("speed"), 0, "Override should take precedence")
end)

test("Removes modifier by ID", "Modifiers", function()
    local attrs = AttributeSet.new({
        defense = { type = "number", default = 10 },
    })

    local modId = attrs:applyModifier("defense", {
        operation = "additive",
        value = 5,
        source = "armor",
    })

    assert_eq(attrs:get("defense"), 15, "Should have modifier applied")

    local success = attrs:removeModifier(modId)
    assert_true(success, "Should remove successfully")
    assert_eq(attrs:get("defense"), 10, "Defense should return to base")
end)

test("Removes modifiers by source", "Modifiers", function()
    local attrs = AttributeSet.new({
        defense = { type = "number", default = 10 },
    })

    attrs:applyModifier("defense", { operation = "additive", value = 5, source = "armor" })
    attrs:applyModifier("defense", { operation = "additive", value = 3, source = "armor" })
    attrs:applyModifier("defense", { operation = "additive", value = 2, source = "ring" })

    local removed = attrs:removeModifiersFromSource("armor")
    assert_eq(removed, 2, "Should remove 2 modifiers")
    assert_eq(attrs:get("defense"), 12, "Defense should be 10 + 2 = 12")
end)

test("getModifiersBySource returns correct IDs", "Modifiers", function()
    local attrs = AttributeSet.new({
        defense = { type = "number", default = 10 },
    })

    attrs:applyModifier("defense", { operation = "additive", value = 5, source = "armor" })
    attrs:applyModifier("defense", { operation = "additive", value = 3, source = "armor" })
    attrs:applyModifier("defense", { operation = "additive", value = 2, source = "ring" })

    local armorMods = attrs:getModifiersBySource("armor")
    assert_eq(#armorMods, 2, "Should have 2 armor modifiers")

    local ringMods = attrs:getModifiersBySource("ring")
    assert_eq(#ringMods, 1, "Should have 1 ring modifier")
end)

--------------------------------------------------------------------------------
-- TEST CASES: DERIVED VALUES
--------------------------------------------------------------------------------

test("Computes derived value from dependencies", "Derived Values", function()
    local attrs = AttributeSet.new({
        baseAttack = { type = "number", default = 10 },
        weaponDamage = { type = "number", default = 5 },
        totalAttack = {
            type = "number",
            derived = true,
            dependencies = { "baseAttack", "weaponDamage" },
            compute = function(values, mods)
                return values.baseAttack + values.weaponDamage
            end,
        },
    })

    assert_eq(attrs:get("totalAttack"), 15, "Total attack should be 10 + 5 = 15")
end)

test("Recomputes derived value when dependency changes", "Derived Values", function()
    local attrs = AttributeSet.new({
        baseAttack = { type = "number", default = 10 },
        totalAttack = {
            type = "number",
            derived = true,
            dependencies = { "baseAttack" },
            compute = function(values, mods)
                return values.baseAttack * 2
            end,
        },
    })

    assert_eq(attrs:get("totalAttack"), 20, "Initial total should be 20")

    attrs:setBase("baseAttack", 25)
    assert_eq(attrs:get("totalAttack"), 50, "Total should update to 50")
end)

test("Derived value receives modifiers in compute", "Derived Values", function()
    local attrs = AttributeSet.new({
        baseDefense = { type = "number", default = 10 },
        effectiveDefense = {
            type = "number",
            derived = true,
            dependencies = { "baseDefense" },
            compute = function(values, mods)
                local base = values.baseDefense
                local add = mods.additive or 0
                local mult = mods.multiplicative or 1
                return (base + add) * mult
            end,
        },
    })

    attrs:applyModifier("effectiveDefense", {
        operation = "additive",
        value = 5,
        source = "armor",
    })

    -- (10 + 5) * 1 = 15
    assert_eq(attrs:get("effectiveDefense"), 15, "Should include additive modifier")

    attrs:applyModifier("effectiveDefense", {
        operation = "multiplicative",
        value = 2,
        source = "buff",
    })

    -- (10 + 5) * 2 = 30
    assert_eq(attrs:get("effectiveDefense"), 30, "Should include multiplicative modifier")
end)

test("Cascaded derived values update in order", "Derived Values", function()
    local attrs = AttributeSet.new({
        base = { type = "number", default = 10 },
        level1 = {
            type = "number",
            derived = true,
            dependencies = { "base" },
            compute = function(v, m)
                return v.base * 2
            end,
        },
        level2 = {
            type = "number",
            derived = true,
            dependencies = { "level1" },
            compute = function(v, m)
                return v.level1 + 5
            end,
        },
    })

    assert_eq(attrs:get("base"), 10, "Base should be 10")
    assert_eq(attrs:get("level1"), 20, "Level1 should be 20")
    assert_eq(attrs:get("level2"), 25, "Level2 should be 25")

    attrs:setBase("base", 20)
    assert_eq(attrs:get("level1"), 40, "Level1 should update to 40")
    assert_eq(attrs:get("level2"), 45, "Level2 should update to 45")
end)

test("Cannot setBase on derived attribute", "Derived Values", function()
    local attrs = AttributeSet.new({
        base = { type = "number", default = 10 },
        derived = {
            type = "number",
            derived = true,
            dependencies = { "base" },
            compute = function(v, m) return v.base * 2 end,
        },
    })

    attrs:setBase("derived", 999)
    assert_eq(attrs:get("derived"), 20, "Derived value should remain computed")
end)

--------------------------------------------------------------------------------
-- TEST CASES: SUBSCRIPTIONS
--------------------------------------------------------------------------------

test("Subscribe fires on value change", "Subscriptions", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    local fired = false
    local receivedNew, receivedOld, receivedName

    attrs:subscribe("health", function(new, old, name)
        fired = true
        receivedNew = new
        receivedOld = old
        receivedName = name
    end)

    attrs:setBase("health", 75)
    task.wait(0.01)  -- Allow task.spawn to execute

    assert_true(fired, "Subscription should fire")
    assert_eq(receivedNew, 75, "New value should be 75")
    assert_eq(receivedOld, 100, "Old value should be 100")
    assert_eq(receivedName, "health", "Attribute name should be 'health'")
end)

test("Subscribe does not fire when value unchanged", "Subscriptions", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    local fireCount = 0
    attrs:subscribe("health", function()
        fireCount = fireCount + 1
    end)

    attrs:setBase("health", 100)  -- Same value
    task.wait(0.01)

    assert_eq(fireCount, 0, "Should not fire when value unchanged")
end)

test("subscribeAll fires for any change", "Subscriptions", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
        mana = { type = "number", default = 50 },
    })

    local changes = {}
    attrs:subscribeAll(function(name, new, old)
        table.insert(changes, { name = name, new = new, old = old })
    end)

    attrs:setBase("health", 75)
    attrs:setBase("mana", 30)
    task.wait(0.01)

    assert_eq(#changes, 2, "Should record 2 changes")
    assert_eq(changes[1].name, "health", "First change should be health")
    assert_eq(changes[2].name, "mana", "Second change should be mana")
end)

test("Unsubscribe stops notifications", "Subscriptions", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    local fireCount = 0
    local unsub = attrs:subscribe("health", function()
        fireCount = fireCount + 1
    end)

    attrs:setBase("health", 75)
    task.wait(0.01)
    assert_eq(fireCount, 1, "Should fire once")

    unsub()

    attrs:setBase("health", 50)
    task.wait(0.01)
    assert_eq(fireCount, 1, "Should not fire after unsubscribe")
end)

test("Subscribe fires for modifier changes", "Subscriptions", function()
    local attrs = AttributeSet.new({
        defense = { type = "number", default = 10 },
    })

    local changes = {}
    attrs:subscribe("defense", function(new, old)
        table.insert(changes, { new = new, old = old })
    end)

    local modId = attrs:applyModifier("defense", {
        operation = "additive",
        value = 5,
        source = "armor",
    })
    task.wait(0.01)

    assert_eq(#changes, 1, "Should fire on modifier apply")
    assert_eq(changes[1].new, 15, "New value should be 15")

    attrs:removeModifier(modId)
    task.wait(0.01)

    assert_eq(#changes, 2, "Should fire on modifier remove")
    assert_eq(changes[2].new, 10, "Value should return to 10")
end)

test("Subscribe fires for derived value changes", "Subscriptions", function()
    local attrs = AttributeSet.new({
        base = { type = "number", default = 10 },
        derived = {
            type = "number",
            derived = true,
            dependencies = { "base" },
            compute = function(v, m) return v.base * 2 end,
        },
    })

    local derivedChanges = {}
    attrs:subscribe("derived", function(new, old)
        table.insert(derivedChanges, { new = new, old = old })
    end)

    attrs:setBase("base", 20)
    task.wait(0.01)

    assert_eq(#derivedChanges, 1, "Should fire for derived change")
    assert_eq(derivedChanges[1].old, 20, "Old derived should be 20")
    assert_eq(derivedChanges[1].new, 40, "New derived should be 40")
end)

--------------------------------------------------------------------------------
-- TEST CASES: REPLICATION
--------------------------------------------------------------------------------

test("shouldReplicate returns correct value", "Replication", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100, replicate = true },
        serverOnly = { type = "number", default = 50, replicate = false },
        unspecified = { type = "number", default = 25 },
    })

    assert_true(attrs:shouldReplicate("health"), "Health should replicate")
    assert_false(attrs:shouldReplicate("serverOnly"), "serverOnly should not replicate")
    assert_false(attrs:shouldReplicate("unspecified"), "Unspecified should default to false")
end)

test("getReplicatedValues returns only replicated", "Replication", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100, replicate = true },
        mana = { type = "number", default = 50, replicate = true },
        serverSecret = { type = "number", default = 999, replicate = false },
    })

    local replicated = attrs:getReplicatedValues()

    assert_eq(replicated.health, 100, "Health should be included")
    assert_eq(replicated.mana, 50, "Mana should be included")
    assert_nil(replicated.serverSecret, "serverSecret should not be included")
end)

--------------------------------------------------------------------------------
-- TEST CASES: EDGE CASES
--------------------------------------------------------------------------------

test("Handles empty schema", "Edge Cases", function()
    local attrs = AttributeSet.new({})
    local all = attrs:getAll()

    local count = 0
    for _ in pairs(all) do count = count + 1 end

    assert_eq(count, 0, "Should have no attributes")
end)

test("Returns nil for unknown attribute", "Edge Cases", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    assert_nil(attrs:get("unknown"), "Unknown attribute should return nil")
    assert_nil(attrs:getBase("unknown"), "Unknown base should return nil")
end)

test("Modifier on unknown attribute returns nil", "Edge Cases", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    local modId = attrs:applyModifier("unknown", {
        operation = "additive",
        value = 5,
        source = "test",
    })

    assert_nil(modId, "Should return nil for unknown attribute")
end)

test("Remove nonexistent modifier returns false", "Edge Cases", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
    })

    local success = attrs:removeModifier(99999)
    assert_false(success, "Should return false for nonexistent modifier")
end)

test("getDebugInfo returns valid data", "Edge Cases", function()
    local attrs = AttributeSet.new({
        health = { type = "number", default = 100 },
        defense = { type = "number", default = 10 },
    })

    attrs:applyModifier("defense", { operation = "additive", value = 5, source = "armor" })

    local debug = attrs:getDebugInfo()
    assert_eq(debug.attributeCount, 2, "Should have 2 attributes")
    assert_eq(debug.modifierCount, 1, "Should have 1 modifier")
    assert_not_nil(debug.dependencyOrder, "Should have dependency order")
end)

return Tests
