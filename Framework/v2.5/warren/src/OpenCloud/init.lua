--[[
    Warren Framework v3.0
    OpenCloud/init.lua - Open Cloud Client Public API

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Lune-only module providing HTTP clients for the Roblox Open Cloud API.
    API keys live on the Lune VPS and are never exposed to Roblox clients.

    Currently wraps:
        - DataStore v1 API (get/set/list/delete entries)
        - MessagingService v1 API (publish to topics)

    Future:
        - Assets API (upload/manage)
        - Groups API (manage group membership)
        - Inventory API (read player inventories)
        - Luau Execution API (run scripts in-universe)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local OpenCloud = Warren.OpenCloud

    -- Create clients with your API key
    local config = {
        universeId = "123456789",
        apiKey = os.getenv("ROBLOX_API_KEY"),
    }

    local datastore = OpenCloud.DataStore.new(config)
    local messaging = OpenCloud.Messaging.new(config)

    -- Use them
    local playerData = datastore:getEntry("PlayerData", "Player_001")
    messaging:publish("announcements", "Server maintenance in 5 minutes")
    ```

--]]

local OpenCloud = {}

OpenCloud.DataStore = require(script.DataStore)
OpenCloud.Messaging = require(script.Messaging)

return OpenCloud
