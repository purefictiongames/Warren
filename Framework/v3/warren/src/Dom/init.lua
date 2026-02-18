--[[
    Warren DOM Architecture v2.5
    Dom/init.lua - Public API Surface

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Warren.dom is the centralized API for working with the DOM tree. It provides
    a web-familiar interface (getElementById, appendChild, setAttribute, etc.)
    built on top of Warren's existing Node and ClassResolver systems.

    The DOM layer is purely additive. No existing modules are modified.
    New code uses Warren.dom.*. Old code keeps working. Dom.wrapNode() bridges
    the two worlds.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Warren = require(game.ReplicatedStorage.Warren)
    local Dom = Warren.Dom

    -- Create elements
    local room = Dom.createElement("Room", { width = 20, height = 12 })
    local light = Dom.createElement("Light", { brightness = 0.8 })

    -- Build tree
    Dom.appendChild(room, light)

    -- Query
    local found = Dom.getElementById("myRoom")
    local lights = Dom.getElementsByClassName("ambient")

    -- Attributes
    Dom.setAttribute(room, "wallThickness", 2)
    local w = Dom.getAttribute(room, "wallThickness")

    -- Classes
    Dom.addClass(room, "dark")
    Dom.hasClass(room, "dark")  -- true

    -- Bridge: wrap existing Warren Node
    local domNode = Dom.wrapNode(existingWarrenNode)
    ```
]]

local DomNode = require(script.DomNode)
local DomTree = require(script.DomTree)
local Renderer = require(script.Renderer)

local Dom = {}

-- Sub-modules exposed for game-level code (e.g. DomBuilder)
Dom.StyleBridge = require(script.StyleBridge)
Dom.Canvas = require(script.Canvas)
Dom.VoxelBuffer = require(script.VoxelBuffer)

--------------------------------------------------------------------------------
-- ELEMENT CREATION
--------------------------------------------------------------------------------

--[[
    Create a new DOM element.

    @param elementType string - Element type ("Part", "Room", "Light", etc.)
    @param attributes table? - Initial attributes (id, class handled specially)
    @return table - DomNode handle
]]
function Dom.createElement(elementType, attributes)
    attributes = attributes or {}

    -- Extract reserved fields
    local id = attributes.id
    local classes = attributes.class or ""
    local cleanAttrs = {}
    for k, v in pairs(attributes) do
        if k ~= "id" and k ~= "class" then
            cleanAttrs[k] = v
        end
    end

    local node = DomNode.new({
        id = id,
        type = elementType,
        classes = classes,
        attributes = cleanAttrs,
    })

    DomTree.addNode(node)
    return node
end

--[[
    Create a document fragment (a parentless container for batching).

    Children of a fragment are transferred to the target when appended.

    @return table - DomNode handle with type "Fragment"
]]
function Dom.createFragment()
    local node = DomNode.new({
        type = "Fragment",
    })
    DomTree.addNode(node)
    return node
end

--------------------------------------------------------------------------------
-- TREE TRAVERSAL
--------------------------------------------------------------------------------

--[[
    Find a DOM element by its ID.

    @param id string - The element ID
    @return table? - DomNode or nil
]]
function Dom.getElementById(id)
    return DomTree.getNode(id)
end

--[[
    Find all DOM elements with a given class name.

    @param className string - Class name to search for
    @return table - Array of matching DomNodes
]]
function Dom.getElementsByClassName(className)
    local results = {}
    for _, nodeId in ipairs(DomTree.getAllIds()) do
        local node = DomTree.getNode(nodeId)
        if node and Dom.hasClass(node, className) then
            table.insert(results, node)
        end
    end
    return results
end

--[[
    Query for a single element using a simple selector.

    Phase 1 supports: "#id", ".className", "TypeName"
    Returns the first match or nil.

    @param selector string - CSS-like selector
    @return table? - DomNode or nil
]]
function Dom.querySelector(selector)
    if not selector or selector == "" then
        return nil
    end

    local firstChar = selector:sub(1, 1)

    -- #id selector
    if firstChar == "#" then
        local id = selector:sub(2)
        return DomTree.getNode(id)
    end

    -- .class selector
    if firstChar == "." then
        local className = selector:sub(2)
        for _, nodeId in ipairs(DomTree.getAllIds()) do
            local node = DomTree.getNode(nodeId)
            if node and Dom.hasClass(node, className) then
                return node
            end
        end
        return nil
    end

    -- Type selector
    for _, nodeId in ipairs(DomTree.getAllIds()) do
        local node = DomTree.getNode(nodeId)
        if node and node._type == selector then
            return node
        end
    end

    return nil
end

--[[
    Query for all elements matching a simple selector.

    Phase 1 supports: "#id", ".className", "TypeName"

    @param selector string - CSS-like selector
    @return table - Array of matching DomNodes
]]
function Dom.querySelectorAll(selector)
    if not selector or selector == "" then
        return {}
    end

    local firstChar = selector:sub(1, 1)

    -- #id selector (returns 0 or 1)
    if firstChar == "#" then
        local id = selector:sub(2)
        local node = DomTree.getNode(id)
        return node and { node } or {}
    end

    -- .class selector
    if firstChar == "." then
        local className = selector:sub(2)
        return Dom.getElementsByClassName(className)
    end

    -- Type selector
    local results = {}
    for _, nodeId in ipairs(DomTree.getAllIds()) do
        local node = DomTree.getNode(nodeId)
        if node and node._type == selector then
            table.insert(results, node)
        end
    end
    return results
end

--[[
    Get the parent of a node.

    @param node table - DomNode
    @return table? - Parent DomNode or nil
]]
function Dom.getParent(node)
    return node._parent
end

--[[
    Get ordered children of a node.

    @param node table - DomNode
    @return table - Array of child DomNodes
]]
function Dom.getChildren(node)
    return DomTree.getChildren(node._id)
end

--[[
    Get all descendants (depth-first) of a node.

    @param node table - DomNode
    @return table - Array of descendant DomNodes
]]
function Dom.getDescendants(node)
    return DomTree.getDescendants(node._id)
end

--------------------------------------------------------------------------------
-- TREE MUTATION
--------------------------------------------------------------------------------

--[[
    Append a child to a parent node.

    If child is a Fragment, its children are transferred instead.

    @param parent table - Parent DomNode
    @param child table - Child DomNode
]]
function Dom.appendChild(parent, child)
    if child._type == "Fragment" then
        -- Transfer fragment children
        local fragmentChildren = {}
        for _, c in ipairs(child._children) do
            table.insert(fragmentChildren, c)
        end
        for _, c in ipairs(fragmentChildren) do
            DomTree.setParent(c._id, parent._id)
            -- Mount transferred child if parent is mounted
            if parent._mounted and not c._mounted and parent._instance then
                Renderer.mount(c, parent._instance)
            end
        end
        -- Remove the empty fragment from tree
        DomTree.removeNode(child._id)
    else
        DomTree.setParent(child._id, parent._id)
        -- Mount child if parent is mounted
        if parent._mounted and not child._mounted and parent._instance then
            Renderer.mount(child, parent._instance)
        elseif parent._mounted and child._mounted and child._instance then
            -- Reparent existing Instance
            Renderer.reparent(child, parent._instance)
        end
    end
end

--[[
    Remove a child from its parent.

    @param parent table - Parent DomNode
    @param child table - Child DomNode to remove
    @return table? - The removed child, or nil if not a child of parent
]]
function Dom.removeChild(parent, child)
    if child._parent ~= parent then
        return nil
    end
    -- Unmount if mounted
    if child._mounted then
        Renderer.unmount(child)
    end
    DomTree.setParent(child._id, nil)
    return child
end

--[[
    Insert a new child before a reference child.

    @param parent table - Parent DomNode
    @param newChild table - New child to insert
    @param refChild table - Reference child (insert before this)
    @return boolean - True if successful
]]
function Dom.insertBefore(parent, newChild, refChild)
    return DomTree.insertBefore(parent._id, newChild._id, refChild._id)
end

--[[
    Replace an old child with a new child.

    @param parent table - Parent DomNode
    @param newChild table - Replacement child
    @param oldChild table - Child to replace
    @return table? - The old child, or nil if not found
]]
function Dom.replaceChild(parent, newChild, oldChild)
    if oldChild._parent ~= parent then
        return nil
    end

    -- Find index of old child
    local index = nil
    for i, child in ipairs(parent._children) do
        if child._id == oldChild._id then
            index = i
            break
        end
    end

    if not index then
        return nil
    end

    -- Insert new child before old, then remove old
    DomTree.insertBefore(parent._id, newChild._id, oldChild._id)
    DomTree.setParent(oldChild._id, nil)

    return oldChild
end

--[[
    Clone a node (shallow or deep).

    @param node table - DomNode to clone
    @param deep boolean? - If true, recursively clone children (default false)
    @return table - New DomNode (detached, new ID)
]]
function Dom.cloneNode(node, deep)
    local cloned = DomNode.clone(node, deep == true)
    -- Register the clone and all its descendants in the tree
    local function registerAll(n)
        DomTree.addNode(n)
        for _, child in ipairs(n._children) do
            registerAll(child)
        end
    end
    registerAll(cloned)
    return cloned
end

--------------------------------------------------------------------------------
-- ATTRIBUTES
--------------------------------------------------------------------------------

--[[
    Set an attribute on a node.

    @param node table - DomNode
    @param key string - Attribute name
    @param value any - Attribute value
]]
function Dom.setAttribute(node, key, value)
    node._attributes[key] = value
    if node._mounted then
        Renderer.applyAttribute(node, key, value)
    end
end

--[[
    Get an attribute from a node.

    @param node table - DomNode
    @param key string - Attribute name
    @return any - Attribute value or nil
]]
function Dom.getAttribute(node, key)
    return node._attributes[key]
end

--[[
    Remove an attribute from a node.

    @param node table - DomNode
    @param key string - Attribute name
]]
function Dom.removeAttribute(node, key)
    node._attributes[key] = nil
end

--[[
    Check if a node has an attribute.

    @param node table - DomNode
    @param key string - Attribute name
    @return boolean
]]
function Dom.hasAttribute(node, key)
    return node._attributes[key] ~= nil
end

--------------------------------------------------------------------------------
-- CLASSES
--------------------------------------------------------------------------------

--[[
    Add a class to a node. No-op if already present.

    @param node table - DomNode
    @param className string - Class to add
]]
function Dom.addClass(node, className)
    if Dom.hasClass(node, className) then
        return
    end
    if node._classes == "" then
        node._classes = className
    else
        node._classes = node._classes .. " " .. className
    end
    -- Re-resolve styles on mounted nodes
    if node._mounted then
        Renderer.applyAllAttributes(node)
    end
end

--[[
    Remove a class from a node.

    @param node table - DomNode
    @param className string - Class to remove
]]
function Dom.removeClass(node, className)
    if node._classes == "" then
        return
    end

    local classes = {}
    for c in node._classes:gmatch("%S+") do
        if c ~= className then
            table.insert(classes, c)
        end
    end
    node._classes = table.concat(classes, " ")
    -- Re-resolve styles on mounted nodes
    if node._mounted then
        Renderer.applyAllAttributes(node)
    end
end

--[[
    Toggle a class on a node.

    @param node table - DomNode
    @param className string - Class to toggle
    @return boolean - Whether the class is now present
]]
function Dom.toggleClass(node, className)
    if Dom.hasClass(node, className) then
        Dom.removeClass(node, className)
        return false
    else
        Dom.addClass(node, className)
        return true
    end
end

--[[
    Check if a node has a specific class.

    @param node table - DomNode
    @param className string - Class to check
    @return boolean
]]
function Dom.hasClass(node, className)
    if node._classes == "" then
        return false
    end
    for c in node._classes:gmatch("%S+") do
        if c == className then
            return true
        end
    end
    return false
end

--[[
    Get all classes of a node as an array.

    @param node table - DomNode
    @return table - Array of class name strings
]]
function Dom.getClasses(node)
    if node._classes == "" then
        return {}
    end
    local result = {}
    for c in node._classes:gmatch("%S+") do
        table.insert(result, c)
    end
    return result
end

--------------------------------------------------------------------------------
-- LIFECYCLE
--------------------------------------------------------------------------------

--[[
    Mount a node into the world under a parent Instance.

    Creates Roblox Instances for the node and all descendants.
    If no parentInstance given, just marks as mounted (Phase 1 compat).

    @param node table - DomNode
    @param parentInstance Instance? - Parent Roblox Instance
]]
function Dom.mount(node, parentInstance)
    if parentInstance then
        Renderer.mount(node, parentInstance)
    else
        node._mounted = true
    end
end

--[[
    Unmount a node from the world.

    Destroys Roblox Instances for the node and all descendants.

    @param node table - DomNode
]]
function Dom.unmount(node)
    if node._instance then
        Renderer.unmount(node)
    else
        node._mounted = false
    end
end

--------------------------------------------------------------------------------
-- BRIDGE (Coexistence with existing Node system)
--------------------------------------------------------------------------------

--[[
    Wrap an existing Warren Node as a DomNode.

    Creates a DomNode handle that references the Node. The Node's id, class,
    model, and attributes are mirrored.

    @param warrenNode table - Existing Node instance
    @return table - DomNode handle
]]
function Dom.wrapNode(warrenNode)
    local node = DomNode.new({
        id = warrenNode.id,
        type = warrenNode.class or "Node",
        attributes = (warrenNode.getAttributes and warrenNode:getAttributes()) or {},
        node = warrenNode,
        instance = warrenNode.model,
    })
    DomTree.addNode(node)
    return node
end

--[[
    Wrap a Roblox Instance as a DomNode.

    @param instance Instance - Roblox Instance
    @param elementType string? - Element type (defaults to Instance.ClassName)
    @return table - DomNode handle
]]
function Dom.wrapInstance(instance, elementType)
    local node = DomNode.new({
        type = elementType or instance.ClassName,
        instance = instance,
    })
    DomTree.addNode(node)
    return node
end

--[[
    Get the backing Roblox Instance from a DomNode.

    @param node table - DomNode
    @return Instance? - Roblox Instance or nil
]]
function Dom.getBackingInstance(node)
    return node._instance
end

--[[
    Get the backing Warren Node from a DomNode.

    @param node table - DomNode
    @return table? - Warren Node or nil
]]
function Dom.getBackingNode(node)
    return node._node
end

--------------------------------------------------------------------------------
-- UTILITIES
--------------------------------------------------------------------------------

--[[
    Check if a value is a DomNode.

    @param value any
    @return boolean
]]
function Dom.isDomNode(value)
    return DomNode.isDomNode(value)
end

--[[
    Set the style resolver for the Renderer.
    Called as: resolver(node) -> table of resolved properties

    @param fn function - Style resolver function
]]
function Dom.setStyleResolver(fn)
    Renderer.setStyleResolver(fn)
end

--[[
    Get the Renderer module (for advanced use / testing).

    @return table - Renderer module
]]
function Dom.getRenderer()
    return Renderer
end

--[[
    Reset all DOM state (for testing).
]]
function Dom._reset()
    DomTree.reset()
    DomNode._resetIdCounter()
end

return Dom
