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

local NodePool = Node.extend({
    name = "NodePool",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Pool state
            self._available = {}        -- Array of available nodes (stack)
            self._inUse = {}            -- { [entityId] = { node, nodeId, checkoutTime } }
            self._allNodes = {}         -- { [nodeId] = node } all nodes in pool
            self._lastActivity = {}     -- { [nodeId] = timestamp } for shrink
            self._nodeCounter = 0       -- For generating unique IDs
            self._configured = false
            self._shrinkTask = nil

            -- Configuration (set via onConfigure)
            self._nodeClass = nil       -- The class to instantiate
            self._nodeClassName = nil   -- String name for IDs
            self._poolMode = "elastic"
            self._poolSize = 5
            self._minSize = 0
            self._maxSize = 50
            self._shrinkDelay = 10
            self._nodeConfig = {}
            self._checkoutSignals = {}
            self._releaseOn = nil
            self._context = {}

            -- Default attributes
            if not self:getAttribute("PoolMode") then
                self:setAttribute("PoolMode", "elastic")
            end
        end,

        onStart = function(self)
            -- Start shrink monitor for elastic mode
            if self._poolMode == "elastic" and self._shrinkDelay > 0 then
                self:_startShrinkMonitor()
            end
        end,

        onStop = function(self)
            -- Stop shrink monitor
            if self._shrinkTask then
                task.cancel(self._shrinkTask)
                self._shrinkTask = nil
            end

            -- Stop all nodes
            for nodeId, node in pairs(self._allNodes) do
                if node.Sys and node.Sys.onStop then
                    node.Sys.onStop(node)
                end
            end
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Configure the pool.
        --]]
        onConfigure = function(self, data)
            if not data then return end

            -- Resolve node class
            if data.nodeClass then
                if type(data.nodeClass) == "string" then
                    -- Look up in Components
                    local Components = require(script.Parent)
                    self._nodeClass = Components[data.nodeClass]
                    self._nodeClassName = data.nodeClass
                    if not self._nodeClass then
                        self.Err:Fire({
                            reason = "invalid_class",
                            message = "Unknown node class: " .. data.nodeClass,
                            poolId = self.id,
                        })
                        return
                    end
                else
                    -- Direct class reference
                    self._nodeClass = data.nodeClass
                    self._nodeClassName = data.nodeClass.name or "PooledNode"
                end
            end

            -- Pool mode
            if data.poolMode then
                self._poolMode = data.poolMode
                self:setAttribute("PoolMode", data.poolMode)
            end

            -- Fixed mode settings
            if data.poolSize then
                self._poolSize = data.poolSize
            end

            -- Elastic mode settings
            if data.minSize then
                self._minSize = data.minSize
            end
            if data.maxSize then
                self._maxSize = data.maxSize
            end
            if data.shrinkDelay then
                self._shrinkDelay = data.shrinkDelay
            end

            -- Node configuration
            if data.nodeConfig then
                self._nodeConfig = data.nodeConfig
            end

            -- Checkout signals
            if data.checkoutSignals then
                self._checkoutSignals = data.checkoutSignals
            end

            -- Auto-release signal
            if data.releaseOn then
                self._releaseOn = data.releaseOn
            end

            -- Shared context
            if data.context then
                self._context = data.context
            end

            self._configured = true

            -- Pre-allocate for fixed mode
            if self._poolMode == "fixed" then
                self:_preallocate(self._poolSize)
            elseif self._poolMode == "elastic" and self._minSize > 0 then
                -- Pre-allocate minimum for elastic
                self:_preallocate(self._minSize)
            end
        end,

        --[[
            Check out a node from the pool.
        --]]
        onCheckout = function(self, data)
            if not self._configured or not self._nodeClass then
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
            if self._inUse[entityId] then
                self.Err:Fire({
                    reason = "already_checked_out",
                    message = "Entity already has a checked out node: " .. entityId,
                    poolId = self.id,
                    entityId = entityId,
                })
                return
            end

            -- Try to get an available node
            local node = self:_getAvailableNode()

            if not node then
                -- No available nodes
                local totalNodes = self:_getTotalNodeCount()

                if self._poolMode == "elastic" and totalNodes < self._maxSize then
                    -- Create a new node
                    node = self:_createNode()
                else
                    -- At capacity, fire exhausted
                    self.Out:Fire("exhausted", {
                        entityId = entityId,
                        poolId = self.id,
                        currentSize = totalNodes,
                        maxSize = self._maxSize,
                    })
                    return
                end
            end

            -- Mark as in use
            self._inUse[entityId] = {
                node = node,
                nodeId = node.id,
                checkoutTime = os.clock(),
            }

            -- Send checkout signals to the node
            self:_sendCheckoutSignals(node, data)

            -- Setup auto-release listener
            if self._releaseOn then
                self:_setupAutoRelease(node, entityId)
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

            self:_releaseNode(data.entityId)
        end,

        --[[
            Release all checked-out nodes.
        --]]
        onReleaseAll = function(self)
            local toRelease = {}
            for entityId in pairs(self._inUse) do
                table.insert(toRelease, entityId)
            end

            for _, entityId in ipairs(toRelease) do
                self:_releaseNode(entityId)
            end
        end,

        --[[
            Destroy all nodes and reset pool.
        --]]
        onDestroy = function(self)
            -- Stop all nodes
            for nodeId, node in pairs(self._allNodes) do
                if node.Sys and node.Sys.onStop then
                    node.Sys.onStop(node)
                end
            end

            -- Clear state
            self._available = {}
            self._inUse = {}
            self._allNodes = {}
            self._lastActivity = {}
            self._nodeCounter = 0
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA
    ----------------------------------------------------------------------------

    Out = {
        checkedOut = {},    -- { nodeId, entityId, node, poolId }
        released = {},      -- { nodeId, entityId, poolId }
        exhausted = {},     -- { entityId, poolId, currentSize, maxSize }
        nodeCreated = {},   -- { nodeId, poolId }
        nodeDestroyed = {}, -- { nodeId, poolId }
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Get total node count (available + in use).
    --]]
    _getTotalNodeCount = function(self)
        local count = 0
        for _ in pairs(self._allNodes) do
            count = count + 1
        end
        return count
    end,

    --[[
        Pre-allocate nodes.
    --]]
    _preallocate = function(self, count)
        for i = 1, count do
            local node = self:_createNode()
            if node then
                table.insert(self._available, node)
            end
        end
    end,

    --[[
        Create a new pooled node.
    --]]
    _createNode = function(self)
        if not self._nodeClass then
            return nil
        end

        self._nodeCounter = self._nodeCounter + 1
        local nodeId = self.id .. "_" .. self._nodeClassName .. "_" .. self._nodeCounter

        local node = self._nodeClass:new({
            id = nodeId,
        })

        -- Initialize
        if node.Sys and node.Sys.onInit then
            node.Sys.onInit(node)
        end

        -- Configure
        if node.In and node.In.onConfigure and self._nodeConfig then
            node.In.onConfigure(node, self._nodeConfig)
        end

        -- Track
        self._allNodes[nodeId] = node
        self._lastActivity[nodeId] = os.clock()

        -- Fire nodeCreated
        self.Out:Fire("nodeCreated", {
            nodeId = nodeId,
            poolId = self.id,
        })

        return node
    end,

    --[[
        Get an available node from the pool.
    --]]
    _getAvailableNode = function(self)
        if #self._available > 0 then
            return table.remove(self._available)
        end
        return nil
    end,

    --[[
        Release a node back to the pool.
    --]]
    _releaseNode = function(self, entityId)
        local record = self._inUse[entityId]
        if not record then
            return false
        end

        local node = record.node
        local nodeId = record.nodeId

        -- Clear from in-use
        self._inUse[entityId] = nil

        -- Reset node state
        self:_resetNode(node)

        -- Update activity timestamp
        self._lastActivity[nodeId] = os.clock()

        -- Return to available pool
        table.insert(self._available, node)

        -- Fire released
        self.Out:Fire("released", {
            nodeId = nodeId,
            entityId = entityId,
            poolId = self.id,
        })

        return true
    end,

    --[[
        Reset a node for reuse.
    --]]
    _resetNode = function(self, node)
        -- Clear internal state that PathFollower or other nodes might have
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
    end,

    --[[
        Send checkout signals to a node.
    --]]
    _sendCheckoutSignals = function(self, node, checkoutData)
        for _, signalDef in ipairs(self._checkoutSignals) do
            local signal = signalDef.signal
            local mapping = signalDef.map or {}

            -- Build data for this signal
            local signalData = {}
            for nodeField, sourceField in pairs(mapping) do
                local value

                if type(sourceField) == "string" and string.sub(sourceField, 1, 1) == "$" then
                    -- Context reference
                    local contextKey = string.sub(sourceField, 2)
                    value = self._context[contextKey]
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
    end,

    --[[
        Setup auto-release listener on a node.
    --]]
    _setupAutoRelease = function(self, node, entityId)
        local releaseSignal = self._releaseOn
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
                poolSelf:_releaseNode(entityId)
            end
        end

        node.Out = wrapper
    end,

    --[[
        Start the shrink monitor for elastic mode.
    --]]
    _startShrinkMonitor = function(self)
        self._shrinkTask = task.spawn(function()
            while true do
                task.wait(self._shrinkDelay / 2)  -- Check at half the shrink delay

                if self._poolMode ~= "elastic" then
                    break
                end

                self:_checkForShrink()
            end
        end)
    end,

    --[[
        Check for nodes that can be shrunk (destroyed).
    --]]
    _checkForShrink = function(self)
        local now = os.clock()
        local totalNodes = self:_getTotalNodeCount()

        -- Only shrink if above minimum
        if totalNodes <= self._minSize then
            return
        end

        -- Check available nodes for idle time
        local toRemove = {}
        for i, node in ipairs(self._available) do
            local lastActive = self._lastActivity[node.id] or 0
            local idleTime = now - lastActive

            if idleTime >= self._shrinkDelay and totalNodes - #toRemove > self._minSize then
                table.insert(toRemove, { index = i, node = node })
            end
        end

        -- Remove from end to preserve indices
        table.sort(toRemove, function(a, b) return a.index > b.index end)

        for _, item in ipairs(toRemove) do
            local node = item.node
            local nodeId = node.id

            -- Remove from available
            table.remove(self._available, item.index)

            -- Stop the node
            if node.Sys and node.Sys.onStop then
                node.Sys.onStop(node)
            end

            -- Remove from tracking
            self._allNodes[nodeId] = nil
            self._lastActivity[nodeId] = nil

            -- Fire nodeDestroyed
            self.Out:Fire("nodeDestroyed", {
                nodeId = nodeId,
                poolId = self.id,
            })
        end
    end,

    ----------------------------------------------------------------------------
    -- PUBLIC QUERY METHODS
    ----------------------------------------------------------------------------

    --[[
        Get pool statistics.
    --]]
    getStats = function(self)
        local inUseCount = 0
        for _ in pairs(self._inUse) do
            inUseCount = inUseCount + 1
        end

        return {
            available = #self._available,
            inUse = inUseCount,
            total = self:_getTotalNodeCount(),
            mode = self._poolMode,
            minSize = self._minSize,
            maxSize = self._maxSize,
        }
    end,

    --[[
        Check if pool has available nodes.
    --]]
    hasAvailable = function(self)
        if #self._available > 0 then
            return true
        end
        -- In elastic mode, check if we can grow
        if self._poolMode == "elastic" then
            return self:_getTotalNodeCount() < self._maxSize
        end
        return false
    end,
})

return NodePool
