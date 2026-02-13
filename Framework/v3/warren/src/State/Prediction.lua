--[[
    Warren Framework v3.0
    State/Prediction.lua - Optimistic Update Prediction Queue

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Roblox-side optimistic update system. Applies local predictions
    immediately for responsive UX, then reconciles when the Lune authority
    confirms or rejects.

    Flow:
        1. Player acts (e.g. "buy sword")
        2. Prediction applied locally — UI updates instantly
        3. Request sent to Lune via Transport
        4a. Lune confirms → prediction drained from queue (no-op)
        4b. Lune rejects → prediction rolled back, UI corrects

    ============================================================================
    ROLLBACK UX
    ============================================================================

    - Soft rollback: State silently corrects. UI elements animate back.
      Used for most cases (lag compensation, minor desync).

    - Hard rollback: Brief toast/flash. "Not enough gold."
      Used when the player explicitly attempted something that failed.

    - Never: No technical error messages reach the player.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Prediction = require(Warren.State.Prediction)

    Prediction.start(store)

    -- Predict and request in one call
    local seq = Prediction.predict({
        channel = "state.action.buy",
        ops = {
            { op = "set", path = "player.p123.gold", value = 450 },
            { op = "insert", path = "player.p123.inventory", value = { id = "sword_02" } },
        },
        request = { itemId = "sword_02", cost = 50 },
    })

    -- On rejection, register a callback for user feedback
    Prediction.onReject(function(seq, reason)
        -- Show brief "Not enough gold" toast
    end)
    ```

--]]

local Runtime = require(script.Parent.Parent.Runtime)
local Diff = require(script.Parent.Diff)

local Prediction = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _store = nil
local _transport = nil
local _started = false
local _sequence = 0
local _pending = {}        -- seq → { ops, inverseOps, channel, timestamp }
local _rejectCallbacks = {}
local _confirmCallbacks = {}
local _maxPending = 32     -- Ring buffer size — oldest predictions auto-expire

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

--[[
    Bind the Transport module.

    @param transport table - Warren.Transport module
]]
function Prediction.bindTransport(transport)
    _transport = transport
end

--[[
    Start the prediction queue.

    @param store Store - The local replica store
]]
function Prediction.start(store)
    assert(not _started, "Prediction already started")
    assert(_transport, "Transport not bound — call Prediction.bindTransport() first")

    _store = store
    _started = true

    -- Listen for responses to our action requests
    _transport.listen("state.action.*", function(envelope)
        if envelope.action == "response" and envelope.ack then
            Prediction._handleResponse(envelope)
        end
    end)
end

--[[
    Stop the prediction queue and roll back all pending predictions.
]]
function Prediction.stop()
    -- Roll back all pending predictions in reverse order
    Prediction._rollbackAll()
    _started = false
    _store = nil
    _pending = {}
    _sequence = 0
end

--------------------------------------------------------------------------------
-- PREDICT
--------------------------------------------------------------------------------

--[[
    Apply an optimistic prediction and send the action request.

    @param options table:
        - channel: string - Action channel (e.g. "state.action.buy")
        - ops: table - Diff operations to apply optimistically
        - request: table - Payload to send to Lune
        - timeout: number? - Request timeout in seconds (default 10)
    @return number - Sequence number for this prediction
]]
function Prediction.predict(options)
    assert(_started, "Prediction not started")
    assert(options.channel, "Prediction requires a channel")
    assert(options.ops, "Prediction requires ops")

    _sequence += 1
    local seq = _sequence

    -- Snapshot state at the paths we're about to change, for rollback
    local inverseOps = Diff.invert(_store._data, options.ops)

    -- Apply optimistic ops to the local store
    Diff.apply(_store._data, options.ops)
    _store._version += 1

    -- Notify store listeners for immediate UI update
    for _, op in ipairs(options.ops) do
        _store:_notifyListeners(op.path, op.value, nil)
    end

    -- Queue the prediction
    _pending[seq] = {
        ops = options.ops,
        inverseOps = inverseOps,
        channel = options.channel,
        timestamp = os.clock(),
        requestId = nil,  -- Will be set when we send
    }

    -- Trim old predictions if over max
    Prediction._trimPending()

    -- Send the request to Lune
    task.spawn(function()
        local envelope = _transport.Envelope.create({
            channel = options.channel,
            action = _transport.Action.REQUEST,
            payload = options.request or {},
        })

        -- Track the envelope ID for response matching
        if _pending[seq] then
            _pending[seq].requestId = envelope.id
        end

        _transport.sendRaw(envelope)
    end)

    return seq
end

--------------------------------------------------------------------------------
-- RESPONSE HANDLING
--------------------------------------------------------------------------------

--[[
    Handle a response from Lune to one of our action requests.
]]
function Prediction._handleResponse(envelope)
    -- Find the pending prediction by request ID
    local matchedSeq = nil
    for seq, prediction in pairs(_pending) do
        if prediction.requestId == envelope.ack then
            matchedSeq = seq
            break
        end
    end

    if not matchedSeq then
        return  -- Response for an expired or unknown prediction
    end

    local prediction = _pending[matchedSeq]
    local payload = envelope.payload or {}

    if payload.status == "ok" then
        -- Confirmed — drain from queue, prediction was correct
        _pending[matchedSeq] = nil

        -- Fire confirm callbacks
        for _, cb in ipairs(_confirmCallbacks) do
            task.spawn(cb, matchedSeq, payload)
        end
    else
        -- Rejected — roll back this prediction
        Prediction._rollback(matchedSeq, payload.reason or "rejected")
    end
end

--------------------------------------------------------------------------------
-- ROLLBACK
--------------------------------------------------------------------------------

--[[
    Roll back a single prediction by applying its inverse ops.
]]
function Prediction._rollback(seq, reason)
    local prediction = _pending[seq]
    if not prediction then
        return
    end

    -- Apply inverse operations
    Diff.apply(_store._data, prediction.inverseOps)
    _store._version += 1

    -- Notify listeners for UI correction
    for _, op in ipairs(prediction.inverseOps) do
        _store:_notifyListeners(op.path, op.value, nil)
    end

    _pending[seq] = nil

    -- Fire reject callbacks
    for _, cb in ipairs(_rejectCallbacks) do
        task.spawn(cb, seq, reason)
    end
end

--[[
    Roll back all pending predictions (e.g. on disconnect or resync).
    Rolls back in reverse sequence order to maintain consistency.
]]
function Prediction._rollbackAll()
    -- Collect and sort sequences in reverse order
    local seqs = {}
    for seq in pairs(_pending) do
        table.insert(seqs, seq)
    end
    table.sort(seqs, function(a, b) return a > b end)

    for _, seq in ipairs(seqs) do
        Prediction._rollback(seq, "rollback_all")
    end
end

--[[
    Trim the pending queue if it exceeds max size.
    Oldest predictions are auto-confirmed (assumed successful if no response).
]]
function Prediction._trimPending()
    local seqs = {}
    for seq in pairs(_pending) do
        table.insert(seqs, seq)
    end

    if #seqs <= _maxPending then
        return
    end

    table.sort(seqs)
    while #seqs > _maxPending do
        local oldestSeq = table.remove(seqs, 1)
        _pending[oldestSeq] = nil  -- Silently expire
    end
end

--------------------------------------------------------------------------------
-- CALLBACKS
--------------------------------------------------------------------------------

--[[
    Register a callback for when a prediction is rejected.

    @param callback function(seq, reason) - Called on rejection
    @return function - Unsubscribe function
]]
function Prediction.onReject(callback)
    table.insert(_rejectCallbacks, callback)
    local index = #_rejectCallbacks
    return function()
        table.remove(_rejectCallbacks, index)
    end
end

--[[
    Register a callback for when a prediction is confirmed.

    @param callback function(seq, payload) - Called on confirmation
    @return function - Unsubscribe function
]]
function Prediction.onConfirm(callback)
    table.insert(_confirmCallbacks, callback)
    local index = #_confirmCallbacks
    return function()
        table.remove(_confirmCallbacks, index)
    end
end

--------------------------------------------------------------------------------
-- QUERY
--------------------------------------------------------------------------------

--[[
    Get the number of unconfirmed predictions.

    @return number
]]
function Prediction.pendingCount()
    local count = 0
    for _ in pairs(_pending) do
        count += 1
    end
    return count
end

--[[
    Check if there are any unconfirmed predictions.

    @return boolean
]]
function Prediction.hasPending()
    return next(_pending) ~= nil
end

return Prediction
