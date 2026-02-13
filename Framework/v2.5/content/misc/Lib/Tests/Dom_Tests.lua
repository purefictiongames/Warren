--[[
    Warren DOM Architecture v2.5
    Dom Test Suite

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar (after game runs):

    ```lua
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.Dom.runAll()
    ```

    Or run specific test groups:

    ```lua
    Tests.Dom.runGroup("createElement")
    Tests.Dom.runGroup("Tree Mutation")
    Tests.Dom.runGroup("Attributes")
    Tests.Dom.runGroup("Classes")
    Tests.Dom.runGroup("querySelector")
    Tests.Dom.runGroup("Clone")
    Tests.Dom.runGroup("Bridge")
    ```
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Dom = Lib.Dom
local Node = Lib.Node

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

local function test(name, group, fn)
    table.insert(testCases, { name = name, group = group, fn = fn })
    testGroups[group] = testGroups[group] or {}
    table.insert(testGroups[group], name)
end

local function runTest(testCase)
    -- Reset DOM state before each test
    Dom._reset()

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
    print("  Warren DOM Test Suite")
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
    print("  Warren DOM:", group)
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
-- createElement TESTS
--------------------------------------------------------------------------------

test("createElement returns a DomNode", "createElement", function()
    local el = Dom.createElement("Part")
    assert_true(Dom.isDomNode(el), "Should be a DomNode")
end)

test("createElement sets type", "createElement", function()
    local el = Dom.createElement("Room")
    assert_eq(el._type, "Room", "Type should be Room")
end)

test("createElement sets id from attributes", "createElement", function()
    local el = Dom.createElement("Part", { id = "myPart" })
    assert_eq(el._id, "myPart", "ID should be myPart")
end)

test("createElement auto-generates id when not provided", "createElement", function()
    local el = Dom.createElement("Part")
    assert_not_nil(el._id, "Should have auto-generated ID")
    assert_true(type(el._id) == "string", "ID should be a string")
end)

test("createElement sets class from attributes", "createElement", function()
    local el = Dom.createElement("Part", { class = "brick_red weathered" })
    assert_eq(el._classes, "brick_red weathered", "Classes should be set")
end)

test("createElement stores other attributes", "createElement", function()
    local el = Dom.createElement("Part", { width = 20, height = 12 })
    assert_eq(el._attributes.width, 20, "Width attribute")
    assert_eq(el._attributes.height, 12, "Height attribute")
end)

test("createElement does not store id/class as attributes", "createElement", function()
    local el = Dom.createElement("Part", { id = "x", class = "y", width = 5 })
    assert_nil(el._attributes.id, "id should not be in attributes")
    assert_nil(el._attributes.class, "class should not be in attributes")
    assert_eq(el._attributes.width, 5, "width should be in attributes")
end)

test("createElement registers in tree for lookup", "createElement", function()
    local el = Dom.createElement("Part", { id = "lookup_test" })
    local found = Dom.getElementById("lookup_test")
    assert_eq(found, el, "Should find element by ID")
end)

test("createFragment returns Fragment type", "createElement", function()
    local frag = Dom.createFragment()
    assert_eq(frag._type, "Fragment", "Type should be Fragment")
end)

--------------------------------------------------------------------------------
-- TREE MUTATION TESTS
--------------------------------------------------------------------------------

test("appendChild sets parent-child relationship", "Tree Mutation", function()
    local parent = Dom.createElement("Room", { id = "room1" })
    local child = Dom.createElement("Light", { id = "light1" })

    Dom.appendChild(parent, child)

    assert_eq(child._parent, parent, "Child's parent should be room")
    assert_eq(#parent._children, 1, "Parent should have 1 child")
    assert_eq(parent._children[1], child, "First child should be light")
end)

test("appendChild maintains order", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local a = Dom.createElement("Part", { id = "a" })
    local b = Dom.createElement("Part", { id = "b" })
    local c = Dom.createElement("Part", { id = "c" })

    Dom.appendChild(parent, a)
    Dom.appendChild(parent, b)
    Dom.appendChild(parent, c)

    local children = Dom.getChildren(parent)
    assert_eq(#children, 3, "Should have 3 children")
    assert_eq(children[1]._id, "a", "First child")
    assert_eq(children[2]._id, "b", "Second child")
    assert_eq(children[3]._id, "c", "Third child")
end)

test("removeChild detaches from parent", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local child = Dom.createElement("Light")

    Dom.appendChild(parent, child)
    assert_eq(#parent._children, 1, "Should have 1 child before remove")

    local removed = Dom.removeChild(parent, child)
    assert_eq(removed, child, "Should return removed child")
    assert_eq(#parent._children, 0, "Should have 0 children after remove")
    assert_nil(child._parent, "Child parent should be nil")
end)

test("removeChild returns nil for non-child", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local other = Dom.createElement("Light")

    local result = Dom.removeChild(parent, other)
    assert_nil(result, "Should return nil when not a child")
end)

test("insertBefore places child at correct position", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local a = Dom.createElement("Part", { id = "a" })
    local b = Dom.createElement("Part", { id = "b" })
    local c = Dom.createElement("Part", { id = "c" })

    Dom.appendChild(parent, a)
    Dom.appendChild(parent, c)
    Dom.insertBefore(parent, b, c)

    local children = Dom.getChildren(parent)
    assert_eq(#children, 3, "Should have 3 children")
    assert_eq(children[1]._id, "a", "First child should be a")
    assert_eq(children[2]._id, "b", "Second child should be b (inserted)")
    assert_eq(children[3]._id, "c", "Third child should be c")
end)

test("replaceChild swaps old for new", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local a = Dom.createElement("Part", { id = "a" })
    local b = Dom.createElement("Part", { id = "b" })
    local replacement = Dom.createElement("Part", { id = "r" })

    Dom.appendChild(parent, a)
    Dom.appendChild(parent, b)

    local old = Dom.replaceChild(parent, replacement, a)
    assert_eq(old, a, "Should return old child")

    local children = Dom.getChildren(parent)
    assert_eq(#children, 2, "Should still have 2 children")
    assert_eq(children[1]._id, "r", "First child should be replacement")
    assert_eq(children[2]._id, "b", "Second child should be b")
end)

test("appendChild with fragment transfers children", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local frag = Dom.createFragment()
    local a = Dom.createElement("Part", { id = "fa" })
    local b = Dom.createElement("Part", { id = "fb" })

    Dom.appendChild(frag, a)
    Dom.appendChild(frag, b)
    Dom.appendChild(parent, frag)

    local children = Dom.getChildren(parent)
    assert_eq(#children, 2, "Should have 2 children from fragment")
    assert_eq(children[1]._id, "fa", "First from fragment")
    assert_eq(children[2]._id, "fb", "Second from fragment")
end)

test("appendChild moves child from old parent", "Tree Mutation", function()
    local parent1 = Dom.createElement("Room", { id = "p1" })
    local parent2 = Dom.createElement("Room", { id = "p2" })
    local child = Dom.createElement("Part", { id = "ch" })

    Dom.appendChild(parent1, child)
    assert_eq(#parent1._children, 1, "Parent1 has child")

    Dom.appendChild(parent2, child)
    assert_eq(#parent1._children, 0, "Parent1 lost child")
    assert_eq(#parent2._children, 1, "Parent2 gained child")
    assert_eq(child._parent, parent2, "Child parent is now parent2")
end)

test("getParent returns correct parent", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local child = Dom.createElement("Part")
    Dom.appendChild(parent, child)
    assert_eq(Dom.getParent(child), parent, "getParent returns parent")
end)

test("getChildren returns ordered children", "Tree Mutation", function()
    local parent = Dom.createElement("Room")
    local a = Dom.createElement("Part", { id = "x1" })
    local b = Dom.createElement("Part", { id = "x2" })
    Dom.appendChild(parent, a)
    Dom.appendChild(parent, b)

    local children = Dom.getChildren(parent)
    assert_eq(#children, 2, "Two children")
    assert_eq(children[1]._id, "x1", "First child")
    assert_eq(children[2]._id, "x2", "Second child")
end)

test("getDescendants returns depth-first", "Tree Mutation", function()
    local root = Dom.createElement("Root", { id = "root" })
    local a = Dom.createElement("A", { id = "a" })
    local b = Dom.createElement("B", { id = "b" })
    local a1 = Dom.createElement("A1", { id = "a1" })
    local a2 = Dom.createElement("A2", { id = "a2" })

    Dom.appendChild(root, a)
    Dom.appendChild(root, b)
    Dom.appendChild(a, a1)
    Dom.appendChild(a, a2)

    local desc = Dom.getDescendants(root)
    assert_eq(#desc, 4, "Should have 4 descendants")
    assert_eq(desc[1]._id, "a", "First: a")
    assert_eq(desc[2]._id, "a1", "Second: a1 (depth-first)")
    assert_eq(desc[3]._id, "a2", "Third: a2")
    assert_eq(desc[4]._id, "b", "Fourth: b")
end)

--------------------------------------------------------------------------------
-- ATTRIBUTE TESTS
--------------------------------------------------------------------------------

test("setAttribute/getAttribute round-trip", "Attributes", function()
    local el = Dom.createElement("Part")
    Dom.setAttribute(el, "color", "red")
    assert_eq(Dom.getAttribute(el, "color"), "red", "Should get red")
end)

test("getAttribute returns nil for missing key", "Attributes", function()
    local el = Dom.createElement("Part")
    assert_nil(Dom.getAttribute(el, "nonexistent"), "Should be nil")
end)

test("removeAttribute removes key", "Attributes", function()
    local el = Dom.createElement("Part", { color = "blue" })
    Dom.removeAttribute(el, "color")
    assert_nil(Dom.getAttribute(el, "color"), "Should be nil after remove")
end)

test("hasAttribute returns true for existing", "Attributes", function()
    local el = Dom.createElement("Part", { size = 10 })
    assert_true(Dom.hasAttribute(el, "size"), "Should have size")
end)

test("hasAttribute returns false for missing", "Attributes", function()
    local el = Dom.createElement("Part")
    assert_false(Dom.hasAttribute(el, "missing"), "Should not have missing")
end)

test("setAttribute overwrites existing value", "Attributes", function()
    local el = Dom.createElement("Part", { x = 1 })
    Dom.setAttribute(el, "x", 2)
    assert_eq(Dom.getAttribute(el, "x"), 2, "Should be updated to 2")
end)

--------------------------------------------------------------------------------
-- CLASS TESTS
--------------------------------------------------------------------------------

test("addClass adds a class", "Classes", function()
    local el = Dom.createElement("Part")
    Dom.addClass(el, "brick_red")
    assert_true(Dom.hasClass(el, "brick_red"), "Should have class")
end)

test("addClass no-op if already present", "Classes", function()
    local el = Dom.createElement("Part", { class = "brick_red" })
    Dom.addClass(el, "brick_red")
    assert_eq(el._classes, "brick_red", "Should not duplicate")
end)

test("removeClass removes a class", "Classes", function()
    local el = Dom.createElement("Part", { class = "a b c" })
    Dom.removeClass(el, "b")
    assert_false(Dom.hasClass(el, "b"), "Should not have b")
    assert_true(Dom.hasClass(el, "a"), "Should still have a")
    assert_true(Dom.hasClass(el, "c"), "Should still have c")
end)

test("toggleClass adds when absent", "Classes", function()
    local el = Dom.createElement("Part")
    local result = Dom.toggleClass(el, "active")
    assert_true(result, "Should return true (added)")
    assert_true(Dom.hasClass(el, "active"), "Should now have class")
end)

test("toggleClass removes when present", "Classes", function()
    local el = Dom.createElement("Part", { class = "active" })
    local result = Dom.toggleClass(el, "active")
    assert_false(result, "Should return false (removed)")
    assert_false(Dom.hasClass(el, "active"), "Should not have class")
end)

test("hasClass returns false for empty", "Classes", function()
    local el = Dom.createElement("Part")
    assert_false(Dom.hasClass(el, "anything"), "No classes at all")
end)

test("getClasses returns array of class names", "Classes", function()
    local el = Dom.createElement("Part", { class = "a b c" })
    local classes = Dom.getClasses(el)
    assert_eq(#classes, 3, "Should have 3 classes")
    assert_eq(classes[1], "a", "First class")
    assert_eq(classes[2], "b", "Second class")
    assert_eq(classes[3], "c", "Third class")
end)

test("getClasses returns empty for no classes", "Classes", function()
    local el = Dom.createElement("Part")
    local classes = Dom.getClasses(el)
    assert_eq(#classes, 0, "Should have 0 classes")
end)

--------------------------------------------------------------------------------
-- querySelector TESTS
--------------------------------------------------------------------------------

test("querySelector #id finds by ID", "querySelector", function()
    local el = Dom.createElement("Part", { id = "target" })
    local found = Dom.querySelector("#target")
    assert_eq(found, el, "Should find by #id")
end)

test("querySelector #id returns nil for missing", "querySelector", function()
    local found = Dom.querySelector("#nonexistent")
    assert_nil(found, "Should return nil")
end)

test("querySelector .class finds by class", "querySelector", function()
    Dom.createElement("Part", { id = "other" })
    local el = Dom.createElement("Part", { id = "target", class = "special" })
    local found = Dom.querySelector(".special")
    assert_eq(found, el, "Should find by .class")
end)

test("querySelector .class returns nil for missing", "querySelector", function()
    Dom.createElement("Part")
    local found = Dom.querySelector(".nonexistent")
    assert_nil(found, "Should return nil")
end)

test("querySelector Type finds by type", "querySelector", function()
    Dom.createElement("Part", { id = "p1" })
    local room = Dom.createElement("Room", { id = "r1" })
    local found = Dom.querySelector("Room")
    assert_eq(found, room, "Should find by type")
end)

test("querySelectorAll returns all matches", "querySelector", function()
    Dom.createElement("Part", { id = "p1", class = "wall" })
    Dom.createElement("Part", { id = "p2", class = "wall" })
    Dom.createElement("Light", { id = "l1" })

    local walls = Dom.querySelectorAll(".wall")
    assert_eq(#walls, 2, "Should find 2 walls")

    local parts = Dom.querySelectorAll("Part")
    assert_eq(#parts, 2, "Should find 2 Parts")

    local lights = Dom.querySelectorAll("Light")
    assert_eq(#lights, 1, "Should find 1 Light")
end)

test("querySelectorAll #id returns 0 or 1", "querySelector", function()
    Dom.createElement("Part", { id = "unique" })
    local results = Dom.querySelectorAll("#unique")
    assert_eq(#results, 1, "Should find exactly 1")

    local empty = Dom.querySelectorAll("#missing")
    assert_eq(#empty, 0, "Should find 0")
end)

test("querySelector empty string returns nil", "querySelector", function()
    assert_nil(Dom.querySelector(""), "Empty selector")
    assert_nil(Dom.querySelector(nil), "Nil selector")
end)

test("getElementsByClassName finds multiple", "querySelector", function()
    Dom.createElement("Part", { class = "ambient" })
    Dom.createElement("Light", { class = "ambient bright" })
    Dom.createElement("Part", { class = "bright" })

    local ambients = Dom.getElementsByClassName("ambient")
    assert_eq(#ambients, 2, "Should find 2 ambient elements")
end)

--------------------------------------------------------------------------------
-- CLONE TESTS
--------------------------------------------------------------------------------

test("cloneNode shallow creates new node with same attributes", "Clone", function()
    local el = Dom.createElement("Part", { id = "src", class = "wall", width = 10 })
    local cloned = Dom.cloneNode(el)

    assert_true(cloned._id ~= el._id, "Should have new ID")
    assert_eq(cloned._type, "Part", "Same type")
    assert_eq(cloned._classes, "wall", "Same classes")
    assert_eq(Dom.getAttribute(cloned, "width"), 10, "Same attributes")
end)

test("cloneNode shallow does not clone children", "Clone", function()
    local parent = Dom.createElement("Room")
    local child = Dom.createElement("Part")
    Dom.appendChild(parent, child)

    local cloned = Dom.cloneNode(parent)
    assert_eq(#cloned._children, 0, "Shallow clone has no children")
end)

test("cloneNode deep clones children", "Clone", function()
    local parent = Dom.createElement("Room", { id = "pClone" })
    local a = Dom.createElement("Part", { id = "aClone" })
    local b = Dom.createElement("Part", { id = "bClone" })
    Dom.appendChild(parent, a)
    Dom.appendChild(parent, b)

    local cloned = Dom.cloneNode(parent, true)
    assert_eq(#cloned._children, 2, "Deep clone has 2 children")
    assert_true(cloned._children[1]._id ~= "aClone", "Child has new ID")
    assert_true(cloned._children[2]._id ~= "bClone", "Child has new ID")
    assert_eq(cloned._children[1]._type, "Part", "Child has same type")
end)

test("cloneNode deep clones grandchildren", "Clone", function()
    local root = Dom.createElement("Root")
    local mid = Dom.createElement("Mid")
    local leaf = Dom.createElement("Leaf", { class = "deep" })
    Dom.appendChild(root, mid)
    Dom.appendChild(mid, leaf)

    local cloned = Dom.cloneNode(root, true)
    assert_eq(#cloned._children, 1, "Has cloned mid")
    assert_eq(#cloned._children[1]._children, 1, "Has cloned leaf")
    assert_eq(cloned._children[1]._children[1]._classes, "deep", "Leaf class preserved")
end)

test("cloneNode is detached from tree", "Clone", function()
    local parent = Dom.createElement("Room")
    local child = Dom.createElement("Part")
    Dom.appendChild(parent, child)

    local cloned = Dom.cloneNode(child)
    assert_nil(cloned._parent, "Clone should have no parent")
    assert_eq(#parent._children, 1, "Original parent unchanged")
end)

--------------------------------------------------------------------------------
-- BRIDGE TESTS
--------------------------------------------------------------------------------

test("wrapNode creates DomNode from Warren Node", "Bridge", function()
    -- Create a minimal Warren Node (without IPC/CollectionService)
    local warrenNode = {
        id = "test_node_1",
        class = "TestComponent",
        _attributes = { health = 100 },
        model = nil,
    }

    local domNode = Dom.wrapNode(warrenNode)
    assert_true(Dom.isDomNode(domNode), "Should be DomNode")
    assert_eq(domNode._id, "test_node_1", "ID from Warren Node")
    assert_eq(domNode._type, "TestComponent", "Type from class")
    assert_eq(Dom.getAttribute(domNode, "health"), 100, "Attributes copied")
end)

test("wrapNode stores backing reference", "Bridge", function()
    local warrenNode = {
        id = "test_node_2",
        class = "Foo",
        _attributes = {},
        model = nil,
    }

    local domNode = Dom.wrapNode(warrenNode)
    assert_eq(Dom.getBackingNode(domNode), warrenNode, "Should reference Warren Node")
end)

test("getBackingInstance returns nil when no instance", "Bridge", function()
    local el = Dom.createElement("Part")
    assert_nil(Dom.getBackingInstance(el), "No backing instance")
end)

test("getBackingNode returns nil for pure DOM elements", "Bridge", function()
    local el = Dom.createElement("Part")
    assert_nil(Dom.getBackingNode(el), "No backing node")
end)

test("getElementById finds wrapped nodes", "Bridge", function()
    local warrenNode = {
        id = "bridged_node",
        class = "Test",
        _attributes = {},
        model = nil,
    }

    local domNode = Dom.wrapNode(warrenNode)
    local found = Dom.getElementById("bridged_node")
    assert_eq(found, domNode, "Should find wrapped node by ID")
end)

--------------------------------------------------------------------------------
-- LIFECYCLE TESTS
--------------------------------------------------------------------------------

test("mount/unmount sets mounted flag", "Lifecycle", function()
    local el = Dom.createElement("Part")
    assert_false(el._mounted, "Should start unmounted")

    Dom.mount(el)
    assert_true(el._mounted, "Should be mounted")

    Dom.unmount(el)
    assert_false(el._mounted, "Should be unmounted")
end)

--------------------------------------------------------------------------------
-- isDomNode TESTS
--------------------------------------------------------------------------------

test("isDomNode returns true for DomNodes", "isDomNode", function()
    local el = Dom.createElement("Part")
    assert_true(Dom.isDomNode(el), "createElement result is DomNode")
end)

test("isDomNode returns false for plain tables", "isDomNode", function()
    assert_false(Dom.isDomNode({}), "Empty table is not DomNode")
    assert_false(Dom.isDomNode({ _id = "x" }), "Partial table is not DomNode")
end)

test("isDomNode returns false for non-tables", "isDomNode", function()
    assert_false(Dom.isDomNode("string"), "String")
    assert_false(Dom.isDomNode(123), "Number")
    assert_false(Dom.isDomNode(nil), "Nil")
    assert_false(Dom.isDomNode(true), "Boolean")
end)

return Tests
