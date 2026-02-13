--[[
    Warren Framework v3.0
    State/Store.lua - Versioned State Store

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    A versioned key-value store for game state. Every mutation increments
    a monotonic version number, enabling diff-based synchronization between
    Roblox and Lune runtimes.

    State is organized by dot-delimited paths:
        "player.p123.inventory.gold"
        "world.rooms.room_01.enemies"

    The store is a shared module — both runtimes use the same API. Lune is
    authoritative for writes; Roblox applies patches received via Transport.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Store = require(Warren.State.Store)

    local store = Store.new()

    -- Set values at paths
    store:set("player.p123.gold", 500)
    store:set("player.p123.inventory", { "sword", "shield" })

    -- Get values
    local gold = store:get("player.p123.gold")  -- 500

    -- Get nested subtree
    local player = store:get("player.p123")
    -- { gold = 500, inventory = { "sword", "shield" } }

    -- Check version
    print(store:getVersion())  -- 2

    -- Snapshot for full-state sync
    local snapshot = store:snapshot()
    -- { data = { player = { p123 = { ... } } }, version = 2 }

    -- Subscribe to changes
    store:onChange("player.p123.gold", function(newValue, oldValue, path)
        print("Gold changed:", oldValue, "→", newValue)
    end)
    ```

--]]

local task = task or require("@lune/task")

local Store = {}
Store.__index = Store

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

--[[
    Create a new state store.

    @return Store
]]
function Store.new()
    local self = setmetatable({}, Store)
    self._data = {}
    self._version = 0
    self._changeLog = {}     -- Ring buffer: { version, path, op, value, oldValue }
    self._maxLogSize = 100   -- Keep last N changes for diff computation
    self._listeners = {}     -- path pattern → { callback, ... }
    return self
end

--------------------------------------------------------------------------------
-- PATH UTILITIES
--------------------------------------------------------------------------------

--[[
    Split a dot-delimited path into segments.

    @param path string - "player.p123.gold"
    @return table - { "player", "p123", "gold" }
]]
local function splitPath(path)
    local segments = {}
    for segment in string.gmatch(path, "[^%.]+") do
        table.insert(segments, segment)
    end
    return segments
end

--[[
    Navigate to a nested table location, creating tables as needed.
    Returns the parent table and the final key.

    @param root table - Root data table
    @param segments table - Path segments
    @param create boolean - Whether to create missing intermediate tables
    @return table?, string? - Parent table and final key, or nil if path doesn't exist
]]
local function navigate(root, segments, create)
    local current = root
    for i = 1, #segments - 1 do
        local key = segments[i]
        if type(current[key]) ~= "table" then
            if create then
                current[key] = {}
            else
                return nil, nil
            end
        end
        current = current[key]
    end
    return current, segments[#segments]
end

--------------------------------------------------------------------------------
-- DEEP COPY
--------------------------------------------------------------------------------

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
-- READ API
--------------------------------------------------------------------------------

--[[
    Get a value at a path.

    @param path string - Dot-delimited path
    @return any - Value at path, or nil if not found
]]
function Store:get(path)
    if not path or path == "" then
        return deepCopy(self._data)
    end

    local segments = splitPath(path)
    if #segments == 0 then
        return deepCopy(self._data)
    end

    local parent, key = navigate(self._data, segments, false)
    if not parent then
        return nil
    end
    return deepCopy(parent[key])
end

--[[
    Get the current version number.

    @return number
]]
function Store:getVersion()
    return self._version
end

--[[
    Get a full snapshot of the store for initial sync.

    @return table - { data = ..., version = number }
]]
function Store:snapshot()
    return {
        data = deepCopy(self._data),
        version = self._version,
    }
end

--------------------------------------------------------------------------------
-- WRITE API
--------------------------------------------------------------------------------

--[[
    Set a value at a path. Creates intermediate tables as needed.
    Increments the store version and logs the change.

    @param path string - Dot-delimited path
    @param value any - Value to set
]]
function Store:set(path, value)
    local segments = splitPath(path)
    assert(#segments > 0, "Store:set() requires a non-empty path")

    local parent, key = navigate(self._data, segments, true)
    local oldValue = parent[key]

    -- No-op if value hasn't changed (primitive comparison)
    if type(value) ~= "table" and value == oldValue then
        return
    end

    parent[key] = deepCopy(value)
    self._version += 1

    -- Log the change
    self:_logChange({
        version = self._version,
        path = path,
        op = "set",
        value = deepCopy(value),
        oldValue = deepCopy(oldValue),
    })

    -- Notify listeners
    self:_notifyListeners(path, value, oldValue)
end

--[[
    Delete a value at a path.

    @param path string - Dot-delimited path
]]
function Store:delete(path)
    local segments = splitPath(path)
    assert(#segments > 0, "Store:delete() requires a non-empty path")

    local parent, key = navigate(self._data, segments, false)
    if not parent or parent[key] == nil then
        return  -- Nothing to delete
    end

    local oldValue = parent[key]
    parent[key] = nil
    self._version += 1

    self:_logChange({
        version = self._version,
        path = path,
        op = "delete",
        value = nil,
        oldValue = deepCopy(oldValue),
    })

    self:_notifyListeners(path, nil, oldValue)
end

--[[
    Insert a value into an array at a path.

    @param path string - Dot-delimited path to the array
    @param value any - Value to insert
    @param index number? - Position to insert at (default: end)
]]
function Store:insert(path, value, index)
    local segments = splitPath(path)
    assert(#segments > 0, "Store:insert() requires a non-empty path")

    local parent, key = navigate(self._data, segments, true)
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end

    local arr = parent[key]
    local copied = deepCopy(value)

    if index then
        table.insert(arr, index, copied)
    else
        table.insert(arr, copied)
    end

    self._version += 1

    self:_logChange({
        version = self._version,
        path = path,
        op = "insert",
        value = deepCopy(value),
        index = index,
    })

    self:_notifyListeners(path, arr, nil)
end

--[[
    Load a full state snapshot (used on join/reconnect).
    Replaces all data and sets version.

    @param snapshot table - { data = ..., version = number }
]]
function Store:loadSnapshot(snapshot)
    local oldData = self._data
    self._data = deepCopy(snapshot.data)
    self._version = snapshot.version
    self._changeLog = {}  -- Clear log — snapshot is the new baseline

    -- Notify root listeners
    self:_notifyListeners("", self._data, oldData)
end

--------------------------------------------------------------------------------
-- CHANGE LOG
--------------------------------------------------------------------------------

--[[
    Get changes since a given version.
    Returns entries from the change log with version > sinceVersion.

    @param sinceVersion number - Version to diff from
    @return table - Array of change entries
    @return boolean - true if complete, false if log was truncated (need full sync)
]]
function Store:getChangesSince(sinceVersion)
    -- If the requested version is older than our log, caller needs a full snapshot
    if #self._changeLog > 0 and self._changeLog[1].version > sinceVersion + 1 then
        return {}, false
    end

    local changes = {}
    for _, entry in ipairs(self._changeLog) do
        if entry.version > sinceVersion then
            table.insert(changes, entry)
        end
    end
    return changes, true
end

function Store:_logChange(entry)
    table.insert(self._changeLog, entry)

    -- Trim to max size (remove oldest)
    while #self._changeLog > self._maxLogSize do
        table.remove(self._changeLog, 1)
    end
end

--------------------------------------------------------------------------------
-- CHANGE LISTENERS
--------------------------------------------------------------------------------

--[[
    Subscribe to changes at a path pattern.

    @param pattern string - Dot-delimited path or "*" for all changes
    @param callback function(newValue, oldValue, path) - Handler
    @return function - Unsubscribe function
]]
function Store:onChange(pattern, callback)
    if not self._listeners[pattern] then
        self._listeners[pattern] = {}
    end
    table.insert(self._listeners[pattern], callback)

    local list = self._listeners[pattern]
    local index = #list
    return function()
        table.remove(list, index)
        if #list == 0 then
            self._listeners[pattern] = nil
        end
    end
end

--[[
    Notify matching listeners of a change.
]]
function Store:_notifyListeners(path, newValue, oldValue)
    for pattern, listeners in pairs(self._listeners) do
        if self:_matchPath(path, pattern) then
            for _, callback in ipairs(listeners) do
                task.spawn(callback, newValue, oldValue, path)
            end
        end
    end
end

--[[
    Match a path against a listener pattern.
    "*" matches everything. "foo.bar.*" matches "foo.bar.anything".
    Exact match for non-wildcard patterns.
]]
function Store:_matchPath(path, pattern)
    if pattern == "*" or pattern == "" then
        return true
    end
    if pattern == path then
        return true
    end
    if string.sub(pattern, -2) == ".*" then
        local prefix = string.sub(pattern, 1, -3)
        return string.sub(path, 1, #prefix) == prefix
    end
    return false
end

return Store
