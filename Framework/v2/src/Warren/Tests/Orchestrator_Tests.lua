--[[
    Warren Framework v2
    Orchestrator Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Warren.Tests)
    Tests.Orchestrator.runAll()
    ```

    Or run specific test groups:

    ```lua
    Tests.Orchestrator.runGroup("Configuration")
    Tests.Orchestrator.runGroup("Node Management")
    Tests.Orchestrator.runGroup("Wiring")
    Tests.Orchestrator.runGroup("Schema Validation")
    Tests.Orchestrator.runGroup("Mode System")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local Node = Lib.Node
local Components = Lib.Components
local Orchestrator = Components.Orchestrator
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
    print("  Orchestrator Test Suite")
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
    print("  Orchestrator:", group)
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
-- HELPER: CREATE TEST ORCHESTRATOR
--------------------------------------------------------------------------------

local function createOrchestrator(id)
    local orch = Orchestrator:new({ id = id or "TestOrchestrator" })
    orch.Sys.onInit(orch)
    return orch
end

local function cleanupOrchestrator(orch)
    if orch and orch.Sys and orch.Sys.onStop then
        orch.Sys.onStop(orch)
    end
end

--------------------------------------------------------------------------------
-- HELPER: MOCK NODE CLASS FOR TESTING
--------------------------------------------------------------------------------

-- Create a simple test node that tracks signals
local function createTestNodeClass(name)
    return Node.extend({
        name = name or "TestNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                self._received = {}
                self._started = false
            end,
            onStart = function(self)
                self._started = true
            end,
            onStop = function(self)
                self._started = false
            end,
        },

        In = {
            onConfigure = function(self, data)
                table.insert(self._received, { signal = "onConfigure", data = data })
            end,
            onSignal = function(self, data)
                table.insert(self._received, { signal = "onSignal", data = data })
            end,
            onProcess = function(self, data)
                table.insert(self._received, { signal = "onProcess", data = data })
                -- Echo back via Out
                self.Out:Fire("processed", { input = data, nodeId = self.id })
            end,
        },

        Out = {
            processed = {},
        },
    })
end

-- Register test nodes with Components (temporarily)
local TestNodeA = createTestNodeClass("TestNodeA")
local TestNodeB = createTestNodeClass("TestNodeB")
Components.TestNodeA = TestNodeA
Components.TestNodeB = TestNodeB

--------------------------------------------------------------------------------
-- BASIC TESTS
--------------------------------------------------------------------------------

test("Orchestrator extends Node", "Basics", function()
    assert_eq(Orchestrator.name, "Orchestrator", "Has correct name")
    assert_not_nil(Orchestrator.Sys, "Has Sys handlers")
    assert_not_nil(Orchestrator.In, "Has In handlers")
    assert_not_nil(Orchestrator.Out, "Has Out schema")
end)

test("Orchestrator creates instance", "Basics", function()
    local orch = createOrchestrator("TestOrch1")
    assert_not_nil(orch, "Instance created")
    assert_eq(orch.id, "TestOrch1", "Has correct ID")
    assert_eq(orch.class, "Orchestrator", "Has correct class")
    cleanupOrchestrator(orch)
end)

test("Orchestrator initializes internal state", "Basics", function()
    local orch = createOrchestrator("TestOrch2")
    assert_not_nil(orch._nodes, "Has nodes table")
    assert_not_nil(orch._schemas, "Has schemas table")
    assert_not_nil(orch._defaultWiring, "Has wiring table")
    assert_eq(orch._enabled, false, "Not enabled initially")
    cleanupOrchestrator(orch)
end)

--------------------------------------------------------------------------------
-- CONFIGURATION TESTS
--------------------------------------------------------------------------------

test("onConfigure accepts empty config", "Configuration", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {})
    -- Should not error
    cleanupOrchestrator(orch)
end)

test("onConfigure registers schemas", "Configuration", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        schemas = {
            TestSchema = {
                name = { type = "string", required = true },
            },
        },
    })
    assert_not_nil(orch:getSchema("TestSchema"), "Schema registered")
    cleanupOrchestrator(orch)
end)

test("onConfigure rejects invalid schema", "Configuration", function()
    local orch = createOrchestrator()
    local errFired = false
    orch.Err = {
        Fire = function(self, data)
            errFired = true
            assert_eq(data.reason, "invalidSchema", "Correct error reason")
        end,
    }
    orch.In.onConfigure(orch, {
        schemas = {
            BadSchema = {
                name = { type = "FakeType" },  -- Invalid type
            },
        },
    })
    assert_true(errFired, "Error was fired")
    cleanupOrchestrator(orch)
end)

test("onConfigure spawns nodes", "Configuration", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        nodes = {
            NodeA = { class = "TestNodeA" },
            NodeB = { class = "TestNodeB" },
        },
    })
    assert_not_nil(orch:getNode("NodeA"), "NodeA spawned")
    assert_not_nil(orch:getNode("NodeB"), "NodeB spawned")
    assert_eq(#orch:getNodeIds(), 2, "Two nodes total")
    cleanupOrchestrator(orch)
end)

test("onConfigure rejects unknown class", "Configuration", function()
    local orch = createOrchestrator()
    local errFired = false
    orch.Err = {
        Fire = function(self, data)
            errFired = true
            assert_eq(data.reason, "nodeError", "Correct error reason")
        end,
    }
    orch.In.onConfigure(orch, {
        nodes = {
            BadNode = { class = "NonExistentClass" },
        },
    })
    assert_true(errFired, "Error was fired")
    cleanupOrchestrator(orch)
end)

test("onConfigure fires configured signal", "Configuration", function()
    local orch = createOrchestrator()
    local configuredFired = false
    local configuredData = nil
    local originalFire = orch.Out.Fire
    orch.Out.Fire = function(self, signal, data)
        if signal == "configured" then
            configuredFired = true
            configuredData = data
        end
        originalFire(self, signal, data)
    end

    orch.In.onConfigure(orch, {
        schemas = { S1 = { x = { type = "number" } } },
        nodes = { N1 = { class = "TestNodeA" } },
        wiring = {},
    })

    assert_true(configuredFired, "configured signal fired")
    assert_eq(configuredData.nodeCount, 1, "nodeCount correct")
    assert_eq(configuredData.schemaCount, 1, "schemaCount correct")
    cleanupOrchestrator(orch)
end)

--------------------------------------------------------------------------------
-- NODE MANAGEMENT TESTS
--------------------------------------------------------------------------------

test("onAddNode adds single node", "Node Management", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {})
    orch.In.onAddNode(orch, { id = "DynamicNode", class = "TestNodeA" })
    assert_not_nil(orch:getNode("DynamicNode"), "Node added")
    cleanupOrchestrator(orch)
end)

test("onRemoveNode removes node", "Node Management", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        nodes = { ToRemove = { class = "TestNodeA" } },
    })
    assert_not_nil(orch:getNode("ToRemove"), "Node exists")
    orch.In.onRemoveNode(orch, { id = "ToRemove" })
    assert_nil(orch:getNode("ToRemove"), "Node removed")
    cleanupOrchestrator(orch)
end)

test("getNodeIds returns all node IDs", "Node Management", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        nodes = {
            N1 = { class = "TestNodeA" },
            N2 = { class = "TestNodeB" },
            N3 = { class = "TestNodeA" },
        },
    })
    local ids = orch:getNodeIds()
    assert_eq(#ids, 3, "Three nodes")
    cleanupOrchestrator(orch)
end)

test("nodes receive onInit during configuration", "Node Management", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        nodes = { InitTest = { class = "TestNodeA" } },
    })
    local node = orch:getNode("InitTest")
    assert_not_nil(node._received, "Node was initialized")
    cleanupOrchestrator(orch)
end)

--------------------------------------------------------------------------------
-- WIRING TESTS
--------------------------------------------------------------------------------

test("wiring routes signals between nodes", "Wiring", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        nodes = {
            Source = { class = "TestNodeA" },
            Target = { class = "TestNodeB" },
        },
        wiring = {
            {
                from = "Source",
                signal = "processed",
                to = "Target",
                handler = "onSignal",
            },
        },
    })

    -- Enable routing
    orch.In.onEnable(orch)

    -- Trigger signal from Source
    local source = orch:getNode("Source")
    local target = orch:getNode("Target")
    source._received = {}
    target._received = {}

    -- Trigger onProcess which fires 'processed'
    source.In.onProcess(source, { value = 42 })

    -- Check target received it
    assert_eq(#target._received, 1, "Target received signal")
    assert_eq(target._received[1].signal, "onSignal", "Correct handler called")

    cleanupOrchestrator(orch)
end)

test("wiring validates config structure", "Wiring", function()
    local orch = createOrchestrator()
    local errFired = false
    orch.Err = {
        Fire = function(self, data)
            errFired = true
            assert_eq(data.reason, "invalidWiring", "Correct error reason")
        end,
    }
    orch.In.onConfigure(orch, {
        wiring = {
            { from = "Source" },  -- Missing signal, to, handler
        },
    })
    assert_true(errFired, "Error was fired")
    cleanupOrchestrator(orch)
end)

test("enable/disable controls routing", "Wiring", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        nodes = {
            A = { class = "TestNodeA" },
            B = { class = "TestNodeB" },
        },
        wiring = {
            { from = "A", signal = "processed", to = "B", handler = "onSignal" },
        },
    })

    -- Initially disabled after configure
    assert_false(orch:isEnabled(), "Not enabled initially")

    -- Enable
    orch.In.onEnable(orch)
    assert_true(orch:isEnabled(), "Enabled after onEnable")

    -- Disable
    orch.In.onDisable(orch)
    assert_false(orch:isEnabled(), "Disabled after onDisable")

    cleanupOrchestrator(orch)
end)

--------------------------------------------------------------------------------
-- SCHEMA VALIDATION TESTS
--------------------------------------------------------------------------------

test("wiring validates payload against schema", "Schema Validation", function()
    local orch = createOrchestrator()
    local validationFailed = false

    local originalFire = orch.Out.Fire
    orch.Out.Fire = function(self, signal, data)
        if signal == "validationFailed" then
            validationFailed = true
        end
        originalFire(self, signal, data)
    end

    orch.In.onConfigure(orch, {
        schemas = {
            ProcessedSchema = {
                input = { type = "table", required = true },
                nodeId = { type = "string", required = true },
            },
        },
        nodes = {
            Source = { class = "TestNodeA" },
            Target = { class = "TestNodeB" },
        },
        wiring = {
            {
                from = "Source",
                signal = "processed",
                to = "Target",
                handler = "onSignal",
                schema = "ProcessedSchema",
                validate = true,
            },
        },
    })

    orch.In.onEnable(orch)

    -- Send valid payload
    local source = orch:getNode("Source")
    source.In.onProcess(source, { value = 1 })  -- This will fire 'processed' with correct format

    -- The processed signal has { input = data, nodeId = self.id } which matches schema
    -- So validation should pass
    assert_false(validationFailed, "Valid payload passes")

    cleanupOrchestrator(orch)
end)

test("strict validation blocks invalid payload", "Schema Validation", function()
    local orch = createOrchestrator()

    orch.In.onConfigure(orch, {
        schemas = {
            StrictSchema = {
                requiredField = { type = "string", required = true },
            },
        },
        nodes = {
            Source = { class = "TestNodeA" },
            Target = { class = "TestNodeB" },
        },
        wiring = {
            {
                from = "Source",
                signal = "processed",
                to = "Target",
                handler = "onSignal",
                schema = "StrictSchema",
                validate = true,  -- Strict mode
            },
        },
    })

    orch.In.onEnable(orch)

    local target = orch:getNode("Target")
    target._received = {}

    -- The 'processed' signal payload doesn't have 'requiredField'
    -- So with strict validation, target should NOT receive it
    local source = orch:getNode("Source")
    source.In.onProcess(source, {})

    -- Target should not receive because validation failed
    assert_eq(#target._received, 0, "Target did not receive blocked payload")

    cleanupOrchestrator(orch)
end)

test("inline schema works", "Schema Validation", function()
    local orch = createOrchestrator()

    orch.In.onConfigure(orch, {
        nodes = {
            Source = { class = "TestNodeA" },
            Target = { class = "TestNodeB" },
        },
        wiring = {
            {
                from = "Source",
                signal = "processed",
                to = "Target",
                handler = "onSignal",
                schema = {
                    input = { type = "table" },
                },
                validate = true,
            },
        },
    })

    orch.In.onEnable(orch)

    local target = orch:getNode("Target")
    target._received = {}

    local source = orch:getNode("Source")
    source.In.onProcess(source, { x = 1 })

    -- Should pass with inline schema
    assert_eq(#target._received, 1, "Target received validated payload")

    cleanupOrchestrator(orch)
end)

--------------------------------------------------------------------------------
-- MODE SYSTEM TESTS
--------------------------------------------------------------------------------

test("onSetMode switches modes", "Mode System", function()
    local orch = createOrchestrator()
    orch.In.onConfigure(orch, {
        modes = {
            modeA = { wiring = {} },
            modeB = { wiring = {} },
        },
    })

    assert_eq(orch:getCurrentMode(), "", "Starts with default mode")

    orch.In.onSetMode(orch, { mode = "modeA" })
    assert_eq(orch:getCurrentMode(), "modeA", "Switched to modeA")

    orch.In.onSetMode(orch, { mode = "modeB" })
    assert_eq(orch:getCurrentMode(), "modeB", "Switched to modeB")

    cleanupOrchestrator(orch)
end)

test("mode switch fires modeChanged signal", "Mode System", function()
    local orch = createOrchestrator()
    local modeChangedData = nil

    local originalFire = orch.Out.Fire
    orch.Out.Fire = function(self, signal, data)
        if signal == "modeChanged" then
            modeChangedData = data
        end
        originalFire(self, signal, data)
    end

    orch.In.onConfigure(orch, {
        modes = { testMode = { wiring = {} } },
    })

    orch.In.onSetMode(orch, { mode = "testMode" })

    assert_not_nil(modeChangedData, "modeChanged fired")
    assert_eq(modeChangedData.from, "", "from is empty string")
    assert_eq(modeChangedData.to, "testMode", "to is testMode")

    cleanupOrchestrator(orch)
end)

test("mode-specific wiring adds to default", "Mode System", function()
    local orch = createOrchestrator()

    orch.In.onConfigure(orch, {
        nodes = {
            A = { class = "TestNodeA" },
            B = { class = "TestNodeB" },
        },
        wiring = {
            -- Default wiring: A -> B
            { from = "A", signal = "processed", to = "B", handler = "onSignal" },
        },
        modes = {
            special = {
                wiring = {
                    -- Mode adds: A -> A (self loop for testing)
                    { from = "A", signal = "processed", to = "A", handler = "onConfigure" },
                },
            },
        },
    })

    orch.In.onEnable(orch)

    -- Helper to count signals by name
    local function countSignals(received, signalName)
        local count = 0
        for _, entry in ipairs(received) do
            if entry.signal == signalName then
                count = count + 1
            end
        end
        return count
    end

    -- In default mode, only A->B (onSignal), no self-loop (onConfigure)
    local a = orch:getNode("A")
    local b = orch:getNode("B")
    a._received = {}
    b._received = {}

    a.In.onProcess(a, { test = 1 })
    assert_eq(countSignals(b._received, "onSignal"), 1, "B received onSignal in default mode")
    assert_eq(countSignals(a._received, "onConfigure"), 0, "A did not receive onConfigure in default mode")

    -- Switch to special mode (additive wiring)
    orch.In.onSetMode(orch, { mode = "special" })
    a._received = {}
    b._received = {}

    a.In.onProcess(a, { test = 2 })
    assert_eq(countSignals(b._received, "onSignal"), 1, "B still receives onSignal in special mode")
    assert_eq(countSignals(a._received, "onConfigure"), 1, "A receives onConfigure self-loop in special mode")

    cleanupOrchestrator(orch)
end)

--------------------------------------------------------------------------------
-- ERROR HANDLING TESTS
--------------------------------------------------------------------------------

test("errors on invalid config data", "Error Handling", function()
    local orch = createOrchestrator()
    local errFired = false
    orch.Err = {
        Fire = function(self, data)
            errFired = true
        end,
    }
    orch.In.onConfigure(orch, nil)
    assert_true(errFired, "Error fired for nil config")
    cleanupOrchestrator(orch)
end)

test("errors on missing target node", "Error Handling", function()
    local orch = createOrchestrator()
    local errFired = false
    local errReason = nil
    orch.Err = {
        Fire = function(self, data)
            errFired = true
            errReason = data.reason
        end,
    }

    orch.In.onConfigure(orch, {
        nodes = {
            Source = { class = "TestNodeA" },
            -- Target not created
        },
        wiring = {
            { from = "Source", signal = "processed", to = "MissingTarget", handler = "onSignal" },
        },
    })

    orch.In.onEnable(orch)

    -- Trigger signal
    local source = orch:getNode("Source")
    source.In.onProcess(source, {})

    assert_true(errFired, "Error fired for missing target")
    assert_eq(errReason, "nodeError", "Correct error reason")

    cleanupOrchestrator(orch)
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

-- Remove test node classes from Components
local function cleanupTestNodes()
    Components.TestNodeA = nil
    Components.TestNodeB = nil
end

-- Call this after tests are done
function Tests.cleanup()
    cleanupTestNodes()
    print("Test cleanup complete")
end

return Tests
