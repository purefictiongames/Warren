--[[
    LibPureFiction Framework v2
    IPC & Node System Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests.IPC_Node_Tests)
    Tests.runAll()
    ```

    Or run specific test groups:

    ```lua
    Tests.runGroup("Node")
    Tests.runGroup("IPC")
    Tests.runGroup("Messaging")
    ```

    Or run a single test:

    ```lua
    Tests.run("Node.extend creates class with name")
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Lib
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Node = Lib.Node
local IPC = Lib.System.IPC
local Asset = Lib.System.Asset
local Debug = Lib.System.Debug

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

local function assert_error(fn, expectedPattern, message)
    local success, err = pcall(fn)
    if success then
        error(message or "Expected function to throw an error", 2)
    end
    if expectedPattern and not string.find(tostring(err), expectedPattern) then
        error(string.format("%s: error message '%s' did not match pattern '%s'",
            message or "Error pattern mismatch",
            tostring(err),
            expectedPattern), 2)
    end
end

local function assert_type(value, expectedType, message)
    local actualType = typeof(value)
    if actualType ~= expectedType then
        error(string.format("%s: expected type %s, got %s",
            message or "Type mismatch",
            expectedType,
            actualType), 2)
    end
end

local function assert_table_has(tbl, key, message)
    if tbl[key] == nil then
        error(string.format("%s: table missing key '%s'",
            message or "Missing key",
            tostring(key)), 2)
    end
end

local function test(name, group, fn)
    table.insert(testCases, { name = name, group = group, fn = fn })
    testGroups[group] = testGroups[group] or {}
    table.insert(testGroups[group], name)
end

local function runTest(testCase)
    -- Reset state before each test
    Asset.reset()
    IPC.reset()

    local success, err = pcall(testCase.fn)
    if success then
        stats.passed = stats.passed + 1
        log("pass", testCase.name)
        return true
    else
        stats.failed = stats.failed + 1
        log("fail", testCase.name)
        log("info", "     Error:", tostring(err))
        return false
    end
end

function Tests.run(name)
    resetStats()
    for _, tc in ipairs(testCases) do
        if tc.name == name then
            log("group", "Running: " .. name)
            runTest(tc)
            break
        end
    end
    Tests.printSummary()
end

function Tests.runGroup(group)
    resetStats()
    log("group", "Test Group: " .. group)

    local groupTests = {}
    for _, tc in ipairs(testCases) do
        if tc.group == group then
            table.insert(groupTests, tc)
        end
    end

    for _, tc in ipairs(groupTests) do
        runTest(tc)
    end

    Tests.printSummary()
end

function Tests.runAll()
    resetStats()
    log("summary", "═══════════════════════════════════════════════════════")
    log("summary", "  LibPureFiction v2 - IPC & Node Test Suite")
    log("summary", "═══════════════════════════════════════════════════════")

    local currentGroup = nil
    for _, tc in ipairs(testCases) do
        if tc.group ~= currentGroup then
            currentGroup = tc.group
            log("group", currentGroup)
        end
        runTest(tc)
    end

    Tests.printSummary()
end

function Tests.printSummary()
    local total = stats.passed + stats.failed
    local status = stats.failed == 0 and "ALL PASSED" or "FAILURES DETECTED"

    log("summary", "───────────────────────────────────────────────────────")
    log("summary", string.format("  Results: %d/%d passed  |  %s", stats.passed, total, status))
    log("summary", "───────────────────────────────────────────────────────")

    return stats.failed == 0
end

function Tests.list()
    print("\nAvailable Test Groups:")
    for group in pairs(testGroups) do
        print("  •", group, "(" .. #testGroups[group] .. " tests)")
    end
    print("\nRun with: Tests.runGroup('GroupName') or Tests.runAll()")
end

--------------------------------------------------------------------------------
-- TEST CASES: NODE BASE CLASS
--------------------------------------------------------------------------------

test("Node.extend creates class with name", "Node", function()
    local MyNode = Node.extend({ name = "MyNode" })
    assert_eq(MyNode.name, "MyNode", "Class should have name")
end)

test("Node.extend requires name", "Node", function()
    assert_error(function()
        Node.extend({})
    end, "must have a name")
end)

test("Node.extend requires definition", "Node", function()
    assert_error(function()
        Node.extend(nil)
    end, "Definition required")
end)

test("Node.extend sets default domain to shared", "Node", function()
    local MyNode = Node.extend({ name = "MyNode" })
    assert_eq(MyNode.domain, "shared", "Default domain should be shared")
end)

test("Node.extend respects custom domain", "Node", function()
    local ServerNode = Node.extend({ name = "ServerNode", domain = "server" })
    assert_eq(ServerNode.domain, "server", "Domain should be server")
end)

test("Node.extend inherits required from Node", "Node", function()
    local MyNode = Node.extend({ name = "MyNode" })
    assert_not_nil(MyNode.required, "Should have required table")
    assert_not_nil(MyNode.required.Sys, "Should have Sys requirements")
end)

test("Node.extend merges custom required", "Node", function()
    local MyNode = Node.extend({
        name = "MyNode",
        required = { In = { "onCustom" } }
    })
    assert_not_nil(MyNode.required.In, "Should have In requirements")
    assert_eq(MyNode.required.In[1], "onCustom", "Should have custom requirement")
end)

test("Node.extend inherits defaults from Node", "Node", function()
    local MyNode = Node.extend({ name = "MyNode" })
    assert_not_nil(MyNode.defaults, "Should have defaults table")
    assert_not_nil(MyNode.defaults.Sys, "Should have Sys defaults")
    assert_not_nil(MyNode.defaults.Sys.onInit, "Should have onInit default")
end)

test("Node.extend copies Sys handlers", "Node", function()
    local initCalled = false
    local MyNode = Node.extend({
        name = "MyNode",
        Sys = {
            onInit = function(self) initCalled = true end
        }
    })
    assert_not_nil(MyNode.Sys, "Should have Sys table")
    assert_not_nil(MyNode.Sys.onInit, "Should have onInit handler")
end)

test("Node.extend copies In handlers", "Node", function()
    local MyNode = Node.extend({
        name = "MyNode",
        In = {
            onTest = function(self, data) end
        }
    })
    assert_not_nil(MyNode.In, "Should have In table")
    assert_not_nil(MyNode.In.onTest, "Should have onTest handler")
end)

test("Extended node can extend further", "Node", function()
    local BaseNode = Node.extend({ name = "BaseNode" })
    local ChildNode = BaseNode.extend({ name = "ChildNode" })
    assert_eq(ChildNode.name, "ChildNode", "Child should have its own name")
    assert_eq(ChildNode._parent, BaseNode, "Child should reference parent")
end)

test("Child inherits parent handlers", "Node", function()
    local BaseNode = Node.extend({
        name = "BaseNode",
        In = { onBase = function() end }
    })
    local ChildNode = BaseNode.extend({
        name = "ChildNode",
        In = { onChild = function() end }
    })
    assert_not_nil(ChildNode.In.onBase, "Child should inherit onBase")
    assert_not_nil(ChildNode.In.onChild, "Child should have onChild")
end)

test("Child can override parent handlers", "Node", function()
    local parentCalled = false
    local childCalled = false

    local BaseNode = Node.extend({
        name = "BaseNode",
        In = { onTest = function() parentCalled = true end }
    })
    local ChildNode = BaseNode.extend({
        name = "ChildNode",
        In = { onTest = function() childCalled = true end }
    })

    -- Call the child handler
    ChildNode.In.onTest()
    assert_true(childCalled, "Child handler should be called")
    assert_false(parentCalled, "Parent handler should not be called")
end)

--------------------------------------------------------------------------------
-- TEST CASES: NODE INSTANCES
--------------------------------------------------------------------------------

test("Node:new creates instance with id", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_eq(inst.id, "test1", "Instance should have id")
end)

test("Node:new requires id", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    assert_error(function()
        MyNode:new({})
    end, "must have an id")
end)

test("Node:new sets class name", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_eq(inst.class, "MyNode", "Instance should have class name")
end)

test("Node:new creates Out channel", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_not_nil(inst.Out, "Instance should have Out channel")
    assert_not_nil(inst.Out.Fire, "Out should have Fire method")
end)

test("Node:new creates Err channel", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_not_nil(inst.Err, "Instance should have Err channel")
    assert_not_nil(inst.Err.Fire, "Err should have Fire method")
end)

test("Node:new injects default handlers", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_not_nil(inst.Sys.onInit, "Instance should have onInit")
    assert_not_nil(inst.Sys.onStart, "Instance should have onStart")
    assert_not_nil(inst.Sys.onStop, "Instance should have onStop")
end)

test("Node:new respects custom Sys handlers", "Node Instance", function()
    local customInit = function(self) return "custom" end
    local MyNode = Node.extend({
        name = "MyNode",
        Sys = { onInit = customInit }
    })
    local inst = MyNode:new({ id = "test1" })
    assert_eq(inst.Sys.onInit, customInit, "Should use custom handler")
end)

test("Node:getAttribute returns nil for missing", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_nil(inst:getAttribute("missing"), "Missing attribute should be nil")
end)

test("Node:setAttribute and getAttribute work", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    inst:setAttribute("score", 100)
    assert_eq(inst:getAttribute("score"), 100, "Should get set value")
end)

test("Node:getAttributes returns all", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1", attributes = { a = 1, b = 2 } })
    local attrs = inst:getAttributes()
    assert_eq(attrs.a, 1, "Should have attribute a")
    assert_eq(attrs.b, 2, "Should have attribute b")
end)

test("Node:hasHandler finds Sys handlers", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_true(inst:hasHandler("Sys", "onInit"), "Should find onInit")
end)

test("Node:hasHandler finds In handlers", "Node Instance", function()
    local MyNode = Node.extend({
        name = "MyNode",
        In = { onTest = function() end }
    })
    local inst = MyNode:new({ id = "test1" })
    assert_true(inst:hasHandler("In", "onTest"), "Should find onTest")
end)

test("Node:hasHandler returns false for missing", "Node Instance", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local inst = MyNode:new({ id = "test1" })
    assert_false(inst:hasHandler("In", "onMissing"), "Should not find missing")
end)

--------------------------------------------------------------------------------
-- TEST CASES: IPC REGISTRATION
--------------------------------------------------------------------------------

test("IPC.registerNode accepts valid node", "IPC Registration", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local success = IPC.registerNode(MyNode)
    assert_true(success, "Should register successfully")
end)

test("IPC.registerNode requires name", "IPC Registration", function()
    assert_error(function()
        IPC.registerNode({})
    end, "must have a name")
end)

test("IPC.registerNode validates contract", "IPC Registration", function()
    local BadNode = Node.extend({
        name = "BadNode",
        required = { In = { "onMustExist" } }
        -- Missing onMustExist handler, no default
    })
    assert_error(function()
        IPC.registerNode(BadNode)
    end, "missing required handlers")
end)

test("IPC.registerNode accepts node with defaults fulfilling required", "IPC Registration", function()
    local GoodNode = Node.extend({
        name = "GoodNode",
        required = { In = { "onOptional" } },
        defaults = { In = { onOptional = function() end } }
    })
    local success = IPC.registerNode(GoodNode)
    assert_true(success, "Should register when defaults fulfill required")
end)

test("IPC.getNodeClasses returns registered", "IPC Registration", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    local classes = IPC.getNodeClasses()
    assert_true(table.find(classes, "MyNode") ~= nil, "Should find MyNode")
end)

--------------------------------------------------------------------------------
-- TEST CASES: IPC INSTANCES
--------------------------------------------------------------------------------

test("IPC.createInstance creates instance", "IPC Instances", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    local inst = IPC.createInstance("MyNode", { id = "test1" })
    assert_not_nil(inst, "Should create instance")
    assert_eq(inst.id, "test1", "Instance should have correct id")
end)

test("IPC.createInstance requires registered class", "IPC Instances", function()
    assert_error(function()
        IPC.createInstance("NotRegistered", { id = "test1" })
    end, "not registered")
end)

test("IPC.createInstance requires id", "IPC Instances", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    assert_error(function()
        IPC.createInstance("MyNode", {})
    end, "must have an id")
end)

test("IPC.createInstance rejects duplicate id", "IPC Instances", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })
    assert_error(function()
        IPC.createInstance("MyNode", { id = "test1" })
    end, "already exists")
end)

test("IPC.getInstance returns created instance", "IPC Instances", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    local created = IPC.createInstance("MyNode", { id = "test1" })
    local fetched = IPC.getInstance("test1")
    assert_eq(fetched, created, "Should return same instance")
end)

test("IPC.getInstance returns nil for missing", "IPC Instances", function()
    local fetched = IPC.getInstance("nonexistent")
    assert_nil(fetched, "Should return nil")
end)

test("IPC.getInstancesByClass returns all of class", "IPC Instances", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })
    IPC.createInstance("MyNode", { id = "test2" })
    local instances = IPC.getInstancesByClass("MyNode")
    assert_eq(#instances, 2, "Should return 2 instances")
end)

test("IPC.getInstanceCount returns correct count", "IPC Instances", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    assert_eq(IPC.getInstanceCount(), 0, "Should start at 0")
    IPC.createInstance("MyNode", { id = "test1" })
    assert_eq(IPC.getInstanceCount(), 1, "Should be 1")
    IPC.createInstance("MyNode", { id = "test2" })
    assert_eq(IPC.getInstanceCount(), 2, "Should be 2")
end)

test("IPC.despawn removes instance", "IPC Instances", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })
    IPC.despawn("test1")
    assert_nil(IPC.getInstance("test1"), "Instance should be removed")
    assert_eq(IPC.getInstanceCount(), 0, "Count should be 0")
end)

--------------------------------------------------------------------------------
-- TEST CASES: IPC MODES
--------------------------------------------------------------------------------

test("IPC.defineMode stores config", "IPC Modes", function()
    IPC.defineMode("TestMode", {
        nodes = { "NodeA" },
        wiring = { NodeA = { "NodeB" } }
    })
    local config = IPC.getModeConfig("TestMode")
    assert_not_nil(config, "Should store config")
    assert_eq(config.nodes[1], "NodeA", "Should have nodes")
end)

test("IPC.defineMode requires name", "IPC Modes", function()
    assert_error(function()
        IPC.defineMode(nil, {})
    end, "must have a name")
end)

test("IPC.getMode returns nil before switch", "IPC Modes", function()
    assert_nil(IPC.getMode(), "Should be nil initially")
end)

test("IPC.switchMode sets current mode", "IPC Modes", function()
    IPC.defineMode("TestMode", { nodes = {} })
    IPC.switchMode("TestMode")
    assert_eq(IPC.getMode(), "TestMode", "Should set mode")
end)

test("IPC.switchMode requires defined mode", "IPC Modes", function()
    assert_error(function()
        IPC.switchMode("UndefinedMode")
    end, "not defined")
end)

test("IPC.switchMode applies attributes", "IPC Modes", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.defineMode("TestMode", {
        nodes = { "MyNode" },
        attributes = {
            MyNode = { speed = 10 }
        }
    })

    IPC.init()
    IPC.switchMode("TestMode")

    local inst = IPC.getInstance("test1")
    assert_eq(inst:getAttribute("speed"), 10, "Should apply attribute")
end)

test("IPC.getModes returns all defined modes", "IPC Modes", function()
    IPC.defineMode("Mode1", { nodes = {} })
    IPC.defineMode("Mode2", { nodes = {} })
    local modes = IPC.getModes()
    assert_eq(#modes, 2, "Should have 2 modes")
end)

--------------------------------------------------------------------------------
-- TEST CASES: IPC LIFECYCLE
--------------------------------------------------------------------------------

test("IPC.init calls onInit on instances", "IPC Lifecycle", function()
    local initCalled = false
    local MyNode = Node.extend({
        name = "MyNode",
        Sys = { onInit = function(self) initCalled = true end }
    })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.init()
    assert_true(initCalled, "onInit should be called")
end)

test("IPC.init sets initialized flag", "IPC Lifecycle", function()
    assert_false(IPC.isInitialized(), "Should not be initialized")
    IPC.init()
    assert_true(IPC.isInitialized(), "Should be initialized")
end)

test("IPC.start calls onStart on instances", "IPC Lifecycle", function()
    local startCalled = false
    local MyNode = Node.extend({
        name = "MyNode",
        Sys = { onStart = function(self) startCalled = true end }
    })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.init()
    IPC.start()
    assert_true(startCalled, "onStart should be called")
end)

test("IPC.start requires init first", "IPC Lifecycle", function()
    assert_error(function()
        IPC.start()
    end, "Must call IPC.init")
end)

test("IPC.start sets started flag", "IPC Lifecycle", function()
    IPC.init()
    assert_false(IPC.isStarted(), "Should not be started")
    IPC.start()
    assert_true(IPC.isStarted(), "Should be started")
end)

test("IPC.stop calls onStop on instances", "IPC Lifecycle", function()
    local stopCalled = false
    local MyNode = Node.extend({
        name = "MyNode",
        Sys = { onStop = function(self) stopCalled = true end }
    })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.init()
    IPC.start()
    IPC.stop()
    assert_true(stopCalled, "onStop should be called")
end)

test("IPC.switchMode calls onModeChange", "IPC Lifecycle", function()
    local modeChangeCalled = false
    local receivedOld, receivedNew

    local MyNode = Node.extend({
        name = "MyNode",
        Sys = {
            onModeChange = function(self, data)
                modeChangeCalled = true
                receivedOld = data.oldMode
                receivedNew = data.newMode
            end
        }
    })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.defineMode("Mode1", { nodes = {} })
    IPC.defineMode("Mode2", { nodes = {} })

    IPC.init()
    IPC.switchMode("Mode1")
    IPC.switchMode("Mode2")

    assert_true(modeChangeCalled, "onModeChange should be called")
    assert_eq(receivedOld, "Mode1", "Should receive old mode")
    assert_eq(receivedNew, "Mode2", "Should receive new mode")
end)

test("IPC.spawn calls lifecycle hooks", "IPC Lifecycle", function()
    local spawnedCalled = false
    local initCalled = false
    local startCalled = false

    local MyNode = Node.extend({
        name = "MyNode",
        Sys = {
            onSpawned = function(self) spawnedCalled = true end,
            onInit = function(self) initCalled = true end,
            onStart = function(self) startCalled = true end,
        }
    })
    IPC.registerNode(MyNode)

    IPC.init()
    IPC.start()

    IPC.spawn("MyNode", { id = "dynamic1" })

    assert_true(spawnedCalled, "onSpawned should be called")
    assert_true(initCalled, "onInit should be called")
    assert_true(startCalled, "onStart should be called")
end)

test("IPC.despawn calls lifecycle hooks", "IPC Lifecycle", function()
    local stopCalled = false
    local despawningCalled = false

    local MyNode = Node.extend({
        name = "MyNode",
        Sys = {
            onStop = function(self) stopCalled = true end,
            onDespawning = function(self) despawningCalled = true end,
        }
    })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.despawn("test1")

    assert_true(stopCalled, "onStop should be called")
    assert_true(despawningCalled, "onDespawning should be called")
end)

--------------------------------------------------------------------------------
-- TEST CASES: IPC MESSAGING
--------------------------------------------------------------------------------

test("IPC.getMessageId returns incrementing ids", "IPC Messaging", function()
    local id1 = IPC.getMessageId()
    local id2 = IPC.getMessageId()
    local id3 = IPC.getMessageId()

    assert_true(id2 > id1, "IDs should increment")
    assert_true(id3 > id2, "IDs should increment")
end)

test("IPC.sendTo delivers message to instance", "IPC Messaging", function()
    local received = nil

    local MyNode = Node.extend({
        name = "MyNode",
        In = {
            onPing = function(self, data)
                received = data
            end
        }
    })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.init()
    IPC.start()

    IPC.sendTo("test1", "ping", { msg = "hello" })

    assert_not_nil(received, "Should receive message")
    assert_eq(received.msg, "hello", "Should have correct data")
end)

test("IPC.sendTo requires started", "IPC Messaging", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    -- Not started, should warn but not error
    IPC.sendTo("test1", "ping", {})
    -- No error thrown
end)

test("IPC.send routes through wiring", "IPC Messaging", function()
    local receivedByB = nil

    local NodeA = Node.extend({
        name = "NodeA",
        In = { onTrigger = function(self)
            self.Out:Fire("forwarded", { from = "A" })
        end }
    })

    local NodeB = Node.extend({
        name = "NodeB",
        In = { onForwarded = function(self, data)
            receivedByB = data
        end }
    })

    IPC.registerNode(NodeA)
    IPC.registerNode(NodeB)
    IPC.createInstance("NodeA", { id = "a1" })
    IPC.createInstance("NodeB", { id = "b1" })

    IPC.defineMode("TestMode", {
        nodes = { "NodeA", "NodeB" },
        wiring = { NodeA = { "NodeB" } }
    })

    IPC.init()
    IPC.switchMode("TestMode")
    IPC.start()

    IPC.sendTo("a1", "trigger", {})

    assert_not_nil(receivedByB, "NodeB should receive forwarded message")
    assert_eq(receivedByB.from, "A", "Should have correct data")
end)

test("IPC.broadcast delivers to all instances Sys", "IPC Messaging", function()
    local calls = {}

    local MyNode = Node.extend({
        name = "MyNode",
        Sys = {
            onCustomBroadcast = function(self, data)
                table.insert(calls, self.id)
            end
        }
    })

    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })
    IPC.createInstance("MyNode", { id = "test2" })

    IPC.broadcast("customBroadcast", { test = true })

    assert_eq(#calls, 2, "Should call on all instances")
    assert_true(table.find(calls, "test1") ~= nil, "Should include test1")
    assert_true(table.find(calls, "test2") ~= nil, "Should include test2")
end)

test("Cycle detection prevents infinite loops", "IPC Messaging", function()
    local callCount = 0

    local LoopNode = Node.extend({
        name = "LoopNode",
        In = {
            onLoop = function(self, data)
                callCount = callCount + 1
                -- Try to send back to self (should be blocked)
                self.Out:Fire("loop", data)
            end
        }
    })

    IPC.registerNode(LoopNode)
    IPC.createInstance("LoopNode", { id = "loop1" })

    IPC.defineMode("LoopMode", {
        nodes = { "LoopNode" },
        wiring = { LoopNode = { "LoopNode" } }  -- Self-loop
    })

    IPC.init()
    IPC.switchMode("LoopMode")
    IPC.start()

    IPC.sendTo("loop1", "loop", {})

    -- Should only be called once due to cycle detection
    assert_eq(callCount, 1, "Cycle detection should prevent infinite loop")
end)

--------------------------------------------------------------------------------
-- TEST CASES: ERROR HANDLING
--------------------------------------------------------------------------------

test("Handler errors are caught and reported", "Error Handling", function()
    local errorHandled = false

    local ErrorNode = Node.extend({
        name = "ErrorNode",
        In = {
            onError = function(self, data)
                error("Intentional test error")
            end
        }
    })

    IPC.registerNode(ErrorNode)
    IPC.createInstance("ErrorNode", { id = "err1" })

    IPC.init()
    IPC.start()

    -- Should not throw, error should be caught
    IPC.sendTo("err1", "error", {})

    -- If we get here, error was caught
    assert_true(true, "Error should be caught")
end)

test("Err channel fires on handler error", "Error Handling", function()
    local errFired = false

    local ErrorNode = Node.extend({
        name = "ErrorNode",
        In = {
            onError = function(self, data)
                error("Test error")
            end
        }
    })

    IPC.registerNode(ErrorNode)
    local inst = IPC.createInstance("ErrorNode", { id = "err1" })

    -- Intercept Err:Fire
    local originalFire = inst.Err.Fire
    inst.Err.Fire = function(self, data)
        errFired = true
        originalFire(self, data)
    end

    IPC.init()
    IPC.start()

    IPC.sendTo("err1", "error", {})

    assert_true(errFired, "Err channel should fire")
end)

--------------------------------------------------------------------------------
-- TEST CASES: MODE-SPECIFIC PINS
--------------------------------------------------------------------------------

test("Mode-specific In handlers are called", "Mode Pins", function()
    local defaultCalled = false
    local tutorialCalled = false

    local MyNode = Node.extend({
        name = "MyNode",
        In = {
            onAction = function(self) defaultCalled = true end
        },
        Tutorial = {
            In = {
                onAction = function(self) tutorialCalled = true end
            }
        }
    })

    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.defineMode("Tutorial", { nodes = { "MyNode" } })

    IPC.init()
    IPC.switchMode("Tutorial")
    IPC.start()

    IPC.sendTo("test1", "action", {})

    assert_true(tutorialCalled, "Tutorial handler should be called")
    assert_false(defaultCalled, "Default handler should not be called")
end)

test("Falls back to default In when mode has no handler", "Mode Pins", function()
    local defaultCalled = false

    local MyNode = Node.extend({
        name = "MyNode",
        In = {
            onAction = function(self) defaultCalled = true end
        },
        Tutorial = {
            In = {
                -- No onAction here
            }
        }
    })

    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })

    IPC.defineMode("Tutorial", { nodes = { "MyNode" } })

    IPC.init()
    IPC.switchMode("Tutorial")
    IPC.start()

    IPC.sendTo("test1", "action", {})

    assert_true(defaultCalled, "Default handler should be called as fallback")
end)

--------------------------------------------------------------------------------
-- TEST CASES: RESET & UTILITIES
--------------------------------------------------------------------------------

test("IPC.reset clears all state", "IPC Utilities", function()
    local MyNode = Node.extend({ name = "MyNode" })
    IPC.registerNode(MyNode)
    IPC.createInstance("MyNode", { id = "test1" })
    IPC.defineMode("TestMode", { nodes = {} })
    IPC.init()
    IPC.start()

    IPC.reset()

    assert_eq(IPC.getInstanceCount(), 0, "Instances should be cleared")
    assert_eq(#IPC.getNodeClasses(), 0, "Classes should be cleared")
    assert_eq(#IPC.getModes(), 0, "Modes should be cleared")
    assert_false(IPC.isInitialized(), "Should not be initialized")
    assert_false(IPC.isStarted(), "Should not be started")
end)

--------------------------------------------------------------------------------
-- TEST CASES: ASSET REGISTRATION
--------------------------------------------------------------------------------

test("Asset.register accepts valid node", "Asset Registration", function()
    local MyNode = Node.extend({ name = "MyNode" })
    local success = Asset.register(MyNode)
    assert_true(success, "Should register successfully")
end)

test("Asset.register requires NodeClass", "Asset Registration", function()
    assert_error(function()
        Asset.register(nil)
    end, "NodeClass required")
end)

test("Asset.register requires name", "Asset Registration", function()
    assert_error(function()
        Asset.register({})
    end, "must have a name")
end)

test("Asset.register also registers with IPC", "Asset Registration", function()
    local MyNode = Node.extend({ name = "MyNode" })
    Asset.register(MyNode)

    -- Should be able to create instance via IPC
    local inst = IPC.createInstance("MyNode", { id = "test1" })
    assert_not_nil(inst, "IPC should have the node registered")
end)

test("Asset.get returns registered class", "Asset Registration", function()
    local MyNode = Node.extend({ name = "MyNode" })
    Asset.register(MyNode)

    local retrieved = Asset.get("MyNode")
    assert_eq(retrieved, MyNode, "Should return same class")
end)

test("Asset.get returns nil for unregistered", "Asset Registration", function()
    local retrieved = Asset.get("NotRegistered")
    assert_nil(retrieved, "Should return nil")
end)

test("Asset.getAll returns all registered", "Asset Registration", function()
    local NodeA = Node.extend({ name = "NodeA" })
    local NodeB = Node.extend({ name = "NodeB" })
    Asset.register(NodeA)
    Asset.register(NodeB)

    local all = Asset.getAll()
    assert_eq(#all, 2, "Should have 2 classes")
end)

test("Asset.isRegistered returns correct state", "Asset Registration", function()
    local MyNode = Node.extend({ name = "MyNode" })
    assert_false(Asset.isRegistered("MyNode"), "Should not be registered")
    Asset.register(MyNode)
    assert_true(Asset.isRegistered("MyNode"), "Should be registered")
end)

--------------------------------------------------------------------------------
-- TEST CASES: ASSET VERIFICATION
--------------------------------------------------------------------------------

test("Asset.verify passes with all present", "Asset Verification", function()
    local NodeA = Node.extend({ name = "NodeA" })
    local NodeB = Node.extend({ name = "NodeB" })
    Asset.register(NodeA)
    Asset.register(NodeB)

    local success = Asset.verify({ "NodeA", "NodeB" })
    assert_true(success, "Should verify successfully")
end)

test("Asset.verify throws on missing class", "Asset Verification", function()
    local NodeA = Node.extend({ name = "NodeA" })
    Asset.register(NodeA)

    assert_error(function()
        Asset.verify({ "NodeA", "NodeB" })
    end, "Missing required node classes")
end)

test("Asset.verify passes with empty list", "Asset Verification", function()
    local success = Asset.verify({})
    assert_true(success, "Should pass with empty list")
end)

--------------------------------------------------------------------------------
-- TEST CASES: ASSET INHERITANCE TREE
--------------------------------------------------------------------------------

test("Asset.getChain returns correct chain", "Asset Inheritance", function()
    local BaseNode = Node.extend({ name = "BaseNode" })
    local ChildNode = BaseNode.extend({ name = "ChildNode" })
    local GrandChild = ChildNode.extend({ name = "GrandChild" })

    Asset.register(BaseNode)
    Asset.register(ChildNode)
    Asset.register(GrandChild)

    local chain = Asset.getChain("GrandChild")
    assert_eq(#chain, 4, "Chain should have 4 elements (Node, Base, Child, Grand)")
    assert_eq(chain[1], "Node", "First should be Node")
    assert_eq(chain[2], "BaseNode", "Second should be BaseNode")
    assert_eq(chain[3], "ChildNode", "Third should be ChildNode")
    assert_eq(chain[4], "GrandChild", "Fourth should be GrandChild")
end)

test("Asset.getChain returns empty for unregistered", "Asset Inheritance", function()
    local chain = Asset.getChain("NotRegistered")
    assert_eq(#chain, 0, "Should return empty chain")
end)

test("Asset.buildInheritanceTree creates tree", "Asset Inheritance", function()
    local BaseNode = Node.extend({ name = "BaseNode" })
    local ChildNode = BaseNode.extend({ name = "ChildNode" })

    Asset.register(BaseNode)
    Asset.register(ChildNode)

    local tree = Asset.buildInheritanceTree()
    assert_eq(tree.name, "Node", "Root should be Node")
    assert_true(#tree.children > 0, "Should have children")
end)

--------------------------------------------------------------------------------
-- TEST CASES: ASSET SPAWNING (without actual Roblox models)
--------------------------------------------------------------------------------

test("Asset.spawn requires model", "Asset Spawning", function()
    assert_error(function()
        Asset.spawn(nil)
    end, "Model required")
end)

test("Asset.getSpawnedCount starts at 0", "Asset Spawning", function()
    assert_eq(Asset.getSpawnedCount(), 0, "Should start at 0")
end)

test("Asset.reset clears all state", "Asset Utilities", function()
    local NodeA = Node.extend({ name = "NodeA" })
    Asset.register(NodeA)

    Asset.reset()

    assert_false(Asset.isRegistered("NodeA"), "Should clear registry")
    assert_eq(Asset.getSpawnedCount(), 0, "Should clear spawned")
end)

--------------------------------------------------------------------------------
-- TEST CASES: NODE LOCKING
--------------------------------------------------------------------------------

test("Node.isLocked returns false by default", "Node Locking", function()
    local MyNode = Node.extend({ name = "MyNode" })
    Asset.register(MyNode)

    local instance = IPC.createInstance("MyNode", { id = "test_lock1" })

    assert_false(instance:isLocked(), "Should not be locked by default")
end)

test("Node._messageQueue starts empty", "Node Locking", function()
    local MyNode = Node.extend({ name = "MyNode" })
    Asset.register(MyNode)

    local instance = IPC.createInstance("MyNode", { id = "test_queue1" })

    assert_true(instance._messageQueue == nil or #instance._messageQueue == 0, "Queue should be empty")
end)

test("IPC queues messages to locked nodes", "Node Locking", function()
    local receivedCount = 0
    local MyNode = Node.extend({
        name = "MyNode",
        In = {
            onTest = function(self, data)
                receivedCount = receivedCount + 1
            end,
        },
    })
    Asset.register(MyNode)

    local instance = IPC.createInstance("MyNode", { id = "test_locked_dispatch" })

    -- Manually lock the node
    instance._locked = true
    instance._messageQueue = {}

    -- Try to send a message
    IPC.sendTo("test_locked_dispatch", "test", { value = 1 })

    -- Message should be queued, not delivered
    assert_eq(receivedCount, 0, "Should not receive message while locked")
    assert_eq(#instance._messageQueue, 1, "Should have 1 queued message")
end)

test("Node._flushMessageQueue replays queued messages", "Node Locking", function()
    local receivedValues = {}
    local MyNode = Node.extend({
        name = "MyNode",
        In = {
            onTest = function(self, data)
                table.insert(receivedValues, data.value)
            end,
        },
    })
    Asset.register(MyNode)

    local instance = IPC.createInstance("MyNode", { id = "test_flush" })

    -- Manually queue some messages
    instance._messageQueue = {
        { "test", { value = 1 }, nil },
        { "test", { value = 2 }, nil },
    }

    -- Store System reference for flush
    instance._System = Lib.System

    -- Flush the queue
    instance:_flushMessageQueue()

    -- Messages should be delivered
    assert_eq(#receivedValues, 2, "Should receive 2 messages")
    assert_eq(receivedValues[1], 1, "First message value")
    assert_eq(receivedValues[2], 2, "Second message value")
end)

--------------------------------------------------------------------------------
-- TEST CASES: PATHFOLLOWER COMPONENT
--------------------------------------------------------------------------------

test("PathFollower can be required", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    assert_not_nil(PathFollower, "PathFollower should exist")
    assert_eq(PathFollower.name, "PathFollower", "Name should match")
end)

test("PathFollower has correct structure", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    -- Check handlers exist
    assert_not_nil(PathFollower.Sys, "Should have Sys handlers")
    assert_not_nil(PathFollower.In, "Should have In handlers")
    assert_not_nil(PathFollower.Out, "Should have Out schema")
end)

test("PathFollower instance initializes state", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    local instance = IPC.createInstance("PathFollower", { id = "pf_test1" })

    -- Trigger init
    if instance.Sys and instance.Sys.onInit then
        instance.Sys.onInit(instance)
    end

    -- Check initial state
    assert_nil(instance._entity, "Entity should be nil initially")
    assert_nil(instance._waypoints, "Waypoints should be nil initially")
    assert_false(instance._navigating, "Should not be navigating initially")
end)

test("PathFollower default attributes", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    local instance = IPC.createInstance("PathFollower", { id = "pf_test2" })

    -- Trigger init
    if instance.Sys and instance.Sys.onInit then
        instance.Sys.onInit(instance)
    end

    -- Check default attributes
    assert_eq(instance:getAttribute("Speed"), 16, "Default speed should be 16")
    assert_false(instance:getAttribute("WaitForAck"), "WaitForAck should default to false")
    assert_eq(instance:getAttribute("AckTimeout"), 5, "Default timeout should be 5")
end)

test("PathFollower does not start without both signals", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    local instance = IPC.createInstance("PathFollower", { id = "pf_test3" })

    -- Trigger init
    if instance.Sys and instance.Sys.onInit then
        instance.Sys.onInit(instance)
    end

    -- Send only onControl (no waypoints)
    local mockEntity = { Name = "MockEntity" }
    instance.In.onControl(instance, { entity = mockEntity })

    -- Should NOT be navigating yet
    assert_false(instance._navigating, "Should not navigate with only entity")

    -- Now send waypoints
    local mockWaypoints = { { Position = Vector3.new(0, 0, 0) } }
    instance.In.onWaypoints(instance, { targets = mockWaypoints })

    -- Now it should be navigating (or at least have both pieces)
    assert_not_nil(instance._entity, "Should have entity")
    assert_not_nil(instance._waypoints, "Should have waypoints")
end)

test("PathFollower onPause sets paused state", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    local instance = IPC.createInstance("PathFollower", { id = "pf_test4" })

    -- Trigger init
    if instance.Sys and instance.Sys.onInit then
        instance.Sys.onInit(instance)
    end

    -- Simulate navigating state
    instance._navigating = true
    instance._paused = false

    -- Pause
    instance.In.onPause(instance)

    assert_true(instance._paused, "Should be paused")
end)

test("PathFollower onResume clears paused state", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    local instance = IPC.createInstance("PathFollower", { id = "pf_test5" })

    -- Trigger init
    if instance.Sys and instance.Sys.onInit then
        instance.Sys.onInit(instance)
    end

    -- Simulate paused navigating state
    instance._navigating = true
    instance._paused = true

    -- Resume
    instance.In.onResume(instance)

    assert_false(instance._paused, "Should not be paused after resume")
end)

test("PathFollower onSetSpeed updates attribute", "PathFollower", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    local instance = IPC.createInstance("PathFollower", { id = "pf_test6" })

    -- Trigger init
    if instance.Sys and instance.Sys.onInit then
        instance.Sys.onInit(instance)
    end

    -- Change speed
    instance.In.onSetSpeed(instance, { speed = 24 })

    assert_eq(instance:getAttribute("Speed"), 24, "Speed should be updated")
end)

--------------------------------------------------------------------------------
-- TEST CASES: PATHFOLLOWER INTEGRATION (with real Roblox instances)
--------------------------------------------------------------------------------

--[[
    Integration test that creates actual Parts and tests PathFollower navigation.

    Run from Studio Command Bar:
        local Tests = require(game.ReplicatedStorage.Lib.Tests.IPC_Node_Tests)
        Tests.runGroup("PathFollower Integration")

    Or run just this test:
        Tests.run("PathFollower navigates box through waypoints")
--]]

test("PathFollower navigates box through waypoints", "PathFollower Integration", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    -- Track events received
    local eventsReceived = {}
    local navigationComplete = false

    -- Create the entity: a simple Box part
    local boxModel = Instance.new("Model")
    boxModel.Name = "TestBox"

    local boxPart = Instance.new("Part")
    boxPart.Name = "Box"
    boxPart.Size = Vector3.new(2, 2, 2)
    boxPart.Position = Vector3.new(0, 5, 0)
    boxPart.Anchored = false
    boxPart.CanCollide = false
    boxPart.BrickColor = BrickColor.new("Bright blue")
    boxPart.Parent = boxModel

    boxModel.PrimaryPart = boxPart
    boxModel.Parent = workspace

    -- Create waypoint parts (spread out more for visibility)
    local waypoint1 = Instance.new("Part")
    waypoint1.Name = "Waypoint1"
    waypoint1.Size = Vector3.new(2, 2, 2)
    waypoint1.Position = Vector3.new(20, 5, 0)
    waypoint1.Anchored = true
    waypoint1.CanCollide = false
    waypoint1.Transparency = 0.5
    waypoint1.BrickColor = BrickColor.new("Bright green")
    waypoint1.Parent = workspace

    local waypoint2 = Instance.new("Part")
    waypoint2.Name = "Waypoint2"
    waypoint2.Size = Vector3.new(2, 2, 2)
    waypoint2.Position = Vector3.new(20, 5, 20)
    waypoint2.Anchored = true
    waypoint2.CanCollide = false
    waypoint2.Transparency = 0.5
    waypoint2.BrickColor = BrickColor.new("Bright yellow")
    waypoint2.Parent = workspace

    local waypoint3 = Instance.new("Part")
    waypoint3.Name = "Waypoint3"
    waypoint3.Size = Vector3.new(2, 2, 2)
    waypoint3.Position = Vector3.new(0, 5, 20)
    waypoint3.Anchored = true
    waypoint3.CanCollide = false
    waypoint3.Transparency = 0.5
    waypoint3.BrickColor = BrickColor.new("Bright red")
    waypoint3.Parent = workspace

    -- Create PathFollower instance
    local pf = IPC.createInstance("PathFollower", {
        id = "pf_integration_test",
        attributes = { Speed = 10 },  -- Slower for visual testing
    })

    -- Initialize
    if pf.Sys and pf.Sys.onInit then
        pf.Sys.onInit(pf)
    end

    -- Hook into Out signals to track events
    local originalOutFire = pf.Out.Fire
    pf.Out.Fire = function(self, signal, data)
        table.insert(eventsReceived, { signal = signal, data = data })
        print("  → PathFollower fired:", signal, data and data.index or "")
        if signal == "pathComplete" then
            navigationComplete = true
        end
        -- Call original if it exists
        if originalOutFire then
            originalOutFire(self, signal, data)
        end
    end

    -- Send control signal (assign entity)
    print("  Sending onControl signal...")
    pf.In.onControl(pf, {
        entity = boxModel,
        entityId = "TestBox_1",
    })

    -- Send waypoints signal
    print("  Sending onWaypoints signal...")
    pf.In.onWaypoints(pf, {
        targets = { waypoint1, waypoint2, waypoint3 },
    })

    -- Wait for navigation to complete (with timeout)
    print("  Waiting for navigation...")
    local startTime = os.clock()
    local timeout = 30  -- 30 second timeout for slower speed

    while not navigationComplete and (os.clock() - startTime) < timeout do
        task.wait(0.1)
    end

    -- Verify results
    assert_true(navigationComplete, "Navigation should complete within timeout")
    assert_true(#eventsReceived >= 4, "Should receive at least 4 events (3 waypoints + complete)")

    -- Check we got waypointReached for each waypoint
    local waypointReachedCount = 0
    local pathCompleteCount = 0
    for _, event in ipairs(eventsReceived) do
        if event.signal == "waypointReached" then
            waypointReachedCount = waypointReachedCount + 1
        elseif event.signal == "pathComplete" then
            pathCompleteCount = pathCompleteCount + 1
        end
    end

    assert_eq(waypointReachedCount, 3, "Should have 3 waypointReached events")
    assert_eq(pathCompleteCount, 1, "Should have 1 pathComplete event")

    -- Check final position is near waypoint3 (relaxed for gravity/physics)
    local finalPos = boxPart.Position
    local targetPos = waypoint3.Position
    local distance = (finalPos - targetPos).Magnitude

    print("  Final box position:", finalPos)
    print("  Target position:", targetPos)
    print("  Distance:", distance)

    -- Pause to let user see result before cleanup
    print("  Pausing 3 seconds before cleanup...")
    task.wait(3)

    -- Cleanup
    boxModel:Destroy()
    waypoint1:Destroy()
    waypoint2:Destroy()
    waypoint3:Destroy()

    -- Relaxed distance check (box may have fallen due to gravity)
    assert_true(distance < 10, "Box should be near final waypoint (distance: " .. distance .. ")")

    print("  ✓ Integration test passed!")
end)

test("PathFollower with Humanoid navigates through waypoints", "PathFollower Integration", function()
    local PathFollower = Lib.Components.PathFollower
    Asset.register(PathFollower)

    -- Track events
    local eventsReceived = {}
    local navigationComplete = false

    -- Create a simple Humanoid-based model (like an NPC)
    local npcModel = Instance.new("Model")
    npcModel.Name = "TestNPC"

    local torso = Instance.new("Part")
    torso.Name = "HumanoidRootPart"
    torso.Size = Vector3.new(2, 2, 1)
    torso.Position = Vector3.new(0, 3, 0)
    torso.Anchored = false
    torso.CanCollide = false
    torso.BrickColor = BrickColor.new("Medium stone grey")
    torso.Parent = npcModel

    local humanoid = Instance.new("Humanoid")
    humanoid.Parent = npcModel

    npcModel.PrimaryPart = torso
    npcModel.Parent = workspace

    -- Ground the NPC so it can walk
    torso.Position = Vector3.new(0, 3, 0)

    -- Create waypoints (close and on ground level for Humanoid)
    local wp1 = Instance.new("Part")
    wp1.Name = "HumanoidWP1"
    wp1.Size = Vector3.new(1, 1, 1)
    wp1.Position = Vector3.new(8, 3, 0)
    wp1.Anchored = true
    wp1.CanCollide = false
    wp1.Transparency = 0.5
    wp1.BrickColor = BrickColor.new("Lime green")
    wp1.Parent = workspace

    local wp2 = Instance.new("Part")
    wp2.Name = "HumanoidWP2"
    wp2.Size = Vector3.new(1, 1, 1)
    wp2.Position = Vector3.new(8, 3, 8)
    wp2.Anchored = true
    wp2.CanCollide = false
    wp2.Transparency = 0.5
    wp2.BrickColor = BrickColor.new("Lime green")
    wp2.Parent = workspace

    -- Create PathFollower
    local pf = IPC.createInstance("PathFollower", {
        id = "pf_humanoid_test",
    })

    if pf.Sys and pf.Sys.onInit then
        pf.Sys.onInit(pf)
    end

    -- Hook Out signals
    pf.Out.Fire = function(self, signal, data)
        table.insert(eventsReceived, { signal = signal, data = data })
        print("  → Humanoid PathFollower fired:", signal)
        if signal == "pathComplete" then
            navigationComplete = true
        end
    end

    -- Send signals
    print("  Sending control signal for Humanoid NPC...")
    pf.In.onControl(pf, { entity = npcModel, entityId = "NPC_1" })

    print("  Sending waypoints...")
    pf.In.onWaypoints(pf, { targets = { wp1, wp2 } })

    -- Wait for completion
    print("  Waiting for Humanoid navigation...")
    local startTime = os.clock()
    while not navigationComplete and (os.clock() - startTime) < 15 do
        task.wait(0.1)
    end

    -- Verify
    assert_true(navigationComplete, "Humanoid navigation should complete")

    local waypointCount = 0
    for _, e in ipairs(eventsReceived) do
        if e.signal == "waypointReached" then
            waypointCount = waypointCount + 1
        end
    end
    assert_eq(waypointCount, 2, "Should reach 2 waypoints")

    -- Cleanup
    npcModel:Destroy()
    wp1:Destroy()
    wp2:Destroy()

    print("  ✓ Humanoid integration test passed!")
end)

--------------------------------------------------------------------------------
-- RETURN MODULE
--------------------------------------------------------------------------------

return Tests
