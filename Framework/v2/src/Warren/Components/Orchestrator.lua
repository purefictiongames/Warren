--[[
    Warren Framework v2
    Orchestrator.lua - Declarative Component Composition

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Orchestrator is a meta-component that manages other components. It provides:
    - Declarative node instantiation via configuration tables
    - Signal wiring between components
    - Schema-validated message contracts
    - Mode-based wiring configurations
    - Client->Server message security

    Think of Orchestrator as a "circuit board" that you configure with components
    and wiring, then it handles all the signal routing automatically.

    ============================================================================
    CONFIGURATION
    ============================================================================

    ```lua
    local orchestrator = Orchestrator:new({ id = "GameOrchestrator" })
    orchestrator.In.onConfigure(orchestrator, {
        -- Named schemas for reuse
        schemas = {
            SpawnedPayload = {
                entity = { type = "Instance", required = true },
                entityId = { type = "string", required = true },
            },
        },

        -- Node instances to create
        nodes = {
            Spawner = { class = "Dropper", config = { interval = 2 } },
            EndZone = { class = "Zone", config = { filter = { class = "Crate" } } },
        },

        -- Signal wiring
        wiring = {
            {
                from = "Spawner",
                signal = "spawned",
                to = "EndZone",
                handler = "onConfigure",
                schema = "SpawnedPayload",  -- Named or inline schema
                validate = true,            -- Block invalid payloads
            },
            -- Special target "Out" - forward to orchestrator's own Out
            {
                from = "EndZone",
                signal = "entityEntered",
                to = "Out",                 -- Fire on orchestrator's Out
                handler = "entityReached",  -- Optional: rename signal (default: same name)
            },
        },

        -- Optional: Mode-specific wiring
        modes = {
            lobby = { wiring = { ... } },
            gameplay = { wiring = { ... } },
        },
    })
    ```

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ schemas?, nodes, wiring, modes? })
            - Full configuration

        onAddNode({ id, class, config?, model? })
            - Add a single node

        onRemoveNode({ id })
            - Remove a node

        onSetMode({ mode })
            - Switch to a different wiring mode

        onEnable()
            - Enable signal routing

        onDisable()
            - Disable signal routing

    OUT (emits):
        configured({ nodeCount, wireCount, schemaCount })
            - After successful configuration

        nodeSpawned({ id, class })
            - After node creation

        nodeDespawned({ id })
            - After node removal

        modeChanged({ from, to })
            - After mode switch

        validationFailed({ from, signal, to, errors })
            - When schema validation fails (validate = "warn" or internal logging)

    Err (detour):
        invalidSchema({ schemaName, reason })
        invalidWiring({ index, reason })
        validationError({ from, signal, to, field, expected, received })
        nodeError({ id, reason })

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Enabled: boolean (default true)
        Whether signal routing is active

    CurrentMode: string (default "")
        The current wiring mode (empty = default wiring)

--]]

local Node = require(script.Parent.Parent.Node)
local SchemaValidator = require(script.Parent.Parent.Internal.SchemaValidator)

--------------------------------------------------------------------------------
-- ORCHESTRATOR NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Orchestrator = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Managed nodes
                nodes = {},            -- { [nodeId] = instance }
                nodeConfigs = {},      -- { [nodeId] = config } for recreation

                -- Schema registry
                schemas = {},          -- { [schemaName] = schemaDef }

                -- Wiring configurations
                defaultWiring = {},    -- Default wiring rules
                modeWiring = {},       -- { [modeName] = wiringRules }
                activeWiring = {},     -- Currently active wiring (lookup table)

                -- Original Out:Fire functions for restoration
                originalFires = {},    -- { [nodeId] = originalFireFn }

                -- State
                enabled = false,
                currentMode = "",
                isStopped = false,     -- Guard against double-stop
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    -- Forward declarations for mutual recursion
    local spawnNode
    local despawnNode
    local despawnAllNodes
    local unwireNode
    local wireNode
    local enableRouting
    local disableRouting
    local routeSignal
    local executeWire

    --[[
        Private: Count managed nodes.
    --]]
    local function countNodes(self)
        local state = getState(self)
        local count = 0
        for _ in pairs(state.nodes) do
            count = count + 1
        end
        return count
    end

    --[[
        Private: Count registered schemas.
    --]]
    local function countSchemas(self)
        local state = getState(self)
        local count = 0
        for _ in pairs(state.schemas) do
            count = count + 1
        end
        return count
    end

    --[[
        Private: Validate wiring configuration.
    --]]
    local function validateWiring(self, wiring)
        local state = getState(self)

        if type(wiring) ~= "table" then
            return false, "Wiring must be an array"
        end

        for i, wire in ipairs(wiring) do
            if type(wire) ~= "table" then
                return false, string.format("Wire %d must be a table", i)
            end

            if not wire.from then
                return false, string.format("Wire %d missing 'from'", i)
            end

            if not wire.signal then
                return false, string.format("Wire %d missing 'signal'", i)
            end

            if not wire.to then
                return false, string.format("Wire %d missing 'to'", i)
            end

            -- Handler is optional for "Out" target (defaults to signal name)
            if wire.to ~= "Out" and not wire.handler then
                return false, string.format("Wire %d missing 'handler'", i)
            end

            -- Validate schema reference
            if wire.schema and type(wire.schema) == "string" then
                if not state.schemas[wire.schema] then
                    return false, string.format(
                        "Wire %d references unknown schema '%s'",
                        i, wire.schema
                    )
                end
            end
        end

        return true, nil
    end

    --[[
        Private: Build the active wiring lookup table.
    --]]
    local function buildActiveWiring(self)
        local state = getState(self)
        state.activeWiring = {}

        -- Apply default wiring
        for _, wire in ipairs(state.defaultWiring) do
            local key = wire.from .. "." .. wire.signal
            state.activeWiring[key] = state.activeWiring[key] or {}
            table.insert(state.activeWiring[key], wire)
        end

        -- Apply mode-specific wiring (additive)
        if state.currentMode ~= "" and state.modeWiring[state.currentMode] then
            for _, wire in ipairs(state.modeWiring[state.currentMode]) do
                local key = wire.from .. "." .. wire.signal
                state.activeWiring[key] = state.activeWiring[key] or {}
                table.insert(state.activeWiring[key], wire)
            end
        end
    end

    --[[
        Private: Execute a single wire (validate and deliver).

        Special targets:
        - "Out": Fire to orchestrator's own Out (for external consumers)
        - "Self": Route to orchestrator's own In handlers (for internal handling)
        - "Client": Reserved for client replication (no error if missing)
    --]]
    executeWire = function(self, wire, data, fromNodeId, signal)
        local state = getState(self)

        -- Special target: "Out" - fire to orchestrator's own Out
        if wire.to == "Out" then
            local outSignal = wire.handler or signal  -- handler = signal name to emit
            self.Out:Fire(outSignal, data)
            return
        end

        -- Special target: "Self" - route to orchestrator's own In handlers
        if wire.to == "Self" then
            local handler = self.In and self.In[wire.handler]
            if not handler then
                self.Err:Fire({
                    reason = "nodeError",
                    id = "Self",
                    message = string.format("Handler '%s' not found on orchestrator", wire.handler),
                })
                return
            end

            -- Execute handler on self
            local success, err = pcall(function()
                handler(self, data)
            end)

            if not success then
                self.Err:Fire({
                    reason = "nodeError",
                    id = "Self",
                    handler = wire.handler,
                    message = tostring(err),
                })
            end
            return
        end

        -- Get target node
        local targetNode = state.nodes[wire.to]
        if not targetNode then
            -- Target might be "Client" or external - skip internal routing
            if wire.to ~= "Client" then
                self.Err:Fire({
                    reason = "nodeError",
                    id = wire.to,
                    message = "Target node not found",
                })
            end
            return
        end

        -- Get schema (by name or inline)
        local schema = nil
        if wire.schema then
            if type(wire.schema) == "string" then
                schema = state.schemas[wire.schema]
            elseif type(wire.schema) == "table" then
                schema = wire.schema
            end
        end

        -- Validate if schema specified
        if schema then
            local valid, errors, processed = SchemaValidator.validateAndProcess(data, schema)

            if not valid then
                -- Fire validation failed signal
                self.Out:Fire("validationFailed", {
                    from = fromNodeId,
                    signal = signal,
                    to = wire.to,
                    errors = errors,
                })

                -- Fire Err channel
                for _, err in ipairs(errors) do
                    self.Err:Fire({
                        reason = "validationError",
                        from = fromNodeId,
                        signal = signal,
                        to = wire.to,
                        field = err.field,
                        expected = err.expected,
                        received = err.received,
                        message = err.message,
                    })
                end

                -- Block if strict validation
                if wire.validate == true then
                    return
                end
            else
                -- Use processed data (with defaults injected)
                data = processed
            end
        end

        -- Sanitize if schema specified (security: only declared fields)
        if schema and wire.validate == true then
            data = SchemaValidator.sanitize(data, schema)
        end

        -- Get handler
        local handler = targetNode.In and targetNode.In[wire.handler]
        if not handler then
            self.Err:Fire({
                reason = "nodeError",
                id = wire.to,
                message = string.format("Handler '%s' not found", wire.handler),
            })
            return
        end

        -- Execute handler
        local success, err = pcall(function()
            handler(targetNode, data)
        end)

        if not success then
            self.Err:Fire({
                reason = "nodeError",
                id = wire.to,
                handler = wire.handler,
                message = tostring(err),
            })
        end
    end

    --[[
        Private: Route a signal through the wiring configuration.
    --]]
    routeSignal = function(self, fromNodeId, signal, data)
        local state = getState(self)

        if not state.enabled then
            return
        end

        local key = fromNodeId .. "." .. signal
        local wires = state.activeWiring[key]

        if not wires then
            return
        end

        for _, wire in ipairs(wires) do
            executeWire(self, wire, data, fromNodeId, signal)
        end
    end

    --[[
        Private: Wire a single node (intercept its Out:Fire).
        Does NOT start the node - that's done separately after all nodes are wired.
    --]]
    wireNode = function(self, nodeId)
        local state = getState(self)
        local instance = state.nodes[nodeId]
        if not instance then
            return
        end

        -- Already wired
        if state.originalFires[nodeId] then
            return
        end

        -- Store original
        local originalFire = instance.Out.Fire
        state.originalFires[nodeId] = originalFire

        -- Create interceptor
        local orchestrator = self
        instance.Out.Fire = function(outSelf, signal, data)
            -- Route through orchestrator
            routeSignal(orchestrator, nodeId, signal, data)

            -- Also call original for IPC routing
            originalFire(outSelf, signal, data)
        end
    end

    --[[
        Private: Start a single node.
    --]]
    local startNode = function(self, nodeId)
        local state = getState(self)
        local instance = state.nodes[nodeId]
        if not instance then
            return
        end

        if instance.Sys and instance.Sys.onStart then
            instance.Sys.onStart(instance)
        end
    end

    --[[
        Private: Unwire a single node (restore original Out:Fire).
    --]]
    unwireNode = function(self, nodeId)
        local state = getState(self)
        local instance = state.nodes[nodeId]
        if not instance then
            return
        end

        local originalFire = state.originalFires[nodeId]
        if originalFire then
            instance.Out.Fire = originalFire
            state.originalFires[nodeId] = nil
        end
    end

    --[[
        Private: Enable routing by intercepting Out:Fire on all managed nodes.

        IMPORTANT: We wire ALL nodes first, THEN start them all.
        This ensures that when a node fires discovery signals during onStart,
        all other nodes are already wired and can respond.
    --]]
    enableRouting = function(self)
        local state = getState(self)

        if state.enabled then
            return
        end

        state.enabled = true

        -- Phase 1: Wire all nodes (intercept Out.Fire)
        for nodeId in pairs(state.nodes) do
            wireNode(self, nodeId)
        end

        -- Phase 2: Start all nodes (now all wiring is in place)
        for nodeId in pairs(state.nodes) do
            startNode(self, nodeId)
        end
    end

    --[[
        Private: Disable routing by restoring original Out:Fire on all managed nodes.
    --]]
    disableRouting = function(self)
        local state = getState(self)

        if not state.enabled then
            return
        end

        state.enabled = false

        for nodeId in pairs(state.nodes) do
            unwireNode(self, nodeId)
        end
    end

    --[[
        Private: Spawn a node from configuration.
    --]]
    spawnNode = function(self, nodeId, config)
        local state = getState(self)

        if state.nodes[nodeId] then
            self.Err:Fire({
                reason = "nodeError",
                id = nodeId,
                message = "Node already exists",
            })
            return false
        end

        -- Get the component class
        local Components = require(script.Parent)
        local NodeClass = Components[config.class]

        if not NodeClass then
            self.Err:Fire({
                reason = "nodeError",
                id = nodeId,
                message = string.format("Unknown component class '%s'", config.class),
            })
            return false
        end

        -- Create instance
        local instance = NodeClass:new({
            id = nodeId,
            model = config.model,
            attributes = config.config,
        })

        -- Initialize
        if instance.Sys and instance.Sys.onInit then
            instance.Sys.onInit(instance)
        end

        -- Configure if config provided
        if config.config and instance.In and instance.In.onConfigure then
            instance.In.onConfigure(instance, config.config)
        end

        -- Store
        state.nodes[nodeId] = instance
        state.nodeConfigs[nodeId] = config

        return true
    end

    --[[
        Private: Despawn a node.
    --]]
    despawnNode = function(self, nodeId)
        local state = getState(self)
        local instance = state.nodes[nodeId]
        if not instance then
            return
        end

        -- Stop
        if instance.Sys and instance.Sys.onStop then
            instance.Sys.onStop(instance)
        end

        -- Restore original Out:Fire
        if state.originalFires[nodeId] then
            instance.Out.Fire = state.originalFires[nodeId]
            state.originalFires[nodeId] = nil
        end

        -- Remove
        state.nodes[nodeId] = nil
        state.nodeConfigs[nodeId] = nil
    end

    --[[
        Private: Despawn all managed nodes.
    --]]
    despawnAllNodes = function(self)
        local state = getState(self)
        for nodeId in pairs(state.nodes) do
            despawnNode(self, nodeId)
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Orchestrator",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Default attributes
                if self:getAttribute("Enabled") == nil then
                    self:setAttribute("Enabled", true)
                end
                if not self:getAttribute("CurrentMode") then
                    self:setAttribute("CurrentMode", "")
                end
            end,

            onStart = function(self)
                if self:getAttribute("Enabled") then
                    enableRouting(self)
                end
            end,

            onStop = function(self)
                local state = getState(self)

                -- Guard against double-stop
                if state.isStopped then
                    return
                end
                state.isStopped = true

                disableRouting(self)
                despawnAllNodes(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure the orchestrator with nodes, wiring, and schemas.
            --]]
            onConfigure = function(self, data)
                if not data then
                    self.Err:Fire({ reason = "invalid_config", message = "Configuration data required" })
                    return
                end

                local state = getState(self)
                local wasEnabled = state.enabled
                if wasEnabled then
                    disableRouting(self)
                end

                -- Register schemas
                if data.schemas then
                    for name, schema in pairs(data.schemas) do
                        local valid, err = SchemaValidator.validateSchema(schema)
                        if not valid then
                            self.Err:Fire({
                                reason = "invalidSchema",
                                schemaName = name,
                                message = err,
                            })
                            return
                        end
                        state.schemas[name] = schema
                    end
                end

                -- Spawn nodes
                if data.nodes then
                    for nodeId, nodeConfig in pairs(data.nodes) do
                        local success = spawnNode(self, nodeId, nodeConfig)
                        if not success then
                            return  -- Error already fired
                        end
                    end
                end

                -- Configure default wiring
                if data.wiring then
                    local valid, err = validateWiring(self, data.wiring)
                    if not valid then
                        self.Err:Fire({
                            reason = "invalidWiring",
                            message = err,
                        })
                        return
                    end
                    state.defaultWiring = data.wiring
                end

                -- Configure mode-specific wiring
                if data.modes then
                    for modeName, modeConfig in pairs(data.modes) do
                        if modeConfig.wiring then
                            local valid, err = validateWiring(self, modeConfig.wiring)
                            if not valid then
                                self.Err:Fire({
                                    reason = "invalidWiring",
                                    mode = modeName,
                                    message = err,
                                })
                                return
                            end
                            state.modeWiring[modeName] = modeConfig.wiring
                        end
                    end
                end

                -- Build active wiring lookup
                buildActiveWiring(self)

                -- Re-enable if was previously enabled (not on first configure)
                if wasEnabled then
                    enableRouting(self)
                end

                -- Fire configured signal
                self.Out:Fire("configured", {
                    nodeCount = countNodes(self),
                    wireCount = #state.defaultWiring,
                    schemaCount = countSchemas(self),
                })
            end,

            --[[
                Add a single node dynamically.
            --]]
            onAddNode = function(self, data)
                if not data or not data.id or not data.class then
                    self.Err:Fire({ reason = "invalid_node", message = "Node must have id and class" })
                    return
                end

                local state = getState(self)
                local wasEnabled = state.enabled
                if wasEnabled then
                    unwireNode(self, data.id)
                end

                local success = spawnNode(self, data.id, {
                    class = data.class,
                    config = data.config,
                    model = data.model,
                })

                if success and wasEnabled then
                    wireNode(self, data.id)
                    startNode(self, data.id)
                end

                if success then
                    self.Out:Fire("nodeSpawned", { id = data.id, class = data.class })
                end
            end,

            --[[
                Remove a node dynamically.
            --]]
            onRemoveNode = function(self, data)
                if not data or not data.id then
                    return
                end

                unwireNode(self, data.id)
                despawnNode(self, data.id)

                self.Out:Fire("nodeDespawned", { id = data.id })
            end,

            --[[
                Switch to a different wiring mode.
            --]]
            onSetMode = function(self, data)
                if not data or not data.mode then
                    return
                end

                local state = getState(self)
                local oldMode = state.currentMode
                local newMode = data.mode

                if oldMode == newMode then
                    return
                end

                -- Disable current wiring
                local wasEnabled = state.enabled
                if wasEnabled then
                    disableRouting(self)
                end

                -- Update mode
                state.currentMode = newMode
                self:setAttribute("CurrentMode", newMode)

                -- Rebuild active wiring for new mode
                buildActiveWiring(self)

                -- Re-enable
                if wasEnabled then
                    enableRouting(self)
                end

                self.Out:Fire("modeChanged", { from = oldMode, to = newMode })
            end,

            --[[
                Enable signal routing.
            --]]
            onEnable = function(self)
                self:setAttribute("Enabled", true)
                enableRouting(self)
            end,

            --[[
                Disable signal routing.
            --]]
            onDisable = function(self)
                self:setAttribute("Enabled", false)
                disableRouting(self)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            configured = {},        -- { nodeCount, wireCount, schemaCount }
            nodeSpawned = {},       -- { id, class }
            nodeDespawned = {},     -- { id }
            modeChanged = {},       -- { from, to }
            validationFailed = {},  -- { from, signal, to, errors }
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS (intentionally exposed)
        ------------------------------------------------------------------------

        --[[
            Get a managed node by ID.
        --]]
        getNode = function(self, nodeId)
            local state = getState(self)
            return state.nodes[nodeId]
        end,

        --[[
            Get all managed node IDs.
        --]]
        getNodeIds = function(self)
            local state = getState(self)
            local ids = {}
            for id in pairs(state.nodes) do
                table.insert(ids, id)
            end
            return ids
        end,

        --[[
            Get a registered schema by name.
        --]]
        getSchema = function(self, name)
            local state = getState(self)
            return state.schemas[name]
        end,

        --[[
            Get the current wiring mode.
        --]]
        getCurrentMode = function(self)
            local state = getState(self)
            return state.currentMode
        end,

        --[[
            Check if routing is enabled.
        --]]
        isEnabled = function(self)
            local state = getState(self)
            return state.enabled
        end,
    }
end)

return Orchestrator
