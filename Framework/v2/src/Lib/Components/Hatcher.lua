--[[
    LibPureFiction Framework v2
    Hatcher.lua - Gacha/Egg Hatching Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Hatcher implements gacha/egg mechanics with weighted rarity selection,
    pity system, and currency cost requirements.

    The component is signal-driven with a fire-and-wait pattern for cost
    validation: it fires costCheck, waits for onCostConfirmed, then proceeds
    with the hatch if approved.

    Uses SpawnerCore internally for spawning the resulting item/entity.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ pool: table })
            - Sets the reward pool with weighted rarities
            - Pool format: { { template, rarity, weight, pity? }, ... }

        onHatch({ player?: Player })
            - Triggers a hatch attempt for the specified player
            - Fires costCheck and waits for onCostConfirmed

        onCostConfirmed({ player: Player, approved: boolean })
            - Response to costCheck signal
            - If approved=true, hatch proceeds; otherwise hatchFailed fires

        onSetPity({ player: Player, count: number })
            - Manually set pity counter for a player
            - Useful for loading saved pity progress

    OUT (emits):
        costCheck({ player: Player, cost: number, costType: string, hatcherId: string })
            - Fired before hatch to request cost validation
            - External system should respond with onCostConfirmed

        hatchStarted({ player: Player, hatchTime: number, hatcherId: string })
            - Fired when hatch begins (after cost confirmed)

        hatched({ player: Player, result: table, rarity: string, assetId: string,
                  pityTriggered: boolean, hatcherId: string })
            - Fired when hatch completes successfully
            - result contains the pool entry that was selected

        hatchFailed({ player: Player, reason: string, hatcherId: string })
            - Fired when hatch cannot proceed (cost denied, no pool, etc.)

    ============================================================================
    ATTRIBUTES
    ============================================================================

    HatchTime: number (default 0)
        Seconds to wait during hatch animation (0 = instant)

    Cost: number (default 0)
        Currency cost per hatch (0 = free)

    CostType: string (default "")
        Currency type identifier for cost validation

    PityThreshold: number (default 0)
        Guaranteed pity item after N hatches without one (0 = disabled)

    CostConfirmTimeout: number (default 10)
        Seconds to wait for onCostConfirmed before timing out

    SpawnParent: Instance (optional)
        Parent for spawned items (if not set, items spawn at Hatcher position)

    ============================================================================
    POOL FORMAT
    ============================================================================

    ```lua
    {
        { template = "CommonPet", rarity = "Common", weight = 60 },
        { template = "RarePet", rarity = "Rare", weight = 30 },
        { template = "LegendaryPet", rarity = "Legendary", weight = 10, pity = true },
    }
    ```

    - template: Name of template to spawn (resolved via SpawnerCore)
    - rarity: Display rarity string
    - weight: Relative probability weight
    - pity: If true, this item can be given by pity system

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Register the component
    local Hatcher = Lib.Components.Hatcher
    System.Asset.register(Hatcher)

    -- Configure via wiring or direct call
    System.IPC.sendTo("EggHatcher_1", "configure", {
        pool = {
            { template = "CommonPet", rarity = "Common", weight = 60 },
            { template = "RarePet", rarity = "Rare", weight = 30 },
            { template = "LegendaryPet", rarity = "Legendary", weight = 10, pity = true },
        },
    })

    -- Trigger hatch
    System.IPC.sendTo("EggHatcher_1", "hatch", { player = player })

    -- Handle costCheck in Currency component, respond with costConfirmed
    ```

--]]

local Node = require(script.Parent.Parent.Node)
local SpawnerCore = require(script.Parent.Parent.Internal.SpawnerCore)

local Hatcher = Node.extend({
    name = "Hatcher",
    domain = "server",  -- Hatching should be server-authoritative

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Reward pool configuration
            self._pool = nil
            self._totalWeight = 0

            -- Pity tracking per player (userId -> count)
            self._pityCounters = {}

            -- Pending hatch state (waiting for cost confirmation)
            self._pendingHatch = nil  -- { player, timestamp }

            -- Default attributes
            if not self:getAttribute("HatchTime") then
                self:setAttribute("HatchTime", 0)
            end
            if not self:getAttribute("Cost") then
                self:setAttribute("Cost", 0)
            end
            if not self:getAttribute("CostType") then
                self:setAttribute("CostType", "")
            end
            if not self:getAttribute("PityThreshold") then
                self:setAttribute("PityThreshold", 0)
            end
            if not self:getAttribute("CostConfirmTimeout") then
                self:setAttribute("CostConfirmTimeout", 10)
            end

            -- Initialize SpawnerCore if not already initialized
            if not SpawnerCore.isInitialized() then
                SpawnerCore.init({})
            end
        end,

        onStart = function(self)
            -- Nothing to do on start - we wait for signals
        end,

        onStop = function(self)
            -- Clear pending state
            self._pendingHatch = nil
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Configure the reward pool.
        --]]
        onConfigure = function(self, data)
            if not data or not data.pool or type(data.pool) ~= "table" then
                self.Err:Fire({
                    reason = "invalid_pool",
                    message = "onConfigure requires { pool: table }",
                    hatcherId = self.id,
                })
                return
            end

            self._pool = data.pool

            -- Calculate total weight
            self._totalWeight = 0
            for _, entry in ipairs(self._pool) do
                self._totalWeight = self._totalWeight + (entry.weight or 0)
            end

            -- Validate pool has valid entries
            if self._totalWeight <= 0 then
                self.Err:Fire({
                    reason = "invalid_pool",
                    message = "Pool has no valid weighted entries",
                    hatcherId = self.id,
                })
                self._pool = nil
            end
        end,

        --[[
            Trigger a hatch attempt.
            Fires costCheck and waits for onCostConfirmed.
        --]]
        onHatch = function(self, data)
            local player = data and data.player

            -- Validate pool is configured
            if not self._pool then
                self.Out:Fire("hatchFailed", {
                    player = player,
                    reason = "no_pool",
                    hatcherId = self.id,
                })
                return
            end

            -- Check if already waiting for confirmation
            if self._pendingHatch then
                self.Out:Fire("hatchFailed", {
                    player = player,
                    reason = "hatch_in_progress",
                    hatcherId = self.id,
                })
                return
            end

            local cost = self:getAttribute("Cost") or 0
            local costType = self:getAttribute("CostType") or ""

            -- If no cost, skip cost check
            if cost <= 0 then
                self:_executeHatch(player, false)
                return
            end

            -- Store pending hatch state
            self._pendingHatch = {
                player = player,
                timestamp = os.clock(),
            }

            -- Fire cost check signal
            self.Out:Fire("costCheck", {
                player = player,
                cost = cost,
                costType = costType,
                hatcherId = self.id,
            })

            -- Wait for confirmation with timeout
            local timeout = self:getAttribute("CostConfirmTimeout") or 10
            local confirmed = self:waitForSignal("onCostConfirmed", timeout)

            -- Clear pending state
            local pendingPlayer = self._pendingHatch and self._pendingHatch.player
            self._pendingHatch = nil

            if not confirmed then
                self.Out:Fire("hatchFailed", {
                    player = pendingPlayer,
                    reason = "cost_timeout",
                    hatcherId = self.id,
                })
            end
            -- Note: actual hatch execution happens in onCostConfirmed handler
        end,

        --[[
            Response to costCheck signal.
        --]]
        onCostConfirmed = function(self, data)
            if not data then
                return
            end

            local approved = data.approved
            local player = data.player

            -- Verify this matches our pending hatch
            if not self._pendingHatch then
                -- No pending hatch - ignore stale confirmation
                return
            end

            -- Verify player matches (if both are provided)
            local pendingPlayer = self._pendingHatch.player
            if player and pendingPlayer and player ~= pendingPlayer then
                -- Player mismatch - ignore
                return
            end

            local actualPlayer = player or pendingPlayer

            if approved then
                -- Execute the hatch
                self:_executeHatch(actualPlayer, false)
            else
                -- Clear pending and fire failure
                self._pendingHatch = nil
                self.Out:Fire("hatchFailed", {
                    player = actualPlayer,
                    reason = "cost_denied",
                    hatcherId = self.id,
                })
            end
        end,

        --[[
            Manually set pity counter for a player.
        --]]
        onSetPity = function(self, data)
            if not data or not data.player then
                return
            end

            local playerId = self:_getPlayerId(data.player)
            if playerId then
                self._pityCounters[playerId] = data.count or 0
            end
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA (documentation)
    ----------------------------------------------------------------------------

    Out = {
        costCheck = {},     -- { player, cost, costType, hatcherId }
        hatchStarted = {},  -- { player, hatchTime, hatcherId }
        hatched = {},       -- { player, result, rarity, assetId, pityTriggered, hatcherId }
        hatchFailed = {},   -- { player, reason, hatcherId }
    },

    -- Err (detour) signals:
    -- { reason = "invalid_pool", message, hatcherId }
    -- { reason = "spawn_failed", message, hatcherId }

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Get a consistent player identifier for pity tracking.
    --]]
    _getPlayerId = function(self, player)
        if not player then
            return "anonymous"
        end
        if typeof(player) == "Instance" and player:IsA("Player") then
            return tostring(player.UserId)
        end
        return tostring(player)
    end,

    --[[
        Get pity counter for a player.
    --]]
    _getPityCount = function(self, player)
        local playerId = self:_getPlayerId(player)
        return self._pityCounters[playerId] or 0
    end,

    --[[
        Increment pity counter for a player.
    --]]
    _incrementPity = function(self, player)
        local playerId = self:_getPlayerId(player)
        self._pityCounters[playerId] = (self._pityCounters[playerId] or 0) + 1
        return self._pityCounters[playerId]
    end,

    --[[
        Reset pity counter for a player.
    --]]
    _resetPity = function(self, player)
        local playerId = self:_getPlayerId(player)
        self._pityCounters[playerId] = 0
    end,

    --[[
        Select a random entry from the pool using weighted selection.
    --]]
    _selectFromPool = function(self)
        if not self._pool or self._totalWeight <= 0 then
            return nil
        end

        local roll = math.random() * self._totalWeight
        local cumulative = 0

        for _, entry in ipairs(self._pool) do
            cumulative = cumulative + (entry.weight or 0)
            if roll <= cumulative then
                return entry
            end
        end

        -- Fallback to last entry (shouldn't happen with valid weights)
        return self._pool[#self._pool]
    end,

    --[[
        Get the pity item from the pool.
    --]]
    _getPityItem = function(self)
        if not self._pool then
            return nil
        end

        for _, entry in ipairs(self._pool) do
            if entry.pity then
                return entry
            end
        end

        return nil
    end,

    --[[
        Check if pity should trigger for a player.
    --]]
    _shouldTriggerPity = function(self, player)
        local threshold = self:getAttribute("PityThreshold") or 0
        if threshold <= 0 then
            return false
        end

        local count = self:_getPityCount(player)
        return count >= threshold
    end,

    --[[
        Execute the hatch after cost validation.

        @param player Player - The player hatching
        @param fromPending boolean - Whether this came from pending state resolution
    --]]
    _executeHatch = function(self, player, fromPending)
        local hatchTime = self:getAttribute("HatchTime") or 0

        -- Fire hatch started
        self.Out:Fire("hatchStarted", {
            player = player,
            hatchTime = hatchTime,
            hatcherId = self.id,
        })

        -- Wait for hatch time (in a spawned task to not block)
        task.spawn(function()
            if hatchTime > 0 then
                task.wait(hatchTime)
            end

            -- Select result
            local pityTriggered = false
            local result

            if self:_shouldTriggerPity(player) then
                result = self:_getPityItem()
                if result then
                    pityTriggered = true
                    self:_resetPity(player)
                end
            end

            -- If no pity or pity item not found, roll normally
            if not result then
                result = self:_selectFromPool()
                -- Increment pity counter (only reset when pity triggers)
                self:_incrementPity(player)
            end

            if not result then
                self.Out:Fire("hatchFailed", {
                    player = player,
                    reason = "selection_failed",
                    hatcherId = self.id,
                })
                return
            end

            -- Spawn the result using SpawnerCore
            local spawnParent = self:getAttribute("SpawnParent")
            local spawnPosition

            -- Determine spawn position
            if self.model and self.model.PrimaryPart then
                spawnPosition = self.model.PrimaryPart.Position + Vector3.new(0, 3, 0)
            elseif self.model then
                local part = self.model:FindFirstChildWhichIsA("BasePart")
                if part then
                    spawnPosition = part.Position + Vector3.new(0, 3, 0)
                end
            end

            local spawnResult, spawnErr = SpawnerCore.spawn({
                templateName = result.template,
                parent = spawnParent or workspace,
                position = spawnPosition,
                attributes = {
                    Rarity = result.rarity,
                    HatchedBy = player and player.Name or "Unknown",
                },
                metadata = {
                    player = player,
                    poolEntry = result,
                },
            })

            if not spawnResult then
                self.Err:Fire({
                    reason = "spawn_failed",
                    message = spawnErr or "Unknown spawn error",
                    hatcherId = self.id,
                })
                self.Out:Fire("hatchFailed", {
                    player = player,
                    reason = "spawn_failed",
                    hatcherId = self.id,
                })
                return
            end

            -- Fire hatched signal
            self.Out:Fire("hatched", {
                player = player,
                result = result,
                rarity = result.rarity,
                template = result.template,
                assetId = spawnResult.assetId,
                instance = spawnResult.instance,
                pityTriggered = pityTriggered,
                hatcherId = self.id,
            })
        end)
    end,
})

return Hatcher
