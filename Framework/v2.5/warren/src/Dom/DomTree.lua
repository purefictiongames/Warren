--[[
    Warren DOM Architecture v2.5
    DomTree.lua - Parent/Child Tree Structure

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Adds what Node.Registry lacks — parent/child relationships and tree traversal.

    The tree maintains three maps for O(1) lookups:
        - nodeMap: { [nodeId] = DomNode }
        - parentMap: { [nodeId] = parentNodeId }
        - childrenMap: { [nodeId] = { childId1, childId2, ... } }

    The DomNode._parent and _children fields are the canonical source of truth.
    The maps are indexes that mirror them for fast lookup by ID.
]]

local DomTree = {}

--------------------------------------------------------------------------------
-- PRIVATE STATE
--------------------------------------------------------------------------------

local nodeMap = {}      -- { [id] = DomNode }
local parentMap = {}    -- { [id] = parentId }
local childrenMap = {}  -- { [id] = { childId1, childId2, ... } }

--------------------------------------------------------------------------------
-- INDEX MANAGEMENT
--------------------------------------------------------------------------------

local function indexNode(node)
    nodeMap[node._id] = node
    childrenMap[node._id] = childrenMap[node._id] or {}

    if node._parent then
        parentMap[node._id] = node._parent._id
    end
end

local function unindexNode(id)
    nodeMap[id] = nil
    parentMap[id] = nil
    childrenMap[id] = nil
end

--------------------------------------------------------------------------------
-- REGISTRATION
--------------------------------------------------------------------------------

--[[
    Add a node to the tree (register in maps).
    Does NOT set parent/child — use setParent or appendChild for that.

    @param node table - DomNode
]]
function DomTree.addNode(node)
    nodeMap[node._id] = node
    childrenMap[node._id] = childrenMap[node._id] or {}
end

--[[
    Remove a node from the tree.
    Detaches from parent, removes all children recursively.

    @param id string - Node ID
    @return boolean - True if found and removed
]]
function DomTree.removeNode(id)
    local node = nodeMap[id]
    if not node then
        return false
    end

    -- Detach from parent
    if node._parent then
        local parentChildren = node._parent._children
        for i, child in ipairs(parentChildren) do
            if child._id == id then
                table.remove(parentChildren, i)
                break
            end
        end

        -- Update parent's children index
        local parentId = node._parent._id
        if childrenMap[parentId] then
            for i, childId in ipairs(childrenMap[parentId]) do
                if childId == id then
                    table.remove(childrenMap[parentId], i)
                    break
                end
            end
        end

        node._parent = nil
    end

    -- Recursively remove children
    local childIds = {}
    for _, childId in ipairs(childrenMap[id] or {}) do
        table.insert(childIds, childId)
    end
    for _, childId in ipairs(childIds) do
        DomTree.removeNode(childId)
    end

    -- Clean up maps
    unindexNode(id)

    return true
end

--------------------------------------------------------------------------------
-- PARENT/CHILD OPERATIONS
--------------------------------------------------------------------------------

--[[
    Set the parent of a node.
    Removes from old parent if any. Pass nil to detach.

    @param nodeId string - Child node ID
    @param parentId string? - New parent node ID (nil = detach)
]]
function DomTree.setParent(nodeId, parentId)
    local node = nodeMap[nodeId]
    if not node then return end

    -- Remove from old parent
    if node._parent then
        local oldParentId = node._parent._id
        local oldParentChildren = node._parent._children
        for i, child in ipairs(oldParentChildren) do
            if child._id == nodeId then
                table.remove(oldParentChildren, i)
                break
            end
        end
        if childrenMap[oldParentId] then
            for i, childId in ipairs(childrenMap[oldParentId]) do
                if childId == nodeId then
                    table.remove(childrenMap[oldParentId], i)
                    break
                end
            end
        end
        node._parent = nil
        parentMap[nodeId] = nil
    end

    -- Attach to new parent
    if parentId then
        local parent = nodeMap[parentId]
        if not parent then return end

        node._parent = parent
        table.insert(parent._children, node)
        parentMap[nodeId] = parentId
        childrenMap[parentId] = childrenMap[parentId] or {}
        table.insert(childrenMap[parentId], nodeId)
    end
end

--[[
    Get the parent DomNode of a node.

    @param nodeId string - Node ID
    @return table? - Parent DomNode or nil
]]
function DomTree.getParent(nodeId)
    local node = nodeMap[nodeId]
    return node and node._parent
end

--[[
    Get ordered children of a node.

    @param nodeId string - Node ID
    @return table - Array of child DomNodes
]]
function DomTree.getChildren(nodeId)
    local node = nodeMap[nodeId]
    if not node then
        return {}
    end
    -- Return a copy to prevent external mutation
    local result = {}
    for _, child in ipairs(node._children) do
        table.insert(result, child)
    end
    return result
end

--[[
    Get all descendants depth-first.

    @param nodeId string - Node ID
    @return table - Array of descendant DomNodes (depth-first order)
]]
function DomTree.getDescendants(nodeId)
    local node = nodeMap[nodeId]
    if not node then
        return {}
    end

    local result = {}
    local function traverse(n)
        for _, child in ipairs(n._children) do
            table.insert(result, child)
            traverse(child)
        end
    end
    traverse(node)
    return result
end

--[[
    Insert a child before a reference child.

    @param parentId string - Parent node ID
    @param newChildId string - New child node ID
    @param refChildId string - Reference child node ID (insert before this)
    @return boolean - True if successful
]]
function DomTree.insertBefore(parentId, newChildId, refChildId)
    local parent = nodeMap[parentId]
    local newChild = nodeMap[newChildId]
    local refChild = nodeMap[refChildId]

    if not parent or not newChild then
        return false
    end

    -- Detach newChild from current parent
    if newChild._parent then
        DomTree.setParent(newChildId, nil)
    end

    -- Find reference index
    local refIndex = nil
    if refChild then
        for i, child in ipairs(parent._children) do
            if child._id == refChildId then
                refIndex = i
                break
            end
        end
    end

    -- Insert
    newChild._parent = parent
    parentMap[newChildId] = parentId
    childrenMap[parentId] = childrenMap[parentId] or {}

    if refIndex then
        table.insert(parent._children, refIndex, newChild)
        table.insert(childrenMap[parentId], refIndex, newChildId)
    else
        -- No ref child or not found — append
        table.insert(parent._children, newChild)
        table.insert(childrenMap[parentId], newChildId)
    end

    return true
end

--------------------------------------------------------------------------------
-- LOOKUP
--------------------------------------------------------------------------------

--[[
    Get a DomNode by ID.

    @param id string - Node ID
    @return table? - DomNode or nil
]]
function DomTree.getNode(id)
    return nodeMap[id]
end

--[[
    Get all registered DomNode IDs.

    @return table - Array of IDs
]]
function DomTree.getAllIds()
    local ids = {}
    for id in pairs(nodeMap) do
        table.insert(ids, id)
    end
    return ids
end

--[[
    Get count of registered nodes.

    @return number
]]
function DomTree.count()
    local c = 0
    for _ in pairs(nodeMap) do
        c = c + 1
    end
    return c
end

--------------------------------------------------------------------------------
-- RESET
--------------------------------------------------------------------------------

--[[
    Clear all tree state (for testing).
]]
function DomTree.reset()
    nodeMap = {}
    parentMap = {}
    childrenMap = {}
end

return DomTree
