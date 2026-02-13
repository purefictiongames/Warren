--[[
    Warren Framework v3.0
    Transport/LuneBridge.lua - Lune Transport Implementation

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Lune-side bridge using net.serve() for inbound HTTP from Roblox
    and an outbox queue that Roblox polls via /poll.

    Inbound:  net.serve() handles POST /send from Roblox
    Outbound: Envelopes queue in _outbox, drained by GET /poll from Roblox

    ============================================================================
    CONFIG
    ============================================================================

    {
        port = 8080,                -- HTTP server port
        authToken = "...",          -- Shared secret for request validation
    }

--]]

local net = require("@lune/net")
local task = require("@lune/task")

local Bridge = require(script.Parent.Bridge)
local Codec = require(script.Parent.Codec)

local LuneBridge = setmetatable({}, { __index = Bridge })
LuneBridge.__index = LuneBridge

function LuneBridge.new()
    local self = Bridge.new()
    setmetatable(self, LuneBridge)
    self._outbox = {}        -- Queued outbound envelopes (polled by Roblox)
    self._server = nil
    self._config = nil
    return self
end

--[[
    Start the HTTP server.

    @param config table - See CONFIG section above
]]
function LuneBridge:start(config)
    self._config = {
        port = config.port or 8080,
        authToken = config.authToken or "",
    }
    self._started = true

    self._server = net.serve(self._config.port, function(request)
        return self:_handleRequest(request)
    end)
end

--[[
    Stop the HTTP server.
]]
function LuneBridge:stop()
    self._started = false
    if self._server then
        self._server.stop()
        self._server = nil
    end
end

--[[
    Queue an envelope for outbound delivery (Roblox will poll for it).

    @param envelope table - Transport envelope
]]
function LuneBridge:send(envelope)
    table.insert(self._outbox, envelope)
end

--------------------------------------------------------------------------------
-- PRIVATE: HTTP SERVER
--------------------------------------------------------------------------------

--[[
    Route incoming HTTP requests.
]]
function LuneBridge:_handleRequest(request)
    -- Auth check
    if self._config.authToken ~= "" then
        local auth = request.headers["authorization"] or ""
        local expected = "Bearer " .. self._config.authToken
        if auth ~= expected then
            return {
                status = 401,
                body = '{"error":"unauthorized"}',
            }
        end
    end

    local path = request.path

    if path == "/send" and request.method == "POST" then
        return self:_handleSend(request)
    elseif path == "/poll" and request.method == "GET" then
        return self:_handlePoll()
    elseif path == "/health" and request.method == "GET" then
        return {
            status = 200,
            body = '{"status":"ok","runtime":"lune"}',
        }
    else
        return {
            status = 404,
            body = '{"error":"not found"}',
        }
    end
end

--[[
    Handle POST /send — receive envelopes from Roblox.
]]
function LuneBridge:_handleSend(request)
    local ok, decoded = pcall(Codec.decode, request.body)
    if not ok or not decoded or not decoded.envelopes then
        return {
            status = 400,
            body = '{"error":"invalid payload"}',
        }
    end

    for _, envelope in ipairs(decoded.envelopes) do
        task.spawn(self._dispatch, self, envelope)
    end

    return {
        status = 200,
        body = '{"received":' .. #decoded.envelopes .. '}',
    }
end

--[[
    Handle GET /poll — drain outbox and return queued envelopes to Roblox.
]]
function LuneBridge:_handlePoll()
    local batch = self._outbox
    self._outbox = {}

    local body = Codec.encode({
        envelopes = batch,
    })

    return {
        status = 200,
        headers = { ["Content-Type"] = "application/json" },
        body = body,
    }
end

return LuneBridge
