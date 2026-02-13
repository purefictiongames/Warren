--[[
    Warren Framework v3.0
    State/Diff.lua - State Diff & Patch Engine

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Computes minimal diffs between state trees and applies patches.
    Used by Lune to generate update payloads and by Roblox to apply them.

    A patch is an array of operations:
        { op = "set",    path = "player.gold", value = 500 }
        { op = "delete", path = "player.tempBuff" }
        { op = "insert", path = "player.inventory", value = { id = "sword" }, index = 3 }

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Diff = require(Warren.State.Diff)

    -- Compute diff between two state trees
    local ops = Diff.compute(oldState, newState)
    -- → { { op = "set", path = "player.gold", value = 450 }, ... }

    -- Apply a patch to a state tree
    Diff.apply(state, ops)

    -- Convert a change log (from Store) into patch ops
    local ops = Diff.fromChangeLog(changes)
    ```

--]]

local Diff = {}

--------------------------------------------------------------------------------
-- PATH UTILITIES
--------------------------------------------------------------------------------

local function splitPath(path)
    local segments = {}
    for segment in string.gmatch(path, "[^%.]+") do
        table.insert(segments, segment)
    end
    return segments
end

local function joinPath(...)
    local parts = {}
    for _, part in ipairs({...}) do
        if part ~= "" then
            table.insert(parts, part)
        end
    end
    return table.concat(parts, ".")
end

--------------------------------------------------------------------------------
-- DEEP COMPARISON
--------------------------------------------------------------------------------

local function deepEqual(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    -- Check all keys in a exist in b with same value
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then
            return false
        end
    end
    -- Check b doesn't have extra keys
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

--------------------------------------------------------------------------------
-- DIFF COMPUTATION
--------------------------------------------------------------------------------

--[[
    Compute the minimal set of operations to transform oldState into newState.
    Produces a flat list of path-based operations.

    @param oldState table - Previous state tree
    @param newState table - Current state tree
    @param prefix string? - Path prefix for recursion (internal)
    @return table - Array of { op, path, value? } operations
]]
function Diff.compute(oldState, newState, prefix)
    prefix = prefix or ""
    local ops = {}

    oldState = oldState or {}
    newState = newState or {}

    -- Find changed and new keys
    for key, newVal in pairs(newState) do
        local path = joinPath(prefix, tostring(key))
        local oldVal = oldState[key]

        if oldVal == nil then
            -- New key
            table.insert(ops, { op = "set", path = path, value = deepCopy(newVal) })
        elseif type(newVal) == "table" and type(oldVal) == "table" then
            -- Both tables — recurse for granular diff
            local subOps = Diff.compute(oldVal, newVal, path)
            for _, subOp in ipairs(subOps) do
                table.insert(ops, subOp)
            end
        elseif not deepEqual(oldVal, newVal) then
            -- Value changed
            table.insert(ops, { op = "set", path = path, value = deepCopy(newVal) })
        end
    end

    -- Find deleted keys
    for key in pairs(oldState) do
        if newState[key] == nil then
            local path = joinPath(prefix, tostring(key))
            table.insert(ops, { op = "delete", path = path })
        end
    end

    return ops
end

--------------------------------------------------------------------------------
-- PATCH APPLICATION
--------------------------------------------------------------------------------

--[[
    Apply a list of operations to a state tree (mutates in place).

    @param state table - State tree to modify
    @param ops table - Array of { op, path, value?, index? } operations
]]
function Diff.apply(state, ops)
    for _, op in ipairs(ops) do
        if op.op == "set" then
            Diff._applySet(state, op.path, op.value)
        elseif op.op == "delete" then
            Diff._applyDelete(state, op.path)
        elseif op.op == "insert" then
            Diff._applyInsert(state, op.path, op.value, op.index)
        end
    end
end

function Diff._applySet(state, path, value)
    local segments = splitPath(path)
    local current = state
    for i = 1, #segments - 1 do
        local key = segments[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    current[segments[#segments]] = deepCopy(value)
end

function Diff._applyDelete(state, path)
    local segments = splitPath(path)
    local current = state
    for i = 1, #segments - 1 do
        local key = segments[i]
        if type(current[key]) ~= "table" then
            return  -- Path doesn't exist, nothing to delete
        end
        current = current[key]
    end
    current[segments[#segments]] = nil
end

function Diff._applyInsert(state, path, value, index)
    local segments = splitPath(path)
    local current = state
    for i = 1, #segments - 1 do
        local key = segments[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end

    local key = segments[#segments]
    if type(current[key]) ~= "table" then
        current[key] = {}
    end

    local arr = current[key]
    if index then
        table.insert(arr, index, deepCopy(value))
    else
        table.insert(arr, deepCopy(value))
    end
end

--------------------------------------------------------------------------------
-- CHANGE LOG → OPS CONVERSION
--------------------------------------------------------------------------------

--[[
    Convert a Store change log into patch operations.
    This is the bridge between Store's internal log and Transport's
    envelope payload format.

    @param changes table - Array of { version, path, op, value, oldValue, index? }
    @return table - Array of { op, path, value?, index? }
    @return number - Highest version in the change set
]]
function Diff.fromChangeLog(changes)
    local ops = {}
    local maxVersion = 0

    for _, change in ipairs(changes) do
        table.insert(ops, {
            op = change.op,
            path = change.path,
            value = change.value,
            index = change.index,
        })
        if change.version > maxVersion then
            maxVersion = change.version
        end
    end

    return ops, maxVersion
end

--------------------------------------------------------------------------------
-- PATCH INVERSION (for rollback)
--------------------------------------------------------------------------------

--[[
    Create an inverse patch that undoes the given operations.
    Requires the original state to compute old values for set/delete ops.

    Used by Prediction queue for optimistic update rollback.

    @param state table - State BEFORE the patch was applied
    @param ops table - Operations that were applied
    @return table - Inverse operations that undo the patch
]]
function Diff.invert(state, ops)
    local inverse = {}

    for i = #ops, 1, -1 do
        local op = ops[i]
        if op.op == "set" then
            local oldVal = Diff._getAtPath(state, op.path)
            if oldVal == nil then
                table.insert(inverse, { op = "delete", path = op.path })
            else
                table.insert(inverse, { op = "set", path = op.path, value = deepCopy(oldVal) })
            end
        elseif op.op == "delete" then
            local oldVal = Diff._getAtPath(state, op.path)
            if oldVal ~= nil then
                table.insert(inverse, { op = "set", path = op.path, value = deepCopy(oldVal) })
            end
        elseif op.op == "insert" then
            -- Inverse of insert is a removal — but we track by path for simplicity
            -- The prediction queue handles array rollback via full snapshot
            table.insert(inverse, { op = "delete_last", path = op.path, index = op.index })
        end
    end

    return inverse
end

--[[
    Get a value at a dot-delimited path from a plain table.
]]
function Diff._getAtPath(state, path)
    local segments = splitPath(path)
    local current = state
    for _, key in ipairs(segments) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    return current
end

return Diff
