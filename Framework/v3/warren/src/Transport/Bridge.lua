--[[
    Warren Framework v3.0
    Transport/Bridge.lua - Abstract Transport Bridge

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Abstract interface for transport bridges. A bridge handles the physical
    sending and receiving of envelopes between runtimes.

    RobloxBridge and LuneBridge implement this interface using their
    respective networking primitives.

    ============================================================================
    INTERFACE
    ============================================================================

    Bridge:start(config)              -- Initialize the bridge
    Bridge:stop()                     -- Shut down the bridge
    Bridge:send(envelope)             -- Send an envelope to the other runtime
    Bridge:onReceive(callback)        -- Register a handler for incoming envelopes
    Bridge:request(envelope) → response  -- Send and await response (by ack)

--]]

local Bridge = {}
Bridge.__index = Bridge

function Bridge.new()
    local self = setmetatable({}, Bridge)
    self._listeners = {}
    self._pendingRequests = {}  -- id → { callback, timeout }
    self._started = false
    return self
end

--[[
    Register a callback for incoming envelopes.
    Multiple listeners can be registered.

    @param callback function(envelope) - Called for each incoming envelope
    @return function - Unsubscribe function
]]
function Bridge:onReceive(callback)
    table.insert(self._listeners, callback)
    local index = #self._listeners
    return function()
        table.remove(self._listeners, index)
    end
end

--[[
    Dispatch an incoming envelope to all registered listeners.
    Also resolves pending request/response pairs.

    @param envelope table - Decoded envelope
]]
function Bridge:_dispatch(envelope)
    -- Check if this is a response to a pending request
    if envelope.action == "response" and envelope.ack then
        local pending = self._pendingRequests[envelope.ack]
        if pending then
            self._pendingRequests[envelope.ack] = nil
            pending.callback(envelope)
            return
        end
    end

    -- Broadcast to all listeners
    for _, listener in ipairs(self._listeners) do
        task.spawn(listener, envelope)
    end
end

-- Subclasses must implement these:

function Bridge:start(_config)
    error("Bridge:start() must be implemented by subclass")
end

function Bridge:stop()
    error("Bridge:stop() must be implemented by subclass")
end

function Bridge:send(_envelope)
    error("Bridge:send() must be implemented by subclass")
end

--[[
    Send a request and wait for the matching response.

    @param envelope table - Request envelope (action must be "request")
    @param timeout number - Seconds to wait (default 10)
    @return table? - Response envelope, or nil on timeout
]]
function Bridge:request(envelope, timeout)
    timeout = timeout or 10
    assert(envelope.action == "request", "Bridge:request() requires action='request'")

    local result = nil
    local done = false

    self._pendingRequests[envelope.id] = {
        callback = function(response)
            result = response
            done = true
        end,
    }

    self:send(envelope)

    -- Poll until response or timeout
    local elapsed = 0
    local interval = 0.05
    while not done and elapsed < timeout do
        task.wait(interval)
        elapsed += interval
    end

    -- Clean up if timed out
    if not done then
        self._pendingRequests[envelope.id] = nil
        return nil
    end

    return result
end

return Bridge
