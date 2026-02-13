--[[
    Warren DOM Architecture v2.5
    DomNode.lua - Lightweight Handle Type

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    A DomNode is a lightweight identity token — a thin handle to an element in
    the DOM tree. It stores identity, class, attributes, and optional backing
    references (Roblox Instance, Warren Node).

    DomNode does NOT replace Node.lua. It wraps it. Bridge functions in Dom/init
    connect the two worlds.

    DomNodes are plain tables, not metatabled objects with methods. All operations
    go through the Dom API: Dom.setAttribute(node, k, v), not node:setAttribute.
]]

local DomNode = {}

--------------------------------------------------------------------------------
-- ID GENERATION
--------------------------------------------------------------------------------

local _nextId = 0

local function generateId()
    _nextId = _nextId + 1
    return "dom_" .. _nextId
end

-- Reset counter (for testing)
function DomNode._resetIdCounter()
    _nextId = 0
end

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

--[[
    Create a new DomNode handle.

    @param config table - Configuration:
        - id: string? - Explicit ID (auto-generated if nil)
        - type: string? - Element type ("Part", "Model", "Room", etc.)
        - classes: string? - Space-separated class string
        - attributes: table? - Initial key-value attributes
        - instance: Instance? - Backing Roblox Instance
        - node: table? - Backing Warren Node
    @return table - DomNode handle
]]
function DomNode.new(config)
    config = config or {}

    local node = {
        _id = config.id or generateId(),
        _type = config.type or "Element",
        _classes = config.classes or "",
        _attributes = {},
        _instance = config.instance or nil,
        _node = config.node or nil,
        _parent = nil,
        _children = {},
        _mounted = false,
    }

    -- Copy initial attributes
    if config.attributes then
        for k, v in pairs(config.attributes) do
            node._attributes[k] = v
        end
    end

    return node
end

--------------------------------------------------------------------------------
-- CLONE
--------------------------------------------------------------------------------

--[[
    Clone a DomNode.

    @param source table - DomNode to clone
    @param deep boolean - If true, recursively clone children
    @return table - New DomNode (with new ID, no parent, not mounted)
]]
function DomNode.clone(source, deep)
    -- Copy attributes
    local attrsCopy = {}
    for k, v in pairs(source._attributes) do
        attrsCopy[k] = v
    end

    local cloned = {
        _id = generateId(),
        _type = source._type,
        _classes = source._classes,
        _attributes = attrsCopy,
        _instance = nil,  -- Clones don't share backing instances
        _node = nil,       -- Clones don't share backing nodes
        _parent = nil,     -- Clones start detached
        _children = {},
        _mounted = false,
    }

    if deep and #source._children > 0 then
        for _, child in ipairs(source._children) do
            local clonedChild = DomNode.clone(child, true)
            clonedChild._parent = cloned
            table.insert(cloned._children, clonedChild)
        end
    end

    return cloned
end

--------------------------------------------------------------------------------
-- IDENTITY
--------------------------------------------------------------------------------

--[[
    Check if a table is a DomNode (duck-typing).

    @param value any
    @return boolean
]]
function DomNode.isDomNode(value)
    return type(value) == "table"
        and type(value._id) == "string"
        and value._type ~= nil
        and value._attributes ~= nil
        and value._children ~= nil
end

return DomNode
