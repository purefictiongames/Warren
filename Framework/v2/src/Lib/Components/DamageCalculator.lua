--[[
    LibPureFiction Framework v2
    DamageCalculator.lua - Combat Formula Node

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    DamageCalculator owns combat formulas. It receives raw damage requests,
    queries target defense from EntityStats, computes final damage, and
    sends the result back to EntityStats.

    This separation allows games to customize formulas by extending
    DamageCalculator and overriding the computeDamage method.

    Key features:
    - Query/response flow for stat lookup
    - Extensible damage formula
    - Supports damage types (physical, magic, true)
    - Tracks pending calculations for async resolution

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onCalculateDamage({ targetId, rawDamage, damageType?, sourceId? })
            - Calculate and apply damage to target
            - Queries target defense, computes final damage, applies to health

        onAttributeQueried({ entityId, attribute, value, queryId })
            - Response from EntityStats with queried value
            - Wired from EntityStats.attributeQueried

    OUT (emits):
        queryAttribute({ targetId, attribute, queryId })
            - Query attribute from EntityStats
            - Wire to EntityStats.onQueryAttribute

        applyDamage({ targetId, attribute, value, sourceId, damageType })
            - Apply final damage to EntityStats
            - Wire to EntityStats.onSetAttribute (negative value = damage)

        damageCalculated({ targetId, rawDamage, defense, finalDamage, damageType })
            - Informational: fired after calculation complete

    ============================================================================
    DAMAGE TYPES
    ============================================================================

    physical (default): Standard damage, reduced by defense
    magic: Can use custom formula (e.g., 50% defense reduction)
    true: Ignores defense entirely

    ============================================================================
    EXTENDING
    ============================================================================

    Games can customize formulas by extending:

    ```lua
    local MyCalculator = DamageCalculator.extend({
        name = "MyCalculator",

        computeDamage = function(self, rawDamage, defense, damageType)
            if damageType == "magic" then
                -- Magic ignores 50% of defense
                return math.max(1, rawDamage - (defense * 0.5))
            end
            return math.max(1, rawDamage - defense)
        end,
    })
    ```

--]]

local Node = require(script.Parent.Parent.Node)
local System = require(script.Parent.Parent.System)

--------------------------------------------------------------------------------
-- DAMAGECALCULATOR NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local DamageCalculator = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                pendingQueries = {},  -- queryId -> { targetId, rawDamage, damageType, sourceId }
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Apply calculated damage to target.
    --]]
    local function applyDamage(self, targetId, finalDamage, sourceId, damageType, defense, rawDamage)
        -- Apply damage to health
        self.Out:Fire("applyDamage", {
            targetId = targetId,
            attribute = "health",
            delta = -finalDamage,  -- Negative = damage
            sourceId = sourceId,
            damageType = damageType,
        })

        -- Emit informational signal
        self.Out:Fire("damageCalculated", {
            targetId = targetId,
            rawDamage = rawDamage or finalDamage,
            defense = defense,
            finalDamage = finalDamage,
            damageType = damageType,
        })

        System.Debug.trace("DamageCalculator", "Applied", finalDamage, "damage to", targetId,
            "(defense:", defense, "type:", damageType, ")")
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "DamageCalculator",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                getState(self)  -- Initialize this instance's state
                System.Debug.trace("DamageCalculator", "Initialized:", self.id)
            end,

            onStart = function(self)
                System.Debug.trace("DamageCalculator", "Started:", self.id)
            end,

            onStop = function(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
                System.Debug.trace("DamageCalculator", "Stopped:", self.id)
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Calculate and apply damage to a target.

                @param data.targetId string - EntityStats instance ID
                @param data.rawDamage number - Damage before mitigation
                @param data.damageType string? - "physical", "magic", "true"
                @param data.sourceId string? - Who dealt the damage
            --]]
            onCalculateDamage = function(self, data)
                if not data.targetId or not data.rawDamage then
                    System.Debug.warn("DamageCalculator", "Missing targetId or rawDamage")
                    return
                end

                local damageType = data.damageType or "physical"

                -- True damage bypasses defense query
                if damageType == "true" then
                    local finalDamage = data.rawDamage
                    applyDamage(self, data.targetId, finalDamage, data.sourceId, damageType, 0, data.rawDamage)
                    return
                end

                -- Generate query ID for correlation
                local queryId = tostring(tick()) .. "_" .. tostring(math.random(10000, 99999))

                -- Store pending query
                local state = getState(self)
                state.pendingQueries[queryId] = {
                    targetId = data.targetId,
                    rawDamage = data.rawDamage,
                    damageType = damageType,
                    sourceId = data.sourceId,
                }

                -- Query target's defense
                self.Out:Fire("queryAttribute", {
                    targetId = data.targetId,
                    attribute = "effectiveDefense",
                    queryId = queryId,
                })

                System.Debug.trace("DamageCalculator", "Querying defense for", data.targetId, "queryId:", queryId)
            end,

            --[[
                Receive defense value from EntityStats.

                @param data.entityId string - Entity ID
                @param data.attribute string - Attribute name
                @param data.value any - Attribute value
                @param data.queryId string - Correlation ID
            --]]
            onAttributeQueried = function(self, data)
                local state = getState(self)
                local pending = state.pendingQueries[data.queryId]
                if not pending then
                    -- Not our query or already processed
                    return
                end

                -- Clear pending
                state.pendingQueries[data.queryId] = nil

                -- Compute final damage
                local defense = data.value or 0
                local finalDamage = self:computeDamage(
                    pending.rawDamage,
                    defense,
                    pending.damageType
                )

                -- Apply damage
                applyDamage(
                    self,
                    pending.targetId,
                    finalDamage,
                    pending.sourceId,
                    pending.damageType,
                    defense,
                    pending.rawDamage
                )
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            queryAttribute = {},     -- { targetId, attribute, queryId }
            applyDamage = {},        -- { targetId, attribute, value, sourceId, damageType }
            damageCalculated = {},   -- { targetId, rawDamage, defense, finalDamage, damageType }
        },

        ------------------------------------------------------------------------
        -- OVERRIDABLE FORMULA (intentionally public for extension)
        ------------------------------------------------------------------------

        --[[
            Compute final damage from raw damage and defense.

            Override this method in extended classes for custom formulas.

            @param rawDamage number - Damage before mitigation
            @param defense number - Target's defense value
            @param damageType string - "physical", "magic", "true"
            @return number - Final damage to apply
        --]]
        computeDamage = function(self, rawDamage, defense, damageType)
            if damageType == "true" then
                -- True damage ignores defense
                return rawDamage
            end

            -- Standard formula: raw damage minus defense, minimum 1
            return math.max(1, rawDamage - defense)
        end,
    }
end)

return DamageCalculator
