--[[
    Warren Framework v3.0
    OpenCloud/init.lua - Open Cloud Client Public API (Cross-Runtime)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Cross-runtime module providing HTTP clients for the Roblox Open Cloud API.

    On Lune:   API keys come from environment variables.
    On Roblox: API keys come from game Secrets (opaque Secret objects that
               work as HTTP header values via the "Open Cloud via HttpService
               Without Proxies" beta).

    Currently wraps:
        - DataStore v1 API (get/set/list/delete entries)
        - MessagingService v1 API (publish to topics)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local OpenCloud = Warren.OpenCloud

    -- Create clients with your API key
    local config = {
        universeId = "123456789",
        apiKey = apiKey,  -- string on Lune, Secret on Roblox
    }

    local datastore = OpenCloud.DataStore.new(config)
    local messaging = OpenCloud.Messaging.new(config)

    -- Use them
    local playerData = datastore:getEntry("PlayerData", "Player_001")
    messaging:publish("announcements", "Server maintenance in 5 minutes")
    ```

--]]

local _L = script == nil

local OpenCloud = {}

OpenCloud.DataStore = _L and require("@warren/OpenCloud/DataStore") or require(script.DataStore)
OpenCloud.Messaging = _L and require("@warren/OpenCloud/Messaging") or require(script.Messaging)
OpenCloud.Platform = _L and require("@warren/OpenCloud/Platform") or require(script.Platform)

return OpenCloud
