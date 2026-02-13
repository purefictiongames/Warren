--[[
    LibPureFiction Framework v2
    EntityStats.lua - Attribute Storage Node

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    EntityStats is a pure storage node that owns an AttributeSet for an entity.
    It receives modifier messages, stores values, and emits change events.

    EntityStats has NO formulas - all computation goes through DamageCalculator
    or other formula nodes. This separation keeps stat storage simple and
    allows different games to define their own combat/formula logic.

    Key features:
    - Owns an AttributeSet with configurable schema
    - Receives modifiers through IPC (gatekept by wiring)
    - Emits change events for subscribers
    - Supports attribute queries for formula nodes
    - Death detection at health <= 0

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ schema, entityId, initialValues? })
            - Configure the attribute set
            - schema: attribute definitions (see System.Attribute)
            - entityId: identifier for this entity
            - initialValues: optional { attrName = value, ... }

        onApplyModifier({ attribute, operation, value, source })
            - Apply a modifier to an attribute
            - Routed through IPC with gatekeeping (modifierWiring)

        onRemoveModifier({ modifierId?, source? })
            - Remove modifier(s)
            - modifierId: remove specific modifier
            - source: remove all from source

        onSetAttribute({ attribute, value })
            - Set base value directly (from DamageCalculator, etc.)

        onQueryAttribute({ attribute, queryId })
            - Query current value, respond via Out

    OUT (emits):
        attributeChanged({ entityId, attribute, value, oldValue })
            - Fired when any attribute changes

        attributeQueried({ entityId, attribute, value, queryId })
            - Response to onQueryAttribute

        died({ entityId })
            - Fired when health <= 0

        modifierApplied({ entityId, attribute, modifierId, source })
            - Fired when modifier is applied

        modifierRemoved({ entityId, attribute, source })
            - Fired when modifier is removed

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Model attributes are not used for runtime configuration.
    All configuration happens through onConfigure signal.

--]]

local Node = require(script.Parent.Parent.Node)
local System = require(script.Parent.Parent.System)
local AttributeSet = require(script.Parent.Parent.Internal.AttributeSet)

--------------------------------------------------------------------------------
-- ENTITYSTATS NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local EntityStats = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                attributeSet = nil,
                entityId = nil,
                configured = false,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "EntityStats",
        domain = "server",  -- Server authoritative

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)
                state.attributeSet = nil
                state.entityId = nil
                state.configured = false

                System.Debug.trace("EntityStats", "Initialized:", self.id)
            end,

            onStart = function(self)
                System.Debug.trace("EntityStats", "Started:", self.id)
            end,

            onStop = function(self)
                -- Clean up attribute set
                local state = getState(self)
                if state.attributeSet then
                    state.attributeSet = nil
                end
                System.Debug.trace("EntityStats", "Stopped:", self.id)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure the attribute set with schema.

                @param data.schema table - Attribute definitions
                @param data.entityId string - Entity identifier
                @param data.initialValues table? - Optional initial values
            --]]
            onConfigure = function(self, data)
                local state = getState(self)

                if state.configured then
                    System.Debug.warn("EntityStats", "Already configured:", self.id)
                    return
                end

                if not data.schema then
                    System.Debug.warn("EntityStats", "No schema provided")
                    return
                end

                state.entityId = data.entityId or self.id

                -- Create attribute set
                state.attributeSet = AttributeSet.new(data.schema)

                -- Apply initial values
                if data.initialValues then
                    for attrName, value in pairs(data.initialValues) do
                        state.attributeSet:setBase(attrName, value)
                    end
                end

                -- Subscribe to all changes
                state.attributeSet:subscribeAll(function(attrName, newValue, oldValue)
                    self.Out:Fire("attributeChanged", {
                        entityId = state.entityId,
                        attribute = attrName,
                        value = newValue,
                        oldValue = oldValue,
                    })

                    -- Death detection
                    if attrName == "health" and newValue <= 0 then
                        self.Out:Fire("died", {
                            entityId = state.entityId,
                        })
                        System.Debug.info("EntityStats", "Entity died:", state.entityId)
                    end
                end)

                state.configured = true
                System.Debug.info("EntityStats", "Configured:", state.entityId)
            end,

            --[[
                Apply a modifier to an attribute.

                @param data.attribute string - Attribute name
                @param data.operation string - "additive", "multiplicative", "override"
                @param data.value number - Modifier value
                @param data.source string - Source identifier
            --]]
            onApplyModifier = function(self, data)
                local state = getState(self)

                if not state.attributeSet then
                    System.Debug.warn("EntityStats", "Not configured, cannot apply modifier")
                    return
                end

                local modId = state.attributeSet:applyModifier(data.attribute, {
                    operation = data.operation,
                    value = data.value,
                    source = data.source,
                    priority = data.priority,
                })

                if modId then
                    self.Out:Fire("modifierApplied", {
                        entityId = state.entityId,
                        attribute = data.attribute,
                        modifierId = modId,
                        source = data.source,
                    })

                    System.Debug.trace("EntityStats", "Modifier applied:",
                        data.attribute, data.operation, data.value, "from", data.source)
                end
            end,

            --[[
                Remove modifier(s).

                @param data.modifierId number? - Specific modifier ID
                @param data.source string? - Remove all from source
            --]]
            onRemoveModifier = function(self, data)
                local state = getState(self)

                if not state.attributeSet then
                    System.Debug.warn("EntityStats", "Not configured, cannot remove modifier")
                    return
                end

                if data.modifierId then
                    local success = state.attributeSet:removeModifier(data.modifierId)
                    if success then
                        self.Out:Fire("modifierRemoved", {
                            entityId = state.entityId,
                            modifierId = data.modifierId,
                        })
                    end
                elseif data.source then
                    local count = state.attributeSet:removeModifiersFromSource(data.source)
                    if count > 0 then
                        self.Out:Fire("modifierRemoved", {
                            entityId = state.entityId,
                            source = data.source,
                            count = count,
                        })
                        System.Debug.trace("EntityStats", "Removed", count, "modifiers from", data.source)
                    end
                end
            end,

            --[[
                Set base value directly.

                @param data.attribute string - Attribute name
                @param data.value number - New base value
            --]]
            onSetAttribute = function(self, data)
                local state = getState(self)

                if not state.attributeSet then
                    System.Debug.warn("EntityStats", "Not configured, cannot set attribute")
                    return
                end

                state.attributeSet:setBase(data.attribute, data.value)
                System.Debug.trace("EntityStats", "Set", data.attribute, "to", data.value)
            end,

            --[[
                Query current attribute value.

                @param data.attribute string - Attribute name
                @param data.queryId any - Correlation ID for response
            --]]
            onQueryAttribute = function(self, data)
                local state = getState(self)

                if not state.attributeSet then
                    System.Debug.warn("EntityStats", "Not configured, cannot query")
                    return
                end

                local value = state.attributeSet:get(data.attribute)

                self.Out:Fire("attributeQueried", {
                    entityId = state.entityId,
                    attribute = data.attribute,
                    value = value,
                    queryId = data.queryId,
                })
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            attributeChanged = {},   -- { entityId, attribute, value, oldValue }
            attributeQueried = {},   -- { entityId, attribute, value, queryId }
            died = {},               -- { entityId }
            modifierApplied = {},    -- { entityId, attribute, modifierId, source }
            modifierRemoved = {},    -- { entityId, modifierId?, source?, count? }
        },

        ------------------------------------------------------------------------
        -- PUBLIC METHODS
        -- These are intentionally exposed for direct attribute queries.
        -- EntityStats exposes AttributeSet methods as PUBLIC by design.
        ------------------------------------------------------------------------

        --[[
            Get current value of an attribute.

            @param attrName string
            @return any
        --]]
        get = function(self, attrName)
            local state = getState(self)
            if not state.attributeSet then
                return nil
            end
            return state.attributeSet:get(attrName)
        end,

        --[[
            Get base value of an attribute.

            @param attrName string
            @return any
        --]]
        getBase = function(self, attrName)
            local state = getState(self)
            if not state.attributeSet then
                return nil
            end
            return state.attributeSet:getBase(attrName)
        end,

        --[[
            Get all current values.

            @return table
        --]]
        getAll = function(self)
            local state = getState(self)
            if not state.attributeSet then
                return {}
            end
            return state.attributeSet:getAll()
        end,

        --[[
            Get entity ID.

            @return string
        --]]
        getEntityId = function(self)
            local state = getState(self)
            return state.entityId
        end,

        --[[
            Check if configured.

            @return boolean
        --]]
        isConfigured = function(self)
            local state = getState(self)
            return state.configured
        end,

        --[[
            Get the underlying AttributeSet.

            @return AttributeSet|nil
        --]]
        getAttributeSet = function(self)
            local state = getState(self)
            return state.attributeSet
        end,
    }
end)

return EntityStats
