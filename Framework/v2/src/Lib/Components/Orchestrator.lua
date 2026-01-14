--[[
    LibPureFiction Framework v2
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

local Orchestrator = Node.extend({
    name = "Orchestrator",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Managed nodes
            self._nodes = {}            -- { [nodeId] = instance }
            self._nodeConfigs = {}      -- { [nodeId] = config } for recreation

            -- Schema registry
            self._schemas = {}          -- { [schemaName] = schemaDef }

            -- Wiring configurations
            self._defaultWiring = {}    -- Default wiring rules
            self._modeWiring = {}       -- { [modeName] = wiringRules }
            self._activeWiring = {}     -- Currently active wiring (lookup table)

            -- Original Out:Fire functions for restoration
            self._originalFires = {}    -- { [nodeId] = originalFireFn }

            -- State
            self._enabled = false
            self._currentMode = ""

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
                self:_enableRouting()
            end
        end,

        onStop = function(self)
            self:_disableRouting()
            self:_despawnAllNodes()
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Configure the orchestrator with nodes, wiring, and schemas.
        --]]
        onConfigure = function(self, data)
            if not data then
                self.Err:Fire({ reason = "invalid_config", message = "Configuration data required" })
                return
            end

            local wasEnabled = self._enabled
            if wasEnabled then
                self:_disableRouting()
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
                    self._schemas[name] = schema
                end
            end

            -- Spawn nodes
            if data.nodes then
                for nodeId, nodeConfig in pairs(data.nodes) do
                    local success = self:_spawnNode(nodeId, nodeConfig)
                    if not success then
                        return  -- Error already fired
                    end
                end
            end

            -- Configure default wiring
            if data.wiring then
                local valid, err = self:_validateWiring(data.wiring)
                if not valid then
                    self.Err:Fire({
                        reason = "invalidWiring",
                        message = err,
                    })
                    return
                end
                self._defaultWiring = data.wiring
            end

            -- Configure mode-specific wiring
            if data.modes then
                for modeName, modeConfig in pairs(data.modes) do
                    if modeConfig.wiring then
                        local valid, err = self:_validateWiring(modeConfig.wiring)
                        if not valid then
                            self.Err:Fire({
                                reason = "invalidWiring",
                                mode = modeName,
                                message = err,
                            })
                            return
                        end
                        self._modeWiring[modeName] = modeConfig.wiring
                    end
                end
            end

            -- Build active wiring lookup
            self:_buildActiveWiring()

            -- Re-enable if was previously enabled (not on first configure)
            if wasEnabled then
                self:_enableRouting()
            end

            -- Fire configured signal
            self.Out:Fire("configured", {
                nodeCount = self:_countNodes(),
                wireCount = #self._defaultWiring,
                schemaCount = self:_countSchemas(),
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

            local wasEnabled = self._enabled
            if wasEnabled then
                self:_unwireNode(data.id)
            end

            local success = self:_spawnNode(data.id, {
                class = data.class,
                config = data.config,
                model = data.model,
            })

            if success and wasEnabled then
                self:_wireNode(data.id)
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

            self:_unwireNode(data.id)
            self:_despawnNode(data.id)

            self.Out:Fire("nodeDespawned", { id = data.id })
        end,

        --[[
            Switch to a different wiring mode.
        --]]
        onSetMode = function(self, data)
            if not data or not data.mode then
                return
            end

            local oldMode = self._currentMode
            local newMode = data.mode

            if oldMode == newMode then
                return
            end

            -- Disable current wiring
            local wasEnabled = self._enabled
            if wasEnabled then
                self:_disableRouting()
            end

            -- Update mode
            self._currentMode = newMode
            self:setAttribute("CurrentMode", newMode)

            -- Rebuild active wiring for new mode
            self:_buildActiveWiring()

            -- Re-enable
            if wasEnabled then
                self:_enableRouting()
            end

            self.Out:Fire("modeChanged", { from = oldMode, to = newMode })
        end,

        --[[
            Enable signal routing.
        --]]
        onEnable = function(self)
            self:setAttribute("Enabled", true)
            self:_enableRouting()
        end,

        --[[
            Disable signal routing.
        --]]
        onDisable = function(self)
            self:setAttribute("Enabled", false)
            self:_disableRouting()
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA
    ----------------------------------------------------------------------------

    Out = {
        configured = {},        -- { nodeCount, wireCount, schemaCount }
        nodeSpawned = {},       -- { id, class }
        nodeDespawned = {},     -- { id }
        modeChanged = {},       -- { from, to }
        validationFailed = {},  -- { from, signal, to, errors }
    },

    ----------------------------------------------------------------------------
    -- PRIVATE: NODE MANAGEMENT
    ----------------------------------------------------------------------------

    --[[
        Spawn a node from configuration.
    --]]
    _spawnNode = function(self, nodeId, config)
        if self._nodes[nodeId] then
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
        self._nodes[nodeId] = instance
        self._nodeConfigs[nodeId] = config

        return true
    end,

    --[[
        Despawn a node.
    --]]
    _despawnNode = function(self, nodeId)
        local instance = self._nodes[nodeId]
        if not instance then
            return
        end

        -- Stop
        if instance.Sys and instance.Sys.onStop then
            instance.Sys.onStop(instance)
        end

        -- Restore original Out:Fire
        if self._originalFires[nodeId] then
            instance.Out.Fire = self._originalFires[nodeId]
            self._originalFires[nodeId] = nil
        end

        -- Remove
        self._nodes[nodeId] = nil
        self._nodeConfigs[nodeId] = nil
    end,

    --[[
        Despawn all managed nodes.
    --]]
    _despawnAllNodes = function(self)
        for nodeId in pairs(self._nodes) do
            self:_despawnNode(nodeId)
        end
    end,

    --[[
        Count managed nodes.
    --]]
    _countNodes = function(self)
        local count = 0
        for _ in pairs(self._nodes) do
            count = count + 1
        end
        return count
    end,

    --[[
        Count registered schemas.
    --]]
    _countSchemas = function(self)
        local count = 0
        for _ in pairs(self._schemas) do
            count = count + 1
        end
        return count
    end,

    ----------------------------------------------------------------------------
    -- PRIVATE: WIRING
    ----------------------------------------------------------------------------

    --[[
        Validate wiring configuration.
    --]]
    _validateWiring = function(self, wiring)
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

            if not wire.handler then
                return false, string.format("Wire %d missing 'handler'", i)
            end

            -- Validate schema reference
            if wire.schema and type(wire.schema) == "string" then
                if not self._schemas[wire.schema] then
                    return false, string.format(
                        "Wire %d references unknown schema '%s'",
                        i, wire.schema
                    )
                end
            end
        end

        return true, nil
    end,

    --[[
        Build the active wiring lookup table.

        Combines default wiring with mode-specific wiring (mode overrides default).
    --]]
    _buildActiveWiring = function(self)
        self._activeWiring = {}

        -- Apply default wiring
        for _, wire in ipairs(self._defaultWiring) do
            local key = wire.from .. "." .. wire.signal
            self._activeWiring[key] = self._activeWiring[key] or {}
            table.insert(self._activeWiring[key], wire)
        end

        -- Apply mode-specific wiring (additive)
        if self._currentMode ~= "" and self._modeWiring[self._currentMode] then
            for _, wire in ipairs(self._modeWiring[self._currentMode]) do
                local key = wire.from .. "." .. wire.signal
                self._activeWiring[key] = self._activeWiring[key] or {}
                table.insert(self._activeWiring[key], wire)
            end
        end
    end,

    --[[
        Enable routing by intercepting Out:Fire on all managed nodes.
    --]]
    _enableRouting = function(self)
        if self._enabled then
            return
        end

        self._enabled = true

        for nodeId, instance in pairs(self._nodes) do
            self:_wireNode(nodeId)
        end
    end,

    --[[
        Disable routing by restoring original Out:Fire on all managed nodes.
    --]]
    _disableRouting = function(self)
        if not self._enabled then
            return
        end

        self._enabled = false

        for nodeId in pairs(self._nodes) do
            self:_unwireNode(nodeId)
        end
    end,

    --[[
        Wire a single node (intercept its Out:Fire).
    --]]
    _wireNode = function(self, nodeId)
        local instance = self._nodes[nodeId]
        if not instance then
            return
        end

        -- Already wired
        if self._originalFires[nodeId] then
            return
        end

        -- Store original
        local originalFire = instance.Out.Fire
        self._originalFires[nodeId] = originalFire

        -- Create interceptor
        local orchestrator = self
        instance.Out.Fire = function(outSelf, signal, data)
            -- Route through orchestrator
            orchestrator:_routeSignal(nodeId, signal, data)

            -- Also call original for IPC routing
            originalFire(outSelf, signal, data)
        end

        -- Start the node if not started
        if instance.Sys and instance.Sys.onStart then
            instance.Sys.onStart(instance)
        end
    end,

    --[[
        Unwire a single node (restore original Out:Fire).
    --]]
    _unwireNode = function(self, nodeId)
        local instance = self._nodes[nodeId]
        if not instance then
            return
        end

        local originalFire = self._originalFires[nodeId]
        if originalFire then
            instance.Out.Fire = originalFire
            self._originalFires[nodeId] = nil
        end
    end,

    --[[
        Route a signal through the wiring configuration.
    --]]
    _routeSignal = function(self, fromNodeId, signal, data)
        if not self._enabled then
            return
        end

        local key = fromNodeId .. "." .. signal
        local wires = self._activeWiring[key]

        if not wires then
            return
        end

        for _, wire in ipairs(wires) do
            self:_executeWire(wire, data, fromNodeId, signal)
        end
    end,

    --[[
        Execute a single wire (validate and deliver).
    --]]
    _executeWire = function(self, wire, data, fromNodeId, signal)
        -- Get target node
        local targetNode = self._nodes[wire.to]
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
                schema = self._schemas[wire.schema]
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
    end,

    ----------------------------------------------------------------------------
    -- PUBLIC API
    ----------------------------------------------------------------------------

    --[[
        Get a managed node by ID.

        @param nodeId string - The node ID
        @return table|nil - The node instance
    --]]
    getNode = function(self, nodeId)
        return self._nodes[nodeId]
    end,

    --[[
        Get all managed node IDs.

        @return string[] - Array of node IDs
    --]]
    getNodeIds = function(self)
        local ids = {}
        for id in pairs(self._nodes) do
            table.insert(ids, id)
        end
        return ids
    end,

    --[[
        Get a registered schema by name.

        @param name string - Schema name
        @return table|nil - Schema definition
    --]]
    getSchema = function(self, name)
        return self._schemas[name]
    end,

    --[[
        Get the current wiring mode.

        @return string - Current mode name (empty string for default)
    --]]
    getCurrentMode = function(self)
        return self._currentMode
    end,

    --[[
        Check if routing is enabled.

        @return boolean
    --]]
    isEnabled = function(self)
        return self._enabled
    end,
})

return Orchestrator
