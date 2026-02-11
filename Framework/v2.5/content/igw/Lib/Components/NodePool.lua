--[[
    LibPureFiction Framework v2
    NodePool.lua - Generic Node Pool Manager Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    NodePool manages a pool of reusable Node instances. Instead of creating
    and destroying nodes dynamically, the pool maintains a set of nodes that
    can be checked out for work and returned when done.

    Supports two modes:
    - Fixed: Pre-allocate N nodes, never grow/shrink
    - Elastic: Grow on demand up to max, shrink when idle

    Key features:
    - Generic: Works with any Node component class
    - Auto-release: Listens for configurable signal to auto-return nodes
    - Checkout signals: Automatically sends configured signals on checkout
    - Context injection: Shared data available to all pooled nodes

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ nodeClass, poolMode, poolSize, minSize, maxSize, ... })
            - Configure the pool (see CONFIGURATION section)

        onCheckout({ entity?, entityId?, ... })
            - Request a node from the pool
            - Additional data passed to checkout signals
            - Returns immediately, fires checkedOut or exhausted

        onRelease({ entityId })
            - Manually return a node to the pool by entityId

        onReleaseAll()
            - Return all checked-out nodes to the pool

        onDestroy()
            - Destroy all nodes and reset pool

    OUT (emits):
        checkedOut({ nodeId: string, entityId: string, node: Node })
            - Fired when a node is successfully checked out

        released({ nodeId: string, entityId: string })
            - Fired when a node is returned to the pool

        exhausted({ entityId: string, queuePosition?: number })
            - Fired when no nodes available and at max capacity

        nodeCreated({ nodeId: string })
            - Fired when a new node is created (elastic mode)

        nodeDestroyed({ nodeId: string })
            - Fired when an idle node is destroyed (elastic shrink)

    ============================================================================
    CONFIGURATION
    ============================================================================

    onConfigure data:
        nodeClass: string | table
            - Class name (string) to lookup in Lib.Components, or
            - Class table directly (e.g., Lib.Components.PathFollower)

        poolMode: "fixed" | "elastic" (default "elastic")
            - fixed: Pre-allocate poolSize nodes
            - elastic: Grow/shrink between minSize and maxSize

        -- Fixed mode
        poolSize: number (default 5)
            - Number of nodes to pre-allocate

        -- Elastic mode
        minSize: number (default 0)
            - Minimum nodes to keep (even when idle)
        maxSize: number (default 50)
            - Maximum nodes (cap growth)
        shrinkDelay: number (default 10)
            - Seconds a node must be idle before destroying

        nodeConfig: table (optional)
            - Config passed to each node's onConfigure

        checkoutSignals: table (optional)
            - Signals to send to node on checkout
            - Format: { { signal = "onFoo", map = { nodeField = "checkoutField" } }, ... }
            - Use "$contextKey" to reference context values

        releaseOn: string (optional)
            - Signal name that triggers auto-release (e.g., "pathComplete")

        context: table (optional)
            - Shared data available via "$key" in signal mapping

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local pool = NodePool:new({ id = "PathFollowerPool" })
    pool.Sys.onInit(pool)

    pool.In.onConfigure(pool, {
        nodeClass = "PathFollower",
        poolMode = "elastic",
        minSize = 2,
        maxSize = 10,
        shrinkDelay = 15,
        nodeConfig = { speed = 16 },
        checkoutSignals = {
            { signal = "onControl", map = { entity = "entity", entityId = "entityId" } },
            { signal = "onWaypoints", map = { targets = "$waypoints" } },
        },
        releaseOn = "pathComplete",
        context = {
            waypoints = { workspace.WP1, workspace.WP2, workspace.WP3 },
        },
    })

    -- Wire dropper to pool
    dropper.Out.spawned -> pool.In.onCheckout
    ```

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- NODEPOOL NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local NodePool = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Pool state
                available = {},        -- Array of available nodes (stack)
                inUse = {},            -- { [entityId] = { node, nodeId, checkoutTime } }
                allNodes = {},         -- { [nodeId] = node } all nodes in pool
                lastActivity = {},     -- { [nodeId] = timestamp } for shrink
                nodeCounter = 0,       -- For generating unique IDs
                configured = false,
                shrinkTask = nil,

                -- Configuration (set via onConfigure)
                nodeClass = nil,       -- The class to instantiate
                nodeClassName = nil,   -- String name for IDs
                poolMode = "elastic",
                poolSize = 5,
                minSize = 0,
                maxSize = 50,
                shrinkDelay = 10,
                nodeConfig = {},
                checkoutSignals = {},
                releaseOn = nil,
                context = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Get total node count (available + in use).
    --]]
    local function getTotalNodeCount(self)
        local state = getState(self)
        local count = 0
        for _ in pairs(state.allNodes) do
            count = count + 1
        end
        return count
    end

    -- Forward declarations for mutual recursion
    local createNode
    local releaseNode
    local checkForShrink

    --[[
        Private: Reset a node for reuse.
    --]]
    local function resetNode(self, node)
        -- Clear internal state that PathFollower or other nodes might have
        -- Note: These are properties that may have been set on nodes before
        -- the closure migration. After full migration, nodes won't have
        -- these properties directly accessible anyway.
        node._entity = nil
        node._entityId = nil
        node._waypoints = nil
        node._currentIndex = 0
        node._paused = false
        node._stopped = false
        node._navigating = false
        node._interrupted = false

        -- Disconnect any auto-release listener
        if node._poolAutoReleaseConnection then
            node._poolAutoReleaseConnection:Disconnect()
            node._poolAutoReleaseConnection = nil
        end

        -- Restore original OutChannel (create fresh one)
        -- Import OutChannel pattern from Node
        local OutChannel = {}
        OutChannel.__index = OutChannel

        function OutChannel.new(targetNode)
            local outSelf = setmetatable({}, OutChannel)
            outSelf._node = targetNode
            return outSelf
        end

        function OutChannel:Fire(signal, data)
            -- Stub - will be rewired on next checkout
            if self._node._ipcSend then
                self._node._ipcSend(self._node.id, signal, data)
            end
        end

        node.Out = OutChannel.new(node)
    end

    --[[
        Private: Pre-allocate nodes.
    --]]
    local function preallocate(self, count)
        local state = getState(self)
        for i = 1, count do
            local node = createNode(self)
            if node then
                table.insert(state.available, node)
            end
        end
    end

    --[[
        Private: Create a new pooled node.
    --]]
    createNode = function(self)
        local state = getState(self)

        if not state.nodeClass then
            return nil
        end

        state.nodeCounter = state.nodeCounter + 1
        local nodeId = self.id .. "_" .. state.nodeClassName .. "_" .. state.nodeCounter

        local node = state.nodeClass:new({
            id = nodeId,
        })

        -- Initialize
        if node.Sys and node.Sys.onInit then
            node.Sys.onInit(node)
        end

        -- Configure
        if node.In and node.In.onConfigure and state.nodeConfig then
            node.In.onConfigure(node, state.nodeConfig)
        end

        -- Track
        state.allNodes[nodeId] = node
        state.lastActivity[nodeId] = os.clock()

        -- Fire nodeCreated
        self.Out:Fire("nodeCreated", {
            nodeId = nodeId,
            poolId = self.id,
        })

        return node
    end

    --[[
        Private: Get an available node from the pool.
    --]]
    local function getAvailableNode(self)
        local state = getState(self)
        if #state.available > 0 then
            return table.remove(state.available)
        end
        return nil
    end

    --[[
        Private: Release a node back to the pool.
    --]]
    releaseNode = function(self, entityId)
        local state = getState(self)
        local record = state.inUse[entityId]
        if not record then
            return false
        end

        local node = record.node
        local nodeId = record.nodeId

        -- Clear from in-use
        state.inUse[entityId] = nil

        -- Reset node state
        resetNode(self, node)

        -- Update activity timestamp
        state.lastActivity[nodeId] = os.clock()

        -- Return to available pool
        table.insert(state.available, node)

        -- Fire released
        self.Out:Fire("released", {
            nodeId = nodeId,
            entityId = entityId,
            poolId = self.id,
        })

        return true
    end

    --[[
        Private: Send checkout signals to a node.
    --]]
    local function sendCheckoutSignals(self, node, checkoutData)
        local state = getState(self)

        for _, signalDef in ipairs(state.checkoutSignals) do
            local signal = signalDef.signal
            local mapping = signalDef.map or {}

            -- Build data for this signal
            local signalData = {}
            for nodeField, sourceField in pairs(mapping) do
                local value

                if type(sourceField) == "string" and string.sub(sourceField, 1, 1) == "$" then
                    -- Context reference
                    local contextKey = string.sub(sourceField, 2)
                    value = state.context[contextKey]
                else
                    -- Direct field from checkout data
                    value = checkoutData[sourceField]
                end

                signalData[nodeField] = value
            end

            -- Send signal to node
            if node.In and node.In[signal] then
                node.In[signal](node, signalData)
            end
        end
    end

    --[[
        Private: Setup auto-release listener on a node.
    --]]
    local function setupAutoRelease(self, node, entityId)
        local state = getState(self)
        local releaseSignal = state.releaseOn
        local poolSelf = self

        -- Store original Out channel
        local originalOut = node.Out

        -- Create wrapper that intercepts signals
        local wrapper = {
            _node = node,  -- Preserve node reference for compatibility
        }

        function wrapper:Fire(signal, data)
            -- Call original OutChannel's Fire with correct self
            if originalOut and originalOut.Fire then
                originalOut:Fire(signal, data)
            end

            -- Check for release signal
            if signal == releaseSignal then
                -- Auto-release this node
                releaseNode(poolSelf, entityId)
            end
        end

        node.Out = wrapper
    end

    --[[
        Private: Check for nodes that can be shrunk (destroyed).
    --]]
    checkForShrink = function(self)
        local state = getState(self)
        local now = os.clock()
        local totalNodes = getTotalNodeCount(self)

        -- Only shrink if above minimum
        if totalNodes <= state.minSize then
            return
        end

        -- Check available nodes for idle time
        local toRemove = {}
        for i, node in ipairs(state.available) do
            local lastActive = state.lastActivity[node.id] or 0
            local idleTime = now - lastActive

            if idleTime >= state.shrinkDelay and totalNodes - #toRemove > state.minSize then
                table.insert(toRemove, { index = i, node = node })
            end
        end

        -- Remove from end to preserve indices
        table.sort(toRemove, function(a, b) return a.index > b.index end)

        for _, item in ipairs(toRemove) do
            local node = item.node
            local nodeId = node.id

            -- Remove from available
            table.remove(state.available, item.index)

            -- Stop the node
            if node.Sys and node.Sys.onStop then
                node.Sys.onStop(node)
            end

            -- Remove from tracking
            state.allNodes[nodeId] = nil
            state.lastActivity[nodeId] = nil

            -- Fire nodeDestroyed
            self.Out:Fire("nodeDestroyed", {
                nodeId = nodeId,
                poolId = self.id,
            })
        end
    end

    --[[
        Private: Start the shrink monitor for elastic mode.
    --]]
    local function startShrinkMonitor(self)
        local state = getState(self)

        state.shrinkTask = task.spawn(function()
            while true do
                task.wait(state.shrinkDelay / 2)  -- Check at half the shrink delay

                if state.poolMode ~= "elastic" then
                    break
                end

                checkForShrink(self)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "NodePool",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Default attributes
                if not self:getAttribute("PoolMode") then
                    self:setAttribute("PoolMode", "elastic")
                end
            end,

            onStart = function(self)
                local state = getState(self)

                -- Start shrink monitor for elastic mode
                if state.poolMode == "elastic" and state.shrinkDelay > 0 then
                    startShrinkMonitor(self)
                end
            end,

            onStop = function(self)
                local state = getState(self)

                -- Stop shrink monitor
                if state.shrinkTask then
                    task.cancel(state.shrinkTask)
                    state.shrinkTask = nil
                end

                -- Stop all nodes
                for nodeId, node in pairs(state.allNodes) do
                    if node.Sys and node.Sys.onStop then
                        node.Sys.onStop(node)
                    end
                end

                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure the pool.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                -- Resolve node class
                if data.nodeClass then
                    if type(data.nodeClass) == "string" then
                        -- Look up in Components
                        local Components = require(script.Parent)
                        state.nodeClass = Components[data.nodeClass]
                        state.nodeClassName = data.nodeClass
                        if not state.nodeClass then
                            self.Err:Fire({
                                reason = "invalid_class",
                                message = "Unknown node class: " .. data.nodeClass,
                                poolId = self.id,
                            })
                            return
                        end
                    else
                        -- Direct class reference
                        state.nodeClass = data.nodeClass
                        state.nodeClassName = data.nodeClass.name or "PooledNode"
                    end
                end

                -- Pool mode
                if data.poolMode then
                    state.poolMode = data.poolMode
                    self:setAttribute("PoolMode", data.poolMode)
                end

                -- Fixed mode settings
                if data.poolSize then
                    state.poolSize = data.poolSize
                end

                -- Elastic mode settings
                if data.minSize then
                    state.minSize = data.minSize
                end
                if data.maxSize then
                    state.maxSize = data.maxSize
                end
                if data.shrinkDelay then
                    state.shrinkDelay = data.shrinkDelay
                end

                -- Node configuration
                if data.nodeConfig then
                    state.nodeConfig = data.nodeConfig
                end

                -- Checkout signals
                if data.checkoutSignals then
                    state.checkoutSignals = data.checkoutSignals
                end

                -- Auto-release signal
                if data.releaseOn then
                    state.releaseOn = data.releaseOn
                end

                -- Shared context
                if data.context then
                    state.context = data.context
                end

                state.configured = true

                -- Pre-allocate for fixed mode
                if state.poolMode == "fixed" then
                    preallocate(self, state.poolSize)
                elseif state.poolMode == "elastic" and state.minSize > 0 then
                    -- Pre-allocate minimum for elastic
                    preallocate(self, state.minSize)
                end
            end,

            --[[
                Check out a node from the pool.
            --]]
            onCheckout = function(self, data)
                local state = getState(self)

                if not state.configured or not state.nodeClass then
                    self.Err:Fire({
                        reason = "not_configured",
                        message = "Pool not configured. Call onConfigure first.",
                        poolId = self.id,
                    })
                    return
                end

                data = data or {}
                local entityId = data.entityId or ("entity_" .. os.clock())

                -- Check if already checked out
                if state.inUse[entityId] then
                    self.Err:Fire({
                        reason = "already_checked_out",
                        message = "Entity already has a checked out node: " .. entityId,
                        poolId = self.id,
                        entityId = entityId,
                    })
                    return
                end

                -- Try to get an available node
                local node = getAvailableNode(self)

                if not node then
                    -- No available nodes
                    local totalNodes = getTotalNodeCount(self)

                    if state.poolMode == "elastic" and totalNodes < state.maxSize then
                        -- Create a new node
                        node = createNode(self)
                    else
                        -- At capacity, fire exhausted
                        self.Out:Fire("exhausted", {
                            entityId = entityId,
                            poolId = self.id,
                            currentSize = totalNodes,
                            maxSize = state.maxSize,
                        })
                        return
                    end
                end

                -- Mark as in use
                state.inUse[entityId] = {
                    node = node,
                    nodeId = node.id,
                    checkoutTime = os.clock(),
                }

                -- Send checkout signals to the node
                sendCheckoutSignals(self, node, data)

                -- Setup auto-release listener
                if state.releaseOn then
                    setupAutoRelease(self, node, entityId)
                end

                -- Fire checkedOut
                self.Out:Fire("checkedOut", {
                    nodeId = node.id,
                    entityId = entityId,
                    node = node,
                    poolId = self.id,
                })
            end,

            --[[
                Release a node back to the pool.
            --]]
            onRelease = function(self, data)
                if not data or not data.entityId then
                    return
                end

                releaseNode(self, data.entityId)
            end,

            --[[
                Release all checked-out nodes.
            --]]
            onReleaseAll = function(self)
                local state = getState(self)
                local toRelease = {}
                for entityId in pairs(state.inUse) do
                    table.insert(toRelease, entityId)
                end

                for _, entityId in ipairs(toRelease) do
                    releaseNode(self, entityId)
                end
            end,

            --[[
                Destroy all nodes and reset pool.
            --]]
            onDestroy = function(self)
                local state = getState(self)

                -- Stop all nodes
                for nodeId, node in pairs(state.allNodes) do
                    if node.Sys and node.Sys.onStop then
                        node.Sys.onStop(node)
                    end
                end

                -- Clear state
                state.available = {}
                state.inUse = {}
                state.allNodes = {}
                state.lastActivity = {}
                state.nodeCounter = 0
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            checkedOut = {},    -- { nodeId, entityId, node, poolId }
            released = {},      -- { nodeId, entityId, poolId }
            exhausted = {},     -- { entityId, poolId, currentSize, maxSize }
            nodeCreated = {},   -- { nodeId, poolId }
            nodeDestroyed = {}, -- { nodeId, poolId }
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS (intentionally exposed)
        ------------------------------------------------------------------------

        --[[
            Get pool statistics.
        --]]
        getStats = function(self)
            local state = getState(self)
            local inUseCount = 0
            for _ in pairs(state.inUse) do
                inUseCount = inUseCount + 1
            end

            return {
                available = #state.available,
                inUse = inUseCount,
                total = getTotalNodeCount(self),
                mode = state.poolMode,
                minSize = state.minSize,
                maxSize = state.maxSize,
            }
        end,

        --[[
            Check if pool has available nodes.
        --]]
        hasAvailable = function(self)
            local state = getState(self)
            if #state.available > 0 then
                return true
            end
            -- In elastic mode, check if we can grow
            if state.poolMode == "elastic" then
                return getTotalNodeCount(self) < state.maxSize
            end
            return false
        end,
    }
end)

return NodePool
