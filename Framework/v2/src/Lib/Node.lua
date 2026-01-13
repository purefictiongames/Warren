--[[
    LibPureFiction Framework v2
    Node.lua - Base Node Class

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Nodes are self-contained units of game logic with standard I/O pins.
    They communicate via events routed through the IPC system.

    Analogy: Nodes are like integrated circuits (ICUs) on a breadboard.
    The IPC system provides the wiring between them based on the active run mode.

    ============================================================================
    PIN MODEL
    ============================================================================

    Every node has these standard pins:

        Sys.In  - Control signals from system (lifecycle)
        In      - Game signals from other nodes (via wiring)
        Out     - Outbound signals to other nodes (via wiring)
        Err     - Error propagation back to system

    Nodes can also have mode-specific pins:

        Tutorial.In   - Tutorial mode input handlers
        Tutorial.Out  - Tutorial mode output (documentation)
        Playing.In    - Playing mode input handlers

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Node = require(game.ReplicatedStorage.Lib.Node)

    -- Define a node type
    local Dropper = Node.extend({
        name = "Dropper",
        domain = "server",

        Sys = {
            onInit = function(self)
                self:setAttribute("Remaining", self:getAttribute("MaxItems") or 10)
            end,
            onStart = function(self) end,
            onStop = function(self) end,
        },

        In = {
            onDrop = function(self, data)
                local remaining = self:getAttribute("Remaining")
                if remaining > 0 then
                    self:setAttribute("Remaining", remaining - 1)
                    self.Out:Fire("dropped", { count = remaining - 1 })
                end
            end,
        },
    })

    -- Create an instance
    local instance = Dropper:new({
        id = "Dropper_1",
        model = workspace.Dropper_1,
    })
    ```

    ============================================================================
    INHERITANCE
    ============================================================================

    Nodes support prototype inheritance via extend():

    ```lua
    -- Base dispenser (in Lib)
    local Dispenser = Node.extend({
        name = "Dispenser",
        required = { In = { "onDispense" } },
        defaults = {
            In = {
                onRefill = function(self, count) ... end,
            },
        },
    })

    -- Game-specific implementation
    local MarshmallowBag = Dispenser.extend({
        name = "MarshmallowBag",
        In = {
            onDispense = function(self) ... end,  -- Required
            -- onRefill uses Dispenser default
        },
    })
    ```

--]]

local Node = {}
Node.__index = Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------
-- These are injected into nodes that don't provide their own implementations.

Node.defaults = {
    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
        onModeChange = function(self, oldMode, newMode) end,
        onSpawned = function(self) end,
        onDespawning = function(self) end,
    },
}

Node.required = {
    Sys = { "onInit", "onStart", "onStop" },
}

--------------------------------------------------------------------------------
-- OUT CHANNEL
--------------------------------------------------------------------------------
-- Stub that will be connected to IPC routing when IPC.init() is called.

local OutChannel = {}
OutChannel.__index = OutChannel

function OutChannel.new(node)
    local self = setmetatable({}, OutChannel)
    self._node = node
    return self
end

function OutChannel:Fire(signal, data)
    -- This will be replaced by IPC routing
    -- For now, just log if Debug is available
    local System = self._node._System
    if System and System.Debug then
        System.Debug.trace(self._node.id or "Node", "Out:Fire", signal)
    end

    -- Store for IPC to pick up
    if self._node._ipcSend then
        self._node._ipcSend(self._node.id, signal, data)
    end
end

--------------------------------------------------------------------------------
-- ERR CHANNEL
--------------------------------------------------------------------------------
-- Propagates errors to IPC.ErrIn for centralized handling.

local ErrChannel = {}
ErrChannel.__index = ErrChannel

function ErrChannel.new(node)
    local self = setmetatable({}, ErrChannel)
    self._node = node
    return self
end

function ErrChannel:Fire(errorData)
    -- Add node context
    local enriched = {
        node = self._node.id,
        class = self._node.class,
        timestamp = os.time(),
    }

    -- Merge error data
    if type(errorData) == "table" then
        for k, v in pairs(errorData) do
            enriched[k] = v
        end
    else
        enriched.error = tostring(errorData)
    end

    -- Route to IPC error handler (if connected)
    if self._node._ipcError then
        self._node._ipcError(enriched)
    else
        -- Fallback to Debug.error if IPC not connected
        local System = self._node._System
        if System and System.Debug then
            System.Debug.error(self._node.id or "Node", "Unhandled error:", enriched.error or "unknown")
        end
    end
end

--------------------------------------------------------------------------------
-- EXTEND (Factory Pattern)
--------------------------------------------------------------------------------
--[[
    Factory function that creates extend functions with correct parent capture.

    This pattern ensures each class gets its own extend function with the
    correct parent class captured in the closure. Without this, child classes
    would share the same extend function and use the wrong parent reference.

    @param parent table - Parent class to extend from
    @return function - extend function for the parent class
--]]
local function makeExtendFunction(parent)
    return function(definition)
        -- Validate definition
        if not definition then
            error("[Node.extend] Definition required")
        end
        if not definition.name then
            error("[Node.extend] Definition must have a name")
        end

        -- Create new class with prototype chain to parent
        local NewClass = setmetatable({}, { __index = parent })
        NewClass.__index = NewClass

        -- Store class metadata
        NewClass.name = definition.name
        NewClass.domain = definition.domain or parent.domain or "shared"
        NewClass._parent = parent
        NewClass._definition = definition

        -- Merge required handlers from parent
        NewClass.required = {}
        if parent.required then
            for pin, handlers in pairs(parent.required) do
                NewClass.required[pin] = {}
                for _, handler in ipairs(handlers) do
                    table.insert(NewClass.required[pin], handler)
                end
            end
        end
        if definition.required then
            for pin, handlers in pairs(definition.required) do
                NewClass.required[pin] = NewClass.required[pin] or {}
                for _, handler in ipairs(handlers) do
                    -- Avoid duplicates
                    local exists = false
                    for _, existing in ipairs(NewClass.required[pin]) do
                        if existing == handler then
                            exists = true
                            break
                        end
                    end
                    if not exists then
                        table.insert(NewClass.required[pin], handler)
                    end
                end
            end
        end

        -- Merge defaults from parent
        NewClass.defaults = {}
        if parent.defaults then
            for pin, handlers in pairs(parent.defaults) do
                NewClass.defaults[pin] = NewClass.defaults[pin] or {}
                for name, fn in pairs(handlers) do
                    NewClass.defaults[pin][name] = fn
                end
            end
        end
        if definition.defaults then
            for pin, handlers in pairs(definition.defaults) do
                NewClass.defaults[pin] = NewClass.defaults[pin] or {}
                for name, fn in pairs(handlers) do
                    NewClass.defaults[pin][name] = fn
                end
            end
        end

        -- Copy Sys handlers (merge with parent)
        NewClass.Sys = {}
        if parent.Sys then
            for name, fn in pairs(parent.Sys) do
                NewClass.Sys[name] = fn
            end
        end
        if definition.Sys then
            for name, fn in pairs(definition.Sys) do
                NewClass.Sys[name] = fn
            end
        end

        -- Copy In handlers (merge with parent)
        NewClass.In = {}
        if parent.In then
            for name, value in pairs(parent.In) do
                NewClass.In[name] = value
            end
        end
        if definition.In then
            for name, value in pairs(definition.In) do
                NewClass.In[name] = value
            end
        end

        -- Copy Out schema
        if definition.Out then
            NewClass.Out = definition.Out
        elseif parent.Out then
            NewClass.Out = parent.Out
        end

        -- Copy mode-specific handlers
        for key, value in pairs(definition) do
            if type(value) == "table" and key ~= "Sys" and key ~= "In" and key ~= "Out" and key ~= "Err"
                and key ~= "required" and key ~= "defaults" and key ~= "name" and key ~= "domain" then
                -- Assume this is a mode-specific handler table (e.g., Tutorial = { In = {...} })
                NewClass[key] = value
            end
        end

        -- Copy private methods (functions not in reserved keys)
        for key, value in pairs(definition) do
            if type(value) == "function" and key ~= "Sys" and key ~= "In" and key ~= "Out" and key ~= "Err" then
                NewClass[key] = value
            end
        end

        -- Create a fresh extend function for this new class
        -- This ensures grandchildren correctly reference NewClass as parent
        NewClass.extend = makeExtendFunction(NewClass)

        return NewClass
    end
end

-- Initialize Node.extend with the factory
Node.extend = makeExtendFunction(Node)

--------------------------------------------------------------------------------
-- NEW (Instance Creation)
--------------------------------------------------------------------------------
--[[
    Create a new instance of a node class.

    @param config table - Instance configuration
        id: string (required) - Unique instance ID
        model: Instance (optional) - Associated Roblox Instance
        attributes: table (optional) - Initial attributes

    @return table - Node instance with pins and methods
--]]
function Node:new(config)
    config = config or {}

    if not config.id then
        error("[Node:new] Instance must have an id")
    end

    local instance = setmetatable({}, self)

    -- Instance metadata
    instance.id = config.id
    instance.class = self.name or "Node"
    instance.domain = self.domain or "shared"
    instance.model = config.model
    instance._attributes = config.attributes or {}
    instance._System = nil  -- Will be set by IPC

    -- Create output channels
    instance.Out = OutChannel.new(instance)
    instance.Err = ErrChannel.new(instance)

    -- Copy Sys handlers (with default injection)
    instance.Sys = {}
    -- First, apply defaults
    if self.defaults and self.defaults.Sys then
        for name, fn in pairs(self.defaults.Sys) do
            instance.Sys[name] = fn
        end
    end
    -- Then, override with class handlers
    if self.Sys then
        for name, fn in pairs(self.Sys) do
            instance.Sys[name] = fn
        end
    end

    -- Copy In handlers (with default injection)
    instance.In = {}
    -- First, apply defaults
    if self.defaults and self.defaults.In then
        for name, value in pairs(self.defaults.In) do
            instance.In[name] = value
        end
    end
    -- Then, override with class handlers
    if self.In then
        for name, value in pairs(self.In) do
            instance.In[name] = value
        end
    end

    -- Copy mode-specific handlers
    for key, value in pairs(self) do
        if type(value) == "table" and key ~= "Sys" and key ~= "In" and key ~= "Out" and key ~= "Err"
            and key ~= "required" and key ~= "defaults" and key ~= "__index" and key ~= "_parent"
            and key ~= "_definition" and key ~= "name" and key ~= "domain" then
            -- Deep copy mode-specific handlers
            instance[key] = {}
            for subKey, subValue in pairs(value) do
                if type(subValue) == "table" then
                    instance[key][subKey] = {}
                    for k, v in pairs(subValue) do
                        instance[key][subKey][k] = v
                    end
                else
                    instance[key][subKey] = subValue
                end
            end
        end
    end

    return instance
end

--------------------------------------------------------------------------------
-- INHERITANCE CHAIN
--------------------------------------------------------------------------------
--[[
    Get the full inheritance chain for this node class.

    Used for contract validation - walks up the prototype chain
    to collect all required handlers from all ancestors.

    @return table - Array of ancestor classes (oldest first)
--]]
function Node:getInheritanceChain()
    local chain = {}
    local current = self

    while current do
        table.insert(chain, 1, current)  -- Insert at beginning (oldest first)
        current = current._parent
    end

    return chain
end

--------------------------------------------------------------------------------
-- HANDLER CHECKS
--------------------------------------------------------------------------------
--[[
    Check if this node has a handler for a given pin and name.

    Looks in both the class definition and defaults.

    @param pin string - Pin name ("Sys", "In", etc.)
    @param handlerName string - Handler name (e.g., "onInit")
    @return boolean - True if handler exists
--]]
function Node:hasHandler(pin, handlerName)
    -- Check instance handler
    if self[pin] and self[pin][handlerName] then
        return true
    end

    -- Check defaults
    if self.defaults and self.defaults[pin] and self.defaults[pin][handlerName] then
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- PIN RESOLUTION
--------------------------------------------------------------------------------
--[[
    Resolve the appropriate pin handlers for a given mode.

    Resolution order:
    1. Check {Mode}.In - if exists, use it
    2. Fall back to In

    @param mode string - Current run mode (e.g., "Tutorial", "Playing")
    @param pinType string - Pin type ("In" or "Out")
    @return table - Handler table to use
--]]
function Node:resolvePin(mode, pinType)
    -- Check mode-specific pin
    if mode and self[mode] and self[mode][pinType] then
        return self[mode][pinType]
    end

    -- Fall back to default pin
    return self[pinType] or {}
end

--------------------------------------------------------------------------------
-- ATTRIBUTES
--------------------------------------------------------------------------------
--[[
    Get an attribute value.

    First checks the associated model (if any), then falls back to
    internal attribute storage.

    @param name string - Attribute name
    @return any - Attribute value or nil
--]]
function Node:getAttribute(name)
    -- Try model attributes first
    if self.model and typeof(self.model) == "Instance" then
        local success, value = pcall(function()
            return self.model:GetAttribute(name)
        end)
        if success and value ~= nil then
            return value
        end
    end

    -- Fall back to internal storage
    return self._attributes[name]
end

--[[
    Set an attribute value.

    Sets on both the model (if any) and internal storage.

    @param name string - Attribute name
    @param value any - Attribute value
--]]
function Node:setAttribute(name, value)
    -- Store internally
    self._attributes[name] = value

    -- Also set on model if available
    if self.model and typeof(self.model) == "Instance" then
        pcall(function()
            self.model:SetAttribute(name, value)
        end)
    end
end

--[[
    Get all attributes.

    Merges model attributes with internal storage.

    @return table - All attribute key-value pairs
--]]
function Node:getAttributes()
    local result = {}

    -- Copy internal attributes
    for k, v in pairs(self._attributes) do
        result[k] = v
    end

    -- Merge model attributes (overwrite internals if conflict)
    if self.model and typeof(self.model) == "Instance" then
        local success, attrs = pcall(function()
            return self.model:GetAttributes()
        end)
        if success and attrs then
            for k, v in pairs(attrs) do
                result[k] = v
            end
        end
    end

    return result
end

--------------------------------------------------------------------------------
-- LOCKING & SIGNAL WAITING
--------------------------------------------------------------------------------
--[[
    Check if this node is currently locked (waiting for a signal).

    When locked, IPC will queue incoming messages instead of dispatching them.

    @return boolean - True if node is locked
--]]
function Node:isLocked()
    return self._locked == true
end

--[[
    Wait for a specific signal to be received.

    Automatically locks the node during the wait, causing IPC to queue
    other incoming messages. When the signal is received or timeout occurs,
    the node unlocks and queued messages are flushed.

    @param signalName string - The In handler to wait for (e.g., "onAck")
    @param timeout number - Maximum seconds to wait (default 5)
    @return any - The data received with the signal, or nil on timeout
--]]
function Node:waitForSignal(signalName, timeout)
    timeout = timeout or 5

    -- Create internal signal mechanism
    local received = false
    local receivedData = nil
    local waitEvent = Instance.new("BindableEvent")

    -- Store the original handler (if any)
    local originalHandler = self.In and self.In[signalName]

    -- Install temporary handler that captures the signal
    self.In = self.In or {}
    self.In[signalName] = function(selfRef, data)
        receivedData = data
        received = true
        waitEvent:Fire()
    end

    -- Lock the node
    self._locked = true
    self._messageQueue = self._messageQueue or {}

    -- Wait with timeout
    local startTime = os.clock()
    local connection
    connection = waitEvent.Event:Connect(function() end)

    -- Timeout loop
    task.spawn(function()
        while not received and (os.clock() - startTime) < timeout do
            task.wait(0.1)
        end
        if not received then
            waitEvent:Fire()  -- Unblock on timeout
        end
    end)

    -- Block until signal or timeout
    waitEvent.Event:Wait()

    -- Cleanup
    connection:Disconnect()
    waitEvent:Destroy()

    -- Restore original handler
    if originalHandler then
        self.In[signalName] = originalHandler
    else
        self.In[signalName] = nil
    end

    -- Unlock and flush queue
    self._locked = false
    self:_flushMessageQueue()

    -- Return result
    if received then
        return receivedData
    else
        return nil  -- Timeout
    end
end

--[[
    Flush queued messages that arrived while node was locked.

    Called automatically by waitForSignal() after unlocking.
    Messages are dispatched in order they were received.
--]]
function Node:_flushMessageQueue()
    if not self._messageQueue or #self._messageQueue == 0 then
        return
    end

    local System = self._System
    if not System or not System.IPC then
        self._messageQueue = {}
        return
    end

    -- Process queued messages
    local queue = self._messageQueue
    self._messageQueue = {}

    for _, msg in ipairs(queue) do
        local signal, data, msgId = msg[1], msg[2], msg[3]
        -- Re-dispatch through IPC
        System.IPC.sendTo(self.id, signal, data)
    end
end

return Node
