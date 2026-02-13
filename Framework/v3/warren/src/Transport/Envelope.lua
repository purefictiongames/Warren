--[[
    Warren Framework v3.0
    Transport/Envelope.lua - Transport Envelope Schema

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Creates and validates transport envelopes — the unit of communication
    between Roblox and Lune runtimes.

    ============================================================================
    ENVELOPE SCHEMA
    ============================================================================

    {
        id      = "unique-id",                -- Dedup + ordering
        ts      = 1707849600.123,             -- os.clock() on sender
        src     = "roblox" | "lune",          -- Origin runtime
        channel = "state.player.inventory",   -- Dot-delimited topic
        action  = "update"|"request"|"response"|"event",
        payload = { ... },                    -- Typed data
        ack     = "id-of-request",            -- Request/response pairing (optional)
    }

--]]

local _L = script == nil
local Runtime = _L and require("@warren/Runtime") or require(script.Parent.Parent.Runtime)

local Envelope = {}

--------------------------------------------------------------------------------
-- ID GENERATION
--------------------------------------------------------------------------------

local _counter = 0
local _prefix = Runtime.context .. "-"

local function generateId()
    _counter += 1
    -- Format: runtime-timestamp-counter (unique per runtime instance)
    return _prefix .. string.format("%.0f", os.clock() * 1000) .. "-" .. _counter
end

--------------------------------------------------------------------------------
-- ACTIONS
--------------------------------------------------------------------------------

Envelope.Action = {
    UPDATE   = "update",    -- State push (Lune → Roblox)
    REQUEST  = "request",   -- Action request (Roblox → Lune)
    RESPONSE = "response",  -- Action result (Lune → Roblox)
    EVENT    = "event",     -- Fire-and-forget notification (either direction)
}

local VALID_ACTIONS = {}
for _, v in pairs(Envelope.Action) do
    VALID_ACTIONS[v] = true
end

--------------------------------------------------------------------------------
-- CREATION
--------------------------------------------------------------------------------

--[[
    Create a new transport envelope.

    @param options table:
        - channel: string (required) - Dot-delimited topic
        - action: string (required) - One of Envelope.Action values
        - payload: table (optional) - Data to send
        - ack: string (optional) - ID of request being responded to
    @return table - Envelope
]]
function Envelope.create(options)
    assert(type(options.channel) == "string", "Envelope requires a channel")
    assert(VALID_ACTIONS[options.action], "Envelope requires a valid action")

    return {
        id      = generateId(),
        ts      = os.clock(),
        src     = Runtime.context,
        channel = options.channel,
        action  = options.action,
        payload = options.payload or {},
        ack     = options.ack,
    }
end

--[[
    Create a response envelope for a given request.

    @param request table - The original request envelope
    @param payload table - Response data
    @return table - Response envelope on the same channel
]]
function Envelope.respond(request, payload)
    return Envelope.create({
        channel = request.channel,
        action  = Envelope.Action.RESPONSE,
        payload = payload,
        ack     = request.id,
    })
end

--------------------------------------------------------------------------------
-- VALIDATION
--------------------------------------------------------------------------------

--[[
    Validate an envelope has all required fields and correct types.

    @param envelope table
    @return boolean, string? - true if valid, false + reason if not
]]
function Envelope.validate(envelope)
    if type(envelope) ~= "table" then
        return false, "Envelope must be a table"
    end
    if type(envelope.id) ~= "string" then
        return false, "Envelope missing id"
    end
    if type(envelope.ts) ~= "number" then
        return false, "Envelope missing ts"
    end
    if envelope.src ~= "roblox" and envelope.src ~= "lune" then
        return false, "Envelope src must be 'roblox' or 'lune'"
    end
    if type(envelope.channel) ~= "string" then
        return false, "Envelope missing channel"
    end
    if not VALID_ACTIONS[envelope.action] then
        return false, "Envelope has invalid action: " .. tostring(envelope.action)
    end
    return true
end

return Envelope
