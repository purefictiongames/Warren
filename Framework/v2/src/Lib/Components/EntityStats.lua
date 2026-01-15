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
-- ENTITYSTATS NODE
--------------------------------------------------------------------------------

local EntityStats = Node.extend({
    name = "EntityStats",
    domain = "server",  -- Server authoritative

    --------------------------------------------------------------------------------
    -- SYSTEM HANDLERS
    --------------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            self._attributeSet = nil
            self._entityId = nil
            self._configured = false

            System.Debug.trace("EntityStats", "Initialized:", self.id)
        end,

        onStart = function(self)
            System.Debug.trace("EntityStats", "Started:", self.id)
        end,

        onStop = function(self)
            -- Clean up attribute set
            if self._attributeSet then
                self._attributeSet = nil
            end
            System.Debug.trace("EntityStats", "Stopped:", self.id)
        end,
    },

    --------------------------------------------------------------------------------
    -- INPUT HANDLERS
    --------------------------------------------------------------------------------

    In = {
        --[[
            Configure the attribute set with schema.

            @param data.schema table - Attribute definitions
            @param data.entityId string - Entity identifier
            @param data.initialValues table? - Optional initial values
        --]]
        onConfigure = function(self, data)
            if self._configured then
                System.Debug.warn("EntityStats", "Already configured:", self.id)
                return
            end

            if not data.schema then
                System.Debug.warn("EntityStats", "No schema provided")
                return
            end

            self._entityId = data.entityId or self.id

            -- Create attribute set
            self._attributeSet = AttributeSet.new(data.schema)

            -- Apply initial values
            if data.initialValues then
                for attrName, value in pairs(data.initialValues) do
                    self._attributeSet:setBase(attrName, value)
                end
            end

            -- Subscribe to all changes
            self._attributeSet:subscribeAll(function(attrName, newValue, oldValue)
                self.Out:Fire("attributeChanged", {
                    entityId = self._entityId,
                    attribute = attrName,
                    value = newValue,
                    oldValue = oldValue,
                })

                -- Death detection
                if attrName == "health" and newValue <= 0 then
                    self.Out:Fire("died", {
                        entityId = self._entityId,
                    })
                    System.Debug.info("EntityStats", "Entity died:", self._entityId)
                end
            end)

            self._configured = true
            System.Debug.info("EntityStats", "Configured:", self._entityId)
        end,

        --[[
            Apply a modifier to an attribute.

            @param data.attribute string - Attribute name
            @param data.operation string - "additive", "multiplicative", "override"
            @param data.value number - Modifier value
            @param data.source string - Source identifier
        --]]
        onApplyModifier = function(self, data)
            if not self._attributeSet then
                System.Debug.warn("EntityStats", "Not configured, cannot apply modifier")
                return
            end

            local modId = self._attributeSet:applyModifier(data.attribute, {
                operation = data.operation,
                value = data.value,
                source = data.source,
                priority = data.priority,
            })

            if modId then
                self.Out:Fire("modifierApplied", {
                    entityId = self._entityId,
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
            if not self._attributeSet then
                System.Debug.warn("EntityStats", "Not configured, cannot remove modifier")
                return
            end

            if data.modifierId then
                local success = self._attributeSet:removeModifier(data.modifierId)
                if success then
                    self.Out:Fire("modifierRemoved", {
                        entityId = self._entityId,
                        modifierId = data.modifierId,
                    })
                end
            elseif data.source then
                local count = self._attributeSet:removeModifiersFromSource(data.source)
                if count > 0 then
                    self.Out:Fire("modifierRemoved", {
                        entityId = self._entityId,
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
            if not self._attributeSet then
                System.Debug.warn("EntityStats", "Not configured, cannot set attribute")
                return
            end

            self._attributeSet:setBase(data.attribute, data.value)
            System.Debug.trace("EntityStats", "Set", data.attribute, "to", data.value)
        end,

        --[[
            Query current attribute value.

            @param data.attribute string - Attribute name
            @param data.queryId any - Correlation ID for response
        --]]
        onQueryAttribute = function(self, data)
            if not self._attributeSet then
                System.Debug.warn("EntityStats", "Not configured, cannot query")
                return
            end

            local value = self._attributeSet:get(data.attribute)

            self.Out:Fire("attributeQueried", {
                entityId = self._entityId,
                attribute = data.attribute,
                value = value,
                queryId = data.queryId,
            })
        end,
    },

    --------------------------------------------------------------------------------
    -- OUTPUT SIGNALS
    --------------------------------------------------------------------------------

    Out = {
        attributeChanged = {},   -- { entityId, attribute, value, oldValue }
        attributeQueried = {},   -- { entityId, attribute, value, queryId }
        died = {},               -- { entityId }
        modifierApplied = {},    -- { entityId, attribute, modifierId, source }
        modifierRemoved = {},    -- { entityId, modifierId?, source?, count? }
    },

    --------------------------------------------------------------------------------
    -- PUBLIC METHODS
    --------------------------------------------------------------------------------

    --[[
        Get current value of an attribute.

        @param attrName string
        @return any
    --]]
    get = function(self, attrName)
        if not self._attributeSet then
            return nil
        end
        return self._attributeSet:get(attrName)
    end,

    --[[
        Get base value of an attribute.

        @param attrName string
        @return any
    --]]
    getBase = function(self, attrName)
        if not self._attributeSet then
            return nil
        end
        return self._attributeSet:getBase(attrName)
    end,

    --[[
        Get all current values.

        @return table
    --]]
    getAll = function(self)
        if not self._attributeSet then
            return {}
        end
        return self._attributeSet:getAll()
    end,

    --[[
        Get entity ID.

        @return string
    --]]
    getEntityId = function(self)
        return self._entityId
    end,

    --[[
        Check if configured.

        @return boolean
    --]]
    isConfigured = function(self)
        return self._configured
    end,

    --[[
        Get the underlying AttributeSet.

        @return AttributeSet|nil
    --]]
    getAttributeSet = function(self)
        return self._attributeSet
    end,
})

return EntityStats
