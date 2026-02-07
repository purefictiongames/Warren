--[[
    Warren Framework v2
    StatusEffect.lua - Timed Buff/Debuff Node

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    StatusEffect manages timed buffs and debuffs. It applies modifiers when
    an effect starts and automatically removes them when the effect expires.

    Key features:
    - Timed effects with automatic expiration
    - Multiple modifiers per effect
    - Manual early removal
    - Tracks all active effects per target

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onApplyEffect({ targetId, effectType, duration, modifiers })
            - Apply a timed effect
            - modifiers: array of { attribute, operation, value }

        onRemoveEffect({ effectId })
            - Remove an effect early

        onRemoveAllEffects({ targetId })
            - Remove all effects from a target

    OUT (emits):
        applyModifier({ targetId, attribute, operation, value, source })
            - Apply modifier to EntityStats
            - Wire to EntityStats.onApplyModifier

        removeModifier({ targetId, source })
            - Remove modifiers by source
            - Wire to EntityStats.onRemoveModifier

        effectApplied({ effectId, targetId, effectType, duration })
            - Fired when effect starts

        effectExpired({ effectId, targetId, effectType })
            - Fired when effect ends (natural or manual)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Apply a speed boost buff for 10 seconds
    statusEffect.In.onApplyEffect(statusEffect, {
        targetId = "player_1",
        effectType = "speed_boost",
        duration = 10,
        modifiers = {
            { attribute = "speed", operation = "multiplicative", value = 1.5 },
        },
    })

    -- Apply a poison debuff
    statusEffect.In.onApplyEffect(statusEffect, {
        targetId = "enemy_1",
        effectType = "poison",
        duration = 5,
        modifiers = {
            { attribute = "health", operation = "additive", value = -5 },
        },
    })
    ```

--]]

local Node = require(script.Parent.Parent.Node)
local System = require(script.Parent.Parent.System)

--------------------------------------------------------------------------------
-- STATUSEFFECT NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local StatusEffect = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                activeEffects = {},      -- effectId -> { targetId, source, expiresAt, effectType, scheduledTask }
                effectsByTarget = {},    -- targetId -> { effectId, ... }
                nextEffectId = 1,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Remove an effect and clean up.

        @param self - Node instance
        @param effectId number - Effect ID
        @param silent boolean - If true, don't emit expired signal
    --]]
    local function removeEffect(self, effectId, silent)
        local state = getState(self)
        local effect = state.activeEffects[effectId]
        if not effect then
            return
        end

        -- Cancel scheduled task if still pending (pcall handles case where task is currently executing)
        if effect.scheduledTask then
            pcall(task.cancel, effect.scheduledTask)
        end

        -- Remove modifiers from EntityStats
        self.Out:Fire("removeModifier", {
            targetId = effect.targetId,
            source = effect.source,
        })

        -- Remove from tracking
        state.activeEffects[effectId] = nil

        -- Remove from target's effect list
        local targetEffects = state.effectsByTarget[effect.targetId]
        if targetEffects then
            for i, id in ipairs(targetEffects) do
                if id == effectId then
                    table.remove(targetEffects, i)
                    break
                end
            end
            -- Clean up empty target entry
            if #targetEffects == 0 then
                state.effectsByTarget[effect.targetId] = nil
            end
        end

        -- Emit expired signal
        if not silent then
            self.Out:Fire("effectExpired", {
                effectId = effectId,
                targetId = effect.targetId,
                effectType = effect.effectType,
            })

            System.Debug.info("StatusEffect", "Effect", effectId,
                "(", effect.effectType, ") expired on", effect.targetId)
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "StatusEffect",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                getState(self)  -- Initialize this instance's state
                System.Debug.trace("StatusEffect", "Initialized:", self.id)
            end,

            onStart = function(self)
                System.Debug.trace("StatusEffect", "Started:", self.id)
            end,

            onStop = function(self)
                -- Clean up all active effects
                local state = getState(self)
                for effectId in pairs(state.activeEffects) do
                    removeEffect(self, effectId, true)  -- silent = true
                end

                -- Clean up instance state (CRITICAL: prevents memory leak)
                cleanupState(self)

                System.Debug.trace("StatusEffect", "Stopped:", self.id)
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Apply a timed effect to a target.

                @param data.targetId string - EntityStats instance ID
                @param data.effectType string - Effect name (e.g., "speed_boost", "poison")
                @param data.duration number - Duration in seconds
                @param data.modifiers array - { { attribute, operation, value }, ... }
            --]]
            onApplyEffect = function(self, data)
                if not data.targetId or not data.duration or not data.modifiers then
                    System.Debug.warn("StatusEffect", "Missing targetId, duration, or modifiers")
                    return
                end

                local state = getState(self)

                -- Generate effect ID
                local effectId = state.nextEffectId
                state.nextEffectId = state.nextEffectId + 1

                -- Create unique source identifier for this effect
                local source = "StatusEffect_" .. self.id .. "_" .. effectId

                -- Apply all modifiers
                for _, mod in ipairs(data.modifiers) do
                    self.Out:Fire("applyModifier", {
                        targetId = data.targetId,
                        attribute = mod.attribute,
                        operation = mod.operation,
                        value = mod.value,
                        source = source,
                    })
                end

                -- Schedule expiration
                local expiresAt = tick() + data.duration
                local scheduledTask = task.delay(data.duration, function()
                    removeEffect(self, effectId, false)
                end)

                -- Track effect
                state.activeEffects[effectId] = {
                    targetId = data.targetId,
                    source = source,
                    expiresAt = expiresAt,
                    effectType = data.effectType or "unknown",
                    scheduledTask = scheduledTask,
                }

                -- Track by target
                if not state.effectsByTarget[data.targetId] then
                    state.effectsByTarget[data.targetId] = {}
                end
                table.insert(state.effectsByTarget[data.targetId], effectId)

                -- Emit applied signal
                self.Out:Fire("effectApplied", {
                    effectId = effectId,
                    targetId = data.targetId,
                    effectType = data.effectType or "unknown",
                    duration = data.duration,
                })

                System.Debug.info("StatusEffect", "Applied effect", effectId,
                    "(", data.effectType or "unknown", ") to", data.targetId, "for", data.duration, "s")
            end,

            --[[
                Remove an effect early.

                @param data.effectId number - Effect ID to remove
            --]]
            onRemoveEffect = function(self, data)
                if not data.effectId then
                    System.Debug.warn("StatusEffect", "Missing effectId")
                    return
                end

                removeEffect(self, data.effectId, false)
            end,

            --[[
                Remove all effects from a target.

                @param data.targetId string - Target to clear effects from
            --]]
            onRemoveAllEffects = function(self, data)
                if not data.targetId then
                    System.Debug.warn("StatusEffect", "Missing targetId")
                    return
                end

                local state = getState(self)
                local effects = state.effectsByTarget[data.targetId]
                if not effects then
                    return
                end

                -- Copy array since we'll be modifying it
                local toRemove = {}
                for _, effectId in ipairs(effects) do
                    table.insert(toRemove, effectId)
                end

                for _, effectId in ipairs(toRemove) do
                    removeEffect(self, effectId, false)
                end

                System.Debug.info("StatusEffect", "Removed all effects from", data.targetId)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            applyModifier = {},     -- { targetId, attribute, operation, value, source }
            removeModifier = {},    -- { targetId, source }
            effectApplied = {},     -- { effectId, targetId, effectType, duration }
            effectExpired = {},     -- { effectId, targetId, effectType }
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS (intentionally exposed)
        ------------------------------------------------------------------------

        --[[
            Get all active effects.

            @return table - { effectId = effectInfo, ... }
        --]]
        getActiveEffects = function(self)
            local state = getState(self)
            return state.activeEffects
        end,

        --[[
            Get active effects for a target.

            @param targetId string
            @return array - { effectId, ... }
        --]]
        getEffectsForTarget = function(self, targetId)
            local state = getState(self)
            return state.effectsByTarget[targetId] or {}
        end,

        --[[
            Check if a target has a specific effect type active.

            @param targetId string
            @param effectType string
            @return boolean
        --]]
        hasEffect = function(self, targetId, effectType)
            local state = getState(self)
            local effects = state.effectsByTarget[targetId]
            if not effects then
                return false
            end

            for _, effectId in ipairs(effects) do
                local effect = state.activeEffects[effectId]
                if effect and effect.effectType == effectType then
                    return true
                end
            end

            return false
        end,

        --[[
            Get remaining duration for an effect.

            @param effectId number
            @return number|nil - Remaining seconds or nil if not found
        --]]
        getRemainingDuration = function(self, effectId)
            local state = getState(self)
            local effect = state.activeEffects[effectId]
            if not effect then
                return nil
            end

            return math.max(0, effect.expiresAt - tick())
        end,
    }
end)

return StatusEffect
