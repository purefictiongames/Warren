--[[
    Warren Framework v3.0
    State/Sync.lua - State Synchronization Coordinator

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Ties the State store to the Transport layer for bidirectional
    synchronization between Roblox and Lune.

    On Lune (authoritative):
        - Watches the local Store for changes
        - Generates diffs and pushes them via Transport
        - Handles incoming action requests from Roblox
        - Sends full snapshots on player join

    On Roblox (consumer):
        - Receives state patches from Lune via Transport
        - Applies patches to the local Store replica
        - Requests full snapshot on connect/reconnect
        - Detects missed versions and triggers resync

    ============================================================================
    CHANNELS
    ============================================================================

    state.sync.snapshot     Full-state snapshot (join/reconnect)
    state.sync.patch        Incremental diff patch
    state.sync.resync       Client requests full resync
    state.action.*          Action requests (Roblox → Lune)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Sync = require(Warren.State.Sync)

    -- Lune side: start as authority
    Sync.startAuthority(store, {
        pushInterval = 0.1,  -- Batch and push diffs every 100ms
    })

    -- Roblox side: start as replica
    Sync.startReplica(store, {
        onResync = function() print("Resynced from server") end,
    })
    ```

--]]

local _L = script == nil
local task = _L and require("@lune/task") or task
local Runtime = _L and require("@warren/Runtime") or require(script.Parent.Parent.Runtime)
local Diff = _L and require("@warren/State/Diff") or require(script.Parent.Diff)

local Sync = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _store = nil
local _transport = nil  -- Set by init.lua wiring
local _mode = nil        -- "authority" or "replica"
local _lastPushedVersion = 0
local _lastReceivedVersion = 0
local _pushThread = nil
local _started = false
local _config = {}
local _actionHandlers = {}  -- channel → handler

--------------------------------------------------------------------------------
-- TRANSPORT BINDING
--------------------------------------------------------------------------------

--[[
    Bind the Transport module. Called during Warren initialization
    so Sync doesn't need to require Transport directly (avoids cycles).

    @param transport table - Warren.Transport module
]]
function Sync.bindTransport(transport)
    _transport = transport
end

--------------------------------------------------------------------------------
-- AUTHORITY MODE (Lune)
--------------------------------------------------------------------------------

--[[
    Start as the authoritative state server.
    Watches the store for changes and pushes diffs to Roblox clients.

    @param store Store - The authoritative state store
    @param config table? - { pushInterval = number }
]]
function Sync.startAuthority(store, config)
    assert(not _started, "Sync already started")
    assert(_transport, "Transport not bound — call Sync.bindTransport() first")

    _store = store
    _mode = "authority"
    _config = config or {}
    _config.pushInterval = _config.pushInterval or 0.1
    _started = true
    _lastPushedVersion = store:getVersion()

    -- Listen for resync requests from Roblox
    _transport.listen("state.sync.resync", function(envelope)
        Sync._handleResyncRequest(envelope)
    end)

    -- Listen for action requests from Roblox
    _transport.listen("state.action.*", function(envelope)
        Sync._handleActionRequest(envelope)
    end)

    -- Start diff push loop
    _pushThread = task.spawn(function()
        while _started do
            Sync._pushDiffs()
            task.wait(_config.pushInterval)
        end
    end)
end

--[[
    Register a handler for an action channel.
    When Roblox sends a request on this channel, the handler is called
    and its return value is sent back as the response payload.

    @param channel string - Action channel (e.g. "state.action.buy")
    @param handler function(payload, envelope) → table - Handler that returns response data
]]
function Sync.onAction(channel, handler)
    _actionHandlers[channel] = handler
end

--[[
    Push pending diffs to connected Roblox clients.
]]
function Sync._pushDiffs()
    local currentVersion = _store:getVersion()
    if currentVersion == _lastPushedVersion then
        return  -- No changes
    end

    local changes, complete = _store:getChangesSince(_lastPushedVersion)
    if not complete then
        -- Log was truncated — shouldn't happen in authority push loop
        -- but if it does, connected clients will detect the gap and resync
        _lastPushedVersion = currentVersion
        return
    end

    local ops, maxVersion = Diff.fromChangeLog(changes)

    _transport.update("state.sync.patch", {
        ops = ops,
        fromVersion = _lastPushedVersion,
        toVersion = maxVersion,
    })

    _lastPushedVersion = maxVersion
end

--[[
    Handle a resync request from a Roblox client.
]]
function Sync._handleResyncRequest(envelope)
    local snapshot = _store:snapshot()

    -- Respond with full snapshot
    _transport.sendRaw(
        _transport.Envelope.respond(envelope, {
            snapshot = snapshot,
        })
    )
end

--[[
    Handle an action request from Roblox.
    Dispatches to registered action handlers.
]]
function Sync._handleActionRequest(envelope)
    local handler = _actionHandlers[envelope.channel]
    if not handler then
        -- No handler registered — respond with rejection
        _transport.sendRaw(
            _transport.Envelope.respond(envelope, {
                status = "rejected",
                reason = "no_handler",
            })
        )
        return
    end

    -- Call the handler
    local ok, result = pcall(handler, envelope.payload, envelope)

    if ok and result then
        result.status = result.status or "ok"
        _transport.sendRaw(
            _transport.Envelope.respond(envelope, result)
        )
    else
        _transport.sendRaw(
            _transport.Envelope.respond(envelope, {
                status = "error",
                reason = ok and "handler returned nil" or tostring(result),
            })
        )
    end
end

--------------------------------------------------------------------------------
-- REPLICA MODE (Roblox)
--------------------------------------------------------------------------------

--[[
    Start as a state replica.
    Receives patches from Lune and applies them to the local store copy.

    @param store Store - The local replica store
    @param config table? - { onResync = function? }
]]
function Sync.startReplica(store, config)
    assert(not _started, "Sync already started")
    assert(_transport, "Transport not bound — call Sync.bindTransport() first")

    _store = store
    _mode = "replica"
    _config = config or {}
    _started = true
    _lastReceivedVersion = 0

    -- Listen for state patches
    _transport.listen("state.sync.patch", function(envelope)
        Sync._handlePatch(envelope)
    end)

    -- Listen for snapshot responses (from resync)
    _transport.listen("state.sync.snapshot", function(envelope)
        Sync._handleSnapshot(envelope)
    end)

    -- Request initial state
    Sync.requestResync()
end

--[[
    Request a full state resync from the authority.
]]
function Sync.requestResync()
    local response = _transport.request("state.sync.resync", {
        lastVersion = _lastReceivedVersion,
    })

    if response and response.snapshot then
        _store:loadSnapshot(response.snapshot)
        _lastReceivedVersion = response.snapshot.version

        if _config.onResync then
            task.spawn(_config.onResync)
        end
    end
end

--[[
    Handle an incoming state patch from Lune.
]]
function Sync._handlePatch(envelope)
    local payload = envelope.payload
    if not payload or not payload.ops then
        return
    end

    -- Version continuity check
    if payload.fromVersion ~= _lastReceivedVersion then
        -- Gap detected — we missed updates. Request full resync.
        warn("[Warren.Sync] Version gap detected: expected "
            .. _lastReceivedVersion .. ", got fromVersion " .. payload.fromVersion
            .. ". Requesting resync.")
        Sync.requestResync()
        return
    end

    -- Apply the patch
    Diff.apply(_store._data, payload.ops)
    _store._version = payload.toVersion
    _lastReceivedVersion = payload.toVersion

    -- Notify store listeners for each changed path
    for _, op in ipairs(payload.ops) do
        _store:_notifyListeners(op.path, op.value, nil)
    end
end

--[[
    Handle a snapshot response (from resync request).
]]
function Sync._handleSnapshot(envelope)
    local payload = envelope.payload
    if payload and payload.snapshot then
        _store:loadSnapshot(payload.snapshot)
        _lastReceivedVersion = payload.snapshot.version

        if _config.onResync then
            task.spawn(_config.onResync)
        end
    end
end

--------------------------------------------------------------------------------
-- SHARED
--------------------------------------------------------------------------------

--[[
    Stop the sync coordinator.
]]
function Sync.stop()
    _started = false
    _store = nil
    _mode = nil
end

--[[
    Get the current sync mode.

    @return string? - "authority" or "replica", or nil if not started
]]
function Sync.getMode()
    return _mode
end

return Sync
