--[[
    Warren Framework v3.0
    OpenCloud/Messaging.lua - Open Cloud MessagingService Client (Cross-Runtime)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    HTTP client wrapping the Roblox Open Cloud Messaging v1 API.
    Runs on both Roblox and Lune via the Platform abstraction layer.

    Publishes messages to topics that Roblox game servers subscribe to
    via MessagingService:SubscribeAsync().

    This enables push notifications for:
        - Server-wide announcements
        - Player kick/ban commands
        - LiveOps event triggers
        - Cross-server coordination

    ============================================================================
    API REFERENCE
    ============================================================================

    POST https://apis.roblox.com/messaging-service/v1/universes/{universeId}/topics/{topic}
    Body: { "message": "string" }
    Auth: x-api-key header
    Limit: 1KB message size

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Messaging = require(Warren.OpenCloud.Messaging)

    local msg = Messaging.new({
        universeId = "123456789",
        apiKey = "your-open-cloud-api-key",  -- or Roblox Secret object
    })

    -- Publish a string message
    msg:publish("announcements", "Double XP weekend starts now!")

    -- Publish structured data (auto-serialized to JSON string)
    msg:publish("admin.commands", {
        action = "kick",
        playerId = 12345,
        reason = "AFK too long",
    })
    ```

--]]

local _L = script == nil
local Platform = _L and require("@warren/OpenCloud/Platform") or require(script.Parent.Platform)

local Messaging = {}
Messaging.__index = Messaging

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local BASE_URL = "https://apis.roblox.com/messaging-service/v1/universes"
local MAX_MESSAGE_SIZE = 1024  -- 1KB limit per Open Cloud docs

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

--[[
    Create a new Messaging client.

    @param config table:
        - universeId: string (required)
        - apiKey: string|Secret (required) — plain string on Lune, Secret on Roblox
    @return Messaging
]]
function Messaging.new(config)
    assert(config.universeId, "Messaging requires universeId")
    assert(config.apiKey, "Messaging requires apiKey")

    local self = setmetatable({}, Messaging)
    self._universeId = tostring(config.universeId)
    self._apiKey = config.apiKey
    self._baseUrl = BASE_URL .. "/" .. self._universeId .. "/topics"
    return self
end

--------------------------------------------------------------------------------
-- PUBLISH
--------------------------------------------------------------------------------

--[[
    Publish a message to a topic.
    Roblox game servers subscribed to this topic via
    MessagingService:SubscribeAsync() will receive it.

    @param topic string - Topic name
    @param message string|table - Message content. Tables are auto-serialized to JSON.
    @return boolean - true on success
]]
function Messaging:publish(topic, message)
    assert(type(topic) == "string" and #topic > 0, "Topic must be a non-empty string")

    -- Serialize tables to JSON strings
    local messageStr
    if type(message) == "table" then
        messageStr = Platform.jsonEncode(message)
    else
        messageStr = tostring(message)
    end

    -- Size check
    if #messageStr > MAX_MESSAGE_SIZE then
        error("[Warren.OpenCloud.Messaging] Message exceeds 1KB limit ("
            .. #messageStr .. " bytes). Consider splitting or compressing.")
    end

    local url = self._baseUrl .. "/" .. Platform.urlEncode(topic)

    local body = Platform.jsonEncode({
        message = messageStr,
    })

    local response = Platform.request({
        url = url,
        method = "POST",
        headers = {
            ["x-api-key"] = self._apiKey,
            ["content-type"] = "application/json",
        },
        body = body,
    })

    if response.statusCode ~= 200 then
        error("[Warren.OpenCloud.Messaging] publish failed ("
            .. response.statusCode .. "): " .. response.body)
    end

    return true
end

--[[
    Publish to multiple topics in sequence.

    @param topics table - Array of { topic = string, message = string|table }
    @return number - Count of successfully published messages
]]
function Messaging:publishBatch(topics)
    local count = 0
    for _, entry in ipairs(topics) do
        local ok, err = pcall(self.publish, self, entry.topic, entry.message)
        if ok then
            count += 1
        else
            warn("[Warren.OpenCloud.Messaging] Batch publish failed for topic '"
                .. entry.topic .. "': " .. tostring(err))
        end
    end
    return count
end

return Messaging
