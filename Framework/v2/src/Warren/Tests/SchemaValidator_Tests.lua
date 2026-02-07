--[[
    Warren Framework v2
    SchemaValidator Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.SchemaValidator.runAll()
    ```

    Or run specific test groups:

    ```lua
    Tests.SchemaValidator.runGroup("Type Checking")
    Tests.SchemaValidator.runGroup("Field Validation")
    Tests.SchemaValidator.runGroup("Schema Validation")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local SchemaValidator = require(ReplicatedStorage.Warren.Internal.SchemaValidator)

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

local function assert_table_length(tbl, expected, message)
    local actual = #tbl
    if actual ~= expected then
        error(string.format("%s: expected length %d, got %d",
            message or "Assertion failed",
            expected,
            actual), 2)
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
    print("  SchemaValidator Test Suite")
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
    print("  SchemaValidator:", group)
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
-- TYPE CHECKING TESTS
--------------------------------------------------------------------------------

test("getTypeChecker returns function for valid types", "Type Checking", function()
    assert_not_nil(SchemaValidator.getTypeChecker("string"), "string")
    assert_not_nil(SchemaValidator.getTypeChecker("number"), "number")
    assert_not_nil(SchemaValidator.getTypeChecker("boolean"), "boolean")
    assert_not_nil(SchemaValidator.getTypeChecker("table"), "table")
    assert_not_nil(SchemaValidator.getTypeChecker("Instance"), "Instance")
    assert_not_nil(SchemaValidator.getTypeChecker("Vector3"), "Vector3")
    assert_not_nil(SchemaValidator.getTypeChecker("CFrame"), "CFrame")
end)

test("getTypeChecker returns nil for unknown types", "Type Checking", function()
    assert_nil(SchemaValidator.getTypeChecker("FakeType"), "FakeType")
    assert_nil(SchemaValidator.getTypeChecker(""), "empty string")
end)

test("isValidType returns true for valid types", "Type Checking", function()
    assert_true(SchemaValidator.isValidType("string"), "string")
    assert_true(SchemaValidator.isValidType("number"), "number")
    assert_true(SchemaValidator.isValidType("Instance"), "Instance")
    assert_true(SchemaValidator.isValidType("any"), "any")
end)

test("isValidType returns false for invalid types", "Type Checking", function()
    assert_false(SchemaValidator.isValidType("FakeType"), "FakeType")
    assert_false(SchemaValidator.isValidType(nil), "nil")
end)

test("string type checker works", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("string")
    assert_true(checker("hello"), "string literal")
    assert_true(checker(""), "empty string")
    assert_false(checker(123), "number")
    assert_false(checker(nil), "nil")
    assert_false(checker({}), "table")
end)

test("number type checker works", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("number")
    assert_true(checker(123), "integer")
    assert_true(checker(3.14), "float")
    assert_true(checker(0), "zero")
    assert_true(checker(-5), "negative")
    assert_false(checker("123"), "string")
    assert_false(checker(nil), "nil")
end)

test("boolean type checker works", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("boolean")
    assert_true(checker(true), "true")
    assert_true(checker(false), "false")
    assert_false(checker(1), "number")
    assert_false(checker("true"), "string")
end)

test("table type checker works", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("table")
    assert_true(checker({}), "empty table")
    assert_true(checker({1, 2, 3}), "array")
    assert_true(checker({a = 1}), "dictionary")
    assert_false(checker("{}"), "string")
end)

test("any type checker accepts everything", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("any")
    assert_true(checker("string"), "string")
    assert_true(checker(123), "number")
    assert_true(checker({}), "table")
    assert_true(checker(true), "boolean")
    -- 'any' accepts nil too according to the checker
    assert_true(checker(nil), "nil")
end)

test("Vector3 type checker works", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("Vector3")
    assert_true(checker(Vector3.new(0, 0, 0)), "zero vector")
    assert_true(checker(Vector3.new(1, 2, 3)), "vector")
    assert_false(checker({x = 1, y = 2, z = 3}), "table")
    assert_false(checker("Vector3"), "string")
end)

test("CFrame type checker works", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("CFrame")
    assert_true(checker(CFrame.new()), "identity")
    assert_true(checker(CFrame.new(1, 2, 3)), "position")
    assert_false(checker(Vector3.new()), "Vector3")
end)

test("Instance type checker works", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("Instance")
    local part = Instance.new("Part")
    local folder = Instance.new("Folder")
    assert_true(checker(part), "Part")
    assert_true(checker(folder), "Folder")
    assert_false(checker({}), "table")
    part:Destroy()
    folder:Destroy()
end)

test("Part type checker requires BasePart", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("Part")
    local part = Instance.new("Part")
    local folder = Instance.new("Folder")
    assert_true(checker(part), "Part")
    assert_false(checker(folder), "Folder is not BasePart")
    part:Destroy()
    folder:Destroy()
end)

test("Model type checker requires Model", "Type Checking", function()
    local checker = SchemaValidator.getTypeChecker("Model")
    local model = Instance.new("Model")
    local folder = Instance.new("Folder")
    assert_true(checker(model), "Model")
    assert_false(checker(folder), "Folder is not Model")
    model:Destroy()
    folder:Destroy()
end)

--------------------------------------------------------------------------------
-- FIELD VALIDATION TESTS
--------------------------------------------------------------------------------

test("validateField passes valid string", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        "hello",
        { type = "string" },
        "testField",
        {}
    )
    assert_true(valid, "Should pass")
    assert_nil(err, "No error")
end)

test("validateField fails invalid type", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        123,
        { type = "string" },
        "testField",
        {}
    )
    assert_false(valid, "Should fail")
    assert_not_nil(err, "Has error message")
end)

test("validateField passes nil for non-required", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        nil,
        { type = "string", required = false },
        "testField",
        {}
    )
    assert_true(valid, "Should pass")
end)

test("validateField fails nil for required", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        nil,
        { type = "string", required = true },
        "testField",
        {}
    )
    assert_false(valid, "Should fail")
    assert_not_nil(err, "Has error message")
end)

test("validateField passes enum value", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        "Rare",
        { type = "string", enum = { "Common", "Rare", "Epic" } },
        "rarity",
        {}
    )
    assert_true(valid, "Should pass")
end)

test("validateField fails invalid enum value", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        "Legendary",
        { type = "string", enum = { "Common", "Rare", "Epic" } },
        "rarity",
        {}
    )
    assert_false(valid, "Should fail")
    assert_not_nil(err, "Has error message")
end)

test("validateField passes number in range", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        50,
        { type = "number", range = { min = 1, max = 100 } },
        "count",
        {}
    )
    assert_true(valid, "Should pass")
end)

test("validateField fails number below min", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        0,
        { type = "number", range = { min = 1, max = 100 } },
        "count",
        {}
    )
    assert_false(valid, "Should fail")
end)

test("validateField fails number above max", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        150,
        { type = "number", range = { min = 1, max = 100 } },
        "count",
        {}
    )
    assert_false(valid, "Should fail")
end)

test("validateField passes custom validator", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        "test",
        {
            type = "string",
            validator = function(v) return v:len() > 2 end,
        },
        "name",
        {}
    )
    assert_true(valid, "Should pass")
end)

test("validateField fails custom validator", "Field Validation", function()
    local valid, err = SchemaValidator.validateField(
        "ab",
        {
            type = "string",
            validator = function(v) return v:len() > 2 end,
        },
        "name",
        {}
    )
    assert_false(valid, "Should fail")
end)

test("validateField custom validator receives payload", "Field Validation", function()
    local receivedPayload = nil
    local valid, err = SchemaValidator.validateField(
        "test",
        {
            type = "string",
            validator = function(v, f, p)
                receivedPayload = p
                return true
            end,
        },
        "name",
        { other = "value" }
    )
    assert_not_nil(receivedPayload, "Received payload")
    assert_eq(receivedPayload.other, "value", "Payload has correct value")
end)

--------------------------------------------------------------------------------
-- SCHEMA VALIDATION TESTS
--------------------------------------------------------------------------------

test("validate passes valid payload", "Schema Validation", function()
    local schema = {
        name = { type = "string", required = true },
        count = { type = "number" },
    }
    local payload = { name = "test", count = 5 }
    local valid, errors = SchemaValidator.validate(payload, schema)
    assert_true(valid, "Should pass")
    assert_table_length(errors, 0, "No errors")
end)

test("validate fails missing required field", "Schema Validation", function()
    local schema = {
        name = { type = "string", required = true },
        count = { type = "number" },
    }
    local payload = { count = 5 }
    local valid, errors = SchemaValidator.validate(payload, schema)
    assert_false(valid, "Should fail")
    assert_table_length(errors, 1, "One error")
    assert_eq(errors[1].field, "name", "Error on correct field")
end)

test("validate fails wrong type", "Schema Validation", function()
    local schema = {
        name = { type = "string" },
        count = { type = "number" },
    }
    local payload = { name = "test", count = "five" }
    local valid, errors = SchemaValidator.validate(payload, schema)
    assert_false(valid, "Should fail")
    assert_table_length(errors, 1, "One error")
    assert_eq(errors[1].field, "count", "Error on correct field")
end)

test("validate collects multiple errors", "Schema Validation", function()
    local schema = {
        name = { type = "string", required = true },
        count = { type = "number", required = true },
    }
    local payload = {}
    local valid, errors = SchemaValidator.validate(payload, schema)
    assert_false(valid, "Should fail")
    assert_eq(#errors, 2, "Two errors")
end)

test("validate rejects non-table payload", "Schema Validation", function()
    local schema = { name = { type = "string" } }
    local valid, errors = SchemaValidator.validate("not a table", schema)
    assert_false(valid, "Should fail")
end)

test("validate rejects non-table schema", "Schema Validation", function()
    local valid, errors = SchemaValidator.validate({}, "not a table")
    assert_false(valid, "Should fail")
end)

--------------------------------------------------------------------------------
-- VALIDATE AND PROCESS TESTS
--------------------------------------------------------------------------------

test("validateAndProcess injects defaults", "Validate and Process", function()
    local schema = {
        name = { type = "string", required = true },
        count = { type = "number", default = 1 },
    }
    local payload = { name = "test" }
    local valid, errors, processed = SchemaValidator.validateAndProcess(payload, schema)
    assert_true(valid, "Should pass")
    assert_eq(processed.name, "test", "Name preserved")
    assert_eq(processed.count, 1, "Default injected")
end)

test("validateAndProcess preserves existing values over defaults", "Validate and Process", function()
    local schema = {
        count = { type = "number", default = 1 },
    }
    local payload = { count = 5 }
    local valid, errors, processed = SchemaValidator.validateAndProcess(payload, schema)
    assert_true(valid, "Should pass")
    assert_eq(processed.count, 5, "Existing value preserved")
end)

test("validateAndProcess validates after injecting defaults", "Validate and Process", function()
    local schema = {
        count = { type = "number", default = 1, range = { min = 1, max = 10 } },
    }
    local payload = {}
    local valid, errors, processed = SchemaValidator.validateAndProcess(payload, schema)
    assert_true(valid, "Should pass")
    assert_eq(processed.count, 1, "Default in range")
end)

--------------------------------------------------------------------------------
-- SANITIZE TESTS
--------------------------------------------------------------------------------

test("sanitize removes undeclared fields", "Sanitize", function()
    local schema = {
        name = { type = "string" },
    }
    local payload = { name = "test", extra = "removed", hack = true }
    local sanitized = SchemaValidator.sanitize(payload, schema)
    assert_eq(sanitized.name, "test", "Declared field kept")
    assert_nil(sanitized.extra, "Extra field removed")
    assert_nil(sanitized.hack, "Hack field removed")
end)

test("sanitize injects defaults", "Sanitize", function()
    local schema = {
        name = { type = "string" },
        count = { type = "number", default = 1 },
    }
    local payload = { name = "test" }
    local sanitized = SchemaValidator.sanitize(payload, schema)
    assert_eq(sanitized.name, "test", "Name kept")
    assert_eq(sanitized.count, 1, "Default injected")
end)

test("sanitize handles nil/non-table inputs", "Sanitize", function()
    local schema = { name = { type = "string" } }
    local sanitized1 = SchemaValidator.sanitize(nil, schema)
    local sanitized2 = SchemaValidator.sanitize({}, nil)
    assert_eq(type(sanitized1), "table", "Returns table for nil payload")
    assert_eq(type(sanitized2), "table", "Returns table for nil schema")
end)

--------------------------------------------------------------------------------
-- SCHEMA DEFINITION VALIDATION TESTS
--------------------------------------------------------------------------------

test("validateSchema passes valid schema", "Schema Definition", function()
    local schema = {
        name = { type = "string", required = true },
        count = { type = "number", range = { min = 1 } },
        rarity = { type = "string", enum = { "Common", "Rare" } },
    }
    local valid, err = SchemaValidator.validateSchema(schema)
    assert_true(valid, "Should pass")
    assert_nil(err, "No error")
end)

test("validateSchema fails missing type", "Schema Definition", function()
    local schema = {
        name = { required = true },  -- Missing type
    }
    local valid, err = SchemaValidator.validateSchema(schema)
    assert_false(valid, "Should fail")
    assert_not_nil(err, "Has error")
end)

test("validateSchema fails unknown type", "Schema Definition", function()
    local schema = {
        name = { type = "FakeType" },
    }
    local valid, err = SchemaValidator.validateSchema(schema)
    assert_false(valid, "Should fail")
end)

test("validateSchema fails enum on non-string", "Schema Definition", function()
    local schema = {
        count = { type = "number", enum = { 1, 2, 3 } },
    }
    local valid, err = SchemaValidator.validateSchema(schema)
    assert_false(valid, "Should fail")
end)

test("validateSchema fails range on non-number", "Schema Definition", function()
    local schema = {
        name = { type = "string", range = { min = 1 } },
    }
    local valid, err = SchemaValidator.validateSchema(schema)
    assert_false(valid, "Should fail")
end)

test("validateSchema fails non-function validator", "Schema Definition", function()
    local schema = {
        name = { type = "string", validator = "not a function" },
    }
    local valid, err = SchemaValidator.validateSchema(schema)
    assert_false(valid, "Should fail")
end)

--------------------------------------------------------------------------------
-- UTILITY TESTS
--------------------------------------------------------------------------------

test("mergeSchemas combines two schemas", "Utilities", function()
    local base = {
        name = { type = "string" },
        count = { type = "number" },
    }
    local extension = {
        count = { type = "number", required = true },  -- Override
        extra = { type = "boolean" },  -- Add new
    }
    local merged = SchemaValidator.mergeSchemas(base, extension)
    assert_not_nil(merged.name, "Base field kept")
    assert_not_nil(merged.extra, "Extension field added")
    assert_true(merged.count.required, "Extension overrides base")
end)

test("formatErrors creates readable string", "Utilities", function()
    local errors = {
        { field = "name", message = "Name is required" },
        { field = "count", message = "Count must be positive" },
    }
    local formatted = SchemaValidator.formatErrors(errors)
    assert_not_nil(formatted:find("Name is required"), "Contains first error")
    assert_not_nil(formatted:find("Count must be positive"), "Contains second error")
end)

test("formatErrors handles empty array", "Utilities", function()
    local formatted = SchemaValidator.formatErrors({})
    assert_eq(formatted, "No errors", "Returns 'No errors'")
end)

test("getSupportedTypes returns array of types", "Utilities", function()
    local types = SchemaValidator.getSupportedTypes()
    assert_true(#types > 0, "Has types")
    -- Check some expected types exist
    local hasString = false
    local hasNumber = false
    for _, t in ipairs(types) do
        if t == "string" then hasString = true end
        if t == "number" then hasNumber = true end
    end
    assert_true(hasString, "Has string type")
    assert_true(hasNumber, "Has number type")
end)

--------------------------------------------------------------------------------
-- SENDER VALIDATION TESTS
--------------------------------------------------------------------------------

test("validateSender passes matching player", "Sender Validation", function()
    -- Can only properly test with actual Player objects in-game
    -- This tests the function structure with nil/non-player values
    local payload = {}
    local valid, err = SchemaValidator.validateSender(payload, "player", nil)
    -- No player field means it passes (field is optional)
    assert_true(valid, "Should pass with no player field")
end)

test("validateSender fails non-table payload", "Sender Validation", function()
    local valid, err = SchemaValidator.validateSender("not a table", "player", nil)
    assert_false(valid, "Should fail")
end)

return Tests
