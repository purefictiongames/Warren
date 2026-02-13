--[[
    Warren Framework v3.0
    Boot/init.lua - Lune Bootstrap Sequence

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    The Lune-side equivalent of Roblox's game startup. Initializes Warren
    in a headless environment with no `game`, no `workspace`, no `RunService`.

    Boot sequence:
        1. Validate runtime (must be Lune)
        2. Load configuration from environment or config file
        3. Initialize Transport (HTTP server)
        4. Initialize State store (authoritative)
        5. Initialize OpenCloud clients
        6. Start Sync authority
        7. Signal ready

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- server.lua (Lune entry point)
    local Warren = require("warren")
    local Boot = Warren.Boot

    Boot.start({
        -- Transport
        port = 8080,
        authToken = os.getenv("WARREN_AUTH_TOKEN"),

        -- Open Cloud
        universeId = os.getenv("ROBLOX_UNIVERSE_ID"),
        apiKey = os.getenv("ROBLOX_API_KEY"),

        -- State
        pushInterval = 0.1,

        -- Lifecycle
        onReady = function(ctx)
            print("Warren Lune server ready on port " .. ctx.port)
            print("Universe: " .. ctx.universeId)
        end,
    })
    ```

    The Boot module returns a context object with references to all
    initialized subsystems, so game logic can wire into them:

    ```lua
    local ctx = Boot.start(config)

    -- Register action handlers
    ctx.sync.onAction("state.action.buy", function(payload)
        -- handle purchase
    end)

    -- Access datastore
    local data = ctx.datastore:getEntry("PlayerData", "Player_001")

    -- Publish to game servers
    ctx.messaging:publish("events", { type = "double_xp", duration = 3600 })
    ```

--]]

local _L = script == nil
local Runtime = _L and require("@warren/Runtime") or require(script.Parent.Runtime)

local Boot = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _context = nil
local _started = false

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------

--[[
    Start the Lune-side Warren server.

    @param config table - See USAGE section for all options
    @return table - Context object with references to all subsystems
]]
function Boot.start(config)
    assert(Runtime.isLune, "Boot.start() can only be called on Lune")
    assert(not _started, "Boot already started")
    assert(config, "Boot.start() requires a config table")

    local stdio = require("@lune/stdio")

    stdio.write("[Warren.Boot] Starting Lune server...\n")

    -- -------------------------------------------------------------------------
    -- 1. VALIDATE CONFIG
    -- -------------------------------------------------------------------------

    assert(config.universeId, "Boot requires universeId")
    assert(config.apiKey, "Boot requires apiKey")

    local port = config.port or 8080
    local authToken = config.authToken or ""
    local pushInterval = config.pushInterval or 0.1

    -- -------------------------------------------------------------------------
    -- 2. INITIALIZE STATE STORE
    -- -------------------------------------------------------------------------

    local State = _L and require("@warren/State") or require(script.Parent.State)
    local store = State.createStore()

    stdio.write("[Warren.Boot] State store initialized\n")

    -- -------------------------------------------------------------------------
    -- 3. INITIALIZE TRANSPORT
    -- -------------------------------------------------------------------------

    local Transport = _L and require("@warren/Transport") or require(script.Parent.Transport)
    State.bindTransport(Transport)

    Transport.start({
        port = port,
        authToken = authToken,
    })

    stdio.write("[Warren.Boot] Transport server listening on port " .. tostring(port) .. "\n")

    -- -------------------------------------------------------------------------
    -- 4. INITIALIZE OPEN CLOUD CLIENTS
    -- -------------------------------------------------------------------------

    local OpenCloud = _L and require("@warren/OpenCloud") or require(script.Parent.OpenCloud)

    local cloudConfig = {
        universeId = config.universeId,
        apiKey = config.apiKey,
    }

    local datastore = OpenCloud.DataStore.new(cloudConfig)
    local messaging = OpenCloud.Messaging.new(cloudConfig)

    stdio.write("[Warren.Boot] Open Cloud clients initialized (universe "
        .. config.universeId .. ")\n")

    -- -------------------------------------------------------------------------
    -- 5. START SYNC AUTHORITY
    -- -------------------------------------------------------------------------

    local Sync = State.Sync
    Sync.startAuthority(store, {
        pushInterval = pushInterval,
    })

    stdio.write("[Warren.Boot] Sync authority started (push interval "
        .. tostring(pushInterval) .. "s)\n")

    -- -------------------------------------------------------------------------
    -- 6. BUILD CONTEXT
    -- -------------------------------------------------------------------------

    _context = {
        -- Config
        port = port,
        universeId = config.universeId,

        -- Subsystems
        store = store,
        transport = Transport,
        sync = Sync,
        state = State,
        datastore = datastore,
        messaging = messaging,
        opencloud = OpenCloud,

        -- Convenience: register an action handler
        onAction = function(channel, handler)
            Sync.onAction(channel, handler)
        end,
    }

    _started = true

    -- -------------------------------------------------------------------------
    -- 7. SIGNAL READY
    -- -------------------------------------------------------------------------

    stdio.write("[Warren.Boot] Ready.\n")

    if config.onReady then
        config.onReady(_context)
    end

    return _context
end

--[[
    Get the current boot context.

    @return table? - Context object, or nil if not started
]]
function Boot.getContext()
    return _context
end

--[[
    Stop the Lune server and clean up all subsystems.
]]
function Boot.stop()
    if not _started then
        return
    end

    local stdio = require("@lune/stdio")
    stdio.write("[Warren.Boot] Shutting down...\n")

    if _context then
        _context.sync.stop()
        _context.transport.stop()
    end

    _context = nil
    _started = false

    stdio.write("[Warren.Boot] Stopped.\n")
end

--[[
    Check if the boot sequence has completed.

    @return boolean
]]
function Boot.isReady()
    return _started
end

return Boot
