--[[
    Warren Framework v3.0
    State/init.lua - State System Public API

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Unified state management for the dual-runtime architecture.
    Provides a versioned store, diff engine, sync coordinator,
    and optimistic prediction queue.

    Lune is authoritative — it owns the Store and pushes diffs.
    Roblox is a replica — it receives patches and applies them locally,
    with optimistic predictions for responsive UX.

    ============================================================================
    USAGE
    ============================================================================

    Lune (authority):
    ```lua
    local State = Warren.State
    local store = State.createStore()

    store:set("world.time", 0)
    store:set("player.p123.gold", 500)

    State.Sync.startAuthority(store)

    State.Sync.onAction("state.action.buy", function(payload)
        local player = store:get("player." .. payload.playerId)
        if player.gold >= payload.cost then
            store:set("player." .. payload.playerId .. ".gold", player.gold - payload.cost)
            store:insert("player." .. payload.playerId .. ".inventory", { id = payload.itemId })
            return { status = "ok" }
        else
            return { status = "rejected", reason = "insufficient_gold" }
        end
    end)
    ```

    Roblox (replica):
    ```lua
    local State = Warren.State
    local store = State.createStore()

    State.Sync.startReplica(store)

    -- Optimistic purchase
    State.Prediction.predict({
        channel = "state.action.buy",
        ops = {
            { op = "set", path = "player.p123.gold", value = 450 },
        },
        request = { playerId = "p123", itemId = "sword_02", cost = 50 },
    })

    -- React to rejection
    State.Prediction.onReject(function(seq, reason)
        if reason == "insufficient_gold" then
            -- Show "Not enough gold" toast
        end
    end)

    -- Subscribe to state changes
    store:onChange("player.p123.gold", function(newVal, oldVal)
        updateGoldUI(newVal)
    end)
    ```

--]]

local _L = script == nil
local Runtime = _L and require("@warren/Runtime") or require(script.Parent.Runtime)

local State = {}

-- Core modules (shared, both runtimes)
State.Store = _L and require("@warren/State/Store") or require(script.Store)
State.Diff = _L and require("@warren/State/Diff") or require(script.Diff)
State.Sync = _L and require("@warren/State/Sync") or require(script.Sync)

-- Prediction queue (Roblox-only — Lune doesn't predict, it decides)
if Runtime.isRoblox then
    State.Prediction = require(script.Prediction)
end

--------------------------------------------------------------------------------
-- CONVENIENCE
--------------------------------------------------------------------------------

--[[
    Create a new state store instance.

    @return Store
]]
function State.createStore()
    return State.Store.new()
end

--[[
    Wire up Transport bindings for Sync and Prediction.
    Called by Warren init after Transport is loaded.

    @param transport table - Warren.Transport module
]]
function State.bindTransport(transport)
    State.Sync.bindTransport(transport)
    if State.Prediction then
        State.Prediction.bindTransport(transport)
    end
end

return State
