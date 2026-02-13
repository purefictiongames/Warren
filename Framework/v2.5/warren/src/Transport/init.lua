--[[
    Warren Framework v3.0
    Transport/init.lua - Transport Layer Public API

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Public API for the Warren transport layer. Auto-selects the correct
    bridge implementation based on runtime context.

    Roblox: HttpService polling/posting to Lune VPS
    Lune:   net.serve() HTTP server polled by Roblox

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Transport = require(Warren.Transport)

    -- Start the transport
    Transport.start({
        endpoint = "https://vps.example.com/warren",  -- Roblox only
        port = 8080,                                    -- Lune only
        authToken = "shared-secret",
    })

    -- Send a fire-and-forget event
    Transport.send("player.joined", { playerId = 123 })

    -- Send a request and await response
    local response = Transport.request("inventory.purchase", {
        itemId = "sword_02",
        cost = 500,
    })

    -- Listen for incoming envelopes on a channel pattern
    Transport.listen("state.player.*", function(envelope)
        print("Got state update:", envelope.channel)
    end)

    -- Listen for all incoming envelopes
    Transport.onReceive(function(envelope)
        print(envelope.channel, envelope.action)
    end)
    ```

--]]

local Runtime = require(script.Parent.Runtime)
local Envelope = require(script.Envelope)
local Codec = require(script.Codec)

local Transport = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _bridge = nil
local _channelListeners = {}  -- pattern → { callback, ... }

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

--[[
    Start the transport layer.

    @param config table - Bridge configuration (see RobloxBridge/LuneBridge)
]]
function Transport.start(config)
    if _bridge then
        warn("[Warren.Transport] Already started")
        return
    end

    if Runtime.isRoblox then
        local RobloxBridge = require(script.RobloxBridge)
        _bridge = RobloxBridge.new()
    else
        local LuneBridge = require(script.LuneBridge)
        _bridge = LuneBridge.new()
    end

    -- Wire up channel routing
    _bridge:onReceive(function(envelope)
        Transport._routeToChannelListeners(envelope)
    end)

    _bridge:start(config)
end

--[[
    Stop the transport layer.
]]
function Transport.stop()
    if _bridge then
        _bridge:stop()
        _bridge = nil
    end
end

--------------------------------------------------------------------------------
-- SENDING
--------------------------------------------------------------------------------

--[[
    Send a fire-and-forget event to the other runtime.

    @param channel string - Dot-delimited topic
    @param payload table? - Data to send
]]
function Transport.send(channel, payload)
    assert(_bridge, "[Warren.Transport] Not started")

    local envelope = Envelope.create({
        channel = channel,
        action = Envelope.Action.EVENT,
        payload = payload,
    })
    _bridge:send(envelope)
end

--[[
    Send a state update to the other runtime.

    @param channel string - Dot-delimited topic
    @param payload table - State patch data
]]
function Transport.update(channel, payload)
    assert(_bridge, "[Warren.Transport] Not started")

    local envelope = Envelope.create({
        channel = channel,
        action = Envelope.Action.UPDATE,
        payload = payload,
    })
    _bridge:send(envelope)
end

--[[
    Send a request and wait for the response.

    @param channel string - Dot-delimited topic
    @param payload table? - Request data
    @param timeout number? - Seconds to wait (default 10)
    @return table? - Response payload, or nil on timeout
]]
function Transport.request(channel, payload, timeout)
    assert(_bridge, "[Warren.Transport] Not started")

    local envelope = Envelope.create({
        channel = channel,
        action = Envelope.Action.REQUEST,
        payload = payload,
    })

    local response = _bridge:request(envelope, timeout)
    if response then
        return response.payload
    end
    return nil
end

--[[
    Send a raw envelope (for advanced use).

    @param envelope table - Pre-built envelope
]]
function Transport.sendRaw(envelope)
    assert(_bridge, "[Warren.Transport] Not started")
    _bridge:send(envelope)
end

--------------------------------------------------------------------------------
-- RECEIVING
--------------------------------------------------------------------------------

--[[
    Listen for envelopes on a specific channel pattern.

    Supports dot-delimited patterns with * wildcard:
        "state.player.*"     matches "state.player.inventory", "state.player.health"
        "state.player.gold"  matches exactly "state.player.gold"
        "*"                  matches everything

    @param pattern string - Channel pattern
    @param callback function(envelope) - Handler
    @return function - Unsubscribe function
]]
function Transport.listen(pattern, callback)
    if not _channelListeners[pattern] then
        _channelListeners[pattern] = {}
    end
    table.insert(_channelListeners[pattern], callback)

    local list = _channelListeners[pattern]
    local index = #list
    return function()
        table.remove(list, index)
        if #list == 0 then
            _channelListeners[pattern] = nil
        end
    end
end

--[[
    Register a raw listener for all incoming envelopes (no filtering).

    @param callback function(envelope) - Handler
    @return function - Unsubscribe function
]]
function Transport.onReceive(callback)
    assert(_bridge, "[Warren.Transport] Not started")
    return _bridge:onReceive(callback)
end

--------------------------------------------------------------------------------
-- PRIVATE: CHANNEL ROUTING
--------------------------------------------------------------------------------

--[[
    Match a channel against a pattern.
    Supports trailing * wildcard on dot-delimited segments.
]]
local function matchChannel(channel, pattern)
    if pattern == "*" then
        return true
    end
    if pattern == channel then
        return true
    end

    -- Wildcard matching: "state.player.*" matches "state.player.anything"
    if string.sub(pattern, -2) == ".*" then
        local prefix = string.sub(pattern, 1, -3)  -- "state.player"
        -- Channel must start with prefix followed by a dot
        return string.sub(channel, 1, #prefix) == prefix
            and (string.sub(channel, #prefix + 1, #prefix + 1) == "."
                or #channel == #prefix)
    end

    return false
end

--[[
    Route an envelope to matching channel listeners.
]]
function Transport._routeToChannelListeners(envelope)
    for pattern, listeners in pairs(_channelListeners) do
        if matchChannel(envelope.channel, pattern) then
            for _, callback in ipairs(listeners) do
                task.spawn(callback, envelope)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- RE-EXPORTS
--------------------------------------------------------------------------------

Transport.Envelope = Envelope
Transport.Codec = Codec
Transport.Action = Envelope.Action

return Transport
