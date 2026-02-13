--[[
    Warren Framework v3.0
    Transport/RobloxBridge.lua - Roblox Transport Implementation

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Roblox-side bridge using HttpService for outbound HTTP to the Lune VPS
    and a polling or MessagingService channel for inbound.

    Outbound: HttpService:RequestAsync() → Lune HTTP endpoint
    Inbound:  Poll endpoint, or MessagingService subscription

    ============================================================================
    CONFIG
    ============================================================================

    {
        endpoint = "https://your-vps.example.com/warren",  -- Lune server URL
        authToken = "...",          -- Shared secret for request signing
        pollInterval = 0.5,         -- Seconds between poll requests (default 0.5)
        batchSize = 10,             -- Max envelopes per outbound batch
    }

--]]

local HttpService = game:GetService("HttpService")

local Bridge = require(script.Parent.Bridge)
local Codec = require(script.Parent.Codec)

local RobloxBridge = setmetatable({}, { __index = Bridge })
RobloxBridge.__index = RobloxBridge

function RobloxBridge.new()
    local self = Bridge.new()
    setmetatable(self, RobloxBridge)
    self._outbox = {}        -- Queued outbound envelopes
    self._pollThread = nil
    self._flushThread = nil
    self._config = nil
    return self
end

--[[
    Start the bridge with connection config.

    @param config table - See CONFIG section above
]]
function RobloxBridge:start(config)
    assert(config.endpoint, "RobloxBridge requires an endpoint URL")
    self._config = {
        endpoint = config.endpoint,
        authToken = config.authToken or "",
        pollInterval = config.pollInterval or 0.5,
        batchSize = config.batchSize or 10,
    }
    self._started = true

    -- Start poll loop for inbound envelopes
    self._pollThread = task.spawn(function()
        while self._started do
            self:_poll()
            task.wait(self._config.pollInterval)
        end
    end)

    -- Start flush loop for outbound batching
    self._flushThread = task.spawn(function()
        while self._started do
            self:_flush()
            task.wait(self._config.pollInterval)
        end
    end)
end

--[[
    Stop the bridge.
]]
function RobloxBridge:stop()
    self._started = false
    -- Flush remaining outbox
    if #self._outbox > 0 then
        self:_flush()
    end
end

--[[
    Queue an envelope for outbound delivery.

    @param envelope table - Transport envelope
]]
function RobloxBridge:send(envelope)
    table.insert(self._outbox, envelope)

    -- Immediate flush if batch is full
    if #self._outbox >= self._config.batchSize then
        self:_flush()
    end
end

--------------------------------------------------------------------------------
-- PRIVATE: HTTP OPERATIONS
--------------------------------------------------------------------------------

--[[
    Flush the outbox — send queued envelopes to Lune as a batch.
]]
function RobloxBridge:_flush()
    if #self._outbox == 0 then
        return
    end

    -- Drain the outbox
    local batch = self._outbox
    self._outbox = {}

    local body = Codec.encode({
        envelopes = batch,
    })

    local ok, err = pcall(function()
        HttpService:RequestAsync({
            Url = self._config.endpoint .. "/send",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = self._config.authToken:AddPrefix("Bearer "),
            },
            Body = body,
        })
    end)

    if not ok then
        -- Re-queue failed batch for retry
        for i = #batch, 1, -1 do
            table.insert(self._outbox, 1, batch[i])
        end
        warn("[Warren.Transport] Flush failed: " .. tostring(err))
    end
end

--[[
    Poll the Lune endpoint for inbound envelopes.
]]
function RobloxBridge:_poll()
    local ok, result = pcall(function()
        return HttpService:RequestAsync({
            Url = self._config.endpoint .. "/poll",
            Method = "GET",
            Headers = {
                ["Authorization"] = self._config.authToken:AddPrefix("Bearer "),
            },
        })
    end)

    if not ok then
        -- Silent fail — poll will retry next interval
        return
    end

    if result.StatusCode ~= 200 then
        return
    end

    local decoded = Codec.decode(result.Body)
    if decoded and decoded.envelopes then
        for _, envelope in ipairs(decoded.envelopes) do
            self:_dispatch(envelope)
        end
    end
end

return RobloxBridge
